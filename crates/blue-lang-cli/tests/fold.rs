use std::path::PathBuf;
use std::process::Command;

const LOOP: &str = "def weight(n)\n  reduce((a, x) -> a + x * x, 0, range(n))\nend\n\ndef score(xs)\n  map((x) -> x + weight(40), xs)\nend\n\ndef main()\n  write_stdout(to_s(reduce((a, x) -> a + x, 0, score(range(5_000)))))\nend\n";

fn fixture() -> PathBuf {
    let d = std::env::temp_dir().join(format!("blue-fold-test-{}", std::process::id()));
    std::fs::create_dir_all(&d).expect("scratch dir");
    let p = d.join("loop.b");
    std::fs::write(&p, LOOP).expect("write fixture");
    p
}

struct Ran {
    stdout: String,
    steps: u64,
    folded: Option<String>,
}

fn run(fold: &str, door: &str) -> Ran {
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_DOOR")
        .env("BLUE_MEMO", "off")
        .env("BLUE_FOLD", fold)
        .args(["run", "--quiet", "--timings", "--door", door])
        .arg(fixture())
        .output()
        .expect("spawn blue");
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    assert!(out.status.success(), "{stderr}");
    let row = |name: &str| {
        stderr
            .lines()
            .find_map(|l| l.strip_prefix(name).map(|r| r.trim().to_string()))
    };
    Ran {
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        steps: row("steps").and_then(|n| n.parse().ok()).unwrap_or(0),
        folded: row("folded"),
    }
}

#[test]
fn a_pure_call_on_literals_in_a_loop_runs_once_before_the_run_with_the_same_output() {
    for door in ["vm", "walker"] {
        let on = run("on", door);
        let off = run("off", door);
        assert_eq!(on.stdout, off.stdout, "{door}");
        assert_eq!(on.stdout, "115197500", "{door}");
        assert_eq!(
            on.folded.as_deref(),
            Some("1 %root/weight"),
            "{door}: the rewrite did not run"
        );
        assert_eq!(off.folded, None, "{door}: BLUE_FOLD=off still folded");
        if door == "walker" {
            assert!(
                on.steps * 4 < off.steps,
                "{door}: folded {} steps, unfolded {}",
                on.steps,
                off.steps
            );
        }
    }
}
