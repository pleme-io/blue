//! The branch probe every interpreter binds: `(blue-coverage-arm "def" site
//! arm)`, which `blue test --coverage` places first in each arm of a decision
//! (docs/COVERAGE.md B1, B2, E3).
//!
//! The record is one per process, so an arm a spawned process takes is
//! recorded too: a process runs on its own interpreter, and only a binding
//! every interpreter holds reaches it. The name is kebab-case, so no blue
//! program can call it; only the instrumented tree names it.

use std::collections::BTreeSet;
use std::sync::{LazyLock, Mutex};

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{Interpreter, Value};

/// The probe's name.
pub const PROBE: &str = "blue-coverage-arm";

static TAKEN: LazyLock<Mutex<BTreeSet<(String, usize, usize)>>> =
    LazyLock::new(|| Mutex::new(BTreeSet::new()));

/// Bind the probe.
pub fn install<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        PROBE,
        Arity::Exact(3),
        |args: &[Value], _h: &mut H, _span| {
            if let (Value::Str(def), Value::Int(site), Value::Int(arm)) =
                (&args[0], &args[1], &args[2])
            {
                if let (Ok(site), Ok(arm), Ok(mut t)) =
                    (usize::try_from(*site), usize::try_from(*arm), TAKEN.lock())
                {
                    t.insert((def.to_string(), site, arm));
                }
            }
            Ok(Value::Nil)
        },
    );
}

/// Whether a run in this process took arm `arm` of decision `site` of `def`.
#[must_use]
pub fn taken(def: &str, site: usize, arm: usize) -> bool {
    TAKEN
        .lock()
        .is_ok_and(|t| t.contains(&(def.to_string(), site, arm)))
}
