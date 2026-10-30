//! The witness: what a run's calls of each loose definition showed, and the
//! signature [`witness::lock`] reads off them (`blue_lang_mondou::witness`).
//!
//! Every program runs through `pipeline::run_observed`, the door `blue run`,
//! `blue test` and the language server's witness pass share.

use std::collections::BTreeSet;
use std::path::PathBuf;
use std::sync::Arc;

use blue_lang_check::Ty;
use blue_lang_mondou::store::Identity;
use blue_lang_mondou::witness::{
    self, Locked, Observation, Shape, Witness, Witnessed, Witnesses, MAX_SEEN,
};
use blue_lang_mondou::DefHash;
use blue_lang_runtime::pipeline::run_observed;
use blue_lang_runtime::uses::{Entry, NoLoader};
use blue_lang_runtime::Inputs;

fn scratch(name: &str) -> PathBuf {
    let p = std::env::temp_dir().join(format!("blue-witness-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&p);
    p
}

/// What running `src` showed, and the hash of each definition by its name.
fn witnessed(src: &str) -> (Witnessed, impl Fn(&str) -> DefHash) {
    let mut held = None;
    let mut hashes = None;
    let ran = run_observed(Entry::anonymous(src), Inputs::new(), &NoLoader, None, |w| {
        let h = blue_lang_mondou::hash_checked(w.program, w.lowered);
        let witness = Arc::new(Witness::new(w.lowered, &h, None));
        hashes = Some(h);
        held = Some(Arc::clone(&witness));
        witness
    })
    .expect("the program checks");
    assert!(
        ran.outcome.is_ok(),
        "the program runs: {:?}",
        ran.outcome.err()
    );
    let hashes = hashes.expect("hashed");
    let hash = move |name: &str| {
        hashes
            .of_key(&format!("%root/{name}"))
            .unwrap_or_else(|| panic!("no definition {name}"))
            .hash
    };
    (held.expect("watched").witnessed(), hash)
}

fn seen(w: &Witnessed, def: DefHash) -> Vec<String> {
    w.of(&def)
        .map(|s| s.iter().map(ToString::to_string).collect())
        .unwrap_or_default()
}

#[test]
fn a_run_records_the_types_each_call_showed() {
    let (w, hash) = witnessed("def inc(x)\n  x + 1\nend\n\ninc(1)\ninc(41)\n");
    assert_eq!(seen(&w, hash("inc")), vec!["Int -> Int"]);
    assert_eq!(
        witness::lock(w.of(&hash("inc")).expect("seen"), 1),
        Some(Locked {
            params: vec![Ty::Int],
            ret: Ty::Int
        })
    );
}

/// Red run (2026-10-30): an `Exit::Raised` recorded with a `?` result:
/// `left: ["Int -> Int", "Str -> ?", "Nil -> ?"]`.
#[test]
fn a_call_that_raised_is_not_recorded() {
    let (w, hash) = witnessed(
        "def half(x)\n  x / 2\nend\n\nhalf(4)\nhalf(\"a\") rescue nil\nhalf(nil) rescue nil\n",
    );
    assert_eq!(seen(&w, hash("half")), vec!["Int -> Int"]);
}

/// Red run (2026-10-30): a frame that tail-called dropped instead of
/// carried: `f` has no observation, `left: []`.
#[test]
fn the_first_call_of_a_tail_chain_is_recorded_with_what_the_chain_returned() {
    let (w, hash) = witnessed("def g(x)\n  [x]\nend\n\ndef f(x)\n  g(x)\nend\n\nf(1)\n");
    assert_eq!(seen(&w, hash("f")), vec!["Int -> List(Int)"]);
    assert_eq!(seen(&w, hash("g")), vec!["Int -> List(Int)"]);
}

#[test]
fn an_empty_list_joins_the_list_type_its_siblings_showed() {
    let (w, hash) = witnessed("def same(xs)\n  xs\nend\n\nsame([1, 2])\nsame([])\n");
    assert_eq!(
        seen(&w, hash("same")),
        vec!["List() -> List()", "List(Int) -> List(Int)"]
    );
    let int_list = Ty::List(Box::new(Ty::Int));
    assert_eq!(
        witness::lock(w.of(&hash("same")).expect("seen"), 1),
        Some(Locked {
            params: vec![int_list.clone()],
            ret: int_list
        })
    );
}

#[test]
fn nothing_locks_what_no_type_names_or_no_call_showed() {
    let (w, hash) = witnessed(
        "def id(x)\n  x\nend\n\ndef empty()\n  []\nend\n\n\
         id(1)\nid(\"a\")\nid({a: 1})\nempty\n",
    );
    let id = w.of(&hash("id")).expect("seen");
    assert_eq!(
        id.iter().map(ToString::to_string).collect::<Vec<_>>(),
        vec!["Int -> Int", "Str -> Str", "? -> ?"]
    );
    assert_eq!(witness::lock(id, 1), None);
    assert_eq!(seen(&w, hash("empty")), vec!["-> List()"]);
    assert_eq!(witness::lock(w.of(&hash("empty")).expect("seen"), 0), None);
    assert_eq!(witness::lock(&BTreeSet::new(), 1), None);
    let only_int = BTreeSet::from([Observation {
        args: vec![Shape::Int],
        ret: Shape::Int,
    }]);
    assert_eq!(witness::lock(&only_int, 2), None, "another arity");
}

#[test]
fn shapes_mixed_inside_a_list_show_no_type() {
    let (w, hash) = witnessed("def same(xs)\n  xs\nend\n\nsame([1, \"a\"])\nsame([[1], []])\n");
    assert_eq!(
        seen(&w, hash("same")),
        vec!["List(List(Int)) -> List(List(Int))", "? -> ?"]
    );
}

#[test]
fn an_observation_reads_back_as_it_was_written() {
    for o in [
        Observation {
            args: vec![Shape::Int, Shape::List(Some(Box::new(Shape::Str)))],
            ret: Shape::List(None),
        },
        Observation {
            args: vec![],
            ret: Shape::Sym,
        },
        Observation::varied(),
    ] {
        assert_eq!(Observation::parse(&o.to_string()), Some(o));
    }
    for bad in [
        "",
        "Int",
        "Int ->",
        "-> Int Int",
        "Num -> Int",
        "List(Int -> Int",
    ] {
        assert_eq!(Observation::parse(bad), None, "{bad:?}");
    }
}

#[test]
fn past_max_seen_a_definition_is_varied_and_locks_nothing() {
    let def = DefHash([7; 32]);
    let mut w = Witnessed::default();
    let mut shape = Shape::Int;
    for _ in 0..=MAX_SEEN {
        shape = Shape::List(Some(Box::new(shape)));
        w.insert(
            def,
            Observation {
                args: vec![Shape::List(None)],
                ret: shape.clone(),
            },
        );
    }
    let seen = w.of(&def).expect("seen");
    assert!(seen.contains(&Observation::varied()));
    assert_eq!(witness::lock(seen, 1), None);
}

/// Red run (2026-10-30): `record` appending without reading the bucket: the
/// second record writes 1 again, `left: 1, right: 0`.
#[test]
fn the_store_keeps_each_definitions_observations_for_the_next_run() {
    let dir = scratch("store");
    let (w, hash) = witnessed("def inc(x)\n  x + 1\nend\n\ninc(1)\n");
    let store = Witnesses::open(&dir, Identity::from_parts(&[b"witness test"])).expect("store");
    assert_eq!(store.record(&w).expect("recorded"), 1);
    assert_eq!(store.record(&w).expect("recorded"), 0, "already there");
    let again = Witnesses::open(&dir, Identity::from_parts(&[b"witness test"])).expect("store");
    assert_eq!(
        again.load(&hash("inc")),
        BTreeSet::from([Observation {
            args: vec![Shape::Int],
            ret: Shape::Int
        }])
    );
    let (edited, edited_hash) = witnessed("def inc(x)\n  x + 2\nend\n\ninc(\"a\") rescue nil\n");
    assert!(edited.is_empty());
    assert_ne!(
        edited_hash("inc"),
        hash("inc"),
        "an edit is another definition"
    );
    assert!(again.load(&edited_hash("inc")).is_empty());
    let other = Witnesses::open(&dir, Identity::from_parts(&[b"another blue"])).expect("store");
    assert!(other.load(&hash("inc")).is_empty(), "another evaluator");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_store_past_max_seen_records_the_definition_as_varied() {
    let dir = scratch("varied");
    let store = Witnesses::open(&dir, Identity::from_parts(&[b"witness test"])).expect("store");
    let def = DefHash([9; 32]);
    let mut shape = Shape::Int;
    for _ in 0..MAX_SEEN + 2 {
        shape = Shape::List(Some(Box::new(shape)));
        let mut w = Witnessed::default();
        w.insert(
            def,
            Observation {
                args: vec![],
                ret: shape.clone(),
            },
        );
        store.record(&w).expect("recorded");
    }
    let loaded = store.load(&def);
    assert!(loaded.contains(&Observation::varied()));
    assert_eq!(loaded.len(), MAX_SEEN + 1);
    let _ = std::fs::remove_dir_all(&dir);
}
