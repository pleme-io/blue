//! Embedding blue in a Rust host: load a program into an interpreter the host
//! built, then call its definitions by name.
//!
//! [`crate::pipeline::run_in_surface`] evaluates with a hostless interpreter
//! and returns the last value, which suits `blue run` and nothing that wants a
//! program to be a library of entry points. A host (arnes's slash commands and
//! tools are the first) needs three things that path cannot give: its own
//! primitives, closures that reach its state through `&mut H`, and a call into
//! one named function with arguments.
//!
//! The stages before evaluation are [`crate::pipeline::prepare`], the same
//! function `run_in_surface` uses, so a hosted program is checked and erased
//! exactly as a run one is. Only the interpreter differs: it is built by
//! [`crate::interpreter`] with the host's type, and the host installs its
//! primitives on it before the program's top-level forms run.

use std::sync::Arc;

use tatara_lisp_eval::{Interpreter, Value};

use crate::pipeline::{builtin_names, eval_prepared, prepare, RunError};
use crate::uses::{Entry, Loader};

/// A loaded blue program whose definitions a host can call.
pub struct Hosted<H: 'static> {
    interp: Interpreter<H>,
    /// The entry file's namespace: its definitions run under this
    /// namespace's keys (`%root/f` for a script), and a host names them bare.
    entry: blue_lang_check::Namespace,
}

/// Parse, check and erase `entry`, build a blue interpreter over `H`, let
/// `install` register the host's primitives on it, then evaluate the
/// program's top-level forms (its `def`s) with `host`.
///
/// # Errors
///
/// Every [`RunError`] the pipeline has: parse, import, type and runtime
/// errors, the last two rendered `file:line:col: message`.
pub fn load_hosted<H: 'static>(
    entry: Entry<'_>,
    loader: &dyn Loader,
    host: &mut H,
    install: impl FnOnce(&mut Interpreter<H>),
) -> Result<Hosted<H>, RunError> {
    // The host's primitives are installed BEFORE the check stage, so names
    // the host binds resolve: the stage reads its name table off this
    // interpreter. Installing is not evaluation; the stage order holds.
    let mut interp = crate::interpreter(host);
    install(&mut interp);
    let prepared = prepare(entry, loader, None, &builtin_names(&interp))?;
    eval_prepared(&mut interp, &prepared, host)?;
    let entry = prepared.entry_namespace();
    Ok(Hosted { interp, entry })
}

impl<H: 'static> Hosted<H> {
    /// What `name` is bound to: the entry's definition of it (under its
    /// runtime key), else a global of that name (a host primitive, a builtin).
    /// A qualified `pkg::name` is bidama `pkg`'s definition, exactly as a
    /// program writes it, and `blue::name` is the builtin.
    fn lookup(&self, name: &str) -> Option<Value> {
        match name.split_once("::") {
            Some((blue_lang_syntax::BUILTIN_QUALIFIER, bare)) => self.interp.lookup_global(bare),
            Some((pkg, bare)) => self.interp.lookup_global(&blue_lang_check::names::key(
                &blue_lang_check::Namespace::Bidama(pkg.to_owned()),
                bare,
            )),
            None => self
                .interp
                .lookup_global(&blue_lang_check::names::key(&self.entry, name))
                .or_else(|| self.interp.lookup_global(name)),
        }
    }

    /// Whether the program defines a callable named `name`.
    #[must_use]
    pub fn defines(&self, name: &str) -> bool {
        matches!(
            self.lookup(name),
            Some(Value::Closure(_) | Value::NativeFn(_))
        )
    }

    /// Call the definition `name` with `args`.
    ///
    /// # Errors
    ///
    /// [`RunError::Eval`] naming the function when it is not defined or is not
    /// callable, or with the message it raised.
    pub fn call(&mut self, name: &str, args: Vec<Value>, host: &mut H) -> Result<Value, RunError> {
        let callee = match self.lookup(name) {
            Some(v @ (Value::Closure(_) | Value::NativeFn(_))) => v,
            Some(other) => {
                return Err(RunError::Eval(Box::new(crate::observe::Fault::from(
                    format!("{name} is not a function (it is {})", kind(&other)),
                ))))
            }
            None => {
                return Err(RunError::Eval(Box::new(
                    format!("no function named {name}").into(),
                )))
            }
        };
        self.interp
            .apply_external_value(&callee, args, host, tatara_lisp::Span::synthetic())
            .map_err(|e| RunError::Eval(Box::new(format!("{name}: {}", e.short_message()).into())))
    }
}

/// Why a framed load ([`load_hosted_in_frame`]) refused a program.
#[derive(Debug, thiserror::Error)]
pub enum FramedError {
    /// A stage of the pipeline refused it, or its top-level forms raised.
    #[error("{0}")]
    Run(#[from] RunError),
    /// It names what its frame does not permit. Every name, not the first.
    #[error("it names {} outside its frame: {}", if .names.len() == 1 { "a name" } else { "names" }, .names.join(", "))]
    Escapes { names: Vec<String> },
}

/// Why a budgeted call ([`Hosted::call_budgeted`]) stopped short.
#[derive(Debug, thiserror::Error)]
pub enum CallError {
    #[error("no function named {0}")]
    Undefined(String),
    #[error("{name} is not a function (it is {kind})")]
    NotAFunction { name: String, kind: &'static str },
    /// The call ran past its step or depth budget.
    #[error("{name}: {message}")]
    Exhausted { name: String, message: String },
    /// The call raised.
    #[error("{name}: {message}")]
    Raised { name: String, message: String },
}

/// [`load_hosted`], refusing a program that names anything `permits` does
/// not admit, and running its top-level forms under `budget`.
///
/// The frame is checked over the whole resolved program, every imported
/// bidama's forms included, after the check stage and before any form runs
/// (`blue_lang_waku::free_names`, the reach check a Bluefile is read under).
/// A name the frame refuses that the interpreter binds is also rebound to a
/// refusal, so a name the tree cannot show, one built at run time and
/// applied, is refused when it is called rather than run.
///
/// # Errors
///
/// [`FramedError::Run`] for every [`RunError`] [`load_hosted`] has,
/// [`FramedError::Escapes`] naming every refused name.
pub fn load_hosted_in_frame<H: 'static>(
    entry: Entry<'_>,
    loader: &dyn Loader,
    host: &mut H,
    install: impl FnOnce(&mut Interpreter<H>),
    permits: &dyn Fn(&str) -> bool,
    budget: tatara_lisp_eval::vm::Budget,
) -> Result<Hosted<H>, FramedError> {
    let mut interp = crate::interpreter(host);
    install(&mut interp);
    let prepared = prepare(entry, loader, None, &builtin_names(&interp))?;
    let escapes = blue_lang_waku::free_names(prepared.erased(), permits);
    if !escapes.is_empty() {
        return Err(FramedError::Escapes {
            names: escapes.into_iter().collect(),
        });
    }
    for name in interp.reserved_head_names() {
        if !permits(&name) && interp.lookup_global(&name).is_some() {
            let refused = name.clone();
            interp.register_fn(
                name,
                tatara_lisp_eval::Arity::Any,
                move |_: &[Value], _: &mut H, span| {
                    Err(tatara_lisp_eval::EvalError::native_fn(
                        refused.to_string(),
                        "outside this program's frame",
                        span,
                    ))
                },
            );
        }
    }
    interp
        .set_budget(budget)
        .map_err(|e| RunError::Eval(Box::new(e.to_string().into())))?;
    eval_prepared(&mut interp, &prepared, host)?;
    let entry = prepared.entry_namespace();
    Ok(Hosted { interp, entry })
}

impl<H: 'static> Hosted<H> {
    /// Call the definition `name` with `args` under `budget`, which starts
    /// unspent for this call. Running past it is [`CallError::Exhausted`],
    /// told apart from a raise.
    ///
    /// # Errors
    ///
    /// [`CallError`]: the name is not a function, or the call ran out or
    /// raised.
    pub fn call_budgeted(
        &mut self,
        name: &str,
        args: Vec<Value>,
        host: &mut H,
        budget: tatara_lisp_eval::vm::Budget,
    ) -> Result<Value, CallError> {
        let callee = self.callee(name)?;
        if let Err(e) = self.interp.set_budget(budget) {
            return Err(CallError::Raised {
                name: name.to_string(),
                message: e.to_string(),
            });
        }
        self.apply(name, &callee, args, host)
    }

    pub fn try_call(
        &mut self,
        name: &str,
        args: Vec<Value>,
        host: &mut H,
    ) -> Result<Value, CallError> {
        let callee = self.callee(name)?;
        self.apply(name, &callee, args, host)
    }

    fn callee(&self, name: &str) -> Result<Value, CallError> {
        match self.lookup(name) {
            Some(v @ (Value::Closure(_) | Value::NativeFn(_))) => Ok(v),
            Some(other) => Err(CallError::NotAFunction {
                name: name.to_string(),
                kind: kind(&other),
            }),
            None => Err(CallError::Undefined(name.to_string())),
        }
    }

    fn apply(
        &mut self,
        name: &str,
        callee: &Value,
        args: Vec<Value>,
        host: &mut H,
    ) -> Result<Value, CallError> {
        self.interp
            .apply_external_value(callee, args, host, tatara_lisp::Span::synthetic())
            .map_err(|e| match e {
                tatara_lisp_eval::EvalError::BudgetExceeded { .. } => CallError::Exhausted {
                    name: name.to_string(),
                    message: e.short_message(),
                },
                other => CallError::Raised {
                    name: name.to_string(),
                    message: other.short_message(),
                },
            })
    }
}

/// A string argument, the common case for a host passing text in.
#[must_use]
pub fn text(s: &str) -> Value {
    Value::Str(Arc::from(s))
}

fn kind(v: &Value) -> &'static str {
    match v {
        Value::Nil => "nil",
        Value::Bool(_) => "a boolean",
        Value::Int(_) | Value::Float(_) => "a number",
        Value::Str(_) => "a string",
        Value::List(_) => "a list",
        Value::Map(_) => "a map",
        _ => "a value",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::uses::NoLoader;
    use tatara_lisp_eval::Arity;

    /// What a host sees of the program: the notes it was sent.
    #[derive(Default)]
    struct Notes(Vec<String>);

    fn install(interp: &mut Interpreter<Notes>) {
        interp.register_fn(
            "note",
            Arity::Exact(1),
            |args: &[Value], h: &mut Notes, _span| {
                if let Value::Str(s) = &args[0] {
                    h.0.push(s.to_string());
                }
                Ok(Value::Nil)
            },
        );
    }

    fn load(src: &str, host: &mut Notes) -> Result<Hosted<Notes>, RunError> {
        load_hosted(Entry::anonymous(src), &NoLoader, host, install)
    }

    fn as_text(v: &Value) -> String {
        match v {
            Value::Str(s) => s.to_string(),
            other => format!("{other:?}"),
        }
    }

    #[test]
    fn an_empty_program_defines_nothing() {
        let mut host = Notes::default();
        let mut p = load("", &mut host).expect("an empty program loads");
        assert!(!p.defines("run"));
        let err = p.call("run", vec![], &mut host).unwrap_err().to_string();
        assert!(err.contains("no function named run"), "{err}");
    }

    #[test]
    fn a_call_returns_the_function_value_for_its_arguments() {
        let mut host = Notes::default();
        let src = "def greet(who)\n  \"hello #{who}\"\nend\n";
        let mut p = load(src, &mut host).unwrap();
        assert!(p.defines("greet"));
        let v = p.call("greet", vec![text("blue")], &mut host).unwrap();
        assert_eq!(as_text(&v), "hello blue");
        // Identity: two calls with the same argument agree.
        let again = p.call("greet", vec![text("blue")], &mut host).unwrap();
        assert_eq!(as_text(&again), as_text(&v));
    }

    #[test]
    fn host_primitives_reach_the_host_state() {
        let mut host = Notes::default();
        let src = "def run(x)\n  note(\"saw #{x}\")\n  note(\"done\")\n  size_of(x)\nend\ndef size_of(s)\n  length(s)\nend\n";
        let mut p = load(src, &mut host).unwrap();
        let v = p.call("run", vec![text("abcd")], &mut host).unwrap();
        assert!(matches!(v, Value::Int(4)), "{v:?}");
        assert_eq!(host.0, vec!["saw abcd".to_owned(), "done".to_owned()]);
    }

    #[test]
    fn a_type_error_stops_the_load_before_anything_runs() {
        let mut host = Notes::default();
        let src = "note(\"top level ran\")\ndef f(x: Int) -> Int\n  \"no\"\nend\n";
        let err = load(src, &mut host).err().expect("refused").to_string();
        assert!(err.contains("error[B0003]"), "{err}");
        assert!(
            host.0.is_empty(),
            "no top-level form may run before the check passes"
        );
    }

    #[test]
    fn a_qualified_name_calls_a_bidamas_definition_and_a_bare_one_does_not() {
        let mut host = Notes::default();
        let loader = crate::uses::tests::MemLoader(
            [("tama", "def exports()\n  \"tama rows\"\nend\n")]
                .into_iter()
                .collect(),
        );
        let mut p = load_hosted(
            Entry::anonymous("use(\"tama\")\n"),
            &loader,
            &mut host,
            install,
        )
        .unwrap();
        assert!(p.defines("tama::exports"));
        let v = p.call("tama::exports", vec![], &mut host).unwrap();
        assert_eq!(as_text(&v), "tama rows");
        assert!(!p.defines("exports"));
        assert!(!p.defines("other::exports"));
        assert!(p.defines("blue::length"));
        let err = p
            .call("tama::absent", vec![], &mut host)
            .unwrap_err()
            .to_string();
        assert!(err.contains("no function named tama::absent"), "{err}");
    }

    #[test]
    fn a_raise_and_a_non_function_are_typed_errors_naming_the_function() {
        let mut host = Notes::default();
        let src = "LIMIT = 3\ndef boom()\n  throw(error(\"bad\"))\nend\n";
        let mut p = load(src, &mut host).unwrap();
        let raised = p.call("boom", vec![], &mut host).unwrap_err().to_string();
        assert!(raised.contains("boom"), "{raised}");
        let not_fn = p.call("LIMIT", vec![], &mut host).unwrap_err().to_string();
        assert!(not_fn.contains("not a function"), "{not_fn}");
    }
}
