use std::path::{Path, PathBuf};
use std::process::Command;

fn bidama(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../bidamas")
        .join(rel)
        .canonicalize()
        .expect("the bidama is in the checkout")
}

fn left(tmp: &Path) -> Vec<String> {
    let mut out = Vec::new();
    for d in [tmp.to_path_buf(), tmp.join("blue-scratch")] {
        for e in std::fs::read_dir(&d).into_iter().flatten().flatten() {
            let n = e.file_name().to_string_lossy().into_owned();
            if n != "blue-scratch" {
                out.push(n);
            }
        }
    }
    out
}

fn tested_leaves_nothing(rel: &str) {
    let file = bidama(rel);
    let tmp = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!(
        "temp-leak-{}-{}",
        file.file_stem().unwrap().to_string_lossy(),
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).expect("a private TMPDIR");
    let o = Command::new(env!("CARGO_BIN_EXE_blue"))
        .current_dir(file.parent().unwrap())
        .args(["test", "--no-cache"])
        .arg(&file)
        .env("BLUE_PATH", bidama(""))
        .env("TMPDIR", &tmp)
        .env_remove("GEN_ROOT")
        .env_remove("BLUE_INPUTS")
        .output()
        .expect("blue runs");
    assert!(
        o.status.success(),
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    );
    assert_eq!(
        left(&tmp),
        Vec::<String>::new(),
        "{rel} left these in TMPDIR"
    );
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn tesuto_s_own_tests_leave_nothing_in_tmpdir() {
    tested_leaves_nothing("tesuto/tesuto.b");
}

#[test]
fn toride_s_tests_through_tesuto_fresh_dir_leave_nothing_in_tmpdir() {
    tested_leaves_nothing("toride/toride.b");
}

#[test]
fn kyuuji_s_tests_leave_nothing_in_tmpdir() {
    tested_leaves_nothing("eigyou/kyuuji/kyuuji.b");
}
