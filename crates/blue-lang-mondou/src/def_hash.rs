//! `def_hash(def)`: a definition's identity is the hash of its resolved tree
//! (`theory/BLUE-ENGINE.md` §3.2, milestone E4), Unison's rule.
//!
//! The tree is the one the runtime evaluates before erasure
//! (`blue_lang_runtime::pipeline::lower`): every reference to a program
//! definition is already its runtime key (`%root/f`, `retsu/first`), a local
//! stays bare, a builtin stays bare. Hashing it, each reference to another
//! definition is replaced by that definition's hash, so a definition's hash
//! changes exactly when it, or anything it reaches, changes. Spans, comments
//! and layout are not in the tree, so they are not in the hash.
//!
//! A definition's own name is metadata, not content: renaming one leaves its
//! hash, and every caller's, as it was (§5.2: a rename changes names, never
//! `def_hash`es). Mutually recursive definitions hash as one unit: a strongly
//! connected component is hashed once, its members in an order fixed by their
//! shapes, and each member's hash is the unit's hash and its place in it.
//!
//! BLAKE3, written `b3:<hex>` as blue's build inputs are (§3.3): a key that
//! leaves the process (the memo store, a shared cache) must not collide.

use std::collections::{BTreeMap, HashMap};

use blue_lang_syntax::{Atom, Spanned, SpannedForm};

/// The identity of one definition's resolved tree.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct DefHash(pub [u8; 32]);

impl DefHash {
    #[must_use]
    pub fn bytes(&self) -> &[u8; 32] {
        &self.0
    }

    /// The lowercase hex of the hash, without the `b3:` prefix.
    #[must_use]
    pub fn hex(&self) -> String {
        let mut s = String::with_capacity(64);
        for b in self.0 {
            s.push(char::from(b"0123456789abcdef"[usize::from(b >> 4)]));
            s.push(char::from(b"0123456789abcdef"[usize::from(b & 15)]));
        }
        s
    }
}

impl std::fmt::Display for DefHash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "b3:{}", self.hex())
    }
}

impl std::fmt::Debug for DefHash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "b3:{}…", &self.hex()[..12])
    }
}

/// What a top-level form defines.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DefKind {
    /// `def f(…)`, or `f = fn(…) … end`: a name bound to a function.
    Function,
    /// `x = e`.
    Value,
    /// `defmacro m(…)`.
    Macro,
}

/// One top-level definition, hashed.
#[derive(Clone, Debug)]
pub struct HashedDef {
    /// Its index among the program's top-level forms.
    pub top_level: usize,
    /// The runtime key it binds: `%root/f`, `retsu/first`.
    pub key: String,
    pub kind: DefKind,
    pub hash: DefHash,
    /// The definitions its tree names, by index in [`DefHashes::defs`].
    pub calls: Vec<usize>,
    /// The definitions hashed as one unit with it, itself included; a
    /// definition that does not reach itself is alone.
    pub unit: Vec<usize>,
}

/// Every definition of a program, hashed.
#[derive(Clone, Debug, Default)]
pub struct DefHashes {
    defs: Vec<HashedDef>,
    by_top_level: HashMap<usize, usize>,
    by_key: HashMap<String, Vec<usize>>,
}

impl DefHashes {
    #[must_use]
    pub fn defs(&self) -> &[HashedDef] {
        &self.defs
    }

    /// The definition top-level form `top_level` makes, if it makes one.
    #[must_use]
    pub fn at(&self, top_level: usize) -> Option<&HashedDef> {
        self.by_top_level.get(&top_level).map(|&i| &self.defs[i])
    }

    /// The definition binding `key`, when exactly one form binds it.
    #[must_use]
    pub fn of_key(&self, key: &str) -> Option<&HashedDef> {
        match self.by_key.get(key).map(Vec::as_slice) {
            Some([i]) => Some(&self.defs[*i]),
            _ => None,
        }
    }

    /// Whether more than one top-level form binds `key`: which one a call
    /// reaches depends on when it runs, so neither has a single identity.
    #[must_use]
    pub fn is_ambiguous(&self, key: &str) -> bool {
        self.by_key.get(key).is_some_and(|v| v.len() > 1)
    }

    /// Every key a top-level form of the program binds.
    pub fn keys(&self) -> impl Iterator<Item = &str> {
        self.by_key.keys().map(String::as_str)
    }
}

/// The key a top-level form binds and what it binds there, if it is a
/// definition.
#[must_use]
pub fn defined(form: &Spanned) -> Option<(&str, DefKind)> {
    let items = form.as_list()?;
    match items.first()?.as_symbol()? {
        "defmacro" => Some((items.get(1)?.as_symbol()?, DefKind::Macro)),
        "define" | "define-typed" => {
            let node = blue_lang_syntax::scope::defined_name_node(items)?;
            let function = items[1].as_list().is_some()
                || items
                    .get(2)
                    .and_then(Spanned::as_list)
                    .and_then(|v| v.first())
                    .and_then(Spanned::as_symbol)
                    == Some("lambda");
            let kind = if function {
                DefKind::Function
            } else {
                DefKind::Value
            };
            Some((node.as_symbol()?, kind))
        }
        _ => None,
    }
}

/// Hash every definition of a program, given its top-level forms as
/// [`blue_lang_runtime::pipeline::lower`] produces them.
#[must_use]
pub fn hash_program(lowered: &[Spanned]) -> DefHashes {
    hash_program_documented(lowered, &|_| None)
}

/// [`hash_program`], each definition's `@doc` text hashed with its tree:
/// `doc_of(i)` is the text documenting top-level form `i`. A doc that
/// changes changes the definition's hash and every caller's, so a doc that
/// drifts from its subject is a hash change, not a silent one.
#[must_use]
pub fn hash_program_documented(
    lowered: &[Spanned],
    doc_of: &dyn Fn(usize) -> Option<String>,
) -> DefHashes {
    let mut out = DefHashes::default();
    let mut docs = Vec::new();
    let mut forms = Vec::new();
    for (i, form) in lowered.iter().enumerate() {
        let Some((key, kind)) = defined(form) else {
            continue;
        };
        let index = out.defs.len();
        out.by_top_level.insert(i, index);
        out.by_key.entry(key.to_string()).or_default().push(index);
        out.defs.push(HashedDef {
            top_level: i,
            key: key.to_string(),
            kind,
            hash: DefHash([0; 32]),
            calls: Vec::new(),
            unit: Vec::new(),
        });
        forms.push(form);
        docs.push(doc_of(i));
    }
    let unique: HashMap<&str, usize> = out
        .by_key
        .iter()
        .filter(|(_, v)| v.len() == 1)
        .map(|(k, v)| (k.as_str(), v[0]))
        .collect();
    for (d, form) in forms.iter().enumerate() {
        let mut calls = Vec::new();
        names(form, &mut |s| {
            if let Some(&c) = unique.get(s) {
                calls.push(c);
            }
        });
        calls.sort_unstable();
        calls.dedup();
        out.defs[d].calls = calls;
    }
    let graph: Vec<Vec<usize>> = out.defs.iter().map(|d| d.calls.clone()).collect();
    for unit in components(&graph) {
        let mut hasher = Unit {
            forms: &forms,
            docs: &docs,
            defs: &out.defs,
            unique: &unique,
        };
        let hashes = hasher.hash(&unit);
        for (&member, hash) in unit.iter().zip(hashes) {
            out.defs[member].hash = hash;
            out.defs[member].unit.clone_from(&unit);
        }
    }
    out
}

/// Every symbol of `form`, in any position.
fn names<'a>(form: &'a Spanned, out: &mut dyn FnMut(&'a str)) {
    match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => out(s),
        SpannedForm::List(items) => {
            for i in items {
                names(i, out);
            }
        }
        SpannedForm::Quote(x)
        | SpannedForm::Quasiquote(x)
        | SpannedForm::Unquote(x)
        | SpannedForm::UnquoteSplice(x) => names(x, out),
        _ => {}
    }
}

/// Tarjan's strongly connected components, each emitted after every
/// component it reaches, so a unit is hashed after everything it names.
fn components(graph: &[Vec<usize>]) -> Vec<Vec<usize>> {
    struct State<'g> {
        graph: &'g [Vec<usize>],
        index: Vec<Option<usize>>,
        low: Vec<usize>,
        on_stack: Vec<bool>,
        stack: Vec<usize>,
        next: usize,
        out: Vec<Vec<usize>>,
    }
    // Iterative, so a long chain of definitions cannot overflow the stack.
    fn visit(s: &mut State<'_>, root: usize) {
        let mut work: Vec<(usize, usize)> = vec![(root, 0)];
        s.index[root] = Some(s.next);
        s.low[root] = s.next;
        s.next += 1;
        s.stack.push(root);
        s.on_stack[root] = true;
        while let Some(top) = work.last_mut() {
            let v = top.0;
            if let Some(&w) = s.graph[v].get(top.1) {
                top.1 += 1;
                match s.index[w] {
                    None => {
                        s.index[w] = Some(s.next);
                        s.low[w] = s.next;
                        s.next += 1;
                        s.stack.push(w);
                        s.on_stack[w] = true;
                        work.push((w, 0));
                    }
                    Some(iw) if s.on_stack[w] => s.low[v] = s.low[v].min(iw),
                    Some(_) => {}
                }
                continue;
            }
            work.pop();
            if let Some(&(parent, _)) = work.last() {
                s.low[parent] = s.low[parent].min(s.low[v]);
            }
            if Some(s.low[v]) == s.index[v] {
                let mut unit = Vec::new();
                while let Some(w) = s.stack.pop() {
                    s.on_stack[w] = false;
                    unit.push(w);
                    if w == v {
                        break;
                    }
                }
                unit.sort_unstable();
                s.out.push(unit);
            }
        }
    }
    let n = graph.len();
    let mut s = State {
        graph,
        index: vec![None; n],
        low: vec![0; n],
        on_stack: vec![false; n],
        stack: Vec::new(),
        next: 0,
        out: Vec::new(),
    };
    for v in 0..n {
        if s.index[v].is_none() {
            visit(&mut s, v);
        }
    }
    s.out
}

/// The encoding's tags. One byte each, then a fixed-width or
/// length-prefixed payload, so no two trees encode alike.
mod tag {
    pub const NIL: u8 = 0;
    pub const SYMBOL: u8 = 1;
    pub const KEYWORD: u8 = 2;
    pub const STR: u8 = 3;
    pub const INT: u8 = 4;
    pub const FLOAT: u8 = 5;
    pub const BOOL: u8 = 6;
    pub const LIST: u8 = 7;
    pub const QUOTE: u8 = 8;
    pub const QUASIQUOTE: u8 = 9;
    pub const UNQUOTE: u8 = 10;
    pub const UNQUOTE_SPLICE: u8 = 11;
    /// A reference to another definition: its hash follows.
    pub const DEF: u8 = 12;
    /// A reference into the unit being hashed: its place in the unit follows.
    pub const UNIT: u8 = 13;
    /// A reference into the unit, before the unit's order is fixed.
    pub const UNIT_UNORDERED: u8 = 14;
    /// A definition's `@doc` text: its bytes follow.
    pub const DOC: u8 = 15;
}

/// The domain of every hash this module writes, so a `def_hash` can never
/// equal a hash of something else that happens to share bytes.
const DOMAIN: &str = "blue def_hash v1";

struct Unit<'a> {
    forms: &'a [&'a Spanned],
    docs: &'a [Option<String>],
    defs: &'a [HashedDef],
    unique: &'a HashMap<&'a str, usize>,
}

impl Unit<'_> {
    /// The members' hashes, in `unit` order.
    fn hash(&mut self, unit: &[usize]) -> Vec<DefHash> {
        // Each member's shape, with every reference into the unit written
        // alike: the order the unit is hashed in, independent of the names.
        let mut shaped: Vec<(DefHash, &str, usize)> = unit
            .iter()
            .map(|&m| {
                let mut h = blake3::Hasher::new_derive_key(DOMAIN);
                self.encode(&mut h, m, unit, None);
                (
                    DefHash(*h.finalize().as_bytes()),
                    self.defs[m].key.as_str(),
                    m,
                )
            })
            .collect();
        shaped.sort();
        let order: BTreeMap<usize, usize> = shaped
            .iter()
            .enumerate()
            .map(|(place, &(_, _, m))| (m, place))
            .collect();
        let mut whole = blake3::Hasher::new_derive_key(DOMAIN);
        whole.update(&(unit.len() as u64).to_le_bytes());
        for &(_, _, m) in &shaped {
            self.encode(&mut whole, m, unit, Some(&order));
        }
        let whole = whole.finalize();
        unit.iter()
            .map(|m| {
                let mut h = blake3::Hasher::new_derive_key(DOMAIN);
                h.update(whole.as_bytes());
                h.update(&(order[m] as u64).to_le_bytes());
                DefHash(*h.finalize().as_bytes())
            })
            .collect()
    }

    fn encode(
        &self,
        h: &mut blake3::Hasher,
        member: usize,
        unit: &[usize],
        order: Option<&BTreeMap<usize, usize>>,
    ) {
        let own = self.defs[member].key.as_str();
        let form = self.forms[member];
        let items = form.as_list().unwrap_or_default();
        // The head and the definition's shape; its own name is written as a
        // reference into the unit, like any other self-reference.
        h.update(&[tag::LIST]);
        h.update(&(items.len() as u64).to_le_bytes());
        for item in items {
            self.node(h, item, own, unit, order);
        }
        if let Some(doc) = &self.docs[member] {
            h.update(&[tag::DOC]);
            h.update(&(doc.len() as u64).to_le_bytes());
            h.update(doc.as_bytes());
        }
    }

    fn node(
        &self,
        h: &mut blake3::Hasher,
        node: &Spanned,
        own: &str,
        unit: &[usize],
        order: Option<&BTreeMap<usize, usize>>,
    ) {
        let bytes = |h: &mut blake3::Hasher, tag: u8, b: &[u8]| {
            h.update(&[tag]);
            h.update(&(b.len() as u64).to_le_bytes());
            h.update(b);
        };
        match &node.form {
            SpannedForm::Nil => {
                h.update(&[tag::NIL]);
            }
            SpannedForm::Atom(Atom::Symbol(s)) => match self.unique.get(s.as_str()) {
                Some(&d) if unit.contains(&d) => match order {
                    Some(order) => {
                        h.update(&[tag::UNIT]);
                        h.update(&(order[&d] as u64).to_le_bytes());
                    }
                    None => {
                        h.update(&[tag::UNIT_UNORDERED]);
                    }
                },
                Some(&d) => {
                    h.update(&[tag::DEF]);
                    h.update(self.defs[d].hash.bytes());
                }
                None if s == own => {
                    // Bound twice in the program, so not in `unique`: its own
                    // name is still metadata.
                    h.update(&[tag::UNIT_UNORDERED]);
                }
                None => bytes(h, tag::SYMBOL, s.as_bytes()),
            },
            SpannedForm::Atom(Atom::Keyword(s)) => bytes(h, tag::KEYWORD, s.as_bytes()),
            SpannedForm::Atom(Atom::Str(s)) => bytes(h, tag::STR, s.as_bytes()),
            SpannedForm::Atom(Atom::Int(n)) => {
                h.update(&[tag::INT]);
                h.update(&n.to_le_bytes());
            }
            SpannedForm::Atom(Atom::Float(x)) => {
                h.update(&[tag::FLOAT]);
                h.update(&x.to_bits().to_le_bytes());
            }
            SpannedForm::Atom(Atom::Bool(b)) => {
                h.update(&[tag::BOOL, u8::from(*b)]);
            }
            SpannedForm::List(items) => {
                h.update(&[tag::LIST]);
                h.update(&(items.len() as u64).to_le_bytes());
                for i in items {
                    self.node(h, i, own, unit, order);
                }
            }
            SpannedForm::Quote(x) => {
                h.update(&[tag::QUOTE]);
                self.node(h, x, own, unit, order);
            }
            SpannedForm::Quasiquote(x) => {
                h.update(&[tag::QUASIQUOTE]);
                self.node(h, x, own, unit, order);
            }
            SpannedForm::Unquote(x) => {
                h.update(&[tag::UNQUOTE]);
                self.node(h, x, own, unit, order);
            }
            SpannedForm::UnquoteSplice(x) => {
                h.update(&[tag::UNQUOTE_SPLICE]);
                self.node(h, x, own, unit, order);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lowered(src: &str) -> Vec<Spanned> {
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        assert!(checked.outcome.ok(), "{:?}", checked.outcome.diagnostics);
        blue_lang_runtime::pipeline::lower(&checked.program, &checked.names)
    }

    fn hash_of(src: &str, name: &str) -> DefHash {
        let key = format!("%root/{name}");
        hash_program(&lowered(src))
            .of_key(&key)
            .unwrap_or_else(|| panic!("{key} is not defined"))
            .hash
    }

    const BASE: &str =
        "def g(x)\n  x * 2\nend\n\ndef f(x)\n  g(x) + 1\nend\n\ndef h(x)\n  x - 1\nend\n";

    #[test]
    fn layout_comments_and_position_are_not_in_the_hash() {
        let moved = "# a comment\n\n\ndef h(x)\n  x - 1\nend\n\ndef g(x)\n  # doubled\n  x * 2\nend\n\ndef f(x)\n  g(x) + 1\nend\n";
        for name in ["f", "g", "h"] {
            assert_eq!(hash_of(BASE, name), hash_of(moved, name), "{name}");
        }
    }

    fn documented_hash_of(src: &str, name: &str) -> DefHash {
        let checked = blue_lang_runtime::pipeline::check_entry(
            blue_lang_runtime::uses::Entry::anonymous(src),
            &blue_lang_runtime::uses::NoLoader,
            None,
            blue_lang_runtime::pipeline::Checking::Program,
        )
        .expect("checks");
        let docs = crate::program_docs(&checked.program);
        let key = format!("%root/{name}");
        hash_program_documented(
            &blue_lang_runtime::pipeline::lower(&checked.program, &checked.names),
            &|i| docs.get(&i).cloned(),
        )
        .of_key(&key)
        .unwrap_or_else(|| panic!("{key} is not defined"))
        .hash
    }

    /// Red run (2026-10-24): with the `tag::DOC` block removed from
    /// `encode`, the first assertion failed: both texts hashed alike.
    #[test]
    fn a_doc_is_in_its_definitions_hash_and_every_callers() {
        let doc = |t: &str| format!("@doc \"\"\"\n{t}\n\"\"\"\n{BASE}");
        let a = doc("g doubles a number.");
        let b = doc("g triples a number.");
        assert_ne!(documented_hash_of(&a, "g"), documented_hash_of(&b, "g"));
        assert_ne!(documented_hash_of(&a, "f"), documented_hash_of(&b, "f"));
        assert_eq!(documented_hash_of(&a, "h"), documented_hash_of(&b, "h"));
        assert_ne!(documented_hash_of(&a, "g"), documented_hash_of(BASE, "g"));
        assert_eq!(documented_hash_of(BASE, "g"), hash_of(BASE, "g"));
    }

    #[test]
    fn an_edit_to_a_callee_changes_every_caller_and_nothing_else() {
        let edited = BASE.replace("x * 2", "x * 3");
        assert_ne!(hash_of(BASE, "g"), hash_of(&edited, "g"), "the edited def");
        assert_ne!(hash_of(BASE, "f"), hash_of(&edited, "f"), "its caller");
        assert_eq!(
            hash_of(BASE, "h"),
            hash_of(&edited, "h"),
            "an unrelated def"
        );
    }

    #[test]
    fn a_rename_changes_names_and_no_hash() {
        let renamed = BASE.replace("g(", "twice(");
        assert_eq!(hash_of(BASE, "g"), hash_of(&renamed, "twice"));
        assert_eq!(hash_of(BASE, "f"), hash_of(&renamed, "f"));
    }

    #[test]
    fn equal_trees_hash_equal_and_different_kinds_do_not() {
        let src = "def a(x)\n  x + 1\nend\n\ndef b(x)\n  x + 1\nend\n\nc = fn(x) x + 1 end\n";
        assert_eq!(hash_of(src, "a"), hash_of(src, "b"));
        assert_ne!(hash_of(src, "a"), hash_of(src, "c"));
    }

    #[test]
    fn mutual_recursion_hashes_as_one_unit_with_distinct_members() {
        let src = "def ev(n)\n  if n == 0\n    true\n  else\n    od(n - 1)\n  end\nend\n\ndef od(n)\n  if n == 0\n    false\n  else\n    ev(n - 1)\n  end\nend\n";
        let hashes = hash_program(&lowered(src));
        let ev = hashes.of_key("%root/ev").expect("ev");
        let od = hashes.of_key("%root/od").expect("od");
        assert_eq!(ev.unit.len(), 2);
        assert_eq!(ev.unit, od.unit);
        assert_ne!(ev.hash, od.hash);
        // Swapping the names swaps nothing: each member is its shape.
        let swapped = src
            .replace("ev", "TMP")
            .replace("od", "ev")
            .replace("TMP", "od");
        assert_eq!(hash_of(src, "ev"), hash_of(&swapped, "od"));
        // An edit to one member changes both.
        let edited = src.replace("false", "nil");
        assert_ne!(hash_of(src, "ev"), hash_of(&edited, "ev"));
        assert_ne!(hash_of(src, "od"), hash_of(&edited, "od"));
    }

    #[test]
    fn a_value_definition_a_function_reads_is_part_of_its_hash() {
        let src = "limit = 3\n\ndef over(x)\n  x > limit\nend\n";
        let edited = src.replace("= 3", "= 4");
        assert_ne!(hash_of(src, "over"), hash_of(&edited, "over"));
    }

    #[test]
    fn components_are_emitted_callees_first() {
        // 0 -> 1 -> 2 -> 1, 3 alone.
        let graph = vec![vec![1], vec![2], vec![1], vec![]];
        let units = components(&graph);
        let place = |v: usize| units.iter().position(|u| u.contains(&v)).expect("placed");
        assert_eq!(units.iter().filter(|u| u.len() == 2).count(), 1);
        assert!(place(1) < place(0));
        assert_eq!(place(1), place(2));
    }

    #[test]
    fn a_long_chain_does_not_overflow() {
        let graph: Vec<Vec<usize>> = (0..200_000)
            .map(|i| if i == 0 { vec![] } else { vec![i - 1] })
            .collect();
        assert_eq!(components(&graph).len(), 200_000);
    }

    #[test]
    fn the_hash_prints_as_a_b3_declaration() {
        let h = hash_of(BASE, "f").to_string();
        assert!(h.starts_with("b3:") && h.len() == 67, "{h}");
    }
}
