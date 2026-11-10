//! `blue debug`: a Debug Adapter Protocol server over a recorded run
//! (`docs/HORIZON.md` §H4).
//!
//! The run is one recorded with `blue run --receipts DIR --record`; its
//! receipt is the `launch` request's `receipt`. The launch replays it once
//! from its tape, under a call observer that numbers every STEP: a call of a
//! definition the program makes, or its return. Every stop after that is a
//! fresh replay to the step asked for, which holds the stack there: the
//! active definitions, each with its parameters bound to the arguments it
//! was called with, and the innermost one's return value at a return step.
//! Stepping back is a replay to an earlier step, never an undo, so the values
//! seen there are the values the run had there. Each replay is held to the
//! launch's steps, so a replay that would number them differently is refused
//! by name rather than shown.
//!
//! Breakpoints name a definition (`setFunctionBreakpoints`) by its name or by
//! its `def_hash` (`b3:<hex>`), or a source line on which a definition starts
//! (`setBreakpoints`); each stops at that definition's calls. Each stack
//! frame carries its definition's hash as `defHash`, the name a breakpoint
//! keeps when the definition is renamed. The protocol is
//! framed by `blue_lang_lsp::frame`, the language server's own framing.
//!
//! A step is a call or a return, not a line: a local bound inside a body is
//! not shown until a definition it is passed to is called.

use std::collections::HashMap;
use std::io::Write;
use std::path::Path;
use std::process::ExitCode;
use std::sync::{Arc, Mutex, PoisonError};
use std::thread::ThreadId;

use blue_lang_lsp::frame::{read_message, write_message};
use blue_lang_runtime::def_hash::{hash_program, DefHashes};
use blue_lang_runtime::observe::{Call, CallObserver, Definitions, Exit};
use blue_lang_runtime::pipeline::Watched;
use serde_json::{json, Value as Json};
use tatara_lisp::Spanned;
use tatara_lisp_eval::Value;

use crate::config::BlueConfig;
use crate::record::{self, Loaded};
use crate::CliError;

const THREAD: i64 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Edge {
    Enter,
    Leave,
}

/// One step of a run: a definition entered or left, and how many program
/// definitions were active beneath it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Step {
    pub edge: Edge,
    pub def: usize,
    pub depth: usize,
}

#[derive(Clone)]
enum Left {
    Returned(Value),
    Raised(String),
}

#[derive(Clone)]
struct Active {
    def: usize,
    args: Vec<Value>,
    at: Option<usize>,
}

#[derive(Clone)]
struct Held {
    active: Active,
    left: Option<Left>,
}

#[derive(Default)]
struct Watching {
    steps: Vec<Step>,
    stacks: HashMap<ThreadId, Vec<Active>>,
    held: Option<Vec<Held>>,
}

struct Watcher {
    defs: Arc<Definitions>,
    target: Option<usize>,
    state: Mutex<Watching>,
}

impl Watcher {
    fn step(&self, w: &mut Watching, edge: Edge, def: usize, left: Option<Left>) {
        let stack = w
            .stacks
            .get(&std::thread::current().id())
            .map_or(&[][..], Vec::as_slice);
        let depth = stack.len().saturating_sub(1);
        if self.target == Some(w.steps.len()) {
            let mut held: Vec<Held> = stack
                .iter()
                .map(|a| Held {
                    active: a.clone(),
                    left: None,
                })
                .collect();
            if let Some(top) = held.last_mut() {
                top.left = left;
            }
            w.held = Some(held);
        }
        w.steps.push(Step { edge, def, depth });
    }
}

impl CallObserver for Watcher {
    fn enter(&self, call: &Call<'_>, args: &[Value]) -> Option<Value> {
        let def = self.defs.of_call(call.name, call.source)?;
        let mut w = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        w.stacks
            .entry(std::thread::current().id())
            .or_default()
            .push(Active {
                def,
                args: args.to_vec(),
                at: (!call.at.is_synthetic()).then_some(call.at.start),
            });
        self.step(&mut w, Edge::Enter, def, None);
        None
    }

    fn leave(&self, call: &Call<'_>, exit: Exit<'_>) {
        let Some(def) = self.defs.of_call(call.name, call.source) else {
            return;
        };
        let mut w = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        let left = match exit {
            Exit::Returned(v) | Exit::Supplied(v) => Some(Left::Returned(v.clone())),
            Exit::Raised(e) => Some(Left::Raised(e.to_string())),
            Exit::TailCalled => None,
        };
        if left.is_some() {
            self.step(&mut w, Edge::Leave, def, left);
        }
        if let Some(stack) = w.stacks.get_mut(&std::thread::current().id()) {
            stack.pop();
        }
    }
}

fn params_of(form: &Spanned) -> Vec<String> {
    let Some(items) = form.as_list() else {
        return Vec::new();
    };
    let list = match items.get(1).and_then(Spanned::as_list) {
        Some(head) => head.get(1..).unwrap_or_default(),
        None => items
            .get(2)
            .and_then(Spanned::as_list)
            .and_then(|lambda| lambda.get(1))
            .and_then(Spanned::as_list)
            .unwrap_or_default(),
    };
    list.iter()
        .filter_map(Spanned::as_symbol)
        .map(str::to_string)
        .collect()
}

struct Pass {
    defs: Arc<Definitions>,
    params: Vec<Vec<String>>,
    hashes: Option<DefHashes>,
    steps: Vec<Step>,
    held: Option<Vec<Held>>,
    run: record::Rerun,
}

fn replay_to(cfg: &BlueConfig, loaded: &Loaded, target: Option<usize>) -> Result<Pass, String> {
    let mut seen: Option<(Arc<Watcher>, Vec<Vec<String>>, Option<DefHashes>)> = None;
    let run = record::rerun(
        cfg,
        loaded,
        Some(Box::new(|w: &Watched<'_>| {
            let watcher = Arc::new(Watcher {
                defs: Arc::clone(w.definitions),
                target,
                state: Mutex::default(),
            });
            let params = w
                .definitions
                .iter()
                .map(|d| w.erased.get(d.top_level).map(params_of).unwrap_or_default())
                .collect();
            let hashes = target.is_none().then(|| hash_program(w.lowered));
            seen = Some((Arc::clone(&watcher), params, hashes));
            watcher
        })),
    )
    .map_err(|e| e.to_string())?;
    let (watcher, params, hashes) =
        seen.ok_or("the recorded run stopped before it was evaluated")?;
    let watching =
        std::mem::take(&mut *watcher.state.lock().unwrap_or_else(PoisonError::into_inner));
    if let Some(d) = run.invoked.account.host_io.taped().and_then(|t| t.diverged) {
        return Err(format!("the replay left its tape: {d}"));
    }
    Ok(Pass {
        defs: Arc::clone(&watcher.defs),
        params,
        hashes,
        steps: watching.steps,
        held: watching.held,
        run,
    })
}

/// Where a stop can move from step `at` of `steps`, each `None` past the end.
pub mod moves {
    use super::{Edge, Step};

    #[must_use]
    pub fn step_in(steps: &[Step], at: usize) -> Option<usize> {
        (at + 1 < steps.len()).then_some(at + 1)
    }

    #[must_use]
    pub fn next(steps: &[Step], at: usize) -> Option<usize> {
        let depth = steps.get(at)?.depth;
        (at + 1..steps.len()).find(|&i| steps[i].depth <= depth)
    }

    #[must_use]
    pub fn step_out(steps: &[Step], at: usize) -> Option<usize> {
        let here = steps.get(at)?;
        let depth = match here.edge {
            Edge::Enter => here.depth,
            Edge::Leave => here.depth.checked_sub(1)?,
        };
        (at + 1..steps.len()).find(|&i| steps[i].edge == Edge::Leave && steps[i].depth == depth)
    }

    #[must_use]
    pub fn step_back(at: usize) -> usize {
        at.saturating_sub(1)
    }

    #[must_use]
    pub fn forward_to(steps: &[Step], from: usize, hit: &dyn Fn(&Step) -> bool) -> Option<usize> {
        (from..steps.len()).find(|&i| steps[i].edge == Edge::Enter && hit(&steps[i]))
    }

    #[must_use]
    pub fn back_to(steps: &[Step], at: usize, hit: &dyn Fn(&Step) -> bool) -> Option<usize> {
        (0..at)
            .rev()
            .find(|&i| steps[i].edge == Edge::Enter && hit(&steps[i]))
    }
}

struct Debugged {
    loaded: Loaded,
    defs: Arc<Definitions>,
    params: Vec<Vec<String>>,
    hashes: DefHashes,
    steps: Vec<Step>,
    at: usize,
    held: Vec<Held>,
    breaks: Vec<bool>,
    stop_on_entry: bool,
}

impl Debugged {
    fn launch(cfg: &BlueConfig, receipt: &Path, stop_on_entry: bool) -> Result<Self, String> {
        let loaded = record::open(receipt).map_err(|e| e.to_string())?;
        let pass = replay_to(cfg, &loaded, None)?;
        if pass.run.replayed != loaded.original {
            return Err(format!(
                "the replay does not reproduce the recorded run: recorded {}, replayed {}",
                loaded.original, pass.run.replayed
            ));
        }
        let breaks = vec![false; pass.defs.len()];
        Ok(Self {
            loaded,
            hashes: pass.hashes.unwrap_or_default(),
            defs: pass.defs,
            params: pass.params,
            steps: pass.steps,
            at: 0,
            held: Vec::new(),
            breaks,
            stop_on_entry,
        })
    }

    fn goto(&mut self, cfg: &BlueConfig, at: usize) -> Result<(), String> {
        let pass = replay_to(cfg, &self.loaded, Some(at))?;
        if pass.steps != self.steps {
            return Err(format!(
                "the replay to step {at} numbered {} steps where the launch numbered {}",
                pass.steps.len(),
                self.steps.len()
            ));
        }
        self.held = pass.held.unwrap_or_default();
        self.at = at;
        Ok(())
    }

    fn hit(&self) -> impl Fn(&Step) -> bool + '_ {
        |s: &Step| self.breaks.get(s.def).copied().unwrap_or(false)
    }

    fn named(&self, name: &str) -> Vec<usize> {
        if name.starts_with("b3:") {
            return self
                .defs
                .iter()
                .enumerate()
                .filter(|(_, d)| {
                    self.hashes
                        .at(d.top_level)
                        .is_some_and(|h| h.hash.to_string() == name)
                })
                .map(|(i, _)| i)
                .collect();
        }
        self.defs.named(name)
    }

    fn on_line(&self, file: &str, line: usize) -> Vec<usize> {
        let wanted = Path::new(file).file_name();
        self.defs
            .iter()
            .enumerate()
            .filter(|(_, d)| {
                d.place.line == Some(line)
                    && d.place
                        .file
                        .as_deref()
                        .map(|f| Path::new(f).file_name() == wanted)
                        .unwrap_or(false)
            })
            .map(|(i, _)| i)
            .collect()
    }

    fn line_of(&self, offset: usize) -> Option<usize> {
        let src = self.loaded.recorded.source.as_bytes();
        (offset <= src.len()).then(|| src[..offset].iter().filter(|&&b| b == b'\n').count() + 1)
    }

    fn frames(&self) -> Vec<Json> {
        let mut out = Vec::new();
        for (k, held) in self.held.iter().enumerate().rev() {
            let def = self.defs.get(held.active.def);
            let callee = self.held.get(k + 1);
            let line = callee
                .filter(|_| def.is_some_and(|d| d.entry))
                .and_then(|c| c.active.at)
                .and_then(|o| self.line_of(o))
                .or_else(|| def.and_then(|d| d.place.line))
                .unwrap_or(0);
            let source = def.and_then(|d| d.place.file.clone()).map(|f| {
                let name = Path::new(&f)
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_else(|| f.clone());
                json!({"name": name, "path": f})
            });
            let hash = def
                .and_then(|d| self.hashes.at(d.top_level))
                .map(|h| h.hash.to_string());
            out.push(json!({
                "id": k + 1,
                "defHash": hash,
                "name": def.map_or_else(|| "?".to_string(), |d| d.name.clone()),
                "source": source,
                "line": line,
                "column": 1,
            }));
        }
        out
    }

    fn variables(&self, frame: usize) -> Vec<Json> {
        let Some(held) = frame.checked_sub(1).and_then(|k| self.held.get(k)) else {
            return Vec::new();
        };
        let names = self
            .params
            .get(held.active.def)
            .cloned()
            .unwrap_or_default();
        let mut out: Vec<Json> = held
            .active
            .args
            .iter()
            .enumerate()
            .map(|(i, v)| {
                let name = names.get(i).cloned().unwrap_or_else(|| format!("arg{i}"));
                json!({"name": name, "value": crate::render(v), "variablesReference": 0})
            })
            .collect();
        match &held.left {
            Some(Left::Returned(v)) => out.push(
                json!({"name": "return", "value": crate::render(v), "variablesReference": 0}),
            ),
            Some(Left::Raised(e)) => {
                out.push(json!({"name": "raised", "value": e, "variablesReference": 0}));
            }
            None => {}
        }
        out
    }
}

/// The server: requests in, messages out, no I/O of its own.
pub struct Server<'c> {
    cfg: &'c BlueConfig,
    seq: i64,
    run: Option<Debugged>,
    pending_functions: Vec<String>,
    done: bool,
}

impl<'c> Server<'c> {
    #[must_use]
    pub fn new(cfg: &'c BlueConfig) -> Self {
        Self {
            cfg,
            seq: 0,
            run: None,
            pending_functions: Vec::new(),
            done: false,
        }
    }

    #[must_use]
    pub fn is_done(&self) -> bool {
        self.done
    }

    fn next_seq(&mut self) -> i64 {
        self.seq += 1;
        self.seq
    }

    fn response(&mut self, req: &Json, body: Result<Json, String>) -> Json {
        let seq = self.next_seq();
        let command = req.get("command").cloned().unwrap_or(Json::Null);
        let request_seq = req.get("seq").cloned().unwrap_or(Json::Null);
        match body {
            Ok(body) => json!({
                "seq": seq, "type": "response", "request_seq": request_seq,
                "success": true, "command": command, "body": body,
            }),
            Err(message) => json!({
                "seq": seq, "type": "response", "request_seq": request_seq,
                "success": false, "command": command, "message": message,
            }),
        }
    }

    fn event(&mut self, event: &str, body: Json) -> Json {
        let seq = self.next_seq();
        json!({"seq": seq, "type": "event", "event": event, "body": body})
    }

    fn stopped(&mut self, reason: &str) -> Json {
        self.event(
            "stopped",
            json!({"reason": reason, "threadId": THREAD, "allThreadsStopped": true}),
        )
    }

    fn running(&mut self) -> Result<&mut Debugged, String> {
        self.run
            .as_mut()
            .ok_or_else(|| "no recorded run is launched".to_string())
    }

    fn travel(&mut self, to: Option<usize>, reason: &str) -> Result<Json, String> {
        let cfg = self.cfg;
        let run = self.running()?;
        match to {
            None => Ok(self.event("terminated", json!({}))),
            Some(at) => {
                run.goto(cfg, at)?;
                Ok(self.stopped(reason))
            }
        }
    }

    fn arrive(&mut self, req: &Json, to: Option<usize>, reason: &str) -> Vec<Json> {
        match self.travel(to, reason) {
            Err(e) => vec![self.response(req, Err(e))],
            Ok(event) => {
                let reply = self.response(req, Ok(json!({"allThreadsContinued": true})));
                vec![reply, event]
            }
        }
    }

    /// Answer one request: its response, then any events it raises.
    pub fn handle(&mut self, req: &Json) -> Vec<Json> {
        let command = req
            .get("command")
            .and_then(Json::as_str)
            .unwrap_or_default()
            .to_string();
        let args = req.get("arguments").cloned().unwrap_or(Json::Null);
        match command.as_str() {
            "initialize" => {
                let caps = json!({
                    "supportsConfigurationDoneRequest": true,
                    "supportsFunctionBreakpoints": true,
                    "supportsStepBack": true,
                    "supportsTerminateRequest": true,
                });
                vec![self.response(req, Ok(caps))]
            }
            "launch" => self.launch(req, &args),
            "setFunctionBreakpoints" => {
                let names: Vec<String> = args
                    .get("breakpoints")
                    .and_then(Json::as_array)
                    .map(|bs| {
                        bs.iter()
                            .filter_map(|b| b.get("name").and_then(Json::as_str))
                            .map(str::to_string)
                            .collect()
                    })
                    .unwrap_or_default();
                self.pending_functions = names;
                let body = self.function_breaks();
                vec![self.response(req, body)]
            }
            "setBreakpoints" => {
                let body = self.line_breaks(&args);
                vec![self.response(req, body)]
            }
            "configurationDone" => {
                let reply = self.response(req, Ok(json!({})));
                let mut out = vec![reply];
                let first = self.run.as_ref().map(|run| {
                    if run.stop_on_entry {
                        (Some(0).filter(|_| !run.steps.is_empty()), "entry")
                    } else {
                        (moves::forward_to(&run.steps, 0, &run.hit()), "breakpoint")
                    }
                });
                if let Some((to, reason)) = first {
                    match self.travel(to, reason) {
                        Ok(event) => out.push(event),
                        Err(e) => {
                            let said = self.event(
                                "output",
                                json!({"category": "stderr", "output": format!("{e}\n")}),
                            );
                            out.push(said);
                            out.push(self.event("terminated", json!({})));
                        }
                    }
                }
                out
            }
            "threads" => {
                vec![self.response(
                    req,
                    Ok(json!({"threads": [{"id": THREAD, "name": "main"}]})),
                )]
            }
            "stackTrace" => {
                let body = self.running().map(|run| {
                    let frames = run.frames();
                    json!({"totalFrames": frames.len(), "stackFrames": frames})
                });
                vec![self.response(req, body)]
            }
            "scopes" => {
                let frame = args.get("frameId").and_then(Json::as_u64).unwrap_or(0);
                let body = json!({"scopes": [{
                    "name": "Locals", "variablesReference": frame, "expensive": false,
                }]});
                vec![self.response(req, Ok(body))]
            }
            "variables" => {
                let frame = args
                    .get("variablesReference")
                    .and_then(Json::as_u64)
                    .and_then(|f| usize::try_from(f).ok())
                    .unwrap_or(0);
                let body = self
                    .running()
                    .map(|run| json!({"variables": run.variables(frame)}));
                vec![self.response(req, body)]
            }
            "next" | "stepIn" | "stepOut" | "stepBack" | "continue" | "reverseContinue" => {
                let target = self.running().map(|run| {
                    let at = run.at;
                    let steps = &run.steps;
                    match command.as_str() {
                        "next" => (moves::next(steps, at), "step"),
                        "stepIn" => (moves::step_in(steps, at), "step"),
                        "stepOut" => (moves::step_out(steps, at), "step"),
                        "stepBack" => (Some(moves::step_back(at)), "step"),
                        "continue" => (moves::forward_to(steps, at + 1, &run.hit()), "breakpoint"),
                        _ => match moves::back_to(steps, at, &run.hit()) {
                            Some(i) => (Some(i), "breakpoint"),
                            None => (Some(0), "entry"),
                        },
                    }
                });
                match target {
                    Err(e) => vec![self.response(req, Err(e))],
                    Ok((to, reason)) => self.arrive(req, to, reason),
                }
            }
            "disconnect" | "terminate" => {
                self.done = true;
                vec![self.response(req, Ok(json!({})))]
            }
            other => vec![self.response(req, Err(format!("`{other}` is not supported")))],
        }
    }

    fn launch(&mut self, req: &Json, args: &Json) -> Vec<Json> {
        let Some(receipt) = args.get("receipt").and_then(Json::as_str) else {
            return vec![self.response(
                req,
                Err("launch needs `receipt`: the receipt of a run recorded with `blue run --receipts DIR --record`".into()),
            )];
        };
        let stop_on_entry = args
            .get("stopOnEntry")
            .and_then(Json::as_bool)
            .unwrap_or(false);
        match Debugged::launch(self.cfg, Path::new(receipt), stop_on_entry) {
            Err(e) => vec![self.response(req, Err(e))],
            Ok(run) => {
                let steps = run.steps.len();
                self.run = Some(run);
                let reply = self.response(req, Ok(json!({})));
                let said = self.event(
                    "output",
                    json!({"category": "console", "output": format!("replayed {receipt}: {steps} steps\n")}),
                );
                vec![reply, said, self.event("initialized", json!({}))]
            }
        }
    }

    fn function_breaks(&mut self) -> Result<Json, String> {
        let names = self.pending_functions.clone();
        let run = self.running()?;
        run.breaks.iter_mut().for_each(|b| *b = false);
        let mut out = Vec::new();
        for name in &names {
            let found = run.named(name);
            for &d in &found {
                run.breaks[d] = true;
            }
            out.push(if found.is_empty() {
                json!({"verified": false, "message": format!("no definition is named `{name}`")})
            } else {
                json!({"verified": true})
            });
        }
        Ok(json!({"breakpoints": out}))
    }

    fn line_breaks(&mut self, args: &Json) -> Result<Json, String> {
        let file = args
            .get("source")
            .and_then(|s| s.get("path"))
            .and_then(Json::as_str)
            .unwrap_or_default()
            .to_string();
        let lines: Vec<usize> = args
            .get("breakpoints")
            .and_then(Json::as_array)
            .map(|bs| {
                bs.iter()
                    .filter_map(|b| b.get("line").and_then(Json::as_u64))
                    .filter_map(|l| usize::try_from(l).ok())
                    .collect()
            })
            .unwrap_or_default();
        let run = self.running()?;
        let mut out = Vec::new();
        for line in lines {
            let found = run.on_line(&file, line);
            for &d in &found {
                run.breaks[d] = true;
            }
            out.push(if found.is_empty() {
                json!({"verified": false, "line": line, "message": "no definition starts on this line"})
            } else {
                json!({"verified": true, "line": line})
            });
        }
        Ok(json!({"breakpoints": out}))
    }
}

#[cfg(unix)]
fn protocol_out() -> std::io::Result<Box<dyn Write>> {
    use std::os::fd::AsFd;
    let protocol = std::io::stdout().as_fd().try_clone_to_owned()?;
    rustix::stdio::dup2_stdout(std::io::stderr())?;
    Ok(Box::new(std::fs::File::from(protocol)))
}

#[cfg(not(unix))]
fn protocol_out() -> std::io::Result<Box<dyn Write>> {
    Ok(Box::new(std::io::stdout()))
}

/// Serve the Debug Adapter Protocol on stdin and stdout until `disconnect`
/// or the end of the input.
///
/// # Errors
///
/// A read or a write of the protocol that fails.
pub fn serve(cfg: &BlueConfig) -> Result<ExitCode, CliError> {
    let failed = |source| CliError::Write {
        path: "<stdio>".to_string(),
        source,
    };
    let mut out = protocol_out().map_err(failed)?;
    let mut input = std::io::stdin().lock();
    let mut server = Server::new(cfg);
    while let Some(msg) = read_message(&mut input).map_err(failed)? {
        for m in server.handle(&msg) {
            write_message(&mut out, &m).map_err(failed)?;
        }
        if server.is_done() {
            break;
        }
    }
    Ok(ExitCode::SUCCESS)
}
