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
        #[arg(
            long,
            value_name = "SNAPSHOT.json",
            requires = "facts",
            help = "Read each home word from the facts under this header (blue arika emit) instead of checking its package; facts whose root is not the header's are refused as blind"
        )]
        snapshot: Option<PathBuf>,
        #[arg(
            long,
            value_name = "FACTS.jsonl",
            requires = "snapshot",
            help = "The facts the header roots (nix build .#arika-facts)"
        )]
        facts: Option<PathBuf>,
    },
    #[command(
        about = "Find a blue word by NAME: its canonical spelling, an old spelling's new home, and catalogue glosses that mention NAME (T5)"
    )]
    Word {
        name: String,
        #[arg(long, help = "Print the facts as one JSON object")]
        json: bool,
        #[arg(
            long,
            value_name = "SNAPSHOT.json",
            requires = "facts",
            help = "Search every word, old spelling and doc gloss of the facts under this header (blue arika emit) instead of WORD_SHAPES, the packages' sources and CATALOG.md; facts whose root is not the header's are refused as blind"
        )]
        snapshot: Option<PathBuf>,
        #[arg(
            long,
            value_name = "FACTS.jsonl",
            requires = "snapshot",
            help = "The facts the header roots (nix build .#arika-facts)"
        )]
        facts: Option<PathBuf>,
    },
    #[command(
        about = "Write the header SNAPSHOT.json for the bidamas under ROOT (each package's RFC 9162 unit_root and row count, and the snapshot_root over them) and, with --facts, the facts: every definition the engine sees as one JSON line (readable id, def_hash, shape hashes, gloss, file, line, legacy names). The same tree gives the same bytes"
    )]
    Emit {
        #[arg(default_value = "bidamas")]
        root: PathBuf,
        #[arg(
            long,
            help = "Where to write the snapshot (default ROOT/SNAPSHOT.json)"
        )]
        out: Option<PathBuf>,
        #[arg(
            long,
            value_name = "FACTS.jsonl",
            help = "Also write the facts, one row per line"
        )]
        facts: Option<PathBuf>,
    },
    #[command(
        about = "Blue words whose name, package or doc gloss match TEXT, ranked by BM25 (the junni words), from the facts"
    )]
    Find {
        text: String,
        #[arg(long, default_value_t = 12)]
        limit: usize,
        #[arg(long, help = "Print the answer as one JSON object")]
        json: bool,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(about = "Every fact of one word, by pkg::name or readable id")]
    Get {
        word: String,
        #[arg(long, help = "Print the answer as one JSON object")]
        json: bool,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(about = "The definitions that call a word, by pkg::name or readable id")]
    Uses {
        word: String,
        #[arg(long, help = "Print the answer as one JSON object")]
        json: bool,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(
        about = "Why a word exists and is shaped as it is: the reasons recorded for it (its @doc, the commits and docs/ROADMAP.md and docs/HORIZON.md lines that name it), what pins it (the tests that name it, its callers, the commit that first wrote it), each cited; `no recorded reason` when every source was read and none says why, blind when one could not be read"
    )]
    Why {
        word: String,
        #[arg(long, help = "Print the answer as one JSON object")]
        json: bool,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(
        about = "Functions of MIN nodes or more that share one computed shape across words (T2 over the whole tree)"
    )]
    Groups {
        #[arg(long, default_value_t = 12)]
        min: usize,
        #[arg(long, help = "Print the answer as one JSON object")]
        json: bool,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(
        about = "How PACKAGE's words moved since an older facts file: added, removed, and code or doc moved"
    )]
    Changed {
        package: String,
        #[arg(long, value_name = "FACTS.jsonl", help = "The older facts")]
        since: PathBuf,
        #[arg(long, help = "Print the answer as one JSON object")]
        json: bool,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(
        about = "Answer a named question over blue's knowledge graph (definitions, tests, docs and rules as khipu quads, asked through DuckDB): untested-CAPABILITY is every definition that reaches the capability and that no test or doc example names"
    )]
    Ask {
        question: String,
        #[arg(long, help = "Print the answer as one JSON object")]
        json: bool,
        #[arg(
            long,
            value_name = "FILE",
            help = "Where to write the quad store (default: a file in the temp dir, removed after)"
        )]
        store: Option<PathBuf>,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(
        about = "Ask every golden question of FILE (one `intent<TAB>word` per line, # comments) through find and name each whose word is no longer the top hit (G5)"
    )]
    Golden {
        file: PathBuf,
        #[arg(long, help = "Print the answer as one JSON object")]
        json: bool,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(about = "Write blue's definitions, tests, docs and rules as N-Quads to OUT")]
    Quads {
        out: PathBuf,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(about = "Print the MCP tool list, rendered from the blue schema TOOLS in arika.b")]
    Tools,
    #[command(
        about = "Answer one MCP JSON-RPC request (REQUEST is the JSON text) from the facts, as the service would; a notification prints nothing"
    )]
    Mcp {
        request: String,
        #[command(flatten)]
        from: FactsFrom,
    },
    #[command(
        about = "Serve the blue_word_* tools as an MCP server over Streamable HTTP (POST JSON-RPC to any path; /healthz answers ok)"
    )]
    Serve {
        #[arg(default_value = "127.0.0.1:8433")]
        addr: String,
        #[arg(
            long,
            value_name = "FILE",
            help = "Where blue_word_ask writes its quad store"
        )]
        store: Option<PathBuf>,
        #[command(flatten)]
        from: FactsFrom,
    },
}

#[derive(clap::Args)]
pub struct FactsFrom {
    #[arg(
        long,
        value_name = "SNAPSHOT.json",
        requires = "facts",
        help = "Answer from the facts under this header; facts whose root is not the header's are refused as blind. Without it the facts of ROOT are built in process"
    )]
    snapshot: Option<PathBuf>,
    #[arg(
        long,
        value_name = "FACTS.jsonl",
        requires = "snapshot",
        help = "The facts the header roots (nix build .#arika-facts)"
    )]
    facts: Option<PathBuf>,
    #[arg(
        long,
        default_value = "bidamas",
        help = "The bidamas to build the facts of when no header is given; `why` reads the git history holding it and the docs/ROADMAP.md and docs/HORIZON.md beside it"
    )]
    root: PathBuf,
}

impl FactsFrom {
    fn check(&self) -> Result<Json, String> {
        match (&self.snapshot, &self.facts) {
            (Some(header), Some(facts)) => {
                let snap = Snapshot::read(header, facts)?;
                Ok(json!({"root": snap.root, "rows": snap.rows}))
            }
            _ => Ok(json!({"root": null, "rows": emit_facts(&self.root)["rows"]})),
        }
    }
}

fn rules() -> Json {
    blue_lang_check::RULES
        .iter()
        .map(|r| {
            json!({
                "code": r.code.to_string(),
                "slug": r.slug,
                "severity": r.severity.label(),
                "law": r.law,
            })
        })
        .collect()
}

fn over_facts(verb: &str, json: bool, query: &Json, from: &FactsFrom) -> Result<ExitCode, String> {
    let check = from.check()?;
    let mut query = query.clone();
    query["dir"] = json!(from.root.display().to_string());
    render(vec![
        verb.into(),
        mode(json).into(),
        query.to_string(),
        check.to_string(),
    ])
}

fn scratch_store(
    store: Option<PathBuf>,
) -> Result<(PathBuf, Option<blue_lang_runtime::scratch::Scratch>), String> {
    match store {
        Some(p) => Ok((p, None)),
        None => {
            let held = blue_lang_runtime::scratch::Scratch::new("arika-store")
                .map_err(|e| format!("a scratch store: {e}"))?;
            Ok((held.path().join("store.jsonl"), Some(held)))
        }
    }
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
    id_of_hex(word, &hash.hex())
}

fn id_of_hex(word: &str, hex: &str) -> String {
    format!("blue:{REPO}:{word}@{}", hex.get(..12).unwrap_or(hex))
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

struct Ours {
    hash: Option<String>,
    written: Option<String>,
}

struct HomeDef {
    file: String,
    line: usize,
    def_hash: Option<String>,
    written: Option<String>,
}

fn engine_home(home: &Result<Home, String>, bare: &str) -> Result<HomeDef, String> {
    let home = home.as_ref().map_err(Clone::clone)?;
    let found = home
        .computed
        .iter()
        .find(|s| {
            s.name() == bare
                && home.checked.program.owner_of(s.top_level) == Some(ResolvedProgram::ENTRY)
        })
        .ok_or_else(|| format!("{} defines no `{bare}`", home.file.display()))?;
    let start = home.checked.program.forms()[found.top_level].span.start;
    let text = home
        .checked
        .program
        .file(ResolvedProgram::ENTRY)
        .map(|f| f.text.to_string())
        .unwrap_or_default();
    Ok(HomeDef {
        file: home.file.display().to_string(),
        line: line_of(&text, start),
        def_hash: home.hashes.at(found.top_level).map(|d| d.hash.hex()),
        written: shape_at(&home.written, found.top_level).map(|s| s.hash.hex()),
    })
}

fn bare_hex(v: &Json) -> Option<String> {
    v.as_str()
        .map(|h| h.strip_prefix("b3:").unwrap_or(h).to_string())
}

fn snapshot_home(snapshot: &Snapshot, word: &str) -> Result<HomeDef, String> {
    let leaf = format!(
        "{}.b",
        word.rsplit_once("::")
            .map_or(word, |(p, _)| p.rsplit_once('/').map_or(p, |(_, l)| l))
    );
    let rows: Vec<&Json> = snapshot
        .by_word
        .get(word)
        .map(|rs| rs.iter().filter(|r| r["kind"] == "function").collect())
        .unwrap_or_default();
    let row = rows
        .iter()
        .find(|r| {
            r["file"]
                .as_str()
                .and_then(|f| Path::new(f).file_name())
                .is_some_and(|n| n == leaf.as_str())
        })
        .or_else(|| rows.first())
        .ok_or_else(|| format!("{} holds no `{word}`", snapshot.path.display()))?;
    Ok(HomeDef {
        file: snapshot
            .dir()
            .join(row["file"].as_str().unwrap_or_default())
            .display()
            .to_string(),
        line: row["line"]
            .as_u64()
            .and_then(|l| usize::try_from(l).ok())
            .unwrap_or_default(),
        def_hash: bare_hex(&row["def_hash"]),
        written: bare_hex(&row["written_shape"]),
    })
}

fn hit(word: &str, foundation: bool, ours: &Ours, home: Result<HomeDef, String>) -> Json {
    let (package, bare) = word.rsplit_once("::").unwrap_or(("", word));
    let mut b = json!({
        "word": word,
        "package": package,
        "name": bare,
        "foundation": foundation,
        "fix": if foundation { "import" } else { "move_down" },
    });
    let home = match home {
        Ok(h) => h,
        Err(why) => {
            b["tier"] = json!("T2");
            b["home"] = json!({"outcome": "blind", "why": why});
            return b;
        }
    };
    let exact = matches!((&ours.hash, &home.def_hash), (Some(a), Some(b)) if a == b);
    let written = matches!((&ours.written, &home.written), (Some(a), Some(b)) if a == b);
    b["tier"] = json!(tier(exact, written));
    b["id"] = home
        .def_hash
        .as_ref()
        .map_or(Json::Null, |h| json!(id_of_hex(word, h)));
    b["home"] = json!({
        "outcome": "found",
        "file": home.file,
        "line": home.line,
        "def_hash": home.def_hash,
    });
    b
}

pub struct Snapshot {
    pub path: PathBuf,
    pub root: String,
    pub rows: Vec<Json>,
    pub by_word: BTreeMap<String, Vec<Json>>,
}

impl Snapshot {
    /// # Errors
    ///
    /// A header or facts file that cannot be read, or a header that is not an
    /// arika header.
    pub fn read(header: &Path, facts: &Path) -> Result<Self, String> {
        let text =
            std::fs::read_to_string(header).map_err(|e| format!("{}: {e}", header.display()))?;
        let doc: Json =
            serde_json::from_str(&text).map_err(|e| format!("{}: {e}", header.display()))?;
        if doc["format"] != FORMAT {
            return Err(format!("{} is not an {FORMAT} header", header.display()));
        }
        let lines =
            std::fs::read_to_string(facts).map_err(|e| format!("{}: {e}", facts.display()))?;
        let rows = lines
            .lines()
            .filter(|l| !l.is_empty())
            .map(|l| serde_json::from_str(l).map_err(|e| format!("{}: {e}", facts.display())))
            .collect::<Result<Vec<Json>, String>>()?;
        let mut by_word: BTreeMap<String, Vec<Json>> = BTreeMap::new();
        for row in &rows {
            if let Some(w) = row["word"].as_str() {
                by_word.entry(w.to_string()).or_default().push(row.clone());
            }
        }
        Ok(Snapshot {
            path: header.to_path_buf(),
            root: doc["snapshot_root"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
            rows,
            by_word,
        })
    }

    fn dir(&self) -> PathBuf {
        self.path
            .parent()
            .map_or_else(PathBuf::new, Path::to_path_buf)
    }

    fn check(&self) -> String {
        json!({"root": self.root, "rows": self.rows}).to_string()
    }
}

pub const FORMAT: &str = "arika/1";

#[must_use]
pub fn like_facts(draft: &Draft, snapshot: Option<&Snapshot>) -> Json {
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
            hash: hashes.at(s.top_level).map(|d| d.hash.hex()),
            written: shape_at(&written, s.top_level).map(|w| w.hash.hex()),
        };
        let hits = match standing(&s.hash, &s.key) {
            Standing::CopyOf { word, foundation } => {
                let home = match snapshot {
                    Some(snap) => snapshot_home(snap, word),
                    None => {
                        let package = word.rsplit_once("::").map_or(word, |(p, _)| p).to_string();
                        let (_, bare) = word.rsplit_once("::").unwrap_or(("", word));
                        let home = homes
                            .entry(package.clone())
                            .or_insert_with(|| load_home(&environment, &draft.path, &package));
                        engine_home(home, bare)
                    }
                };
                vec![hit(word, foundation, &ours, home)]
            }
            Standing::OwnWord | Standing::NoWord => Vec::new(),
        };
        defs.push(json!({
            "name": s.name(),
            "line": first,
            "size": s.size,
            "def_hash": ours.hash,
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
    let mut out = json!({"outcome": outcome, "file": file, "line": draft.line, "defs": defs});
    if let Some(snap) = snapshot {
        out["snapshot_root"] = json!(snap.root);
    }
    out
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

fn foundation_packages() -> BTreeSet<&'static str> {
    WORD_SHAPES
        .iter()
        .filter(|(_, _, f)| *f)
        .filter_map(|(_, w, _)| w.rsplit_once("::").map(|(p, _)| p))
        .collect()
}

#[must_use]
pub fn word_facts_from(name: &str, snapshot: &Snapshot) -> Json {
    let foundation = foundation_packages();
    let mut words = Vec::new();
    let mut moves = Vec::new();
    let mut glosses = Vec::new();
    for (word, rows) in &snapshot.by_word {
        let package = word.rsplit_once("::").map_or("", |(p, _)| p);
        words.push(json!({"word": word, "foundation": foundation.contains(package)}));
        let Some(row) = rows.first() else { continue };
        if let Some(gloss) = row["gloss"].as_str() {
            glosses.push(json!({"word": word, "gloss": gloss}));
        }
        for old in row["legacy"].as_array().into_iter().flatten() {
            moves.push(json!({"old": old["old"], "word": word, "since": old["since"]}));
        }
    }
    json!({
        "query": name,
        "words": words,
        "moves": moves,
        "blind": [],
        "catalog": snapshot.path.display().to_string(),
        "glosses": glosses,
        "snapshot_root": snapshot.root,
    })
}

fn rel_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .display()
        .to_string()
}

#[must_use]
pub fn word_of_key(key: &str) -> String {
    key.rsplit_once('/')
        .map_or_else(|| key.to_string(), |(p, n)| format!("{p}::{n}"))
}

fn row_of(
    package: &str,
    file: &str,
    f: &blue_lang_mondou::facts::DefFact,
    links: &blue_lang_mondou::facts::Links,
) -> Json {
    let word = format!("{package}::{}", f.name);
    let calls: Vec<String> = links
        .calls
        .get(&f.top_level)
        .into_iter()
        .flatten()
        .map(|k| word_of_key(k))
        .filter(|w| *w != word)
        .collect();
    json!({
        "calls": calls,
        "reach": links.reach.get(&f.top_level).cloned().unwrap_or_default(),
        "tests": [],
        "id": readable_id(&word, &f.def_hash),
        "word": word,
        "package": package,
        "name": f.name,
        "kind": f.kind_name(),
        "def_hash": f.def_hash.to_string(),
        "shape": f.shape.as_ref().map(|s| s.hash.to_string()),
        "written_shape": f.written_shape.map(|h| h.to_string()),
        "size": f.shape.as_ref().map(|s| s.size),
        "file": file,
        "line": f.line,
        "gloss": f.gloss(),
        "doc": f.doc,
        "legacy": [],
    })
}

fn moved_names(package: &str, text: &str, into: &mut BTreeMap<String, BTreeSet<(String, String)>>) {
    use blue_lang_syntax::scope::{legacy_target, LegacyKind};
    let Ok(forms) = blue_lang_syntax::parse_program_tree(text) else {
        return;
    };
    for legacy in forms.iter().filter_map(legacy_target) {
        if let LegacyKind::Moved(ms) = legacy.kind {
            for m in ms {
                into.entry(format!("{}::{}", m.home, m.new))
                    .or_default()
                    .insert((format!("{package}::{}", m.old), legacy.since.to_string()));
            }
        }
    }
}

#[must_use]
pub fn emit_facts(root: &Path) -> Json {
    let files = blue_lang_pkg::corpus::files(root);
    let environment = crate::census::environment_over(&files);
    let shown = root.display().to_string();
    let mut rows = Vec::new();
    let mut definitions = 0usize;
    let mut outside = 0usize;
    let mut blind = Vec::new();
    let mut legacy: BTreeMap<String, BTreeSet<(String, String)>> = BTreeMap::new();
    let mut tested: BTreeMap<String, BTreeSet<(String, usize, String, bool)>> = BTreeMap::new();
    for path in &files {
        let rel = rel_path(root, path);
        let checked = std::fs::read_to_string(path)
            .map_err(|e| e.to_string())
            .and_then(|text| {
                check_file(path, &text, &environment.load_path(Some(path))).map(|c| (c, text))
            });
        let (checked, text) = match checked {
            Ok(found) => found,
            Err(why) => {
                blind.push(json!({"file": rel, "why": why.replace(&shown, "ROOT")}));
                continue;
            }
        };
        let Some(package) = checked
            .program
            .file(ResolvedProgram::ENTRY)
            .and_then(|f| f.package.clone())
        else {
            outside += 1;
            continue;
        };
        let (entry, links) = blue_lang_mondou::facts::of_entry_linked(&checked);
        definitions += entry.definitions;
        rows.extend(
            entry
                .facts
                .iter()
                .map(|f| row_of(&package, &rel, f, &links)),
        );
        for t in &links.tests {
            for key in &t.names {
                tested.entry(word_of_key(key)).or_default().insert((
                    rel.clone(),
                    t.line,
                    t.name.clone(),
                    t.doc,
                ));
            }
        }
        moved_names(&package, &text, &mut legacy);
    }
    for row in &mut rows {
        let word = row["word"].as_str().unwrap_or_default().to_string();
        if let Some(olds) = legacy.get(&word) {
            row["legacy"] = olds
                .iter()
                .map(|(old, since)| json!({"old": old, "since": since}))
                .collect();
        }
        if let Some(tests) = tested.get(&word) {
            row["tests"] = tests
                .iter()
                .map(|(file, line, name, doc)| {
                    json!({"file": file, "line": line, "name": name, "doc": doc})
                })
                .collect();
        }
    }
    rows.sort_by_cached_key(|r| {
        (
            r["package"].as_str().unwrap_or_default().to_string(),
            r["word"].as_str().unwrap_or_default().to_string(),
            r["file"].as_str().unwrap_or_default().to_string(),
            r["line"].as_u64().unwrap_or_default(),
        )
    });
    json!({
        "repo": REPO,
        "files": files.len(),
        "outside": outside,
        "definitions": definitions,
        "blind": blind,
        "rows": rows,
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
        let facts = like_facts(&draft, None);
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
        ArikaCmd::Like {
            target,
            json,
            snapshot,
            facts,
            ..
        } => {
            let (path, line) = split_target(&target.unwrap_or_default());
            let text =
                std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
            let snapshot = read_snapshot(snapshot, facts)?;
            let answer = like_facts(&Draft { path, text, line }, snapshot.as_ref());
            let mut args = vec!["like".into(), mode(json).into(), answer.to_string()];
            args.extend(snapshot.as_ref().map(Snapshot::check));
            render(args)
        }
        ArikaCmd::Word {
            name,
            json,
            snapshot,
            facts,
        } => {
            let snapshot = read_snapshot(snapshot, facts)?;
            let answer = match &snapshot {
                Some(snap) => word_facts_from(&name, snap),
                None => {
                    let cwd = std::env::current_dir()
                        .map_err(|e| format!("the working directory: {e}"))?;
                    word_facts(&name, &cwd)
                }
            };
            let mut args = vec!["word".into(), mode(json).into(), answer.to_string()];
            args.extend(snapshot.as_ref().map(Snapshot::check));
            render(args)
        }
        ArikaCmd::Emit { root, out, facts } => {
            let emitted = emit_facts(&root);
            let out = out.unwrap_or_else(|| root.join("SNAPSHOT.json"));
            render(vec![
                "emit".into(),
                out.display().to_string(),
                emitted.to_string(),
                facts.map(|f| f.display().to_string()).unwrap_or_default(),
            ])
        }
        ArikaCmd::Find {
            text,
            limit,
            json,
            from,
        } => over_facts("find", json, &json!({"text": text, "limit": limit}), &from),
        ArikaCmd::Get { word, json, from } => {
            over_facts("get", json, &json!({"word": word}), &from)
        }
        ArikaCmd::Uses { word, json, from } => {
            over_facts("uses", json, &json!({"word": word}), &from)
        }
        ArikaCmd::Why { word, json, from } => {
            over_facts("why", json, &json!({"word": word}), &from)
        }
        ArikaCmd::Groups { min, json, from } => {
            over_facts("groups", json, &json!({"min": min}), &from)
        }
        ArikaCmd::Changed {
            package,
            since,
            json,
            from,
        } => over_facts(
            "changed",
            json,
            &json!({"package": package, "since": since.display().to_string()}),
            &from,
        ),
        ArikaCmd::Golden { file, json, from } => {
            let text =
                std::fs::read_to_string(&file).map_err(|e| format!("{}: {e}", file.display()))?;
            let questions: Vec<Json> = text
                .lines()
                .filter(|l| !l.trim().is_empty() && !l.starts_with('#'))
                .map(|l| {
                    l.split_once('\t').map_or_else(
                        || Err(format!("{}: `{l}` is not intent<TAB>word", file.display())),
                        |(intent, word)| Ok(json!([intent, word])),
                    )
                })
                .collect::<Result<_, _>>()?;
            over_facts("golden", json, &json!({"questions": questions}), &from)
        }
        ArikaCmd::Ask {
            question,
            json,
            store,
            from,
        } => {
            let (store, _held) = scratch_store(store)?;
            over_facts(
                "ask",
                json,
                &json!({"question": question, "store": store.display().to_string(), "rules": rules()}),
                &from,
            )
        }
        ArikaCmd::Quads { out, from } => over_facts(
            "quads",
            false,
            &json!({"out": out.display().to_string(), "rules": rules()}),
            &from,
        ),
        ArikaCmd::Tools => render(vec!["tools".into()]),
        ArikaCmd::Mcp { request, from } => {
            let request: Json =
                serde_json::from_str(&request).map_err(|e| format!("REQUEST is not JSON: {e}"))?;
            let (store, _held) = scratch_store(None)?;
            over_facts(
                "mcp",
                true,
                &json!({"request": request, "store": store.display().to_string(), "rules": rules()}),
                &from,
            )
        }
        ArikaCmd::Serve { addr, store, from } => {
            let (store, _held) = scratch_store(store)?;
            over_facts(
                "serve",
                false,
                &json!({"addr": addr, "store": store.display().to_string(), "rules": rules()}),
                &from,
            )
        }
    }
}

fn read_snapshot(
    snapshot: Option<PathBuf>,
    facts: Option<PathBuf>,
) -> Result<Option<Snapshot>, String> {
    match (snapshot, facts) {
        (Some(header), Some(facts)) => Snapshot::read(&header, &facts).map(Some),
        _ => Ok(None),
    }
}
