use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn blue_in(dir: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_DIST")
        .env("BLUE_PATH", repo().join("bidamas"))
        .current_dir(dir)
        .args(args)
        .output()
        .expect("spawn")
}

fn census(dir: &Path, flags: &[&str]) -> Output {
    let mut args = vec!["census", "--reuse", "."];
    args.extend_from_slice(flags);
    blue_in(dir, &args)
}

fn text(out: &Output) -> String {
    String::from_utf8_lossy(&out.stdout).into_owned()
}

fn code(out: &Output) -> i32 {
    out.status.code().unwrap_or(-1)
}

struct Project(PathBuf);

impl Project {
    fn new(name: &str) -> Self {
        let dir =
            std::env::temp_dir().join(format!("blue-census-reuse-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("mkdir");
        Project(dir)
    }

    fn write(&self, file: &str, source: &str) {
        std::fs::write(self.0.join(file), source).expect("write");
    }

    fn remove(&self, file: &str) {
        std::fs::remove_file(self.0.join(file)).expect("remove");
    }

    fn baseline(&self) -> String {
        std::fs::read_to_string(self.0.join("reuse.baseline")).unwrap_or_default()
    }

    fn recorded(self) -> Self {
        let out = census(&self.0, &["--record", "--receipt", "first measure"]);
        assert_eq!(code(&out), 0, "{}", text(&out));
        self
    }
}

impl Drop for Project {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

const SPREAD: &str = "def spread(xs)\n  map((x) -> x * 2 + 1, xs)\nend\n";
const WIDEN: &str = "def widen(ys)\n  map((y) -> y * 3 + 7, ys)\nend\n";
const OWN: &str = "def own(z)\n  z\nend\n";

fn twins(name: &str) -> Project {
    let p = Project::new(name);
    p.write("one.b", SPREAD);
    p.write("two.b", SPREAD);
    p
}

#[test]
fn an_absent_baseline_enforces_nothing_and_names_how_to_adopt() {
    let p = twins("absent");
    let out = census(&p.0, &[]);
    assert_eq!(code(&out), 0, "{}", text(&out));
    let shown = text(&out);
    assert!(shown.contains("2 copies"), "{shown}");
    assert!(shown.contains("--record --receipt"), "{shown}");
    assert!(p.baseline().is_empty(), "a check never writes the baseline");
}

#[test]
fn a_first_record_needs_a_receipt_and_then_holds() {
    let p = twins("first");
    let refused = census(&p.0, &["--record"]);
    assert_eq!(code(&refused), 1, "{}", text(&refused));
    assert!(text(&refused).contains("needs a reason"));
    assert!(p.baseline().is_empty(), "a refused record writes nothing");
    let p = p.recorded();
    assert_eq!(
        p.baseline(),
        "# receipt: first measure\nreuse-copy: %root:one.b 1\nreuse-copy: %root:two.b 1\n"
    );
    let held = census(&p.0, &[]);
    assert_eq!(code(&held), 0, "{}", text(&held));
    assert!(text(&held).contains("0 grew or new, 0 shrunk, 0 gone"));
}

#[test]
fn a_grown_or_new_row_fails_and_names_only_its_own_copies() {
    let p = twins("grown").recorded();
    p.write("one.b", &format!("{SPREAD}\n{WIDEN}"));
    p.write("three.b", WIDEN);
    let out = census(&p.0, &[]);
    let shown = text(&out);
    assert_eq!(code(&out), 1, "{shown}");
    assert!(
        shown.contains("%root:one.b measures 2, past its recorded 1 by 1"),
        "{shown}"
    );
    assert!(
        shown.contains("%root:three.b measures 1 and the baseline has no row"),
        "{shown}"
    );
    assert!(shown.contains("three.b:1 def widen [promote]"), "{shown}");
    assert!(
        !shown.contains("two.b:1 def spread"),
        "a held row is not the fault: {shown}"
    );
}

#[test]
fn run_and_test_still_work_on_a_tree_the_ratchet_refuses() {
    let p = twins("doors").recorded();
    let src = format!(
        "{WIDEN}\ndef main()\n  write_stdout(to_s(first(widen([1]))))\nend\n\n\
         test \"widens\"\n  assert widen([1]) == [10]\nend\n"
    );
    p.write("three.b", &src);
    p.write("four.b", WIDEN);
    assert_eq!(code(&census(&p.0, &[])), 1);
    let ran = blue_in(&p.0, &["run", "three.b"]);
    assert_eq!(code(&ran), 0, "{}", String::from_utf8_lossy(&ran.stderr));
    assert!(text(&ran).starts_with("10"), "{}", text(&ran));
    let tested = blue_in(&p.0, &["test", "three.b"]);
    assert_eq!(code(&tested), 0, "{}", text(&tested));
}

#[test]
fn a_shrink_passes_and_record_banks_it_without_a_receipt() {
    let p = Project::new("shrink");
    p.write("one.b", &format!("{SPREAD}\n{WIDEN}"));
    p.write("two.b", &format!("{SPREAD}\n{WIDEN}"));
    let p = p.recorded();
    p.write("one.b", SPREAD);
    p.write("two.b", &format!("{SPREAD}\n{OWN}"));
    p.write("three.b", OWN);
    let out = census(&p.0, &[]);
    let shown = text(&out);
    assert_eq!(code(&out), 0, "{shown}");
    assert!(shown.contains("2 shrunk"), "{shown}");
    assert!(
        shown.contains("bank it: blue census --reuse . --record"),
        "{shown}"
    );
    let banked = census(&p.0, &["--record"]);
    assert_eq!(code(&banked), 0, "{}", text(&banked));
    assert_eq!(
        p.baseline(),
        "# receipt: first measure\nreuse-copy: %root:one.b 1\nreuse-copy: %root:two.b 1\n"
    );
}

#[test]
fn a_gone_row_is_advisory_and_record_drops_it() {
    let p = twins("gone").recorded();
    p.remove("two.b");
    let out = census(&p.0, &[]);
    let shown = text(&out);
    assert_eq!(code(&out), 0, "{shown}");
    assert!(shown.contains("2 gone"), "{shown}");
    assert_eq!(code(&census(&p.0, &["--record"])), 0);
    assert_eq!(p.baseline(), "# receipt: first measure\n");
}

#[test]
fn a_raise_needs_a_receipt_and_keeps_it_beside_the_row() {
    let p = twins("raise").recorded();
    p.write("one.b", &format!("{SPREAD}\n{WIDEN}"));
    p.write("two.b", &format!("{SPREAD}\n{WIDEN}"));
    let before = p.baseline();
    let refused = census(&p.0, &["--record"]);
    assert_eq!(code(&refused), 1, "{}", text(&refused));
    assert_eq!(p.baseline(), before, "a refused raise leaves the file");
    let raised = census(&p.0, &["--record", "--receipt", "a vendored pair"]);
    assert_eq!(code(&raised), 0, "{}", text(&raised));
    assert_eq!(
        p.baseline(),
        "# receipt: first measure\n# receipt: a vendored pair\n\
         reuse-copy: %root:one.b 2\nreuse-copy: %root:two.b 2\n"
    );
}

#[test]
fn a_file_that_cannot_load_is_blind_and_reads_as_no_zero() {
    let p = twins("blind").recorded();
    p.write(
        "broken.b",
        "use(\"no_such_bidama\")\n\nno_such_bidama::x(1)\n",
    );
    let out = census(&p.0, &[]);
    let shown = text(&out);
    assert_eq!(code(&out), 0, "{shown}");
    assert!(shown.contains("1 blind"), "{shown}");
    assert!(shown.contains("blind: broken.b:"), "{shown}");
}

#[test]
fn json_carries_the_rows_and_each_home_and_exits_as_the_check_does() {
    let p = twins("json").recorded();
    p.write("three.b", SPREAD);
    let out = census(&p.0, &["--json"]);
    assert_eq!(code(&out), 1, "{}", text(&out));
    let doc: serde_json::Value = serde_json::from_str(text(&out).trim()).expect("one document");
    assert_eq!(doc["adopted"], true);
    assert_eq!(doc["copies"], 3);
    assert_eq!(doc["definitions"], 3);
    assert_eq!(doc["broken"][0]["scope"], "%root:three.b");
    assert_eq!(doc["broken"][0]["verdict"], "unrecorded");
    let homes: Vec<&str> = doc["findings"]
        .as_array()
        .expect("findings")
        .iter()
        .map(|f| f["home"].as_str().expect("home"))
        .collect();
    assert!(
        homes.iter().all(|h| h.starts_with("no home yet")),
        "{homes:?}"
    );
    let clean = twins("json-absent");
    let advisory = census(&clean.0, &["--json"]);
    assert_eq!(code(&advisory), 0, "{}", text(&advisory));
    let doc: serde_json::Value = serde_json::from_str(text(&advisory).trim()).expect("one");
    assert_eq!(doc["adopted"], false);
    assert_eq!(doc["broken"], serde_json::json!([]));
}

#[test]
fn facts_print_one_definition_per_line_at_the_floor_and_exit_zero() {
    let p = twins("facts");
    p.write("small.b", OWN);
    let out = census(&p.0, &["--facts"]);
    assert_eq!(code(&out), 0);
    let shown = text(&out);
    let rows: Vec<serde_json::Value> = shown
        .lines()
        .map(|l| serde_json::from_str(l).expect("a JSON line"))
        .collect();
    assert_eq!(rows.len(), 2, "{shown}");
    assert_eq!(rows[0]["shape"], rows[1]["shape"]);
    assert_eq!(rows[0]["shape"].as_str().map(str::len), Some(64));
}

#[test]
fn the_tools_own_tests_pass() {
    let file = repo().join("crates/blue-lang-cli/blue/reuse.b");
    let out = blue_in(&repo(), &["test", &file.display().to_string()]);
    assert_eq!(code(&out), 0, "{}", text(&out));
}
