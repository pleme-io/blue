//! A-colour of docs/ASYNC.md: in a restricted file, a definition that can
//! reach a suspension point is declared with `suspends(f)` (B0101).

use blue_lang_check::Code;
use blue_lang_runtime::pipeline::{check_entry, Checking};
use blue_lang_runtime::uses::{Entry, NoLoader};

const INPUT: &str = "definput(\"schema\", \"b3:abc\")\n\n";

const PAUSE: &str = "def pause(ms: Int) -> Int\n  sleep_for(ms)\n  ms\nend\n\ndef twice(ms: Int) -> Int\n  pause(ms) + pause(ms)\nend\n\ndef add(a: Int, b: Int) -> Int\n  a + b\nend\n";

fn refused(src: &str) -> Vec<String> {
    let checked =
        check_entry(Entry::anonymous(src), &NoLoader, None, Checking::Program).expect("checks");
    checked
        .outcome
        .diagnostics
        .iter()
        .filter(|d| d.code == Code::B0101)
        .map(|d| d.message.clone())
        .collect()
}

#[test]
fn a_restricted_file_names_each_undeclared_suspending_definition_and_its_chain() {
    let found = refused(&format!("{INPUT}{PAUSE}"));
    assert_eq!(found.len(), 2, "{found:?}");
    assert!(
        found[0].contains("`pause`") && found[0].contains("sleep_for"),
        "{found:?}"
    );
    assert!(
        found[1].contains("`twice`") && found[1].contains("pause → sleep_for"),
        "{found:?}"
    );
}

#[test]
fn a_declared_definition_passes() {
    let src = format!("{INPUT}{PAUSE}\nsuspends(pause)\nsuspends(twice)\n");
    assert_eq!(refused(&src), Vec::<String>::new());
}

#[test]
fn below_restricted_a_suspension_is_inferred_and_asks_nothing() {
    assert_eq!(refused(PAUSE), Vec::<String>::new());
    assert_eq!(
        refused(&format!("{INPUT}def nap(ms)\n  sleep_for(ms)\nend\n")),
        Vec::<String>::new()
    );
}
