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

const FRAME: &[(&str, &str, &str)] = &[
    ("if true\n  count = 5\nend", "count", "count(xs) >= 0"),
    (
        "LIMIT = if true\n  count = 5\n  3\nelse\n  4\nend",
        "count",
        "count(xs) >= 0",
    ),
    (
        "def size_of(xs)\n  length(xs)\nend\n\nsize_of = 5",
        "size_of",
        "size_of(xs) >= 0",
    ),
    (
        "def size_of(xs)\n  length(xs)\nend\n\nif true\n  size_of = 5\nend",
        "size_of",
        "size_of(xs) >= 0",
    ),
];

const OWN_FRAMES: &[(&str, &str)] = &[
    ("def g()\n  count = 5\n  count\nend", "count(xs) >= 0"),
    ("twice = fn(n)\n  count = n\n  count\nend", "count(xs) >= 0"),
    (
        "test \"a test binds in its own frame\"\n  count = 5\n  assert count == 5\nend",
        "count(xs) >= 0",
    ),
    (
        "size_of = 5\n\ndef size_of(xs)\n  length(xs)\nend",
        "size_of(xs) >= 0",
    ),
];

const LOCALS: &[(&str, &str, &str)] = &[
    ("", "count", "count = 5\n  count(xs) >= 0"),
    (
        "def size_of(xs)\n  length(xs)\nend",
        "size_of",
        "size_of = 7\n  size_of(xs) >= 0",
    ),
    (
        "def size_of(xs)\n  length = 3\n  length(xs)\nend",
        "length",
        "size_of(xs) >= 0",
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

fn local(name: &str) -> Decision {
    Decision::Outside(format!(
        "`{name}` is a local here, and the solver does not read a call to a local"
    ))
}

fn assert_read<'a>(rows: impl IntoIterator<Item = (&'a str, String, Decision)>) {
    let out: Vec<String> = rows
        .into_iter()
        .filter_map(|(defined, body, want)| {
            let got = decided(defined, &body);
            (got != want).then(|| format!("{body:?} beside {defined:?}: {got:?}"))
        })
        .collect();
    assert!(out.is_empty(), "laws misread:\n  {}", out.join("\n  "));
}

#[test]
fn a_law_reads_every_name_a_definition_binds_as_the_file_binds_it() {
    assert_read(
        UNREAD
            .iter()
            .map(|n| (SHAPES, format!("{n}(n) == {n}(n)"), bound(n)))
            .chain(
                READ.iter()
                    .map(|n| (SHAPES, format!("{n}(n) == n"), Decision::Proved)),
            ),
    );
}

#[test]
fn a_record_or_union_that_binds_a_fragment_word_is_never_read_as_that_word() {
    assert_read(
        SHADOWS
            .iter()
            .map(|&(defined, name, body)| (defined, body.to_string(), bound(name))),
    );
}

#[test]
fn a_name_a_statement_a_value_or_a_later_form_binds_is_never_read_as_a_word_or_a_def() {
    assert_read(
        FRAME
            .iter()
            .map(|&(defined, name, body)| (defined, body.to_string(), bound(name))),
    );
}

#[test]
fn a_name_bound_only_in_its_own_frame_or_before_the_last_def_leaves_the_law_proved() {
    assert_read(
        OWN_FRAMES
            .iter()
            .map(|&(defined, body)| (defined, body.to_string(), Decision::Proved)),
    );
}

#[test]
fn a_call_to_a_local_is_never_read_as_a_word_or_a_def() {
    assert_read(
        LOCALS
            .iter()
            .map(|&(defined, name, body)| (defined, body.to_string(), local(name))),
    );
}
