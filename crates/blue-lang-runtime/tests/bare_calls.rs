use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{check_entry, run, run_in_surface, Checking};
use blue_lang_runtime::uses::{Entry, Loader};
use std::path::Path;

struct Mem(&'static [(&'static str, &'static str)]);

impl Loader for Mem {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.0
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(n, s)| vec![(format!("{n}.b"), (*s).to_string())])
            .ok_or_else(|| format!("no bidama named \"{name}\""))
    }
}

const NONE: Mem = Mem(&[]);

fn shown(src: &str) -> String {
    let out = run(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
    blue_lang_runtime::literal::render_value(&out.value)
}

fn shown_with(src: &str, loader: &dyn Loader) -> String {
    let out = run_in_surface(Entry::anonymous(src), Inputs::new(), loader, None)
        .unwrap_or_else(|e| panic!("{src:?}: {e}"));
    blue_lang_runtime::literal::render_value(&out.value)
}

fn failure(src: &str) -> String {
    run(src).map(|_| ()).expect_err(src).to_string()
}

fn lowered(src: &str, loader: &dyn Loader) -> Vec<String> {
    let checked = check_entry(Entry::anonymous(src), loader, None, Checking::WithTests)
        .unwrap_or_else(|e| panic!("{src:?}: {e}"));
    blue_lang_runtime::pipeline::lower(&checked.program, &checked.names)
        .iter()
        .map(|f| f.to_sexp().to_string())
        .collect()
}

fn codes_in_file(src: &str) -> Vec<String> {
    let entry = Entry {
        path: Some(Path::new("stored.b")),
        text: src,
    };
    check_entry(entry, &NONE, None, Checking::WithTests)
        .expect("checks")
        .outcome
        .diagnostics
        .iter()
        .map(|d| d.code.as_str().to_string())
        .collect()
}

const ANSWER: &str = "def answer()\n  42\nend\n\n";

#[test]
fn a_bare_zero_parameter_definition_is_called() {
    assert_eq!(shown(&format!("{ANSWER}answer")), "42");
    assert_eq!(shown(&format!("{ANSWER}answer + 1")), "43");
}

#[test]
fn bare_and_parenthesized_lower_to_one_tree() {
    let bare = lowered(&format!("{ANSWER}[answer, answer + 1]"), &NONE);
    let called = lowered(&format!("{ANSWER}[answer(), answer() + 1]"), &NONE);
    assert_eq!(bare, called);
    assert_eq!(
        bare.last().map(String::as_str),
        Some("(list (%root/answer) (+ (%root/answer) 1))")
    );
}

#[test]
fn a_zero_parameter_builtin_is_called_bare() {
    assert_eq!(shown("integer?(now_ms)"), "true");
    assert_eq!(shown("now_ms > 0"), "true");
    assert_eq!(shown("integer?(self)"), "true");
}

#[test]
fn a_bool_returned_by_a_bare_call_is_tested_not_the_function() {
    let src = "def no()\n  false\nend\n\nif no\n  :taken\nelse\n  :not_taken\nend";
    assert_eq!(shown(src), ":not_taken");
}

#[test]
fn a_local_or_parameter_of_the_same_name_is_its_value() {
    let param = format!("{ANSWER}def shadow(answer)\n  answer + 1\nend\n\nshadow(1)");
    assert_eq!(shown(&param), "2");
    let local = format!("{ANSWER}def local()\n  answer = 7\n  answer\nend\n\nlocal");
    assert_eq!(shown(&local), "7");
    let lambda = format!("{ANSWER}map(fn(answer) answer * 2 end, [1, 2])");
    assert_eq!(shown(&lambda), "[2, 4]");
}

#[test]
fn a_function_that_takes_arguments_stays_a_value_when_bare() {
    let src = "def inc(x)\n  x + 1\nend\n\n[map(inc, [1, 2]), apply(inc, [5])]";
    assert_eq!(shown(src), "[[2, 3], 6]");
}

#[test]
fn optional_and_variadic_builtins_stay_values_when_bare() {
    assert_eq!(shown("procedure?(gensym)"), "true");
    assert_eq!(shown("procedure?(receive)"), "true");
    assert_eq!(shown("procedure?(list)"), "true");
}

#[test]
fn a_value_bound_lambda_is_a_value_when_bare() {
    assert_eq!(shown("f = fn() 1 end\nprocedure?(f)"), "true");
    assert_eq!(shown("f = fn() 1 end\nf()"), "1");
}

#[test]
fn the_function_itself_is_passed_as_fn_name_end() {
    let src = format!("{ANSWER}def twice(f)\n  f() + f()\nend\n\ntwice(fn() answer end)");
    assert_eq!(shown(&src), "84");
    let applied = format!("{ANSWER}apply(fn() answer end, [])");
    assert_eq!(shown(&applied), "42");
}

#[test]
fn a_keyword_of_the_same_name_is_unaffected() {
    assert_eq!(
        shown(&format!("{ANSWER}[:answer, answer]")),
        "[:answer, 42]"
    );
    assert_eq!(shown("keyword?(:argv)"), "true");
}

#[test]
fn interpolation_calls_a_bare_zero_parameter_name() {
    assert_eq!(shown(&format!("{ANSWER}\"is #{{answer}}\"")), "\"is 42\"");
}

#[test]
fn a_pipeline_threads_a_bare_call() {
    let src = format!("{ANSWER}def inc(x)\n  x + 1\nend\n\nanswer |> inc");
    assert_eq!(shown(&src), "43");
}

#[test]
fn a_zero_parameter_definition_recurses_bare() {
    let src = "def depth()\n  if false\n    depth\n  else\n    :bottom\n  end\nend\n\ndepth";
    assert_eq!(shown(src), ":bottom");
}

#[test]
fn a_quoted_template_keeps_the_name_as_written() {
    let src = format!("{ANSWER}quote\n  answer\nend");
    assert_eq!(shown(&src), "%root/answer");
}

#[test]
fn an_imported_zero_parameter_definition_is_called_bare() {
    let loader = Mem(&[("kagi", "def kagi()\n  7\nend\n")]);
    assert_eq!(
        shown_with("use(\"kagi\", [:kagi])\n\nkagi + 1", &loader),
        "8"
    );
    assert_eq!(shown_with("use(\"kagi\")\n\nkagi::kagi + 1", &loader), "8");
}

#[test]
fn a_test_block_calls_bare_names() {
    let src = format!("{ANSWER}test \"bare\"\n  assert answer == 42\nend\n");
    let codes = codes_in_file(&src);
    assert!(codes.is_empty(), "{codes:?}");
}

#[test]
fn a_parenthesized_zero_parameter_call_in_a_stored_file_is_b0023() {
    assert_eq!(codes_in_file(&format!("{ANSWER}answer()\n")), ["B0023"]);
    assert_eq!(codes_in_file("now_ms()\n"), ["B0023"]);
    assert!(codes_in_file(&format!("{ANSWER}answer\n")).is_empty());
    let param = format!("{ANSWER}def g(answer)\n  answer()\nend\n\ng(fn() 1 end)\n");
    assert!(codes_in_file(&param).is_empty());
}

#[test]
fn source_with_no_file_accepts_both_spellings() {
    assert_eq!(shown(&format!("{ANSWER}answer()")), "42");
}

#[test]
fn a_function_taking_arguments_used_bare_as_a_number_names_the_rule() {
    let message = failure("def inc(x)\n  x + 1\nend\n\ninc + 1");
    assert!(
        message.contains("`inc` takes arguments, so bare `inc` is the function itself"),
        "{message}"
    );
}

#[test]
fn a_bare_zero_parameter_call_where_a_function_was_wanted_names_the_rule() {
    let message = failure(&format!("{ANSWER}apply(answer, [])"));
    assert!(
        message.contains("`answer` takes no arguments, so writing it bare calls it"),
        "{message}"
    );
    assert!(message.contains("fn() answer end"), "{message}");
}
