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
//! blue check   FILE            the sliding-scale report: analysis and seams
//! blue test    FILE            run the file's `test` blocks
//! blue deps    BLUEFILE        resolve the manifest's dependencies
//! blue posture BLUEFILE        the posture the manifest's floors require
//! blue config  [TIER]          the bounds blue is running with
//! blue lsp                     speak LSP over stdio
//! blue banner                  the wordmark — the blueshift ramp
//! blue shift   FILE            how far this is shifted, and what is shifting it
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
//! Every subcommand runs under the bounds in `config` — resolved once, here,
//! and threaded down.
//!
//! `blue ast` and `blue erase` are separate on purpose: the difference
//! between them *is* the sliding scale, and being able to print both sides of
//! it is how a reader sees that annotations are consumed rather than carried.

mod config;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

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
    },
    /// Format a program. There is one formatting; this produces it.
    Fmt {
        file: PathBuf,
        /// Report drift and exit non-zero instead of rewriting.
        #[arg(long)]
        check: bool,
        /// Rewrite the file in place.
        #[arg(long)]
        write: bool,
    },
    /// Print the tatara-lisp form, annotations intact.
    Ast { file: PathBuf },
    /// Print the tatara-lisp form after type erasure — what actually runs.
    Erase { file: PathBuf },
    /// Report what the type checker did: analysis performed, seams found.
    Check { file: PathBuf },
    /// Run the file's `test` blocks.
    Test { file: PathBuf },
    /// Resolve a Bluefile's dependencies. Does not fetch.
    Deps { file: PathBuf },
    /// Report the posture a Bluefile's declared floor requires.
    Posture { file: PathBuf },
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
    #[error("{0}")]
    Config(#[from] shikumi::cli::ConfigShowError),
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
    match cli.cmd {
        Cmd::Run { file, inputs } => {
            let src = read(&file)?;
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
            let out = blue_lang_runtime::pipeline::run_with_loader(
                &src,
                bind_inputs(&src, &inputs, &cfg)?,
                &loader,
            )?;
            println!("{}", render(&out.value));
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Fmt { file, check, write } => {
            let src = read(&file)?;
            // The LOSSLESS rendering is the canonical form of a file that has
            // comments, so `--check` must compare against it. Comparing against
            // the comment-stripped rendering made every commented file report
            // "not formatted" forever — a --check that can never be satisfied.
            let formatted = blue_lang_fmt::format_source_lossless(&src)
                .map_err(|e| CliError::Fmt(e.to_string()))?;
            if check {
                // Compare trimmed: a trailing newline is not drift.
                if formatted.trim_end() == src.trim_end() {
                    return Ok(ExitCode::SUCCESS);
                }
                eprintln!("{}: not formatted", file.display());
                return Ok(ExitCode::FAILURE);
            }
            if write {
                // The LOSSLESS path, because this overwrites the file. blue's
                // formatter drops comments, and `--write` used to delete every
                // one silently. Refusing is strictly better than losing the one
                // part of a program a machine cannot reconstruct.
                let formatted = blue_lang_fmt::format_source_lossless(&src)
                    .map_err(|e| CliError::Fmt(e.to_string()))?;
                std::fs::write(&file, &formatted).map_err(|source| CliError::Write {
                    path: file.display().to_string(),
                    source,
                })?;
            } else {
                print!("{formatted}");
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Ast { file } => {
            for form in parse(&read(&file)?, &cfg)? {
                println!("{form}");
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Erase { file } => {
            let forms = parse(&read(&file)?, &cfg)?;
            for form in blue_lang_runtime::erase_types(&forms) {
                println!("{form}");
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Check { file } => {
            let forms = parse(&read(&file)?, &cfg)?;
            let outcome = blue_lang_check::check_program(&forms);
            // Report the analysis performed, not just pass/fail. §0's rule is
            // that an invisible cost is the one unacceptable outcome, and the
            // cost of typing is analysis — so it is printed.
            println!("typed declarations: {}", outcome.stats.typed_decls);
            println!("nodes analysed:     {}", outcome.stats.visited);
            println!("seams:              {}", outcome.seams.len());
            for seam in &outcome.seams {
                println!("  seam at {} expects {:?}", seam.at, seam.expected);
            }
            for d in &outcome.diagnostics {
                eprintln!("error: {d}");
            }
            Ok(if outcome.ok() {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            })
        }

        Cmd::Test { file } => {
            let forms = parse(&read(&file)?, &cfg)?;
            // Imports resolve here too, for the same reason they do in `run`.
            //
            // Wiring only `run` was a real gap and it failed loudly the first
            // time a bidama with a dependency was tested: EVERY test in the
            // file errored with `unbound symbol: use`, because the import never
            // expanded and `use` reached the evaluator as a call. A package
            // that cannot be tested with its dependencies is a package with no
            // tests, so this is not a convenience — a distribution where only
            // the leaf packages can be tested has no gate on the rest.
            let forms = blue_lang_runtime::uses::resolve_uses(
                forms,
                &blue_lang_pkg::load_path::LoadPath::from_env(),
            )
            .map_err(blue_lang_runtime::pipeline::RunError::Import)?;
            let report = blue_lang_test::run(&forms);
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

        Cmd::Morph => {
            use blue_lang_bidama::{enforcement, exclusive_pairs, qualities_at, shapes, Quality};

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
            blue_lang_lsp::Server::new()
                .serve(stdin.lock(), stdout.lock())
                .map_err(|source| CliError::Write {
                    path: "<stdio>".to_string(),
                    source,
                })?;
            Ok(ExitCode::SUCCESS)
        }
    }
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
        blue_lang_waku::Reach::Only(names) => {
            let list = names.iter().cloned().collect::<Vec<_>>().join(", ");
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
