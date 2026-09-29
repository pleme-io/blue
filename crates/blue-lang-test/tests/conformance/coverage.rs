//! **The missing-row gate.** Every entry in the implementation's own tables
//! has a spec row, and every row's claim names a real entry.
//!
//! The registries are read from the tables the implementation RUNS on, never
//! from the rows and never from a copy:
//!
//! | key | registry |
//! |---|---|
//! | `rule:B0001` | `blue_lang_check::RULES`, the check stage's rule registry |
//! | `form:<example>` | `blue_lang_syntax::FORMS`, the surface-form table |
//! | `keyword:<word>` | `SURFACE_KEYWORDS` + `BLOCK_KEYWORDS`, the reserved words |
//! | `op:<op>` | `blue_lang_syntax::INFIX`, the operator table |
//! | `builtin:<name>` | `blue_lang_runtime::docs::NAMES`, what `blue reference` prints |
//! | `okite:D0001` | `bidamas/okite/RULES.md`, the generated card of okite's ledger |
//! | `rung:<rung>` | the four blueshift rungs; covered by a row whose program MEASURES there |
//!
//! Two directions, like `docs::NAMES` against a live interpreter: an entry with
//! no row is red, and a row claiming a key that names nothing is red. A claim
//! that can be checked is checked: a `builtin:` claim must name a symbol the
//! row's program contains, a `rule:` claim must be the code the row expects,
//! an `op:` or `keyword:` claim must appear in the program's text.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use blue_lang_syntax::{Atom, Sexp};

use crate::rows::{Expect, Row};

pub const RUNGS: [&str; 4] = ["dynamic", "annotated", "checked", "restricted"];

/// Every key the implementation's tables define, by registry.
pub fn registry(repo: &Path) -> BTreeMap<&'static str, BTreeSet<String>> {
    let mut reg: BTreeMap<&'static str, BTreeSet<String>> = BTreeMap::new();
    reg.insert(
        "rule",
        blue_lang_check::RULES
            .iter()
            .map(|r| r.code.as_str().to_owned())
            .collect(),
    );
    reg.insert(
        "form",
        blue_lang_syntax::FORMS
            .iter()
            .map(|f| f.example.to_owned())
            .collect(),
    );
    reg.insert(
        "keyword",
        blue_lang_syntax::SURFACE_KEYWORDS
            .iter()
            .chain(blue_lang_syntax::BLOCK_KEYWORDS)
            .map(|w| (*w).to_owned())
            .collect(),
    );
    reg.insert(
        "op",
        blue_lang_syntax::INFIX
            .iter()
            .map(|i| i.op.to_owned())
            .collect(),
    );
    reg.insert(
        "builtin",
        blue_lang_runtime::docs::NAMES
            .iter()
            .map(|n| n.name.to_owned())
            .collect(),
    );
    reg.insert("okite", okite_ids(repo));
    reg.insert("rung", RUNGS.iter().map(|r| (*r).to_owned()).collect());
    reg
}

/// `D0001`… from the generated card. The card is gated fresh against okite's
/// ledger (`checks.generated-okite-rules-fresh`), so reading it is reading the
/// ledger.
fn okite_ids(repo: &Path) -> BTreeSet<String> {
    let card = repo.join("bidamas/okite/RULES.md");
    let text = std::fs::read_to_string(&card)
        .unwrap_or_else(|e| panic!("{} is okite's card: {e}", card.display()));
    text.lines()
        .filter_map(|l| l.strip_prefix("- **"))
        .filter_map(|l| l.split("**").next())
        .map(str::to_owned)
        .collect()
}

fn symbols(s: &Sexp, out: &mut BTreeSet<String>) {
    match s {
        Sexp::Atom(Atom::Symbol(x)) => {
            out.insert(x.clone());
        }
        Sexp::List(items) => items.iter().for_each(|i| symbols(i, out)),
        // The reader forms name the special form they are.
        Sexp::Quote(x) | Sexp::Quasiquote(x) | Sexp::Unquote(x) | Sexp::UnquoteSplice(x) => {
            out.insert(
                match s {
                    Sexp::Quote(_) => "quote",
                    Sexp::Quasiquote(_) => "quasiquote",
                    Sexp::Unquote(_) => "unquote",
                    _ => "unquote-splicing",
                }
                .to_owned(),
            );
            symbols(x, out);
        }
        _ => {}
    }
}

/// The result of the gate.
pub struct Coverage {
    /// Registry → keys with no row.
    pub missing: BTreeMap<&'static str, Vec<String>>,
    /// Claims refused, each naming its row.
    pub refused: Vec<String>,
    /// Registry → (keys, covered).
    pub totals: BTreeMap<&'static str, (usize, usize)>,
}

impl Coverage {
    pub fn ok(&self) -> bool {
        self.missing.values().all(Vec::is_empty) && self.refused.is_empty()
    }
}

/// Check `rows` against `reg`. `rung_of` measures a program's blueshift rung.
pub fn gate(
    rows: &[Row],
    reg: &BTreeMap<&'static str, BTreeSet<String>>,
    rung_of: impl Fn(&str) -> String,
) -> Coverage {
    let mut covered: BTreeMap<&'static str, BTreeSet<String>> = BTreeMap::new();
    let mut refused = Vec::new();
    for row in rows {
        // A rung is covered by measurement, not by claim: the program really
        // sits there.
        let rung = rung_of(&row.src);
        if RUNGS.contains(&rung.as_str()) {
            covered.entry("rung").or_default().insert(rung);
        }
        let syms = {
            let mut s = BTreeSet::new();
            if let Ok(forms) = blue_lang_syntax::parse_program(&row.src) {
                forms.iter().for_each(|f| symbols(f, &mut s));
            }
            s
        };
        for claim in &row.covers {
            let Some((kind, key)) = claim.split_once(':') else {
                refused.push(format!("{}: `{claim}` is not `registry:key`", row.id));
                continue;
            };
            let Some((&kind, keys)) = reg.get_key_value(kind) else {
                refused.push(format!(
                    "{}: `{kind}` is not a registry ({})",
                    row.id,
                    reg.keys().copied().collect::<Vec<_>>().join(", ")
                ));
                continue;
            };
            if kind == "rung" {
                refused.push(format!(
                    "{}: a rung is covered by measurement; drop `{claim}` and use position(…)",
                    row.id
                ));
                continue;
            }
            if !keys.contains(key) {
                refused.push(format!("{}: `{claim}` names nothing in the {kind} registry", row.id));
                continue;
            }
            let verified = match kind {
                "builtin" => syms.contains(key),
                "rule" => match &row.expect {
                    Expect::Diagnoses(codes) => codes.iter().any(|c| c == key),
                    Expect::Fails(crate::rows::Stage::Check, needle) => needle.contains(key),
                    _ => false,
                },
                "op" | "keyword" => row.src.contains(key),
                _ => true,
            };
            if !verified {
                refused.push(format!(
                    "{}: claims `{claim}`, but the row's {} does not contain it",
                    row.id,
                    if kind == "rule" { "expectation" } else { "program" }
                ));
                continue;
            }
            covered.entry(kind).or_default().insert(key.to_owned());
        }
    }
    let mut missing = BTreeMap::new();
    let mut totals = BTreeMap::new();
    for (&kind, keys) in reg {
        let have = covered.get(kind).cloned().unwrap_or_default();
        let gap: Vec<String> = keys.difference(&have).cloned().collect();
        totals.insert(kind, (keys.len(), keys.len() - gap.len()));
        missing.insert(kind, gap);
    }
    Coverage {
        missing,
        refused,
        totals,
    }
}
