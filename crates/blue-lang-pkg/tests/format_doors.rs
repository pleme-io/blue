use std::path::Path;

use blue_lang_fmt::{comment_count, format_source_lossless};
use blue_lang_pkg::canonical::format_resolved;

const SOURCES: &[&str] = &[
    "x = fn(a)\n  # c\n  a\nend\n",
    "x = fn(a) # c\n  a\nend\n",
    "x = fn(a)\n  a # c\nend\n",
    "x = fn(a)\n  # c\nend\n",
    "x = (a) ->\n  # c\n  a\n",
    "x = (a) -> (\n  # c\n  a\n)\n",
    "f(fn(a)\n  # c\n  a\nend, 1)\n",
    "x = fn(a)\n  # c\n  a\n  b\nend\n",
    "x = f(\n  1\n  # c\n) rescue 2\n",
    "x = a rescue\n  # c\n  b\n",
    "a rescue (if c\n  # n\n  1\nend)\n",
    "def f(a)\n  # c\n  a |> g\nend\n",
];

#[test]
fn the_cli_door_keeps_every_comment_the_library_door_keeps() {
    for src in SOURCES {
        let library = format_source_lossless(src);
        let cli = format_resolved(Path::new("/nonexistent/witness.b"), src);
        match (&library, &cli) {
            (Ok(l), Ok(c)) => {
                assert_eq!(
                    comment_count(c),
                    comment_count(src),
                    "the CLI door dropped a comment of {src:?}\n--- library\n{l}--- cli\n{c}"
                );
            }
            (Ok(l), Err(e)) => {
                panic!("the CLI door refuses what the library formats: {src:?}\n{l}\n{e}")
            }
            (Err(_), _) => {}
        }
    }
}

#[test]
fn a_refusal_is_the_same_at_both_doors() {
    for src in SOURCES {
        let library = format_source_lossless(src).is_ok();
        let cli = format_resolved(Path::new("/nonexistent/witness.b"), src).is_ok();
        assert_eq!(library, cli, "{src:?}");
    }
}
