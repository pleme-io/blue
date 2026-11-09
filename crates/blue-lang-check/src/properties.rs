//! Properties from what a definition already says (HORIZON H6).
//!
//! A `@doc` example is a point: `pick(1) #=> "b"` says what one call returns.
//! A typed signature is a promise over every call: `def pick(i: Int) -> Str`
//! says each `Int` argument gives back a `Str`. The type erases before the
//! evaluator runs, so nothing holds that promise at run time, and an example
//! can only say no at its own point.
//!
//! [`properties`] puts the two together. For each example call of a typed
//! definition it draws calls in the neighbourhood of the point: each literal
//! argument whose declared type is `Int`, `Float`, `Str` or `Bool` moves a
//! little, the other arguments stay as written. Each drawn call becomes one
//! assertion of a `test` block: the call returns the declared type, judged by
//! the one predicate that judges a typed record field ([`CONFORMS`]). A call
//! that raises passes, since a refusal breaks no return type.
//!
//! The draws come from `ran`'s linear congruential generator, seeded per
//! definition and example from one seed ([`Setting`], `BLUE_PROPERTY_SEED`),
//! and land in the tree as literals. So a seed names its cases, the same seed
//! gives the same cases, and the failing call is printed as blue source.
//!
//! What gets no property, so no program that runs today is refused: an
//! untyped definition, a typed one whose return type is `dyn` or a name, one
//! with an optional or rest parameter, and an example call with no literal
//! argument of a type the generator draws.

use std::collections::BTreeMap;

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::Ty;

/// The name every generated property's `test` block starts with.
pub const PROPERTY_PREFIX: &str = "@property ";

/// The runtime predicate a property asserts with: `(blue-conforms? 'T v)`,
/// whether `v` is a value of the signature type `T`.
pub const CONFORMS: &str = "blue-conforms?";

/// The word a failing property is printed with: `conforms?(grade(50), Str)`.
pub const SHOWN: &str = "conforms?";

/// The variable that seeds the generator, or turns it off.
pub const ENV: &str = "BLUE_PROPERTY_SEED";

/// The seed when [`ENV`] is unset, so every run draws the same cases.
pub const DEFAULT_SEED: u32 = 1;

/// Calls drawn around each example call, before duplicates are dropped.
pub const DRAWS: usize = 8;

/// Whether properties are generated, and from which seed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Setting {
    Off,
    Seed(u32),
}

impl Setting {
    /// Read a setting as [`ENV`] spells it: unset or empty is
    /// [`DEFAULT_SEED`], `off` turns properties off, a whole number is the
    /// seed.
    ///
    /// # Errors
    ///
    /// Any other text, named with what the variable takes.
    pub fn from_setting(setting: Option<&str>) -> Result<Self, String> {
        match setting.map(str::trim) {
            None | Some("") => Ok(Self::Seed(DEFAULT_SEED)),
            Some("off") => Ok(Self::Off),
            Some(v) => v.parse::<u32>().map(Self::Seed).map_err(|_| {
                format!("{ENV} is {v:?}; it takes off, or a whole number from 0 to 4294967295")
            }),
        }
    }

    /// The setting of this process's environment.
    ///
    /// # Errors
    ///
    /// As [`Setting::from_setting`].
    pub fn configured() -> Result<Self, String> {
        Self::from_setting(std::env::var(ENV).ok().as_deref())
    }
}

/// `ran::next_seed`: the generator's step.
#[must_use]
pub fn next_seed(s: u32) -> u32 {
    s.wrapping_mul(1_664_525).wrapping_add(1_013_904_223)
}

/// `ran::next_uniform`: a draw in `[0, bound)` from the top of the next word.
#[must_use]
pub fn next_uniform(s: u32, bound: u32) -> u32 {
    ((u64::from(next_seed(s)) * u64::from(bound)) >> 32) as u32
}

/// The first state of the stream for one definition's example `k`: the seed
/// mixed with the name, so a definition's cases do not move when another
/// definition is added beside it.
#[must_use]
pub fn stream(seed: u32, name: &str, k: usize) -> u32 {
    let mut h: u32 = 0x811c_9dc5;
    for b in name.bytes().chain((k as u32).to_le_bytes()) {
        h = (h ^ u32::from(b)).wrapping_mul(0x0100_0193);
    }
    h ^ seed
}

/// A typed signature a property can be drawn from: every parameter plain
/// (no optional or rest marker) and a return type the runtime can judge.
#[derive(Clone, Debug, PartialEq)]
pub struct Signature {
    pub params: Vec<Ty>,
    pub ret: Ty,
}

fn judged(t: &Ty) -> bool {
    match t {
        Ty::Int | Ty::Float | Ty::Str | Ty::Bool | Ty::Sym | Ty::Nil => true,
        Ty::List(inner) => judged(inner),
        _ => false,
    }
}

/// The signatures of `forms`' typed definitions a property can be drawn
/// from, by name.
#[must_use]
pub fn signatures(forms: &[Spanned]) -> BTreeMap<String, Signature> {
    forms
        .iter()
        .filter(|f| {
            f.as_list()
                .and_then(|items| items.get(1))
                .and_then(Spanned::as_list)
                .is_some_and(|sig| !sig[1..].iter().any(crate::is_marker))
        })
        .filter_map(crate::read_typed_decl)
        .filter(|(_, sig)| judged(&sig.ret))
        .map(|(name, sig)| {
            (
                name,
                Signature {
                    params: sig.params,
                    ret: sig.ret,
                },
            )
        })
        .collect()
}

/// The generated property tests of a program: `forms` is its parse,
/// `doctests` its `@doc` examples as `blue_lang_syntax::doc::doctests` lowers
/// them. One `test` block per example of a typed definition that has a drawn
/// call, spanned at the example.
#[must_use]
pub fn properties(forms: &[Spanned], doctests: &[Spanned], seed: u32) -> Vec<Spanned> {
    if doctests.is_empty() {
        return Vec::new();
    }
    let sigs = signatures(forms);
    if sigs.is_empty() {
        return Vec::new();
    }
    doctests
        .iter()
        .filter_map(|t| property(t, &sigs, seed))
        .collect()
}

fn subject(test: &Spanned) -> Option<(String, usize, &Spanned)> {
    let [_, title, body] = test.as_list()? else {
        return None;
    };
    if !blue_lang_syntax::doc::is_doctest(test) {
        return None;
    }
    let rest = title
        .as_string()?
        .strip_prefix(blue_lang_syntax::doc::DOCTEST_PREFIX)?;
    let (name, tail) = rest.strip_prefix('`')?.split_once('`')?;
    let k = tail.trim().strip_prefix("example ")?.parse().ok()?;
    Some((name.to_string(), k, body))
}

fn property(test: &Spanned, sigs: &BTreeMap<String, Signature>, seed: u32) -> Option<Spanned> {
    let (name, k, body) = subject(test)?;
    let sig = sigs.get(&name)?;
    let stmts: Vec<&Spanned> = match body.as_list() {
        Some([head, rest @ ..]) if head.as_symbol() == Some("begin") => rest.iter().collect(),
        _ => vec![body],
    };
    let mut s = stream(seed, &name, k);
    let mut out = vec![sym(body.span, "begin")];
    let mut drawn = 0;
    for stmt in stmts {
        match checked_call(stmt, &name) {
            Some(call) => {
                for case in neighbours(call, sig, &mut s) {
                    out.push(assertion(&sig.ret, case));
                    drawn += 1;
                }
            }
            None if is_assert(stmt) => {}
            None => out.push(stmt.clone()),
        }
    }
    (drawn > 0).then(|| {
        Spanned::new(
            test.span,
            SpannedForm::List(vec![
                sym(test.span, "deftest"),
                Spanned::new(
                    test.span,
                    SpannedForm::Atom(Atom::Str(format!(
                        "{PROPERTY_PREFIX}`{name}` example {k}, seed {seed}"
                    ))),
                ),
                Spanned::new(body.span, SpannedForm::List(out)),
            ]),
        )
    })
}

fn is_assert(stmt: &Spanned) -> bool {
    stmt.as_list()
        .and_then(|items| items.first())
        .and_then(Spanned::as_symbol)
        == Some(blue_lang_syntax::LOWERED_ASSERT)
}

fn checked_call<'a>(stmt: &'a Spanned, name: &str) -> Option<&'a Spanned> {
    if !is_assert(stmt) {
        return None;
    }
    let [_, _, cmp] = stmt.as_list()? else {
        return None;
    };
    let [op, call, _] = cmp.as_list()? else {
        return None;
    };
    if op.as_symbol() != Some("equal?") {
        return None;
    }
    let head = call.as_list()?.first()?.as_symbol()?;
    (head == name).then_some(call)
}

fn neighbours(call: &Spanned, sig: &Signature, s: &mut u32) -> Vec<Spanned> {
    let Some([head, args @ ..]) = call.as_list() else {
        return Vec::new();
    };
    if args.len() != sig.params.len() {
        return Vec::new();
    }
    let drawable: Vec<bool> = args
        .iter()
        .zip(&sig.params)
        .map(|(a, t)| drawable(a, t))
        .collect();
    if !drawable.contains(&true) {
        return Vec::new();
    }
    let point = call.to_sexp().to_string();
    let mut seen = std::collections::BTreeSet::from([point]);
    let mut out = Vec::new();
    for _ in 0..DRAWS {
        let mut items = vec![head.clone()];
        for (a, d) in args.iter().zip(&drawable) {
            items.push(if *d { moved(a, s) } else { a.clone() });
        }
        let case = Spanned::new(call.span, SpannedForm::List(items));
        if seen.insert(case.to_sexp().to_string()) {
            out.push(case);
        }
    }
    out
}

fn drawable(arg: &Spanned, ty: &Ty) -> bool {
    matches!(
        (&arg.form, ty),
        (SpannedForm::Atom(Atom::Int(_)), Ty::Int)
            | (SpannedForm::Atom(Atom::Float(_)), Ty::Float)
            | (SpannedForm::Atom(Atom::Str(_)), Ty::Str)
            | (SpannedForm::Atom(Atom::Bool(_)), Ty::Bool)
    )
}

fn draw(s: &mut u32, bound: u32) -> u32 {
    let v = next_uniform(*s, bound);
    *s = next_seed(*s);
    v
}

fn moved(arg: &Spanned, s: &mut u32) -> Spanned {
    let atom = match &arg.form {
        SpannedForm::Atom(Atom::Int(v)) => Atom::Int(v.saturating_add(i64::from(draw(s, 9)) - 4)),
        SpannedForm::Atom(Atom::Float(v)) => Atom::Float(v + (f64::from(draw(s, 9)) - 4.0) * 0.5),
        SpannedForm::Atom(Atom::Bool(v)) => Atom::Bool(if draw(s, 2) == 0 { !v } else { *v }),
        SpannedForm::Atom(Atom::Str(v)) => {
            let mut chars: Vec<char> = v.chars().collect();
            let text = match draw(s, 5) {
                0 => String::new(),
                1 => format!("{v}a"),
                2 => {
                    chars.pop();
                    chars.into_iter().collect()
                }
                3 => format!("{v}{v}"),
                _ => chars.first().map(char::to_string).unwrap_or_default(),
            };
            Atom::Str(text)
        }
        _ => return arg.clone(),
    };
    Spanned::new(arg.span, SpannedForm::Atom(atom))
}

fn type_form(at: Span, t: &Ty) -> Spanned {
    match t {
        Ty::List(inner) => Spanned::new(
            at,
            SpannedForm::List(vec![sym(at, "List"), type_form(at, inner)]),
        ),
        other => sym(at, &other.name()),
    }
}

fn assertion(ret: &Ty, case: Spanned) -> Spanned {
    let at = case.span;
    let list = |items: Vec<Spanned>| Spanned::new(at, SpannedForm::List(items));
    let quote = |x: Spanned| Spanned::new(at, SpannedForm::Quote(Box::new(x)));
    let shown = list(vec![sym(at, SHOWN), case.clone(), type_form(at, ret)]);
    let judged = list(vec![sym(at, CONFORMS), quote(type_form(at, ret)), case]);
    let held = list(vec![
        sym(at, "try"),
        judged,
        list(vec![
            sym(at, "catch"),
            list(vec![sym(at, "_")]),
            Spanned::new(at, SpannedForm::Atom(Atom::Bool(true))),
        ]),
    ]);
    list(vec![
        sym(at, blue_lang_syntax::LOWERED_ASSERT),
        quote(shown),
        held,
    ])
}

fn sym(at: Span, name: &str) -> Spanned {
    Spanned::new(at, SpannedForm::Atom(Atom::Symbol(name.into())))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn generated(src: &str, seed: u32) -> Vec<String> {
        let forms = blue_lang_syntax::parse_program_tree(src).unwrap();
        let tests = blue_lang_syntax::doc::doctests(src).unwrap();
        properties(&forms, &tests, seed)
            .iter()
            .map(|t| t.to_sexp().to_string())
            .collect()
    }

    const TYPED: &str = "@doc \"\"\"\npick: a letter.\n\n    pick(1) #=> \"b\"\n\"\"\"\ndef pick(i: Int) -> Str\n  [\"a\", \"b\", \"c\"][i]\nend\n";

    #[test]
    fn the_generator_is_rans() {
        assert_eq!(next_seed(1), 1_015_568_748);
        assert_eq!(next_uniform(1, 2), 0, "ran: next_bool(1) #=> false");
        assert_eq!(next_seed(u32::MAX), 1_012_239_698);
    }

    #[test]
    fn a_typed_example_gets_one_property_of_drawn_neighbours() {
        let got = generated(TYPED, DEFAULT_SEED);
        assert_eq!(got.len(), 1, "{got:?}");
        assert!(
            got[0].starts_with("(deftest \"@property `pick` example 1, seed 1\""),
            "{}",
            got[0]
        );
        assert!(
            got[0].contains("(blue-conforms? 'Str (pick ") && got[0].contains("'(conforms? (pick "),
            "{}",
            got[0]
        );
        assert!(
            !got[0].contains("(pick 1)"),
            "the point itself is the doctest's: {}",
            got[0]
        );
    }

    #[test]
    fn one_seed_draws_one_set_of_cases_and_another_seed_another() {
        assert_eq!(generated(TYPED, 7), generated(TYPED, 7));
        let a = generated(TYPED, 7)[0].replace("seed 7", "");
        let b = generated(TYPED, 8)[0].replace("seed 8", "");
        assert_ne!(a, b);
    }

    #[test]
    fn an_untyped_definition_gets_no_property() {
        let untyped = TYPED.replace("def pick(i: Int) -> Str", "def pick(i)");
        assert!(generated(&untyped, DEFAULT_SEED).is_empty());
    }

    #[test]
    fn nothing_to_judge_or_draw_gets_no_property() {
        for (from, to) in [
            ("-> Str", "-> dyn"),
            ("-> Str", "-> letter"),
            ("pick(i: Int)", "pick(i: Int, j?: Int)"),
            ("pick(i: Int)", "pick(i: Str)"),
            ("pick(1) #=> \"b\"", "pick(ONE) #=> \"b\""),
        ] {
            let src = TYPED.replace(from, to);
            assert!(generated(&src, DEFAULT_SEED).is_empty(), "{from} -> {to}");
        }
    }

    #[test]
    fn the_setting_reads_off_a_seed_or_the_default_and_refuses_the_rest() {
        assert_eq!(Setting::from_setting(None), Ok(Setting::Seed(DEFAULT_SEED)));
        assert_eq!(
            Setting::from_setting(Some("")),
            Ok(Setting::Seed(DEFAULT_SEED))
        );
        assert_eq!(Setting::from_setting(Some("off")), Ok(Setting::Off));
        assert_eq!(Setting::from_setting(Some(" 42 ")), Ok(Setting::Seed(42)));
        let e = Setting::from_setting(Some("-1")).unwrap_err();
        assert!(e.contains(ENV) && e.contains("off"), "{e}");
    }
}
