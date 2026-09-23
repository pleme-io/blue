//! The Bluefile: a manifest that is a blue program.
//!
//! ```text
//! package("myapp", "0.1.0")
//! needs("gaming", "^1.2")
//! needs("audio", ">=0.4.0")
//! posture(when: "preceding")
//! ```
//!
//! ## Why evaluation rather than a second parser
//!
//! Reading this file *is* running it: `package`, `needs` and `posture` are
//! primitives installed into a blue interpreter, and what they record is the
//! manifest. There is no Bluefile grammar, no TOML dialect, and nothing that
//! can drift from the language.
//!
//! The payoff is not tidiness. It means a manifest can **compute** — a version
//! from a variable, a dependency list from a macro, a conditional dependency
//! from an `if` — using the language the project is already written in, with the
//! same formatter and the same diagnostics.
//!
//! ## The cost, and the frame that pays it
//!
//! Evaluating a manifest is executing code. That is fine for a project's own
//! Bluefile, and the same is true of `Rakefile`, `build.rs` and `setup.py`. But
//! **resolving a dependency runs the dependency's code**: `GitRegistry` reads a
//! `Bluefile` out of every package on `BLUE_PATH`, and reading it is running
//! it.
//!
//! This module used to end that paragraph with "blue's answer is the `waku`
//! frame … **and that restriction is not wired here yet.** Until it is, only
//! read Bluefiles you would run." It is wired now: [`manifest_frame`] is the
//! frame a manifest evaluates in, and [`read_bluefile`] checks the manifest's
//! forms against it **before** the interpreter sees them.
//!
//! **What that buys, stated precisely — and the previous statement of it was
//! measurably wrong.** This paragraph used to read: *"Nothing dangerous is
//! bound in the manifest interpreter today — it is `interpreter_hostless` plus
//! three recording primitives — so the manifest was safe by absence of a
//! binding."* Measured 2026-08-13, the first clause is false.
//! `interpreter_hostless` is a fork of a base built by `interpreter(&mut ())`,
//! and `interpreter` installs the sys layer under `#[cfg(feature = "sys")]` —
//! so **whenever that feature is on, "hostless" binds all 37 host primitives**,
//! `read_file` and `rm_rf` among them. `blue-lang-cli` turns it on for itself,
//! and cargo unifies features across a workspace build, so it is on for this
//! crate's own `cargo test --workspace` run.
//! `blue-lang-cli/tests/capability_surface.rs` pins that as a measurement.
//!
//! **The manifest is still safe, by the frame rather than by absence** — which
//! is why this correction matters rather than merely being tidy. The old
//! reading credited a property the build does not have and treated the frame as
//! belt-and-braces; in fact the frame is the only thing standing between a
//! third-party Bluefile and `rm_rf`. A name outside the declared vocabulary is
//! refused before the interpreter is built, so installing a capability without
//! naming it in the frame is a **failing test**, not a quiet grant.
//!
//! **Honest tier: parse-time-rejected at this boundary, and no further.** A
//! [`Bluefile`] cannot be constructed from a manifest that escapes the frame,
//! and this is its only constructor. The check itself is `check_reach` over a
//! tree — a manifest that built a name at run time and `eval`d it would be
//! outside what the tree shows, which is what `When` tracks and this does not.
//! It is not unrepresentability: the escape is a `Result::Err`, not an absent
//! code path.
//!
//! **What is still missing, so nobody cites this as more than it is.** The
//! frame is a constant blue fixes, not something a manifest declares.
//!
//! **Half of the reason it could not be declared is gone as of 2026-08-13.**
//! This paragraph said a declared `Reach` *"needs a closed capability universe
//! to declare over, and blue has none — `Reach::Only` still takes arbitrary
//! strings."* `theory/BLUE-EXECUTION.md` M0 built that universe:
//! [`blue_lang_waku::Capability`] is closed, so `posture(reach: …)` now has an
//! enumerable vocabulary to accept and a misspelling in it would be a parse
//! failure rather than a silent grant of nothing.
//!
//! **`posture` still accepts only the `when` coordinate, and that is now a
//! plain to-do rather than a blocked design.** Accepting a `reach` means
//! deciding what a manifest keyword looks like and how a *dependency's*
//! declaration composes with the root's ceiling, which is bīdama's question,
//! not this module's. Recorded here so the next reader does not re-derive the
//! old blocker and conclude it is still there.
//!
//! ## The vocabulary is the whole build (`theory/BLUE-STRUCTURE.md` §5.5)
//!
//! A blue project writes no nix. Every fact a hand-written flake used to state
//! is a word here, recorded into [`Project`] and printed by
//! `blue bluefile --json`:
//!
//! | Word | Records |
//! |---|---|
//! | `source(name, url, dir)` | a named external distribution root |
//! | `packages(dir)` | a local package root |
//! | `run(name, file[, reads])` | a program run as its own cached derivation |
//! | `tool(name)` | a nixpkgs attribute on PATH for runs, checks and apps |
//! | `check(name, file)` | a test file run as a check |
//! | `app(name, file)` | a program exposed as `nix run .#name` |
//! | `catalog(path)` | the mokuroku catalogue of `packages`, gated fresh |
//!
//! The words are FACTS, never nix expressions (§5.3 stands): one engine lowers
//! them. **The table is [`WORDS`], and it is the only place a word is defined**
//! — its arity, its signature and what it records. Every call is checked
//! against it before anything is recorded, so a malformed call is a typed
//! [`Malformed`] rather than the silent drop `package` and `needs` used to
//! perform on a non-string argument.

use std::collections::btree_map::Entry;
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use blue_lang_waku::{check_reach_program, Capability, Waku, When};
use serde::{Deserialize, Serialize};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::solve::Manifest;
use crate::version::{Range, Version};

/// The file a package's manifest lives in.
pub const MANIFEST_FILE: &str = "Bluefile";

/// What a Bluefile declared.
#[derive(Clone, Debug, PartialEq)]
pub struct Bluefile {
    pub name: String,
    pub version: Version,
    pub manifest: Manifest,
    /// The least frame this package needs — its bīdama floor.
    pub floor: Waku,
    /// Every other fact the project states about its build — §5.5's words.
    pub project: Project,
}

/// The project facts a Bluefile records beyond its identity, needs and floor.
///
/// **These field names ARE the JSON keys** `blue bluefile --json` prints and
/// `Bluefile.lock` carries, so the nix side reads exactly what is declared
/// here. Named things are maps keyed by the author's name — which is also the
/// name `nix build .#<name>` will use — and a second declaration of one name is
/// [`Malformed::Duplicate`], never a silent overwrite.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Project {
    /// `source(name, url, dir)`.
    pub sources: BTreeMap<String, Source>,
    /// `packages(dir)`, in declaration order — the order a load path searches.
    pub packages: Vec<String>,
    /// `run(name, file[, reads])`.
    pub runs: BTreeMap<String, Run>,
    /// `tool(name)`, in declaration order.
    pub tools: Vec<String>,
    /// `check(name, file)`.
    pub checks: BTreeMap<String, Program>,
    /// `app(name, file)`.
    pub apps: BTreeMap<String, Program>,
    /// `catalog(path)` — where the catalogue of `packages` is committed.
    pub catalog: Option<String>,
    /// `generate(name, output, program)`: a committed file a blue program
    /// writes. Skipped when empty, so the locks of packages that generate
    /// nothing keep their bytes.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub generated: BTreeMap<String, Generated>,
}

/// A committed file that a blue program writes: the program writes to
/// `$GEN_OUT`, nix gates the committed copy's freshness against a fresh run,
/// and `nix run .#regen` rewrites it in place. One declaration, three uses.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Generated {
    /// Where the file is committed, relative to the Bluefile.
    pub output: String,
    /// The blue program that writes it, relative to the Bluefile.
    pub program: String,
}

/// A named external distribution root: where to fetch it, and which directory
/// inside it holds the packages. The pin lives in `Bluefile.lock`, not here —
/// a Bluefile states intent, the lock states the revision.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Source {
    pub url: String,
    pub dir: String,
}

/// A program run as its own cached derivation.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Run {
    pub file: String,
    /// The runs whose outputs this one reads. Every name must be a declared
    /// run, and the graph must be acyclic — both checked at read time.
    pub reads: Vec<String>,
}

/// A program a check or an app runs.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Program {
    pub file: String,
}

#[derive(Debug, thiserror::Error)]
pub enum BluefileError {
    #[error("parse error: {0}")]
    Parse(String),
    #[error("error evaluating the Bluefile: {0}")]
    Eval(String),
    /// A Bluefile with no `package(...)` call. Rejected rather than defaulted:
    /// a manifest that silently names itself `""` at version `0.0.0` resolves,
    /// and then nothing downstream can tell it apart from a real one.
    #[error("this Bluefile never calls `package(name, version)`")]
    NoPackage,
    #[error("{0}")]
    Version(#[from] crate::version::VersionError),
    #[error("`{0}` is not a recognised `when` posture (sealed, preceding, anytime)")]
    BadWhen(String),
    /// The manifest named something [`manifest_frame`] does not permit.
    ///
    /// Reported before evaluation, and carrying **every** escaping name rather
    /// than the first: a manifest author fixing one wants to see the rest, and
    /// a reviewer reading a refusal wants the whole set the package asked for.
    #[error(
        "this Bluefile names {} outside the manifest frame: {}. \
         A manifest may use the vocabulary in `blue_lang_pkg::bluefile::manifest_frame`; \
         widening it is a deliberate edit there, not something a manifest can ask for.",
        if .names.len() == 1 { "a name" } else { "names" },
        .names.join(", ")
    )]
    Escapes { names: Vec<String> },
    /// A word was called wrongly — see [`Malformed`].
    #[error("{0}")]
    Malformed(#[from] Malformed),
    /// A `run` reads a run the Bluefile never declares. The engine would have
    /// nothing to wire the edge to.
    #[error("run `{run}` reads `{missing}`, which no `run(...)` in this Bluefile declares")]
    UnknownRead { run: String, missing: String },
    /// Runs that read each other in a cycle — no order can build them.
    #[error("runs read each other in a cycle: {}", .cycle.join(" -> "))]
    RunCycle { cycle: Vec<String> },
    /// `catalog(...)` catalogues the `packages(...)` roots; with none there is
    /// nothing to catalogue, and an empty catalogue would pass its own gate.
    #[error(
        "`catalog(...)` catalogues the `packages(...)` roots, and this Bluefile declares none"
    )]
    CatalogWithoutPackages,
}

/// A call to a manifest word that does not match the word's signature.
///
/// Each arm names the word, because a manifest error that says only "type
/// mismatch" sends the author hunting through every call in the file.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum Malformed {
    #[error("`{word}` is called as `{signature}`; this call passes {got} argument(s)")]
    Arity {
        word: &'static str,
        signature: &'static str,
        got: usize,
    },
    #[error("`{word}`: `{param}` must be {expected}, got {got}")]
    Type {
        word: &'static str,
        param: &'static str,
        expected: &'static str,
        got: &'static str,
    },
    /// A path argument that is absolute or climbs out of the project. The
    /// engine reads every path relative to the project root, and a path that
    /// leaves it would make the build read what the project does not contain.
    #[error("`{word}`: `{param}` must be a relative path inside the project, got `{got}`")]
    Path {
        word: &'static str,
        param: &'static str,
        got: String,
    },
    #[error("`{word}` declares `{name}` twice")]
    Duplicate { word: &'static str, name: String },
}

/// The frame a Bluefile is evaluated in.
///
/// `When::Preceding` because a manifest is read top to bottom and nothing in it
/// should need a resident evaluator; `Where::Process` because it computes in
/// its own heap. The `Reach` is the manifest vocabulary: **four capabilities,
/// none of them a host effect**, so `imports_of(manifest_frame())` is empty and
/// a manifest opens nothing.
///
/// `Capability::Collections` joined on 2026-09-23 (P1b) for one reason:
/// `run(name, file, reads)` takes a LIST of run names, and `["a", "b"]` lowers
/// to `list`. It also grants the map constructor; both are pure, so the frame
/// still derives no import.
///
/// **The three name lists this function used to own moved into
/// [`blue_lang_waku::Capability`] when M0 closed the universe**, and the move is
/// the point rather than tidying: a vocabulary spelled out here was a set of
/// strings only this function could interpret, so nothing else could ask what a
/// frame grants. `Capability::ManifestDeclaration` still means exactly
/// `package`/`needs`/`posture`, `Capability::CoreForms` still means the nine
/// control-flow heads, and `Capability::Operators` is still *read from*
/// `blue_lang_syntax::INFIX` rather than copied out of it — the repo's rule that
/// `INFIX` is one table and both directions read it, now one level up.
///
/// Deliberately small. A manifest that wants `map` over a dependency list is
/// refused, and that is the design: widening the vocabulary a third party's
/// code may name is an edit to this function, reviewed once, rather than
/// something any manifest can help itself to.
#[must_use]
pub fn manifest_frame() -> Waku {
    Waku::macro_phase([
        Capability::ManifestDeclaration,
        Capability::CoreForms,
        Capability::Operators,
        Capability::Collections,
    ])
}

/// What the primitives record while the manifest runs.
#[derive(Default)]
struct Collected {
    package: Option<(String, String)>,
    needs: BTreeMap<String, String>,
    when: Option<String>,
    project: Project,
    /// The first malformed call. Recorded here as well as raised, so the typed
    /// error survives the trip through the evaluator's untyped `EvalError`.
    malformed: Option<Malformed>,
}

type Shared = Arc<Mutex<Collected>>;

/// One word of the manifest vocabulary.
struct Word {
    name: &'static str,
    /// How an author calls it — quoted in every arity error.
    signature: &'static str,
    min: usize,
    max: usize,
    /// What the word records. Runs only after the arity is checked, and reads
    /// its arguments through [`Call`], which types each one.
    record: fn(&Call<'_>, &mut Collected) -> Result<(), Malformed>,
}

/// **The vocabulary — the one place a manifest word is defined.**
///
/// `the_word_table_is_the_manifest_capability` pins these names against
/// `Capability::ManifestDeclaration` in both directions: a name the frame
/// grants with no row here would pass the frame and die unbound, and a row the
/// frame does not grant could never be called.
const WORDS: &[Word] = &[
    Word {
        name: "package",
        signature: "package(name, version)",
        min: 2,
        max: 2,
        record: |c, into| {
            let name = c.text(0, "name")?;
            let version = c.text(1, "version")?;
            set_once(&mut into.package, c.word, name.clone(), (name, version))
        },
    },
    Word {
        name: "needs",
        signature: "needs(name, range)",
        min: 2,
        max: 2,
        record: |c, into| {
            let name = c.text(0, "name")?;
            let range = c.text(1, "range")?;
            insert_once(&mut into.needs, c.word, name, range)
        },
    },
    Word {
        name: "posture",
        signature: "posture(when)",
        min: 1,
        max: 1,
        record: |c, into| {
            let when = c.label(0, "when")?;
            set_once(&mut into.when, c.word, when.clone(), when)
        },
    },
    Word {
        name: "source",
        signature: "source(name, url, dir)",
        min: 3,
        max: 3,
        record: |c, into| {
            let name = c.text(0, "name")?;
            let source = Source {
                url: c.text(1, "url")?,
                dir: c.path(2, "dir")?,
            };
            insert_once(&mut into.project.sources, c.word, name, source)
        },
    },
    Word {
        name: "packages",
        signature: "packages(dir)",
        min: 1,
        max: 1,
        record: |c, into| push_once(&mut into.project.packages, c.word, c.path(0, "dir")?),
    },
    Word {
        name: "run",
        signature: "run(name, file[, reads])",
        min: 2,
        max: 3,
        record: |c, into| {
            let name = c.text(0, "name")?;
            let run = Run {
                file: c.path(1, "file")?,
                reads: if c.args.len() > 2 {
                    c.names(2, "reads")?
                } else {
                    Vec::new()
                },
            };
            insert_once(&mut into.project.runs, c.word, name, run)
        },
    },
    Word {
        name: "tool",
        signature: "tool(name)",
        min: 1,
        max: 1,
        record: |c, into| push_once(&mut into.project.tools, c.word, c.text(0, "name")?),
    },
    Word {
        name: "check",
        signature: "check(name, file)",
        min: 2,
        max: 2,
        record: |c, into| {
            let name = c.text(0, "name")?;
            let program = Program {
                file: c.path(1, "file")?,
            };
            insert_once(&mut into.project.checks, c.word, name, program)
        },
    },
    Word {
        name: "app",
        signature: "app(name, file)",
        min: 2,
        max: 2,
        record: |c, into| {
            let name = c.text(0, "name")?;
            let program = Program {
                file: c.path(1, "file")?,
            };
            insert_once(&mut into.project.apps, c.word, name, program)
        },
    },
    Word {
        name: "generate",
        signature: "generate(name, output, program)",
        min: 3,
        max: 3,
        record: |c, into| {
            let name = c.text(0, "name")?;
            let generated = Generated {
                output: c.path(1, "output")?,
                program: c.path(2, "program")?,
            };
            insert_once(&mut into.project.generated, c.word, name, generated)
        },
    },
    Word {
        name: "catalog",
        signature: "catalog(path)",
        min: 1,
        max: 1,
        record: |c, into| {
            let path = c.path(0, "path")?;
            set_once(&mut into.project.catalog, c.word, path.clone(), path)
        },
    },
];

/// One call to a word, with typed access to its arguments.
struct Call<'a> {
    word: &'static str,
    args: &'a [Value],
}

impl Call<'_> {
    fn type_error(&self, i: usize, param: &'static str, expected: &'static str) -> Malformed {
        Malformed::Type {
            word: self.word,
            param,
            expected,
            got: self.args[i].type_name(),
        }
    }

    /// A string argument.
    fn text(&self, i: usize, param: &'static str) -> Result<String, Malformed> {
        match &self.args[i] {
            Value::Str(s) => Ok(s.to_string()),
            _ => Err(self.type_error(i, param, "a string")),
        }
    }

    /// A string or a keyword — `posture("sealed")` and `posture(:sealed)`.
    fn label(&self, i: usize, param: &'static str) -> Result<String, Malformed> {
        match &self.args[i] {
            Value::Str(s) | Value::Keyword(s) => Ok(s.to_string()),
            _ => Err(self.type_error(i, param, "a string or a keyword")),
        }
    }

    /// A string naming a path relative to the project root.
    fn path(&self, i: usize, param: &'static str) -> Result<String, Malformed> {
        let text = self.text(i, param)?;
        let p = std::path::Path::new(&text);
        let inside = !text.is_empty()
            && p.components().all(|c| {
                matches!(
                    c,
                    std::path::Component::Normal(_) | std::path::Component::CurDir
                )
            });
        if inside {
            Ok(text)
        } else {
            Err(Malformed::Path {
                word: self.word,
                param,
                got: text,
            })
        }
    }

    /// A list of strings.
    fn names(&self, i: usize, param: &'static str) -> Result<Vec<String>, Malformed> {
        let expected = "a list of strings";
        let Value::List(items) = &self.args[i] else {
            return Err(self.type_error(i, param, expected));
        };
        items
            .iter()
            .map(|v| match v {
                Value::Str(s) => Ok(s.to_string()),
                _ => Err(self.type_error(i, param, expected)),
            })
            .collect()
    }
}

/// Record a single-valued fact, refusing a second declaration.
fn set_once<T>(
    slot: &mut Option<T>,
    word: &'static str,
    name: String,
    value: T,
) -> Result<(), Malformed> {
    if slot.is_some() {
        return Err(Malformed::Duplicate { word, name });
    }
    *slot = Some(value);
    Ok(())
}

/// Record a named fact, refusing a second declaration of the name.
fn insert_once<V>(
    map: &mut BTreeMap<String, V>,
    word: &'static str,
    name: String,
    value: V,
) -> Result<(), Malformed> {
    match map.entry(name) {
        Entry::Vacant(e) => {
            e.insert(value);
            Ok(())
        }
        Entry::Occupied(e) => Err(Malformed::Duplicate {
            word,
            name: e.key().clone(),
        }),
    }
}

/// Record an ordered fact, refusing a repeat.
fn push_once(list: &mut Vec<String>, word: &'static str, value: String) -> Result<(), Malformed> {
    if list.contains(&value) {
        return Err(Malformed::Duplicate { word, name: value });
    }
    list.push(value);
    Ok(())
}

/// The `when` coordinate as a Bluefile spells it. Exhaustive, no wildcard —
/// the parse below reads this function rather than a second spelling table, so
/// a posture cannot be written one way and recorded another.
#[must_use]
pub fn when_label(when: When) -> &'static str {
    match when {
        When::Sealed => "sealed",
        When::Preceding => "preceding",
        When::Anytime => "anytime",
    }
}

fn parse_when(text: &str) -> Option<When> {
    [When::Sealed, When::Preceding, When::Anytime]
        .into_iter()
        .find(|w| when_label(*w) == text)
}

/// Read a Bluefile from blue source.
pub fn read_bluefile(src: &str) -> Result<Bluefile, BluefileError> {
    // The SPANNED door, because erasure runs on spans now. A manifest reports
    // no positions of its own, so nothing here spends them — but taking the
    // spanless door would mean lifting back to `Spanned` before evaluation,
    // and that lift is the `Span::synthetic()` stamp the pipeline just stopped
    // paying.
    let forms = blue_lang_syntax::parse_program_tree(src)
        .map_err(|e| BluefileError::Parse(e.to_string()))?;
    let collected: Shared = Arc::new(Mutex::new(Collected::default()));

    let erased = blue_lang_runtime::erase_types(&forms);

    // THE FRAME, checked BEFORE the interpreter exists.
    //
    // Before evaluation and not during it, because the point is that a
    // manifest which names something outside the vocabulary never runs at all
    // — not that it runs until it reaches the bad call. `package("m","1.0.0")`
    // followed by an escaping call would otherwise have recorded the package
    // first.
    //
    // `check_reach_program` reads the spanless tree; the projection is the one
    // place this function throws a position away, and it throws none the
    // evaluation below needs.
    let escapes = check_reach_program(&manifest_frame(), &blue_lang_runtime::to_sexps(&erased));
    if !escapes.is_empty() {
        return Err(BluefileError::Escapes {
            names: escapes.into_iter().map(|e| e.name).collect(),
        });
    }

    let mut interp = blue_lang_runtime::interpreter_hostless();
    install_manifest_primitives(&mut interp, &collected);

    let evaluated = interp.eval_program(&erased, &mut ());
    let c = std::mem::take(&mut *collected.lock().expect("manifest lock"));
    // The typed malformation first: it is the REASON evaluation stopped, and
    // the `EvalError` it travelled as is the same fact with its type erased.
    if let Some(m) = c.malformed {
        return Err(m.into());
    }
    evaluated.map_err(|e| BluefileError::Eval(e.to_string()))?;

    let (name, version_text) = c.package.ok_or(BluefileError::NoPackage)?;
    let version = Version::parse(&version_text)?;

    let mut needs = BTreeMap::new();
    for (dep, range_text) in &c.needs {
        needs.insert(dep.clone(), Range::parse(range_text)?);
    }

    // The floor starts at the TOP and is lowered by declaration — a package
    // that declares nothing needs nothing restricted. Starting at the bottom
    // would make every unannotated package demand a sealed evaluator.
    let mut floor = Waku::top();
    if let Some(w) = &c.when {
        floor.when = parse_when(w).ok_or_else(|| BluefileError::BadWhen(w.clone()))?;
    }

    check_project(&c.project)?;

    Ok(Bluefile {
        name,
        version,
        manifest: Manifest { needs },
        floor,
        project: c.project,
    })
}

/// The facts that span more than one call, checked once the whole manifest
/// has run — a `run` may read one declared further down the file.
fn check_project(project: &Project) -> Result<(), BluefileError> {
    if project.catalog.is_some() && project.packages.is_empty() {
        return Err(BluefileError::CatalogWithoutPackages);
    }
    for (name, run) in &project.runs {
        if let Some(missing) = run.reads.iter().find(|r| !project.runs.contains_key(*r)) {
            return Err(BluefileError::UnknownRead {
                run: name.clone(),
                missing: missing.clone(),
            });
        }
    }
    // Depth-first, three-coloured: `open` is the current path, so reaching an
    // open run again IS the cycle, and the path from it is what gets reported.
    fn visit<'a>(
        name: &'a str,
        runs: &'a BTreeMap<String, Run>,
        done: &mut std::collections::BTreeSet<&'a str>,
        open: &mut Vec<&'a str>,
    ) -> Option<Vec<String>> {
        if done.contains(name) {
            return None;
        }
        if let Some(at) = open.iter().position(|n| *n == name) {
            let mut cycle: Vec<String> = open[at..].iter().map(|n| (*n).to_string()).collect();
            cycle.push(name.to_string());
            return Some(cycle);
        }
        open.push(name);
        let reads = runs
            .get(name)
            .map(|r| r.reads.as_slice())
            .unwrap_or_default();
        for read in reads {
            if let Some(cycle) = visit(read, runs, done, open) {
                return Some(cycle);
            }
        }
        open.pop();
        done.insert(name);
        None
    }
    let mut done = std::collections::BTreeSet::new();
    for name in project.runs.keys() {
        if let Some(cycle) = visit(name, &project.runs, &mut done, &mut Vec::new()) {
            return Err(BluefileError::RunCycle { cycle });
        }
    }
    Ok(())
}

/// Bind every word in [`WORDS`] into the manifest interpreter.
///
/// Registered with `Arity::Any` and checked here instead, against the word's
/// own `min`/`max`: tatara's arity refusal is an untyped `EvalError`, and the
/// whole point of the table is that a malformed call comes back as a
/// [`Malformed`] naming the word and its signature.
fn install_manifest_primitives(interp: &mut Interpreter<()>, collected: &Shared) {
    for word in WORDS {
        let slot = collected.clone();
        interp.register_fn(
            word.name,
            Arity::Any,
            move |args: &[Value], _h: &mut (), span| {
                let mut c = slot.lock().map_err(|_| {
                    EvalError::native_fn(word.name, "the manifest recorder was poisoned", span)
                })?;
                let recorded = if (word.min..=word.max).contains(&args.len()) {
                    (word.record)(
                        &Call {
                            word: word.name,
                            args,
                        },
                        &mut c,
                    )
                } else {
                    Err(Malformed::Arity {
                        word: word.name,
                        signature: word.signature,
                        got: args.len(),
                    })
                };
                match recorded {
                    Ok(()) => Ok(Value::Nil),
                    Err(m) => {
                        let raised = EvalError::native_fn(word.name, m.to_string(), span);
                        c.malformed.get_or_insert(m);
                        Err(raised)
                    }
                }
            },
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    const SIMPLE: &str = "package(\"myapp\", \"0.1.0\")\nneeds(\"gaming\", \"^1.2\")";

    /// **The frame did not change when its representation did — and when it
    /// grew, it grew by exactly these names.**
    ///
    /// M0 replaced three hand-written name lists in this file with three
    /// capabilities. The names are spelled out here — independently of the
    /// capability definitions — so a bundle that quietly grew or shrank moves
    /// the manifest vocabulary and fails here rather than widening what a third
    /// party's Bluefile may name.
    ///
    /// **Widened deliberately on 2026-09-23 (`BLUE-STRUCTURE.md` P1b):** the
    /// seven §5.5 words, and `list` plus the map constructor for
    /// `run(name, file, reads)`'s list argument. Every addition is listed by
    /// name below; nothing a host installs joined.
    #[test]
    fn the_manifest_frame_grants_exactly_the_vocabulary_it_always_did() {
        let f = manifest_frame();
        let expected: BTreeSet<&str> = ["package", "needs", "posture"]
            .into_iter()
            // P1b's words, 2026-09-23.
            .chain([
                "source", "packages", "run", "tool", "check", "app", "catalog",
            ])
            // `generate`, 2026-09-23: committed files a blue program writes.
            .chain(["generate"])
            // P1b's list argument, 2026-09-23 — `Capability::Collections`.
            .chain(["list", blue_lang_syntax::LOWERED_MAP])
            .chain([
                "define", "defmacro", "lambda", "let", "begin", "if", "cond", "else", "not",
            ])
            .chain(blue_lang_syntax::INFIX.iter().map(|i| i.callee))
            .collect();

        for name in &expected {
            assert!(
                f.reach.permits(name),
                "the frame stopped permitting `{name}`"
            );
        }
        // And nothing beyond it. Checked against the whole universe rather than
        // a sample, so a fourth capability sneaking into the frame is caught.
        let granted: BTreeSet<&str> = Capability::ALL
            .into_iter()
            .filter(|c| f.reach.grants(*c))
            .flat_map(Capability::names)
            .collect();
        assert_eq!(granted, expected);

        // The manifest opens nothing: no host effect, so no import.
        assert!(blue_lang_waku::imports_of(&f).is_empty());
    }

    /// Anti-vacuity for the frame: it must actually REFUSE the host surface.
    /// A frame that permitted everything would pass every test above.
    #[test]
    fn the_manifest_frame_refuses_the_host_surface() {
        let f = manifest_frame();
        for name in ["read_file", "rm_rf", "exec_capture", "getenv", "now"] {
            assert!(!f.reach.permits(name), "the frame permits `{name}`");
        }
    }

    #[test]
    fn a_bluefile_declares_a_package_and_its_needs() {
        let b = read_bluefile(SIMPLE).expect("read");
        assert_eq!(b.name, "myapp");
        assert_eq!(b.version, Version::new(0, 1, 0));
        assert_eq!(b.manifest.needs["gaming"], Range::parse("^1.2").unwrap());
    }

    /// **The manifest can compute.** This is the point of the Bluefile being a
    /// blue program rather than a data format: the version comes from a
    /// function, and a data format could not express it.
    #[test]
    fn a_manifest_can_compute_its_own_values() {
        let b = read_bluefile(
            "def my_version()\n  \"2.3.4\"\nend\npackage(\"computed\", my_version())",
        )
        .expect("read");
        assert_eq!(b.version, Version::new(2, 3, 4));
    }

    /// And it can use a macro — the same expander a blue program uses, so a
    /// dependency list can be generated.
    #[test]
    fn a_manifest_can_use_a_macro() {
        let b = read_bluefile(
            "defmacro dep(n)\n  quote\n    needs(unquote(n), \"*\")\n  end\nend\n\
             package(\"m\", \"1.0.0\")\ndep(\"one\")\ndep(\"two\")",
        )
        .expect("read");
        assert_eq!(b.manifest.needs.len(), 2);
        assert!(b.manifest.needs.contains_key("one"));
        assert!(b.manifest.needs.contains_key("two"));
    }

    /// And conditionals, which is what a data format forces into a plugin.
    #[test]
    fn a_manifest_can_be_conditional() {
        let b = read_bluefile(
            "package(\"c\", \"1.0.0\")\nif 1 < 2\n  needs(\"yes\", \"*\")\nelse\n  needs(\"no\", \"*\")\nend",
        )
        .expect("read");
        assert!(b.manifest.needs.contains_key("yes"));
        assert!(!b.manifest.needs.contains_key("no"));
    }

    /// **A missing `package` is an error, not a default.** A manifest that
    /// silently names itself `""` at `0.0.0` resolves, and then nothing
    /// downstream can tell it from a real one.
    #[test]
    fn a_bluefile_with_no_package_call_is_rejected() {
        let err = read_bluefile("needs(\"a\", \"*\")").expect_err("must reject");
        assert!(matches!(err, BluefileError::NoPackage), "got {err}");
    }

    #[test]
    fn a_malformed_version_is_reported_as_a_version_error() {
        let err = read_bluefile("package(\"m\", \"not-a-version\")").expect_err("must reject");
        assert!(matches!(err, BluefileError::Version(_)), "got {err}");
    }

    #[test]
    fn a_malformed_range_is_reported() {
        let err =
            read_bluefile("package(\"m\", \"1.0.0\")\nneeds(\"a\", \"~~~\")").expect_err("reject");
        assert!(matches!(err, BluefileError::Version(_)), "got {err}");
    }

    /// **The floor starts at the top and is lowered by declaration.** A package
    /// that declares nothing needs nothing restricted; starting at the bottom
    /// would make every unannotated package demand a sealed evaluator.
    #[test]
    fn an_undeclared_posture_is_the_top_not_the_bottom() {
        let b = read_bluefile(SIMPLE).expect("read");
        assert_eq!(b.floor, Waku::top());
        assert_eq!(b.floor.when, When::Anytime);
    }

    #[test]
    fn a_declared_posture_lowers_the_floor() {
        let b = read_bluefile("package(\"m\", \"1.0.0\")\nposture(\"sealed\")").expect("read");
        assert_eq!(b.floor.when, When::Sealed);
        let b2 = read_bluefile("package(\"m\", \"1.0.0\")\nposture(:preceding)").expect("read");
        assert_eq!(b2.floor.when, When::Preceding, "a keyword works too");
    }

    /// An unknown posture is rejected rather than ignored. An ignored posture
    /// declaration is how a package comes to believe it is sealed when it is
    /// not.
    #[test]
    fn an_unknown_posture_is_rejected_not_ignored() {
        let err =
            read_bluefile("package(\"m\", \"1.0.0\")\nposture(\"whenever\")").expect_err("reject");
        assert!(matches!(err, BluefileError::BadWhen(_)), "got {err}");
    }

    #[test]
    fn a_syntax_error_in_a_bluefile_is_reported_as_one() {
        let err = read_bluefile("package(").expect_err("reject");
        assert!(matches!(err, BluefileError::Parse(_)), "got {err}");
    }

    /// A runtime error in the manifest is reported as such, not swallowed into
    /// a half-built manifest.
    ///
    /// The program has to fail *inside the frame* to reach evaluation at all —
    /// this used to be `no_such_thing()`, which the frame now refuses before
    /// the interpreter exists. It then became `needs("a")`, which is now a
    /// typed [`Malformed::Arity`] (below). Dividing by zero is an operator the
    /// frame grants failing at run time, which keeps the `Eval` arm proven
    /// reachable rather than dead behind two gates.
    #[test]
    fn a_runtime_error_in_a_bluefile_is_reported() {
        let err = read_bluefile("package(\"m\", \"1.0.0\")\nx = 1 / 0").expect_err("reject");
        assert!(matches!(err, BluefileError::Eval(_)), "got {err}");
    }

    // ── the §5.5 vocabulary: every word reads back ────────────────────────

    fn project_of(body: &str) -> Project {
        let src = String::from("package(\"p\", \"0.1.0\")\n") + body;
        read_bluefile(&src)
            .unwrap_or_else(|e| panic!("{body}: {e}"))
            .project
    }

    fn refusal_of(body: &str) -> BluefileError {
        let src = String::from("package(\"p\", \"0.1.0\")\n") + body;
        read_bluefile(&src).expect_err(body)
    }

    #[test]
    fn source_records_a_named_distribution_root() {
        let p = project_of("source(\"blue\", \"github:pleme-io/blue\", \"bidamas\")");
        assert_eq!(
            p.sources["blue"],
            Source {
                url: "github:pleme-io/blue".into(),
                dir: "bidamas".into()
            }
        );
    }

    #[test]
    fn packages_records_local_roots_in_declaration_order() {
        let p = project_of("packages(\"bidamas\")\npackages(\"vendor/extra\")");
        assert_eq!(p.packages, vec!["bidamas", "vendor/extra"]);
    }

    #[test]
    fn run_records_a_program_and_the_runs_it_reads() {
        let p = project_of(
            "run(\"games\", \"src/games.b\")\nrun(\"report\", \"src/report.b\", [\"games\"])",
        );
        assert_eq!(
            p.runs["games"],
            Run {
                file: "src/games.b".into(),
                reads: vec![]
            }
        );
        assert_eq!(p.runs["report"].reads, vec!["games"]);
    }

    /// A run may read one declared further down: the graph is checked once the
    /// whole manifest has run, not call by call.
    #[test]
    fn a_run_may_read_one_declared_later() {
        let p = project_of("run(\"b\", \"b.b\", [\"a\"])\nrun(\"a\", \"a.b\")");
        assert_eq!(p.runs["b"].reads, vec!["a"]);
    }

    #[test]
    fn tool_records_a_nixpkgs_attribute() {
        let p = project_of("tool(\"duckdb\")\ntool(\"jq\")");
        assert_eq!(p.tools, vec!["duckdb", "jq"]);
    }

    #[test]
    fn check_records_a_test_file() {
        let p = project_of("check(\"unit\", \"tests/unit.b\")");
        assert_eq!(p.checks["unit"].file, "tests/unit.b");
    }

    #[test]
    fn app_records_a_program() {
        let p = project_of("app(\"report\", \"bin/report.b\")");
        assert_eq!(p.apps["report"].file, "bin/report.b");
    }

    #[test]
    fn catalog_records_where_the_catalogue_is_committed() {
        let p = project_of("packages(\"bidamas\")\ncatalog(\"bidamas/CATALOG.md\")");
        assert_eq!(p.catalog.as_deref(), Some("bidamas/CATALOG.md"));
    }

    /// And a manifest that says none of it records none of it — the words are
    /// additive, so every existing Bluefile reads exactly as before.
    #[test]
    fn a_bluefile_without_the_new_words_has_an_empty_project() {
        assert_eq!(
            read_bluefile(SIMPLE).expect("read").project,
            Project::default()
        );
    }

    // ── malformed calls are typed, never dropped ──────────────────────────

    /// **The fix this work owed.** `package("m", 1)` used to be dropped in
    /// silence, and the manifest then failed as `NoPackage` — an error about a
    /// call the author DID write.
    #[test]
    fn a_non_string_package_argument_is_malformed_not_dropped() {
        let err = read_bluefile("package(\"m\", 1)").expect_err("reject");
        assert!(
            matches!(
                err,
                BluefileError::Malformed(Malformed::Type {
                    word: "package",
                    param: "version",
                    expected: "a string",
                    got: "int"
                })
            ),
            "got {err}"
        );
    }

    /// `needs(1, "^1")` was the same silent drop: the package resolved with one
    /// dependency fewer than its author wrote.
    #[test]
    fn a_non_string_needs_argument_is_malformed_not_dropped() {
        let err = refusal_of("needs(1, \"^1\")");
        assert!(
            matches!(
                err,
                BluefileError::Malformed(Malformed::Type {
                    word: "needs",
                    param: "name",
                    ..
                })
            ),
            "got {err}"
        );
    }

    #[test]
    fn a_posture_that_is_neither_string_nor_keyword_is_malformed() {
        let err = refusal_of("posture(3)");
        assert!(
            matches!(
                err,
                BluefileError::Malformed(Malformed::Type {
                    word: "posture",
                    ..
                })
            ),
            "got {err}"
        );
    }

    /// Wrong arity names the word AND how it is called.
    #[test]
    fn wrong_arity_is_malformed_and_quotes_the_signature() {
        let err = refusal_of("needs(\"a\")");
        assert_eq!(
            err.to_string(),
            "`needs` is called as `needs(name, range)`; this call passes 1 argument(s)"
        );
        for body in [
            "run(\"a\")",
            "run(\"a\", \"a.b\", [], \"x\")",
            "source(\"a\", \"b\")",
        ] {
            assert!(
                matches!(
                    refusal_of(body),
                    BluefileError::Malformed(Malformed::Arity { .. })
                ),
                "{body}"
            );
        }
    }

    #[test]
    fn reads_must_be_a_list_of_strings() {
        for body in ["run(\"a\", \"a.b\", \"b\")", "run(\"a\", \"a.b\", [1])"] {
            assert!(
                matches!(
                    refusal_of(body),
                    BluefileError::Malformed(Malformed::Type {
                        word: "run",
                        param: "reads",
                        ..
                    })
                ),
                "{body}"
            );
        }
    }

    #[test]
    fn a_path_leaving_the_project_is_malformed() {
        for body in [
            "packages(\"../elsewhere\")",
            "check(\"c\", \"/etc/passwd\")",
            "run(\"r\", \"src/../../x.b\")",
            "catalog(\"\")",
            "generate(\"g\", \"../out.rs\", \"gen/g.b\")",
            "generate(\"g\", \"src/out.rs\", \"/tmp/g.b\")",
        ] {
            assert!(
                matches!(
                    refusal_of(body),
                    BluefileError::Malformed(Malformed::Path { .. })
                ),
                "{body}"
            );
        }
    }

    /// A second declaration is refused, not a silent overwrite of the first —
    /// including `needs`, which used to keep whichever range came last.
    #[test]
    fn a_second_declaration_of_one_name_is_refused() {
        for (body, word) in [
            ("needs(\"a\", \"^1\")\nneeds(\"a\", \"^2\")", "needs"),
            ("tool(\"jq\")\ntool(\"jq\")", "tool"),
            ("run(\"r\", \"a.b\")\nrun(\"r\", \"b.b\")", "run"),
            ("app(\"a\", \"a.b\")\napp(\"a\", \"a.b\")", "app"),
            (
                "generate(\"t\", \"a.rs\", \"a.b\")\ngenerate(\"t\", \"b.rs\", \"b.b\")",
                "generate",
            ),
            ("posture(\"sealed\")\nposture(\"anytime\")", "posture"),
            ("package(\"q\", \"0.2.0\")", "package"),
        ] {
            match refusal_of(body) {
                BluefileError::Malformed(Malformed::Duplicate { word: w, .. }) => {
                    assert_eq!(w, word, "{body}")
                }
                other => panic!("{body}: expected a duplicate, got {other}"),
            }
        }
    }

    /// `generate` records the committed file and the program that writes it,
    /// keyed by the author's name: the name nix builds and gates it under.
    #[test]
    fn generate_records_a_committed_file_and_its_program() {
        let b = read_bluefile(
            "package(\"p\", \"0.1.0\")\n\
             generate(\"kigou-tables\", \"crates/s/src/kigou/tables.rs\", \"crates/s/gen/kigou.b\")",
        )
        .expect("read");
        assert_eq!(
            b.project.generated["kigou-tables"],
            Generated {
                output: "crates/s/src/kigou/tables.rs".into(),
                program: "crates/s/gen/kigou.b".into(),
            }
        );
    }

    /// A project that generates nothing serializes no `generated` key, so the
    /// word's arrival changed no existing lock's bytes.
    #[test]
    fn an_empty_generated_map_is_absent_from_the_json() {
        let b = read_bluefile("package(\"p\", \"0.1.0\")").expect("read");
        let v = serde_json::to_value(&b.project).expect("json");
        assert!(v.get("generated").is_none(), "{v}");
    }

    #[test]
    fn a_read_of_an_undeclared_run_is_refused() {
        let err = refusal_of("run(\"report\", \"r.b\", [\"games\"])");
        assert!(
            matches!(err, BluefileError::UnknownRead { ref run, ref missing }
                if run == "report" && missing == "games"),
            "got {err}"
        );
    }

    #[test]
    fn runs_that_read_each_other_in_a_cycle_are_refused() {
        let err = refusal_of("run(\"a\", \"a.b\", [\"b\"])\nrun(\"b\", \"b.b\", [\"a\"])");
        match err {
            BluefileError::RunCycle { cycle } => assert_eq!(cycle, vec!["a", "b", "a"]),
            other => panic!("expected a cycle, got {other}"),
        }
        assert!(matches!(
            refusal_of("run(\"a\", \"a.b\", [\"a\"])"),
            BluefileError::RunCycle { .. }
        ));
    }

    #[test]
    fn a_catalog_with_no_packages_is_refused() {
        let err = refusal_of("catalog(\"CATALOG.md\")");
        assert!(
            matches!(err, BluefileError::CatalogWithoutPackages),
            "got {err}"
        );
    }

    /// **A misspelled word is an `Escapes` refusal naming it** — P1b's gate.
    ///
    /// Red run, recorded 2026-09-23: deleting `"tool"` from
    /// `blue_lang_waku`'s `MANIFEST_NAMES` failed 5 tests here —
    /// `tool_records_a_nixpkgs_attribute` with ``this Bluefile names a name
    /// outside the manifest frame: tool``, `the_word_table_is_the_manifest_capability`
    /// with the difference `["tool"]`, `the_manifest_frame_grants_exactly_…` with
    /// ``the frame stopped permitting `tool` ``, and two tests that call `tool`
    /// incidentally — and 2 in `blue-lang-cli/tests/cli.rs`, among them
    /// `bluefile_json_reads_back_tool`. Reverted.
    #[test]
    fn a_misspelled_word_is_an_escape_naming_it() {
        match refusal_of("sourse(\"blue\", \"github:pleme-io/blue\", \"bidamas\")") {
            BluefileError::Escapes { names } => assert_eq!(names, vec!["sourse"]),
            other => panic!("expected an escape, got {other}"),
        }
    }

    /// **The word table and the frame's vocabulary are one set.** A name the
    /// frame grants with no recorder passes the frame and dies unbound; a
    /// recorder the frame does not grant can never be called. Both directions,
    /// against the capability rather than against this file.
    #[test]
    fn the_word_table_is_the_manifest_capability() {
        let table: BTreeSet<&str> = WORDS.iter().map(|w| w.name).collect();
        assert_eq!(table.len(), WORDS.len(), "a word is defined twice");
        let granted: BTreeSet<&str> = Capability::ManifestDeclaration
            .names()
            .into_iter()
            .collect();
        assert_eq!(
            table.symmetric_difference(&granted).collect::<Vec<_>>(),
            Vec::<&&str>::new(),
            "the word table and Capability::ManifestDeclaration disagree"
        );
        for w in WORDS {
            assert!(w.min <= w.max && w.max > 0, "{}", w.name);
        }
    }

    /// **Every word is a binding the manifest interpreter owns, and nothing
    /// else claims it.** The `assert` lesson: a name tatara already binds as a
    /// macro or special form beats a primitive, so a word shadowed that way
    /// would record nothing and every read-back test would go red only by luck.
    /// Asked of a real interpreter, across all three arbiters.
    #[test]
    fn every_word_is_unclaimed_by_the_runtime_and_bound_by_the_manifest() {
        let bare = blue_lang_runtime::interpreter_hostless();
        let mut manifest = blue_lang_runtime::interpreter_hostless();
        install_manifest_primitives(&mut manifest, &Shared::default());
        for w in WORDS {
            assert_eq!(
                bare.resolve_head(w.name),
                None,
                "the runtime already claims `{}`",
                w.name
            );
            assert_eq!(
                manifest.resolve_head(w.name),
                Some(tatara_lisp_eval::HeadBinding::Value),
                "`{}` is not an ordinary binding in the manifest interpreter",
                w.name
            );
        }
    }

    /// The `when` spellings round-trip through the one function both
    /// directions read.
    #[test]
    fn every_when_round_trips_through_its_label() {
        for w in [When::Sealed, When::Preceding, When::Anytime] {
            assert_eq!(parse_when(when_label(w)), Some(w));
        }
    }

    // ── the manifest frame ────────────────────────────────────────────────

    /// **The gate, red.** A manifest that names something the frame does not
    /// permit is refused, and the refusal names it.
    ///
    /// `no_such_thing()` was previously an `Eval` error — the manifest ran,
    /// recorded its package, and died at the call. That is the behaviour this
    /// changes.
    #[test]
    fn a_manifest_naming_something_outside_the_frame_is_refused() {
        let err =
            read_bluefile("package(\"m\", \"1.0.0\")\nno_such_thing()").expect_err("must refuse");
        match err {
            BluefileError::Escapes { names } => {
                assert_eq!(names, vec!["no_such_thing".to_string()])
            }
            other => panic!("expected an escape, got {other}"),
        }
    }

    /// **And it is refused BEFORE anything runs.** The escape sits after a
    /// perfectly good `package(...)`; if the check ran during evaluation the
    /// name would have been recorded first. Nothing observable survives a
    /// refused manifest.
    #[test]
    fn a_refused_manifest_never_runs_its_earlier_forms() {
        let src = "package(\"recorded\", \"1.0.0\")\nread_file(\"/etc/passwd\")";
        let err = read_bluefile(src).expect_err("must refuse");
        assert!(
            matches!(err, BluefileError::Escapes { ref names } if names == &["read_file".to_string()]),
            "got {err}"
        );
        // The whole point: there is no half-built manifest to observe. The
        // error carries no package, and `read_bluefile` is the only way to get
        // a `Bluefile`, so nothing downstream can see one.
        assert!(read_bluefile(src).is_err());
    }

    /// **Anti-vacuity.** Every Bluefile the distribution actually ships passes
    /// the frame. A frame nothing can satisfy would make the test above pass
    /// for the wrong reason, and a frame everything satisfies would make it
    /// impossible — this pins both ends against real files.
    #[test]
    fn every_bluefile_in_the_distribution_stays_inside_the_frame() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../bidamas")
            .canonicalize()
            .expect("the distribution is in the repo");
        let mut checked = 0usize;
        for entry in std::fs::read_dir(&root).expect("read bidamas") {
            let manifest = entry.expect("entry").path().join("Bluefile");
            if !manifest.is_file() {
                continue;
            }
            let src = std::fs::read_to_string(&manifest).expect("read manifest");
            read_bluefile(&src).unwrap_or_else(|e| {
                panic!("{} escaped the manifest frame: {e}", manifest.display())
            });
            checked += 1;
        }
        assert!(
            checked >= 18,
            "only {checked} manifests were checked — the corpus went missing, \
             which would make this test pass over nothing"
        );
    }

    /// The frame reads the operator table rather than copying it, so an
    /// operator added to `INFIX` is usable in a manifest with no second edit.
    #[test]
    fn the_frame_permits_every_operator_the_parser_lowers_to() {
        let frame = manifest_frame();
        for infix in blue_lang_syntax::INFIX {
            assert!(
                frame.reach.permits(infix.callee),
                "`{}` lowers to `{}`, which the manifest frame does not permit",
                infix.op,
                infix.callee
            );
        }
    }
}
