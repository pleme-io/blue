//! Watching a blue program run: the call stack a runtime error reports, and
//! the per-definition counters `blue profile`, `blue test --coverage` and
//! `blue trace` read.
//!
//! One mechanism under all of them: tatara-lisp-eval's call hook
//! (`tatara_lisp_eval::observe`), which every closure activation passes once,
//! tail calls included. Its unwind arm is always on and costs nothing until an
//! error, so every runtime error carries the frames it left ([`Fault`]). Its
//! observer arm is installed only when a tool asks, and [`Recorder`] is the one
//! observer here: counts, inclusive and exclusive time and allocations
//! ([`crate::alloc`]), and the trace of one definition. The hook's `enter` may also answer a call without running its
//! body, which is where a memo table keyed on a definition and its arguments
//! plugs in (`theory/BLUE-TOOLING.md` T-M) without a second hook.
//!
//! Every count is keyed by the DEFINITION the runtime binds (`retsu/first`,
//! `%root/f`), the key the check stage resolved. That is the key the engine's
//! per-definition queries carry (`theory/BLUE-ENGINE.md` §3), so when
//! `def_hash` replaces the name, the counters move with it.
//!
//! The tree-walker only: the VM reports neither arm.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Duration, Instant};

use tatara_lisp::{Span, Spanned};
use tatara_lisp_eval::{EvalError, Value};

pub use tatara_lisp_eval::observe::{Call, CallObserver, Exit, Trace, TraceFrame};

use crate::alloc::Allocations;
use crate::uses::ResolvedProgram;

/// A function the program defines at the top level, under its runtime key.
#[derive(Clone, Debug)]
pub struct Definition {
    /// What the runtime binds: `retsu/first`, `%root/f`.
    pub key: Arc<str>,
    /// What the author writes: `retsu::first`, `f`.
    pub name: String,
    /// The top-level form that defines it.
    pub top_level: usize,
    /// The defining form's span, in its own file.
    pub span: Span,
    /// Defined in the entry file rather than an imported one.
    pub entry: bool,
    /// Where it is defined.
    pub place: Place,
}

/// A position as a reader follows it. Each part is absent when it cannot be
/// justified, never guessed.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Place {
    pub file: Option<String>,
    pub line: Option<usize>,
    pub column: Option<usize>,
}

impl Place {
    fn of(program: &ResolvedProgram, top_level: usize, span: Span) -> Self {
        let at = program.locate(top_level, span, "");
        Self {
            file: at.file_name(),
            line: at.line_col().map(|(l, _)| l),
            column: at.line_col().map(|(_, c)| c),
        }
    }

    fn json(&self) -> serde_json::Value {
        serde_json::json!({ "file": self.file, "line": self.line, "column": self.column })
    }
}

impl std::fmt::Display for Place {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.file.as_deref().unwrap_or("<unknown file>"))?;
        if let Some(line) = self.line {
            write!(f, ":{line}")?;
            if let Some(col) = self.column {
                write!(f, ":{col}")?;
            }
        }
        Ok(())
    }
}

/// Every function a program defines at its top level: the denominator of
/// coverage, and the table that turns a closure's runtime key back into a
/// name and a place.
#[derive(Debug, Default)]
pub struct Definitions {
    defs: Vec<Definition>,
    by_key: HashMap<Arc<str>, usize>,
    /// `f = fn(x) … end` binds an unnamed lambda: found by its span. `None`
    /// when two definitions share one (two files, same offsets), so no
    /// activation is credited to the wrong one.
    by_lambda: HashMap<Span, Option<usize>>,
}

impl Definitions {
    /// Read off the tree the evaluator runs (`erased`, one form per top-level
    /// form of `program`).
    #[must_use]
    pub fn of(program: &ResolvedProgram, erased: &[Spanned]) -> Self {
        let mut out = Self::default();
        for (i, form) in erased.iter().enumerate() {
            let Some(items) = form.as_list() else {
                continue;
            };
            if items.first().and_then(Spanned::as_symbol) != Some("define") || items.len() < 3 {
                continue;
            }
            let (key, lambda) = match items[1].as_list() {
                Some(head) => match head.first().and_then(Spanned::as_symbol) {
                    Some(k) => (k, None),
                    None => continue,
                },
                None => match (items[1].as_symbol(), items[2].as_list()) {
                    (Some(k), Some(value))
                        if value.first().and_then(Spanned::as_symbol) == Some("lambda") =>
                    {
                        (k, Some(items[2].span))
                    }
                    _ => continue,
                },
            };
            let key: Arc<str> = Arc::from(key);
            let index = out.defs.len();
            out.defs.push(Definition {
                name: display_key(&key),
                key: Arc::clone(&key),
                top_level: i,
                span: form.span,
                entry: program.owner_of(i) == Some(ResolvedProgram::ENTRY),
                place: Place::of(program, i, form.span),
            });
            out.by_key.insert(key, index);
            if let Some(span) = lambda {
                out.by_lambda
                    .entry(span)
                    .and_modify(|slot| *slot = None)
                    .or_insert(Some(index));
            }
        }
        out
    }

    pub fn iter(&self) -> impl Iterator<Item = &Definition> {
        self.defs.iter()
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.defs.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.defs.is_empty()
    }

    #[must_use]
    pub fn get(&self, index: usize) -> Option<&Definition> {
        self.defs.get(index)
    }

    /// The definitions an author's `name` can mean: the exact name
    /// (`retsu::first`, `f`), else every definition whose own name is it.
    #[must_use]
    pub fn named(&self, name: &str) -> Vec<usize> {
        let exact: Vec<usize> = (0..self.defs.len())
            .filter(|&i| self.defs[i].name == name || &*self.defs[i].key == name)
            .collect();
        if !exact.is_empty() {
            return exact;
        }
        (0..self.defs.len())
            .filter(|&i| self.defs[i].name.rsplit("::").next() == Some(name))
            .collect()
    }

    /// Which definition an activation is a call of: by its name, or for a
    /// lambda bound at the top level, by its span.
    fn of_call(&self, name: Option<&Arc<str>>, source: Span) -> Option<usize> {
        match name {
            Some(n) => self.by_key.get(n).copied(),
            None => self.by_lambda.get(&source).copied().flatten(),
        }
    }

    fn of_frame(&self, frame: &TraceFrame) -> Option<usize> {
        self.of_call(frame.name.as_ref(), frame.source)
    }

    /// A named closure the program did not define: one of the runtime's own
    /// tatara-lisp builtins. Every program definition runs under a qualified
    /// key (`%root/f`, `retsu/first`), so a bare name is never the author's.
    fn is_builtin(&self, frame: &TraceFrame) -> bool {
        frame.name.as_ref().is_some_and(|n| {
            !self.by_key.contains_key(n) && blue_lang_syntax::qualified(n).is_none()
        })
    }

    /// Where the program's own code was when an error left it: the innermost
    /// frame that is not a builtin, and the span inside it — the error's own
    /// span, or the call into the builtin that raised.
    fn first_own(&self, trace: &Trace, error: Span) -> (Option<usize>, Span) {
        let frames = &trace.frames;
        let own = frames.iter().position(|f| !self.is_builtin(f));
        match own {
            Some(0) | None => (own, error),
            Some(k) => (Some(k), frames[k - 1].at),
        }
    }
}

/// A runtime key as the author writes it: `%root/f` is `f`, `retsu/first` is
/// `retsu::first`, a builtin stays bare.
#[must_use]
pub fn display_key(key: &str) -> String {
    let root = format!(
        "{}{}",
        blue_lang_check::names::ROOT_QUALIFIER,
        blue_lang_syntax::QUALIFIER
    );
    if let Some(rest) = key.strip_prefix(&root) {
        rest.to_string()
    } else if let Some((pkg, name)) = blue_lang_syntax::qualified(key) {
        format!("{pkg}::{name}")
    } else {
        key.to_string()
    }
}

/// One frame of a blue call stack: the definition that was running and where
/// in it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StackFrame {
    pub function: String,
    /// `None` for a builtin the runtime defines in tatara-lisp (`first`,
    /// `map`): its offsets index the runtime's own source, not the program's.
    pub place: Option<Place>,
}

/// The frames a runtime error unwound through, innermost first, ending with
/// the top-level form that started the chain when it was recorded.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Stack {
    pub frames: Vec<StackFrame>,
    /// Activations unwound, recorded or not. Above `frames.len()` when the
    /// recursion was deeper than `tatara_lisp_eval::observe::TRACE_FRAMES`.
    pub depth: usize,
}

/// Distinct lines a rendered stack shows before it summarises the rest.
pub const STACK_LINES: usize = 24;

impl Stack {
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.frames.is_empty()
    }

    /// Read a [`Trace`] against the program that ran. `error` is where the
    /// innermost frame raised; `top_level` the form that was executing.
    #[must_use]
    pub fn of(
        program: &ResolvedProgram,
        defs: &Definitions,
        trace: &Trace,
        error: Span,
        top_level: usize,
    ) -> Self {
        let frames = &trace.frames;
        let mut out = Vec::with_capacity(frames.len() + 1);
        for (k, frame) in frames.iter().enumerate() {
            let def = defs.of_frame(frame);
            // A lambda is defined inside whatever named frame is outward of
            // it, which is the file its body's offsets index.
            let outer = frames[k + 1..].iter().find_map(|f| defs.of_frame(f));
            let site = def
                .or(outer)
                .and_then(|d| defs.get(d))
                .map_or(top_level, |d| d.top_level);
            if defs.is_builtin(frame) {
                out.push(StackFrame {
                    function: frame.name.as_deref().map_or_else(String::new, display_key),
                    place: None,
                });
                continue;
            }
            let at = if k == 0 { error } else { frames[k - 1].at };
            let function = match (def.and_then(|d| defs.get(d)), &frame.name) {
                (Some(d), _) => d.name.clone(),
                (None, Some(n)) => display_key(n),
                (None, None) => match outer.and_then(|d| defs.get(d)) {
                    Some(d) => format!("fn in {}", d.name),
                    None => "fn".to_string(),
                },
            };
            out.push(StackFrame {
                function,
                place: Some(Place::of(program, site, at)),
            });
        }
        if let Some(last) = frames.last() {
            if trace.depth == frames.len() {
                out.push(StackFrame {
                    function: "<top level>".to_string(),
                    place: Some(Place::of(program, top_level, last.at)),
                });
            }
        }
        Self {
            frames: out,
            depth: trace.depth,
        }
    }

    #[must_use]
    pub fn json(&self) -> serde_json::Value {
        serde_json::Value::Array(
            self.frames
                .iter()
                .map(|f| {
                    let mut v = f
                        .place
                        .as_ref()
                        .map_or_else(|| serde_json::json!({ "builtin": true }), Place::json);
                    v["function"] = serde_json::Value::String(f.function.clone());
                    v
                })
                .collect(),
        )
    }
}

impl std::fmt::Display for Stack {
    /// `  at f (file:line:col)`, one line per frame, a run of identical frames
    /// folded into one, at most [`STACK_LINES`] lines.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut runs: Vec<(&StackFrame, usize)> = Vec::new();
        for frame in &self.frames {
            match runs.last_mut() {
                Some((last, n)) if *last == frame => *n += 1,
                _ => runs.push((frame, 1)),
            }
        }
        let mut first = true;
        let mut line = |f: &mut std::fmt::Formatter<'_>, text: String| {
            let sep = if first { "" } else { "\n" };
            first = false;
            write!(f, "{sep}  {text}")
        };
        for (shown, (frame, n)) in runs.iter().enumerate() {
            if shown == STACK_LINES {
                let rest: usize = runs[shown..].iter().map(|(_, n)| n).sum();
                line(f, format!("… {rest} more frame(s)"))?;
                break;
            }
            match &frame.place {
                Some(place) => line(f, format!("at {} ({place})", frame.function))?,
                None => line(f, format!("at {} (builtin)", frame.function))?,
            }
            if *n > 1 {
                line(f, format!("… repeated {} more time(s)", n - 1))?;
            }
        }
        let unrecorded = self.depth.saturating_sub(self.frames.len());
        if unrecorded > 0 {
            line(f, format!("… {unrecorded} outer frame(s) not recorded"))?;
        }
        Ok(())
    }
}

/// A runtime error: what went wrong, where, and the blue call stack that led
/// there. [`crate::RunError::Eval`] carries one.
#[derive(Clone, Debug, Default)]
pub struct Fault {
    /// The message, names as the author writes them, without a position.
    pub message: String,
    /// Where it was raised.
    pub place: Place,
    /// `file:line:col: message`, the one-line form.
    pub located: String,
    pub stack: Stack,
}

impl Fault {
    /// An error at `top_level` of `program`, unwound through `trace`.
    #[must_use]
    pub fn of(
        program: &ResolvedProgram,
        erased: &[Spanned],
        top_level: usize,
        e: &EvalError,
        trace: &Trace,
    ) -> Self {
        let defs = Definitions::of(program, erased);
        let message = crate::pipeline::display_keys(&crate::messages::describe(e, erased));
        // `span()` is `None` for the arms that genuinely have no position
        // (`Reader`, `Halted`, `NotImplemented`); synthetic is the honest
        // stand-in, rendered as a file with no line.
        let raised = e.span().unwrap_or_else(Span::synthetic);
        // The innermost frame of the program's own owns the error's offsets,
        // which is what lets a raise inside a callee from another file name
        // that file; inside a builtin, the position is the call into it.
        let (own, at) = defs.first_own(trace, raised);
        let site = own
            .and_then(|k| trace.frames[k..].iter().find_map(|f| defs.of_frame(f)))
            .and_then(|d| defs.get(d))
            .map_or(top_level, |d| d.top_level);
        Self {
            located: program.locate(site, at, &message).to_string(),
            place: Place::of(program, site, at),
            stack: Stack::of(program, &defs, trace, raised, top_level),
            message,
        }
    }

    /// The JSON form: one object, the stack innermost first.
    #[must_use]
    pub fn json(&self) -> serde_json::Value {
        let mut v = self.place.json();
        v["stage"] = "eval".into();
        v["severity"] = "error".into();
        v["message"] = self.message.clone().into();
        v["stack"] = self.stack.json();
        v["stack_depth"] = self.stack.depth.into();
        v
    }
}

impl From<String> for Fault {
    fn from(message: String) -> Self {
        Self {
            located: message.clone(),
            message,
            ..Self::default()
        }
    }
}

impl std::fmt::Display for Fault {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.located)?;
        if !self.stack.is_empty() {
            write!(f, "\n{}", self.stack)?;
        }
        Ok(())
    }
}

/// What one definition, or one unnamed function, cost.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counts {
    /// Activations, a tail call counting as one.
    pub calls: u64,
    /// Time inside it and everything it called, counted once across recursion.
    pub inclusive: Duration,
    /// Time inside it alone.
    pub exclusive: Duration,
    /// Allocations made inside it and everything it called, counted once
    /// across recursion. Zero when the binary does not count allocations;
    /// [`Recorder::counts_allocations`] says which.
    pub allocated: Allocations,
    /// Allocations made inside it alone.
    pub allocated_exclusive: Allocations,
}

/// A recorded function: a definition, or a lambda no top-level name binds.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
enum Slot {
    Def(usize),
    /// Keyed by its runtime name when it has one (a macro's `define`), else
    /// by its span and the definition it ran inside.
    Other {
        name: Option<Arc<str>>,
        within: Option<usize>,
        source: Span,
    },
}

/// One live activation on the recorder's shadow stack.
struct Active {
    slot: Slot,
    start: Option<Instant>,
    children: Duration,
    /// This thread's allocation totals when the activation entered, read
    /// after the recorder's own bookkeeping for the entry.
    allocated_at: Option<Allocations>,
    allocated_children: Allocations,
    /// The arguments of a traced activation, kept for its exit line.
    traced: Option<Vec<Value>>,
}

#[derive(Default)]
struct State {
    stack: Vec<Active>,
    counts: HashMap<Slot, Counts>,
    live: HashMap<Slot, usize>,
    trace_depth: usize,
}

/// One line of `blue trace`: a call of the traced definition, or its exit.
pub enum TraceEvent<'a> {
    Call {
        depth: usize,
        name: &'a str,
        args: &'a [Value],
    },
    Exit {
        depth: usize,
        name: &'a str,
        args: &'a [Value],
        exit: Exit<'a>,
    },
}

/// Which definitions to trace, and where their lines go.
pub struct Tracer {
    pub targets: Vec<usize>,
    pub sink: Box<dyn Fn(&TraceEvent<'_>) + Send + Sync>,
}

/// The one observer: per-definition counts, optionally timed, optionally
/// tracing some definitions.
pub struct Recorder {
    defs: Arc<Definitions>,
    timed: bool,
    tracer: Option<Tracer>,
    state: Mutex<State>,
}

impl Recorder {
    /// `timed` reads the clock twice per activation; coverage leaves it off.
    #[must_use]
    pub fn new(defs: Arc<Definitions>, timed: bool, tracer: Option<Tracer>) -> Self {
        Self {
            defs,
            timed,
            tracer,
            state: Mutex::new(State::default()),
        }
    }

    fn state(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn slot(&self, call: &Call<'_>, stack: &[Active]) -> Slot {
        if let Some(d) = self.defs.of_call(call.name, call.source) {
            return Slot::Def(d);
        }
        let within = stack.iter().rev().find_map(|a| match a.slot {
            Slot::Def(d) => Some(d),
            Slot::Other { within, .. } => within,
        });
        Slot::Other {
            name: call.name.cloned(),
            within,
            source: call.source,
        }
    }

    fn label(&self, slot: &Slot) -> String {
        match slot {
            Slot::Def(d) => self
                .defs
                .get(*d)
                .map_or_else(String::new, |d| d.name.clone()),
            Slot::Other { name: Some(n), .. } => display_key(n),
            Slot::Other {
                name: None, within, ..
            } => match within.and_then(|d| self.defs.get(d)) {
                Some(d) => format!("fn in {}", d.name),
                None => "fn".to_string(),
            },
        }
    }

    /// Every function that ran, with what it cost, and every definition that
    /// did not run with zero calls: the profile and the coverage in one table.
    #[must_use]
    pub fn report(&self) -> Vec<Measured> {
        let state = self.state();
        let mut out: Vec<Measured> = self
            .defs
            .iter()
            .enumerate()
            .map(|(i, d)| Measured {
                name: d.name.clone(),
                definition: Some(i),
                place: d.place.clone(),
                entry: d.entry,
                counts: state.counts.get(&Slot::Def(i)).copied().unwrap_or_default(),
            })
            .collect();
        for (slot, counts) in &state.counts {
            let Slot::Other { within, .. } = slot else {
                continue;
            };
            let place = within
                .and_then(|d| self.defs.get(d))
                .map(|d| d.place.clone())
                .unwrap_or_default();
            out.push(Measured {
                name: self.label(slot),
                definition: None,
                place,
                entry: within
                    .and_then(|d| self.defs.get(d))
                    .is_some_and(|d| d.entry),
                counts: *counts,
            });
        }
        out
    }

    #[must_use]
    pub fn definitions(&self) -> &Definitions {
        &self.defs
    }

    /// Whether the allocation columns of [`Counts`] were measured: true only
    /// in a binary that installs [`crate::alloc::Counting`]. Elsewhere they
    /// read zero, which means unmeasured, never "allocated nothing".
    #[must_use]
    pub fn counts_allocations(&self) -> bool {
        crate::alloc::allocations().is_some()
    }
}

/// One row of [`Recorder::report`].
#[derive(Clone, Debug)]
pub struct Measured {
    pub name: String,
    /// Its index in [`Definitions`]; `None` for an unnamed function.
    pub definition: Option<usize>,
    pub place: Place,
    pub entry: bool,
    pub counts: Counts,
}

impl CallObserver for Recorder {
    fn enter(&self, call: &Call<'_>, args: &[Value]) -> Option<Value> {
        let mut state = self.state();
        let slot = self.slot(call, &state.stack);
        state.counts.entry(slot.clone()).or_default().calls += 1;
        *state.live.entry(slot.clone()).or_default() += 1;
        let traced = match (&self.tracer, &slot) {
            (Some(t), Slot::Def(d)) if t.targets.contains(d) => {
                let depth = state.trace_depth;
                state.trace_depth += 1;
                (t.sink)(&TraceEvent::Call {
                    depth,
                    name: &self.label(&slot),
                    args,
                });
                Some(args.to_vec())
            }
            _ => None,
        };
        state.stack.push(Active {
            slot,
            start: self.timed.then(Instant::now),
            children: Duration::ZERO,
            allocated_at: None,
            allocated_children: Allocations::default(),
            traced,
        });
        // Last, so the entry's own map and stack growth falls outside the
        // window the activation is charged for.
        if let Some(active) = state.stack.last_mut() {
            active.allocated_at = crate::alloc::allocations();
        }
        None
    }

    fn leave(&self, _call: &Call<'_>, exit: Exit<'_>) {
        // First, for the same reason `enter` reads it last.
        let allocated_now = crate::alloc::allocations();
        let mut state = self.state();
        let Some(active) = state.stack.pop() else {
            return;
        };
        let elapsed = active.start.map_or(Duration::ZERO, |s| s.elapsed());
        let allocated = match (allocated_now, active.allocated_at) {
            (Some(now), Some(at)) => now.since(at),
            _ => Allocations::default(),
        };
        if let Some(parent) = state.stack.last_mut() {
            parent.children += elapsed;
            parent.allocated_children += allocated;
        }
        let live = state.live.entry(active.slot.clone()).or_default();
        *live = live.saturating_sub(1);
        let outermost = *live == 0;
        let counts = state.counts.entry(active.slot.clone()).or_default();
        counts.exclusive += elapsed.saturating_sub(active.children);
        counts.allocated_exclusive += allocated.since(active.allocated_children);
        if outermost {
            counts.inclusive += elapsed;
            counts.allocated += allocated;
        }
        if let (Some(t), Some(args)) = (&self.tracer, &active.traced) {
            state.trace_depth = state.trace_depth.saturating_sub(1);
            (t.sink)(&TraceEvent::Exit {
                depth: state.trace_depth,
                name: &self.label(&active.slot),
                args,
                exit,
            });
        }
    }
}
