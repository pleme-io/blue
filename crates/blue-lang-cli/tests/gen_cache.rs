#[macro_use]
mod moduledoc;

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const GENERATOR: &str = moduledoc!(
    "page: the generator copies its declared note through zed and logs each run.",
    "to_s(1) #=> \"1\"",
    "use(\"zed\", [:shout])

def main()
  append_file(getenv(\"RUNS_LOG\", \"runs.log\"), \"ran\\n\")
  write_file(
    getenv(\"GEN_OUT\", \"out.txt\"),
    shout(read_file(path_join(getenv(\"GEN_ROOT\", \".\"), \"docs/a.md\")))
  )
end
"
);

const ZED: &str = moduledoc!(
    "zed: a fixture package.",
    "shout(\"a\") #=> \"a!\"",
    "@doc \"\"\"
shout: The text with a mark.

    shout(\"a\") #=> \"a!\"
\"\"\"
def shout(s)
  \"#{s}!\"
end
"
);

struct Project {
    dir: PathBuf,
    cache: PathBuf,
    log: PathBuf,
}

impl Project {
    fn new(name: &str) -> Self {
        let base = Path::new(env!("CARGO_TARGET_TMPDIR"))
            .join(format!("gen-cache-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let dir = base.join("project");
        std::fs::create_dir_all(dir.join("docs")).expect("docs dir");
        std::fs::create_dir_all(dir.join("unread")).expect("unread dir");
        std::fs::create_dir_all(dir.join("bidamas/zed")).expect("package dir");
        std::fs::write(dir.join("docs/a.md"), "one").expect("declared file");
        std::fs::write(dir.join("unread/b.md"), "two").expect("undeclared file");
        std::fs::write(dir.join("g.b"), GENERATOR).expect("generator");
        std::fs::write(
            dir.join("bidamas/zed/Bluefile"),
            "package(\"zed\", \"0.1.0\")\n",
        )
        .expect("package Bluefile");
        std::fs::write(dir.join("bidamas/zed/zed.b"), ZED).expect("package");
        std::fs::write(
            dir.join("Bluefile"),
            "package(\"fixture\", \"0.1.0\")\n\npackages(\"bidamas\")\ngenerate(\"page\", \"out.txt\", \"g.b\", [\"docs\"])\n",
        )
        .expect("Bluefile");
        let p = Self {
            dir: dir.canonicalize().expect("canonical project"),
            cache: base.join("cache"),
            log: base.join("runs.log"),
        };
        for args in [&["lock", "bidamas/zed"][..], &["lock", "."][..]] {
            let locked = p.blue(args, &[]);
            assert!(locked.status.success(), "{}", text(&locked));
        }
        for args in [&["init", "-q"][..], &["add", "-A"][..]] {
            let g = Command::new("git")
                .arg("-C")
                .arg(&p.dir)
                .args(args)
                .env_remove("GIT_DIR")
                .env_remove("GIT_WORK_TREE")
                .env_remove("GIT_INDEX_FILE")
                .output()
                .expect("git runs");
            assert!(g.status.success(), "{}", text(&g));
        }
        p
    }

    fn blue(&self, args: &[&str], env: &[(&str, &str)]) -> Output {
        let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
        c.current_dir(&self.dir)
            .args(args)
            .env_remove("GEN_ROOT")
            .env_remove("BLUE_INPUTS")
            .env_remove("BLUE_PATH")
            .env_remove("BLUE_GEN_CACHE")
            .env_remove("BLUE_CACHE_SHARED")
            .env("XDG_CACHE_HOME", &self.cache)
            .env("RUNS_LOG", &self.log)
            .env("GEN_OUT", "out.txt")
            .env("TMPDIR", Path::new(env!("CARGO_TARGET_TMPDIR")));
        for (k, v) in env {
            c.env(k, v);
        }
        c.output().expect("blue runs")
    }

    fn generate(&self, env: &[(&str, &str)]) -> usize {
        let o = self.blue(&["run", "g.b"], env);
        assert!(o.status.success(), "{}", text(&o));
        std::fs::read_to_string(&self.log)
            .unwrap_or_default()
            .lines()
            .count()
    }

    fn write(&self, rel: &str, content: &str) {
        std::fs::write(self.dir.join(rel), content).expect("write");
    }

    fn out(&self) -> String {
        std::fs::read_to_string(self.dir.join("out.txt")).expect("the output is written")
    }
}

impl Drop for Project {
    fn drop(&mut self) {
        if let Some(base) = self.dir.parent() {
            let _ = std::fs::remove_dir_all(base);
        }
    }
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

#[test]
fn a_generator_whose_inputs_hash_the_same_does_not_run_again() {
    let p = Project::new("same");
    assert_eq!(p.generate(&[]), 1);
    assert_eq!(p.out(), "one!");
    assert_eq!(p.generate(&[]), 1);
    assert_eq!(p.out(), "one!");
}

#[test]
fn a_changed_declared_input_runs_it_again_and_an_undeclared_file_does_not() {
    let p = Project::new("input");
    assert_eq!(p.generate(&[]), 1);
    p.write("unread/b.md", "three");
    assert_eq!(p.generate(&[]), 1);
    p.write("docs/a.md", "four");
    assert_eq!(p.generate(&[]), 2);
    assert_eq!(p.out(), "four!");
    assert_eq!(p.generate(&[]), 2);
}

#[test]
fn a_changed_program_or_package_runs_it_again() {
    let p = Project::new("code");
    assert_eq!(p.generate(&[]), 1);
    p.write(
        "g.b",
        &GENERATOR
            .replace("shout(read_file", "shout(shout(read_file")
            .replace("docs/a.md\")))", "docs/a.md\"))))"),
    );
    assert_eq!(p.generate(&[]), 2);
    assert_eq!(p.out(), "one!!");
    p.write(
        "bidamas/zed/zed.b",
        &ZED.replace("\"#{s}!\"", "\"#{s}?\"")
            .replace("#=> \"a!\"", "#=> \"a?\""),
    );
    assert_eq!(p.generate(&[]), 3);
    assert_eq!(p.out(), "one??");
}

#[test]
fn an_output_edited_by_hand_is_generated_again() {
    let p = Project::new("output");
    assert_eq!(p.generate(&[]), 1);
    p.write("out.txt", "edited");
    assert_eq!(p.generate(&[]), 2);
    assert_eq!(p.out(), "one!");
}

#[test]
fn the_off_switch_runs_it_every_time() {
    let p = Project::new("off");
    assert_eq!(p.generate(&[]), 1);
    assert_eq!(p.generate(&[("BLUE_GEN_CACHE", "off")]), 2);
    assert_eq!(p.generate(&[]), 2);
    let refused = p.blue(&["run", "g.b"], &[("BLUE_GEN_CACHE", "sometimes")]);
    assert!(!refused.status.success(), "{}", text(&refused));
    assert!(
        text(&refused).contains("BLUE_GEN_CACHE"),
        "{}",
        text(&refused)
    );
}
