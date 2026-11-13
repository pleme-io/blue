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

fn literal_environment_reads<'a>(form: &'a Spanned, out: &mut Vec<(&'a str, &'a Spanned)>) {
    if let Some(items) = form.as_list() {
        if let Some(word @ ("getenv" | "env_required")) = items.first().and_then(Spanned::as_symbol)
        {
            if items.get(1).and_then(Spanned::as_string).is_some() {
                out.push((word, &items[1]));
            }
        }
        for i in items {
            literal_environment_reads(i, out);
        }
    }
}

#[must_use]
pub fn environment(p: &Program<'_>, package: &str) -> Vec<Diagnostic> {
    if package == "settei" {
        return Vec::new();
    }
    let mut out = Vec::new();
    for (i, form) in p.forms.iter().enumerate() {
        if !(p.is_entry)(i) || blue_lang_syntax::test_parts(form).is_some() {
            continue;
        }
        let Some(def) = blue_lang_syntax::doc::defined_name(form) else {
            continue;
        };
        let mut reads = Vec::new();
        literal_environment_reads(form, &mut reads);
        for (word, at) in reads {
            let name = at.as_string().unwrap_or_default();
            out.push(
                Diagnostic::new(
                    Code::B0092,
                    format!("`{def}` reads `{name}` with `{word}`, outside a settei core model"),
                    at.span,
                )
                .at_top_level(i)
                .with_help(format!(
                    "declare it as a knob of the program's model and read it through settei; its environment name stays `{name}`"
                )),
            );
        }
    }
    out
}

#[must_use]
pub fn undeclared_access(
    forms: &[Spanned],
    is_entry: &dyn Fn(usize) -> bool,
    services: &[String],
) -> Vec<Diagnostic> {
    let Some((first, form)) = forms
        .iter()
        .enumerate()
        .find(|(i, f)| is_entry(*i) && !blue_lang_syntax::doc::is_doctest(f))
    else {
        return Vec::new();
    };
    services
        .iter()
        .map(|n| {
            Diagnostic::new(
                Code::B0093,
                format!(
                    "this file is the program of service(\"{n}\", …), whose row declares no `access`, so it runs with the default network, clock, entropy and environment"
                ),
                form.span,
            )
            .at_top_level(first)
            .with_help(format!(
                "declare `access: {{effects: [...], egress: [...], listen: [...]}}` on service(\"{n}\", …) in the Bluefile; or `# waive B0093: reason` above the file's first form"
            ))
        })
        .collect()
}
