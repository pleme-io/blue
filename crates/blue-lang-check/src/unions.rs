use std::collections::BTreeMap;

use blue_lang_syntax::record::record_parts;
use blue_lang_syntax::union::declared;
use tatara_lisp::{Spanned, SpannedForm};

use crate::names::{resolve_program, NameTable, Namespace, Rule};
use crate::{Code, Diagnostic};

const CASE_SUBJECT: &str = "case-subject";

struct Closed<'a> {
    name: &'a str,
    predicate: &'a str,
    arms: Vec<&'a str>,
}

fn shown(key: &str) -> String {
    let bare = key.strip_prefix("%root/").unwrap_or(key);
    bare.replace(blue_lang_syntax::QUALIFIER, "::")
}

fn head_of(form: &Spanned) -> Option<&str> {
    form.as_list()?.first()?.as_symbol()
}

struct Case<'a> {
    patterns: Vec<&'a str>,
    otherwise: bool,
}

fn case_of(form: &Spanned) -> Option<Case<'_>> {
    let items = form.as_list()?;
    let [head, binding, cond] = items else {
        return None;
    };
    if head.as_symbol() != Some("let") {
        return None;
    }
    let [only] = binding.as_list()? else {
        return None;
    };
    if head_of(only) != Some(CASE_SUBJECT) {
        return None;
    }
    let clauses = cond.as_list()?;
    let cond_word = clauses.first()?;
    if cond_word.as_symbol() != Some("cond") {
        return None;
    }
    let mut patterns = Vec::new();
    let mut otherwise = false;
    for clause in &clauses[1..] {
        let parts = clause.as_list()?;
        let test = parts.first()?;
        if test.as_symbol() == Some("else") {
            let implicit = test.span == cond_word.span
                && parts
                    .get(1)
                    .is_some_and(|b| matches!(b.form, SpannedForm::Nil));
            otherwise = !implicit;
            continue;
        }
        if let Some([predicate, subject]) = test.as_list() {
            if subject.as_symbol() == Some(CASE_SUBJECT) {
                if let Some(p) = predicate.as_symbol() {
                    patterns.push(p);
                }
            }
        }
        if let Some([eq, subject, pattern]) = test.as_list() {
            if eq.as_symbol() == Some("equal?") && subject.as_symbol() == Some(CASE_SUBJECT) {
                if let Some(p) = pattern.as_symbol() {
                    patterns.push(p);
                }
            }
        }
    }
    Some(Case {
        patterns,
        otherwise,
    })
}

fn listed(names: &[String]) -> String {
    names
        .iter()
        .map(|n| format!("`{n}`"))
        .collect::<Vec<_>>()
        .join(", ")
}

fn judge(
    form: &Spanned,
    case: &Case<'_>,
    unions: &[Closed<'_>],
    arm_names: &BTreeMap<&str, &str>,
    top: usize,
    out: &mut Vec<Diagnostic>,
) {
    if case.otherwise {
        return;
    }
    for u in unions {
        let touched = case
            .patterns
            .iter()
            .any(|p| *p == u.predicate || u.arms.contains(p));
        if !touched || case.patterns.contains(&u.predicate) {
            continue;
        }
        let missing: Vec<&str> = u
            .arms
            .iter()
            .copied()
            .filter(|a| !case.patterns.contains(a))
            .collect();
        if missing.is_empty() {
            continue;
        }
        let names: Vec<String> = missing
            .iter()
            .map(|a| shown(arm_names.get(a).copied().unwrap_or(a)))
            .collect();
        let tests: Vec<String> = missing.iter().map(|a| shown(a)).collect();
        out.push(
            Diagnostic::new(
                Code::B0081,
                format!(
                    "this case over the union `{}` misses {}",
                    shown(u.name),
                    listed(&names)
                ),
                form.span,
            )
            .at_top_level(top)
            .with_help(format!(
                "add {}, or an `else` for the rest",
                tests
                    .iter()
                    .map(|t| format!("`when {t}`"))
                    .collect::<Vec<_>>()
                    .join(", ")
            )),
        );
    }
}

fn walk(
    form: &Spanned,
    unions: &[Closed<'_>],
    arm_names: &BTreeMap<&str, &str>,
    top: usize,
    out: &mut Vec<Diagnostic>,
) {
    let SpannedForm::List(items) = &form.form else {
        return;
    };
    if let Some(case) = case_of(form) {
        judge(form, &case, unions, arm_names, top, out);
    }
    for item in items {
        walk(item, unions, arm_names, top, out);
    }
}

#[must_use]
pub fn check(
    forms: &[Spanned],
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
) -> Vec<Diagnostic> {
    if !forms.iter().any(|f| declared(f).is_some()) {
        return Vec::new();
    }
    let tree = resolve_program(forms, table, namespace_of).resolved_tree(forms, Rule::Namespaced);
    let unions: Vec<Closed<'_>> = tree
        .iter()
        .filter_map(declared)
        .filter_map(|d| {
            Some(Closed {
                name: d.name.as_symbol()?,
                predicate: d.predicate.as_symbol()?,
                arms: d.arms.iter().filter_map(Spanned::as_symbol).collect(),
            })
        })
        .collect();
    let arm_names: BTreeMap<&str, &str> = tree
        .iter()
        .filter_map(record_parts)
        .filter_map(|r| Some((r.predicate.as_symbol()?, r.name.as_symbol()?)))
        .collect();
    let mut out = Vec::new();
    for (top, form) in tree.iter().enumerate() {
        if declared(form).is_none() && record_parts(form).is_none() {
            walk(form, &unions, &arm_names, top, &mut out);
        }
    }
    out
}
