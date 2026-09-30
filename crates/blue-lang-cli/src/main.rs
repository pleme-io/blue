//! `blue` — the command line.
//!
//! Every subcommand does **one** thing, per ★★ CLOSED-LOOP MASS-SYNTHESIS:
//! a monolithic `blue do-everything` is the shape this forbids. Each one is a
//! projection of the same pipeline, so `blue ast` and `blue run` cannot
//! disagree about what a program means — they read the same stages from
//! `blue_lang_runtime::pipeline`.
//!
//! ```text
//! blue run     FILE            parse, check, erase, execute
//! blue fmt     FILE [--check]  the one formatting; --check exits 1 on drift
//! blue ast     FILE            the tatara-lisp form — homoiconicity, visible
//! blue erase   FILE            the tatara-lisp form after type erasure
//! blue check   FILE [--format json] [--fix]   every rule, the typing report
//! blue explain CODE | --list   what a diagnostic code means
//! blue test    FILE            check, then run the file's `test` blocks
//! blue deps    BLUEFILE        resolve the manifest's dependencies
//! blue posture BLUEFILE        the posture the manifest's floors require
//! blue bluefile --json BLUEFILE         the evaluated manifest, as JSON
//! blue bluefile --confirm BLUEFILE...   exit 1 unless each Bluefile.lock is fresh
//! blue lock    [DIR...]        evaluate, pin every source, write Bluefile.lock
//! blue config  [TIER]          the bounds blue is running with
//! blue lsp                     speak LSP over stdio
//! blue banner                  the wordmark — the blueshift ramp
//! blue shift   FILE            how far this is shifted, and what is shifting it
//! blue reference               the language, from its own tables, as JSON
//! ```
//!
//! `blue deps` and `blue posture` read a **Bluefile**, which is itself a blue
//! program — see `blue_lang_pkg::bluefile`. `posture` was previously absent
//! because there was no declaration surface to read a floor from; there is one
//! now.
//!
//! **Neither fetches anything.** Resolution is real; there is no registry
//! *client*, so `deps` resolves against the distribution already on
//! `BLUE_PATH` (via `GitRegistry`) and installs nothing. With no distribution
//! there, it says so rather than printing a hollow resolution.
//!
//! `blue bluefile` and `blue lock` are how nix reads blue without running it
//! (`theory/BLUE-STRUCTURE.md` §5.1): `lock` commits the evaluation, and
//! `--confirm` is the offline freshness gate the flake runs over every package.
//! `lock` is the one subcommand that starts a process — `nix flake prefetch`,
//! behind `blue_lang_pkg::lock::Prefetch` so no test reaches the network.
//!
//! Every subcommand runs under the bounds in `config` — resolved once, here,
//! and threaded down.
//!
//! `blue ast` and `blue erase` are separate on purpose: the difference
//! between them *is* the sliding scale, and being able to print both sides of
//! it is how a reader sees that annotations are consumed rather than carried.

mod census;
mod config;
mod diagnostics;
mod prefetch;
mod reference;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use blue_lang_pkg::lock::{Freshness, ManifestRecord, LOCK_FILE};
use clap::{Parser, Subcommand};

use config::BlueConfig;

#[derive(Parser)]
#[command(
    name = "blue",
    version,
    about = "The blue language: a Ruby/Elixir surface on tatara-lisp and Rust."
)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Parse, type-check, erase, and execute a program.
    Run {
        file: PathBuf,
        /// Supply a build input: `--input name=path`.
        ///
        /// The program must also `definput(name, "b3:…")`; the bytes are
        /// verified against that hash before any macro can read them. A
        /// mismatch is refused — see `blue_lang_runtime::inputs`.
        #[arg(long = "input", value_name = "NAME=PATH")]
        inputs: Vec<String>,
        /// Do not print the program's final value. An installed command's
        /// output is what it writes (`write_stdout`), not the value its last
        /// expression happens to leave; `mkBlueApp` passes this, so a blue
        /// executable on PATH never ends its output with a stray `nil`.
        #[arg(long, short = 'q')]
        quiet: bool,
        /// The program's own arguments, after the file (use `--` before any
        /// that start with a dash): what `argv()` returns. Before 2026-09-27
        /// `run` refused any, so no blue program could take arguments.
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
    },
    /// Format a program. There is one formatting; this produces it.
    ///
    /// Several files may be named with `--check` or `--write`: each is
    /// reported, and the exit is non-zero if any drifted or was refused. That
    /// is what lets a gate hold a whole tree canonical in ONE command
    /// (`mkFmtCheck`, and `mkBidama`'s own build) rather than in a loop.
    Fmt {
        #[arg(required = true)]
        file: Vec<PathBuf>,
        /// Report drift and exit non-zero instead of rewriting.
        #[arg(long)]
        check: bool,
        /// Rewrite the file in place.
        #[arg(long)]
        write: bool,
    },
    /// Print the tatara-lisp form, annotations intact.
    ///
    /// `--resolved` prints the RESOLVED tree instead: every definition renamed
    /// to its runtime key (`retsu/first`, `%root/f` for a script) and every
    /// reference to what per-bidama namespaces bind it to (a builtin stays
    /// bare). `--json` adds, per reference, what today's flat rule and the
    /// namespace rule each bind it to — the data a migration is proven on.
    Ast {
        file: PathBuf,
        #[arg(long)]
        resolved: bool,
        #[arg(long, requires = "resolved")]
        json: bool,
    },
    /// Print the tatara-lisp form after type erasure — what actually runs.
    Erase { file: PathBuf },
    /// Check a program against every rule in the registry — unbound names,
    /// unused bindings, types, waivers — and report the typing analysis.
    ///
    /// Like `run` and `test`, this compiles only canonical source: a writable
    /// file that is not canonically formatted is REWRITTEN IN PLACE first
    /// (`blue: formatted <path>` on stderr), and a read-only one is refused.
    ///
    /// Exits non-zero when any error-severity diagnostic remains. Test blocks
    /// are checked too. `blue explain CODE` says what a code means.
    Check {
        file: PathBuf,
        /// `text` for people; `json` prints one JSON object per diagnostic
        /// per line on stdout (JSON Lines). The fields are documented in
        /// docs/DIAGNOSTICS.md and are stable.
        #[arg(long, value_enum, default_value_t = Format::Text)]
        format: Format,
        /// Apply every machine-applicable fix to the file, re-format it, and
        /// check again. Suggestions marked maybe-incorrect are never applied.
        #[arg(long)]
        fix: bool,
    },
    /// Count, over every `.b` file under ROOT, each finding of every rule
    /// still being ratcheted in, and fail unless each count equals its
    /// registry row's `ratchet`. `--findings` lists them.
    Census {
        #[arg(default_value = ".")]
        root: PathBuf,
        #[arg(long)]
        findings: bool,
    },
    /// Explain a diagnostic code (`blue explain B0001`), or list them all.
    #[command(group(clap::ArgGroup::new("which").required(true).args(["code", "list"])))]
    Explain {
        code: Option<String>,
        /// List every code with its severity and one-line law.
        #[arg(long)]
        list: bool,
    },
    /// Check the file (as `blue check` does), then run its `test` blocks.
    Test { file: PathBuf },
    /// Resolve a Bluefile's dependencies. Does not fetch.
    Deps { file: PathBuf },
    /// Report the posture a Bluefile's declared floor requires.
    Posture { file: PathBuf },
    /// Print a Bluefile's evaluated manifest, or confirm its lock is fresh.
    #[command(group(clap::ArgGroup::new("mode").required(true).args(["json", "confirm"])))]
    Bluefile {
        /// Print the evaluated manifest as JSON — what `Bluefile.lock` records
        /// under `manifest`.
        #[arg(long)]
        json: bool,
        /// Exit non-zero unless the `Bluefile.lock` beside every named
        /// Bluefile is blue's evaluation of it. Offline.
        #[arg(long)]
        confirm: bool,
        #[arg(required = true)]
        files: Vec<PathBuf>,
    },
    /// Evaluate each directory's Bluefile, pin every `source(...)` with
    /// `nix flake prefetch`, and write `Bluefile.lock` beside it.
    Lock {
        /// Directories holding a Bluefile. The current one when none is named.
        dirs: Vec<PathBuf>,
    },
    /// Run the language server, speaking LSP over stdin/stdout.
    Lsp,
    /// Print blue's wordmark.
    Banner,
    /// Report the blueshift: how far this program is shifted, and what is
    /// shifting it.
    Shift { file: PathBuf },
    /// The morphology: what each posture grants, what it forfeits, which pairs
    /// are genuinely exclusive, and which language each shape corresponds to.
    Morph,
    /// Print the language reference as JSON: operators, keywords, surface
    /// forms, Bluefile words and every bound name, each read from the table
    /// the implementation runs on. `docs/REFERENCE.md` is rendered from it.
    Reference,
    /// Show the bounds `blue` is running with, at any tier.
    ///
    /// The fleet-uniform `config-show` surface, supplied by shikumi rather
    /// than hand-rolled here — see `config` for what may live in it and why
    /// the surface is two fields.
    Config(shikumi::cli::ConfigShowCommand),
}

fn main() -> ExitCode {
    match dispatch(Cli::parse()) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("blue: {e}");
            ExitCode::FAILURE
        }
    }
}

/// `blue check`'s output shape.
#[derive(Clone, Copy, Debug, PartialEq, Eq, clap::ValueEnum)]
enum Format {
    Text,
    Json,
}

/// One error type for the CLI's own failures, so every exit path is typed.
#[derive(Debug, thiserror::Error)]
enum CliError {
    #[error("{path}: {source}")]
    Read {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{path}: {source}")]
    Write {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{0}")]
    Blue(#[from] blue_lang_runtime::RunError),
    #[error("{0}")]
    Fmt(String),
    #[error("{0}")]
    Pkg(String),
    /// blue compiles only canonical source; `blue_lang_pkg::canonical`.
    #[error("{0}")]
    Refused(#[from] blue_lang_pkg::canonical::Refusal),
    #[error("{0}")]
    Config(#[from] shikumi::cli::ConfigShowError),
    #[error("{0}")]
    Bluefile(#[from] blue_lang_pkg::BluefileError),
    #[error("{0}")]
    Lock(#[from] blue_lang_pkg::lock::LockError),
    #[error("could not render JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("no diagnostic code `{0}`; `blue explain --list` lists them")]
    UnknownCode(String),
    /// `--json` prints ONE manifest; several would need a container shape, and
    /// inventing one here would be a second schema beside the lock's.
    #[error("`blue bluefile --json` prints one manifest, and {got} Bluefiles were named")]
    JsonTakesOne { got: usize },
}

/// One line of `blue bluefile --confirm` output: which Bluefile, and its
/// verdict (`{"status": "fresh"}` or `{"status": "stale", "reason": …}`).
#[derive(serde::Serialize)]
struct Confirmation<'a> {
    bluefile: String,
    #[serde(flatten)]
    verdict: &'a Freshness,
}

/// The source of a file blue is about to COMPILE: canonical, or formatted in
/// place first, or refused (`blue_lang_pkg::canonical`). Every door that
/// compiles its entry file reads it here; the ones that only look at a file
/// (`fmt`, `ast`, `erase`) read it with [`read`].
fn read_compiled(path: &Path) -> Result<String, CliError> {
    Ok(blue_lang_pkg::canonical::read_source(path)?)
}

fn read(path: &Path) -> Result<String, CliError> {
    std::fs::read_to_string(path).map_err(|source| CliError::Read {
        path: path.display().to_string(),
        source,
    })
}

/// Parse under the CONFIGURED nesting bound.
///
/// Every direct parse the CLI performs goes through here rather than through
/// `blue_lang_runtime::parse`, for the same reason the pipeline owns stage
/// order: a second door that quietly uses the compiled-in default would make
/// `max_expr_depth` true of some subcommands and not others, and nothing would
/// say which.
fn parse(src: &str, cfg: &BlueConfig) -> Result<Vec<blue_lang_syntax::Sexp>, CliError> {
    Ok(blue_lang_runtime::parse_with_depth(
        src,
        cfg.max_expr_depth,
    )?)
}

/// [`parse`] keeping every node's source span, under the same configured bound.
fn parse_tree(src: &str, cfg: &BlueConfig) -> Result<Vec<blue_lang_syntax::Spanned>, CliError> {
    Ok(blue_lang_runtime::parse_tree_with_depth(
        src,
        cfg.max_expr_depth,
    )?)
}

/// A `file:line:col` prefix.
///
/// A typed `Display` rather than a `format!` at the call site, per ★★ TYPED
/// EMISSION: a consumer that needed the text was a missing `Display`, not a
/// licence to build the string by interpolation. Both `line` and `col` are
/// ONE-based here, because this string is read by humans and by editors, and
/// both count from 1 — `Span::line_col` already answers in those terms.
struct Located {
    file: String,
    line: usize,
    col: usize,
}

impl std::fmt::Display for Located {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}:{}:", self.file, self.line, self.col)
    }
}

/// The distribution on `BLUE_PATH`, if any root holds one.
///
/// Roots are searched in order and the FIRST non-empty one wins — the same
/// "first match wins" rule `LoadPath` itself documents, so `blue deps` and
/// `use(...)` cannot disagree about which distribution is in effect.
fn scan_registry() -> Result<Option<blue_lang_pkg::git_registry::GitRegistry>, CliError> {
    use blue_lang_pkg::git_registry::{GitRegistry, GitRegistryError};
    for root in blue_lang_pkg::load_path::LoadPath::from_env().roots() {
        let registry = match GitRegistry::scan(root) {
            Ok(r) => r,
            // A stale entry in a `PATH`-shaped list is normal, so an unreadable
            // root is skipped. A Bluefile that EXISTS and does not parse is a
            // broken package and is reported — the scanner draws that line
            // deliberately, and swallowing it here would undo it.
            Err(GitRegistryError::Unreadable { .. }) => continue,
            Err(e @ GitRegistryError::BadManifest { .. }) => {
                return Err(CliError::Pkg(e.to_string()))
            }
        };
        if !registry.is_empty() {
            return Ok(Some(registry));
        }
    }
    Ok(None)
}

fn dispatch(cli: Cli) -> Result<ExitCode, CliError> {
    // Resolved ONCE, at the top, and threaded down — never re-read per
    // subcommand. Two reads of a config are two chances to disagree about it,
    // and the pipeline's own lesson (one place owns the order) applies to the
    // bounds the pipeline runs under just as much.
    let cfg = config::resolve();
    // Before any interpreter is built, so every evaluating door — run, test,
    // the LSP, a Bluefile — runs under the configured bounds.
    blue_lang_runtime::set_execution_bounds(cfg.execution_bounds());
    // `self_exe` answers with THIS binary only because it is the blue CLI;
    // any other embedder leaves it nil (blue_lang_runtime::sys::set_blue_exe).
    if let Ok(me) = std::env::current_exe() {
        blue_lang_runtime::sys::set_blue_exe(me.to_string_lossy().into_owned());
    }
    match cli.cmd {
        Cmd::Run { file, inputs, quiet, args } => {
            blue_lang_runtime::sys::set_program_args(args);
            // The SURFACE the program is written in: BLUE_LANG wins, else the
            // host locale. An explicit choice must beat a detected one.
            let surface = resolve_surface().map_err(CliError::Pkg)?;
            // blue compiles only canonical source. The formatter speaks the
            // English surface, so a program that USES a `yakugo` surface's
            // words is compiled as written rather than translated by its
            // formatting. One that parses to the same tree either way is
            // English — the common case under a pt or de locale — and is held
            // to the rule like any other.
            let src = match &surface {
                None => read_compiled(&file)?,
                Some(pack) => {
                    let text = read(&file)?;
                    let english = blue_lang_syntax::parse_program(&text).ok();
                    let spoken = blue_lang_syntax::parse_program_in(&text, pack).ok();
                    if english.is_some() && english == spoken {
                        blue_lang_pkg::canonical::admit(&file, text)?
                    } else {
                        text
                    }
                }
            };
            // Always bind, even with no `--input` flags: a program that
            // DECLARES an input and gets no material must hear "you forgot the
            // flag", not the macro-level "no input named …" from deep inside
            // expansion. Short-circuiting on an empty flag list is what made it
            // report the wrong one.
            // Imports resolve through BLUE_PATH.
            //
            // The CLI is the one place a *user's* environment can supply the
            // loader, and without this wire `use("kazu")` fails from the
            // command line no matter what nix built — the derivations, the
            // BLUE_PATH root and the resolver would all be correct and none of
            // them reachable from `blue run`.
            //
            // Reading the environment rather than taking a flag because that is
            // what makes the nix wrapper work: `mkBlueWithBidamas` prefixes
            // BLUE_PATH, so a wrapped `blue` resolves the distribution with no
            // argument, and an unwrapped one still honours a checkout.
            let loader = blue_lang_pkg::load_path::LoadPath::from_env();
            // The entry file travels WITH its source. Without the path, every
            // type error in the file the user named would report against
            // `<anonymous>` while an imported package's reported its real path
            // — the entry file being the one file the CLI always knows.
            let out = blue_lang_runtime::pipeline::run_in_surface(
                blue_lang_runtime::uses::Entry {
                    path: Some(&file),
                    text: &src,
                },
                bind_inputs(&src, &inputs, &cfg)?,
                &loader,
                surface.as_ref(),
            )?;
            if !quiet {
                println!("{}", render(&out.value));
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Fmt { file, check, write } => {
            if !check && !write && file.len() != 1 {
                return Err(CliError::Fmt(
                    "`blue fmt` prints ONE file; name several with --check or --write".into(),
                ));
            }
            let mut failed = false;
            for file in &file {
                let src = read(file)?;
                // The LOSSLESS rendering is the canonical form of a file that
                // has comments, so `--check` must compare against it. Comparing
                // against the comment-stripped rendering made every commented
                // file report "not formatted" forever — a --check that can
                // never be satisfied.
                let formatted = match blue_lang_fmt::format_source_lossless(&src) {
                    Ok(f) => f,
                    Err(e) if check || write => {
                        eprintln!("blue: {}: {e}", file.display());
                        failed = true;
                        continue;
                    }
                    Err(e) => return Err(CliError::Fmt(e.to_string())),
                };
                if check {
                    // Compare trimmed: a trailing newline is not drift.
                    if formatted.trim_end() != src.trim_end() {
                        eprintln!(
                            "{}: not formatted; run blue fmt --write {}",
                            file.display(),
                            file.display()
                        );
                        failed = true;
                    }
                } else if write {
                    // The LOSSLESS path, because this overwrites the file.
                    // `--write` used to delete every comment silently; a
                    // comment the formatter cannot place is refused above.
                    std::fs::write(file, &formatted).map_err(|source| CliError::Write {
                        path: file.display().to_string(),
                        source,
                    })?;
                } else {
                    print!("{formatted}");
                }
            }
            Ok(if failed {
                ExitCode::FAILURE
            } else {
                ExitCode::SUCCESS
            })
        }

        Cmd::Ast {
            file,
            resolved: false,
            ..
        } => {
            for form in parse(&read(&file)?, &cfg)? {
                println!("{form}");
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Ast { file, json, .. } => {
            use blue_lang_runtime::pipeline::{check_entry, Checking};
            let loader = blue_lang_pkg::load_path::LoadPath::from_env();
            let src = read_compiled(&file)?;
            let checked = check_entry(
                blue_lang_runtime::uses::Entry {
                    path: Some(&file),
                    text: &src,
                },
                &loader,
                None,
                Checking::WithTests,
            )?;
            let resolved = checked.resolve();
            if json {
                println!("{}", diagnostics::resolved_json(&checked, &resolved)?);
            } else {
                let tree =
                    resolved.resolved_tree(checked.program.forms(), blue_lang_check::names::Rule::Namespaced);
                for (i, form) in tree.iter().enumerate() {
                    if checked.program.owner_of(i) == Some(blue_lang_runtime::uses::ResolvedProgram::ENTRY) {
                        println!("{}", form.to_sexp());
                    }
                }
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Erase { file } => {
            // The SPANNED door — erasure runs on spans, so this is the tree it
            // takes. Printed through `to_sexp`, which is the projection that
            // throws the positions away: they are what the erased tree is FOR
            // downstream, and `Spanned` has no `Display` precisely so a caller
            // has to say out loud that it is dropping them.
            let forms = parse_tree(&read(&file)?, &cfg)?;
            for form in blue_lang_runtime::to_sexps(&blue_lang_runtime::erase_types(&forms)) {
                println!("{form}");
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Check { file, format, fix } => check(&file, format, fix),

        Cmd::Census { root, findings } => {
            let c = census::take(&root).map_err(CliError::Pkg)?;
            println!("{} file(s)", c.files);
            for r in blue_lang_check::RULES.iter().filter(|r| r.ratchet.is_some()) {
                let measured = c.findings.get(&r.code).map_or(0, std::collections::BTreeSet::len);
                println!(
                    "{} {:<24} measured {measured:>5}  ratchet {:>5}",
                    r.code,
                    r.slug,
                    r.ratchet.unwrap_or(0)
                );
                if findings {
                    for f in c.findings.get(&r.code).into_iter().flatten() {
                        println!("    {}", f.lines().next().unwrap_or(""));
                    }
                }
            }
            let bad = c.mismatches();
            for (code, measured, ratchet) in &bad {
                eprintln!(
                    "blue census: {code} measured {measured}, ratchet {ratchet}: edit the row's ratchet to {measured} if the change is the intended one"
                );
            }
            Ok(if bad.is_empty() {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            })
        }

        Cmd::Explain { code, list } => {
            if list {
                for r in blue_lang_check::RULES {
                    println!(
                        "{} {:<8} {:<22} {}",
                        r.code,
                        r.severity.label(),
                        r.slug,
                        r.law
                    );
                }
                return Ok(ExitCode::SUCCESS);
            }
            let code = code.unwrap_or_default();
            let c = blue_lang_check::Code::parse(&code).ok_or(CliError::UnknownCode(code))?;
            print!("{}", blue_lang_check::Explain(c.rule()));
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Test { file } => {
            let src = read_compiled(&file)?;
            // The CHECK STAGE first, through the pipeline, with the file's test
            // blocks included: a typo in a test body, or in a function only a
            // test calls, is an error here exactly as it would be for `run`.
            //
            // This door used to call `resolve_uses` itself and hand the result
            // straight to the harness, so `blue test` ran no check at all — a
            // type error the pipeline would refuse ran green under test.
            // Imports resolve through BLUE_PATH, for the same reason they do in
            // `run`: a package that cannot be tested with its dependencies is a
            // package with no tests.
            let checked = blue_lang_runtime::pipeline::check_entry(
                blue_lang_runtime::uses::Entry {
                    path: Some(&file),
                    text: &src,
                },
                &blue_lang_pkg::load_path::LoadPath::from_env(),
                None,
                blue_lang_runtime::pipeline::Checking::WithTests,
            )?;
            // Every finding, errors and warnings, in one pass; then no test
            // runs over a program with an error, as `run` would not evaluate it.
            for d in &checked.outcome.diagnostics {
                eprintln!(
                    "{}",
                    blue_lang_runtime::pipeline::render(&checked.program, d)
                );
            }
            if !checked.outcome.ok() {
                eprintln!(
                    "blue: {}: the check stage rejected the file, so no test ran",
                    file.display()
                );
                return Ok(ExitCode::FAILURE);
            }
            // The harness reports a failing ASSERTION, not a position, so it
            // takes the spanless projection. When it grows one it should take
            // the program itself — the file table is already here.
            let report = blue_lang_test::run(&checked.evaluable());
            // Failures to stderr, the tally to stdout, so a CI job can capture
            // one without the other.
            for failure in &report.failures {
                eprintln!("{failure}");
            }
            println!(
                "{} test(s): {} passed, {} failed",
                report.total(),
                report.passed,
                report.failures.len()
            );
            // Zero tests is a failure, not a pass. Every gate that runs
            // `blue test` (a project's `bidama-test-*` and `check` words,
            // `lib.project`) would otherwise stay green over a file that tests
            // nothing: a mistyped path, or a package that lost its tests.
            if report.total() == 0 {
                eprintln!(
                    "{}: no `test` blocks, so nothing was tested",
                    file.display()
                );
                return Ok(ExitCode::FAILURE);
            }
            Ok(if report.ok() {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            })
        }

        Cmd::Deps { file } => {
            let manifest = blue_lang_pkg::read_bluefile(&read(&file)?)
                .map_err(|e| CliError::Pkg(e.to_string()))?;
            println!("{} {}", manifest.name, manifest.version);
            if manifest.manifest.needs.is_empty() {
                println!("  (no dependencies)");
                return Ok(ExitCode::SUCCESS);
            }
            for (dep, range) in &manifest.manifest.needs {
                println!("  needs {dep} {range}");
            }

            // Resolve against the distribution on BLUE_PATH, if there is one.
            //
            // There is still no registry CLIENT — nothing fetches — but
            // `GitRegistry` reads a checkout that is already on disk, and that
            // is a real registry for resolution purposes. Printing "none is
            // configured" while a scannable distribution sat on BLUE_PATH was
            // the CLI declining to use the thing it had.
            let Some(registry) = scan_registry()? else {
                println!("\nno distribution on BLUE_PATH; nothing to resolve against");
                return Ok(ExitCode::SUCCESS);
            };
            // The configured bound, not the constructor's default. This is the
            // only production caller of the solver, so it is the only place
            // `solver_max_steps` can be read — and if it is not read here the
            // knob is decoration.
            let mut solver =
                blue_lang_pkg::Solver::new(&registry).with_max_steps(cfg.solver_max_steps);
            let resolution = solver
                .solve(&manifest.manifest)
                .map_err(|e| CliError::Pkg(e.to_string()))?;
            println!("\nresolved against {} package(s):", registry.len());
            for (name, version) in &resolution.picks {
                println!("  {name} {version}");
            }
            println!(
                "  ({} step(s), {} skipped by learning)",
                solver.steps_taken(),
                solver.skipped_by_learning()
            );
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Posture { file } => {
            let manifest = blue_lang_pkg::read_bluefile(&read(&file)?)
                .map_err(|e| CliError::Pkg(e.to_string()))?;
            let floor = &manifest.floor;
            println!("{} {}", manifest.name, manifest.version);
            println!("  when:  {:?}", floor.when);
            println!("  where: {:?}", floor.place);
            println!("  reach: {}", describe_reach(&floor.reach));

            // What the declaration actually BUYS, from the same derivation
            // `blue morph` prints. A coordinate is not self-explanatory —
            // `when: Preceding` says nothing to a reader about what they just
            // gave up, and the whole point of the morphology is that the answer
            // is computed rather than remembered.
            let grants = blue_lang_bidama::qualities_at(floor);
            let lost = blue_lang_bidama::forfeits_at(floor);
            let names = |qs: &std::collections::BTreeSet<blue_lang_bidama::Quality>| {
                qs.iter().map(|q| q.label()).collect::<Vec<_>>().join(", ")
            };
            println!("\n  grants:   {}", names(&grants));
            println!("  forfeits: {}", names(&lost));
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Bluefile {
            json,
            confirm: _,
            files,
        } => {
            if json {
                let [file] = files.as_slice() else {
                    return Err(CliError::JsonTakesOne { got: files.len() });
                };
                let bluefile = blue_lang_pkg::read_bluefile(&read(file)?)?;
                print!(
                    "{}",
                    blue_lang_pkg::lock::render(&ManifestRecord::of(&bluefile))?
                );
                return Ok(ExitCode::SUCCESS);
            }
            // `--confirm`, the group's only other member. Every file is
            // checked and reported before the exit code is decided, so one
            // stale package does not hide the next.
            let mut all_fresh = true;
            for file in &files {
                let src = read(file)?;
                let lock_path = file.with_file_name(LOCK_FILE);
                let lock_text = match std::fs::read_to_string(&lock_path) {
                    Ok(text) => Some(text),
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
                    Err(source) => {
                        return Err(CliError::Read {
                            path: lock_path.display().to_string(),
                            source,
                        })
                    }
                };
                let verdict = blue_lang_pkg::lock::confirm(&src, lock_text.as_deref())?;
                println!(
                    "{}",
                    serde_json::to_string(&Confirmation {
                        bluefile: file.display().to_string(),
                        verdict: &verdict,
                    })?
                );
                if let Freshness::Stale { reason } = &verdict {
                    let dir = file.parent().filter(|p| !p.as_os_str().is_empty());
                    eprintln!(
                        "blue: {}: {reason}; run `blue lock {}`",
                        file.display(),
                        dir.unwrap_or(Path::new(".")).display()
                    );
                    all_fresh = false;
                }
            }
            Ok(if all_fresh {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            })
        }

        Cmd::Lock { dirs } => {
            let dirs = if dirs.is_empty() {
                vec![PathBuf::from(".")]
            } else {
                dirs
            };
            // Every lock is computed before any is written: a source that fails
            // to pin must not leave half a directory tree relocked.
            let mut locks = Vec::with_capacity(dirs.len());
            for dir in &dirs {
                let src = read(&dir.join(blue_lang_pkg::MANIFEST_FILE))?;
                let lock = blue_lang_pkg::lock::lock(&src, &prefetch::NixPrefetch)?;
                locks.push((dir.join(LOCK_FILE), lock));
            }
            for (path, lock) in &locks {
                std::fs::write(path, blue_lang_pkg::lock::render(lock)?).map_err(|source| {
                    CliError::Write {
                        path: path.display().to_string(),
                        source,
                    }
                })?;
                println!(
                    "{}: {} source(s) pinned",
                    path.display(),
                    lock.sources.len()
                );
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Shift { file } => {
            let reading = blue_lang_lsp::shift_of(&read(&file)?);
            println!("{}", reading.summary());
            if let Some(rung) = reading.rung {
                println!("{}", rung.meaning());
            }
            if reading.factors.is_empty() {
                return Ok(ExitCode::SUCCESS);
            }
            println!();
            for f in &reading.factors {
                // The arrow says which direction each factor pushes, so a
                // reader can tell "this shifted me" from "this is holding me".
                let arrow = if f.kind.shifts_forward() { "→" } else { "·" };
                println!("  {arrow} {:<24} {}", f.kind.label(), f.detail);
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Reference => {
            println!("{}", serde_json::to_string_pretty(&reference::reference())?);
            Ok(ExitCode::SUCCESS)
        }
        Cmd::Morph => {
            use blue_lang_bidama::{
                enforcement, exclusive_pairs, minimal_exclusive_groups, qualities_at, shapes,
                Quality,
            };

            println!("QUALITIES — where each is enforced\n");
            for q in Quality::ALL {
                let (layer, why) = enforcement(q);
                let mark = if layer.is_enforced() { "✓" } else { "·" };
                println!("  {mark} {:<30} {}", q.label(), layer.label());
                println!("      {why}");
            }

            println!("\nMUTUALLY EXCLUSIVE — derived by enumerating the lattice\n");
            for (a, b) in exclusive_pairs() {
                println!(
                    "  {:<30} ⊥ {:<30} (both on the {:?} axis)",
                    a.label(),
                    b.label(),
                    a.axis()
                );
            }
            println!(
                "\n  Every exclusive pair shares an axis. Two qualities on DIFFERENT\n                   coordinates always have a posture granting both — which is what a\n                   per-package posture buys over one global choice."
            );

            // Past two. A trilemma contains no exclusive pair — every pair has
            // a witness and only the whole set does not — so the section above
            // reports it as nothing at all, which looks like a checked absence.
            let groups: Vec<Vec<Quality>> = minimal_exclusive_groups()
                .into_iter()
                .filter(|g| g.len() > 2)
                .collect();
            if !groups.is_empty() {
                println!("\nPICK ANY TWO — minimal exclusive groups past a pair\n");
                for g in &groups {
                    let names: Vec<&str> = g.iter().map(|q| q.label()).collect();
                    println!(
                        "  {}  (all on the {:?} axis)",
                        names.join("  +  "),
                        g[0].axis()
                    );
                }
                println!(
                    "\n  No pair inside a group is exclusive — only the whole group is.\n  \
                     Dropping any one member names a posture that grants the rest."
                );
            }

            println!("\nSHAPES — a language is a point; blue is the space\n");
            for s in shapes() {
                let q = qualities_at(&s.posture);
                println!("  {:<22} {}", s.name, s.because);
                let names: Vec<&str> = q.iter().map(|x| x.label()).collect();
                println!("      grants: {}", names.join(", "));
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Banner => {
            // The version comes from the crate, never a literal — mado shipped a
            // 0.1.0 wordmark against a 0.1.98 binary from exactly that mistake.
            for line in blue_lang_art::wordmark(env!("CARGO_PKG_VERSION")) {
                println!("{}", line.render());
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Config(cmd) => {
            cmd.run::<BlueConfig>(config::TIER_ENV)?;
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Lsp => {
            let stdin = std::io::stdin();
            let stdout = std::io::stdout();
            // The editor sees the distribution `blue check` does: BLUE_PATH.
            blue_lang_lsp::Server::with_loader(Box::new(
                blue_lang_pkg::load_path::LoadPath::from_env(),
            ))
            .serve(stdin.lock(), stdout.lock())
            .map_err(|source| CliError::Write {
                path: "<stdio>".to_string(),
                source,
            })?;
            Ok(ExitCode::SUCCESS)
        }
    }
}

/// `blue check`: the pipeline's check stage over the file and its imports.
fn check(file: &Path, format: Format, fix: bool) -> Result<ExitCode, CliError> {
    use blue_lang_runtime::pipeline::{check_entry, render, syntax_diagnostic, Checking};
    // A file that does not parse has no tree to check, and the compile door
    // below would refuse it with the formatter's message. Report it here as
    // B0006 instead, so a syntax error arrives in the same shape — code,
    // line:col, JSON — as every other finding.
    let raw = read(file)?;
    if let Some(d) = syntax_diagnostic(&raw) {
        match format {
            Format::Json => print!("{}", diagnostics::syntax_json(file, &raw, &d)?),
            Format::Text => {
                let (line, col) = blue_lang_syntax::Span::line_col(&raw, d.span.start);
                eprintln!(
                    "{} {d}",
                    Located {
                        file: file.display().to_string(),
                        line,
                        col,
                    }
                );
            }
        }
        return Ok(ExitCode::FAILURE);
    }
    let loader = blue_lang_pkg::load_path::LoadPath::from_env();
    let mut src = read_compiled(file)?;
    fn entry<'a>(file: &'a Path, text: &'a str) -> blue_lang_runtime::uses::Entry<'a> {
        blue_lang_runtime::uses::Entry {
            path: Some(file),
            text,
        }
    }
    let mut checked = check_entry(entry(file, &src), &loader, None, Checking::WithTests)?;
    if fix {
        let (fixed, applied) =
            diagnostics::apply_machine_fixes(&checked.program, &checked.outcome, &src);
        if applied > 0 {
            std::fs::write(file, &fixed).map_err(|source| CliError::Write {
                path: file.display().to_string(),
                source,
            })?;
            eprintln!("blue: applied {applied} fix(es) to {}", file.display());
            // Re-format (the compile door rewrites a non-canonical file) and
            // re-check what is now on disk.
            src = read_compiled(file)?;
            checked = check_entry(entry(file, &src), &loader, None, Checking::WithTests)?;
        }
    }
    let outcome = &checked.outcome;
    match format {
        Format::Json => print!("{}", diagnostics::json_lines(&checked.program, outcome)?),
        Format::Text => {
            // Report the analysis performed, not just pass/fail. §0's rule is
            // that an invisible cost is the one unacceptable outcome, and the
            // cost of typing is analysis — so it is printed.
            println!("typed declarations: {}", outcome.stats.typed_decls);
            println!("nodes analysed:     {}", outcome.stats.visited);
            println!("seams:              {}", outcome.seams.len());
            println!("names resolved:     {}", outcome.stats.names_resolved);
            println!("waived:             {}", outcome.waived.len());
            // `file:line:col`, the shape every editor and every `cc` already
            // knows how to jump to.
            for seam in &outcome.seams {
                let (line, col) = blue_lang_syntax::Span::line_col(&src, seam.span.start);
                println!(
                    "  {} seam at {} expects {:?}",
                    Located {
                        file: file.display().to_string(),
                        line,
                        col,
                    },
                    seam.at,
                    seam.expected
                );
            }
            for w in &outcome.waived {
                println!(
                    "  {}",
                    render(
                        &checked.program,
                        &blue_lang_check::Diagnostic::new(
                            w.diagnostic.code,
                            format!("waived: {} ({})", w.diagnostic.message, w.waiver.reason),
                            w.diagnostic.span,
                        )
                        .at_top_level(w.diagnostic.top_level)
                    )
                );
            }
            for d in &outcome.diagnostics {
                eprintln!("{}", render(&checked.program, d));
            }
        }
    }
    Ok(if outcome.ok() {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}

/// Bind `--input name=path` pairs against the program's own `definput`
/// declarations.
///
/// The declaration is the contract and the flag supplies the material. Both
/// halves are required, and each missing half is its own error: supplying bytes
/// for a name the program never declared is a different mistake from declaring
/// a name and forgetting the flag, and telling them apart is the difference
/// between a fixable message and a puzzle.
fn bind_inputs(
    src: &str,
    pairs: &[String],
    cfg: &BlueConfig,
) -> Result<blue_lang_runtime::Inputs, CliError> {
    let forms = parse(src, cfg)?;
    let declared = blue_lang_runtime::declarations(&forms);
    let mut inputs = blue_lang_runtime::Inputs::new();

    for pair in pairs {
        let (name, path) = pair.split_once('=').ok_or_else(|| {
            CliError::Pkg("--input expects NAME=PATH, e.g. --input schema=./schema.json".into())
        })?;
        let decl = declared.iter().find(|d| d.name == name).ok_or_else(|| {
            CliError::Pkg(
                "`".to_string()
                    + name
                    + "` was supplied but the program never declares it. Add                        definput(\"" + name + "\", \"b3:…\").",
            )
        })?;
        let bytes = std::fs::read(path).map_err(|source| CliError::Read {
            path: path.to_string(),
            source,
        })?;
        inputs
            .bind(decl, bytes)
            .map_err(|e| CliError::Pkg(e.to_string()))?;
    }

    // A declaration with no material is refused rather than left absent: the
    // macro would otherwise fail deep inside expansion with "no input named …",
    // which points at the macro instead of at the missing flag.
    if let Some(missing) = declared.iter().find(|d| inputs.get(&d.name).is_none()) {
        return Err(CliError::Pkg(
            "input `".to_string()
                + &missing.name
                + "` is declared but no bytes were supplied — pass --input "
                + &missing.name
                + "=<path>",
        ));
    }
    Ok(inputs)
}

fn describe_reach(r: &blue_lang_waku::Reach) -> String {
    match r {
        blue_lang_waku::Reach::Unrestricted => "unrestricted".to_string(),
        blue_lang_waku::Reach::Only(caps) => {
            // Capability LABELS, not the names they grant. A frame's `Reach` is
            // ten things at most; printing the ~66 identifiers behind them would
            // bury the one fact an operator is reading for — whether the frame
            // opens a host effect.
            let list = caps
                .iter()
                .map(|c| c.label())
                .collect::<Vec<_>>()
                .join(", ");
            let mut out = String::with_capacity(list.len() + 6);
            out.push_str("only ");
            out.push_str(&list);
            out
        }
    }
}

/// A value as the operator should read it.
///
/// A `Display` on `Value` would be tatara-lisp's call to make, not blue's, so
/// this is a small local projection rather than a `format!` of arbitrary
/// structure — it names each shape it prints.
fn render(v: &tatara_lisp_eval::Value) -> String {
    use tatara_lisp_eval::Value;
    match v {
        Value::Nil => "nil".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Int(n) => n.to_string(),
        Value::Float(x) => x.to_string(),
        Value::Str(s) => s.to_string(),
        Value::Symbol(s) => s.to_string(),
        Value::Keyword(k) => {
            let mut out = String::with_capacity(k.len() + 1);
            out.push(':');
            out.push_str(k);
            out
        }
        Value::List(items) => {
            let inner = items.iter().map(render).collect::<Vec<_>>().join(", ");
            let mut out = String::with_capacity(inner.len() + 2);
            out.push('[');
            out.push_str(&inner);
            out.push(']');
            out
        }
        other => format!("{other:?}"),
    }
}

/// Which `yakugo` surface to parse in: `BLUE_LANG`, else the host locale.
fn resolve_surface() -> Result<Option<blue_lang_syntax::yakugo::Yakugo>, String> {
    if let Ok(tag) = std::env::var("BLUE_LANG") {
        if tag.is_empty() {
            return Ok(None);
        }
        return match blue_lang_syntax::yakugo::pack_for_locale(&tag)? {
            Some(p) => Ok(Some(p)),
            None => Err(format!(
                "BLUE_LANG=\"{tag}\" names no surface. Available: {}",
                blue_lang_syntax::yakugo::BUILTIN_PACKS
                    .iter()
                    .map(|(t, _)| *t)
                    .collect::<Vec<_>>()
                    .join(", ")
            )),
        };
    }
    // The host locale is a HINT, so an unrecognised one is simply English —
    // unlike an explicit BLUE_LANG, nobody asked for it.
    for var in ["LC_ALL", "LC_MESSAGES", "LANG"] {
        if let Ok(loc) = std::env::var(var) {
            if let Some(p) = blue_lang_syntax::yakugo::pack_for_locale(&loc)? {
                return Ok(Some(p));
            }
        }
    }
    Ok(None)
}
