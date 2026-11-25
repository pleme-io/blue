use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::{LazyLock, Mutex};

use blue_lang_runtime::check_cache::{self, CheckStore};
use blue_lang_runtime::def_hash::DefHash;

#[derive(Default)]
struct Kept {
    entries: Mutex<HashMap<DefHash, HashMap<[u8; 32], Vec<u8>>>>,
    loaded: Mutex<Vec<DefHash>>,
}

impl CheckStore for Kept {
    fn load(&self, bucket: &DefHash) -> HashMap<[u8; 32], Vec<u8>> {
        self.loaded.lock().unwrap().push(*bucket);
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
        Some([9; 32])
    }
}

static STORE: LazyLock<Kept> = LazyLock::new(Kept::default);

const TALLY: &str = "def tally(xs)\n  reduce((a, x) -> a + x, 0, filter((x) -> x > 2, map((x) -> x * 7, xs)))\nend\n\ndef lone(xs)\n  map((x) -> x + 1, xs)\nend\n";

const TOTAL: &str = "def total(xs)\n  reduce((a, x) -> a + x, 0, map((x) -> x * 3, xs))\nend\n";

struct Ran {
    forms: Vec<String>,
    hashes: Vec<DefHash>,
    added: BTreeMap<DefHash, Vec<[u8; 32]>>,
    loaded: Vec<DefHash>,
}

fn keys() -> BTreeMap<DefHash, BTreeSet<[u8; 32]>> {
    STORE
        .entries
        .lock()
        .unwrap()
        .iter()
        .map(|(b, m)| (*b, m.keys().copied().collect()))
        .collect()
}

fn saturated(src: &str) -> Ran {
    let checked = blue_lang_runtime::pipeline::check_entry(
        blue_lang_runtime::uses::Entry::anonymous(src),
        &blue_lang_runtime::uses::NoLoader,
        None,
        blue_lang_runtime::pipeline::Checking::Program,
    )
    .expect("checks");
    let lowered = blue_lang_runtime::pipeline::lower(&checked.program, &checked.names);
    let hashes = blue_lang_runtime::def_hash::hash_program(&lowered)
        .defs()
        .iter()
        .map(|d| d.hash)
        .collect();
    let erased = blue_lang_runtime::erase::unfused(&lowered);
    let before = keys();
    STORE.loaded.lock().unwrap().clear();
    let out = blue_lang_runtime::saturation::program(
        erased,
        &lowered,
        &blue_lang_runtime::saturation::unmeasured(),
    );
    let added = keys()
        .into_iter()
        .filter_map(|(b, ks)| {
            let new: Vec<[u8; 32]> = ks
                .difference(before.get(&b).unwrap_or(&BTreeSet::new()))
                .copied()
                .collect();
            (!new.is_empty()).then_some((b, new))
        })
        .collect();
    Ran {
        forms: out.forms.iter().map(|f| f.to_sexp().to_string()).collect(),
        hashes,
        added,
        loaded: STORE.loaded.lock().unwrap().clone(),
    }
}

#[test]
fn a_saturation_is_kept_with_its_definition_and_a_run_reads_only_its_own() {
    assert!(check_cache::install(&*STORE, [9; 32]));
    let tally = saturated(TALLY);
    assert_eq!(
        tally.added.keys().copied().collect::<Vec<_>>(),
        [tally.hashes[0]],
        "the chain's choice is kept with tally, and the lone map keeps nothing"
    );
    let [choice] = tally.added[&tally.hashes[0]][..] else {
        panic!("one choice: {:?}", tally.added);
    };

    let total = saturated(TOTAL);
    assert_eq!(
        total.loaded,
        [total.hashes[0]],
        "a run reads the buckets of its own definitions and no other program's"
    );

    let was = {
        let mut entries = STORE.entries.lock().unwrap();
        let kept = entries
            .get_mut(&tally.hashes[0])
            .and_then(|m| m.get_mut(&choice))
            .expect("tally's choice");
        let was = kept.clone();
        *kept = if was == b"fused" {
            b"kept".to_vec()
        } else {
            b"fused".to_vec()
        };
        was
    };
    let again = saturated(TALLY);
    assert_eq!(
        again.forms[0].contains("%fuse0_"),
        was == b"kept",
        "the second run takes the choice it recalls: {:?}",
        again.forms
    );
    assert!(again.added.is_empty(), "{:?}", again.added);
}
