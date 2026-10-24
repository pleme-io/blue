use std::path::{Path, PathBuf};

use blue_lang_check::Code;
use blue_lang_pkg::load_path::LoadPath;
use blue_lang_runtime::pipeline::{check_entry, Checking};
use blue_lang_runtime::uses::{Entry, Loader, ResolvedProgram};

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .canonicalize()
        .expect("root")
}

fn view() -> PathBuf {
    root().join("examples/frontend/views/profile.b")
}

fn loader() -> LoadPath {
    LoadPath::new([root().join("bidamas")])
}

fn source() -> String {
    std::fs::read_to_string(view()).expect("profile.b")
}

fn checked(path: &Path, text: &str) -> blue_lang_runtime::pipeline::Checked {
    check_entry(
        Entry {
            path: Some(path),
            text,
        },
        &loader(),
        None,
        Checking::WithTests,
    )
    .unwrap_or_else(|e| panic!("{e}"))
}

fn codes(text: &str) -> Vec<Code> {
    let c = checked(&view(), text);
    c.outcome
        .diagnostics
        .iter()
        .chain(&c.outcome.census)
        .map(|d| d.code)
        .collect()
}

fn mutated(from: &str, to: &str) -> String {
    let src = source();
    assert!(src.contains(from), "the view no longer holds {from:?}");
    src.replace(from, to)
}

#[test]
fn the_frontend_finds_its_schema_table_and_its_views() {
    let l = loader();
    let fe = l.frontend(&view()).expect("a frontend");
    assert!(fe.view);
    let (label, text) = fe.table.expect("the generated table");
    assert!(label.ends_with("schema.table"), "{label}");
    let schema = blue_lang_check::data_laws::Schema::read(&text).expect("reads");
    assert_eq!(schema.enums["Tone"], vec!["WARM", "COOL"]);
    let generator = root().join("examples/frontend/gen/schema.b");
    let fe = l.frontend(&generator).expect("the project's table");
    assert!(!fe.view, "the generator is not a view");
    assert!(l
        .frontend(&root().join("bidamas/danpen/danpen.b"))
        .is_none());
}

#[test]
fn the_example_view_holds_every_law() {
    assert_eq!(codes(&source()), Vec::<Code>::new());
}

#[test]
fn each_law_fires_on_the_view_it_breaks() {
    let cases = [
        (Code::B0048, mutated("#{user.name}", "#{user.id}")),
        (
            Code::B0048,
            mutated(
                "def profile(data: Profile)\n  user_card(data.user)\n",
                "def profile(data: Profile)\n  user_card(data.user)\n  data.user.name\n",
            ),
        ),
        (Code::B0049, mutated("[:id, \"...user_card\"]", "[:id]")),
        (Code::B0049, mutated("\"...user_card\"", "\"...nobody\"")),
        (Code::B0050, mutated("on: \"User\"", "on: \"Person\"")),
        (Code::B0050, mutated("WARM: \"Warm\"", "HOT: \"Warm\"")),
        (Code::B0050, mutated("labels(:Tone,", "labels(:Mood,")),
        (
            Code::B0051,
            mutated(
                "def user_card",
                "ALL = [\"COOL\", \"WARM\"]\n\ndef user_card",
            ),
        ),
        (
            Code::B0052,
            mutated(
                "def user_card",
                "ME = \"mutation Go { go }\"\n\ndef user_card",
            ),
        ),
    ];
    for (code, text) in cases {
        let got = codes(&text);
        assert!(
            got.contains(&code),
            "expected {code}, got {got:?} for:\n{text}"
        );
    }
}

#[test]
fn a_parent_reading_a_childs_field_is_told_whose_field_it_is() {
    let text = mutated(
        "def profile(data: Profile)\n  user_card(data.user)\n",
        "def profile(data: Profile)\n  user_card(data.user)\n  data.user.name\n",
    );
    let c = checked(&view(), &text);
    let d = c
        .outcome
        .diagnostics
        .iter()
        .find(|d| d.code == Code::B0048)
        .expect("B0048");
    assert!(
        d.message.contains("declared by fragment `user_card`"),
        "{}",
        d.message
    );
    assert!(d.fixes.is_empty(), "moving a read is not mechanical");
}

#[test]
fn the_composition_fix_spreads_the_fragment_and_the_view_then_holds() {
    let text = mutated("[:id, \"...user_card\"]", "[:id]");
    let c = checked(&view(), &text);
    let (fixed, n) = blue_lang_check::fixes::apply_machine_fixes(
        &c.outcome.diagnostics,
        &|i| c.program.owner_of(i) == Some(ResolvedProgram::ENTRY),
        &text,
    );
    assert_eq!(n, 1);
    assert!(fixed.contains("[:id, \"...user_card\"]"), "{fixed}");
    assert_eq!(codes(&fixed), Vec::<Code>::new());
}

#[test]
fn a_ref_seen_through_a_local_is_still_masked_and_a_lambda_parameter_shadows_it() {
    let aliased = mutated(
        "\"#{user.name} (#{get(TONES.entries, user.tone)}) #{user.avatar.url}\"",
        "a = user.avatar\n  a.alt",
    );
    assert!(codes(&aliased).contains(&Code::B0048));
    let shadowed = mutated(
        "\"#{user.name} (#{get(TONES.entries, user.tone)}) #{user.avatar.url}\"",
        "map((user) -> user.anything, [user.name])",
    );
    assert_eq!(codes(&shadowed), Vec::<Code>::new());
}

#[test]
fn query_text_in_a_views_test_or_outside_a_frontend_is_not_reported() {
    let in_test = format!(
        "{}\ntest \"text\"\n  assert \"query Q {{ a }}\" != \"\"\nend\n",
        source()
    );
    assert_eq!(codes(&in_test), Vec::<Code>::new());
    let elsewhere = root().join("bidamas/danpen/danpen.b");
    let text = "q = \"query Q { a }\"\nALL = [\"COOL\", \"WARM\"]\n";
    let c = checked(&elsewhere, text);
    assert!(
        !c.outcome
            .diagnostics
            .iter()
            .any(|d| matches!(d.code, Code::B0050 | Code::B0051 | Code::B0052)),
        "{:?}",
        c.outcome.diagnostics
    );
}
