//! Where a type error inside an IMPORTED package is reported.
//!
//! `blue run` resolves `use("kazu")` by splicing kazu's forms into the program
//! and checking the whole thing at once. Until 2026-08-12 it checked a tree
//! lifted with `Spanned::from_sexp_synthetic`, so every type error — the
//! importer's own and its packages' alike — came back as a bare message with
//! no position at all. The reason was real: `Span` is a byte range with no file
//! identity, and a byte range from kazu's source resolved against the ENTRY
//! file names a line in the wrong file, confidently.
//!
//! blue now carries the file identity beside the span, per top-level form, and
//! this is the gate on that. It asserts the two halves that were wrong in
//! opposite ways:
//!
//! 1. the FILE is the imported package's, not the entry program's;
//! 2. the LINE is the line in THAT file, hand-counted below rather than
//!    derived from the code under test.
//!
//! The fixture is built so a regression cannot pass by luck: the error sits at
//! byte 52 of a 60-byte package, and the entry program is 22 bytes — so a span
//! resolved against the entry file cannot land on line 6, and `line_col`'s
//! walk-off-the-end behaviour puts it on line 2 instead.
//!
//! **Red runs** (2026-08-12), both against
//! `a_type_error_in_an_imported_package_names_that_package_and_its_line`:
//!
//! 1. `expand` stamping every form with the entry file instead of its own —
//!    `got "/work/main.b:2:11: `bad` declares it returns Str, but its body
//!    produces Int"`. Line 2 column 11 is the END of the 22-byte entry
//!    program: the confident-wrong position predicted above, in the file the
//!    reader would have opened.
//! 2. the imported source parsed through the spanless door, as it was until
//!    this change — `got "/dist/kazu/kazu.b: `bad` declares it returns Str,
//!    but its body produces Int"`. The file survives, the line does not, which
//!    is what a synthetic span honestly renders as.

use std::collections::BTreeMap;

use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{run_in_surface, RunError};
use blue_lang_runtime::uses::{Entry, Loader};

/// An in-memory distribution, so the gate needs no files on disk.
///
/// The label is a full path, as `blue_lang_pkg::load_path`'s real loader
/// produces (`path.display().to_string()`), because the label IS what a reader
/// is told to open.
struct MemLoader(BTreeMap<&'static str, &'static str>);

impl Loader for MemLoader {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.0
            .get(name)
            .map(|s| vec![(format!("/dist/{name}/{name}.b"), (*s).to_owned())])
            .ok_or_else(|| format!("no bidama named \"{name}\""))
    }
}

/// A package whose SIXTH line does not typecheck.
///
/// Hand-counted, and the count is the assertion:
///
/// ```text
/// 1  def double(n)
/// 2    n * 2
/// 3  end
/// 4
/// 5  def bad(n: Int) -> Str
/// 6    n + 1
/// 7  end
/// ```
///
/// `bad` declares `Str` and its body produces `Int`, so the diagnostic points
/// at the BODY — line 6, column 3, where `n` sits after two spaces of indent.
const KAZU: &str = "def double(n)\n  n * 2\nend\n\ndef bad(n: Int) -> Str\n  n + 1\nend";

/// The importer. Two lines, 22 bytes, and no type error of its own.
const ENTRY: &str = "use(\"kazu\")\ndouble(21)";

fn kazu() -> MemLoader {
    MemLoader(BTreeMap::from([("kazu", KAZU)]))
}

fn type_errors(entry: Entry<'_>, loader: &dyn Loader) -> Vec<String> {
    match run_in_surface(entry, Inputs::new(), loader, None) {
        Err(RunError::Types(d)) => d,
        other => panic!("expected type diagnostics, got {other:?}"),
    }
}

/// **The load-bearing assertion: the imported file, and the line in it.**
#[test]
fn a_type_error_in_an_imported_package_names_that_package_and_its_line() {
    let diagnostics = type_errors(
        Entry {
            path: Some(std::path::Path::new("/work/main.b")),
            text: ENTRY,
        },
        &kazu(),
    );
    assert_eq!(diagnostics.len(), 1, "{diagnostics:?}");
    let reported = &diagnostics[0];

    assert!(
        reported.starts_with("/dist/kazu/kazu.b:6:3:"),
        "an imported package's type error must report ITS file and line — \
         hand-counted as line 6, column 3 of the package source — got {reported:?}"
    );
    assert!(
        !reported.contains("/work/main.b"),
        "the error was attributed to the ENTRY file, which is the exact \
         mis-attribution a file-less span produces: {reported:?}"
    );
    assert!(
        reported.contains("declares it returns Str"),
        "the message itself must survive being given a position: {reported:?}"
    );
}

/// The entry file's OWN errors still name the entry file.
///
/// The counterpart to the test above, and not a formality: an implementation
/// that attributed everything to the last file it loaded would pass that one.
/// Hand-counted — the entry program's error is on line 2, column 3.
#[test]
fn a_type_error_in_the_entry_file_names_the_entry_file() {
    let src = "def bad(n: Int) -> Str\n  n + 1\nend\nbad(1)";
    let diagnostics = type_errors(
        Entry {
            path: Some(std::path::Path::new("/work/main.b")),
            text: src,
        },
        &kazu(),
    );
    assert_eq!(diagnostics.len(), 1, "{diagnostics:?}");
    assert!(
        diagnostics[0].starts_with("/work/main.b:2:3:"),
        "got {:?}",
        diagnostics[0]
    );
}

/// Both files at once, each reported against itself.
///
/// The strongest form of the property: one run, two errors, two different
/// files and two different line numbers. A single shared offset base cannot
/// satisfy both.
#[test]
fn two_files_two_positions() {
    let src = "use(\"kazu\")\ndef also_bad(n: Int) -> Str\n  n + 1\nend\nalso_bad(1)";
    let diagnostics = type_errors(
        Entry {
            path: Some(std::path::Path::new("/work/main.b")),
            text: src,
        },
        &kazu(),
    );
    assert_eq!(diagnostics.len(), 2, "{diagnostics:?}");
    let joined = diagnostics.join("\n");
    // kazu's is on line 6 of kazu; the entry's is on line 3 of the entry.
    assert!(
        joined.contains("/dist/kazu/kazu.b:6:3:"),
        "the imported error moved: {joined}"
    );
    assert!(
        joined.contains("/work/main.b:3:3:"),
        "the entry error moved: {joined}"
    );
}

/// Source with no file behind it says so, rather than inventing a name.
///
/// `pipeline::run_with_loader` takes bare text — an embedder, a test, the WASM
/// surface — and there is no path to report. `<anonymous>` is the honest
/// answer; a fabricated `<stdin>` would be a claim about where the text came
/// from that nothing checked.
#[test]
fn text_with_no_file_reports_no_file() {
    let src = "def bad(n: Int) -> Str\n  n + 1\nend\nbad(1)";
    let diagnostics = type_errors(Entry::anonymous(src), &kazu());
    assert_eq!(diagnostics.len(), 1, "{diagnostics:?}");
    assert!(
        diagnostics[0].starts_with("<anonymous>:2:3:"),
        "got {:?}",
        diagnostics[0]
    );
}
