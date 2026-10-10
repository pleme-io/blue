//! `completions(file, pos)`: every name a reference at the cursor could
//! resolve to, ranked by the locked resolution order (`RESOLUTION_ORDER`):
//! locals innermost first, the file's own definitions, the names its `use`
//! forms list, builtins — then names it could reach with one more `use`,
//! each carrying the edit that adds it.

use std::collections::BTreeSet;

use blue_lang_check::{NameTable, Namespace, ScopeKind};
use blue_lang_syntax::Span;

use crate::{Analysis, Engine, ItemKind};

/// A completion's rank: the tier that would resolve it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Tier {
    Local,
    Own,
    Imported,
    Builtin,
    /// Not reachable yet: one `use` away.
    Reachable,
}

impl Tier {
    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Tier::Local => "local",
            Tier::Own => "own",
            Tier::Imported => "imported",
            Tier::Builtin => "builtin",
            Tier::Reachable => "needs a use",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CompletionKind {
    Function,
    Value,
    Keyword,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Completion {
    pub label: String,
    /// What to insert, when it is not the label (`kueri::join`).
    pub insert: Option<String>,
    pub tier: Tier,
    /// Where it lives: `this file`, `bidama \`retsu\``, `builtin`.
    pub namespace: String,
    pub kind: CompletionKind,
    pub signature: Option<String>,
    pub doc: Option<String>,
    /// A second edit the completion needs, applied with it: the `use` that
    /// makes a reachable name resolve.
    pub edit: Option<(Span, String)>,
}

/// The identifier being typed before `offset`, and any `pkg::` before it.
fn prefix_at(text: &str, offset: usize) -> (Option<String>, String) {
    let offset = offset.min(text.len());
    let word = |c: char| c.is_alphanumeric() || c == '_' || c == '?' || c == '!';
    let before = &text[..offset];
    let start = before
        .char_indices()
        .rev()
        .take_while(|(_, c)| word(*c))
        .last()
        .map_or(offset, |(i, _)| i);
    let prefix = before[start..].to_string();
    let qualifier = before[..start].strip_suffix("::").map(|q| {
        let qs = q
            .char_indices()
            .rev()
            .take_while(|(_, c)| word(*c))
            .last()
            .map_or(q.len(), |(i, _)| i);
        q[qs..].to_string()
    });
    (qualifier.filter(|q| !q.is_empty()), prefix)
}

fn spellable(name: &str) -> bool {
    name.chars()
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
        && !name.contains('-')
        && !name.contains('/')
}

impl Engine {
    /// The completions at byte `offset` of document `id`.
    #[must_use]
    pub fn completions(&self, id: &str, offset: usize) -> Vec<Completion> {
        let Some(current) = self.analysis(id) else {
            return Vec::new();
        };
        let (qualifier, prefix) = prefix_at(&current.text, offset);
        let good = self.last_good(id);
        let mut out = Vec::new();
        if let Some(q) = qualifier {
            self.qualified(&current, good.as_deref(), &q, &mut |c| {
                if c.label.starts_with(&prefix) {
                    out.push(c);
                }
            });
            return finish(out);
        }
        let mut taken = BTreeSet::new();
        if current.parsed.is_ok() {
            for b in current.locals(self).in_scope(offset) {
                if b.name.starts_with(&prefix) && taken.insert(b.name.clone()) {
                    out.push(Completion {
                        label: b.name.clone(),
                        insert: None,
                        tier: Tier::Local,
                        namespace: "local".to_string(),
                        kind: CompletionKind::Value,
                        signature: None,
                        doc: None,
                        edit: None,
                    });
                }
            }
        }
        let source = good.as_deref().unwrap_or(&current);
        let mut shadowing = taken.clone();
        for c in self.resolvable(source, &prefix) {
            if c.tier == Tier::Own {
                shadowing.insert(c.label.clone());
            }
            if taken.insert(c.label.clone()) {
                out.push(c);
            }
        }
        if !prefix.is_empty() {
            for c in self.reachable(source, &prefix) {
                if !shadowing.contains(&c.label) {
                    out.push(c);
                }
            }
        }
        finish(out)
    }

    /// Own definitions, listed imports and builtins, in that order.
    fn resolvable(&self, a: &Analysis, prefix: &str) -> Vec<Completion> {
        let own = a.own_namespace();
        let table: &NameTable = a.checked().map_or(self.builtins(), |c| &c.names);
        let mut out = Vec::new();
        let doc_of = |ns: &Namespace, name: &str| -> (Option<String>, Option<String>) {
            match ns {
                Namespace::Builtin | Namespace::Macro | Namespace::SpecialForm => {
                    match blue_lang_runtime::docs::doc_of(name) {
                        Some(d) => (Some(d.signature.to_string()), Some(d.doc.to_string())),
                        None => (None, None),
                    }
                }
                _ => match a.definition_of(self, ns, name) {
                    Some(l) => self
                        .item_at(a, &l)
                        .map_or((None, None), |i| (Some(i.signature), i.doc)),
                    None => (None, None),
                },
            }
        };
        let own_scope = table.scopes().iter().find(|s| s.namespace == own);
        if let Some(scope) = own_scope {
            for b in scope.bindings() {
                if !spellable(&b.name) || !b.name.starts_with(prefix) {
                    continue;
                }
                let (signature, doc) = doc_of(&own, &b.name);
                out.push(Completion {
                    label: b.name.clone(),
                    insert: None,
                    tier: Tier::Own,
                    namespace: own.to_string(),
                    kind: kind_of(b.kind, signature.as_deref()),
                    signature,
                    doc,
                    edit: None,
                });
            }
        }
        for import in a.imports() {
            let ns = Namespace::Bidama(import.package.clone());
            for (name, _) in &import.names {
                let defined = table
                    .bidama(&import.package)
                    .is_some_and(|s| s.get(name).is_some());
                if !defined || !name.starts_with(prefix) {
                    continue;
                }
                let (signature, doc) = doc_of(&ns, name);
                out.push(Completion {
                    label: name.clone(),
                    insert: None,
                    tier: Tier::Imported,
                    namespace: ns.to_string(),
                    kind: kind_of(ScopeKind::Value, signature.as_deref()),
                    signature,
                    doc,
                    edit: None,
                });
            }
        }
        for scope in table.scopes() {
            if !matches!(
                scope.namespace,
                Namespace::Harness | Namespace::SpecialForm | Namespace::Macro | Namespace::Builtin
            ) {
                continue;
            }
            for b in scope.bindings() {
                if !spellable(&b.name) || !b.name.starts_with(prefix) {
                    continue;
                }
                let (signature, doc) = doc_of(&scope.namespace, &b.name);
                out.push(Completion {
                    label: b.name.clone(),
                    insert: None,
                    tier: Tier::Builtin,
                    namespace: scope.namespace.to_string(),
                    kind: match (scope.namespace.clone(), b.kind) {
                        (_, ScopeKind::SpecialForm | ScopeKind::Macro) => CompletionKind::Keyword,
                        _ => CompletionKind::Function,
                    },
                    signature,
                    doc,
                    edit: None,
                });
            }
        }
        out
    }

    /// Definitions of every bidama on the load path the file does not list,
    /// each with the edit that reaches it.
    fn reachable(&self, a: &Analysis, prefix: &str) -> Vec<Completion> {
        let imports = a.imports();
        let own = a.own_namespace();
        let mut out = Vec::new();
        for pkg in self.available() {
            if own == Namespace::Bidama(pkg.clone()) {
                continue;
            }
            let import = imports.iter().find(|i| i.package == pkg);
            let Ok(package) = self.package(&pkg) else {
                continue;
            };
            for (_, text) in &package.files {
                for item in self.memo.items(text).iter().cloned() {
                    if !matches!(
                        item.kind,
                        ItemKind::Function | ItemKind::Value | ItemKind::Macro
                    ) || !spellable(&item.name)
                        || !item.name.starts_with(prefix)
                    {
                        continue;
                    }
                    if import.is_some_and(|i| i.names.iter().any(|(n, _)| *n == item.name)) {
                        continue;
                    }
                    let (insert, edit) = match import {
                        Some(i) if i.listed => (None, list_edit(a, i, &item.name)),
                        Some(_) => (Some(format!("{pkg}::{}", item.name)), None),
                        None => (None, Some(use_edit(a, &imports, &pkg, &item.name))),
                    };
                    out.push(Completion {
                        label: item.name.clone(),
                        insert,
                        tier: Tier::Reachable,
                        namespace: Namespace::Bidama(pkg.clone()).to_string(),
                        kind: if item.kind == ItemKind::Function {
                            CompletionKind::Function
                        } else {
                            CompletionKind::Value
                        },
                        signature: Some(item.signature),
                        doc: item.doc,
                        edit,
                    });
                }
            }
        }
        out
    }

    /// After `pkg::`: that bidama's definitions.
    fn qualified(
        &self,
        current: &Analysis,
        good: Option<&Analysis>,
        pkg: &str,
        push: &mut dyn FnMut(Completion),
    ) {
        if pkg == blue_lang_syntax::BUILTIN_QUALIFIER {
            let a = good.unwrap_or(current);
            for c in self
                .resolvable(a, "")
                .into_iter()
                .filter(|c| c.tier == Tier::Builtin)
            {
                push(c);
            }
            return;
        }
        let Ok(package) = self.package(pkg) else {
            return;
        };
        let a = good.unwrap_or(current);
        let imports = a.imports();
        let used = imports.iter().any(|i| i.package == pkg)
            || a.own_namespace() == Namespace::Bidama(pkg.to_string());
        for (_, text) in &package.files {
            for item in self.memo.items(text).iter().cloned() {
                if !matches!(
                    item.kind,
                    ItemKind::Function | ItemKind::Value | ItemKind::Macro
                ) || !spellable(&item.name)
                {
                    continue;
                }
                push(Completion {
                    label: item.name.clone(),
                    insert: None,
                    tier: if used {
                        Tier::Imported
                    } else {
                        Tier::Reachable
                    },
                    namespace: Namespace::Bidama(pkg.to_string()).to_string(),
                    kind: if item.kind == ItemKind::Function {
                        CompletionKind::Function
                    } else {
                        CompletionKind::Value
                    },
                    signature: Some(item.signature),
                    doc: item.doc,
                    edit: (!used).then(|| {
                        let (span, text) = use_edit(a, &imports, pkg, "");
                        (span, text)
                    }),
                });
            }
        }
    }

    /// The item a definition location names, in whichever file holds it.
    #[must_use]
    pub fn item_at(&self, a: &Analysis, l: &crate::Located) -> Option<crate::Item> {
        let inside = |i: &crate::Item| {
            i.name_span == l.span || (i.span.start <= l.span.start && l.span.end <= i.span.end)
        };
        if matches!(&l.file, crate::FileRef::Document(id) if a.id.as_deref() == Some(id.as_str())) {
            return a.items().iter().find(|i| inside(i)).cloned();
        }
        let text = match &l.file {
            crate::FileRef::Document(id) => self.document_text(id)?.to_string(),
            crate::FileRef::Path(_) => a.file_text(&l.file)?.to_string(),
        };
        self.memo.items(&text).iter().find(|i| inside(i)).cloned()
    }
}

fn kind_of(kind: ScopeKind, signature: Option<&str>) -> CompletionKind {
    match kind {
        ScopeKind::SpecialForm | ScopeKind::Macro => CompletionKind::Keyword,
        ScopeKind::Value if signature.is_some_and(|s| s.starts_with("def ")) => {
            CompletionKind::Function
        }
        ScopeKind::Value => CompletionKind::Value,
    }
}

fn finish(mut out: Vec<Completion>) -> Vec<Completion> {
    out.sort_by(|a, b| (a.tier, &a.label).cmp(&(b.tier, &b.label)));
    out
}

/// Add `:name` to the list of an existing `use("pkg", [...])`, where the
/// list's sorted order puts it (B0015).
fn list_edit(
    a: &Analysis,
    import: &blue_lang_syntax::scope::Import,
    name: &str,
) -> Option<(Span, String)> {
    if let Some((_, at)) = import.names.iter().find(|(n, _)| n.as_str() > name) {
        return Some((Span::new(at.start, at.start), format!(":{name}, ")));
    }
    let form = &a.text[import.span.start..import.span.end];
    let close = form.rfind(']')?;
    let at = import.span.start + close;
    let text = if import.names.is_empty() {
        format!(":{name}")
    } else {
        format!(", :{name}")
    };
    Some((Span::new(at, at), text))
}

/// A new `use("pkg", [:name])` line, among the file's `use` forms in sorted
/// order, or at the top with a blank line after it when it has none.
fn use_edit(
    a: &Analysis,
    imports: &[blue_lang_syntax::scope::Import],
    pkg: &str,
    name: &str,
) -> (Span, String) {
    let line = if name.is_empty() {
        format!("use(\"{pkg}\")\n")
    } else {
        format!("use(\"{pkg}\", [:{name}])\n")
    };
    if let Some(after) = imports.iter().find(|i| i.package.as_str() > pkg) {
        let at = a.text[..after.span.start].rfind('\n').map_or(0, |n| n + 1);
        return (Span::new(at, at), line);
    }
    match imports.last() {
        Some(last) => {
            let at = a.text[last.span.end..]
                .find('\n')
                .map_or(a.text.len(), |n| last.span.end + n + 1);
            let line = if at == a.text.len() && !a.text.ends_with('\n') {
                format!("\n{}", line.trim_end())
            } else {
                line
            };
            (Span::new(at, at), line)
        }
        None => (Span::new(0, 0), format!("{line}\n")),
    }
}
