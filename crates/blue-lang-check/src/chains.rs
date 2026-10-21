use tatara_lisp::{Atom, Spanned, SpannedForm};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Text,
    Int,
    Float,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ChainRule {
    pub id: &'static str,
    pub slug: &'static str,
    pub outer: &'static str,
    pub inner_calls: &'static [&'static str],
    pub inner_literal: Option<Kind>,
    pub soundness: &'static str,
}

pub const TEXT_CALLS: &[&str] = &["to_s", "string", "concat", "trim", "upcase", "downcase"];
pub const INT_CALLS: &[&str] = &["to_int!", "length"];
pub const FLOAT_CALLS: &[&str] = &["sqrt"];

pub const RULES: &[ChainRule] = &[
    ChainRule {
        id: "C0001",
        slug: "to_s-of-text",
        outer: "to_s",
        inner_calls: TEXT_CALLS,
        inner_literal: Some(Kind::Text),
        soundness: "to_s of a string is the string (D0005), and each inner call always returns a string or refuses before to_s runs",
    },
    ChainRule {
        id: "C0002",
        slug: "string-of-text",
        outer: "string",
        inner_calls: TEXT_CALLS,
        inner_literal: Some(Kind::Text),
        soundness: "string renders a string as its own characters, and each inner call always returns a string or refuses before string runs",
    },
    ChainRule {
        id: "C0003",
        slug: "to_int!-of-int",
        outer: "to_int!",
        inner_calls: INT_CALLS,
        inner_literal: Some(Kind::Int),
        soundness: "to_int! of an Int is the Int, and each inner call always returns an Int or refuses before to_int! runs",
    },
    ChainRule {
        id: "C0004",
        slug: "to_int-of-int",
        outer: "to_int",
        inner_calls: INT_CALLS,
        inner_literal: Some(Kind::Int),
        soundness: "to_int of an Int is the Int, and each inner call always returns an Int or refuses before to_int runs",
    },
    ChainRule {
        id: "C0005",
        slug: "to_float-of-float",
        outer: "to_float",
        inner_calls: FLOAT_CALLS,
        inner_literal: Some(Kind::Float),
        soundness: "to_float of a Float is the Float, and sqrt always returns a Float or refuses before to_float runs",
    },
    ChainRule {
        id: "C0006",
        slug: "trim-twice",
        outer: "trim",
        inner_calls: &["trim"],
        inner_literal: None,
        soundness: "the result of trim starts and ends with a non-whitespace character, so a second trim removes nothing",
    },
];

pub const REJECTED: &[(&str, &str)] = &[
    ("to_int(to_int(x))", "x = \"abc\": the inner call is nil and to_int(nil) refuses, while to_int(\"abc\") is nil"),
    ("to_float(to_float(x))", "x = \"abc\": the inner call is nil and to_float(nil) refuses, while to_float(\"abc\") is nil"),
    ("to_int(to_s(x))", "x = 1.5: to_int(1.5) is 1, while to_int(\"1.5\") is nil"),
    ("to_s(to_int(x))", "x = \"abc\": to_s(nil) is \"\", while to_s(\"abc\") is \"abc\""),
    ("to_int(to_float(x))", "x = 9007199254740993: the Float rounds, so the Int changes"),
    ("to_float(to_int(x))", "x = 1.5: to_float(to_int(1.5)) is 1.0, while to_float(1.5) is 1.5"),
    ("to_s(string(x))", "x = :a: string(:a) is \":a\", so to_s gives \":a\" where to_s(:a) is \"a\""),
    ("upcase(downcase(x))", "x = \"\\u{1e9e}\": downcase gives \"ß\", upcase gives \"SS\", where upcase(x) is \"\\u{1e9e}\""),
    ("upcase(upcase(x)), downcase(downcase(x))", "idempotence of case mapping is not guaranteed by Unicode, so no proof"),
    ("cast(:float, to_float(x))", "x = \"abc\": the inner call is nil and cast(:float, nil) refuses, while to_float(\"abc\") is nil"),
];

#[must_use]
pub fn rule(id: &str) -> Option<&'static ChainRule> {
    RULES.iter().find(|r| r.id == id)
}

#[must_use]
pub fn call_arity_ok(call: &str, argc: usize) -> bool {
    if call == "concat" {
        argc >= 1
    } else {
        argc == 1
    }
}

#[must_use]
pub fn literal_kind(form: &Spanned) -> Option<Kind> {
    match &form.form {
        SpannedForm::Atom(Atom::Str(_)) => Some(Kind::Text),
        SpannedForm::Atom(Atom::Int(_)) => Some(Kind::Int),
        SpannedForm::Atom(Atom::Float(_)) => Some(Kind::Float),
        _ => None,
    }
}

#[must_use]
pub fn simplifies(outer: &str, arg: &Spanned, builtin: &dyn Fn(&str) -> bool) -> Option<&'static ChainRule> {
    RULES.iter().find(|r| {
        r.outer == outer
            && match arg.as_list() {
                Some([head, rest @ ..]) => head.as_symbol().is_some_and(|h| {
                    r.inner_calls.contains(&h) && call_arity_ok(h, rest.len()) && builtin(h)
                }),
                _ => r
                    .inner_literal
                    .is_some_and(|k| literal_kind(arg) == Some(k)),
            }
    })
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Case {
    Call { inner: &'static str, argc: usize },
    Literal(Kind),
}

#[must_use]
pub fn cases(rule: &ChainRule) -> Vec<Case> {
    let mut out: Vec<Case> = rule
        .inner_calls
        .iter()
        .map(|c| Case::Call {
            inner: c,
            argc: if *c == "concat" { 2 } else { 1 },
        })
        .collect();
    out.extend(rule.inner_literal.map(Case::Literal));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_unique_and_every_row_has_a_case_and_a_reason() {
        let mut ids: Vec<&str> = RULES.iter().map(|r| r.id).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), RULES.len());
        for r in RULES {
            assert!(!cases(r).is_empty(), "{} matches nothing", r.id);
            assert!(!r.soundness.trim().is_empty(), "{} has no soundness note", r.id);
        }
    }
}
