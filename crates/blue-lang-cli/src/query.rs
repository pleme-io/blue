//! `blue query QUERY [PATH…]`: every definition under the paths that satisfies
//! a query, one engine call per file (`blue_lang_mondou::Engine::query`), each
//! file loaded as `blue check FILE` and the language server load it
//! (`Environment`'s scopes), so an editor asking the engine gets the same
//! answers.
//!
//! QUERY is the query's tatara-lisp text, or the name of a `query(name, …)`
//! in the Bluefile of the current directory or above it. A file that does not
//! parse or whose imports do not load has no resolved tree to ask; it is
//! named on stderr and the run exits 1, so a skipped file never reads as a
//! file with no hits.

use std::io::Write;
use std::path::PathBuf;
use std::process::ExitCode;

use blue_lang_mondou::{Engine, Hit, Query, Reaches};
use blue_lang_pkg::load_path::Environment;

use crate::CliError;

pub fn run(query: &str, paths: &[PathBuf], json: bool) -> Result<ExitCode, CliError> {
    let text = query_text(query)?;
    let q = Query::parse(&text).map_err(|e| CliError::Pkg(e.to_string()))?;
    let files = files(paths);
    let mut engine = Engine::with_scopes(Box::new(Environment::from_env()));
    let mut out = std::io::stdout().lock();
    let (mut hits, mut skipped) = (0usize, 0usize);
    for path in &files {
        let source = std::fs::read_to_string(path).map_err(|source| CliError::Read {
            path: path.display().to_string(),
            source,
        })?;
        let id = path.display().to_string();
        engine.set_document(&id, Some(path.clone()), &source);
        if let Some(why) = unanswerable(&engine, &id) {
            eprintln!("blue query: {id}: skipped, {why}");
            skipped += 1;
            engine.close_document(&id);
            continue;
        }
        let found = engine
            .query(&id, &q)
            .map_err(|e| CliError::Pkg(format!("{id}: {e}")))?;
        for h in &found {
            let line = if json {
                h.json(&id).to_string()
            } else {
                text_line(&id, h, &q)
            };
            let _ = writeln!(out, "{line}");
        }
        hits += found.len();
        engine.close_document(&id);
    }
    eprintln!(
        "{hits} hit(s) in {} file(s){}",
        files.len() - skipped,
        if skipped > 0 {
            format!(", {skipped} skipped")
        } else {
            String::new()
        }
    );
    Ok(if skipped == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}

/// The query's text: QUERY itself when it is data, else the Bluefile query
/// it names.
fn query_text(query: &str) -> Result<String, CliError> {
    let trimmed = query.trim_start();
    if trimmed.starts_with('(') || trimmed.starts_with('`') {
        return Ok(query.to_string());
    }
    let cwd = std::env::current_dir().map_err(|source| CliError::Read {
        path: ".".into(),
        source,
    })?;
    let Some(bluefile) = cwd
        .ancestors()
        .map(|d| d.join(blue_lang_pkg::MANIFEST_FILE))
        .find(|f| f.is_file())
    else {
        return Err(CliError::Pkg(format!(
            "`{query}` is not a query (one starts with `(`) and no Bluefile above {} names queries",
            cwd.display()
        )));
    };
    let src = std::fs::read_to_string(&bluefile).map_err(|source| CliError::Read {
        path: bluefile.display().to_string(),
        source,
    })?;
    let project = blue_lang_pkg::read_bluefile(&src)?.project;
    project.queries.get(query).cloned().ok_or_else(|| {
        CliError::Pkg(format!(
            "{} declares no query `{query}`; it declares: {}",
            bluefile.display(),
            if project.queries.is_empty() {
                "none".to_string()
            } else {
                project
                    .queries
                    .keys()
                    .cloned()
                    .collect::<Vec<_>>()
                    .join(", ")
            }
        ))
    })
}

/// Every `.b` file the paths name: a directory's through the corpus walk
/// `blue census` uses, a file itself. No path is the current directory.
fn files(paths: &[PathBuf]) -> Vec<PathBuf> {
    let dot = [PathBuf::from(".")];
    let paths = if paths.is_empty() { &dot[..] } else { paths };
    let mut out = Vec::new();
    for p in paths {
        if p.is_dir() {
            out.extend(blue_lang_pkg::corpus::files(p));
        } else {
            out.push(p.clone());
        }
    }
    out.dedup();
    out
}

/// Why document `id` has no resolved tree to query, when it has none.
fn unanswerable(engine: &Engine, id: &str) -> Option<String> {
    let a = engine.analysis(id)?;
    match (a.parsed.as_ref(), &a.checked) {
        (Err(e), _) => Some(format!("it does not parse: {e}")),
        (_, Some(Err(e))) => Some(format!("its imports do not load: {e}")),
        _ => None,
    }
}

/// `file:line:col: definition`, then what the pattern bound, then for each
/// capability a `reaches` clause names, the chain the definition reaches it
/// through.
fn text_line(file: &str, h: &Hit, q: &Query) -> String {
    let mut line = format!("{file}:{}:{}: {}", h.line, h.column, h.definition);
    if !h.bindings.is_empty() {
        let bound: Vec<String> = h
            .bindings
            .iter()
            .map(|(n, v)| format!("{n} = {v}"))
            .collect();
        line.push_str("  ");
        line.push_str(&bound.join(", "));
    }
    for (cap, via) in &h.reach {
        let named = q.reaches().iter().any(|r| match r {
            Reaches::Any => true,
            Reaches::One(c) => c == cap,
        });
        if named {
            line.push_str(&format!("  {} via {}", cap.label(), via.join(" -> ")));
        }
    }
    line
}
