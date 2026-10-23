use blue_lang_runtime::dispatch::{KINDS, MASTER_VERBS};
use blue_lang_runtime::docs::NAMES;
use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{check_entry, run_in_surface, Checking};
use blue_lang_runtime::uses::{Entry, Loader};
use tatara_lisp_eval::Value;

struct Mem;

const FZ: &str = "\
def put(m, k, v)
  assoc(m, k, v)
end

def read(src, n?)
  [src, n]
end

def helper()
  1
end

space_for(:map, \"fz\")
verb_for(\"fz\", \"put\", put)
verb_for(\"fz\", \"read\", read)
";

const OTHER: &str = "\
def read(src, n?)
  [:other, src, n]
end

verb_for(\"other\", \"read\", read)
";

const JISHO: &str = include_str!("../../../bidamas/jisho/jisho.b");
const RETSU: &str = include_str!("../../../bidamas/retsu/retsu.b");
const KAZU: &str = include_str!("../../../bidamas/kazu/kazu.b");

impl Loader for Mem {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        let src = match name {
            "fz" => FZ,
            "other" => OTHER,
            "jisho" => JISHO,
            "retsu" => RETSU,
            "kazu" => KAZU,
            _ => return Err(format!("no bidama named \"{name}\"")),
        };
        Ok(vec![(format!("{name}.b"), src.to_string())])
    }
}

fn shown(src: &str) -> String {
    let wrapped = format!("{src}\n");
    match run_in_surface(Entry::anonymous(&wrapped), Inputs::new(), &Mem, None) {
        Ok(out) => match out.value {
            Value::Str(s) => s.to_string(),
            other => format!("{other:?}"),
        },
        Err(e) => format!("ERR {e:?}"),
    }
}

fn caught(body: &str) -> String {
    shown(&format!(
        "use(\"fz\")\n\nbegin\n  {body}\nrescue e\n  to_s([e.kind, e.message])\nend"
    ))
}

#[test]
fn a_plain_map_goes_to_the_space_that_owns_maps() {
    assert_eq!(shown("use(\"fz\")\n\nto_s(put({}, :a, 1))"), "{a: 1}");
}

#[test]
fn a_tagged_subject_reaches_its_handler_untagged_with_the_other_arguments() {
    assert_eq!(
        shown("use(\"fz\")\n\nto_s(read(in_space(\"fz\", \"p\"), 3))"),
        "[\"p\", 3]"
    );
}

#[test]
fn an_omitted_optional_argument_stays_omitted() {
    assert_eq!(
        shown("use(\"fz\")\n\nto_s(read(in_space(\"fz\", \"p\")))"),
        "[\"p\", nil]"
    );
}

#[test]
fn the_tag_chooses_between_two_spaces_with_the_same_verb() {
    assert_eq!(
        shown("use(\"fz\")\nuse(\"other\")\n\nto_s([read(in_space(\"fz\", 1)), read(in_space(\"other\", 1))])"),
        "[[1, nil], [:other, 1, nil]]"
    );
}

#[test]
fn a_nil_subject_inside_a_tag_reaches_the_handler_as_nil() {
    assert_eq!(
        shown("use(\"fz\")\n\nto_s(read(in_space(\"fz\", nil), 2))"),
        "[nil, 2]"
    );
}

#[test]
fn a_subject_no_space_owns_raises_usage_naming_the_kind() {
    let s = caught("read(\"/etc/hosts\")");
    assert!(s.contains("usage"), "{s}");
    assert!(s.contains("no space owns a string subject"), "{s}");
    assert!(s.contains("in_space"), "{s}");
}

#[test]
fn a_nil_subject_has_no_space() {
    let s = caught("put(nil, :a, 1)");
    assert!(
        s.contains("no space owns a nil subject") || s.contains("no space owns"),
        "{s}"
    );
}

#[test]
fn a_space_without_the_verb_raises_usage_and_names_the_bidama_to_load() {
    let s = caught("delete({}, :a)");
    assert!(s.contains("usage"), "{s}");
    assert!(s.contains("space fz has no handler"), "{s}");
    assert!(
        s.contains("use(\\\"fz\\\")") || s.contains("use(\"fz\")"),
        "{s}"
    );
}

#[test]
fn the_error_lists_the_spaces_that_do_hold_a_handler() {
    let s = shown(
        "use(\"fz\")\nuse(\"other\")\n\nbegin\n  read(in_space(\"nowhere\", 1))\nrescue e\n  e.message\nend",
    );
    assert!(s.contains("space nowhere has no handler"), "{s}");
    assert!(s.contains("loaded: fz, other"), "{s}");
}

#[test]
fn a_space_that_was_never_loaded_has_no_handlers_to_list() {
    let s = shown("begin\n  read(in_space(\"ghost\", 1))\nrescue e\n  e.message\nend");
    assert!(s.contains("no space has loaded one"), "{s}");
}

#[test]
fn only_master_verbs_can_be_registered() {
    let s = shown("begin\n  verb_for(\"fz\", \"fetch\", (x) -> x)\nrescue e\n  to_s([e.kind, e.message])\nend");
    assert!(s.contains("usage"), "{s}");
    assert!(s.contains("fetch is not a dispatched master verb"), "{s}");
}

#[test]
fn a_handler_must_be_a_function() {
    let s =
        shown("begin\n  verb_for(\"fz\", \"read\", 3)\nrescue e\n  to_s([e.kind, e.message])\nend");
    assert!(s.contains("usage"), "{s}");
    assert!(s.contains("the handler is a function"), "{s}");
}

#[test]
fn a_space_and_a_verb_must_be_non_empty_strings() {
    let a = shown("begin\n  verb_for(\"\", \"read\", (x) -> x)\nrescue e\n  e.message\nend");
    assert!(a.contains("the space is a non-empty string"), "{a}");
    let b = shown("begin\n  verb_for(\"fz\", :read, (x) -> x)\nrescue e\n  e.message\nend");
    assert!(b.contains("the verb is a non-empty string"), "{b}");
    let c = shown("begin\n  in_space(\"\", 1)\nrescue e\n  e.message\nend");
    assert!(c.contains("the space is a non-empty string"), "{c}");
}

#[test]
fn registering_a_handler_again_replaces_it() {
    assert_eq!(
        shown("verb_for(\"s\", \"read\", (x) -> 1)\nverb_for(\"s\", \"read\", (x) -> 2)\n\nread(in_space(\"s\", 0))"),
        "Int(2)"
    );
}

#[test]
fn a_kind_must_be_one_of_the_closed_set() {
    let s = shown("begin\n  space_for(:vector, \"x\")\nrescue e\n  to_s([e.kind, e.message])\nend");
    assert!(s.contains("usage"), "{s}");
    assert!(s.contains("the kind is one of"), "{s}");
    for k in KINDS {
        assert!(s.contains(k), "{k} missing from {s}");
    }
}

#[test]
fn a_kind_belongs_to_one_space() {
    let s = shown(
        "space_for(:map, \"x\")\nbegin\n  space_for(:map, \"y\")\nrescue e\n  e.message\nend",
    );
    assert!(s.contains("kind map already belongs to space x"), "{s}");
    assert_eq!(
        shown("space_for(:map, \"x\")\nspace_for(:map, \"x\")"),
        "Nil"
    );
}

#[test]
fn space_of_reads_the_tag_then_the_kind() {
    assert_eq!(shown("space_of({})"), "Nil");
    assert_eq!(shown("space_for(:map, \"x\")\nspace_of({})"), "x");
    assert_eq!(
        shown("space_for(:map, \"x\")\nspace_of(in_space(\"y\", {}))"),
        "y"
    );
    assert_eq!(shown("space_of(nil)"), "Nil");
    assert_eq!(shown("space_of(\"p\")"), "Nil");
}

#[test]
fn a_subject_cannot_move_between_spaces_but_may_be_tagged_again_in_its_own() {
    let a = shown("begin\n  in_space(\"b\", in_space(\"a\", 1))\nrescue e\n  e.message\nend");
    assert!(a.contains("already in space a, not b"), "{a}");
    assert_eq!(
        shown("to_s(in_space(\"a\", in_space(\"a\", 1)) == in_space(\"a\", 1))"),
        "true"
    );
}

#[test]
fn a_map_that_only_looks_like_a_tag_is_still_a_plain_map() {
    assert_eq!(
        shown("space_for(:map, \"x\")\nspace_of({space: \"y\", of: 1, extra: 2})"),
        "x"
    );
    assert_eq!(
        shown("space_for(:map, \"x\")\nspace_of({space: 1, of: 2})"),
        "x"
    );
}

#[test]
fn jisho_answers_the_store_verbs_for_a_plain_map() {
    let pre = "use(\"jisho\")\n\n";
    assert_eq!(
        shown(&format!("{pre}to_s(put({{\"a\" => 1}}, \"b\", 2))")),
        "{\"a\" => 1, \"b\" => 2}"
    );
    assert_eq!(
        shown(&format!("{pre}has?({{\"a\" => nil}}, \"a\")")),
        "Bool(true)"
    );
    assert_eq!(shown(&format!("{pre}has?({{}}, \"a\")")), "Bool(false)");
    assert_eq!(
        shown(&format!("{pre}need({{\"a\" => 1}}, \"a\")")),
        "Int(1)"
    );
    assert_eq!(
        shown(&format!(
            "{pre}to_s(update({{\"n\" => 1}}, \"n\", (x) -> x + 1))"
        )),
        "{\"n\" => 2}"
    );
    assert_eq!(
        shown(&format!("{pre}to_s(delete({{\"a\" => 1}}, \"a\"))")),
        "{}"
    );
    assert_eq!(shown(&format!("{pre}to_s(delete({{}}, \"a\"))")), "{}");
}

#[test]
fn jisho_need_and_update_raise_not_found_through_the_dispatcher() {
    let pre = "use(\"jisho\")\n\n";
    let n = shown(&format!(
        "{pre}begin\n  need({{}}, \"z\")\nrescue e\n  e.kind\nend"
    ));
    assert_eq!(n, "Keyword(:not_found)");
    let u = shown(&format!(
        "{pre}begin\n  update({{}}, \"z\", (x) -> x)\nrescue e\n  e.kind\nend"
    ));
    assert_eq!(u, "Keyword(:not_found)");
}

#[test]
fn without_the_space_loaded_a_plain_map_has_no_owner() {
    let s = shown("begin\n  put({}, :a, 1)\nrescue e\n  e.message\nend");
    assert!(s.contains("no space owns a map subject"), "{s}");
}

#[test]
fn a_bare_master_verb_after_use_is_not_the_implicit_reference_error() {
    let src = "use(\"fz\")\n\nput({}, :a, 1)\n";
    let checked = check_entry(Entry::anonymous(src), &Mem, None, Checking::Program).expect("check");
    assert!(
        checked.outcome.diagnostics.is_empty(),
        "{:?}",
        checked.outcome.diagnostics
    );
}

#[test]
fn another_bare_name_of_a_loaded_bidama_stays_the_implicit_reference_error() {
    let src = "use(\"fz\")\n\nhelper()\n";
    let checked = check_entry(Entry::anonymous(src), &Mem, None, Checking::Program).expect("check");
    let codes: Vec<String> = checked
        .outcome
        .diagnostics
        .iter()
        .map(|d| format!("{:?}", d.code))
        .collect();
    assert_eq!(codes, vec!["B0012".to_string()], "{codes:?}");
}

#[test]
fn every_master_verb_is_a_contract_row_and_a_documented_name() {
    let table = include_str!("../../../docs/verbs/contracts.tsv");
    for verb in MASTER_VERBS {
        let row = table
            .lines()
            .find(|l| l.split('\t').next() == Some(verb))
            .unwrap_or_else(|| panic!("{verb} has no row in contracts.tsv"));
        let status = row.split('\t').last().unwrap_or("");
        assert!(
            status == "stdlib" || status == "decided",
            "{verb} is {status} in contracts.tsv"
        );
        assert!(
            NAMES.iter().any(|n| n.name == *verb),
            "{verb} has no docs row"
        );
    }
    for name in ["verb_for", "space_for", "in_space", "space_of"] {
        assert!(
            NAMES.iter().any(|n| n.name == name),
            "{name} has no docs row"
        );
    }
}
