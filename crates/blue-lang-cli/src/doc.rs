//! `blue doc`: the blue program `blue/doc.b`, compiled into this binary, and
//! the two things it asks of the binary that are not blue's to read.
//!
//! The program's own imports (mokuroku, which reads every bidama's
//! definitions for the catalogue) resolve through `BLUE_PATH`, then the
//! standard distribution compiled into blue, so the tool works with no
//! `BLUE_PATH`; what it documents is the distribution `BLUE_PATH` names.
//!
//! `blue doc --rows` prints the conformance rows compiled in by `build.rs`
//! (`spec/rows/*.b`) as one JSON array of
//! `{id, src, expect, covers, marks, waits_on}`: a builtin's example is the
//! row that specifies it, `marks` holds each `pending` and `flaky` mark as
//! `{mark, gap, on}`, `on` null when the mark holds on every evaluator, and
//! `waits_on` is the first mark that holds on the walker, the reference
//! evaluator: null when main holds what the row states, else the row states a
//! destination its gap has not reached. Rows are parsed, never evaluated,
//! exactly as the conformance runner reads them.

use blue_lang_syntax::{Atom, Sexp};

include!(concat!(env!("OUT_DIR"), "/rows.rs"));

/// The program.
pub const PROGRAM: &str = include_str!("../blue/doc.b");

#[derive(serde::Serialize)]
struct RowJson {
    id: String,
    src: String,
    expect: String,
    covers: Vec<String>,
    marks: Vec<MarkJson>,
    waits_on: Option<MarkJson>,
}

#[derive(Clone, serde::Serialize)]
struct MarkJson {
    mark: String,
    gap: String,
    on: Option<String>,
}

fn mark(option: &Sexp) -> Option<MarkJson> {
    let Sexp::List(xs) = option else { return None };
    let word = xs.first().and_then(Sexp::as_symbol)?;
    if word != "pending" && word != "flaky" {
        return None;
    }
    Some(MarkJson {
        mark: word.to_owned(),
        gap: text(xs.get(1)?)?,
        on: xs.get(2).and_then(text),
    })
}

fn text(s: &Sexp) -> Option<String> {
    match s {
        Sexp::Atom(Atom::Str(t)) => Some(t.clone()),
        _ => None,
    }
}

fn program(s: &Sexp) -> Option<String> {
    blue_lang_syntax::constant_text(s)
}

/// Every compiled-in row, as one JSON array. A form that is not a `row(…)` call
/// with a string id and a program the runner reads as text (a string, or
/// `join_lines` of strings) is skipped: the conformance runner is the gate
/// that refuses one, by name.
///
/// # Errors
///
/// serde's, which these types cannot raise.
pub fn rows_json() -> serde_json::Result<String> {
    let mut out = Vec::new();
    for (_, source) in ROWS {
        let Ok(forms) = blue_lang_syntax::parse_program(source) else {
            continue;
        };
        for form in forms {
            let Sexp::List(items) = form else { continue };
            let [head, id, src, expect, options @ ..] = items.as_slice() else {
                continue;
            };
            if head.as_symbol() != Some("row") {
                continue;
            }
            let (Some(id), Some(src)) = (text(id), program(src)) else {
                continue;
            };
            let covers = options
                .iter()
                .filter_map(|o| match o {
                    Sexp::List(xs) if xs.first().and_then(Sexp::as_symbol) == Some("covers") => {
                        Some(xs[1..].iter().filter_map(text).collect::<Vec<_>>())
                    }
                    _ => None,
                })
                .flatten()
                .collect();
            let marks: Vec<MarkJson> = options.iter().filter_map(mark).collect();
            let row = RowJson {
                id,
                src,
                expect: blue_lang_fmt::format_forms(std::slice::from_ref(expect))
                    .trim_end()
                    .to_string(),
                covers,
                waits_on: marks
                    .iter()
                    .find(|m| m.on.as_deref().is_none_or(|on| on == "walker"))
                    .cloned(),
                marks,
            };
            out.push(row);
        }
    }
    serde_json::to_string(&out)
}

/// mondou's derived view of one definition as one JSON object: the stored
/// `doc`, and every row blue derives, with `lines` the same rendering hover
/// shows.
///
/// # Errors
///
/// serde's, which these types cannot raise.
pub fn derived_json(v: &blue_lang_lsp::docview::DocView) -> serde_json::Result<String> {
    serde_json::to_string(&serde_json::json!({
        "name": v.name,
        "bidama": v.bidama,
        "doc": v.doc,
        "signature": v.signature,
        "params": v.params.iter().map(|(n, t)| serde_json::json!({"name": n, "type": t})).collect::<Vec<_>>(),
        "returns": v.returns,
        "rung": v.rung,
        "contract": v.contract,
        "verb": v.verb.as_ref().map(|r| serde_json::json!({
            "space": r.space, "kind": r.kind, "shape": r.shape, "laterals": r.laterals,
        })),
        "edges": v.edges,
        "callers": v.callers,
        "refusals": v.refusals.iter().map(|(k, m)| serde_json::json!({"kind": k, "meaning": m})).collect::<Vec<_>>(),
        "reach": v.reach.as_ref().map(|r| r.keys().map(|c| c.label()).collect::<Vec<_>>()),
        "lines": v.derived_lines(),
    }))
}
