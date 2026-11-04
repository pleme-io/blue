use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};

use blue_lang_host::{Budget, CallError, Canonical, Capability, Entry, Hosted, Program, Value};
use blue_lang_pkg::load_path::{Environment, LoadPath};
use blue_lang_runtime::json::{json_to_value, value_to_json};
use tatara_lisp_eval::MapKey;

use crate::wire::{Refusal, Reply, Request};

pub const DEFAULT_FUEL: usize = 20_000_000;
pub const DEFAULT_MEMORY_MB: u64 = 1024;

pub fn capabilities_named(names: &[String]) -> Result<Vec<Capability>, String> {
    names
        .iter()
        .map(|name| {
            Capability::host_effects()
                .into_iter()
                .find(|c| c.label() == name)
                .ok_or_else(|| format!("{name} is no host capability"))
        })
        .collect()
}

fn loader_for(entry: &Path) -> LoadPath {
    let mut roots: Vec<PathBuf> = Vec::new();
    if let Some(dir) = entry.parent() {
        roots.push(dir.join("bidamas"));
        if let Some(up) = dir.parent() {
            roots.push(up.join("bidamas"));
        }
    }
    roots.retain(|root| root.is_dir());
    let inherited = std::env::var_os("BLUE_PATH").unwrap_or_default();
    roots.extend(std::env::split_paths(&inherited));
    let joined = std::env::join_paths(&roots).unwrap_or_default();
    let dist = std::env::var_os("BLUE_DIST").unwrap_or_default();
    Environment::from_vars(&joined, &dist).load_path(Some(entry))
}

pub fn load(file: &Path, allow: &[Capability]) -> Result<Hosted<()>, Refusal> {
    let text = std::fs::read_to_string(file)
        .map_err(|e| Refusal::new("load", format!("{}: {e}", file.display())))?;
    let loader = loader_for(file);
    let entry = Entry {
        path: Some(file),
        text: &text,
    };
    Program::<()>::builder(entry)
        .loader(&loader)
        .canonical(Canonical::AsWritten)
        .posture(allow)
        .load(&mut ())
        .map(Program::into_hosted)
        .map_err(|e| Refusal::new("load", e.to_string()))
}

fn budget(fuel: usize) -> Budget {
    Budget {
        fuel: Some(fuel),
        ..Budget::tree_walker_default()
    }
}

fn refusal_of(e: &CallError) -> Refusal {
    match e {
        CallError::Exhausted { .. } => Refusal::new("exhausted", e.to_string()),
        CallError::Undefined(_) | CallError::NotAFunction { .. } => {
            Refusal::new("load", e.to_string())
        }
        CallError::Raised { .. } => Refusal::new("raised", e.to_string()),
    }
}

#[must_use]
pub fn record_of(value: &serde_json::Value) -> Value {
    match value {
        serde_json::Value::Array(items) => Value::list(items.iter().map(record_of)),
        serde_json::Value::Object(fields) => Value::map(fields.iter().map(|(key, field)| {
            (
                MapKey::Keyword(std::sync::Arc::from(key.as_str())),
                record_of(field),
            )
        })),
        other => json_to_value(other),
    }
}

fn say(out: &mut impl Write, reply: &Reply) -> bool {
    let Ok(line) = serde_json::to_string(reply) else {
        return false;
    };
    writeln!(out, "{line}").and_then(|()| out.flush()).is_ok()
}

#[must_use]
pub fn answer(hosted: &mut Hosted<()>, request: &Request, fuel: usize) -> Reply {
    let args: Vec<Value> = request.args.iter().map(record_of).collect();
    match hosted.call_budgeted(&request.call, args, &mut (), budget(fuel)) {
        Ok(value) => Reply::Answer {
            id: request.id,
            value: value_to_json(&value),
        },
        Err(e) => Reply::Refused {
            id: request.id,
            refused: refusal_of(&e),
        },
    }
}

#[cfg(target_os = "linux")]
fn bound_memory(mb: u64) {
    use rustix::process::{setrlimit, Resource, Rlimit};
    let bytes = mb.saturating_mul(1024 * 1024);
    let limit = Rlimit {
        current: Some(bytes),
        maximum: Some(bytes),
    };
    let _ = setrlimit(Resource::As, limit);
}

#[cfg(not(target_os = "linux"))]
fn bound_memory(_mb: u64) {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServeArgs {
    pub file: PathBuf,
    pub allow: Vec<String>,
    pub fuel: usize,
    pub memory_mb: u64,
}

#[must_use]
pub fn serve(args: &ServeArgs) -> i32 {
    bound_memory(args.memory_mb);
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    let allow = match capabilities_named(&args.allow) {
        Ok(allow) => allow,
        Err(why) => {
            say(
                &mut out,
                &Reply::LoadRefused {
                    load_refused: Refusal::new("load", why),
                },
            );
            return 0;
        }
    };
    let mut program = match load(&args.file, &allow) {
        Ok(program) => program,
        Err(refused) => {
            say(
                &mut out,
                &Reply::LoadRefused {
                    load_refused: refused,
                },
            );
            return 0;
        }
    };
    for line in std::io::stdin().lock().lines() {
        let Ok(line) = line else { break };
        let Ok(request) = serde_json::from_str::<Request>(&line) else {
            continue;
        };
        let reply = answer(&mut program, &request, args.fuel);
        if !say(&mut out, &reply) {
            break;
        }
    }
    0
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Judge<'a> {
    pub entry: &'a str,
    pub program: &'a str,
}

pub fn judged(file: &Path, judge: Judge<'_>, fuel: usize) -> Result<serde_json::Value, Refusal> {
    let allow = [Capability::Environment, Capability::Clock];
    let mut world = load(file, &allow)?;
    let entries = world
        .call_budgeted(judge.entry, Vec::new(), &mut (), budget(fuel))
        .map_err(|e| refusal_of(&e))?;
    let loader = Environment::from_env().load_path(None);
    let mut judging = Program::<()>::builder(Entry::anonymous(judge.program))
        .loader(&loader)
        .canonical(Canonical::AsWritten)
        .posture(&[])
        .load(&mut ())
        .map(Program::into_hosted)
        .map_err(|e| Refusal::new("load", e.to_string()))?;
    let verdict = judging
        .call_budgeted("judged", vec![entries], &mut (), budget(fuel))
        .map_err(|e| refusal_of(&e))?;
    Ok(value_to_json(&verdict))
}

#[must_use]
pub fn run_judged(file: &Path, judge: Judge<'_>, fuel: usize, memory_mb: u64) -> i32 {
    bound_memory(memory_mb);
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    let reply = match judged(file, judge, fuel) {
        Ok(value) => Reply::Answer { id: 0, value },
        Err(refused) => Reply::LoadRefused {
            load_refused: refused,
        },
    };
    say(&mut out, &reply);
    0
}

pub const SERVE: &str = "blue-serve";
pub const JUDGED: &str = "blue-judged";

fn flag_values(args: &[String], flag: &str) -> Vec<String> {
    args.windows(2)
        .filter(|w| w[0] == flag)
        .map(|w| w[1].clone())
        .collect()
}

fn flag_value<T: std::str::FromStr>(args: &[String], flag: &str, default: T) -> T {
    flag_values(args, flag)
        .first()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

#[must_use]
pub fn parse_serve(args: &[String]) -> Option<ServeArgs> {
    Some(ServeArgs {
        file: PathBuf::from(flag_values(args, "--file").first()?),
        allow: flag_values(args, "--allow"),
        fuel: flag_value(args, "--fuel", DEFAULT_FUEL),
        memory_mb: flag_value(args, "--memory-mb", DEFAULT_MEMORY_MB),
    })
}

#[must_use]
pub fn serve_args(args: &ServeArgs) -> Vec<String> {
    let mut out = vec![
        SERVE.to_owned(),
        "--file".to_owned(),
        args.file.display().to_string(),
        "--fuel".to_owned(),
        args.fuel.to_string(),
        "--memory-mb".to_owned(),
        args.memory_mb.to_string(),
    ];
    for capability in &args.allow {
        out.push("--allow".to_owned());
        out.push(capability.clone());
    }
    out
}

#[must_use]
pub fn judged_args(file: &Path) -> Vec<String> {
    vec![
        JUDGED.to_owned(),
        "--file".to_owned(),
        file.display().to_string(),
    ]
}

#[must_use]
pub fn dispatch(args: &[String], judge: Judge<'_>) -> Option<i32> {
    let word = args.first()?;
    if word == SERVE {
        return Some(parse_serve(&args[1..]).map_or(2, |a| serve(&a)));
    }
    if word == JUDGED {
        let rest = &args[1..];
        let Some(file) = flag_values(rest, "--file").first().cloned() else {
            return Some(2);
        };
        return Some(run_judged(
            Path::new(&file),
            judge,
            flag_value(rest, "--fuel", DEFAULT_FUEL),
            flag_value(rest, "--memory-mb", DEFAULT_MEMORY_MB),
        ));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(dir: &Path, name: &str, text: &str) -> PathBuf {
        let path = dir.join(name);
        std::fs::write(&path, text).unwrap();
        path
    }

    fn temp(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("blue-worker-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn request(call: &str) -> Request {
        Request {
            id: 7,
            call: call.to_owned(),
            args: Vec::new(),
        }
    }

    #[test]
    fn an_answer_carries_its_id_and_a_raise_is_refused() {
        let dir = temp("answer");
        let file = write(
            &dir,
            "m.b",
            "def fine()\n  \"ok\"\nend\n\ndef bad()\n  raise(\"boom\")\nend\n",
        );
        let mut hosted = load(&file, &[]).unwrap();
        assert_eq!(
            answer(&mut hosted, &request("fine"), DEFAULT_FUEL),
            Reply::Answer {
                id: 7,
                value: serde_json::json!("ok")
            }
        );
        match answer(&mut hosted, &request("bad"), DEFAULT_FUEL) {
            Reply::Refused { id: 7, refused } => assert_eq!(refused.kind, "raised"),
            other => panic!("{other:?}"),
        }
        match answer(&mut hosted, &request("nope"), DEFAULT_FUEL) {
            Reply::Refused { id: 7, refused } => assert_eq!(refused.kind, "load"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn arguments_reach_blue_as_values() {
        let dir = temp("args");
        let file = write(&dir, "m.b", "def twice(n)\n  n * 2\nend\n");
        let mut hosted = load(&file, &[]).unwrap();
        let r = Request {
            id: 1,
            call: "twice".to_owned(),
            args: vec![serde_json::json!(21)],
        };
        assert_eq!(
            answer(&mut hosted, &r, DEFAULT_FUEL),
            Reply::Answer {
                id: 1,
                value: serde_json::json!(42)
            }
        );
    }

    #[test]
    fn a_record_reaches_blue_with_keyword_fields_and_comes_back_plain() {
        let dir = temp("record");
        let file = write(
            &dir,
            "m.b",
            "def shape(n)\n  {name: n[:name], twice: n[:deep][:v] * 2}\nend\n",
        );
        let mut hosted = load(&file, &[]).unwrap();
        let r = Request {
            id: 1,
            call: "shape".to_owned(),
            args: vec![serde_json::json!({"name": "a", "deep": {"v": 21}})],
        };
        assert_eq!(
            answer(&mut hosted, &r, DEFAULT_FUEL),
            Reply::Answer {
                id: 1,
                value: serde_json::json!({"name": "a", "twice": 42})
            }
        );
    }

    #[test]
    fn a_loop_runs_out_of_fuel_and_is_refused() {
        let dir = temp("loop");
        let file = write(
            &dir,
            "m.b",
            "def spin(n)\n  spin(n + 1)\nend\n\ndef go()\n  spin(0)\nend\n",
        );
        let mut hosted = load(&file, &[]).unwrap();
        match answer(&mut hosted, &request("go"), 5_000) {
            Reply::Refused { refused, .. } => assert_eq!(refused.kind, "exhausted"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn a_file_that_does_not_parse_is_refused_at_load() {
        let dir = temp("parse");
        let file = write(&dir, "m.b", "def (((\n");
        let refused = load(&file, &[]).err().unwrap();
        assert_eq!(refused.kind, "load");
        let missing = load(&dir.join("absent.b"), &[]).err().unwrap();
        assert_eq!(missing.kind, "load");
    }

    #[test]
    fn a_bidama_beside_the_file_or_one_folder_up_is_found() {
        let dir = temp("private");
        std::fs::create_dir_all(dir.join("bidamas/mine")).unwrap();
        std::fs::create_dir_all(dir.join("bar")).unwrap();
        write(
            &dir,
            "bidamas/mine/Bluefile",
            "package(\"mine\", \"0.1.0\")\n",
        );
        write(&dir, "bidamas/mine/mine.b", "def word()\n  \"mine\"\nend\n");
        let body = "use(\"mine\", [:word])\n\ndef go()\n  word\nend\n";
        for file in [write(&dir, "top.b", body), write(&dir, "bar/low.b", body)] {
            let mut hosted = load(&file, &[]).unwrap();
            assert_eq!(
                answer(&mut hosted, &request("go"), DEFAULT_FUEL),
                Reply::Answer {
                    id: 7,
                    value: serde_json::json!("mine")
                }
            );
        }
    }

    #[test]
    fn a_refused_capability_name_is_named() {
        let why = capabilities_named(&["root".to_owned()]).unwrap_err();
        assert!(why.contains("root"), "{why}");
        assert_eq!(
            capabilities_named(&["filesystem".to_owned()])
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn a_host_capability_not_granted_is_refused_inside_blue() {
        let dir = temp("posture");
        let file = write(
            &dir,
            "m.b",
            "def go()\n  read_file(\"/etc/hostname\")\nend\n",
        );
        let mut hosted = load(&file, &[]).unwrap();
        match answer(&mut hosted, &request("go"), DEFAULT_FUEL) {
            Reply::Refused { refused, .. } => assert_eq!(refused.kind, "raised"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn the_flags_round_trip_through_their_own_parser() {
        let args = ServeArgs {
            file: PathBuf::from("/c/bar/a.b"),
            allow: vec!["filesystem".to_owned(), "clock".to_owned()],
            fuel: 9,
            memory_mb: 3,
        };
        let words = serve_args(&args);
        assert_eq!(words[0], SERVE);
        assert_eq!(parse_serve(&words[1..]), Some(args));
    }

    #[test]
    fn a_judge_reads_entries_and_a_world_that_raises_is_refused() {
        let dir = temp("judge");
        let judge = Judge {
            entry: "world",
            program:
                "use(\"retsu\", [:size])\n\ndef judged(entries)\n  {count: size(entries)}\nend\n",
        };
        let good = write(&dir, "w.b", "def world()\n  [1, 2, 3]\nend\n");
        assert_eq!(
            judged(&good, judge, DEFAULT_FUEL).unwrap(),
            serde_json::json!({"count": 3})
        );
        let bad = write(&dir, "x.b", "def world()\n  raise(\"no\")\nend\n");
        assert_eq!(
            judged(&bad, judge, DEFAULT_FUEL).unwrap_err().kind,
            "raised"
        );
    }

    #[test]
    fn an_unknown_word_is_no_worker() {
        let judge = Judge {
            entry: "w",
            program: "",
        };
        assert_eq!(dispatch(&["--mode".to_owned()], judge), None);
        assert_eq!(dispatch(&[], judge), None);
    }
}
