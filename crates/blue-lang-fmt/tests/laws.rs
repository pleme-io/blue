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
    // case/when.
    "case x\nwhen 1\n  \"one\"\nend",
    "case x\nwhen 1\n  \"one\"\nwhen 2\n  \"two\"\nend",
    "case x\nwhen 1\n  \"one\"\nelse\n  \"other\"\nend",
    // String interpolation. The formatter had no arm and printed the lowered
    // `concat(concat("a", x), "")` — correct tree, nothing a person would write.
    "\"value: #{x}\"",
    "\"#{a} and #{b}\"",
    "\"#{a}#{b}\"",
    "\"n=#{1 + 2}\"",
    // A hand-written concat is NOT interpolation and must stay a call.
    "concat(\"a\", \"b\")",
    // Lambdas and bindings.
    "fn(x)\n  x + 1\nend",
    "fn()\n  1\nend",
    "fn(a, b)\n  a + b\nend",
    "x = 5",
    "total = 1 + 2",
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

// ---------------------------------------------------------------------------
// Comment preservation
//
// `blue fmt --write` silently DELETED every comment in a file. A comment is the
// one part of a program a machine cannot reconstruct, so that was data loss on
// a routine operation.
//
// Comments are not in the tree — they carry no meaning, and putting them there
// would break canonicality (two programs differing only in a comment would stop
// formatting identically). They are re-interleaved by POSITION instead.
// ---------------------------------------------------------------------------

use blue_lang_fmt::{format_source_lossless, FormatError};

#[test]
fn a_leading_comment_survives_formatting() {
    let src = "# a note\n1 + 2\n";
    let out = format_source_lossless(src).expect("lossless");
    assert!(out.contains("# a note"), "the comment must survive: {out:?}");
    assert!(out.contains("1 + 2"), "and so must the code: {out:?}");
    assert!(
        out.find("# a note") < out.find("1 + 2"),
        "and stay before it: {out:?}"
    );
}

#[test]
fn a_multi_line_comment_block_survives_in_order() {
    let src = "# first\n# second\n# third\n1 + 2\n";
    let out = format_source_lossless(src).expect("lossless");
    let f = out.find("# first").expect("first");
    let s = out.find("# second").expect("second");
    let t = out.find("# third").expect("third");
    assert!(f < s && s < t, "order must be preserved: {out:?}");
}

/// A comment between two top-level forms attaches to the one that follows.
#[test]
fn a_comment_between_forms_stays_between_them() {
    let src = "1 + 1\n# about the second\n2 + 2\n";
    let out = format_source_lossless(src).expect("lossless");
    let first = out.find("1 + 1").expect("first form");
    let note = out.find("# about the second").expect("comment");
    let second = out.find("2 + 2").expect("second form");
    assert!(
        first < note && note < second,
        "the comment must stay between the forms: {out:?}"
    );
}

/// A trailing comment stays on its own line's end rather than being promoted
/// above the code.
#[test]
fn a_trailing_comment_stays_trailing() {
    let src = "1 + 2 # why\n";
    let out = format_source_lossless(src).expect("lossless");
    let line = out.lines().find(|l| l.contains("1 + 2")).expect("code line");
    assert!(
        line.contains("# why"),
        "the trailing comment must stay on the code line: {line:?}"
    );
}

/// Comments around a `def` — the shape a real file actually has.
#[test]
fn comments_around_a_definition_survive() {
    let src = "# Adds two numbers.\ndef add(a, b)\n  a + b\nend\n\n# And uses it.\nadd(1, 2)\n";
    let out = format_source_lossless(src).expect("lossless");
    assert!(out.contains("# Adds two numbers."), "{out}");
    assert!(out.contains("# And uses it."), "{out}");
    assert!(out.contains("def add(a, b)"), "{out}");
    assert!(
        out.find("# Adds two numbers.") < out.find("def add"),
        "the doc comment must precede the def: {out}"
    );
}

/// **Formatting with comments is idempotent.** Otherwise `fmt` would keep
/// changing a file that already looks right — and `--check` would never settle.
#[test]
fn formatting_with_comments_is_idempotent() {
    for src in [
        "# a\n1 + 2\n",
        "# a\n# b\n\ndef f(x)\n  x\nend\n",
        "1 + 1\n# mid\n2 + 2\n",
        "1 + 2 # trailing\n",
    ] {
        let once = format_source_lossless(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        let twice = format_source_lossless(&once)
            .unwrap_or_else(|e| panic!("second pass on {once:?}: {e}"));
        assert_eq!(once, twice, "not idempotent for {src:?}");
    }
}

/// **And it preserves the tree.** The comment machinery must not disturb the
/// program.
#[test]
fn formatting_with_comments_preserves_the_tree() {
    for src in [
        "# a\n1 + 2\n",
        "# doc\ndef add(a, b)\n  a + b\nend\nadd(1, 2)\n",
        "1 + 1\n# mid\n2 + 2\n",
    ] {
        let before = parse_program(src).expect("parse");
        let out = format_source_lossless(src).expect("format");
        let after = parse_program(&out).expect("re-parse");
        assert_eq!(before, after, "the tree changed for {src:?}\n{out}");
    }
}

/// **No comment is lost, ever** — the property the whole feature exists for.
#[test]
fn no_comment_is_lost() {
    for src in [
        "# a\n1 + 2\n",
        "# a\n# b\n1 + 2\n",
        "1 + 1\n# mid\n2 + 2\n",
        "1 + 2 # trailing\n",
        "# lead\ndef f(x)\n  x\nend\n# tail\n",
    ] {
        let before = blue_lang_fmt::comment_count(src);
        let out = format_source_lossless(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        let after = blue_lang_fmt::comment_count(&out);
        assert_eq!(
            before, after,
            "lost {} comment(s) formatting {src:?}\n{out}",
            before - after
        );
    }
}

/// **A comment inside a form is REFUSED, not dropped.** Those lines have been
/// re-laid out and there is no line left to attach it to. Naming the line is
/// what makes the refusal actionable.
#[test]
fn a_comment_inside_a_form_is_refused_with_its_line() {
    let src = "def f(x)\n  # inside the body\n  x\nend\n";
    let err = format_source_lossless(src).expect_err("must refuse");
    match err {
        FormatError::UnplaceableComments { count, ref lines } => {
            assert_eq!(count, 1);
            assert_eq!(lines, "2", "the line must be named so the author can find it");
        }
        other => panic!("expected UnplaceableComments, got {other}"),
    }
}

/// Anti-vacuity: the refusal is NARROW. A file whose comments are all placeable
/// must format, or the feature would be a blanket refusal wearing a fix's
/// clothes.
#[test]
fn placeable_comments_do_not_trigger_the_refusal() {
    for src in [
        "# a\n1 + 2\n",
        "# a\ndef f(x)\n  x\nend\n",
        "1 + 2 # t\n",
        "# only a comment\n",
    ] {
        assert!(
            format_source_lossless(src).is_ok(),
            "must not refuse {src:?}: {:?}",
            format_source_lossless(src).err().map(|e| e.to_string())
        );
    }
}

/// A `#` inside a string is not a comment, so a file containing one must still
/// format. Counting by scanning text rather than lexing would refuse it.
#[test]
fn a_hash_inside_a_string_is_not_a_comment() {
    let src = "\"not # a comment\"\n";
    assert_eq!(blue_lang_fmt::comment_count(src), 0);
    assert!(format_source_lossless(src).is_ok());
}

/// **A comment block does not grow blank lines.** The first implementation
/// measured the gap from each comment to the FORM's start rather than to
/// whatever came next, so every pair of consecutive comment lines got a blank
/// line between them — a three-line header became six lines, and `--check`
/// could never settle.
#[test]
fn a_comment_block_is_not_padded_with_blank_lines() {
    let src = "# one\n# two\n# three\n1 + 2\n";
    let out = format_source_lossless(src).expect("lossless");
    assert_eq!(
        out, src,
        "a canonical comment block must round-trip byte for byte"
    );
    assert!(
        !out.contains("\n\n#"),
        "no blank line may appear inside the block: {out:?}"
    );
}

/// A blank line the author DID write between a comment and the code is kept —
/// so the fix above did not simply delete all blank lines.
#[test]
fn a_deliberate_blank_line_after_a_comment_is_kept() {
    let src = "# header\n\n1 + 2\n";
    let out = format_source_lossless(src).expect("lossless");
    assert_eq!(out, src, "got {out:?}");
}

/// **A binding renders as `name = value`, not `define(name, value)`.**
///
/// It rendered as the call form, which re-parses to the *same tree* — so all
/// three laws passed while `fmt --write` silently rewrote every binding in
/// blue's own spec files. The third time a green round-trip law has coexisted
/// with output no one would write, after the method-send calls and the
/// unparseable `defmacro`.
///
/// A round-trip law measures the tree. Reading the output is the only thing
/// that measures the output.
#[test]
fn a_binding_renders_as_an_assignment() {
    assert_eq!(format_source("x = 5").expect("fmt").trim(), "x = 5");
    assert_eq!(
        format_source("total = 1 + 2").expect("fmt").trim(),
        "total = 1 + 2"
    );
    assert!(
        !format_source("x = 5").expect("fmt").contains("define("),
        "must not print the lowered call form"
    );
}

/// And a `def` still renders as a `def` — the two share the `define` head, so
/// the new arm must not capture the function form.
#[test]
fn a_def_still_renders_as_a_def() {
    let out = format_source("def f(x)\n  x\nend").expect("fmt");
    assert!(out.contains("def f(x)"), "got {out}");
    assert!(!out.contains(" = "), "a def is not a binding: {out}");
}

/// **Interpolation renders back as interpolation**, not as the lowered
/// `concat` chain it becomes.
#[test]
fn interpolation_renders_as_interpolation() {
    assert_eq!(
        format_source("\"value: #{x}\"").expect("fmt").trim(),
        "\"value: #{x}\""
    );
    assert!(
        !format_source("\"value: #{x}\"").expect("fmt").contains("concat("),
        "must not print the lowered chain"
    );
}

/// And a hand-written `concat` is not interpolation — the shape check must be
/// narrow or every two-argument concat turns into a string literal.
#[test]
fn a_hand_written_concat_stays_a_call() {
    let out = format_source("concat(\"a\", \"b\")").expect("fmt");
    assert!(out.contains("concat("), "got {out}");
}
