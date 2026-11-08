use std::collections::BTreeMap;

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};

use crate::parse::{list_at, sym_at, ParseError, LOWERED_MAP, LOWERED_SPLICE};
use crate::record::record_parts;
use crate::union::union_parts;

pub const LOWERED_BIND: &str = "blue-bind";

pub const CASE_SUBJECT: &str = "case-subject";

pub const BIND_SUBJECT: &str = "bind-subject";

pub const SHAPE_LIST: &str = "blue-shape-list?";

pub const SHAPE_KEY: &str = "blue-shape-key?";

pub const SHAPE_AT: &str = "blue-shape-at";

pub const SHAPE_FROM: &str = "blue-shape-from";

pub const SHAPE_REFUSE: &str = "blue-shape-refuse";

pub const WILDCARD: &str = "_";

pub const SHAPE_WORDS: &[&str] = &[SHAPE_LIST, SHAPE_KEY, SHAPE_AT, SHAPE_FROM, SHAPE_REFUSE];

#[derive(Clone, Debug)]
struct Shape {
    name: String,
    predicate: String,
    fields: Vec<String>,
}

#[derive(Default)]
struct Shapes {
    by_name: BTreeMap<String, Shape>,
    by_predicate: BTreeMap<String, String>,
}

impl Shapes {
    fn add(&mut self, r: &crate::record::Record<'_>) {
        let (Some(name), Some(predicate)) = (r.name.as_symbol(), r.predicate.as_symbol()) else {
            return;
        };
        self.by_predicate
            .insert(predicate.to_string(), name.to_string());
        self.by_name.insert(
            name.to_string(),
            Shape {
                name: name.to_string(),
                predicate: predicate.to_string(),
                fields: r.field_names().iter().map(|f| (*f).to_string()).collect(),
            },
        );
    }

    fn of(forms: &[Spanned]) -> Self {
        let mut s = Self::default();
        for f in forms {
            if let Some(r) = record_parts(f) {
                s.add(&r);
            }
            if let Some(u) = union_parts(f) {
                for r in &u.arms {
                    s.add(r);
                }
            }
        }
        s
    }

    fn by_predicate(&self, p: &str) -> Option<&Shape> {
        self.by_name.get(self.by_predicate.get(p)?)
    }
}

enum Pat<'a> {
    Wild,
    Bind(&'a Spanned),
    Lit(&'a Spanned),
    List {
        items: Vec<Pat<'a>>,
        rest: Option<&'a Spanned>,
    },
    Map {
        entries: Vec<(&'a Spanned, Pat<'a>)>,
    },
    Record {
        shape: Shape,
        args: Vec<Pat<'a>>,
    },
}

impl Pat<'_> {
    fn destructures(&self) -> bool {
        match self {
            Pat::Wild | Pat::Bind(_) => true,
            Pat::Lit(_) => false,
            Pat::List { items, rest, .. } => rest.is_some() || items.iter().any(Pat::destructures),
            Pat::Map { entries, .. } => entries.iter().any(|(_, p)| p.destructures()),
            Pat::Record { args, .. } => args.iter().any(Pat::destructures),
        }
    }
}

fn head_of(form: &Spanned) -> Option<&str> {
    form.as_list()?.first()?.as_symbol()
}

fn splice_name(form: &Spanned) -> Option<&Spanned> {
    match form.as_list()? {
        [h, name] if h.as_symbol() == Some(LOWERED_SPLICE) && name.as_symbol().is_some() => {
            Some(name)
        }
        _ => None,
    }
}

fn read<'a>(p: &'a Spanned, shapes: &Shapes, top: bool) -> Result<Pat<'a>, ParseError> {
    if let Some(name) = p.as_symbol() {
        if top {
            return Ok(Pat::Lit(p));
        }
        return Ok(if name == WILDCARD {
            Pat::Wild
        } else {
            Pat::Bind(p)
        });
    }
    let Some(items) = p.as_list() else {
        return Ok(Pat::Lit(p));
    };
    let Some(head) = items.first().and_then(Spanned::as_symbol) else {
        return Ok(Pat::Lit(p));
    };
    if head == "list" {
        let mut out = Vec::new();
        let mut rest = None;
        let elems = &items[1..];
        for (i, e) in elems.iter().enumerate() {
            if let Some(name) = splice_name(e) {
                if i + 1 != elems.len() {
                    return Err(ParseError::new(
                        "a `*rest` takes what is left of the list, so it comes last",
                        e.span,
                    ));
                }
                rest = Some(name);
                continue;
            }
            out.push(read(e, shapes, false)?);
        }
        return Ok(Pat::List { items: out, rest });
    }
    if head == LOWERED_MAP && !items.len().is_multiple_of(2) {
        let pairs: Vec<&[Spanned]> = items[1..].chunks(2).collect();
        if pairs.iter().all(|kv| kv[0].as_keyword().is_some()) {
            let mut entries = Vec::new();
            for kv in pairs {
                entries.push((&kv[0], read(&kv[1], shapes, false)?));
            }
            return Ok(Pat::Map { entries });
        }
        return Ok(Pat::Lit(p));
    }
    if let Some(shape) = shapes.by_name.get(head) {
        if shape.fields.len() == items.len() - 1 {
            let args = items[1..]
                .iter()
                .map(|a| read(a, shapes, false))
                .collect::<Result<Vec<_>, _>>()?;
            return Ok(Pat::Record {
                shape: shape.clone(),
                args,
            });
        }
    }
    Ok(Pat::Lit(p))
}

fn int_at(at: Span, n: usize) -> Spanned {
    Spanned::new(
        at,
        SpannedForm::Atom(Atom::Int(i64::try_from(n).unwrap_or(i64::MAX))),
    )
}

fn keyword_at(at: Span, k: &str) -> Spanned {
    Spanned::new(at, SpannedForm::Atom(Atom::Keyword(k.to_string())))
}

fn call(at: Span, head: &str, args: Vec<Spanned>) -> Spanned {
    let mut items = vec![sym_at(at, head)];
    items.extend(args);
    list_at(at, items)
}

struct Compiled {
    tests: Vec<Spanned>,
    binds: Vec<(Spanned, Spanned)>,
}

fn compile(p: &Pat<'_>, access: &Spanned, out: &mut Compiled) -> Result<(), ParseError> {
    let span = access.span;
    match p {
        Pat::Wild => {}
        Pat::Bind(name) => {
            let text = name.as_symbol().unwrap_or_default();
            if out.binds.iter().any(|(n, _)| n.as_symbol() == Some(text)) {
                return Err(ParseError::new(
                    format!("this pattern binds `{text}` twice"),
                    name.span,
                ));
            }
            out.binds.push(((*name).clone(), access.clone()));
        }
        Pat::Lit(v) => out
            .tests
            .push(call(span, "equal?", vec![access.clone(), (*v).clone()])),
        Pat::List { items, rest, .. } => {
            out.tests.push(call(
                span,
                SHAPE_LIST,
                vec![
                    access.clone(),
                    int_at(span, items.len()),
                    Spanned::new(span, SpannedForm::Atom(Atom::Bool(rest.is_some()))),
                ],
            ));
            for (i, item) in items.iter().enumerate() {
                let here = call(span, SHAPE_AT, vec![access.clone(), int_at(span, i)]);
                compile(item, &here, out)?;
            }
            if let Some(name) = rest {
                let from = call(
                    span,
                    SHAPE_FROM,
                    vec![access.clone(), int_at(span, items.len())],
                );
                compile(&read(name, &Shapes::default(), false)?, &from, out)?;
            }
        }
        Pat::Map { entries, .. } => {
            for (k, v) in entries {
                out.tests
                    .push(call(span, SHAPE_KEY, vec![access.clone(), (*k).clone()]));
                let here = call(span, SHAPE_AT, vec![access.clone(), (*k).clone()]);
                compile(v, &here, out)?;
            }
        }
        Pat::Record { shape, args, .. } => {
            let test = if access.as_symbol() == Some(CASE_SUBJECT) {
                call(
                    span,
                    "equal?",
                    vec![access.clone(), sym_at(span, &shape.predicate)],
                )
            } else {
                call(span, &shape.predicate, vec![access.clone()])
            };
            out.tests.push(test);
            for (arg, field) in args.iter().zip(&shape.fields) {
                let here = call(
                    span,
                    SHAPE_AT,
                    vec![access.clone(), keyword_at(span, field)],
                );
                compile(arg, &here, out)?;
            }
        }
    }
    Ok(())
}

fn all_of(at: Span, mut tests: Vec<Spanned>) -> Spanned {
    if tests.len() == 1 {
        return tests.remove(0);
    }
    call(at, "and", tests)
}

fn let_form(at: Span, binds: Vec<(Spanned, Spanned)>, body: Spanned) -> Spanned {
    let pairs = binds
        .into_iter()
        .map(|(n, a)| list_at(n.span.merge(a.span), vec![n, a]))
        .collect();
    list_at(at, vec![sym_at(at, "let"), list_at(at, pairs), body])
}

fn subject_of(form: &Spanned, word: &str) -> Option<Spanned> {
    match form.as_list()? {
        [l, binding, cond] if l.as_symbol() == Some("let") => {
            let [only] = binding.as_list()? else {
                return None;
            };
            let [name, _] = only.as_list()? else {
                return None;
            };
            (name.as_symbol() == Some(word) && head_of(cond) == Some("cond")).then(|| name.clone())
        }
        _ => None,
    }
}

fn lower_clause(clause: Spanned, shapes: &Shapes) -> Result<Spanned, ParseError> {
    let at = clause.span;
    let SpannedForm::List(mut parts) = clause.form else {
        return Ok(clause);
    };
    let [test, _] = parts.as_slice() else {
        return Ok(list_at(at, parts));
    };
    let pattern = match test.as_list() {
        Some([eq, s, p])
            if eq.as_symbol() == Some("equal?") && s.as_symbol() == Some(CASE_SUBJECT) =>
        {
            p.clone()
        }
        _ => return Ok(list_at(at, parts)),
    };
    let pat = read(&pattern, shapes, true)?;
    if matches!(pat, Pat::Lit(_)) || !pat.destructures() {
        return Ok(list_at(at, parts));
    }
    let mut out = Compiled {
        tests: Vec::new(),
        binds: Vec::new(),
    };
    compile(&pat, &sym_at(pattern.span, CASE_SUBJECT), &mut out)?;
    let body = parts.pop().expect("a clause is (test body)");
    Ok(list_at(
        at,
        vec![
            all_of(pattern.span, out.tests),
            let_form(at, out.binds, body),
        ],
    ))
}

fn lower_case(form: Spanned, shapes: &Shapes) -> Result<Spanned, ParseError> {
    if subject_of(&form, CASE_SUBJECT).is_none() {
        return Ok(form);
    }
    let span = form.span;
    let SpannedForm::List(mut items) = form.form else {
        return Ok(form);
    };
    let cond = items.pop().expect("a case is (let bind cond)");
    let cond_at = cond.span;
    let SpannedForm::List(clauses) = cond.form else {
        items.push(cond);
        return Ok(list_at(span, items));
    };
    let mut out = Vec::with_capacity(clauses.len());
    for (k, c) in clauses.into_iter().enumerate() {
        out.push(if k == 0 { c } else { lower_clause(c, shapes)? });
    }
    items.push(list_at(cond_at, out));
    Ok(list_at(span, items))
}

fn bind_statements(form: &Spanned, shapes: &Shapes) -> Result<Option<Vec<Spanned>>, ParseError> {
    let Some([head, pattern, value]) = form.as_list() else {
        return Ok(None);
    };
    if head.as_symbol() != Some(LOWERED_BIND) {
        return Ok(None);
    }
    let pat = read(pattern, shapes, true)?;
    if !matches!(pat, Pat::List { .. } | Pat::Map { .. }) {
        return Err(ParseError::new(
            "a destructuring binding takes a list `[a, b]` or a map `{name:}` on the left",
            pattern.span,
        ));
    }
    let at = form.span;
    let subject = sym_at(pattern.span, BIND_SUBJECT);
    let mut out = Compiled {
        tests: Vec::new(),
        binds: Vec::new(),
    };
    compile(&pat, &subject, &mut out)?;
    let text = Spanned::new(pattern.span, SpannedForm::Atom(Atom::Str(shown(pattern))));
    let mut stmts = vec![
        call(at, "define", vec![subject.clone(), value.clone()]),
        call(
            at,
            "if",
            vec![
                call(pattern.span, "not", vec![all_of(pattern.span, out.tests)]),
                call(pattern.span, SHAPE_REFUSE, vec![text, subject.clone()]),
            ],
        ),
    ];
    stmts.extend(
        out.binds
            .into_iter()
            .map(|(n, a)| call(n.span.merge(a.span), "define", vec![n, a])),
    );
    Ok(Some(stmts))
}

fn splice(items: Vec<Spanned>, shapes: &Shapes) -> Result<Vec<Spanned>, ParseError> {
    let mut out = Vec::with_capacity(items.len());
    for item in items {
        match bind_statements(&item, shapes)? {
            Some(stmts) => out.extend(stmts),
            None => out.push(item),
        }
    }
    Ok(out)
}

fn stray_rest(items: &[Spanned]) -> Option<Span> {
    if items.first().and_then(Spanned::as_symbol) != Some("list") {
        return None;
    }
    items[1..]
        .iter()
        .find_map(|e| splice_name(e).map(|_| e.span))
}

fn walk(form: Spanned, shapes: &Shapes) -> Result<Spanned, ParseError> {
    let span = form.span;
    let SpannedForm::List(items) = form.form else {
        return Ok(form);
    };
    let form = list_at(span, items);
    if let Some(stmts) = bind_statements(&form, shapes)? {
        let inner = stmts
            .into_iter()
            .map(|s| walk(s, shapes))
            .collect::<Result<Vec<_>, _>>()?;
        let mut seq = vec![sym_at(span, "begin")];
        seq.extend(inner);
        return Ok(list_at(span, seq));
    }
    let form = lower_case(form, shapes)?;
    let SpannedForm::List(items) = form.form else {
        return Ok(form);
    };
    if let Some(at) = stray_rest(&items) {
        return Err(ParseError::new(
            "a `*rest` takes the rest of a list only in a pattern: a `when`, or the left of `=`",
            at,
        ));
    }
    let items = if items.first().and_then(Spanned::as_symbol) == Some("begin") {
        splice(items, shapes)?
    } else {
        items
    };
    let items = items
        .into_iter()
        .map(|i| walk(i, shapes))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(list_at(span, items))
}

pub fn lower(forms: Vec<Spanned>) -> Result<Vec<Spanned>, ParseError> {
    let shapes = Shapes::of(&forms);
    splice(forms, &shapes)?
        .into_iter()
        .map(|f| walk(f, &shapes))
        .collect()
}

fn shown(p: &Spanned) -> String {
    let joined = |xs: &[Spanned]| xs.iter().map(shown).collect::<Vec<_>>().join(", ");
    if let Some(name) = splice_name(p) {
        return format!("*{}", name.as_symbol().unwrap_or_default());
    }
    match &p.form {
        SpannedForm::Atom(Atom::Symbol(s)) => s.clone(),
        SpannedForm::Atom(Atom::Keyword(k)) => format!(":{k}"),
        SpannedForm::Atom(Atom::Str(s)) => format!("{s:?}"),
        SpannedForm::Atom(Atom::Int(n)) => n.to_string(),
        SpannedForm::Atom(Atom::Float(x)) => format!("{x:?}"),
        SpannedForm::Atom(Atom::Bool(b)) => b.to_string(),
        SpannedForm::Nil => "nil".to_string(),
        SpannedForm::List(items) => match items.split_first() {
            Some((h, rest)) if h.as_symbol() == Some("list") => format!("[{}]", joined(rest)),
            Some((h, rest)) if h.as_symbol() == Some(LOWERED_MAP) => {
                let entries: Vec<String> = rest
                    .chunks(2)
                    .map(|kv| match (kv[0].as_keyword(), kv.get(1)) {
                        (Some(k), Some(v)) if v.as_symbol() == Some(k) => format!("{k}:"),
                        (Some(k), Some(v)) => format!("{k}: {}", shown(v)),
                        _ => joined(kv),
                    })
                    .collect();
                format!("{{{}}}", entries.join(", "))
            }
            Some((h, rest)) if h.as_symbol().is_some() => {
                format!("{}({})", h.as_symbol().unwrap_or_default(), joined(rest))
            }
            _ => p.to_sexp().to_string(),
        },
        _ => p.to_sexp().to_string(),
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Step {
    At(i64),
    Key(String),
}

#[derive(Default)]
struct Node {
    list: Option<(usize, bool)>,
    keys: Vec<String>,
    record: Option<Shape>,
    lit: Option<Spanned>,
    bind: Option<Spanned>,
    rest: Option<Spanned>,
}

fn path_of(access: &Spanned, root: &str) -> Option<(Vec<Step>, bool)> {
    if access.as_symbol() == Some(root) {
        return Some((Vec::new(), false));
    }
    match access.as_list()? {
        [h, inner, step] if h.as_symbol() == Some(SHAPE_AT) => {
            let (mut path, false) = path_of(inner, root)? else {
                return None;
            };
            path.push(match (step.as_int(), step.as_keyword()) {
                (Some(i), _) => Step::At(i),
                (_, Some(k)) => Step::Key(k.to_string()),
                _ => return None,
            });
            Some((path, false))
        }
        [h, inner, _] if h.as_symbol() == Some(SHAPE_FROM) => {
            let (path, false) = path_of(inner, root)? else {
                return None;
            };
            Some((path, true))
        }
        _ => None,
    }
}

struct Tree {
    nodes: BTreeMap<Vec<Step>, Node>,
}

impl Tree {
    fn node(&mut self, path: Vec<Step>) -> &mut Node {
        self.nodes.entry(path).or_default()
    }

    fn test(&mut self, t: &Spanned, root: &str, shapes: &Shapes) -> Option<()> {
        let items = t.as_list()?;
        let head = items.first()?.as_symbol()?;
        match (head, &items[1..]) {
            (SHAPE_LIST, [a, n, open]) => {
                let (path, false) = path_of(a, root)? else {
                    return None;
                };
                let open = matches!(open.form, SpannedForm::Atom(Atom::Bool(true)));
                self.node(path).list = Some((usize::try_from(n.as_int()?).ok()?, open));
            }
            (SHAPE_KEY, [a, k]) => {
                let (path, false) = path_of(a, root)? else {
                    return None;
                };
                self.node(path).keys.push(k.as_keyword()?.to_string());
            }
            ("equal?", [a, v]) => {
                let (path, false) = path_of(a, root)? else {
                    return None;
                };
                match v.as_symbol().and_then(|p| shapes.by_predicate(p)) {
                    Some(shape) if path.is_empty() && root == CASE_SUBJECT => {
                        self.node(path).record = Some(shape.clone());
                    }
                    _ => self.node(path).lit = Some(v.clone()),
                }
            }
            (pred, [a]) => {
                let shape = shapes.by_predicate(pred)?.clone();
                let (path, false) = path_of(a, root)? else {
                    return None;
                };
                self.node(path).record = Some(shape);
            }
            _ => return None,
        }
        Some(())
    }

    fn bind(&mut self, name: &Spanned, access: &Spanned, root: &str) -> Option<()> {
        let (path, rest) = path_of(access, root)?;
        let node = self.node(path);
        if rest {
            node.rest = Some(name.clone());
        } else {
            node.bind = Some(name.clone());
        }
        Some(())
    }

    fn build(&self, path: &[Step], at: Span) -> Spanned {
        let Some(node) = self.nodes.get(path) else {
            return sym_at(at, WILDCARD);
        };
        if let Some(name) = &node.bind {
            return name.clone();
        }
        if let Some(v) = &node.lit {
            return v.clone();
        }
        let below = |step: Step| {
            let mut p = path.to_vec();
            p.push(step);
            self.build(&p, at)
        };
        if let Some(shape) = &node.record {
            let mut items = vec![sym_at(at, &shape.name)];
            items.extend(shape.fields.iter().map(|f| below(Step::Key(f.clone()))));
            return list_at(at, items);
        }
        if let Some((n, open)) = node.list {
            let mut items = vec![sym_at(at, "list")];
            items.extend((0..n).map(|i| below(Step::At(i64::try_from(i).unwrap_or(0)))));
            if open {
                let rest = node.rest.clone().unwrap_or_else(|| sym_at(at, WILDCARD));
                items.push(list_at(
                    rest.span,
                    vec![sym_at(rest.span, LOWERED_SPLICE), rest],
                ));
            }
            return list_at(at, items);
        }
        let mut items = vec![sym_at(at, LOWERED_MAP)];
        for k in &node.keys {
            items.push(keyword_at(at, k));
            items.push(below(Step::Key(k.clone())));
        }
        list_at(at, items)
    }
}

fn decompile(
    test: &Spanned,
    binds: &[(&Spanned, &Spanned)],
    root: &str,
    shapes: &Shapes,
    at: Span,
) -> Option<Spanned> {
    let tests: Vec<&Spanned> = match test.as_list() {
        Some([h, rest @ ..]) if h.as_symbol() == Some("and") => rest.iter().collect(),
        _ => vec![test],
    };
    let mut tree = Tree {
        nodes: BTreeMap::new(),
    };
    for t in tests {
        tree.test(t, root, shapes)?;
    }
    for (name, access) in binds {
        tree.bind(name, access, root)?;
    }
    tree.nodes.get(&Vec::new())?;
    Some(tree.build(&[], at))
}

fn let_parts(body: &Spanned) -> Option<(Vec<(&Spanned, &Spanned)>, &Spanned)> {
    let [l, pairs, inner] = body.as_list()? else {
        return None;
    };
    if l.as_symbol() != Some("let") {
        return None;
    }
    let binds = pairs
        .as_list()?
        .iter()
        .map(|p| match p.as_list()? {
            [n, a] if n.as_symbol().is_some_and(|s| s != CASE_SUBJECT) => Some((n, a)),
            _ => None,
        })
        .collect::<Option<Vec<_>>>()?;
    Some((binds, inner))
}

fn raise_clause(clause: Spanned, shapes: &Shapes) -> Spanned {
    let Some([test, body]) = clause.as_list() else {
        return clause;
    };
    let Some((binds, inner)) = let_parts(body) else {
        return clause;
    };
    let Some(pattern) = decompile(test, &binds, CASE_SUBJECT, shapes, test.span) else {
        return clause;
    };
    let eq = call(
        test.span,
        "equal?",
        vec![sym_at(test.span, CASE_SUBJECT), pattern],
    );
    list_at(clause.span, vec![eq, inner.clone()])
}

fn raise_case(form: Spanned, shapes: &Shapes) -> Spanned {
    if subject_of(&form, CASE_SUBJECT).is_none() {
        return form;
    }
    let span = form.span;
    let SpannedForm::List(mut items) = form.form else {
        return form;
    };
    let cond = items.pop().expect("a case is (let bind cond)");
    let cond_at = cond.span;
    let SpannedForm::List(clauses) = cond.form else {
        items.push(cond);
        return list_at(span, items);
    };
    let out = clauses
        .into_iter()
        .enumerate()
        .map(|(k, c)| if k == 0 { c } else { raise_clause(c, shapes) })
        .collect();
    items.push(list_at(cond_at, out));
    list_at(span, items)
}

fn defines(form: &Spanned) -> Option<(&Spanned, &Spanned)> {
    match form.as_list()? {
        [d, n, v] if d.as_symbol() == Some("define") && n.as_symbol().is_some() => Some((n, v)),
        _ => None,
    }
}

fn refusal_test(form: &Spanned) -> Option<&Spanned> {
    let [i, not, refuse] = form.as_list()? else {
        return None;
    };
    if i.as_symbol() != Some("if") || head_of(refuse) != Some(SHAPE_REFUSE) {
        return None;
    }
    match not.as_list()? {
        [n, t] if n.as_symbol() == Some("not") => Some(t),
        _ => None,
    }
}

fn raise_binds(items: Vec<Spanned>, shapes: &Shapes) -> Vec<Spanned> {
    let mut out = Vec::with_capacity(items.len());
    let mut i = 0;
    while i < items.len() {
        let start = defines(&items[i]).filter(|(n, _)| n.as_symbol() == Some(BIND_SUBJECT));
        let test = items.get(i + 1).and_then(refusal_test);
        if let (Some((_, value)), Some(test)) = (start, test) {
            let mut j = i + 2;
            let mut binds = Vec::new();
            while let Some((n, a)) = items.get(j).and_then(defines) {
                if n.as_symbol() == Some(BIND_SUBJECT) || path_of(a, BIND_SUBJECT).is_none() {
                    break;
                }
                binds.push((n, a));
                j += 1;
            }
            let at = items[i].span.merge(items[j - 1].span);
            if let Some(pattern) = decompile(test, &binds, BIND_SUBJECT, shapes, test.span) {
                out.push(call(at, LOWERED_BIND, vec![pattern, value.clone()]));
                i = j;
                continue;
            }
        }
        out.push(items[i].clone());
        i += 1;
    }
    out
}

fn raise_walk(form: Spanned, shapes: &Shapes) -> Spanned {
    let span = form.span;
    let SpannedForm::List(items) = form.form else {
        return form;
    };
    let items: Vec<Spanned> = items.into_iter().map(|i| raise_walk(i, shapes)).collect();
    let form = raise_case(list_at(span, items), shapes);
    let SpannedForm::List(items) = form.form else {
        return form;
    };
    if items.first().and_then(Spanned::as_symbol) != Some("begin") {
        return list_at(span, items);
    }
    let mut raised = raise_binds(items, shapes);
    if raised.len() == 2 && head_of(&raised[1]) == Some(LOWERED_BIND) {
        return raised.pop().expect("checked len");
    }
    list_at(span, raised)
}

#[must_use]
pub fn raise(forms: Vec<Spanned>) -> Vec<Spanned> {
    let shapes = Shapes::of(&forms);
    if !forms.iter().any(mentions_shape) {
        return forms;
    }
    raise_binds(forms, &shapes)
        .into_iter()
        .map(|f| raise_walk(f, &shapes))
        .collect()
}

fn mentions_shape(form: &Spanned) -> bool {
    match &form.form {
        SpannedForm::Atom(Atom::Symbol(s)) => {
            SHAPE_WORDS.contains(&s.as_str()) || s == BIND_SUBJECT || s == "let"
        }
        SpannedForm::List(items) => items.iter().any(mentions_shape),
        _ => false,
    }
}
