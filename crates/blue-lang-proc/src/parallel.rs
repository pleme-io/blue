//! A `map` whose callback only computes, run on several cores (W4.1 of
//! docs/FACTS.md).
//!
//! The callback travels as a process's would: [`crate::code::function_code`]
//! turns it back into code, and every element is copied as a message is
//! ([`crate::mailbox::copy_data`]). Each worker builds its own interpreter,
//! maps one contiguous slice, and copies its answers back; the slices are
//! joined in order, so the answer is the one a single thread gives.
//!
//! A callback or an element that cannot travel, a worker that raises, and a
//! worker that dies all answer [`Err`]: the caller then maps on its own
//! thread, which gives the same answer, or raises the error a single thread
//! raises first.

use std::sync::Arc;

use tatara_lisp_eval::vm::{compile_program, Budget, Vm, DEFAULT_MAX_DEPTH};
use tatara_lisp_eval::{Interpreter, Value};

use crate::code;
use crate::mailbox::copy_data;
use crate::scheduling::LANE_STACK;

/// What a worker's interpreter is built from.
pub type Factory = dyn Fn() -> Interpreter<()> + Sync;

const CALLBACK: &str = "%par_f";
const SLICE: &str = "%par_xs";

/// `f` applied to every element of `xs`, in order, on `workers` threads.
///
/// # Errors
///
/// Why the map could not run apart: the callback or an element cannot be
/// copied, or a worker raised or died. The caller maps on its own thread.
pub fn map(f: &Value, xs: &[Value], workers: usize, child: &Factory) -> Result<Vec<Value>, String> {
    let program = code::function_code(f, CALLBACK)?;
    let copied: Vec<Value> = xs
        .iter()
        .map(|x| {
            copy_data(x).map_err(|kind| format!("an element is {kind}, which cannot be copied"))
        })
        .collect::<Result<_, _>>()?;
    let per = copied.len().div_ceil(workers.max(1)).max(1);
    let slices: Vec<Vec<Value>> = copied.chunks(per).map(<[Value]>::to_vec).collect();
    let mut start = program.defs.clone();
    start.push(code::call(code::symbol("map"), &[CALLBACK, SLICE]));
    let chunk = Arc::new(compile_program(&start).map_err(|e| e.to_string())?);
    let bindings = &program.bindings;
    let answers: Vec<Result<Vec<Value>, String>> = std::thread::scope(|scope| {
        let running: Vec<_> = slices
            .into_iter()
            .map(|slice| {
                let chunk = chunk.clone();
                std::thread::Builder::new()
                    .name("blue-par-map".into())
                    .stack_size(LANE_STACK)
                    .spawn_scoped(scope, move || {
                        let mut interp = child();
                        for (n, v) in bindings {
                            interp.define_global(n.clone(), v.clone());
                        }
                        interp.define_global(Arc::from(SLICE), Value::list(slice));
                        let mut vm = Vm::with_budget(Budget {
                            fuel: None,
                            max_depth: Some(DEFAULT_MAX_DEPTH),
                            quantum: None,
                        });
                        let out = vm
                            .run(&chunk, &mut interp, &mut ())
                            .map_err(|e| e.to_string())?;
                        detached(&out)
                    })
            })
            .collect();
        running
            .into_iter()
            .map(|t| match t {
                Ok(handle) => handle
                    .join()
                    .unwrap_or_else(|_| Err("a worker died".into())),
                Err(e) => Err(e.to_string()),
            })
            .collect()
    });
    let mut joined = Vec::with_capacity(xs.len());
    for answer in answers {
        joined.extend(answer?);
    }
    Ok(joined)
}

fn detached(out: &Value) -> Result<Vec<Value>, String> {
    let items: Vec<Value> = match out {
        Value::List(items) => items.to_vec(),
        Value::Nil => Vec::new(),
        other => return Err(format!("a worker answered {}", other.type_name())),
    };
    items
        .iter()
        .map(|v| {
            copy_data(v).map_err(|kind| format!("an answer is {kind}, which cannot be copied"))
        })
        .collect()
}
