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
    let lowered = checked.lowered();
    let (hashes, docs) = crate::hash_checked_documented(&checked.program, &lowered);
    entry_facts(checked, &hashes, &docs)
}

#[must_use]
pub fn of_entry_linked(checked: &Checked) -> (EntryFacts, Links) {
    let lowered = checked.lowered();
    let (hashes, docs) = crate::hash_checked_documented(&checked.program, &lowered);
    (
        entry_facts(checked, &hashes, &docs),
        links_with(checked, &lowered, &hashes),
    )
}

fn entry_facts(
    checked: &Checked,
    hashes: &blue_lang_runtime::def_hash::DefHashes,
    docs: &HashMap<usize, String>,
) -> EntryFacts {
    let program = &checked.program;
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TestFact {
    pub name: String,
    pub line: usize,
    pub doc: bool,
    pub names: Vec<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Links {
    pub calls: HashMap<usize, Vec<String>>,
    pub reach: HashMap<usize, Vec<String>>,
    pub tests: Vec<TestFact>,
}

fn test_name(form: &blue_lang_syntax::Spanned) -> Option<String> {
    let items = form.as_list()?;
    if items.first()?.as_symbol()? != "deftest" {
        return None;
    }
    items.get(1)?.as_string().map(str::to_string)
}

#[must_use]
pub fn links_of(checked: &Checked) -> Links {
    let lowered = checked.lowered();
    let hashes = crate::hash_checked(&checked.program, &lowered);
    links_with(checked, &lowered, &hashes)
}

fn links_with(
    checked: &Checked,
    lowered: &[blue_lang_syntax::Spanned],
    hashes: &blue_lang_runtime::def_hash::DefHashes,
) -> Links {
    let program = &checked.program;
    let erased = blue_lang_runtime::erase_types(lowered);
    let host = crate::reach::host_reach(&erased, hashes);
    let named = crate::reach::form_reach(&erased, hashes);
    let defs = hashes.defs();
    let text = program
        .file(ResolvedProgram::ENTRY)
        .map(|f| f.text.to_string())
        .unwrap_or_default();
    let keys_of = |top_level: usize| -> Vec<String> {
        let mut ks: Vec<String> = named
            .get(top_level)
            .map(|n| n.names.iter().map(|&d| defs[d].key.clone()).collect())
            .unwrap_or_default();
        ks.sort();
        ks.dedup();
        ks
    };
    let mut links = Links::default();
    for (i, d) in defs.iter().enumerate() {
        if program.owner_of(d.top_level) != Some(ResolvedProgram::ENTRY) {
            continue;
        }
        links.calls.insert(d.top_level, keys_of(d.top_level));
        let mut caps: Vec<String> = host
            .get(i)
            .map(|r| r.keys().map(|c| c.label().to_string()).collect())
            .unwrap_or_default();
        caps.sort();
        links.reach.insert(d.top_level, caps);
    }
    for (t, form) in program.forms().iter().enumerate() {
        if program.owner_of(t) != Some(ResolvedProgram::ENTRY) {
            continue;
        }
        let Some(name) = test_name(form) else {
            continue;
        };
        links.tests.push(TestFact {
            doc: name.starts_with(blue_lang_syntax::doc::DOCTEST_PREFIX),
            name,
            line: line_of(&text, form.span.start),
            names: keys_of(t),
        });
    }
    links
}
