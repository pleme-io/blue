//! `use("name")` — how a blue program consumes a bidama.
//!
//! ## The gap this closes
//!
//! Before this, blue's packaging had a manifest (`Bluefile`), a resolver
//! (`blue-lang-pkg`), a git registry and a nix derivation per package — and
//! **no way for a program to consume any of it**. `retsu/Bluefile` declared
//! `needs("kazu", "^0.1")` while `retsu`'s source never referenced a single
//! thing from kazu, because the language had no import form at all. The
//! dependency graph was described by four layers and traversed by none.
//!
//! That is the difference between packaging that exists and packaging that
//! works, and it is why this is a load-bearing addition rather than a
//! convenience: a distribution whose packages cannot see each other is a
//! directory of unrelated files wearing a distribution's name.
//!
//! ## Why a pipeline pass and not a builtin
//!
//! A `register_fn` native takes `(&[Value], &mut H, Span)`. It cannot define
//! anything, because it never sees the interpreter — so `use` implemented as a
//! builtin could load a package's text and would have nowhere to put its
//! definitions. Resolution therefore happens on the FORM tree, before
//! evaluation: a `use` is replaced by the forms of the package it names, and
//! the whole program is then checked and run as one unit.
//!
//! That ordering is deliberate and worth stating, because it decides a real
//! behaviour: the type checker sees the imported code, so a package that fails
//! `blue-lang-check` fails at the point its consumer imports it rather than at
//! whatever later moment its code first ran.
//!
//! ## Why the loader is a trait
//!
//! Loading a package means reading a filesystem, and this crate compiles to
//! `wasm32-unknown-unknown` with zero host imports (`blue-lang-wasm`). A
//! direct `std::fs` call here would break that target for every consumer,
//! including ones that never call `use`.
//!
//! So the capability is injected — [`Loader`] here, the real filesystem
//! implementation in `blue-lang-pkg`, which is native-only. This is the
//! fleet's mockable-`Environment` seam, and it buys the usual thing: every
//! test below drives the whole resolution pass against an in-memory loader,
//! with no temp directories and no fixture files on disk.

use std::collections::BTreeSet;

use tatara_lisp::{Atom, Sexp};

/// Supplies the source of a named bidama.
///
/// One method, because resolution needs exactly one thing: given a name, the
/// blue source that name refers to. *Where* it came from — a working tree, a
/// nix store path, a git object, memory — is the implementation's business and
/// deliberately invisible here.
pub trait Loader {
    /// The `.b` sources of `name`, as `(label, source)` pairs.
    ///
    /// The label is for diagnostics only; nothing keys on it. A package with
    /// several files returns several pairs, and their relative order is the
    /// implementation's to fix — [`FsLoader`](../../blue_lang_pkg/load_path/index.html)
    /// sorts by filename so a load is reproducible rather than
    /// directory-order-dependent.
    ///
    /// `Err` is a human-readable reason the package could not be loaded. It
    /// must name what was looked for, because "package not found" without a
    /// name sends the reader grepping a distribution to find which one.
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String>;
}

/// A loader that resolves nothing, and says so.
///
/// The default for [`run`](crate::pipeline::run), so a program using `use` in
/// a context with no packaging configured gets a typed error naming the
/// package — not a silently-undefined function that fails much later as an
/// unbound symbol pointing at innocent code.
pub struct NoLoader;

impl Loader for NoLoader {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        Err(format!(
            "cannot load bidama \"{name}\": no loader is installed. A program \
             that uses packages must run with one — `blue_lang_pkg::LoadPath` \
             reads BLUE_PATH, which `nix develop` and the bidama derivations \
             populate."
        ))
    }
}

/// Is this form a `use("name")` call? If so, the name.
///
/// Matches the *call* form only. `use "kazu"` without parentheses parses as
/// two unrelated top-level atoms (blue has no paren-less call syntax), which
/// would silently do nothing — so it is not treated as an import, and the
/// bare symbol `use` then fails as an unbound name rather than being quietly
/// ignored.
fn use_target(form: &Sexp) -> Option<String> {
    let Sexp::List(items) = form else {
        return None;
    };
    let [head, arg] = items.as_slice() else {
        return None;
    };
    match (head, arg) {
        (Sexp::Atom(Atom::Symbol(s)), Sexp::Atom(Atom::Str(name))) if s == "use" => {
            Some(name.clone())
        }
        _ => None,
    }
}

/// Replace every `use(...)` with the forms of the package it names.
///
/// Transitive by construction: a loaded package's own `use` calls are resolved
/// the same way, depth-first, so a consumer names its direct dependency and
/// gets the closure.
///
/// **A package is loaded at most once.** Two importers of one package must
/// share its definitions — loading twice would re-evaluate them, which is at
/// best wasted work and at worst two distinct copies of anything stateful.
/// That same visited-set is what makes a dependency CYCLE terminate: the
/// second visit is a no-op rather than infinite recursion, so a cyclic
/// distribution loads and runs instead of hanging.
///
/// # Errors
///
/// Returns the loader's message, prefixed with the import chain that reached
/// it, when a package cannot be loaded or its source cannot be parsed.
pub fn resolve_uses(forms: Vec<Sexp>, loader: &dyn Loader) -> Result<Vec<Sexp>, String> {
    let mut seen = BTreeSet::new();
    expand(forms, loader, &mut seen, &[])
}

fn expand(
    forms: Vec<Sexp>,
    loader: &dyn Loader,
    seen: &mut BTreeSet<String>,
    chain: &[String],
) -> Result<Vec<Sexp>, String> {
    let mut out = Vec::with_capacity(forms.len());
    for form in forms {
        let Some(name) = use_target(&form) else {
            out.push(form);
            continue;
        };
        if !seen.insert(name.clone()) {
            continue;
        }

        let sources = loader.load(&name).map_err(|e| describe(chain, &name, &e))?;
        let mut inner_chain = chain.to_vec();
        inner_chain.push(name.clone());

        for (label, src) in sources {
            let parsed = blue_lang_syntax::parse_program(&src)
                .map_err(|e| describe(chain, &name, &format!("{label}: {e}")))?;
            out.extend(expand(parsed, loader, seen, &inner_chain)?);
        }
    }
    Ok(out)
}

/// Prefix a failure with the import chain that reached it.
///
/// A transitive failure otherwise names only the leaf, and the reader has no
/// way to tell which of their own imports pulled it in — the exact question
/// they need answered to fix it.
fn describe(chain: &[String], name: &str, reason: &str) -> String {
    if chain.is_empty() {
        return reason.to_owned();
    }
    format!("while loading {} -> {name}: {reason}", chain.join(" -> "))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    /// An in-memory distribution — the whole pass runs with no filesystem.
    struct MemLoader(BTreeMap<&'static str, &'static str>);

    impl Loader for MemLoader {
        fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
            self.0
                .get(name)
                .map(|s| vec![(format!("{name}.b"), (*s).to_owned())])
                .ok_or_else(|| format!("no bidama named \"{name}\""))
        }
    }

    fn parse(src: &str) -> Vec<Sexp> {
        blue_lang_syntax::parse_program(src).expect("test source must parse")
    }

    #[test]
    fn a_use_is_replaced_by_the_packages_forms() {
        let loader = MemLoader(BTreeMap::from([("kazu", "def double(n)\n  n * 2\nend")]));
        let out = resolve_uses(parse("use(\"kazu\")\ndouble(21)"), &loader).expect("resolves");
        // The `use` itself is GONE — it is not a call that survives to the
        // evaluator, where `use` is not a defined function.
        assert!(
            out.iter().all(|f| super::use_target(f).is_none()),
            "a use form survived resolution and would reach the evaluator as \
             an unbound function: {out:?}"
        );
        assert!(
            out.len() > 1,
            "the package's definitions must be spliced in, not dropped: {out:?}"
        );
    }

    #[test]
    fn imports_are_transitive() {
        let loader = MemLoader(BTreeMap::from([
            ("retsu", "use(\"kazu\")\ndef sum2(a, b)\n  a + b\nend"),
            ("kazu", "def double(n)\n  n * 2\nend"),
        ]));
        let out = resolve_uses(parse("use(\"retsu\")"), &loader).expect("resolves");
        // A consumer names retsu only; kazu arrives because retsu needs it.
        assert!(
            out.len() >= 2,
            "the transitive dependency did not arrive: {out:?}"
        );
    }

    #[test]
    fn a_package_is_loaded_at_most_once() {
        let loader = MemLoader(BTreeMap::from([("kazu", "def double(n)\n  n * 2\nend")]));
        let once = resolve_uses(parse("use(\"kazu\")"), &loader).expect("resolves");
        let twice = resolve_uses(parse("use(\"kazu\")\nuse(\"kazu\")"), &loader).expect("resolves");
        assert_eq!(
            once.len(),
            twice.len(),
            "importing a package twice duplicated its definitions; two \
             importers of one package must share it"
        );
    }

    /// The property that keeps a cyclic distribution from hanging.
    #[test]
    fn a_dependency_cycle_terminates() {
        let loader = MemLoader(BTreeMap::from([
            ("a", "use(\"b\")\ndef fa()\n  1\nend"),
            ("b", "use(\"a\")\ndef fb()\n  2\nend"),
        ]));
        let out = resolve_uses(parse("use(\"a\")"), &loader).expect("a cycle must resolve");
        assert!(!out.is_empty(), "a cycle resolved to nothing: {out:?}");
    }

    #[test]
    fn a_missing_package_names_itself_and_the_chain() {
        let loader = MemLoader(BTreeMap::from([("retsu", "use(\"nowhere\")")]));
        let err = resolve_uses(parse("use(\"retsu\")"), &loader).expect_err("must fail");
        assert!(
            err.contains("nowhere"),
            "the error must name the missing package: {err}"
        );
        assert!(
            err.contains("retsu"),
            "the error must name the import that pulled it in, or the reader \
             cannot tell which of their own imports is at fault: {err}"
        );
    }

    #[test]
    fn the_default_loader_refuses_by_name() {
        let err = resolve_uses(parse("use(\"kazu\")"), &NoLoader).expect_err("must fail");
        assert!(
            err.contains("kazu"),
            "NoLoader must name what was asked for: {err}"
        );
    }

    /// A non-`use` program must come out byte-identical.
    ///
    /// This pass runs on EVERY program, so a bug here would corrupt source
    /// that never mentions a package.
    #[test]
    fn a_program_without_imports_is_unchanged() {
        let loader = MemLoader(BTreeMap::new());
        let src = parse("def f(n)\n  n + 1\nend\nf(1)");
        let out = resolve_uses(src.clone(), &loader).expect("resolves");
        assert_eq!(format!("{src:?}"), format!("{out:?}"));
    }
}
