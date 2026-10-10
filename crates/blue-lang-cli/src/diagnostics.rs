//! How `blue check` shows what the check stage found: text for a person,
//! JSON Lines for a tool, and `--fix` for the machine-applicable repairs.
//!
//! ## `--format json`: one object per line, per diagnostic
//!
//! The field names are a stable interface; `docs/DIAGNOSTICS.md` documents
//! each one and `tests/check_json.rs` pins the exact output for a fixture, so
//! a rename is a red test rather than a silent break in someone's tool.
//!
//! ```json
//! {"code":"B0001","slug":"unbound-name","severity":"error",
//!  "message":"unbound name `lenght`","file":"f.b",
//!  "line":2,"column":3,"end_line":2,"end_column":9,"byte_start":12,"byte_end":18,
//!  "help":"did you mean `length` (builtin)?","related":[],
//!  "fixes":[{"message":"replace with `length` (builtin)","applicability":"maybe-incorrect",
//!            "edits":[{"file":"f.b","line":2,"column":3,"end_line":2,"end_column":9,
//!                      "byte_start":12,"byte_end":18,"original":"lenght","replacement":"length"}]}],
//!  "waiver":null}
//! ```

use std::path::Path;

use blue_lang_check::{Applicability, Diagnostic, Outcome};
use blue_lang_runtime::uses::{ResolvedProgram, SourceFile};
use blue_lang_syntax::Span;
use serde::Serialize;

/// A position range in one file. Lines and columns are 1-based; columns count
/// characters, not bytes. `byte_start`/`byte_end` are the half-open byte range.
#[derive(Serialize)]
pub struct Location {
    pub file: Option<String>,
    pub line: Option<usize>,
    pub column: Option<usize>,
    pub end_line: Option<usize>,
    pub end_column: Option<usize>,
    pub byte_start: Option<usize>,
    pub byte_end: Option<usize>,
}

impl Location {
    fn of(file: Option<&SourceFile>, span: Span) -> Self {
        let name = file.map(|f| {
            f.path
                .as_ref()
                .map_or_else(|| "<anonymous>".to_string(), |p| p.display().to_string())
        });
        let text = file.map(|f| f.text.as_str());
        match text {
            Some(t) if !span.is_synthetic() && span.end <= t.len() => {
                let (line, column) = Span::line_col(t, span.start);
                let (end_line, end_column) = Span::line_col(t, span.end);
                Self {
                    file: name,
                    line: Some(line),
                    column: Some(column),
                    end_line: Some(end_line),
                    end_column: Some(end_column),
                    byte_start: Some(span.start),
                    byte_end: Some(span.end),
                }
            }
            _ => Self {
                file: name,
                line: None,
                column: None,
                end_line: None,
                end_column: None,
                byte_start: None,
                byte_end: None,
            },
        }
    }
}

#[derive(Serialize)]
pub struct JsonRelated {
    #[serde(flatten)]
    pub at: Location,
    pub message: String,
}

#[derive(Serialize)]
pub struct JsonEdit {
    #[serde(flatten)]
    pub at: Location,
    pub original: String,
    pub replacement: String,
}

#[derive(Serialize)]
pub struct JsonFix {
    pub message: String,
    pub applicability: &'static str,
    pub edits: Vec<JsonEdit>,
}

#[derive(Serialize)]
pub struct JsonWaiver {
    pub reason: String,
    pub line: Option<usize>,
}

/// One line of `blue check --format json`.
#[derive(Serialize)]
pub struct JsonDiagnostic {
    pub code: &'static str,
    pub slug: &'static str,
    pub severity: &'static str,
    pub message: String,
    #[serde(flatten)]
    pub at: Location,
    pub help: Option<String>,
    pub related: Vec<JsonRelated>,
    pub fixes: Vec<JsonFix>,
    /// Set when an in-source waiver suppressed this diagnostic.
    pub waiver: Option<JsonWaiver>,
}

fn file_of(program: &ResolvedProgram, top_level: usize) -> Option<&SourceFile> {
    program.owner_of(top_level).and_then(|id| program.file(id))
}

/// A diagnostic as its JSON object.
#[must_use]
pub fn to_json(
    program: &ResolvedProgram,
    d: &Diagnostic,
    waiver: Option<JsonWaiver>,
) -> JsonDiagnostic {
    let file = file_of(program, d.top_level);
    let rule = d.code.rule();
    JsonDiagnostic {
        code: d.code.as_str(),
        slug: rule.slug,
        severity: d.severity.label(),
        message: d.message.clone(),
        at: Location::of(file, d.span),
        help: d.help.clone(),
        related: d
            .related
            .iter()
            .map(|r| JsonRelated {
                at: Location::of(file, r.span),
                message: r.message.clone(),
            })
            .collect(),
        fixes: d
            .fixes
            .iter()
            .map(|f| JsonFix {
                message: f.message.clone(),
                applicability: f.applicability.label(),
                edits: f
                    .edits
                    .iter()
                    .map(|e| JsonEdit {
                        at: Location::of(file, e.span),
                        original: e.original.clone(),
                        replacement: e.replacement.clone(),
                    })
                    .collect(),
            })
            .collect(),
        waiver,
    }
}

/// Every diagnostic in `outcome` — reported and waived — as JSON Lines.
///
/// # Errors
///
/// Serialisation cannot fail for these types; the `Result` is serde's.
pub fn json_lines(program: &ResolvedProgram, outcome: &Outcome) -> serde_json::Result<String> {
    let mut out = String::new();
    for d in &outcome.diagnostics {
        out.push_str(&serde_json::to_string(&to_json(program, d, None))?);
        out.push('\n');
    }
    for w in &outcome.waived {
        let file = file_of(program, w.waiver.top_level);
        let line = file.map(|f| Span::line_col(&f.text, w.waiver.span.start).0);
        let waiver = JsonWaiver {
            reason: w.waiver.reason.clone(),
            line,
        };
        out.push_str(&serde_json::to_string(&to_json(
            program,
            &w.diagnostic,
            Some(waiver),
        ))?);
        out.push('\n');
    }
    Ok(out)
}

/// A syntax error, which has no resolved program behind it, as JSON.
///
/// # Errors
///
/// As [`json_lines`].
pub fn syntax_json(path: &Path, text: &str, d: &Diagnostic) -> serde_json::Result<String> {
    let file = SourceFile {
        id: ResolvedProgram::ENTRY,
        path: Some(path.to_path_buf()),
        package: None,
        text: text.to_string(),
    };
    let rule = d.code.rule();
    let j = JsonDiagnostic {
        code: d.code.as_str(),
        slug: rule.slug,
        severity: d.severity.label(),
        message: d.message.clone(),
        at: Location::of(Some(&file), d.span),
        help: d.help.clone(),
        related: Vec::new(),
        fixes: Vec::new(),
        waiver: None,
    };
    let mut s = serde_json::to_string(&j)?;
    s.push('\n');
    Ok(s)
}

/// Apply every MACHINE-APPLICABLE fix whose edits land in the entry file:
/// [`blue_lang_check::fixes::apply_machine_fixes`], the one rewrite an
/// editor's "fix all" applies too.
#[must_use]
pub fn apply_machine_fixes(
    program: &ResolvedProgram,
    outcome: &Outcome,
    text: &str,
) -> (String, usize) {
    blue_lang_check::fixes::apply_machine_fixes(
        &outcome.diagnostics,
        &|i| program.owner_of(i) == Some(ResolvedProgram::ENTRY),
        text,
    )
}

// ---- `blue ast --resolved --json` -------------------------------------------

/// What one reference binds to, as `ast --resolved --json` prints it.
#[derive(Serialize)]
struct TargetJson {
    /// `local`, `def`, `builtin` or `unbound`.
    kind: &'static str,
    /// The defining bidama for a `def`; `null` for the root namespace and
    /// every other kind.
    namespace: Option<String>,
    name: Option<String>,
    /// The symbol the resolved tree writes: `retsu/first`, `count`.
    key: Option<String>,
}

fn target_json(t: &blue_lang_check::names::Target) -> TargetJson {
    use blue_lang_check::names::Target;
    use blue_lang_check::Namespace;
    let key = t.resolved_symbol();
    match t {
        Target::Local => TargetJson {
            kind: "local",
            namespace: None,
            name: None,
            key,
        },
        Target::Def(ns, n) => TargetJson {
            kind: "def",
            namespace: match ns {
                Namespace::Bidama(p) => Some(p.clone()),
                _ => None,
            },
            name: Some(n.clone()),
            key,
        },
        Target::Builtin(n) => TargetJson {
            kind: "builtin",
            namespace: None,
            name: Some(n.clone()),
            key,
        },
        Target::Ambiguous(_) => TargetJson {
            kind: "ambiguous",
            namespace: None,
            name: None,
            key,
        },
        Target::Unbound => TargetJson {
            kind: "unbound",
            namespace: None,
            name: None,
            key,
        },
    }
}

#[derive(Serialize)]
struct ReferenceJson {
    #[serde(flatten)]
    at: Location,
    top_level: usize,
    written: String,
    opaque: bool,
    flat: TargetJson,
    ns: TargetJson,
    /// The locals in scope where it is written, innermost first.
    locals: Vec<String>,
}

#[derive(Serialize)]
struct ImportJson {
    #[serde(flatten)]
    at: Location,
    package: String,
    /// The names listed for bare use; empty for a whole-package `use`.
    names: Vec<String>,
}

#[derive(Serialize)]
struct ResolvedJson {
    /// The entry file's bidama, or `null` for the root namespace.
    namespace: Option<String>,
    /// The entry file's top-level forms, resolved under the flat rule.
    flat: Vec<String>,
    /// The same forms under per-bidama namespaces.
    ns: Vec<String>,
    /// Every non-local reference in the entry file.
    references: Vec<ReferenceJson>,
    /// The entry file's `use` declarations.
    imports: Vec<ImportJson>,
    /// The first line of the entry file's first top-level form, `null` for
    /// a file with none: where a first `use` goes.
    first_line: Option<usize>,
    /// The entry file's top-level definitions: name and where the name is.
    definitions: Vec<DefinitionJson>,
    /// Every name the interpreter binds, sorted: what a bare name falls to.
    builtins: Vec<String>,
    /// The reserved words, which no definition can be named.
    reserved: Vec<&'static str>,
}

#[derive(Serialize)]
struct DefinitionJson {
    #[serde(flatten)]
    at: Location,
    name: String,
}

/// The entry file's resolution, as one JSON object.
///
/// # Errors
///
/// Serialization only.
pub fn resolved_json(
    checked: &blue_lang_runtime::pipeline::Checked,
    resolved: &blue_lang_check::names::Resolved,
) -> Result<String, serde_json::Error> {
    use blue_lang_check::names::Rule;
    let program = &checked.program;
    let entry = |i: usize| program.owner_of(i) == Some(ResolvedProgram::ENTRY);
    let tree = |rule| -> Vec<String> {
        resolved
            .resolved_tree(program.forms(), rule)
            .iter()
            .enumerate()
            .filter(|(i, _)| entry(*i))
            .map(|(_, f)| f.to_sexp().to_string())
            .collect()
    };
    let file = program.file(ResolvedProgram::ENTRY);
    let out = ResolvedJson {
        namespace: file.and_then(|f| f.package.clone()),
        flat: tree(Rule::Flat),
        ns: tree(Rule::Namespaced),
        references: resolved
            .references
            .iter()
            .filter(|r| entry(r.top_level))
            .map(|r| ReferenceJson {
                at: Location::of(file, r.span),
                top_level: r.top_level,
                written: r.written.clone(),
                opaque: r.opaque,
                flat: target_json(&r.flat),
                ns: target_json(&r.ns),
                locals: r.locals.clone(),
            })
            .collect(),
        imports: program
            .imports()
            .iter()
            .filter(|(f, _)| *f == ResolvedProgram::ENTRY)
            .map(|(_, u)| ImportJson {
                at: Location::of(file, u.span),
                package: u.package.clone(),
                names: u.names.iter().map(|(n, _)| n.clone()).collect(),
            })
            .collect(),
        first_line: program
            .forms()
            .iter()
            .enumerate()
            .find(|(i, _)| entry(*i))
            .and_then(|(_, f)| Location::of(file, f.span).line),
        definitions: program
            .forms()
            .iter()
            .enumerate()
            .filter(|(i, _)| entry(*i))
            .flat_map(|(_, f)| blue_lang_check::names::definitions_of(f))
            .map(|(name, span, _)| DefinitionJson {
                at: Location::of(file, span),
                name,
            })
            .collect(),
        builtins: {
            let mut b: Vec<String> = checked
                .names
                .scopes()
                .iter()
                .filter(|s| {
                    !matches!(
                        s.namespace,
                        blue_lang_check::Namespace::File(_) | blue_lang_check::Namespace::Bidama(_)
                    )
                })
                .flat_map(|s| s.bindings().map(|b| b.name.clone()))
                .collect();
            b.sort();
            b.dedup();
            b
        },
        reserved: blue_lang_syntax::SURFACE_KEYWORDS
            .iter()
            .chain(blue_lang_syntax::BLOCK_KEYWORDS)
            .copied()
            .collect(),
    };
    serde_json::to_string(&out)
}

// ---- cross-tier overrides ----------------------------------------------------

fn tier_word(t: blue_lang_check::names::Tier) -> &'static str {
    use blue_lang_check::names::Tier;
    match t {
        Tier::Local => "local",
        Tier::Own => "own",
        Tier::Imported => "imported",
        Tier::Builtin => "builtin",
    }
}

fn namespace_word(n: &blue_lang_check::Namespace) -> String {
    use blue_lang_check::Namespace;
    match n {
        Namespace::Bidama(p) => p.clone(),
        Namespace::File(_) => "this file".to_string(),
        other => other.to_string(),
    }
}

#[derive(Serialize)]
struct ShadowedJson {
    tier: &'static str,
    namespace: String,
}

#[derive(Serialize)]
struct OverrideJson {
    kind: &'static str,
    name: String,
    #[serde(flatten)]
    at: Location,
    tier: &'static str,
    namespace: String,
    shadowed: Vec<ShadowedJson>,
}

/// One JSON line per cross-tier override in the entry file: a bare name the
/// resolution order bound in a higher tier while a lower tier also had it.
/// Not a diagnostic — each tier is something the author wrote — and recorded
/// so a tool can see every place the order decided.
///
/// # Errors
///
/// Serialization only.
pub fn overrides_json(
    checked: &blue_lang_runtime::pipeline::Checked,
    resolved: &blue_lang_check::names::Resolved,
) -> Result<String, serde_json::Error> {
    use blue_lang_check::names::Target;
    let program = &checked.program;
    let file = program.file(ResolvedProgram::ENTRY);
    let mut out = String::new();
    let mut seen = std::collections::BTreeSet::new();
    for r in &resolved.references {
        if r.shadowed.is_empty() || program.owner_of(r.top_level) != Some(ResolvedProgram::ENTRY) {
            continue;
        }
        if !seen.insert((r.span.start, r.span.end, r.written.clone())) {
            continue;
        }
        let Target::Def(ns, _) = &r.ns else { continue };
        let (tier, namespace) = (tier_of_winner(checked, r), namespace_word(ns));
        let line = OverrideJson {
            kind: "override",
            name: r.written.clone(),
            at: Location::of(file, r.span),
            tier,
            namespace,
            shadowed: r
                .shadowed
                .iter()
                .map(|(t, n)| ShadowedJson {
                    tier: tier_word(*t),
                    namespace: namespace_word(n),
                })
                .collect(),
        };
        out.push_str(&serde_json::to_string(&line)?);
        out.push('\n');
    }
    Ok(out)
}

/// The tier a reference's namespaced binding came from: the first non-empty
/// tier of its resolution path.
fn tier_of_winner(
    checked: &blue_lang_runtime::pipeline::Checked,
    r: &blue_lang_check::names::Reference,
) -> &'static str {
    let own = blue_lang_runtime::pipeline::namespace_of(&checked.program, r.top_level);
    checked
        .names
        .tiers_of(&r.written, &own, r.top_level)
        .into_iter()
        .find(|(_, nss)| !nss.is_empty())
        .map_or("builtin", |(t, _)| tier_word(t))
}
