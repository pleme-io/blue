//! Reading `spec/rows/*.b` into [`Row`]s.
//!
//! A row file is blue source that is **parsed, never evaluated**. Each
//! top-level form is one call:
//!
//! ```text
//! row(ID, SRC, EXPECTATION, OPTION...)
//! ```
//!
//! Parsing rather than evaluating is deliberate. The rows are the yardstick
//! every evaluator is measured against, so reading them must not depend on any
//! evaluator being right — only on the parser, which every stage shares. A
//! future self-hosted blue reads the same files the same way.
//!
//! Anything that is not a well-formed row is refused **by name, per row**: one
//! malformed row fails the run and names itself, and every valid sibling is
//! still run and reported. A file-level refusal would hide how much of the
//! suite still holds.

use std::path::{Path, PathBuf};

use blue_lang_syntax::{Atom, Sexp};

/// Which evaluator (or door) an observation came from.
#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
pub enum Ev {
    /// The tree-walker behind `blue run`: `pipeline::run_in_surface`. Stage 0:
    /// every other evaluator is compared against it.
    Walker,
    /// The bytecode VM: the same check and erasure, then batched expansion and
    /// `tatara_lisp_eval::vm` (`Interpreter::eval_program_vm`).
    Vm,
    /// The WASM surface's ABI (`blue_lang_wasm::eval_tagged`), observed at the
    /// resolution the ABI has: an integer, "not an integer", or an error.
    Wasm,
    /// The shipped `blue` binary, as a subprocess: the only door where output
    /// and the command-line surfaces (`fmt`, `check`, `shift`) are observable.
    Cli,
    /// The static stages every evaluator shares: parse, check, format and the
    /// blueshift reading, called in-process.
    Static,
}

impl Ev {
    pub const ALL: [Ev; 5] = [Ev::Walker, Ev::Vm, Ev::Wasm, Ev::Cli, Ev::Static];

    pub fn name(self) -> &'static str {
        match self {
            Ev::Walker => "walker",
            Ev::Vm => "vm",
            Ev::Wasm => "wasm",
            Ev::Cli => "cli",
            Ev::Static => "static",
        }
    }

    fn parse(name: &str) -> Option<Ev> {
        Ev::ALL.into_iter().find(|e| e.name() == name)
    }
}

/// Where a failure is expected to stop the program.
#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Stage {
    Parse,
    Check,
    Import,
    Eval,
}

impl Stage {
    pub fn name(self) -> &'static str {
        match self {
            Stage::Parse => "parse",
            Stage::Check => "check",
            Stage::Import => "import",
            Stage::Eval => "eval",
        }
    }

    fn parse(name: &str) -> Option<Stage> {
        [Stage::Parse, Stage::Check, Stage::Import, Stage::Eval]
            .into_iter()
            .find(|s| s.name() == name)
    }
}

/// What a row expects.
#[derive(Clone, Debug)]
pub enum Expect {
    /// `value("[1, 2]")`: the program's final value, rendered as its blue
    /// literal by blue's own `to_s` literal renderer (okite D0006).
    Value(String),
    /// `fails(:eval, "division by zero")`: the program stops at that stage,
    /// and the message contains the text. For `:check` the text is a rule
    /// code (`"B0001"`).
    Fails(Stage, String),
    /// `prints("hi\n")`: exactly this on stdout, and a clean exit.
    Prints(String),
    /// `diagnoses(["B0002"])`: the check stage reports exactly these codes,
    /// warnings included, in order of appearance.
    Diagnoses(Vec<String>),
    /// `formats("x = 1\n")`: the one formatting of the source is this text,
    /// and formatting it again changes nothing.
    Formats(String),
    /// `shifts("annotated", ["loose"])`: the blueshift reading is this rung,
    /// and these declarations are what hold it back.
    Shifts(String, Vec<String>),
}

impl Expect {
    pub fn kind(&self) -> &'static str {
        match self {
            Expect::Value(_) => "value",
            Expect::Fails(..) => "fails",
            Expect::Prints(_) => "prints",
            Expect::Diagnoses(_) => "diagnoses",
            Expect::Formats(_) => "formats",
            Expect::Shifts(..) => "shifts",
        }
    }
}

/// `pending("G5")` or `pending("G16", "wasm")`: the row states the DESTINATION
/// behaviour, which the named gap has not reached yet — on every evaluator, or
/// on one.
#[derive(Clone, Debug)]
pub struct Pending {
    pub gap: String,
    pub on: Option<Ev>,
}

#[derive(Clone, Debug)]
pub struct Row {
    pub file: String,
    pub id: String,
    pub src: String,
    pub expect: Expect,
    pub pending: Vec<Pending>,
    /// `position("checked")`: the blueshift rung this behaviour applies at.
    /// The runner measures the program's rung and refuses a row whose program
    /// does not sit where it says.
    pub position: Option<String>,
    /// `covers("builtin:append", "form:x = 5", …)`: the registry rows this row
    /// specifies. The missing-row gate reads these.
    pub covers: Vec<String>,
    /// `host()`: the program reaches a host effect (files, processes, the
    /// clock). The WASM surface is blind to such a row in this build; see
    /// `eval::wasm`.
    pub host: bool,
    /// `isolate()`: the program may take its evaluator down with it (a stack
    /// overflow aborts the OS process; a runaway never returns). The row runs
    /// in a child process with a time limit, and a death is an observation.
    pub isolate: bool,
}

impl Row {
    /// The pending mark that applies to `ev`, if any.
    pub fn pending_on(&self, ev: Ev) -> Option<&Pending> {
        self.pending.iter().find(|p| p.on.is_none_or(|on| on == ev))
    }
}

/// Every row file, sorted, so a report is reproducible.
pub fn row_files(dir: &Path) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .unwrap_or_else(|e| {
            panic!(
                "{} must exist: it is the specification ({e})",
                dir.display()
            )
        })
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "b"))
        .collect();
    files.sort();
    files
}

/// Read every row. Returns the rows and, separately, every refusal.
pub fn load(dir: &Path) -> (Vec<Row>, Vec<String>) {
    let mut rows = Vec::new();
    let mut refusals = Vec::new();
    for path in row_files(dir) {
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let text = match std::fs::read_to_string(&path) {
            Ok(t) => t,
            Err(e) => {
                refusals.push(format!("{name}: unreadable: {e}"));
                continue;
            }
        };
        let forms = match blue_lang_syntax::parse_program(&text) {
            Ok(f) => f,
            Err(e) => {
                // A file that does not parse has no rows to refuse one by one.
                refusals.push(format!("{name}: does not parse: {e}"));
                continue;
            }
        };
        for (i, form) in forms.iter().enumerate() {
            match row_of(&name, form) {
                Ok(row) => rows.push(row),
                Err(why) => refusals.push(format!("{name}: form {}: {why}", i + 1)),
            }
        }
    }
    (rows, refusals)
}

fn str_of(s: &Sexp) -> Option<&str> {
    match s {
        Sexp::Atom(Atom::Str(x)) => Some(x),
        _ => None,
    }
}

fn head_of(s: &Sexp) -> Option<(&str, &[Sexp])> {
    match s {
        Sexp::List(items) => match items.split_first() {
            Some((Sexp::Atom(Atom::Symbol(h)), rest)) => Some((h.as_str(), rest)),
            _ => None,
        },
        _ => None,
    }
}

/// A blue list literal of strings, `["a", "b"]`, which lowers to `(list …)`.
fn strings_of(s: &Sexp) -> Option<Vec<String>> {
    let (head, items) = head_of(s)?;
    if head != "list" {
        return None;
    }
    items.iter().map(|i| str_of(i).map(str::to_owned)).collect()
}

fn one_str<'a>(what: &str, args: &'a [Sexp]) -> Result<&'a str, String> {
    match args {
        [s] => str_of(s).ok_or_else(|| format!("{what}(…) takes one string")),
        _ => Err(format!("{what}(…) takes one string")),
    }
}

fn expect_of(s: &Sexp) -> Result<Expect, String> {
    let (head, args) = head_of(s).ok_or("the third argument must be an expectation call")?;
    Ok(match head {
        "value" => Expect::Value(one_str("value", args)?.to_owned()),
        "prints" => Expect::Prints(one_str("prints", args)?.to_owned()),
        "formats" => Expect::Formats(one_str("formats", args)?.to_owned()),
        "fails" => match args {
            [Sexp::Atom(Atom::Keyword(k)), needle] => Expect::Fails(
                Stage::parse(k).ok_or_else(|| {
                    format!("fails(:{k}, …): the stage is one of :parse, :check, :import, :eval")
                })?,
                str_of(needle)
                    .ok_or("fails(:stage, TEXT): TEXT is a string")?
                    .to_owned(),
            ),
            _ => return Err("fails(:stage, \"text\")".into()),
        },
        "diagnoses" => match args {
            [codes] => Expect::Diagnoses(
                strings_of(codes).ok_or("diagnoses([\"B0001\", …]) takes a list of codes")?,
            ),
            _ => return Err("diagnoses([\"B0001\", …]) takes a list of codes".into()),
        },
        "shifts" => match args {
            [rung, holding] => Expect::Shifts(
                str_of(rung).ok_or("shifts(RUNG, [NAME, …])")?.to_owned(),
                strings_of(holding).ok_or("shifts(RUNG, [NAME, …])")?,
            ),
            _ => return Err("shifts(\"rung\", [\"name\", …])".into()),
        },
        other => return Err(format!("`{other}` is not an expectation")),
    })
}

const RUNGS: [&str; 4] = ["dynamic", "annotated", "checked", "restricted"];

fn row_of(file: &str, form: &Sexp) -> Result<Row, String> {
    let (head, args) = head_of(form).ok_or("a row file holds only row(…) calls")?;
    if head != "row" {
        return Err(format!(
            "`{head}(…)` is not a row; a row file holds only row(…) calls"
        ));
    }
    let [id, src, expect, options @ ..] = args else {
        return Err("row(ID, SRC, EXPECTATION, OPTION...) needs at least three arguments".into());
    };
    let id = str_of(id).ok_or("the row id is a string")?.to_owned();
    let label = |why: String| format!("row \"{id}\": {why}");
    let src = str_of(src)
        .ok_or_else(|| label("the program is a string".into()))?
        .to_owned();
    let expect = expect_of(expect).map_err(label)?;
    let mut row = Row {
        file: file.to_owned(),
        id: id.clone(),
        src,
        expect,
        pending: Vec::new(),
        position: None,
        covers: Vec::new(),
        host: false,
        isolate: false,
    };
    for option in options {
        let (name, args) = head_of(option).ok_or_else(|| label("an option is a call".into()))?;
        match name {
            "pending" => {
                let (gap, on) = match args {
                    [gap] => (gap, None),
                    [gap, on] => (gap, Some(on)),
                    _ => return Err(label("pending(GAP) or pending(GAP, EVALUATOR)".into())),
                };
                let gap = str_of(gap)
                    .ok_or_else(|| label("pending(\"G5\"): the gap is a string".into()))?
                    .to_owned();
                let on = match on {
                    None => None,
                    Some(e) => {
                        let e =
                            str_of(e).ok_or_else(|| label("the evaluator is a string".into()))?;
                        Some(Ev::parse(e).ok_or_else(|| {
                            label(format!(
                                "`{e}` is not an evaluator: walker, vm, wasm, cli, static"
                            ))
                        })?)
                    }
                };
                row.pending.push(Pending { gap, on });
            }
            "position" => {
                let p = one_str("position", args).map_err(label)?;
                if !RUNGS.contains(&p) {
                    return Err(label(format!(
                        "position(\"{p}\"): the rung is one of {}",
                        RUNGS.join(", ")
                    )));
                }
                row.position = Some(p.to_owned());
            }
            "covers" => {
                for a in args {
                    row.covers.push(
                        str_of(a)
                            .ok_or_else(|| label("covers(…) takes strings".into()))?
                            .to_owned(),
                    );
                }
            }
            "host" if args.is_empty() => row.host = true,
            "isolate" if args.is_empty() => row.isolate = true,
            other => return Err(label(format!("`{other}(…)` is not a row option"))),
        }
    }
    Ok(row)
}
