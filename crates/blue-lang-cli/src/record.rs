use std::path::{Path, PathBuf};
use std::process::ExitCode;

use blue_lang_proc::receipt::Tapes;
use blue_lang_proc::receipt::{canonical, Replay};
use blue_lang_proc::trace::{crash_hash, tape_from_json, tape_to_json};
use blue_lang_proc::Pid;
use blue_lang_runtime::pipeline::{Run, RunError};
use blue_lang_runtime::{Account, Hold, Receipt};
use serde_json::{json, Value as Json};

use crate::config::BlueConfig;
use crate::{invoke, CliError, Invocation, Invoked};

pub const FORMAT: &str = "blue-run-record";
pub const VERSION: u64 = 1;
pub const EXTENSION: &str = "run.json";

pub enum Taping {
    Off,
    Record,
    Replay(Tapes),
}

pub struct Inputs<'a> {
    pub file: &'a Path,
    pub inputs: &'a [String],
    pub allow: &'a [String],
    pub args: &'a [String],
    pub receipt_steps: bool,
}

fn tapes_to_json(tapes: &Tapes) -> Json {
    Json::Object(
        tapes
            .iter()
            .map(|(pid, t)| (pid.0.to_string(), tape_to_json(t)))
            .collect(),
    )
}

fn tapes_from_json(j: &Json) -> Result<Tapes, String> {
    j.as_object()
        .ok_or("the tapes are not an object of process tapes")?
        .iter()
        .map(|(pid, t)| {
            let pid = pid
                .parse()
                .map_err(|_| format!("`{pid}` is not a process id"))?;
            Ok((Pid(pid), tape_from_json(t)?))
        })
        .collect()
}

fn hash(j: &Json) -> String {
    format!("b3:{}", crash_hash(j))
}

fn inputs_json(given: &Inputs<'_>, source: &str) -> Json {
    json!({
        "allow": given.allow,
        "args": given.args,
        "clock": "virtual",
        "file": given.file.display().to_string(),
        "inputs": given.inputs,
        "receipt_steps": given.receipt_steps,
        "source": source,
    })
}

fn output_hash(ran: &Result<Run, RunError>) -> String {
    let (kind, text) = blue_lang_runtime::receipt::exit_of(ran);
    let value = ran.as_ref().ok().map(|r| crate::render(&r.value));
    hash(&json!({"exit": {"kind": kind, "text": text}, "value": value}))
}

fn receipt_of(
    hold: &Hold,
    account: &Account,
    ran: &Result<Run, RunError>,
    inputs: &Json,
) -> Receipt {
    let mut receipt =
        blue_lang_runtime::receipt::of_run(hold, account, blue_lang_runtime::receipt::exit_of(ran));
    let tapes = account.host_io.taped().map(|t| t.tapes).unwrap_or_default();
    receipt.replay = Some(Replay {
        inputs: hash(inputs),
        output: output_hash(ran),
        tape: hash(&tapes_to_json(&tapes)),
    });
    receipt
}

fn name_of(receipt: &Receipt) -> String {
    let file = blue_lang_runtime::receipt::name_of(&receipt.bytes());
    format!(
        "b3:{}",
        file.trim_end_matches(blue_lang_runtime::receipt::EXTENSION)
            .trim_end_matches('.')
    )
}

pub fn write(dir: &Path, invoked: &Invoked, given: &Inputs<'_>) {
    let Some(hold) = invoked.hold.as_ref() else {
        return;
    };
    let inputs = inputs_json(given, &invoked.src);
    let receipt = receipt_of(hold, &invoked.account, &invoked.ran, &inputs);
    let tapes = invoked
        .account
        .host_io
        .taped()
        .map(|t| t.tapes)
        .unwrap_or_default();
    let named = name_of(&receipt);
    let record = json!({
        "format": FORMAT,
        "version": VERSION,
        "receipt": named,
        "run": inputs,
        "tapes": tapes_to_json(&tapes),
    });
    let written = blue_lang_runtime::receipt::write(dir, &receipt).and_then(|_| {
        let hex = named.trim_start_matches("b3:");
        std::fs::write(
            dir.join(format!("{hex}.{EXTENSION}")),
            canonical(&record).into_bytes(),
        )
    });
    if let Err(e) = written {
        eprintln!(
            "blue: the run's record could not be written to {}: {e}",
            dir.display()
        );
    }
}

struct Recorded {
    file: PathBuf,
    source: String,
    inputs: Vec<String>,
    allow: Vec<String>,
    args: Vec<String>,
    receipt_steps: bool,
    tapes: Tapes,
}

fn strings(j: &Json, key: &str) -> Result<Vec<String>, String> {
    j.get(key)
        .and_then(Json::as_array)
        .ok_or_else(|| format!("the record's run has no `{key}`"))?
        .iter()
        .map(|v| {
            v.as_str()
                .map(str::to_string)
                .ok_or_else(|| format!("`{key}` holds {v}, not a string"))
        })
        .collect()
}

fn load(path: &Path, receipt: &str) -> Result<Recorded, String> {
    let shown = path.display();
    let bytes = std::fs::read(path).map_err(|e| format!("{shown}: {e}"))?;
    let j: Json = serde_json::from_slice(&bytes).map_err(|e| format!("{shown}: not JSON: {e}"))?;
    if j.get("format").and_then(Json::as_str) != Some(FORMAT) {
        return Err(format!("{shown}: not a {FORMAT}"));
    }
    if j.get("version").and_then(Json::as_u64) != Some(VERSION) {
        return Err(format!(
            "{shown}: {FORMAT} version {}; this blue reads version {VERSION}",
            j["version"]
        ));
    }
    if j.get("receipt").and_then(Json::as_str) != Some(receipt) {
        return Err(format!(
            "{shown}: records the run of {}, not of {receipt}",
            j["receipt"]
        ));
    }
    let run = j.get("run").ok_or_else(|| format!("{shown}: no `run`"))?;
    let text = |k: &str| {
        run.get(k)
            .and_then(Json::as_str)
            .map(str::to_string)
            .ok_or_else(|| format!("{shown}: the record's run has no `{k}`"))
    };
    Ok(Recorded {
        file: PathBuf::from(text("file")?),
        source: text("source")?,
        inputs: strings(run, "inputs")?,
        allow: strings(run, "allow")?,
        args: strings(run, "args")?,
        receipt_steps: run
            .get("receipt_steps")
            .and_then(Json::as_bool)
            .unwrap_or(false),
        tapes: tapes_from_json(j.get("tapes").unwrap_or(&Json::Null))
            .map_err(|e| format!("{shown}: its tapes: {e}"))?,
    })
}

pub fn replay(cfg: &BlueConfig, receipt_path: &Path) -> Result<ExitCode, CliError> {
    let original = blue_lang_runtime::receipt::verify(receipt_path).map_err(CliError::Fmt)?;
    let hex = original.trim_start_matches("b3:");
    let record_path = receipt_path
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join(format!("{hex}.{EXTENSION}"));
    let recorded = load(&record_path, &original).map_err(|e| {
        CliError::Fmt(format!(
            "{e}\nblue: only a run recorded with `blue run --receipts DIR --record` replays from its receipt"
        ))
    })?;
    let scratch = std::env::temp_dir().join(format!("blue-replay-{}-{hex}", std::process::id()));
    let given = Inputs {
        file: &recorded.file,
        inputs: &recorded.inputs,
        allow: &recorded.allow,
        args: &recorded.args,
        receipt_steps: recorded.receipt_steps,
    };
    let taped: usize = recorded.tapes.values().map(Vec::len).sum();
    let invoked = invoke(
        cfg,
        Invocation {
            file: &recorded.file,
            src: Some(recorded.source.clone()),
            inputs: &recorded.inputs,
            allow: &recorded.allow,
            receipts: Some(&scratch),
            receipt_steps: recorded.receipt_steps,
            no_memo: true,
            executor: blue_lang_runtime::pipeline::Executor::Walker,
            args: recorded.args.clone(),
            taping: Taping::Replay(recorded.tapes.clone()),
        },
    );
    let _ = std::fs::remove_dir_all(&scratch);
    let invoked = invoked?;
    let hold = invoked
        .hold
        .as_ref()
        .ok_or_else(|| CliError::Fmt("the replay ran under no hold".into()))?;
    let receipt = receipt_of(
        hold,
        &invoked.account,
        &invoked.ran,
        &inputs_json(&given, &invoked.src),
    );
    let replayed = name_of(&receipt);
    let consumed = invoked.account.host_io.taped();
    println!("recorded: {original}");
    println!("replayed: {replayed}");
    if let Some(t) = &consumed {
        println!("tape: {} of {taped} host answers read", t.entries);
        if let Some(d) = &t.diverged {
            println!("diverged: {d}");
        }
    }
    if replayed == original {
        println!("reproduced: the replayed run's receipt is the recorded run's");
        Ok(ExitCode::SUCCESS)
    } else {
        println!("not reproduced: the replayed run's receipt differs from the recorded run's");
        println!(
            "replayed receipt: {}",
            String::from_utf8_lossy(&receipt.bytes())
        );
        Ok(ExitCode::FAILURE)
    }
}
