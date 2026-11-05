use std::collections::BTreeMap;

use blue_lang_syntax::record::{record_parts, Record, LIST_TYPE, VALUE_TYPES};
use blue_lang_syntax::{LOWERED_KWARGS, LOWERED_MAP, LOWERED_MERGE, LOWERED_SPLICE};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::names::{resolve_program, NameTable, Namespace, Rule};
use crate::{Code, Diagnostic};

type Known<'a> = BTreeMap<&'a str, Record<'a>>;

fn shown(key: &str) -> String {
    let bare = key.strip_prefix("%root/").unwrap_or(key);
    bare.replace(blue_lang_syntax::QUALIFIER, "::")
}

fn head_of(form: &Spanned) -> Option<&str> {
    form.as_list()?.first()?.as_symbol()
}

fn kind_of(arg: &Spanned, known: &Known<'_>) -> Option<String> {
    let kind = match &arg.form {
        SpannedForm::Atom(Atom::Int(_)) => "Int",
        SpannedForm::Atom(Atom::Float(_)) => "Float",
        SpannedForm::Atom(Atom::Str(_)) => "Str",
        SpannedForm::Atom(Atom::Bool(_)) => "Bool",
        SpannedForm::Atom(Atom::Keyword(_)) => "Sym",
        SpannedForm::Nil => "Nil",
        SpannedForm::List(_) => match head_of(arg)? {
            "list" => LIST_TYPE,
            h if h == LOWERED_MAP => "Map",
            "concat" => "Str",
            h if known.contains_key(h) => h,
            _ => return None,
        },
        _ => return None,
    };
    Some(kind.to_string())
}

fn mismatch(want: &Spanned, arg: &Spanned, known: &Known<'_>) -> Option<(String, String)> {
    if let Some([head, inner]) = want.as_list() {
        if head.as_symbol() != Some(LIST_TYPE) {
            return None;
        }
        if head_of(arg) == Some("list") {
            return arg.as_list()?[1..]
                .iter()
                .find_map(|item| mismatch(inner, item, known))
                .map(|(w, g)| (format!("{LIST_TYPE}({w})"), format!("a list holding {g}")));
        }
        let got = kind_of(arg, known)?;
        return Some((format!("{LIST_TYPE}({})", shown_type(inner)), shown(&got)));
    }
    let want_name = want.as_symbol()?;
    let got = kind_of(arg, known)?;
    (got != want_name).then(|| (shown_type(want), shown(&got)))
}

fn shown_type(ty: &Spanned) -> String {
    match ty.as_symbol() {
        Some(n) if VALUE_TYPES.contains(&n) => n.to_string(),
        Some(n) => shown(n),
        None => LIST_TYPE.to_string(),
    }
}

fn entries_of(form: &Spanned, out: &mut Vec<(String, Span, Spanned)>) {
    let Some(items) = form.as_list() else { return };
    for pair in items[1..].chunks(2) {
        if let [key, value] = pair {
            let name = match &key.form {
                SpannedForm::Atom(Atom::Keyword(k) | Atom::Str(k)) => k.clone(),
                _ => continue,
            };
            out.push((name, key.span, value.clone()));
        }
    }
}

fn named(arg: &Spanned) -> Option<(Vec<(String, Span, Spanned)>, bool)> {
    let head = head_of(arg)?;
    let mut out = Vec::new();
    if head == LOWERED_MAP {
        entries_of(arg, &mut out);
        return Some((out, false));
    }
    if head != LOWERED_KWARGS && head != LOWERED_MERGE {
        return None;
    }
    let mut open = false;
    for part in &arg.as_list()?[1..] {
        match head_of(part) {
            Some(h) if h == LOWERED_MAP => entries_of(part, &mut out),
            Some(h) if h == LOWERED_SPLICE => open = true,
            _ => open = true,
        }
    }
    Some((out, open))
}

fn listed(names: &[&str]) -> String {
    names
        .iter()
        .map(|n| format!("`{n}`"))
        .collect::<Vec<_>>()
        .join(", ")
}

fn field_diagnostics(
    name: &str,
    fields: &[&str],
    found: impl Iterator<Item = (String, Span)>,
    top: usize,
    out: &mut Vec<Diagnostic>,
) {
    for (field, span) in found {
        out.push(
            Diagnostic::new(
                Code::B0079,
                format!("`{name}` has no field `{field}`"),
                span,
            )
            .at_top_level(top)
            .with_help(format!("its fields are {}", listed(fields))),
        );
    }
}

fn check_call(
    call: &Spanned,
    record: &Record<'_>,
    known: &Known<'_>,
    top: usize,
    out: &mut Vec<Diagnostic>,
) {
    let Some(items) = call.as_list() else { return };
    let name = shown(items[0].as_symbol().unwrap_or("_"));
    let fields = record.field_names();
    let args = &items[1..];
    let typed = |field: &str, arg: &Spanned, out: &mut Vec<Diagnostic>| {
        let want = record
            .fields
            .iter()
            .find(|f| f.name == field)
            .and_then(|f| f.ty);
        if let Some((w, g)) = want.and_then(|t| mismatch(t, arg, known)) {
            out.push(
                Diagnostic::new(
                    Code::B0079,
                    format!("`{name}`'s field `{field}` is {w}, and it is given {g}"),
                    arg.span,
                )
                .at_top_level(top),
            );
        }
    };
    if let [only] = args {
        if let Some((entries, open)) = named(only) {
            let unknown = entries
                .iter()
                .filter(|(k, _, _)| !fields.contains(&k.as_str()))
                .map(|(k, s, _)| (k.clone(), *s));
            field_diagnostics(&name, &fields, unknown, top, out);
            for (k, _, v) in &entries {
                typed(k, v, out);
            }
            if !open {
                let missing: Vec<&str> = fields
                    .iter()
                    .copied()
                    .filter(|f| !entries.iter().any(|(k, _, _)| k == f))
                    .collect();
                if !missing.is_empty() {
                    out.push(
                        Diagnostic::new(
                            Code::B0079,
                            format!("`{name}` is missing {}", listed(&missing)),
                            call.span,
                        )
                        .at_top_level(top)
                        .with_help(format!("its fields are {}", listed(&fields))),
                    );
                }
            }
            return;
        }
    }
    if args.len() != fields.len() {
        out.push(
            Diagnostic::new(
                Code::B0079,
                format!(
                    "`{name}` takes {} fields and is given {}",
                    fields.len(),
                    args.len()
                ),
                call.span,
            )
            .at_top_level(top)
            .with_help(format!("its fields are {}", listed(&fields))),
        );
        return;
    }
    for (field, arg) in fields.iter().zip(args) {
        typed(field, arg, out);
    }
}

fn walk(form: &Spanned, known: &Known<'_>, top: usize, out: &mut Vec<Diagnostic>) {
    let SpannedForm::List(items) = &form.form else {
        return;
    };
    if let Some(record) = items
        .first()
        .and_then(Spanned::as_symbol)
        .and_then(|h| known.get(h))
    {
        check_call(form, record, known, top, out);
    }
    for item in items {
        walk(item, known, top, out);
    }
}

#[must_use]
pub fn check(
    forms: &[Spanned],
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
) -> Vec<Diagnostic> {
    if !forms.iter().any(|f| record_parts(f).is_some()) {
        return Vec::new();
    }
    let tree = resolve_program(forms, table, namespace_of).resolved_tree(forms, Rule::Namespaced);
    let known: Known<'_> = tree
        .iter()
        .filter_map(record_parts)
        .filter_map(|r| Some((r.name.as_symbol()?, r)))
        .collect();
    let mut out = Vec::new();
    for (top, form) in tree.iter().enumerate() {
        if record_parts(form).is_none() {
            walk(form, &known, top, &mut out);
        }
    }
    out
}
