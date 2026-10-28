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
//! the default is every prefix. `KIWARI_THREADS` bounds the workers,
//! `KIWARI_ONLY` keeps the files whose path contains it, and
//! `KIWARI_STOP_AFTER` is how many disagreements end the run (`STOP_AFTER`).

use std::path::{Path, PathBuf};

use blue_lang_kiwari::agree::{corpus, run, Scope, STOP_AFTER};
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
    let stop_after = std::env::var("KIWARI_STOP_AFTER")
        .ok()
        .and_then(|n| n.parse().ok())
        .unwrap_or(STOP_AFTER);
    let started = std::time::Instant::now();
    let t = run(&rt, &spec, &files, scope, threads, stop_after).unwrap_or_else(|e| panic!("{e}"));
    eprintln!(
        "kiwari differential ({scope:?}, {threads} threads, {:.1}s): {} files, {} with a disagreement; {} prefixes judged ({} typed, {} opened): {} both accept, {} both refuse, {} closed statements checked; {} disagreements{}",
        started.elapsed().as_secs_f64(),
        t.files,
        t.files - t.files_agreeing,
        t.prefixes,
        t.typing,
        t.opening,
        t.both_accept,
        t.both_refuse,
        t.closed_statements_checked,
        t.disagreements,
        if t.stopped_early {
            format!(", stopped at KIWARI_STOP_AFTER={stop_after} with prefixes unjudged")
        } else {
            String::new()
        }
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

#[test]
fn a_failing_differential_stops_at_its_cap() {
    let Some(rt) = runtime() else { return };
    let mut spec: serde_json::Value =
        serde_json::from_str(blue_lang_kiwari::spec::BLUE).expect("the rendered spec is JSON");
    spec["lower"]["integer"] = serde_json::json!(["sym", "not-the-integer"]);
    let spec = Spec::parse(&spec.to_string()).expect("the broken spec loads");
    let files = corpus(&[repo().join("spec"), repo().join("bidamas")]);
    let total: usize = files
        .iter()
        .map(|f| std::fs::read_to_string(f).expect("a corpus file").len())
        .sum();
    let started = std::time::Instant::now();
    let t = run(&rt, &spec, &files, Scope::EveryPrefix, 4, 3).unwrap_or_else(|e| panic!("{e}"));
    eprintln!(
        "a spec lowering every integer wrongly: {} disagreements, {} of about {total} prefixes judged, {:.1}s",
        t.disagreements,
        t.prefixes,
        started.elapsed().as_secs_f64()
    );
    assert_eq!(
        t.disagreements, 3,
        "the run kept more or fewer than its cap"
    );
    assert_eq!(t.findings.len(), 3);
    assert!(t.stopped_early, "the run did not report that it stopped");
    assert!(
        t.prefixes < total / 10,
        "the run judged {} of {total} prefixes after its cap",
        t.prefixes
    );
}
