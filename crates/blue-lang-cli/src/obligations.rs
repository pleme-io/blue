use std::path::{Path, PathBuf};
use std::process::ExitCode;

use blue_lang_check::obligations::{Refusal, OBLIGATIONS};
use blue_lang_check::relations::{CANDIDATES, KINDS, RELATIONS};
use blue_lang_check::RULES;
use serde_json::{json, Value as Json};

pub const PROGRAM: &str = include_str!("../blue/discover.b");

#[derive(clap::Subcommand)]
pub enum ObligationsCmd {
    #[command(
        about = "Every obligation, relation kind and ratified relation, as the registry states them"
    )]
    List {
        #[arg(long, help = "Print the rows as one JSON object")]
        json: bool,
    },
    #[command(
        about = "The evidence discovery reads: one JSON line per registry row, the form denominator and every obligation site (finding or waiver) under ROOT. The same tree gives the same bytes"
    )]
    Facts {
        #[arg(default_value = ".")]
        root: PathBuf,
        #[arg(
            long = "in",
            value_name = "DIR",
            help = "Read only these paths under ROOT (repeatable); every .b file under ROOT when none is given"
        )]
        dirs: Vec<String>,
    },
    #[command(
        about = "Mine relations between obligations and candidate obligations from the facts of ROOT, the recorded history and the consumer rows, and print the discovery report; --check fails when the committed report differs"
    )]
    Discover {
        #[arg(default_value = ".")]
        root: PathBuf,
        #[arg(
            long = "in",
            value_name = "DIR",
            help = "Read only these paths under ROOT (repeatable); every .b file under ROOT when none is given"
        )]
        dirs: Vec<String>,
        #[arg(long, help = "Print the report as JSON instead of Markdown")]
        json: bool,
        #[arg(
            long,
            value_name = "FILE",
            help = "Compare the report with FILE and exit 1 when they differ"
        )]
        check: Option<PathBuf>,
    },
    #[command(
        about = "Append the registry's debt per code to the history file when it moved since the last row, or with --backfill rebuild it from git; the history discovery reads for trades and fixes made together"
    )]
    History {
        #[arg(default_value = "gen/obligation-debt.tsv")]
        file: PathBuf,
        #[arg(
            long,
            help = "Rebuild the file from every commit of git's first-parent history that moved a ratchet or a held count"
        )]
        backfill: bool,
    },
}

#[must_use]
pub fn registry() -> Json {
    json!({
        "obligations": OBLIGATIONS.iter().map(|o| json!({
            "id": o.id,
            "code": match o.refusal { Refusal::Code(c) => Some(c.as_str()), _ => None },
            "refusal": o.refusal.label(),
            "evidence": o.evidence.label(),
            "profile": o.profile.label(),
            "held": o.held,
            "forced": o.refusal.forced(),
        })).collect::<Vec<_>>(),
        "kinds": KINDS.iter().map(|k| json!({
            "kind": k.kind.label(),
            "symmetric": k.symmetric,
            "sources": k.sources.iter().map(|s| s.label()).collect::<Vec<_>>(),
            "action": k.action.label(),
            "enabled": k.enabled,
            "law": k.law,
        })).collect::<Vec<_>>(),
        "relations": RELATIONS.iter().map(|r| json!({
            "kind": r.kind.label(),
            "a": r.a.as_str(),
            "b": r.b.as_str(),
            "state": r.state.label(),
            "why": r.state.why(),
            "tier": r.tier.label(),
            "evidence": r.evidence,
            "live": r.live(),
        })).collect::<Vec<_>>(),
        "candidates": CANDIDATES.iter().map(|c| json!({
            "kind": c.kind,
            "code": c.code.as_str(),
            "state": c.state.label(),
            "why": c.state.why(),
        })).collect::<Vec<_>>(),
    })
}

#[must_use]
pub fn rule_facts() -> Vec<Json> {
    RULES
        .iter()
        .filter(|r| r.ratchet.is_some() || blue_lang_check::obligations::of_code(r.code).is_some())
        .map(|r| {
            let o = blue_lang_check::obligations::of_code(r.code);
            json!({
                "fact": "rule",
                "code": r.code.as_str(),
                "slug": r.slug,
                "obligation": o.map(|o| o.id),
                "ratchet": r.ratchet,
                "held": o.map_or(0, |o| o.held),
                "debt": r.ratchet.unwrap_or(0) + o.map_or(0, |o| o.held),
                "law": r.law,
                "explanation": r.explanation,
            })
        })
        .collect()
}

pub fn facts(root: &Path, dirs: &[String]) -> Result<Vec<Json>, String> {
    let c = if dirs.is_empty() {
        crate::census::take(root)?
    } else {
        crate::census::take_files(root, crate::census::files_under(root, dirs))?
    };
    let mut out = rule_facts();
    out.push(json!({"fact": "forms", "files": c.files, "forms": c.forms}));
    out.extend(c.sites.iter().map(crate::census::Site::to_json));
    Ok(out)
}

fn lines(rows: &[Json]) -> String {
    let mut s = String::new();
    for r in rows {
        s.push_str(&r.to_string());
        s.push('\n');
    }
    s
}

fn miner(args: Vec<String>) -> Result<ExitCode, String> {
    blue_lang_runtime::sys::set_program_args(args);
    let out = blue_lang_runtime::pipeline::run_in_surface(
        blue_lang_runtime::uses::Entry {
            path: Some(Path::new("crates/blue-lang-cli/blue/discover.b")),
            text: PROGRAM,
        },
        blue_lang_runtime::inputs::Inputs::new(),
        &blue_lang_pkg::load_path::Environment::from_env().load_path(None),
        None,
    )
    .map_err(|e| e.to_string())?;
    Ok(
        if matches!(out.value, tatara_lisp_eval::Value::Bool(false)) {
            ExitCode::FAILURE
        } else {
            ExitCode::SUCCESS
        },
    )
}

pub fn run(cmd: ObligationsCmd) -> Result<ExitCode, String> {
    match cmd {
        ObligationsCmd::List { json: true } => {
            println!("{}", registry());
            Ok(ExitCode::SUCCESS)
        }
        ObligationsCmd::List { json: false } => {
            for o in OBLIGATIONS {
                println!(
                    "{:<24} {:<8} {:<12} held {:>4}",
                    o.id,
                    o.refusal.label(),
                    o.evidence.label(),
                    o.held
                );
            }
            for k in KINDS {
                println!(
                    "kind {:<16} {:<8} {}",
                    k.kind.label(),
                    if k.enabled { "on" } else { "off" },
                    k.law
                );
            }
            for r in RELATIONS {
                println!(
                    "{} {:<16} {} {:<10} {}",
                    r.a,
                    r.kind.label(),
                    r.b,
                    r.state.label(),
                    r.evidence
                );
            }
            Ok(ExitCode::SUCCESS)
        }
        ObligationsCmd::Facts { root, dirs } => {
            print!("{}", lines(&facts(&root, &dirs)?));
            Ok(ExitCode::SUCCESS)
        }
        ObligationsCmd::Discover {
            root,
            dirs,
            json,
            check,
        } => {
            let scratch =
                std::env::temp_dir().join(format!("blue-obligations-{}.jsonl", std::process::id()));
            std::fs::write(&scratch, lines(&facts(&root, &dirs)?)).map_err(|e| e.to_string())?;
            std::fs::write(
                scratch.with_extension("registry.json"),
                registry().to_string(),
            )
            .map_err(|e| e.to_string())?;
            let mut args = vec![
                "discover".to_string(),
                root.display().to_string(),
                scratch.display().to_string(),
                scratch
                    .with_extension("registry.json")
                    .display()
                    .to_string(),
            ];
            if json {
                args.push("--json".into());
            }
            if let Some(f) = check {
                args.push("--check".into());
                args.push(f.display().to_string());
            }
            let got = miner(args);
            let _ = std::fs::remove_file(&scratch);
            let _ = std::fs::remove_file(scratch.with_extension("registry.json"));
            got
        }
        ObligationsCmd::History { file, backfill } => {
            let rows = rule_facts();
            let scratch = std::env::temp_dir().join(format!(
                "blue-obligations-rules-{}.jsonl",
                std::process::id()
            ));
            std::fs::write(&scratch, lines(&rows)).map_err(|e| e.to_string())?;
            let mut args = vec![
                "history".to_string(),
                file.display().to_string(),
                scratch.display().to_string(),
            ];
            if backfill {
                args.push("--backfill".into());
            }
            let got = miner(args);
            let _ = std::fs::remove_file(&scratch);
            got
        }
    }
}
