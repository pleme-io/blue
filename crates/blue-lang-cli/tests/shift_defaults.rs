use std::process::Command;

const PROGRAM: &str = "def fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n\ndef area(w, h)\n  w * h\nend\n\ndef total(xs, allowed)\n  map((x) -> x + area(3, 4), filter((x) -> member?(x, allowed), xs))\nend\n\ndef walk(n)\n  if n < 2\n    now_ms\n  else\n    walk(n - 1) + walk(n - 2)\n  end\nend\n\ndef main()\n  write_stdout(to_s(total([1, 2, 3], [2, 3])))\nend\n";

struct Scratch(std::path::PathBuf);

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn scratch(tag: &str) -> Scratch {
    let d = std::env::temp_dir().join(format!("blue-shift-defaults-{}-{tag}", std::process::id()));
    std::fs::create_dir_all(d.join("cache")).expect("scratch");
    std::fs::write(d.join("d.b"), PROGRAM).expect("program");
    Scratch(d)
}

fn blue(d: &Scratch, switches: &[(&str, &str)], args: &[&str]) -> std::process::Output {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_DOOR")
        .env_remove("BLUE_MEMO")
        .env_remove("BLUE_NATIVE")
        .env_remove("BLUE_FOLD")
        .env_remove("BLUE_INDEX")
        .env_remove("BLUE_FUSE")
        .env_remove("BLUE_CACHE_SHARED")
        .env("XDG_CACHE_HOME", d.0.join("cache"));
    for (k, v) in switches {
        c.env(k, v);
    }
    c.args(args)
        .arg(d.0.join("d.b"))
        .output()
        .expect("spawn blue")
}

fn report(d: &Scratch, switches: &[(&str, &str)]) -> serde_json::Value {
    let out = blue(d, switches, &["shift", "--defaults", "--json"]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    serde_json::from_slice(&out.stdout).expect("one JSON object")
}

fn rules<'a>(r: &'a serde_json::Value, name: &str) -> Vec<(&'a str, bool)> {
    r["definitions"]
        .as_array()
        .expect("definitions")
        .iter()
        .find(|d| d["name"] == name)
        .unwrap_or_else(|| panic!("no definition {name} in {r}"))["rules"]
        .as_array()
        .expect("rules")
        .iter()
        .map(|x| {
            (
                x["rule"].as_str().expect("id"),
                x["fires"].as_bool().expect("fires"),
            )
        })
        .collect()
}

#[test]
fn each_definition_names_its_facts_and_the_defaults_they_fire() {
    let d = scratch("facts");
    let r = report(&d, &[]);
    assert_eq!(rules(&r, "fib"), vec![("R2", true)], "{r}");
    assert_eq!(rules(&r, "area"), vec![], "{r}");
    assert_eq!(rules(&r, "total"), vec![("R4", true), ("R10", true)], "{r}");
    assert_eq!(rules(&r, "walk"), vec![("R2", false)], "{r}");
    let walk = r["definitions"]
        .as_array()
        .expect("definitions")
        .iter()
        .find(|x| x["name"] == "walk")
        .expect("walk");
    assert!(
        walk["rules"][0]["missing"]
            .as_str()
            .expect("the missing fact")
            .contains("now_ms"),
        "{r}"
    );
    assert!(
        r["definitions"]
            .as_array()
            .expect("definitions")
            .iter()
            .all(|x| x["key"].as_str().expect("key").starts_with("%root/")),
        "{r}"
    );
    let text = blue(&d, &[], &["shift", "--defaults"]);
    let text = String::from_utf8_lossy(&text.stdout);
    assert!(
        text.contains("✅ R10") && text.contains("⚠️ R2  missing: it is not pure"),
        "{text}"
    );
}

#[test]
fn the_report_says_what_the_run_does_under_each_switch() {
    let d = scratch("agree");
    for (switches, folds, indexes) in [
        (vec![], true, true),
        (vec![("BLUE_FOLD", "off")], false, true),
        (vec![("BLUE_INDEX", "off")], true, false),
    ] {
        let whole = report(&d, &switches);
        let r = rules(&whole, "total");
        let run = blue(&d, &switches, &["run", "--quiet", "--timings"]);
        assert!(
            run.status.success(),
            "{}",
            String::from_utf8_lossy(&run.stderr)
        );
        let timings = String::from_utf8_lossy(&run.stderr).into_owned();
        let row = |name: &str| {
            timings
                .lines()
                .any(|l| l.split_whitespace().next() == Some(name))
        };
        assert_eq!(r.contains(&("R4", true)), folds, "{switches:?}: {r:?}");
        assert_eq!(row("folded"), folds, "{switches:?}: {timings}");
        assert_eq!(r.contains(&("R10", true)), indexes, "{switches:?}: {r:?}");
        assert_eq!(row("indexed"), indexes, "{switches:?}: {timings}");
    }
}

#[test]
fn a_file_that_fails_the_check_stage_is_refused() {
    let d = scratch("refused");
    std::fs::write(d.0.join("d.b"), "def f(x)\n  y\nend\n").expect("program");
    let out = blue(&d, &[], &["shift", "--defaults"]);
    assert!(!out.status.success());
}
