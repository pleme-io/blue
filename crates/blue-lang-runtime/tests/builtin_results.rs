use blue_lang_check::{builtin_result, Ty};
use blue_lang_runtime::docs::NAMES;

const PROBES: &[(&str, &[&str])] = &[
    (
        "length",
        &["length([1, 2])", "length(\"ab\")", "length([])"],
    ),
    ("count", &["count([1])", "count(nil)", "count(\"ab\")"]),
    ("to_s", &["to_s(1)", "to_s(nil)", "to_s([1])", "to_s(:a)"]),
    ("upcase", &["upcase(\"a\")", "upcase(:a)"]),
    ("downcase", &["downcase(\"A\")"]),
    ("trim", &["trim(\" a \")"]),
    ("join", &["join([\"a\", 1], \",\")", "join([], \",\")"]),
    (
        "join_lines",
        &["join_lines([\"a\", \"b\"])", "join_lines([])"],
    ),
    ("unlines", &["unlines([\"a\"])", "unlines([])"]),
    ("replace", &["replace(\"ab\", \"a\", \"c\")"]),
    (
        "split",
        &[
            "split(\"a,b,\", \",\")",
            "split(\"ab\", \"\")",
            "split(\"\", \",\")",
        ],
    ),
    ("chars", &["chars(\"ab\")", "chars(\"\")"]),
    ("empty?", &["empty?([])", "empty?(nil)", "empty?(\"a\")"]),
    ("contains?", &["contains?(\"ab\", \"a\")"]),
    ("starts_with?", &["starts_with?(\"ab\", \"a\")"]),
    ("ends_with?", &["ends_with?(\"ab\", \"a\")"]),
    ("member?", &["member?(1, [1, 2])", "member?(3, [1])"]),
    ("even?", &["even?(2)"]),
    ("odd?", &["odd?(2)"]),
    ("zero?", &["zero?(0)", "zero?(0.0)"]),
    ("positive?", &["positive?(1)", "positive?(-1.5)"]),
    ("negative?", &["negative?(1)"]),
    ("string?", &["string?(1)", "string?(\"a\")"]),
    ("number?", &["number?(1)", "number?(nil)"]),
    ("integer?", &["integer?(1.0)"]),
    ("nil?", &["nil.nil?", "1.nil?"]),
    ("some?", &["some?(nil)", "some?(1)"]),
    ("list?", &["list?([])", "list?(nil)"]),
    ("map?", &["map?({a: 1})", "map?(1)"]),
    ("keyword?", &["keyword?(:a)"]),
    ("bool?", &["bool?(true)", "bool?(1)"]),
    ("symbol?", &["symbol?(:a)"]),
];

fn test_of(t: &Ty) -> &'static str {
    match t {
        Ty::Int => "integer?(r)",
        Ty::Str => "string?(r)",
        Ty::Bool => "bool?(r)",
        Ty::List(inner) if **inner == Ty::Str => "list?(r) && r != nil && every?(string?, r)",
        other => panic!("no runtime test for {}", other.name()),
    }
}

#[test]
fn every_declared_builtin_result_is_what_the_builtin_returns() {
    let declared: Vec<(&str, Ty)> = NAMES
        .iter()
        .filter_map(|d| builtin_result(d.name).map(|t| (d.name, t)))
        .collect();
    let probed: Vec<&str> = PROBES.iter().map(|(n, _)| *n).collect();
    let unprobed: Vec<&str> = declared
        .iter()
        .map(|(n, _)| *n)
        .filter(|n| !probed.contains(n))
        .collect();
    assert!(
        unprobed.is_empty(),
        "declared without a probe: {unprobed:?}"
    );
    let undeclared: Vec<&str> = probed
        .iter()
        .copied()
        .filter(|n| !declared.iter().any(|(d, _)| d == n))
        .collect();
    assert!(
        undeclared.is_empty(),
        "probed but not a documented builtin with a declared result: {undeclared:?}"
    );
    let mut wrong = Vec::new();
    for (name, ty) in &declared {
        let calls = PROBES.iter().find(|(n, _)| n == name).expect("probed").1;
        for call in calls {
            let src = format!(
                "r = {call}\nif !({})\n  raise(:wrong_result, to_s(r))\nend\n",
                test_of(ty)
            );
            if let Err(e) = blue_lang_runtime::pipeline::run(&src) {
                wrong.push(format!("{call} is declared {}: {e}", ty.name()));
            }
        }
    }
    assert!(wrong.is_empty(), "{}", wrong.join("\n"));
}
