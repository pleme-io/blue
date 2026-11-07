use blue_lang_runtime::def_hash::hash_program;
use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{run_in_surface, RunError};
use blue_lang_runtime::uses::{Entry, Loader};
use blue_lang_syntax::parse_program_tree;
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

fn value(src: &str) -> String {
    let v: Value = run(src).unwrap_or_else(|e| panic!("{src}\n{e}"));
    format!("{v:?}")
}

fn hash_of(src: &str, name: &str) -> String {
    let forms = parse_program_tree(src).unwrap_or_else(|e| panic!("{src}\n{e}"));
    let hashes = hash_program(&forms);
    let keys: Vec<&str> = hashes.keys().collect();
    let def = hashes
        .defs()
        .iter()
        .find(|d| d.key == name || d.key.ends_with(&format!("/{name}")))
        .unwrap_or_else(|| panic!("no def {name} among {keys:?}"));
    def.hash.to_string()
}

fn refused(src: &str, says: &str) {
    match run(src) {
        Err(RunError::Types(errors)) => {
            let all = errors.join("\n");
            assert!(all.contains("B0080"), "{all}");
            assert!(all.contains(says), "{says}: {all}");
        }
        other => panic!("{src}: not refused at check: {other:?}"),
    }
}

const GUARD: &str = "def read(n)
  s = n * 2
  if s > 10
    return :big
  end
  t = s + 1
  [s, t]
end
";

const NESTED: &str = "def read(n)
  s = n * 2
  if s > 10
    :big
  else
    t = s + 1
    [s, t]
  end
end
";

/// R-lower. Red run: lowering the guard `return` to a call left the two
/// programs different trees, so the hashes differed and the check refused it.
#[test]
fn a_guard_and_its_nested_if_are_one_program() {
    assert_eq!(hash_of(GUARD, "read"), hash_of(NESTED, "read"));
    for n in [1, 6] {
        let call = format!("\nread({n})\n");
        assert_eq!(
            value(&format!("{GUARD}{call}")),
            value(&format!("{NESTED}{call}")),
            "read({n})"
        );
    }
    assert_eq!(value(&format!("{GUARD}\nread(6)\n")), value(":big"));
}

#[test]
fn guards_stack_flat_and_a_bare_return_is_nil() {
    let src = "def grade(n)
  if n < 0
    return
  end
  if n < 50
    return :low
  end
  if n < 80
    return :mid
  end
  :high
end
[grade(-1), grade(10), grade(60), grade(99)]
";
    assert_eq!(value(src), value("[nil, :low, :mid, :high]"));
}

/// R-total. Red run: dropping the implicit `else` (the rest of the body)
/// made `pick(2)` answer nil instead of :two.
#[test]
fn every_path_has_a_value_when_every_branch_returns() {
    let src = "def pick(n)
  if n == 1
    return :one
  elsif n == 2
    x = :two
    return x
  else
    return :many
  end
end
[pick(1), pick(2), pick(3)]
";
    assert_eq!(value(src), value("[:one, :two, :many]"));
}

#[test]
fn a_case_arm_returns_and_the_others_fall_through() {
    let src = "def size(x)
  case x
  when 0
    return :none
  when 1
    return :one
  end
  :some
end
[size(0), size(1), size(7)]
";
    assert_eq!(value(src), value("[:none, :one, :some]"));
}

#[test]
fn a_return_nested_two_ifs_deep_still_lowers() {
    let src = "def f(a, b)
  if a
    if b
      return :both
    end
    return :a_only
  end
  :neither
end
[f(true, true), f(true, false), f(false, false)]
";
    assert_eq!(value(src), value("[:both, :a_only, :neither]"));
}

/// R-refuse. Red run: lowering a `return` inside a `fn` made it leave the
/// lambda, and `f([1])` answered a list of returns with no finding.
#[test]
fn a_return_the_rewrite_cannot_place_is_refused_by_name() {
    refused(
        "def f(xs)\n  map(xs, fn(x)\n    return x\n  end)\nend\nf([1])\n",
        "a function value",
    );
    refused(
        "def f(c)\n  x = if c\n    return 1\n  else\n    2\n  end\n  x\nend\nf(true)\n",
        "the value of `x = …`",
    );
    refused("return 1\n", "the top level of the file");
    refused("def f()\n  g(return 1)\nend\nf()\n", "an argument of `g`");
}

#[test]
fn code_after_a_return_never_runs_and_is_a_parse_error() {
    let e = parse_program_tree("def f()\n  return 1\n  2\nend\n").unwrap_err();
    assert!(e.message.contains("never runs"), "{e}");
    assert_eq!(e.line, 3);
}

#[test]
fn the_formatter_keeps_the_guard_as_written() {
    let doc = blue_lang_syntax::parse_program_documented(GUARD).unwrap();
    let text = format!("{doc:?}");
    assert!(text.contains("return"), "the surface tree keeps `return`");
}
