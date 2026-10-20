use std::collections::HashMap;

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::{Code, Diagnostic};

#[must_use]
pub fn check(forms: &[Spanned], is_entry: &dyn Fn(usize) -> bool, script: bool) -> Vec<Diagnostic> {
    let mut out = Vec::new();
    let mut tests: HashMap<String, Span> = HashMap::new();
    let entry: Vec<(usize, &Spanned)> = forms
        .iter()
        .enumerate()
        .filter(|(i, _)| is_entry(*i))
        .collect();
    for (i, form) in &entry {
        swallowed(form, *i, &mut out);
        if !is_constant(form) {
            names(form, *i, &mut out);
        }
        if let Some((name, span)) = test_name(form) {
            if tests.contains_key(&name) {
                out.push(
                    Diagnostic::new(
                        Code::B0039,
                        format!("a test named \"{name}\" is already in this file"),
                        span,
                    )
                    .at_top_level(*i)
                    .with_help("rename one of the two so each says what it holds"),
                );
            } else {
                tests.insert(name, span);
            }
        }
    }
    let bodies: Vec<&Spanned> = entry.iter().map(|(_, f)| *f).collect();
    if script {
        if let Some(prefix) = script_prefix(&bodies) {
            let at = entry
                .iter()
                .find(|(_, f)| defined_name(f).is_some_and(|n| n.starts_with(&prefix)));
            if let Some((i, f)) = at {
                let fixable = strip_plan(&bodies, &prefix).is_some();
                let message = format!(
                    "this program prefixes its definitions with `{prefix}`, a hand-made namespace; the file is the namespace"
                );
                let help = if fixable {
                    format!("`blue fmt --write`, `blue run` and `blue check --fix` strip `{prefix}` from every definition and use")
                } else {
                    format!("strip `{prefix}` by hand: a stripped name is already used in the file, a builtin or a reserved word")
                };
                out.push(
                    Diagnostic::new(Code::B0043, message, f.span)
                        .at_top_level(*i)
                        .with_help(help),
                );
            }
        }
    }
    for (i, form) in &entry {
        if let Some(guard) = main_guard(form) {
            let d = match guard_fix(&bodies, guard) {
                Ok(_) => Diagnostic::new(
                    Code::B0041,
                    format!("this guard runs `{}` as the program's entry point; it is written `def main()`", guard.callee),
                    form.span,
                )
                .at_top_level(*i)
                .with_help("`blue fmt --write`, `blue run` and `blue check --fix` remove the guard and name the function `main`; `blue run` calls `main`, and `blue test` and `use` never do"),
                Err(why) => Diagnostic::new(
                    Code::B0041,
                    format!("this guard runs `{}` as the program's entry point, and {why}", guard.callee),
                    form.span,
                )
                .at_top_level(*i)
                .with_help("define `def main()` as the entry point and remove the guard by hand; `blue run` calls `main`"),
            };
            out.push(d);
        }
    }
    out
}

fn defined_name(form: &Spanned) -> Option<&str> {
    let items = form.as_list()?;
    if !matches!(
        items.first().and_then(Spanned::as_symbol),
        Some("define" | "define-typed" | "defmacro")
    ) {
        return None;
    }
    match items.get(1)? {
        s if s.as_symbol().is_some() && items[0].as_symbol() == Some("defmacro") => s.as_symbol(),
        s => s.as_list()?.first()?.as_symbol(),
    }
}

fn script_prefix(forms: &[&Spanned]) -> Option<String> {
    let names: Vec<&str> = forms.iter().filter_map(|f| defined_name(f)).collect();
    if names.len() < 3 {
        return None;
    }
    let first = names[0].split_once('_')?.0;
    let shaped = (1..=4).contains(&first.len()) && first.chars().all(|c| c.is_ascii_lowercase());
    let prefix = format!("{first}_");
    (shaped
        && names
            .iter()
            .all(|n| n.starts_with(&prefix) && n.len() > prefix.len()))
    .then_some(prefix)
}

fn symbols(form: &Spanned, out: &mut std::collections::BTreeSet<String>) {
    match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => {
            out.insert(s.clone());
        }
        SpannedForm::List(items) => items.iter().for_each(|i| symbols(i, out)),
        SpannedForm::Quote(i)
        | SpannedForm::Quasiquote(i)
        | SpannedForm::Unquote(i)
        | SpannedForm::UnquoteSplice(i) => {
            symbols(i, out);
        }
        _ => {}
    }
}

fn strip_plan(forms: &[&Spanned], prefix: &str) -> Option<Vec<(String, String)>> {
    let mut used = std::collections::BTreeSet::new();
    for f in forms {
        symbols(f, &mut used);
    }
    let mut plan = Vec::new();
    for f in forms {
        let Some(name) = defined_name(f) else {
            continue;
        };
        let Some(stripped) = name.strip_prefix(prefix).filter(|s| !s.is_empty()) else {
            continue;
        };
        if used.contains(stripped) || blue_lang_syntax::is_reserved_word(stripped) {
            return None;
        }
        plan.push((name.to_string(), stripped.to_string()));
    }
    let mut seen = std::collections::BTreeSet::new();
    plan.iter()
        .all(|(_, s)| seen.insert(s.clone()))
        .then_some(plan)
}

#[must_use]
pub fn without_prefix(forms: &[Spanned]) -> Option<Vec<Spanned>> {
    let refs: Vec<&Spanned> = forms.iter().collect();
    let prefix = script_prefix(&refs)?;
    let plan = strip_plan(&refs, &prefix)?;
    let map: std::collections::HashMap<&str, &str> =
        plan.iter().map(|(a, b)| (a.as_str(), b.as_str())).collect();
    Some(forms.iter().map(|f| rename_all(f, &map)).collect())
}

fn rename_all(form: &Spanned, map: &std::collections::HashMap<&str, &str>) -> Spanned {
    let inner = match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => match map.get(s.as_str()) {
            Some(to) => SpannedForm::Atom(Atom::Symbol((*to).to_string())),
            None => SpannedForm::Atom(Atom::Symbol(s.clone())),
        },
        SpannedForm::List(items) => {
            SpannedForm::List(items.iter().map(|i| rename_all(i, map)).collect())
        }
        SpannedForm::Quote(i) => SpannedForm::Quote(Box::new(rename_all(i, map))),
        SpannedForm::Quasiquote(i) => SpannedForm::Quasiquote(Box::new(rename_all(i, map))),
        SpannedForm::Unquote(i) => SpannedForm::Unquote(Box::new(rename_all(i, map))),
        SpannedForm::UnquoteSplice(i) => SpannedForm::UnquoteSplice(Box::new(rename_all(i, map))),
        other => other.clone(),
    };
    Spanned::new(form.span, inner)
}

fn test_name(form: &Spanned) -> Option<(String, Span)> {
    let items = form.as_list()?;
    if items.len() == 3 && items[0].as_symbol() == Some("deftest") {
        return Some((items[1].as_string()?.to_string(), items[1].span));
    }
    None
}

fn is_nil(s: &Spanned) -> bool {
    matches!(s.form, SpannedForm::Nil)
}

fn swallowed(form: &Spanned, top: usize, out: &mut Vec<Diagnostic>) {
    let SpannedForm::List(items) = &form.form else {
        return;
    };
    if items.first().and_then(Spanned::as_symbol) == Some("catch") && items.len() == 3 {
        let binder = items[1]
            .as_list()
            .and_then(|b| b.first())
            .and_then(Spanned::as_symbol);
        if let Some(b) = binder {
            if b != "_" && b != blue_lang_syntax::RESCUED && is_nil(&items[2]) {
                out.push(swallow_diagnostic(b, items[1].span, top));
            }
        }
    }
    if items.first().and_then(Spanned::as_symbol) == Some("else") && items.len() == 2 {
        if let Some([l, binds, body]) = items[1].as_list() {
            let bound = binds
                .as_list()
                .and_then(|b| b.first())
                .and_then(Spanned::as_list)
                .filter(|pair| {
                    pair.len() == 2 && pair[1].as_symbol() == Some(blue_lang_syntax::RESCUED)
                })
                .and_then(|pair| pair[0].as_symbol());
            if l.as_symbol() == Some("let") && is_nil(body) {
                if let Some(b) = bound.filter(|b| *b != "_") {
                    out.push(swallow_diagnostic(b, binds.span, top));
                }
            }
        }
    }
    for i in items {
        swallowed(i, top, out);
    }
}

fn swallow_diagnostic(binder: &str, span: Span, top: usize) -> Diagnostic {
    Diagnostic::new(
        Code::B0038,
        format!("`rescue {binder}` catches every error and does nothing with it"),
        span,
    )
    .at_top_level(top)
    .with_help("to discard every error on purpose, write `rescue _` and `nil` (or `x rescue nil`); otherwise handle or re-raise it")
}

fn is_constant(form: &Spanned) -> bool {
    let Some([head, name, _]) = form.as_list() else {
        return false;
    };
    head.as_symbol() == Some("define")
        && name.as_symbol().is_some_and(|n| {
            n.chars()
                .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
                && n.chars().any(|c| c.is_ascii_uppercase())
        })
}

fn snake(name: &str) -> bool {
    let bare = name.trim_end_matches(['?', '!']);
    !bare.chars().any(|c| c.is_ascii_uppercase())
}

fn names(form: &Spanned, top: usize, out: &mut Vec<Diagnostic>) {
    let SpannedForm::List(items) = &form.form else {
        return;
    };
    let head = items.first().and_then(Spanned::as_symbol);
    let mut check = |n: &Spanned| {
        if let Some(name) = n.as_symbol() {
            if blue_lang_syntax::qualified(name).is_none() && !snake(name) {
                out.push(
                    Diagnostic::new(
                        Code::B0040,
                        format!("`{name}` is not in lower snake_case"),
                        n.span,
                    )
                    .at_top_level(top)
                    .with_help(format!(
                        "rename it `{}` here and at every use",
                        snake_of(name)
                    )),
                );
            }
        }
    };
    match head {
        Some("define" | "define-typed") if items.len() >= 3 => match items[1].as_list() {
            Some(sig) => {
                for p in sig {
                    match p.as_list() {
                        Some(pair) if !pair.is_empty() => check(&pair[0]),
                        _ => check(p),
                    }
                }
            }
            None => check(&items[1]),
        },
        Some("lambda") if items.len() >= 3 => {
            for p in items[1].as_list().unwrap_or(&[]) {
                check(p);
            }
        }
        Some("defmacro") if items.len() >= 3 => {
            check(&items[1]);
            for p in items[2].as_list().unwrap_or(&[]) {
                check(p);
            }
        }
        _ => {}
    }
    for i in items {
        names(i, top, out);
    }
}

fn snake_of(name: &str) -> String {
    let mut out = String::new();
    for (k, c) in name.chars().enumerate() {
        if c.is_ascii_uppercase() {
            if k > 0 && !out.ends_with('_') {
                out.push('_');
            }
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}

#[derive(Clone, Copy)]
pub struct Guard<'a> {
    pub callee: &'a str,
    pub callee_span: Span,
}

#[must_use]
pub fn main_guard(form: &Spanned) -> Option<Guard<'_>> {
    let items = form.as_list()?;
    let [head, cond, body] = items else {
        return None;
    };
    if head.as_symbol() != Some("if") {
        return None;
    }
    let [eq, call, one] = cond.as_list()? else {
        return None;
    };
    let [getenv, var, default] = call.as_list()? else {
        return None;
    };
    let shape = eq.as_symbol() == Some("equal?")
        && getenv.as_symbol() == Some("getenv")
        && var.as_string().is_some_and(|v| v.ends_with("_MAIN"))
        && default.as_string() == Some("")
        && one.as_string() == Some("1");
    if !shape {
        return None;
    }
    let callee = match &body.form {
        SpannedForm::Atom(Atom::Symbol(s)) => (s.as_str(), body.span),
        SpannedForm::List(c) if c.len() == 1 => (c[0].as_symbol()?, c[0].span),
        _ => return None,
    };
    Some(Guard {
        callee: callee.0,
        callee_span: callee.1,
    })
}

fn defines(form: &Spanned, name: &str, zero: bool) -> bool {
    let Some(items) = form.as_list() else {
        return false;
    };
    matches!(
        items.first().and_then(Spanned::as_symbol),
        Some("define" | "define-typed")
    ) && items.get(1).and_then(Spanned::as_list).is_some_and(|sig| {
        sig.first().and_then(Spanned::as_symbol) == Some(name) && (!zero || sig.len() == 1)
    })
}

fn mentions(form: &Spanned, name: &str) -> usize {
    match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => usize::from(s == name),
        SpannedForm::List(items) => items.iter().map(|i| mentions(i, name)).sum(),
        SpannedForm::Quote(i)
        | SpannedForm::Quasiquote(i)
        | SpannedForm::Unquote(i)
        | SpannedForm::UnquoteSplice(i) => mentions(i, name),
        _ => 0,
    }
}

fn guard_fix(forms: &[&Spanned], guard: Guard<'_>) -> Result<(), String> {
    if forms.iter().any(|f| defines(f, "main", false)) && guard.callee != "main" {
        return Err("the file already defines a `main`".to_string());
    }
    if !forms.iter().any(|f| defines(f, guard.callee, true)) {
        return Err(format!(
            "`{}` is not a zero-parameter definition of this file",
            guard.callee
        ));
    }
    let uses: usize = forms.iter().map(|f| mentions(f, guard.callee)).sum();
    if uses != 2 {
        return Err(format!(
            "`{}` is also called elsewhere in the file",
            guard.callee
        ));
    }
    Ok(())
}

#[must_use]
pub fn without_main_guard(forms: &[Spanned]) -> Option<Vec<Spanned>> {
    let refs: Vec<&Spanned> = forms.iter().collect();
    let (at, guard) = forms
        .iter()
        .enumerate()
        .find_map(|(i, f)| main_guard(f).map(|g| (i, g)))?;
    guard_fix(&refs, guard).ok()?;
    let callee = guard.callee.to_string();
    Some(
        forms
            .iter()
            .enumerate()
            .filter(|(i, _)| *i != at)
            .map(|(_, f)| rename(f, &callee, "main"))
            .collect(),
    )
}

fn rename(form: &Spanned, from: &str, to: &str) -> Spanned {
    let inner = match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) if s == from => {
            SpannedForm::Atom(Atom::Symbol(to.to_string()))
        }
        SpannedForm::List(items) => {
            SpannedForm::List(items.iter().map(|i| rename(i, from, to)).collect())
        }
        other => other.clone(),
    };
    Spanned::new(form.span, inner)
}
