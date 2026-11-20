//! `temp_dir` keeps its promise in a host that runs many programs: the
//! directory is "owned by this run: removed when the run ends, however it
//! ends". It used to be held until the process exited, so an in-process host
//! kept every run's directory (and its record) for its whole life.

use blue_lang_runtime::pipeline::run_framed_accounted;
use blue_lang_runtime::uses::{Entry, NoLoader};
use blue_lang_runtime::{Account, Inputs};
use tatara_lisp_eval::Value;

fn run(src: &str) -> Value {
    run_framed_accounted(
        Entry::anonymous(src),
        Inputs::new(),
        &NoLoader,
        None,
        None,
        &Account::default(),
    )
    .expect("the run answers")
    .value
}

#[test]
fn a_runs_temp_dir_is_removed_when_the_run_ends() {
    let Value::Str(path) = run("temp_dir(\"per-run\")\n") else {
        panic!("temp_dir gave no path");
    };
    assert!(
        !std::path::Path::new(&*path).exists(),
        "{path} outlived its run"
    );
}

#[test]
fn a_temp_dir_is_there_while_its_run_uses_it() {
    assert!(matches!(
        run("d = temp_dir(\"in-use\")\nis_dir?(d)\n"),
        Value::Bool(true)
    ));
}
