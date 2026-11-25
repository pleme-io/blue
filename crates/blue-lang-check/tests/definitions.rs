use blue_lang_check::laws::{decide, Decision};
use blue_lang_check::lia::Backend;

const SHAPES: &str = "record point(x, y)

union shape = circle(r) | square(s)

LIMIT = 3

twice = (n) -> n * 2

defmacro both(x)
  quote
    unquote(x)
  end
end

def f(n)
  n
end

def typed(n: Int) -> Int
  n
end
";

const UNREAD: &[&str] = &[
    "point", "point?", "shape?", "circle", "circle?", "square", "square?", "LIMIT", "twice", "both",
];

const READ: &[&str] = &["f", "typed"];

const SHADOWS: &[(&str, &str, &str)] = &[
    ("record count(v)", "count", "count(xs) >= 0"),
    (
        "record empty(v)",
        "empty?",
        "empty?(xs) == (length(xs) == 0)",
    ),
    (
        "union empty = vacant(v) | filled(v)",
        "empty?",
        "empty?(xs) == (length(xs) == 0)",
    ),
    ("union magnitude = abs(v) | sign(s)", "abs", "abs(n) >= 0"),
    (
        "union fill = empty(v) | full(v)",
        "empty?",
        "empty?(xs) == (length(xs) == 0)",
    ),
];

fn decided(defined: &str, body: &str) -> Decision {
    let src = format!("{defined}\n\ndef law_x(xs: List(Int), n: Int) -> Bool\n  {body}\nend\n");
    let forms = blue_lang_syntax::parse_program_tree(&src).expect("parses");
    decide(&forms, "law_x", Backend::Cooper).expect("the file has the law")
}

fn bound(name: &str) -> Decision {
    Decision::Outside(format!(
        "`{name}` is bound in this file to something the solver does not read"
    ))
}

#[test]
fn a_law_reads_every_name_a_definition_binds_as_the_file_binds_it() {
    let mut out = Vec::new();
    for name in UNREAD {
        let got = decided(SHAPES, &format!("{name}(n) == {name}(n)"));
        if got != bound(name) {
            out.push(format!("`{name}(n)`: {got:?}"));
        }
    }
    for name in READ {
        let got = decided(SHAPES, &format!("{name}(n) == n"));
        if got != Decision::Proved {
            out.push(format!("`{name}(n)`: {got:?}"));
        }
    }
    assert!(out.is_empty(), "laws misread:\n  {}", out.join("\n  "));
}

#[test]
fn a_record_or_union_that_binds_a_fragment_word_is_never_read_as_that_word() {
    let mut out = Vec::new();
    for (defined, name, body) in SHADOWS {
        let got = decided(defined, body);
        if got != bound(name) {
            out.push(format!("{defined}, `{body}`: {got:?}"));
        }
    }
    assert!(out.is_empty(), "laws misread:\n  {}", out.join("\n  "));
}
