use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use blue_lang_runtime::def_hash::{DefHash, Shape};
use blue_lang_runtime::pipeline::{check_entry, Checked, Checking};
use blue_lang_runtime::uses::{Entry, ResolvedProgram};
use blue_lang_runtime::word_shapes::{standing, Standing, WORD_SHAPES};
use serde_json::{json, Value as Json};

pub const PROGRAM: &str = include_str!("../blue/arika.b");

pub const REPO: &str = "blue";

#[derive(clap::Subcommand)]
pub enum ArikaCmd {
    #[command(
        about = "The words a draft already is: each definition of FILE (or the one at FILE:LINE) matched to a blue word by def hash (T0), written shape (T1) and shape through a wrapper (T2), with the word's id and import line"
    )]
    Like {
        #[arg(required_unless_present = "hook", value_name = "FILE[:LINE]")]
        target: Option<String>,
        #[arg(long, help = "Print the facts as one JSON object")]
        json: bool,
        #[arg(
            long,
            conflicts_with = "json",
            help = "Read Claude Code's PreToolUse JSON from stdin, lower the draft a Write, Edit or MultiEdit would leave in a .b file, print one advice line per word it already is, and always exit 0"
        )]
        hook: bool,
    },
    #[command(
        about = "Find a blue word by NAME: its canonical spelling, an old spelling's new home, and catalogue glosses that mention NAME (T5)"
    )]
    Word {
        name: String,
        #[arg(long, help = "Print the facts as one JSON object")]
        json: bool,
    },
}

pub struct Draft {
    pub path: PathBuf,
    pub text: String,
    pub line: Option<usize>,
}

#[must_use]
pub fn split_target(target: &str) -> (PathBuf, Option<usize>) {
    match target.rsplit_once(':') {
        Some((file, line)) if !file.is_empty() && line.parse::<usize>().is_ok() => {
            (PathBuf::from(file), line.parse().ok())
        }
        _ => (PathBuf::from(target), None),
    }
}

fn line_of(text: &str, at: usize) -> usize {
    text.get(..at)
        .map_or(1, |head| head.matches('\n').count() + 1)
}

struct Home {
    file: PathBuf,
    checked: Checked,
    computed: Vec<Shape>,
    written: Vec<Shape>,
    hashes: blue_lang_runtime::def_hash::DefHashes,
}

fn check_file(
    path: &Path,
    text: &str,
    loader: &dyn blue_lang_runtime::uses::Loader,
) -> Result<Checked, String> {
    check_entry(
        Entry {
            path: Some(path),
            text,
        },
        loader,
        None,
        Checking::WithTests,
    )
    .map_err(|e| e.to_string())
}

fn package_source(
    loader: &blue_lang_pkg::load_path::LoadPath,
    package: &str,
) -> Result<(PathBuf, String), String> {
    use blue_lang_runtime::uses::Loader;
    let leaf = format!("{}.b", package.rsplit_once('/').map_or(package, |(_, l)| l));
    let files = loader.load(package)?;
    let pick = files
        .iter()
        .find(|(label, _)| {
            Path::new(label)
                .file_name()
                .is_some_and(|n| n == leaf.as_str())
        })
        .or_else(|| files.first())
        .ok_or_else(|| format!("`{package}` has no source file"))?;
    Ok((PathBuf::from(&pick.0), pick.1.clone()))
}

fn load_home(
    environment: &blue_lang_pkg::load_path::Environment,
    from: &Path,
    package: &str,
) -> Result<Home, String> {
    let loader = environment.load_path(Some(from));
    let (file, text) = package_source(&loader, package)?;
    let checked = check_file(&file, &text, &loader)?;
    let lowered = checked.lowered();
    let hashes = blue_lang_mondou::hash_checked(&checked.program, &lowered);
    Ok(Home {
        computed: checked.entry_shapes(),
        written: checked.entry_written_shapes(),
        file,
        checked,
        hashes,
    })
}

fn shape_at(shapes: &[Shape], top_level: usize) -> Option<&Shape> {
    shapes.iter().find(|s| s.top_level == top_level)
}

#[must_use]
pub fn readable_id(word: &str, hash: &DefHash) -> String {
    format!("blue:{REPO}:{word}@{}", &hash.hex()[..12])
}

fn tier(exact: bool, written: bool) -> &'static str {
    if exact {
        "T0"
    } else if written {
        "T1"
    } else {
        "T2"
    }
}

struct Ours<'a> {
    hash: Option<&'a DefHash>,
    written: Option<&'a Shape>,
}

fn hit(word: &str, foundation: bool, ours: &Ours<'_>, home: &Result<Home, String>) -> Json {
    let (package, bare) = word.rsplit_once("::").unwrap_or(("", word));
    let base = json!({
        "word": word,
        "package": package,
        "name": bare,
        "foundation": foundation,
        "fix": if foundation { "import" } else { "move_down" },
    });
    let home = match home {
        Ok(h) => h,
        Err(why) => {
            let mut b = base;
            b["tier"] = json!("T2");
            b["home"] = json!({"outcome": "blind", "why": why});
            return b;
        }
    };
    let found = home.computed.iter().find(|s| {
        s.name() == bare
            && home.checked.program.owner_of(s.top_level) == Some(ResolvedProgram::ENTRY)
    });
    let Some(found) = found else {
        let mut b = base;
        b["tier"] = json!("T2");
        b["home"] = json!({"outcome": "blind", "why": format!("{} defines no `{bare}`", home.file.display())});
        return b;
    };
    let home_hash = home.hashes.at(found.top_level).map(|d| d.hash);
    let home_written = shape_at(&home.written, found.top_level);
    let exact = matches!((ours.hash, home_hash.as_ref()), (Some(a), Some(b)) if a == b);
    let written = matches!((ours.written, home_written), (Some(a), Some(b)) if a.hash == b.hash);
    let start = home.checked.program.forms()[found.top_level].span.start;
    let text = home
        .checked
        .program
        .file(ResolvedProgram::ENTRY)
        .map(|f| f.text.to_string())
        .unwrap_or_default();
    let mut b = base;
    b["tier"] = json!(tier(exact, written));
    b["id"] = home_hash
        .as_ref()
        .map_or(Json::Null, |h| json!(readable_id(word, h)));
    b["home"] = json!({
        "outcome": "found",
        "file": home.file.display().to_string(),
        "line": line_of(&text, start),
        "def_hash": home_hash.map(|h| h.hex()),
    });
    b
}

#[must_use]
pub fn like_facts(draft: &Draft) -> Json {
    let environment = crate::census::environment_over(std::slice::from_ref(&draft.path));
    let loader = environment.load_path(Some(&draft.path));
    let file = draft.path.display().to_string();
    let checked = match check_file(&draft.path, &draft.text, &loader) {
        Ok(c) => c,
        Err(why) => return json!({"outcome": "blind", "file": file, "why": why, "defs": []}),
    };
    let lowered = checked.lowered();
    let hashes = blue_lang_mondou::hash_checked(&checked.program, &lowered);
    let written = checked.entry_written_shapes();
    let mut homes: BTreeMap<String, Result<Home, String>> = BTreeMap::new();
    let mut defs = Vec::new();
    for s in checked.entry_shapes() {
        let form = &checked.program.forms()[s.top_level];
        let (first, last) = (
            line_of(&draft.text, form.span.start),
            line_of(&draft.text, form.span.end),
        );
        if draft.line.is_some_and(|l| l < first || l > last) {
            continue;
        }
        let ours = Ours {
            hash: hashes.at(s.top_level).map(|d| &d.hash),
            written: shape_at(&written, s.top_level),
        };
        let hits = match standing(&s.hash, &s.key) {
            Standing::CopyOf { word, foundation } => {
                let package = word.rsplit_once("::").map_or(word, |(p, _)| p).to_string();
                let home = homes
                    .entry(package.clone())
                    .or_insert_with(|| load_home(&environment, &draft.path, &package));
                vec![hit(word, foundation, &ours, home)]
            }
            Standing::OwnWord | Standing::NoWord => Vec::new(),
        };
        defs.push(json!({
            "name": s.name(),
            "line": first,
            "size": s.size,
            "def_hash": ours.hash.map(DefHash::hex),
            "shape": s.hash.hex(),
            "own_word": matches!(standing(&s.hash, &s.key), Standing::OwnWord),
            "hits": hits,
        }));
    }
    let outcome = if defs
        .iter()
        .any(|d| d["hits"].as_array().is_some_and(|h| !h.is_empty()))
    {
        "found"
    } else {
        "empty"
    };
    json!({"outcome": outcome, "file": file, "line": draft.line, "defs": defs})
}

fn legacy_moves(
    loader: &blue_lang_pkg::load_path::LoadPath,
    packages: &BTreeSet<&str>,
) -> (Vec<Json>, Vec<Json>) {
    use blue_lang_syntax::scope::{legacy_target, LegacyKind};
    let mut moves = Vec::new();
    let mut blind = Vec::new();
    for package in packages {
        let (file, text) = match package_source(loader, package) {
            Ok(found) => found,
            Err(why) => {
                blind.push(json!({"package": package, "why": why}));
                continue;
            }
        };
        let Ok(forms) = blue_lang_syntax::parse_program_tree(&text) else {
            blind.push(
                json!({"package": package, "why": format!("{} does not parse", file.display())}),
            );
            continue;
        };
        for legacy in forms.iter().filter_map(legacy_target) {
            if let LegacyKind::Moved(ms) = legacy.kind {
                for m in ms {
                    moves.push(json!({
                        "old": format!("{package}::{}", m.old),
                        "word": format!("{}::{}", m.home, m.new),
                        "since": legacy.since,
                    }));
                }
            }
        }
    }
    (moves, blind)
}

fn catalog_of(loader: &blue_lang_pkg::load_path::LoadPath, cwd: &Path) -> Option<PathBuf> {
    loader
        .roots()
        .iter()
        .cloned()
        .chain(cwd.ancestors().map(|a| a.join("bidamas")))
        .map(|d| d.join("CATALOG.md"))
        .find(|c| c.is_file())
}

#[must_use]
pub fn word_facts(name: &str, cwd: &Path) -> Json {
    let loader = blue_lang_pkg::load_path::LoadPath::for_dir(cwd);
    let words: BTreeMap<&str, bool> = WORD_SHAPES.iter().map(|(_, w, f)| (*w, *f)).collect();
    let packages: BTreeSet<&str> = words
        .keys()
        .filter_map(|w| w.rsplit_once("::").map(|(p, _)| p))
        .collect();
    let (moves, blind) = legacy_moves(&loader, &packages);
    let catalog = catalog_of(&loader, cwd);
    json!({
        "query": name,
        "words": words.iter().map(|(w, f)| json!({"word": w, "foundation": f})).collect::<Vec<_>>(),
        "moves": moves,
        "blind": blind,
        "catalog": catalog.map(|c| c.display().to_string()),
    })
}

fn draft_of_hook(input: &str) -> Option<Draft> {
    let doc: Json = serde_json::from_str(input).ok()?;
    let tool = doc.get("tool_name")?.as_str()?;
    let args = doc.get("tool_input")?;
    let path = PathBuf::from(args.get("file_path")?.as_str()?);
    if path.extension().is_none_or(|x| x != "b") {
        return None;
    }
    let text = match tool {
        "Write" => args.get("content")?.as_str()?.to_string(),
        "Edit" => apply_edit(&std::fs::read_to_string(&path).ok()?, args)?,
        "MultiEdit" => args
            .get("edits")?
            .as_array()?
            .iter()
            .try_fold(std::fs::read_to_string(&path).ok()?, |text, e| {
                apply_edit(&text, e)
            })?,
        _ => return None,
    };
    Some(Draft {
        path,
        text,
        line: None,
    })
}

fn apply_edit(text: &str, edit: &Json) -> Option<String> {
    let old = edit.get("old_string")?.as_str()?;
    let new = edit.get("new_string")?.as_str()?;
    if old.is_empty() || !text.contains(old) {
        return None;
    }
    Some(
        if edit.get("replace_all").and_then(Json::as_bool) == Some(true) {
            text.replace(old, new)
        } else {
            text.replacen(old, new, 1)
        },
    )
}

fn render(args: Vec<String>) -> Result<ExitCode, String> {
    blue_lang_runtime::sys::set_program_args(args);
    blue_lang_runtime::pipeline::run_in_surface(
        Entry {
            path: Some(Path::new("crates/blue-lang-cli/blue/arika.b")),
            text: PROGRAM,
        },
        blue_lang_runtime::inputs::Inputs::new(),
        &blue_lang_pkg::load_path::Environment::from_env().load_path(None),
        None,
    )
    .map_err(|e| e.to_string())?;
    Ok(ExitCode::SUCCESS)
}

fn mode(json: bool) -> &'static str {
    if json {
        "--json"
    } else {
        "--text"
    }
}

fn hook() -> ExitCode {
    use std::io::Read;
    std::panic::set_hook(Box::new(|_| {}));
    let _ = std::panic::catch_unwind(|| {
        let mut input = String::new();
        let _ = std::io::stdin().read_to_string(&mut input);
        let Some(draft) = draft_of_hook(&input) else {
            return;
        };
        let facts = like_facts(&draft);
        let _ = render(vec!["like".into(), "--hook".into(), facts.to_string()]);
    });
    ExitCode::SUCCESS
}

/// # Errors
///
/// A FILE that cannot be read, or the embedded program failing to run.
pub fn run(cmd: ArikaCmd) -> Result<ExitCode, String> {
    match cmd {
        ArikaCmd::Like { hook: true, .. } => Ok(hook()),
        ArikaCmd::Like { target, json, .. } => {
            let (path, line) = split_target(&target.unwrap_or_default());
            let text =
                std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
            let facts = like_facts(&Draft { path, text, line });
            render(vec!["like".into(), mode(json).into(), facts.to_string()])
        }
        ArikaCmd::Word { name, json } => {
            let cwd = std::env::current_dir().map_err(|e| format!("the working directory: {e}"))?;
            let facts = word_facts(&name, &cwd);
            render(vec!["word".into(), mode(json).into(), facts.to_string()])
        }
    }
}
