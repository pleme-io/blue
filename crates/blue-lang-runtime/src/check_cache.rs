use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};

use blue_lang_syntax::{Atom, Spanned, SpannedForm};

use crate::def_hash::DefHash;

pub const DOMAIN: &str = "blue check v1";

pub const ENV: &str = "BLUE_CHECK_CACHE";

#[must_use]
pub fn parse(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "" | "on" | "1" | "true" | "yes" => Some(true),
        "off" | "0" | "false" | "no" => Some(false),
        _ => None,
    }
}

pub fn enabled(value: Option<&str>) -> Result<bool, String> {
    match value {
        None => Ok(true),
        Some(v) => {
            parse(v).ok_or_else(|| format!("{ENV} is \"{v}\"; it takes on (the default) or off"))
        }
    }
}

pub trait CheckStore {
    fn load(&self, bucket: &DefHash) -> HashMap<[u8; 32], Vec<u8>>;
    fn append(&self, bucket: &DefHash, entries: &[([u8; 32], Vec<u8>)]);
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Pass {
    Resolve,
    Names,
    Rule,
}

impl Pass {
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Resolve => "resolve",
            Self::Names => "names",
            Self::Rule => "rule",
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Tally {
    pub asked: usize,
    pub checked: Vec<usize>,
}

impl Tally {
    #[must_use]
    pub fn reused(&self) -> usize {
        self.asked.saturating_sub(self.checked.len())
    }
}

type Entries = HashMap<[u8; 32], Vec<u8>>;

pub struct CheckCache<'s> {
    store: &'s dyn CheckStore,
    identity: [u8; 32],
    loaded: RefCell<HashMap<DefHash, Entries>>,
    pending: RefCell<BTreeMap<DefHash, Vec<([u8; 32], Vec<u8>)>>>,
    tally: RefCell<BTreeMap<Pass, Tally>>,
}

fn length_prefixed(h: &mut blake3::Hasher, part: &[u8]) {
    h.update(&(part.len() as u64).to_le_bytes());
    h.update(part);
}

#[must_use]
pub fn digest(parts: &[&[u8]]) -> [u8; 32] {
    let mut h = blake3::Hasher::new_derive_key("blue check read v1");
    for p in parts {
        length_prefixed(&mut h, p);
    }
    *h.finalize().as_bytes()
}

#[must_use]
pub fn tree_digest(form: &Spanned) -> [u8; 32] {
    let mut h = blake3::Hasher::new_derive_key("blue check tree v1");
    tree_into(form, form.span, &mut h);
    *h.finalize().as_bytes()
}

fn tree_into(form: &Spanned, base: tatara_lisp::Span, h: &mut blake3::Hasher) {
    if form.span == tatara_lisp::Span::synthetic() {
        h.update(&[0]);
    } else {
        h.update(&[1]);
        h.update(&(form.span.start.wrapping_sub(base.start) as u64).to_le_bytes());
        h.update(&(form.span.end.wrapping_sub(base.start) as u64).to_le_bytes());
    }
    match &form.form {
        SpannedForm::Nil => {
            h.update(&[10]);
        }
        SpannedForm::Atom(a) => match a {
            Atom::Symbol(s) => {
                h.update(&[11]);
                length_prefixed(h, s.as_bytes());
            }
            Atom::Keyword(s) => {
                h.update(&[12]);
                length_prefixed(h, s.as_bytes());
            }
            Atom::Str(s) => {
                h.update(&[13]);
                length_prefixed(h, s.as_bytes());
            }
            Atom::Int(n) => {
                h.update(&[14]);
                h.update(&n.to_le_bytes());
            }
            Atom::Float(f) => {
                h.update(&[15]);
                h.update(&f.to_bits().to_le_bytes());
            }
            Atom::Bool(b) => {
                h.update(&[16, u8::from(*b)]);
            }
        },
        SpannedForm::List(items) => {
            h.update(&[17]);
            h.update(&(items.len() as u64).to_le_bytes());
            for i in items {
                tree_into(i, base, h);
            }
        }
        SpannedForm::Quote(i) => {
            h.update(&[18]);
            tree_into(i, base, h);
        }
        SpannedForm::Quasiquote(i) => {
            h.update(&[19]);
            tree_into(i, base, h);
        }
        SpannedForm::Unquote(i) => {
            h.update(&[20]);
            tree_into(i, base, h);
        }
        SpannedForm::UnquoteSplice(i) => {
            h.update(&[21]);
            tree_into(i, base, h);
        }
    }
}

impl<'s> CheckCache<'s> {
    #[must_use]
    pub fn new(store: &'s dyn CheckStore, identity: [u8; 32]) -> Self {
        Self {
            store,
            identity,
            loaded: RefCell::new(HashMap::new()),
            pending: RefCell::new(BTreeMap::new()),
            tally: RefCell::new(BTreeMap::new()),
        }
    }

    #[must_use]
    pub fn key(&self, pass: Pass, parts: &[&[u8]]) -> [u8; 32] {
        let mut h = blake3::Hasher::new_derive_key(DOMAIN);
        length_prefixed(&mut h, &self.identity);
        length_prefixed(&mut h, pass.name().as_bytes());
        for p in parts {
            length_prefixed(&mut h, p);
        }
        *h.finalize().as_bytes()
    }

    #[must_use]
    pub fn get(&self, pass: Pass, bucket: &DefHash, key: &[u8; 32]) -> Option<Vec<u8>> {
        self.tally.borrow_mut().entry(pass).or_default().asked += 1;
        if let Some(v) = self
            .pending
            .borrow()
            .get(bucket)
            .and_then(|p| p.iter().find(|(k, _)| k == key))
        {
            return Some(v.1.clone());
        }
        let mut loaded = self.loaded.borrow_mut();
        loaded
            .entry(*bucket)
            .or_insert_with(|| self.store.load(bucket))
            .get(key)
            .cloned()
    }

    pub fn put(&self, bucket: &DefHash, key: [u8; 32], value: Vec<u8>) {
        self.pending
            .borrow_mut()
            .entry(*bucket)
            .or_default()
            .push((key, value));
    }

    pub fn checked(&self, pass: Pass, top_level: usize) {
        self.tally
            .borrow_mut()
            .entry(pass)
            .or_default()
            .checked
            .push(top_level);
    }

    #[must_use]
    pub fn tally(&self, pass: Pass) -> Tally {
        self.tally.borrow().get(&pass).cloned().unwrap_or_default()
    }

    pub fn flush(&self) {
        let pending = std::mem::take(&mut *self.pending.borrow_mut());
        for (bucket, entries) in pending {
            self.store.append(&bucket, &entries);
            if let Some(l) = self.loaded.borrow_mut().get_mut(&bucket) {
                l.extend(entries);
            }
        }
    }
}

pub(crate) struct FormMemo<'c, 's> {
    pub cache: &'c CheckCache<'s>,
    pub pass: Pass,
    pub keys: Vec<([u8; 32], DefHash)>,
}

impl blue_lang_check::walk_cache::WalkMemo for FormMemo<'_, '_> {
    fn recall(&mut self, top_level: usize) -> Option<Vec<u8>> {
        let (key, bucket) = self.keys.get(top_level)?;
        self.cache.get(self.pass, bucket, key)
    }

    fn keep(&mut self, top_level: usize, value: Vec<u8>) {
        if let Some((key, bucket)) = self.keys.get(top_level) {
            self.cache.put(bucket, *key, value);
        }
    }

    fn walked(&mut self, top_level: usize) {
        self.cache.checked(self.pass, top_level);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_cache_is_on_unless_named_off() {
        assert_eq!(enabled(None), Ok(true));
        for on in ["", "on", "1", "true", "YES"] {
            assert_eq!(parse(on), Some(true), "{on}");
        }
        for off in ["off", "0", "false", "no"] {
            assert_eq!(parse(off), Some(false), "{off}");
        }
        assert!(enabled(Some("store")).is_err());
    }

    #[test]
    fn a_key_moves_with_the_identity_the_pass_and_each_part() {
        struct Nothing;
        impl CheckStore for Nothing {
            fn load(&self, _: &DefHash) -> HashMap<[u8; 32], Vec<u8>> {
                HashMap::new()
            }
            fn append(&self, _: &DefHash, _: &[([u8; 32], Vec<u8>)]) {}
        }
        let a = CheckCache::new(&Nothing, [1; 32]);
        let b = CheckCache::new(&Nothing, [2; 32]);
        let k = a.key(Pass::Names, &[b"x", b"y"]);
        assert_ne!(k, b.key(Pass::Names, &[b"x", b"y"]));
        assert_ne!(k, a.key(Pass::Resolve, &[b"x", b"y"]));
        assert_ne!(k, a.key(Pass::Names, &[b"xy"]));
        assert_eq!(k, a.key(Pass::Names, &[b"x", b"y"]));
    }
}
