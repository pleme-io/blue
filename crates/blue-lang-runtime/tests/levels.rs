//! **A bidama is a tree.** Every law of nested namespaces, driven against an
//! in-memory tree: a full path at every depth, a path relative to an import,
//! a second name, a listed name, a miss naming what exists, a refused
//! ambiguity, a refused cycle, a refused computed path, and every spelling of
//! `use` loading one identical thing.

use std::collections::BTreeSet;

use blue_lang_check::Code;
use blue_lang_runtime::inputs::Inputs;
use blue_lang_runtime::pipeline::{check_entry, run_in_surface, Checking};
use blue_lang_runtime::uses::{Entry, Loader};
use tatara_lisp_eval::Value;

struct Tree(&'static [(&'static str, &'static str)]);

impl Loader for Tree {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.0
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(n, s)| vec![(format!("{n}.b"), (*s).to_string())])
            .ok_or_else(|| format!("no bidama named \"{name}\""))
    }

    fn children(&self, name: &str) -> Vec<String> {
        let below = format!("{name}/");
        self.0
            .iter()
            .filter_map(|(n, _)| n.strip_prefix(&below).map(|rest| (*n, rest)))
            .filter(|(_, rest)| !rest.contains('/'))
            .map(|(n, _)| n.to_string())
            .collect()
    }
}

const THING: &[(&str, &str)] = &[
    ("thing", "def top()\n  \"top\"\nend\n"),
    ("thing/other", "def word()\n  \"other\"\nend\n"),
    ("thing/sub", "def inner()\n  \"inner\"\nend\n"),
    (
        "thing/sub/waka",
        "def goodness()\n  {something: \"good\"}\nend\n",
    ),
    ("thing/sub/waka/deep", "def bottom()\n  \"bottom\"\nend\n"),
    ("elsewhere", "def e()\n  1\nend\n"),
    (
        "elsewhere/sub",
        "def inner()\n  \"elsewhere\"\nend\n\ndef only_here()\n  \"only\"\nend\n",
    ),
];

fn text(src: &str) -> String {
    let run = run_in_surface(Entry::anonymous(src), Inputs::default(), &Tree(THING), None)
        .unwrap_or_else(|e| panic!("{src}: {e}"));
    match run.value {
        Value::Str(s) => s.to_string(),
        other => panic!("{src}: {other:?}"),
    }
}

fn diagnostics(src: &str) -> Vec<(Code, String, String)> {
    let checked =
        check_entry(Entry::anonymous(src), &Tree(THING), None, Checking::Program).expect("check");
    checked
        .outcome
        .diagnostics
        .iter()
        .map(|d| {
            (
                d.code,
                d.message.clone(),
                d.help.clone().unwrap_or_default(),
            )
        })
        .collect()
}

#[test]
fn a_full_path_resolves_at_one_two_and_three_levels() {
    assert_eq!(text("use(\"thing\")\n\nthing::top\n"), "top");
    assert_eq!(text("use(\"thing\")\n\nthing::sub::inner\n"), "inner");
    assert_eq!(
        text("use(\"thing\")\n\nthing::sub::waka::goodness.something\n"),
        "good"
    );
    assert_eq!(
        text("use(\"thing\")\n\nthing::sub::waka::deep::bottom\n"),
        "bottom"
    );
}

/// The operator's sentence: `use("thing/sub")`, and `thing::sub::waka::goodness`
/// is also `sub::waka::goodness` and `waka::goodness`.
#[test]
fn a_shortcut_is_a_path_relative_to_the_import_at_each_depth() {
    for name in [
        "thing::sub::waka::goodness",
        "sub::waka::goodness",
        "waka::goodness",
    ] {
        assert_eq!(
            text(&format!("use(\"thing/sub\")\n\n{name}.something\n")),
            "good",
            "{name}"
        );
    }
    assert_eq!(text("use(\"thing/sub\")\n\nsub::inner\n"), "inner");
    assert_eq!(text("use(\"thing/sub\")\n\nthing::sub::inner\n"), "inner");
    assert_eq!(text("use(\"thing/sub\")\n\nwaka::deep::bottom\n"), "bottom");
    assert_eq!(
        text("use(\"thing/sub/waka/deep\")\n\ndeep::bottom\n"),
        "bottom"
    );
    assert_eq!(
        text("use(\"thing/sub/waka/deep\")\n\nwaka::deep::bottom\n"),
        "bottom"
    );
    assert_eq!(text("use(\"thing\")\n\nsub::inner\n"), "inner");
    assert_eq!(
        text("use(\"thing\")\n\nsub::waka::goodness.something\n"),
        "good"
    );
}

#[test]
fn a_shortcut_that_starts_too_low_is_refused_with_the_path_that_works() {
    let d = diagnostics("use(\"thing\")\n\ndeep::bottom\n");
    assert_eq!(d.len(), 1, "{d:?}");
    assert_eq!(d[0].0, Code::B0010);
    assert!(d[0].2.contains("`sub::waka::deep::bottom`"), "{d:?}");
}

#[test]
fn a_level_a_file_never_imported_is_refused() {
    let d = diagnostics("use(\"thing/sub\")\n\nother::word\n");
    assert_eq!(d[0].0, Code::B0010, "{d:?}");
    assert!(d[0].1.contains("`other::word`"), "{d:?}");
}

/// Load order never picks: both candidates are named, and the full path of
/// either is the way out.
#[test]
fn two_imports_that_fit_one_shortcut_are_refused_naming_both() {
    let both = "use(\"elsewhere/sub\")\nuse(\"thing/sub\")\n\n";
    let d = diagnostics(&format!("{both}sub::inner\n"));
    assert_eq!(d.len(), 1, "{d:?}");
    assert_eq!(d[0].0, Code::B0009);
    assert!(
        d[0].1.contains("`elsewhere::sub::inner`") && d[0].1.contains("`thing::sub::inner`"),
        "{d:?}"
    );
    assert_eq!(text(&format!("{both}thing::sub::inner\n")), "inner");
    assert_eq!(text(&format!("{both}elsewhere::sub::inner\n")), "elsewhere");
    assert_eq!(text(&format!("{both}sub::only_here\n")), "only");
}

/// A miss at each depth names what the level holds, and a level is not a value.
#[test]
fn a_miss_at_each_level_names_what_exists() {
    for (name, says) in [
        (
            "thing::nope",
            "`thing` defines `top`; below it: `thing::other`, `thing::sub`",
        ),
        (
            "thing::sub::nope",
            "`thing::sub` defines `inner`; below it: `thing::sub::waka`",
        ),
        (
            "sub::waka::nope",
            "`thing::sub::waka` defines `goodness`; below it: `thing::sub::waka::deep`",
        ),
        (
            "thing::sub::waka::deep::nope",
            "`thing::sub::waka::deep` defines `bottom`, and has no level below it",
        ),
    ] {
        let d = diagnostics(&format!("use(\"thing\")\n\n{name}\n"));
        assert_eq!(d[0].0, Code::B0011, "{name}: {d:?}");
        assert!(d[0].2.contains(says), "{name}: {d:?}");
    }
    let d = diagnostics("use(\"thing\")\n\nthing::sub\n");
    assert_eq!(d[0].1, "`thing::sub` is a level, not a definition", "{d:?}");
}

/// A one-level bidama's miss reads as it always has.
#[test]
fn a_bidama_with_no_levels_misses_as_before() {
    let d = diagnostics("use(\"thing/other\")\n\nother::nope\n");
    assert!(d[0].2.contains("`thing::other` defines `word`"), "{d:?}");
    const FLAT: &[(&str, &str)] = &[("flat", "def f()\n  1\nend\n")];
    let checked = check_entry(
        Entry::anonymous("use(\"flat\")\n\nflat::nope\n"),
        &Tree(FLAT),
        None,
        Checking::Program,
    )
    .expect("check");
    let help = checked.outcome.diagnostics[0]
        .help
        .clone()
        .unwrap_or_default();
    assert_eq!(help, "nothing in `flat` is close to `nope`");
}

fn loaded(src: &str) -> (BTreeSet<String>, Vec<String>) {
    let checked = check_entry(Entry::anonymous(src), &Tree(THING), None, Checking::Program)
        .unwrap_or_else(|e| panic!("{src}: {e}"));
    assert!(
        checked.outcome.diagnostics.is_empty(),
        "{src}: {:?}",
        checked.outcome.diagnostics
    );
    let files = checked
        .program
        .files()
        .iter()
        .filter_map(|f| f.package.clone())
        .collect();
    let imports = checked
        .program
        .imports()
        .iter()
        .map(|(_, i)| i.package.clone())
        .collect();
    (files, imports)
}

/// Every spelling of one path is one import and one load.
#[test]
fn every_spelling_of_a_path_loads_one_identical_thing() {
    let body = "\n\nsub::inner\n";
    let want = loaded(&format!("use(\"thing/sub\"){body}"));
    assert_eq!(
        want.0,
        ["thing/sub", "thing/sub/waka", "thing/sub/waka/deep"]
            .map(String::from)
            .into_iter()
            .collect()
    );
    assert_eq!(want.1, vec!["thing/sub".to_string()]);
    for spelling in [
        "\"thing::sub\"",
        "%i[thing sub]",
        "[:thing, :sub]",
        "%w[thing sub]",
        "[\"thing\", \"sub\"]",
        "*%i[thing sub]",
        "**%i[thing sub]",
        "*%w[thing sub]",
    ] {
        let src = format!("use({spelling}){body}");
        assert_eq!(loaded(&src), want, "{spelling}");
        assert_eq!(text(&src), "inner", "{spelling}");
    }
}

#[test]
fn a_second_name_reaches_the_level_and_everything_below_it() {
    let src = "use({s: \"thing/sub\"})\n\n";
    assert_eq!(text(&format!("{src}s::inner\n")), "inner");
    assert_eq!(text(&format!("{src}s::waka::goodness.something\n")), "good");
    assert_eq!(text(&format!("{src}thing::sub::inner\n")), "inner");
    assert_eq!(text("use({s: %i[thing sub]})\n\ns::inner\n"), "inner");
    let d = diagnostics("use({s: \"thing/sub\"})\nuse({s: \"thing/other\"})\n\ns::inner\n");
    assert!(
        d.iter()
            .any(|(c, m, _)| *c == Code::B0015 && m.contains("`s` names both")),
        "{d:?}"
    );
}

#[test]
fn several_children_come_from_one_form_with_their_lists_at_any_depth() {
    assert_eq!(
        text("use(\"thing\", %w[other sub])\n\nconcat(other::word, sub::inner)\n"),
        "otherinner"
    );
    assert_eq!(
        text("use(\"thing\", {other: [:word], sub: []})\n\nconcat(word, sub::inner)\n"),
        "otherinner"
    );
    assert_eq!(
        text("use(\"thing/sub\", {waka: [:goodness]})\n\ngoodness.something\n"),
        "good"
    );
    assert_eq!(
        text("use(%i[thing sub], %w[waka/deep])\n\ndeep::bottom\n"),
        "bottom"
    );
    assert_eq!(
        text("use(\"thing/sub/waka/deep\", [:bottom])\n\nbottom\n"),
        "bottom"
    );
}

/// No fix rewrites one spelling into another, and no qualifier is called
/// redundant on a path through a tree.
#[test]
fn every_spelling_stands_and_no_fix_touches_it() {
    let src = "use(\"thing/sub\", [:inner])\n\nconcat(inner, sub::inner)\n";
    assert_eq!(text(src), "innerinner");
    let checked = check_entry(
        Entry::anonymous("use(%i[zeta one])\n"),
        &Tree(&[("zeta/one", "def f()\n  1\nend\n")]),
        None,
        Checking::WithTests,
    )
    .expect("check");
    let d = &checked.outcome.diagnostics;
    assert_eq!(d[0].code, Code::B0016, "{d:?}");
    assert!(
        d[0].fixes.is_empty(),
        "a fix would erase the spelling: {d:?}"
    );
}

#[test]
fn a_computed_path_is_refused_at_the_check_stage_with_the_reason() {
    for src in [
        "path = \"thing\"\nuse(path)\n",
        "xs = [\"thing\"]\nuse(*xs)\n",
        "x = :inner\nuse(\"thing\", [x])\n",
        "use(\"thing\", [:a, \"b\"])\n",
        "use(\"thing\", %i[a], %i[b])\n",
        "def f()\n  use(\"thing\")\nend\n",
    ] {
        let d = diagnostics(src);
        assert!(
            d.iter()
                .any(|(c, _, h)| *c == Code::B0073 && h.contains("literal")),
            "{src}: {d:?}"
        );
    }
}

#[test]
fn a_cycle_between_levels_is_refused_with_its_path() {
    const UP: &[(&str, &str)] = &[
        ("top", "def t()\n  1\nend\n"),
        ("top/kid", "use(\"top\")\n\ndef k()\n  top::t\nend\n"),
    ];
    let e = check_entry(
        Entry::anonymous("use(\"top\")\n"),
        &Tree(UP),
        None,
        Checking::Program,
    )
    .err()
    .expect("a level importing its ancestor has no load order")
    .to_string();
    assert!(e.contains("top -> top::kid -> top"), "{e}");

    const SIDE: &[(&str, &str)] = &[
        ("top", "def t()\n  1\nend\n"),
        ("top/a", "use(\"top/b\")\n\ndef a()\n  b::b\nend\n"),
        ("top/b", "use(\"top/a\")\n\ndef b()\n  a::a\nend\n"),
    ];
    let e = check_entry(
        Entry::anonymous("use(\"top/a\")\n"),
        &Tree(SIDE),
        None,
        Checking::Program,
    )
    .err()
    .expect("siblings importing each other")
    .to_string();
    assert!(e.contains("top::a -> top::b -> top::a"), "{e}");
}

/// A level reaches below itself with no `use`: what is below it always loads.
#[test]
fn a_level_reaches_below_itself_and_its_definitions_keep_their_key() {
    const SELF: &[(&str, &str)] = &[
        ("top", "def t()\n  sub::s\nend\n"),
        ("top/sub", "def s()\n  \"below\"\nend\n"),
    ];
    let run = run_in_surface(
        Entry::anonymous("use(\"top\")\n\ntop::t\n"),
        Inputs::default(),
        &Tree(SELF),
        None,
    )
    .expect("runs");
    assert!(matches!(run.value, Value::Str(s) if &*s == "below"));
}
