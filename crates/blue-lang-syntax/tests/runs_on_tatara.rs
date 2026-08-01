//! End-to-end: blue source → tatara-lisp → the real evaluator.
//!
//! These are the tests that make the thesis falsifiable. Parsing to an
//! `Sexp` that merely *looks* right proves nothing; the forms have to be
//! accepted and executed by the shipped tatara-lisp interpreter, with the
//! answers a Ruby programmer would predict.

use blue_lang_syntax::parse_program;
use tatara_lisp_eval::Value;

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

    let mut interp = blue_lang_runtime::interpreter_hostless();
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

// ---------------------------------------------------------------------------
// The operator-coverage gate.
//
// This is the gate whose absence let `==` ship. `a == b` parsed cleanly,
// formatted cleanly, and lowered to `(== a b)` — a symbol nothing binds — so
// the defect surfaced only when a program actually *ran* one, which is the
// worst possible place to find it.
//
// It is not enough to check that every operator has a callee: a callee is a
// string, and a string can name a primitive that does not exist. The gate
// therefore RESOLVES each callee by evaluating it in the real interpreter.
// ---------------------------------------------------------------------------

/// Operands that are legal for every operator in the table — numeric, so
/// arithmetic and comparison both work, and non-zero so `/` and `mod` are
/// defined.
const LHS: i64 = 6;
const RHS: i64 = 3;

/// **Every infix operator must lower to a callee the interpreter resolves.**
///
/// Adding a row to `INFIX` with a misspelled or nonexistent callee takes this
/// red, naming the operator.
#[test]
fn every_infix_operator_lowers_to_a_callee_the_interpreter_resolves() {
    let mut broken: Vec<(String, String)> = Vec::new();

    for i in blue_lang_syntax::INFIX {
        let src = format!("{LHS} {} {RHS}", i.op);
        let forms = match parse_program(&src) {
            Ok(f) => f,
            Err(e) => {
                broken.push((i.op.to_string(), format!("parse: {e}")));
                continue;
            }
        };
        let text = forms
            .iter()
            .map(|f| f.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        let spanned = match tatara_lisp::read_spanned(&text) {
            Ok(s) => s,
            Err(e) => {
                broken.push((i.op.to_string(), format!("reader: {e:?}")));
                continue;
            }
        };
        let mut interp = blue_lang_runtime::interpreter_hostless();
        if let Err(e) = interp.eval_program(&spanned, &mut ()) {
            broken.push((i.op.to_string(), format!("eval {text}: {e}")));
        }
    }

    assert!(
        broken.is_empty(),
        "these operators do not lower to anything runnable: {broken:#?}"
    );
}

/// Anti-vacuity: the gate must be running over a table that actually holds
/// the operators, and each must lower to something OTHER than its surface
/// spelling where the two differ — otherwise a table of pass-throughs would
/// satisfy the test above while `==` was still broken.
#[test]
fn the_operator_table_is_populated_and_actually_renames_where_needed() {
    let ops: Vec<&str> = blue_lang_syntax::INFIX.iter().map(|i| i.op).collect();
    for expected in ["==", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "%", "&&", "||"] {
        assert!(ops.contains(&expected), "operator {expected} is missing from INFIX");
    }
    let renamed: Vec<(&str, &str)> = blue_lang_syntax::INFIX
        .iter()
        .filter(|i| i.op != i.callee)
        .map(|i| (i.op, i.callee))
        .collect();
    assert!(
        renamed.contains(&("==", "=")) && renamed.contains(&("!=", "not=")),
        "the surface spellings that differ from tatara's must be renamed: {renamed:?}"
    );
}

/// And the semantics, not just the resolution: a renamed operator must mean
/// what a Ruby programmer expects. Resolution alone would be satisfied by
/// lowering `==` to `+`.
#[test]
fn renamed_comparison_operators_mean_what_they_say() {
    assert!(matches!(run("1 == 1"), Value::Bool(true)));
    assert!(matches!(run("1 == 2"), Value::Bool(false)));
    assert!(matches!(run("1 != 2"), Value::Bool(true)));
    assert!(matches!(run("1 != 1"), Value::Bool(false)));
    assert_eq!(int("7 % 3"), 1);
    assert!(matches!(run("true && false"), Value::Bool(false)));
    assert!(matches!(run("true || false"), Value::Bool(true)));
}

// NOTE on annotated defs. `(define-typed …)` is READABLE by tatara-lisp's
// reader — it is an ordinary list — but not EVALUABLE, because tatara has no
// such form. Type erasure is what makes it runnable, and erasure is a
// pipeline stage, so the "annotating changes nothing else" claim is asserted
// where the pipeline lives:
// `blue_lang_runtime::pipeline::annotating_buys_analysis_and_changes_nothing_else`.
// Asserting it here would have to re-implement erasure in the test harness,
// which is how a second, drifting copy of a pipeline stage gets born.
