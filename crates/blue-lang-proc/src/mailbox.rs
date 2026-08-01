//! Mailboxes, `send`, and `receive`.
//!
//! Supervision without message passing is just restart. A telephony switch or
//! an order router is a *mesh* of processes exchanging messages; the
//! supervisor is what keeps the mesh up, not what makes it work.
//!
//! ## Blocking is free, and that is the whole point
//!
//! `receive` on an empty mailbox parks the process via
//! [`tatara_lisp_eval::vm::Vm::park`]: the VM restores the operand stack,
//! rewinds to the call, and reports `Progress::Blocked`. The scheduler then
//! sets the process aside until a message arrives.
//!
//! The alternative — polling in a loop — is not merely wasteful. It **burns
//! the waiting process's fuel**, so a process waiting on a message that will
//! certainly arrive can die of a budget it never needed. A telephony process
//! idle between calls would be the first casualty.
//!
//! ## `receive` cannot lose a message, structurally
//!
//! A parking primitive must consume nothing, because its call is
//! re-executed — and `receive` is registered through
//! [`Interpreter::register_awaitable_fn`], whose readiness phase holds an
//! **immutable** `&System`. Dequeue-then-park is therefore not discouraged
//! here; it does not typecheck (`register_awaitable_fn`'s `compile_fail`
//! doctest asserts exactly that).
//!
//! This matters most for the case that does not exist yet. A *selective*
//! receive takes a message, finds it does not match the pattern, and must
//! wait — the shape that loses the message on every non-match. The split
//! removes the possibility before the feature that would have hit it.

use std::collections::{HashMap, VecDeque};

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{Interpreter, Value};

use crate::Pid;

/// The host state a blue process tree runs against.
///
/// Mailboxes live here rather than on the [`crate::Supervisor`] on purpose:
/// the supervisor owns the processes and hands `&mut H` to `Vm::step`, so a
/// supervisor-owned mailbox map would be borrowed twice at once.
#[derive(Debug, Default)]
pub struct System {
    boxes: HashMap<Pid, VecDeque<Value>>,
    /// Whose turn it is. The scheduler sets this before each slice so
    /// `receive` and `self` know which process is asking.
    current: Pid,
    /// Sends to a pid with no mailbox. Kept rather than dropped so a
    /// misdirected message is diagnosable instead of invisible.
    pub undeliverable: Vec<(Pid, Value)>,
}

impl crate::Readiness for System {
    fn is_ready(&self, pid: Pid) -> bool {
        self.has_mail(pid)
    }

    fn any_pending(&self) -> bool {
        self.any_mail()
    }

    fn set_current(&mut self, pid: Pid) {
        self.current = pid;
    }

    fn on_restart(&mut self, pid: Pid) {
        self.clear(pid);
    }
}

impl System {
    pub fn new() -> Self {
        Self::default()
    }

    /// Give `pid` a mailbox. Called by the supervisor on spawn.
    pub fn register(&mut self, pid: Pid) {
        self.boxes.entry(pid).or_default();
    }

    pub fn current(&self) -> Pid {
        self.current
    }

    /// Enqueue a **deep copy** of `msg`.
    ///
    /// `Value` is `Arc`-based, so pushing it as-is would share structure
    /// between two processes and quietly reintroduce exactly the coupling that
    /// separate interpreters removed. Copying at the boundary is what makes
    /// "processes share nothing" true rather than nearly true.
    pub fn send(&mut self, to: Pid, msg: Value) {
        let msg = deep_copy(&msg);
        match self.boxes.get_mut(&to) {
            Some(q) => q.push_back(msg),
            None => self.undeliverable.push((to, msg)),
        }
    }

    pub fn has_mail(&self, pid: Pid) -> bool {
        self.boxes.get(&pid).is_some_and(|q| !q.is_empty())
    }

    pub fn mail_count(&self, pid: Pid) -> usize {
        self.boxes.get(&pid).map_or(0, VecDeque::len)
    }

    /// Empty a mailbox. A restarted process starts with a clean one: the
    /// messages that were in flight when it crashed were addressed to the
    /// *incarnation that died*, and replaying them into the fresh one is how
    /// a poison message takes down a process forever.
    pub fn clear(&mut self, pid: Pid) {
        if let Some(q) = self.boxes.get_mut(&pid) {
            q.clear();
        }
    }

    /// Is any mailbox non-empty? Used to tell a live wait from a deadlock.
    pub fn any_mail(&self) -> bool {
        self.boxes.values().any(|q| !q.is_empty())
    }
}

/// Copy a value so nothing is shared with the sender.
///
/// Scalars are already values. Containers are rebuilt, so the receiver holds
/// its own `Arc`s. **Non-data values are refused rather than shared**: a
/// closure captures its defining environment, so sending one would hand a
/// second process a live reference into the first's globals — the exact leak
/// this function exists to prevent. Refusing yields `Nil` at the boundary
/// rather than silently sharing.
pub fn deep_copy(v: &Value) -> Value {
    match v {
        Value::Nil
        | Value::Bool(_)
        | Value::Int(_)
        | Value::Float(_)
        | Value::Str(_)
        | Value::Symbol(_)
        | Value::Keyword(_) => v.clone(),
        Value::List(items) => Value::List(std::sync::Arc::new(
            items.iter().map(deep_copy).collect::<Vec<_>>(),
        )),
        Value::Sexp(s, span) => Value::Sexp(s.clone(), *span),
        // A closure, a promise, a foreign handle, an error object: each either
        // captures an environment or wraps host state. Not copyable, and not
        // safe to share.
        _ => Value::Nil,
    }
}

/// Install `send`, `receive` and `self` into an interpreter whose host is a
/// [`System`].
///
/// Separate from `blue_lang_runtime::interpreter` because these three are the
/// only primitives that require a scheduler: called from `Vm::run`, `receive`
/// on an empty mailbox is a named deadlock rather than a wait.
pub fn install_process_primitives(interp: &mut Interpreter<System>) {
    // (send pid msg) -> msg
    //
    // Returns the message, as Erlang's `!` does, so `send` composes in an
    // expression rather than only as a statement.
    interp.register_fn(
        "send",
        Arity::Exact(2),
        |args: &[Value], sys: &mut System, span| {
            let to = match &args[0] {
                Value::Int(n) => Pid(*n as u64),
                // A typed rejection, not a silent no-op: sending to a
                // non-pid is a program error and must read as one.
                other => {
                    return Err(tatara_lisp_eval::EvalError::type_mismatch(
                        "pid (int)",
                        other.type_name(),
                        span,
                    )
                    .into())
                }
            };
            sys.send(to, args[1].clone());
            Ok(args[1].clone())
        },
    );

    // (receive) -> the oldest message, parking while the mailbox is empty.
    //
    // Two-phase: `ready` may only LOOK at the mailbox (it holds `&System`),
    // and `take` runs only once something is there. The compiler, not a
    // comment, is what stops a future selective receive from popping a
    // message and then parking.
    interp.register_awaitable_fn(
        "receive",
        Arity::Exact(0),
        |_args: &[Value], sys: &System| sys.has_mail(sys.current()),
        |_args: &[Value], sys: &mut System, _span| {
            let me = sys.current();
            Ok(sys
                .boxes
                .get_mut(&me)
                .and_then(VecDeque::pop_front)
                .unwrap_or(Value::Nil))
        },
    );

    // (self) -> my pid
    interp.register_fn(
        "self",
        Arity::Exact(0),
        |_args: &[Value], sys: &mut System, _span| Ok(Value::Int(sys.current().0 as i64)),
    );
}
