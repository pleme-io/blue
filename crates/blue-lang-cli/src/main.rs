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
//! ```
//!
//! **`blue posture` is deliberately absent.** A posture is resolved from the
//! *floors a package set declares* (`blue_lang_bidama::resolve`), and blue has
//! no package-declaration surface yet — no `Bluefile`, no `defbidama` reader.
//! A subcommand that read postures out of a single source file would be
//! inventing a declaration format ahead of the design, so it waits for the
//! package manager rather than shipping a guess.
//!
//! `blue ast` and `blue erase` are separate on purpose: the difference
//! between them *is* the sliding scale, and being able to print both sides of
//! it is how a reader sees that annotations are consumed rather than carried.

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::{Parser, Subcommand};

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
    Run { file: PathBuf },
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
}

fn read(path: &Path) -> Result<String, CliError> {
    std::fs::read_to_string(path).map_err(|source| CliError::Read {
        path: path.display().to_string(),
        source,
    })
}

fn dispatch(cli: Cli) -> Result<ExitCode, CliError> {
    match cli.cmd {
        Cmd::Run { file } => {
            let out = blue_lang_runtime::run(&read(&file)?)?;
            println!("{}", render(&out.value));
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Fmt { file, check, write } => {
            let src = read(&file)?;
            let formatted =
                blue_lang_fmt::format_source(&src).map_err(|e| CliError::Fmt(e.to_string()))?;
            if check {
                // Compare trimmed: a trailing newline is not drift.
                if formatted.trim_end() == src.trim_end() {
                    return Ok(ExitCode::SUCCESS);
                }
                eprintln!("{}: not formatted", file.display());
                return Ok(ExitCode::FAILURE);
            }
            if write {
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
            for form in blue_lang_runtime::parse(&read(&file)?)? {
                println!("{form}");
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Erase { file } => {
            let forms = blue_lang_runtime::parse(&read(&file)?)?;
            for form in blue_lang_runtime::erase_types(&forms) {
                println!("{form}");
            }
            Ok(ExitCode::SUCCESS)
        }

        Cmd::Check { file } => {
            let forms = blue_lang_runtime::parse(&read(&file)?)?;
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
            let forms = blue_lang_runtime::parse(&read(&file)?)?;
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
