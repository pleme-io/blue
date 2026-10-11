//! [`B0023`](crate::Code::B0023): a name is a keyword, not a string.
//!
//! The rewrite `"kind"` → `:kind` keeps a program's meaning only where the
//! runtime reads the string and the keyword alike. [`TEXT_NAMES`] lists those
//! argument positions, each one a builtin whose implementation turns either
//! into the same text before using it, and each pinned by a conformance row
//! (`spec/rows/keywords.b`) that compares the two calls' results. There the
//! fix is machine-applicable, and canonical: applied before every compile.
//!
//! The position is the builtin's only when the call's head RESOLVES to it. A
//! local, an own definition or a listed import named `error` is somebody
//! else's function, which may treat a string and a keyword differently, so the
//! resolution the names pass recorded for the head decides, not the spelling.
//!
//! A string key in a map literal is reported with a maybe-incorrect suggestion
//! only: `{"a" => 1}` and `{a: 1}` are different maps, and every read of the
//! key has to change with it.

use std::collections::HashMap;

use blue_lang_syntax::words::is_symbol_name;
use tatara_lisp::{Atom, Spanned, SpannedForm};

use crate::names::{Reference, Target};
use crate::rules::Code;
use crate::{Applicability, Diagnostic, Edit, Fix};

/// `(builtin, argument index)` where the runtime reads a string and a keyword
/// as the same text. Index 1 is the first argument.
///
/// | builtin | why the two are one value to it |
/// |---|---|
/// | `error` | tatara-lisp's `error` stores the kind as its text (`Keyword(s) \| Str(s) => s`) |
/// | `json_get`, `json_get_or` | the key goes through `json::as_str`, which accepts both, before the lookup |
pub const TEXT_NAMES: &[(&str, usize)] = &[("error", 1), ("json_get", 2), ("json_get_or", 2)];

/// B0023 over the forms `report` selects (the entry file's: an imported
/// package's findings are its own author's).
pub(crate) fn check(
    forms: &[Spanned],
    references: &[Reference],
    report: &dyn Fn(usize) -> bool,
) -> Vec<Diagnostic> {
    let heads: HashMap<usize, &Reference> = references.iter().map(|r| (r.node, r)).collect();
    let mut out = Vec::new();
    for (i, form) in forms.iter().enumerate() {
        if report(i) {
            visit(form, i, &heads, &mut out);
        }
    }
    out
}

fn visit(
    form: &Spanned,
    top_level: usize,
    heads: &HashMap<usize, &Reference>,
    out: &mut Vec<Diagnostic>,
) {
    // Quoted code is data: a string in it is the string the program builds.
    let SpannedForm::List(items) = &form.form else {
        return;
    };
    if let Some(head) = items.first().and_then(Spanned::as_symbol) {
        if head == blue_lang_syntax::LOWERED_MAP {
            for key in items[1..].iter().step_by(2) {
                if let Some(name) = name_string(key) {
                    out.push(map_key(key, name, top_level));
                }
            }
        }
        let builtin = heads
            .get(&(std::ptr::from_ref(&items[0]) as usize))
            .filter(|r| !r.opaque)
            .and_then(|r| match &r.ns {
                Target::Builtin(b) => Some(b.as_str()),
                _ => None,
            });
        if let Some(b) = builtin {
            for (callee, at) in TEXT_NAMES {
                if *callee == b {
                    if let Some(arg) = items.get(*at) {
                        if let Some(name) = name_string(arg) {
                            out.push(text_name(arg, name, b, top_level));
                        }
                    }
                }
            }
        }
    }
    for item in items {
        visit(item, top_level, heads, out);
    }
}

/// The string `node` is, when `:string` could spell it and the node is that
/// literal as written. A call inside an interpolation (`"#{get(r, "k")}"`)
/// is parsed from a substring, and every node of it carries the whole outer
/// string's span: there is no span to put the edit on, so it is not reported.
fn name_string(node: &Spanned) -> Option<&str> {
    match &node.form {
        SpannedForm::Atom(Atom::Str(s))
            if is_symbol_name(s) && node.span.end - node.span.start == s.len() + 2 =>
        {
            Some(s)
        }
        _ => None,
    }
}

fn edit(node: &Spanned, name: &str) -> Edit {
    Edit {
        span: node.span,
        original: format!("\"{name}\""),
        replacement: format!(":{name}"),
    }
}

fn text_name(node: &Spanned, name: &str, builtin: &str, top_level: usize) -> Diagnostic {
    Diagnostic::new(
        Code::B0023,
        format!("`{builtin}` reads `\"{name}\"` as a name: write `:{name}`"),
        node.span,
    )
    .at_top_level(top_level)
    .with_help(format!(
        "`{builtin}` treats the string and the keyword as the same text, so `:{name}` is the same program"
    ))
    .with_fix(Fix {
        message: format!("write `:{name}`"),
        edits: vec![edit(node, name)],
        applicability: Applicability::MachineApplicable,
    })
}

fn map_key(node: &Spanned, name: &str, top_level: usize) -> Diagnostic {
    Diagnostic::new(
        Code::B0023,
        format!("the map key `\"{name}\"` could be the keyword `:{name}`"),
        node.span,
    )
    .at_top_level(top_level)
    .with_help(format!(
        "`{{{name}: …}}` is a different key: change every `get`, `assoc` and `dissoc` of it too"
    ))
    .with_fix(Fix {
        message: format!("key the map by `:{name}`"),
        edits: vec![edit(node, name)],
        applicability: Applicability::MaybeIncorrect,
    })
}
