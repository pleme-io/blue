use std::path::{Path, PathBuf};
use std::sync::mpsc::{channel, Receiver};
use std::sync::Arc;
use std::time::{Duration, Instant};

use blue_lang_worker::child::{judged_args, serve_args, ServeArgs, DEFAULT_FUEL};
use blue_lang_worker::{run_once, Event, OnceRun, Pool, Refusal, Reply, WorkerSpec};

fn exe() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_blue-lang-worker"))
}

fn temp(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-pool-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn write(dir: &Path, name: &str, text: &str) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, text).unwrap();
    path
}

fn spec(name: &str, file: &Path, fuel: usize, hard_ms: u64) -> WorkerSpec {
    let mut s = WorkerSpec::new(
        name,
        serve_args(&ServeArgs {
            file: file.to_path_buf(),
            allow: vec!["process".to_owned()],
            fuel,
            memory_mb: 1024,
        }),
    );
    s.soft_ms = 20;
    s.hard_ms = hard_ms;
    s
}

fn pool() -> (Pool, Receiver<Event>) {
    let (tx, rx) = channel();
    let tx = std::sync::Mutex::new(tx);
    let sink: blue_lang_worker::Sink = Arc::new(move |e| {
        let _ = tx.lock().unwrap().send(e);
    });
    (Pool::new(exe(), sink), rx)
}

fn next(rx: &Receiver<Event>) -> Event {
    rx.recv_timeout(Duration::from_secs(30))
        .expect("no event in 30 s")
}

#[test]
fn a_worker_answers_and_is_kept_for_the_next_question() {
    let dir = temp("answer");
    let file = write(&dir, "m.b", "def render()\n  \"hi\"\nend\n");
    let (mut p, rx) = pool();
    p.set_specs(vec![spec("m", &file, DEFAULT_FUEL, 30_000)]);
    p.ask("m", 1, "render", vec![]).unwrap();
    let Event::Line { epoch, reply, .. } = next(&rx) else {
        panic!("no line");
    };
    assert_eq!(
        reply,
        Reply::Answer {
            id: 1,
            value: serde_json::json!("hi")
        }
    );
    assert!(p.answered("m", epoch));
    assert!(!p.busy());
    p.ask("m", 2, "render", vec![]).unwrap();
    let Event::Line { epoch: same, .. } = next(&rx) else {
        panic!("no line");
    };
    assert_eq!(
        same, epoch,
        "a second question must not cost a second child"
    );
    assert_eq!(p.running(), 1);
}

#[test]
fn a_load_failure_is_named_and_later_questions_answer_with_it() {
    let dir = temp("load");
    let file = write(&dir, "m.b", "def (((\n");
    let (mut p, rx) = pool();
    p.set_specs(vec![spec("m", &file, DEFAULT_FUEL, 30_000)]);
    p.ask("m", 1, "render", vec![]).unwrap();
    let Event::Line { epoch, reply, .. } = next(&rx) else {
        panic!("no line");
    };
    let Reply::LoadRefused { load_refused } = reply else {
        panic!("{reply:?}");
    };
    assert_eq!(load_refused.kind, "load");
    assert!(p.load_refused("m", epoch, &load_refused));
    assert_eq!(p.ask("m", 2, "render", vec![]).unwrap_err().kind, "load");
    let Event::Closed { worker, epoch } = next(&rx) else {
        panic!("no close");
    };
    assert_eq!(
        p.closed(&worker, epoch),
        None,
        "the load refusal already said why"
    );
    assert_eq!(p.running(), 0);
}

#[test]
fn a_hang_is_slow_first_then_killed_and_the_next_question_gets_a_new_child() {
    let dir = temp("hang");
    let file = write(
        &dir,
        "m.b",
        "def hang()\n  exec_capture([\"sleep\", \"30\"])\nend\n\ndef fine()\n  \"up\"\nend\n",
    );
    let (mut p, rx) = pool();
    p.set_specs(vec![spec("m", &file, DEFAULT_FUEL, 400)]);
    p.ask("m", 1, "hang", vec![]).unwrap();
    let started = Instant::now();
    let mut kinds = Vec::new();
    while kinds.last().map(String::as_str) != Some("killed") {
        assert!(
            started.elapsed() < Duration::from_secs(20),
            "never killed: {kinds:?}"
        );
        for overdue in p.tick(Instant::now()) {
            kinds.push(overdue.refusal.kind);
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(kinds, vec!["slow", "killed"]);
    assert_eq!(p.running(), 0);
    let _ = rx.try_iter().count();
    p.ask("m", 2, "fine", vec![]).unwrap();
    loop {
        if let Event::Line { reply, .. } = next(&rx) {
            assert_eq!(
                reply,
                Reply::Answer {
                    id: 2,
                    value: serde_json::json!("up")
                }
            );
            break;
        }
    }
}

#[test]
fn a_child_that_dies_is_seen_as_closed_and_its_refusal_says_so() {
    let dir = temp("die");
    let file = write(&dir, "m.b", "def die()\n  exit_with(7)\nend\n");
    let (mut p, rx) = pool();
    p.set_specs(vec![spec("m", &file, DEFAULT_FUEL, 30_000)]);
    p.ask("m", 1, "die", vec![]).unwrap();
    loop {
        match next(&rx) {
            Event::Closed { worker, epoch } => {
                let (id, refusal) = p.closed(&worker, epoch).unwrap();
                assert_eq!(id, 1);
                assert_eq!(refusal.kind, "died");
                break;
            }
            Event::Line { .. } => {}
        }
    }
    assert_eq!(p.running(), 0);
}

#[test]
fn a_stale_line_from_an_earlier_child_is_no_answer() {
    let dir = temp("stale");
    let file = write(&dir, "m.b", "def render()\n  \"hi\"\nend\n");
    let (mut p, _rx) = pool();
    p.set_specs(vec![spec("m", &file, DEFAULT_FUEL, 30_000)]);
    p.ask("m", 1, "render", vec![]).unwrap();
    assert!(!p.answered("m", 999));
    assert!(p.closed("m", 999).is_none());
    assert!(!p.load_refused("m", 999, &Refusal::new("load", "x")));
    assert!(!p.answered("nope", 1));
}

#[test]
fn an_unknown_worker_is_refused_by_name() {
    let (mut p, _rx) = pool();
    let r = p.ask("nope", 1, "render", vec![]).unwrap_err();
    assert_eq!(r.kind, "unknown");
    assert!(r.why.contains("nope"));
}

#[test]
fn a_changed_spec_stops_its_child_and_an_equal_one_keeps_it() {
    let dir = temp("specs");
    let file = write(&dir, "m.b", "def render()\n  \"hi\"\nend\n");
    let (mut p, rx) = pool();
    let s = spec("m", &file, DEFAULT_FUEL, 30_000);
    p.set_specs(vec![s.clone()]);
    p.ask("m", 1, "render", vec![]).unwrap();
    let Event::Line { epoch, .. } = next(&rx) else {
        panic!("no line");
    };
    p.answered("m", epoch);
    p.set_specs(vec![s.clone()]);
    assert_eq!(p.running(), 1);
    p.set_specs(vec![spec("m", &file, 9, 30_000)]);
    assert_eq!(p.running(), 0);
    p.set_specs(vec![]);
    assert!(p.names().is_empty());
}

#[test]
fn cancel_all_stops_only_what_is_in_flight() {
    let dir = temp("cancel");
    let file = write(
        &dir,
        "m.b",
        "def hang()\n  exec_capture([\"sleep\", \"30\"])\nend\n",
    );
    let (mut p, _rx) = pool();
    p.set_specs(vec![spec("m", &file, DEFAULT_FUEL, 30_000)]);
    p.ask("m", 1, "hang", vec![]).unwrap();
    assert!(p.busy());
    p.cancel_all();
    assert!(!p.busy());
    assert_eq!(p.running(), 0);
}

#[test]
fn a_judged_run_answers_once_on_stdout() {
    let dir = temp("judged");
    let file = write(&dir, "w.b", "def world()\n  [1, 2]\nend\n");
    let mut c = std::process::Command::new(exe());
    c.args(judged_args(&file));
    let OnceRun::Finished { stdout } = run_once(c, Duration::from_secs(30)) else {
        panic!("no answer");
    };
    let reply: Reply = serde_json::from_slice(&stdout).unwrap();
    assert_eq!(
        reply,
        Reply::Answer {
            id: 0,
            value: serde_json::json!([1, 2])
        }
    );
}

#[test]
fn a_judged_world_that_does_not_load_says_so() {
    let dir = temp("judged-bad");
    let file = write(&dir, "w.b", "def (((\n");
    let mut c = std::process::Command::new(exe());
    c.args(judged_args(&file));
    let OnceRun::Finished { stdout } = run_once(c, Duration::from_secs(30)) else {
        panic!("no answer");
    };
    let Reply::LoadRefused { load_refused } = serde_json::from_slice(&stdout).unwrap() else {
        panic!("not refused");
    };
    assert_eq!(load_refused.kind, "load");
}
