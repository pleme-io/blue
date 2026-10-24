//! The documentation requirement (`theory/BLUE.md`, "The documentation
//! requirement"): rules B0056–B0060 over one bidama file, and the fixes that
//! fill what a source already holds.
//!
//! **Public** is what blue already has: every top-level definition of a
//! bidama — a `def`, a `defmacro`, a top-level `name = value` — is one a
//! `use` can name, so each is public. Blue has no private definition.
//!
//! **Fill before refuse.** Each finding carries the fix that writes what can
//! be derived, from sources in this order, and never text it cannot source:
//!
//! | what | source |
//! |---|---|
//! | intent | the `#` block directly above the `def` (what the catalogue read), the verb graph row's `meaning`, the `docs::NAMES` line |
//! | example | the simplest assertion of the file's own tests that calls the definition and reads no test local |
//! | module purpose | the file's first comment block, whose first line is its CATALOG line |

use std::collections::{BTreeSet, HashMap};

use blue_lang_syntax::doc::{self as d};
use blue_lang_syntax::{Comment, Spanned, SpannedForm};
use tatara_lisp::Span;

use crate::{Applicability, Code, Diagnostic, Edit, Fix};

/// Where a definition's intent can come from, besides its own file.
pub struct Sources<'a> {
    /// The verb graph's `meaning` for this bidama's verb, if it has a row.
    pub meaning: &'a dyn Fn(&str) -> Option<String>,
    /// The builtin reference line for a name, if the runtime binds it.
    pub names_line: &'a dyn Fn(&str) -> Option<String>,
}

/// One bidama file's documentation findings.
///
/// `forms` are the file's top-level forms as the check stage holds them
/// (stripped, doctests excluded), each with its index in the program;
/// `package` is the bidama's name: the comment block heading the file is its
/// purpose when it stands apart or starts with that name, and then it is never
/// a definition's.
#[must_use]
pub fn check_file(
    text: &str,
    forms: &[(usize, &Spanned)],
    package: &str,
    sources: &Sources<'_>,
) -> Vec<Diagnostic> {
    let Ok(documented) = blue_lang_syntax::parse_program_documented(text) else {
        return Vec::new();
    };
    let comments = blue_lang_syntax::comments(text);
    let tests = TestAssertions::of(text, &documented);
    let head = header(text, &documented, &comments, package);
    let header_span = head
        .as_ref()
        .map(|b| Span::new(b[0].span.start, b[b.len() - 1].span.end));
    let mut out = Vec::new();
    if let Some(&(i, _)) = forms.first() {
        out.extend(module_rule(text, &documented, head.as_deref(), &tests, i));
    }
    for f in &documented {
        let (doc, def) = match d::documented(f) {
            Some((t, def)) => (Some(t), def),
            None => (None, f),
        };
        let Some(name) = d::defined_name(def) else {
            continue;
        };
        let Some(&(top_level, _)) = forms.iter().find(|(_, s)| s.span == f.span) else {
            continue;
        };
        let at = name_span(def).unwrap_or(def.span);
        match doc {
            None => {
                let mut diag = Diagnostic::new(
                    Code::B0056,
                    format!("`{name}` is public and has no `@doc`"),
                    at,
                )
                .at_top_level(top_level)
                .with_help("write `@doc \"\"\"` above it: one sentence starting with its name, then an indented `expr #=> value` example");
                if let Some(fix) =
                    fill_definition(text, &comments, header_span, f, name, &tests, sources)
                {
                    diag = diag.with_fix(fix);
                }
                out.push(diag);
            }
            Some(text_of_doc) => {
                out.extend(
                    doc_findings(text, f, def, name, text_of_doc, &tests, at)
                        .into_iter()
                        .map(|d| d.at_top_level(top_level)),
                );
            }
        }
    }
    out
}

fn name_span(def: &Spanned) -> Option<Span> {
    let items = def.as_list()?;
    if items.first()?.as_symbol()? == "defmacro" {
        return Some(items.get(1)?.span);
    }
    Some(blue_lang_syntax::scope::defined_name_node(items)?.span)
}

const PLACEHOLDERS: &[&str] = &[
    "todo",
    "tbd",
    "fixme",
    "xxx",
    "wip",
    "...",
    "…",
    "-",
    "?",
    "doc",
    "docs",
    "documentation",
    "description",
    "none",
    "n/a",
];

/// The intent with the name it starts with taken off, or `None` when it does
/// not start with the name.
fn after_name<'a>(intent: &'a str, name: &str) -> Option<&'a str> {
    let rest = intent
        .strip_prefix('`')
        .and_then(|r| r.strip_prefix(name))
        .and_then(|r| r.strip_prefix('`'))
        .or_else(|| intent.strip_prefix(name))?;
    match rest.chars().next() {
        None => Some(rest),
        Some(c) if c.is_alphanumeric() || c == '_' || c == '?' || c == '!' => None,
        Some(_) => Some(rest.trim_start_matches([':', ',', ' ', '—', '-'])),
    }
}

fn is_placeholder(s: &str) -> bool {
    let core = s
        .trim()
        .trim_end_matches(['.', '!', ':'])
        .trim()
        .to_lowercase();
    core.is_empty()
        || PLACEHOLDERS.contains(&core.as_str())
        || s.split(|c: char| !c.is_alphanumeric())
            .any(|w| matches!(w, "TODO" | "FIXME" | "TBD" | "XXX"))
}

/// A prose line that says what the signature, a type or a contract row
/// already says.
fn restates(line: &str, name: &str) -> bool {
    let l = line.trim().to_lowercase();
    let field = l.split_once(':').map(|(k, _)| k.trim()).filter(|k| {
        matches!(
            *k,
            "args"
                | "arguments"
                | "param"
                | "params"
                | "parameters"
                | "opts"
                | "options"
                | "return"
                | "returns"
                | "raises"
                | "type"
                | "types"
                | "signature"
                | "spec"
        )
    });
    field.is_some()
        || ["@param", "@return", "@raise", "@type", "@spec", "@arg"]
            .iter()
            .any(|t| l.starts_with(t))
        || (line.contains(&format!("{name}(")) && line.contains(") ->"))
}

fn doc_findings(
    text: &str,
    wrapper: &Spanned,
    def: &Spanned,
    name: &str,
    doc: &str,
    tests: &TestAssertions,
    at: Span,
) -> Vec<Diagnostic> {
    let mut out = Vec::new();
    let intent = d::intent(doc);
    let text_span = doc_text_span(wrapper);
    if doc.trim().is_empty()
        || is_placeholder(&intent)
        || after_name(&intent, name).is_some_and(is_placeholder)
    {
        out.push(
            Diagnostic::new(
                Code::B0059,
                format!("`{name}`'s `@doc` is empty or a placeholder"),
                text_span,
            )
            .with_help("say what it is for, in one sentence starting with its name"),
        );
        return out;
    }
    if after_name(&intent, name).is_none() {
        out.push(
            Diagnostic::new(
                Code::B0056,
                format!("`{name}`'s `@doc` does not start with its name"),
                text_span,
            )
            .with_help(format!("start the first sentence with `{name}`")),
        );
    }
    if let Some(line) = doc
        .lines()
        .filter(|l| !l.starts_with([' ', '\t']))
        .find(|l| restates(l, name))
    {
        let mut diag = Diagnostic::new(
            Code::B0060,
            format!("`{name}`'s `@doc` restates what blue derives: `{}`", line.trim()),
            text_span,
        )
        .with_help("the signature, the blueshift and the contract row already say this; `blue doc` shows them");
        if let Some(fix) = delete_line(text, text_span, line) {
            diag = diag.with_fix(fix);
        }
        out.push(diag);
    }
    if d::examples(doc).is_empty() {
        let mut diag =
            Diagnostic::new(Code::B0057, format!("`{name}`'s `@doc` has no example"), at)
                .with_help("add an indented line `expr #=> value`; `blue test` runs it");
        if let Some(example) = tests.example_for(name) {
            if let Some(fix) = add_example(text, wrapper, &example) {
                diag = diag.with_fix(fix);
            }
        }
        out.push(diag);
    }
    let _ = def;
    out
}

/// Delete the source line of a doc text that reads `line` once stripped.
fn delete_line(text: &str, within: Span, line: &str) -> Option<Fix> {
    let region = text.get(within.start..within.end)?;
    let mut at = within.start;
    for l in region.split_inclusive('\n') {
        if l.trim() == line.trim() {
            return Some(Fix {
                message: "delete the line blue derives".into(),
                edits: vec![Edit {
                    span: Span::new(at, at + l.len()),
                    original: l.to_string(),
                    replacement: String::new(),
                }],
                applicability: Applicability::MachineApplicable,
            });
        }
        at += l.len();
    }
    None
}

fn doc_text_span(wrapper: &Spanned) -> Span {
    wrapper
        .as_list()
        .and_then(|items| items.get(1))
        .map_or(wrapper.span, |t| t.span)
}

fn module_rule(
    text: &str,
    documented: &[Spanned],
    head: Option<&[&Comment]>,
    tests: &TestAssertions,
    top_level: usize,
) -> Vec<Diagnostic> {
    let defined: BTreeSet<String> = documented
        .iter()
        .filter_map(|f| {
            d::documented(f).map_or_else(|| d::defined_name(f), |(_, def)| d::defined_name(def))
        })
        .map(str::to_string)
        .collect();
    match d::module_doc(documented) {
        Some((doc, span)) => {
            if doc.trim().is_empty() || is_placeholder(&d::intent(doc)) {
                return vec![Diagnostic::new(
                    Code::B0059,
                    "the `@moduledoc` is empty or a placeholder",
                    span,
                )
                .at_top_level(top_level)];
            }
            if d::examples(doc).is_empty() {
                let mut diag =
                    Diagnostic::new(Code::B0058, "the `@moduledoc` has no whole example", span)
                        .at_top_level(top_level)
                        .with_help(
                            "add an indented example whose `expr #=> value` lines `blue test` runs",
                        );
                if let Some(example) = tests.any_example(&defined) {
                    let close = span.end - 3;
                    let line_start = text[..close].rfind('\n').map_or(0, |i| i + 1);
                    diag = diag.with_fix(Fix {
                        message: "add the example the file's own tests hold".into(),
                        edits: vec![Edit {
                            span: Span::new(line_start, line_start),
                            original: String::new(),
                            replacement: format!("\n    {example}\n"),
                        }],
                        applicability: Applicability::MachineApplicable,
                    });
                }
                return vec![diag];
            }
            Vec::new()
        }
        None => {
            let at = documented
                .first()
                .map_or(Span::new(0, 0), |f| Span::new(f.span.start, f.span.start));
            let mut diag = Diagnostic::new(Code::B0058, "the bidama has no `@moduledoc`", at)
                .at_top_level(top_level)
                .with_help(
                    "open the file with `@moduledoc \"\"\"`: its purpose, then one whole example",
                );
            if let Some(fix) = head.and_then(|h| fill_module(text, h, tests, &defined)) {
                diag = diag.with_fix(fix);
            }
            vec![diag]
        }
    }
}

/// The comment block heading the file: the first run of own-line comments
/// before its first definition, when a blank line follows it or its first
/// line names the bidama (the CATALOG gloss, `kazu (数) — numbers.`).
fn header<'c>(
    text: &str,
    documented: &[Spanned],
    comments: &'c [Comment],
    package: &str,
) -> Option<Vec<&'c Comment>> {
    let code_starts = documented
        .iter()
        .find(|f| {
            !matches!(
                f.as_list()
                    .and_then(|i| i.first())
                    .and_then(Spanned::as_symbol),
                Some("use" | "legacy_names" | "blue-moduledoc")
            )
        })
        .map_or(text.len(), |f| f.span.start);
    let first = comments
        .iter()
        .position(|c| c.own_line && !is_waiver(&c.text) && c.span.start < code_starts)?;
    let mut block = vec![&comments[first]];
    for c in &comments[first + 1..] {
        let prev = block[block.len() - 1];
        let between = &text[prev.span.end..c.span.start];
        if c.own_line && between.matches('\n').count() == 1 && between.trim().is_empty() {
            block.push(c);
        } else {
            break;
        }
    }
    let last = block[block.len() - 1];
    let rest = &text[last.span.end..];
    let detached = rest.starts_with("\n\n") || rest.trim().is_empty();
    let named = comment_line(block[0])
        .strip_prefix(package)
        .is_some_and(|r| !r.starts_with(|c: char| c.is_alphanumeric() || c == '_'));
    (detached || named).then_some(block)
}

fn is_waiver(comment: &str) -> bool {
    comment
        .trim_start_matches('#')
        .trim_start()
        .starts_with("waive ")
}

fn comment_line(c: &Comment) -> String {
    let t = c.text.strip_prefix('#').unwrap_or(&c.text);
    t.strip_prefix(' ').unwrap_or(t).trim_end().to_string()
}

fn heredoc(word: &str, text: &str) -> String {
    format!("{word} \"\"\"\n{text}\n\"\"\"\n")
}

fn fill_module(
    text: &str,
    block: &[&Comment],
    tests: &TestAssertions,
    defined: &BTreeSet<String>,
) -> Option<Fix> {
    let lines: Vec<String> = block.iter().map(|c| comment_line(c)).collect();
    let purpose = lines.join("\n").trim().to_string();
    if purpose.is_empty() || purpose.contains("\"\"\"") || is_placeholder(&d::intent(&purpose)) {
        return None;
    }
    let mut body = purpose;
    if let Some(example) = tests.any_example(defined) {
        body.push_str(&format!("\n\n    {example}"));
    }
    let doc = format!("{}\n", heredoc("@moduledoc", &body));
    let start = line_start(text, block[0].span.start);
    let end = block[block.len() - 1].span.end;
    let end = if text[end..].starts_with("\n\n") {
        end + 2
    } else if text[end..].starts_with('\n') {
        end + 1
    } else {
        end
    };
    let lifted = Edit {
        span: Span::new(start, end),
        original: text[start..end].to_string(),
        replacement: String::new(),
    };
    let edits = if start == 0 {
        vec![Edit {
            replacement: doc,
            ..lifted
        }]
    } else {
        vec![
            Edit {
                span: Span::new(0, 0),
                original: String::new(),
                replacement: doc,
            },
            lifted,
        ]
    };
    Some(Fix {
        message: "lift the file's leading comment block into `@moduledoc`".into(),
        edits,
        applicability: Applicability::MachineApplicable,
    })
}

fn line_start(text: &str, at: usize) -> usize {
    text[..at].rfind('\n').map_or(0, |i| i + 1)
}

/// The own-line comments directly above `start`, waivers apart: the doc
/// comment the catalogue reads, and the waivers that stay comments.
fn comments_above<'c>(text: &str, comments: &'c [Comment], start: usize) -> Vec<&'c Comment> {
    let mut out: Vec<&Comment> = Vec::new();
    let mut edge = line_start(text, start);
    for c in comments.iter().rev() {
        if c.span.end > edge {
            continue;
        }
        if !c.own_line {
            break;
        }
        let between = &text[c.span.end..edge];
        if between.matches('\n').count() != 1 || !between.trim().is_empty() {
            break;
        }
        out.push(c);
        edge = line_start(text, c.span.start);
    }
    out.reverse();
    out
}

fn decoration(line: &str) -> bool {
    !line.chars().any(char::is_alphanumeric)
}

/// A sentence that ends: the source's own punctuation, or a period.
fn closed(s: &str) -> String {
    let mut out = s.trim_end().to_string();
    if !out.ends_with(['.', '!', '?', ':', ')']) {
        out.push('.');
    }
    out
}

/// The source's first line, starting with the name; the source keeps its
/// case, so a proper noun (`GraphQL`, `Euler`) is never lowered.
fn named(name: &str, source: &str) -> Option<String> {
    let s = source.trim();
    if s.is_empty() || is_placeholder(s) {
        return None;
    }
    Some(if after_name(s, name).is_some() {
        s.to_string()
    } else {
        format!("{name}: {s}")
    })
}

fn fill_definition(
    text: &str,
    comments: &[Comment],
    header: Option<Span>,
    wrapper: &Spanned,
    name: &str,
    tests: &TestAssertions,
    sources: &Sources<'_>,
) -> Option<Fix> {
    let in_header =
        |c: &&Comment| header.is_some_and(|h| c.span.start >= h.start && c.span.end <= h.end);
    let above: Vec<&Comment> = comments_above(text, comments, wrapper.span.start)
        .into_iter()
        .filter(|c| !in_header(c))
        .collect();
    let lifted: Vec<&Comment> = above
        .iter()
        .copied()
        .filter(|c| !is_waiver(&c.text))
        .collect();
    let prose: Vec<String> = lifted
        .iter()
        .map(|c| comment_line(c))
        .filter(|l| l.is_empty() || !decoration(l))
        .collect();
    let prose: Vec<String> = {
        let mut p = prose;
        while p.first().is_some_and(String::is_empty) {
            p.remove(0);
        }
        while p.last().is_some_and(String::is_empty) {
            p.pop();
        }
        p
    };
    let (intent, from_comments) = if prose.is_empty() {
        let meaning = (sources.meaning)(name).or_else(|| (sources.names_line)(name))?;
        (closed(&named(name, &meaning)?), false)
    } else {
        let mut lines = prose.clone();
        lines[0] = named(name, &lines[0])?;
        let paragraph = lines
            .iter()
            .position(String::is_empty)
            .unwrap_or(lines.len());
        lines[paragraph - 1] = closed(&lines[paragraph - 1]);
        (lines.join("\n"), true)
    };
    if intent.contains("\"\"\"")
        || intent.lines().any(|l| restates(l, name))
        || after_name(&d::intent(&intent), name).is_none_or(is_placeholder)
    {
        return None;
    }
    let mut body = intent;
    if let Some(example) = tests.example_for(name) {
        body.push_str(&format!("\n\n    {example}"));
    }
    let doc = heredoc("@doc", &body);
    let start = line_start(text, wrapper.span.start);
    let (span, original, replacement) = if from_comments && !lifted.is_empty() {
        let from = line_start(text, lifted[0].span.start);
        let waivers: String = above
            .iter()
            .filter(|c| c.span.start >= from && is_waiver(&c.text))
            .map(|c| format!("{}\n", c.text.trim_end()))
            .collect();
        (
            Span::new(from, start),
            text[from..start].to_string(),
            format!("{waivers}{doc}"),
        )
    } else {
        (Span::new(start, start), String::new(), doc)
    };
    Some(Fix {
        message: format!("write `{name}`'s `@doc` from what its sources hold"),
        edits: vec![Edit {
            span,
            original,
            replacement,
        }],
        applicability: Applicability::MachineApplicable,
    })
}

fn add_example(text: &str, wrapper: &Spanned, example: &str) -> Option<Fix> {
    let text_span = doc_text_span(wrapper);
    let region = &text[text_span.start..text_span.end];
    let close = text_span.start + region.rfind("\"\"\"")?;
    let at = line_start(text, close);
    Some(Fix {
        message: "add the example the file's own tests hold".into(),
        edits: vec![Edit {
            span: Span::new(at, at),
            original: String::new(),
            replacement: format!("\n    {example}\n"),
        }],
        applicability: Applicability::MachineApplicable,
    })
}

/// The file's test assertions of the shape `assert lhs == rhs`, each one
/// line, reading no local of its test.
struct TestAssertions {
    /// `(callee or value name, "lhs #=> rhs")`.
    found: Vec<(String, String)>,
}

impl TestAssertions {
    fn of(text: &str, documented: &[Spanned]) -> Self {
        let mut found = Vec::new();
        for form in documented {
            let Some([head, _, body]) = form.as_list() else {
                continue;
            };
            if head.as_symbol() != Some("deftest") {
                continue;
            }
            let mut locals = BTreeSet::new();
            assigned(body, &mut locals);
            let mut asserts = Vec::new();
            assertions(body, &mut asserts);
            for a in asserts {
                let Some([h, lhs, rhs]) = a.as_list() else {
                    continue;
                };
                if h.as_symbol() != Some("equal?") {
                    continue;
                }
                let subject = match &lhs.form {
                    SpannedForm::Atom(_) => lhs.as_symbol(),
                    SpannedForm::List(items) => items.first().and_then(Spanned::as_symbol),
                    _ => None,
                };
                let Some(subject) = subject else {
                    continue;
                };
                let mut names = BTreeSet::new();
                symbols(lhs, &mut names);
                symbols(rhs, &mut names);
                if names.iter().any(|n| locals.contains(n)) || has_lambda(lhs) || has_lambda(rhs) {
                    continue;
                }
                let (Some(l), Some(r)) = (slice(text, lhs.span), slice(text, rhs.span)) else {
                    continue;
                };
                if l.contains('\n') || r.contains('\n') || l.contains(" #=> ") {
                    continue;
                }
                found.push((subject.to_string(), format!("{l} #=> {r}")));
            }
        }
        Self { found }
    }

    /// The shortest assertion about `name`.
    fn example_for(&self, name: &str) -> Option<String> {
        self.found
            .iter()
            .filter(|(s, _)| s == name)
            .map(|(_, e)| e)
            .min_by_key(|e| (e.len(), (*e).clone()))
            .cloned()
    }

    /// The shortest assertion of the file about one of `defined`.
    fn any_example(&self, defined: &BTreeSet<String>) -> Option<String> {
        self.found
            .iter()
            .filter(|(s, _)| defined.contains(s))
            .map(|(_, e)| e)
            .min_by_key(|e| (e.len(), (*e).clone()))
            .cloned()
    }
}

fn slice(text: &str, span: Span) -> Option<&str> {
    if span.is_synthetic() {
        return None;
    }
    text.get(span.start..span.end)
}

fn assertions<'t>(node: &'t Spanned, out: &mut Vec<&'t Spanned>) {
    if let Some(items) = node.as_list() {
        if items.first().and_then(Spanned::as_symbol) == Some(blue_lang_syntax::LOWERED_ASSERT) {
            if let Some(e) = items.get(2) {
                out.push(e);
            }
            return;
        }
        for i in items {
            assertions(i, out);
        }
    }
}

fn assigned(node: &Spanned, out: &mut BTreeSet<String>) {
    if let Some(items) = node.as_list() {
        if items.first().and_then(Spanned::as_symbol) == Some("define") {
            if let Some(n) = items.get(1).and_then(Spanned::as_symbol) {
                out.insert(n.to_string());
            }
        }
        for i in items {
            assigned(i, out);
        }
    }
}

fn symbols(node: &Spanned, out: &mut BTreeSet<String>) {
    match &node.form {
        SpannedForm::Atom(_) => {
            if let Some(s) = node.as_symbol() {
                out.insert(s.to_string());
            }
        }
        SpannedForm::List(items) => {
            for i in items {
                symbols(i, out);
            }
        }
        SpannedForm::Quote(x)
        | SpannedForm::Quasiquote(x)
        | SpannedForm::Unquote(x)
        | SpannedForm::UnquoteSplice(x) => symbols(x, out),
        SpannedForm::Nil => {}
    }
}

fn has_lambda(node: &Spanned) -> bool {
    match node.as_list() {
        Some(items) => {
            items.first().and_then(Spanned::as_symbol) == Some("lambda")
                || items.iter().any(has_lambda)
        }
        None => false,
    }
}

/// The verb graph's rows as `(bidama, verb) -> meaning`, read from the row
/// files' text (they are parsed, never run): every `verb(space, name, {…})`
/// whose `today` names the bidama it exists in.
#[must_use]
pub fn graph_meanings(row_files: &[String]) -> HashMap<(String, String), String> {
    let mut out = HashMap::new();
    for text in row_files {
        let Ok(forms) = blue_lang_syntax::parse_program(text) else {
            continue;
        };
        for f in forms {
            let Some([head, _space, verb, fields]) = f.as_list() else {
                continue;
            };
            if head.as_symbol() != Some("verb") {
                continue;
            }
            let Some(verb) = verb.as_string() else {
                continue;
            };
            let Some(map) = fields.as_list() else {
                continue;
            };
            let mut today = None;
            let mut meaning = None;
            for pair in map.get(1..).unwrap_or_default().chunks(2) {
                let [k, v] = pair else { continue };
                match (k.as_keyword(), v.as_string()) {
                    (Some("today"), Some(t)) => today = Some(t.to_string()),
                    (Some("meaning"), Some(m)) => meaning = Some(m.to_string()),
                    _ => {}
                }
            }
            let (Some(today), Some(meaning)) = (today, meaning) else {
                continue;
            };
            for part in today.split(['|', ',']) {
                if let Some((state, bidama)) = part.trim().split_once(':') {
                    if matches!(state, "exists" | "partial") {
                        out.insert((bidama.to_string(), verb.to_string()), meaning.clone());
                    }
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn findings(text: &str) -> Vec<Diagnostic> {
        let stripped = blue_lang_syntax::parse_program_tree(text).unwrap();
        let forms: Vec<(usize, &Spanned)> = stripped.iter().enumerate().collect();
        let none = |_: &str| None;
        check_file(
            text,
            &forms,
            "m",
            &Sources {
                meaning: &|n| (n == "g").then(|| "the g of a thing".to_string()),
                names_line: &none,
            },
        )
    }

    fn codes(text: &str) -> Vec<Code> {
        findings(text).iter().map(|d| d.code).collect()
    }

    fn fixed(text: &str) -> String {
        let ds = findings(text);
        crate::fixes::apply_machine_fixes(&ds, &|_| true, text).0
    }

    const DOCUMENTED: &str = "@moduledoc \"\"\"\nm holds f.\n\n    f(1) #=> 2\n\"\"\"\n\n@doc \"\"\"\nf adds one.\n\n    f(1) #=> 2\n\"\"\"\ndef f(n)\n  n + 1\nend\n";

    #[test]
    fn a_documented_file_is_clean() {
        assert_eq!(codes(DOCUMENTED), vec![]);
    }

    #[test]
    fn each_rule_finds_its_case() {
        let module = "@moduledoc \"\"\"\nm holds f.\n\n    f(1) #=> 2\n\"\"\"\n\n";
        assert_eq!(
            codes(&format!("{module}def f(n)\n  n\nend\n")),
            vec![Code::B0056]
        );
        assert_eq!(
            codes(&format!(
                "{module}@doc \"\"\"\nadds one.\n\n    f(1) #=> 1\n\"\"\"\ndef f(n)\n  n\nend\n"
            )),
            vec![Code::B0056]
        );
        assert_eq!(
            codes(&format!(
                "{module}@doc \"\"\"\nf adds one.\n\"\"\"\ndef f(n)\n  n\nend\n"
            )),
            vec![Code::B0057]
        );
        assert_eq!(
            codes("def f(n)\n  n\nend\n"),
            vec![Code::B0058, Code::B0056]
        );
        assert_eq!(
            codes(&format!(
                "{module}@doc \"\"\"\nf: TODO\n\"\"\"\ndef f(n)\n  n\nend\n"
            )),
            vec![Code::B0059]
        );
        assert_eq!(
            codes(&format!("{module}@doc \"\"\"\nf adds one.\n\nReturns: an Int.\n\n    f(1) #=> 1\n\"\"\"\ndef f(n)\n  n\nend\n")),
            vec![Code::B0060]
        );
    }

    #[test]
    fn the_fix_lifts_the_comment_and_the_test() {
        let src = "use(\"retsu\", [:first])\n\n# m: the f package.\n# It adds.\n\n# waive B0002: kept\n# The successor of a number.\ndef f(n)\n  n + 1\nend\n\n# Its own line.\ndef g()\n  1\nend\n\ndef h()\n  2\nend\n\ntest \"f\"\n  x = 3\n  assert f(x) == 4\n  assert f(10) == 11\n  assert f(1) == 2\nend\n";
        let out = fixed(src);
        assert_eq!(
            out,
            "@moduledoc \"\"\"\nm: the f package.\nIt adds.\n\n    f(1) #=> 2\n\"\"\"\n\nuse(\"retsu\", [:first])\n\n# waive B0002: kept\n@doc \"\"\"\nf: The successor of a number.\n\n    f(1) #=> 2\n\"\"\"\ndef f(n)\n  n + 1\nend\n\n@doc \"\"\"\ng: Its own line.\n\"\"\"\ndef g()\n  1\nend\n\ndef h()\n  2\nend\n\ntest \"f\"\n  x = 3\n  assert f(x) == 4\n  assert f(10) == 11\n  assert f(1) == 2\nend\n",
            "\n{out}"
        );
    }

    /// Red run (2026-10-24): before `header` named the bidama, keiyu's
    /// header, attached to its first `def`, became that def's `@doc`, and a
    /// header after `legacy_names` was not lifted at all.
    #[test]
    fn a_header_naming_the_bidama_is_its_purpose_even_when_attached() {
        let src = "use(\"retsu\", [:first])\n\nlegacy_names(\"0.1.1\", \"m\")\n\n# m (例) — one thing.\ndef f()\n  1\nend\n\ntest \"f\"\n  assert f == 1\nend\n";
        let out = fixed(src);
        assert_eq!(
            out,
            "@moduledoc \"\"\"\nm (例) — one thing.\n\n    f #=> 1\n\"\"\"\n\nuse(\"retsu\", [:first])\n\nlegacy_names(\"0.1.1\", \"m\")\n\ndef f()\n  1\nend\n\ntest \"f\"\n  assert f == 1\nend\n",
            "\n{out}"
        );
    }

    #[test]
    fn the_graph_row_is_the_second_source_and_nothing_is_invented() {
        let src = "@moduledoc \"\"\"\nm holds g.\n\n    g #=> 1\n\"\"\"\n\ndef g()\n  1\nend\n\ndef h()\n  2\nend\n";
        let out = fixed(src);
        assert!(
            out.contains("@doc \"\"\"\ng: the g of a thing.\n\"\"\"\ndef g()"),
            "{out}"
        );
        assert!(
            out.contains("end\n\ndef h()"),
            "h has no source, so no doc: {out}"
        );
    }

    #[test]
    fn graph_rows_are_read_as_data() {
        let rows = vec!["space(\"retsu\", {status: :ratified})\n\nverb(\"retsu\", \"at\", {kind: :pure, today: \"exists:retsu\", meaning: \"item at an index\"})\nverb(\"retsu\", \"chunk\", {today: \"absent\", meaning: \"x\"})\n".to_string()];
        let m = graph_meanings(&rows);
        assert_eq!(
            m.get(&("retsu".into(), "at".into())).map(String::as_str),
            Some("item at an index")
        );
        assert_eq!(m.len(), 1);
    }
}
