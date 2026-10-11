//! The differential: the parser emitted from kiwari against blue's parser,
//! over every `.b` file and `Bluefile` in `spec/` and `bidamas/`, whole and at
//! every prefix (`agree` defines what agreeing means for each).
//!
//! It needs the tree-sitter runtime and the built grammar: `KIWARI_RUNTIME`
//! (`libtree-sitter`) and `KIWARI_PARSER` (the grammar's shared library, as
//! nix's `tree-sitter.buildGrammar` builds it). Without them it says so and
//! passes, unless `KIWARI_REQUIRE` is set, which the flake's `kiwari` check
//! sets, so the gate cannot go green having parsed nothing.
//!
//! `KIWARI_SCOPE=whole` judges whole files only (M0's round trip, seconds);
//! the default is every prefix. `KIWARI_THREADS` bounds the workers, and
//! `KIWARI_ONLY` keeps the files whose path contains it.

use std::path::{Path, PathBuf};

use blue_lang_kiwari::agree::{corpus, run, Scope};
use blue_lang_kiwari::spec::Spec;
use blue_lang_kiwari::ts::Runtime;

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn runtime() -> Option<Runtime> {
    let (Some(rt), Some(parser)) = (
        std::env::var_os("KIWARI_RUNTIME"),
        std::env::var_os("KIWARI_PARSER"),
    ) else {
        assert!(
            std::env::var_os("KIWARI_REQUIRE").is_none(),
            "KIWARI_REQUIRE is set and KIWARI_RUNTIME or KIWARI_PARSER is not"
        );
        eprintln!(
            "SKIPPED: no tree-sitter runtime or grammar (set KIWARI_RUNTIME and KIWARI_PARSER)"
        );
        return None;
    };
    Some(
        Runtime::load(Path::new(&rt), Path::new(&parser), "blue").unwrap_or_else(|e| panic!("{e}")),
    )
}

#[test]
fn the_emitted_parser_agrees_with_blue_on_the_corpus_and_every_prefix() {
    let Some(rt) = runtime() else { return };
    let spec = Spec::blue().expect("the rendered spec loads");
    let files = corpus(&[repo().join("spec"), repo().join("bidamas")]);
    assert!(
        files.len() > 100,
        "the corpus walk found {} files; it is not reading the corpus",
        files.len()
    );
    let files: Vec<_> = match std::env::var("KIWARI_ONLY") {
        Ok(only) => files
            .into_iter()
            .filter(|f| f.to_string_lossy().contains(&only))
            .collect(),
        Err(_) => files,
    };
    let scope = match std::env::var("KIWARI_SCOPE").as_deref() {
        Ok("whole") => Scope::Whole,
        _ => Scope::EveryPrefix,
    };
    let threads = std::env::var("KIWARI_THREADS")
        .ok()
        .and_then(|t| t.parse().ok())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(4, |n| n.get()));
    let started = std::time::Instant::now();
    let t = run(&rt, &spec, &files, scope, threads, 40).unwrap_or_else(|e| panic!("{e}"));
    eprintln!(
        "kiwari differential ({scope:?}, {threads} threads, {:.1}s): {} files, {} agree; {} prefixes judged ({} typed, {} opened): {} both accept, {} both refuse, {} closed statements checked; {} disagreements",
        started.elapsed().as_secs_f64(),
        t.files,
        t.files_agreeing,
        t.prefixes,
        t.typing,
        t.opening,
        t.both_accept,
        t.both_refuse,
        t.closed_statements_checked,
        t.disagreements
    );
    for f in &t.findings {
        eprintln!("  {f}");
    }
    assert_eq!(
        t.disagreements,
        0,
        "the emitted parser and blue's parser disagree; the first {} are above",
        t.findings.len()
    );
}
