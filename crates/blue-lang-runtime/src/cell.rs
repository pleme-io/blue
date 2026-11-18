//! Typed cells: the one place a value changes (docs/PURE-BLUE.md L1).
//!
//! A blue value is immutable, and a name is bound once. `set!` rebinds a name
//! that a closure may already hold, which is mutation hidden in a frame and a
//! cycle blue cannot see. A cell makes the same thing explicit: it is a value,
//! read with `cell_get` and replaced with `cell_put`, so a rebind is a typed
//! operation a checker, a census and a collector can find.
//!
//! A cell is held by a `Foreign` value. It is process-local by construction:
//! a message copies what it carries, and a cell has no data form to copy, so
//! it never crosses a process.

use std::sync::{Arc, Mutex};

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::errors::raise_kind;

/// What a `cell` value holds.
pub struct Cell(Mutex<Value>);

fn cell_of<'a>(
    v: &'a Value,
    word: &'static str,
    span: tatara_lisp::Span,
) -> Result<&'a Cell, EvalError> {
    match v {
        Value::Foreign(f) => f
            .downcast_ref::<Cell>()
            .ok_or_else(|| not_a_cell(v, word, span)),
        other => Err(not_a_cell(other, word, span)),
    }
}

fn not_a_cell(v: &Value, word: &'static str, span: tatara_lisp::Span) -> EvalError {
    raise_kind(
        "type_error",
        format!("{word}: a cell, got {}", v.type_name()),
        span,
    )
}

/// Bind `cell`, `cell_get`, `cell_put` and `cell?`.
pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn("cell", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Foreign(Arc::new(Cell(Mutex::new(a[0].clone())))))
    });
    interp.register_fn(
        "cell_get",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| {
            let c = cell_of(&a[0], "cell_get", span)?;
            Ok(c.0.lock().map(|g| g.clone()).unwrap_or(Value::Nil))
        },
    );
    interp.register_fn(
        "cell_put",
        Arity::Exact(2),
        |a: &[Value], _h: &mut H, span| {
            let c = cell_of(&a[0], "cell_put", span)?;
            if let Ok(mut g) = c.0.lock() {
                *g = a[1].clone();
            }
            Ok(a[1].clone())
        },
    );
    interp.register_fn("cell?", Arity::Exact(1), |a: &[Value], _h: &mut H, _s| {
        Ok(Value::Bool(matches!(
            &a[0],
            Value::Foreign(f) if f.is::<Cell>()
        )))
    });
}
