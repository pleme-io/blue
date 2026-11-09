use std::path::PathBuf;
use std::process::Command;

fn bidamas() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bidamas")
        .canonicalize()
        .expect("the bidamas directory")
}

fn run(program: &str) -> String {
    let dir = std::env::temp_dir().join(format!("blue-seikika-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    let file = dir.join("p.b");
    std::fs::write(&file, program).expect("program");
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env("BLUE_PATH", bidamas())
        .env_remove("BLUE_DIST")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_MEMO")
        .env("BLUE_TRACE_DIR", "")
        .arg("run")
        .arg(&file)
        .output()
        .expect("blue run");
    let _ = std::fs::remove_dir_all(&dir);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

#[test]
fn a_union_arm_and_a_declared_record_read_back_as_themselves_and_keep_their_own_roots() {
    let program = r#"use("seikika", %i[decode encode root same?])

union shape = circle(r: Float) | rect(w: Float, h: Float)

record point(x, y)

values = [circle(1.5), rect(2.0, 3.0), point(1, [circle(0.5)])]

println(
  every?(
    (v) -> same?(decode(encode(v)), v) and record_name(decode(encode(v))) == record_name(v),
    values
  )
)
println(root(circle(1.5)) != root({r: 1.5}))
println(root(rect(1.0, 2.0)) != root(rect(2.0, 1.0)))
println(root(circle(1.5)) == root(decode(encode(circle(1.5)))))
"#;
    assert_eq!(
        run(program).lines().collect::<Vec<_>>(),
        ["#t", "#t", "#t", "#t"]
    );
}
