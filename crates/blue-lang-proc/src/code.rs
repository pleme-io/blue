//! What a new process runs: a function value turned back into code.
//!
//! `spawn(f, args)` hands the new process **the code of `f` and copies of the
//! values it reaches**, never a reference into the spawner's environment. That
//! is Erlang's rule for a fun sent to `spawn`, and it is the only reading of
//! "processes share nothing" that survives a function value: a closure carries
//! its defining environment, and sharing that environment is the coupling
//! process isolation exists to remove (`mailbox::deep_copy` refuses closures
//! for the same reason).
//!
//! So the spawner's function is walked, not shared:
//!
//! - every free name it reaches that is bound to **a function** becomes a
//!   definition in the child, recursively, so helpers come along;
//! - every free name bound to **data** becomes a binding in the child, a deep
//!   copy taken now (a local the closure captured, a top-level constant);
//! - a name bound to a builtin is left alone: the child has its own runtime;
//! - a name bound to anything else (a host handle, a promise) is refused by
//!   name, because a process must open its own resources.
//!
//! The result is compiled for the bytecode VM, because the VM is the executor
//! that can preempt and park; a function the tree-walker defined is
//! recompiled, not called across.

use std::collections::BTreeMap;
use std::sync::Arc;

use tatara_lisp::{Atom, Span, Spanned, SpannedForm};
use tatara_lisp_eval::value::Closure;
use tatara_lisp_eval::vm::run::CompiledClosure;
use tatara_lisp_eval::Value;

use crate::mailbox::copy_data;

/// A process's program: definitions, data bindings, and the form it starts at.
///
/// Kept as trees, not as a compiled chunk, because a restart, a migration and
/// a crash trace all need the program again: the restart recompiles it, the
/// migration extends it, and the trace writes it down so `blue replay` needs
/// nothing but the trace.
#[derive(Clone, Debug, Default)]
pub struct Code {
    /// `(define (name params…) body…)` forms, one per function reached.
    pub defs: Vec<Spanned>,
    /// Globals the child starts with: copied arguments and captured data.
    pub bindings: Vec<(Arc<str>, Value)>,
    /// The form the process evaluates; its value is the process's result.
    pub start: Option<Spanned>,
}

impl Code {
    /// Every form the VM compiles, in order.
    #[must_use]
    pub fn program(&self) -> Vec<Spanned> {
        let mut forms = self.defs.clone();
        forms.extend(self.start.clone());
        forms
    }

    /// Set a binding, replacing an earlier one of the same name.
    pub fn bind(&mut self, name: &str, value: Value) {
        match self.bindings.iter_mut().find(|(n, _)| &**n == name) {
            Some(slot) => slot.1 = value,
            None => self.bindings.push((Arc::from(name), value)),
        }
    }
}

/// How the code reached its entry function.
#[derive(Clone, Debug)]
pub enum Entry {
    /// A named function; the code defines it under this name.
    Named(String),
    /// An anonymous function, as a `(lambda …)` form.
    Lambda(Spanned),
    /// A builtin, called by name.
    Builtin(String),
}

/// A function value normalised to its source shape.
#[derive(Clone)]
enum Function {
    Source(Arc<Closure>),
    Builtin(Arc<str>),
}

fn function_of(v: &Value) -> Option<Function> {
    match v {
        Value::Closure(c) => Some(Function::Source(c.clone())),
        Value::NativeFn(n) => Some(Function::Builtin(n.name.clone())),
        Value::Foreign(any) => any.clone().downcast::<CompiledClosure>().ok().map(|cc| {
            // A VM closure keeps its source body; lifting gives it the same
            // shape a tree-walker closure has, captures included.
            let lifted = cc.lift_to_closure();
            Function::Source(Arc::new(Closure {
                params: lifted.params.clone(),
                rest: lifted.rest.clone(),
                body: lifted.body.clone(),
                captured_env: lifted.captured_env.clone(),
                source: lifted.source,
                name: cc.body.name.clone(),
            }))
        }),
        _ => None,
    }
}

/// The name a function value was defined under, if it has one. What
/// `defmigrate` matches running processes by.
#[must_use]
pub fn name_of(v: &Value) -> Option<String> {
    match function_of(v)? {
        Function::Source(c) => c.name.as_deref().map(str::to_string),
        Function::Builtin(n) => Some(n.to_string()),
    }
}

/// Is this value something `spawn` can run?
#[must_use]
pub fn is_function(v: &Value) -> bool {
    function_of(v).is_some()
}

fn sym(name: &str) -> Spanned {
    Spanned::new(
        Span::synthetic(),
        SpannedForm::Atom(Atom::Symbol(name.to_string())),
    )
}

fn list(items: Vec<Spanned>) -> Spanned {
    Spanned::new(Span::synthetic(), SpannedForm::List(items))
}

/// `(p1 p2 &rest r)`.
fn params_of(c: &Closure) -> Spanned {
    let mut ps: Vec<Spanned> = c.params.iter().map(|p| sym(p)).collect();
    if let Some(r) = &c.rest {
        ps.push(sym("&rest"));
        ps.push(sym(r));
    }
    list(ps)
}

/// `(lambda (params…) body…)`, keeping the body's own spans.
fn lambda_of(c: &Closure) -> Spanned {
    let mut items = vec![sym("lambda"), params_of(c)];
    items.extend(c.body.iter().cloned());
    Spanned::new(c.source, SpannedForm::List(items))
}

/// `(define (name params…) body…)`.
fn define_of(name: &str, c: &Closure) -> Spanned {
    let mut head = vec![sym(name)];
    if let SpannedForm::List(ps) = params_of(c).form {
        head.extend(ps);
    }
    let mut items = vec![sym("define"), list(head)];
    items.extend(c.body.iter().cloned());
    Spanned::new(c.source, SpannedForm::List(items))
}

/// `(define name value-form)`.
#[must_use]
pub fn define_value(name: &str, value: Spanned) -> Spanned {
    list(vec![sym("define"), sym(name), value])
}

/// `(f a1 a2 …)` where each argument is a global holding a copied value.
#[must_use]
pub fn call(head: Spanned, args: &[&str]) -> Spanned {
    let mut items = vec![head];
    items.extend(args.iter().map(|a| sym(a)));
    list(items)
}

/// A symbol form.
#[must_use]
pub fn symbol(name: &str) -> Spanned {
    sym(name)
}

/// Two `Value`s are the same binding when they are the same allocation.
fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Closure(x), Value::Closure(y)) => Arc::ptr_eq(x, y),
        (Value::Foreign(x), Value::Foreign(y)) => Arc::ptr_eq(x, y),
        (Value::List(x), Value::List(y)) => Arc::ptr_eq(x, y),
        (Value::Map(x), Value::Map(y)) => Arc::ptr_eq(x, y),
        (Value::NativeFn(x), Value::NativeFn(y)) => x.name == y.name,
        _ => crate::pattern::data_eq(a, b),
    }
}

/// Collects the definitions and bindings one entry function reaches.
struct Walk {
    defs: Vec<Spanned>,
    /// name → the value bound under it, so two different values reached
    /// under one name are refused instead of one silently winning.
    seen: BTreeMap<String, Value>,
    bindings: Vec<(Arc<str>, Value)>,
}

impl Walk {
    fn new() -> Self {
        Self {
            defs: Vec::new(),
            seen: BTreeMap::new(),
            bindings: Vec::new(),
        }
    }

    /// Bring along everything `c`'s body names.
    fn reach(&mut self, c: &Closure) -> Result<(), String> {
        let free = blue_lang_waku::free_names(&[lambda_of(c)], &|_| false);
        for name in free {
            let Some(v) = c.captured_env.lookup(&name) else {
                // A special form, a macro, or a global not defined yet: the
                // child's runtime answers it or the call fails there.
                continue;
            };
            self.bring(&name, &v)?;
        }
        Ok(())
    }

    fn bring(&mut self, name: &str, v: &Value) -> Result<(), String> {
        if let Some(prev) = self.seen.get(name) {
            if same(prev, v) {
                return Ok(());
            }
            return Err(format!(
                "spawn reaches two different values named `{name}`; rename one"
            ));
        }
        self.seen.insert(name.to_string(), v.clone());
        match function_of(v) {
            // The child's own runtime binds every builtin, including its own
            // process words, which must not be the spawner's.
            Some(Function::Builtin(_)) => Ok(()),
            Some(Function::Source(k)) => {
                self.defs.push(define_of(name, &k));
                self.reach(&k)
            }
            None => {
                let copy = copy_data(v).map_err(|kind| {
                    format!(
                        "spawn copies the values a process reaches, and `{name}` is a {kind}, \
                         which is not data; create it inside the process"
                    )
                })?;
                self.bindings.push((Arc::from(name), copy));
                Ok(())
            }
        }
    }
}

/// The code that runs `f(args…)` in a new process.
///
/// # Errors
///
/// When `f` is not a function, or reaches a value that cannot be copied.
pub fn spawn_code(f: &Value, args: &[Value]) -> Result<(Code, Entry), String> {
    let function =
        function_of(f).ok_or_else(|| format!("spawn takes a function, got {}", f.type_name()))?;
    let mut walk = Walk::new();
    let mut arg_names = Vec::with_capacity(args.len());
    for (i, a) in args.iter().enumerate() {
        let name = format!("%a{i}");
        let copy = copy_data(a).map_err(|kind| {
            format!(
                "spawn copies its arguments, and argument {} is a {kind}, which is not data",
                i + 1
            )
        })?;
        walk.bindings.push((Arc::from(name.as_str()), copy));
        arg_names.push(name);
    }
    let names: Vec<&str> = arg_names.iter().map(String::as_str).collect();
    let (entry, start) = match function {
        Function::Builtin(n) => (Entry::Builtin(n.to_string()), call(sym(&n), &names)),
        Function::Source(c) => {
            // A named function the spawner can still see under its name is a
            // definition; anything else is called as the lambda it is.
            let named = c.name.as_deref().filter(|n| {
                c.captured_env
                    .lookup(n)
                    .is_some_and(|v| name_of(&v).as_deref() == Some(*n))
            });
            match named {
                Some(n) => {
                    let global = c
                        .captured_env
                        .lookup(n)
                        .unwrap_or(Value::Closure(c.clone()));
                    walk.bring(n, &global)?;
                    (Entry::Named(n.to_string()), call(sym(n), &names))
                }
                None => {
                    walk.reach(&c)?;
                    let lambda = lambda_of(&c);
                    (Entry::Lambda(lambda.clone()), call(lambda, &names))
                }
            }
        }
    };
    Ok((
        Code {
            defs: walk.defs,
            bindings: walk.bindings,
            start: Some(start),
        },
        entry,
    ))
}

/// The definitions and bindings `f` reaches, with `f` itself defined under
/// `as_name`. What a migration installs and a server's handler starts from.
///
/// # Errors
///
/// As [`spawn_code`].
pub fn function_code(f: &Value, as_name: &str) -> Result<Code, String> {
    let function =
        function_of(f).ok_or_else(|| format!("expected a function, got {}", f.type_name()))?;
    let mut walk = Walk::new();
    match function {
        Function::Builtin(n) => {
            walk.defs.push(define_value(as_name, sym(&n)));
        }
        Function::Source(c) => {
            let named = c.name.as_deref().filter(|n| {
                c.captured_env
                    .lookup(n)
                    .is_some_and(|v| name_of(&v).as_deref() == Some(*n))
            });
            match named {
                Some(n) => {
                    let global = c
                        .captured_env
                        .lookup(n)
                        .unwrap_or(Value::Closure(c.clone()));
                    walk.bring(n, &global)?;
                    if n != as_name {
                        walk.defs.push(define_value(as_name, sym(n)));
                    }
                }
                None => {
                    walk.reach(&c)?;
                    walk.defs.push(define_value(as_name, lambda_of(&c)));
                }
            }
        }
    }
    Ok(Code {
        defs: walk.defs,
        bindings: walk.bindings,
        start: None,
    })
}
