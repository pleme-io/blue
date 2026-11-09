#[macro_use]
mod moduledoc;

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG")
        .env_remove("BLUE_MEMO");
    c
}

fn put(path: &Path, text: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).expect("write fixture");
}

fn out(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

fn err(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

const SPIN: &str = moduledoc!(
    "spin counts down to done.",
    "spin(3) #=> :done",
    "def spin(n)\n  if n == 0\n    :done\n  else\n    spin(n - 1)\n  end\nend\n\ndef main()\n  spin(1_000_000)\nend\n\ntest \"spins\"\n  assert spin(1_000_000) == :done\nend\n"
);

const HOG: &str = moduledoc!(
    "hog holds a pair for every number below 20000.",
    "length(map((x) -> [x, x], range(0, 3))) #=> 3",
    "def main()\n  length(map((x) -> [x, x], range(0, 20000)))\nend\n\ntest \"small\"\n  assert length(map((x) -> [x, x], range(0, 10))) == 10\nend\n\ntest \"hog\"\n  assert length(map((x) -> [x, x], range(0, 20000))) == 20000\nend\n"
);

const CHILD: &str = moduledoc!(
    "child spins in a process of its own, and its exit is the answer.",
    "spin(3) #=> :done",
    "def spin(n)\n  if n == 0\n    :done\n  else\n    spin(n - 1)\n  end\nend\n\ndef child()\n  p = spawn(spin, [1_000_000])\n  monitor(p)\n  last(receive())\nend\n\ndef main()\n  child\nend\n\ntest \"a child spins to the end\"\n  assert child == :normal\nend\n"
);

fn project(name: &str, bluefile: &str, app: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-bounds-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    put(&dir.join("Bluefile"), bluefile);
    put(&dir.join("app.b"), app);
    let dir = dir.canonicalize().unwrap();
    let locked = blue().arg("lock").arg(&dir).output().unwrap();
    assert!(locked.status.success(), "{name}: {}", err(&locked));
    dir
}

fn run(dir: &Path, cfg: Option<&Path>) -> Output {
    let mut c = blue();
    if let Some(cfg) = cfg {
        c.env("BLUE_CONFIG", cfg);
    }
    c.arg("run").arg(dir.join("app.b")).output().unwrap()
}

fn test(dir: &Path) -> Output {
    blue().arg("test").arg(dir.join("app.b")).output().unwrap()
}

fn config(dir: &Path, yaml: &str) -> PathBuf {
    let at = dir.join("operator.yaml");
    put(&at, yaml);
    at
}

#[test]
fn a_step_bound_the_project_declares_refuses_a_loop_it_completes_without_it() {
    let free = project("steps-free", "package(\"spin\", \"0.1.0\")\n", SPIN);
    let ran = run(&free, None);
    assert!(ran.status.success(), "{}", err(&ran));
    assert_eq!(out(&ran).trim(), ":done");
    let tested = test(&free);
    assert!(tested.status.success(), "{}{}", out(&tested), err(&tested));

    let bounded = project(
        "steps-bounded",
        "package(\"spin\", \"0.1.0\")\nbounds({steps: 100_000})\n",
        SPIN,
    );
    let refused = run(&bounded, None);
    assert!(!refused.status.success(), "{}", out(&refused));
    assert!(
        err(&refused).contains("fuel budget of 100000 exceeded in `spin::spin`"),
        "{}",
        err(&refused)
    );
    let held = blue()
        .args(["run", "--allow", "none"])
        .arg(bounded.join("app.b"))
        .output()
        .unwrap();
    assert!(
        err(&held).contains("fuel budget of 100000 exceeded"),
        "--allow narrows the frame and keeps the bounds: {}",
        err(&held)
    );
    let tested = test(&bounded);
    assert!(!tested.status.success(), "{}", out(&tested));
    assert!(
        format!("{}{}", out(&tested), err(&tested)).contains("fuel budget of 100000 exceeded"),
        "{}{}",
        out(&tested),
        err(&tested)
    );
}

#[test]
fn a_live_byte_bound_the_project_declares_refuses_what_it_holds_without_it() {
    let free = project("alloc-free", "package(\"hog\", \"0.1.0\")\n", HOG);
    let ran = run(&free, None);
    assert!(ran.status.success(), "{}", err(&ran));
    assert_eq!(out(&ran).trim(), "20000");
    let tested = test(&free);
    assert!(
        out(&tested).contains("3 passed, 0 failed"),
        "{}{}",
        out(&tested),
        err(&tested)
    );

    let bounded = project(
        "alloc-bounded",
        "package(\"hog\", \"0.1.0\")\nbounds({alloc_bytes: 1_048_576})\n",
        HOG,
    );
    let refused = run(&bounded, None);
    assert!(!refused.status.success(), "{}", out(&refused));
    assert!(
        err(&refused).contains("memory-exhausted: live-byte budget of 1048576 exceeded"),
        "{}",
        err(&refused)
    );
    let tested = test(&bounded);
    assert!(
        !tested.status.success() && out(&tested).contains("2 passed, 1 failed"),
        "{}{}",
        out(&tested),
        err(&tested)
    );
    assert!(
        format!("{}{}", out(&tested), err(&tested))
            .contains("memory-exhausted: live-byte budget of 1048576 exceeded"),
        "{}{}",
        out(&tested),
        err(&tested)
    );
}

#[test]
fn a_bound_the_project_declares_past_the_operators_does_not_widen_it() {
    let wide = project(
        "wide",
        "package(\"spin\", \"0.1.0\")\nbounds({steps: 100_000_000, alloc_bytes: 1_073_741_824})\n",
        SPIN,
    );
    let operator = config(&wide, "max_steps: 100000\n");
    let refused = run(&wide, Some(&operator));
    assert!(!refused.status.success(), "{}", out(&refused));
    assert!(
        err(&refused).contains("fuel budget of 100000 exceeded"),
        "the operator's bound holds: {}",
        err(&refused)
    );

    let hog = project(
        "wide-hog",
        "package(\"hog\", \"0.1.0\")\nbounds({alloc_bytes: 1_073_741_824})\n",
        HOG,
    );
    let operator = config(&hog, "max_alloc_bytes: 1048576\n");
    let refused = run(&hog, Some(&operator));
    assert!(!refused.status.success(), "{}", out(&refused));
    assert!(
        err(&refused).contains("live-byte budget of 1048576 exceeded"),
        "the operator's bound holds: {}",
        err(&refused)
    );

    let narrow = project(
        "narrow",
        "package(\"spin\", \"0.1.0\")\nbounds({steps: 50_000})\n",
        SPIN,
    );
    let operator = config(&narrow, "max_steps: 100000\n");
    let refused = run(&narrow, Some(&operator));
    assert!(
        err(&refused).contains("fuel budget of 50000 exceeded"),
        "the lesser of the two holds: {}",
        err(&refused)
    );
}

#[test]
fn blue_lock_records_the_bounds_and_confirm_holds_the_lock_to_them() {
    let dir = project(
        "lock",
        "package(\"spin\", \"0.1.0\")\nbounds({steps: 100_000, call_depth: 2000})\n",
        SPIN,
    );
    let written: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap()).unwrap();
    assert_eq!(
        written["capabilities"]["bounds"],
        serde_json::json!({"steps": 100_000, "call_depth": 2000}),
        "{written}"
    );
    assert_eq!(
        written["manifest"]["bounds"], written["capabilities"]["bounds"],
        "{written}"
    );
    assert!(
        written["capabilities"].get("ceiling").is_none(),
        "{written}"
    );

    let confirm = || {
        blue()
            .args(["bluefile", "--confirm"])
            .arg(dir.join("Bluefile"))
            .output()
            .unwrap()
    };
    let fresh = confirm();
    assert!(fresh.status.success(), "{}", err(&fresh));

    put(
        &dir.join("Bluefile"),
        "package(\"spin\", \"0.1.0\")\nbounds({steps: 200_000, call_depth: 2000})\n",
    );
    let stale = confirm();
    assert!(!stale.status.success(), "a changed bound is stale");
    assert!(
        err(&stale).contains("recorded capabilities"),
        "{}",
        err(&stale)
    );
    let relocked = blue().arg("lock").arg(&dir).output().unwrap();
    assert!(relocked.status.success(), "{}", err(&relocked));
    assert!(confirm().status.success());

    put(&dir.join("Bluefile"), "package(\"spin\", \"0.1.0\")\n");
    let dropped = confirm();
    assert!(
        !dropped.status.success() && err(&dropped).contains("recorded capabilities"),
        "a record whose Bluefile declares nothing is stale: {}",
        err(&dropped)
    );
    let relocked = blue().arg("lock").arg(&dir).output().unwrap();
    assert!(relocked.status.success(), "{}", err(&relocked));
    let unbounded: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(dir.join("Bluefile.lock")).unwrap()).unwrap();
    assert!(unbounded.get("capabilities").is_none(), "{unbounded}");
    assert!(unbounded["manifest"].get("bounds").is_none(), "{unbounded}");
    let ran = run(&dir, None);
    assert_eq!(out(&ran).trim(), ":done", "{}", err(&ran));
}

#[test]
fn a_bound_that_is_not_a_positive_integer_refuses_the_lock() {
    let dir = std::env::temp_dir().join(format!("blue-bounds-zero-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    put(
        &dir.join("Bluefile"),
        "package(\"spin\", \"0.1.0\")\nbounds({steps: 0})\n",
    );
    put(&dir.join("app.b"), SPIN);
    let locked = blue().arg("lock").arg(&dir).output().unwrap();
    assert!(!locked.status.success());
    assert!(
        err(&locked).contains("`bounds`: `steps` must be a positive integer, got 0"),
        "{}",
        err(&locked)
    );
    assert!(!dir.join("Bluefile.lock").exists());
    let ran = blue().arg("run").arg(dir.join("app.b")).output().unwrap();
    assert!(
        !ran.status.success(),
        "blue run refuses rather than run unbounded: {}",
        out(&ran)
    );
}

#[test]
fn a_process_the_program_spawns_is_held_to_the_projects_step_bound() {
    let free = project("child-free", "package(\"spin\", \"0.1.0\")\n", CHILD);
    let ran = run(&free, None);
    assert_eq!(out(&ran).trim(), ":normal", "{}", err(&ran));
    let tested = test(&free);
    assert!(tested.status.success(), "{}{}", out(&tested), err(&tested));

    let bounded = project(
        "child-bounded",
        "package(\"spin\", \"0.1.0\")\nbounds({steps: 100_000})\n",
        CHILD,
    );
    let ran = run(&bounded, None);
    assert!(
        out(&ran).contains("[:runaway, ") && out(&ran).contains("(limit 100000)"),
        "the child exits on the project's bound: {}{}",
        out(&ran),
        err(&ran)
    );
    let tested = test(&bounded);
    assert!(
        !tested.status.success() && out(&tested).contains("1 passed, 1 failed"),
        "a child a test spawns is held too: {}{}",
        out(&tested),
        err(&tested)
    );
}

fn served(opts: &str) -> String {
    format!(
        "{}def spin(k)\n  if k == 0\n    0\n  else\n    spin(k - 1)\n  end\nend\n\ndef h(m, n)\n  if list?(m)\n    send(first(m), n)\n    n\n  elsif m == 0\n    spin(5000)\n    n + 1000\n  else\n    n + m\n  end\nend\n\ndef main()\n  s = spawn_server(h, 0{opts})\n  monitor(s)\n  send(s, 1)\n  send(s, 0)\n  send(s, [self])\n  receive(:_, 5000)\nend\n",
        moduledoc!(
            "srv adds what it is sent to its state, and spins on a zero.",
            "h(2, 1) #=> 3"
        )
    )
}

#[test]
fn a_dispatch_bound_the_project_declares_meets_the_one_a_server_is_spawned_with() {
    let free = project(
        "dispatch-free",
        "package(\"srv\", \"0.1.0\")\n",
        &served(""),
    );
    let ran = run(&free, None);
    assert_eq!(out(&ran).trim(), "1001", "{}", err(&ran));

    let declared = "package(\"srv\", \"0.1.0\")\nbounds({dispatch_steps: 2000})\n";
    let bounded = project("dispatch-bounded", declared, &served(""));
    let written: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(bounded.join("Bluefile.lock")).unwrap())
            .unwrap();
    assert_eq!(
        written["capabilities"]["bounds"],
        serde_json::json!({"dispatch_steps": 2000}),
        "{written}"
    );
    for (opts, limit) in [
        ("", 2000),
        (", {dispatch_steps: 1500}", 1500),
        (", {dispatch_steps: 100_000}", 2000),
    ] {
        let dir = project(
            &format!("dispatch-{limit}-{}", opts.len()),
            declared,
            &served(opts),
        );
        let ran = run(&dir, None);
        assert!(
            out(&ran).contains(&format!(
                "[:runaway, execution budget exhausted: steps per dispatch (limit {limit})]"
            )),
            "{opts}: {}{}",
            out(&ran),
            err(&ran)
        );
        assert!(!err(&ran).contains("formatted"), "{}", err(&ran));
    }
    let narrowed = project(
        "dispatch-spawned",
        "package(\"srv\", \"0.1.0\")\n",
        &served(", {dispatch_steps: 1500}"),
    );
    let ran = run(&narrowed, None);
    assert!(
        out(&ran).contains("steps per dispatch (limit 1500)"),
        "{}{}",
        out(&ran),
        err(&ran)
    );
}
