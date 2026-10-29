//! The memo against the run it replaces: every program answers the same with
//! the memo off, cold, and warm from the store a cold run wrote
//! (`theory/BLUE-TOOLING.md` T-M).
//!
//! In process, through the same doors `blue run` uses
//! (`pipeline::run_in_surface` with the memo off, `pipeline::run_observed`
//! with it on), over a store in a scratch directory.
//!
//! Red runs, recorded 2026-10-11, each mutation reverted after:
//!
//! - a hit answering `nil` instead of the stored value: the seeded
//!   differential fails on its first program with a repeated call, and so do
//!   `fib_is_answered_by_the_memo` and the warm-run tests;
//! - the key without the arguments (the definition's hash alone): the
//!   differential fails, every call of a definition answering its first;
//! - `def_hash` ignoring callees (a callee written by name, not hash):
//!   `an_edit_to_a_callee_misses_and_an_unrelated_definition_hits` fails,
//!   the edited callee's caller answered from the old store;
//! - the store's checksum not compared: `a_damaged_entry_is_ignored` fails,
//!   the damaged value served.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use blue_lang_mondou::recall::{Plan, Policy, Recall, Report};
use blue_lang_mondou::store::{Identity, Store, DEFAULT_MAX_BYTES};
use blue_lang_runtime::pipeline::{run_in_surface, run_observed};
use blue_lang_runtime::uses::{Entry, NoLoader};
use blue_lang_runtime::Inputs;

fn scratch(name: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("blue-memo-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&p);
    p
}

/// What a run answered: its value as blue text, or its error.
fn plain(src: &str) -> String {
    match run_in_surface(Entry::anonymous(src), Inputs::new(), &NoLoader, None) {
        Ok(r) => blue_lang_runtime::literal::render_value(&r.value),
        Err(e) => format!("error: {e}"),
    }
}

/// A memoized run over the store at `dir` (none when `None`).
fn memoized(src: &str, dir: Option<&Path>, policy: Policy) -> (String, Report) {
    let store = dir.map(|d| {
        Arc::new(
            Store::open(d, Identity::from_parts(&[b"test"]), DEFAULT_MAX_BYTES).expect("store"),
        )
    });
    let mut held = None;
    let ran = run_observed(Entry::anonymous(src), Inputs::new(), &NoLoader, None, |w| {
        let m = Arc::new(Recall::new(
            Arc::clone(w.definitions),
            Plan::of(w.definitions, w.lowered, w.erased),
            store,
            None,
            policy,
        ));
        held = Some(Arc::clone(&m));
        m
    });
    let memo = held.expect("the program got past the check stage");
    let flushed = memo.flush();
    assert_eq!(flushed.error, None, "the store took the run's results");
    let answer = match ran.and_then(|o| o.outcome) {
        Ok(r) => blue_lang_runtime::literal::render_value(&r.value),
        Err(e) => format!("error: {e}"),
    };
    (answer, memo.report())
}

/// Store every result, whatever it cost, and never stop looking: the
/// differential then exercises every call.
fn eager() -> Policy {
    Policy {
        store_min: Duration::ZERO,
        window: u64::MAX,
        ..Policy::default()
    }
}

fn row<'r>(report: &'r Report, name: &str) -> &'r blue_lang_mondou::recall::Counts {
    &report
        .rows
        .iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("{name} was not cached: {report:?}"))
        .counts
}

const FIB: &str =
    "def fib(n)\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n";

#[test]
fn fib_is_answered_by_the_memo() {
    let src = format!("{FIB}\nfib(25)\n");
    let (answer, report) = memoized(&src, None, Policy::default());
    assert_eq!(answer, "75025");
    let fib = row(&report, "fib");
    assert!(fib.calls < 200, "{fib:?}");
    assert!(fib.hits > 0, "{fib:?}");
}

#[test]
fn a_warm_run_answers_from_disk_what_the_cold_run_computed() {
    let dir = scratch("warm");
    let src = format!("{FIB}\nfib(24)\n");
    let (cold, report) = memoized(&src, Some(&dir), Policy::default());
    assert_eq!(row(&report, "fib").disk_hits, 0);
    let (warm, report) = memoized(&src, Some(&dir), Policy::default());
    assert_eq!(cold, warm);
    let fib = row(&report, "fib");
    assert_eq!((fib.disk_hits, fib.misses), (1, 0), "{fib:?}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn only_the_outermost_of_a_recursion_is_written_unless_asked_again() {
    let dir = scratch("outer");
    let src = "def sum_to(n)\n  if n == 0\n    0\n  else\n    n + sum_to(n - 1)\n  end\nend\n\nsum_to(400)\n";
    let (_, report) = memoized(src, Some(&dir), eager());
    assert!(row(&report, "sum_to").stored >= 400);
    let written: Vec<_> = std::fs::read_dir(&dir)
        .expect("the store")
        .flatten()
        .flat_map(|d| std::fs::read_dir(d.path()).expect("an identity").flatten())
        .collect();
    assert_eq!(written.len(), 1, "one definition, one file");
    let len = written[0].metadata().expect("a file").len();
    assert!(len < 400, "one entry, not four hundred: {len} bytes");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_tail_call_chain_is_stored_under_its_first_call() {
    let src = "def count(n, acc)\n  if n == 0\n    acc\n  else\n    count(n - 1, acc + n)\n  end\nend\n\n[count(300, 0), count(300, 0)]\n";
    let (answer, report) = memoized(src, None, Policy::default());
    assert_eq!(answer, plain(src));
    let count = row(&report, "count");
    assert_eq!(count.hits, 1, "{count:?}");
    assert_eq!(count.stored, 1, "only the chain's first call: {count:?}");
}

#[test]
fn an_edit_to_a_callee_misses_and_an_unrelated_definition_hits() {
    let dir = scratch("edit");
    let program = |g: &str| {
        format!(
            "def g(n)\n  if n == 0\n    {g}\n  else\n    1 + g(n - 1)\n  end\nend\n\n\
             def f(n)\n  g(n) * 2\nend\n\n\
             def h(n)\n  if n == 0\n    0\n  else\n    2 + h(n - 1)\n  end\nend\n\n\
             [f(200), h(200)]\n"
        )
    };
    let before = program("0");
    let (a, _) = memoized(&before, Some(&dir), eager());
    assert_eq!(a, "[400, 400]");
    let after = program("1");
    let (b, report) = memoized(&after, Some(&dir), eager());
    assert_eq!(b, "[402, 400]", "the edit is seen, not the old answer");
    assert_eq!(
        row(&report, "f").disk_hits,
        0,
        "f reaches the edit: new key"
    );
    assert_eq!(row(&report, "g").disk_hits, 0);
    assert_eq!(row(&report, "h").disk_hits, 1, "h does not: same key");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_volatile_definition_is_never_cached() {
    let src = "def make_counter()\n  n = 0\n  fn()\n    set!(n, n + 1)\n    n\n  end\nend\n\n\
               counter = make_counter()\n\n\
               def next_id()\n  counter()\nend\n\n\
               def twice(x)\n  x * 2\nend\n\nvolatile(twice)\n\n\
               [next_id(), next_id(), next_id(), twice(2), twice(2)]\n";
    let (answer, report) = memoized(src, None, eager());
    assert_eq!(answer, "[1, 2, 3, 4, 4]");
    for name in ["next_id", "make_counter", "twice"] {
        assert!(
            report.rows.iter().all(|r| r.name != name),
            "{name} was looked up: {report:?}"
        );
    }
}

#[test]
fn a_damaged_entry_is_ignored() {
    let dir = scratch("damaged");
    let src = format!("{FIB}\nfib(22)\n");
    let (cold, _) = memoized(&src, Some(&dir), Policy::default());
    let mut entries = 0;
    for identity in std::fs::read_dir(&dir).expect("store").flatten() {
        for file in std::fs::read_dir(identity.path())
            .expect("identity")
            .flatten()
        {
            let mut bytes = std::fs::read(file.path()).expect("read");
            let mut at = 78;
            while at + 4 <= bytes.len() {
                let len = u32::from_le_bytes(bytes[at..at + 4].try_into().expect("4")) as usize;
                bytes[at + 4 + 32] ^= 0xff;
                at += 4 + len + 16;
                entries += 1;
            }
            std::fs::write(file.path(), bytes).expect("write");
        }
    }
    assert!(entries > 0, "the cold run wrote entries to damage");
    let (warm, report) = memoized(&src, Some(&dir), Policy::default());
    assert_eq!(
        cold, warm,
        "the damaged entries were recomputed, not served"
    );
    assert_eq!(
        report.damaged, entries,
        "every damaged entry was seen: {report:?}"
    );
    assert_eq!(row(&report, "fib").disk_hits, 0);
    let _ = std::fs::remove_dir_all(&dir);
}

/// A small deterministic generator (xorshift64*), so a failing program is
/// reproduced by its seed.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
}

/// A random program of pure definitions `d0 … dk`: each takes `(n, m)`,
/// stops at `n <= 0`, and calls itself with a smaller `n` and earlier
/// definitions with anything, so every one terminates. Some answer lists,
/// maps and strings, so results of every encodable shape are cached. The
/// program's value is a list of calls, some of them repeated.
fn program(seed: u64) -> String {
    let mut r = Rng(seed | 1);
    let defs = 2 + r.below(5) as usize;
    let mut src = String::new();
    for i in 0..defs {
        let leaf = match r.below(4) {
            0 => "m % 7".to_string(),
            1 => "n + m".to_string(),
            2 => format!("m * {}", 1 + r.below(3)),
            _ => "1".to_string(),
        };
        let mut terms = vec![format!(
            "first_int(d{i}(n - {}, m + {}))",
            1 + r.below(2),
            r.below(3)
        )];
        if i > 0 {
            let j = r.below(i as u64);
            terms.push(format!("first_int(d{j}(n - 1, m))"));
        }
        if r.below(2) == 0 {
            terms.push(format!(
                "length(map(fn(x) x + n end, [n, m, {}]))",
                r.below(9)
            ));
        }
        let step = terms.join(" + ");
        let body = format!("if n <= 0\n    {leaf}\n  else\n    ({step}) % 1000\n  end");
        let shaped = match r.below(4) {
            0 => format!("  x = {body}\n  [x, \"#{{n}}:#{{x}}\"]"),
            1 => format!("  x = {body}\n  {{n: n, x: x}}"),
            _ => format!("  {body}"),
        };
        src.push_str(&format!("def d{i}(n, m)\n{shaped}\nend\n\n"));
    }
    src.push_str(
        "def first_int(v)\n  if list?(v)\n    first(v)\n  elsif map?(v)\n    get(v, :x)\n  else\n    v\n  end\nend\n\n",
    );
    let mut calls = Vec::new();
    for _ in 0..(3 + r.below(6)) {
        let call = format!("d{}({}, {})", r.below(defs as u64), r.below(12), r.below(5));
        calls.push(call.clone());
        if r.below(2) == 0 {
            calls.push(call);
        }
    }
    src.push_str(&format!("[{}]\n", calls.join(", ")));
    src
}

/// **The differential.** Every seeded program answers the same with the memo
/// off, cold (default policy and storing everything), and warm from disk.
/// `BLUE_MEMO_SEED` replays one seed; `BLUE_MEMO_PROGRAMS` runs more.
#[test]
fn every_seeded_program_answers_the_same_off_cold_and_warm() {
    let count: u64 = std::env::var("BLUE_MEMO_PROGRAMS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(120);
    let seeds: Vec<u64> = match std::env::var("BLUE_MEMO_SEED")
        .ok()
        .and_then(|v| v.parse().ok())
    {
        Some(s) => vec![s],
        None => (1..=count)
            .map(|i| i.wrapping_mul(0x9E37_79B9_7F4A_7C15))
            .collect(),
    };
    let dir = scratch("differential");
    let (mut hits, mut disk_hits) = (0, 0);
    for seed in seeds {
        let src = program(seed);
        let off = plain(&src);
        assert!(
            !off.starts_with("error"),
            "seed {seed}: the program itself fails: {off}\n{src}"
        );
        let store = dir.join(seed.to_string());
        for policy in [Policy::default(), eager()] {
            let _ = std::fs::remove_dir_all(&store);
            let (cold, a) = memoized(&src, Some(&store), policy);
            let (warm, b) = memoized(&src, Some(&store), policy);
            assert_eq!(off, cold, "seed {seed}, {policy:?}: cold differs\n{src}");
            assert_eq!(off, warm, "seed {seed}, {policy:?}: warm differs\n{src}");
            hits += a.total().hits + b.total().hits;
            disk_hits += b.total().disk_hits;
        }
    }
    assert!(
        hits > 0 && disk_hits > 0,
        "hits {hits}, from disk {disk_hits}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

/// What the memo costs a call, measured: the numbers behind
/// `Policy::default` (`theory/BLUE-TOOLING.md` T-M). Run in release:
/// `cargo test --release -p blue-lang-mondou --test memo measure -- --ignored --nocapture`.
#[test]
#[ignore = "a measurement, not a gate"]
fn measure_the_cost_of_a_lookup() {
    use std::time::Instant;
    const N: i64 = 200_000;
    let time = |label: &str, src: &str, policy: Option<Policy>| {
        let mut best = Duration::MAX;
        for _ in 0..5 {
            let started = Instant::now();
            let answer = match policy {
                None => plain(src),
                Some(p) => memoized(src, None, p).0,
            };
            best = best.min(started.elapsed());
            assert!(!answer.starts_with("error"), "{answer}");
        }
        #[allow(clippy::cast_precision_loss)]
        let per = best.as_secs_f64() * 1e9 / N as f64;
        println!(
            "{label:<52} {:>9.1} ms  {per:>7.0} ns per call",
            best.as_secs_f64() * 1e3
        );
        per
    };
    let fresh = format!(
        "def inc1(x)\n  x + 1\nend\n\nreduce(fn(acc, x) acc + inc1(x) end, 0, range({N}))\n"
    );
    let same = format!(
        "def inc1(x)\n  x + 1\nend\n\nreduce(fn(acc, x) acc + inc1(5) end, 0, range({N}))\n"
    );
    let never = Policy {
        store_min: Duration::MAX,
        window: u64::MAX,
        ..Policy::default()
    };
    let always = Policy {
        store_min: Duration::ZERO,
        window: u64::MAX,
        ..Policy::default()
    };
    let off = time("memo off: inc1(x), fresh arguments", &fresh, None);
    let miss = time(
        "memo on, every call a lookup that misses",
        &fresh,
        Some(never),
    );
    let retired = time(
        "memo on, default policy (retires inc1)",
        &fresh,
        Some(Policy::default()),
    );
    let off_same = time("memo off: inc1(5), the same argument", &same, None);
    let hit = time("memo on, every call a hit", &same, Some(always));
    println!("lookup that misses: {:.0} ns over a plain call", miss - off);
    println!(
        "hit instead of the call: {:.0} ns against {:.0} ns",
        hit, off_same
    );
    println!(
        "default policy over memo off: {:.0} ns per call",
        retired - off
    );
}
