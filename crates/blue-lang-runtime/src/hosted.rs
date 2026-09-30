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
    fn lookup(&self, name: &str) -> Option<Value> {
        self.interp
            .lookup_global(&blue_lang_check::names::key(&self.entry, name))
            .or_else(|| self.interp.lookup_global(name))
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
                return Err(RunError::Eval(format!(
                    "{name} is not a function (it is {})",
                    kind(&other)
                )))
            }
            None => return Err(RunError::Eval(format!("no function named {name}"))),
        };
        self.interp
            .apply_external_value(&callee, args, host, tatara_lisp::Span::synthetic())
            .map_err(|e| RunError::Eval(format!("{name}: {}", e.short_message())))
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
