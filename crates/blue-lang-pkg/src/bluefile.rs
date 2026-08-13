//! The Bluefile: a manifest that is a blue program.
//!
//! ```text
//! package("myapp", "0.1.0")
//! needs("gaming", "^1.2")
//! needs("audio", ">=0.4.0")
//! posture(when: "preceding")
//! ```
//!
//! ## Why evaluation rather than a second parser
//!
//! Reading this file *is* running it: `package`, `needs` and `posture` are
//! primitives installed into a blue interpreter, and what they record is the
//! manifest. There is no Bluefile grammar, no TOML dialect, and nothing that
//! can drift from the language.
//!
//! The payoff is not tidiness. It means a manifest can **compute** — a version
//! from a variable, a dependency list from a macro, a conditional dependency
//! from an `if` — using the language the project is already written in, with the
//! same formatter and the same diagnostics.
//!
//! ## The cost, and the frame that pays it
//!
//! Evaluating a manifest is executing code. That is fine for a project's own
//! Bluefile, and the same is true of `Rakefile`, `build.rs` and `setup.py`. But
//! **resolving a dependency runs the dependency's code**: `GitRegistry` reads a
//! `Bluefile` out of every package on `BLUE_PATH`, and reading it is running
//! it.
//!
//! This module used to end that paragraph with "blue's answer is the `waku`
//! frame … **and that restriction is not wired here yet.** Until it is, only
//! read Bluefiles you would run." It is wired now: [`manifest_frame`] is the
//! frame a manifest evaluates in, and [`read_bluefile`] checks the manifest's
//! forms against it **before** the interpreter sees them.
//!
//! **What that buys, stated precisely — and the previous statement of it was
//! measurably wrong.** This paragraph used to read: *"Nothing dangerous is
//! bound in the manifest interpreter today — it is `interpreter_hostless` plus
//! three recording primitives — so the manifest was safe by absence of a
//! binding."* Measured 2026-08-13, the first clause is false.
//! `interpreter_hostless` is a fork of a base built by `interpreter(&mut ())`,
//! and `interpreter` installs the sys layer under `#[cfg(feature = "sys")]` —
//! so **whenever that feature is on, "hostless" binds all 37 host primitives**,
//! `read_file` and `rm_rf` among them. `blue-lang-cli` turns it on for itself,
//! and cargo unifies features across a workspace build, so it is on for this
//! crate's own `cargo test --workspace` run.
//! `blue-lang-cli/tests/capability_surface.rs` pins that as a measurement.
//!
//! **The manifest is still safe, by the frame rather than by absence** — which
//! is why this correction matters rather than merely being tidy. The old
//! reading credited a property the build does not have and treated the frame as
//! belt-and-braces; in fact the frame is the only thing standing between a
//! third-party Bluefile and `rm_rf`. A name outside the declared vocabulary is
//! refused before the interpreter is built, so installing a capability without
//! naming it in the frame is a **failing test**, not a quiet grant.
//!
//! **Honest tier: parse-time-rejected at this boundary, and no further.** A
//! [`Bluefile`] cannot be constructed from a manifest that escapes the frame,
//! and this is its only constructor. The check itself is `check_reach` over a
//! tree — a manifest that built a name at run time and `eval`d it would be
//! outside what the tree shows, which is what `When` tracks and this does not.
//! It is not unrepresentability: the escape is a `Result::Err`, not an absent
//! code path.
//!
//! **What is still missing, so nobody cites this as more than it is.** The
//! frame is a constant blue fixes, not something a manifest declares.
//!
//! **Half of the reason it could not be declared is gone as of 2026-08-13.**
//! This paragraph said a declared `Reach` *"needs a closed capability universe
//! to declare over, and blue has none — `Reach::Only` still takes arbitrary
//! strings."* `theory/BLUE-EXECUTION.md` M0 built that universe:
//! [`blue_lang_waku::Capability`] is closed, so `posture(reach: …)` now has an
//! enumerable vocabulary to accept and a misspelling in it would be a parse
//! failure rather than a silent grant of nothing.
//!
//! **`posture` still accepts only the `when` coordinate, and that is now a
//! plain to-do rather than a blocked design.** Accepting a `reach` means
//! deciding what a manifest keyword looks like and how a *dependency's*
//! declaration composes with the root's ceiling, which is bīdama's question,
//! not this module's. Recorded here so the next reader does not re-derive the
//! old blocker and conclude it is still there.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use blue_lang_waku::{check_reach_program, Capability, Waku, When};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{Interpreter, Value};

use crate::solve::Manifest;
use crate::version::{Range, Version};

/// What a Bluefile declared.
#[derive(Clone, Debug, PartialEq)]
pub struct Bluefile {
    pub name: String,
    pub version: Version,
    pub manifest: Manifest,
    /// The least frame this package needs — its bīdama floor.
    pub floor: Waku,
}

#[derive(Debug, thiserror::Error)]
pub enum BluefileError {
    #[error("parse error: {0}")]
    Parse(String),
    #[error("error evaluating the Bluefile: {0}")]
    Eval(String),
    /// A Bluefile with no `package(...)` call. Rejected rather than defaulted:
    /// a manifest that silently names itself `""` at version `0.0.0` resolves,
    /// and then nothing downstream can tell it apart from a real one.
    #[error("this Bluefile never calls `package(name, version)`")]
    NoPackage,
    #[error("{0}")]
    Version(#[from] crate::version::VersionError),
    #[error("`{0}` is not a recognised `when` posture (sealed, preceding, anytime)")]
    BadWhen(String),
    /// The manifest named something [`manifest_frame`] does not permit.
    ///
    /// Reported before evaluation, and carrying **every** escaping name rather
    /// than the first: a manifest author fixing one wants to see the rest, and
    /// a reviewer reading a refusal wants the whole set the package asked for.
    #[error(
        "this Bluefile names {} outside the manifest frame: {}. \
         A manifest may use the vocabulary in `blue_lang_pkg::bluefile::manifest_frame`; \
         widening it is a deliberate edit there, not something a manifest can ask for.",
        if .names.len() == 1 { "a name" } else { "names" },
        .names.join(", ")
    )]
    Escapes { names: Vec<String> },
}

/// The frame a Bluefile is evaluated in.
///
/// `When::Preceding` because a manifest is read top to bottom and nothing in it
/// should need a resident evaluator; `Where::Process` because it computes in
/// its own heap. The `Reach` is the manifest vocabulary: **three capabilities,
/// none of them a host effect**, so `imports_of(manifest_frame())` is empty and
/// a manifest opens nothing.
///
/// **The three name lists this function used to own moved into
/// [`blue_lang_waku::Capability`] when M0 closed the universe**, and the move is
/// the point rather than tidying: a vocabulary spelled out here was a set of
/// strings only this function could interpret, so nothing else could ask what a
/// frame grants. `Capability::ManifestDeclaration` still means exactly
/// `package`/`needs`/`posture`, `Capability::CoreForms` still means the nine
/// control-flow heads, and `Capability::Operators` is still *read from*
/// `blue_lang_syntax::INFIX` rather than copied out of it — the repo's rule that
/// `INFIX` is one table and both directions read it, now one level up.
///
/// Deliberately small. A manifest that wants `map` over a dependency list is
/// refused, and that is the design: widening the vocabulary a third party's
/// code may name is an edit to this function, reviewed once, rather than
/// something any manifest can help itself to.
#[must_use]
pub fn manifest_frame() -> Waku {
    Waku::macro_phase([
        Capability::ManifestDeclaration,
        Capability::CoreForms,
        Capability::Operators,
    ])
}

/// What the primitives record while the manifest runs.
#[derive(Default)]
struct Collected {
    package: Option<(String, String)>,
    needs: Vec<(String, String)>,
    when: Option<String>,
}

type Shared = Arc<Mutex<Collected>>;

/// Read a Bluefile from blue source.
pub fn read_bluefile(src: &str) -> Result<Bluefile, BluefileError> {
    // The SPANNED door, because erasure runs on spans now. A manifest reports
    // no positions of its own, so nothing here spends them — but taking the
    // spanless door would mean lifting back to `Spanned` before evaluation,
    // and that lift is the `Span::synthetic()` stamp the pipeline just stopped
    // paying.
    let forms = blue_lang_syntax::parse_program_tree(src)
        .map_err(|e| BluefileError::Parse(e.to_string()))?;
    let collected: Shared = Arc::new(Mutex::new(Collected::default()));

    let erased = blue_lang_runtime::erase_types(&forms);

    // THE FRAME, checked BEFORE the interpreter exists.
    //
    // Before evaluation and not during it, because the point is that a
    // manifest which names something outside the vocabulary never runs at all
    // — not that it runs until it reaches the bad call. `package("m","1.0.0")`
    // followed by an escaping call would otherwise have recorded the package
    // first.
    //
    // `check_reach_program` reads the spanless tree; the projection is the one
    // place this function throws a position away, and it throws none the
    // evaluation below needs.
    let escapes = check_reach_program(&manifest_frame(), &blue_lang_runtime::to_sexps(&erased));
    if !escapes.is_empty() {
        return Err(BluefileError::Escapes {
            names: escapes.into_iter().map(|e| e.name).collect(),
        });
    }

    let mut interp = blue_lang_runtime::interpreter_hostless();
    install_manifest_primitives(&mut interp, &collected);

    interp
        .eval_program(&erased, &mut ())
        .map_err(|e| BluefileError::Eval(e.to_string()))?;

    let c = collected.lock().expect("manifest lock");
    let (name, version_text) = c.package.clone().ok_or(BluefileError::NoPackage)?;
    let version = Version::parse(&version_text)?;

    let mut needs = BTreeMap::new();
    for (dep, range_text) in &c.needs {
        needs.insert(dep.clone(), Range::parse(range_text)?);
    }

    // The floor starts at the TOP and is lowered by declaration — a package
    // that declares nothing needs nothing restricted. Starting at the bottom
    // would make every unannotated package demand a sealed evaluator.
    let mut floor = Waku::top();
    if let Some(w) = &c.when {
        floor.when = match w.as_str() {
            "sealed" => When::Sealed,
            "preceding" => When::Preceding,
            "anytime" => When::Anytime,
            other => return Err(BluefileError::BadWhen(other.to_string())),
        };
    }

    Ok(Bluefile {
        name,
        version,
        manifest: Manifest { needs },
        floor,
    })
}

fn install_manifest_primitives(interp: &mut Interpreter<()>, collected: &Shared) {
    // package(name, version)
    let slot = collected.clone();
    interp.register_fn(
        "package",
        Arity::Exact(2),
        move |args: &[Value], _h: &mut (), _s| {
            if let (Value::Str(n), Value::Str(v)) = (&args[0], &args[1]) {
                if let Ok(mut c) = slot.lock() {
                    c.package = Some((n.to_string(), v.to_string()));
                }
            }
            Ok(Value::Nil)
        },
    );

    // needs(name, range)
    let slot = collected.clone();
    interp.register_fn(
        "needs",
        Arity::Exact(2),
        move |args: &[Value], _h: &mut (), _s| {
            if let (Value::Str(n), Value::Str(r)) = (&args[0], &args[1]) {
                if let Ok(mut c) = slot.lock() {
                    c.needs.push((n.to_string(), r.to_string()));
                }
            }
            Ok(Value::Nil)
        },
    );

    // posture(when) — one coordinate for now. `Reach` and `Where` are declared
    // but not yet accepted here, because a package's capability set needs the
    // capability surface to be wired before a declaration can mean anything.
    let slot = collected.clone();
    interp.register_fn(
        "posture",
        Arity::Exact(1),
        move |args: &[Value], _h: &mut (), _s| {
            let w = match &args[0] {
                Value::Str(s) => Some(s.to_string()),
                Value::Keyword(k) => Some(k.to_string()),
                _ => None,
            };
            if let (Some(w), Ok(mut c)) = (w, slot.lock()) {
                c.when = Some(w);
            }
            Ok(Value::Nil)
        },
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    const SIMPLE: &str = "package(\"myapp\", \"0.1.0\")\nneeds(\"gaming\", \"^1.2\")";

    /// **The frame did not change when its representation did.**
    ///
    /// M0 replaced three hand-written name lists in this file with three
    /// capabilities. The names are spelled out here — independently of the
    /// capability definitions, and matching what this function granted before
    /// the change — so a bundle that quietly grew or shrank moves the manifest
    /// vocabulary and fails here rather than widening what a third party's
    /// Bluefile may name.
    #[test]
    fn the_manifest_frame_grants_exactly_the_vocabulary_it_always_did() {
        let f = manifest_frame();
        let expected: BTreeSet<&str> = ["package", "needs", "posture"]
            .into_iter()
            .chain([
                "define", "defmacro", "lambda", "let", "begin", "if", "cond", "else", "not",
            ])
            .chain(blue_lang_syntax::INFIX.iter().map(|i| i.callee))
            .collect();

        for name in &expected {
            assert!(
                f.reach.permits(name),
                "the frame stopped permitting `{name}`"
            );
        }
        // And nothing beyond it. Checked against the whole universe rather than
        // a sample, so a fourth capability sneaking into the frame is caught.
        let granted: BTreeSet<&str> = Capability::ALL
            .into_iter()
            .filter(|c| f.reach.grants(*c))
            .flat_map(Capability::names)
            .collect();
        assert_eq!(granted, expected);

        // The manifest opens nothing: no host effect, so no import.
        assert!(blue_lang_waku::imports_of(&f).is_empty());
    }

    /// Anti-vacuity for the frame: it must actually REFUSE the host surface.
    /// A frame that permitted everything would pass every test above.
    #[test]
    fn the_manifest_frame_refuses_the_host_surface() {
        let f = manifest_frame();
        for name in ["read_file", "rm_rf", "exec_capture", "getenv", "now"] {
            assert!(!f.reach.permits(name), "the frame permits `{name}`");
        }
    }

    #[test]
    fn a_bluefile_declares_a_package_and_its_needs() {
        let b = read_bluefile(SIMPLE).expect("read");
        assert_eq!(b.name, "myapp");
        assert_eq!(b.version, Version::new(0, 1, 0));
        assert_eq!(b.manifest.needs["gaming"], Range::parse("^1.2").unwrap());
    }

    /// **The manifest can compute.** This is the point of the Bluefile being a
    /// blue program rather than a data format: the version comes from a
    /// function, and a data format could not express it.
    #[test]
    fn a_manifest_can_compute_its_own_values() {
        let b = read_bluefile(
            "def my_version()\n  \"2.3.4\"\nend\npackage(\"computed\", my_version())",
        )
        .expect("read");
        assert_eq!(b.version, Version::new(2, 3, 4));
    }

    /// And it can use a macro — the same expander a blue program uses, so a
    /// dependency list can be generated.
    #[test]
    fn a_manifest_can_use_a_macro() {
        let b = read_bluefile(
            "defmacro dep(n)\n  quote\n    needs(unquote(n), \"*\")\n  end\nend\n\
             package(\"m\", \"1.0.0\")\ndep(\"one\")\ndep(\"two\")",
        )
        .expect("read");
        assert_eq!(b.manifest.needs.len(), 2);
        assert!(b.manifest.needs.contains_key("one"));
        assert!(b.manifest.needs.contains_key("two"));
    }

    /// And conditionals, which is what a data format forces into a plugin.
    #[test]
    fn a_manifest_can_be_conditional() {
        let b = read_bluefile(
            "package(\"c\", \"1.0.0\")\nif 1 < 2\n  needs(\"yes\", \"*\")\nelse\n  needs(\"no\", \"*\")\nend",
        )
        .expect("read");
        assert!(b.manifest.needs.contains_key("yes"));
        assert!(!b.manifest.needs.contains_key("no"));
    }

    /// **A missing `package` is an error, not a default.** A manifest that
    /// silently names itself `""` at `0.0.0` resolves, and then nothing
    /// downstream can tell it from a real one.
    #[test]
    fn a_bluefile_with_no_package_call_is_rejected() {
        let err = read_bluefile("needs(\"a\", \"*\")").expect_err("must reject");
        assert!(matches!(err, BluefileError::NoPackage), "got {err}");
    }

    #[test]
    fn a_malformed_version_is_reported_as_a_version_error() {
        let err = read_bluefile("package(\"m\", \"not-a-version\")").expect_err("must reject");
        assert!(matches!(err, BluefileError::Version(_)), "got {err}");
    }

    #[test]
    fn a_malformed_range_is_reported() {
        let err =
            read_bluefile("package(\"m\", \"1.0.0\")\nneeds(\"a\", \"~~~\")").expect_err("reject");
        assert!(matches!(err, BluefileError::Version(_)), "got {err}");
    }

    /// **The floor starts at the top and is lowered by declaration.** A package
    /// that declares nothing needs nothing restricted; starting at the bottom
    /// would make every unannotated package demand a sealed evaluator.
    #[test]
    fn an_undeclared_posture_is_the_top_not_the_bottom() {
        let b = read_bluefile(SIMPLE).expect("read");
        assert_eq!(b.floor, Waku::top());
        assert_eq!(b.floor.when, When::Anytime);
    }

    #[test]
    fn a_declared_posture_lowers_the_floor() {
        let b = read_bluefile("package(\"m\", \"1.0.0\")\nposture(\"sealed\")").expect("read");
        assert_eq!(b.floor.when, When::Sealed);
        let b2 = read_bluefile("package(\"m\", \"1.0.0\")\nposture(:preceding)").expect("read");
        assert_eq!(b2.floor.when, When::Preceding, "a keyword works too");
    }

    /// An unknown posture is rejected rather than ignored. An ignored posture
    /// declaration is how a package comes to believe it is sealed when it is
    /// not.
    #[test]
    fn an_unknown_posture_is_rejected_not_ignored() {
        let err =
            read_bluefile("package(\"m\", \"1.0.0\")\nposture(\"whenever\")").expect_err("reject");
        assert!(matches!(err, BluefileError::BadWhen(_)), "got {err}");
    }

    #[test]
    fn a_syntax_error_in_a_bluefile_is_reported_as_one() {
        let err = read_bluefile("package(").expect_err("reject");
        assert!(matches!(err, BluefileError::Parse(_)), "got {err}");
    }

    /// A runtime error in the manifest is reported as such, not swallowed into
    /// a half-built manifest.
    ///
    /// The program has to fail *inside the frame* to reach evaluation at all —
    /// this used to be `no_such_thing()`, which the frame now refuses before
    /// the interpreter exists. Calling a permitted primitive wrongly is the
    /// remaining way to get there, and it is the more honest test: it proves
    /// the `Eval` arm is still reachable rather than dead behind the gate.
    #[test]
    fn a_runtime_error_in_a_bluefile_is_reported() {
        let err = read_bluefile("package(\"m\", \"1.0.0\")\nneeds(\"a\")").expect_err("reject");
        assert!(matches!(err, BluefileError::Eval(_)), "got {err}");
    }

    // ── the manifest frame ────────────────────────────────────────────────

    /// **The gate, red.** A manifest that names something the frame does not
    /// permit is refused, and the refusal names it.
    ///
    /// `no_such_thing()` was previously an `Eval` error — the manifest ran,
    /// recorded its package, and died at the call. That is the behaviour this
    /// changes.
    #[test]
    fn a_manifest_naming_something_outside_the_frame_is_refused() {
        let err =
            read_bluefile("package(\"m\", \"1.0.0\")\nno_such_thing()").expect_err("must refuse");
        match err {
            BluefileError::Escapes { names } => {
                assert_eq!(names, vec!["no_such_thing".to_string()])
            }
            other => panic!("expected an escape, got {other}"),
        }
    }

    /// **And it is refused BEFORE anything runs.** The escape sits after a
    /// perfectly good `package(...)`; if the check ran during evaluation the
    /// name would have been recorded first. Nothing observable survives a
    /// refused manifest.
    #[test]
    fn a_refused_manifest_never_runs_its_earlier_forms() {
        let src = "package(\"recorded\", \"1.0.0\")\nread_file(\"/etc/passwd\")";
        let err = read_bluefile(src).expect_err("must refuse");
        assert!(
            matches!(err, BluefileError::Escapes { ref names } if names == &["read_file".to_string()]),
            "got {err}"
        );
        // The whole point: there is no half-built manifest to observe. The
        // error carries no package, and `read_bluefile` is the only way to get
        // a `Bluefile`, so nothing downstream can see one.
        assert!(read_bluefile(src).is_err());
    }

    /// **Anti-vacuity.** Every Bluefile the distribution actually ships passes
    /// the frame. A frame nothing can satisfy would make the test above pass
    /// for the wrong reason, and a frame everything satisfies would make it
    /// impossible — this pins both ends against real files.
    #[test]
    fn every_bluefile_in_the_distribution_stays_inside_the_frame() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../bidamas")
            .canonicalize()
            .expect("the distribution is in the repo");
        let mut checked = 0usize;
        for entry in std::fs::read_dir(&root).expect("read bidamas") {
            let manifest = entry.expect("entry").path().join("Bluefile");
            if !manifest.is_file() {
                continue;
            }
            let src = std::fs::read_to_string(&manifest).expect("read manifest");
            read_bluefile(&src).unwrap_or_else(|e| {
                panic!("{} escaped the manifest frame: {e}", manifest.display())
            });
            checked += 1;
        }
        assert!(
            checked >= 18,
            "only {checked} manifests were checked — the corpus went missing, \
             which would make this test pass over nothing"
        );
    }

    /// The frame reads the operator table rather than copying it, so an
    /// operator added to `INFIX` is usable in a manifest with no second edit.
    #[test]
    fn the_frame_permits_every_operator_the_parser_lowers_to() {
        let frame = manifest_frame();
        for infix in blue_lang_syntax::INFIX {
            assert!(
                frame.reach.permits(infix.callee),
                "`{}` lowers to `{}`, which the manifest frame does not permit",
                infix.op,
                infix.callee
            );
        }
    }
}
