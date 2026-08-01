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
//! ## The cost, stated plainly
//!
//! Evaluating a manifest is executing code. That is fine here because the code
//! is the project's own, and the same is true of `Rakefile`, `build.rs` and
//! `setup.py`. But it means a Bluefile is **not** safe to read from an
//! untrusted package: resolving a dependency's manifest would run the
//! dependency's code at resolve time. blue's answer is the `waku` frame — a
//! manifest read under a `Reach` that omits IO cannot *name* a file operation
//! — and **that restriction is not wired here yet.** Until it is, only read
//! Bluefiles you would run.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use blue_lang_waku::{When, Waku};
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
    let forms = blue_lang_syntax::parse_program(src)
        .map_err(|e| BluefileError::Parse(e.to_string()))?;
    let collected: Shared = Arc::new(Mutex::new(Collected::default()));

    let mut interp = blue_lang_runtime::interpreter_hostless();
    install_manifest_primitives(&mut interp, &collected);

    let erased = blue_lang_runtime::erase_types(&forms);
    let text = erased
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("\n");
    let spanned =
        tatara_lisp::read_spanned(&text).map_err(|e| BluefileError::Eval(format!("{e:?}")))?;
    interp
        .eval_program(&spanned, &mut ())
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

    const SIMPLE: &str = "package(\"myapp\", \"0.1.0\")\nneeds(\"gaming\", \"^1.2\")";

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
    #[test]
    fn a_runtime_error_in_a_bluefile_is_reported() {
        let err = read_bluefile("package(\"m\", \"1.0.0\")\nno_such_thing()").expect_err("reject");
        assert!(matches!(err, BluefileError::Eval(_)), "got {err}");
    }
}
