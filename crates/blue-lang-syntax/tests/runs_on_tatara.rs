//! End-to-end: blue source → tatara-lisp → the real evaluator.
//!
//! These are the tests that make the thesis falsifiable. Parsing to an
//! `Sexp` that merely *looks* right proves nothing; the forms have to be
//! accepted and executed by the shipped tatara-lisp interpreter, with the
//! answers a Ruby programmer would predict.

use blue_lang_syntax::parse_program;
use tatara_lisp_eval::{install_primitives, Interpreter, Value};

/// Parse blue source, run it on the real interpreter, return the value.
fn run(src: &str) -> Value {
    let forms = parse_program(src).unwrap_or_else(|e| panic!("parse {src:?}: {e}"));
    // Round-trip through canonical text into tatara-lisp's own reader. If
    // blue emitted a tree the reader cannot read back, that is a defect in
    // the lowering and this is where it surfaces.
    let text = forms
        .iter()
        .map(|f| f.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    let spanned = tatara_lisp::read_spanned(&text)
        .unwrap_or_else(|e| panic!("tatara-lisp could not read blue's output {text:?}: {e:?}"));

    let mut interp = Interpreter::new();
    install_primitives(&mut interp);
    interp
        .eval_program(&spanned, &mut ())
        .unwrap_or_else(|e| panic!("eval {text:?}: {e}"))
}

fn int(src: &str) -> i64 {
    match run(src) {
        Value::Int(v) => v,
        other => panic!("{src:?} produced {other:?}, expected an Int"),
    }
}

#[test]
fn arithmetic_evaluates_with_ruby_precedence() {
    assert_eq!(int("1 + 2 * 3"), 7);
    assert_eq!(int("(1 + 2) * 3"), 9);
    assert_eq!(int("10 - 2 - 3"), 5);
}

#[test]
fn a_blue_function_definition_runs() {
    assert_eq!(int("def add(a, b)\n  a + b\nend\nadd(2, 3)"), 5);
}

#[test]
fn if_else_selects_the_right_branch() {
    assert_eq!(int("if 1 < 2\n  10\nelse\n  20\nend"), 10);
    assert_eq!(int("if 2 < 1\n  10\nelse\n  20\nend"), 20);
}

#[test]
fn unless_is_the_negation_and_actually_runs() {
    assert_eq!(int("unless 2 < 1\n  7\nend"), 7);
}

#[test]
fn a_multi_statement_body_runs_in_order_and_yields_the_last() {
    assert_eq!(int("def f()\n  1\n  2\n  3\nend\nf()"), 3);
}

#[test]
fn recursion_works() {
    let src = "\
def fact(n)
  if n < 2
    1
  else
    n * fact(n - 1)
  end
end
fact(5)";
    assert_eq!(int(src), 120);
}

/// The pipeline is not decoration — it composes and it executes.
#[test]
fn the_pipeline_runs() {
    let src = "\
def double(x)
  x * 2
end
def inc(x)
  x + 1
end
5 |> double |> inc";
    assert_eq!(int(src), 11);
}

#[test]
fn pipeline_threads_into_the_first_argument_at_runtime() {
    let src = "\
def sub(a, b)
  a - b
end
10 |> sub(3)";
    assert_eq!(int(src), 7);
}

/// Anti-vacuity: `run` must be able to fail. If a broken program still
/// produced a value, every assertion above would be worthless.
#[test]
#[should_panic(expected = "parse")]
fn the_harness_fails_on_unparseable_blue() {
    run("if a");
}
