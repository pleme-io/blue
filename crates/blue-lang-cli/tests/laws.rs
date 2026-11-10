//! **Solver-checked laws** (HORIZON H6): `blue test` checks each typed
//! `law_…` definition by the solver where its body is linear integer
//! arithmetic, by drawn calls where it is not, and names which one checked it.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const CLAMP: &str = "def clamp(x: Int, lo: Int, hi: Int) -> Int
  if x < lo
    lo
  elsif x > hi
    hi
  else
    x
  end
end

def law_clamp_in_range(x: Int, lo: Int, hi: Int) -> Bool
  lo > hi or clamp(x, lo, hi) >= lo and clamp(x, lo, hi) <= hi
end
";

const IDENTITY: &str = "
def law_clamp_is_identity(x: Int, lo: Int, hi: Int) -> Bool
  clamp(x, lo, hi) == x
end
";

const PRODUCT: &str = "
def law_product_commutes(a: Int, b: Int) -> Bool
  a * b == b * a
end
";

const LISTS: &str = "def law_append_adds_lengths(xs: List(Int), ys: List(Int)) -> Bool
  length(append(xs, ys)) == length(xs) + length(ys)
end

def law_take_keeps_n(xs: List(Int), n: Int) -> Bool
  length(take(n, xs)) == n
end
";

fn place(name: &str) -> PathBuf {
    let dir =
        Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("laws-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir
}

fn run(name: &str, src: &str, set: &[(&str, &str)]) -> Output {
    let file = place(name).join("clamp.b");
    std::fs::write(&file, src).expect("fixture");
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.arg("test").arg("--no-cache").arg(&file);
    for var in [
        "BLUE_PATH",
        "BLUE_CONFIG",
        "BLUE_TIER",
        "BLUE_PROPERTY_SEED",
        "BLUE_LAWS",
    ] {
        c.env_remove(var);
    }
    c.envs(set.iter().copied());
    c.output().expect("blue test runs")
}

fn test(name: &str, src: &str, laws: Option<&str>) -> Output {
    match laws {
        Some(s) => run(name, src, &[("BLUE_LAWS", s)]),
        None => run(name, src, &[]),
    }
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

/// A law the solver proves passes as proved, and the tally says so.
///
/// Red run (2026-11-10): with `Backend::Cooper` answering `Unknown` for every
/// formula, the tally read `1 law(s): 0 proved, 0 refuted, 1 tested`.
#[test]
fn a_law_the_solver_proves_is_green_and_named_proved() {
    let o = test("proved", CLAMP, None);
    let out = text(&o);
    assert!(o.status.success(), "{out}");
    assert!(
        out.contains("1 law(s): 1 proved, 0 refuted, 0 tested, 0 unchecked"),
        "{out}"
    );
}

/// A law the solver refutes is red at the counterexample it found, printed as
/// the call that breaks it.
///
/// Red run (2026-11-10): with `Backend::Cooper` answering `Unsat` for every
/// formula, the false law was named `proved (cooper)`; only the drawn calls
/// beside the proof failed it.
#[test]
fn a_law_the_solver_refutes_is_red_at_its_counterexample() {
    let o = test("refuted", &format!("{CLAMP}{IDENTITY}"), None);
    let out = text(&o);
    assert!(!o.status.success(), "{out}");
    assert!(
        out.contains("@law `law_clamp_is_identity`: refuted (cooper) at x = "),
        "{out}"
    );
    assert!(out.contains("assert law_clamp_is_identity("), "{out}");
    assert!(out.contains("1 proved, 1 refuted"), "{out}");
}

/// Without a solver the same true law is tested, and tested never reads as
/// proved.
#[test]
fn without_a_solver_a_law_is_tested_never_proved() {
    let o = test("tested", CLAMP, Some("tested"));
    let out = text(&o);
    assert!(o.status.success(), "{out}");
    assert!(out.contains("0 proved, 0 refuted, 1 tested"), "{out}");
}

/// A law outside linear arithmetic falls back to drawn calls and stays tested.
#[test]
fn a_law_outside_the_fragment_is_tested() {
    let o = test("outside", &format!("{CLAMP}{PRODUCT}"), None);
    let out = text(&o);
    assert!(o.status.success(), "{out}");
    assert!(out.contains("1 proved, 0 refuted, 1 tested"), "{out}");
}

/// A law over list lengths is proved and its drawn lists agree; a false one is
/// red at a list built to the length the solver chose.
#[test]
fn a_list_length_law_is_proved_and_a_false_one_is_red_at_a_built_list() {
    let o = test("lists", LISTS, None);
    let out = text(&o);
    assert!(!o.status.success(), "{out}");
    assert!(
        !out.contains("FAIL @law `law_append_adds_lengths`"),
        "{out}"
    );
    assert!(
        out.contains("FAIL @law `law_take_keeps_n`: refuted (cooper) at xs = ["),
        "{out}"
    );
    assert!(out.contains("assert law_take_keeps_n(["), "{out}");
    assert!(out.contains("2 law(s): 1 proved, 1 refuted"), "{out}");
}

/// A law no check can take is named unchecked and the file still runs; so
/// does a proved law with draws off, its block asserting nothing.
#[test]
fn an_unchecked_law_and_a_proof_without_draws_leave_the_file_running() {
    let src = "def law_float(a: Int, f: Float) -> Bool\n  a + 1 > a or f == f\nend\n";
    let o = test("unchecked", src, None);
    let out = text(&o);
    assert!(o.status.success(), "{out}");
    assert!(
        out.contains("1 law(s): 0 proved, 0 refuted, 0 tested, 1 unchecked"),
        "{out}"
    );
    let o = run("undrawn", CLAMP, &[("BLUE_PROPERTY_SEED", "off")]);
    let out = text(&o);
    assert!(o.status.success(), "{out}");
    assert!(out.contains("1 law(s): 1 proved"), "{out}");
}

/// `BLUE_LAWS=off` turns the law blocks off and leaves the file as it ran.
#[test]
fn laws_off_runs_no_law_block() {
    let src = format!("{CLAMP}\ntest \"clamp\"\n  assert clamp(5, 0, 3) == 3\nend\n");
    let o = test("off", &src, Some("off"));
    let out = text(&o);
    assert!(o.status.success(), "{out}");
    assert!(!out.contains("law(s)"), "{out}");
}
