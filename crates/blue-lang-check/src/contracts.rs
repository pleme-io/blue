use std::collections::{BTreeMap, BTreeSet};

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::names::{NameTable, Namespace};
use crate::{Applicability, Code, Diagnostic, Edit, Fix};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Kind {
    Map,
    List,
    Str,
    Num,
    Fn,
    Bool,
    Kw,
}

impl Kind {
    pub const ALL: &'static [Kind] = &[
        Kind::Map,
        Kind::List,
        Kind::Str,
        Kind::Num,
        Kind::Fn,
        Kind::Bool,
        Kind::Kw,
    ];

    #[must_use]
    pub const fn word(self) -> &'static str {
        match self {
            Kind::Map => "a map",
            Kind::List => "a list",
            Kind::Str => "a string",
            Kind::Num => "a number",
            Kind::Fn => "a function",
            Kind::Bool => "a boolean",
            Kind::Kw => "a keyword",
        }
    }

    #[must_use]
    pub const fn literal(self) -> &'static str {
        match self {
            Kind::Map => "{a: 1}",
            Kind::List => "[1, 2]",
            Kind::Str => "\"text\"",
            Kind::Num => "1",
            Kind::Fn => "(x) -> x",
            Kind::Bool => "true",
            Kind::Kw => ":k",
        }
    }
}

#[must_use]
pub fn kinds_of_parameter(name: &str) -> Option<&'static [Kind]> {
    match name {
        "f" | "g" | "pred" | "handler" | "listener" | "transform" => Some(&[Kind::Fn]),
        "xs" | "ys" => Some(&[Kind::List]),
        "m" => Some(&[Kind::Map]),
        "s" => Some(&[Kind::Str, Kind::Kw]),
        "n" => Some(&[Kind::Num]),
        _ => None,
    }
}

#[must_use]
pub fn parameters(signature: &str) -> Option<Vec<String>> {
    let open = signature.find('(')?;
    let close = signature.rfind(')')?;
    if close < open {
        return None;
    }
    let inner: String = signature[open + 1..close]
        .chars()
        .filter(|c| !matches!(c, '[' | ']'))
        .collect();
    if inner.trim().is_empty() {
        return Some(Vec::new());
    }
    let mut out = Vec::new();
    for p in inner.split(',') {
        let p = p.trim();
        if p.ends_with("...") || p == "…" {
            out.push(String::new());
            break;
        }
        if p.is_empty() || !p.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            out.push(String::new());
            continue;
        }
        out.push(p.to_string());
    }
    Some(out)
}

#[derive(Clone, Copy, Debug)]
pub struct BuiltinRow {
    pub name: &'static str,
    pub signature: &'static str,
    pub kinded: bool,
    pub guard: bool,
}

#[derive(Clone, Debug, Default)]
pub struct Signatures {
    params: BTreeMap<String, Vec<Option<&'static [Kind]>>>,
    guards: BTreeSet<String>,
}

impl Signatures {
    #[must_use]
    pub fn new(rows: &[BuiltinRow]) -> Self {
        let mut s = Signatures::default();
        for r in rows {
            if r.guard {
                s.guards.insert(r.name.to_string());
            }
            let Some(ps) = parameters(r.signature) else {
                continue;
            };
            if !r.signature.starts_with(&format!("{}(", r.name)) {
                continue;
            }
            if r.kinded {
                s.params.insert(
                    r.name.to_string(),
                    ps.iter().map(|p| kinds_of_parameter(p)).collect(),
                );
            }
        }
        s
    }

    fn kinds(&self, name: &str, i: usize) -> Option<&'static [Kind]> {
        self.params.get(name)?.get(i).copied().flatten()
    }

    #[must_use]
    pub fn collection_first(&self, name: &str) -> bool {
        let collection = self
            .kinds(name, 0)
            .is_some_and(|k| k.iter().all(|k| matches!(k, Kind::List | Kind::Map)));
        collection && self.kinds(name, 1) == Some(&[Kind::Fn])
    }

    pub fn collection_first_names(&self) -> impl Iterator<Item = &str> {
        self.params
            .keys()
            .map(String::as_str)
            .filter(|n| self.collection_first(n))
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Keys {
    Closed(BTreeSet<String>),
    Open,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Need {
    Any,
    Of(Vec<Kind>),
    Guarded,
}

impl Need {
    fn meet(&mut self, kinds: &[Kind]) {
        *self = match std::mem::replace(self, Need::Any) {
            Need::Any => Need::Of(kinds.to_vec()),
            Need::Of(have) => {
                let both: Vec<Kind> = have.into_iter().filter(|k| kinds.contains(k)).collect();
                if both.is_empty() {
                    Need::Guarded
                } else {
                    Need::Of(both)
                }
            }
            Need::Guarded => Need::Guarded,
        };
    }

    fn kinds(&self) -> Option<&[Kind]> {
        match self {
            Need::Of(k) => Some(k),
            _ => None,
        }
    }
}

#[derive(Clone, Debug)]
struct Param {
    name: String,
    optional: bool,
    keys: Keys,
    read: Vec<(String, Span)>,
    declared: Option<BTreeSet<String>>,
    need: Need,
    edges: Vec<(usize, usize)>,
}

struct Def<'a> {
    top: usize,
    params: Vec<Param>,
    rest_at: Option<usize>,
    body: &'a [Spanned],
    locals: BTreeSet<String>,
    returns_value: bool,
}

enum Callee<'s> {
    Def(usize),
    Builtin(&'s str),
    Unknown,
}

struct Program<'a> {
    defs: Vec<Def<'a>>,
    index: BTreeMap<(Namespace, String), usize>,
    table: &'a NameTable,
    namespace_of: &'a dyn Fn(usize) -> Namespace,
    sigs: &'a Signatures,
}

type Parts<'a> = (&'a str, Vec<(String, bool)>, Option<usize>, &'a [Spanned]);

fn define_parts(form: &Spanned) -> Option<Parts<'_>> {
    let items = form.as_list()?;
    let head = items.first()?.as_symbol()?;
    let body_from = match head {
        "define" => 2,
        "define-typed" => 3,
        _ => return None,
    };
    let sig = items.get(1)?.as_list()?;
    let name = sig.first()?.as_symbol()?;
    let mut params = Vec::new();
    let mut rest_at = None;
    let mut rest_next = false;
    let mut optional = false;
    for p in &sig[1..] {
        let n = p.as_symbol().or_else(|| {
            p.as_list()
                .and_then(|l| l.first())
                .and_then(Spanned::as_symbol)
        });
        let Some(n) = n else { continue };
        match n {
            "&optional" => optional = true,
            "&rest" => rest_next = true,
            _ if rest_next => {
                rest_at = Some(params.len());
                break;
            }
            _ => params.push((n.to_string(), optional)),
        }
    }
    Some((name, params, rest_at, items.get(body_from..).unwrap_or(&[])))
}

fn locals_of(body: &[Spanned], out: &mut BTreeSet<String>) {
    for s in body {
        let Some(items) = s.as_list() else { continue };
        match items.first().and_then(Spanned::as_symbol) {
            Some("define") => {
                if let Some(n) = items.get(1).and_then(Spanned::as_symbol) {
                    out.insert(n.to_string());
                }
                if let Some(sig) = items.get(1).and_then(Spanned::as_list) {
                    for p in sig {
                        if let Some(n) = p.as_symbol() {
                            out.insert(n.to_string());
                        }
                    }
                }
            }
            Some("lambda" | "fn") => {
                if let Some(ps) = items.get(1).and_then(Spanned::as_list) {
                    for p in ps {
                        if let Some(n) = p.as_symbol() {
                            out.insert(n.to_string());
                        }
                    }
                }
            }
            Some("let" | "let*" | "letrec") => {
                if let Some(bs) = items.get(1).and_then(Spanned::as_list) {
                    for b in bs {
                        if let Some(n) = b
                            .as_list()
                            .and_then(|l| l.first())
                            .and_then(Spanned::as_symbol)
                        {
                            out.insert(n.to_string());
                        }
                    }
                }
            }
            Some("try") => {
                if let Some(n) = items
                    .iter()
                    .filter_map(Spanned::as_list)
                    .filter(|l| l.first().and_then(Spanned::as_symbol) == Some("catch"))
                    .find_map(|l| {
                        l.get(1)
                            .and_then(Spanned::as_list)
                            .and_then(|b| b.first())
                            .and_then(Spanned::as_symbol)
                    })
                {
                    out.insert(n.to_string());
                }
            }
            _ => {}
        }
        locals_of(items, out);
    }
}

fn keyword_list(s: &Spanned) -> Option<BTreeSet<String>> {
    let items = s.as_list()?;
    if items.first()?.as_symbol()? != "list" {
        return None;
    }
    items[1..]
        .iter()
        .map(|k| k.as_keyword().map(str::to_string))
        .collect()
}

fn literal_kind(s: &Spanned) -> Option<Kind> {
    match &s.form {
        SpannedForm::Atom(Atom::Str(_)) => Some(Kind::Str),
        SpannedForm::Atom(Atom::Int(_) | Atom::Float(_)) => Some(Kind::Num),
        SpannedForm::Atom(Atom::Keyword(_)) => Some(Kind::Kw),
        SpannedForm::Atom(Atom::Bool(_)) => Some(Kind::Bool),
        SpannedForm::List(items) => match items.first().and_then(Spanned::as_symbol)? {
            "hash-map" | "blue-merge" => Some(Kind::Map),
            "list" => Some(Kind::List),
            "lambda" | "fn" => Some(Kind::Fn),
            "concat" if items[1..].iter().any(|i| i.as_string().is_some()) => Some(Kind::Str),
            _ => None,
        },
        _ => None,
    }
}

impl<'a> Program<'a> {
    fn resolve<'s>(&self, head: &'s str, top: usize, locals: &BTreeSet<String>) -> Callee<'s> {
        if locals.contains(head) {
            return Callee::Unknown;
        }
        if blue_lang_syntax::LOWERED_HEADS.contains(&head) || head == blue_lang_syntax::LOWERED_MAP
        {
            return Callee::Builtin(head);
        }
        if let Some((pkg, name)) = head.split_once('/') {
            if pkg == "blue" {
                return Callee::Builtin(name);
            }
            return self
                .index
                .get(&(Namespace::Bidama(pkg.to_string()), name.to_string()))
                .map_or(Callee::Unknown, |d| Callee::Def(*d));
        }
        if let Some(d) = self
            .index
            .get(&((self.namespace_of)(top), head.to_string()))
        {
            return Callee::Def(*d);
        }
        if let Some(pkgs) = self.table.imports_of(top).and_then(|f| f.names.get(head)) {
            if let [pkg] = pkgs.as_slice() {
                return self
                    .index
                    .get(&(Namespace::Bidama(pkg.clone()), head.to_string()))
                    .map_or(Callee::Unknown, |d| Callee::Def(*d));
            }
            return Callee::Unknown;
        }
        Callee::Builtin(head)
    }

    fn yields_value(&self, s: &Spanned, top: usize, locals: &BTreeSet<String>) -> bool {
        if matches!(s.form, SpannedForm::Nil) {
            return true;
        }
        if let Some(k) = literal_kind(s) {
            return k != Kind::Fn;
        }
        if let Some(n) = s.as_symbol() {
            return matches!(self.resolve(n, top, locals), Callee::Def(d) if self.defs[d].returns_value);
        }
        let Some(items) = s.as_list() else {
            return false;
        };
        match items.first().and_then(Spanned::as_symbol) {
            Some("begin") => items
                .last()
                .is_some_and(|l| self.yields_value(l, top, locals)),
            Some("if") => {
                items.len() >= 3 && items[2..].iter().all(|b| self.yields_value(b, top, locals))
            }
            Some(h) => {
                matches!(self.resolve(h, top, locals), Callee::Def(d) if self.defs[d].returns_value)
            }
            None => false,
        }
    }

    fn need_at(&self, callee: &Callee<'_>, j: usize) -> Option<Vec<Kind>> {
        match callee {
            Callee::Builtin(b) => self.sigs.kinds(b, j).map(<[Kind]>::to_vec),
            Callee::Def(d) => {
                let def = &self.defs[*d];
                if def.rest_at.is_some_and(|r| j >= r) {
                    return None;
                }
                def.params
                    .get(j)
                    .and_then(|p| p.need.kinds().map(<[Kind]>::to_vec))
            }
            Callee::Unknown => None,
        }
    }
}

fn is_alias(s: &Spanned, aliases: &BTreeSet<String>) -> bool {
    if let Some(n) = s.as_symbol() {
        return aliases.contains(n);
    }
    let Some(items) = s.as_list() else {
        return false;
    };
    match items.first().and_then(Spanned::as_symbol) {
        Some("or") => {
            items.len() == 3
                && is_alias(&items[1], aliases)
                && items[2]
                    .as_list()
                    .and_then(|l| l.first())
                    .and_then(Spanned::as_symbol)
                    == Some("hash-map")
                && items[2].as_list().is_some_and(|l| l.len() == 1)
        }
        Some("checked") => {
            items.len() == 3 && is_alias(&items[1], aliases) && keyword_list(&items[2]).is_some()
        }
        _ => false,
    }
}

fn declared_in(s: &Spanned, aliases: &BTreeSet<String>) -> Option<BTreeSet<String>> {
    let items = s.as_list()?;
    match items.first()?.as_symbol()? {
        "checked" if items.len() == 3 && is_alias(&items[1], aliases) => keyword_list(&items[2]),
        "or" => declared_in(&items[1], aliases),
        _ => None,
    }
}

fn aliases_of(param: &str, body: &[Spanned]) -> BTreeSet<String> {
    fn scan(s: &Spanned, set: &mut BTreeSet<String>, grew: &mut bool) {
        let Some(items) = s.as_list() else { return };
        if items.first().and_then(Spanned::as_symbol) == Some("define") && items.len() == 3 {
            if let Some(n) = items[1].as_symbol() {
                if !set.contains(n) && is_alias(&items[2], set) {
                    set.insert(n.to_string());
                    *grew = true;
                }
            }
        }
        if matches!(
            items.first().and_then(Spanned::as_symbol),
            Some("lambda" | "fn" | "quote")
        ) {
            return;
        }
        for i in items {
            scan(i, set, grew);
        }
    }
    let mut set = BTreeSet::from([param.to_string()]);
    loop {
        let mut grew = false;
        for s in body {
            scan(s, &mut set, &mut grew);
        }
        if !grew {
            return set;
        }
    }
}

struct Use<'p> {
    keys: Keys,
    read: Vec<(String, Span)>,
    declared: Option<BTreeSet<String>>,
    need: Need,
    edges: Vec<(usize, usize)>,
    program: &'p Program<'p>,
    top: usize,
    locals: &'p BTreeSet<String>,
    aliases: BTreeSet<String>,
}

impl Use<'_> {
    fn open(&mut self) {
        self.keys = Keys::Open;
    }

    fn add_key(&mut self, k: &str, span: Span) {
        if k == "nil?" {
            return;
        }
        if let Keys::Closed(set) = &mut self.keys {
            set.insert(k.to_string());
        }
        self.read.push((k.to_string(), span));
    }

    fn walk(&mut self, s: &Spanned) {
        if let Some(n) = s.as_symbol() {
            if self.aliases.contains(n) {
                self.open();
            }
            return;
        }
        let Some(items) = s.as_list() else {
            if matches!(s.form, SpannedForm::Quote(_) | SpannedForm::Quasiquote(_)) {
                return;
            }
            return;
        };
        let Some(head) = items.first() else { return };
        if let Some(h) = head.as_symbol() {
            if h == "quote" {
                return;
            }
            if h == "define"
                && items.len() == 3
                && items[1]
                    .as_symbol()
                    .is_some_and(|n| self.aliases.contains(n))
            {
                if let Some(d) = declared_in(&items[2], &self.aliases) {
                    self.declared = Some(d);
                }
                if is_alias(&items[2], &self.aliases) {
                    self.walk_alias_expr(&items[2]);
                    return;
                }
            }
        }
        if is_alias(head, &self.aliases) {
            self.need.meet(&[Kind::Fn]);
            self.open();
            for a in &items[1..] {
                self.walk(a);
            }
            return;
        }
        let head_name = head.as_symbol();
        for (j, a) in items.iter().enumerate().skip(1) {
            if is_alias(a, &self.aliases) {
                self.walk_alias_expr(a);
                match head_name {
                    Some(h) => self.classify(h, j - 1, items),
                    None => self.open(),
                }
            } else {
                self.walk(a);
            }
        }
        if head_name.is_none() {
            self.walk(head);
        }
    }

    fn walk_alias_expr(&mut self, a: &Spanned) {
        if let Some(d) = declared_in(a, &self.aliases) {
            self.declared = Some(d);
        }
    }

    fn classify(&mut self, head: &str, j: usize, items: &[Spanned]) {
        match head {
            "nil?" | "some?" | "define" => return,
            "if" | "when" | "and" | "not" if j == 0 => return,
            _ => {}
        }
        if (head == "get" || head == blue_lang_syntax::LOWERED_FIELD) && j == 0 {
            if let Some(k) = items.get(2).and_then(Spanned::as_keyword) {
                self.add_key(k, items[2].span);
                if head == blue_lang_syntax::LOWERED_FIELD {
                    return;
                }
            } else {
                self.open();
            }
        }
        if head == "checked" && j == 0 {
            return;
        }
        let program = self.program;
        let callee = program.resolve(head, self.top, self.locals);
        match callee {
            Callee::Builtin(b) => {
                if program.sigs.guards.contains(b) {
                    self.need = Need::Guarded;
                } else if let Some(k) = program.sigs.kinds(b, j) {
                    self.need.meet(k);
                }
                if b != "get" {
                    self.open();
                }
            }
            Callee::Def(d) => {
                let def = &program.defs[d];
                if def.rest_at.is_some_and(|r| j >= r) || j >= def.params.len() {
                    self.open();
                } else {
                    self.edges.push((d, j));
                }
            }
            Callee::Unknown => self.open(),
        }
    }
}

fn analyse<'a>(
    forms: &'a [Spanned],
    table: &'a NameTable,
    namespace_of: &'a dyn Fn(usize) -> Namespace,
    sigs: &'a Signatures,
) -> Program<'a> {
    let mut program = Program {
        defs: Vec::new(),
        index: BTreeMap::new(),
        table,
        namespace_of,
        sigs,
    };
    for (i, f) in forms.iter().enumerate() {
        if let Some((name, params, rest_at, body)) = define_parts(f) {
            let mut locals = BTreeSet::new();
            locals_of(body, &mut locals);
            for (p, _) in &params {
                locals.remove(p);
            }
            let ns = namespace_of(i);
            program
                .index
                .insert((ns, name.to_string()), program.defs.len());
            program.defs.push(Def {
                top: i,
                params: params
                    .into_iter()
                    .map(|(name, optional)| Param {
                        name,
                        optional,
                        keys: Keys::Closed(BTreeSet::new()),
                        read: Vec::new(),
                        declared: None,
                        need: Need::Any,
                        edges: Vec::new(),
                    })
                    .collect(),
                rest_at,
                body,
                locals,
                returns_value: false,
            });
        }
    }
    let mut found = Vec::new();
    for def in &program.defs {
        let mut per = Vec::new();
        for p in &def.params {
            let mut locals = def.locals.clone();
            let aliases = aliases_of(&p.name, def.body);
            for a in &aliases {
                locals.remove(a);
            }
            let mut u = Use {
                keys: Keys::Closed(BTreeSet::new()),
                read: Vec::new(),
                declared: None,
                need: Need::Any,
                edges: Vec::new(),
                program: &program,
                top: def.top,
                locals: &locals,
                aliases,
            };
            let shadowed = def.locals.contains(&p.name);
            for s in def.body {
                u.walk(s);
            }
            if shadowed {
                u.keys = Keys::Open;
                u.need = Need::Guarded;
            }
            per.push((u.keys, u.read, u.declared, u.need, u.edges));
        }
        found.push(per);
    }
    for (def, per) in program.defs.iter_mut().zip(found) {
        for (p, (keys, read, declared, need, edges)) in def.params.iter_mut().zip(per) {
            p.keys = keys;
            p.read = read;
            p.declared = declared;
            p.need = need;
            p.edges = edges;
        }
    }
    for _ in 0..32 {
        let mut changed = false;
        for d in 0..program.defs.len() {
            if !program.defs[d].returns_value
                && program.defs[d].body.last().is_some_and(|l| {
                    program.yields_value(l, program.defs[d].top, &program.defs[d].locals)
                })
            {
                program.defs[d].returns_value = true;
                changed = true;
            }
        }
        for d in 0..program.defs.len() {
            for k in 0..program.defs[d].params.len() {
                let edges = program.defs[d].params[k].edges.clone();
                let mut keys = program.defs[d].params[k].keys.clone();
                let mut need = program.defs[d].params[k].need.clone();
                for (e, j) in edges {
                    let callee = &program.defs[e].params[j];
                    match (&mut keys, &callee.keys) {
                        (Keys::Closed(mine), Keys::Closed(theirs)) => {
                            mine.extend(theirs.iter().cloned());
                        }
                        (Keys::Closed(_), Keys::Open) => keys = Keys::Open,
                        _ => {}
                    }
                    if let Need::Of(ks) = &callee.need {
                        need.meet(ks);
                    }
                }
                let p = &mut program.defs[d].params[k];
                if p.keys != keys || p.need != need {
                    p.keys = keys;
                    p.need = need;
                    changed = true;
                }
            }
        }
        if !changed {
            break;
        }
    }
    program
}

#[must_use]
pub fn check<'t>(
    forms: &[Spanned],
    table: &NameTable,
    namespace_of: &dyn Fn(usize) -> Namespace,
    is_entry: &dyn Fn(usize) -> bool,
    text_of: &dyn Fn(usize) -> Option<&'t str>,
    sigs: &Signatures,
) -> Vec<Diagnostic> {
    let program = analyse(forms, table, namespace_of, sigs);
    let mut out = Vec::new();
    for def in &program.defs {
        if !is_entry(def.top) {
            continue;
        }
        for p in &def.params {
            let Some(declared) = &p.declared else {
                continue;
            };
            for (k, span) in &p.read {
                if !declared.contains(k) {
                    out.push(
                        Diagnostic::new(
                            Code::B0061,
                            format!("`{}` reads the option `{k}`, which its `checked` list does not declare", p.name),
                            *span,
                        )
                        .at_top_level(def.top)
                        .with_help(format!("declare `:{k}` in the list, or read one of {}", listed(declared))),
                    );
                }
            }
        }
    }
    let mut globals = BTreeMap::new();
    for form in forms {
        if let Some([head, name, value]) = form.as_list() {
            if let (Some("define"), Some(n)) = (head.as_symbol(), name.as_symbol()) {
                globals
                    .entry(n.to_string())
                    .and_modify(|v| *v = None)
                    .or_insert(literal_kind(value));
            }
        }
    }
    for (i, form) in forms.iter().enumerate() {
        if !is_entry(i) {
            continue;
        }
        let mut locals = BTreeSet::new();
        if let Some((_, params, _, body)) = define_parts(form) {
            locals_of(body, &mut locals);
            locals.extend(params.into_iter().map(|(p, _)| p));
        } else {
            locals_of(std::slice::from_ref(form), &mut locals);
        }
        let mut known = BTreeMap::new();
        bound_literals(form, &mut known);
        let known: BTreeMap<String, Kind> = known
            .into_iter()
            .filter_map(|(n, k)| k.map(|k| (n, k)))
            .collect();
        let cx = Site {
            top: i,
            program: &program,
            locals: &locals,
            known: &known,
            globals: &globals,
            text: text_of(i),
        };
        calls(form, &cx, false, &mut out);
    }
    out
}

fn proves_refusal(head: &str, in_test: bool) -> bool {
    let bare = head.rsplit('/').next().unwrap_or(head);
    matches!(bare, "raises?" | "raised") || (in_test && bare == "try")
}

fn listed(keys: &BTreeSet<String>) -> String {
    if keys.is_empty() {
        return "no key".to_string();
    }
    keys.iter()
        .map(|k| format!("`{k}`"))
        .collect::<Vec<_>>()
        .join(", ")
}

struct Site<'s> {
    top: usize,
    program: &'s Program<'s>,
    locals: &'s BTreeSet<String>,
    known: &'s BTreeMap<String, Kind>,
    globals: &'s BTreeMap<String, Option<Kind>>,
    text: Option<&'s str>,
}

fn bound_literals(s: &Spanned, out: &mut BTreeMap<String, Option<Kind>>) {
    let Some(items) = s.as_list() else { return };
    if items.first().and_then(Spanned::as_symbol) == Some("define") && items.len() == 3 {
        if let Some(n) = items[1].as_symbol() {
            let k = literal_kind(&items[2]);
            out.entry(n.to_string())
                .and_modify(|v| *v = None)
                .or_insert(k);
        }
    }
    for i in items {
        bound_literals(i, out);
    }
}

fn calls(s: &Spanned, cx: &Site<'_>, in_test: bool, out: &mut Vec<Diagnostic>) {
    let (top, program, locals) = (cx.top, cx.program, cx.locals);
    let Some(items) = s.as_list() else { return };
    let Some(head) = items.first() else { return };
    let h = head.as_symbol();
    if matches!(
        h,
        Some("quote" | "quasiquote" | "define" | "define-typed" | "defmacro")
    ) {
        if matches!(h, Some("define" | "define-typed")) {
            let from = if h == Some("define-typed") { 3 } else { 2 };
            for b in items.get(from..).unwrap_or(&[]) {
                calls(b, cx, in_test, out);
            }
        }
        return;
    }
    if h.is_some_and(|h| proves_refusal(h, in_test)) {
        return;
    }
    let in_test = in_test || h == Some("deftest");
    if let Some(h) = h {
        let callee = program.resolve(h, top, locals);
        for j in 0..items.len() - 1 {
            contract(h, &callee, j, &items[1..], cx, out);
        }
    }
    for i in items {
        calls(i, cx, in_test, out);
    }
}

fn contract(
    head: &str,
    callee: &Callee<'_>,
    j: usize,
    args: &[Spanned],
    cx: &Site<'_>,
    out: &mut Vec<Diagnostic>,
) {
    let arg = &args[j];
    let (top, program, locals) = (cx.top, cx.program, cx.locals);
    let shown = head.replace('/', "::");
    if let Callee::Def(d) = callee {
        let def = &program.defs[*d];
        let param = (!def.rest_at.is_some_and(|r| j >= r))
            .then(|| def.params.get(j))
            .flatten();
        if let Some(p) = param {
            let options = p.optional || p.name == "opts" || p.name == "options";
            let set = match (&p.declared, &p.keys) {
                (Some(d), _) => Some(d),
                (None, Keys::Closed(k)) if options && !k.is_empty() => Some(k),
                _ => None,
            };
            if let (Some(set), Some(entries)) = (set, map_literal(arg)) {
                for (k, span) in entries {
                    if !set.contains(&k) {
                        let near = set
                            .iter()
                            .filter_map(|c| crate::suggest::closeness(&k, c).map(|d| (d, c)))
                            .min()
                            .map(|(_, c)| format!("; did you mean `{c}`?"))
                            .unwrap_or_default();
                        out.push(
                            Diagnostic::new(
                                Code::B0061,
                                format!("`{shown}` reads no option `{k}` from `{}`{near}", p.name),
                                span,
                            )
                            .at_top_level(top)
                            .with_help(format!(
                                "`{}` takes {}",
                                p.name,
                                listed(set)
                            )),
                        );
                    }
                }
            }
        }
    }
    let Some(need) = program.need_at(callee, j) else {
        return;
    };
    let bound = arg.as_symbol().and_then(|n| cx.known.get(n).copied());
    if let Some(kind) = literal_kind(arg).or(bound) {
        if !need.contains(&kind) {
            let want: Vec<&str> = need.iter().map(|k| k.word()).collect();
            let found = Diagnostic::new(
                Code::B0062,
                format!(
                    "argument {} of `{shown}` takes {}, and this is {}",
                    j + 1,
                    want.join(" or "),
                    kind.word()
                ),
                arg.span,
            )
            .at_top_level(top);
            out.push(match swap_fix(callee, j, args, cx) {
                Some(fix) => found
                    .with_help(format!(
                        "`{shown}` takes the collection first: `blue check --fix` swaps the two arguments"
                    ))
                    .with_fix(fix),
                None => found.with_help(format!(
                    "pass {}, or test the kind before the call",
                    want.join(" or ")
                )),
            });
        }
        return;
    }
    if need.as_slice() != [Kind::Fn] {
        return;
    }
    let Some(name) = arg.as_symbol() else { return };
    if locals.contains(name) {
        return;
    }
    let nullary = match program.resolve(name, top, locals) {
        Callee::Def(d) => {
            program.defs[d].params.is_empty()
                && program.defs[d].rest_at.is_none()
                && program.defs[d].returns_value
        }
        Callee::Builtin(_) | Callee::Unknown => false,
    };
    if !nullary {
        return;
    }
    let spelled = name.replace('/', "::");
    let replacement = format!("() -> {spelled}");
    out.push(
        Diagnostic::new(
            Code::B0063,
            format!("`{spelled}` takes no argument, so it is called here and `{shown}` gets its value, not the function"),
            arg.span,
        )
        .at_top_level(top)
        .with_help(format!("pass the function: `{replacement}`"))
        .with_fix(Fix {
            message: format!("write `{replacement}`"),
            edits: vec![Edit {
                span: arg.span,
                original: spelled,
                replacement,
            }],
            applicability: Applicability::MaybeIncorrect,
        }),
    );
}

fn swap_fix(callee: &Callee<'_>, j: usize, args: &[Spanned], cx: &Site<'_>) -> Option<Fix> {
    let collection_first = match callee {
        Callee::Builtin(b) => cx.program.sigs.collection_first(b),
        Callee::Def(_) => {
            cx.program.need_at(callee, 0).is_some_and(|k| {
                !k.is_empty() && k.iter().all(|k| matches!(k, Kind::List | Kind::Map))
            }) && cx.program.need_at(callee, 1).as_deref() == Some(&[Kind::Fn])
        }
        Callee::Unknown => false,
    };
    if j != 0 || !collection_first {
        return None;
    }
    let (f, xs) = (args.first()?, args.get(1)?);
    if literal_kind(f) != Some(Kind::Fn) || may_be_function(xs, cx) {
        return None;
    }
    let text = cx.text?;
    let (fs, xss) = (
        text.get(f.span.start..f.span.end)?,
        text.get(xs.span.start..xs.span.end)?,
    );
    if !reads_as(fs, f) || !reads_as(xss, xs) {
        return None;
    }
    let between = text.get(f.span.end..xs.span.start)?;
    let span = Span::new(f.span.start, xs.span.end);
    Some(Fix {
        message: "put the collection first".to_string(),
        edits: vec![Edit {
            span,
            original: text.get(span.start..span.end)?.to_string(),
            replacement: format!("{xss}{between}{fs}"),
        }],
        applicability: Applicability::MachineApplicable,
    })
}

fn may_be_function(s: &Spanned, cx: &Site<'_>) -> bool {
    if literal_kind(s).is_some_and(|k| k == Kind::Fn) {
        return true;
    }
    let Some(name) = s.as_symbol() else {
        return false;
    };
    if cx.known.get(name) == Some(&Kind::Fn) {
        return true;
    }
    if cx.locals.contains(name) {
        return false;
    }
    match cx.program.resolve(name, cx.top, cx.locals) {
        Callee::Def(d) => {
            let def = &cx.program.defs[d];
            !def.params.is_empty() || def.rest_at.is_some() || !def.returns_value
        }
        Callee::Builtin(b) => cx
            .globals
            .get(b)
            .is_none_or(|k| k.is_none_or(|k| k == Kind::Fn)),
        Callee::Unknown => true,
    }
}

fn reads_as(slice: &str, s: &Spanned) -> bool {
    matches!(
        blue_lang_syntax::parse_program_tree(slice).as_deref(),
        Ok([one]) if one.to_sexp() == s.to_sexp()
    )
}

fn map_literal(s: &Spanned) -> Option<Vec<(String, Span)>> {
    let items = s.as_list()?;
    if items.first()?.as_symbol()? != "hash-map" {
        return None;
    }
    let mut out = Vec::new();
    for pair in items[1..].chunks(2) {
        let k = pair[0].as_keyword()?;
        out.push((k.to_string(), pair[0].span));
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use blue_lang_syntax::parse_program_tree;

    const ROWS: &[BuiltinRow] = &[
        BuiltinRow {
            name: "get",
            signature: "get(m, k)",
            kinded: true,
            guard: false,
        },
        BuiltinRow {
            name: "map",
            signature: "map(f, xs, more...)",
            kinded: true,
            guard: false,
        },
        BuiltinRow {
            name: "find",
            signature: "find(xs, f)",
            kinded: true,
            guard: false,
        },
        BuiltinRow {
            name: "string?",
            signature: "string?(x)",
            kinded: false,
            guard: true,
        },
        BuiltinRow {
            name: "now_ms",
            signature: "now_ms()",
            kinded: false,
            guard: false,
        },
    ];

    fn codes(src: &str) -> Vec<(Code, String)> {
        let forms = parse_program_tree(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        let mut table = NameTable::new();
        table.add_program(&forms, |_| Namespace::File("t.b".into()));
        check(
            &forms,
            &table,
            &|_| Namespace::File("t.b".into()),
            &|_| true,
            &|_| Some(src),
            &Signatures::new(ROWS),
        )
        .into_iter()
        .map(|d| (d.code, src[d.span.start..d.span.end].to_string()))
        .collect()
    }

    fn fixed(src: &str) -> String {
        let forms = parse_program_tree(src).unwrap_or_else(|e| panic!("{src:?}: {e}"));
        let mut table = NameTable::new();
        table.add_program(&forms, |_| Namespace::File("t.b".into()));
        let found = check(
            &forms,
            &table,
            &|_| Namespace::File("t.b".into()),
            &|_| true,
            &|_| Some(src),
            &Signatures::new(ROWS),
        );
        crate::fixes::apply_machine_fixes(&found, &|_| true, src).0
    }

    #[test]
    fn the_collection_first_builtins_are_read_from_the_signatures() {
        let sigs = Signatures::new(ROWS);
        let names: Vec<&str> = sigs.collection_first_names().collect();
        assert_eq!(names, vec!["find"]);
    }

    #[test]
    fn a_function_literal_before_the_collection_is_swapped() {
        assert_eq!(
            fixed("def big(ys)\n  find((x) -> x > 1, ys)\nend\n"),
            "def big(ys)\n  find(ys, (x) -> x > 1)\nend\n"
        );
        assert_eq!(
            fixed("find(fn(x)\n  x\nend, [1])\n"),
            "find([1], fn(x)\n  x\nend)\n"
        );
    }

    #[test]
    fn a_definition_that_takes_the_collection_first_is_swapped_too() {
        assert_eq!(
            fixed("def fm(xs, f)\n  find(xs, f)\nend\n\nfm((x) -> x, [1])\n"),
            "def fm(xs, f)\n  find(xs, f)\nend\n\nfm([1], (x) -> x)\n"
        );
    }

    #[test]
    fn a_global_list_is_swapped_in() {
        assert_eq!(
            fixed("ys = [1]\nfind((x) -> x, ys)\n"),
            "ys = [1]\nfind(ys, (x) -> x)\n"
        );
    }

    #[test]
    fn a_swap_that_could_change_meaning_is_left_as_a_suggestion() {
        for src in [
            "def inc(x)\n  x + 1\nend\n\nfind((x) -> x, inc)\n",
            "find((x) -> x, (y) -> y)\n",
            "g = (y) -> y\nfind((x) -> x, g)\n",
            "find(5, (x) -> x)\n",
            "map([1], (x) -> x)\n",
            "find((x) -> x, length)\n",
        ] {
            assert_eq!(fixed(src), src);
        }
    }

    #[test]
    fn a_key_the_function_does_not_read_is_refused_at_the_call() {
        let src = "def prepared(sc, opts)\n  get(opts, :vars)\nend\n\ndef execute(sc, opts?)\n  o = opts or {}\n  prepared(sc, o)\nend\n\nexecute(1, {variables: 2})\nexecute(1, {vars: 2})\n";
        assert_eq!(codes(src), vec![(Code::B0061, "variables:".to_string())]);
    }

    #[test]
    fn a_checked_list_closes_the_reads() {
        let src = "def f(opts)\n  opts = checked(opts, [:a])\n  [get(opts, :a), opts.b]\nend\n\ndef checked(o, ks)\n  o\nend\n";
        assert_eq!(codes(src), vec![(Code::B0061, "b".to_string())]);
    }

    #[test]
    fn an_escaping_record_is_open() {
        let src = "def f(opts)\n  [get(opts, :a), opts]\nend\n\nf({b: 1})\n";
        assert!(codes(src).is_empty());
    }

    #[test]
    fn a_literal_of_the_wrong_kind_is_refused_through_a_parameter() {
        let src = "def kind_of(schema)\n  get(schema, :kind)\nend\n\nkind_of(\"text\")\nkind_of({kind: 1})\n\ntest \"t\"\n  sdl = \"type Query\"\n  assert kind_of(sdl).nil?\nend\n";
        assert_eq!(
            codes(src),
            vec![
                (Code::B0062, "\"text\"".to_string()),
                (Code::B0062, "sdl".to_string())
            ]
        );
    }

    #[test]
    fn a_kind_test_lifts_the_need() {
        let src = "def kind_of(schema)\n  if string?(schema)\n    schema\n  else\n    get(schema, :kind)\n  end\nend\n\nkind_of(\"text\")\n";
        assert!(codes(src).is_empty());
    }

    #[test]
    fn a_bare_nullary_name_where_a_function_goes_is_refused_with_its_lambda() {
        let src = "def gate(name, f)\n  r = f()\n  [name, r]\nend\n\ndef pin()\n  1\nend\n\ngate(\"a\", pin)\ngate(\"b\", () -> pin)\nmap(pin, [1])\n";
        assert_eq!(
            codes(src),
            vec![
                (Code::B0063, "pin".to_string()),
                (Code::B0063, "pin".to_string())
            ]
        );
    }

    #[test]
    fn a_nullary_definition_that_returns_a_function_is_passed_bare() {
        let src = "def text()\n  (v) -> v\nend\n\ndef site()\n  router([])\nend\n\nmap(text, [1])\nmap(site, [1])\n";
        assert!(codes(src).is_empty());
    }

    #[test]
    fn a_call_that_proves_a_refusal_is_not_reported() {
        let src = "def f(opts)\n  get(opts, :a)\nend\n\ntest \"t\"\n  assert raises?(:bad_option, () -> f({b: 1}))\n  r = f({b: 1}) rescue nil\n  assert r.nil?\nend\n";
        assert!(codes(src).is_empty());
    }
}
