use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const CHECK: &str = "test \"the declared input is there\"
  assert path_exists(path_join(getenv(\"GEN_ROOT\", \".\"), \"docs/a.md\"))
end

test \"a path the check does not declare is not\"
  assert not path_exists(path_join(getenv(\"GEN_ROOT\", \".\"), \"unread/b.md\"))
end

test \"a path that climbs out of a declared input reaches nothing\"
  root = getenv(\"GEN_ROOT\", \".\")
  assert not path_exists(path_join(root, \"docs/../unread/b.md\"))
  assert not path_exists(path_join(root, \"docs/../t.b\"))
end
";

const GENERATOR: &str = "def main()
  write_file(
    getenv(\"GEN_OUT\", \"out.txt\"),
    to_s(path_exists(path_join(getenv(\"GEN_ROOT\", \".\"), \"unread/b.md\")))
  )
end
";

fn project(name: &str, inputs: &str) -> PathBuf {
    let dir = fixture(Path::new(env!("CARGO_TARGET_TMPDIR")), name, inputs);
    for args in [&["init", "-q"][..], &["add", "-A"][..]] {
        let g = git(&dir, args);
        assert!(g.status.success(), "{}", text(&g));
    }
    dir
}

fn loose(name: &str, inputs: &str) -> PathBuf {
    let dir = fixture(&std::env::temp_dir(), name, inputs);
    assert!(
        !git(&dir, &["rev-parse", "--git-dir"]).status.success(),
        "{} is inside a git repository, and this case needs one outside",
        dir.display()
    );
    dir
}

fn git(dir: &Path, args: &[&str]) -> Output {
    Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .env_remove("GIT_DIR")
        .env_remove("GIT_WORK_TREE")
        .env_remove("GIT_INDEX_FILE")
        .output()
        .expect("git runs")
}

fn fixture(base: &Path, name: &str, inputs: &str) -> PathBuf {
    let dir = base.join(format!("declared-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("docs")).expect("docs dir");
    std::fs::create_dir_all(dir.join("unread")).expect("unread dir");
    std::fs::write(dir.join("docs/a.md"), "# A\n").expect("declared file");
    std::fs::write(dir.join("unread/b.md"), "# B\n").expect("undeclared file");
    std::fs::write(dir.join("t.b"), CHECK).expect("check file");
    std::fs::write(dir.join("g.b"), GENERATOR).expect("generator");
    std::fs::write(
        dir.join("Bluefile"),
        format!(
            "package(\"fixture\", \"0.1.0\")\n\ncheck(\"reads\", \"t.b\", {inputs})\ngenerate(\"page\", \"out.txt\", \"g.b\", {inputs})\n"
        ),
    )
    .expect("Bluefile");
    let locked = blue(&dir, &["lock", "."], &[]);
    assert!(locked.status.success(), "{}", text(&locked));
    dir.canonicalize().expect("canonical project")
}

fn blue(dir: &Path, args: &[&str], env: &[(&str, &str)]) -> Output {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.current_dir(dir)
        .args(args)
        .env_remove("GEN_ROOT")
        .env_remove("BLUE_INPUTS")
        .env_remove("BLUE_PATH")
        .env("TMPDIR", Path::new(env!("CARGO_TARGET_TMPDIR")));
    for (k, v) in env {
        c.env(k, v);
    }
    c.output().expect("blue runs")
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

#[test]
fn a_check_reads_only_its_declared_inputs_as_nix_runs_it_and_the_off_switch_reads_the_checkout() {
    let dir = project("check", "[\"docs\"]");
    let held = blue(&dir, &["test", "t.b"], &[]);
    assert!(held.status.success(), "{}", text(&held));
    let open = blue(&dir, &["test", "t.b"], &[("BLUE_INPUTS", "checkout")]);
    assert!(!open.status.success(), "{}", text(&open));
    let named = blue(&dir, &["test", "t.b"], &[("GEN_ROOT", ".")]);
    assert!(
        !named.status.success(),
        "an explicit GEN_ROOT wins: {}",
        text(&named)
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_generator_run_reads_only_its_declared_inputs_and_the_off_switch_reads_the_checkout() {
    let dir = project("generate", "[\"docs\"]");
    let held = blue(&dir, &["run", "--quiet", "g.b"], &[]);
    assert!(held.status.success(), "{}", text(&held));
    assert_eq!(
        std::fs::read_to_string(dir.join("out.txt")).unwrap(),
        "false"
    );
    let open = blue(
        &dir,
        &["run", "--quiet", "g.b"],
        &[("BLUE_INPUTS", "checkout")],
    );
    assert!(open.status.success(), "{}", text(&open));
    assert_eq!(
        std::fs::read_to_string(dir.join("out.txt")).unwrap(),
        "true"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_failing_check_says_it_read_only_its_declared_inputs_and_names_the_off_switch() {
    let dir = project("note", "[\"unread\"]");
    let o = blue(&dir, &["test", "t.b"], &[]);
    assert!(!o.status.success(), "{}", text(&o));
    let said = text(&o);
    assert!(said.contains("ran as check(\"reads\")"), "{said}");
    assert!(said.contains("BLUE_INPUTS=checkout"), "{said}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_declared_input_that_does_not_exist_is_refused_by_name() {
    let dir = project("gone", "[\"docs\"]");
    std::fs::remove_dir_all(dir.join("docs")).unwrap();
    let o = blue(&dir, &["test", "t.b"], &[]);
    assert!(!o.status.success());
    assert!(
        text(&o).contains("declares the input `docs`"),
        "{}",
        text(&o)
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_declared_input_git_does_not_track_is_refused_as_the_sandbox_would_not_see_it() {
    let dir = project("untracked", "[\"docs\"]");
    std::fs::create_dir_all(dir.join("more")).unwrap();
    std::fs::write(dir.join("more/c.md"), "# C\n").unwrap();
    std::fs::write(
        dir.join("Bluefile"),
        "package(\"fixture\", \"0.1.0\")\n\ncheck(\"reads\", \"t.b\", [\"more\"])\n",
    )
    .unwrap();
    assert!(blue(&dir, &["lock", "."], &[]).status.success());
    let o = blue(&dir, &["test", "t.b"], &[]);
    assert!(!o.status.success());
    assert!(
        text(&o).contains("git tracks no file there"),
        "{}",
        text(&o)
    );
    std::fs::write(
        dir.join("Bluefile"),
        "package(\"fixture\", \"0.1.0\")\n\ncheck(\"reads\", \"t.b\", [\"more/c.md\"])\n",
    )
    .unwrap();
    assert!(blue(&dir, &["lock", "."], &[]).status.success());
    let one = blue(&dir, &["test", "t.b"], &[]);
    assert!(!one.status.success());
    assert!(
        text(&one).contains("git tracks no file there"),
        "{}",
        text(&one)
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_declared_file_is_there_alone_and_nothing_beside_it() {
    let dir = project("file", "[\"docs/a.md\"]");
    let o = blue(&dir, &["test", "t.b"], &[]);
    assert!(o.status.success(), "{}", text(&o));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn outside_git_every_file_of_a_declared_directory_is_read_and_a_declared_file_too() {
    let dir = loose("loose", "[\"docs\", \"Bluefile\"]");
    let o = blue(&dir, &["test", "t.b"], &[]);
    assert!(o.status.success(), "{}", text(&o));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_switch_outside_its_set_is_refused() {
    let dir = project("bad", "[\"docs\"]");
    let o = blue(&dir, &["test", "t.b"], &[("BLUE_INPUTS", "sometimes")]);
    assert!(!o.status.success());
    assert!(
        text(&o).contains("BLUE_INPUTS is \"sometimes\""),
        "{}",
        text(&o)
    );
    let _ = std::fs::remove_dir_all(&dir);
}
