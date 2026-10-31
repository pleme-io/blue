use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use frost_ed25519 as frost;
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, MapKey, Value};

use crate::crypto::{
    ed25519_verify, encode_hex, hex_vec, message_bytes, KEY_BYTES, SIGNATURE_BYTES,
};
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

struct ShareSecret {
    participant: u16,
    package: frost::keys::KeyPackage,
}

struct Pending {
    participant: u16,
    digest: [u8; 32],
    nonces: frost::round1::SigningNonces,
}

struct Nonces(Mutex<Option<Pending>>);

struct Round1State {
    participant: u16,
    max: u16,
    package: frost::keys::dkg::round1::SecretPackage,
}

struct Round1Secret(Mutex<Option<Round1State>>);

struct Round2State {
    participant: u16,
    max: u16,
    package: frost::keys::dkg::round2::SecretPackage,
}

struct Round2Secret(Mutex<Option<Round2State>>);

fn refused(fname: &'static str, message: String, span: Span) -> EvalError {
    raise_kind("refused", format!("{fname}: {message}"), span)
}

fn bad_option(fname: &'static str, message: String, span: Span) -> EvalError {
    raise_kind("bad_option", format!("{fname}: {message}"), span)
}

fn undecodable(
    fname: &'static str,
    what: &str,
    why: impl std::fmt::Display,
    span: Span,
) -> EvalError {
    raise_kind(
        "decode_error",
        format!("{fname}: the {what} does not decode: {why}"),
        span,
    )
}

fn protocol(fname: &'static str, e: &frost::Error, span: Span) -> EvalError {
    refused(fname, format!("the threshold protocol refused: {e}"), span)
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

fn identifier(participant: u16) -> frost::Identifier {
    frost::Identifier::try_from(participant).expect("a participant from 1 is a frost identifier")
}

fn participant_of(id: &frost::Identifier) -> Option<u16> {
    match id.serialize().as_slice() {
        [low, high, rest @ ..] if rest.iter().all(|b| *b == 0) => {
            let p = u16::from_le_bytes([*low, *high]);
            (p >= 1 && identifier(p) == *id).then_some(p)
        }
        _ => None,
    }
}

fn params(
    min: &Value,
    max: &Value,
    fname: &'static str,
    span: Span,
) -> Result<(u16, u16), EvalError> {
    let k = index(min, "threshold", fname, span)?;
    let n = index(max, "group size", fname, span)?;
    if k < 2 || k > n {
        return Err(bad_option(
            fname,
            format!("a threshold group needs 2 <= k <= n, got {k}-of-{n}"),
            span,
        ));
    }
    Ok((k, n))
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

fn share_value(secret: ShareSecret) -> Result<Value, String> {
    let key = verifying_hex(secret.package.verifying_key())?;
    let min = *secret.package.min_signers();
    let participant = secret.participant;
    Ok(record(vec![
        ("participant", int(participant)),
        ("key", text(key)),
        ("min", int(min)),
        ("secret", Value::Foreign(Arc::new(secret))),
    ]))
}

fn share_of(v: &Value, fname: &'static str, span: Span) -> Result<Arc<ShareSecret>, EvalError> {
    field(v, "secret")
        .and_then(foreign::<ShareSecret>)
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

fn verifying_hex(key: &frost::VerifyingKey) -> Result<String, String> {
    key.serialize()
        .map(|b| encode_hex(&b))
        .map_err(|e| e.to_string())
}

fn group_value(group: &frost::keys::PublicKeyPackage) -> Result<(String, String), String> {
    let bytes = group.serialize().map_err(|e| e.to_string())?;
    Ok((encode_hex(&bytes), verifying_hex(group.verifying_key())?))
}

fn group_of(
    v: &Value,
    fname: &'static str,
    span: Span,
) -> Result<frost::keys::PublicKeyPackage, EvalError> {
    let bytes = hex_of(v, "group", fname, span)?;
    frost::keys::PublicKeyPackage::deserialize(&bytes)
        .map_err(|e| undecodable(fname, "group", e, span))
}

fn commitments_of(
    v: &Value,
    fname: &'static str,
    span: Span,
) -> Result<BTreeMap<frost::Identifier, frost::round1::SigningCommitments>, EvalError> {
    let mut by = BTreeMap::new();
    for c in &list(v, "commitments", fname, span)? {
        let participant = index(
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
        let commitment = frost::round1::SigningCommitments::deserialize(&bytes)
            .map_err(|e| undecodable(fname, "commitment", e, span))?;
        if by.insert(identifier(participant), commitment).is_some() {
            return Err(refused(
                fname,
                format!("participant {participant} commits twice"),
                span,
            ));
        }
    }
    Ok(by)
}

fn at_least(
    have: usize,
    need: u16,
    what: &str,
    fname: &'static str,
    span: Span,
) -> Result<(), EvalError> {
    if have < usize::from(need) {
        return Err(raise_kind_with(
            "refused",
            format!("{fname}: {have} {what} cannot sign for a group that needs {need}"),
            record(vec![
                ("have", int(i64::try_from(have).unwrap_or(i64::MAX))),
                ("need", int(need)),
            ]),
            span,
        ));
    }
    Ok(())
}

fn digest(message: &[u8]) -> [u8; 32] {
    *blake3::hash(message).as_bytes()
}

fn deal(source: &Source, args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_deal";
    let (k, n) = params(&args[0], &args[1], F, span)?;
    let rng = source.draw(F, span)?;
    let (secret_shares, group) =
        frost::keys::generate_with_dealer(n, k, frost::keys::IdentifierList::Default, rng)
            .map_err(|e| protocol(F, &e, span))?;
    let native = |e: String| EvalError::native_fn(F, e, span);
    let mut shares = Vec::with_capacity(usize::from(n));
    for participant in 1..=n {
        let secret_share = secret_shares
            .get(&identifier(participant))
            .ok_or_else(|| native(format!("the dealer made no share for {participant}")))?;
        let package = frost::keys::KeyPackage::try_from(secret_share.clone())
            .map_err(|e| protocol(F, &e, span))?;
        shares.push(
            share_value(ShareSecret {
                participant,
                package,
            })
            .map_err(native)?,
        );
    }
    let (group_hex, key) = group_value(&group).map_err(native)?;
    Ok(record(vec![
        ("group", text(group_hex)),
        ("key", text(key)),
        ("min", int(k)),
        ("max", int(n)),
        ("shares", Value::list(shares)),
    ]))
}

fn dkg_start(source: &Source, args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_dkg_start";
    let participant = index(&args[0], "participant", F, span)?;
    let (k, n) = params(&args[1], &args[2], F, span)?;
    if participant > n {
        return Err(bad_option(
            F,
            format!("participant {participant} is not in a group of {n}"),
            span,
        ));
    }
    let rng = source.draw(F, span)?;
    let (secret, package) = frost::keys::dkg::part1(identifier(participant), n, k, rng)
        .map_err(|e| protocol(F, &e, span))?;
    let bytes = package.serialize().map_err(|e| protocol(F, &e, span))?;
    Ok(record(vec![
        (
            "secret",
            Value::Foreign(Arc::new(Round1Secret(Mutex::new(Some(Round1State {
                participant,
                max: n,
                package: secret,
            }))))),
        ),
        (
            "broadcast",
            record(vec![
                ("from", int(participant)),
                ("package", text(encode_hex(&bytes))),
            ]),
        ),
    ]))
}

fn broadcasts_from_others(
    me: u16,
    max: u16,
    v: &Value,
    fname: &'static str,
    span: Span,
) -> Result<BTreeMap<frost::Identifier, frost::keys::dkg::round1::Package>, EvalError> {
    let mut others = BTreeMap::new();
    for b in &list(v, "broadcasts", fname, span)? {
        let from = index(
            need(b, "from", "broadcast", fname, span)?,
            "sender",
            fname,
            span,
        )?;
        if from > max {
            return Err(refused(
                fname,
                format!("participant {from} is not in a group of {max}"),
                span,
            ));
        }
        if from == me {
            continue;
        }
        let bytes = hex_of(
            need(b, "package", "broadcast", fname, span)?,
            "broadcast",
            fname,
            span,
        )?;
        let package = frost::keys::dkg::round1::Package::deserialize(&bytes)
            .map_err(|e| undecodable(fname, "broadcast", e, span))?;
        if others.insert(identifier(from), package).is_some() {
            return Err(refused(
                fname,
                format!("participant {from} broadcasts twice"),
                span,
            ));
        }
    }
    Ok(others)
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
    let others = broadcasts_from_others(state.participant, state.max, &args[1], F, span)?;
    let (secret, outgoing) =
        frost::keys::dkg::part2(state.package, &others).map_err(|e| protocol(F, &e, span))?;
    let mut sends = Vec::with_capacity(outgoing.len());
    for to in 1..=state.max {
        if let Some(package) = outgoing.get(&identifier(to)) {
            let bytes = package.serialize().map_err(|e| protocol(F, &e, span))?;
            sends.push(record(vec![
                ("from", int(state.participant)),
                ("to", int(to)),
                ("package", text(encode_hex(&bytes))),
            ]));
        }
    }
    Ok(record(vec![
        (
            "secret",
            Value::Foreign(Arc::new(Round2Secret(Mutex::new(Some(Round2State {
                participant: state.participant,
                max: state.max,
                package: secret,
            }))))),
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
    let others = broadcasts_from_others(state.participant, state.max, &args[1], F, span)?;
    let mut mine = BTreeMap::new();
    for s in &list(&args[2], "sends", F, span)? {
        let to = index(need(s, "to", "send", F, span)?, "recipient", F, span)?;
        if to != state.participant {
            continue;
        }
        let from = index(need(s, "from", "send", F, span)?, "sender", F, span)?;
        if from > state.max || from == state.participant {
            return Err(refused(
                F,
                format!("participant {from} cannot send to {to}"),
                span,
            ));
        }
        let bytes = hex_of(need(s, "package", "send", F, span)?, "send", F, span)?;
        let package = frost::keys::dkg::round2::Package::deserialize(&bytes)
            .map_err(|e| undecodable(F, "send", e, span))?;
        if mine.insert(identifier(from), package).is_some() {
            return Err(refused(F, format!("participant {from} sends twice"), span));
        }
    }
    let (package, group) = frost::keys::dkg::part3(&state.package, &others, &mine)
        .map_err(|e| protocol(F, &e, span))?;
    let native = |e: String| EvalError::native_fn(F, e, span);
    let share = share_value(ShareSecret {
        participant: state.participant,
        package,
    })
    .map_err(native)?;
    let (group_hex, key) = group_value(&group).map_err(native)?;
    Ok(record(vec![
        ("share", share),
        ("group", text(group_hex)),
        ("key", text(key)),
    ]))
}

fn commit(source: &Source, args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_commit";
    let share = share_of(&args[0], F, span)?;
    let data = message(&args[1], F, span)?;
    let mut rng = source.draw(F, span)?;
    let (nonces, commitments) = frost::round1::commit(share.package.signing_share(), &mut rng);
    let bytes = commitments.serialize().map_err(|e| protocol(F, &e, span))?;
    Ok(record(vec![
        (
            "nonces",
            Value::Foreign(Arc::new(Nonces(Mutex::new(Some(Pending {
                participant: share.participant,
                digest: digest(&data),
                nonces,
            }))))),
        ),
        (
            "commitment",
            record(vec![
                ("participant", int(share.participant)),
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
    let commitments = commitments_of(&args[3], F, span)?;
    let pending = locked(&handle.0).take().ok_or_else(|| {
        refused(
            F,
            "these nonces already signed once; commit again".into(),
            span,
        )
    })?;
    if pending.participant != share.participant || pending.digest != digest(&data) {
        return Err(refused(
            F,
            format!(
                "participant {} committed to a different signing session",
                share.participant
            ),
            span,
        ));
    }
    at_least(
        commitments.len(),
        *share.package.min_signers(),
        "commitments",
        F,
        span,
    )?;
    let request = frost::SigningPackage::new(commitments, &data);
    let signature_share =
        frost::round2::sign(&request, &pending.nonces, &share.package).map_err(|e| match e {
            frost::Error::MissingCommitment | frost::Error::IncorrectCommitment => refused(
                F,
                format!(
                    "the commitments do not carry participant {}'s commitment",
                    share.participant
                ),
                span,
            ),
            other => protocol(F, &other, span),
        })?;
    Ok(record(vec![
        ("participant", int(share.participant)),
        ("hex", text(encode_hex(&signature_share.serialize()))),
    ]))
}

fn aggregate(args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_aggregate";
    let group = group_of(&args[0], F, span)?;
    let data = message(&args[1], F, span)?;
    let commitments = commitments_of(&args[2], F, span)?;
    let need_k = group
        .min_signers()
        .ok_or_else(|| EvalError::native_fn(F, "the group names no threshold", span))?;
    let mut by = BTreeMap::new();
    let mut signers = BTreeSet::new();
    for s in &list(&args[3], "signature shares", F, span)? {
        let participant = index(
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
        let share = frost::round2::SignatureShare::deserialize(&bytes)
            .map_err(|e| undecodable(F, "signature share", e, span))?;
        if !commitments.contains_key(&identifier(participant)) {
            return Err(refused(
                F,
                format!("participant {participant} signed without a commitment"),
                span,
            ));
        }
        if by.insert(identifier(participant), share).is_some() {
            return Err(refused(
                F,
                format!("participant {participant} signs twice"),
                span,
            ));
        }
        signers.insert(participant);
    }
    at_least(by.len(), need_k, "signature shares", F, span)?;
    let request = frost::SigningPackage::new(commitments, &data);
    let signature = frost::aggregate(&request, &by, &group).map_err(|e| {
        let culprits: Vec<Value> = signers
            .iter()
            .filter(|p| e.culprits().contains(&identifier(**p)))
            .map(|p| int(*p))
            .collect();
        if culprits.is_empty() {
            protocol(F, &e, span)
        } else {
            raise_kind_with(
                "tampered",
                format!(
                    "{F}: signature shares from participants {} do not verify",
                    to_list(&culprits)
                ),
                record(vec![("culprits", Value::list(culprits))]),
                span,
            )
        }
    })?;
    let bytes = signature.serialize().map_err(|e| protocol(F, &e, span))?;
    let sig = <[u8; SIGNATURE_BYTES]>::try_from(bytes.as_slice())
        .map_err(|_| EvalError::native_fn(F, "an Ed25519 signature is 64 bytes", span))?;
    let key_bytes = group
        .verifying_key()
        .serialize()
        .map_err(|e| protocol(F, &e, span))?;
    let key = <[u8; KEY_BYTES]>::try_from(key_bytes.as_slice())
        .map_err(|_| EvalError::native_fn(F, "an Ed25519 key is 32 bytes", span))?;
    match ed25519_verify(&key, &data, &sig) {
        Ok(true) => Ok(text(encode_hex(&sig))),
        Ok(false) | Err(_) => Err(raise_kind(
            "tampered",
            format!("{F}: the aggregate is not a valid signature under the group key"),
            span,
        )),
    }
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
    let bytes = share
        .package
        .serialize()
        .map_err(|e| protocol(F, &e, span))?;
    Ok(text(encode_hex(&bytes)))
}

fn share_import(args: &[Value], span: Span) -> Result<Value, EvalError> {
    const F: &str = "threshold_share_import";
    let bytes = hex_of(&args[0], "share", F, span)?;
    let package = frost::keys::KeyPackage::deserialize(&bytes)
        .map_err(|e| undecodable(F, "share", e, span))?;
    let participant = participant_of(package.identifier()).ok_or_else(|| {
        refused(
            F,
            "the share names no participant from 1 to 65535".into(),
            span,
        )
    })?;
    share_value(ShareSecret {
        participant,
        package,
    })
    .map_err(|e| EvalError::native_fn(F, e, span))
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
        assert!(source.contains("frost::keys::generate_with_dealer"));
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
