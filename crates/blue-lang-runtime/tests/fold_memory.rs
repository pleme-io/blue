use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};

use blue_lang_runtime::check_cache::{self, CheckStore};
use blue_lang_runtime::def_hash::DefHash;

#[derive(Default)]
struct Kept {
    entries: Mutex<HashMap<DefHash, HashMap<[u8; 32], Vec<u8>>>>,
}

impl CheckStore for Kept {
    fn load(&self, bucket: &DefHash) -> HashMap<[u8; 32], Vec<u8>> {
        self.entries
            .lock()
            .unwrap()
            .get(bucket)
            .cloned()
            .unwrap_or_default()
    }

    fn append(&self, bucket: &DefHash, entries: &[([u8; 32], Vec<u8>)]) {
        self.entries
            .lock()
            .unwrap()
            .entry(*bucket)
            .or_default()
            .extend(entries.iter().cloned());
    }

    fn identity(&self) -> Option<[u8; 32]> {
        Some([7; 32])
    }
}

static STORE: LazyLock<Kept> = LazyLock::new(Kept::default);

const PROGRAM: &str = "def fib(n: Int) -> Int\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n\ndef small(x: Int) -> Int\n  x + fib(12)\nend\n\ndef large(x: Int) -> Int\n  x + fib(22)\nend\n";

fn folded() -> Vec<String> {
    let checked = blue_lang_runtime::pipeline::check_entry(
        blue_lang_runtime::uses::Entry::anonymous(PROGRAM),
        &blue_lang_runtime::uses::NoLoader,
        None,
        blue_lang_runtime::pipeline::Checking::Program,
    )
    .expect("checks");
    let lowered = blue_lang_runtime::pipeline::lower(&checked.program, &checked.names);
    let fused = blue_lang_runtime::erase::erase_fused(&lowered);
    let out = blue_lang_runtime::fold::fold(fused.forms, &lowered);
    out.forms.iter().map(|f| f.to_sexp().to_string()).collect()
}

#[test]
fn a_fold_is_decided_once_per_definition_and_recalled_after() {
    assert!(check_cache::install(&*STORE, [7; 32]));
    let first = folded();
    assert!(first.iter().any(|f| f.contains("144")), "{first:?}");
    assert!(
        first.iter().any(|f| f.contains("(%root/fib 22)")),
        "{first:?}"
    );
    let kept: Vec<Vec<u8>> = STORE
        .entries
        .lock()
        .unwrap()
        .values()
        .flat_map(|m| m.values().cloned())
        .collect();
    assert!(
        kept.contains(&b"144".to_vec()) && kept.contains(&Vec::new()),
        "the literal and the give-up are both kept"
    );
    for m in STORE.entries.lock().unwrap().values_mut() {
        for v in m.values_mut() {
            if *v == b"144".to_vec() {
                *v = b"999".to_vec();
            }
        }
    }
    let second = folded();
    assert!(
        second.iter().any(|f| f.contains("999")),
        "the second fold answers from what was kept, not by running the call again: {second:?}"
    );
    assert!(
        second.iter().any(|f| f.contains("(%root/fib 22)")),
        "{second:?}"
    );
}
