//! M0's check against the parser: every table the kiwari spec states and
//! blue-lang-syntax also holds must be the same table.
//!
//! Until blue's parser is emitted from the spec (M3) these facts exist twice,
//! once in `bidamas/kiwari` and once in `parse.rs` / `kigou`; this file is
//! what keeps the second copy from drifting. The differential checks the
//! structure the tables drive; this checks the tables themselves, including
//! rows the corpus never exercises.
//!
//! Red runs, 2026-10-10, each reverted: `%`'s callee `mod` changed to `rem` in
//! the spec failed `the_infix_table_is_parse_rs_table`; `≠` dropped from the
//! `!=` row's aliases failed `the_operator_aliases_are_kigou_aliases`.

use std::collections::BTreeSet;

use blue_lang_kiwari::spec::{Spec, Template};
use blue_lang_syntax::kigou::OPERATOR_ALIASES;
use blue_lang_syntax::{
    BLOCK_KEYWORDS, INFIX, LOWERED_ASSERT, LOWERED_CONCAT, LOWERED_MAP, SURFACE_KEYWORDS,
};

fn spec() -> Spec {
    Spec::blue().expect("the rendered spec loads, every template with it")
}

#[test]
fn the_infix_table_is_parse_rs_table() {
    let ours: Vec<(String, (u8, u8), String)> = spec()
        .infix
        .iter()
        .map(|i| (i.op.clone(), i.power, i.callee.clone()))
        .collect();
    let theirs: Vec<(String, (u8, u8), String)> = INFIX
        .iter()
        .map(|i| (i.op.to_string(), i.power, i.callee.to_string()))
        .collect();
    assert_eq!(ours, theirs);
}

#[test]
fn the_operator_aliases_are_kigou_aliases() {
    let s = spec();
    let ours: BTreeSet<(String, String)> = s
        .infix
        .iter()
        .flat_map(|i| i.aliases.iter().map(|a| (a.clone(), i.op.clone())))
        .chain(
            s.unary
                .iter()
                .flat_map(|u| u.aliases.iter().map(|a| (a.clone(), u.op.clone()))),
        )
        .collect();
    let word = |op: &str| {
        blue_lang_syntax::SYMBOL_SPELLINGS
            .iter()
            .find(|(sym, _)| *sym == op)
            .map_or(op.to_string(), |(_, w)| (*w).to_string())
    };
    let theirs: BTreeSet<(String, String)> = OPERATOR_ALIASES
        .iter()
        .map(|(c, op, _)| (c.to_string(), word(op)))
        .chain(
            blue_lang_syntax::SYMBOL_SPELLINGS
                .iter()
                .map(|(sym, w)| ((*sym).to_string(), (*w).to_string())),
        )
        .collect();
    assert_eq!(ours, theirs);
}

#[test]
fn the_reserved_words_are_parse_rs_words() {
    let s = spec();
    assert_eq!(s.keywords.surface, SURFACE_KEYWORDS);
    assert_eq!(s.keywords.block, BLOCK_KEYWORDS);
}

fn mentions(t: &Template, sym: &str) -> bool {
    match t {
        Template::Sym(s) => s == sym,
        Template::Interpolate { join, .. } => join == sym,
        Template::List(ts) | Template::Seq(ts) => ts.iter().any(|t| mentions(t, sym)),
        Template::Field {
            default: Some(d), ..
        } => mentions(d, sym),
        Template::Each { each, .. } => mentions(each, sym),
        Template::Quote(t)
        | Template::Quasiquote(t)
        | Template::Unquote(t)
        | Template::UnquoteSplice(t) => mentions(t, sym),
        Template::IfAny {
            then, otherwise, ..
        }
        | Template::IfKind {
            then, otherwise, ..
        } => mentions(then, sym) || mentions(otherwise, sym),
        _ => false,
    }
}

#[test]
fn the_lowered_names_are_the_parser_s() {
    let s = spec();
    for (kind, name) in [
        ("assert", LOWERED_ASSERT),
        ("map", LOWERED_MAP),
        ("string", LOWERED_CONCAT),
    ] {
        let t = s
            .lower
            .get(kind)
            .unwrap_or_else(|| panic!("the spec lowers no `{kind}`"));
        assert!(
            mentions(t, name),
            "`{kind}` lowers without `{name}`, the name parse.rs lowers it to"
        );
    }
}
