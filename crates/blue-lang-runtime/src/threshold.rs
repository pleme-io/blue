use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use tameshi::threshold::keygen::{self, dkg};
use tameshi::threshold::signing;
use tameshi::threshold::{GroupKey, KeyShare, ParticipantId, ThresholdError, ThresholdParams};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, MapKey, Value};

use crate::crypto::{encode_hex, hex_vec, message_bytes};
use crate::errors::{raise_kind, raise_kind_with};
use crate::net::record;
use crate::provide::Key;

const SEEDED_CONTEXT: &str = "blue seeded-threshold 2026-10-31";
const DRAW_CONTEXT: &str = "blue threshold draw 2026-10-31";

type Span = tatara_lisp::Span;

#[derive(Clone)]
enum Source {
    Host,
    Seeded(Arc<Mutex<blake3::OutputReader>>),
}

impl Source {
    fn seeded(seed: &str) -> Self {
        Source::Seeded(Arc::new(Mutex::new(
            blake3::Hasher::new_derive_key(SEEDED_CONTEXT)
                .update(seed.as_bytes())
                .finalize_xof(),
        )))
    }

    fn draw(&self, fname: &'static str, span: Span) -> Result<Draw, EvalError> {
        let mut seed = [0u8; 32];
        match self {
            Source::Host => {
                let bytes = crate::entropy::random_vec(seed.len())
                    .map_err(|e| EvalError::native_fn(fname, e.to_string(), span))?;
                seed.copy_from_slice(&bytes);
            }
            Source::Seeded(stream) => locked(stream).fill(&mut seed),
        }
        Ok(Draw(
            blake3::Hasher::new_derive_key(DRAW_CONTEXT)
                .update(&seed)
                .finalize_xof(),
        ))
    }
}

struct Draw(blake3::OutputReader);

impl rand_core::RngCore for Draw {
    fn next_u32(&mut self) -> u32 {
        rand_core::impls::next_u32_via_fill(self)
    }

    fn next_u64(&mut self) -> u64 {
        rand_core::impls::next_u64_via_fill(self)
    }

    fn fill_bytes(&mut self, dest: &mut [u8]) {
        self.0.fill(dest);
    }

    fn try_fill_bytes(&mut self, dest: &mut [u8]) -> Result<(), rand_core::Error> {
        self.0.fill(dest);
        Ok(())
    }
}

impl rand_core::CryptoRng for Draw {}

fn locked<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(PoisonError::into_inner)
}

struct Nonces(Mutex<Option<signing::Nonces>>);

struct Round1Secret(Mutex<Option<dkg::Round1Secret>>);

struct Round2Secret(Mutex<Option<dkg::Round2Secret>>);

fn refused(fname: &'static str, message: String, span: Span) -> EvalError {
    raise_kind("refused", format!("{fname}: {message}"), span)
}

fn bad_option(fname: &'static str, message: String, span: Span) -> EvalError {
    raise_kind("bad_option", format!("{fname}: {message}"), span)
}

fn undecodable(fname: &'static str, what: &str, e: ThresholdError, span: Span) -> EvalError {
    let why = match e {
        ThresholdError::Protocol(why) => why,
        other => other.to_string(),
    };
    raise_kind(
        "decode_error",
        format!("{fname}: the {what} does not decode: {why}"),
        span,
    )
}

fn refusal(fname: &'static str, e: ThresholdError, span: Span) -> EvalError {
    match e {
        ThresholdError::InvalidParams { .. } => bad_option(fname, e.to_string(), span),
        ThresholdError::InvalidShares { culprits } if !culprits.is_empty() => {
            let culprits: Vec<Value> = culprits.iter().map(|p| int(p.get())).collect();
            raise_kind_with(
                "tampered",
                format!(
                    "{fname}: signature shares from participants {} do not verify",
                    to_list(&culprits)
                ),
                record(vec![("culprits", Value::list(culprits))]),
                span,
            )
        }
        ThresholdError::InvalidSignature => raise_kind(
            "tampered",
            format!("{fname}: the aggregate is not a valid signature under the group key"),
            span,
        ),
        other => refused(fname, other.to_string(), span),
    }
}

fn below(fname: &'static str, what: &str, have: usize, need: u16, span: Span) -> EvalError {
    raise_kind_with(
        "refused",
        format!("{fname}: {have} {what} cannot sign for a group that needs {need}"),
        record(vec![
            ("have", int(i64::try_from(have).unwrap_or(i64::MAX))),
            ("need", int(need)),
        ]),
        span,
    )
}

fn int(n: impl Into<i64>) -> Value {
    Value::Int(n.into())
}

fn text(s: impl Into<String>) -> Value {
    Value::Str(Arc::from(s.into()))
}

fn field<'a>(v: &'a Value, name: &str) -> Option<&'a Value> {
    match v {
        Value::Map(m) => m.get(&MapKey::Keyword(Arc::from(name))),
        _ => None,
    }
}

fn need<'a>(
    v: &'a Value,
    name: &str,
    what: &str,
    fname: &'static str,
    span: Span,
) -> Result<&'a Value, EvalError> {
    field(v, name).ok_or_else(|| {
        bad_option(
            fname,
            format!("a {what} is a map with {name}:, got {}", v.type_name()),
            span,
        )
    })
}

fn index(v: &Value, what: &str, fname: &'static str, span: Span) -> Result<u16, EvalError> {
    match v {
        Value::Int(n) => u16::try_from(*n)
            .ok()
            .filter(|n| *n >= 1)
            .ok_or_else(|| bad_option(fname, format!("the {what} is 1 to 65535, got {n}"), span)),
        other => Err(bad_option(
            fname,
            format!("the {what} is an integer, got {}", other.type_name()),
            span,
        )),
    }
}

fn participant(
    v: &Value,
    what: &str,
    fname: &'static str,
    span: Span,
) -> Result<ParticipantId, EvalError> {
    ParticipantId::new(index(v, what, fname, span)?).map_err(|e| refusal(fname, e, span))
}

fn params(
    min: &Value,
    max: &Value,
    fname: &'static str,
    span: Span,
) -> Result<ThresholdParams, EvalError> {
    let k = index(min, "threshold", fname, span)?;
    let n = index(max, "group size", fname, span)?;
    ThresholdParams::new(k, n).map_err(|e| refusal(fname, e, span))
}

fn hex_of(
    v: &Value,
    what: &'static str,
    fname: &'static str,
    span: Span,
) -> Result<Vec<u8>, EvalError> {
    hex_vec(v, what).map_err(|e| raise_kind("decode_error", format!("{fname}: {e}"), span))
}

fn list(v: &Value, what: &str, fname: &'static str, span: Span) -> Result<Vec<Value>, EvalError> {
    match v {
        Value::List(items) => Ok(items.iter().cloned().collect()),
        Value::Nil => Ok(Vec::new()),
        other => Err(bad_option(
            fname,
            format!("the {what} are a list, got {}", other.type_name()),
            span,
        )),
    }
}

fn message(v: &Value, fname: &'static str, span: Span) -> Result<Vec<u8>, EvalError> {
    message_bytes(v).map_err(|e| bad_option(fname, e.to_string(), span))
}

fn foreign<T: Send + Sync + 'static>(v: &Value) -> Option<Arc<T>> {
    match v {
        Value::Foreign(any) => Arc::downcast::<T>(any.clone()).ok(),
        _ => None,
    }
}

fn share_value(share: KeyShare) -> Value {
    record(vec![
        ("participant", int(share.participant().get())),
        ("key", text(encode_hex(&share.group_key()))),
        ("min", int(share.min_signers())),
        ("secret", Value::Foreign(Arc::new(share))),
    ])
}

fn share_of(v: &Value, fname: &'static str, span: Span) -> Result<Arc<KeyShare>, EvalError> {
    field(v, "secret")
        .and_then(foreign::<KeyShare>)
        .ok_or_else(|| {
            bad_option(
                fname,
                format!(
                    "expected a share from threshold_deal, threshold_dkg_finish or threshold_share_import, got {}",
                    v.type_name()
                ),
                span,
            )
        })
}

fn group_value(group: &GroupKey) -> Result<(String, String), ThresholdError> {
    Ok((
        encode_hex(&group.to_bytes()?),
        encode_hex(&group.verifying_key()),
    ))
}

fn request(
    data: &[u8],
    v: &Value,
    fname: &'static str,
    span: Span,
) -> Result<signing::SigningRequest, EvalError> {
    let mut commitments = Vec::new();
    for c in &list(v, "commitments", fname, span)? {
        let signer = participant(
            need(c, "participant", "commitment", fname, span)?,
            "participant",
            fname,
            span,
        )?;
        let bytes = hex_of(
            need(c, "hex", "commitment", fname, span)?,
            "commitment",
            fname,
            span,
        )?;
        commitments.push(
            signing::Commitment::from_bytes(signer, &bytes)
                .map_err(|e| undecodable(fname, "commitment", e, span))?,
        );
    }
    signing::SigningRequest::from_commitments(data, commitments).map_err(|e| match e {
        ThresholdError::DuplicateParticipant(p) => {
            refused(fname, format!("participant {p} commits twice"), span)
        }
        other => refusal(fname, other, span),
    })
}

fn broadcasts(
    v: &Value,
    fname: &'static str,
    span: Span,
) -> Result<Vec<dkg::Round1Package>, EvalError> {
    list(v, "broadcasts", fname, span)?
        .iter()
        .map(|b| {
            let from = participant(
                need(b, "from", "broadcast", fname, span)?,
                "sender",
                fname,
                span,
            )?;
            let bytes = hex_of(
                need(b, "package", "broadcast", fname, span)?,
                "broadcast",
                fname,
                span,
            )?;
            dkg::Round1Package::from_bytes(from, &bytes)
                .map_err(|e| undecodable(fname, "broadcast", e, span))
        })
        .collect()
}

fn deal(source: &Source, args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_deal";
    let params = params(&args[0], &args[1], F, span)?;
    let mut rng = source.draw(F, span)?;
    let (shares, group) =
        keygen::trusted_dealer_with_rng(params, &mut rng).map_err(|e| refusal(F, e, span))?;
    let (group_hex, key) = group_value(&group).map_err(|e| refusal(F, e, span))?;
    Ok(record(vec![
        ("group", text(group_hex)),
        ("key", text(key)),
        ("min", int(params.min_signers())),
        ("max", int(params.max_signers())),
        ("shares", Value::list(shares.into_iter().map(share_value))),
    ]))
}

fn dkg_start(source: &Source, args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_dkg_start";
    let me = participant(&args[0], "participant", F, span)?;
    let params = params(&args[1], &args[2], F, span)?;
    let mut rng = source.draw(F, span)?;
    let (secret, package) = dkg::start_with_rng(me, params, &mut rng).map_err(|e| match e {
        ThresholdError::UnknownParticipant(p) => bad_option(
            F,
            format!(
                "participant {p} is not in a group of {}",
                params.max_signers()
            ),
            span,
        ),
        other => refusal(F, other, span),
    })?;
    let bytes = package.to_bytes().map_err(|e| refusal(F, e, span))?;
    Ok(record(vec![
        (
            "secret",
            Value::Foreign(Arc::new(Round1Secret(Mutex::new(Some(secret))))),
        ),
        (
            "broadcast",
            record(vec![
                ("from", int(me.get())),
                ("package", text(encode_hex(&bytes))),
            ]),
        ),
    ]))
}

fn dkg_exchange(args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_dkg_exchange";
    let handle = foreign::<Round1Secret>(&args[0]).ok_or_else(|| {
        bad_option(
            F,
            "expected the secret threshold_dkg_start made".into(),
            span,
        )
    })?;
    let state = locked(&handle.0).take().ok_or_else(|| {
        refused(
            F,
            "this round one secret was already exchanged".into(),
            span,
        )
    })?;
    let max = state.params().max_signers();
    let received = broadcasts(&args[1], F, span)?;
    let (secret, outgoing) = dkg::exchange(state, &received).map_err(|e| match e {
        ThresholdError::UnknownParticipant(p) => refused(
            F,
            format!("participant {p} is not in a group of {max}"),
            span,
        ),
        ThresholdError::DuplicateParticipant(p) => {
            refused(F, format!("participant {p} broadcasts twice"), span)
        }
        other => refusal(F, other, span),
    })?;
    let mut sends = Vec::with_capacity(outgoing.len());
    for package in &outgoing {
        let bytes = package.to_bytes().map_err(|e| refusal(F, e, span))?;
        sends.push(record(vec![
            ("from", int(package.from.get())),
            ("to", int(package.to.get())),
            ("package", text(encode_hex(&bytes))),
        ]));
    }
    Ok(record(vec![
        (
            "secret",
            Value::Foreign(Arc::new(Round2Secret(Mutex::new(Some(secret))))),
        ),
        ("sends", Value::list(sends)),
    ]))
}

fn dkg_finish(args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_dkg_finish";
    let handle = foreign::<Round2Secret>(&args[0]).ok_or_else(|| {
        bad_option(
            F,
            "expected the secret threshold_dkg_exchange made".into(),
            span,
        )
    })?;
    let state = locked(&handle.0)
        .take()
        .ok_or_else(|| refused(F, "this round two secret already finished".into(), span))?;
    let me = state.participant();
    let max = state.params().max_signers();
    let received = broadcasts(&args[1], F, span)?;
    let mut mine = Vec::new();
    for s in &list(&args[2], "sends", F, span)? {
        let to = participant(need(s, "to", "send", F, span)?, "recipient", F, span)?;
        if to != me {
            continue;
        }
        let from = participant(need(s, "from", "send", F, span)?, "sender", F, span)?;
        let bytes = hex_of(need(s, "package", "send", F, span)?, "send", F, span)?;
        mine.push(
            dkg::Round2Package::from_bytes(from, to, &bytes)
                .map_err(|e| undecodable(F, "send", e, span))?,
        );
    }
    let (share, group) = dkg::finish(&state, &received, &mine).map_err(|e| match e {
        ThresholdError::UnknownParticipant(p) => refused(
            F,
            format!("participant {p} is not in a group of {max}"),
            span,
        ),
        other => refusal(F, other, span),
    })?;
    let (group_hex, key) = group_value(&group).map_err(|e| refusal(F, e, span))?;
    Ok(record(vec![
        ("share", share_value(share)),
        ("group", text(group_hex)),
        ("key", text(key)),
    ]))
}

fn commit(source: &Source, args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_commit";
    let share = share_of(&args[0], F, span)?;
    let data = message(&args[1], F, span)?;
    let mut rng = source.draw(F, span)?;
    let (nonces, commitment) = signing::commit_with_rng(&share, &data, &mut rng);
    let bytes = commitment.to_bytes().map_err(|e| refusal(F, e, span))?;
    Ok(record(vec![
        (
            "nonces",
            Value::Foreign(Arc::new(Nonces(Mutex::new(Some(nonces))))),
        ),
        (
            "commitment",
            record(vec![
                ("participant", int(commitment.participant.get())),
                ("hex", text(encode_hex(&bytes))),
            ]),
        ),
    ]))
}

fn sign(args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_sign";
    let share = share_of(&args[0], F, span)?;
    let handle = foreign::<Nonces>(&args[1])
        .ok_or_else(|| bad_option(F, "expected the nonces threshold_commit made".into(), span))?;
    let data = message(&args[2], F, span)?;
    let request = request(&data, &args[3], F, span)?;
    let pending = locked(&handle.0).take().ok_or_else(|| {
        refused(
            F,
            "these nonces already signed once; commit again".into(),
            span,
        )
    })?;
    let part = signing::sign(&request, pending, &share).map_err(|e| match e {
        ThresholdError::BelowThreshold { have, need } => below(F, "commitments", have, need, span),
        other => refusal(F, other, span),
    })?;
    Ok(record(vec![
        ("participant", int(part.participant.get())),
        ("hex", text(encode_hex(&part.to_bytes()))),
    ]))
}

fn aggregate(args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_aggregate";
    let group = GroupKey::from_bytes(&hex_of(&args[0], "group", F, span)?)
        .map_err(|e| undecodable(F, "group", e, span))?;
    let data = message(&args[1], F, span)?;
    let request = request(&data, &args[2], F, span)?;
    let mut parts = Vec::new();
    for s in &list(&args[3], "signature shares", F, span)? {
        let signer = participant(
            need(s, "participant", "signature share", F, span)?,
            "participant",
            F,
            span,
        )?;
        let bytes = hex_of(
            need(s, "hex", "signature share", F, span)?,
            "signature share",
            F,
            span,
        )?;
        parts.push(
            signing::SignatureShare::from_bytes(signer, &bytes)
                .map_err(|e| undecodable(F, "signature share", e, span))?,
        );
    }
    let signature = signing::aggregate(&group, &request, &parts).map_err(|e| match e {
        ThresholdError::BelowThreshold { have, need } => {
            below(F, "signature shares", have, need, span)
        }
        ThresholdError::UnknownParticipant(p) => refused(
            F,
            format!("participant {p} signed without a commitment"),
            span,
        ),
        ThresholdError::DuplicateParticipant(p) => {
            refused(F, format!("participant {p} signs twice"), span)
        }
        other => refusal(F, other, span),
    })?;
    Ok(text(encode_hex(&signature.to_bytes())))
}

fn to_list(xs: &[Value]) -> String {
    xs.iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(", ")
}

fn share_export(args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_share_export";
    let share = share_of(&args[0], F, span)?;
    let bytes = share.to_bytes().map_err(|e| refusal(F, e, span))?;
    Ok(text(encode_hex(&bytes)))
}

fn share_import(args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_share_import";
    let bytes = hex_of(&args[0], "share", F, span)?;
    let share = KeyShare::from_bytes(&bytes).map_err(|e| match e {
        ThresholdError::InvalidParticipant(_) => refused(
            F,
            "the share names no participant from 1 to 65535".into(),
            span,
        ),
        other => undecodable(F, "share", other, span),
    })?;
    Ok(share_value(share))
}

fn install<H: 'static>(interp: &mut Interpreter<H>, key: Key, source: &Source) {
    let s = source.clone();
    interp.register_fn(
        key("threshold_deal"),
        Arity::Exact(2),
        move |args: &[Value], _h: &mut H, span| deal(&s, args, span),
    );
    let s = source.clone();
    interp.register_fn(
        key("threshold_dkg_start"),
        Arity::Exact(3),
        move |args: &[Value], _h: &mut H, span| dkg_start(&s, args, span),
    );
    interp.register_fn(
        key("threshold_dkg_exchange"),
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| dkg_exchange(args, span),
    );
    interp.register_fn(
        key("threshold_dkg_finish"),
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, span| dkg_finish(args, span),
    );
    let s = source.clone();
    interp.register_fn(
        key("threshold_commit"),
        Arity::Exact(2),
        move |args: &[Value], _h: &mut H, span| commit(&s, args, span),
    );
    interp.register_fn(
        key("threshold_sign"),
        Arity::Exact(4),
        |args: &[Value], _h: &mut H, span| sign(args, span),
    );
    interp.register_fn(
        key("threshold_aggregate"),
        Arity::Exact(4),
        |args: &[Value], _h: &mut H, span| aggregate(args, span),
    );
    interp.register_fn(
        key("threshold_share_export"),
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| share_export(args, span),
    );
    interp.register_fn(
        key("threshold_share_import"),
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| share_import(args, span),
    );
}

pub fn install_threshold<H: 'static>(interp: &mut Interpreter<H>) {
    install(interp, String::from, &Source::Host);
}

pub fn provide_seeded<H: 'static>(interp: &mut Interpreter<H>, key: Key, seed: &str) {
    install(interp, key, &Source::seeded(seed));
}

#[cfg(test)]
mod tests {
    use super::*;

    const WHOLE_KEY: &[&str] = &[
        "keys::reconstruct",
        "keys::split",
        "SigningKey",
        "keys::refresh",
        "keys::repairable",
    ];

    fn module_source() -> &'static str {
        let all = include_str!("threshold.rs");
        &all[..all.find("#[cfg(test)]").expect("the test module")]
    }

    #[test]
    fn the_module_names_no_frost_item_that_holds_or_rebuilds_a_whole_key() {
        let source = module_source();
        assert!(source.contains("keygen::trusted_dealer_with_rng"));
        assert!(!source.contains("frost"));
        for item in WHOLE_KEY {
            assert!(!source.contains(item), "{item}");
        }
    }

    fn eval(interp: &mut Interpreter<()>, src: &str) -> Result<String, String> {
        let forms = tatara_lisp::read_spanned(src).map_err(|e| e.to_string())?;
        interp
            .eval_program(&forms, &mut ())
            .map(|v| v.to_string())
            .map_err(|e| e.to_string())
    }

    fn seeded(seed: &str) -> Interpreter<()> {
        let mut interp = crate::interpreter_hostless();
        provide_seeded(&mut interp, String::from, seed);
        interp
    }

    const DEAL_AND_SIGN: &str = "(begin (define g (threshold_deal 2 3)) (define s1 (car (get g :shares))) (define s2 (car (cdr (get g :shares)))) (define a (threshold_commit s1 \"m\")) (define b (threshold_commit s2 \"m\")) (define cs (list (get a :commitment) (get b :commitment))) (define parts (list (threshold_sign s1 (get a :nonces) \"m\" cs) (threshold_sign s2 (get b :nonces) \"m\" cs))) (list (get g :key) (threshold_aggregate (get g :group) \"m\" cs parts)))";

    #[test]
    fn a_seeded_source_deals_and_signs_the_same_way_twice_and_another_seed_does_not() {
        let first = eval(&mut seeded("synod"), DEAL_AND_SIGN).expect("seeded");
        let again = eval(&mut seeded("synod"), DEAL_AND_SIGN).expect("seeded");
        let other = eval(&mut seeded("other"), DEAL_AND_SIGN).expect("seeded");
        assert_eq!(first, again);
        assert_ne!(first, other);
    }

    #[test]
    fn the_host_source_draws_fresh_keys_each_deal() {
        let mut interp = crate::interpreter_hostless();
        install_threshold(&mut interp);
        let a = eval(&mut interp, "(get (threshold_deal 2 3) :key)").expect("host");
        let b = eval(&mut interp, "(get (threshold_deal 2 3) :key)").expect("host");
        assert_ne!(a, b);
    }

    #[test]
    fn a_draw_is_keyed_by_its_seed_and_advances_the_stream() {
        let source = Source::seeded("s");
        let span = Span::synthetic();
        let mut one = [0u8; 16];
        let mut two = [0u8; 16];
        rand_core::RngCore::fill_bytes(&mut source.draw("t", span).expect("draw"), &mut one);
        rand_core::RngCore::fill_bytes(&mut source.draw("t", span).expect("draw"), &mut two);
        assert_ne!(one, two);
        let mut fresh = [0u8; 16];
        rand_core::RngCore::fill_bytes(
            &mut Source::seeded("s").draw("t", span).expect("draw"),
            &mut fresh,
        );
        assert_eq!(one, fresh);
    }
}
