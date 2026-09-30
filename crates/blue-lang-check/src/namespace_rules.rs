//! The namespace rules that look at a whole file or a whole namespace, run
//! after the name walk: how a file declares its imports (B0015, B0016,
//! B0019) and how a bidama names its definitions (B0013, B0014, B0017). The
//! per-reference rules (B0009–B0012, B0018, B0020) are the walker's, in
//! [`crate::names`].
//!
//! Every one is a row in [`crate::RULES`]; which of them is enforced is the
//! row's `ratchet`, never a switch here.

use std::collections::{BTreeMap, BTreeSet};

use blue_lang_syntax::scope::{self, Import};
use tatara_lisp::{Span, Spanned};

use crate::names::{NameTable, Namespace, Reference, Target};
use crate::rules::Code;
use crate::{Applicability, Diagnostic, Edit, Fix};

/// A file's `use` declarations, each with its top-level index.
struct FileUses {
    uses: Vec<(usize, Import)>,
    /// Indices of the file's other top-level forms, in order.
    others: Vec<usize>,
}

/// Run the file and namespace rules over `forms`.
#[must_use]
pub fn check(
    forms: &[Spanned],
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
    references: &[Reference],
    whole_file: &dyn Fn(usize) -> bool,
) -> Vec<Diagnostic> {
    let mut out = Vec::new();
    let mut files: BTreeMap<usize, FileUses> = BTreeMap::new();
    for (i, form) in forms.iter().enumerate() {
        let file = table.file_of(i);
        let entry = files.entry(file).or_insert_with(|| FileUses {
            uses: Vec::new(),
            others: Vec::new(),
        });
        match scope::use_target(form) {
            Some(u) => entry.uses.push((i, u)),
            None => entry.others.push(i),
        }
    }
    for (file, fu) in &files {
        canonical_imports(fu, &mut out);
        // Only a file checked whole — its test blocks included, which an
        // imported bidama's are not — can say a listed name is never read.
        let whole = fu
            .uses
            .first()
            .map(|(i, _)| *i)
            .or(fu.others.first().copied())
            .is_some_and(whole_file);
        if whole {
            unused_imports(*file, fu, table, references, &mut out);
        }
    }
    needs_agree(&files, table, namespace_of, &mut out);
    definitions(forms, namespace_of, &mut out);
    out
}

/// How `use("pkg", [:a, :b])` is written, canonically.
fn render_use(import: &Import, names: &[String]) -> String {
    if names.is_empty() {
        format!("use(\"{}\")", import.package)
    } else {
        let list: Vec<String> = names.iter().map(|n| format!(":{n}")).collect();
        format!("use(\"{}\", [{}])", import.package, list.join(", "))
    }
}

/// B0015: one `use` per package, every `use` before the file's other forms,
/// sorted by package, each list sorted and without duplicates.
fn canonical_imports(fu: &FileUses, out: &mut Vec<Diagnostic>) {
    let first_other = fu.others.first().copied();
    let mut seen: BTreeSet<&str> = BTreeSet::new();
    let mut previous: Option<&str> = None;
    for (i, u) in &fu.uses {
        let at = |msg: String| Diagnostic::new(Code::B0015, msg, u.span).at_top_level(*i);
        if !seen.insert(u.package.as_str()) {
            out.push(
                at(format!("`{}` is used twice in this file", u.package))
                    .with_help("merge the two into one `use`, with one list"),
            );
            continue;
        }
        if first_other.is_some_and(|o| o < *i) {
            out.push(
                at(format!("`use(\"{}\")` comes after the file's definitions", u.package))
                    .with_help("move every `use` to the top of the file, before any other form"),
            );
        } else if previous.is_some_and(|p| p > u.package.as_str()) {
            out.push(
                at(format!("`use(\"{}\")` is out of order", u.package))
                    .with_help("sort the file's `use` forms by package name"),
            );
        }
        previous = Some(u.package.as_str());
        let written: Vec<String> = u.names.iter().map(|(n, _)| n.clone()).collect();
        let mut canonical = written.clone();
        canonical.sort();
        canonical.dedup();
        if u.listed && written.is_empty() {
            out.push(
                at(format!("`use(\"{}\", [])` lists nothing", u.package)).with_fix(Fix {
                    message: format!("write `use(\"{}\")`", u.package),
                    edits: vec![Edit {
                        span: u.span,
                        original: format!("use(\"{}\", [])", u.package),
                        replacement: render_use(u, &[]),
                    }],
                    applicability: Applicability::MachineApplicable,
                }),
            );
        } else if written != canonical {
            // Sorting a list changes nothing a program means, so the fix is
            // machine-applicable.
            out.push(
                at(format!(
                    "the names `use(\"{}\")` lists are not sorted, or repeat",
                    u.package
                ))
                .with_fix(Fix {
                    message: "sort the list and drop repeats".to_string(),
                    edits: vec![Edit {
                        span: u.span,
                        original: render_use(u, &written),
                        replacement: render_use(u, &canonical),
                    }],
                    applicability: Applicability::MachineApplicable,
                }),
            );
        }
    }
}

/// B0016: a `use` nothing in the file reaches, or a listed name nothing
/// reads. Reached means: under per-bidama namespaces, some reference of the
/// file binds to one of the package's definitions.
fn unused_imports(
    file: usize,
    fu: &FileUses,
    table: &NameTable,
    references: &[Reference],
    out: &mut Vec<Diagnostic>,
) {
    // (package, name) pairs the file's references bind to: under the
    // namespaced rule, every candidate of an ambiguous one, and — while the
    // flat rule still holds — what a bare name reaches through the one
    // global environment (B0012 reports those). A qualified reference
    // reaches its qualifier's package whatever it names.
    let mut reached: BTreeSet<(String, String)> = BTreeSet::new();
    for r in references.iter().filter(|r| table.file_of(r.top_level) == file) {
        let mut add = |t: &Target| match t {
            Target::Def(Namespace::Bidama(p), n) => {
                reached.insert((p.clone(), n.clone()));
            }
            Target::Ambiguous(nss) => {
                for ns in nss {
                    if let Namespace::Bidama(p) = ns {
                        reached.insert((p.clone(), r.written.clone()));
                    }
                }
            }
            _ => {}
        };
        add(&r.ns);
        add(&r.flat);
        if let Some((p, n)) = blue_lang_syntax::qualified(&r.written) {
            reached.insert((p.to_string(), n.to_string()));
        }
    }
    for (i, u) in &fu.uses {
        let via = table.imports_of(*i).map(|fi| &fi.via);
        let any = reached.iter().any(|(p, _)| {
            *p == u.package || via.is_some_and(|v| v.get(p) == Some(&u.package))
        });
        if !any {
            out.push(
                Diagnostic::new(
                    Code::B0016,
                    format!("nothing in this file reaches `{}`", u.package),
                    u.span,
                )
                .at_top_level(*i)
                .with_help(format!(
                    "list the names it uses (`use(\"{0}\", [:name])`) or qualify them (`{0}::name`); remove the `use` if it is not needed",
                    u.package
                )),
            );
            continue;
        }
        for (n, span) in &u.names {
            if !reached.contains(&(u.package.clone(), n.clone())) {
                out.push(
                    Diagnostic::new(
                        Code::B0016,
                        format!("`{n}` is listed from `{}` and never read", u.package),
                        *span,
                    )
                    .at_top_level(*i)
                    .with_help("remove it from the list"),
                );
            }
        }
    }
}

/// B0019: inside a bidama, the packages its source `use`s are exactly the
/// ones its Bluefile `needs`.
fn needs_agree(
    files: &BTreeMap<usize, FileUses>,
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
    out: &mut Vec<Diagnostic>,
) {
    // Per bidama: every use of every one of its files, and a form to report
    // a `needs` with no `use` at.
    let mut per: BTreeMap<String, (Vec<(usize, &Import)>, usize)> = BTreeMap::new();
    for fu in files.values() {
        let any = fu.uses.first().map(|(i, _)| *i).or(fu.others.first().copied());
        let Some(any) = any else { continue };
        let Namespace::Bidama(pkg) = namespace_of(any) else {
            continue;
        };
        let e = per.entry(pkg).or_insert((Vec::new(), any));
        e.0.extend(fu.uses.iter().map(|(i, u)| (*i, u)));
    }
    for (pkg, (uses, anchor)) in per {
        let Some(needs) = table.needs_of(&pkg) else {
            continue;
        };
        let used: BTreeSet<&str> = uses.iter().map(|(_, u)| u.package.as_str()).collect();
        for (i, u) in &uses {
            if !needs.contains(&u.package) {
                out.push(
                    Diagnostic::new(
                        Code::B0019,
                        format!(
                            "bidama `{pkg}` uses `{}`, and its Bluefile does not `needs` it",
                            u.package
                        ),
                        u.span,
                    )
                    .at_top_level(*i)
                    .with_help(format!(
                        "add `needs(\"{}\", \"^0.1\")` to {pkg}/Bluefile and run `blue lock {pkg}`",
                        u.package
                    )),
                );
            }
        }
        for n in needs.iter().filter(|n| !used.contains(n.as_str())) {
            out.push(
                Diagnostic::new(
                    Code::B0019,
                    format!("bidama `{pkg}`'s Bluefile needs `{n}`, and no file of it uses `{n}`"),
                    Span::synthetic(),
                )
                .at_top_level(anchor)
                .with_help(format!(
                    "remove the `needs` from {pkg}/Bluefile (and run `blue lock {pkg}`), or `use` it"
                )),
            );
        }
    }
}

/// B0013, B0014, B0017: how a bidama names its definitions.
fn definitions(
    forms: &[Spanned],
    namespace_of: &dyn Fn(usize) -> Namespace,
    out: &mut Vec<Diagnostic>,
) {
    // (namespace) -> [(name, span, top_level, is_function)]
    let mut defs: BTreeMap<Namespace, Vec<(String, Span, usize, bool)>> = BTreeMap::new();
    for (i, form) in forms.iter().enumerate() {
        let function = is_function_def(form);
        let mut here: BTreeSet<String> = BTreeSet::new();
        for (name, span, _) in scope::definitions_of(form) {
            if here.insert(name.clone()) {
                defs.entry(namespace_of(i))
                    .or_default()
                    .push((name, span, i, function));
            }
        }
    }
    for (ns, list) in &defs {
        // B0017: `def f` twice in one namespace. A value may be rebound at
        // the top level (`total = total + 1` in a script); a function is
        // defined once.
        let mut first: BTreeMap<&str, usize> = BTreeMap::new();
        for (name, span, i, function) in list {
            if !function {
                continue;
            }
            if first.contains_key(name.as_str()) {
                out.push(
                    Diagnostic::new(
                        Code::B0017,
                        format!("`{name}` is defined twice in {ns}"),
                        *span,
                    )
                    .at_top_level(*i)
                    .with_help("rename one; the one evaluated last would silently replace the other"),
                );
            } else {
                first.insert(name, *i);
            }
        }
        let Namespace::Bidama(pkg) = ns else { continue };
        // B0013: a definition that spells its own package.
        let own_prefix = format!("{pkg}_");
        for (name, span, i, _) in list {
            if name.starts_with(&own_prefix) && name.len() > own_prefix.len() {
                out.push(
                    Diagnostic::new(
                        Code::B0013,
                        format!("`{name}` spells its own bidama's name; the namespace already says it"),
                        *span,
                    )
                    .at_top_level(*i)
                    .with_help(format!(
                        "name it `{}`: callers write `{pkg}::{}`",
                        &name[own_prefix.len()..],
                        &name[own_prefix.len()..]
                    )),
                );
            }
        }
        // B0014: a hand-mangled namespace.
        if let Some(prefix) = mangling_prefix(list.iter().map(|(n, ..)| n.as_str())) {
            if let Some((name, span, i, _)) = list.iter().find(|(n, ..)| n.starts_with(&prefix)) {
                out.push(
                    Diagnostic::new(
                        Code::B0014,
                        format!(
                            "bidama `{pkg}` prefixes its definitions with `{prefix}` (`{name}`, …): a hand-made namespace"
                        ),
                        *span,
                    )
                    .at_top_level(*i)
                    .with_help(format!(
                        "the bidama is the namespace: strip `{prefix}` (callers write `{pkg}::name`), with `blue migrate`"
                    )),
                );
            }
        }
    }
}

/// `(define (f …) …)` or a macro.
fn is_function_def(form: &Spanned) -> bool {
    form.as_list().is_some_and(|items| {
        match items.first().and_then(Spanned::as_symbol) {
            Some("define" | "define-typed") => items.get(1).is_some_and(|t| t.as_list().is_some()),
            Some("defmacro") => true,
            _ => false,
        }
    })
}

/// The one `x_` prefix (one to four letters) that at least 90% of eight or
/// more names share, if there is one. Calibrated on the distribution: it
/// finds exactly the 13 hand-prefixed bidamas, and the next highest share is
/// 60%.
#[must_use]
pub fn mangling_prefix<'a>(names: impl Iterator<Item = &'a str>) -> Option<String> {
    let names: Vec<&str> = names.collect();
    if names.len() < 8 {
        return None;
    }
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    for n in &names {
        if let Some((p, rest)) = n.split_once('_') {
            if (1..=4).contains(&p.len()) && p.chars().all(|c| c.is_ascii_lowercase()) && !rest.is_empty()
            {
                *counts.entry(format!("{p}_")).or_default() += 1;
            }
        }
    }
    let (prefix, n) = counts.into_iter().max_by_key(|(_, n)| *n)?;
    (n * 10 >= names.len() * 9).then_some(prefix)
}
