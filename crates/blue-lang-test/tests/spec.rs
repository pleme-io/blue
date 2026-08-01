//! **blue's own behaviour, specified in blue.**
//!
//! `spec/*.b` in the repo root is not a demo directory. It is blue describing
//! itself in itself, and this test is what makes it load-bearing: every `.b`
//! file there runs through the test runner, and a failure fails the build.
//!
//! ## What this is and is not
//!
//! This is **self-hosting on the specification axis**, not on the
//! implementation axis. blue's lexer, parser, checker, formatter and runtime
//! are Rust; nothing here compiles blue with blue. What is in blue is the
//! *statement of what blue does*, executed by blue.
//!
//! That distinction matters because "self-hosted" usually means the compiler
//! compiles itself, and this does not. Claiming otherwise would be the
//! overstatement the rest of this repo is written to avoid.
//! `theory/BLUE.md` §V.26 carries the row.
//!
//! ## Why it earns its keep anyway
//!
//! Every other test in this workspace asserts about blue from *outside* — a
//! Rust test calling a Rust function. These assert from inside, in the surface
//! an author actually writes, exercising the whole path at once: lexer →
//! parser → checker → erasure → macro expander → evaluator → the test runner →
//! the formatter that renders a failure. A break anywhere in that chain shows
//! up here as a failing spec rather than as a passing unit test.

use std::path::PathBuf;

fn spec_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("repo root")
        .join("spec")
}

fn spec_files() -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(spec_dir())
        .expect("spec/ must exist — it is part of the gate, not optional")
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "b"))
        .collect();
    // Deterministic order, so a failure report is reproducible.
    files.sort();
    files
}

/// Every spec file passes.
#[test]
fn every_spec_file_passes() {
    let files = spec_files();
    let mut failures: Vec<String> = Vec::new();
    let mut total = 0usize;

    for path in &files {
        let src = std::fs::read_to_string(path).expect("read spec");
        let forms = match blue_lang_syntax::parse_program(&src) {
            Ok(f) => f,
            Err(e) => {
                failures.push(format!("{}: parse error: {e}", path.display()));
                continue;
            }
        };
        let report = blue_lang_test::run(&forms);
        total += report.total();
        if !report.ok() {
            failures.push(format!("{}:\n{report}", path.display()));
        }
    }

    assert!(
        failures.is_empty(),
        "blue's own specification does not hold:\n{}",
        failures.join("\n\n")
    );
    // Anti-vacuity, inline: a green run over zero tests is not a pass. Without
    // this the gate goes green if the spec files are deleted, emptied, or
    // silently fail to be discovered.
    assert!(
        total >= 10,
        "expected a real spec suite, found only {total} test(s) across {} file(s) — \
         a gate that passes on an empty corpus proves nothing",
        files.len()
    );
}

/// **Every spec file must contain tests.** A `.b` file with none passes
/// trivially and dilutes the suite silently; naming the empty file is the
/// difference between a gate and a decoration.
#[test]
fn no_spec_file_is_empty_of_tests() {
    let mut empty: Vec<String> = Vec::new();
    for path in spec_files() {
        let src = std::fs::read_to_string(&path).expect("read spec");
        let forms = blue_lang_syntax::parse_program(&src).expect("spec must parse");
        let (tests, _) = blue_lang_test::split(&forms);
        if tests.is_empty() {
            empty.push(path.display().to_string());
        }
    }
    assert!(
        empty.is_empty(),
        "these spec files declare no tests: {empty:?}"
    );
}

/// The spec directory is non-empty and discovery works. If `spec/` moved or the
/// extension filter broke, the tests above would pass over nothing.
#[test]
fn spec_discovery_finds_the_files() {
    let files = spec_files();
    assert!(
        files.len() >= 3,
        "expected at least three spec files, found {}: {files:?}",
        files.len()
    );
    assert!(
        files.iter().all(|p| p.extension().is_some_and(|e| e == "b")),
        "discovery must find `.b` files"
    );
}

/// **Every spec file's CODE is canonically formatted.**
///
/// Compared against the formatting of the code with comments removed, because
/// blue's formatter does not preserve comments yet — asserting byte equality
/// against the commented file would force the spec files to be comment-free,
/// and a specification nobody can annotate is worth much less than one that is.
///
/// `blue fmt --write` refuses on these files for the same reason
/// (`FormatError::WouldDropComments`), so the gap cannot cause data loss; see
/// `blue-lang-cli`'s `fmt_write_refuses_to_delete_comments`.
#[test]
fn every_spec_files_code_is_canonically_formatted() {
    let mut drifted: Vec<String> = Vec::new();
    for path in spec_files() {
        let src = std::fs::read_to_string(&path).expect("read spec");
        let code = strip_comments(&src);
        match blue_lang_fmt::format_source(&code) {
            Err(e) => drifted.push(format!("{}: {e}", path.display())),
            Ok(formatted) => {
                if formatted.trim_end() != code.trim_end() {
                    drifted.push(format!(
                        "{}: the code is not canonically formatted\n--- want ---\n{formatted}\n--- got ---\n{code}",
                        path.display()
                    ));
                }
            }
        }
    }
    assert!(drifted.is_empty(), "{}", drifted.join("\n"));
}

/// Drop whole-line comments and the blank lines they leave, so what remains is
/// the code the formatter is responsible for.
fn strip_comments(src: &str) -> String {
    let lines: Vec<&str> = src
        .lines()
        .filter(|l| !l.trim_start().starts_with('#'))
        .collect();
    let mut out = String::new();
    for line in lines {
        if line.trim().is_empty() && out.is_empty() {
            continue; // leading blanks left by a stripped header
        }
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// Anti-vacuity: the comment stripper must actually remove something, or the
/// test above is comparing a file to itself.
#[test]
fn the_comment_stripper_removes_comments() {
    let src = "# a comment\ntest \"t\"\n  assert true\nend\n";
    let stripped = strip_comments(src);
    assert!(!stripped.contains('#'), "got {stripped:?}");
    assert!(stripped.contains("assert true"), "and keeps the code: {stripped:?}");
    assert!(
        spec_files().iter().any(|p| {
            let s = std::fs::read_to_string(p).expect("read");
            strip_comments(&s) != s
        }),
        "at least one spec file must actually carry comments, or the stripper \
         is being exercised on nothing"
    );
}
