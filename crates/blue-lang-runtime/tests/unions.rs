use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{run_in_surface, RunError};
use blue_lang_runtime::uses::{Entry, Loader};
use blue_lang_syntax::union::{declared, raise, union_parts};
use blue_lang_syntax::{parse_program_documented, parse_program_tree};
use tatara_lisp_eval::Value;

const GEO: &str = "@moduledoc \"\"\"\ngeo holds shapes.\n\n    shape?(circle(1)) #=> true\n\"\"\"\n\n@doc \"\"\"\nshape is a circle or a rect.\n\n    shape?(rect(1, 2)) #=> true\n\"\"\"\nunion shape = circle(r: Int) | rect(w: Int, h: Int)\n";

struct Geo;

impl Loader for Geo {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        if name == "geo" {
            return Ok(vec![("geo.b".to_string(), GEO.to_string())]);
        }
        Err(format!("no bidama named \"{name}\""))
    }
}

fn run(src: &str) -> Result<Value, RunError> {
    run_in_surface(Entry::anonymous(src), Inputs::new(), &Geo, None).map(|r| r.value)
}

fn yes(src: &str) {
    let got = run(src).unwrap_or_else(|e| panic!("{src}\n{e}"));
    assert!(matches!(got, Value::Bool(true)), "{src}\n{got:?}");
}

fn refused(src: &str, says: &[&str]) {
    match run(src) {
        Err(RunError::Types(errors)) => {
            let all = errors.join("\n");
            assert!(all.contains("B0081"), "{all}");
            for s in says {
                assert!(all.contains(s), "{s}: {all}");
            }
        }
        other => panic!("{src}: not refused at check: {other:?}"),
    }
}

const SHAPE: &str = "union shape = circle(r) | rect(w, h) | tri(a, b, c)\n\n";

fn with_shape(body: &str) -> String {
    format!("{SHAPE}{body}")
}

fn case_of(arms: &[&str], otherwise: bool) -> String {
    let mut s = String::from("def f(s)\n  case s\n");
    for a in arms {
        s.push_str(&format!("  when {a}\n    :{}\n", a.trim_end_matches('?')));
    }
    if otherwise {
        s.push_str("  else\n    :other\n");
    }
    s.push_str("  end\nend\n\nf(rect(1, 2))\n");
    with_shape(&s)
}

#[test]
fn every_arm_is_a_record() {
    yes(&with_shape("rect(1, 2) == rect({h: 2, w: 1})"));
    yes(&with_shape("rect(1, 2).h == 2"));
    yes(&with_shape("p = rect(1, 2)\nrect(**p, w: 9) == rect(9, 2)"));
    yes(&with_shape("record_name(tri(1, 2, 3)) == \"tri\""));
    yes(&with_shape(
        "json_read(json_stringify(circle([1]))) == circle([1])",
    ));
}

#[test]
fn the_union_predicate_is_true_for_any_arm_and_nothing_else() {
    yes(&with_shape(
        "record point(x, y)\n\n[shape?(circle(1)), shape?(rect(1, 2)), shape?(tri(1, 2, 3)), shape?(point(1, 2)), shape?({r: 1}), shape?(nil)] == [true, true, true, false, false, false]",
    ));
}

#[test]
fn a_case_that_names_every_arm_runs() {
    let got = run(&case_of(&["circle?", "rect?", "tri?"], false)).unwrap();
    assert_eq!(format!("{got:?}"), format!("{:?}", run(":rect").unwrap()));
}

#[test]
fn a_case_that_misses_an_arm_is_refused_naming_each() {
    refused(
        &case_of(&["circle?"], false),
        &["`shape`", "`rect`", "`tri`"],
    );
    refused(&case_of(&["circle?", "tri?"], false), &["misses `rect`"]);
}

#[test]
fn an_else_or_the_union_predicate_covers_the_rest() {
    run(&case_of(&["circle?"], true)).unwrap();
    run(&case_of(&["shape?"], false)).unwrap();
}

#[test]
fn a_case_over_other_values_is_not_judged() {
    run(&with_shape(
        "def f(x)\n  case x\n  when 1\n    :one\n  end\nend\n\nf(2)\n",
    ))
    .unwrap();
}

#[test]
fn a_guard_return_in_a_case_arm_fills_its_else() {
    run(&with_shape(
        "def f(s)\n  case s\n  when circle?\n    return :round\n  end\n  :other\nend\n\nf(rect(1, 2))\n",
    ))
    .unwrap();
}

#[test]
fn a_union_from_a_bidama_is_read_by_its_qualified_names() {
    yes("use(\"geo\")\ngeo::shape?(geo::rect(1, 2)) and geo::rect?(geo::rect(1, 2))");
    yes("use(\"geo\")\ngeo::rect(1, 2).h == 2");
    refused(
        "use(\"geo\")\n\ndef f(s)\n  case s\n  when geo::circle?\n    1\n  end\nend\n\nf(geo::circle(1))\n",
        &["geo::rect"],
    );
}

#[test]
fn the_tree_holds_the_arms_as_records_and_the_union_as_its_predicate() {
    let src = "union shape = circle(r) | rect(w, h)\n";
    let tree = parse_program_tree(src).unwrap();
    let heads: Vec<String> = tree.iter().map(|f| f.to_sexp().to_string()).collect();
    assert_eq!(
        heads,
        [
            "(blue-record circle circle? :r)",
            "(blue-record rect rect? :w :h)",
            "(blue-union shape shape? circle? rect?)",
        ]
    );
    assert!(declared(&tree[2]).is_some());
    let raised = raise(tree);
    let written = parse_program_documented(src).unwrap();
    assert_eq!(raised.len(), 1);
    assert_eq!(raised[0].to_sexp(), written[0].to_sexp());
    assert!(union_parts(&raised[0]).is_some());
}

#[test]
fn union_stays_a_free_name() {
    yes("def union(a, b)\n  append(a, b)\nend\n\nunion([1], [2]) == [1, 2]");
    yes("union = 3\nunion == 3");
}
