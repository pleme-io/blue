//! The evaluators, each turned into one [`Obs`] per row.
//!
//! Every evaluator blue has today, and every door a row's behaviour is
//! observable through:
//!
//! | evaluator | what it runs | what it can observe |
//! |---|---|---|
//! | `walker` | `pipeline::run_in_surface`, the `blue run` path, with a loader | value, failure |
//! | `vm` | the same check and erasure, then `eval_program_vm`: batched expansion and the bytecode VM | value, failure |
//! | `wasm` | `blue_lang_wasm::eval_tagged`, the module's ABI, with no loader | integer / non-integer / error |
//! | `cli` | the shipped `blue` binary as a subprocess | output, failure, `fmt`, `check`, `shift` |
//! | `static` | the shared front end in-process: check, format, blueshift | diagnostics, formatting, rung |
//!
//! An evaluator that cannot observe what a row expects reports [`Obs::Blind`]
//! with the reason. Blind is never a pass: the report counts it apart.

use std::path::{Path, PathBuf};
use std::process::Command;

use blue_lang_runtime::pipeline::{check_entry, render, run_in_surface, Checking, RunError};
use blue_lang_runtime::uses::{Entry, Loader};
use blue_lang_runtime::Inputs;
use tatara_lisp_eval::Value;

use crate::rows::{Ev, Expect, Row, Stage};

/// What one evaluator saw.
#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum Obs {
    /// The final value, as its blue literal.
    Value(String),
    /// The program stopped. `message` has its `file:line:col: ` prefix removed,
    /// because the path is the runner's temp file and differs per door.
    Failed { stage: Stage, message: String },
    /// The WASM ABI's reading.
    Abi(Abi),
    /// What the binary wrote to stdout, and whether it exited cleanly.
    Printed { stdout: String, ok: bool },
    /// Check-stage codes, in order.
    Codes(Vec<String>),
    /// The one formatting.
    Text(String),
    /// A blueshift reading: the rung (or `none`) and what holds it back.
    Shift { rung: String, holding: Vec<String> },
    /// The evaluator itself died: a Rust panic, an abort (a stack overflow is
    /// one, and nothing in-process can catch it), or a run past its time.
    /// Never a pass, whatever the row expects: a crash is not a refusal.
    Crashed(String),
    /// This evaluator cannot observe what the row expects.
    Blind(String),
}

/// The three things `blue_eval` can return.
#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Abi {
    Int(i64),
    NonInt,
    Error,
}

impl std::fmt::Display for Obs {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Obs::Value(v) => write!(f, "value {v}"),
            Obs::Failed { stage, message } => write!(f, "fails :{} {message:?}", stage.name()),
            Obs::Abi(Abi::Int(n)) => write!(f, "abi int {n}"),
            Obs::Abi(Abi::NonInt) => write!(f, "abi non-int"),
            Obs::Abi(Abi::Error) => write!(f, "abi error"),
            Obs::Printed { stdout, ok } => write!(f, "prints {stdout:?} (exit ok: {ok})"),
            Obs::Codes(c) => write!(f, "diagnoses {c:?}"),
            Obs::Text(t) => write!(f, "formats {t:?}"),
            Obs::Shift { rung, holding } => write!(f, "shifts {rung} holding {holding:?}"),
            Obs::Crashed(why) => write!(f, "CRASHED: {why}"),
            Obs::Blind(why) => write!(f, "blind: {why}"),
        }
    }
}

/// Everything the evaluators share: the loader roots, the binary, a renderer.
pub struct Env {
    pub roots: Vec<PathBuf>,
    pub cli: Option<PathBuf>,
    pub scratch: PathBuf,
    renderer: tatara_lisp_eval::Interpreter<()>,
    to_s: Value,
}

impl Env {
    pub fn new(roots: Vec<PathBuf>, cli: Option<PathBuf>, scratch: PathBuf) -> Self {
        std::fs::create_dir_all(&scratch).expect("scratch directory");
        let renderer = blue_lang_runtime::interpreter_hostless();
        let to_s = renderer
            .lookup_global("to_s")
            .expect("blue binds to_s: it is the literal renderer (okite D0006)");
        Self {
            roots,
            cli,
            scratch,
            renderer,
            to_s,
        }
    }

    fn loader(&self) -> blue_lang_pkg::load_path::LoadPath {
        blue_lang_pkg::load_path::LoadPath::new(self.roots.clone())
    }

    /// A value as its blue literal, through blue's own renderer.
    ///
    /// Not a second renderer: `to_s` of a one-element list is `[<literal>]`
    /// (okite D0006), so the literal of any value is that text minus its
    /// brackets. A top-level string would otherwise come back unquoted (D0005:
    /// `to_s("a")` is `a`), and `"1"` and `1` must not read the same.
    pub fn literal(&mut self, v: &Value) -> String {
        let wrapped = Value::list([v.clone()]);
        match self
            .renderer
            .apply_external_value(&self.to_s, vec![wrapped], &mut (), tatara_lisp::Span::synthetic())
        {
            Ok(Value::Str(s)) => s
                .strip_prefix('[')
                .and_then(|s| s.strip_suffix(']'))
                .map_or_else(|| s.to_string(), str::to_owned),
            Ok(other) => format!("<to_s returned {}>", other.type_name()),
            Err(e) => format!("<to_s failed: {e}>"),
        }
    }
}

/// The label every in-process door gives the row's source.
const ROW_FILE: &str = "row.b";

/// Remove a leading `path:line:col: ` (or `path: `) that names the row file.
fn unlocate(message: &str) -> String {
    let mut m = message.trim();
    // A check-stage report is `N error(s) in the check stage:\n<lines>`; each
    // line is located. The codes carry the meaning, so they are what is kept.
    for prefix in ["runtime error: ", "import error: ", "parse error: "] {
        if let Some(rest) = m.strip_prefix(prefix) {
            m = rest;
        }
    }
    // A bare `line:col: ` (the parser's own position) goes too.
    let digits = |t: &str| !t.is_empty() && t.chars().all(|c| c.is_ascii_digit());
    if let Some((lc, rest)) = m.split_once(": ") {
        if let Some((l, c)) = lc.split_once(':') {
            if digits(l) && digits(c) {
                m = rest;
            }
        }
    }
    let mut out = m.to_owned();
    if let Some(idx) = m.find(".b:").or_else(|| m.find(".b ")) {
        let head = &m[..idx];
        if !head.contains(' ') {
            let rest = &m[idx + 2..];
            // Skip `:line:col` if present, then the `: ` separator.
            let rest = rest.trim_start_matches(|c: char| c == ':' || c.is_ascii_digit());
            out = rest.trim_start().to_owned();
        }
    }
    out
}

/// Every `error[B0001]`-style code in a rendered check report, in order.
fn codes_in(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(i) = rest.find("error[B").or_else(|| rest.find("warning[B")) {
        let after = &rest[i..];
        let open = after.find('[').unwrap_or(0) + 1;
        let code: String = after[open..].chars().take_while(|c| *c != ']').collect();
        out.push(code);
        rest = &after[open..];
    }
    out
}

fn failed(e: &RunError) -> Obs {
    match e {
        RunError::Parse(m) => Obs::Failed {
            stage: Stage::Parse,
            message: unlocate(m),
        },
        RunError::Types(lines) => Obs::Failed {
            stage: Stage::Check,
            message: codes_in(&lines.join("\n")).join(" "),
        },
        RunError::Import(m) => Obs::Failed {
            stage: Stage::Import,
            message: import_message(m),
        },
        RunError::Eval(m) => Obs::Failed {
            stage: Stage::Eval,
            message: unlocate(m),
        },
        RunError::Lower(m) => Obs::Failed {
            stage: Stage::Eval,
            message: format!("lower: {m}"),
        },
    }
}

/// An import error names the roots it searched, which are absolute and differ
/// per machine; keep the part before them.
fn import_message(m: &str) -> String {
    let m = unlocate(m);
    match m.find(" (searched") {
        Some(i) => m[..i].to_owned(),
        None => m,
    }
}

/// Does this row's expectation run on value-and-failure evaluators?
fn runs(row: &Row) -> bool {
    matches!(row.expect, Expect::Value(_) | Expect::Fails(..))
}

pub fn walker(env: &mut Env, row: &Row) -> Obs {
    if !runs(row) {
        return Obs::Blind(format!("a {} row is observed by the front end", row.expect.kind()));
    }
    let loader = env.loader();
    let entry = Entry {
        path: Some(Path::new(ROW_FILE)),
        text: &row.src,
    };
    match run_in_surface(entry, Inputs::new(), &loader, None) {
        Ok(run) => Obs::Value(env.literal(&run.value)),
        Err(e) => failed(&e),
    }
}

pub fn vm(env: &mut Env, row: &Row) -> Obs {
    if !runs(row) {
        return Obs::Blind(format!("a {} row is observed by the front end", row.expect.kind()));
    }
    let loader = env.loader();
    let entry = Entry {
        path: Some(Path::new(ROW_FILE)),
        text: &row.src,
    };
    // The same check stage as every door, through its public door.
    let checked = match check_entry(entry, &loader, None, Checking::Program) {
        Ok(c) => c,
        Err(e) => return failed(&e),
    };
    if !checked.outcome.ok() {
        let rendered: Vec<String> = checked
            .outcome
            .errors()
            .map(|d| render(&checked.program, d))
            .collect();
        return failed(&RunError::Types(rendered));
    }
    // The pipeline's own tree: lowered (every `use` declaration inert, every
    // qualified name at its key) and erased.
    let erased = checked.erased();
    let mut interp = blue_lang_runtime::interpreter_hostless();
    blue_lang_runtime::install_input_primitives(&mut interp, Inputs::new());
    match interp.eval_program_vm(&erased, &mut ()) {
        Ok(v) => Obs::Value(env.literal(&v)),
        Err(e) => Obs::Failed {
            stage: Stage::Eval,
            message: blue_lang_runtime::messages::describe(&e, &erased),
        },
    }
}

pub fn wasm(_env: &mut Env, row: &Row) -> Obs {
    if !runs(row) {
        return Obs::Blind(format!("a {} row is observed by the front end", row.expect.kind()));
    }
    if row.host {
        // In a cargo test the runtime is built with `sys` on (the workspace
        // unifies it), so the host-linked ABI binds every host primitive that
        // the real wasm32 module does not. Reporting that as the wasm
        // surface's behaviour would be a claim about a build nobody ships.
        return Obs::Blind(
            "a host-effect row: this host-linked ABI binds the host primitives the wasm32 \
             module does not"
                .into(),
        );
    }
    let tagged = blue_lang_wasm::eval_tagged(&row.src);
    Obs::Abi(match blue_lang_wasm::decode(tagged) {
        blue_lang_wasm::Decoded::Int(n) => Abi::Int(n),
        blue_lang_wasm::Decoded::NonInt => Abi::NonInt,
        blue_lang_wasm::Decoded::Error => Abi::Error,
    })
}

/// What the ABI would report for an observation on another evaluator.
pub fn project(obs: &Obs) -> Option<Abi> {
    match obs {
        Obs::Value(v) => Some(match v.parse::<i64>() {
            Ok(n) if (blue_lang_wasm::MIN_TAGGED..=blue_lang_wasm::MAX_TAGGED).contains(&n) => {
                Abi::Int(n)
            }
            _ => Abi::NonInt,
        }),
        Obs::Failed { .. } => Some(Abi::Error),
        _ => None,
    }
}

pub fn statics(row: &Row, roots: &[PathBuf]) -> Obs {
    match &row.expect {
        Expect::Diagnoses(_) => Obs::Codes(static_codes(&row.src, roots)),
        Expect::Formats(_) => match blue_lang_fmt::format_source_lossless(&row.src) {
            Ok(t) => Obs::Text(t),
            Err(e) => Obs::Failed {
                stage: Stage::Parse,
                message: e.to_string(),
            },
        },
        Expect::Shifts(..) => {
            let s = blue_lang_lsp::shift_of(&row.src);
            Obs::Shift {
                rung: s.rung.map_or("none", |r| r.label()).to_owned(),
                holding: s.holding_back().iter().map(|f| f.subject.clone()).collect(),
            }
        }
        _ => Obs::Blind(format!("a {} row runs on the evaluators", row.expect.kind())),
    }
}

/// The codes `blue check` reports: a parse failure is `B0006`, otherwise
/// every diagnostic the check stage finds, test blocks included.
fn static_codes(src: &str, roots: &[PathBuf]) -> Vec<String> {
    if let Some(d) = blue_lang_runtime::pipeline::syntax_diagnostic(src) {
        return vec![d.code.as_str().to_owned()];
    }
    let loader = blue_lang_pkg::load_path::LoadPath::new(roots.to_vec());
    let entry = Entry {
        path: Some(Path::new(ROW_FILE)),
        text: src,
    };
    match check_entry(entry, &loader as &dyn Loader, None, Checking::WithTests) {
        Ok(c) => c
            .outcome
            .diagnostics
            .iter()
            .map(|d| d.code.as_str().to_owned())
            .collect(),
        Err(e) => vec![format!("<{e}>")],
    }
}

/// The measured blueshift rung of a program, or `none`.
pub fn rung_of(src: &str) -> String {
    blue_lang_lsp::shift_of(src)
        .rung
        .map_or("none", |r| r.label())
        .to_owned()
}

pub fn cli(env: &mut Env, row: &Row, n: usize) -> Obs {
    let Some(bin) = env.cli.clone() else {
        return Obs::Blind("no `blue` binary: set BLUE_BIN".into());
    };
    if matches!(row.expect, Expect::Value(_)) {
        // The final-value printer is not the literal renderer (G12), so a
        // value row read through it would measure the printer, not the row.
        // The printer has rows of its own (spec/rows/printing.b).
        return Obs::Blind("a value is not observable on stdout; see printing.b".into());
    }
    let file = env.scratch.join(format!("row-{n}.b"));
    if let Err(e) = std::fs::write(&file, &row.src) {
        return Obs::Blind(format!("cannot write {}: {e}", file.display()));
    }
    let blue_path = std::env::join_paths(&env.roots).expect("BLUE_PATH roots");
    let bounds = env.scratch.join("bounds.yaml");
    if let Err(e) = std::fs::write(&bounds, format!("max_steps: {ROW_STEPS}\n")) {
        return Obs::Blind(format!("cannot write {}: {e}", bounds.display()));
    }
    let mut cmd = Command::new(&bin);
    cmd.env("BLUE_PATH", &blue_path)
        .env("RUST_BACKTRACE", "0")
        .env("BLUE_CONFIG", &bounds)
        .env_remove("BLUE_TIER");
    match &row.expect {
        Expect::Fails(..) | Expect::Prints(_) => {
            cmd.arg("run").arg("--quiet").arg(&file);
        }
        Expect::Formats(_) => {
            cmd.arg("fmt").arg(&file);
        }
        Expect::Diagnoses(_) => {
            cmd.arg("check").arg("--format").arg("json").arg(&file);
        }
        Expect::Shifts(..) => {
            cmd.arg("shift").arg(&file);
        }
        Expect::Value(_) => unreachable!("returned above"),
    }
    let out = match output_within(&mut cmd) {
        Ok(o) => o,
        Err(crashed) => return crashed,
    };
    let raw_err = String::from_utf8_lossy(&out.stderr);
    if let Some(i) = raw_err.find("panicked at ") {
        // `thread 'main' panicked at FILE:L:C:\nMESSAGE` — the message is the
        // line after the location, the same text an in-process catch keeps.
        let msg = raw_err[i..].lines().nth(1).unwrap_or("").trim();
        return Obs::Crashed(format!("panic: {msg}"));
    }
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
    // `run` formats a non-canonical file in place and says so; that line is
    // the door's courtesy, not the program's output.
    let stderr: String = stderr
        .lines()
        .filter(|l| !l.starts_with("blue: formatted "))
        .collect::<Vec<_>>()
        .join("\n");
    match &row.expect {
        Expect::Prints(_) if out.status.success() => Obs::Printed { stdout, ok: true },
        Expect::Fails(..) | Expect::Prints(_) => {
            if out.status.success() {
                Obs::Printed { stdout, ok: true }
            } else {
                cli_failure(&stderr)
            }
        }
        Expect::Formats(_) => {
            if out.status.success() {
                Obs::Text(stdout)
            } else {
                Obs::Failed {
                    stage: Stage::Parse,
                    message: unlocate(stderr.trim_start_matches("blue: ")),
                }
            }
        }
        Expect::Diagnoses(_) => Obs::Codes(
            stdout
                .lines()
                .filter_map(|l| serde_json::from_str::<serde_json::Value>(l).ok())
                // A waived diagnostic is reported with its waiver; the check
                // stage's outcome does not count it.
                .filter(|v| v.get("waiver").is_none_or(serde_json::Value::is_null))
                .filter_map(|v| v.get("code").and_then(|c| c.as_str()).map(str::to_owned))
                .collect(),
        ),
        Expect::Shifts(..) => {
            let mut lines = stdout.lines();
            // `███░ checked  (…)`: the ramp, then the rung. A file with no
            // reading prints no ramp.
            let mut first = lines.next().unwrap_or("").split_whitespace();
            let rung = match (first.next(), first.next()) {
                (Some(ramp), Some(r)) if ramp.chars().all(|c| c == '█' || c == '░') => r,
                _ => "none",
            }
            .to_owned();
            let holding = stdout
                .lines()
                .filter(|l| l.trim_start().starts_with('·'))
                .filter_map(|l| l.split('`').nth(1).map(str::to_owned))
                .collect();
            Obs::Shift { rung, holding }
        }
        Expect::Value(_) => unreachable!("returned above"),
    }
}

/// How long any child process may run before it counts as a runaway. Long
/// enough for the VM to spend its whole default fuel budget in a debug build
/// (measured ~15 s), so a bounded runaway is reported as bounded.
/// The step budget every column runs rows under: the VM's own runaway guard.
///
/// blue's default is unbounded (a default bound would end long runs that
/// work), so a row whose program never ends — `fn.runaway_is_bounded` — only
/// ends because the suite declares a budget, as any host running code it did
/// not write should. In-process columns get it through
/// `blue_lang_runtime::set_execution_bounds` (see `main`), the `cli` column
/// through a `BLUE_CONFIG` file, so all four refuse at the same count.
pub const ROW_STEPS: usize = tatara_lisp_eval::vm::DEFAULT_FUEL;

pub const CHILD_LIMIT: std::time::Duration = std::time::Duration::from_secs(45);

/// Run `cmd` to completion within [`CHILD_LIMIT`], with its output captured.
///
/// The one subprocess shape both children use (the `blue` binary and the
/// runner's own isolated mode). A run past the limit is killed, and a death
/// by signal — a stack overflow aborts — is returned as the observation.
pub fn output_within(cmd: &mut Command) -> Result<std::process::Output, Obs> {
    use std::io::Read as _;
    use std::process::Stdio;
    let mut child = cmd
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| Obs::Blind(format!("cannot spawn {cmd:?}: {e}")))?;
    // Drain both pipes on threads, so a chatty child cannot block on a full
    // pipe while this side waits for it to exit.
    let mut out = child.stdout.take().expect("piped stdout");
    let mut err = child.stderr.take().expect("piped stderr");
    let t_out = std::thread::spawn(move || {
        let mut b = Vec::new();
        let _ = out.read_to_end(&mut b);
        b
    });
    let t_err = std::thread::spawn(move || {
        let mut b = Vec::new();
        let _ = err.read_to_end(&mut b);
        b
    });
    let start = std::time::Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s,
            Ok(None) if start.elapsed() > CHILD_LIMIT => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(Obs::Crashed(format!(
                    "runaway: still running after {CHILD_LIMIT:?}"
                )));
            }
            Ok(None) => std::thread::sleep(std::time::Duration::from_millis(10)),
            Err(e) => return Err(Obs::Crashed(format!("cannot wait on the child: {e}"))),
        }
    };
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt as _;
        if let Some(sig) = status.signal() {
            return Err(Obs::Crashed(format!("the process died on signal {sig}")));
        }
    }
    Ok(std::process::Output {
        status,
        stdout: t_out.join().unwrap_or_default(),
        stderr: t_err.join().unwrap_or_default(),
    })
}

/// Classify what `blue run` wrote to stderr on a failing exit.
fn cli_failure(stderr: &str) -> Obs {
    let text = stderr.trim();
    let body = text.strip_prefix("blue: ").unwrap_or(text);
    if body.contains("error(s) in the check stage") {
        return Obs::Failed {
            stage: Stage::Check,
            message: codes_in(body).join(" "),
        };
    }
    if let Some(rest) = body.strip_prefix("runtime error: ") {
        return Obs::Failed {
            stage: Stage::Eval,
            message: unlocate(rest),
        };
    }
    if let Some(rest) = body.strip_prefix("import error: ") {
        return Obs::Failed {
            stage: Stage::Import,
            message: import_message(rest),
        };
    }
    if let Some(i) = body.find("cannot be formatted, so it is not compiled: ") {
        let rest = &body[i + "cannot be formatted, so it is not compiled: ".len()..];
        let rest = rest.trim_start_matches(|c: char| c == ':' || c.is_ascii_digit());
        return Obs::Failed {
            stage: Stage::Parse,
            message: rest.trim_start().to_owned(),
        };
    }
    if let Some(rest) = body.strip_prefix("parse error: ") {
        return Obs::Failed {
            stage: Stage::Parse,
            message: unlocate(rest),
        };
    }
    Obs::Failed {
        stage: Stage::Eval,
        message: format!("<unclassified> {body}"),
    }
}

/// Whether `ev` observes rows of this kind at all (so a blind reading is the
/// design, not a gap).
pub fn observes(ev: Ev, row: &Row) -> bool {
    match (&row.expect, ev) {
        (Expect::Value(_), Ev::Walker | Ev::Vm | Ev::Wasm) => true,
        (Expect::Fails(..), Ev::Walker | Ev::Vm | Ev::Wasm | Ev::Cli) => true,
        (Expect::Prints(_), Ev::Cli) => true,
        (Expect::Diagnoses(_) | Expect::Formats(_) | Expect::Shifts(..), Ev::Static | Ev::Cli) => {
            true
        }
        _ => false,
    }
}
