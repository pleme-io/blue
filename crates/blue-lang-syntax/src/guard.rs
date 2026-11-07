//! Guard-clause `return`, lowered to `if`/`else` before anything runs.
//!
//! The parser reads `return x` as `(return x)` wherever an expression starts.
//! In a function body, a `return` that ends a branch of an `if` or `case`
//! that is itself a statement is rewritten here: the rest of the body after
//! that `if` becomes the branches that did not return. The evaluator, the VM,
//! `def_hash` and every shape hash see only `if`/`else`, so a guard and the
//! nested `if` it stands for are one program. A `return` this pass cannot
//! place stays in the tree, and the check stage refuses it as B0080, naming
//! the form in the way. `docs/GUARD-RETURN.md`.

use tatara_lisp::{Span, Spanned, SpannedForm};

use crate::parse::{cover, list_at, sym_at, ParseError};

pub const RETURN: &str = "return";

/// Lower every guard `return` in `forms`. An error is code written after a
/// `return` in the same sequence, which can never run.
pub fn lower(forms: Vec<Spanned>) -> Result<Vec<Spanned>, ParseError> {
    forms.into_iter().map(walk).collect()
}

fn walk(form: Spanned) -> Result<Spanned, ParseError> {
    let span = form.span;
    let SpannedForm::List(items) = form.form else {
        return Ok(form);
    };
    let mut items = items.into_iter().map(walk).collect::<Result<Vec<_>, _>>()?;
    if is_function_definition(&items) {
        if let Some(body) = items.pop() {
            items.push(lower_body(body)?);
        }
    }
    Ok(list_at(span, items))
}

fn is_function_definition(items: &[Spanned]) -> bool {
    matches!(
        items.first().and_then(Spanned::as_symbol),
        Some("define" | "define-typed")
    ) && matches!(items.get(1).map(|s| &s.form), Some(SpannedForm::List(_)))
        && items.len() >= 3
}

fn lower_body(body: Spanned) -> Result<Spanned, ParseError> {
    if !holds_return(&body) {
        return Ok(body);
    }
    let at = body.span;
    lower_seq(statements(body), &[], at)
}

/// The value of a `return` node, `nil` when it gives none.
fn returned(form: &Spanned) -> Option<Spanned> {
    let SpannedForm::List(items) = &form.form else {
        return None;
    };
    if items.first().and_then(Spanned::as_symbol) != Some(RETURN) {
        return None;
    }
    Some(
        items
            .get(1)
            .cloned()
            .unwrap_or_else(|| Spanned::new(form.span, SpannedForm::Nil)),
    )
}

/// Does `form`, read as a statement, end some path with a guard `return`?
fn holds_return(form: &Spanned) -> bool {
    if returned(form).is_some() {
        return true;
    }
    let held = |forms: Vec<&Spanned>| forms.into_iter().any(holds_return);
    branches(form).is_some_and(|bs| bs.into_iter().any(|b| held(statements_of(b))))
        || statements_of(form).len() > 1 && held(statements_of(form))
}

/// The branch bodies of an `if` or a `case` statement.
fn branches(form: &Spanned) -> Option<Vec<&Spanned>> {
    let SpannedForm::List(items) = &form.form else {
        return None;
    };
    match items.first().and_then(Spanned::as_symbol) {
        Some("if") if (3..=4).contains(&items.len()) => Some(items[2..].iter().collect()),
        Some("let") => case_clauses(items).map(|cs| cs.iter().filter_map(|c| c.last()).collect()),
        _ => None,
    }
}

/// The `cond` clauses a `case` lowers to: `(let (bind) (cond (t body)… (else body)))`.
fn case_clauses(items: &[Spanned]) -> Option<Vec<&Vec<Spanned>>> {
    if items.len() != 3 {
        return None;
    }
    let SpannedForm::List(cond) = &items[2].form else {
        return None;
    };
    if cond.first().and_then(Spanned::as_symbol) != Some("cond") {
        return None;
    }
    cond[1..]
        .iter()
        .map(|c| match &c.form {
            SpannedForm::List(clause) if clause.len() == 2 => Some(clause),
            _ => None,
        })
        .collect()
}

fn statements_of(form: &Spanned) -> Vec<&Spanned> {
    match &form.form {
        SpannedForm::List(items) if items.first().and_then(Spanned::as_symbol) == Some("begin") => {
            items[1..].iter().collect()
        }
        SpannedForm::Nil => Vec::new(),
        _ => vec![form],
    }
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

/// One expression from a statement sequence, as the parser builds a body.
fn sequence(forms: Vec<Spanned>, at: Span) -> Spanned {
    match forms.len() {
        0 => Spanned::new(Span::new(at.start, at.start), SpannedForm::Nil),
        1 => forms.into_iter().next().expect("checked len"),
        _ => {
            let span = cover(&forms, at);
            let mut list = vec![sym_at(Span::new(span.start, span.start), "begin")];
            list.extend(forms);
            list_at(span, list)
        }
    }
}

/// `stmts` followed by `rest`, the statements that run after them when no
/// branch inside returned.
fn lower_seq(stmts: Vec<Spanned>, rest: &[Spanned], at: Span) -> Result<Spanned, ParseError> {
    let written = stmts.len();
    let mut all = stmts;
    all.extend(rest.iter().cloned());
    let mut before = Vec::new();
    let mut it = all.into_iter().enumerate();
    while let Some((i, s)) = it.next() {
        if let Some(value) = returned(&s) {
            if i + 1 < written {
                let next = it.next().expect("a written statement follows");
                return Err(ParseError::new(
                    "this code follows a `return` and never runs: delete it, or put the `return` in a branch",
                    next.1.span,
                ));
            }
            before.push(value);
            return Ok(sequence(before, at));
        }
        if holds_return(&s) {
            let after: Vec<Spanned> = it.map(|(_, s)| s).collect();
            before.push(lower_branching(s, &after)?);
            return Ok(sequence(before, at));
        }
        before.push(s);
    }
    Ok(sequence(before, at))
}

/// The surface a lowered tree was written as, for the formatter. Lowering
/// keeps every node's source span, so a guard `if` is the one whose branches
/// hold statements written after its own `end`: those are the rest of the
/// body, printed once after it, and a branch that holds none of them ended
/// in a `return`. A tree with no guard comes back unchanged. A `return` that
/// changes nothing (one ending the body's last statement) is not restored:
/// the canonical form writes the value.
#[must_use]
pub fn raise(src: &str, forms: Vec<Spanned>) -> Vec<Spanned> {
    forms.into_iter().map(|f| raise_form(src, f)).collect()
}

fn raise_form(src: &str, form: Spanned) -> Spanned {
    let span = form.span;
    let SpannedForm::List(items) = form.form else {
        return form;
    };
    let mut items: Vec<Spanned> = items.into_iter().map(|f| raise_form(src, f)).collect();
    let guarded = items
        .last()
        .is_some_and(|b| statements_of(b).into_iter().any(is_guard));
    if is_function_definition(&items) && guarded {
        if let Some(body) = items.pop() {
            let at = body.span;
            let stmts = statements(body);
            items.push(sequence(raise_seq(src, stmts, span.end), at));
        }
    }
    list_at(span, items)
}

fn is_guard(form: &Spanned) -> bool {
    branches(form).is_some_and(|bs| bs.into_iter().any(|b| reaches_beyond(b, form.span.end)))
}

fn reaches_beyond(form: &Spanned, end: usize) -> bool {
    statements_of(form).into_iter().any(|s| {
        s.span.start >= end
            || branches(s).is_some_and(|bs| bs.into_iter().any(|b| reaches_beyond(b, end)))
    })
}

/// The statements written after `end`, wherever the lowering put them.
fn continuation(form: &Spanned, end: usize) -> Option<Vec<Spanned>> {
    let stmts = statements_of(form);
    if let Some(i) = stmts.iter().position(|s| s.span.start >= end) {
        return Some(stmts[i..].iter().map(|s| (*s).clone()).collect());
    }
    stmts
        .into_iter()
        .find_map(|s| branches(s).and_then(|bs| bs.into_iter().find_map(|b| continuation(b, end))))
}

fn raise_seq(src: &str, stmts: Vec<Spanned>, limit: usize) -> Vec<Spanned> {
    let mut out = Vec::new();
    for s in stmts {
        if s.span.start >= limit {
            break;
        }
        if !is_guard(&s) {
            out.push(s);
            continue;
        }
        let end = s.span.end;
        let after = continuation(&s, end).unwrap_or_default();
        out.push(raise_guard(src, s, end));
        out.extend(raise_seq(src, after, limit));
        break;
    }
    out
}

fn raise_branch(src: &str, branch: Spanned, end: usize) -> Option<Spanned> {
    let at = branch.span;
    let returned = !reaches_beyond(&branch, end);
    let mut own = raise_seq(src, statements(branch), end);
    if !returned {
        return (!own.is_empty()).then(|| sequence(own, at));
    }
    let last = own.pop();
    let ret = |value: Option<Spanned>| {
        let bare = value
            .as_ref()
            .filter(|v| matches!(v.form, SpannedForm::Nil))
            .map(|v| v.span);
        let value = value.filter(|v| !matches!(v.form, SpannedForm::Nil));
        let span = match (&value, bare) {
            (Some(v), _) => Span::new(keyword_before(src, v.span.start), v.span.end),
            (None, Some(b)) => b,
            (None, None) => Span::new(at.start, at.start),
        };
        let mut node = vec![sym_at(Span::new(span.start, span.start), RETURN)];
        node.extend(value);
        list_at(span, node)
    };
    match last {
        Some(l) if branches(&l).is_some() => own.push(l),
        other => own.push(ret(other)),
    }
    Some(sequence(own, at))
}

/// Where the `return` keyword written before `at` starts, or `at` when the
/// source holds none there (the value was a branch's last statement).
fn keyword_before(src: &str, at: usize) -> usize {
    let head = src.get(..at).unwrap_or_default().trim_end();
    match head.strip_suffix(RETURN) {
        Some(rest) if !rest.ends_with(|c: char| c.is_alphanumeric() || c == '_') => rest.len(),
        _ => at,
    }
}

fn raise_guard(src: &str, form: Spanned, end: usize) -> Spanned {
    let span = form.span;
    let SpannedForm::List(mut items) = form.form else {
        return form;
    };
    match items.first().and_then(Spanned::as_symbol) {
        Some("if") => {
            let els = (items.len() == 4).then(|| items.pop().expect("checked len"));
            let then = items.pop().expect("an if has a then");
            let then_at = then.span;
            items.push(raise_branch(src, then, end).unwrap_or_else(|| {
                Spanned::new(Span::new(then_at.start, then_at.start), SpannedForm::Nil)
            }));
            if let Some(e) = els.and_then(|e| raise_branch(src, e, end)) {
                items.push(e);
            }
            list_at(span, items)
        }
        Some("let") => {
            let cond = items.pop().expect("a case is (let bind cond)");
            let cond_at = cond.span;
            let SpannedForm::List(clauses) = cond.form else {
                return list_at(span, items);
            };
            let mut out = Vec::with_capacity(clauses.len());
            for (k, clause) in clauses.into_iter().enumerate() {
                let clause_at = clause.span;
                let SpannedForm::List(mut parts) = clause.form else {
                    out.push(clause);
                    continue;
                };
                if k > 0 {
                    let body = parts.pop().expect("a clause is (test body)");
                    let body_at = body.span;
                    parts.push(raise_branch(src, body, end).unwrap_or_else(|| {
                        Spanned::new(Span::new(body_at.start, body_at.start), SpannedForm::Nil)
                    }));
                }
                out.push(list_at(clause_at, parts));
            }
            items.push(list_at(cond_at, out));
            list_at(span, items)
        }
        _ => list_at(span, items),
    }
}

fn lower_branching(form: Spanned, after: &[Spanned]) -> Result<Spanned, ParseError> {
    let span = form.span;
    let SpannedForm::List(mut items) = form.form else {
        unreachable!("only a list holds a return");
    };
    match items.first().and_then(Spanned::as_symbol) {
        Some("if") => {
            let then = items.remove(2);
            let then_at = then.span;
            items.insert(2, lower_seq(statements(then), after, then_at)?);
            if items.len() == 4 {
                let els = items.pop().expect("checked len");
                let els_at = els.span;
                items.push(lower_seq(statements(els), after, els_at)?);
            } else if !after.is_empty() {
                items.push(lower_seq(Vec::new(), after, span)?);
            }
            Ok(list_at(span, items))
        }
        Some("let") => {
            let cond = items.pop().expect("a case is (let bind cond)");
            let cond_at = cond.span;
            let SpannedForm::List(clauses) = cond.form else {
                unreachable!("case_clauses checked the shape");
            };
            let mut out = Vec::with_capacity(clauses.len());
            for (k, clause) in clauses.into_iter().enumerate() {
                if k == 0 {
                    out.push(clause);
                    continue;
                }
                let clause_at = clause.span;
                let SpannedForm::List(mut parts) = clause.form else {
                    unreachable!("case_clauses checked the shape");
                };
                let body = parts.pop().expect("a clause is (test body)");
                let body_at = body.span;
                parts.push(lower_seq(statements(body), after, body_at)?);
                out.push(list_at(clause_at, parts));
            }
            items.push(list_at(cond_at, out));
            Ok(list_at(span, items))
        }
        _ => {
            let at = span;
            lower_seq(
                statements(Spanned::new(span, SpannedForm::List(items))),
                after,
                at,
            )
        }
    }
}
