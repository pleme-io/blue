use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{run_in_surface, RunError};
use blue_lang_runtime::uses::{Entry, Loader};
use blue_lang_syntax::{parse_program_documented, parse_program_tree, Spanned};
use tatara_lisp_eval::Value;

struct NoBidamas;

impl Loader for NoBidamas {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        Err(format!("no bidama named \"{name}\""))
    }
}

fn run(src: &str) -> Result<Value, RunError> {
    run_in_surface(Entry::anonymous(src), Inputs::new(), &NoBidamas, None).map(|r| r.value)
}

fn sexps(forms: &[Spanned]) -> Vec<String> {
    forms.iter().map(|f| f.to_sexp().to_string()).collect()
}

const HALF: &str = "def half(n)\n  if n % 2 == 0\n    {ok: true, value: n / 2}\n  else\n    {ok: false, refusal: [:odd, n]}\n  end\nend\n";

const FLOWS: &[&str] = &[
    "def quarter(n)\n  h = half(n)?\n  half(h)\nend\n",
    "def eighth(n)\n  half(n)?\n  q = quarter(n)?\n  q\nend\n",
    "def pick(n, go)\n  if go\n    v = half(n)?\n    v + 1\n  else\n    0\n  end\nend\n",
    "def last(n)\n  half(n)?\nend\n",
];

#[test]
fn raising_the_lowered_tree_gives_back_every_question_mark() {
    for body in FLOWS {
        let src = format!("{HALF}\n{body}");
        let lowered = parse_program_tree(&src).unwrap_or_else(|e| panic!("{src}\n{e}"));
        let surface = parse_program_documented(&src).unwrap();
        let raised = blue_lang_syntax::try_op::raise(lowered);
        let raised = blue_lang_syntax::guard::raise(&src, raised);
        assert_eq!(sexps(&raised), sexps(&surface), "{src}");
    }
}

#[test]
fn a_refusal_returns_at_once_and_a_value_is_unwrapped() {
    let src = format!(
        "{HALF}\n{}\n{}\n{}\n{}\n[quarter(8), quarter(6), eighth(16), pick(3, true), pick(1, false), last(4)]\n",
        FLOWS[0], FLOWS[1], FLOWS[2], FLOWS[3]
    );
    let got = run(&src).unwrap_or_else(|e| panic!("{e}"));
    let want = run("[{ok: true, value: 2}, {ok: false, refusal: [:odd, 3]}, 4, {ok: false, refusal: [:odd, 3]}, 0, 2]")
        .unwrap_or_else(|e| panic!("{e}"));
    assert_eq!(format!("{got:?}"), format!("{want:?}"));
}

#[test]
fn a_value_that_is_not_a_result_is_refused_by_name() {
    let src = "def five()\n  5\nend\n\ndef f()\n  x = five()?\n  x\nend\n\nf()\n";
    match run(src) {
        Err(e) => assert!(e.to_string().contains("`?` takes a result"), "{e}"),
        Ok(v) => panic!("a non-result passed through `?`: {v:?}"),
    }
}

#[test]
fn a_question_mark_that_cannot_return_is_a_parse_error() {
    for src in [
        "def f(r)\n  [g(r)?]\nend\n",
        "x = g(1)?\n",
        "def f(xs)\n  map(xs, (x) -> g(x)?)\nend\n",
    ] {
        let e = parse_program_tree(src).expect_err(src);
        assert!(e.message.contains("ends a statement"), "{src}: {e}");
    }
}
