use std::cell::RefCell;
use std::collections::{BTreeSet, HashMap};
use std::path::PathBuf;

use blue_lang_mondou::store::{Identity, Store, DEFAULT_MAX_BYTES};
use blue_lang_runtime::check_cache::{CheckCache, CheckStore, Pass};
use blue_lang_runtime::def_hash::{defined, DefHash};
use blue_lang_runtime::pipeline::{check_entry, check_entry_cached, Checked, Checking};
use blue_lang_runtime::uses::{Entry, NoLoader};

const BASE: &str = "def g(x)\n  x * 2\nend\n\ndef f(x)\n  g(x) + 1\nend\n\ndef h(x)\n  x - 1\nend\n\ndef k(y)\n  y + 7\nend\n";

const A: [u8; 32] = [1; 32];
const B: [u8; 32] = [2; 32];

#[derive(Default)]
struct Memory(RefCell<HashMap<DefHash, HashMap<[u8; 32], Vec<u8>>>>);

impl CheckStore for Memory {
    fn load(&self, bucket: &DefHash) -> HashMap<[u8; 32], Vec<u8>> {
        self.0.borrow().get(bucket).cloned().unwrap_or_default()
    }

    fn append(&self, bucket: &DefHash, entries: &[([u8; 32], Vec<u8>)]) {
        self.0
            .borrow_mut()
            .entry(*bucket)
            .or_default()
            .extend(entries.iter().cloned());
    }
}

struct Run {
    checked: Checked,
    names: BTreeSet<String>,
    resolved: BTreeSet<String>,
}

fn named(checked: &Checked, at: &[usize]) -> BTreeSet<String> {
    at.iter()
        .map(|i| {
            defined(&checked.program.forms()[*i])
                .map_or_else(|| format!("form {i}"), |(n, _)| n.to_string())
        })
        .collect()
}

fn run(src: &str, store: &dyn CheckStore, identity: [u8; 32]) -> Run {
    let cache = CheckCache::new(store, identity);
    let checked = check_entry_cached(
        Entry::anonymous(src),
        &NoLoader,
        None,
        Checking::WithTests,
        Some(&cache),
    )
    .expect("checks");
    cache.flush();
    let names = named(&checked, &cache.tally(Pass::Names).checked);
    let resolved = named(&checked, &cache.tally(Pass::Resolve).checked);
    Run {
        checked,
        names,
        resolved,
    }
}

fn set(names: &[&str]) -> BTreeSet<String> {
    names.iter().map(|n| (*n).to_string()).collect()
}

#[test]
fn a_cold_run_checks_every_definition_and_a_warm_run_none() {
    let store = Memory::default();
    assert_eq!(run(BASE, &store, A).names, set(&["f", "g", "h", "k"]));
    let warm = run(BASE, &store, A);
    assert!(warm.names.is_empty(), "{:?}", warm.names);
    assert!(warm.resolved.is_empty(), "{:?}", warm.resolved);
}

#[test]
fn a_callee_edit_checks_its_caller_again() {
    let store = Memory::default();
    run(BASE, &store, A);
    let edited = run(&BASE.replace("x * 2", "x * 3"), &store, A);
    assert_eq!(edited.names, set(&["f", "g"]));
    assert_eq!(edited.resolved, set(&["g"]));
}

#[test]
fn an_unrelated_edit_checks_no_other_definition() {
    let store = Memory::default();
    run(BASE, &store, A);
    let edited = run(&BASE.replace("x - 1", "x - 2"), &store, A);
    assert_eq!(edited.names, set(&["h"]));
    assert_eq!(edited.resolved, set(&["h"]));
}

#[test]
fn a_result_under_another_engine_identity_is_refused() {
    let store = Memory::default();
    run(BASE, &store, A);
    let other = run(BASE, &store, B);
    assert_eq!(other.names, set(&["f", "g", "h", "k"]));
    assert_eq!(other.resolved, set(&["f", "g", "h", "k"]));
    assert!(run(BASE, &store, A).names.is_empty());
}

fn scratch(name: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("blue-check-cache-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&p);
    p
}

#[test]
fn a_store_file_copied_under_another_identity_is_refused() {
    let root = scratch("copied");
    let a = Identity::from_parts(&[b"engine a"]);
    let b = Identity::from_parts(&[b"engine b"]);
    let first = Store::open(&root, a, DEFAULT_MAX_BYTES).expect("opens");
    run(BASE, &first, a.0);
    assert!(run(BASE, &first, a.0).names.is_empty());
    let second = Store::open(&root, b, DEFAULT_MAX_BYTES).expect("opens");
    for e in std::fs::read_dir(first.dir()).expect("lists").flatten() {
        std::fs::copy(e.path(), second.dir().join(e.file_name())).expect("copies");
    }
    assert_eq!(run(BASE, &second, b.0).names, set(&["f", "g", "h", "k"]));
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn a_warm_run_reports_what_an_uncached_run_reports() {
    let src = "def g(x)\n  y = 1\n  x * 2\nend\n\ndef f(x)\n  g(x) + 1\nend\n\ndef bad()\n  nope_name(1)\nend\n\ntest \"f\"\n  assert f(1) == 3\nend\n";
    let plain = check_entry(Entry::anonymous(src), &NoLoader, None, Checking::WithTests);
    let store = Memory::default();
    let cold = run(src, &store, A);
    let warm = run(src, &store, A);
    match plain {
        Ok(plain) => {
            for got in [&cold.checked, &warm.checked] {
                assert_eq!(got.outcome.diagnostics, plain.outcome.diagnostics);
                assert_eq!(
                    got.lowered()
                        .iter()
                        .map(|f| f.to_sexp().to_string())
                        .collect::<Vec<_>>(),
                    plain
                        .lowered()
                        .iter()
                        .map(|f| f.to_sexp().to_string())
                        .collect::<Vec<_>>()
                );
                assert_eq!(
                    got.call_explicit_forms()
                        .iter()
                        .map(|f| f.to_sexp().to_string())
                        .collect::<Vec<_>>(),
                    plain
                        .call_explicit_forms()
                        .iter()
                        .map(|f| f.to_sexp().to_string())
                        .collect::<Vec<_>>()
                );
            }
        }
        Err(e) => panic!("{e}"),
    }
}
