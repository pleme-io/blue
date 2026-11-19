use blue_lang_saturate::{cheapest, equivalent, from_expr, rule, size, to_expr, Limits};
use tatara_lisp::Spanned;

fn tree(src: &str) -> Spanned {
    blue_lang_syntax::parse_program_tree(src)
        .expect("parses")
        .into_iter()
        .next()
        .expect("one form")
}

fn same(a: &Spanned, b: &Spanned) -> bool {
    a.to_sexp() == b.to_sexp()
}

#[test]
fn every_tree_comes_back_from_its_expression_as_it_went_in() {
    for src in [
        "f(1, 2.5, \"a\\nb\", :k, true, false, nil)",
        "f()",
        "[1, [2, []], g(x)]",
        "map((x) -> x * 2, xs)",
        "def h(a, b)\n  a + b\nend",
        "{a: 1, \"b\" => [x, y]}",
    ] {
        let t = tree(src);
        let back = from_expr(&to_expr(&t)).expect("decodes");
        assert!(
            same(&t, &back),
            "{src}: {:?} came back as {:?}",
            t.to_sexp(),
            back.to_sexp()
        );
    }
}

#[test]
fn a_rule_proves_two_forms_equal_and_saturation_says_when_it_cannot() {
    let rules = vec![rule("double-reverse", "(reverse (reverse ?x))", "?x").expect("rule")];
    let limits = Limits::default();
    assert_eq!(
        equivalent(&tree("reverse(reverse(xs))"), &tree("xs"), &rules, limits),
        Some(true)
    );
    assert_eq!(
        equivalent(&tree("reverse(xs)"), &tree("xs"), &rules, limits),
        Some(false)
    );
}

#[test]
fn the_cheapest_form_comes_back_and_a_form_with_nothing_cheaper_stays_as_written() {
    let rules = vec![rule("double-reverse", "(reverse (reverse ?x))", "?x").expect("rule")];
    let price = |_: &str, children: &[f64]| 1.0 + children.iter().sum::<f64>();
    let (out, before, after) = cheapest(
        &tree("length(reverse(reverse(xs)))"),
        &rules,
        Limits::default(),
        price,
    );
    assert!(same(&out, &tree("length(xs)")), "{:?}", out.to_sexp());
    assert!(after < before);
    let t = tree("length(xs)");
    let (kept, b, a) = cheapest(&t, &rules, Limits::default(), price);
    assert!(same(&kept, &t));
    assert_eq!(a, b);
    assert_eq!(size(&t), 2);
}
