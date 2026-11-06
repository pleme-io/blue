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
fn a_word_that_forwards_to_a_sibling_has_the_shape_of_what_it_computes() {
    let p = Project::new("forward");
    p.write(
        "words.b",
        "def tilt(xs, by)\n  map((x) -> x * 2 + by, xs)\nend\n\n\
         def lean(ys)\n  tilt(ys, 1)\nend\n",
    );
    p.write("copy.b", SPREAD);
    let out = census(&p.0, &["--facts"]);
    assert_eq!(code(&out), 0);
    let shown = text(&out);
    let rows: Vec<serde_json::Value> = shown
        .lines()
        .map(|l| serde_json::from_str(l).expect("a JSON line"))
        .collect();
    let shape = |name: &str| {
        rows.iter()
            .find(|r| r["name"] == name)
            .map(|r| r["shape"].clone())
            .unwrap_or_else(|| panic!("no row for {name}: {shown}"))
    };
    assert_eq!(shape("lean"), shape("spread"), "{shown}");
    assert_ne!(shape("tilt"), shape("spread"), "{shown}");
}

#[test]
fn the_tools_own_tests_pass() {
    let file = repo().join("crates/blue-lang-cli/blue/reuse.b");
    let out = blue_in(&repo(), &["test", &file.display().to_string()]);
    assert_eq!(code(&out), 0, "{}", text(&out));
}

const TALLY: &str = "def tally(ns)\n  reduce((acc, n) -> acc + n, 0, ns)\nend\n";
const CODED: &str = "def coded(code, why)\n  if why != nil\n    [code, why]\n  end\nend\n";

fn check_codes(dir: &Path, file: &str) -> (i32, String) {
    let out = blue_in(dir, &["check", "--format", "json", file]);
    (code(&out), text(&out))
}

#[test]
fn a_copy_of_a_word_names_it_counts_it_and_stops_no_door() {
    let p = Project::new("word");
    let src = format!(
        "{TALLY}\ndef main()\n  write_stdout(to_s(tally([1, 2, 3])))\nend\n\n\
         test \"tallies\"\n  assert tally([1, 2]) == 3\nend\n"
    );
    p.write("one.b", &src);
    let doc = census(&p.0, &["--json"]);
    let doc: serde_json::Value = serde_json::from_str(text(&doc).trim()).expect("one document");
    assert_eq!(doc["copies"], 1);
    assert_eq!(doc["findings"][0]["home"], "kazu::sum");
    assert_eq!(doc["findings"][0]["fix"], "import");
    let (status, shown) = check_codes(&p.0, "one.b");
    assert_eq!(status, 0, "{shown}");
    assert!(shown.contains("\"B0070\""), "{shown}");
    let ran = blue_in(&p.0, &["run", "one.b"]);
    assert_eq!(code(&ran), 0, "{}", String::from_utf8_lossy(&ran.stderr));
    assert!(text(&ran).starts_with('6'));
    assert_eq!(code(&blue_in(&p.0, &["test", "one.b"])), 0);
}

#[test]
fn fix_forwards_to_a_foundation_word_in_one_command_and_the_program_is_unchanged() {
    let p = Project::new("fix");
    p.write(
        "one.b",
        &format!("{TALLY}\ndef main()\n  write_stdout(to_s(tally([1, 2, 3])))\nend\n"),
    );
    let fixed = blue_in(&p.0, &["check", "--fix", "one.b"]);
    assert_eq!(code(&fixed), 0, "{}", text(&fixed));
    let written = std::fs::read_to_string(p.0.join("one.b")).expect("read");
    assert!(written.starts_with("use(\"kazu\")\n"), "{written}");
    assert!(written.contains("  kazu::sum(ns)\n"), "{written}");
    let (_, shown) = check_codes(&p.0, "one.b");
    assert!(!shown.contains("B0070"), "{shown}");
    let ran = blue_in(&p.0, &["run", "one.b"]);
    assert_eq!(code(&ran), 0, "{}", String::from_utf8_lossy(&ran.stderr));
    assert!(text(&ran).starts_with('6'));
}

#[test]
fn a_domain_home_says_move_down_and_fix_leaves_it_alone() {
    let p = Project::new("domain");
    p.write("one.b", CODED);
    let lines = text(&blue_in(&p.0, &["check", "--reuse", "one.b"]));
    assert!(lines.contains("shomei::merkle_side"), "{lines}");
    assert!(lines.contains("move down"), "{lines}");
    let doc = census(&p.0, &["--json"]);
    let doc: serde_json::Value = serde_json::from_str(text(&doc).trim()).expect("one document");
    assert_eq!(doc["findings"][0]["fix"], "move_down");
    assert_eq!(code(&blue_in(&p.0, &["check", "--fix", "one.b"])), 0);
    assert_eq!(
        std::fs::read_to_string(p.0.join("one.b")).expect("read"),
        CODED
    );
}

#[test]
fn a_waiver_is_honored_by_every_reader_and_refused_when_stale_only_where_the_rule_runs() {
    let p = Project::new("waiver");
    p.write(
        "one.b",
        &format!("# waive B0070: tally rounds soon, and the word never will\n{TALLY}"),
    );
    let plain = blue_in(&p.0, &["check", "one.b"]);
    assert_eq!(code(&plain), 0, "{}", text(&plain));
    let told = format!("{}{}", text(&plain), String::from_utf8_lossy(&plain.stderr));
    assert!(told.contains("waived:             1"), "{told}");
    assert!(
        told.contains("warning[B0070]: waived: `tally`"),
        "listed as waived and nothing else: {told}"
    );
    assert_eq!(text(&blue_in(&p.0, &["check", "--reuse", "one.b"])), "");
    let doc = census(&p.0, &["--json"]);
    let doc: serde_json::Value = serde_json::from_str(text(&doc).trim()).expect("one document");
    assert_eq!(doc["copies"], 0);
    assert_eq!(doc["waived"], 1);
    let stale = "# waive B0070: nothing to waive\ndef own(z)\n  z\nend\n\n\
                 def main()\n  write_stdout(to_s(own(1)))\nend\n";
    p.write("two.b", stale);
    let (status, shown) = check_codes(&p.0, "two.b");
    assert_ne!(status, 0, "{shown}");
    assert!(shown.contains("B0008"), "{shown}");
    let ran = blue_in(&p.0, &["run", "two.b"]);
    assert_eq!(code(&ran), 0, "{}", String::from_utf8_lossy(&ran.stderr));
}

#[test]
fn a_twin_inside_one_scope_is_no_copy() {
    let p = Project::new("own-twin");
    p.write(
        "one.b",
        &format!("{SPREAD}\ndef again(zs)\n  map((z) -> z * 2 + 1, zs)\nend\n"),
    );
    let doc = census(&p.0, &["--json"]);
    let doc: serde_json::Value = serde_json::from_str(text(&doc).trim()).expect("one document");
    assert_eq!(doc["copies"], 0);
}

fn hook(dir: &Path, stdin: &str) -> Output {
    use std::io::Write;
    use std::process::Stdio;
    let mut child = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_DIST")
        .env("BLUE_PATH", repo().join("bidamas"))
        .current_dir(dir)
        .args(["check", "--reuse", "--hook"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn");
    child
        .stdin
        .take()
        .expect("stdin")
        .write_all(stdin.as_bytes())
        .expect("write");
    child.wait_with_output().expect("wait")
}

#[test]
fn the_hook_prints_one_line_per_finding_and_is_silent_and_green_on_everything_else() {
    let p = Project::new("hook");
    p.write("one.b", TALLY);
    let file = p.0.join("one.b").display().to_string();
    let found = hook(
        &p.0,
        &serde_json::json!({"tool_name": "Edit", "tool_input": {"file_path": file}}).to_string(),
    );
    assert_eq!(code(&found), 0);
    let shown = text(&found);
    assert_eq!(shown.lines().count(), 1, "{shown}");
    assert!(shown.contains(&format!("{file}:1:5")), "{shown}");
    assert!(shown.contains("kazu::sum"), "{shown}");
    assert!(shown.contains("use(\"kazu\", [:sum])"), "{shown}");
    p.write("broken.b", "def broken(\n");
    p.write("notes.txt", TALLY);
    for silent in [
        String::new(),
        "not json".to_string(),
        "{}".to_string(),
        serde_json::json!({"tool_input": {}}).to_string(),
        serde_json::json!({"tool_input": {"file_path": 7}}).to_string(),
        serde_json::json!({"tool_input": {"file_path": p.0.join("notes.txt")}}).to_string(),
        serde_json::json!({"tool_input": {"file_path": p.0.join("gone.b")}}).to_string(),
        serde_json::json!({"tool_input": {"file_path": p.0.join("broken.b")}}).to_string(),
    ] {
        let out = hook(&p.0, &silent);
        assert_eq!(code(&out), 0, "{silent}");
        assert_eq!(text(&out), "", "{silent}");
        assert!(out.stderr.is_empty(), "{silent}");
    }
}

#[test]
fn check_reuse_for_people_prints_the_same_line_and_exits_zero_on_a_missing_file() {
    let p = Project::new("people");
    p.write("one.b", TALLY);
    let out = blue_in(&p.0, &["check", "--reuse", "one.b"]);
    assert_eq!(code(&out), 0);
    assert!(text(&out).starts_with("one.b:1:5: `tally` is the shape of `kazu::sum`"));
    assert_eq!(code(&blue_in(&p.0, &["check", "--reuse", "gone.b"])), 0);
    let usage = blue_in(&p.0, &["check"]);
    assert_eq!(code(&usage), 2, "FILE stays required without --hook");
}

#[test]
fn a_projects_own_packages_are_found_from_the_tree_with_no_configuration() {
    let p = Project::new("tree-roots");
    std::fs::create_dir_all(p.0.join("kit/tool")).expect("mkdir");
    p.write("kit/tool/tool.b", &format!("{SPREAD}\n{OWN}"));
    let caller = format!(
        "use(\"tool\", [:own])\n\n{}\ndef main()\n  write_stdout(to_s(own(1)))\nend\n",
        SPREAD.replace("spread", "again")
    );
    p.write("caller.b", &caller);
    let doc = census(&p.0, &["--json"]);
    let doc: serde_json::Value = serde_json::from_str(text(&doc).trim()).expect("one document");
    assert_eq!(doc["blind"], serde_json::json!([]), "{doc}");
    assert_eq!(doc["files"], 2);
    assert_eq!(doc["copies"], 2, "{doc}");
}
