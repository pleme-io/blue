use std::collections::HashMap;

use blue_lang_runtime::def_hash::{DefHash, DefKind, Shape};
use blue_lang_runtime::pipeline::Checked;
use blue_lang_runtime::uses::ResolvedProgram;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DefFact {
    pub top_level: usize,
    pub key: String,
    pub name: String,
    pub kind: DefKind,
    pub line: usize,
    pub def_hash: DefHash,
    pub shape: Option<Shape>,
    pub written_shape: Option<DefHash>,
    pub doc: Option<String>,
}

impl DefFact {
    #[must_use]
    pub fn gloss(&self) -> Option<&str> {
        self.doc
            .as_deref()?
            .lines()
            .map(str::trim)
            .find(|l| !l.is_empty())
    }

    #[must_use]
    pub fn kind_name(&self) -> &'static str {
        match self.kind {
            DefKind::Function => "function",
            DefKind::Value => "value",
            DefKind::Macro => "macro",
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct EntryFacts {
    pub definitions: usize,
    pub facts: Vec<DefFact>,
}

fn line_of(text: &str, at: usize) -> usize {
    text.get(..at)
        .map_or(1, |head| head.matches('\n').count() + 1)
}

#[must_use]
pub fn of_entry(checked: &Checked) -> EntryFacts {
    let program = &checked.program;
    let lowered = checked.lowered();
    let (hashes, docs) = crate::hash_checked_documented(program, &lowered);
    let mut computed: HashMap<usize, Shape> = checked
        .entry_shapes()
        .into_iter()
        .map(|s| (s.top_level, s))
        .collect();
    let written: HashMap<usize, DefHash> = checked
        .entry_written_shapes()
        .into_iter()
        .map(|s| (s.top_level, s.hash))
        .collect();
    let text = program
        .file(ResolvedProgram::ENTRY)
        .map(|f| f.text.to_string())
        .unwrap_or_default();
    let mut own: Vec<_> = hashes
        .defs()
        .iter()
        .filter(|d| program.owner_of(d.top_level) == Some(ResolvedProgram::ENTRY))
        .collect();
    own.sort_by_key(|d| d.top_level);
    let definitions = own.len();
    let facts = own
        .into_iter()
        .map(|d| DefFact {
            top_level: d.top_level,
            key: d.key.clone(),
            name: d
                .key
                .rsplit_once('/')
                .map_or(d.key.as_str(), |(_, n)| n)
                .to_string(),
            kind: d.kind,
            line: line_of(&text, program.forms()[d.top_level].span.start),
            def_hash: d.hash,
            shape: computed.remove(&d.top_level),
            written_shape: written.get(&d.top_level).copied(),
            doc: docs.get(&d.top_level).cloned(),
        })
        .collect();
    EntryFacts { definitions, facts }
}
