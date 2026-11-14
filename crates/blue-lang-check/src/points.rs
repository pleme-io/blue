//! Integration points: where a program meets the world, and the test of the
//! point's kind each one owes (docs/TESTING.md section 5; obligations
//! `point/effect` and `point/seam`).
//!
//! A definition of the entry file that names a host builtin outside the
//! ambient set is an effect point (B0083). A definition that calls an
//! imported word whose reach names one is a seam point (B0084). Each is
//! discharged by a test of the same file, declared `kind: :integration` or
//! `kind: :e2e`, whose reach includes it: a test that calls a caller of the
//! point reaches it too. Reach is read from the resolved references, so a
//! local that shadows a builtin is not a point, and a qualified call is.

use std::collections::{BTreeMap, BTreeSet};

use tatara_lisp::Spanned;

use crate::names::{key, Namespace, Reference, Target};
use crate::{Code, Diagnostic};

/// What the point detector reads of a checked program.
pub struct Program<'a> {
    pub forms: &'a [Spanned],
    pub references: &'a [Reference],
    pub is_entry: &'a dyn Fn(usize) -> bool,
    pub namespace_of: &'a dyn Fn(usize) -> Namespace,
    /// The host capability a builtin needs when naming it makes a point:
    /// `Some("network")` for `http_request`, `None` for a pure or ambient one.
    pub point_capability: &'a dyn Fn(&str) -> Option<&'static str>,
}

/// The kinds a test may declare that discharge an integration point.
pub const INTEGRATION_KINDS: &[&str] = &["integration", "e2e"];

/// B0083 and B0084 over the entry file's definitions.
#[must_use]
pub fn check(p: &Program<'_>) -> Vec<Diagnostic> {
    let mut defs: BTreeMap<String, usize> = BTreeMap::new();
    for (i, form) in p.forms.iter().enumerate() {
        if let Some(name) = blue_lang_syntax::doc::defined_name(form) {
            defs.insert(key(&(p.namespace_of)(i), name), i);
        }
    }
    let mut direct: BTreeMap<usize, BTreeSet<(&'static str, String)>> = BTreeMap::new();
    let mut calls: BTreeMap<usize, BTreeSet<usize>> = BTreeMap::new();
    for r in p.references {
        match &r.ns {
            Target::Builtin(name) => {
                if let Some(cap) = (p.point_capability)(name) {
                    direct
                        .entry(r.top_level)
                        .or_default()
                        .insert((cap, name.clone()));
                }
            }
            Target::Def(ns, name) => {
                if let Some(&j) = defs.get(&key(ns, name)) {
                    if j != r.top_level {
                        calls.entry(r.top_level).or_default().insert(j);
                    }
                }
            }
            _ => {}
        }
    }
    let reach = |from: usize| -> BTreeSet<usize> {
        let mut seen = BTreeSet::from([from]);
        let mut todo = vec![from];
        while let Some(i) = todo.pop() {
            for &j in calls.get(&i).into_iter().flatten() {
                if seen.insert(j) {
                    todo.push(j);
                }
            }
        }
        seen
    };
    let mut covered = BTreeSet::new();
    for (i, form) in p.forms.iter().enumerate() {
        if (p.is_entry)(i) && integration_test(form) {
            covered.extend(reach(i));
        }
    }
    let mut out = Vec::new();
    for (i, form) in p.forms.iter().enumerate() {
        if !(p.is_entry)(i) || covered.contains(&i) {
            continue;
        }
        let Some(name) = blue_lang_syntax::doc::defined_name(form) else {
            continue;
        };
        let at = name_span(form).unwrap_or(form.span);
        if let Some(effects) = direct.get(&i) {
            let caps: BTreeSet<&str> = effects.iter().map(|(c, _)| *c).collect();
            let named: Vec<String> = caps
                .iter()
                .map(|cap| {
                    let words: Vec<String> = effects
                        .iter()
                        .filter(|(c, _)| c == cap)
                        .map(|(_, w)| format!("`{w}`"))
                        .collect();
                    format!("{cap} ({})", words.join(", "))
                })
                .collect();
            out.push(
                Diagnostic::new(
                    Code::B0083,
                    format!(
                        "`{name}` reaches the host through {}, and no test of this file declared `kind: :integration` reaches it",
                        named.join(", ")
                    ),
                    at,
                )
                .at_top_level(i)
                .with_help(help(Code::B0083, name, &caps)),
            );
            continue;
        }
        let mut seams: Vec<(String, BTreeSet<&'static str>)> = Vec::new();
        for &j in calls.get(&i).into_iter().flatten() {
            if (p.is_entry)(j) {
                continue;
            }
            let caps: BTreeSet<&'static str> = reach(j)
                .iter()
                .flat_map(|k| direct.get(k).into_iter().flatten().map(|(c, _)| *c))
                .collect();
            if caps.is_empty() {
                continue;
            }
            let word = blue_lang_syntax::doc::defined_name(&p.forms[j]).unwrap_or("?");
            let shown = match (p.namespace_of)(j) {
                Namespace::Bidama(pkg) => format!("{pkg}::{word}"),
                _ => word.to_string(),
            };
            seams.push((shown, caps));
        }
        if seams.is_empty() {
            continue;
        }
        let caps: BTreeSet<&str> = seams.iter().flat_map(|(_, c)| c.iter().copied()).collect();
        let named: Vec<String> = seams
            .iter()
            .map(|(w, c)| {
                format!(
                    "`{w}` ({})",
                    c.iter().copied().collect::<Vec<_>>().join(", ")
                )
            })
            .collect();
        out.push(
            Diagnostic::new(
                Code::B0084,
                format!(
                    "`{name}` calls {}, which reach{} the host, and no test of this file declared `kind: :integration` reaches it",
                    named.join(", "),
                    if seams.len() == 1 { "es" } else { "" }
                ),
                at,
            )
            .at_top_level(i)
            .with_help(help(Code::B0084, name, &caps)),
        );
    }
    out
}

fn help(code: Code, name: &str, caps: &BTreeSet<&str>) -> String {
    let allow: Vec<String> = caps
        .iter()
        .map(|c| format!(":{}", c.replace('-', "_")))
        .collect();
    format!(
        "write `test \"…\", {{kind: :integration, allow: [{}]}}` in this file and reach `{name}` from it, with a declared fake or fixture for the outside side; or `# waive {code}: reason` above `{name}`",
        allow.join(", ")
    )
}

fn integration_test(form: &Spanned) -> bool {
    blue_lang_syntax::test_parts(form)
        .and_then(|p| p.meta)
        .and_then(blue_lang_syntax::test_meta)
        .and_then(|m| m.kind)
        .is_some_and(|(k, _)| INTEGRATION_KINDS.contains(&k))
}

fn name_span(form: &Spanned) -> Option<tatara_lisp::Span> {
    let items = form.as_list()?;
    blue_lang_syntax::scope::defined_name_node(items).map(|n| n.span)
}

/// A point the entry file declares for its project: the Bluefile row that
/// names it, the kind of test it owes and the code that refuses it.
pub struct ProjectPoint {
    pub what: String,
    pub kind: &'static str,
    pub code: Code,
}

/// B0085, B0086 and B0087: each project point of the entry file that no test
/// of the file declared with its kind. The finding sits on the file's first
/// form, so `# waive CODE: reason` above it holds the file's debt.
#[must_use]
pub fn project_points(
    forms: &[Spanned],
    is_entry: &dyn Fn(usize) -> bool,
    points: &[ProjectPoint],
) -> Vec<Diagnostic> {
    let kinds: BTreeSet<&str> = forms
        .iter()
        .enumerate()
        .filter(|(i, _)| is_entry(*i))
        .filter_map(|(_, f)| {
            blue_lang_syntax::test_parts(f)
                .and_then(|p| p.meta)
                .and_then(blue_lang_syntax::test_meta)
                .and_then(|m| m.kind.map(|(k, _)| k))
        })
        .collect();
    let Some((first, form)) = forms
        .iter()
        .enumerate()
        .find(|(i, f)| is_entry(*i) && !blue_lang_syntax::doc::is_doctest(f))
    else {
        return Vec::new();
    };
    points
        .iter()
        .filter(|p| !kinds.contains(p.kind))
        .map(|p| {
            Diagnostic::new(
                p.code,
                format!(
                    "this file is {} and holds no test declared `kind: :{}`",
                    p.what, p.kind
                ),
                form.span,
            )
            .at_top_level(first)
            .with_help(format!(
                "write `test \"…\", {{kind: :{}}}` in this file that feeds what it declares to its consumer; or `# waive {}: reason` above the file's first form",
                p.kind, p.code
            ))
        })
        .collect()
}

/// B0092 for each `check` row whose program is the entry file and which
/// declares no `stage:`. The finding sits on the file's first form, so `#
/// waive B0092: reason` above it holds the file's debt.
#[must_use]
pub fn unstaged_gates(
    forms: &[Spanned],
    is_entry: &dyn Fn(usize) -> bool,
    gates: &[String],
) -> Vec<Diagnostic> {
    let Some((first, form)) = forms
        .iter()
        .enumerate()
        .find(|(i, f)| is_entry(*i) && !blue_lang_syntax::doc::is_doctest(f))
    else {
        return Vec::new();
    };
    gates
        .iter()
        .map(|n| {
            Diagnostic::new(
                Code::B0092,
                format!(
                    "this file is the program of check(\"{n}\", …), whose row declares no `stage:`"
                ),
                form.span,
            )
            .at_top_level(first)
            .with_help(format!(
                "give the row its earliest gate: `check(\"{n}\", file, inputs, {{stage: :push}})` (or `:ci`, `:release`), then `blue lock`; or `# waive B0092: reason` above the file's first form"
            ))
        })
        .collect()
}

fn call_graph(p: &Program<'_>) -> BTreeMap<usize, BTreeSet<usize>> {
    let mut defs: BTreeMap<String, usize> = BTreeMap::new();
    for (i, form) in p.forms.iter().enumerate() {
        if let Some(name) = blue_lang_syntax::doc::defined_name(form) {
            defs.insert(key(&(p.namespace_of)(i), name), i);
        }
    }
    let mut calls: BTreeMap<usize, BTreeSet<usize>> = BTreeMap::new();
    for r in p.references {
        if let Target::Def(ns, name) = &r.ns {
            if let Some(&j) = defs.get(&key(ns, name)) {
                if j != r.top_level {
                    calls.entry(r.top_level).or_default().insert(j);
                }
            }
        }
    }
    calls
}

fn holds_assertion(form: &Spanned) -> bool {
    match form.as_list() {
        Some(items) => {
            items.first().and_then(Spanned::as_symbol).is_some_and(|h| {
                h == blue_lang_syntax::LOWERED_ASSERT
                    || h == blue_lang_syntax::LOWERED_ASSERT_PANICS
            }) || items.iter().any(holds_assertion)
        }
        None => false,
    }
}

fn tautology(form: &Spanned) -> bool {
    match form.as_list() {
        Some([head, _, e]) if head.as_symbol() == Some(blue_lang_syntax::LOWERED_ASSERT) => {
            if e.as_list().is_none() && e.as_symbol().is_none() {
                return true;
            }
            matches!(
                e.as_list(),
                Some([op, a, b])
                    if matches!(op.as_symbol(), Some("==" | "equal?" | "eq?"))
                        && a.as_list().is_none()
                        && a.to_sexp() == b.to_sexp()
            )
        }
        Some(items) => items.iter().any(tautology),
        None => false,
    }
}

/// B0088 for a test whose reach holds no assertion (an `assert`, an
/// `assert_panics` or a `tesuto::snapshot`), and B0089 for an assertion
/// that holds whatever the code does: `assert true`, `assert 1`, `assert x
/// == x`. The test cannot say no in either case (docs/COVERAGE.md S1, S2).
#[must_use]
pub fn strength(p: &Program<'_>) -> Vec<Diagnostic> {
    let calls = call_graph(p);
    let snapshots: BTreeSet<usize> = p
        .references
        .iter()
        .filter(|r| {
            matches!(&r.ns, Target::Def(Namespace::Bidama(b), n) if b == "tesuto" && n == "snapshot")
        })
        .map(|r| r.top_level)
        .collect();
    let asserting = |i: usize| snapshots.contains(&i) || holds_assertion(&p.forms[i]);
    let mut out = Vec::new();
    for (i, form) in p.forms.iter().enumerate() {
        if !(p.is_entry)(i) {
            continue;
        }
        let Some(parts) = blue_lang_syntax::test_parts(form) else {
            continue;
        };
        if blue_lang_syntax::doc::is_doctest(form) {
            continue;
        }
        if tautology(parts.body) {
            out.push(
                Diagnostic::new(
                    Code::B0089,
                    format!("test \"{}\" asserts something that holds whatever the code does", parts.name),
                    parts.name_span,
                )
                .at_top_level(i)
                .with_help("assert what the code under test answers, against a value it could fail to answer"),
            );
        }
        let mut seen = BTreeSet::from([i]);
        let mut todo = vec![i];
        let mut found = false;
        while let Some(k) = todo.pop() {
            if asserting(k) {
                found = true;
                break;
            }
            for &j in calls.get(&k).into_iter().flatten() {
                if seen.insert(j) {
                    todo.push(j);
                }
            }
        }
        if !found {
            out.push(
                Diagnostic::new(
                    Code::B0088,
                    format!("test \"{}\" asserts nothing, so it cannot fail on a wrong answer", parts.name),
                    parts.name_span,
                )
                .at_top_level(i)
                .with_help("assert what the code answers; a test that only runs code passes whatever it returns"),
            );
        }
    }
    out
}

fn local_values<'a>(form: &'a Spanned, out: &mut BTreeMap<String, Vec<&'a Spanned>>) {
    if let Some(items) = form.as_list() {
        if let [head, name, value] = items {
            if head.as_symbol() == Some("define") {
                if let Some(n) = name.as_symbol() {
                    out.entry(n.to_string()).or_default().push(value);
                }
            }
        }
        for i in items {
            local_values(i, out);
        }
    }
}

fn asserted<'a>(form: &'a Spanned, out: &mut Vec<&'a Spanned>) {
    if let Some(items) = form.as_list() {
        if let [head, _, e] = items {
            if head.as_symbol() == Some(blue_lang_syntax::LOWERED_ASSERT) {
                out.push(e);
                return;
            }
        }
        for i in items {
            asserted(i, out);
        }
    }
}

fn symbols_in(form: &Spanned, out: &mut BTreeSet<String>) {
    if let Some(s) = form.as_symbol() {
        out.insert(s.to_string());
    }
    if let Some(items) = form.as_list() {
        for i in items {
            symbols_in(i, out);
        }
    }
}

/// The builtins an assertion judges with, which reach no code under test:
/// comparison, logic, a field of a value, and the list and map a literal
/// lowers to.
const JUDGING: &[&str] = &[
    "equal?",
    "eq?",
    "==",
    "!=",
    "not",
    "and",
    "or",
    "<",
    ">",
    "<=",
    ">=",
    "blue-field",
    "list",
    "hash-map",
    "quote",
];

/// Whether the assertion `e` of test form `t` depends on code: a reference
/// inside it resolves to a definition or to a builtin it does not merely
/// judge with, or a local it reads was bound from an expression that does,
/// followed through the test's own bindings.
fn sliced(
    p: &Program<'_>,
    t: usize,
    e: &Spanned,
    locals: &BTreeMap<String, Vec<&Spanned>>,
    seen: &mut BTreeSet<String>,
) -> bool {
    let reaches_def = p.references.iter().any(|r| {
        r.top_level == t
            && r.span.start >= e.span.start
            && r.span.end <= e.span.end
            && match &r.ns {
                Target::Def(..) => true,
                Target::Builtin(n) => !JUDGING.contains(&n.as_str()),
                _ => false,
            }
    });
    if reaches_def {
        return true;
    }
    let mut names = BTreeSet::new();
    symbols_in(e, &mut names);
    names.into_iter().any(|n| {
        locals.get(&n).is_some_and(|values| {
            seen.insert(n.clone()) && values.iter().any(|v| sliced(p, t, v, locals, seen))
        })
    })
}

/// B0093 for an assertion of a test whose backward slice reaches no code:
/// it reads only literals, the builtins an assertion judges with and locals
/// bound from them, so it holds or fails whatever the code under test does
/// (docs/COVERAGE.md S3). The slice follows the test's own bindings; a call
/// of any definition or of any other builtin ends it.
#[must_use]
pub fn sliced_assertions(p: &Program<'_>) -> Vec<Diagnostic> {
    let mut out = Vec::new();
    for (i, form) in p.forms.iter().enumerate() {
        if !(p.is_entry)(i) || blue_lang_syntax::doc::is_doctest(form) {
            continue;
        }
        let Some(parts) = blue_lang_syntax::test_parts(form) else {
            continue;
        };
        let mut locals = BTreeMap::new();
        local_values(parts.body, &mut locals);
        let mut asserts = Vec::new();
        asserted(parts.body, &mut asserts);
        for e in asserts {
            if e.as_list().is_none() && e.as_symbol().is_none() {
                continue;
            }
            if !sliced(p, i, e, &locals, &mut BTreeSet::new()) {
                out.push(
                    Diagnostic::new(
                        Code::B0093,
                        format!(
                            "an assertion of test \"{}\" reads no code, only literals, so it holds or fails whatever the code does",
                            parts.name
                        ),
                        e.span,
                    )
                    .at_top_level(i)
                    .with_help("assert on what a definition answers: call the code under test inside the assertion or in the binding it reads"),
                );
            }
        }
    }
    out
}

fn test_forms(p: &Program<'_>) -> Vec<usize> {
    p.forms
        .iter()
        .enumerate()
        .filter(|(i, f)| {
            (p.is_entry)(*i)
                && blue_lang_syntax::test_parts(f).is_some()
                && !blue_lang_syntax::doc::is_doctest(f)
        })
        .map(|(i, _)| i)
        .collect()
}

fn calls_in<'a>(form: &'a Spanned, out: &mut Vec<&'a [Spanned]>) {
    if let Some(items) = form.as_list() {
        out.push(items);
        for i in items {
            calls_in(i, out);
        }
    }
}

fn optional_params(form: &Spanned) -> Option<(&str, usize, usize)> {
    let items = form.as_list()?;
    if items.first()?.as_symbol()? != "define" {
        return None;
    }
    let sig = items.get(1)?.as_list()?;
    let name = sig.first()?.as_symbol()?;
    let params: Vec<&str> = sig[1..].iter().filter_map(Spanned::as_symbol).collect();
    let at = params.iter().position(|p| *p == "&optional")?;
    let rest = params[at + 1..]
        .iter()
        .take_while(|p| !p.starts_with('&'))
        .count();
    (rest > 0).then_some((name, at, at + rest))
}

/// B0095 for a definition with optional parameters that the tests of its
/// file call, but never both with every optional argument given and with
/// one absent (docs/COVERAGE.md D2). A definition no test calls is B0090's.
#[must_use]
pub fn optional_shapes(p: &Program<'_>) -> Vec<Diagnostic> {
    let tests = test_forms(p);
    let mut out = Vec::new();
    for (i, form) in p.forms.iter().enumerate() {
        if !(p.is_entry)(i) {
            continue;
        }
        let Some((name, required, total)) = optional_params(form) else {
            continue;
        };
        let target = key(&(p.namespace_of)(i), name);
        let mut arities = BTreeSet::new();
        for &t in &tests {
            let mut lists = Vec::new();
            calls_in(&p.forms[t], &mut lists);
            for items in lists {
                let Some(head) = items.first() else { continue };
                let names_it = p.references.iter().any(|r| {
                    r.top_level == t
                        && r.span == head.span
                        && matches!(&r.ns, Target::Def(ns, n) if key(ns, n) == target)
                });
                if names_it {
                    arities.insert(items.len() - 1);
                }
            }
        }
        if arities.is_empty() {
            continue;
        }
        let given = arities.iter().any(|a| *a >= total);
        let absent = arities.iter().any(|a| *a >= required && *a < total);
        if !(given && absent) {
            let missing = if given { "absent" } else { "given" };
            out.push(
                Diagnostic::new(
                    Code::B0095,
                    format!("no test calls `{name}` with its optional argument {missing}"),
                    name_span(form).unwrap_or(form.span),
                )
                .at_top_level(i)
                .with_help(format!("call `{name}` in a test of this file with every optional argument given and with one left out")),
            );
        }
    }
    out
}

/// B0094 for an arm of a union the file declares that no test of the file
/// constructs (docs/COVERAGE.md D1, the constructed half).
#[must_use]
pub fn variants(p: &Program<'_>) -> Vec<Diagnostic> {
    let tests: BTreeSet<usize> = test_forms(p).into_iter().collect();
    let constructed: BTreeSet<String> = p
        .references
        .iter()
        .filter(|r| tests.contains(&r.top_level))
        .filter_map(|r| match &r.ns {
            Target::Def(ns, n) => Some(key(ns, n)),
            _ => None,
        })
        .collect();
    let mut records: BTreeMap<String, (usize, &Spanned)> = BTreeMap::new();
    for (i, form) in p.forms.iter().enumerate() {
        if let Some(r) = blue_lang_syntax::record::record_parts(form) {
            if let Some(pred) = r.predicate.as_symbol() {
                records.insert(pred.to_string(), (i, r.name));
            }
        }
    }
    let mut out = Vec::new();
    for (i, form) in p.forms.iter().enumerate() {
        if !(p.is_entry)(i) {
            continue;
        }
        let Some(u) = blue_lang_syntax::union::declared(form) else {
            continue;
        };
        let union = u.name.as_symbol().unwrap_or_default();
        for arm in u.arms {
            let Some(pred) = arm.as_symbol() else {
                continue;
            };
            let Some((ri, name)) = records.get(pred) else {
                continue;
            };
            let Some(n) = name.as_symbol() else { continue };
            if !constructed.contains(&key(&(p.namespace_of)(*ri), n)) {
                out.push(
                    Diagnostic::new(
                        Code::B0094,
                        format!("no test constructs `{n}`, an arm of union `{union}`"),
                        arm.span,
                    )
                    .at_top_level(i)
                    .with_help(format!("build a `{n}` in a test of this file and assert what the union's consumers answer for it")),
                );
            }
        }
    }
    out
}

const FLAGS: &[&str] = &["enable", "enabled"];

fn flag_reads(form: &Spanned) -> bool {
    match form.as_list() {
        Some(items) => {
            let read = matches!(
                items,
                [head, _, k] if matches!(head.as_symbol(), Some("blue-field" | "get" | "blue-index"))
                    && k.as_keyword().is_some_and(|k| FLAGS.contains(&k))
            );
            read || items.iter().any(flag_reads)
        }
        None => false,
    }
}

fn flag_values(form: &Spanned, out: &mut BTreeSet<String>) {
    if let Some(items) = form.as_list() {
        for pair in items.windows(2) {
            if pair[0].as_keyword().is_some_and(|k| FLAGS.contains(&k)) {
                out.insert(pair[1].to_sexp().to_string());
            }
        }
        for i in items {
            flag_values(i, out);
        }
    }
}

/// B0096 for a definition that reads an `enable` or `enabled` field when the
/// tests of its file never set the flag both on and off (docs/COVERAGE.md
/// C1): behaviour configured off must still work, and off must do nothing.
#[must_use]
pub fn flags(p: &Program<'_>) -> Vec<Diagnostic> {
    let mut seen = BTreeSet::new();
    for t in test_forms(p) {
        flag_values(&p.forms[t], &mut seen);
    }
    let both = seen.contains("#t") && seen.contains("#f");
    if both {
        return Vec::new();
    }
    p.forms
        .iter()
        .enumerate()
        .filter(|(i, f)| {
            (p.is_entry)(*i)
                && blue_lang_syntax::test_parts(f).is_none()
                && blue_lang_syntax::doc::defined_name(f).is_some()
                && flag_reads(f)
        })
        .map(|(i, f)| {
            Diagnostic::new(
                Code::B0096,
                "this definition reads an `enabled` flag that no test of its file sets both true and false".to_string(),
                name_span(f).unwrap_or(f.span),
            )
            .at_top_level(i)
            .with_help("test it with `enabled: true` and with `enabled: false`: off must still work and must do nothing")
        })
        .collect()
}

fn raised_tags(form: &Spanned, out: &mut BTreeSet<String>) {
    if let Some(items) = form.as_list() {
        if items.first().and_then(Spanned::as_symbol) == Some("raise") {
            if let Some(tag) = items.get(1).and_then(Spanned::as_keyword) {
                out.insert(tag.to_string());
            }
        }
        for i in items {
            raised_tags(i, out);
        }
    }
}

fn keywords_in(form: &Spanned, out: &mut BTreeSet<String>) {
    if let Some(k) = form.as_keyword() {
        out.insert(k.to_string());
    }
    if let Some(items) = form.as_list() {
        for i in items {
            keywords_in(i, out);
        }
    }
}

/// B0090 for a definition no test of its file names (a call, a reference or
/// `target:`), and B0091 for a tag a definition raises that no test of its
/// file names (docs/COVERAGE.md R2, E2). Both are ratcheted: the census
/// counts them until the corpus reaches zero.
#[must_use]
pub fn reach(p: &Program<'_>) -> Vec<Diagnostic> {
    let mut defs: BTreeMap<String, usize> = BTreeMap::new();
    for (i, form) in p.forms.iter().enumerate() {
        if let Some(name) = blue_lang_syntax::doc::defined_name(form) {
            defs.insert(key(&(p.namespace_of)(i), name), i);
        }
    }
    let tests: BTreeSet<usize> = p
        .forms
        .iter()
        .enumerate()
        .filter(|(i, f)| (p.is_entry)(*i) && blue_lang_syntax::test_parts(f).is_some())
        .map(|(i, _)| i)
        .collect();
    let mut named: BTreeSet<usize> = BTreeSet::new();
    for r in p.references {
        if let Target::Def(ns, name) = &r.ns {
            if tests.contains(&r.top_level) {
                if let Some(&j) = defs.get(&key(ns, name)) {
                    named.insert(j);
                }
            }
        }
    }
    let mut expected = BTreeSet::new();
    for &t in &tests {
        keywords_in(&p.forms[t], &mut expected);
    }
    let mut out = Vec::new();
    for (i, form) in p.forms.iter().enumerate() {
        if !(p.is_entry)(i) || tests.contains(&i) {
            continue;
        }
        let Some(name) = blue_lang_syntax::doc::defined_name(form) else {
            continue;
        };
        let at = name_span(form).unwrap_or(form.span);
        if !named.contains(&i) {
            out.push(
                Diagnostic::new(
                    Code::B0090,
                    format!("no test of this file names `{name}`; it is reached, if at all, only through a caller"),
                    at,
                )
                .at_top_level(i)
                .with_help(format!("write a test that calls `{name}`, or declares `target: {name}`")),
            );
        }
        let mut tags = BTreeSet::new();
        raised_tags(form, &mut tags);
        for tag in tags.difference(&expected) {
            out.push(
                Diagnostic::new(
                    Code::B0091,
                    format!("`{name}` raises `:{tag}` and no test of this file expects it"),
                    at,
                )
                .at_top_level(i)
                .with_help(format!(
                    "assert the refusal: `assert raises?(:{tag}, () -> …)`"
                )),
            );
        }
    }
    out
}
