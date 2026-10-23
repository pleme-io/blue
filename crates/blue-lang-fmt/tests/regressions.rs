use blue_lang_fmt::{comment_count, format_source, format_source_lossless, FormatError};
use blue_lang_syntax::{comments, parse_program, INFIX, SURFACE_KEYWORDS};

mod common;

fn texts(src: &str) -> Vec<String> {
    comments(src)
        .into_iter()
        .map(|c| c.text.trim_end().to_string())
        .collect()
}

fn holds_every_law(class: &str, src: &str) -> String {
    let out = format_source_lossless(src).unwrap_or_else(|e| panic!("[{class}] {src:?}: {e}"));
    assert_eq!(
        parse_program(&out).unwrap_or_else(|e| panic!("[{class}] {src:?} -> {out:?}: {e}")),
        parse_program(src).expect("the source parses"),
        "[{class}] formatting changed the tree of {src:?}\n--- output\n{out}"
    );
    assert_eq!(
        format_source_lossless(&out).as_deref().ok(),
        Some(out.as_str()),
        "[{class}] not idempotent: {src:?}\n--- output\n{out}"
    );
    assert_eq!(
        texts(&out),
        texts(src),
        "[{class}] comments changed: {src:?}\n--- output\n{out}"
    );
    assert_eq!(comment_count(&out), comment_count(src), "[{class}] {src:?}");
    for line in out.lines() {
        assert!(
            line.chars().count() <= common::WIDTH || common::lawful_overflow(line),
            "[{class}] line past the width in the output of {src:?}\n{line}"
        );
    }
    out
}

const FIXED: &[(&str, &str, &str)] = &[
    (
        "inline-lambda-drops-comments",
        "fn(x) # c\n  x\nend",
        "fn(x) # c\n  x\nend\n",
    ),
    (
        "inline-lambda-drops-comments",
        "fn(x)\n  # c\n  x\nend",
        "fn(x)\n  # c\n  x\nend\n",
    ),
    (
        "inline-lambda-drops-comments",
        "fn(x)\n  x # c\nend",
        "fn(x)\n  x # c\nend\n",
    ),
    (
        "inline-lambda-drops-comments",
        "fn(x)\n  x\n  # tail\nend",
        "fn(x)\n  x\n  # tail\nend\n",
    ),
    (
        "inline-lambda-drops-comments",
        "f(fn(x) # c\n  x\nend)",
        "f(\n  fn(x) # c\n    x\n  end\n)\n",
    ),
    (
        "inline-lambda-drops-comments",
        "f(a, fn(x)\n  # in\n  x\nend, b)",
        "f(\n  a,\n  fn(x)\n    # in\n    x\n  end,\n  b\n)\n",
    ),
    (
        "inline-lambda-drops-comments",
        "m = {a: fn(x)\n  # c\n  x\nend}",
        "m = {\n  a: fn(x)\n    # c\n    x\n  end\n}\n",
    ),
    (
        "arrow-lambda-comment-dropped",
        "(x) ->\n  # c\n  x + 1",
        "fn(x)\n  # c\n  x + 1\nend\n",
    ),
    (
        "arrow-lambda-comment-dropped",
        "f((x) ->\n  # in\n  x\n)",
        "f(\n  fn(x)\n    # in\n    x\n  end\n)\n",
    ),
    (
        "rescue-modifier-block-operand-drops-comments",
        "a rescue (if c\n  # n\n  1\nend)",
        "begin\n  a\nrescue _\n  if c\n    # n\n    1\n  end\nend\n",
    ),
    (
        "rescue-modifier-block-operand-drops-comments",
        "a rescue (def f()\n  1 # n\nend)",
        "begin\n  a\nrescue _\n  def f()\n    1 # n\n  end\nend\n",
    ),
    (
        "rescue-head-comment",
        "x = f(\n  1\n  # c\n) rescue 2\n",
        "x = begin\n  f(\n    1\n    # c\n  )\nrescue _\n  2\nend\n",
    ),
    (
        "rescue-head-comment",
        "x = [1 # c\n] rescue 2",
        "x = begin\n  [\n    1 # c\n  ]\nrescue _\n  2\nend\n",
    ),
    (
        "rescue-handler-comment-refused",
        "x = f(1) rescue\n  # c\n  2\n",
        "x = f(1) rescue\n  # c\n  2\n",
    ),
    (
        "rescue-handler-comment-refused",
        "x = a rescue # t\n  b",
        "x = a rescue # t\n  b\n",
    ),
    (
        "lambda-before-rescue-modifier",
        "(fn() a end) rescue (a)",
        "(() -> a) rescue a\n",
    ),
    (
        "lambda-before-rescue-modifier",
        "x = (fn(x) x end) rescue 1",
        "x = ((x) -> x) rescue 1\n",
    ),
    (
        "lambda-before-rescue-modifier",
        "(() -> 1) rescue z",
        "(() -> 1) rescue z\n",
    ),
    (
        "lambda-before-rescue-modifier",
        "(assert a) rescue z",
        "(assert a) rescue z\n",
    ),
    (
        "lambda-before-rescue-modifier",
        "(assert a == b) rescue z",
        "(assert a == b) rescue z\n",
    ),
    (
        "lambda-before-rescue-modifier",
        "(assert a |> f) rescue z",
        "(assert f(a)) rescue z\n",
    ),
    (
        "lambda-before-rescue-modifier",
        "a rescue (fn(x) x end)",
        "a rescue ((x) -> x)\n",
    ),
    (
        "pipe-into-block-form",
        "xs |> begin\n  a\nrescue e\n  b\nend",
        "xs |> (begin\n  a\nrescue e\n  b\nend)\n",
    ),
    (
        "pipe-into-block-form",
        "z |> (a rescue b)",
        "z |> (a rescue b)\n",
    ),
    (
        "pipe-into-block-form",
        "xs |> fn(x) x end",
        "xs |> ((x) -> x)\n",
    ),
    (
        "pipe-into-block-form",
        "xs |> def f(a) a end",
        "xs |> (def f(a)\n  a\nend)\n",
    ),
    (
        "pipe-into-block-form",
        "xs |> test \"t\" assert 1 end",
        "xs |> (test \"t\"\n  assert 1\nend)\n",
    ),
    (
        "pipe-into-block-form",
        "xs |> quote a end",
        "xs |> (quote\n  a\nend)\n",
    ),
    (
        "pipe-into-block-form",
        "xs |> defmacro m(a) quote a end end",
        "xs |> (defmacro m(a)\n  quote\n    a\n  end\nend)\n",
    ),
    (
        "pipe-into-block-form",
        "xs |> def f(a: Int) -> Int a end",
        "xs |> (def f(a: Int) -> Int\n  a\nend)\n",
    ),
    ("pipe-into-operator", "z |> (a % b)", "z |> (a % b)\n"),
    ("pipe-into-operator", "z |> (a == b)", "z |> (a == b)\n"),
    ("pipe-into-operator", "z |> (not a)", "z |> (not a)\n"),
    (
        "typed-def-type-application-arity",
        "def a(x: Map(Str, Int))\n  x\nend",
        "def a(x: Map(Str, Int))\n  x\nend\n",
    ),
    (
        "typed-def-type-application-arity",
        "def a(x) -> Map(Str, Int)\n  x\nend",
        "def a(x) -> Map(Str, Int)\n  x\nend\n",
    ),
    (
        "typed-def-type-application-arity",
        "def a(x: List())\n  x\nend",
        "def a(x: List())\n  x\nend\n",
    ),
    (
        "typed-def-type-application-arity",
        "def a(x) -> List(Int, Str)\n  x\nend",
        "def a(x) -> List(Int, Str)\n  x\nend\n",
    ),
    (
        "typed-def-type-application-arity",
        "def a(x: List(List(Int)))\n  x\nend",
        "def a(x: List(List(Int)))\n  x\nend\n",
    ),
    ("splat-before-unary-minus", "f(*(-a))", "f(*(-a))\n"),
    ("splat-before-unary-minus", "f(*(-1))", "f(*(-1))\n"),
    (
        "splat-before-unary-minus",
        "f(*(-(a + b)))",
        "f(*(-(a + b)))\n",
    ),
    (
        "all-dyn-typed-def-prints-as-untyped",
        "def a(a: dyn) -> dyn\n  a\nend",
        "def a(a) -> dyn\n  a\nend\n",
    ),
    (
        "all-dyn-typed-def-prints-as-untyped",
        "def a(a: dyn)\n  a\nend",
        "def a(a) -> dyn\n  a\nend\n",
    ),
    (
        "all-dyn-typed-def-prints-as-untyped",
        "def a(a) -> dyn\n  a\nend",
        "def a(a) -> dyn\n  a\nend\n",
    ),
    (
        "all-dyn-typed-def-prints-as-untyped",
        "def a(a: Int, b) -> dyn\n  a\nend",
        "def a(a: Int, b)\n  a\nend\n",
    ),
    (
        "brace-in-string-inside-interpolation",
        "\"a#{\"{\" |> \"}\"}b\"",
        "\"a#{\"}\"(\"{\")}b\"\n",
    ),
    (
        "brace-in-string-inside-interpolation",
        "\"a#{f(\"}\")}b\"",
        "\"a#{f(\"}\")}b\"\n",
    ),
    (
        "pipe-into-splat-call",
        "a::a |> and(a, *a)",
        "a::a |> (and(a, *a))\n",
    ),
    (
        "pipe-into-splat-call",
        "a |> and(a, *a)",
        "a |> (and(a, *a))\n",
    ),
    ("splat-before-unary-minus", "f(1, *xs)", "f(1, *xs)\n"),
    (
        "splat-call-of-a-reserved-head",
        "not(a, *b)",
        "not(a, *b)\n",
    ),
    ("splat-call-of-a-reserved-head", "not(*b)", "not(*b)\n"),
    (
        "splat-call-of-a-reserved-head",
        "and(a, *b)",
        "and(a, *b)\n",
    ),
    ("splat-call-of-a-reserved-head", "or(a, *b)", "or(a, *b)\n"),
    (
        "splat-call-of-a-reserved-head",
        "begin(a, *b)",
        "begin(a, *b)\n",
    ),
    (
        "splat-call-of-a-reserved-head",
        "a = if not(a, *a)\na\nend",
        "a = if not(a, *a)\n  a\nend\n",
    ),
];

#[test]
fn each_fixed_class_prints_its_pinned_output_and_holds_every_law() {
    for (class, src, want) in FIXED {
        let out = holds_every_law(class, src);
        assert_eq!(&out, want, "[{class}] {src:?}");
    }
}

#[test]
fn the_tree_door_agrees_with_the_lossless_door_on_every_comment_free_row() {
    for (class, src, _) in FIXED {
        if comment_count(src) > 0 {
            continue;
        }
        assert_eq!(
            format_source(src).as_deref().ok(),
            format_source_lossless(src).as_deref().ok(),
            "[{class}] {src:?}"
        );
    }
}

const WORDS_THE_PARSER_REFUSES: &[(&str, &str)] = &[
    (
        "typed-def-nonname-return-type",
        "def a(x) -> not a\n  x\nend",
    ),
    ("typed-def-nonname-return-type", "def a(x) -> if\n  x\nend"),
    ("typed-def-nonname-return-type", "def def a(x)\n  x\nend"),
    ("typed-def-nonname-return-type", "def end()\n  1\nend"),
    (
        "typed-def-nonname-return-type",
        "defmacro defmacro a(x)\n  quote\n    x\n  end\nend",
    ),
    ("typed-def-nonname-return-type", "def f(end)\n  1\nend"),
    ("typed-def-nonname-return-type", "def f(a: not)\n  1\nend"),
    (
        "typed-def-nonname-return-type",
        "def f(a: List(1 + 2))\n  1\nend",
    ),
    (
        "typed-def-nonname-return-type",
        "def f(a: List(end))\n  1\nend",
    ),
];

#[test]
fn a_word_no_source_can_write_back_is_refused_at_the_parser() {
    for (class, src) in WORDS_THE_PARSER_REFUSES {
        assert!(
            parse_program(src).is_err(),
            "[{class}] the parser accepted {src:?}, a tree the formatter cannot spell"
        );
    }
}

#[test]
fn a_name_that_is_not_reserved_still_parses_where_a_reserved_one_is_refused() {
    for src in [
        "def then(model, stages)\n  model\nend",
        "def f(a: Int, b: Map(Str, List(Int))) -> Unit()\n  a\nend",
    ] {
        parse_program(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
    }
}

const HIDDEN: &[(&str, &str, usize)] = &[
    (
        "interpolation-comment-after-a-nested-string",
        "\"#{\"a\"#}\"",
        1,
    ),
    ("interpolation-comment-dropped", "\"#{a # n\n}\"", 1),
    ("interpolation-comment-dropped", "x = \"a#{b # c\n}\"", 1),
    (
        "interpolation-comment-dropped",
        "x = \"a#{f(\n 1\n # c\n)}\"\n",
        1,
    ),
    (
        "interpolation-comment-dropped",
        "\"a#{\"b#{c # d\n}\"}\"",
        1,
    ),
    (
        "interpolation-comment-dropped",
        "\"#{a # x\n}#{b # y\n}\"",
        2,
    ),
];

#[test]
fn a_comment_inside_interpolated_code_is_counted_and_refused_never_dropped() {
    for (class, src, n) in HIDDEN {
        assert_eq!(comment_count(src), *n, "[{class}] {src:?} is counted");
        match format_source_lossless(src) {
            Err(FormatError::UnplaceableComments { count, .. }) => {
                assert_eq!(count, *n, "[{class}] {src:?}");
            }
            other => panic!("[{class}] {src:?} must be refused, got {other:?}"),
        }
    }
}

#[test]
fn a_hash_in_a_string_or_a_plain_interpolation_is_not_a_hidden_comment() {
    for src in ["\"a#{b}\"", "\"# not a comment #{b}\"", "x = \"#{f(1)}#\""] {
        assert_eq!(comment_count(src), 0, "{src:?}");
        assert!(format_source_lossless(src).is_ok(), "{src:?}");
    }
}

#[test]
fn the_lossless_door_never_returns_text_with_fewer_comments() {
    for (class, src, _) in FIXED {
        if let Ok(out) = format_source_lossless(src) {
            assert_eq!(texts(&out), texts(src), "[{class}] {src:?}");
        }
    }
}

const GREEDY_OPERANDS: &[&str] = &[
    "fn(x) x end",
    "fn() a end",
    "(x) -> x",
    "assert a",
    "assert a == b",
    "not a",
    "-a",
    "-1",
    "!a",
    "a rescue b",
    "a |> f",
    "a |> (b != c)",
    "if c a else b end",
    "unless c a end",
    "case x when 1 a else b end",
    "begin a rescue e b end",
    "begin a ensure b end",
    "def f(a) a end",
    "def f(a: Int) -> Int a end",
    "defmacro m(a) quote a end end",
    "quote a end",
    "unquote(a)",
    "unquote_splice(a)",
    "test \"t\" assert 1 end",
    "a + b",
    "a && b",
    "a == b",
    "x = 1",
    "\"s#{a}\"",
    "{a: 1}",
    "[a]",
    "a.b",
    "a.b(1)",
];

fn contexts() -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for i in INFIX {
        out.push(format!("({{}}) {} z", i.op));
        out.push(format!("z {} ({{}})", i.op));
    }
    for t in [
        "({}) rescue z",
        "z rescue ({})",
        "({}) |> f",
        "z |> ({})",
        "z |> f(({}))",
        "({}).m",
        "({}).m(1)",
        "({})(1)",
        "(({}).m)(1)",
        "(({}).m.n)(1)",
        "(({}).m(1).n)(1)",
        "({}).m.n",
        "({}).m(1).n",
        "f(*({}))",
        "f(1, *({}))",
        "-({})",
        "not ({})",
        "!({})",
        "x = ({})",
        "x = ({}) rescue 1",
        "[({})]",
        "{a: ({})}",
        "{({}) => 1}",
        "f(({}), 1)",
        "\"#{({})}\"",
        "assert ({})",
        "if ({})\n  1\nend",
        "case ({})\nwhen ({})\n  1\nend",
        "def f()\n  ({})\nend",
        "def f()\n  ({}) rescue 1\nend",
        "fn(x)\n  ({})\nend",
        "({}) |> (a rescue b)",
    ] {
        out.push(t.to_string());
    }
    out
}

fn fill(template: &str, operand: &str) -> String {
    template.replace("{}", operand)
}

#[test]
fn every_operand_in_every_position_keeps_its_tree() {
    let mut checked = 0usize;
    let mut failures = Vec::new();
    for ctx in contexts() {
        for operand in GREEDY_OPERANDS {
            let src = fill(&ctx, operand);
            let Ok(before) = parse_program(&src) else {
                continue;
            };
            checked += 1;
            let once = match format_source_lossless(&src) {
                Ok(o) => o,
                Err(e) => {
                    failures.push(format!("{src:?}: refused: {e}"));
                    continue;
                }
            };
            match parse_program(&once) {
                Ok(after) if after == before => {}
                Ok(_) => failures.push(format!("{src:?}: tree changed\n--- output\n{once}")),
                Err(e) => failures.push(format!("{src:?}: output does not parse: {e}\n{once}")),
            }
            match format_source_lossless(&once) {
                Ok(twice) if twice == once => {}
                _ => failures.push(format!("{src:?}: not idempotent\n--- output\n{once}")),
            }
        }
    }
    assert!(checked > 600, "the matrix reached only {checked} programs");
    assert!(
        failures.is_empty(),
        "{} of {checked} failed:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn the_operand_matrix_reaches_every_surface_keyword_and_every_operator() {
    for kw in SURFACE_KEYWORDS {
        assert!(
            GREEDY_OPERANDS.iter().any(|o| o.contains(kw)),
            "surface keyword {kw} has no row in GREEDY_OPERANDS"
        );
    }
    let ctxs = contexts();
    for i in INFIX {
        assert!(
            ctxs.iter().any(|c| c.contains(&format!(") {} z", i.op))),
            "operator {} has no context",
            i.op
        );
    }
}

#[test]
fn the_width_counts_scalar_values_not_terminal_columns() {
    let wide = "😀".repeat(30);
    let src = format!("x = f(\"{wide}\", \"{}\")", "a".repeat(30));
    let out = format_source_lossless(&src).expect("formats");
    assert_eq!(
        out.lines().count(),
        1,
        "60 emoji columns and 30 letters is 60 characters: one line\n{out}"
    );
    let marks = "e\u{301}".repeat(19);
    let src = format!("x = f(\"{marks}\", \"{}\")", "a".repeat(40));
    let out = format_source_lossless(&src).expect("formats");
    assert!(
        out.lines().count() > 1,
        "38 marked letters and 40 letters is 82 characters: it breaks\n{out}"
    );
}

#[test]
fn a_leading_byte_order_mark_is_a_signature_and_one_inside_the_text_is_refused() {
    let out = holds_every_law("bom-before-comment", "\u{feff}# c\nx = 1\n");
    assert_eq!(out, "# c\nx = 1\n");
    let out = holds_every_law("bom-before-comment", "\u{feff}x = 1 # c\n");
    assert_eq!(out, "x = 1 # c\n");
    for src in ["x = 1\n\u{feff}# c\ny = 2\n", "x = \u{feff}1\n"] {
        assert!(parse_program(src).is_err(), "{src:?} parsed");
    }
    assert!(parse_program("x = \"a\u{feff}b\"").is_ok());
}

const LAID_OUT: &[(&str, &str, &str)] = &[
    (
        "if-condition-continuation-same-indent-as-body",
        "def f(aaaaaaaaaaaa, bbbbbbbbbbbbb)\n  if contains(aaaaaaaaaaaa, \"create_items\") and not contains(bbbbbbbbbbbbb, \"read_items\")\n    1\n  else\n    2\n  end\nend\n",
        "def f(aaaaaaaaaaaa, bbbbbbbbbbbbb)\n  if contains(aaaaaaaaaaaa, \"create_items\") and\n      not contains(bbbbbbbbbbbbb, \"read_items\")\n    1\n  else\n    2\n  end\nend\n",
    ),
    (
        "if-condition-continuation-same-indent-as-body",
        "if aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa == bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n  1\nelsif cccccccccccccccccccccccccccccccccccccc && dddddddddddddddddddddddddddddddddddddddddd\n  2\nend\n",
        "if aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ==\n    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n  1\nelsif cccccccccccccccccccccccccccccccccccccc and\n    dddddddddddddddddddddddddddddddddddddddddd\n  2\nend\n",
    ),
    (
        "infix-orphan-rhs-after-broken-lhs",
        "def f(a)\n  x = contains(map(problem_kind, problems(:base, push(example_base, first(row)))), nth(1, row)) == false\nend\n",
        "def f(a)\n  x = contains(\n    map(problem_kind, problems(:base, push(example_base, first(row)))),\n    nth(1, row)\n  ) == false\nend\n",
    ),
    (
        "infix-orphan-rhs-after-broken-lhs",
        "def f(a)\n  assert count_where(aaaaaaaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbbbbbb) + size(cccccccccccccccccccccc, ddddddddddddddddd) == 4\nend\n",
        "def f(a)\n  assert count_where(aaaaaaaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbbbbbb) +\n    size(cccccccccccccccccccccc, ddddddddddddddddd) == 4\nend\n",
    ),
    (
        "infix-orphan-rhs-after-broken-lhs",
        "def f(a)\n  w = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa + bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb + cccccccccccc\nend\n",
        "def f(a)\n  w = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa +\n    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb +\n    cccccccccccc\nend\n",
    ),
    (
        "paren-group-hanging-closer",
        "x = not (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa && bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb && c)\n",
        "x = not (\n  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa and\n  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb and\n  c\n)\n",
    ),
    (
        "paren-group-hanging-closer",
        "def f(a)\n  z = 2 * (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa + bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb + cccccccccccc)\nend\n",
        "def f(a)\n  z = 2 *\n    (\n      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa +\n      bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb +\n      cccccccccccc\n    )\nend\n",
    ),
    (
        "paren-group-comment-has-no-line",
        "x = ( # c\n  a and b\n) + a\n",
        "x = ( # c\n  a and b\n) + a\n",
    ),
    (
        "paren-group-comment-has-no-line",
        "x = (a and b # c\n) + a\n",
        "x = (\n  a and b # c\n) + a\n",
    ),
    (
        "paren-group-comment-has-no-line",
        "x = (\n  a and b\n  # last\n) + a\n",
        "x = (\n  a and b\n  # last\n) + a\n",
    ),
    (
        "paren-group-hanging-closer",
        "y = !(a && # c\n  b)\n",
        "y = not (\n  a and # c\n  b\n)\n",
    ),
];

#[test]
fn each_laid_out_class_prints_its_pinned_layout_and_holds_every_law() {
    for (class, src, want) in LAID_OUT {
        let out = holds_every_law(class, src);
        assert_eq!(&out, want, "[{class}] {src:?}");
    }
}

#[test]
fn a_short_chain_and_a_short_paren_group_stay_on_one_line() {
    for src in [
        "x = a + b * c\n",
        "x = 2 * (a + b)\n",
        "if a == b\n  1\nend\n",
    ] {
        assert_eq!(holds_every_law("flat-chain", src), src);
    }
}
