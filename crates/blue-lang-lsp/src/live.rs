//! Live evaluation: an open document's top-level expressions and its `@doc`
//! examples, evaluated speculatively while the author types.
//!
//! **Transport-free**, like [`crate::analysis`]: text in, [`Finding`]s out,
//! then [`diagnostics`] and [`hints`] as plain Rust types for the shim to
//! encode.
//!
//! Every evaluation goes through one pure [`Session`]
//! (`blue_lang_runtime::session`): its frame grants no host capability, so a
//! name that reaches the host stops the evaluation as [`Stop::Volatile`]
//! instead of touching it. Each request is bounded by [`Limits::steps`], the
//! whole document by [`Limits::wall`], and a newer revision ends an older run
//! through [`Cancel::supersede`]. A panic in a native function ends the item
//! it happened in, never the caller.
//!
//! Examples run one line at a time in the document's context, after its
//! expressions, so a binding an example makes is seen by the examples after
//! it, never by an expression.

use std::collections::{BTreeMap, BTreeSet};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::time::Duration;

use blue_lang_runtime::session::{pure_frame, Config, Load, Session, Stop};
use blue_lang_runtime::uses::{Frontend, Loader, ResolvedProgram};
use blue_lang_syntax::{Span, Spanned};

use crate::analysis::{Diagnostic, LineIndex, Position, Severity};

/// What one document's evaluation may spend.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Limits {
    /// Steps each expression or example line may take.
    pub steps: usize,
    /// Wall-clock time the whole document may take.
    pub wall: Duration,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            steps: 200_000,
            wall: Duration::from_millis(250),
        }
    }
}

/// The handle that ends a run from another thread.
#[derive(Clone, Debug, Default)]
pub struct Cancel {
    interrupt: Arc<AtomicBool>,
    superseded: Arc<AtomicBool>,
}

impl Cancel {
    /// A newer revision replaces this run: it stops and reports nothing.
    pub fn supersede(&self) {
        self.superseded.store(true, Ordering::SeqCst);
        self.interrupt.store(true, Ordering::SeqCst);
    }

    fn superseded(&self) -> bool {
        self.superseded.load(Ordering::SeqCst)
    }
}

/// What was evaluated.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Subject {
    /// A top-level expression statement.
    Expression,
    /// A top-level binding whose value stopped the document's definitions.
    Binding,
    /// One line of a `@doc` or `@moduledoc` example.
    Doctest,
}

/// How one evaluation ended.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Verdict {
    Value(String),
    Matched,
    Mismatch { got: String, expected: String },
    Volatile { name: String, reach: &'static str },
    Exhausted { limit: usize },
    Failed(String),
    Cut { after: Duration },
    Panicked(String),
}

/// One evaluated span of the document.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Finding {
    pub span: Span,
    pub subject: Subject,
    pub verdict: Verdict,
}

/// An inlay hint: a label shown at a position.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hint {
    pub position: Position,
    pub label: String,
}

/// A loader answering from what one analysis already loaded, so the
/// evaluation sees exactly the bidamas the document was checked against and
/// can move to another thread.
#[derive(Clone, Debug, Default)]
pub struct Snapshot {
    entry: Option<String>,
    packages: BTreeMap<String, Vec<(String, String)>>,
    needs: BTreeMap<String, BTreeSet<String>>,
    versions: BTreeMap<String, String>,
    frontend: Option<Frontend>,
}

impl Snapshot {
    /// Every bidama `program` loaded, with the facts its loader reported.
    #[must_use]
    pub fn of(program: &ResolvedProgram) -> Self {
        let mut packages: BTreeMap<String, Vec<(String, String)>> = BTreeMap::new();
        for file in program.files() {
            if file.id == ResolvedProgram::ENTRY {
                continue;
            }
            let Some(name) = &file.package else {
                continue;
            };
            let label = file
                .path
                .as_ref()
                .map(|p| p.display().to_string())
                .unwrap_or_default();
            packages
                .entry(name.clone())
                .or_default()
                .push((label, file.text.clone()));
        }
        Self {
            entry: program
                .file(ResolvedProgram::ENTRY)
                .and_then(|f| f.package.clone()),
            packages,
            needs: program.needs().clone(),
            versions: program.versions().clone(),
            frontend: program.frontend().cloned(),
        }
    }
}

impl Loader for Snapshot {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.packages.get(name).cloned().ok_or_else(|| {
            format!("cannot load bidama \"{name}\": the document's analysis did not load it")
        })
    }

    fn entry_package(&self, _path: &Path) -> Option<String> {
        self.entry.clone()
    }

    fn needs(&self, package: &str, _entry_dir: Option<&Path>) -> Option<BTreeSet<String>> {
        self.needs.get(package).cloned()
    }

    fn version(&self, package: &str, _entry_dir: Option<&Path>) -> Option<String> {
        self.versions.get(package).cloned()
    }

    fn frontend(&self, _entry: &Path) -> Option<Frontend> {
        self.frontend.clone()
    }
}

/// Evaluate `text`, the document at `path`, in a pure session over `loader`.
/// `None` when `cancel` superseded the run before it finished.
#[must_use]
pub fn evaluate(
    text: &str,
    path: &Path,
    loader: Box<dyn Loader + Send>,
    limits: Limits,
    cancel: &Cancel,
) -> Option<Vec<Finding>> {
    let Ok(forms) = blue_lang_syntax::parse_program_tree(text) else {
        return Some(Vec::new());
    };
    let expressions: Vec<Span> = forms
        .iter()
        .filter(|f| is_expression(f))
        .map(|f| f.span)
        .collect();
    let examples = examples(text);
    if expressions.is_empty() && examples.is_empty() {
        return Some(Vec::new());
    }
    let cut = Arc::new(AtomicBool::new(false));
    let (finished, watchdog) = watch(limits.wall, &cancel.interrupt, &cut);
    let found = catch_unwind(AssertUnwindSafe(|| {
        let session = Session::new(Config {
            frame: pure_frame(),
            budget: Some(limits.steps),
            loader,
            interrupt: Arc::clone(&cancel.interrupt),
            live: None,
        });
        let mut run = Run {
            session,
            text,
            path: path.to_path_buf(),
            limits,
            cancel,
            cut: &cut,
            halted: false,
            halt: None,
            found: Vec::new(),
        };
        run.all(&forms, &expressions, &examples).map(|()| run.found)
    }))
    .unwrap_or_else(|_| Some(Vec::new()));
    drop(finished);
    let _ = watchdog.join();
    found
}

fn watch(
    wall: Duration,
    interrupt: &Arc<AtomicBool>,
    cut: &Arc<AtomicBool>,
) -> (mpsc::Sender<()>, std::thread::JoinHandle<()>) {
    let (finished, done) = mpsc::channel::<()>();
    let interrupt = Arc::clone(interrupt);
    let cut = Arc::clone(cut);
    let watchdog = std::thread::spawn(move || {
        if let Err(mpsc::RecvTimeoutError::Timeout) = done.recv_timeout(wall) {
            cut.store(true, Ordering::SeqCst);
            interrupt.store(true, Ordering::SeqCst);
        }
    });
    (finished, watchdog)
}

fn is_expression(form: &Spanned) -> bool {
    blue_lang_syntax::scope::definitions_of(form).is_empty()
        && blue_lang_syntax::scope::use_target(form).is_none()
        && blue_lang_syntax::scope::legacy_target(form).is_none()
        && !blue_lang_runtime::uses::is_test_form(form)
}

fn is_binding(form: &Spanned) -> bool {
    match form.as_list() {
        Some([head, name, ..]) => {
            matches!(head.as_symbol(), Some("define" | "define-typed"))
                && name.as_symbol().is_some()
        }
        _ => false,
    }
}

enum Line {
    Run(Span),
    Check {
        expr: Span,
        value: Span,
        whole: Span,
    },
}

fn examples(text: &str) -> Vec<Vec<Line>> {
    let Ok(tests) = blue_lang_syntax::doc::doctests(text) else {
        return Vec::new();
    };
    tests
        .iter()
        .filter_map(|t| t.as_list().and_then(|items| items.get(2)))
        .map(|body| {
            let statements: &[Spanned] = match body.as_list() {
                Some([head, rest @ ..]) if head.as_symbol() == Some("begin") => rest,
                _ => std::slice::from_ref(body),
            };
            statements.iter().map(line_of).collect()
        })
        .collect()
}

fn line_of(statement: &Spanned) -> Line {
    if let Some([head, _, compared]) = statement.as_list() {
        if head.as_symbol() == Some(blue_lang_syntax::LOWERED_ASSERT) {
            if let Some([_, expr, value]) = compared.as_list() {
                return Line::Check {
                    expr: expr.span,
                    value: value.span,
                    whole: statement.span,
                };
            }
        }
    }
    Line::Run(statement.span)
}

enum Answer {
    Value(String),
    Stopped(Verdict),
    Halted,
}

struct Run<'a> {
    session: Session,
    text: &'a str,
    path: PathBuf,
    limits: Limits,
    cancel: &'a Cancel,
    cut: &'a AtomicBool,
    halted: bool,
    halt: Option<Verdict>,
    found: Vec<Finding>,
}

impl<'a> Run<'a> {
    fn all(
        &mut self,
        forms: &[Spanned],
        expressions: &[Span],
        examples: &[Vec<Line>],
    ) -> Option<()> {
        if !self.load(forms)? {
            return Some(());
        }
        for &span in expressions {
            match self.eval(self.source(span))? {
                Answer::Value(v) => self.push(span, Subject::Expression, Verdict::Value(v)),
                Answer::Halted => {
                    self.settle(span, Subject::Expression, Answer::Halted);
                    return Some(());
                }
                stopped => self.settle(span, Subject::Expression, stopped),
            }
        }
        for example in examples {
            for line in example {
                if self.halted {
                    return Some(());
                }
                if !self.line(line)? {
                    break;
                }
            }
        }
        Some(())
    }

    fn load(&mut self, forms: &[Spanned]) -> Option<bool> {
        let first = forms.first().map_or(Span::new(0, 0), |f| f.span);
        let loaded = catch_unwind(AssertUnwindSafe(|| {
            self.session
                .load(&self.path, Some(self.text), Load::Definitions)
                .result
        }));
        let stop = match loaded {
            Ok(Ok(_)) => return Some(true),
            Ok(Err(stop)) => stop,
            Err(panic) => {
                let halted = self.halt(Verdict::Panicked(panic_text(&*panic)));
                self.settle(first, Subject::Binding, halted);
                return Some(false);
            }
        };
        match stop {
            Stop::Error(f) if f.code != "runtime" => return Some(false),
            Stop::Interrupted if self.cancel.superseded() => return None,
            Stop::Interrupted => {
                let halted = self.halt(Verdict::Cut {
                    after: self.limits.wall,
                });
                self.settle(first, Subject::Binding, halted);
                return Some(false);
            }
            _ => {}
        }
        for form in forms.iter().filter(|f| is_binding(f)) {
            match self.eval(self.source(form.span))? {
                Answer::Value(_) => {}
                other => {
                    self.settle(form.span, Subject::Binding, other);
                    return Some(false);
                }
            }
        }
        Some(false)
    }

    fn line(&mut self, line: &Line) -> Option<bool> {
        let (expr, value, whole) = match *line {
            Line::Run(span) => {
                return match self.eval(self.source(span))? {
                    Answer::Value(_) => Some(true),
                    other => {
                        self.settle(span, Subject::Doctest, other);
                        Some(false)
                    }
                };
            }
            Line::Check { expr, value, whole } => (expr, value, whole),
        };
        let got = match self.eval(self.source(expr))? {
            Answer::Value(v) => v,
            other => {
                self.settle(whole, Subject::Doctest, other);
                return Some(false);
            }
        };
        let expected = self.source(value).trim();
        let same = if got == expected {
            true
        } else {
            match self.eval(expected)? {
                Answer::Value(rendered) if rendered == got => true,
                Answer::Value(rendered) => match self.eval(&format!("{got} == {rendered}"))? {
                    Answer::Value(equal) => equal == "true",
                    Answer::Stopped(_) => false,
                    Answer::Halted => {
                        self.settle(whole, Subject::Doctest, Answer::Halted);
                        return Some(false);
                    }
                },
                Answer::Stopped(_) => false,
                Answer::Halted => {
                    self.settle(whole, Subject::Doctest, Answer::Halted);
                    return Some(false);
                }
            }
        };
        let verdict = if same {
            Verdict::Matched
        } else {
            Verdict::Mismatch {
                got,
                expected: expected.to_string(),
            }
        };
        self.push(whole, Subject::Doctest, verdict);
        Some(true)
    }

    fn eval(&mut self, code: &str) -> Option<Answer> {
        if self.cancel.superseded() {
            return None;
        }
        if self.halted {
            return Some(Answer::Halted);
        }
        if self.cut.load(Ordering::SeqCst) {
            return Some(self.halt(Verdict::Cut {
                after: self.limits.wall,
            }));
        }
        let path = self.path.clone();
        let steps = self.limits.steps;
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            self.session.eval(code, Some(&path), Some(steps)).result
        }));
        let stop = match outcome {
            Ok(Ok(value)) => return Some(Answer::Value(value)),
            Ok(Err(stop)) => stop,
            Err(panic) => return Some(self.halt(Verdict::Panicked(panic_text(&*panic)))),
        };
        Some(match stop {
            Stop::Interrupted if self.cancel.superseded() => return None,
            Stop::Interrupted => self.halt(Verdict::Cut {
                after: self.limits.wall,
            }),
            Stop::Volatile { reach, name } => Answer::Stopped(Verdict::Volatile {
                name,
                reach: reach.label(),
            }),
            Stop::Exhausted { limit } => Answer::Stopped(Verdict::Exhausted { limit }),
            Stop::Error(f) => Answer::Stopped(Verdict::Failed(unplaced(&f.message).to_string())),
        })
    }

    fn halt(&mut self, verdict: Verdict) -> Answer {
        self.halted = true;
        self.halt = Some(verdict);
        Answer::Halted
    }

    fn settle(&mut self, span: Span, subject: Subject, answer: Answer) {
        match answer {
            Answer::Value(_) => {}
            Answer::Stopped(verdict) => self.push(span, subject, verdict),
            Answer::Halted => {
                if let Some(verdict) = self.halt.take() {
                    self.push(span, subject, verdict);
                }
            }
        }
    }

    fn source(&self, span: Span) -> &'a str {
        self.text.get(span.start..span.end).unwrap_or_default()
    }

    fn push(&mut self, span: Span, subject: Subject, verdict: Verdict) {
        self.found.push(Finding {
            span,
            subject,
            verdict,
        });
    }
}

fn unplaced(message: &str) -> &str {
    let Some(rest) = message.strip_prefix("<eval>:") else {
        return message;
    };
    let rest = rest.trim_start_matches(|c: char| c.is_ascii_digit());
    let rest = rest.strip_prefix(':').unwrap_or(rest);
    let rest = rest.trim_start_matches(|c: char| c.is_ascii_digit());
    rest.strip_prefix(": ").unwrap_or(message)
}

fn panic_text(panic: &(dyn std::any::Any + Send)) -> String {
    panic
        .downcast_ref::<&str>()
        .map(|s| (*s).to_string())
        .or_else(|| panic.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "a panic with no message".to_string())
}

/// The findings an editor shows as diagnostics, never as errors: every one
/// is speculative.
#[must_use]
pub fn diagnostics(found: &[Finding], text: &str) -> Vec<Diagnostic> {
    let index = LineIndex::new(text);
    found
        .iter()
        .filter_map(|f| {
            let (severity, message) = match &f.verdict {
                Verdict::Value(_) | Verdict::Matched => return None,
                Verdict::Mismatch { got, expected } => (
                    Severity::Warning,
                    format!("doctest: got {got}, expected {expected}"),
                ),
                Verdict::Volatile { name, reach } => (
                    Severity::Information,
                    format!(
                        "capability boundary: `{name}` reaches the host ({reach}); live evaluation grants none"
                    ),
                ),
                Verdict::Exhausted { limit } => (
                    Severity::Hint,
                    format!("live evaluation stopped after {limit} steps"),
                ),
                Verdict::Failed(message) => (Severity::Information, message.clone()),
                Verdict::Cut { after } => (
                    Severity::Hint,
                    format!("live evaluation stopped after {} ms", after.as_millis()),
                ),
                Verdict::Panicked(message) => (
                    Severity::Information,
                    format!("live evaluation stopped: the evaluator panicked: {message}"),
                ),
            };
            Some(Diagnostic {
                range: index.range(f.span),
                severity,
                message,
                source: "live",
                code: None,
                help: None,
                fixes: Vec::new(),
            })
        })
        .collect()
}

/// Each top-level expression's value, `=> value` at the end of its line.
#[must_use]
pub fn hints(found: &[Finding], text: &str) -> Vec<Hint> {
    let index = LineIndex::new(text);
    found
        .iter()
        .filter_map(|f| match (&f.verdict, f.subject) {
            (Verdict::Value(v), Subject::Expression) => {
                let end = text
                    .get(f.span.end..)
                    .and_then(|rest| rest.find('\n'))
                    .map_or(text.len(), |n| f.span.end + n);
                Some(Hint {
                    position: index.position(end),
                    label: format!("=> {}", one_line(v)),
                })
            }
            _ => None,
        })
        .collect()
}

fn one_line(value: &str) -> String {
    const MAX: usize = 120;
    let joined = value.lines().map(str::trim).collect::<Vec<_>>().join(" ");
    match joined.char_indices().nth(MAX) {
        Some((at, _)) => format!("{}…", &joined[..at]),
        None => joined,
    }
}
