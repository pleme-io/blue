use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::LazyLock;

use blue_lang_runtime::check_cache::{self, CheckStore};
use blue_lang_runtime::def_hash::DefHash;

#[derive(Default)]
struct Late {
    opens: AtomicBool,
    asked: AtomicUsize,
}

impl CheckStore for Late {
    fn load(&self, _: &DefHash) -> HashMap<[u8; 32], Vec<u8>> {
        HashMap::new()
    }

    fn append(&self, _: &DefHash, _: &[([u8; 32], Vec<u8>)]) {}

    fn identity(&self) -> Option<[u8; 32]> {
        self.asked.fetch_add(1, Ordering::SeqCst);
        self.opens.load(Ordering::SeqCst).then_some([3; 32])
    }
}

static STORE: LazyLock<Late> = LazyLock::new(Late::default);

#[test]
fn a_deferred_store_is_asked_its_identity_only_when_a_check_runs() {
    assert!(check_cache::install_deferred(&*STORE));
    assert_eq!(STORE.asked.load(Ordering::SeqCst), 0, "install asked");
    assert!(
        check_cache::installed().is_none(),
        "a store that cannot open caches nothing"
    );
    assert_eq!(STORE.asked.load(Ordering::SeqCst), 1);
    STORE.opens.store(true, Ordering::SeqCst);
    assert!(check_cache::installed().is_some());
}
