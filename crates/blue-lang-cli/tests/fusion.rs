use std::path::PathBuf;
use std::process::Command;

const CHAIN: &str = "write_stdout(\n  unlines(\n    [\n      reduce(\n        (a, x) -> a + x,\n        0,\n        filter((x) -> x % 2 == 0, map((x) -> x * 3, range(20_000)))\n      )\n    ]\n  )\n)\n";

fn fixture() -> PathBuf {
    let d = std::env::temp_dir().join(format!("blue-fusion-test-{}", std::process::id()));
    std::fs::create_dir_all(&d).expect("scratch dir");
    let p = d.join("chain.b");
    std::fs::write(&p, CHAIN).expect("write fixture");
    p
}

struct Ran {
    stdout: String,
    allocs: u64,
    fused: Option<String>,
}

fn run(fuse: &str, door: &str) -> Ran {
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_DOOR")
        .env("BLUE_MEMO", "off")
        .env("BLUE_FUSE", fuse)
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
        allocs: row("allocs").and_then(|n| n.parse().ok()).unwrap_or(0),
        fused: row("fused"),
    }
}

#[test]
fn a_pure_chain_runs_fused_with_fewer_allocations_and_the_same_output_on_both_doors() {
    for door in ["vm", "walker"] {
        let on = run("on", door);
        let off = run("off", door);
        assert_eq!(on.stdout, off.stdout, "{door}");
        assert_eq!(on.stdout, "299970000\n", "{door}");
        assert_eq!(
            on.fused.as_deref(),
            Some("1 reduce∘filter∘map"),
            "{door}: the rewrite did not run"
        );
        assert_eq!(off.fused, None, "{door}: BLUE_FUSE=off still fused");
        if on.allocs > 0 {
            assert!(
                on.allocs < off.allocs,
                "{door}: fused {} allocations, unfused {}",
                on.allocs,
                off.allocs
            );
        }
    }
}

const ARMS: &str = "@doc \"\"\"\nparity: the sum of 0 for each even and 1 for each odd number.\n\n    parity([1, 2, 3]) #=> 2\n\"\"\"\ndef parity(xs)\n  reduce(\n    (a, x) -> a + x,\n    0,\n    map(\n      (x) ->\n        if x % 2 == 0\n          0\n        else\n          1\n        end,\n      xs\n    )\n  )\nend\n\ntest \"parity counts the odd numbers\"\n  assert parity([1, 2, 3, 4]) == 2\nend\n";

#[test]
fn coverage_sees_each_arm_where_it_is_written_not_inside_a_fused_pass() {
    let d = std::env::temp_dir().join(format!("blue-fusion-cov-{}", std::process::id()));
    std::fs::create_dir_all(&d).expect("scratch dir");
    let p = d.join("arms.b");
    std::fs::write(&p, ARMS).expect("write fixture");
    let formatted = Command::new(env!("CARGO_BIN_EXE_blue"))
        .args(["fmt", "--write"])
        .arg(&p)
        .output()
        .expect("spawn blue fmt");
    assert!(
        formatted.status.success(),
        "{}",
        String::from_utf8_lossy(&formatted.stderr)
    );
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_FUSE")
        .args(["test", "--coverage", "--json"])
        .arg(&p)
        .output()
        .expect("spawn blue");
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let row = stdout
        .lines()
        .find(|l| l.trim_start().starts_with('{'))
        .expect("a coverage row");
    let doc: serde_json::Value = serde_json::from_str(row).expect("coverage JSON");
    assert_eq!(doc["untaken"], serde_json::json!([]), "{row}");
}
