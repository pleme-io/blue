//! B0074: a bidama that moved into another bidama's tree, written by its old
//! name. The root it moved into declares the move in its Bluefile,
//! `legacy_packages("0.2.0", [["bpf", "kaaneru/bpf"]])`, and the resolver
//! loads `use("bpf")` as `kaaneru/bpf` ([`crate::names::PackageBridge`]). This
//! is the package twin of B0021: the old spelling resolves while the bridge is
//! open, is reported where it is written, and `blue check --fix` writes the
//! new path, in the `use`, in every qualifier that crossed the bridge, and,
//! for a bidama, in its Bluefile's `needs`.

use std::collections::{BTreeMap, BTreeSet};

use blue_lang_syntax::scope::{self, Import};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::names::{NameTable, Namespace, PackageBridge, Reference};
use crate::rules::Code;
use crate::{Applicability, Diagnostic, Edit, Fix, Severity};

/// `kaaneru/bpf` as a reader writes it: `kaaneru::bpf`.
fn spelled(level: &str) -> String {
    blue_lang_syntax::spell_level(level)
}

/// The path `written` names once its first segment is `b.new`.
fn moved(written: &str, b: &PackageBridge) -> String {
    match written.strip_prefix(b.old.as_str()) {
        Some("") => b.new.clone(),
        Some(rest) if rest.starts_with(blue_lang_syntax::QUALIFIER) => format!("{}{rest}", b.new),
        _ => written.to_string(),
    }
}

/// The root a bridge's level is in.
fn root(b: &PackageBridge) -> &str {
    blue_lang_syntax::root_of(&b.new)
}

fn severity(b: &PackageBridge, table: &NameTable) -> Severity {
    if !b.open || table.inside_distribution(b.top_level, &b.to) {
        Severity::Error
    } else {
        Severity::Warning
    }
}

fn diagnostic(b: &PackageBridge, table: &NameTable, message: String, span: Span) -> Diagnostic {
    let window = if b.open {
        format!(
            "the old name resolves only until `{}`'s next minor version",
            root(b)
        )
    } else {
        "the bridge has closed".to_string()
    };
    let mut d = Diagnostic::new(Code::B0074, message, span)
        .at_top_level(b.top_level)
        .with_help(format!(
            "write `use(\"{}\")` and `{}::name`; {window}; `blue check --fix` writes both",
            b.to,
            spelled(&b.to)
        ));
    d.severity = severity(b, table);
    d
}

fn headline(b: &PackageBridge) -> String {
    let closed = if b.open {
        ""
    } else {
        ", and the bridge has closed"
    };
    format!(
        "`{}` is the old name of `{}`, moved into bidama `{}` in {} (`legacy_packages`){closed}",
        spelled(&b.written),
        spelled(&b.to),
        root(b),
        b.since
    )
}

/// The string literal a `use` names its path with, when it is one: the
/// value of `use({s: "bpf"})`, or the first argument of `use("bpf", …)`.
/// Any other spelling is the author's, and only its qualifiers are fixed.
fn path_literal<'f>(form: &'f Spanned, import: &Import) -> Option<(&'f Spanned, &'f str)> {
    fn find(form: &Spanned, at: Span) -> Option<(&Spanned, &str)> {
        match &form.form {
            SpannedForm::Atom(Atom::Str(s)) if form.span == at => Some((form, s.as_str())),
            SpannedForm::List(items) => items.iter().find_map(|i| find(i, at)),
            _ => None,
        }
    }
    if import.alias.is_some() {
        return find(form, import.package_span);
    }
    let items = form.as_list()?;
    if items.first()?.as_symbol() != Some("use") {
        return None;
    }
    let first = items.get(1)?;
    find(first, first.span)
}

/// The fix that writes the moved path into the `use` itself.
fn use_edit(form: &Spanned, import: &Import, b: &PackageBridge) -> Option<Edit> {
    let (lit, text) = path_literal(form, import)?;
    if text.contains(['"', '\\']) {
        return None;
    }
    let path = text.replace("::", "/");
    let to = moved(&path, b);
    (to != path).then(|| Edit {
        span: lit.span,
        original: format!("\"{text}\""),
        replacement: format!("\"{to}\""),
    })
}

/// B0074 at each `use` that crossed a bridge, and at each qualifier the file
/// wrote through one.
pub(crate) fn check(
    forms: &[Spanned],
    table: &NameTable,
    references: &[Reference],
    out: &mut Vec<Diagnostic>,
) {
    for b in table.bridges() {
        let Some(form) = forms.get(b.top_level) else {
            continue;
        };
        let import = scope::use_targets(form)
            .into_iter()
            .flatten()
            .find(|i| i.package == b.written);
        let Some(import) = import else { continue };
        let mut d = diagnostic(b, table, headline(b), import.package_span);
        if let Some(edit) = use_edit(form, &import, b) {
            d = d.with_fix(Fix {
                message: format!("write `{}`", edit.replacement),
                edits: vec![edit],
                applicability: Applicability::MachineApplicable,
            });
        }
        out.push(d);
    }
    let mut seen: BTreeSet<(usize, usize, usize)> = BTreeSet::new();
    for r in references {
        let Some((q, n)) = blue_lang_syntax::qualified(&r.written) else {
            continue;
        };
        let first = blue_lang_syntax::root_of(q);
        let file = table.file_of(r.top_level);
        let Some(b) = table
            .bridges()
            .iter()
            .find(|b| b.old == first && table.file_of(b.top_level) == file)
        else {
            continue;
        };
        let through = table
            .imports_of(r.top_level)
            .and_then(|i| i.aliases.get(first))
            .is_some_and(|to| *to == b.new);
        if !through || !seen.insert((file, r.span.start, r.span.end)) {
            continue;
        }
        let original = format!("{}::{n}", spelled(q));
        let replacement = format!("{}::{n}", spelled(&moved(q, b)));
        let d = diagnostic(
            b,
            table,
            format!(
                "`{original}` is qualified by `{}`, the old name of `{}` (`legacy_packages`, {})",
                spelled(q),
                spelled(&moved(q, b)),
                b.since
            ),
            r.span,
        )
        .at_top_level(r.top_level)
        .with_fix(Fix {
            message: format!("write `{replacement}`"),
            edits: vec![Edit {
                span: r.span,
                original,
                replacement,
            }],
            applicability: Applicability::MachineApplicable,
        });
        out.push(d);
    }
}

/// The moved bidamas each bidama's Bluefile still `needs` by their old name,
/// and the root each is in now: `{app: {bpf: kaaneru}}`.
pub(crate) fn needed_by_old_name(
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
) -> BTreeMap<String, BTreeMap<String, String>> {
    let mut out: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
    for b in table.bridges() {
        let Namespace::Bidama(pkg) = namespace_of(b.top_level) else {
            continue;
        };
        let bidama = blue_lang_syntax::root_of(&pkg).to_string();
        if table.needs_of(&bidama).is_some_and(|n| n.contains(&b.old)) {
            out.entry(bidama)
                .or_default()
                .insert(b.old.clone(), root(b).to_string());
        }
    }
    out
}

/// B0074 for a bidama whose Bluefile `needs` a moved bidama by its old name,
/// at the `use` that crossed the bridge. `blue check --fix` rewrites the row
/// to the root's (`blue_lang_pkg::needs::prune`) and relocks.
pub(crate) fn needs_row(
    forms: &[Spanned],
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
    out: &mut Vec<Diagnostic>,
) {
    let old_needs = needed_by_old_name(table, namespace_of);
    let mut said: BTreeSet<(String, String)> = BTreeSet::new();
    for b in table.bridges() {
        let Namespace::Bidama(pkg) = namespace_of(b.top_level) else {
            continue;
        };
        let bidama = blue_lang_syntax::root_of(&pkg).to_string();
        let Some(to) = old_needs.get(&bidama).and_then(|m| m.get(&b.old)) else {
            continue;
        };
        if !said.insert((bidama.clone(), b.old.clone())) {
            continue;
        }
        let d = diagnostic(
            b,
            table,
            format!(
                "bidama `{bidama}`'s Bluefile needs `{}`, which moved into bidama `{to}` as `{}` in {}",
                b.old,
                spelled(&b.new),
                b.since
            ),
            forms.get(b.top_level).map_or_else(Span::synthetic, |f| f.span),
        )
        .with_help(format!(
            "`blue check --fix` on a file of {bidama} writes `needs(\"{to}\", …)` in place of `needs(\"{}\", …)` in {bidama}/Bluefile and relocks",
            b.old
        ));
        out.push(d);
    }
}
