use std::path::PathBuf;
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

fn fixture(name: &str, src: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-chain-fixes-{name}"));
    std::fs::create_dir_all(&dir).expect("dir");
    let p = dir.join("t.b");
    std::fs::write(&p, src).expect("write fixture");
    p
}

fn run(args: &[&str], file: &PathBuf) -> Output {
    blue().args(args).arg(file).output().expect("spawn blue")
}

fn text(file: &PathBuf) -> String {
    std::fs::read_to_string(file).expect("read")
}

const MISSING_USE: &str = "use(\"moji\", [:lines])\n\ndef go(xs)\n  t = now_ms()\n  [last(xs), rest(xs), t, lines(\"a\")]\nend\n";

#[test]
fn check_fix_adds_the_use_a_bare_name_needs_and_keeps_the_uses_sorted() {
    let f = fixture("missing-use", MISSING_USE);
    let out = run(&["check", "--fix"], &f);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stdout)
    );
    assert_eq!(
        text(&f),
        "use(\"moji\", [:lines])\nuse(\"retsu\", [:last, :rest])\n\ndef go(xs)\n  t = now_ms\n  [last(xs), rest(xs), t, lines(\"a\")]\nend\n"
    );
}

#[test]
fn check_reports_the_missing_use_before_it_is_fixed() {
    let f = fixture("missing-use-report", MISSING_USE);
    let out = run(&["check"], &f);
    assert!(!out.status.success());
    let shown = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(shown.contains("B0012"), "{shown}");
}

#[test]
fn check_fix_sorts_use_forms_by_package() {
    let src = "use(\"retsu\", [:size, :first])\nuse(\"moji\", [:lines])\nuse(\"junjo\", [:sort])\n\ndef go(xs)\n  [first(xs), size(xs), lines(\"a\"), sort(xs)]\nend\n";
    let f = fixture("unsorted-uses", src);
    let out = run(&["check", "--fix"], &f);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stdout)
    );
    assert_eq!(
        text(&f),
        "use(\"junjo\", [:sort])\nuse(\"moji\", [:lines])\nuse(\"retsu\", [:first, :size])\n\ndef go(xs)\n  [first(xs), size(xs), lines(\"a\"), sort(xs)]\nend\n"
    );
}

#[test]
fn check_fix_adds_the_use_a_qualifier_needs() {
    let src = "use(\"moji\", [:lines])\n\ndef go(xs)\n  [retsu::first(xs), lines(\"a\")]\nend\n";
    let f = fixture("qualifier", src);
    let out = run(&["check", "--fix"], &f);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stdout)
    );
    assert_eq!(
        text(&f),
        "use(\"moji\", [:lines])\nuse(\"retsu\")\n\ndef go(xs)\n  [retsu::first(xs), lines(\"a\")]\nend\n"
    );
}

#[test]
fn fmt_write_simplifies_a_redundant_conversion_chain() {
    let src = "def go(x)\n  to_s(to_s(to_s(x)))\nend\n";
    let f = fixture("fmt-chain", src);
    let out = run(&["fmt", "--write"], &f);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(text(&f), "def go(x)\n  to_s(x)\nend\n");
}

#[test]
fn check_fix_simplifies_a_redundant_conversion_chain() {
    let src = "def go(x)\n  string(trim(trim(x)))\nend\n";
    let f = fixture("fix-chain", src);
    let out = run(&["check", "--fix"], &f);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stdout)
    );
    assert_eq!(text(&f), "def go(x)\n  trim(x)\nend\n");
}

#[test]
fn a_lossy_chain_is_left_as_written() {
    let src = "def go(x)\n  to_int(to_int(x))\nend\n";
    let f = fixture("lossy", src);
    let out = run(&["fmt", "--write"], &f);
    assert!(out.status.success());
    assert_eq!(text(&f), src);
}

#[test]
fn explain_describes_the_conversion_rule() {
    let out = blue().args(["explain", "B0045"]).output().expect("spawn");
    assert!(out.status.success());
    let shown = String::from_utf8_lossy(&out.stdout);
    assert!(shown.contains("redundant-conversion"), "{shown}");
}
