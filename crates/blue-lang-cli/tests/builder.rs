use std::process::Command;

const CASES: &[&str] = &[
    "def build(n)\n  reduce((s, i) -> \"#{s}<#{i}>\", \"\", range(n))\nend\n\ndef main()\n  write_stdout(build(12))\nend\n",
    "def build(xs)\n  reduce((s, x) -> \"#{s}#{x},\", 5, xs)\nend\n\ndef main()\n  write_stdout(to_s([build([1, 2.5, nil, :k, [3]]), build([])]))\nend\n",
    "def build(xs)\n  reduce((s, x) -> \"#{s}#{x}\", \"start\", xs)\nend\n\ndef main()\n  write_stdout(to_s([build(nil), build([])]))\nend\n",
    "def noisy(x)\n  write_stdout(\"[#{x}]\")\n  x\nend\n\ndef build(xs)\n  reduce((s, x) -> \"#{s}#{noisy(x)}\", \"\", xs)\nend\n\ndef main()\n  write_stdout(build([1, 2, 3]))\nend\n",
    "def build(xs)\n  reduce((s, x) -> \"#{s}#{10 / x}\", \"\", xs)\nend\n\ndef main()\n  write_stdout(build([1, 2, 0, 4]))\nend\n",
    "def build(xs)\n  reduce((s, x) -> \"#{s}#{x}\", \"\", xs)\nend\n\ndef main()\n  write_stdout(build(json_parse(\"5\")))\nend\n",
];

struct Ran {
    stdout: String,
    stderr: String,
    ok: bool,
    built: bool,
    took: std::time::Duration,
}

fn run(src: &str, builder: &str, door: &str, tag: usize) -> Ran {
    let d = std::env::temp_dir().join(format!(
        "blue-builder-{}-{tag}-{builder}-{door}",
        std::process::id()
    ));
    std::fs::create_dir_all(&d).expect("scratch");
    let p = d.join("b.b");
    std::fs::write(&p, src).expect("program");
    let _ = Command::new(env!("CARGO_BIN_EXE_blue"))
        .args(["fmt", "--write"])
        .arg(&p)
        .output();
    let started = std::time::Instant::now();
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env("BLUE_MEMO", "off")
        .env("BLUE_BUILDER", builder)
        .args(["run", "--quiet", "--door", door])
        .arg(&p)
        .output()
        .expect("spawn blue");
    let took = started.elapsed();
    let shift = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env("BLUE_BUILDER", builder)
        .args(["shift", "--defaults", "--json"])
        .arg(&p)
        .output()
        .expect("spawn blue shift");
    let _ = std::fs::remove_dir_all(&d);
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    Ran {
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        built: String::from_utf8_lossy(&shift.stdout).contains("\"R13\""),
        took,
        stderr: stderr
            .replace(&d.display().to_string(), "<dir>")
            .lines()
            .filter(|l| l.starts_with("blue:") || l.contains("error"))
            .collect::<Vec<_>>()
            .join("\n"),
        ok: out.status.success(),
    }
}

#[test]
fn a_built_string_is_the_string_the_loop_builds_on_both_doors() {
    for (i, src) in CASES.iter().enumerate() {
        for door in ["vm", "walker"] {
            let on = run(src, "on", door, i);
            let off = run(src, "off", door, i);
            assert!(on.built, "case {i} on {door} was not rewritten:\n{src}");
            assert!(!off.built, "BLUE_BUILDER=off rewrote case {i}");
            assert_eq!(on.stdout, off.stdout, "case {i} on {door}:\n{src}");
            assert_eq!(on.ok, off.ok, "case {i} on {door}: {}", on.stderr);
            assert_eq!(on.stderr, off.stderr, "case {i} on {door}");
        }
    }
}

#[test]
fn a_long_build_is_linear() {
    let src = "def build(n)\n  reduce((s, i) -> \"#{s}ab\", \"\", range(n))\nend\n\ndef main()\n  write_stdout(to_s(length(build(200_000))))\nend\n";
    let on = run(src, "on", "walker", 99);
    let off = run(src, "off", "walker", 98);
    assert_eq!(on.stdout, "400000");
    assert_eq!(off.stdout, "400000");
    assert!(on.built);
    assert!(
        off.took > on.took * 3,
        "200,000 appends: {:?} built once, {:?} copied at every step",
        on.took,
        off.took
    );
}
