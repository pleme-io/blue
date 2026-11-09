//! **Generated properties** (HORIZON H6): `blue test` draws calls around a
//! typed definition's `@doc` example and holds each to the declared return
//! type, seeded and replayable.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const GRADE: &str = "@doc \"\"\"
grade: the word for a score out of a hundred.

    grade(52) #=> \"pass\"
\"\"\"
def grade(score: Int) -> Str
  if score >= 90
    \"A\"
  elsif score > 50
    \"pass\"
  elsif score < 50
    \"fail\"
  end
end
";

fn place(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join(format!("properties-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir
}

fn test(name: &str, src: &str, seed: Option<&str>) -> Output {
    let file = place(name).join("grade.b");
    std::fs::write(&file, src).expect("fixture");
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.arg("test")
        .arg(&file)
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    match seed {
        Some(s) => c.env("BLUE_PROPERTY_SEED", s),
        None => c.env_remove("BLUE_PROPERTY_SEED"),
    };
    c.output().expect("blue test runs")
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

/// The example passes, the property drawn around it finds the score the
/// example cannot reach (50 returns nil, not a `Str`), and names it.
///
/// Red run (2026-11-09): with `generated_properties` answering no tests,
/// `blue test` passed the fixture (1 test, 1 passed) and this test failed
/// on its first assertion.
#[test]
fn a_drawn_neighbour_finds_the_bug_the_example_cannot() {
    let alone = test("alone", GRADE, Some("off"));
    assert!(alone.status.success(), "{}", text(&alone));
    let o = test("seeded", GRADE, None);
    let out = text(&o);
    assert!(!o.status.success(), "{out}");
    assert!(out.contains("@property `grade` example 1, seed 1"), "{out}");
    assert!(out.contains("assert conforms?(grade(50), Str)"), "{out}");
}

/// The same seed fails on the same case, word for word.
#[test]
fn the_same_seed_replays_the_same_failure() {
    let a = text(&test("replay-a", GRADE, Some("1")));
    let b = text(&test("replay-b", GRADE, Some("1")));
    let strip = |s: &str| {
        s.lines()
            .filter(|l| !l.contains("properties-replay") && !l.contains(" ms") && !l.contains("µs"))
            .collect::<Vec<_>>()
            .join("\n")
    };
    assert_eq!(strip(&a), strip(&b));
    assert!(a.contains("grade(50)"), "{a}");
}

/// An untyped definition gets no property: the same bug, unannotated, runs
/// exactly the tests it ran before.
#[test]
fn an_untyped_definition_gets_no_property() {
    let src = GRADE.replace("def grade(score: Int) -> Str", "def grade(score)");
    let o = test("untyped", &src, None);
    let out = text(&o);
    assert!(o.status.success(), "{out}");
    assert!(!out.contains("@property"), "{out}");
}
