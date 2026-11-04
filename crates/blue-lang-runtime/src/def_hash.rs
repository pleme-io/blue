//! `def_hash(def)`: a definition's identity is the hash of its resolved tree
//! (`theory/BLUE-ENGINE.md` §3.2, milestone E4), Unison's rule.
//!
//! The tree is the one the runtime evaluates before erasure
//! (`crate::pipeline::lower`): every reference to a program
//! definition is already its runtime key (`%root/f`, `retsu/first`), a local
//! stays bare, a builtin stays bare. Hashing it, each reference to another
//! definition is replaced by that definition's hash, so a definition's hash
//! changes exactly when it, or anything it reaches, changes. Spans, comments
//! and layout are not in the tree, so they are not in the hash. The one span
//! `lower` writes into the tree, a `raise`'s `path:line` (`blue-raise-at`),
//! is hashed as the `raise` it was, so how a package was reached, and where
//! in its file a raise sits, change no hash.
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

    /// Where in [`Self::defs`] the definition top-level form `top_level`
    /// makes sits, if it makes one.
    #[must_use]
    pub fn index_at(&self, top_level: usize) -> Option<usize> {
        self.by_top_level.get(&top_level).copied()
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
/// [`crate::pipeline::lower`] produces them.
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
    hash_in_domain(lowered, doc_of, DOMAIN)
}

fn hash_in_domain(
    lowered: &[Spanned],
    doc_of: &dyn Fn(usize) -> Option<String>,
    domain: &'static str,
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
            domain,
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

/// Every unambiguous definition key of a program with its `def_hash`
/// written `b3:<hex>`, each with its `@doc` text as the engine hashes it
/// (`blue_lang_mondou::hash_checked`; `docs` by top-level form), and
/// [`crate::receipt::RUN`] with the hash of the run: a definition
/// whose body is every top-level form in order (a definition by its key, so
/// its hash stands in) and then the call to `main` when the entry has one.
/// What a crash trace and a receipt name.
#[must_use]
pub fn identified(
    lowered: &[Spanned],
    docs: &HashMap<usize, String>,
    main: Option<&str>,
) -> BTreeMap<String, String> {
    let run_key = crate::receipt::RUN;
    let mut bound: HashMap<&str, usize> = HashMap::new();
    for form in lowered {
        if let Some((key, _)) = defined(form) {
            *bound.entry(key).or_default() += 1;
        }
    }
    let synthetic = |form: SpannedForm| Spanned::new(blue_lang_syntax::Span::synthetic(), form);
    let symbol = |s: &str| synthetic(SpannedForm::Atom(Atom::Symbol(s.to_string())));
    let mut run = vec![
        symbol("define"),
        synthetic(SpannedForm::List(vec![symbol(run_key)])),
    ];
    run.extend(lowered.iter().map(|form| match defined(form) {
        Some((key, _)) if bound.get(key) == Some(&1) => symbol(key),
        _ => form.clone(),
    }));
    run.extend(main.map(|m| synthetic(SpannedForm::List(vec![symbol(m)]))));
    let mut forms = lowered.to_vec();
    forms.push(synthetic(SpannedForm::List(run)));
    let hashes = hash_program_documented(&forms, &|i| docs.get(&i).cloned());
    hashes
        .defs()
        .iter()
        .filter(|d| !hashes.is_ambiguous(&d.key))
        .map(|d| (d.key.clone(), d.hash.to_string()))
        .collect()
}

/// What the evidence of a test run names: every unambiguous definition key
/// with its `def_hash`, and every `test` block, by its top-level form, with
/// its own.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TestIdentities {
    pub definitions: BTreeMap<String, String>,
    pub tests: BTreeMap<usize, String>,
}

/// The identities of a lowered program's definitions and of its `test`
/// blocks, each written `b3:<hex>` and `docs` hashed with their definitions
/// as [`identified`] hashes them.
///
/// A test's identity is the `def_hash` of the test as a definition whose body
/// is its declaration and its body: a reference to a definition is that
/// definition's hash, so a test's identity changes when its body, its
/// declaration, its target or anything it calls changes, and never when it is
/// renamed (a test's name, like a definition's, is metadata).
#[must_use]
pub fn test_identities(lowered: &[Spanned], docs: &HashMap<usize, String>) -> TestIdentities {
    let synthetic = |form: SpannedForm| Spanned::new(blue_lang_syntax::Span::synthetic(), form);
    let symbol = |s: &str| synthetic(SpannedForm::Atom(Atom::Symbol(s.to_string())));
    let mut forms = lowered.to_vec();
    let mut keys = Vec::new();
    for (i, form) in lowered.iter().enumerate() {
        let Some(parts) = blue_lang_syntax::test_parts(form) else {
            continue;
        };
        let key = format!("%test/{i}");
        let mut define = vec![
            symbol("define"),
            synthetic(SpannedForm::List(vec![symbol(&key)])),
        ];
        define.extend(parts.meta.cloned());
        define.push(parts.body.clone());
        forms.push(synthetic(SpannedForm::List(define)));
        keys.push((i, key));
    }
    let hashes = hash_program_documented(&forms, &|i| docs.get(&i).cloned());
    let definitions = hashes
        .defs()
        .iter()
        .filter(|d| d.top_level < lowered.len() && !hashes.is_ambiguous(&d.key))
        .map(|d| (d.key.clone(), d.hash.to_string()))
        .collect();
    let tests = keys
        .into_iter()
        .filter_map(|(i, key)| hashes.of_key(&key).map(|d| (i, d.hash.to_string())))
        .collect();
    TestIdentities { definitions, tests }
}

fn located_raise(items: &[Spanned]) -> Option<&[Spanned]> {
    match items {
        [head, site, args @ ..]
            if head.as_symbol() == Some(crate::errors::RAISE_AT)
                && matches!(site.form, SpannedForm::Atom(Atom::Str(_))) =>
        {
            Some(args)
        }
        _ => None,
    }
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
#[doc(hidden)]
#[must_use]
pub fn components(graph: &[Vec<usize>]) -> Vec<Vec<usize>> {
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

const SHAPE_DOMAIN: &str = "blue shape_hash v1";

struct Unit<'a> {
    domain: &'static str,
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
                let mut h = blake3::Hasher::new_derive_key(self.domain);
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
        let mut whole = blake3::Hasher::new_derive_key(self.domain);
        whole.update(&(unit.len() as u64).to_le_bytes());
        for &(_, _, m) in &shaped {
            self.encode(&mut whole, m, unit, Some(&order));
        }
        let whole = whole.finalize();
        unit.iter()
            .map(|m| {
                let mut h = blake3::Hasher::new_derive_key(self.domain);
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
            SpannedForm::List(items) => match located_raise(items) {
                Some(args) => {
                    h.update(&[tag::LIST]);
                    h.update(&((args.len() + 1) as u64).to_le_bytes());
                    let head = Spanned::new(
                        node.span,
                        SpannedForm::Atom(Atom::Symbol("raise".to_string())),
                    );
                    self.node(h, &head, own, unit, order);
                    for i in args {
                        self.node(h, i, own, unit, order);
                    }
                }
                None => {
                    h.update(&[tag::LIST]);
                    h.update(&(items.len() as u64).to_le_bytes());
                    for i in items {
                        self.node(h, i, own, unit, order);
                    }
                }
            },
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Shape {
    pub top_level: usize,
    pub key: String,
    pub hash: DefHash,
    pub size: usize,
}

impl Shape {
    #[must_use]
    pub fn name(&self) -> &str {
        self.key.rsplit_once('/').map_or(&self.key, |(_, n)| n)
    }

    #[must_use]
    pub fn namespace(&self) -> &str {
        self.key.rsplit_once('/').map_or("", |(ns, _)| ns)
    }
}

#[must_use]
pub fn shape_hashes(lowered: &[Spanned], in_scope: &dyn Fn(usize) -> bool) -> Vec<Shape> {
    let numbered: Vec<Spanned> = lowered
        .iter()
        .enumerate()
        .map(|(i, form)| {
            if in_scope(i) {
                number_locals(form)
            } else {
                Spanned::new(form.span, SpannedForm::Nil)
            }
        })
        .collect();
    let hashes = hash_in_domain(&numbered, &|_| None, SHAPE_DOMAIN);
    hashes
        .defs()
        .iter()
        .filter(|d| d.kind == DefKind::Function && !hashes.is_ambiguous(&d.key))
        .map(|d| Shape {
            top_level: d.top_level,
            key: d.key.clone(),
            hash: d.hash,
            size: shape_size(&numbered[d.top_level]),
        })
        .collect()
}

fn shape_size(form: &Spanned) -> usize {
    use blue_lang_check::shape::size;
    let parts = form.as_list().unwrap_or_default();
    let body = tatara_lisp::Sexp::List(
        parts
            .iter()
            .skip(2)
            .map(Spanned::to_sexp)
            .collect::<Vec<_>>(),
    );
    2 + size(&body)
}

#[derive(Default)]
struct Numbering {
    frames: Vec<HashMap<String, usize>>,
    next: usize,
    references: HashMap<*const Spanned, usize>,
    binders: HashMap<(usize, usize, String), usize>,
}

impl Numbering {
    fn local(&self, name: &str) -> Option<usize> {
        self.frames.iter().rev().find_map(|f| f.get(name).copied())
    }
}

impl blue_lang_syntax::scope::Scopes for Numbering {
    fn head_kind(&self, name: &str) -> Option<blue_lang_syntax::scope::HeadKind> {
        blue_lang_syntax::scope::SHAPED_FORMS
            .contains(&name)
            .then_some(blue_lang_syntax::scope::HeadKind::SpecialForm)
    }

    fn open(&mut self) {
        self.frames.push(HashMap::new());
    }

    fn bind(
        &mut self,
        name: &str,
        span: tatara_lisp::Span,
        _kind: blue_lang_syntax::scope::BinderKind,
    ) {
        let next = self.next;
        let Some(frame) = self.frames.last_mut() else {
            return;
        };
        let number = *frame.entry(name.to_string()).or_insert(next);
        if number == next {
            self.next += 1;
        }
        self.binders
            .insert((span.start, span.end, name.to_string()), number);
    }

    fn close(&mut self) {
        self.frames.pop();
    }

    fn reference(&mut self, node: &Spanned, name: &str, _opaque: bool) {
        if let Some(number) = self.local(name) {
            self.references.insert(std::ptr::from_ref(node), number);
        }
    }
}

fn number_locals(form: &Spanned) -> Spanned {
    let mut pass = Numbering::default();
    blue_lang_syntax::scope::walk_top(form, &mut pass);
    numbered(form, &pass)
}

fn numbered(node: &Spanned, pass: &Numbering) -> Spanned {
    let form = match &node.form {
        SpannedForm::Atom(Atom::Symbol(name)) => {
            let number = pass
                .references
                .get(&std::ptr::from_ref(node))
                .or_else(|| {
                    pass.binders
                        .get(&(node.span.start, node.span.end, name.clone()))
                })
                .copied();
            return match number {
                Some(n) => {
                    Spanned::new(node.span, SpannedForm::Atom(Atom::Symbol(format!("%l{n}"))))
                }
                None => node.clone(),
            };
        }
        SpannedForm::List(items) => {
            SpannedForm::List(items.iter().map(|i| numbered(i, pass)).collect())
        }
        SpannedForm::Quote(x) => SpannedForm::Quote(Box::new(numbered(x, pass))),
        SpannedForm::Quasiquote(x) => SpannedForm::Quasiquote(Box::new(numbered(x, pass))),
        SpannedForm::Unquote(x) => SpannedForm::Unquote(Box::new(numbered(x, pass))),
        SpannedForm::UnquoteSplice(x) => SpannedForm::UnquoteSplice(Box::new(numbered(x, pass))),
        other => other.clone(),
    };
    Spanned::new(node.span, form)
}
