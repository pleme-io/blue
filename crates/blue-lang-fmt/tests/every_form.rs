//! The round-trip law over every tree the parser can build — not only the
//! trees the snippet corpus happens to spell.
//!
//! `laws.rs`'s generator writes calls with random names, so it could never
//! name `define`, `lambda`, `deftest`, `not` or `concat`: the heads the
//! printer dispatches on. And the printer dispatches on the head alone. So
//! `q = define(zz, 5)` — a plain call whose tree is exactly a binding's —
//! printed as `q = zz = 5`, which does not parse, and every law stayed green
//! (found by the 2026-09-29 audit, `probe/q.b`). A binding had only ever been
//! written at statement position, so nothing had asked the printer to render
//! one anywhere else.
//!
//! Two things make this generator reach what that one could not:
//!
//! 1. **Call names are drawn from what the parser LOWERS TO**, read off the
//!    parser's own output over a seed corpus, plus the infix table's callees.
//!    A new lowering enters the vocabulary by being emitted, with no list here
//!    to forget to update. Only names a call can spell are kept — one
//!    identifier token, not reserved — since those are the heads a program can
//!    reach both ways.
//! 2. **Every surface form is generated in every position**: blocks as call
//!    arguments and operands, unary operators nested, assertions inside
//!    chains, strings holding the characters the lexer treats specially.
//!
//! Input that does not parse is discarded, so the law is exactly: for every
//! source the parser accepts, the formatter's output parses back to the same
//! tree, and formatting it again changes nothing.

use blue_lang_fmt::{format_forms, format_source, format_source_lossless};
use blue_lang_syntax::parse_program;
use common::gen::program;
use proptest::prelude::*;
use proptest::test_runner::{contextualize_config, TestError, TestRunner};

mod common;

/// The law, stated once so both properties below check the same thing.
fn round_trips(src: &str) -> Result<(), TestCaseError> {
    let Ok(before) = parse_program(src) else {
        return Err(TestCaseError::reject("not blue"));
    };
    if blue_lang_fmt::comment_count(src) > 0 {
        return Err(TestCaseError::reject("a comment inside interpolated code"));
    }
    let once = format_forms(&before);
    let after = parse_program(&once).map_err(|e| {
        TestCaseError::fail(format!(
            "output does not parse: {e}\n--- source\n{src}\n--- output\n{once}"
        ))
    })?;
    prop_assert_eq!(
        &after,
        &before,
        "tree changed\n--- source\n{}\n--- output\n{}",
        src,
        once
    );
    let twice = format_source(&once).expect("parsed a moment ago");
    prop_assert_eq!(&twice, &once, "not idempotent");
    // The door a person's file goes through renders from the SPANNED tree;
    // it must agree with the tree-only rendering on comment-free source.
    let lossless = format_source_lossless(src)
        .map_err(|e| TestCaseError::fail(format!("lossless refused: {e}\n--- source\n{src}")))?;
    prop_assert_eq!(
        &lossless,
        &once,
        "the two doors disagree\n--- source\n{}",
        src
    );
    Ok(())
}

const FOUND: &[&str] = &[
    "q = define(zz, 5)",
    "f(define(x, 1))",
    "[define(x, 1)]",
    "fn(y) define(x, y) end",
    "define(x, define(y, 1))",
    "(assert a) |> if a\na\nelse\na\nend",
    "(assert a) |> f",
    "(assert a) |> f(1)",
    "(assert a) |> fn(x) x end",
    "(assert a) + b",
    "(assert a) == b",
    "(assert a) and b",
    "(assert a).m(1)",
    "f((assert a))",
    "(not a) |> f",
    "(-a) |> f",
    "{a: a(a, *[:a, :a])}",
    "a = a or begin\na = \"a#{\"}\\n{\"}b\"\nrescue a\na\nend",
    "record p(x, y)",
    "record p(x: Int, y: List(Str), z: geo::point)",
    "record p(\n  x,\n  y: Int\n)",
    "record p(x: dyn)",
    "union u = a(x) | b(y: Int, z: geo::point)",
    "union u =\na(x)\n|b(y)",
    "union u = a(\n  x,\n  y: Int\n) | b(z)",
    "union u = a(x) | b(y, z)\ncase v\nwhen a(x)\n  x\nwhen b(_, [z, *r])\n  r\nend",
    "case v\nwhen {a:, b: [_, *c]}\n  c\nend",
];

/// Every accepted source, formatted, parses back to the same tree.
#[test]
fn every_accepted_program_round_trips() {
    let mut config = contextualize_config(ProptestConfig {
        max_global_rejects: 1 << 16,
        ..common::config(4096)
    });
    config.source_file = Some(file!());
    config.test_name = Some(concat!(
        module_path!(),
        "::every_accepted_program_round_trips"
    ));
    if config.failure_persistence.is_some() {
        for src in FOUND {
            round_trips(src)
                .unwrap_or_else(|e| panic!("found case {src:?} no longer round-trips: {e}"));
        }
    }
    match TestRunner::new(config).run(&program(), |src| round_trips(&src)) {
        Ok(()) => {}
        Err(TestError::Fail(why, src)) => panic!(
            "{why}\nminimal failing input: {src:?}\nonce it is fixed, add that input to FOUND in \
             crates/blue-lang-fmt/tests/every_form.rs so every run replays it first"
        ),
        Err(TestError::Abort(why)) => panic!("{why}"),
    }
}

/// The cases this file was written for, pinned so a regression names itself
/// without waiting for the generator to find it again.
#[test]
fn found_cases_round_trip() {
    for src in FOUND {
        round_trips(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
    }
}

/// A qualified name prints as written, at every depth, and every spelling of
/// `use` prints as its own tree: nothing is rewritten into another.
#[test]
fn qualified_names_and_use_spellings_round_trip() {
    for src in [
        "a::b::c\n",
        "a::b::c::d(x)\n",
        "a::b::if(x)\n",
        "a::b::c.field\n",
        "use(\"a/b\")\n",
        "use(\"a::b\")\n",
        "use(%i[a b])\n",
        "use(%w[a b])\n",
        "use(*%i[a b])\n",
        "use(**%i[a b])\n",
        "use({s: \"a/b\"})\n",
        "use(\"a\", %w[b c])\n",
        "use(\"a\", {b: [:x], c: []})\n",
        "namespace()\n",
    ] {
        assert_eq!(format_source(src).expect(src), src, "{src}");
        round_trips(src).expect(src);
    }
    assert_eq!(format_source("a :: b :: c\n").unwrap(), "a::b::c\n");
}

#[test]
fn a_documented_record_keeps_its_doc_through_the_door_a_file_goes_through() {
    let src = "@doc \"\"\"\np is a place.\n\"\"\"\nrecord p(x)\n";
    assert_eq!(format_source_lossless(src).unwrap(), src);
}

#[test]
fn a_record_inside_an_interpolation_is_refused_at_every_door() {
    for src in [
        "a |> \"a#{record a(a, last: Int)}b\"",
        "\"#{record p(x)}\"",
        "x = \"a#{record p(x)}\"",
        "\"a\\n#{record p(x)}\\n\"",
        "\"a\\n#{record p(x)}b\\n\"",
    ] {
        let err = parse_program(src).expect_err(src);
        assert!(
            err.to_string()
                .contains("`record p` is a declaration of the top level of a file")
                || err
                    .to_string()
                    .contains("`record a` is a declaration of the top level of a file"),
            "{src:?}: {err}"
        );
    }
}

#[test]
fn a_comment_inside_a_record_stays_where_it_is() {
    let src = "record p(\n  # the first\n  x,\n  y: Int # the second\n)\n";
    assert_eq!(format_source_lossless(src).unwrap(), src);
}

#[test]
fn a_short_union_is_one_line_and_a_long_one_one_arm_a_line() {
    let short = "union shape = circle(r: Float) | rect(w: Float, h: Float)\n";
    assert_eq!(format_source_lossless(short).unwrap(), short);
    assert_eq!(
        format_source_lossless("union shape =\n  circle(r: Float)\n  | rect(w: Float, h: Float)\n")
            .unwrap(),
        short
    );
    let long = "union event =\n  opened(path: Str, mode: Sym, flags: List(Sym))\n  | closed(path: Str, code: Int)\n  | failed(path: Str, reason: Str)\n";
    assert_eq!(format_source_lossless(long).unwrap(), long);
    assert_eq!(format_source(long).unwrap(), long);
}

#[test]
fn a_documented_union_keeps_its_doc_and_its_neighbours() {
    let src = "x = 1\n\n@doc \"\"\"\nshape is a circle or a rect.\n\"\"\"\nunion shape = circle(r) | rect(w, h)\n\n# after\ny = rect(1, 2)\n";
    assert_eq!(format_source_lossless(src).unwrap(), src);
    let tree = blue_lang_syntax::parse_program_tree(src).unwrap();
    assert_eq!(
        blue_lang_fmt::format_tree_lossless(src, &tree).unwrap(),
        src
    );
}
