use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::wire::{Refusal, Reply, Request};

pub const DEFAULT_SOFT_MS: u64 = 150;
pub const DEFAULT_HARD_MS: u64 = 2000;

pub type Prepare = fn(&mut Command);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkerSpec {
    pub name: String,
    pub args: Vec<String>,
    pub soft_ms: u64,
    pub hard_ms: u64,
}

impl WorkerSpec {
    #[must_use]
    pub fn new(name: &str, args: Vec<String>) -> Self {
        Self {
            name: name.to_owned(),
            args,
            soft_ms: DEFAULT_SOFT_MS,
            hard_ms: DEFAULT_HARD_MS,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Line {
        worker: String,
        epoch: u64,
        reply: Reply,
    },
    Closed {
        worker: String,
        epoch: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Overdue {
    pub worker: String,
    pub id: u64,
    pub refusal: Refusal,
}

pub type Sink = Arc<dyn Fn(Event) + Send + Sync>;

struct Live {
    child: Child,
    stdin: ChildStdin,
}

struct InFlight {
    id: u64,
    sent: Instant,
    slow_said: bool,
}

struct Worker {
    spec: WorkerSpec,
    live: Option<Live>,
    epoch: u64,
    in_flight: Option<InFlight>,
    waiting: Option<Request>,
    load_refused: Option<Refusal>,
}

pub struct Pool {
    exe: PathBuf,
    sink: Sink,
    prepare: Option<Prepare>,
    workers: BTreeMap<String, Worker>,
}

impl Pool {
    #[must_use]
    pub fn new(exe: PathBuf, sink: Sink) -> Self {
        Self {
            exe,
            sink,
            prepare: None,
            workers: BTreeMap::new(),
        }
    }

    #[must_use]
    pub fn with_prepare(mut self, prepare: Prepare) -> Self {
        self.prepare = Some(prepare);
        self
    }

    #[must_use]
    pub fn names(&self) -> Vec<&str> {
        self.workers.keys().map(String::as_str).collect()
    }

    #[must_use]
    pub fn busy(&self) -> bool {
        self.workers
            .values()
            .any(|w| w.in_flight.is_some() || w.waiting.is_some())
    }

    #[must_use]
    pub fn running(&self) -> usize {
        self.workers.values().filter(|w| w.live.is_some()).count()
    }

    pub fn set_specs(&mut self, specs: Vec<WorkerSpec>) {
        let wanted: BTreeMap<String, WorkerSpec> =
            specs.into_iter().map(|s| (s.name.clone(), s)).collect();
        self.workers.retain(|name, worker| {
            let keep = wanted.get(name).is_some_and(|s| *s == worker.spec);
            if !keep {
                worker.stop();
            }
            keep
        });
        for (name, spec) in wanted {
            self.workers.entry(name).or_insert_with(|| Worker {
                spec,
                live: None,
                epoch: 0,
                in_flight: None,
                waiting: None,
                load_refused: None,
            });
        }
    }

    pub fn restart_all(&mut self) {
        for worker in self.workers.values_mut() {
            worker.stop();
        }
    }

    pub fn ask(
        &mut self,
        worker_name: &str,
        id: u64,
        call: &str,
        args: Vec<serde_json::Value>,
    ) -> Result<(), Refusal> {
        let (exe, sink, prepare) = (self.exe.clone(), Arc::clone(&self.sink), self.prepare);
        let worker = self
            .workers
            .get_mut(worker_name)
            .ok_or_else(|| Refusal::new("unknown", format!("{worker_name} is no worker")))?;
        if let Some(load_refused) = &worker.load_refused {
            return Err(load_refused.clone());
        }
        worker.waiting = Some(Request {
            id,
            call: call.to_owned(),
            args,
        });
        worker
            .pump(&exe, &sink, prepare)
            .map_err(|why| Refusal::new("spawn", why))
    }

    pub fn answered(&mut self, worker_name: &str, epoch: u64) -> bool {
        let (exe, sink, prepare) = (self.exe.clone(), Arc::clone(&self.sink), self.prepare);
        let Some(worker) = self.workers.get_mut(worker_name) else {
            return false;
        };
        if worker.epoch != epoch {
            return false;
        }
        worker.in_flight = None;
        let _ = worker.pump(&exe, &sink, prepare);
        true
    }

    pub fn load_refused(&mut self, worker_name: &str, epoch: u64, refusal: &Refusal) -> bool {
        let Some(worker) = self.workers.get_mut(worker_name) else {
            return false;
        };
        if worker.epoch != epoch {
            return false;
        }
        worker.in_flight = None;
        worker.waiting = None;
        worker.load_refused = Some(refusal.clone());
        true
    }

    pub fn closed(&mut self, worker_name: &str, epoch: u64) -> Option<(u64, Refusal)> {
        let worker = self.workers.get_mut(worker_name)?;
        if worker.epoch != epoch {
            return None;
        }
        let status = worker
            .live
            .take()
            .and_then(|mut live| live.child.wait().ok())
            .map_or_else(|| "no status".to_owned(), |s| s.to_string());
        let id = worker.in_flight.take().map_or(0, |f| f.id);
        if worker.load_refused.is_some() {
            return None;
        }
        Some((
            id,
            Refusal::new("died", format!("the worker ended: {status}")),
        ))
    }

    #[must_use]
    pub fn next_deadline(&self) -> Option<Instant> {
        self.workers
            .values()
            .filter_map(|worker| {
                let flight = worker.in_flight.as_ref()?;
                let limit = if flight.slow_said {
                    worker.spec.hard_ms
                } else {
                    worker.spec.soft_ms
                };
                Some(flight.sent + Duration::from_millis(limit))
            })
            .min()
    }

    pub fn tick(&mut self, now: Instant) -> Vec<Overdue> {
        let mut overdue = Vec::new();
        let (exe, sink, prepare) = (self.exe.clone(), Arc::clone(&self.sink), self.prepare);
        for (name, worker) in &mut self.workers {
            let Some(flight) = &mut worker.in_flight else {
                continue;
            };
            let waited = now.saturating_duration_since(flight.sent);
            if waited >= Duration::from_millis(worker.spec.hard_ms) {
                let id = flight.id;
                worker.stop();
                overdue.push(Overdue {
                    worker: name.clone(),
                    id,
                    refusal: Refusal::new(
                        "killed",
                        format!("no answer in {} ms", worker.spec.hard_ms),
                    ),
                });
                if worker.waiting.is_some() {
                    let _ = worker.pump(&exe, &sink, prepare);
                }
            } else if !flight.slow_said && waited >= Duration::from_millis(worker.spec.soft_ms) {
                flight.slow_said = true;
                overdue.push(Overdue {
                    worker: name.clone(),
                    id: flight.id,
                    refusal: Refusal::new(
                        "slow",
                        format!("no answer in {} ms yet", worker.spec.soft_ms),
                    ),
                });
            }
        }
        overdue
    }

    pub fn cancel_all(&mut self) {
        for worker in self.workers.values_mut() {
            worker.waiting = None;
            if worker.in_flight.is_some() {
                worker.stop();
            }
        }
    }
}

impl Drop for Pool {
    fn drop(&mut self) {
        self.restart_all();
    }
}

impl Worker {
    fn stop(&mut self) {
        self.epoch += 1;
        self.in_flight = None;
        self.load_refused = None;
        if let Some(mut live) = self.live.take() {
            let _ = live.child.kill();
            let _ = live.child.wait();
        }
    }

    fn spawn(&mut self, exe: &Path, sink: &Sink, prepare: Option<Prepare>) -> Result<(), String> {
        self.epoch += 1;
        let mut command = Command::new(exe);
        command
            .args(&self.spec.args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .env("RUST_LOG", "off");
        if let Some(prepare) = prepare {
            prepare(&mut command);
        }
        let mut child = command
            .spawn()
            .map_err(|e| format!("{}: {e}", exe.display()))?;
        let stdin = child.stdin.take().ok_or("the worker has no stdin")?;
        let stdout = child.stdout.take().ok_or("the worker has no stdout")?;
        let (worker, epoch, sink) = (self.spec.name.clone(), self.epoch, Arc::clone(sink));
        std::thread::Builder::new()
            .name(format!("blue-worker-{worker}"))
            .spawn(move || {
                for line in BufReader::new(stdout).lines() {
                    let Ok(line) = line else { break };
                    let reply = serde_json::from_str::<Reply>(&line).unwrap_or_else(|e| {
                        Reply::LoadRefused {
                            load_refused: Refusal::new(
                                "wire",
                                format!("the worker wrote a bad line: {e}"),
                            ),
                        }
                    });
                    sink(Event::Line {
                        worker: worker.clone(),
                        epoch,
                        reply,
                    });
                }
                sink(Event::Closed { worker, epoch });
            })
            .map_err(|e| e.to_string())?;
        self.live = Some(Live { child, stdin });
        Ok(())
    }

    fn pump(&mut self, exe: &Path, sink: &Sink, prepare: Option<Prepare>) -> Result<(), String> {
        if self.in_flight.is_some() {
            return Ok(());
        }
        let Some(request) = self.waiting.take() else {
            return Ok(());
        };
        if self.live.is_none() {
            self.spawn(exe, sink, prepare)?;
        }
        let line = serde_json::to_string(&request).map_err(|e| e.to_string())?;
        let written = self.live.as_mut().is_some_and(|live| {
            writeln!(live.stdin, "{line}")
                .and_then(|()| live.stdin.flush())
                .is_ok()
        });
        if written {
            self.in_flight = Some(InFlight {
                id: request.id,
                sent: Instant::now(),
                slow_said: false,
            });
            Ok(())
        } else {
            self.waiting = Some(request);
            Err("the worker's stdin is closed".to_owned())
        }
    }
}
