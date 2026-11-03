#![cfg(feature = "packages")]

use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

use blue_lang_host::world::{self, Load, Refusal, Spec};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const CHILD: &str = "BLUE_WORLD_TEST_CHILD";

const SPEC: Spec<'static> = Spec {
    call: "host",
    kinds: "{**host_kinds, vigy: :open}",
    allow: &[],
    fuel: 2_000_000,
};

fn file(dir: &Path, text: &str) -> PathBuf {
    let path = dir.join("host.b");
    std::fs::write(&path, text).unwrap();
    path
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-world-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn child(mode: &str) -> Command {
    let mut command = Command::new(std::env::current_exe().unwrap());
    command.args(["--exact", "child_body", "--nocapture"]);
    command.env(CHILD, mode);
    command
}

#[test]
fn child_body() {
    let Ok(mode) = std::env::var(CHILD) else {
        return;
    };
    match mode.as_str() {
        "abort" => std::process::abort(),
        "sleep" => std::thread::sleep(Duration::from_secs(120)),
        "flood" => {
            let big = "x".repeat(1 << 20);
            let line = json!({"judged": {"accepted": [big], "off": [], "refusals": []}});
            println!("{line}");
        }
        file => {
            let code = world::serve::<()>(Path::new(file), &SPEC, world::DEFAULT_MEMORY_MB);
            std::process::exit(code);
        }
    }
    std::process::exit(0);
}

#[test]
fn a_world_is_judged_and_each_bad_entry_is_refused_alone() {
    let dir = scratch("judged");
    let path = file(
        &dir,
        "use(\"motenashi\", %i[bind command look motion])\n\ndef host()\n  [look({width: 7}), motion({speed: 2}), bind(\"x\", 9), command(\"hi\", {}), 42]\nend\n",
    );
    let judged = world::judged::<()>(&path, &SPEC).unwrap();
    let names: Vec<Value> = world::listed(&judged, "accepted")
        .iter()
        .map(|e| e["name"].clone())
        .collect();
    assert_eq!(
        names,
        vec![json!("appearance"), json!("motion"), json!("hi")]
    );
    let refusals = world::refusals_of(&judged);
    assert_eq!(refusals.len(), 2, "{refusals:?}");
    assert!(refusals.iter().all(|r| r.kind == "invalid"));
}

#[test]
fn a_loop_a_raise_and_a_parse_error_are_refusals_with_their_kind() {
    let dir = scratch("faults");
    let kind = |text: &str| {
        world::judged::<()>(&file(&dir, text), &SPEC)
            .unwrap_err()
            .kind
    };
    assert_eq!(kind("def host()\n  while(true, 1)\nend\n"), "exhausted");
    assert_eq!(kind("def host()\n  raise(:no, \"no\")\nend\n"), "raised");
    assert_eq!(kind("def host(\n"), "load");
    assert_eq!(kind("def other()\n  []\nend\n"), "load");
}

#[test]
fn a_loop_at_the_top_is_refused_at_its_budget() {
    let dir = scratch("top");
    let path = file(&dir, "while(true, 1)\n");
    assert_eq!(world::judged::<()>(&path, &SPEC).unwrap_err().kind, "load");
}

#[derive(Default)]
struct Words;

#[blue_lang_host::host]
impl Words {
    fn word(&self) -> String {
        "w".to_owned()
    }
}

#[test]
fn a_world_may_name_the_words_of_its_host() {
    let dir = scratch("words");
    let path = file(
        &dir,
        "def host()\n  []\nend\n\ndef hello()\n  word()\nend\n",
    );
    assert!(world::judged::<()>(&path, &SPEC).is_err());
    assert!(world::judged::<Words>(&path, &SPEC).is_ok());
}

#[test]
fn a_program_gets_no_host_effect_it_was_not_allowed() {
    let dir = scratch("posture");
    let effect = blue_lang_host::host_effect_names()[0];
    let text = format!("def host()\n  {effect}(\"x\")\n  []\nend\n");
    assert!(world::judged::<()>(&file(&dir, &text), &SPEC).is_err());
}

#[test]
fn the_real_child_answers_through_read() {
    let dir = scratch("child");
    let path = file(
        &dir,
        "use(\"motenashi\", [:look])\n\ndef host()\n  [look({width: 7})]\nend\n",
    );
    let load = world::read(child(path.to_str().unwrap()), &path, world::READ_LIMIT);
    let Load::Judged(judged) = load else {
        panic!("{load:?}");
    };
    assert_eq!(world::listed(&judged, "accepted")[0]["value"]["width"], 7);
}

#[test]
fn an_absent_file_starts_no_child() {
    let load = world::read(
        Command::new("/nonexistent/worker"),
        Path::new("/nonexistent/host.b"),
        world::READ_LIMIT,
    );
    assert_eq!(load, Load::Absent);
}

#[test]
fn a_dead_child_and_a_silent_child_are_refusals() {
    let here = std::env::current_exe().unwrap();
    let Load::Refused(died) = world::read(child("abort"), &here, world::READ_LIMIT) else {
        panic!("an abort must be refused");
    };
    assert_eq!(died.kind, "died");
    let started = Instant::now();
    let Load::Refused(killed) = world::read(child("sleep"), &here, Duration::from_millis(300))
    else {
        panic!("a hang must be refused");
    };
    assert_eq!(killed.kind, "killed");
    assert!(started.elapsed() < Duration::from_secs(10));
}

#[test]
fn an_answer_larger_than_a_pipe_is_read_whole() {
    let here = std::env::current_exe().unwrap();
    let Load::Judged(judged) = world::read(child("flood"), &here, Duration::from_secs(30)) else {
        panic!("a large answer must arrive");
    };
    assert_eq!(judged["accepted"][0].as_str().unwrap().len(), 1 << 20);
}

#[derive(Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Inner {
    a: u32,
    b: u32,
}

#[derive(Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Config {
    inner: Inner,
    top: String,
}

#[test]
fn a_merge_keeps_the_siblings_and_refuses_what_the_schema_refuses() {
    let base = Config {
        inner: Inner { a: 1, b: 2 },
        top: "t".into(),
    };
    let next: Config = world::merged(&base, &json!({"inner": {"a": 9}})).unwrap();
    assert_eq!(next.inner, Inner { a: 9, b: 2 });
    assert_eq!(next.top, "t");
    assert!(world::merged(&base, &json!({"inner": {"a": "no"}})).is_err());
    assert!(world::merged(&base, &json!({"inner": {"new": 1}})).is_err());
    assert!(world::merged(&base, &json!({"nope": 1})).is_err());
}

#[derive(Debug, Default, PartialEq, Serialize, Deserialize)]
struct Lenient {
    a: u32,
}

#[test]
fn a_field_a_lenient_schema_would_drop_is_refused_by_name() {
    let base = Lenient { a: 1 };
    let next: Lenient = world::merged(&base, &json!({"a": 2})).unwrap();
    assert_eq!(next.a, 2);
    let why = world::merged(&base, &json!({"typo": 2})).unwrap_err();
    assert!(why.contains("typo"), "{why}");
}

#[test]
fn work_in_time_returns_and_late_work_arrives_late() {
    let (tx, rx) = std::sync::mpsc::channel();
    let got = world::within(Duration::from_secs(30), || 7, move |v| tx.send(v).unwrap());
    assert_eq!(got, Some(7));
    assert!(rx.recv_timeout(Duration::from_millis(50)).is_err());

    let (tx, rx) = std::sync::mpsc::channel();
    let got = world::within(
        Duration::from_millis(20),
        || {
            std::thread::sleep(Duration::from_millis(200));
            7
        },
        move |v| tx.send(v).unwrap(),
    );
    assert_eq!(got, None);
    assert_eq!(rx.recv_timeout(Duration::from_secs(10)), Ok(7));
}

#[test]
fn a_refusal_reads_kind_then_why() {
    assert_eq!(Refusal::new("load", "no").to_string(), "load: no");
}
