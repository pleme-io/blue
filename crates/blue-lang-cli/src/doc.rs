//! `blue doc`: the blue program `blue/doc.b`, compiled into this binary, and
//! the two things it asks of the binary that are not blue's to read.
//!
//! The program's own imports (mokuroku, which reads every bidama's
//! definitions for the catalogue) resolve through `BLUE_PATH`, then the
//! standard distribution compiled into blue, so the tool works with no
//! `BLUE_PATH`; what it documents is the distribution `BLUE_PATH` names.
//!
//! `blue doc --rows` prints the conformance rows compiled in by `build.rs`
//! (`spec/rows/*.b`) as one JSON array of `{id, src, expect, covers}`: a builtin's example is the row that specifies it. Rows are
//! parsed, never evaluated, exactly as the conformance runner reads them.

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
}

fn text(s: &Sexp) -> Option<String> {
    match s {
        Sexp::Atom(Atom::Str(t)) => Some(t.clone()),
        _ => None,
    }
}

/// Every compiled-in row, as one JSON array. A form that is not a `row(…)` call
/// with a string id and program is skipped: the conformance runner is the
/// gate that refuses one, by name.
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
            let (Some(id), Some(src)) = (text(id), text(src)) else {
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
            let row = RowJson {
                id,
                src,
                expect: blue_lang_fmt::format_forms(std::slice::from_ref(expect))
                    .trim_end()
                    .to_string(),
                covers,
            };
            out.push(row);
        }
    }
    serde_json::to_string(&out)
}
