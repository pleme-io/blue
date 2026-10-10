//! The three doors onto one evaluation session
//! (`blue_lang_runtime::session`): `blue serve` speaks it as JSON lines,
//! `blue repl` at a terminal, `blue eval` once. None of them evaluates
//! anything itself.

use std::io::{BufRead, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicU8, Ordering};

use blue_lang_runtime::session::{
    frame_granting, incomplete, protocol, Config, Load, Outcome, Session, Step, Stop,
};
use blue_lang_waku::Capability;

/// What every session door takes: the frame it evaluates in, and the step
/// budget of a request that names none.
#[derive(clap::Args, Clone, Debug, Default)]
pub struct SessionArgs {
    /// Let evaluation reach a host capability: `host` for all of them, or one
    /// of `process`, `filesystem`, `environment`, `clock`, `network`.
    /// Repeatable. Without it, code that reaches the host is refused as
    /// volatile.
    #[arg(long = "allow", value_name = "CAPABILITY")]
    allow: Vec<String>,
    /// Steps a request may take before it is stopped as exhausted.
    #[arg(long, value_name = "STEPS")]
    budget: Option<usize>,
}

impl SessionArgs {
    fn config(&self) -> Result<Config, String> {
        let mut granted = Vec::new();
        for name in &self.allow {
            if name == "host" {
                granted.extend(Capability::host_effects());
                continue;
            }
            match Capability::host_effects()
                .into_iter()
                .find(|c| c.label() == name)
            {
                Some(c) => granted.push(c),
                None => {
                    return Err(format!(
                        "--allow {name}: the host capabilities are host, {}",
                        Capability::host_effects()
                            .iter()
                            .map(|c| c.label())
                            .collect::<Vec<_>>()
                            .join(", ")
                    ))
                }
            }
        }
        let mut config = Config::new(Box::new(
            blue_lang_pkg::load_path::LoadPath::from_env().with_standard(),
        ));
        config.frame = frame_granting(&granted);
        config.budget = self.budget;
        Ok(config)
    }
}

/// `blue serve`.
pub fn serve(args: &SessionArgs) -> Result<ExitCode, String> {
    let stdin = std::io::stdin();
    protocol::serve(args.config()?, stdin.lock(), std::io::stdout())
        .map_err(|e| format!("serve: {e}"))?;
    Ok(ExitCode::SUCCESS)
}

/// `blue eval EXPR` or `blue eval FILE:LINE:COL`.
pub fn eval(target: &str, args: &SessionArgs) -> Result<ExitCode, String> {
    let mut session = Session::new(args.config()?);
    let outcome = match at_point(target) {
        Some((file, line, col)) => {
            let text = std::fs::read_to_string(&file)
                .map_err(|e| format!("{}: {e}", file.display()))?;
            let form = form_at(&text, line, col).ok_or_else(|| {
                format!("{target}: no top-level form at that point")
            })?;
            session.eval(&text[form], Some(&file), None)
        }
        None => session.eval(target, None, None),
    };
    let Outcome { result, out } = outcome;
    print!("{out}");
    match result {
        Ok(value) => {
            if !out.is_empty() && !out.ends_with('\n') {
                println!();
            }
            println!("{value}");
            Ok(ExitCode::SUCCESS)
        }
        Err(stop) => {
            let _ = std::io::stdout().flush();
            eprintln!("blue: {}", describe(&stop));
            Ok(ExitCode::FAILURE)
        }
    }
}

/// `FILE:LINE:COL`, when `target` names an existing file that way.
fn at_point(target: &str) -> Option<(PathBuf, usize, usize)> {
    let mut parts = target.rsplitn(3, ':');
    let col = parts.next()?.parse().ok()?;
    let line = parts.next()?.parse().ok()?;
    let file = PathBuf::from(parts.next()?);
    file.is_file().then_some((file, line, col))
}

/// The byte range of the top-level form at 1-based `line`:`col`.
fn form_at(text: &str, line: usize, col: usize) -> Option<std::ops::Range<usize>> {
    let start = text
        .split_inclusive('\n')
        .take(line.checked_sub(1)?)
        .map(str::len)
        .sum::<usize>();
    let row = &text[start..];
    let offset = start
        + row
            .char_indices()
            .nth(col.checked_sub(1)?)
            .map_or(row.len(), |(i, _)| i);
    blue_lang_syntax::parse_program_tree(text)
        .ok()?
        .into_iter()
        .find(|f| f.span.start <= offset && offset < f.span.end.max(f.span.start + 1))
        .map(|f| f.span.start..f.span.end)
}

/// A stop as one line a person reads.
fn describe(stop: &Stop) -> String {
    match stop {
        Stop::Error(f) => f.message.clone(),
        Stop::Volatile { reach, name } => format!(
            "volatile: `{name}` reaches the host ({}), which this session does not allow; \
             pass --allow {} (or --allow host) to evaluate it",
            reach.label(),
            reach.label()
        ),
        Stop::Exhausted { limit } => format!("exhausted: the budget of {limit} steps ran out"),
        Stop::Interrupted => "interrupted".to_string(),
    }
}

/// Whether what the code last wrote ended a line: 0 nothing written, 1 yes,
/// 2 no. The REPL starts a value on a fresh line.
static WROTE: AtomicU8 = AtomicU8::new(0);

/// Standard output, noting how the last write ended.
struct Stdout;

impl Write for Stdout {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        if let Some(last) = buf.last() {
            WROTE.store(if *last == b'\n' { 1 } else { 2 }, Ordering::SeqCst);
        }
        std::io::stdout().write(buf)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        std::io::stdout().flush()
    }
}

const HELP: &str = "\
:load FILE     evaluate FILE and evaluate in its context from now on
:expand CODE   expand a macro call fully
:expand1 CODE  expand it one step
:doc NAME      a name's signature and doc
:reset         forget every definition and loaded file
:quit          leave (so does ctrl-d); ctrl-c stops a running evaluation";

/// `blue repl`.
pub fn repl(args: &SessionArgs) -> Result<ExitCode, String> {
    let mut config = args.config()?;
    config.live = Some(Box::new(Stdout));
    let mut session = Session::new(config);
    let flag = session.interrupt_flag();
    sigint::install(&flag);
    let interactive = std::io::stdin().is_terminal();
    let mut history = history();
    let mut context: Option<PathBuf> = None;
    let mut buffer = String::new();
    let stdin = std::io::stdin();
    let mut lines = stdin.lock();
    loop {
        if interactive {
            print!("{}", if buffer.is_empty() { "blue> " } else { "   .. " });
            let _ = std::io::stdout().flush();
        }
        let mut line = String::new();
        let read = lines.read_line(&mut line).map_err(|e| e.to_string())?;
        if interactive && flag.swap(false, Ordering::SeqCst) {
            buffer.clear();
            println!();
            continue;
        }
        if read == 0 && buffer.trim().is_empty() {
            break;
        }
        buffer.push_str(&line);
        if buffer.trim().is_empty() {
            buffer.clear();
            continue;
        }
        if read != 0 && !buffer.trim_start().starts_with(':') && incomplete(&buffer) {
            continue;
        }
        let entry = std::mem::take(&mut buffer);
        let entry = entry.trim();
        if let Some(h) = history.as_mut() {
            let _ = writeln!(h, "{entry}");
        }
        flag.store(false, Ordering::SeqCst);
        WROTE.store(0, Ordering::SeqCst);
        if let Some(command) = entry.strip_prefix(':') {
            let (name, rest) = command.split_once(char::is_whitespace).unwrap_or((command, ""));
            let rest = rest.trim();
            match name {
                "quit" | "q" => break,
                "help" | "h" => println!("{HELP}"),
                "reset" => {
                    session.reset();
                    context = None;
                }
                "load" => {
                    let file = PathBuf::from(rest);
                    match session.load(&file, None, Load::Whole).result {
                        Ok(defined) => {
                            fresh_line();
                            println!("loaded {}: {}", file.display(), defined.join(", "));
                            context = Some(file);
                        }
                        Err(stop) => report(&stop),
                    }
                }
                "expand" | "expand1" => {
                    let step = if name == "expand" { Step::All } else { Step::One };
                    show(session.expand(rest, context.as_deref(), step));
                }
                "doc" => match session.doc(rest, context.as_deref()) {
                    Some(item) => {
                        println!("{}  ({})", item.signature.unwrap_or(item.name), item.namespace);
                        if let Some(doc) = item.doc {
                            println!("  {doc}");
                        }
                    }
                    None => println!("nothing named `{rest}` here"),
                },
                other => println!("no command :{other}; :help lists them"),
            }
        } else {
            show(session.eval(entry, context.as_deref(), None));
        }
        if read == 0 {
            break;
        }
    }
    Ok(ExitCode::SUCCESS)
}

fn show(outcome: Outcome<String>) {
    match outcome.result {
        Ok(v) => {
            fresh_line();
            println!("=> {v}");
        }
        Err(stop) => report(&stop),
    }
}

fn report(stop: &Stop) {
    fresh_line();
    println!("{}", describe(stop));
}

fn fresh_line() {
    if WROTE.swap(0, Ordering::SeqCst) == 2 {
        println!();
    }
}

/// The history file, appended to: `$XDG_STATE_HOME/blue/history`, else
/// `~/.local/state/blue/history`. None when neither can be opened.
fn history() -> Option<std::fs::File> {
    let state = std::env::var_os("XDG_STATE_HOME")
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| Path::new(&h).join(".local/state")))?;
    let dir = state.join("blue");
    std::fs::create_dir_all(&dir).ok()?;
    std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join("history"))
        .ok()
}

/// Ctrl-C sets the session's interrupt flag instead of ending the process.
mod sigint {
    #![deny(unsafe_code)]

    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, OnceLock};

    static FLAG: OnceLock<Arc<AtomicBool>> = OnceLock::new();

    #[cfg(unix)]
    extern "C" fn on_sigint(_: libc::c_int) {
        if let Some(flag) = FLAG.get() {
            flag.store(true, Ordering::SeqCst);
        }
    }

    pub fn install(flag: &Arc<AtomicBool>) {
        if FLAG.set(Arc::clone(flag)).is_err() {
            return;
        }
        #[cfg(unix)]
        // The one seam: registering a handler that only stores to an atomic.
        #[allow(unsafe_code)]
        unsafe {
            libc::signal(
                libc::SIGINT,
                on_sigint as extern "C" fn(libc::c_int) as libc::sighandler_t,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_point_names_the_top_level_form_around_it() {
        let text = "x = 1\ndef f(a)\n  a + x\nend\nf(2)\n";
        assert_eq!(form_at(text, 1, 1).map(|r| &text[r]), Some("x = 1"));
        assert_eq!(
            form_at(text, 3, 5).map(|r| &text[r]),
            Some("def f(a)\n  a + x\nend")
        );
        assert_eq!(form_at(text, 5, 2).map(|r| &text[r]), Some("f(2)"));
        assert_eq!(form_at(text, 9, 1), None);
    }

    #[test]
    fn an_expression_is_not_mistaken_for_a_point() {
        assert_eq!(at_point("1 + 2"), None);
        assert_eq!(at_point("no/such/file.b:1:1"), None);
    }
}
