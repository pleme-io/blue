use tatara_lisp::{Span, Spanned, SpannedForm};

use crate::parse::{list_at, sym_at, ParseError};

pub const LOWERED_TRY: &str = "blue-try";

pub const TRY_SUBJECT: &str = "try-subject";

pub const TRY_REFUSED: &str = "blue-try-refused?";

pub const TRY_VALUE: &str = "blue-try-value";

const RETURN: &str = crate::guard::RETURN;

fn head_of(form: &Spanned) -> Option<&str> {
    form.as_list()?.first()?.as_symbol()
}

fn tried(form: &Spanned) -> Option<&Spanned> {
    match form.as_list()? {
        [h, e] if h.as_symbol() == Some(LOWERED_TRY) => Some(e),
        _ => None,
    }
}

fn call(at: Span, head: &str, args: Vec<Spanned>) -> Spanned {
    let mut items = vec![sym_at(at, head)];
    items.extend(args);
    list_at(at, items)
}

fn statements(form: Spanned) -> Vec<Spanned> {
    match form.form {
        SpannedForm::List(items) if items.first().and_then(Spanned::as_symbol) == Some("begin") => {
            items.into_iter().skip(1).collect()
        }
        SpannedForm::Nil => Vec::new(),
        other => vec![Spanned::new(form.span, other)],
    }
}

fn sequence(forms: Vec<Spanned>, at: Span) -> Spanned {
    match forms.len() {
        0 => Spanned::new(Span::new(at.start, at.start), SpannedForm::Nil),
        1 => forms.into_iter().next().expect("checked len"),
        _ => {
            let mut list = vec![sym_at(Span::new(at.start, at.start), "begin")];
            list.extend(forms);
            list_at(at, list)
        }
    }
}

fn guard(at: Span, value: &Spanned) -> [Spanned; 2] {
    let subject = sym_at(at, TRY_SUBJECT);
    [
        call(at, "define", vec![subject.clone(), value.clone()]),
        call(
            at,
            "if",
            vec![
                call(at, TRY_REFUSED, vec![subject.clone()]),
                call(at, RETURN, vec![subject]),
            ],
        ),
    ]
}

fn lower_stmts(stmts: Vec<Spanned>) -> Vec<Spanned> {
    let last = stmts.len();
    let mut out = Vec::with_capacity(stmts.len());
    for (k, s) in stmts.into_iter().enumerate() {
        let at = s.span;
        if let Some(e) = tried(&s) {
            out.extend(guard(at, e));
            if k + 1 == last {
                out.push(call(at, TRY_VALUE, vec![sym_at(at, TRY_SUBJECT)]));
            }
            continue;
        }
        if let Some([d, name, value]) = s.as_list() {
            if binds(d, name) {
                if let Some(e) = tried(value) {
                    out.extend(guard(at, e));
                    out.push(call(
                        at,
                        d.as_symbol().unwrap_or("define"),
                        vec![
                            name.clone(),
                            call(value.span, TRY_VALUE, vec![sym_at(value.span, TRY_SUBJECT)]),
                        ],
                    ));
                    continue;
                }
            }
        }
        out.push(lower_branches(s));
    }
    out
}

fn lower_branch(body: Spanned) -> Spanned {
    let at = body.span;
    sequence(lower_stmts(statements(body)), at)
}

fn lower_branches(form: Spanned) -> Spanned {
    let span = form.span;
    let SpannedForm::List(mut items) = form.form else {
        return form;
    };
    match items.first().and_then(Spanned::as_symbol) {
        Some("if") if (3..=4).contains(&items.len()) => {
            let tail: Vec<Spanned> = items.split_off(2).into_iter().map(lower_branch).collect();
            items.extend(tail);
            list_at(span, items)
        }
        Some("let") if items.len() == 3 && head_of(&items[2]) == Some("cond") => {
            let cond = items.pop().expect("checked len");
            let cond_at = cond.span;
            let SpannedForm::List(clauses) = cond.form else {
                unreachable!("checked head");
            };
            let clauses = clauses
                .into_iter()
                .enumerate()
                .map(|(k, c)| {
                    let c_at = c.span;
                    match c.form {
                        SpannedForm::List(mut parts) if k > 0 && parts.len() == 2 => {
                            let body = parts.pop().expect("checked len");
                            parts.push(lower_branch(body));
                            list_at(c_at, parts)
                        }
                        other => Spanned::new(c_at, other),
                    }
                })
                .collect();
            items.push(list_at(cond_at, clauses));
            list_at(span, items)
        }
        _ => list_at(span, items),
    }
}

fn is_function_definition(items: &[Spanned]) -> bool {
    matches!(
        items.first().and_then(Spanned::as_symbol),
        Some("define" | "define-typed")
    ) && matches!(items.get(1).map(|s| &s.form), Some(SpannedForm::List(_)))
        && items.len() >= 3
}

fn walk(form: Spanned) -> Spanned {
    let span = form.span;
    let SpannedForm::List(items) = form.form else {
        return form;
    };
    let mut items: Vec<Spanned> = items.into_iter().map(walk).collect();
    if is_function_definition(&items) {
        if let Some(body) = items.pop() {
            items.push(lower_branch(body));
        }
    }
    list_at(span, items)
}

fn stray(form: &Spanned) -> Option<Span> {
    if tried(form).is_some() {
        return Some(form.span);
    }
    form.as_list()?.iter().find_map(stray)
}

pub fn lower(forms: Vec<Spanned>) -> Result<Vec<Spanned>, ParseError> {
    let out: Vec<Spanned> = forms.into_iter().map(walk).collect();
    if let Some(at) = out.iter().find_map(stray) {
        return Err(ParseError::new(
            "`?` returns a refusal from the function it is in, so it ends a statement of a \
             `def` body: `x = f(y)?` or `f(y)?`, never inside an argument, a lambda or the top level",
            at,
        ));
    }
    Ok(out)
}

fn defines_subject(form: &Spanned) -> Option<&Spanned> {
    match form.as_list()? {
        [d, n, v] if d.as_symbol() == Some("define") && n.as_symbol() == Some(TRY_SUBJECT) => {
            Some(v)
        }
        _ => None,
    }
}

fn returns_refusal(form: &Spanned) -> Option<Option<&Spanned>> {
    let items = form.as_list()?;
    if items.first()?.as_symbol()? != "if" || !(3..=4).contains(&items.len()) {
        return None;
    }
    let test = items[1].as_list()?;
    let is_test = matches!(test, [h, s] if h.as_symbol() == Some(TRY_REFUSED) && s.as_symbol() == Some(TRY_SUBJECT));
    let gives_subject = items[2].as_symbol() == Some(TRY_SUBJECT)
        || matches!(items[2].as_list(), Some([r, s]) if r.as_symbol() == Some(RETURN) && s.as_symbol() == Some(TRY_SUBJECT));
    (is_test && gives_subject).then(|| items.get(3))
}

fn binds(head: &Spanned, target: &Spanned) -> bool {
    match head.as_symbol() {
        Some("define") => target.as_symbol().is_some(),
        Some(crate::pattern::LOWERED_BIND) => true,
        _ => false,
    }
}

fn value_of_subject(form: &Spanned) -> bool {
    matches!(form.as_list(), Some([h, s]) if h.as_symbol() == Some(TRY_VALUE) && s.as_symbol() == Some(TRY_SUBJECT))
}

fn raise_stmts(stmts: Vec<Spanned>) -> Vec<Spanned> {
    let mut out: Vec<Spanned> = Vec::with_capacity(stmts.len());
    let mut queue: std::collections::VecDeque<Spanned> = stmts.into();
    while let Some(s) = queue.pop_front() {
        let Some(e) = defines_subject(&s).cloned() else {
            out.push(s);
            continue;
        };
        let Some(next) = queue.front() else {
            out.push(s);
            continue;
        };
        let Some(rest) = returns_refusal(next).map(|r| r.cloned()) else {
            out.push(s);
            continue;
        };
        queue.pop_front();
        let at = s.span;
        let marked = call(at, LOWERED_TRY, vec![e]);
        let mut after = rest.map(statements).unwrap_or_default();
        while let Some(f) = queue.pop_front() {
            after.push(f);
        }
        match after.first().and_then(Spanned::as_list) {
            Some([d, n, v]) if binds(d, n) && value_of_subject(v) => {
                let first = call(
                    at,
                    d.as_symbol().unwrap_or("define"),
                    vec![n.clone(), marked],
                );
                after[0] = first;
            }
            _ if after.len() == 1 && value_of_subject(&after[0]) => {
                after[0] = marked;
            }
            _ => after.insert(0, marked),
        }
        queue = after.into();
    }
    out
}

fn raise_walk(form: Spanned) -> Spanned {
    let span = form.span;
    let SpannedForm::List(items) = form.form else {
        return form;
    };
    let mut items: Vec<Spanned> = items.into_iter().map(raise_walk).collect();
    if items.first().and_then(Spanned::as_symbol) == Some("begin") {
        let raised = raise_stmts(items.split_off(1));
        if raised.len() == 1 {
            return raised.into_iter().next().expect("checked len");
        }
        items.extend(raised);
    }
    list_at(span, items)
}

#[must_use]
pub fn raise(forms: Vec<Spanned>) -> Vec<Spanned> {
    if !forms.iter().any(mentions_subject) {
        return forms;
    }
    forms.into_iter().map(raise_walk).collect()
}

fn mentions_subject(form: &Spanned) -> bool {
    match &form.form {
        SpannedForm::Atom(tatara_lisp::Atom::Symbol(s)) => s == TRY_SUBJECT,
        SpannedForm::List(items) => items.iter().any(mentions_subject),
        _ => false,
    }
}

fn widen_form(form: Spanned) -> (Spanned, bool) {
    let span = form.span;
    let SpannedForm::List(items) = form.form else {
        return (form, false);
    };
    let mut reach = span;
    let mut widened = false;
    let items: Vec<Spanned> = items
        .into_iter()
        .map(|i| {
            let (i, w) = widen_form(i);
            if w {
                reach = reach.merge(i.span);
                widened = true;
            }
            i
        })
        .collect();
    let node = list_at(reach, items);
    if let Some(Some(rest)) = returns_refusal(&node) {
        let to = node.span.merge(rest.span);
        return (Spanned::new(to, node.form), true);
    }
    (node, widened && reach != span)
}

#[must_use]
pub fn widen(forms: Vec<Spanned>) -> Vec<Spanned> {
    if !forms.iter().any(mentions_subject) {
        return forms;
    }
    forms.into_iter().map(|f| widen_form(f).0).collect()
}
