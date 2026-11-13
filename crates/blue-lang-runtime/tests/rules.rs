//! **Every rule in the registry fires on its witness, through the pipeline.**
//!
//! Each `blue_lang_check::RULES` row carries a `witness`: a program that
//! violates that rule and nothing else. This runs each one through the same
//! check stage `blue run`, `blue test` and `blue check` use, and fails unless
//! the diagnostics that come out are exactly that one code. So:
//!
//! - a row cannot be added without a program proving it can fire;
//! - a rule whose implementation stops firing turns its own row red;
//! - a witness that trips a SECOND rule is caught, which keeps each witness a
//!   precise example for `blue explain`.
//!
//! B0006 (syntax) has no tree to check, so its witness goes through
//! `pipeline::syntax_diagnostic`, the door `blue check` reports it from.
//!
//! Every witness sees the full interpreter's surface (`docs::NAMES`) in
//! every feature set: built without `sys`, the words that layer binds are
//! declared beside the witness in a `blue-host.json`, as a host declares its
//! own. Red run (2026-10-31), `cargo test -p blue-lang-runtime` without
//! `sys` before that: `B0064: expected [B0064], got [B0001, B0064]`, since
//! its witness calls `write_file`.
//!
//! Red run (2026-09-29): `check_names` removed from `check_stage` — the
//! B0001 and B0002 rows fail with `B0001: expected [B0001], got []`.

use blue_lang_check::{Code, Severity, RULES};
use blue_lang_runtime::pipeline::{check_entry, run, syntax_diagnostic, Checking, RunError};
use blue_lang_runtime::uses::{Entry, Loader};

/// The witness's bidamas, in memory, and the schema table of the frontend
/// a data-law witness is a view of.
struct Imports(
    &'static [(&'static str, &'static str)],
    Option<&'static str>,
    Option<&'static str>,
    Option<&'static str>,
);

impl Loader for Imports {
    /// A rule that judges a project point has its witness checked as the
    /// program of that row: `generator`, `service`, or a `binding` service.
    fn roles(&self, _entry: &std::path::Path) -> Vec<blue_lang_runtime::uses::Role> {
        use blue_lang_runtime::uses::Role;
        match self.3 {
            Some("generator") => vec![Role::Generator("witness".into())],
            Some("service") => vec![Role::Service("witness".into())],
            Some("binding") => vec![
                Role::Service("witness".into()),
                Role::Binding("witness".into(), "cache".into()),
            ],
            _ => Vec::new(),
        }
    }

    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.0
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(n, src)| vec![(format!("{n}.b"), (*src).to_string())])
            .ok_or_else(|| format!("no bidama named \"{name}\""))
    }

    /// Every witness bidama is a bidama with no `needs`, so one that `use`s
    /// another is B0019's witness and no other row's.
    fn needs(
        &self,
        package: &str,
        _entry_dir: Option<&std::path::Path>,
    ) -> Option<std::collections::BTreeSet<String>> {
        if self.2 == Some(package) {
            return Some(self.0.iter().map(|(n, _)| (*n).to_string()).collect());
        }
        Some(std::collections::BTreeSet::new())
    }

    /// Every witness bidama is at 0.1.1: B0021's `legacy_names("0.1.1", …)`
    /// is in its window, and B0022's `legacy_names("9.0.0", …)` is not.
    fn version(&self, _package: &str, _entry_dir: Option<&std::path::Path>) -> Option<String> {
        Some("0.1.1".to_string())
    }

    /// A name no witness bidama is, whose last segment one witness level
    /// is, moved there at 0.1.1: B0074's `bpf` is `kaaneru/bpf`.
    fn moved(&self, name: &str) -> Option<blue_lang_runtime::uses::PackageMove> {
        if self.0.iter().any(|(n, _)| *n == name) {
            return None;
        }
        let tail = format!("/{name}");
        let (new, _) = self.0.iter().find(|(n, _)| n.ends_with(&tail))?;
        Some(blue_lang_runtime::uses::PackageMove {
            old: name.to_string(),
            new: (*new).to_string(),
            since: "0.1.1".to_string(),
            version: Some("0.1.1".to_string()),
        })
    }

    /// A rule that judges a bidama's own file has its witness checked as
    /// that bidama's source.
    fn entry_package(&self, _path: &std::path::Path) -> Option<String> {
        self.2.map(str::to_string)
    }

    fn frontend(&self, _entry: &std::path::Path) -> Option<blue_lang_runtime::uses::Frontend> {
        self.1.map(|t| blue_lang_runtime::uses::Frontend {
            table: Some(("schema.table".to_string(), t.to_string())),
            view: true,
        })
    }
}

fn codes_with(src: &str, imports: &'static [(&'static str, &'static str)]) -> Vec<Code> {
    codes_in(src, imports, None, None)
}

/// The words of the full interpreter (`docs::NAMES`, the surface every
/// witness is written against and `blue explain` shows) that this build
/// does not bind: the `sys` layer, when the crate is built without it.
fn host_words() -> Vec<&'static blue_lang_runtime::docs::NameDoc> {
    let interp = blue_lang_runtime::interpreter(&mut ());
    blue_lang_runtime::docs::NAMES
        .iter()
        .filter(|d| interp.resolve_head(d.name).is_none())
        .collect()
}

fn host_surface() -> &'static str {
    static TEXT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    TEXT.get_or_init(|| {
        let words = host_words();
        let params: Vec<Vec<String>> = words
            .iter()
            .map(|d| blue_lang_check::contracts::parameters(d.signature).unwrap_or_default())
            .collect();
        let params: Vec<Vec<&str>> = params
            .iter()
            .map(|p| p.iter().map(String::as_str).collect())
            .collect();
        blue_lang_runtime::host_surface::render(
            words
                .iter()
                .zip(&params)
                .map(|(d, p)| (d.name, p.as_slice(), p.len(), d.doc)),
        )
    })
}

/// A directory whose `blue-host.json` declares [`host_words`], as a host
/// that supplies them declares its own, removed when dropped: a witness
/// checked there sees the surface it was written against in every feature
/// set.
struct FullSurface(std::path::PathBuf);

impl FullSurface {
    fn new() -> Self {
        static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("blue-rules-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("a scratch directory");
        std::fs::write(
            dir.join(blue_lang_runtime::host_surface::FILE),
            host_surface(),
        )
        .expect("the host surface is written");
        Self(dir)
    }
}

impl Drop for FullSurface {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn codes_in(
    src: &str,
    imports: &'static [(&'static str, &'static str)],
    frontend: Option<&'static str>,
    package: Option<&'static str>,
) -> Vec<Code> {
    quiet(codes_as(src, imports, frontend, package, None), None)
}

/// The codes without the two reach rules still being ratcheted in (B0090,
/// B0091), unless `keep` names one: they fire into the census on nearly every
/// bidama a witness is checked as, so a witness of another rule would never
/// be the only code it shows.
fn quiet(codes: Vec<Code>, keep: Option<Code>) -> Vec<Code> {
    codes
        .into_iter()
        .filter(|c| !matches!(c, Code::B0090 | Code::B0091) || Some(*c) == keep)
        .collect()
}

fn codes_as(
    src: &str,
    imports: &'static [(&'static str, &'static str)],
    frontend: Option<&'static str>,
    package: Option<&'static str>,
    role: Option<&'static str>,
) -> Vec<Code> {
    if let Some(d) = syntax_diagnostic(src) {
        return vec![d.code];
    }
    let surface = FullSurface::new();
    let path = surface
        .0
        .join(package.map_or_else(|| "witness.b".to_string(), |p| format!("{p}.b")));
    let checked = check_entry(
        Entry {
            path: Some(&path),
            text: src,
        },
        &Imports(imports, frontend, package, role),
        None,
        Checking::WithTests,
    )
    .unwrap_or_else(|e| panic!("{src:?}: {e}"));
    // A rule still being ratcheted in is computed and not enforced: its
    // witness fires into `census`.
    checked
        .outcome
        .diagnostics
        .iter()
        .chain(&checked.outcome.census)
        .chain(&blue_lang_runtime::pipeline::form_diagnostics(src))
        .map(|d| d.code)
        .collect()
}

fn codes_of(src: &str) -> Vec<Code> {
    codes_with(src, &[])
}

#[test]
fn every_rule_fires_on_its_witness_and_only_it() {
    let mut failures = Vec::new();
    for r in RULES {
        let got = quiet(
            codes_as(r.witness, r.imports, r.frontend, r.package, r.role),
            Some(r.code),
        );
        if got != vec![r.code] {
            failures.push(format!("{}: expected [{}], got {got:?}", r.code, r.code));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn a_witness_sees_the_sys_words_as_the_host_s_only_where_the_build_lacks_them() {
    let words: Vec<&str> = host_words().iter().map(|d| d.name).collect();
    for word in ["write_file", "read_file", "exec_capture"] {
        assert_eq!(
            words.contains(&word),
            !cfg!(feature = "host"),
            "{word} in {words:?}"
        );
    }
    assert!(host_surface().contains("\"write_file\"") != cfg!(feature = "host"));
}

/// Anti-vacuity for the test above: a program that breaks no rule produces
/// nothing, so "exactly one code" is the witness's doing.
#[test]
fn a_clean_program_produces_no_diagnostic() {
    let src = "# waive B0002: the callback shape is fixed\ndef on(event, ctx)\n  event\nend\n\n\
               def add(a: Int, b: Int) -> Int\n  a + b\nend\n\n\
               test \"adds\"\n  assert add(1, 2) == 3\nend\n";
    assert_eq!(codes_of(src), Vec::<Code>::new());
}

/// **The motivating case: a typo in a function that never runs stops
/// `blue run`.** Before the name pass it ran green, and failed only when the
/// branch was finally taken.
///
/// Red run (2026-09-29): `check_names` removed from `check_stage`:
/// `a typo in a dead function must stop the run: Ok(Run { value: Int(1),
/// visited: 0, typed_decls: 0, seams: 0 })`.
#[test]
fn a_typo_in_a_dead_function_stops_the_run() {
    let r = run("def f(xs)\n  lenght(xs)\nend\n\n1\n");
    match r {
        Err(RunError::Types(errors)) => {
            assert_eq!(errors.len(), 1, "{errors:?}");
            assert_eq!(
                errors[0],
                "<anonymous>:2:3: error[B0001]: unbound name `lenght`\n  \
                 help: did you mean `length` (builtin)?"
            );
        }
        other => panic!("a typo in a dead function must stop the run: {other:?}"),
    }
}

/// A warning is reported and does not stop the pipeline.
#[test]
fn a_warning_does_not_stop_the_run() {
    assert!(run("def f(x, unused)\n  x\nend\n\nf(1, 2)\n").is_ok());
    assert_eq!(Code::B0002.severity(), Severity::Warning);
}

/// Every diagnostic in a file comes out of ONE check, not the first only.
#[test]
fn every_diagnostic_is_reported_in_one_pass() {
    let src = "def f()\n  aa()\nend\n\ndef g()\n  bb()\nend\n\ndef h(x: Int) -> Str\n  x\nend\n";
    let got = codes_of(src);
    assert_eq!(got, vec![Code::B0001, Code::B0001, Code::B0003], "{got:?}");
}

/// **A name a builtin macro defines is bound.** `defflow(slug, …)` expands to
/// `(define slug …)`; the check stage expands top-level builtin macro calls to
/// see it. Found by the examples corpus (`examples/08_tatara_forms.b`, five
/// false positives) the day it landed.
///
/// Red run (2026-09-29): the expansion loop in `pipeline::program_names`
/// skipped — `left: [B0001, B0001]`.
#[test]
fn a_name_a_builtin_macro_defines_is_bound() {
    let src = "defflow(slug, trim, downcase)\n\nslug(\" A \")\n\n\
               defsm(door, :initial, :closed, :transitions, [%i[closed open opened]])\n\ndoor(:current)\n";
    assert_eq!(codes_of(src), Vec::<Code>::new());
}

/// **A waiver cannot silence a rule that guards meaning, and a waiver that
/// silences nothing is refused.** B0009 (two imports listing one name) is
/// not waivable: the program would have no one meaning. An unused waiver is
/// B0008, an error, and stops the run.
///
/// Red run (2026-09-29), `waivable` ignored in `waiver::collect`: the B0009
/// waiver is accepted and the check reports nothing (`[]`).
#[test]
fn a_waiver_on_an_unwaivable_rule_or_on_nothing_is_refused() {
    const P: &[(&str, &str)] = &[
        ("kagi_a", "def kagi()\n  1\nend\n"),
        ("kagi_b", "def kagi()\n  2\nend\n"),
    ];
    let src = "use(\"kagi_a\", [:kagi])\nuse(\"kagi_b\", [:kagi])\n\n# waive B0009: pick either\ndef f()\n  kagi()\nend\n";
    let got = codes_with(src, P);
    assert!(
        got.contains(&Code::B0007) && got.contains(&Code::B0009),
        "{got:?}"
    );

    let unused = "# waive B0002: nothing here is unused\ndef f(x)\n  x\nend\n\nf(1)\n";
    assert_eq!(codes_of(unused), vec![Code::B0008]);
    assert!(run(unused).is_err(), "an unused waiver stops the run");
}

#[test]
fn a_definition_the_evaluator_answers_first_stops_the_run_and_a_builtin_name_alone_does_not() {
    let refused = run("def apply()\n  1\nend\n\nx = apply\nto_s(x)\n");
    match refused {
        Err(RunError::Types(errors)) => {
            assert!(errors[0].contains("error[B0071]"), "{errors:?}");
        }
        other => panic!("a definition that never runs must stop the run: {other:?}"),
    }
    for name in [
        "list",
        "concat",
        "apply",
        "equal?",
        "mod",
        "join_lines",
        "unlines",
        "line_break",
        "when",
        "try",
        "let",
        "lambda",
        "eval",
    ] {
        let src = format!("def {name}(a)\n  a\nend\n");
        assert_eq!(codes_of(&src), vec![Code::B0071], "{name}");
    }
    let own = run("def size(xs)\n  99\nend\n\nsize([1, 2])\n").expect("an own definition wins");
    assert!(matches!(own.value, tatara_lisp_eval::Value::Int(99)));
    let waived = "# waive B0071: reached qualified\ndef apply(a)\n  a\nend\n";
    assert_eq!(codes_of(waived), Vec::<Code>::new());
    let stale = "# waive B0071: nothing here\ndef own(a)\n  a\nend\n";
    assert_eq!(codes_of(stale), vec![Code::B0008]);
}

#[test]
fn the_evaluator_name_rule_fires_exactly_on_the_names_a_definition_loses_to() {
    let probe = check_entry(
        Entry::anonymous("1\n"),
        &blue_lang_runtime::uses::NoLoader,
        None,
        Checking::Program,
    )
    .expect("checks");
    let mut names: Vec<String> = probe.names.all().map(|(_, b)| b.name.clone()).collect();
    names.extend(
        blue_lang_syntax::LOWERED_HEADS
            .iter()
            .map(ToString::to_string),
    );
    names.sort();
    names.dedup();
    let (mut measured, mut wrong) = (0, Vec::new());
    for name in &names {
        let src = format!("def {name}(zzq)\n  :mine\nend\n\n{name}(1)\n");
        let Ok(checked) = check_entry(
            Entry::anonymous(&src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            Checking::Program,
        ) else {
            continue;
        };
        let lowered = checked.lowered();
        let defines = lowered.first().is_some_and(|f| {
            f.to_sexp()
                .to_string()
                .starts_with(&format!("(define (%root/{name} "))
        });
        if !defines {
            continue;
        }
        measured += 1;
        let call = lowered
            .last()
            .map(|f| f.to_sexp().to_string())
            .unwrap_or_default();
        let own_wins = call.starts_with(&format!("(%root/{name} "));
        let fires = checked
            .outcome
            .diagnostics
            .iter()
            .any(|d| d.code == Code::B0071);
        if fires == own_wins {
            wrong.push(format!("{name}: fires {fires}, {call}"));
        }
    }
    assert!(measured > 200, "only {measured} names measured");
    assert!(wrong.is_empty(), "{}", wrong.join("\n"));
}

const KAGI_HEAD: &str = "@moduledoc \"\"\"\nkagi asks the machine.\n\n    1 + 1 #=> 2\n\"\"\"\n\n@doc \"\"\"\nkagi runs `date`.\n\n    1 + 1 #=> 2\n\"\"\"\ndef kagi()\n  exec_capture(\"date\")\nend\n\n@doc \"\"\"\nask_kagi asks kagi.\n\n    1 + 1 #=> 2\n\"\"\"\ndef ask_kagi()\n  kagi\nend\n";

fn kagi_codes(tests: &str) -> Vec<Code> {
    codes_in(
        Box::leak(format!("{KAGI_HEAD}\n{tests}").into_boxed_str()),
        &[],
        None,
        Some("kagi"),
    )
}

/// **An integration point with no test of its kind is refused, and the test
/// of its kind discharges it, directly or through a caller.** A unit test that
/// reaches the point does not.
///
/// Red run (2026-11-13): `point_diagnostics` removed from the check stage:
/// `a unit test does not discharge an effect point: []`.
#[test]
fn an_effect_point_is_discharged_only_by_a_test_of_its_kind() {
    assert_eq!(
        kagi_codes("test \"kagi\"\n  assert kagi != nil\nend\n"),
        vec![Code::B0083],
        "a unit test does not discharge an effect point"
    );
    assert_eq!(
        kagi_codes(
            "test \"kagi\", {kind: :integration, allow: [:process]}\n  assert kagi != nil\nend\n"
        ),
        Vec::<Code>::new()
    );
    assert_eq!(
        kagi_codes(
            "test \"through its caller\", {kind: :e2e, allow: [:process]}\n  assert ask_kagi != nil\nend\n"
        ),
        Vec::<Code>::new()
    );
}

/// A script owes no integration test: the point rule judges a bidama's file.
#[test]
fn a_script_owes_no_integration_test() {
    assert_eq!(
        codes_of("def kagi()\n  exec_capture(\"date\")\nend\n"),
        Vec::<Code>::new()
    );
}

/// The ambient capabilities make no point: a unit test reaches the
/// filesystem, the environment and the clock without a fake.
#[test]
fn an_ambient_builtin_makes_no_point() {
    for word in ["read_file(\"x\")", "getenv(\"HOME\")", "now_rfc3339"] {
        let src = format!(
            "@moduledoc \"\"\"\nkagi reads.\n\n    1 + 1 #=> 2\n\"\"\"\n\n@doc \"\"\"\nkagi reads.\n\n    1 + 1 #=> 2\n\"\"\"\ndef kagi()\n  {word}\nend\n"
        );
        assert_eq!(
            codes_in(Box::leak(src.into_boxed_str()), &[], None, Some("kagi")),
            Vec::<Code>::new(),
            "{word}"
        );
    }
}

/// A test's `allow:` names host capabilities; any other word is B0069.
#[test]
fn an_allow_naming_no_host_capability_is_refused() {
    assert_eq!(
        codes_of("test \"t\", {kind: :integration, allow: [:telepathy]}\n  assert true\nend\n"),
        vec![Code::B0069]
    );
    assert_eq!(
        codes_of(
            "test \"t\", {kind: :integration, allow: %i[comm_flash network]}\n  assert true\nend\n"
        ),
        Vec::<Code>::new()
    );
}

/// **A waiver of an integration point is judged only where points are
/// found.** A door that checks no tests (`blue run`, a compiler reading the
/// file) runs no point rule, so it neither applies the waiver nor calls it
/// stale.
///
/// Red run (2026-11-13): obligation waivers applied on every door:
/// `[B0008]` from the program check of a waived point.
#[test]
fn an_obligation_waiver_is_judged_only_where_tests_are_checked() {
    let src = KAGI_HEAD.replacen(
        "@doc \"\"\"\nkagi runs",
        "# waive B0083: the fixture's debt\n@doc \"\"\"\nkagi runs",
        1,
    );
    let surface = FullSurface::new();
    let path = surface.0.join("kagi.b");
    for checking in [Checking::Program, Checking::WithTests] {
        let checked = check_entry(
            Entry {
                path: Some(&path),
                text: &src,
            },
            &Imports(&[], None, Some("kagi"), None),
            None,
            checking,
        )
        .expect("checks");
        let codes: Vec<Code> = checked.outcome.diagnostics.iter().map(|d| d.code).collect();
        assert_eq!(codes, Vec::<Code>::new());
        assert_eq!(
            checked.outcome.waived.len(),
            usize::from(checking == Checking::WithTests)
        );
    }
}

/// **A project point is discharged by a test of its kind and by nothing
/// else.** A generator owes a rendering test, a service an end-to-end test,
/// and a service with a binding a contract test as well.
///
/// Red run (2026-11-13): `project_points` removed from the check stage:
/// `a generator with no rendering test: []`.
#[test]
fn a_project_point_is_discharged_only_by_a_test_of_its_kind() {
    let main = "def main()\n  1\nend\n\n";
    let with = |kind: &str| -> &'static str {
        Box::leak(
            format!("{main}test \"t\", {{kind: :{kind}}}\n  assert main == 1\nend\n")
                .into_boxed_str(),
        )
    };
    assert_eq!(
        codes_as(with("unit"), &[], None, None, Some("generator")),
        vec![Code::B0085],
        "a generator with no rendering test"
    );
    assert_eq!(
        codes_as(with("rendering"), &[], None, None, Some("generator")),
        Vec::<Code>::new()
    );
    assert_eq!(
        codes_as(with("e2e"), &[], None, None, Some("service")),
        Vec::<Code>::new()
    );
    assert_eq!(
        codes_as(with("contract"), &[], None, None, Some("binding")),
        vec![Code::B0086]
    );
    assert_eq!(
        codes_as(with("rendering"), &[], None, None, None),
        Vec::<Code>::new(),
        "a file no row names owes nothing"
    );
}
