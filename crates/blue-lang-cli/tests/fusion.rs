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
