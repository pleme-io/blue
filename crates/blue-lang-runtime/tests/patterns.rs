use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{run_in_surface, RunError};
use blue_lang_runtime::uses::{Entry, Loader};
use blue_lang_syntax::pattern::raise;
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

const PROGRAMS: &[&str] = &[
    "union shape = circle(r) | rect(w, h)\n\ndef f(s)\n  case s\n  when circle(r)\n    r\n  when rect(_, 1)\n    :strip\n  when rect(w, h)\n    w * h\n  end\nend\n",
    "def g(v)\n  case v\n  when [x, *rest]\n    [x, rest]\n  when {name:, tags: [_, *_]}\n    name\n  when [1, 2]\n    :same\n  end\nend\n",
];

#[test]
fn raising_the_lowered_tree_gives_back_the_surface() {
    for src in PROGRAMS {
        let lowered = parse_program_tree(src).unwrap_or_else(|e| panic!("{src}\n{e}"));
        let surface = blue_lang_syntax::union::lower(parse_program_documented(src).unwrap());
        assert_eq!(sexps(&raise(lowered)), sexps(&surface), "{src}");
    }
}

#[test]
fn a_pattern_arm_runs_on_the_walker() {
    let src = format!(
        "{}\n[f(circle(2)), f(rect(3, 1)), f(rect(2, 5))]\n",
        PROGRAMS[0]
    );
    let got = run(&src).unwrap_or_else(|e| panic!("{e}"));
    let want = run("[2, :strip, 10]").unwrap_or_else(|e| panic!("{e}"));
    assert_eq!(format!("{got:?}"), format!("{want:?}"));
}
