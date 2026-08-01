//! The two formatter laws, property-tested over a corpus.
//!
//! An idempotence test ALONE is satisfied by a formatter that deletes the
//! whole file — which is how `caixa-fmt` shipped comment loss its proptest
//! structurally could not see, because it compared trees that had already
//! dropped trivia. So the load-bearing law here is the second one:
//! formatting must not change what the program MEANS, checked by
//! re-parsing and comparing trees.

use blue_lang_fmt::format_source;
use blue_lang_syntax::parse_program;

/// Every construct the surface currently supports. Each entry is a
/// separate law check, so a failure names the construct.
const CORPUS: &[&str] = &[
    // Tests and assertions.
    "test \"adds\"\n  assert 1 + 1 == 2\nend",
    "test \"two asserts\"\n  assert true\n  assert 1 < 2\nend",
    // Macros and the quasiquote family. Absent until `defmacro` shipped
    // rendering as `defmacro(double, x(), ...)` — text that does not re-parse.
    "defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend",
    "defmacro nullary()\n  quote\n    1\n  end\nend",
    "defmacro two(a, b)\n  quote\n    unquote(a) + unquote(b)\n  end\nend",
    "defmacro splat(xs)\n  quote\n    f(unquote_splice(xs))\n  end\nend",
    // Annotated defs. The corpus held NONE, which is exactly why an
    // annotated def printed as a method send and did not re-parse: the three
    // laws below are only as strong as what they are run over.
    "def add(a: Int, b: Int) -> Int\n  a + b\nend",
    "def id(x: Int)\n  x\nend",
    "def ret(x) -> Str\n  x\nend",
    "def mixed(a: Int, b, c: Str) -> Int\n  a\nend",
    "def nested(x: Int) -> Int\n  def inner(y: Int) -> Int\n    y\n  end\nend",
    "def ctor(xs: List(Int)) -> Int\n  1\nend",
    "1",
    "1.5",
    "true",
    "false",
    "nil",
    ":ok",
    r#""hi""#,
    r#""a\nb\t\"q\"""#,
    "x",
    "1 + 2",
    "1 + 2 * 3",
    "(1 + 2) * 3",
    "1 - 2 - 3",
    "1 - (2 - 3)",
    "a < b",
    "a == b",
    "a && b || c",
    "a || b && c",
    "-x",
    "!x",
    "-(a + b)",
    "f()",
    "f(1)",
    "f(1, 2, 3)",
    "user.name",
    "user.greet(1)",
    "a.b.c",
    "a.b(1).c",
    "[]",
    "[1, 2, 3]",
    "[1 + 2, f(3)]",
    "{}",
    "{a: 1}",
    "{a: 1, b: 2}",
    r#"{"k" => 1}"#,
    r#"{a: 1, "k" => 2}"#,
    "x |> f",
    "x |> f(1)",
    "x |> f |> g",
    "1 + 2 |> f",
    "if a\n  1\nend",
    "if a\n  1\nelse\n  2\nend",
    "unless a\n  1\nend",
    "if a\n  1\n  2\nend",
    "def f()\n  1\nend",
    "def add(a, b)\n  a + b\nend",
    "def f(n)\n  if n\n    1\n  else\n    2\n  end\nend",
    "def f(n)\n  n |> g |> h\nend",
    // multi-form programs
    "def f()\n  1\nend\nf()",
    "1\n2\n3",
    // a long call that must break
    "some_function(aaaaaaaaaa, bbbbbbbbbb, cccccccccc, dddddddddd, eeeeeeeeee, ffffffffff, gggggggggg)",
];

/// LAW 1 — idempotence. `fmt(fmt(s)) == fmt(s)`.
#[test]
fn formatting_is_idempotent() {
    for src in CORPUS {
        let once = format_source(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        let twice = format_source(&once)
            .unwrap_or_else(|e| panic!("re-formatting {once:?} failed: {e}"));
        assert_eq!(
            once, twice,
            "not idempotent for {src:?}\n  once:  {once:?}\n  twice: {twice:?}"
        );
    }
}

/// LAW 2 — semantic round-trip. `parse(fmt(s)) == parse(s)`.
///
/// This is the one that matters: formatting may change bytes, never
/// meaning. Compared as TREES, so whitespace and spelling choices are
/// permitted and a changed program is not.
#[test]
fn formatting_preserves_the_tree() {
    for src in CORPUS {
        let before = parse_program(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        let formatted = format_source(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        let after = parse_program(&formatted)
            .unwrap_or_else(|e| panic!("formatted output of {src:?} does not re-parse:\n{formatted}\n{e}"));
        assert_eq!(
            before, after,
            "formatting changed the tree for {src:?}\n  formatted: {formatted:?}"
        );
    }
}

/// LAW 3 — canonicality. Formatted output is a fixed point reached in ONE
/// step from any spelling of the same tree. Two different spellings that
/// parse identically must format identically, which is the text↔tree
/// bijection §V.16.1's content-addressed identity depends on.
#[test]
fn equal_trees_format_to_equal_text() {
    let pairs: &[(&str, &str)] = &[
        ("{a: 1}", "{:a => 1}"),
        ("1+2", "1 + 2"),
        ("f( 1 , 2 )", "f(1,2)"),
        ("user.name", "user . name"),
        ("[1,2]", "[ 1 , 2 ]"),
        ("if a\n1\nend", "if a\n  1\nend"),
    ];
    for (a, b) in pairs {
        let pa = parse_program(a).expect("parse a");
        let pb = parse_program(b).expect("parse b");
        assert_eq!(pa, pb, "{a:?} and {b:?} do not parse to the same tree");
        assert_eq!(
            format_source(a).expect("fmt a"),
            format_source(b).expect("fmt b"),
            "equal trees formatted differently: {a:?} vs {b:?}"
        );
    }
}

/// ANTI-VACUITY. The laws must be falsifiable: the corpus has to contain
/// inputs that formatting actually CHANGES. If `fmt` were the identity
/// function every law above would pass and prove nothing.
#[test]
fn the_formatter_actually_reformats_something() {
    let changed = CORPUS
        .iter()
        .filter(|src| {
            format_source(src).map(|out| out.trim() != src.trim()).unwrap_or(false)
        })
        .count();
    assert!(
        changed >= 5,
        "only {changed} corpus entries were reformatted — the laws may be \
         passing because the formatter is near-identity"
    );
}

/// ANTI-VACUITY. The corpus must be non-trivial and fully parseable; a
/// silently-skipped entry would weaken every law above.
#[test]
fn every_corpus_entry_parses() {
    assert!(CORPUS.len() >= 40, "corpus too small to be meaningful");
    for src in CORPUS {
        parse_program(src).unwrap_or_else(|e| panic!("corpus entry {src:?} does not parse: {e}"));
    }
}

/// There is no configuration surface. This is a compile-time fact — the
/// crate exposes no config type — and this test records the intent so a
/// future addition has to delete it deliberately.
#[test]
fn width_is_a_constant_not_a_parameter() {
    assert_eq!(blue_lang_fmt::WIDTH, 90);
}

/// **The inverse lowering must be a function.** The formatter maps a callee
/// back to a surface spelling, so two operators sharing a callee would make
/// that map ambiguous and silently pick whichever came first — a round-trip
/// that changes the program's text without changing its tree.
///
/// This is the invariant that lets the formatter read the parser's table
/// instead of keeping its own copy.
#[test]
fn callees_are_unique() {
    let mut seen: Vec<&str> = Vec::new();
    let mut dupes: Vec<&str> = Vec::new();
    for i in blue_lang_syntax::INFIX {
        if seen.contains(&i.callee) {
            dupes.push(i.callee);
        }
        seen.push(i.callee);
    }
    assert!(
        dupes.is_empty(),
        "these callees are claimed by more than one operator, so formatting them is ambiguous: {dupes:?}"
    );
}

/// Every operator in the parser's table round-trips through the formatter.
///
/// The generic round-trip law only covers the fixed corpus; this one is
/// driven by the table itself, so a NEW operator is covered the moment it is
/// declared rather than when someone remembers to add a corpus entry.
#[test]
fn every_operator_in_the_table_round_trips() {
    let mut broken: Vec<(String, String)> = Vec::new();
    for i in blue_lang_syntax::INFIX {
        let src = format!("a {} b", i.op);
        let before = match blue_lang_syntax::parse_program(&src) {
            Ok(f) => f,
            Err(e) => {
                broken.push((i.op.to_string(), format!("parse: {e}")));
                continue;
            }
        };
        let text = blue_lang_fmt::format_source(&src).expect("format");
        match blue_lang_syntax::parse_program(&text) {
            Ok(after) if after == before => {}
            Ok(after) => broken.push((
                i.op.to_string(),
                format!("tree changed: {before:?} -> {after:?} via {text:?}"),
            )),
            Err(e) => broken.push((i.op.to_string(), format!("{text:?} does not re-parse: {e}"))),
        }
    }
    assert!(broken.is_empty(), "operators that do not round-trip: {broken:#?}");
}

/// **Every surface keyword must appear in the corpus.**
///
/// This is the structural answer to a failure that happened three times: a form
/// was added to the parser, the formatter was not extended, and all three
/// formatting laws passed anyway — because a law cannot notice a case nobody
/// wrote down. The annotated `def` rendered as a method send; `defmacro`
/// rendered as `defmacro(double, x(), …)`, which does not re-parse at all.
///
/// Making the omission itself the failure means adding a keyword to
/// `SURFACE_KEYWORDS` forces the corpus entry, which then drags the new form
/// through idempotence, tree-preservation and canonicality automatically.
#[test]
fn every_surface_keyword_appears_in_the_corpus() {
    let missing: Vec<&str> = blue_lang_syntax::SURFACE_KEYWORDS
        .iter()
        .copied()
        .filter(|kw| !CORPUS.iter().any(|src| src.contains(*kw)))
        .collect();
    assert!(
        missing.is_empty(),
        "these surface keywords have no corpus entry, so no formatting law covers them: {missing:?}"
    );
}
