use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_MEMO")
        .env_remove("BLUE_DOOR")
        .env_remove("BLUE_WITNESS");
    c
}

fn dir(name: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("blue-door-test-{name}"));
    let _ = std::fs::remove_dir_all(&p);
    std::fs::create_dir_all(&p).expect("scratch dir");
    p
}

fn write(dir: &Path, rel: &str, src: &str) -> PathBuf {
    let p = dir.join(rel);
    std::fs::write(&p, src).expect("write fixture");
    p
}

fn door_of(receipt: &Path) -> serde_json::Value {
    serde_json::from_slice(&std::fs::read(receipt).expect("the door receipt")).expect("door JSON")
}

fn run_with(file: &Path, receipt: &Path, env: Option<(&str, &str)>) -> Output {
    let mut c = blue();
    if let Some((k, v)) = env {
        c.env(k, v);
    }
    c.arg("run")
        .arg("--door-receipt")
        .arg(receipt)
        .arg(file)
        .output()
        .expect("spawn blue")
}

const AGREED: &str = "def fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n\ndef main()\n  [fib(15), count([1, 2, 3]), \"#{fib(5)}\"]\nend\n";

const DISAGREEING: &str = "def main()\n  procedure?(1)\nend\n";

#[test]
fn a_program_of_agreed_constructs_runs_on_the_vm_with_the_walkers_output() {
    let d = dir("agreed");
    let file = write(&d, "agreed.b", AGREED);
    let auto = run_with(&file, &d.join("auto"), None);
    assert!(
        auto.status.success(),
        "{}",
        String::from_utf8_lossy(&auto.stderr)
    );
    let door = door_of(&d.join("auto"));
    assert_eq!(door["door"], "vm", "{door}");
    assert!(door["why"].as_str().unwrap().contains("agreed"), "{door}");
    let walker = run_with(&file, &d.join("walker"), Some(("BLUE_DOOR", "walker")));
    assert!(walker.status.success());
    assert_eq!(door_of(&d.join("walker"))["door"], "walker");
    assert_eq!(auto.stdout, walker.stdout);
    assert_eq!(String::from_utf8_lossy(&auto.stdout), "[610, 3, 5]\n");
}

#[test]
fn a_program_using_a_disagreeing_construct_falls_back_and_names_its_row() {
    let d = dir("disagreeing");
    let file = write(&d, "disagreeing.b", DISAGREEING);
    let out = run_with(&file, &d.join("r"), None);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let door = door_of(&d.join("r"));
    assert_eq!(door["door"], "walker", "{door}");
    let why = door["why"].as_str().unwrap();
    assert!(
        why.contains("pred.procedure") && why.contains("G18"),
        "{why}"
    );
}

#[test]
fn a_call_through_a_value_and_a_lambda_argument_stay_on_the_walker() {
    let d = dir("values");
    let through = write(&d, "through.b", "def f(a, b)\n  a\nend\n\ng = f\ng(1, 2)\n");
    let out = run_with(&through, &d.join("t"), None);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(door_of(&d.join("t"))["why"]
        .as_str()
        .unwrap()
        .contains("fn.arity"));
    let lambda = write(&d, "lambda.b", "map((x) -> x * 2, [1, 2])\n");
    let out = run_with(&lambda, &d.join("l"), None);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let door = door_of(&d.join("l"));
    assert_eq!(door["door"], "walker");
    assert!(door["why"].as_str().unwrap().contains("slower"), "{door}");
}

#[test]
fn the_door_is_named_under_timings_and_the_memo_holds_it_to_the_walker() {
    let d = dir("timings");
    let file = write(&d, "agreed.b", AGREED);
    let out = blue()
        .arg("run")
        .arg("--timings")
        .arg(&file)
        .output()
        .expect("spawn");
    assert!(String::from_utf8_lossy(&out.stderr).contains("door     vm"));
    let out = blue()
        .env("BLUE_MEMO", "process")
        .arg("run")
        .arg("--door-receipt")
        .arg(d.join("m"))
        .arg(&file)
        .output()
        .expect("spawn");
    assert!(out.status.success());
    let door = door_of(&d.join("m"));
    assert_eq!(door["door"], "walker");
    assert!(door["why"].as_str().unwrap().contains("memo"));
}

#[test]
fn a_fault_on_the_vm_runs_again_on_the_walker_with_its_place_and_its_output_once() {
    let d = dir("fault");
    let file = write(
        &d,
        "fault.b",
        "def boom(n)\n  if n == 0\n    raise(:boom, \"at the bottom\")\n  else\n    boom(n - 1)\n  end\nend\n\nwrite_stdout(\"before\\n\")\nboom(3)\n",
    );
    let out = run_with(&file, &d.join("r"), None);
    assert!(!out.status.success());
    assert_eq!(String::from_utf8_lossy(&out.stdout), "before\n");
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("fault.b:3:"), "{err}");
    let door = door_of(&d.join("r"));
    assert_eq!(door["door"], "walker", "{door}");
    assert!(
        door["why"].as_str().unwrap().contains("vm raised"),
        "{door}"
    );
}

#[test]
fn a_program_that_reaches_the_host_stays_on_the_walker() {
    let d = dir("host");
    let file = write(&d, "host.b", "length(getenv(\"HOME\") or \"\")\n");
    let out = run_with(&file, &d.join("r"), None);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let door = door_of(&d.join("r"));
    assert_eq!(door["door"], "walker", "{door}");
    assert!(
        door["why"].as_str().unwrap().contains("host effect"),
        "{door}"
    );
}
