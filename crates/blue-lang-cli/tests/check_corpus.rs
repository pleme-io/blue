//! **The check stage reports zero errors on every `.b` file in the
//! repository.** An error that fires on correct code is worse than none: it
//! teaches every reader to ignore the checker, and since the check stage is on
//! every door (`run`, `test`, every bidama build), a false positive would
//! also stop correct programs from running at all.
//!
//! Measured on the introduction of static name resolution (2026-09-29): 55
//! files at first. The first pass reported 12 unbound names, every one a false
//! positive, from two gaps in the walker, both fixed in the walker rather
//! than waived:
//!
//! - `defmacro` is registered by the expander, not dispatched as a special
//!   form, so no arbiter claimed it and its parameters were never bound
//!   (8 findings, `spec/macros.b`);
//! - a `define` nested in the VALUE of another define —
//!   `converge = if … else home = … end` — binds in the enclosing function's
//!   frame, and the hoister only looked through `if`/`begin`/`cond`
//!   (4 findings, one site in `raifusaikuru.b` seen from four importers).
//!
//! Then the examples corpus landed (68 files) and brought a third: a
//! top-level call to a builtin macro that DEFINES a name — `defflow(slug, …)`,
//! `defsm(door, …)` — 5 findings in `examples/08_tatara_forms.b`. Fixed by
//! expanding such calls in `pipeline::program_names`, not by waiving them.
//!
//! Anti-vacuity is counted, not asserted non-empty: at least 40 files, and a
//! resolved-name total in the tens of thousands, so a pass that silently
//! resolved nothing — or a walk that found no files — cannot pass.
//!
//! Red run (2026-09-29): `bind` in `blue-lang-check`'s walker made a no-op, so
//! no parameter or local is ever in scope:
//! `the check stage reported 61392 error(s) on correct code`.

use std::path::{Path, PathBuf};

use blue_lang_runtime::pipeline::{check_entry, render, Checking};
use blue_lang_runtime::uses::Entry;

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("..")
}

/// Every `.b` file of the corpus: `blue_lang_pkg::corpus`, the walk
/// `blue census` counts over too.
fn corpus() -> Vec<PathBuf> {
    blue_lang_pkg::corpus::files(&root())
}

#[test]
fn the_check_stage_reports_no_error_on_the_corpus() {
    // Every distribution in the tree — blue's own `bidamas/`, and each
    // project's (`nix/project-fixture/bidamas`, `examples/bidamas`) — found
    // by the walk, not listed, so a new project is covered when it lands.
    let files = corpus();
    let loader = distribution_loader(&files);
    let mut errors = Vec::new();
    let mut resolved = 0usize;
    for path in &files {
        let text = std::fs::read_to_string(path).expect("read");
        let checked = check_entry(
            Entry {
                path: Some(path),
                text: &text,
            },
            &loader,
            None,
            Checking::WithTests,
        )
        .unwrap_or_else(|e| panic!("{}: {e}", path.display()));
        resolved += checked.outcome.stats.names_resolved;
        errors.extend(
            checked
                .outcome
                .errors()
                .map(|d| render(&checked.program, d)),
        );
    }
    assert!(
        files.len() >= 40,
        "the walk found {} .b files; the corpus has more than that",
        files.len()
    );
    assert!(
        resolved > 100_000,
        "only {resolved} names resolved across {} files: the pass is not looking",
        files.len()
    );
    assert!(
        errors.is_empty(),
        "the check stage reported {} error(s) on correct code:\n{}",
        errors.len(),
        errors.join("\n")
    );
}

/// **Measured: which distribution definitions replace a builtin.** The
/// runtime binds a name to the definition evaluated last, program-wide, so a
/// bidama `def` whose name a builtin also binds replaces the builtin for
/// every file of every program that imports it (`blue-lang-runtime`'s
/// `tests/resolution_order.rs` pins the mechanism). This lists them, over the
/// whole distribution (`zenbu`, the facade that needs every package), and
/// pins the list, so a new one is a decision someone sees rather than a
/// silent program-wide rebinding.
///
/// Definitions named like a MACRO or SPECIAL FORM are a separate, harsher
/// case: the macro expands the definition's own signature, so it cannot be
/// made at all. There are none, and the second assertion keeps it that way.
#[test]
fn distribution_definitions_that_replace_builtins_are_pinned() {
    use blue_lang_check::names::ScopeKind;
    use blue_lang_check::Namespace;
    let root = root();
    let loader = blue_lang_pkg::load_path::LoadPath::new([root.join("bidamas")]);
    let src = "use(\"zenbu\")\n";
    let checked =
        check_entry(Entry::anonymous(src), &loader, None, Checking::Program).expect("check");
    let table = &checked.names;
    let builtins: Vec<_> = table
        .scopes()
        .iter()
        .filter(|s| {
            matches!(
                s.namespace,
                Namespace::Builtin | Namespace::Macro | Namespace::SpecialForm
            )
        })
        .collect();
    let mut replaces_value = Vec::new();
    let mut replaces_head = Vec::new();
    for scope in table.scopes() {
        let Namespace::Bidama(pkg) = &scope.namespace else {
            continue;
        };
        for b in scope.bindings() {
            for bs in &builtins {
                if let Some(builtin) = bs.get(&b.name) {
                    let row = format!("{pkg}.{}", b.name);
                    match builtin.kind {
                        ScopeKind::Value => replaces_value.push(row),
                        _ => replaces_head.push(row),
                    }
                }
            }
        }
    }
    replaces_value.sort();
    assert_eq!(
        replaces_head,
        Vec::<String>::new(),
        "a definition named like a macro or special form cannot be made"
    );
    // Measured 2026-09-29: 17 definitions in 5 bidamas. retsu's are what
    // AUTHORING.md calls its "total replacements" (`retsu.first` is nil on an
    // empty list) — deliberate, and deliberately program-wide today.
    assert_eq!(
        replaces_value,
        [
            "kansuu.compose",
            "kansuu.flip",
            "kansuu.identity",
            "kansuu.juxt",
            "kansuu.pipe",
            "kansuu.tap",
            "kazu.abs",
            "kazu.max",
            "kazu.min",
            "retsu.first",
            "retsu.interleave",
            "retsu.last",
            "retsu.partition",
            "retsu.rest",
            "retsu.zip",
            "shuugou.frequencies",
            "shuugou.remove",
        ],
        "a bidama definition that replaces a builtin program-wide was added or removed; \
         update this list deliberately"
    );
}

/// **One binder grammar: the reach walk and the name table agree on which
/// names are free, over every file.** `blue_lang_waku::free_names` and the
/// check stage's table both drive `blue_lang_syntax::scope`; this is the gate
/// that they are wired to the same answer. A name is free for the reach walk
/// when no program form binds it and it is not a builtin; for the table, a
/// reference whose flat target is `Unbound`. The reach walk also counts the
/// symbols of a quasiquoted template (data at expansion, code after it),
/// which the table does not resolve, so those are added to the table's side.
///
/// Red run (2026-09-29), waku's own binder walk restored behind the same
/// `free_names` signature: 60 files disagree — a `catch` variable (`e`,
/// `_e`) and the `catch` clause head reported free, and the `deftest` head
/// of every file with tests.
#[test]
fn the_reach_walk_and_the_name_table_agree_on_free_names() {
    use std::collections::BTreeSet;
    let files = corpus();
    let loader = distribution_loader(&files);
    let mut disagreements = Vec::new();
    for path in &files {
        let text = std::fs::read_to_string(path).expect("read");
        let checked = check_entry(
            Entry {
                path: Some(path),
                text: &text,
            },
            &loader,
            None,
            Checking::WithTests,
        )
        .unwrap_or_else(|e| panic!("{}: {e}", path.display()));
        let forms = checked.program.forms();
        let table = &checked.names;
        let program_defined: BTreeSet<String> = table
            .scopes()
            .iter()
            .filter(|s| {
                matches!(
                    s.namespace,
                    blue_lang_check::Namespace::File(_) | blue_lang_check::Namespace::Bidama(_)
                )
            })
            .flat_map(|s| s.bindings().map(|b| b.name.clone()))
            .collect();
        // `defmacro`, `define-typed` and a top-level `use` are heads the
        // pipeline consumes before evaluation (the expander, erasure, the
        // resolver), so no interpreter scope binds them; the reach walk
        // reports every head.
        let builtin = |n: &str| {
            matches!(n, "defmacro" | "define-typed" | "use")
                || table.scopes().iter().any(|s| {
                    !matches!(
                        s.namespace,
                        blue_lang_check::Namespace::File(_) | blue_lang_check::Namespace::Bidama(_)
                    ) && s.get(n).is_some()
                })
        };
        let reach: BTreeSet<String> =
            blue_lang_waku::free_names(forms, &|n| builtin(n) || program_defined.contains(n));
        let mut table_free: BTreeSet<String> = checked
            .resolve()
            .references
            .iter()
            .filter(|r| r.flat == blue_lang_check::names::Target::Unbound)
            .map(|r| r.written.clone())
            .collect();
        table_free.extend(
            template_symbols(forms)
                .into_iter()
                .filter(|n| !builtin(n) && !program_defined.contains(n)),
        );
        // A template symbol can also be a local of the macro that holds it;
        // the reach walk binds it, the template scan cannot see frames.
        let only_reach: Vec<_> = reach.difference(&table_free).cloned().collect();
        let only_table: Vec<_> = table_free
            .difference(&reach)
            .filter(|n| !template_symbols(forms).contains(*n))
            .cloned()
            .collect();
        if !only_reach.is_empty() || !only_table.is_empty() {
            disagreements.push(format!(
                "{}: reach only {only_reach:?}, table only {only_table:?}",
                path.display()
            ));
        }
    }
    assert!(
        disagreements.is_empty(),
        "the two walks disagree:\n{}",
        disagreements.join("\n")
    );
}

/// Every symbol of every quasiquoted template, outside its `unquote`s.
fn template_symbols(forms: &[blue_lang_syntax::Spanned]) -> std::collections::BTreeSet<String> {
    use blue_lang_syntax::{Atom, SpannedForm};
    fn inside(
        f: &blue_lang_syntax::Spanned,
        quoted: bool,
        out: &mut std::collections::BTreeSet<String>,
    ) {
        match &f.form {
            SpannedForm::Atom(Atom::Symbol(s)) if quoted => {
                out.insert(s.clone());
            }
            SpannedForm::List(items) => items.iter().for_each(|i| inside(i, quoted, out)),
            SpannedForm::Quasiquote(i) => inside(i, true, out),
            SpannedForm::Unquote(i) | SpannedForm::UnquoteSplice(i) => inside(i, false, out),
            _ => {}
        }
    }
    let mut out = std::collections::BTreeSet::new();
    for f in forms {
        inside(f, false, &mut out);
    }
    out
}

/// A load path over every distribution in the tree, blue's own first.
fn distribution_loader(files: &[PathBuf]) -> blue_lang_pkg::load_path::LoadPath {
    blue_lang_pkg::corpus::load_path(&root(), files)
}
