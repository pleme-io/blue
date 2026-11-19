use std::path::{Path, PathBuf};
use std::process::Command;

const PAIRS: &[(&str, &str, &str)] = &[
    (
        "a fused chain against the chain",
        "reduce(fn(a, x)\n    if x % 2 == 0\n      a + x * 3\n    else\n      a\n    end\n  end, 0, xs)",
        "reduce((a, x) -> a + x, 0, filter((x) -> x % 2 == 0, map((x) -> x * 3, xs)))",
    ),
    (
        "a length against the length of a map",
        "length(xs)",
        "length(map((x) -> x + 1, xs))",
    ),
    (
        "a list against the list reversed twice",
        "xs",
        "reverse(reverse(xs))",
    ),
    (
        "one map against two",
        "map((x) -> x * 6, xs)",
        "map((x) -> x * 2, map((x) -> x * 3, xs))",
    ),
];

fn dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("blue-cost-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).expect("dir");
    d
}

fn blue(cwd: &Path, cache: &Path) -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env("XDG_CACHE_HOME", cache)
        .current_dir(cwd);
    c
}

fn field(text: &str, name: &str) -> f64 {
    text.lines()
        .find_map(|l| {
            l.strip_prefix(name)?
                .split_whitespace()
                .next()?
                .parse()
                .ok()
        })
        .unwrap_or_else(|| panic!("no `{name}` in:\n{text}"))
}

fn measured(cwd: &Path, cache: &Path, form: &str, weight: f64) -> f64 {
    let file = cwd.join("measured.b");
    std::fs::write(&file, format!("xs = range(1000)\nkeep = {form}\n")).expect("write");
    let out = blue(cwd, cache)
        .envs([
            ("BLUE_DOOR", "walker"),
            ("BLUE_MEMO", "off"),
            ("BLUE_NATIVE", "off"),
            ("BLUE_FUSE", "off"),
            ("BLUE_FOLD", "off"),
            ("BLUE_INDEX", "off"),
        ])
        .args(["run", "--quiet", "--timings"])
        .arg(&file)
        .output()
        .expect("spawn blue");
    let report = String::from_utf8_lossy(&out.stderr);
    assert!(out.status.success(), "{report}");
    field(&report, "steps ") + weight * field(&report, "allocs ")
}

fn predicted(cwd: &Path, cache: &Path, cheaper: &str, dearer: &str) -> (f64, f64, f64) {
    let file = cwd.join("pair.b");
    std::fs::write(
        &file,
        format!("def cheaper(xs)\n  {cheaper}\nend\n\ndef dearer(xs)\n  {dearer}\nend\n"),
    )
    .expect("write");
    let out = blue(cwd, cache)
        .arg("cost")
        .arg(&file)
        .output()
        .expect("spawn blue");
    let text = String::from_utf8_lossy(&out.stdout).into_owned();
    assert!(
        out.status.success(),
        "{text}{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let weight: f64 = text
        .split("an allocation weighs ")
        .nth(1)
        .and_then(|r| r.split_whitespace().next()?.parse().ok())
        .unwrap_or_else(|| panic!("no weight in:\n{text}"));
    let units = |name: &str| {
        text.lines()
            .find(|l| l.trim_end().ends_with(&format!("  {name}")))
            .and_then(|l| l.split_whitespace().next()?.parse::<f64>().ok())
            .unwrap_or_else(|| panic!("no `{name}` in:\n{text}"))
    };
    (units("cheaper"), units("dearer"), weight)
}

#[test]
fn the_cost_model_orders_equal_forms_as_they_measure() {
    let cwd = dir("pairs");
    let cache = cwd.join("cache");
    let mut wrong = Vec::new();
    for (what, cheaper, dearer) in PAIRS {
        let (p_cheap, p_dear, weight) = predicted(&cwd, &cache, cheaper, dearer);
        let (m_cheap, m_dear) = (
            measured(&cwd, &cache, cheaper, weight),
            measured(&cwd, &cache, dearer, weight),
        );
        assert!(
            m_cheap < m_dear,
            "{what}: the pair is not ordered as written ({m_cheap} against {m_dear})"
        );
        if p_cheap >= p_dear {
            wrong.push(format!(
                "{what}: predicted {p_cheap} against {p_dear}, measured {m_cheap} against {m_dear}"
            ));
        }
    }
    assert!(wrong.is_empty(), "{}", wrong.join("\n"));
    let _ = std::fs::remove_dir_all(&cwd);
}

#[test]
fn the_table_is_measured_once_and_read_after() {
    let cwd = dir("once");
    let cache = cwd.join("cache");
    std::fs::write(cwd.join("one.b"), "def one(xs)\n  length(xs)\nend\n").expect("write");
    let first = blue(&cwd, &cache)
        .args(["cost", "one.b"])
        .output()
        .expect("spawn");
    assert!(first.status.success());
    let kept: Vec<_> = std::fs::read_dir(cache.join("blue/cost"))
        .expect("the table is kept")
        .collect();
    assert_eq!(kept.len(), 1);
    let second = blue(&cwd, &cache)
        .args(["cost", "one.b"])
        .output()
        .expect("spawn");
    assert_eq!(
        String::from_utf8_lossy(&first.stdout).lines().nth(2),
        String::from_utf8_lossy(&second.stdout).lines().nth(2),
        "the second run prices from the kept table"
    );
    let _ = std::fs::remove_dir_all(&cwd);
}
