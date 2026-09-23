//! Blue authors Rust types: a blue program's value compiles into a real
//! `#[derive(TataraDomain)]` struct.
//!
//! The struct below is an ordinary TataraDomain, exactly what any Rust crate in
//! the fleet declares. Nothing about it knows blue exists; the bridge is
//! entirely `blue_lang_runtime::domain`.

use blue_lang_runtime::domain::{compile, domain_form, DomainError};
use tatara_lisp::{Atom, DeriveTataraDomain, Sexp};

#[derive(Debug, PartialEq, DeriveTataraDomain)]
#[tatara(keyword = "defreplica")]
struct Replica {
    name: String,
    max_replicas: i64,
    enabled: bool,
    weight: f64,
    tags: Vec<String>,
    region: Option<String>,
}

#[test]
fn a_blue_map_compiles_into_a_rust_domain_type() {
    let r: Replica = compile(
        r#"{name: "api", max_replicas: 3, enabled: true, weight: 0.5, tags: ["web", "edge"], region: "sa-east-1"}"#,
    )
    .expect("compiles");
    assert_eq!(
        r,
        Replica {
            name: "api".into(),
            max_replicas: 3,
            enabled: true,
            weight: 0.5,
            tags: vec!["web".into(), "edge".into()],
            region: Some("sa-east-1".into()),
        }
    );
}

#[test]
fn the_spec_can_compute_because_it_is_a_program() {
    // The reason to author a domain in blue rather than in a data file: the
    // values can be computed, with the whole language.
    let r: Replica = compile(
        "base = 2\n\
         zones = [\"a\", \"b\", \"c\"]\n\
         {name: \"worker\", max_replicas: base * length(zones), enabled: base > 1, weight: 1.5, tags: zones}\n",
    )
    .expect("compiles");
    assert_eq!(r.max_replicas, 6);
    assert!(r.enabled);
    assert_eq!(r.tags, vec!["a", "b", "c"]);
    assert_eq!(r.region, None, "an absent optional field is None");
}

#[test]
fn blue_spelling_meets_lisp_spelling_in_one_canonical_form() {
    // `max_replicas` (blue cannot write `-`) arrives as `:max-replicas`, the
    // head is the domain keyword, and keys are sorted, so one value always
    // yields one form.
    let value = blue_lang_runtime::run(r#"{name: "api", max_replicas: 3}"#)
        .expect("runs")
        .value;
    let form = domain_form("defreplica", &value).expect("form");
    let Sexp::List(items) = form else { panic!("a list") };
    assert_eq!(items[0], Sexp::Atom(Atom::Symbol("defreplica".into())));
    assert_eq!(items[1], Sexp::Atom(Atom::Keyword("max-replicas".into())));
    assert_eq!(items[2], Sexp::Atom(Atom::Int(3)));
    assert_eq!(items[3], Sexp::Atom(Atom::Keyword("name".into())));
    assert_eq!(items[4], Sexp::Atom(Atom::Str("api".into())));
}

#[test]
fn a_nested_map_becomes_a_keyword_list() {
    // The shape the derive reads for struct-valued fields.
    let value = blue_lang_runtime::run(r#"{limits: {cpu_millis: 500}}"#)
        .expect("runs")
        .value;
    let Sexp::List(items) = domain_form("defx", &value).expect("form") else {
        panic!("a list")
    };
    assert_eq!(
        items[2],
        Sexp::List(vec![
            Sexp::Atom(Atom::Keyword("cpu-millis".into())),
            Sexp::Atom(Atom::Int(500)),
        ])
    );
}

#[test]
fn an_unknown_field_is_refused_by_the_domain_naming_it() {
    let err = compile::<Replica>(
        r#"{name: "api", max_replicas: 3, enabled: true, weight: 0.5, tags: [], colour: "blue"}"#,
    )
    .expect_err("an unknown field must be refused");
    let DomainError::Refused { keyword, message } = err else {
        panic!("expected Refused, got {err:?}")
    };
    assert_eq!(keyword, "defreplica");
    assert!(message.contains("colour"), "the refusal names the field: {message}");
}

#[test]
fn a_missing_required_field_is_refused() {
    let err = compile::<Replica>(r#"{name: "api"}"#).expect_err("missing fields");
    assert!(matches!(err, DomainError::Refused { .. }), "{err:?}");
}

#[test]
fn only_a_map_can_author_a_domain() {
    let err = compile::<Replica>("[1, 2, 3]").expect_err("a list is not a domain");
    assert!(matches!(err, DomainError::NotAMap { found: "a list" }), "{err:?}");
}

#[test]
fn a_string_key_is_not_a_field_label() {
    let err = compile::<Replica>(r#"{"name" => "api"}"#).expect_err("string key");
    assert!(matches!(err, DomainError::KeyNotALabel { .. }), "{err:?}");
}

#[test]
fn a_program_that_does_not_run_says_so() {
    let err = compile::<Replica>("{name: ").expect_err("parse error");
    assert!(matches!(err, DomainError::Run(_)), "{err:?}");
}
