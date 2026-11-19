use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const MAIN: &str = "@moduledoc \"\"\"\nburn spreads work over processes.\n\n    burn(0, 0, 3) #=> 5\n\"\"\"\n\n@doc \"\"\"\nburn: the sum of squares below n, modulo a prime.\n\n    burn(0, 0, 2) #=> 1\n\"\"\"\ndef burn(i, acc, n)\n  if i == n\n    acc\n  else\n    burn(i + 1, (acc + i * i) % 1000003, n)\n  end\nend\n\n@doc \"\"\"\nwork: burn for k, sent to root.\n\n    1 #=> 1\n\"\"\"\ndef work(root, k)\n  send(root, [k, burn(0, k, 400000)])\nend\n\ndef main()\n  me = self()\n  map((k) -> spawn(work, [me, k]), [1, 2, 3, 4])\n  write_stdout(to_s(map((k) -> receive([k, :_]), [1, 2, 3, 4])))\nend\n";

fn blue(dir: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env("BLUE_MEMO", "off")
        .env("BLUE_NATIVE", "off")
        .env("XDG_CACHE_HOME", dir.join("cache"))
        .current_dir(dir)
        .args(args)
        .output()
        .expect("spawn blue")
}

fn project(name: &str, word: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-schedulers-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("dir");
    std::fs::write(
        dir.join("Bluefile"),
        format!("package(\"burn\", \"0.1.0\")\napp(\"burn\", \"main.b\")\n{word}"),
    )
    .expect("Bluefile");
    std::fs::write(dir.join("main.b"), MAIN).expect("main");
    let locked = blue(&dir, &["lock", "."]);
    assert!(
        locked.status.success(),
        "{}",
        String::from_utf8_lossy(&locked.stderr)
    );
    dir
}

fn ran(dir: &Path) -> String {
    let out = blue(dir, &["run", "--quiet", "main.b"]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

#[test]
fn a_project_that_declares_schedulers_gives_the_same_answers_as_one_scheduler() {
    let one = project("one", "");
    let four = project("four", "schedulers(4)\n");
    let alone = ran(&one);
    let together = ran(&four);
    assert_eq!(
        alone, together,
        "A-parity across schedulers(1) and schedulers(4)"
    );
    assert!(alone.starts_with("[[1, "), "{alone}");
    let _ = std::fs::remove_dir_all(&one);
    let _ = std::fs::remove_dir_all(&four);
}

const PAR_MAIN: &str = "def main()\n  write_stdout(to_s(par_map((k) -> burn(0, k, 200000), [1, 2, 3, 4, 5, 6, 7, 8])))\nend\n";

fn timed(dir: &Path) -> (String, String) {
    timed_with(dir, PAR_MAIN, &[])
}

fn timed_with(dir: &Path, main: &str, env: &[(&str, &str)]) -> (String, String) {
    let main_at = MAIN.find("def main()").expect("MAIN ends in main");
    std::fs::write(dir.join("main.b"), format!("{}{main}", &MAIN[..main_at])).expect("main");
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_blue"));
    cmd.env_remove("BLUE_PATH")
        .env("BLUE_MEMO", "off")
        .env("BLUE_NATIVE", "off")
        .env("XDG_CACHE_HOME", dir.join("cache"))
        .current_dir(dir)
        .args(["run", "--quiet", "--timings", "main.b"]);
    for (k, v) in env {
        cmd.env(k, v);
    }
    let out = cmd.output().expect("spawn blue");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    (
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

#[test]
fn par_map_runs_apart_on_a_project_s_schedulers_and_answers_as_map_does() {
    let one = project("par-one", "");
    let four = project("par-four", "schedulers(4)\n");
    let (alone, alone_timings) = timed(&one);
    let (together, together_timings) = timed(&four);
    assert_eq!(alone, together, "par_map answers as map does");
    assert!(alone.starts_with("[784003, 784004, "), "{alone}");
    let parallel = ran_apart;
    assert!(
        !parallel(&alone_timings),
        "one scheduler maps at home: {alone_timings}"
    );
    assert!(
        parallel(&together_timings),
        "four schedulers map apart: {together_timings}"
    );
    let _ = std::fs::remove_dir_all(&one);
    let _ = std::fs::remove_dir_all(&four);
}

fn ran_apart(timings: &str) -> bool {
    timings
        .lines()
        .any(|l| l.starts_with("parallel") && !l.trim_end().ends_with(" 0"))
}

const MAP_MAIN: &str = "def main()\n  write_stdout(to_s(map((k) -> burn(0, k, 200000), [1, 2, 3, 4, 5, 6, 7, 8])))\nend\n";

const PRINTING_MAIN: &str = "def main()\n  write_stdout(to_s(map(fn(k)\n    write_stdout(\"\")\n    burn(0, k, 200000)\n  end, [1, 2, 3, 4, 5, 6, 7, 8])))\nend\n";

#[test]
fn rule_r17_runs_a_map_whose_callback_only_computes_apart_and_its_switch_keeps_it_home() {
    let four = project("r17", "schedulers(4)\n");
    let (apart, apart_timings) = timed_with(&four, MAP_MAIN, &[]);
    let (home, home_timings) = timed_with(&four, MAP_MAIN, &[("BLUE_PARMAP", "off")]);
    assert_eq!(apart, home, "R17 answers as map does");
    assert!(ran_apart(&apart_timings), "{apart_timings}");
    assert!(!ran_apart(&home_timings), "BLUE_PARMAP=off: {home_timings}");
    let (_, printing) = timed_with(&four, PRINTING_MAIN, &[]);
    assert!(
        !ran_apart(&printing),
        "a callback with an effect keeps its order: {printing}"
    );
    let _ = std::fs::remove_dir_all(&four);
}
