//! One evaluation session: the function the REPL, `blue eval`, `blue serve`
//! and an editor all call (`theory/BLUE-TOOLING.md` §2, §4).
//!
//! A session holds one interpreter and, per **context**, the program code is
//! evaluated against: a loaded file's top-level forms, or the session's own
//! when no file is named. Evaluating code in a context runs the same stages as
//! `blue run` — parse, resolve imports, check, lower, erase — over the
//! context's forms with the new code spliced in, then evaluates only the new
//! forms (and any bidama they newly import). So a name resolves in the REPL
//! exactly as it would in the file, and a definition made in the session is
//! one more top-level form of its context: redefining a function replaces its
//! form, and because callers reach it by its runtime key at call time, every
//! caller sees the new one at once.
//!
//! Three things bound an evaluation, each reported as its own status rather
//! than as an error message:
//!
//! - **The frame.** A host-effect [`Capability`] the session's frame does not
//!   grant is bound to a refusal: reaching it, directly or through any number
//!   of calls, stops the evaluation as [`Stop::Volatile`] naming the
//!   capability. The default frame grants none, so evaluation is pure unless
//!   the session was started with a wider one.
//! - **The step budget** ([`Stop::Exhausted`]), set fresh for each request.
//! - **The interrupt flag** ([`Stop::Interrupted`]), which another thread sets
//!   while an evaluation runs. The session never clears it before running, so
//!   an interrupt that arrives between "start" and the first step is not lost;
//!   a caller clears it when it starts a request ([`Session::interrupt_flag`]).
//!
//! What the code writes to stdout is captured into [`Outcome::out`], or
//! written through as it happens when the session was built with a live sink.

use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use blue_lang_check::{NameTable, Namespace};
use blue_lang_waku::{Capability, Reach, Waku, When, Where};
use tatara_lisp::{Atom, Sexp, Span, Spanned};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::pipeline::{self, RunError};
use crate::uses::{Entry, Loader, ResolvedProgram};

#[cfg(feature = "sys")]
pub mod protocol;

/// The frame a session evaluates in when nothing wider is asked for: every
/// pure capability, no host effect.
#[must_use]
pub fn pure_frame() -> Waku {
    frame_granting(&[])
}

/// A frame granting the pure capabilities plus `host`.
#[must_use]
pub fn frame_granting(host: &[Capability]) -> Waku {
    Waku {
        reach: Reach::only(
            Capability::ALL
                .into_iter()
                .filter(|c| !c.is_host_effect() || host.contains(c)),
        ),
        when: When::Anytime,
        place: Where::Process,
    }
}

/// How a session is built.
pub struct Config {
    pub frame: Waku,
    /// Steps each request may take when it names no budget; `None` falls back
    /// to the process's configured `max_steps` (unbounded by default).
    pub budget: Option<usize>,
    pub loader: Box<dyn Loader + Send>,
    /// Set from any thread to halt the running evaluation.
    pub interrupt: Arc<AtomicBool>,
    /// Write output through as it is produced instead of capturing it.
    pub live: Option<Box<dyn Write + Send>>,
}

impl Config {
    /// A pure session over `loader`, capturing output.
    #[must_use]
    pub fn new(loader: Box<dyn Loader + Send>) -> Self {
        Self {
            frame: pure_frame(),
            budget: None,
            loader,
            interrupt: Arc::new(AtomicBool::new(false)),
            live: None,
        }
    }
}

/// Why a request stopped without a result.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Stop {
    Error(Failure),
    /// The code reached a host capability the frame does not grant.
    Volatile { reach: Capability, name: String },
    /// The step budget ran out.
    Exhausted { limit: usize },
    Interrupted,
}

/// A request that failed, as a code and the rendered message.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Failure {
    /// `parse`, `import`, `runtime`, `not-found`, or the check rule's code
    /// (`B0001`) when the check stage refused the code.
    pub code: String,
    pub message: String,
}

impl Failure {
    fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }
}

/// What one request produced, and what the code wrote while producing it.
#[derive(Debug)]
pub struct Outcome<T> {
    pub result: Result<T, Stop>,
    pub out: String,
}

/// A name a context can complete to, with what it is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Item {
    /// As a program spells it: bare, or `pkg::name` for a bidama's.
    pub name: String,
    pub namespace: String,
    pub signature: Option<String>,
    pub doc: Option<String>,
}

/// How much of a file a load evaluates.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Load {
    /// Every top-level form, as `blue run` does.
    Whole,
    /// Definitions and `use` forms only: the context an expression in the
    /// file needs, without running the file's program.
    Definitions,
}

/// One macro-expansion step, or all of them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Step {
    One,
    All,
}

/// What the code writes, and the host effect it reached, if any.
#[derive(Default)]
pub struct Host {
    out: String,
    live: Option<Box<dyn Write + Send>>,
    reached: Option<(Capability, &'static str)>,
}

impl Host {
    fn write(&mut self, text: &str) {
        match &mut self.live {
            Some(w) => {
                let _ = w.write_all(text.as_bytes()).and_then(|()| w.flush());
            }
            None => self.out.push_str(text),
        }
    }
}

/// One top-level form of a context, as source.
#[derive(Clone, Debug)]
struct Form {
    /// The text from the end of the previous form through this one, so a
    /// comment or waiver above a definition travels with it.
    text: String,
    /// Where the form itself starts in `text`.
    at: usize,
    defines: Vec<String>,
    is_use: bool,
    /// Set on the forms a request runs: its place in the order they run, and
    /// where it starts in the request's own code when it came from there.
    fresh: Option<(usize, Option<usize>)>,
}

impl Form {
    /// Whether a context keeps this form once the request that wrote it ends.
    fn persists(&self) -> bool {
        !self.defines.is_empty() || self.is_use
    }

    fn settled(mut self) -> Self {
        self.fresh = None;
        self
    }
}

/// Put `form` into `forms`: in place of the form that defines the same name
/// (dropping any other that does), else at the end.
fn splice(forms: &mut Vec<Form>, form: Form) {
    let same = |f: &Form| f.defines.iter().any(|d| form.defines.contains(d));
    match forms.iter().position(same) {
        Some(first) => {
            let mut i = forms.len();
            while i > first + 1 {
                i -= 1;
                if same(&forms[i]) {
                    forms.remove(i);
                }
            }
            forms[first] = form;
        }
        None => forms.push(form),
    }
}

/// What code is evaluated against.
#[derive(Default)]
struct Context {
    path: Option<PathBuf>,
    forms: Vec<Form>,
    /// The last program checked in this context, and its name table.
    program: Option<ResolvedProgram>,
    names: Option<NameTable>,
}


/// One evaluation session.
pub struct Session {
    interp: Interpreter<Host>,
    host: Host,
    frame: Waku,
    budget: Option<usize>,
    loader: Box<dyn Loader + Send>,
    interrupt: Arc<AtomicBool>,
    /// The builtin name table, read once off a pristine interpreter, so a
    /// definition the session makes is never mistaken for a builtin.
    builtins: NameTable,
    contexts: BTreeMap<Option<PathBuf>, Context>,
    /// Bidamas whose forms this interpreter has evaluated.
    packages: BTreeSet<String>,
}

const CODE_LABEL: &str = "<eval>";

impl Session {
    #[must_use]
    pub fn new(config: Config) -> Self {
        let mut host = Host {
            live: config.live,
            ..Host::default()
        };
        let interp = build(&config.frame, &config.interrupt, &mut host);
        let builtins = pipeline::builtin_names(&interp);
        Self {
            interp,
            host,
            frame: config.frame,
            budget: config.budget,
            loader: config.loader,
            interrupt: config.interrupt,
            builtins,
            contexts: BTreeMap::new(),
            packages: BTreeSet::new(),
        }
    }

    /// The flag that halts the running evaluation.
    #[must_use]
    pub fn interrupt_flag(&self) -> Arc<AtomicBool> {
        Arc::clone(&self.interrupt)
    }

    #[must_use]
    pub fn frame(&self) -> &Waku {
        &self.frame
    }

    /// Forget every context and definition: a fresh interpreter, same frame.
    pub fn reset(&mut self) {
        let live = self.host.live.take();
        self.host = Host {
            live,
            ..Host::default()
        };
        self.interp = build(&self.frame, &self.interrupt, &mut self.host);
        self.contexts.clear();
        self.packages.clear();
    }

    /// Load `file` (its text from `text` when given, else from disk) as a
    /// fresh context, replacing any earlier load of it. Answers the names the
    /// file defines.
    pub fn load(&mut self, file: &Path, text: Option<&str>, how: Load) -> Outcome<Vec<String>> {
        let result = self.load_inner(file, text, how);
        self.finish(result)
    }

    /// Evaluate `code` in `file`'s context (loading its definitions first if
    /// it is not loaded), or the session's own when `file` is `None`. Answers
    /// the value of the last form as canonical blue text.
    pub fn eval(&mut self, code: &str, file: Option<&Path>, budget: Option<usize>) -> Outcome<String> {
        let result = self
            .context_key(file)
            .and_then(|key| self.run_code(&key, code, budget, Action::Evaluate))
            .map(|v| render(&v));
        self.finish(result)
    }

    /// Expand the macro call `code` one step or fully, in `file`'s context or
    /// the session's.
    pub fn expand(&mut self, code: &str, file: Option<&Path>, step: Step) -> Outcome<String> {
        let result = self
            .context_key(file)
            .and_then(|key| self.run_code(&key, code, None, Action::Expand(step)))
            .and_then(|v| match crate::literal::value_to_sexp(&v) {
                Some(s) => Ok(crate::literal::format(&unkey(s))),
                None => Err(Stop::Error(Failure::new(
                    "runtime",
                    "the expansion is not a form",
                ))),
            });
        self.finish(result)
    }

    /// Every name `prefix` completes to in `file`'s context (or the
    /// session's), each with its namespace and doc line.
    #[must_use]
    pub fn complete(&self, prefix: &str, file: Option<&Path>) -> Vec<Item> {
        let mut seen = BTreeSet::new();
        let mut out = Vec::new();
        let (table, ctx) = self.table(file);
        for (ns, b) in table.all() {
            let name = spelled(ns, &b.name);
            let spellable = name
                .chars()
                .next()
                .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                && !name.contains('-')
                && !name.contains('%');
            if !spellable || !name.starts_with(prefix) || !seen.insert(name.clone()) {
                continue;
            }
            out.push(self.describe(ns, b, name, ctx));
        }
        out
    }

    /// What `name` is in `file`'s context (or the session's): the first
    /// binding the resolution order reaches. `pkg::name` names a bidama's
    /// definition and `blue::name` the builtin.
    #[must_use]
    pub fn doc(&self, name: &str, file: Option<&Path>) -> Option<Item> {
        let (table, ctx) = self.table(file);
        let (want_ns, bare) = match name.split_once("::") {
            Some((blue_lang_syntax::BUILTIN_QUALIFIER, bare)) => (Some(Namespace::Builtin), bare),
            Some((pkg, bare)) => (Some(Namespace::Bidama(pkg.to_string())), bare),
            None => (None, name),
        };
        table
            .all()
            .find(|(ns, b)| {
                b.name == bare
                    && want_ns.as_ref().is_none_or(|w| w == *ns)
                    && !matches!(ns, Namespace::Harness)
            })
            .map(|(ns, b)| self.describe(ns, b, spelled(ns, &b.name), ctx))
    }

    fn table(&self, file: Option<&Path>) -> (&NameTable, Option<&Context>) {
        let key = file.map(canonical);
        let ctx = self.contexts.get(&key);
        match ctx.and_then(|c| c.names.as_ref()) {
            Some(t) => (t, ctx),
            None => (&self.builtins, ctx),
        }
    }

    fn describe(
        &self,
        ns: &Namespace,
        b: &blue_lang_check::Binding,
        name: String,
        ctx: Option<&Context>,
    ) -> Item {
        let (signature, doc) = match (b.top_level, ctx.and_then(|c| c.program.as_ref())) {
            (Some(i), Some(program)) => definition_doc(program, i),
            _ => match crate::docs::doc_of(&b.name) {
                Some(d) => (Some(d.signature.to_string()), Some(d.doc.to_string())),
                None => (None, None),
            },
        };
        Item {
            name,
            namespace: ns.to_string(),
            signature,
            doc,
        }
    }

    fn finish<T>(&mut self, result: Result<T, Stop>) -> Outcome<T> {
        Outcome {
            result,
            out: std::mem::take(&mut self.host.out),
        }
    }

    fn context_key(&mut self, file: Option<&Path>) -> Result<Option<PathBuf>, Stop> {
        let key = file.map(canonical);
        if let Some(path) = &key {
            if !self.contexts.contains_key(&key) {
                self.load_inner(path, None, Load::Definitions)?;
            }
        }
        self.contexts.entry(key.clone()).or_default();
        Ok(key)
    }

    fn load_inner(&mut self, file: &Path, text: Option<&str>, how: Load) -> Result<Vec<String>, Stop> {
        let path = canonical(file);
        let text = match text {
            Some(t) => t.to_string(),
            None => std::fs::read_to_string(&path).map_err(|e| {
                Stop::Error(Failure::new("not-found", format!("{}: {e}", file.display())))
            })?,
        };
        let mut forms = split(&text).map_err(|e| {
            Stop::Error(Failure::new("parse", format!("{}:{e}", file.display())))
        })?;
        for (order, f) in forms.iter_mut().enumerate() {
            if how == Load::Whole || f.persists() {
                f.fresh = Some((order, None));
            }
        }
        let defined: Vec<String> = forms.iter().flat_map(|f| f.defines.clone()).collect();
        let key = Some(path.clone());
        let mut ctx = Context {
            path: Some(path),
            ..Context::default()
        };
        let run = self.execute(&mut ctx, forms, "", None, Action::Load);
        // A file whose forms ran is loaded even when a later form stopped:
        // its definitions are in the interpreter, and the context holds them.
        self.contexts.insert(key, ctx);
        run.map(|_| defined)
    }

    fn run_code(
        &mut self,
        key: &Option<PathBuf>,
        code: &str,
        budget: Option<usize>,
        action: Action,
    ) -> Result<Value, Stop> {
        let new = split(code).map_err(|e| {
            Stop::Error(Failure::new("parse", format!("{CODE_LABEL}:{e}")))
        })?;
        let mut ctx = self.contexts.remove(key).unwrap_or_default();
        let mut forms = ctx.forms.clone();
        let mut code_at = 0;
        for (order, mut form) in new.into_iter().enumerate() {
            form.fresh = Some((order, Some(code_at + form.at)));
            code_at += form.text.len();
            form.text.insert(0, '\n');
            form.at += 1;
            if form.defines.is_empty() {
                forms.push(form);
            } else {
                splice(&mut forms, form);
            }
        }
        let result = self.execute(&mut ctx, forms, code, budget, action);
        self.contexts.insert(key.clone(), ctx);
        result
    }

    /// Stage `forms` through every stage `blue run` runs, then evaluate (or
    /// expand) the fresh ones. On return `ctx` holds what the request leaves
    /// behind: a load's forms, or the context's own forms with every
    /// persistent fresh form that ran spliced in.
    fn execute(
        &mut self,
        ctx: &mut Context,
        forms: Vec<Form>,
        code: &str,
        budget: Option<usize>,
        action: Action,
    ) -> Result<Value, Stop> {
        let mut text = String::new();
        // Composed-text start of each fresh form, to its place in the run
        // order and its offset in `code`.
        let mut fresh_at: BTreeMap<usize, (usize, Option<usize>, usize)> = BTreeMap::new();
        for (i, f) in forms.iter().enumerate() {
            if let Some((order, code_off)) = f.fresh {
                fresh_at.insert(text.len() + f.at, (order, code_off, i));
            }
            text.push_str(&f.text);
        }

        let entry = Entry {
            path: ctx.path.as_deref(),
            text: &text,
        };
        let mut program = pipeline::parse_and_resolve(entry, self.loader.as_ref(), None)
            .map_err(|e| Stop::Error(run_failure(e)))?;
        program.retain(|f| !crate::uses::is_test_form(f));
        let (outcome, names) = pipeline::check_stage(&program, &self.builtins, false);
        let place = |top_level: usize, span: Span, message: &str| -> String {
            let in_code = (program.owner_of(top_level) == Some(ResolvedProgram::ENTRY)
                && !span.is_synthetic())
            .then(|| in_code(&fresh_at, &forms, span))
            .flatten();
            match in_code {
                Some(at) => {
                    let (line, col) = Span::line_col(code, at.min(code.len()));
                    format!("{CODE_LABEL}:{line}:{col}: {message}")
                }
                None => program.locate(top_level, span, message).to_string(),
            }
        };
        if !outcome.ok() {
            let code = outcome
                .errors()
                .next()
                .map_or_else(|| "check".to_string(), |d| d.code.to_string());
            let message = outcome
                .errors()
                .map(|d| {
                    let mut line = place(d.top_level, d.span, &d.to_string());
                    if let Some(help) = &d.help {
                        line.push_str("\n  help: ");
                        line.push_str(help);
                    }
                    line
                })
                .collect::<Vec<_>>()
                .join("\n");
            return Err(Stop::Error(Failure::new(code, message)));
        }
        let erased = crate::erase::erase_types(&pipeline::lower(&program, &names));

        // What runs: every form of a bidama this interpreter has not seen, in
        // program order, then the fresh forms in the order they were asked for.
        let mut imported = Vec::new();
        let mut asked: Vec<(usize, usize)> = Vec::new();
        let mut new_packages = BTreeSet::new();
        for (i, form) in program.forms().iter().enumerate() {
            let owner = program.owner_of(i);
            if owner == Some(ResolvedProgram::ENTRY) {
                if let Some((order, _, _)) = fresh_at.get(&form.span.start) {
                    asked.push((*order, i));
                }
                continue;
            }
            let package = owner
                .and_then(|o| program.file(o))
                .and_then(|f| f.package.clone());
            if let Some(p) = package.filter(|p| !self.packages.contains(p)) {
                new_packages.insert(p);
                imported.push(i);
            }
        }
        asked.sort_unstable();

        let limit = budget.or(self.budget).or(crate::execution_bounds().max_steps);
        let _ = self.interp.set_budget(tatara_lisp_eval::vm::Budget {
            fuel: limit,
            max_depth: Some(crate::execution_bounds().max_call_depth),
            quantum: None,
        });
        self.host.reached = None;

        let mut value = Value::Nil;
        let mut ran: BTreeSet<usize> = BTreeSet::new();
        let mut failed = None;
        for &i in &imported {
            if let Err(e) = self.interp.eval_top_form(&erased[i], &mut self.host) {
                failed = Some((i, e));
                break;
            }
        }
        if failed.is_none() {
            self.packages.extend(new_packages);
            for &(order, i) in &asked {
                let step = match action {
                    Action::Expand(step) => {
                        expand_form(&mut self.interp, &mut self.host, &erased[i], step)
                    }
                    Action::Evaluate | Action::Load => {
                        self.interp.eval_top_form(&erased[i], &mut self.host)
                    }
                };
                match step {
                    Ok(v) => {
                        value = v;
                        ran.insert(order);
                    }
                    Err(e) => {
                        failed = Some((i, e));
                        break;
                    }
                }
            }
        }
        let stop = failed.map(|(i, e)| self.classify(&e, &erased, |span, msg| place(i, span, msg)));

        match action {
            Action::Load => ctx.forms = forms.into_iter().map(Form::settled).collect(),
            Action::Evaluate => {
                for f in forms {
                    if f.persists() && f.fresh.is_some_and(|(order, _)| ran.contains(&order)) {
                        splice(&mut ctx.forms, f.settled());
                    }
                }
            }
            Action::Expand(_) => {}
        }
        if action != Action::Expand(Step::One) && action != Action::Expand(Step::All) {
            ctx.program = Some(program);
            ctx.names = Some(names);
        }
        if let Some((reach, name)) = self.host.reached.take() {
            return Err(Stop::Volatile {
                reach,
                name: name.to_string(),
            });
        }
        match stop {
            Some(s) => Err(s),
            None => Ok(value),
        }
    }

    fn classify(
        &self,
        e: &EvalError,
        erased: &[Spanned],
        place: impl Fn(Span, &str) -> String,
    ) -> Stop {
        match e {
            EvalError::Halted => {
                self.interrupt.store(false, Ordering::SeqCst);
                Stop::Interrupted
            }
            EvalError::BudgetExceeded {
                dimension: tatara_lisp_eval::error::BudgetDimension::Fuel,
                limit,
                ..
            } => Stop::Exhausted { limit: *limit },
            other => {
                let at = other.span().unwrap_or_else(Span::synthetic);
                let message =
                    pipeline::display_keys(&crate::messages::describe(other, erased));
                Stop::Error(Failure::new("runtime", place(at, &message)))
            }
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Action {
    Load,
    Evaluate,
    Expand(Step),
}

/// The offset in the request's code of `span`, when it lies inside a fresh
/// form that came from the code.
fn in_code(
    fresh_at: &BTreeMap<usize, (usize, Option<usize>, usize)>,
    forms: &[Form],
    span: Span,
) -> Option<usize> {
    let (start, (_, code_off, i)) = fresh_at.range(..=span.start).next_back()?;
    let len = forms[*i].text.len() - forms[*i].at;
    (span.start < start + len).then(|| (*code_off).map(|c| c + (span.start - start)))?
}

fn expand_form(
    interp: &mut Interpreter<Host>,
    host: &mut Host,
    form: &Spanned,
    step: Step,
) -> tatara_lisp_eval::Result<Value> {
    let head = match step {
        Step::One => "macroexpand-1",
        Step::All => "macroexpand",
    };
    let call = Sexp::List(vec![
        Sexp::Atom(Atom::Symbol(head.to_string())),
        Sexp::List(vec![Sexp::Atom(Atom::Symbol("quote".to_string())), form.to_sexp()]),
    ]);
    interp.eval_spanned(&Spanned::from_sexp_synthetic(&call), host)
}

fn run_failure(e: RunError) -> Failure {
    let code = match &e {
        RunError::Parse(_) | RunError::Lower(_) => "parse",
        RunError::Import(_) => "import",
        RunError::Types(_) => "check",
        RunError::Eval(_) => "runtime",
    };
    Failure::new(code, e.to_string())
}

/// The interpreter a session runs: the whole blue runtime, output captured,
/// and every host name the frame does not grant bound to a refusal.
fn build(frame: &Waku, interrupt: &Arc<AtomicBool>, host: &mut Host) -> Interpreter<Host> {
    let mut interp = crate::interpreter(host);
    capture_output(&mut interp);
    for cap in Capability::host_effects() {
        if frame.reach.grants(cap) {
            continue;
        }
        for name in cap.names() {
            if interp.lookup_global(name).is_none() {
                continue;
            }
            interp.register_fn(name, Arity::Any, move |_: &[Value], h: &mut Host, span| {
                h.reached.get_or_insert((cap, name));
                Err(EvalError::native_fn(
                    name,
                    format!(
                        "refused: `{name}` reaches the host ({}), which this session's frame does not grant",
                        cap.label()
                    ),
                    span,
                ))
            });
        }
    }
    interp.set_interrupt(Arc::clone(interrupt));
    interp
}

/// Rebind every primitive that writes to stdout so the session receives what
/// it writes. Each keeps its formatting.
fn capture_output(interp: &mut Interpreter<Host>) {
    interp.register_fn("write_stdout", Arity::Exact(1), |a: &[Value], h: &mut Host, s| {
        match &a[0] {
            Value::Str(t) => {
                h.write(t);
                Ok(Value::Nil)
            }
            other => Err(EvalError::type_mismatch("string", other.type_name(), s)),
        }
    });
    interp.register_fn("display", Arity::Exact(1), |a: &[Value], h: &mut Host, _| {
        h.write(&a[0].to_string());
        Ok(Value::Nil)
    });
    interp.register_fn("print", Arity::Exact(1), |a: &[Value], h: &mut Host, _| {
        h.write(&format!("{}\n", a[0]));
        Ok(Value::Nil)
    });
    interp.register_fn("newline", Arity::Exact(0), |_: &[Value], h: &mut Host, _| {
        h.write("\n");
        Ok(Value::Nil)
    });
    interp.register_fn("println", Arity::Any, |a: &[Value], h: &mut Host, _| {
        let line = a.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ");
        h.write(&format!("{line}\n"));
        Ok(Value::Nil)
    });
}

/// A source's top-level forms, each with the text before it.
fn split(text: &str) -> Result<Vec<Form>, blue_lang_syntax::ParseError> {
    let tree = blue_lang_syntax::parse_program_tree(text)?;
    let mut out = Vec::with_capacity(tree.len());
    let mut prev = 0;
    let last = tree.len().saturating_sub(1);
    for (i, form) in tree.iter().enumerate() {
        let end = if i == last { text.len() } else { form.span.end };
        out.push(Form {
            text: text[prev..end].to_string(),
            at: form.span.start - prev,
            defines: blue_lang_syntax::scope::definitions_of(form)
                .into_iter()
                .map(|(n, _, _)| n)
                .collect(),
            is_use: blue_lang_syntax::scope::use_target(form).is_some()
                || blue_lang_syntax::scope::legacy_target(form).is_some(),
            fresh: None,
        });
        prev = end;
    }
    Ok(out)
}

/// Whether `code` fails to parse only because it stops early: a block with
/// no `end`, an open bracket or string. A REPL reads another line for it.
#[must_use]
pub fn incomplete(code: &str) -> bool {
    match blue_lang_syntax::parse_program_tree(code) {
        Ok(_) => false,
        Err(e) => {
            e.span.end >= code.trim_end().len() || e.message.starts_with("unterminated")
        }
    }
}

/// A value as canonical blue text; a value no literal produces is described.
#[must_use]
pub fn render(v: &Value) -> String {
    match crate::literal::value_literal(v) {
        Some(Sexp::Atom(Atom::Symbol(s))) => unkey_name(&s),
        Some(s) => crate::literal::format(&unkey(s)),
        None => match v {
            Value::Closure(_) => "<function>".to_string(),
            Value::NativeFn(f) => format!("<builtin {}>", f.name),
            other => other.to_string(),
        },
    }
}

/// A tree with every runtime key written as the author would: `%root/f` is
/// `f`; `retsu/first` stays, and the formatter prints it `retsu::first`.
fn unkey(s: Sexp) -> Sexp {
    match s {
        Sexp::Atom(Atom::Symbol(n)) => Sexp::Atom(Atom::Symbol(unkey_name(&n))),
        Sexp::List(items) => Sexp::List(items.into_iter().map(unkey).collect()),
        other => other,
    }
}

fn unkey_name(n: &str) -> String {
    let root = format!(
        "{}{}",
        blue_lang_check::names::ROOT_QUALIFIER,
        blue_lang_syntax::QUALIFIER
    );
    n.strip_prefix(&root).unwrap_or(n).to_string()
}

/// A name as a program spells it from outside its namespace.
fn spelled(ns: &Namespace, name: &str) -> String {
    match ns {
        Namespace::Bidama(p) => format!("{p}::{name}"),
        _ => name.to_string(),
    }
}

/// A definition's signature (the formatter's first line of it) and its doc:
/// the comment lines directly above it.
fn definition_doc(program: &ResolvedProgram, i: usize) -> (Option<String>, Option<String>) {
    let Some(form) = program.forms().get(i) else {
        return (None, None);
    };
    let rendered = crate::literal::format(&unkey(form.to_sexp()));
    let signature = rendered.lines().next().map(str::to_string);
    let text = program
        .owner_of(i)
        .and_then(|o| program.file(o))
        .map(|f| f.text.as_str())
        .unwrap_or_default();
    let before = &text[..form.span.start.min(text.len())];
    let mut lines: Vec<&str> = before
        .lines()
        .rev()
        .skip_while(|l| l.trim().is_empty() && !before.ends_with('\n'))
        .take_while(|l| l.trim_start().starts_with('#'))
        .collect();
    lines.reverse();
    let doc = lines
        .iter()
        .map(|l| l.trim_start().trim_start_matches('#').trim())
        .filter(|l| !l.starts_with("waive "))
        .collect::<Vec<_>>()
        .join(" ");
    (signature, (!doc.is_empty()).then_some(doc))
}

fn canonical(p: &Path) -> PathBuf {
    std::fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf())
}

#[cfg(test)]
mod tests;
