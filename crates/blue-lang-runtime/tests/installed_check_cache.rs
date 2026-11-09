use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{LazyLock, Mutex};

use blue_lang_runtime::check_cache::{self, CheckStore};
use blue_lang_runtime::def_hash::DefHash;
use blue_lang_runtime::pipeline::{self, check_entry, check_entry_cached, Checking};
use blue_lang_runtime::uses::{Entry, NoLoader};

const CHECKED: &str =
    "def g(x)\n  x * 2\nend\n\ndef f(x)\n  g(x) + 1\nend\n\ntest \"f\"\n  assert f(1) == 3\nend\n";

const RUN: &str = "def h(x)\n  x + 40\nend\n\ndef k(y)\n  h(y) * 1\nend\n\nk(2)\n";

#[derive(Default)]
struct Memory {
    buckets: Mutex<HashMap<DefHash, HashMap<[u8; 32], Vec<u8>>>>,
    appended: AtomicUsize,
}

impl CheckStore for Memory {
    fn load(&self, bucket: &DefHash) -> HashMap<[u8; 32], Vec<u8>> {
        self.buckets
            .lock()
            .unwrap()
            .get(bucket)
            .cloned()
            .unwrap_or_default()
    }

    fn append(&self, bucket: &DefHash, entries: &[([u8; 32], Vec<u8>)]) {
        self.appended.fetch_add(entries.len(), Ordering::SeqCst);
        self.buckets
            .lock()
            .unwrap()
            .entry(*bucket)
            .or_default()
            .extend(entries.iter().cloned());
    }
}

static STORE: LazyLock<Memory> = LazyLock::new(Memory::default);

fn appended() -> usize {
    STORE.appended.load(Ordering::SeqCst)
}

fn checked(src: &str) -> String {
    let c =
        check_entry(Entry::anonymous(src), &NoLoader, None, Checking::WithTests).expect("checks");
    assert!(c.outcome.ok(), "{:?}", c.outcome.diagnostics);
    format!("{:?} {:?}", c.outcome.diagnostics, c.lowered())
}

fn ran(src: &str) -> String {
    format!("{:?}", pipeline::run(src).expect("runs").value)
}

#[test]
fn every_check_and_run_goes_through_the_installed_store() {
    let plain_check = checked(CHECKED);
    let plain_run = ran(RUN);
    assert_eq!(appended(), 0, "nothing is installed yet");

    assert!(check_cache::installed().is_none());
    assert!(check_cache::install(&*STORE, [7; 32]));
    assert!(
        !check_cache::install(&*STORE, [8; 32]),
        "the first store stays"
    );
    assert!(check_cache::installed().is_some());

    assert_eq!(checked(CHECKED), plain_check);
    let after_check = appended();
    assert!(
        after_check > 0,
        "check_entry wrote nothing to the installed store"
    );
    assert_eq!(checked(CHECKED), plain_check);
    assert_eq!(appended(), after_check, "a second check recomputed a form");

    assert_eq!(ran(RUN), plain_run);
    let after_run = appended();
    assert!(after_run > after_check, "run's check stage wrote nothing");
    assert_eq!(ran(RUN), plain_run);
    assert_eq!(appended(), after_run, "a second run recomputed a form");

    let explicit = check_entry_cached(
        Entry::anonymous("def fresh(x)\n  x\nend\n"),
        &NoLoader,
        None,
        Checking::WithTests,
        None,
    )
    .expect("checks");
    assert!(explicit.outcome.ok());
    assert_eq!(appended(), after_run, "an explicit None asks for no cache");
}
