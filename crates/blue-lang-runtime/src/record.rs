use std::collections::BTreeMap;
use std::sync::Arc;

use blue_lang_syntax::record::{record_parts, LIST_TYPE, LOWERED_RECORD, RECORD_TAG};
use blue_lang_syntax::{LOWERED_KWARGS, LOWERED_MAP, LOWERED_MERGE};
use tatara_lisp::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::errors::raise_kind_with;

const NEW: &str = "blue-record-new";
const NAMED: &str = "blue-record-named";
const IS: &str = "blue-record?";
const REST: &str = "%fields";
const SUBJECT: &str = "%value";
const ROOT_PREFIX: &str = "%root/";
const CASE_SUBJECT: &str = "case-subject";

#[must_use]
pub fn split_tag(tag: &str) -> Option<(&str, Vec<&str>)> {
    let (name, rest) = tag.split_once('(')?;
    let fields = rest.strip_suffix(')')?;
    (!name.is_empty() && !fields.is_empty()).then(|| (name, fields.split(',').collect()))
}

#[must_use]
pub fn name_of(v: &Value) -> Option<&str> {
    let Value::Map(m) = v else { return None };
    let Some(Value::Str(tag)) = m.get(&MapKey::Keyword(Arc::from(RECORD_TAG))) else {
        return None;
    };
    let (name, fields) = split_tag(tag)?;
    let exact = m.iter().count() == fields.len() + 1
        && fields
            .iter()
            .all(|f| m.get(&MapKey::Keyword(Arc::from(*f))).is_some());
    exact.then_some(name)
}

fn name_part(tag: &str) -> &str {
    tag.split_once('(').map_or(tag, |(name, _)| name)
}

#[must_use]
pub fn is_tag_key(k: &MapKey) -> bool {
    matches!(k, MapKey::Keyword(s) if &**s == RECORD_TAG)
}

#[must_use]
pub fn name_of_key(key: &str) -> String {
    key.strip_prefix(ROOT_PREFIX)
        .unwrap_or(key)
        .replace(blue_lang_syntax::QUALIFIER, "::")
}

struct Slot {
    name: Arc<str>,
    ty: Option<Value>,
}

fn slots(desc: &Value) -> Vec<Slot> {
    let Value::List(xs) = desc else {
        return Vec::new();
    };
    xs.iter()
        .filter_map(|entry| match entry {
            Value::Keyword(k) => Some(Slot {
                name: k.clone(),
                ty: None,
            }),
            Value::List(pair) => match (pair.get(0), pair.get(1)) {
                (Some(Value::Keyword(k)), ty) => Some(Slot {
                    name: k.clone(),
                    ty: ty.cloned(),
                }),
                _ => None,
            },
            _ => None,
        })
        .collect()
}

fn names(fields: &[Slot]) -> Vec<&str> {
    fields.iter().map(|f| &*f.name).collect()
}

fn type_text(ty: &Value) -> String {
    match ty {
        Value::Symbol(s) | Value::Str(s) => s.to_string(),
        Value::List(xs) => match xs.get(1) {
            Some(inner) => format!("{LIST_TYPE}({})", type_text(inner)),
            None => LIST_TYPE.to_string(),
        },
        other => other.type_name().to_string(),
    }
}

fn conforms(ty: &Value, v: &Value) -> bool {
    match ty {
        Value::Symbol(s) => match &**s {
            "Int" => matches!(v, Value::Int(_)),
            "Float" => matches!(v, Value::Float(_)),
            "Str" => matches!(v, Value::Str(_)),
            "Bool" => matches!(v, Value::Bool(_)),
            "Sym" => matches!(v, Value::Keyword(_) | Value::Symbol(_)),
            "Nil" => matches!(v, Value::Nil),
            "Map" => matches!(v, Value::Map(_)),
            _ => false,
        },
        Value::Str(tag) => name_of(v) == Some(&**tag),
        Value::List(xs) => match (xs.get(1), v) {
            (Some(inner), Value::List(items)) => items.iter().all(|i| conforms(inner, i)),
            _ => false,
        },
        _ => false,
    }
}

fn text_list<'a>(xs: impl IntoIterator<Item = &'a str>) -> Value {
    Value::list(xs.into_iter().map(|s| Value::Keyword(Arc::from(s))))
}

fn refused(tag: &str, message: String, missing: &[&str], unknown: &[&str], sp: Span) -> EvalError {
    let data = Value::map([
        (
            MapKey::Keyword(Arc::from("record")),
            Value::Str(Arc::from(tag)),
        ),
        (
            MapKey::Keyword(Arc::from("missing")),
            text_list(missing.iter().copied()),
        ),
        (
            MapKey::Keyword(Arc::from("unknown")),
            text_list(unknown.iter().copied()),
        ),
    ]);
    raise_kind_with("record", message, data, sp)
}

fn build(
    tag: &str,
    slots: &[Slot],
    values: &[(&str, Value)],
    sp: Span,
) -> Result<Value, EvalError> {
    let name_shown = name_part(tag);
    for slot in slots {
        let name = &*slot.name;
        let Some(ty) = &slot.ty else {
            continue;
        };
        let given = values.iter().find(|(n, _)| *n == name).map(|(_, v)| v);
        if let Some(v) = given.filter(|v| !conforms(ty, v)) {
            let got = name_of(v).unwrap_or(v.type_name()).to_string();
            return Err(raise_kind_with(
                "record",
                format!(
                    "`{name_shown}`'s field `{name}` is {}, and it was given {got}",
                    type_text(ty)
                ),
                Value::Nil,
                sp,
            ));
        }
    }
    let mut out = vec![(
        MapKey::Keyword(Arc::from(RECORD_TAG)),
        Value::Str(Arc::from(tag)),
    )];
    out.extend(
        values
            .iter()
            .map(|(n, v)| (MapKey::Keyword(Arc::from(*n)), v.clone())),
    );
    Ok(Value::map(out))
}

fn key_text(k: &MapKey) -> Option<&str> {
    match k {
        MapKey::Keyword(s) | MapKey::Str(s) | MapKey::Symbol(s) => Some(s),
        _ => None,
    }
}

fn by_name(whole: &str, desc: &Value, given: &Value, sp: Span) -> Result<Value, EvalError> {
    let tag = name_part(whole);
    let Value::Map(m) = given else {
        return Err(refused(
            tag,
            format!(
                "`{tag}` by name takes a map, and was given {}",
                given.type_name()
            ),
            &[],
            &[],
            sp,
        ));
    };
    let slots = slots(desc);
    let fields = names(&slots);
    let mut named: BTreeMap<&str, &Value> = BTreeMap::new();
    let mut unknown: Vec<String> = Vec::new();
    for (k, v) in m.iter() {
        if is_tag_key(k) || matches!(k, MapKey::Str(s) if &**s == RECORD_TAG) {
            if !matches!(v, Value::Str(s) if &**s == whole) {
                let other = match v {
                    Value::Str(s) if name_part(s) == tag => s.to_string(),
                    Value::Str(s) => name_part(s).to_string(),
                    other => other.type_name().to_string(),
                };
                return Err(refused(
                    tag,
                    format!("`{tag}` cannot take the fields of a `{other}`"),
                    &[],
                    &[],
                    sp,
                ));
            }
            continue;
        }
        match key_text(k).filter(|n| fields.contains(n)) {
            Some(n) => {
                named.insert(n, v);
            }
            None => unknown.push(key_text(k).map_or_else(|| format!("{k:?}"), str::to_string)),
        }
    }
    unknown.sort();
    let missing: Vec<&str> = fields
        .iter()
        .copied()
        .filter(|f| !named.contains_key(f))
        .collect();
    if !unknown.is_empty() || !missing.is_empty() {
        let mut parts = Vec::new();
        if !unknown.is_empty() {
            parts.push(format!(
                "has no field {} (its fields: {})",
                quoted(unknown.iter().map(String::as_str)),
                fields.join(", ")
            ));
        }
        if !missing.is_empty() {
            parts.push(format!("is missing {}", quoted(missing.iter().copied())));
        }
        let unknown: Vec<&str> = unknown.iter().map(String::as_str).collect();
        return Err(refused(
            tag,
            format!("`{tag}` {}", parts.join(" and ")),
            &missing,
            &unknown,
            sp,
        ));
    }
    let values: Vec<(&str, Value)> = fields.iter().map(|f| (*f, named[f].clone())).collect();
    build(whole, &slots, &values, sp)
}

fn quoted<'a>(names: impl Iterator<Item = &'a str>) -> String {
    names
        .map(|n| format!("`{n}`"))
        .collect::<Vec<_>>()
        .join(", ")
}

fn positional(whole: &str, desc: &Value, args: &Value, sp: Span) -> Result<Value, EvalError> {
    let tag = name_part(whole);
    let slots = slots(desc);
    let fields = names(&slots);
    let args = match args {
        Value::List(xs) => xs.to_vec(),
        _ => Vec::new(),
    };
    if args.len() == 1 && fields.len() > 1 && matches!(args[0], Value::Map(_)) {
        return by_name(whole, desc, &args[0], sp);
    }
    if args.len() != fields.len() {
        let missing: Vec<&str> = fields.iter().skip(args.len()).copied().collect();
        return Err(refused(
            tag,
            format!(
                "`{tag}` takes {} fields ({}) and was given {}",
                fields.len(),
                fields.join(", "),
                args.len()
            ),
            &missing,
            &[],
            sp,
        ));
    }
    let values: Vec<(&str, Value)> = fields.iter().copied().zip(args.iter().cloned()).collect();
    build(whole, &slots, &values, sp)
}

fn holds(tag: &str, desc: &Value, v: &Value) -> bool {
    let Value::Map(m) = v else { return false };
    let slots = slots(desc);
    let carried = m.get(&MapKey::Keyword(Arc::from(RECORD_TAG)));
    if !matches!(carried, Some(Value::Str(s)) if &**s == tag) || m.iter().count() != slots.len() + 1
    {
        return false;
    }
    slots.iter().all(|slot| {
        m.get(&MapKey::Keyword(slot.name.clone()))
            .is_some_and(|x| slot.ty.as_ref().is_none_or(|ty| conforms(ty, x)))
    })
}

fn text_arg(v: &Value) -> &str {
    match v {
        Value::Str(s) => s,
        _ => "",
    }
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(NEW, Arity::Exact(3), |a: &[Value], _: &mut H, sp| {
        positional(text_arg(&a[0]), &a[1], &a[2], sp)
    });
    interp.register_fn(NAMED, Arity::Exact(3), |a: &[Value], _: &mut H, sp| {
        by_name(text_arg(&a[0]), &a[1], &a[2], sp)
    });
    interp.register_fn(IS, Arity::Exact(3), |a: &[Value], _: &mut H, _| {
        Ok(Value::Bool(holds(text_arg(&a[0]), &a[1], &a[2])))
    });
    interp.register_fn(
        "record_name",
        Arity::Exact(1),
        |a: &[Value], _: &mut H, _| {
            Ok(name_of(&a[0]).map_or(Value::Nil, |n| Value::Str(Arc::from(n))))
        },
    );
    interp.register_fn(
        "record_fields",
        Arity::Exact(1),
        |a: &[Value], _: &mut H, sp| match &a[0] {
            Value::Map(m) if name_of(&a[0]).is_some() => Ok(Value::map(
                m.iter()
                    .filter(|(k, _)| !is_tag_key(k))
                    .map(|(k, v)| (k.clone(), v.clone())),
            )),
            other => Err(EvalError::type_mismatch("a record", other.type_name(), sp)),
        },
    );
}

fn node(at: Span, form: SpannedForm) -> Spanned {
    Spanned::new(at, form)
}

fn sym(at: Span, name: &str) -> Spanned {
    node(at, SpannedForm::Atom(Atom::Symbol(name.into())))
}

fn string(at: Span, text: &str) -> Spanned {
    node(at, SpannedForm::Atom(Atom::Str(text.into())))
}

fn list(at: Span, items: Vec<Spanned>) -> Spanned {
    node(at, SpannedForm::List(items))
}

fn lowered_type(ty: &Spanned) -> Spanned {
    if let Some(name) = ty.as_symbol() {
        if blue_lang_syntax::record::VALUE_TYPES.contains(&name) {
            return ty.clone();
        }
        return string(ty.span, &name_of_key(name));
    }
    match ty.as_list() {
        Some([head, rest @ ..]) => {
            let mut items = vec![head.clone()];
            items.extend(rest.iter().map(lowered_type));
            list(ty.span, items)
        }
        _ => ty.clone(),
    }
}

fn whole_tag(key: &str, r: &blue_lang_syntax::record::Record<'_>) -> String {
    let mut fields = r.field_names();
    fields.sort_unstable();
    format!("{}({})", name_of_key(key), fields.join(","))
}

struct Lowered {
    tag: String,
    desc: Spanned,
}

fn descriptor(r: &blue_lang_syntax::record::Record<'_>, at: Span) -> Spanned {
    let fields = r
        .fields
        .iter()
        .map(|f| match f.ty {
            Some(ty) => list(
                f.node.span,
                vec![
                    node(
                        f.node.span,
                        SpannedForm::Atom(Atom::Keyword(f.name.to_string())),
                    ),
                    lowered_type(ty),
                ],
            ),
            None => f.node.clone(),
        })
        .collect();
    node(at, SpannedForm::Quote(Box::new(list(at, fields))))
}

fn define(at: Span, sig: Vec<Spanned>, body: Spanned) -> Spanned {
    list(at, vec![sym(at, "define"), list(at, sig), body])
}

fn declaration(form: &Spanned, known: &BTreeMap<String, Lowered>) -> Option<Spanned> {
    let r = record_parts(form)?;
    let key = r.name.as_symbol()?;
    let predicate = r.predicate.as_symbol()?;
    let l = known.get(key)?;
    let at = form.span;
    let call = |word: &str, arg: &str| {
        list(
            at,
            vec![
                sym(at, word),
                string(at, &l.tag),
                l.desc.clone(),
                sym(at, arg),
            ],
        )
    };
    Some(list(
        at,
        vec![
            sym(at, "begin"),
            define(
                at,
                vec![sym(r.name.span, key), sym(at, "&rest"), sym(at, REST)],
                call(NEW, REST),
            ),
            define(
                at,
                vec![sym(r.predicate.span, predicate), sym(at, SUBJECT)],
                call(IS, SUBJECT),
            ),
        ],
    ))
}

fn is_call_of(form: &Spanned, head: &str) -> bool {
    form.as_list()
        .and_then(|i| i.first())
        .and_then(Spanned::as_symbol)
        == Some(head)
}

fn rewrite_calls(
    form: &Spanned,
    known: &BTreeMap<String, Lowered>,
    predicates: &BTreeMap<String, String>,
) -> Spanned {
    let SpannedForm::List(items) = &form.form else {
        return form.clone();
    };
    if let [head, arg] = items.as_slice() {
        if let Some(l) = head.as_symbol().and_then(|h| known.get(h)) {
            if [LOWERED_KWARGS, LOWERED_MERGE, LOWERED_MAP]
                .iter()
                .any(|h| is_call_of(arg, h))
            {
                return list(
                    form.span,
                    vec![
                        sym(head.span, NAMED),
                        string(head.span, &l.tag),
                        l.desc.clone(),
                        rewrite_calls(arg, known, predicates),
                    ],
                );
            }
        }
    }
    if let [head, subject, pattern] = items.as_slice() {
        let matched = head.as_symbol() == Some("equal?")
            && subject.as_symbol() == Some(CASE_SUBJECT)
            && pattern
                .as_symbol()
                .is_some_and(|p| predicates.contains_key(p));
        if matched {
            return list(form.span, vec![pattern.clone(), subject.clone()]);
        }
    }
    list(
        form.span,
        items
            .iter()
            .map(|i| rewrite_calls(i, known, predicates))
            .collect(),
    )
}

#[must_use]
pub fn lower_records(forms: Vec<Spanned>) -> Vec<Spanned> {
    let mut known = BTreeMap::new();
    let mut predicates = BTreeMap::new();
    for form in &forms {
        if let Some(r) = record_parts(form) {
            let (Some(key), Some(pred)) = (r.name.as_symbol(), r.predicate.as_symbol()) else {
                continue;
            };
            known.insert(
                key.to_string(),
                Lowered {
                    tag: whole_tag(key, &r),
                    desc: descriptor(&r, form.span),
                },
            );
            predicates.insert(pred.to_string(), key.to_string());
        }
    }
    if known.is_empty() {
        return forms;
    }
    forms
        .iter()
        .map(|form| {
            if is_call_of(form, LOWERED_RECORD) {
                declaration(form, &known).unwrap_or_else(|| form.clone())
            } else {
                rewrite_calls(form, &known, &predicates)
            }
        })
        .collect()
}
