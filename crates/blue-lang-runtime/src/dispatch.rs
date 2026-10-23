use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use tatara_lisp_eval::ffi::{Arity, Caller};
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::vm::run::CompiledClosure;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::errors::raise_kind;

pub use blue_lang_syntax::MASTER_VERBS;

pub const KINDS: &[&str] = &[
    "map", "list", "string", "int", "float", "bool", "keyword", "function",
];

const SPACE_KEY: &str = "space";
const OF_KEY: &str = "of";
const USAGE: &str = "usage";
const STATE: &str = "blue-dispatch-state";

#[derive(Default, Clone)]
struct Registry {
    handlers: BTreeMap<(String, String), Value>,
    kinds: BTreeMap<String, String>,
}

type Shared = Arc<Mutex<Registry>>;

fn key(name: &str) -> MapKey {
    MapKey::Keyword(Arc::from(name))
}

#[must_use]
pub fn kind_of(v: &Value) -> Option<&'static str> {
    match v {
        Value::Map(_) => Some("map"),
        Value::List(_) => Some("list"),
        Value::Str(_) => Some("string"),
        Value::Int(_) => Some("int"),
        Value::Float(_) => Some("float"),
        Value::Bool(_) => Some("bool"),
        Value::Keyword(_) => Some("keyword"),
        other if procedure(other) => Some("function"),
        _ => None,
    }
}

fn tagged(v: &Value) -> Option<(&str, &Value)> {
    let Value::Map(m) = v else { return None };
    if m.len() != 2 {
        return None;
    }
    match (m.get(&key(SPACE_KEY)), m.get(&key(OF_KEY))) {
        (Some(Value::Str(space)), Some(of)) => Some((space, of)),
        _ => None,
    }
}

#[must_use]
pub fn tag(space: &str, value: Value) -> Value {
    Value::map([
        (key(SPACE_KEY), Value::Str(Arc::from(space))),
        (key(OF_KEY), value),
    ])
}

fn usage(message: String, sp: tatara_lisp::Span) -> EvalError {
    raise_kind(USAGE, message, sp)
}

fn text<'a>(
    who: &str,
    what: &str,
    v: &'a Value,
    sp: tatara_lisp::Span,
) -> Result<&'a str, EvalError> {
    match v {
        Value::Str(s) if !s.is_empty() => Ok(s),
        other => Err(usage(
            format!(
                "{who}: {what} is a non-empty string, got {}",
                other.type_name()
            ),
            sp,
        )),
    }
}

fn space_of(reg: &Registry, subject: &Value) -> Option<String> {
    if let Some((space, _)) = tagged(subject) {
        return Some(space.to_string());
    }
    kind_of(subject).and_then(|k| reg.kinds.get(k).cloned())
}

fn dispatch<H: 'static>(
    reg: &Shared,
    verb: &str,
    args: &[Value],
    host: &mut H,
    caller: &Caller<H>,
    sp: tatara_lisp::Span,
) -> Result<Value, EvalError> {
    let subject = &args[0];
    let handler = {
        let guard = reg.lock().unwrap_or_else(|p| p.into_inner());
        let Some(space) = space_of(&guard, subject) else {
            return Err(usage(
                format!(
                    "{verb}: no space owns a {} subject; name one with in_space(\"<space>\", subject)",
                    kind_of(subject).unwrap_or_else(|| subject.type_name())
                ),
                sp,
            ));
        };
        let Some(handler) = guard
            .handlers
            .get(&(verb.to_string(), space.clone()))
            .cloned()
        else {
            let owners: Vec<&str> = guard
                .handlers
                .keys()
                .filter(|(v, _)| v == verb)
                .map(|(_, s)| s.as_str())
                .collect();
            let have = if owners.is_empty() {
                "no space has loaded one".to_string()
            } else {
                format!("loaded: {}", owners.join(", "))
            };
            return Err(usage(
                format!(
                    "{verb}: space {space} has no handler ({have}); load it with use(\"{space}\")"
                ),
                sp,
            ));
        };
        handler
    };
    let mut call = Vec::with_capacity(args.len());
    call.push(tagged(subject).map_or_else(|| subject.clone(), |(_, of)| of.clone()));
    call.extend(args[1..].iter().cloned());
    caller.apply_value(&handler, call, host, sp)
}

fn required(verb: &str) -> usize {
    match verb {
        "put" | "update" | "create" => 3,
        "need" | "has?" | "delete" | "diff" => 2,
        _ => 1,
    }
}

fn procedure(v: &Value) -> bool {
    match v {
        Value::Closure(_) | Value::NativeFn(_) => true,
        Value::Foreign(any) => any.is::<CompiledClosure>(),
        _ => false,
    }
}

pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    let inherited = match interp.lookup_global(STATE) {
        Some(Value::Foreign(f)) => f
            .downcast::<Mutex<Registry>>()
            .ok()
            .map(|r| r.lock().unwrap_or_else(|p| p.into_inner()).clone()),
        _ => None,
    };
    let reg: Shared = Arc::new(Mutex::new(inherited.unwrap_or_default()));
    interp.define_global(STATE, Value::Foreign(reg.clone()));

    let r = reg.clone();
    interp.register_fn(
        "verb_for",
        Arity::Exact(3),
        move |a: &[Value], _h: &mut H, sp| {
            let space = text("verb_for", "the space", &a[0], sp)?;
            let verb = text("verb_for", "the verb", &a[1], sp)?;
            if !MASTER_VERBS.contains(&verb) {
                return Err(usage(
                    format!(
                        "verb_for: {verb} is not a dispatched master verb; they are {}",
                        MASTER_VERBS.join(", ")
                    ),
                    sp,
                ));
            }
            if !procedure(&a[2]) {
                return Err(usage(
                    format!(
                        "verb_for: the handler is a function, got {}",
                        a[2].type_name()
                    ),
                    sp,
                ));
            }
            r.lock()
                .unwrap_or_else(|p| p.into_inner())
                .handlers
                .insert((verb.to_string(), space.to_string()), a[2].clone());
            Ok(Value::Nil)
        },
    );

    let r = reg.clone();
    interp.register_fn(
        "space_for",
        Arity::Exact(2),
        move |a: &[Value], _h: &mut H, sp| {
            let kind = match &a[0] {
                Value::Keyword(k) if KINDS.contains(&&**k) => k.to_string(),
                other => {
                    return Err(usage(
                        format!(
                            "space_for: the kind is one of {}, got {}",
                            KINDS.join(", "),
                            crate::literal::render_value(other)
                        ),
                        sp,
                    ))
                }
            };
            let space = text("space_for", "the space", &a[1], sp)?.to_string();
            let mut guard = r.lock().unwrap_or_else(|p| p.into_inner());
            match guard.kinds.get(&kind) {
                Some(owner) if *owner != space => Err(usage(
                    format!("space_for: kind {kind} already belongs to space {owner}"),
                    sp,
                )),
                _ => {
                    guard.kinds.insert(kind, space);
                    Ok(Value::Nil)
                }
            }
        },
    );

    interp.register_fn(
        "in_space",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, sp| {
            let space = text("in_space", "the space", &a[0], sp)?;
            match tagged(&a[1]) {
                Some((owner, _)) if owner == space => Ok(a[1].clone()),
                Some((owner, _)) => Err(usage(
                    format!("in_space: the subject is already in space {owner}, not {space}"),
                    sp,
                )),
                None => Ok(tag(space, a[1].clone())),
            }
        },
    );

    let r = reg.clone();
    interp.register_fn(
        "space_of",
        Arity::Exact(1),
        move |a: &[Value], _h: &mut H, _sp| {
            let guard = r.lock().unwrap_or_else(|p| p.into_inner());
            Ok(space_of(&guard, &a[0]).map_or(Value::Nil, |s| Value::Str(Arc::from(s))))
        },
    );

    for verb in MASTER_VERBS {
        let r = reg.clone();
        let name: &'static str = verb;
        interp.register_higher_order_fn(
            name,
            Arity::AtLeast(required(name)),
            move |a: &[Value], host: &mut H, caller: &Caller<H>, sp| {
                dispatch(&r, name, a, host, caller, sp)
            },
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tag_is_read_back_as_its_space_and_subject() {
        let v = tag("gitto", Value::Str(Arc::from(".")));
        let (space, of) = tagged(&v).expect("tagged");
        assert_eq!(space, "gitto");
        assert!(matches!(of, Value::Str(s) if &**s == "."));
    }

    #[test]
    fn a_map_with_other_keys_is_not_a_tag() {
        let three = Value::map([
            (key(SPACE_KEY), Value::Str(Arc::from("x"))),
            (key(OF_KEY), Value::Nil),
            (key("extra"), Value::Nil),
        ]);
        assert!(tagged(&three).is_none());
        let wrong_type = Value::map([(key(SPACE_KEY), Value::Int(1)), (key(OF_KEY), Value::Nil)]);
        assert!(tagged(&wrong_type).is_none());
        assert!(tagged(&Value::map([])).is_none());
        assert!(tagged(&Value::Nil).is_none());
    }

    #[test]
    fn kinds_name_every_dispatchable_value() {
        assert_eq!(kind_of(&Value::map([])), Some("map"));
        assert_eq!(kind_of(&Value::Str(Arc::from("p"))), Some("string"));
        assert_eq!(kind_of(&Value::Int(1)), Some("int"));
        assert_eq!(kind_of(&Value::Nil), None);
    }

    #[test]
    fn a_kind_resolves_only_when_registered_and_a_tag_always_wins() {
        let mut reg = Registry::default();
        let plain = Value::map([(key("a"), Value::Int(1))]);
        assert_eq!(space_of(&reg, &plain), None);
        reg.kinds.insert("map".into(), "jisho".into());
        assert_eq!(space_of(&reg, &plain).as_deref(), Some("jisho"));
        assert_eq!(
            space_of(&reg, &tag("gitto", Value::Nil)).as_deref(),
            Some("gitto")
        );
        assert_eq!(space_of(&reg, &Value::Nil), None);
    }

    #[test]
    fn a_verb_requires_the_positionals_its_contract_names() {
        let wants: Vec<(&str, usize)> = MASTER_VERBS.iter().map(|v| (*v, required(v))).collect();
        assert_eq!(
            wants,
            vec![
                ("read", 1),
                ("need", 2),
                ("has?", 2),
                ("put", 3),
                ("update", 3),
                ("delete", 2),
                ("create", 3),
                ("diff", 2),
                ("info", 1),
                ("exists?", 1),
            ]
        );
    }

    #[test]
    fn every_master_verb_is_unique() {
        let mut seen = std::collections::BTreeSet::new();
        for v in MASTER_VERBS {
            assert!(seen.insert(*v), "{v} listed twice");
        }
    }
}
