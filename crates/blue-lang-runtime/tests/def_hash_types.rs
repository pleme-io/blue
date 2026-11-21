use blue_lang_runtime::def_hash::{hash_program, DefHash};
use blue_lang_runtime::pipeline::{check_entry, lower, Checking};
use blue_lang_runtime::uses::{Entry, NoLoader};

fn hashes(src: &str) -> blue_lang_runtime::def_hash::DefHashes {
    let checked =
        check_entry(Entry::anonymous(src), &NoLoader, None, Checking::Program).expect("checks");
    assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
    hash_program(&lower(&checked.program, &checked.names))
}

fn hash_of(src: &str, name: &str) -> DefHash {
    hashes(src)
        .of_key(&format!("%root/{name}"))
        .unwrap_or_else(|| panic!("{name} is not defined"))
        .hash
}

const RECORD: &str = "record pt(x: Int, y: Int)\n\ndef sx(p: pt) -> Int\n  p.x + 1\nend\n";

const UNION: &str = "union sh = sq(s: Int) | ci(r: Int)\n\ndef id(v: sh) -> sh\n  v\nend\n";

/// A record or union a definition names only in its signature is one of the
/// definitions it reaches: an edit to the type moves its hash, so a native
/// artifact built for the old type is never answered for the new one.
#[test]
fn a_type_named_only_in_a_signature_is_reached_and_its_edit_moves_the_hash() {
    let h = hashes(RECORD);
    let sx = h.of_key("%root/sx").expect("sx");
    let pt = h
        .defs()
        .iter()
        .position(|d| d.key == "%root/pt")
        .expect("pt");
    assert!(
        sx.calls.contains(&pt),
        "sx reaches pt through its signature"
    );
    assert_ne!(
        hash_of(RECORD, "sx"),
        hash_of(&RECORD.replace("y: Int", "y: Float"), "sx"),
        "an edit to the record moves the hash of a definition that only names it"
    );
    assert_ne!(
        hash_of(UNION, "id"),
        hash_of(&UNION.replace("r: Int", "r: Str"), "id"),
        "an edit to the union moves it too"
    );
    let other = "record pt(x: Int, y: Int)\n\ndef sx(p) -> Int\n  p.x + 1\nend\n";
    assert_eq!(
        hash_of(other, "sx"),
        hash_of(&other.replace("y: Int", "y: Float"), "sx"),
        "a definition that never names the record keeps its hash"
    );
}
