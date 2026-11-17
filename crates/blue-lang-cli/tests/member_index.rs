use std::process::Command;

const COUNT: &str = "def hits(xs, allowed)\n  reduce((a, x) -> if member?(x, allowed)\n    a + 1\n  else\n    a\n  end, 0, xs)\nend\n\ndef main()\n  write_stdout(to_s(hits(range(5000), range(2500, 7500))))\nend\n";

const CASES: &[&str] = &[
    "def hits(xs, allowed)\n  filter((x) -> member?(x, allowed), xs)\nend\n\ndef main()\n  write_stdout(to_s(hits([100, 101, 102, 103, 104, 105, 106, 107, 1, 2.0, 3, 4, \"a\", :b, nil, 0, 7, 8, 9, 10, 11, 12], [2, 3.0, \"a\", nil, -0.0, 12])))\nend\n",
    "def kept(xs, allowed)\n  map((x) -> member?(x, allowed), xs)\nend\n\ndef main()\n  z = 0.0\n  write_stdout(to_s(kept([100, 101, 102, 103, 104, 105, 106, 107, [1], [2], [1.0], z / 1.0, 5, 5, 5, 5, 5, 5, 5, 5, 5], [[1], 6, 0])))\nend\n",
    "def hits(xs, allowed)\n  filter((x) -> member?(x, allowed), xs)\nend\n\ndef main()\n  write_stdout(to_s(hits(range(20), nil)))\nend\n",
    "def hits(xs, allowed)\n  filter((x) -> member?(x, allowed), xs)\nend\n\ndef main()\n  write_stdout(to_s(hits([], json_parse(\"5\"))))\nend\n",
    "def hits(xs, allowed)\n  filter((x) -> member?(x, allowed), xs)\nend\n\ndef main()\n  write_stdout(to_s(hits(range(20), json_parse(\"5\"))))\nend\n",
];

struct Ran {
    stdout: String,
    stderr: String,
    ok: bool,
    indexed: Option<String>,
}

fn run(src: &str, index: &str, door: &str, tag: &str) -> Ran {
    let d = std::env::temp_dir().join(format!(
        "blue-member-index-{}-{tag}-{index}-{door}",
        std::process::id()
    ));
    std::fs::create_dir_all(&d).expect("scratch");
    let p = d.join("m.b");
    std::fs::write(&p, src).expect("program");
    let _ = Command::new(env!("CARGO_BIN_EXE_blue"))
        .args(["fmt", "--write"])
        .arg(&p)
        .output();
    let out = Command::new(env!("CARGO_BIN_EXE_blue"))
        .env_remove("BLUE_PATH")
        .env("BLUE_MEMO", "off")
        .env("BLUE_INDEX", index)
        .args(["run", "--quiet", "--timings", "--door", door])
        .arg(&p)
        .output()
        .expect("spawn blue");
    let _ = std::fs::remove_dir_all(&d);
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    Ran {
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        indexed: stderr
            .lines()
            .find_map(|l| l.strip_prefix("indexed").map(|r| r.trim().to_string())),
        ok: out.status.success(),
        stderr,
    }
}

#[test]
fn a_membership_test_in_a_loop_is_answered_from_an_index_with_the_same_answer() {
    for door in ["vm", "walker"] {
        let on = run(COUNT, "on", door, "count");
        let off = run(COUNT, "off", door, "count");
        assert!(on.ok, "{}", on.stderr);
        assert_eq!(on.stdout, "2500", "{door}");
        assert_eq!(on.stdout, off.stdout, "{door}");
        assert_eq!(
            on.indexed.as_deref(),
            Some("1"),
            "{door}: the rewrite did not run"
        );
        assert_eq!(off.indexed, None, "{door}: BLUE_INDEX=off still indexed");
    }
}

#[test]
fn the_index_answers_what_member_answers_on_every_case_and_door() {
    for (i, src) in CASES.iter().enumerate() {
        for door in ["vm", "walker"] {
            let tag = format!("case{i}");
            let on = run(src, "on", door, &tag);
            let off = run(src, "off", door, &tag);
            assert_eq!(
                on.ok, off.ok,
                "case {i} {door}: {} | {}",
                on.stderr, off.stderr
            );
            assert_eq!(on.stdout, off.stdout, "case {i} {door}");
            if on.ok {
                assert_eq!(
                    on.indexed.as_deref(),
                    Some("1"),
                    "case {i} {door}: the rewrite did not run"
                );
            } else {
                assert!(
                    on.stderr.contains("expected list"),
                    "case {i} {door}: {}",
                    on.stderr
                );
            }
        }
    }
}
