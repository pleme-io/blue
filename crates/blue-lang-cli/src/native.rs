//! Tier T3 (docs/PERFORMANCE.md, 1.7.1): a definition compiled ahead of time by
//! chuuzou, one nix derivation per `def_hash`, and the run-time side that
//! answers a call from it.
//!
//! [`defs`] is what `blue ast --resolved --defs FILE` prints: each definition
//! of the entry file with its `def_hash` and its slice, the resolved forms of
//! every entry definition it reaches, each function and value renamed to
//! `%root/d_<hex>` after its own hash. The slice is then a function of the
//! hash: a rename changes no byte of it, and an edit outside what it reaches
//! changes none either. `native/build/defs.b` reads it, and
//! `nix/native-defs.nix` builds one derivation per slice.
//!
//! [`Tier`] is the call observer `BLUE_NATIVE=on` installs: a call of a
//! definition whose hash has an artifact under `BLUE_CACHE_SHARED`
//! (`blue_lang_mondou::store::native_artifact`), with every argument an Int,
//! is answered by running the artifact; any other call, and any artifact
//! that does not answer, runs in the interpreter as before.

use std::collections::{BTreeSet, HashMap};
use std::path::PathBuf;
use std::sync::Arc;

use blue_lang_mondou::def_hash::{DefHash, DefHashes, DefKind};
use blue_lang_runtime::observe::{Call, CallObserver, Exit};
use blue_lang_runtime::uses::ResolvedProgram;
use blue_lang_syntax::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::Value;

pub(crate) const ENV: &str = "BLUE_NATIVE";

/// Whether `BLUE_NATIVE`'s value turns the native tier on. Off unless named.
pub(crate) fn on(value: Option<&str>) -> bool {
    matches!(
        value.map(|v| v.trim().to_ascii_lowercase()).as_deref(),
        Some("on" | "1" | "true" | "yes")
    )
}

pub(crate) fn enabled() -> bool {
    on(std::env::var(ENV).ok().as_deref())
}

/// The name a definition takes in every slice: its own hash.
fn canonical(hash: &DefHash) -> String {
    format!("%root/d_{}", hash.hex())
}

fn renamable(form: &Spanned) -> bool {
    matches!(
        form.as_list()
            .and_then(|items| items.first())
            .and_then(Spanned::as_symbol),
        Some("define" | "define-typed")
    )
}

fn rename(form: &Spanned, names: &HashMap<&str, String>) -> Spanned {
    let renamed = match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => match names.get(s.as_str()) {
            Some(to) => SpannedForm::Atom(Atom::Symbol(to.clone())),
            None => form.form.clone(),
        },
        SpannedForm::List(items) => {
            SpannedForm::List(items.iter().map(|i| rename(i, names)).collect())
        }
        SpannedForm::Quote(x) => SpannedForm::Quote(Box::new(rename(x, names))),
        SpannedForm::Quasiquote(x) => SpannedForm::Quasiquote(Box::new(rename(x, names))),
        SpannedForm::Unquote(x) => SpannedForm::Unquote(Box::new(rename(x, names))),
        SpannedForm::UnquoteSplice(x) => SpannedForm::UnquoteSplice(Box::new(rename(x, names))),
        other => other.clone(),
    };
    Spanned::new(form.span, renamed)
}

fn reached(hashes: &DefHashes, from: usize, entry: &dyn Fn(usize) -> bool) -> BTreeSet<usize> {
    let mut seen = BTreeSet::new();
    let mut frontier = vec![from];
    while let Some(d) = frontier.pop() {
        if !entry(hashes.defs()[d].top_level) || !seen.insert(d) {
            continue;
        }
        frontier.extend(hashes.defs()[d].calls.iter().copied());
    }
    seen
}

/// Every unambiguous definition of the entry file of `program`: its key, its
/// `def_hash` as `def_hash(f)` answers it, its kind, the name it has in its
/// slice, and the slice. `lowered` is what the hash reads, `tree` the
/// resolved tree chuuzou reads, one form per top-level form of `program`.
///
/// # Errors
///
/// When `lowered` and `tree` do not hold one form per top-level form.
pub(crate) fn defs(
    program: &ResolvedProgram,
    lowered: &[Spanned],
    tree: &[Spanned],
) -> Result<serde_json::Value, String> {
    if lowered.len() != tree.len() {
        return Err(format!(
            "the lowered tree has {} forms and the resolved tree {}",
            lowered.len(),
            tree.len()
        ));
    }
    let hashes = blue_lang_mondou::hash_checked(program, lowered);
    let entry = |top: usize| program.owner_of(top) == Some(ResolvedProgram::ENTRY);
    let names: HashMap<&str, String> = hashes
        .defs()
        .iter()
        .filter(|d| entry(d.top_level) && !hashes.is_ambiguous(&d.key))
        .filter(|d| renamable(&tree[d.top_level]))
        .map(|d| (d.key.as_str(), canonical(&d.hash)))
        .collect();
    let mut out = Vec::new();
    for (i, d) in hashes.defs().iter().enumerate() {
        if !entry(d.top_level) || hashes.is_ambiguous(&d.key) {
            continue;
        }
        let mut seen = BTreeSet::new();
        let slice: Vec<String> = reached(&hashes, i, &entry)
            .into_iter()
            .map(|r| hashes.defs()[r].top_level)
            .collect::<BTreeSet<usize>>()
            .into_iter()
            .map(|top| rename(&tree[top], &names).to_sexp().to_string())
            .filter(|text| seen.insert(text.clone()))
            .collect();
        out.push(serde_json::json!({
            "key": d.key,
            "hash": d.hash.to_string(),
            "kind": match d.kind {
                DefKind::Function => "function",
                DefKind::Value => "value",
                DefKind::Macro => "macro",
            },
            "entry": names.get(d.key.as_str()).cloned().unwrap_or_else(|| d.key.clone()),
            "slice": slice.join("\n"),
        }));
    }
    Ok(serde_json::Value::Array(out))
}

struct Target {
    name: Option<String>,
    artifact: PathBuf,
}

/// The native tier over one program: each function definition whose
/// `def_hash` has an artifact, by the span its closure carries.
pub(crate) struct Tier {
    by_source: HashMap<Span, Target>,
    inner: Option<Arc<dyn CallObserver>>,
}

impl Tier {
    /// The tier for a program about to run, looking each definition's
    /// artifact up with `find`; a definition with none runs as before.
    pub(crate) fn over(
        w: &blue_lang_runtime::pipeline::Watched<'_>,
        find: &dyn Fn(&DefHash) -> Option<PathBuf>,
        inner: Option<Arc<dyn CallObserver>>,
    ) -> Arc<Self> {
        let hashes = blue_lang_mondou::hash_checked(w.program, w.lowered);
        let mut by_source = HashMap::new();
        for d in w.definitions.iter() {
            let Some(hashed) = hashes.at(d.top_level) else {
                continue;
            };
            if hashed.key != *d.key || hashed.kind != DefKind::Function {
                continue;
            }
            let Some(artifact) = find(&hashed.hash) else {
                continue;
            };
            let Some(items) = w.erased.get(d.top_level).and_then(Spanned::as_list) else {
                continue;
            };
            let source = match items.get(1).and_then(Spanned::as_symbol) {
                Some(_) => items.get(2).map(|l| (l.span, None)),
                None => Some((d.span, Some(d.key.to_string()))),
            };
            if let Some((span, name)) = source {
                by_source.insert(span, Target { name, artifact });
            }
        }
        Arc::new(Self { by_source, inner })
    }
}

/// Run one artifact on Int arguments: its result, or `None` when it did not
/// answer (a fault, an arity it refuses, an output that is not one Int).
pub(crate) fn call(artifact: &std::path::Path, args: &[i64]) -> Option<i64> {
    let out = std::process::Command::new(artifact)
        .args(args.iter().map(i64::to_string))
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8(out.stdout).ok()?;
    let mut lines = text.lines();
    let value = lines.next()?.trim().parse().ok()?;
    lines.next().is_none().then_some(value)
}

impl CallObserver for Tier {
    fn enter(&self, call_: &Call<'_>, args: &[Value]) -> Option<Value> {
        if let Some(answered) = self.inner.as_ref().and_then(|i| i.enter(call_, args)) {
            return Some(answered);
        }
        let target = self.by_source.get(&call_.source)?;
        if target.name.as_deref() != call_.name.map(|n| &**n) {
            return None;
        }
        let ints: Option<Vec<i64>> = args
            .iter()
            .map(|a| match a {
                Value::Int(n) => Some(*n),
                _ => None,
            })
            .collect();
        call(&target.artifact, &ints?).map(Value::Int)
    }

    fn leave(&self, call_: &Call<'_>, exit: Exit<'_>) {
        if let Some(inner) = &self.inner {
            inner.leave(call_, exit);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;

    fn checked(src: &str) -> blue_lang_runtime::pipeline::Checked {
        let loader = blue_lang_pkg::load_path::LoadPath::for_entry(
            &std::env::temp_dir().join("native-test.b"),
        );
        let c = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &loader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(c.outcome.ok(), "{:?}", c.outcome.diagnostics);
        c
    }

    fn slices(src: &str) -> BTreeMap<String, (String, String)> {
        let c = checked(src);
        let tree = c
            .resolve()
            .resolved_tree(c.program.forms(), blue_lang_check::names::Rule::Namespaced);
        let v = defs(&c.program, &c.lowered(), &tree).expect("aligned");
        v.as_array()
            .expect("a list")
            .iter()
            .map(|d| {
                (
                    d["key"].as_str().expect("key").to_string(),
                    (
                        d["hash"].as_str().expect("hash").to_string(),
                        d["slice"].as_str().expect("slice").to_string(),
                    ),
                )
            })
            .collect()
    }

    const BASE: &str = "def sq(x: Int) -> Int\n  x * x\nend\n\ndef sum(n: Int, acc: Int) -> Int\n  if n == 0\n    acc\n  else\n    sum(n - 1, acc + sq(n))\n  end\nend\n\ndef fib(n: Int) -> Int\n  if n < 2\n    n\n  else\n    fib(n - 1) + fib(n - 2)\n  end\nend\n";

    #[test]
    fn a_slice_holds_what_its_definition_reaches_named_by_hash() {
        let s = slices(BASE);
        let (sq_hash, sq_slice) = &s["%root/sq"];
        let (_, sum_slice) = &s["%root/sum"];
        let (_, fib_slice) = &s["%root/fib"];
        let sq_name = format!("%root/d_{}", sq_hash.trim_start_matches("b3:"));
        assert!(sq_slice.contains(&sq_name), "{sq_slice}");
        assert!(sum_slice.contains(&sq_name), "{sum_slice}");
        assert!(!fib_slice.contains(&sq_name), "{fib_slice}");
        assert!(!fib_slice.contains("%root/fib"), "{fib_slice}");
        assert_eq!(sq_slice.lines().count(), 1);
        assert_eq!(sum_slice.lines().count(), 2);
    }

    #[test]
    fn an_edit_moves_what_reaches_it_and_a_rename_moves_nothing() {
        let base = slices(BASE);
        let edited = slices(&BASE.replace("x * x", "x * x + 1"));
        let renamed = slices(&BASE.replace("fib", "fibonacci"));
        assert_ne!(base["%root/sq"], edited["%root/sq"]);
        assert_ne!(base["%root/sum"], edited["%root/sum"]);
        assert_eq!(base["%root/fib"], edited["%root/fib"]);
        assert_eq!(base["%root/fib"], renamed["%root/fibonacci"]);
    }

    #[test]
    fn the_hash_is_the_one_def_hash_answers() {
        let c = checked(BASE);
        let lowered = c.lowered();
        let ids = blue_lang_mondou::def_hash::identified(
            &lowered,
            &blue_lang_mondou::program_docs(&c.program),
            None,
        );
        let s = slices(BASE);
        for key in ["%root/sq", "%root/sum", "%root/fib"] {
            assert_eq!(ids[key], s[key].0, "{key}");
        }
    }

    #[test]
    fn the_tier_is_off_unless_named() {
        assert!(!on(None));
        assert!(!on(Some("off")));
        assert!(!on(Some("maybe")));
        assert!(on(Some(" On ")));
        assert!(on(Some("1")));
    }

    #[test]
    fn an_artifact_that_does_not_answer_one_int_is_no_answer() {
        assert_eq!(call(std::path::Path::new("/no/such/artifact"), &[1]), None);
    }
}
