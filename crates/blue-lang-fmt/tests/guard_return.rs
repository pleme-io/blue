use blue_lang_fmt::{format_source_lossless, format_tree_lossless};

const KEPT: &[&str] = &[
    "def read(n)\n  s = n * 2\n  if s > 10\n    return :big\n  end\n  if s < 0\n    return\n  end\n  [s, s + 1]\nend\n",
    "def pick(n)\n  if n == 1\n    return :one\n  elsif n == 2\n    x = :two\n  else\n    return :many\n  end\n  x\nend\n",
    "def size(x)\n  case x\n  when 0\n    return :none\n  when 1\n    y = 2\n  end\n  :some\nend\n",
    "def f(a, b)\n  if a\n    if b\n      return :both\n    end\n    return :a_only\n  end\n  :neither\nend\n",
    "def g(n)\n  # the guard\n  if n < 0\n    # why\n    return :neg\n  end\n\n  # the rest\n  n * 2\nend\n",
];

/// Red run: printing the lowered tree as it stands turned the first guard
/// into `if s > 10 :big elsif s < 0 nil else [s, s + 1] end`.
#[test]
fn a_guard_formats_as_written_from_either_tree() {
    for src in KEPT {
        assert_eq!(
            format_source_lossless(src).unwrap_or_else(|e| panic!("{src}\n{e}")),
            *src,
            "from the surface tree"
        );
        let lowered = blue_lang_syntax::parse_program_tree(src).unwrap();
        assert_eq!(
            format_tree_lossless(src, &lowered).unwrap_or_else(|e| panic!("{src}\n{e}")),
            *src,
            "from the lowered tree the check stage hands the formatter"
        );
    }
}

#[test]
fn a_return_that_changes_nothing_formats_as_its_value() {
    let src = "def f(c)\n  if c\n    return 1\n  end\nend\n";
    let lowered = blue_lang_syntax::parse_program_tree(src).unwrap();
    assert_eq!(
        format_tree_lossless(src, &lowered).unwrap(),
        "def f(c)\n  if c\n    1\n  end\nend\n"
    );
}
