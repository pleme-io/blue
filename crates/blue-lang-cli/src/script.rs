//! `blue FILE [ARGS…]`: a file is a program.
//!
//! The bare-file rule (`theory/BLUE-TOOLING.md` T-C). When the first argument
//! is not a subcommand and names a script, the command line is rewritten to
//!
//! ```text
//! blue run --quiet FILE -- ARGS…
//! ```
//!
//! before clap sees it, so a bare file and `blue run` are one door: the same
//! load path, the same canonical-source rule, the same exit codes. A script is
//! a `.b` path (missing or not, so a typo is reported as a missing file rather
//! than an unknown subcommand) or an existing file whose first line is a
//! shebang naming `blue` (`#!/usr/bin/env blue`). Every argument after FILE
//! reaches the program verbatim, dashes and `--` included, as the operating
//! system passes them to an interpreter.
//!
//! **A subcommand wins.** `blue test` is the subcommand even beside a file
//! named `test`; `blue ./test` runs the file, since no subcommand name holds a
//! path separator.
//!
//! **A bare file is quiet.** `blue run` prints the program's final value,
//! which is what a person evaluating a file wants to see. A script is a
//! command, and a command's output is what it writes: `python x.py`, `ruby
//! x.rb` and `elixir x.exs` print nothing of their own, and `mkBlueApp`
//! already passes `--quiet` so an installed blue program never ends with a
//! stray `nil`. A file run through its shebang is that same installed
//! program, so the bare form takes the same flag. The value is one
//! `blue run FILE` away.

use std::ffi::OsString;
use std::path::Path;

/// The argument vector clap should parse: `argv` itself, or, when its first
/// argument is a script, the `run --quiet` form of it.
pub fn route(argv: Vec<OsString>, cli: &clap::Command) -> Vec<OsString> {
    let Some(first) = argv.get(1) else {
        return argv;
    };
    let Some(name) = first.to_str() else {
        return argv;
    };
    let subcommand = name == "help" || cli.find_subcommand(name).is_some();
    if name.starts_with('-') || subcommand || !is_script(Path::new(name)) {
        return argv;
    }
    let mut out = Vec::with_capacity(argv.len() + 3);
    out.push(argv[0].clone());
    out.extend(["run", "--quiet"].map(OsString::from));
    out.push(first.clone());
    out.push(OsString::from("--"));
    out.extend(argv.into_iter().skip(2));
    out
}

/// Whether `path` is a blue program to run: a `.b` path, or a file whose
/// first line is a blue shebang.
fn is_script(path: &Path) -> bool {
    if path.extension().is_some_and(|e| e == "b") {
        return true;
    }
    path.is_file() && std::fs::read(path).is_ok_and(|bytes| is_blue_shebang(&bytes))
}

/// Whether `text` opens with a shebang whose interpreter, or an argument of
/// it (`/usr/bin/env blue`, `/usr/bin/env -S blue`), is a program named
/// `blue`.
pub fn is_blue_shebang(text: &[u8]) -> bool {
    let Some(rest) = text.strip_prefix(b"#!") else {
        return false;
    };
    let line = rest.split(|b| *b == b'\n').next().unwrap_or_default();
    String::from_utf8_lossy(line)
        .split_whitespace()
        .any(|word| Path::new(word).file_name().is_some_and(|n| n == "blue"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    fn routed(args: &[&str]) -> Vec<String> {
        let argv = args.iter().map(OsString::from).collect();
        route(argv, &crate::Cli::command())
            .into_iter()
            .map(|a| a.to_string_lossy().into_owned())
            .collect()
    }

    #[test]
    fn a_b_file_runs_quietly_with_its_arguments_verbatim() {
        assert_eq!(
            routed(&["blue", "x.b", "-q", "--", "a"]),
            ["blue", "run", "--quiet", "x.b", "--", "-q", "--", "a"]
        );
    }

    #[test]
    fn subcommands_flags_and_other_files_are_left_to_clap() {
        for args in [
            &["blue"][..],
            &["blue", "test", "x.b"],
            &["blue", "help"],
            &["blue", "--version"],
            &["blue", "Cargo.toml"],
        ] {
            assert_eq!(routed(args), args, "{args:?}");
        }
    }

    #[test]
    fn a_shebang_names_blue_as_the_program_or_an_argument() {
        for yes in [
            "#!/usr/bin/env blue\n1",
            "#!/usr/bin/env -S blue\n",
            "#!/nix/store/x-blue/bin/blue",
        ] {
            assert!(is_blue_shebang(yes.as_bytes()), "{yes}");
        }
        for no in [
            "#!/usr/bin/env bluez\n",
            "#!/bin/sh\nblue x.b\n",
            "# blue\n",
            "",
        ] {
            assert!(!is_blue_shebang(no.as_bytes()), "{no}");
        }
    }
}
