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
