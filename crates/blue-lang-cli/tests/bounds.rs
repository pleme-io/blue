use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue(dir: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env_remove("BLUE_MEMO")
        .env("XDG_CACHE_HOME", dir.join("cache"))
        .current_dir(dir)
        .args(args)
        .output()
        .expect("spawn blue")
}

fn project() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-bounds-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("dir");
    std::fs::write(
        dir.join("Bluefile"),
        "package(\"walk\", \"0.1.0\")\napp(\"walk\", \"main.b\")\n",
    )
    .expect("Bluefile");
    std::fs::write(
        dir.join("main.b"),
        "@moduledoc \"\"\"\nwalk sums a range.\n\n    total(3) #=> 3\n\"\"\"\n\n@doc \"\"\"\ntotal: the sum of the Ints below n.\n\n    total(4) #=> 6\n\"\"\"\ndef total(n)\n  reduce((a, x) -> a + x, 0, range(n))\nend\n\ndef main()\n  write_stdout(to_s(total(2000)))\nend\n",
    )
    .expect("main");
    let locked = blue(&dir, &["lock", "."]);
    assert!(
        locked.status.success(),
        "{}",
        String::from_utf8_lossy(&locked.stderr)
    );
    dir
}

#[test]
fn a_measured_run_proposes_bounds_and_writes_them_only_when_accepted() {
    let dir = project();
    let before = std::fs::read_to_string(dir.join("Bluefile")).expect("Bluefile");
    let proposed = blue(&dir, &["bounds", "main.b"]);
    let said = String::from_utf8_lossy(&proposed.stdout).into_owned();
    assert!(
        proposed.status.success(),
        "{}",
        String::from_utf8_lossy(&proposed.stderr)
    );
    assert!(said.contains("proposed: bounds({steps: "), "{said}");
    assert_eq!(
        std::fs::read_to_string(dir.join("Bluefile")).expect("Bluefile"),
        before,
        "a proposal writes nothing"
    );

    let accepted = blue(&dir, &["bounds", "main.b", "--accept"]);
    assert!(
        accepted.status.success(),
        "{}",
        String::from_utf8_lossy(&accepted.stderr)
    );
    let after = std::fs::read_to_string(dir.join("Bluefile")).expect("Bluefile");
    assert!(
        after.contains("bounds({steps: ") && after.contains("alloc_bytes: "),
        "{after}"
    );
    let ran = blue(&dir, &["run", "--quiet", "main.b"]);
    assert!(
        ran.status.success(),
        "the bounded program still runs: {}",
        String::from_utf8_lossy(&ran.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&ran.stdout), "1999000");

    let again = blue(&dir, &["bounds", "main.b", "--accept"]);
    assert!(
        !again.status.success(),
        "a Bluefile with bounds is its author's"
    );
    assert!(String::from_utf8_lossy(&again.stderr).contains("already declares bounds"));
    assert_eq!(
        std::fs::read_to_string(dir.join("Bluefile")).expect("Bluefile"),
        after
    );
    let _ = std::fs::remove_dir_all(&dir);
}
