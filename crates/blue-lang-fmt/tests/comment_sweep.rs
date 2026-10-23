use blue_lang_fmt::{comment_count, format_source, format_source_lossless};
use blue_lang_syntax::{comments, parse_program};
use proptest::prelude::*;

mod common;

use common::gen::{program, SEED};

const SHAPES: &[&str] = &[
    "x = fn(a)\n  a + 1\nend",
    "f(fn(a)\n  a\nend, 2)",
    "y = fn(x)\n  x\nend",
    "y = (x) ->\n  x\n",
    "x = f(\n  1,\n  2\n) rescue 3",
    "x = [\n  1,\n  2\n] rescue g(\n  4\n)",
    "a rescue (if c\n  1\nend)",
    "\"a#{f(\n  1\n)}\"",
    "{\n  a: 1,\n  b: fn(x)\n    x\n  end\n}",
    "m = {k: fn(a) a end, j: [1, 2]}",
    "(fn() a end) rescue (b)",
    "x = f(1, 2) rescue 3",
    "x = [1, 2, 3] rescue g(4)",
    "def f(a)\n  g(a) rescue h(a)\nend",
    "def f(a)\n  g(a)\nrescue :boom\n  1\nrescue e\n  raise(e)\nensure\n  close\nend",
    "xs |> begin\n  a\nrescue e\n  b\nend",
    "z |> (a % b)",
    "def f(a: Map(Str, Int)) -> List(Int, Str)\n  a\nend",
    "f(1, *xs)",
    "case x\nwhen 1\n  a\nelse\n  b\nend",
    "if a\n  1\nelsif b\n  2\nelse\n  3\nend",
    "test \"t\"\n  assert 1 + 1 == 2\nend",
    "a + b * c - d",
    "defmacro m(a)\n  quote\n    unquote(a)\n  end\nend",
    "\"a#{b}c#{d}\"",
    "x = (y) -> y + 1",
    "xs |> map((x) -> x * 2) |> sum",
];

fn texts(src: &str) -> Vec<String> {
    comments(src)
        .into_iter()
        .map(|c| c.text.trim_end().to_string())
        .collect()
}

fn injections(base: &str) -> Vec<String> {
    let lines: Vec<&str> = base.lines().collect();
    let mut out = Vec::new();
    for i in 0..lines.len() {
        let mut trailing = lines
            .clone()
            .iter()
            .map(|l| l.to_string())
            .collect::<Vec<_>>();
        trailing[i].push_str(" # sweep");
        out.push(trailing.join("\n") + "\n");
        let indent: String = lines[i].chars().take_while(|c| *c == ' ').collect();
        let mut own = lines.iter().map(|l| l.to_string()).collect::<Vec<_>>();
        own.insert(i, format!("{indent}# sweep"));
        out.push(own.join("\n") + "\n");
    }
    out
}

fn contract(src: &str, injected: &str) -> Result<bool, String> {
    let Ok(before) = parse_program(injected) else {
        return Ok(false);
    };
    match format_source_lossless(injected) {
        Err(_) => Ok(false),
        Ok(out) => {
            if texts(&out) != texts(injected) {
                return Err(format!(
                    "a comment was lost or reordered\n--- source\n{injected}--- output\n{out}"
                ));
            }
            if comment_count(&out) != comment_count(injected) {
                return Err(format!("comment count changed\n--- source\n{injected}"));
            }
            match parse_program(&out) {
                Ok(after) if after == before => {}
                _ => {
                    return Err(format!(
                        "the tree changed\n--- source\n{injected}--- output\n{out}"
                    ))
                }
            }
            match format_source_lossless(&out) {
                Ok(twice) if twice == out => {}
                _ => {
                    return Err(format!(
                        "not idempotent\n--- source\n{injected}--- output\n{out}"
                    ))
                }
            }
            let _ = src;
            Ok(true)
        }
    }
}

#[test]
fn a_comment_at_every_line_of_every_shape_is_kept_or_refused() {
    let mut kept = 0usize;
    let mut tried = 0usize;
    for src in SEED.iter().chain(SHAPES) {
        let base = format_source(src).expect("the shape formats");
        let authored = format!("{}\n", src.trim_end());
        for injected in injections(&base).into_iter().chain(injections(&authored)) {
            tried += 1;
            match contract(src, &injected) {
                Ok(true) => kept += 1,
                Ok(false) => {}
                Err(e) => panic!("{e}"),
            }
        }
    }
    assert!(tried > 150, "the sweep reached only {tried} programs");
    assert!(
        kept * 2 > tried,
        "only {kept} of {tried} injected programs format: the refusal is no longer narrow"
    );
}

proptest! {
    #![proptest_config(ProptestConfig {
        max_global_rejects: 1 << 20,
        ..common::config(512)
    })]

    #[test]
    fn a_comment_in_a_generated_program_is_kept_or_refused(
        src in program(),
        at in 0usize..64,
        trailing in any::<bool>(),
    ) {
        let Ok(base) = format_source(&src) else {
            return Err(TestCaseError::reject("not blue"));
        };
        let lines: Vec<String> = base.lines().map(str::to_string).collect();
        prop_assume!(!lines.is_empty());
        let i = at % lines.len();
        let mut lines = lines;
        if trailing {
            lines[i].push_str(" # note");
        } else {
            let indent: String = lines[i].chars().take_while(|c| *c == ' ').collect();
            lines.insert(i, format!("{indent}# note"));
        }
        let injected = lines.join("\n") + "\n";
        if let Err(e) = contract(&src, &injected) {
            prop_assert!(false, "{}", e);
        }
    }
}
