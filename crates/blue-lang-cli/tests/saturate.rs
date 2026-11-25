use std::path::{Path, PathBuf};
use std::process::Command;

const MAIN: &str = "def total(xs)\n  reduce((a, x) -> a + x, 0, filter((x) -> x % 2 == 0, map((x) -> x * 3, xs)))\nend\n\ndef main()\n  write_stdout(to_s(total(range(100))))\nend\n";

const EFFECTS: &str = "def pad()\n  0\nend\n\ndef shout(x)\n  write_stdout(unlines([\"map #{x}\"]))\n  x * 10\nend\n\ndef check(x)\n  write_stdout(unlines([\"filter #{x}\"]))\n  x > 10\nend\n\ndef tally(xs)\n  reduce((a, x) -> a + x, 0, filter(check, map(shout, xs)))\nend\n\ndef main()\n  write_stdout(to_s(tally([1, 2, 3])))\nend\n";

fn dir(name: &str, main: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("blue-saturate-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).expect("dir");
    std::fs::write(d.join("main.b"), main).expect("write");
    d
}

fn blue(d: &Path, args: &[&str], env: &[(&str, &str)]) -> (String, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env("BLUE_MEMO", "off")
        .env("BLUE_NATIVE", "off")
        .env("XDG_CACHE_HOME", d.join("cache"))
        .envs(env.iter().copied())
        .current_dir(d)
        .args(args)
        .output()
        .expect("spawn blue");
    let err = String::from_utf8_lossy(&out.stderr).into_owned();
    assert!(out.status.success(), "{err}");
    (String::from_utf8_lossy(&out.stdout).into_owned(), err)
}

fn row(timings: &str, name: &str) -> Option<String> {
    timings
        .lines()
        .find(|l| l.starts_with(name))
        .map(|l| l[name.len()..].trim().to_string())
}

fn saturated(timings: &str) -> bool {
    row(timings, "saturated").is_some_and(|v| v != "0")
}

#[test]
fn rule_r19_decides_a_chain_by_the_measured_table_once_and_its_switch_hands_it_back_to_fusion() {
    let d = dir("decides", MAIN);
    let run = |env: &[(&str, &str)]| blue(&d, &["run", "--quiet", "--timings", "main.b"], env);

    let (answer, before) = run(&[]);
    assert!(!saturated(&before), "no table is measured yet: {before}");
    assert!(
        row(&before, "fused").is_some_and(|f| f.contains("reduce∘filter∘map")),
        "{before}"
    );

    blue(&d, &["cost", "main.b"], &[]);
    let (first, decided) = run(&[]);
    assert_eq!(first, answer);
    assert!(saturated(&decided), "the table is measured: {decided}");
    assert!(
        row(&decided, "fused").is_some_and(|f| f.contains("reduce∘filter∘map")),
        "{decided}"
    );

    let (again, recalled) = run(&[]);
    assert_eq!(again, answer);
    assert!(
        !saturated(&recalled),
        "the decision is recalled, not made again: {recalled}"
    );
    assert!(
        row(&recalled, "fused").is_some_and(|f| f.contains("reduce∘filter∘map")),
        "{recalled}"
    );

    let (off, switched) = run(&[("BLUE_SATURATE", "off")]);
    assert_eq!(off, answer);
    assert!(!saturated(&switched), "{switched}");
    assert!(
        row(&switched, "fused").is_some_and(|f| f.contains("reduce∘filter∘map")),
        "fusion fuses: {switched}"
    );
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn rule_r19_leaves_a_chain_whose_callbacks_write_in_the_order_it_is_written() {
    let d = dir("effects", EFFECTS);
    let run = |env: &[(&str, &str)]| blue(&d, &["run", "--quiet", "--timings", "main.b"], env);
    let written = "map 1\nmap 2\nmap 3\nfilter 10\nfilter 20\nfilter 30\n50";

    let (before, _) = run(&[]);
    assert_eq!(before, written);

    blue(&d, &["cost", "main.b"], &[]);
    let (measured, timings) = run(&[]);
    assert_eq!(measured, written, "{timings}");
    assert!(!saturated(&timings), "{timings}");
    assert!(row(&timings, "fused").is_none(), "{timings}");
    let _ = std::fs::remove_dir_all(&d);
}
