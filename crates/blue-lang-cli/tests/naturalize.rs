use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER");
    c
}

struct Dir(PathBuf);

impl Dir {
    fn new(name: &str) -> Self {
        let dir =
            std::env::temp_dir().join(format!("blue-naturalize-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("mkdir");
        Dir(dir)
    }

    fn write(&self, file: &str, text: &str) {
        let path = self.0.join(file);
        std::fs::create_dir_all(path.parent().expect("parent")).expect("mkdir");
        std::fs::write(path, text).expect("write");
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn run(dir: &Path, args: &[&str]) -> Output {
    blue().current_dir(dir).args(args).output().expect("spawn")
}

fn said(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

fn with_body(text: &str, head: &str, body: &str) -> String {
    let at = text
        .find(head)
        .unwrap_or_else(|| panic!("no `{head}` in\n{text}"));
    let end = at + text[at..].find("\nend\n").expect("the stub's end") + "\nend\n".len();
    format!("{}{body}{}", &text[..at], &text[end..])
}

const GCD: &str = "\
pub fn gcd(a: i64, b: i64) -> i64 {
    if b == 0 { a.abs() } else { gcd(b, a % b) }
}

pub fn halve(n: u32) -> u32 {
    if n % 2 == 1 { panic!(\"odd\") }
    n / 2
}

pub fn ignored(x: Option<i64>) -> i64 {
    x.unwrap_or(0)
}
";

const GCD_BODY: &str =
    "def gcd(a, b)\n  if b == 0\n    abs(a)\n  else\n    gcd(b, a % b)\n  end\nend\n";

const HALVE_BODY: &str =
    "def halve(n)\n  if n % 2 == 1\n    raise(:odd, \"odd\")\n  end\n  floor(n / 2)\nend\n";

#[test]
fn a_naturalized_function_is_red_until_its_blue_body_agrees_with_the_original() {
    let d = Dir::new("module");
    d.write("gcd.rs", GCD);
    let o = run(&d.0, &["naturalize", "gcd.rs", "kazoe"]);
    assert_eq!(o.status.code(), Some(0), "{}", said(&o));
    let out = said(&o);
    assert!(out.contains("naturalized gcd: 40 rows"), "{out}");
    assert!(out.contains("naturalized halve: 8 rows"), "{out}");
    assert!(out.contains("skipped ignored"), "{out}");
    let file = d.0.join("kazoe/kazoe.b");
    let stub = std::fs::read_to_string(&file).expect("the bidama");
    assert!(stub.contains("{args: [1], raises: true}"), "{stub}");
    let check = run(&d.0, &["check", "kazoe/kazoe.b"]);
    assert_eq!(check.status.code(), Some(0), "{}", said(&check));

    let red = run(&d.0, &["test", "kazoe/kazoe.b"]);
    assert_ne!(red.status.code(), Some(0), "{}", said(&red));
    assert!(
        said(&red).contains("FAIL gcd agrees with the original on every recorded row"),
        "{}",
        said(&red)
    );

    let wrong = with_body(&stub, "def gcd(_a, _b)", "def gcd(a, b)\n  a + b\nend\n");
    let wrong = with_body(&wrong, "def halve(_n)", HALVE_BODY);
    std::fs::write(&file, &wrong).expect("write");
    let still = run(&d.0, &["test", "kazoe/kazoe.b"]);
    assert_ne!(still.status.code(), Some(0), "{}", said(&still));
    assert!(said(&still).contains("got:"), "{}", said(&still));

    let ported = with_body(&stub, "def gcd(_a, _b)", GCD_BODY);
    let ported = with_body(&ported, "def halve(_n)", HALVE_BODY);
    std::fs::write(&file, &ported).expect("write");
    let green = run(&d.0, &["test", "kazoe/kazoe.b"]);
    assert_eq!(green.status.code(), Some(0), "{}", said(&green));

    let again = run(&d.0, &["naturalize", "gcd.rs", "kazoe"]);
    assert_ne!(again.status.code(), Some(0), "{}", said(&again));
    assert!(said(&again).contains("not empty"), "{}", said(&again));
}

#[test]
fn a_crate_function_is_naturalized_through_a_path_dependency() {
    let d = Dir::new("crate");
    d.write(
        "kotoba/Cargo.toml",
        "[package]\nname = \"kotoba-lib\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[workspace]\n",
    );
    d.write("kotoba/src/lib.rs", "pub mod text;\n");
    d.write(
        "kotoba/src/text.rs",
        "pub fn twice(s: &str) -> String {\n    format!(\"{s}{s}\")\n}\n\npub fn total(xs: &[i64]) -> i64 {\n    xs.iter().sum()\n}\n",
    );
    let o = run(&d.0, &["naturalize", "kotoba::text::twice", "futatabi"]);
    assert_eq!(o.status.code(), Some(0), "{}", said(&o));
    let stub = std::fs::read_to_string(d.0.join("futatabi/futatabi.b")).expect("the bidama");
    assert!(
        stub.contains("{args: [\"abc\"], out: \"abcabc\"}"),
        "{stub}"
    );
    assert!(!stub.contains("def total"), "{stub}");
    let red = run(&d.0, &["test", "futatabi/futatabi.b"]);
    assert_ne!(red.status.code(), Some(0), "{}", said(&red));
    let ported = with_body(
        &stub,
        "def twice(_s)",
        "def twice(s)\n  \"#{s}#{s}\"\nend\n",
    );
    std::fs::write(d.0.join("futatabi/futatabi.b"), ported).expect("write");
    let green = run(&d.0, &["test", "futatabi/futatabi.b"]);
    assert_eq!(green.status.code(), Some(0), "{}", said(&green));
}
