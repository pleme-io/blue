//! Allocations are counted per thread and attribute to the definition that
//! made them.
//!
//! This binary installs `blue_lang_runtime::alloc::Counting` the way `blue`
//! would, then checks the three things `blue profile` will lean on: the counter
//! reads exactly what a known allocation costs, another thread's work is not
//! charged here, and snapshots taken through tatara-lisp-eval's call hook (the
//! one mechanism `blue profile` is built on) give each definition its own
//! allocations, a cheap one near zero and one that builds a list in proportion
//! to the list.
//!
//! The unit test in `src/alloc.rs` is the other half: a binary that does NOT
//! install the counter answers `None`, never zero.
//!
//! The tests run in parallel safely because the counter is per thread: the
//! harness's other threads never reach a window measured here.
//!
//! ## Red runs, recorded (2026-10-10)
//!
//! - `charge` made a no-op: all three fail, the first with
//!   `left: Allocations { count: 0, bytes: 0 }`.
//! - one process-wide atomic counter instead of the thread-locals: only the
//!   thread arm fails, `spawning and joining costs a handful here, never the
//!   other thread's 1000: Allocations { count: 1006, bytes: 88184 }`.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use blue_lang_runtime::alloc::{allocations, Allocations, Counting};
use tatara_lisp_eval::observe::{Call, CallObserver, Exit};
use tatara_lisp_eval::Value;

#[global_allocator]
static ALLOC: Counting = Counting;

fn now() -> Allocations {
    allocations().expect("this binary installs the counting allocator")
}

#[test]
fn a_known_allocation_is_counted_exactly() {
    let before = now();
    let v: Vec<u64> = Vec::with_capacity(100);
    let after = now();
    drop(v);
    assert_eq!(
        after.since(before),
        Allocations {
            count: 1,
            bytes: 800
        }
    );
}

#[test]
fn another_threads_allocations_are_not_charged_here() {
    let before = now();
    let other = std::thread::spawn(|| {
        let start = now();
        let v: Vec<Vec<u8>> = (0..1000).map(|_| vec![0u8; 64]).collect();
        drop(v);
        now().since(start)
    })
    .join()
    .expect("the other thread runs");
    let here = now().since(before);
    assert!(
        other.count >= 1000,
        "the other thread counted its own: {other:?}"
    );
    assert!(
        here.count < 100,
        "spawning and joining costs a handful here, never the other thread's 1000: {here:?}"
    );
}

/// The integration `blue profile` needs, in miniature: snapshot at the end of
/// `enter`, difference at the start of `leave`, so the observer's own
/// bookkeeping falls outside every window.
#[derive(Default)]
struct PerDefinition {
    stack: Mutex<Vec<Allocations>>,
    inclusive: Mutex<HashMap<String, Allocations>>,
}

impl CallObserver for PerDefinition {
    fn enter(&self, _call: &Call<'_>, _args: &[Value]) -> Option<Value> {
        let mut stack = self.stack.lock().unwrap();
        stack.reserve(1);
        stack.push(now());
        None
    }

    fn leave(&self, call: &Call<'_>, _exit: Exit<'_>) {
        let end = now();
        let start = self.stack.lock().unwrap().pop().expect("balanced");
        let name = call
            .name
            .map_or_else(|| "fn".to_string(), |n| n.to_string());
        *self.inclusive.lock().unwrap().entry(name).or_default() += end.since(start);
    }
}

#[test]
fn each_definition_is_charged_its_own_allocations() {
    let mut host = ();
    let mut interp = blue_lang_runtime::interpreter(&mut host);
    let observer = Arc::new(PerDefinition::default());
    interp.set_call_observer(Some(observer.clone()));
    let src = "(define (small x) (+ x 1)) \
               (define (grow n) (range 0 n)) \
               (small 1) (grow 2000) (small 2)";
    let forms = tatara_lisp_eval::read_spanned(src).expect("reads");
    interp.eval_program(&forms, &mut host).expect("runs");

    let inclusive = observer.inclusive.lock().unwrap().clone();
    let small = inclusive["small"];
    let grow = inclusive["grow"];
    eprintln!("small (2 calls): {small:?}; grow 2000: {grow:?}");
    assert!(
        grow.bytes >= 2000 * 48,
        "a 2000-element list is at least 2000 values of 48 bytes: {grow:?}"
    );
    assert!(
        small.bytes * 20 < grow.bytes,
        "an addition must not be charged for the list another definition built: \
         small {small:?}, grow {grow:?}"
    );
}
