use blue_lang_runtime::pipeline::run;

fn shown(src: &str) -> String {
    let out = run(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
    blue_lang_runtime::literal::render_value(&out.value)
}

fn failure(src: &str) -> String {
    run(src).map(|_| ()).expect_err(src).to_string()
}

const PAIR: &str = "def f(a, b?)\n  [a, b]\nend\n";
const TRIPLE: &str = "def f(a, b?, c?)\n  [a, b, c]\nend\n";

#[test]
fn an_omitted_optional_is_nil() {
    assert_eq!(shown(&format!("{PAIR}f(1)")), "[1, nil]");
    assert_eq!(shown(&format!("{TRIPLE}f(1)")), "[1, nil, nil]");
}

#[test]
fn a_given_optional_is_bound_in_order() {
    assert_eq!(shown(&format!("{PAIR}f(1, 2)")), "[1, 2]");
    assert_eq!(shown(&format!("{TRIPLE}f(1, 2)")), "[1, 2, nil]");
    assert_eq!(shown(&format!("{TRIPLE}f(1, 2, 3)")), "[1, 2, 3]");
}

#[test]
fn an_explicit_nil_and_an_omitted_optional_are_the_same_call() {
    assert_eq!(
        shown(&format!("{PAIR}[f(1, nil), f(1)]")),
        "[[1, nil], [1, nil]]"
    );
}

#[test]
fn a_false_or_empty_optional_is_kept_as_given() {
    assert_eq!(shown(&format!("{PAIR}f(1, false)")), "[1, false]");
    assert_eq!(shown(&format!("{PAIR}f(1, [])")), "[1, []]");
    assert_eq!(shown(&format!("{PAIR}f(1, {{}})")), "[1, {}]");
}

#[test]
fn too_many_arguments_raise_with_the_range_the_def_takes() {
    let e = failure(&format!("{PAIR}f(1, 2, 3)"));
    assert!(e.contains("takes 1 to 2 arguments, got 3"), "{e}");
    let e = failure(&format!("{TRIPLE}f(1, 2, 3, 4, 5)"));
    assert!(e.contains("takes 1 to 3 arguments, got 5"), "{e}");
}

#[test]
fn too_few_arguments_still_raise() {
    assert!(run(&format!("{PAIR}f()")).is_err());
    assert!(run(&format!("{TRIPLE}f()")).is_err());
}

#[test]
fn a_def_of_only_optionals_takes_none_or_all() {
    let src = "def f(a?, b?)\n  [a, b]\nend\n";
    assert_eq!(shown(&format!("{src}f()")), "[nil, nil]");
    assert_eq!(shown(&format!("{src}f(1)")), "[1, nil]");
    assert_eq!(shown(&format!("{src}f(1, 2)")), "[1, 2]");
    let e = failure(&format!("{src}f(1, 2, 3)"));
    assert!(e.contains("takes 0 to 2 arguments, got 3"), "{e}");
}

#[test]
fn an_annotated_optional_runs_as_the_plain_one_does() {
    let src = "def g(a: Int, b?: Int) -> Int\n  a + (b or 10)\nend\n";
    assert_eq!(shown(&format!("{src}[g(1), g(1, 5)]")), "[11, 6]");
}

#[test]
fn an_optional_can_default_in_the_body_and_recurse() {
    let src = "def count(n, acc?)\n  total = acc or 0\n  if n == 0\n    total\n  else\n    count(n - 1, total + n)\n  end\nend\n";
    assert_eq!(shown(&format!("{src}count(4)")), "10");
}

#[test]
fn an_optional_def_is_a_first_class_value() {
    let src = "def f(a, b?)\n  [a, b]\nend\nmap(f, [1, 2])";
    assert_eq!(shown(src), "[[1, nil], [2, nil]]");
}

#[test]
fn optionals_close_over_per_call_not_across_calls() {
    let src = "def f(a, b?)\n  () -> [a, b]\nend\ng = f(1, 2)\nh = f(3)\n[g(), h()]";
    assert_eq!(shown(src), "[[1, 2], [3, nil]]");
}
