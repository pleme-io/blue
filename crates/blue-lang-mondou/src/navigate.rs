//! Where a name is defined, where it is used, and renaming it: all read off
//! the check stage's resolution (`Resolved`, `NameTable`) for top-level
//! names and off [`Locals`](crate::Locals) below them.

use std::collections::BTreeMap;
use std::rc::Rc;

use blue_lang_check::names::Target;
use blue_lang_check::Namespace;
use blue_lang_runtime::uses::ResolvedProgram;
use blue_lang_syntax::Span;

use crate::{name_span, Analysis, Engine, FileRef};

/// What a name at a position is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Symbol {
    /// A local binding of this document, by its index in [`crate::Locals`].
    Local(usize),
    /// A program definition: its namespace and name.
    Def(Namespace, String),
    /// A name the interpreter binds.
    Builtin(String),
    /// A bidama, named by a `use`.
    Package(String),
}

/// A span in a file.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Located {
    pub file: FileRef,
    pub span: Span,
}

/// Why a rename was refused.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Refusal {
    /// Nothing renameable is at the position.
    NothingHere,
    /// A builtin, or a definition in a file that is not open.
    NotOurs(String),
    /// The new name is not a name blue can spell.
    BadName(String),
    /// After the rename, a reference would mean something else.
    ChangesMeaning(String),
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Refusal::NothingHere => f.write_str("no name to rename here"),
            Refusal::NotOurs(why) | Refusal::BadName(why) | Refusal::ChangesMeaning(why) => {
                f.write_str(why)
            }
        }
    }
}

impl Analysis {
    /// The name at byte `offset`, and the span that names it.
    #[must_use]
    pub fn symbol_at(&self, engine: &Engine, offset: usize) -> Option<(Symbol, Span)> {
        if let Some((b, span)) = self.locals(engine).at(offset) {
            return Some((Symbol::Local(b), span));
        }
        let within = |s: Span| s.start <= offset && offset <= s.end;
        if let (Some(c), Some(r)) = (self.checked(), self.resolved()) {
            let hit = r
                .references
                .iter()
                .filter(|r| c.program.owner_of(r.top_level) == Some(ResolvedProgram::ENTRY))
                .filter(|r| within(r.span) && spelled_as_a_name(&r.written))
                .min_by_key(|r| r.span.end - r.span.start);
            if let Some(r) = hit {
                let span = name_span(&self.text, r.span, &r.written);
                return match &r.ns {
                    Target::Def(ns, name) => Some((Symbol::Def(ns.clone(), name.clone()), span)),
                    Target::Builtin(name) => Some((Symbol::Builtin(name.clone()), span)),
                    _ => None,
                };
            }
        }
        let own = self.own_namespace();
        for (_, form) in self.entry_forms() {
            if !within(form.span) {
                continue;
            }
            let mut found = None;
            blue_lang_syntax::scope::definition_nodes(form, &mut |node, _| {
                if within(node.span) {
                    if let Some(n) = node.as_symbol() {
                        found = Some((Symbol::Def(own.clone(), n.to_string()), node.span));
                    }
                }
            });
            if found.is_some() {
                return found;
            }
            if let Some(import) = blue_lang_syntax::scope::use_target(form) {
                if within(import.package_span) {
                    return Some((Symbol::Package(import.package), import.package_span));
                }
                for (n, s) in &import.names {
                    if within(*s) {
                        let span = Span::new(s.end - n.len(), s.end);
                        return Some((
                            Symbol::Def(Namespace::Bidama(import.package.clone()), n.clone()),
                            span,
                        ));
                    }
                }
            }
        }
        None
    }

    /// What a bare or qualified `name` written at the top of this document
    /// would resolve to.
    #[must_use]
    pub fn resolve_name(&self, name: &str) -> Option<Symbol> {
        let c = self.checked()?;
        let at = (0..c.program.forms().len())
            .find(|i| c.program.owner_of(*i) == Some(ResolvedProgram::ENTRY))
            .unwrap_or(0);
        match c.names.ns_target(name, &self.own_namespace(), at) {
            Target::Def(ns, n) => Some(Symbol::Def(ns, n)),
            Target::Builtin(n) => Some(Symbol::Builtin(n)),
            _ => None,
        }
    }

    /// Where a definition `ns`/`name` is, in this program.
    #[must_use]
    pub fn definition_of(&self, engine: &Engine, ns: &Namespace, name: &str) -> Option<Located> {
        let c = self.checked()?;
        let scope = c.names.scopes().iter().find(|s| &s.namespace == ns)?;
        let binding = scope.get(name)?;
        let span = binding.span?;
        let file = self.file_of(engine, binding.top_level?)?;
        Some(Located { file, span })
    }

    /// Where the name at `offset` is defined.
    #[must_use]
    pub fn definition(&self, engine: &Engine, offset: usize) -> Vec<Located> {
        let Some((symbol, _)) = self.symbol_at(engine, offset) else {
            return Vec::new();
        };
        match symbol {
            Symbol::Local(b) => vec![Located {
                file: self.self_ref(),
                span: self.locals(engine).bindings[b].span,
            }],
            Symbol::Def(ns, name) => self.definition_of(engine, &ns, &name).into_iter().collect(),
            Symbol::Builtin(_) => Vec::new(),
            Symbol::Package(p) => self
                .checked()
                .into_iter()
                .flat_map(|c| c.program.files())
                .filter(|f| {
                    f.package.as_deref() == Some(p.as_str()) && f.id != ResolvedProgram::ENTRY
                })
                .filter_map(|f| f.path.clone())
                .take(1)
                .map(|path| Located {
                    file: engine.file_ref(&path),
                    span: Span::new(0, 0),
                })
                .collect(),
        }
    }

    fn self_ref(&self) -> FileRef {
        match &self.id {
            Some(id) => FileRef::Document(id.clone()),
            None => FileRef::Path(self.path.clone().unwrap_or_default()),
        }
    }

    /// Every place this program names definition `ns`/`name`: each
    /// reference, and with `declarations` each definition site.
    fn uses_of(
        &self,
        engine: &Engine,
        ns: &Namespace,
        name: &str,
        declarations: bool,
    ) -> Vec<(Located, String)> {
        let (Some(c), Some(r)) = (self.checked(), self.resolved()) else {
            return Vec::new();
        };
        let want = Target::Def(ns.clone(), name.to_string());
        let mut out = Vec::new();
        let mut texts: BTreeMap<FileRef, Option<String>> = BTreeMap::new();
        for reference in r.references.iter().filter(|r| r.ns == want) {
            let Some(file) = self.file_of(engine, reference.top_level) else {
                continue;
            };
            let text = texts
                .entry(file.clone())
                .or_insert_with(|| self.text_of_form(reference.top_level));
            let span = text.as_deref().map_or(reference.span, |t| {
                name_span(t, reference.span, &reference.written)
            });
            out.push((Located { file, span }, reference.written.clone()));
        }
        for (i, form) in c.program.forms().iter().enumerate() {
            if let Some(import) = blue_lang_syntax::scope::use_target(form) {
                if ns == &Namespace::Bidama(import.package.clone()) {
                    for (n, s) in &import.names {
                        if n == name {
                            if let Some(file) = self.file_of(engine, i) {
                                let span = Span::new(s.end - n.len(), s.end);
                                out.push((Located { file, span }, n.clone()));
                            }
                        }
                    }
                }
            }
            if !declarations || &blue_lang_runtime::pipeline::namespace_of(&c.program, i) != ns {
                continue;
            }
            blue_lang_syntax::scope::definition_nodes(form, &mut |node, _| {
                if node.as_symbol() == Some(name) {
                    if let Some(file) = self.file_of(engine, i) {
                        out.push((
                            Located {
                                file,
                                span: node.span,
                            },
                            name.to_string(),
                        ));
                    }
                }
            });
        }
        out
    }

    fn text_of_form(&self, top_level: usize) -> Option<String> {
        let c = self.checked()?;
        let id = c.program.owner_of(top_level)?;
        c.program.file(id).map(|f| f.text.clone())
    }
}

impl Engine {
    /// Every place the name at `offset` of document `id` is used, across the
    /// open documents and every file their programs loaded.
    #[must_use]
    pub fn references(&self, id: &str, offset: usize, declarations: bool) -> Vec<Located> {
        let Some(a) = self.analysis(id) else {
            return Vec::new();
        };
        let Some((symbol, _)) = a.symbol_at(self, offset) else {
            return Vec::new();
        };
        let mut out: Vec<Located> = match symbol {
            Symbol::Local(b) => {
                let binding = &a.locals(self).bindings[b];
                binding
                    .occurrences
                    .iter()
                    .filter(|s| declarations || **s != binding.span)
                    .map(|s| Located {
                        file: FileRef::Document(id.to_string()),
                        span: *s,
                    })
                    .collect()
            }
            Symbol::Def(ns, name) => self
                .analyses_of_open_documents()
                .iter()
                .flat_map(|x| x.uses_of(self, &ns, &name, declarations))
                .map(|(l, _)| l)
                .collect(),
            Symbol::Builtin(_) | Symbol::Package(_) => Vec::new(),
        };
        out.sort_by_key(|l| (l.file.clone(), l.span.start, l.span.end));
        out.dedup();
        out
    }

    /// The span a rename at `offset` would rewrite, and the name there now.
    ///
    /// # Errors
    ///
    /// A [`Refusal`] when nothing there can be renamed.
    pub fn prepare_rename(&self, id: &str, offset: usize) -> Result<(Span, String), Refusal> {
        let a = self.analysis(id).ok_or(Refusal::NothingHere)?;
        let (symbol, span) = a.symbol_at(self, offset).ok_or(Refusal::NothingHere)?;
        self.renameable(&a, &symbol)?;
        Ok((span, a.text[span.start..span.end].to_string()))
    }

    fn renameable(&self, a: &Analysis, symbol: &Symbol) -> Result<(), Refusal> {
        match symbol {
            Symbol::Local(_) => Ok(()),
            Symbol::Builtin(n) => Err(Refusal::NotOurs(format!(
                "`{n}` is a builtin: the interpreter defines it, not this program"
            ))),
            Symbol::Package(p) => Err(Refusal::NotOurs(format!(
                "`{p}` names a bidama; rename its directory and Bluefile instead"
            ))),
            Symbol::Def(ns, name) => match a.definition_of(self, ns, name) {
                Some(Located {
                    file: FileRef::Document(_),
                    ..
                }) => Ok(()),
                Some(Located {
                    file: FileRef::Path(p),
                    ..
                }) => Err(Refusal::NotOurs(format!(
                    "`{name}` is defined in {}, which is not open: its other callers cannot be seen from here",
                    p.display()
                ))),
                None => Err(Refusal::NotOurs(format!("`{name}` has no definition to rename"))),
            },
        }
    }

    /// Rename the name at `offset` of document `id` to `new_name`: the edits,
    /// per open document.
    ///
    /// **Refused when it would change what any reference means.** Every
    /// affected document is re-analysed with the edits applied, and each
    /// reference must then resolve to what it resolved to before (the
    /// renamed definition under its new name, everything else unchanged). A
    /// local named like the new name, a builtin the new name would hide, or a
    /// second definition the new name collides with each turn some reference
    /// into another binding, and the rename is refused naming it.
    ///
    /// # Errors
    ///
    /// A [`Refusal`] saying why.
    pub fn rename(
        &self,
        id: &str,
        offset: usize,
        new_name: &str,
    ) -> Result<BTreeMap<String, Vec<(Span, String)>>, Refusal> {
        let a = self.analysis(id).ok_or(Refusal::NothingHere)?;
        let (symbol, _) = a.symbol_at(self, offset).ok_or(Refusal::NothingHere)?;
        self.renameable(&a, &symbol)?;
        let spellable = new_name
            .chars()
            .next()
            .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
            && new_name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '?' || c == '!')
            && !blue_lang_syntax::is_reserved_word(new_name);
        if !spellable {
            return Err(Refusal::BadName(format!(
                "`{new_name}` is not a name blue can spell as a definition"
            )));
        }
        let mut edits: BTreeMap<String, Vec<(Span, String)>> = BTreeMap::new();
        match &symbol {
            Symbol::Local(b) => {
                let binding = &a.locals(self).bindings[*b];
                edits.insert(
                    id.to_string(),
                    binding
                        .occurrences
                        .iter()
                        .map(|s| (*s, new_name.to_string()))
                        .collect(),
                );
            }
            Symbol::Def(ns, name) => {
                for x in self.analyses_of_open_documents() {
                    for (l, _) in x.uses_of(self, ns, name, true) {
                        if let FileRef::Document(doc) = l.file {
                            let text = self.document_text(&doc).unwrap_or_default();
                            if text.get(l.span.start..l.span.end) != Some(name.as_str()) {
                                return Err(Refusal::ChangesMeaning(format!(
                                    "a reference to `{name}` is spelled `{}` (a legacy alias); rename it by hand",
                                    text.get(l.span.start..l.span.end).unwrap_or("?")
                                )));
                            }
                            edits
                                .entry(doc)
                                .or_default()
                                .push((l.span, new_name.to_string()));
                        }
                    }
                }
            }
            Symbol::Builtin(_) | Symbol::Package(_) => return Err(Refusal::NothingHere),
        }
        for list in edits.values_mut() {
            list.sort_by_key(|(s, _)| s.start);
            list.dedup();
        }
        let mut befores = Vec::new();
        let mut texts = Vec::new();
        for (doc, list) in &edits {
            let before = self.analysis(doc).ok_or(Refusal::NothingHere)?;
            let mut text = before.text.to_string();
            for (span, replacement) in list.iter().rev() {
                text.replace_range(span.start..span.end, replacement);
            }
            if let Some(path) = &before.path {
                texts.push((path.clone(), Rc::from(text.as_str())));
            }
            befores.push((before, list, text));
        }
        self.with_overlay(&texts, || {
            for (before, list, text) in &befores {
                self.verify(before, text, &symbol, list, new_name)?;
            }
            Ok(())
        })?;
        Ok(edits)
    }

    /// Re-analyse a document as `text`, its `edits` applied (and every other
    /// edited document overlaid), and compare every reference of its own file
    /// with what it meant before.
    fn verify(
        &self,
        before: &Analysis,
        text: &str,
        symbol: &Symbol,
        edits: &[(Span, String)],
        new_name: &str,
    ) -> Result<(), Refusal> {
        let shift = |at: usize| -> usize {
            let mut delta: isize = 0;
            for (span, replacement) in edits {
                if span.end <= at {
                    delta += replacement.len() as isize - (span.end - span.start) as isize;
                }
            }
            (at as isize + delta) as usize
        };
        let after = self.analyse_text(before.path.clone(), text);
        if !matches!(after.checked, Some(Ok(_))) {
            return Err(Refusal::ChangesMeaning(format!(
                "renaming to `{new_name}` leaves the file without a program to check"
            )));
        }
        let renamed_def = |t: &Target| match (symbol, t) {
            (Symbol::Def(ns, name), Target::Def(tns, tname)) => ns == tns && name == tname,
            _ => false,
        };
        let meaning = |a: &Analysis| -> BTreeMap<usize, Meaning> {
            let mut m = BTreeMap::new();
            if let (Some(c), Some(r)) = (a.checked(), a.resolved()) {
                for reference in &r.references {
                    if c.program.owner_of(reference.top_level) == Some(ResolvedProgram::ENTRY) {
                        m.insert(reference.span.start, Meaning::Target(reference.ns.clone()));
                    }
                }
            }
            for b in &a.locals(self).bindings {
                for s in &b.occurrences {
                    m.insert(s.start, Meaning::Local(b.span.start));
                }
            }
            m
        };
        let old = meaning(before);
        let new = meaning(&after);
        for (at, was) in &old {
            let expected = match (was, symbol) {
                (Meaning::Target(t), _) if renamed_def(t) => match t {
                    Target::Def(ns, _) => {
                        Meaning::Target(Target::Def(ns.clone(), new_name.to_string()))
                    }
                    _ => was.clone(),
                },
                (Meaning::Local(b), _) => Meaning::Local(shift(*b)),
                _ => was.clone(),
            };
            let now = new.get(&shift(*at)).cloned();
            if now.as_ref() != Some(&expected) {
                let written: String = before.text[*at..]
                    .chars()
                    .take_while(|c| c.is_alphanumeric() || "_?!:".contains(*c))
                    .collect();
                let line = before.text[..*at].matches('\n').count() + 1;
                return Err(Refusal::ChangesMeaning(format!(
                    "renaming to `{new_name}` would change what `{written}` on line {line} means: {} now, {} after",
                    describe(Some(was), before, self),
                    describe(now.as_ref(), &after, self),
                )));
            }
        }
        Ok(())
    }
}

/// One definition a workspace-wide search found.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WorkspaceSymbol {
    pub item: crate::Item,
    pub at: Located,
    /// The bidama it is in, or `this file` for an open document.
    pub container: String,
}

impl Engine {
    /// Every definition and test whose name contains `query` (ignoring
    /// case), across the open documents and every bidama loaded this
    /// session.
    #[must_use]
    pub fn workspace_symbols(&self, query: &str) -> Vec<WorkspaceSymbol> {
        let query = query.to_lowercase();
        let matches = |i: &crate::Item| {
            i.kind != crate::ItemKind::Use && i.name.to_lowercase().contains(&query)
        };
        let mut out = Vec::new();
        for id in self.document_ids() {
            let Some(a) = self.analysis(&id) else {
                continue;
            };
            for item in a.items().iter().filter(|i| matches(i)) {
                out.push(WorkspaceSymbol {
                    at: Located {
                        file: FileRef::Document(id.clone()),
                        span: item.name_span,
                    },
                    item: item.clone(),
                    container: "this file".to_string(),
                });
            }
        }
        for package in self.memo.loaded() {
            for (label, text) in &package.files {
                let path = std::path::PathBuf::from(label);
                if self.document_at(&path).is_some() {
                    continue;
                }
                for item in self.memo.items(text).iter().filter(|i| matches(i)) {
                    out.push(WorkspaceSymbol {
                        at: Located {
                            file: FileRef::Path(path.clone()),
                            span: item.name_span,
                        },
                        item: item.clone(),
                        container: Namespace::Bidama(package.name.clone()).to_string(),
                    });
                }
            }
        }
        out
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Meaning {
    Target(Target),
    Local(usize),
}

fn describe(m: Option<&Meaning>, a: &Analysis, engine: &Engine) -> String {
    match m {
        Some(Meaning::Target(t)) => t.to_string(),
        Some(Meaning::Local(start)) => a
            .locals(engine)
            .bindings
            .iter()
            .find(|b| b.span.start == *start)
            .map_or_else(
                || "a local".to_string(),
                |b| format!("the local `{}`", b.name),
            ),
        None => "nothing".to_string(),
    }
}

/// A name an author wrote as one: not an operator the parser lowered to a
/// call (`a + b` is `(+ a b)`).
fn spelled_as_a_name(written: &str) -> bool {
    written
        .chars()
        .next()
        .is_some_and(|c| c.is_alphabetic() || c == '_')
}
