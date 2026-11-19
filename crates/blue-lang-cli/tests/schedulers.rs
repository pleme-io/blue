use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const MAIN: &str = "@moduledoc \"\"\"\nburn spreads work over processes.\n\n    burn(0, 0, 3) #=> 5\n\"\"\"\n\n@doc \"\"\"\nburn: the sum of squares below n, modulo a prime.\n\n    burn(0, 0, 2) #=> 1\n\"\"\"\ndef burn(i, acc, n)\n  if i == n\n    acc\n  else\n    burn(i + 1, (acc + i * i) % 1000003, n)\n  end\nend\n\n@doc \"\"\"\nwork: burn for k, sent to root.\n\n    1 #=> 1\n\"\"\"\ndef work(root, k)\n  send(root, [k, burn(0, k, 400000)])\nend\n\ndef main()\n  me = self()\n  map((k) -> spawn(work, [me, k]), [1, 2, 3, 4])\n  write_stdout(to_s(map((k) -> receive([k, :_]), [1, 2, 3, 4])))\nend\n";

fn blue(dir: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env("BLUE_MEMO", "off")
        .env("BLUE_NATIVE", "off")
        .env("XDG_CACHE_HOME", dir.join("cache"))
        .current_dir(dir)
        .args(args)
        .output()
        .expect("spawn blue")
}

fn project(name: &str, word: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-schedulers-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("dir");
    std::fs::write(
        dir.join("Bluefile"),
        format!("package(\"burn\", \"0.1.0\")\napp(\"burn\", \"main.b\")\n{word}"),
    )
    .expect("Bluefile");
    std::fs::write(dir.join("main.b"), MAIN).expect("main");
    let locked = blue(&dir, &["lock", "."]);
    assert!(
        locked.status.success(),
        "{}",
        String::from_utf8_lossy(&locked.stderr)
    );
    dir
}

fn ran(dir: &Path) -> String {
    let out = blue(dir, &["run", "--quiet", "main.b"]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

#[test]
fn a_project_that_declares_schedulers_gives_the_same_answers_as_one_scheduler() {
    let one = project("one", "");
    let four = project("four", "schedulers(4)\n");
    let alone = ran(&one);
    let together = ran(&four);
    assert_eq!(
        alone, together,
        "A-parity across schedulers(1) and schedulers(4)"
    );
    assert!(alone.starts_with("[[1, "), "{alone}");
    let _ = std::fs::remove_dir_all(&one);
    let _ = std::fs::remove_dir_all(&four);
}
