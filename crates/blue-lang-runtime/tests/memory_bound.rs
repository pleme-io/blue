//! The live-byte bound (`max_alloc_bytes`, `crate::memory`), at every door
//! that holds an evaluation to one: a run, a process it spawns, a session
//! request, a project rule.
//!
//! This binary installs `alloc::Counting` as `blue` does and names one bound
//! of 8 MiB for both doors before any interpreter exists. Each program builds
//! a list of `[x, x]` pairs sized as a multiple of the bound, from the bytes
//! one pair costs on this build ([`pair_bytes`]), so the tests follow the
//! bound and not a list representation that may change. Each refusal test has
//! an under-the-bound twin: a bound that refused everything turns the twin
//! red, one that refused nothing turns the refusal red.
//!
//! ## Red runs, recorded (2026-10-30)
//!
//! - `memory::held` made to run its closure unarmed: the six refusal tests
//!   failed (the runs returned their counts, the session answered `Ok`, the
//!   rule `Ok([])`, the supervised hog finished normally so the root's wait
//!   for its supervisor deadlocked); the three twins stayed green.
//! - `Node::slice_held` made to run every slice uncharged: only the
//!   supervised-process test failed, on the same deadlock.
//! - `Node::drive` made to run without `apart`: only the root-credit test
//!   failed, the root returning `3235` because its child's freed list was
//!   credited to it.
//! - the bound read as 0 in `memory::held`: every test failed, the twins
//!   included, on `live-byte budget of 0 exceeded`.

use blue_lang_runtime::alloc::{allocations, Counting};
use blue_lang_runtime::literal::render_value;
use blue_lang_runtime::pipeline::{self, RunError};
use blue_lang_runtime::project_rules::{RuleFailure, RuleProgram, RULE_STEPS};
use blue_lang_runtime::session::{Config, Session, Stop};
use blue_lang_runtime::uses::{Entry, NoLoader};
use blue_lang_runtime::ExecutionBounds;

#[global_allocator]
static ALLOC: Counting = Counting;

const BOUND: u64 = 8 << 20;

fn bounded() {
    blue_lang_runtime::set_execution_bounds(ExecutionBounds {
        max_alloc_bytes: Some(BOUND),
        guest_max_alloc_bytes: Some(BOUND),
        ..ExecutionBounds::DEFAULT
    });
}

fn pairs_src(n: u64) -> String {
    format!("map((x) -> [x, x], range(0, {}))", grouped(n))
}

/// `n` as blue writes it: six or more digits grouped by threes (B0033).
fn grouped(n: u64) -> String {
    let digits = n.to_string();
    if digits.len() < 6 {
        return digits;
    }
    let head = digits.len() % 3;
    let mut out = digits[..head].to_string();
    for (i, chunk) in digits.as_bytes()[head..].chunks(3).enumerate() {
        if head > 0 || i > 0 {
            out.push('_');
        }
        out.push_str(std::str::from_utf8(chunk).expect("ascii digits"));
    }
    out
}

/// The bytes one more pair adds to a list a run holds, measured as the
/// difference of two runs so the interpreter each run builds cancels out.
fn pair_bytes() -> u64 {
    bounded();
    let held = |n: u64| {
        let before = allocations().expect("this binary counts");
        let run = pipeline::run(&pairs_src(n)).expect("well under the bound");
        let after = allocations().expect("this binary counts");
        drop(run);
        after.since(before).retained()
    };
    held(1);
    let per = (held(400) - held(200)) / 200;
    u64::try_from(per).expect("a pair costs bytes")
}

/// How many pairs hold `bytes`.
fn pairs(bytes: u64) -> u64 {
    bytes / pair_bytes()
}

fn hog() -> String {
    format!("length({})", pairs_src(pairs(4 * BOUND)))
}

fn small() -> (String, String) {
    let n = pairs(BOUND / 8);
    (format!("length({})", pairs_src(n)), n.to_string())
}

fn refusal_of(src: &str) -> String {
    match pipeline::run(src) {
        Ok(run) => panic!(
            "refused past {BOUND} live bytes, got {}",
            render_value(&run.value)
        ),
        Err(e @ RunError::Eval(_)) => {
            assert_eq!(e.exit_status(), 1, "a clean error, not a breach: {e}");
            e.to_string()
        }
        Err(other) => panic!("a runtime refusal, got {other}"),
    }
}

#[test]
fn a_run_past_its_bound_is_refused_with_memory_exhausted() {
    let message = refusal_of(&hog());
    assert!(
        message.contains("fatal memory-exhausted")
            && message.contains(&format!("live-byte budget of {BOUND} exceeded")),
        "{message}"
    );
}

#[test]
fn no_rescue_catches_the_refusal() {
    let message = refusal_of(&format!("begin\n  {}\nrescue _\n  :caught\nend", hog()));
    assert!(message.contains("memory-exhausted"), "{message}");
}

#[test]
fn a_run_under_its_bound_returns_what_it_always_did() {
    let (src, n) = small();
    let run = pipeline::run(&src).expect("an eighth of the bound");
    assert_eq!(render_value(&run.value), n);
}

/// The child exits a runaway naming the bound, its monitor sees the reason,
/// its supervisor restarts it until its intensity runs out, and the root that
/// spawned it, held to the same bound on its own account, is not refused.
#[test]
fn a_process_past_its_bound_exits_a_runaway_its_supervisor_sees() {
    let n = grouped(pairs(4 * BOUND));
    let src = format!(
        "def hog(n)
  length(map((x) -> [x, x], range(0, n)))
end

sup = supervisor(:one_for_one, [[hog, [{n}]]], 2)
c = nth(0, children(sup))
m = monitor(c)
s = monitor(sup)
[receive([:down, m, :_, :_]), receive([:down, s, :_, :_])]"
    );
    let run = pipeline::run(&src).expect("the root holds nothing of its child's");
    let value = render_value(&run.value);
    let reason = format!("[:runaway, \"memory-exhausted: live-byte budget of {BOUND} exceeded\"]");
    assert!(
        value.contains(&reason),
        "the child's monitor sees {reason}: {value}"
    );
    assert!(
        value.contains(":gave_up"),
        "the supervisor restarted it until it gave up: {value}"
    );
}

#[test]
fn a_process_under_its_bound_exits_normally() {
    let n = grouped(pairs(BOUND / 8));
    let run = pipeline::run(&format!(
        "def hog(n)\n  length(map((x) -> [x, x], range(0, n)))\nend\n\np = spawn(hog, [{n}])\nm = monitor(p)\nreceive()"
    ))
    .expect("runs");
    assert_eq!(render_value(&run.value), "[:down, 1, 1, :normal]");
}

/// What a child frees is never credited to the root: a child that returns
/// three quarters of the bound and is reaped leaves the root its whole bound,
/// so the root building five quarters is refused.
#[test]
fn a_root_is_not_credited_with_what_its_children_free() {
    let kept = grouped(pairs(BOUND / 4 * 3));
    let src = format!(
        "def keep(n)\n  map((x) -> [x, x], range(0, n))\nend\n\np = spawn(keep, [{kept}])\nm = monitor(p)\nreceive()\nlength({})",
        pairs_src(pairs(BOUND / 4 * 5))
    );
    let message = refusal_of(&src);
    assert!(message.contains("memory-exhausted"), "{message}");
}

/// A session request past the bound is refused, and the session keeps
/// answering: the interrupt the bound set is cleared.
#[test]
fn a_session_request_past_its_bound_is_refused_and_the_session_answers_on() {
    let (hog, (small, n)) = (hog(), small());
    let config = Config::new(Box::new(NoLoader));
    assert_eq!(
        config.max_alloc_bytes,
        Some(BOUND),
        "a session takes guest_max_alloc_bytes"
    );
    let mut s = Session::new(config);
    assert_eq!(
        s.eval(&hog, None, None).result,
        Err(Stop::MemoryExhausted { limit: BOUND })
    );
    assert_eq!(s.eval(&small, None, None).result, Ok(n));
}

fn rule(n: u64) -> String {
    format!(
        "def r(form)\n  if length({}) > 0\n    []\n  else\n    nil\n  end\nend\n",
        pairs_src(n)
    )
}

fn form() -> tatara_lisp::Spanned {
    blue_lang_syntax::parse_program_tree("f(1)\n")
        .expect("parse")
        .remove(0)
}

/// A project rule past the bound is a failure of the rule, never a crash of
/// the check, and the next call runs.
#[test]
fn a_project_rule_past_its_bound_fails_and_the_next_call_runs() {
    let (big, little) = (pairs(4 * BOUND), pairs(BOUND / 8));
    let mut hog =
        RuleProgram::load(Entry::anonymous(&rule(big)), &NoLoader, RULE_STEPS).expect("loads");
    match hog.run("r", &form(), RULE_STEPS) {
        Err(RuleFailure::Exhausted(m)) => assert!(m.contains("memory-exhausted"), "{m}"),
        other => panic!("a memory refusal, got {other:?}"),
    }
    let mut small =
        RuleProgram::load(Entry::anonymous(&rule(little)), &NoLoader, RULE_STEPS).expect("loads");
    assert_eq!(small.run("r", &form(), RULE_STEPS), Ok(Vec::new()));
    assert!(matches!(
        hog.run("r", &form(), RULE_STEPS),
        Err(RuleFailure::Exhausted(_))
    ));
}

#[test]
fn grouping_matches_the_canonical_literal() {
    assert_eq!(grouped(10_000), "10000");
    assert_eq!(grouped(100_000), "100_000");
    assert_eq!(grouped(1_234_567), "1_234_567");
}
