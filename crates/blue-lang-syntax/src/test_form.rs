//! A `test` block as its tree: `(deftest "name" body)`, or with a declaration,
//! `(deftest "name" (blue-test-meta (hash-map :satisfies (list :nist_ac_6)
//! :target parse_token)) body)`.
//!
//! The ONE reader of the shape. The harness, the formatter, the check stage,
//! the resolver's walk and the engine each ask here, so a test with a
//! declaration is a test to all of them, never a stray four-item form one of
//! them evaluates as code.

use tatara_lisp::{Span, Spanned};

use crate::parse::{LOWERED_MAP, LOWERED_TEST_META};

/// The parts of one `deftest` form.
#[derive(Clone, Copy, Debug)]
pub struct TestParts<'a> {
    pub name: &'a str,
    pub name_span: Span,
    /// The `(blue-test-meta …)` node, when the test declares one.
    pub meta: Option<&'a Spanned>,
    pub body: &'a Spanned,
}

/// What a test declares: the controls it satisfies, by keyword, and the
/// definition it targets, as the tree holds it (a symbol, resolved to its
/// runtime key after resolution).
#[derive(Clone, Debug, Default)]
pub struct TestMeta<'a> {
    pub satisfies: Vec<(&'a str, Span)>,
    pub target: Option<&'a Spanned>,
    pub kind: Option<(&'a str, Span)>,
    pub allow: Vec<(&'a str, Span)>,
    pub fakes: Vec<(&'a str, Span)>,
}

/// The keys a test's declaration may hold, in the one order its tree holds
/// them.
pub const TEST_KEYS: &[&str] = &["satisfies", "target", "kind", "allow", "fakes"];

/// The kinds a test may declare (docs/TESTING.md section 4); `unit` when it
/// declares none.
pub const TEST_KINDS: &[&str] = &[
    "unit",
    "property",
    "snapshot",
    "contract",
    "integration",
    "rendering",
    "e2e",
];

/// The parts of `form` when it is a `deftest`.
#[must_use]
pub fn test_parts(form: &Spanned) -> Option<TestParts<'_>> {
    let items = form.as_list()?;
    if items.first()?.as_symbol()? != "deftest" {
        return None;
    }
    let name = items.get(1)?;
    let (meta, body) = match items {
        [_, _, body] => (None, body),
        [_, _, meta, body] if is_meta(meta) => (Some(meta), body),
        _ => return None,
    };
    Some(TestParts {
        name: name.as_string()?,
        name_span: name.span,
        meta,
        body,
    })
}

/// Is `form` a `(blue-test-meta …)` node?
#[must_use]
pub fn is_meta(form: &Spanned) -> bool {
    form.as_list()
        .and_then(|items| items.first())
        .and_then(Spanned::as_symbol)
        == Some(LOWERED_TEST_META)
}

/// The map a `(blue-test-meta (hash-map …))` node carries.
#[must_use]
pub fn meta_map(meta: &Spanned) -> Option<&Spanned> {
    match meta.as_list()? {
        [head, map] if head.as_symbol() == Some(LOWERED_TEST_META) => {
            let items = map.as_list()?;
            (items.first()?.as_symbol()? == LOWERED_MAP).then_some(map)
        }
        _ => None,
    }
}

/// The declaration a `(blue-test-meta …)` node holds.
#[must_use]
pub fn test_meta(meta: &Spanned) -> Option<TestMeta<'_>> {
    let items = meta_map(meta)?.as_list()?;
    let mut out = TestMeta::default();
    for pair in items[1..].chunks(2) {
        let [key, value] = pair else { return None };
        match key.as_keyword()? {
            "satisfies" => out.satisfies = keywords(value)?,
            "allow" => out.allow = keywords(value)?,
            "fakes" => out.fakes = keywords(value)?,
            "target" => out.target = Some(value),
            "kind" => out.kind = Some((value.as_keyword()?, value.span)),
            _ => return None,
        }
    }
    Some(out)
}

fn keywords(value: &Spanned) -> Option<Vec<(&str, Span)>> {
    let list = value.as_list()?;
    if list.first()?.as_symbol()? != "list" {
        return None;
    }
    list[1..]
        .iter()
        .map(|w| w.as_keyword().map(|k| (k, w.span)))
        .collect()
}

/// The kind a test declares, `unit` when it declares none.
#[must_use]
pub fn kind_of<'a>(meta: &TestMeta<'a>) -> &'a str {
    meta.kind.map_or("unit", |(k, _)| k)
}

/// The key a target symbol names: `%root/parse_token` after resolution,
/// `parse_token` as written.
#[must_use]
pub fn target_key<'a>(meta: &TestMeta<'a>) -> Option<&'a str> {
    meta.target.and_then(Spanned::as_symbol)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn first(src: &str) -> Spanned {
        crate::parse_program_tree(src)
            .expect("parse")
            .into_iter()
            .next()
            .expect("a form")
    }

    #[test]
    fn a_plain_test_has_no_meta_and_its_body_is_the_third_item() {
        let form = first("test \"t\"\n  assert 1\nend\n");
        let parts = test_parts(&form).expect("a test");
        assert_eq!(parts.name, "t");
        assert!(parts.meta.is_none());
        assert_eq!(parts.body.to_sexp().to_string(), "(blue-assert '1 1)");
    }

    #[test]
    fn a_test_declares_its_kind_what_it_touches_and_its_fakes_in_one_order() {
        let form = first(
            "test \"t\", {fakes: [:valkey], allow: %i[process network], kind: :integration}\n  assert true\nend\n",
        );
        let meta =
            test_meta(test_parts(&form).expect("a test").meta.expect("meta")).expect("reads");
        assert_eq!(kind_of(&meta), "integration");
        let allow: Vec<&str> = meta.allow.iter().map(|(w, _)| *w).collect();
        assert_eq!(allow, ["network", "process"]);
        assert_eq!(meta.fakes.len(), 1);
        assert_eq!(
            form.to_sexp().to_string(),
            "(deftest \"t\" (blue-test-meta (hash-map :kind :integration :allow (list :network :process) :fakes (list :valkey))) (blue-assert '#t #t))"
        );
        let notes = crate::spelling_notes(
            "test \"t\", {fakes: [:valkey], allow: %i[process network], kind: :integration}\n  assert true\nend\n",
        )
        .expect("parses");
        assert!(notes
            .iter()
            .any(|n| n.spelling == crate::Spelling::TestDeclaration));
        let plain = first("test \"t\"\n  assert true\nend\n");
        assert!(test_parts(&plain).expect("a test").meta.is_none());
    }

    #[test]
    fn a_kind_outside_the_table_an_empty_allow_and_an_unknown_key_are_refused() {
        for (src, says) in [
            (
                "test \"t\", {kind: :smoke}\n  assert true\nend\n",
                "`kind:` is one of",
            ),
            (
                "test \"t\", {allow: []}\n  assert true\nend\n",
                "grants nothing",
            ),
            (
                "test \"t\", {fakes: [:a, :a]}\n  assert true\nend\n",
                "listed twice",
            ),
            (
                "test \"t\", {tags: [:slow]}\n  assert true\nend\n",
                "`tags:` is not one",
            ),
        ] {
            let err = crate::parse_program_tree(src).expect_err(src);
            assert!(err.to_string().contains(says), "{src}: {err}");
        }
    }

    #[test]
    fn a_declared_test_reads_its_controls_and_target() {
        let form = first(
            "test \"t\", {satisfies: %i[nist_ac_6 nist_cm_7], target: parse_token}\n  assert true\nend\n",
        );
        let parts = test_parts(&form).expect("a test");
        let meta = test_meta(parts.meta.expect("meta")).expect("reads");
        let controls: Vec<&str> = meta.satisfies.iter().map(|(c, _)| *c).collect();
        assert_eq!(controls, ["nist_ac_6", "nist_cm_7"]);
        assert_eq!(target_key(&meta), Some("parse_token"));
    }

    fn permutations(items: &[&'static str]) -> Vec<Vec<&'static str>> {
        if items.len() <= 1 {
            return vec![items.to_vec()];
        }
        let mut out = Vec::new();
        for (i, first) in items.iter().enumerate() {
            let mut rest = items.to_vec();
            rest.remove(i);
            for mut tail in permutations(&rest) {
                tail.insert(0, first);
                out.push(tail);
            }
        }
        out
    }

    fn spelled(controls: &[&str], target: Option<&str>, target_first: bool) -> String {
        let list = match controls {
            [one] => format!("[:{one}]"),
            many => format!("%i[{}]", many.join(" ")),
        };
        let entries = match (target, target_first) {
            (Some(t), true) => format!("target: {t}, satisfies: {list}"),
            (Some(t), false) => format!("satisfies: {list}, target: {t}"),
            (None, _) => format!("satisfies: {list}"),
        };
        format!("test \"t\", {{{entries}}}\n  assert true\nend\n")
    }

    /// **Every spelling of one declaration is one tree.** For each set of
    /// one to four controls, every order of the set, both orders of the keys
    /// and with or without a target, the tree is the canonical spelling's,
    /// and B0068's note is recorded exactly when the spelling is not the
    /// canonical one. Exhaustive over 1 + 2 + 6 + 24 orders per class.
    ///
    /// Red run (2026-10-30): dropping the parser's sort made `%i[nist_cm_7
    /// nist_ac_6]` lower to `(list :nist_cm_7 :nist_ac_6)`, a second tree.
    #[test]
    fn every_order_of_a_declaration_lowers_to_the_canonical_tree() {
        let pool = ["nist_ac_6", "nist_cm_7", "nist_sc_7", "nist_si_10"];
        let mut spellings = 0;
        for size in 1..=pool.len() {
            let set = &pool[..size];
            for target in [None, Some("parse_token")] {
                let canonical = spelled(set, target, false);
                let tree = first(&canonical).to_sexp().to_string();
                assert!(crate::spelling_notes(&canonical)
                    .expect("parses")
                    .is_empty());
                for order in permutations(set) {
                    for target_first in [false, true] {
                        let written = spelled(&order, target, target_first);
                        assert_eq!(first(&written).to_sexp().to_string(), tree, "{written}");
                        let noted = crate::spelling_notes(&written)
                            .expect("parses")
                            .iter()
                            .any(|n| n.spelling == crate::Spelling::TestDeclaration);
                        assert_eq!(noted, written != canonical, "{written}");
                        spellings += 1;
                    }
                }
            }
        }
        assert_eq!(spellings, 2 * 2 * (1 + 2 + 6 + 24));
    }

    #[test]
    fn a_four_item_deftest_without_a_meta_head_is_not_a_test() {
        let form = first("deftest(\"t\", 1, 2)\n");
        assert!(test_parts(&form).is_none());
    }
}
