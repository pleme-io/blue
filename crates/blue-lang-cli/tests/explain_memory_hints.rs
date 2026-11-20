//! M2 of docs/PURE-BLUE.md: `blue explain --memory FILE --hints` places each
//! of M1's last-use facts at the local's last read, one JSON hint per line,
//! for the four `memory.last_use.*` rows of spec/rows/memory.b. The places
//! were counted by hand from the sources below.

use std::process::Command;

fn hints(src: &str, name: &str) -> String {
    let dir = std::env::temp_dir().join(format!("blue-memory-hints-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("mkdir");
    let p = dir.join(name);
    std::fs::write(&p, src).expect("write");
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .args(["explain", "--memory", p.to_str().expect("utf-8"), "--hints"])
        .output()
        .expect("spawn");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).expect("utf-8")
}

#[test]
fn each_last_use_row_is_placed_at_its_locals_last_read() {
    assert_eq!(
        hints("def f(x)\n  y = x + 1\n  y * x\nend\n", "straight_line.b"),
        "{\"column\":3,\"label\":\"last read of y\",\"line\":3}\n{\"column\":7,\"label\":\"last read of x\",\"line\":3}\n"
    );
    assert_eq!(
        hints("def sq(x)\n  x * x\nend\n", "read_twice.b"),
        "{\"column\":7,\"label\":\"last read of x\",\"line\":2}\n"
    );
    assert_eq!(
        hints("def g(c, s)\n  if c\n    size(s)\n  else\n    0\n  end\nend\n", "per_branch.b"),
        "{\"column\":6,\"label\":\"last read of c\",\"line\":2}\n{\"column\":10,\"label\":\"last read of s\",\"line\":3}\n"
    );
    assert_eq!(hints("def k(x)\n  1\nend\n", "never_read.b"), "");
}
