//! `blue new`: a program, a bidama or a script, each ready to run and test.
//!
//! Three shapes, each the smallest one the house already uses:
//!
//! - **a program** (`blue new NAME`) is a blue project: a root `Bluefile`
//!   (`packages("bidamas")`, `app`), its `Bluefile.lock`, the constant stub
//!   `flake.nix` every project carries, a bidama `bidamas/NAME/` holding the
//!   code and its tests, and `main.b`, which calls the bidama's `main` the way
//!   the fleet's commands do. Top-level forms run under `blue test` too, so
//!   the code lives in the bidama and the entry stays one call.
//! - **a bidama** (`blue new --bidama NAME`): `Bluefile`, `Bluefile.lock` and
//!   `NAME.b` with its tests, the layout `bidamas/AUTHORING.md` describes. Run
//!   it inside a distribution's directory.
//! - **a script** (`blue new --script NAME.b`): one executable file opening
//!   with `#!/usr/bin/env blue`.
//!
//! Every file is written in its canonical formatting and every lock is blue's
//! own evaluation of the Bluefile beside it, so `blue fmt --check`, `blue
//! bluefile --confirm` and `blue test` pass on what this writes; the CLI tests
//! hold it to that. Nothing that exists is overwritten.

use std::path::Path;

/// What `blue new` makes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shape {
    Program,
    Bidama,
    Script,
}

const FLAKE: &str = r##"{
  description = "__NAME__, a blue project";

  # A blue project writes no nix: the build facts are in ./Bluefile, and
  # blue's project engine lowers its lock (`blue lock .` after an edit).
  inputs.blue.url = "github:pleme-io/blue";

  outputs = { blue, ... }: blue.lib.project { src = ./.; };
}
"##;

const PROGRAM_BLUEFILE: &str = r##"# __NAME__'s build facts. After an edit, `blue lock .` rewrites Bluefile.lock.
package("__NAME__", "0.1.0")

packages("bidamas")
app("__NAME__", "main.b")
"##;

const MAIN: &str = r##"# `blue main.b ARGS` runs __NAME__; `nix run .#__NAME__ -- ARGS` runs it built.
use("__NAME__", [:main])

main(argv())
"##;

const BIDAMA_BLUEFILE: &str = r##"package("__NAME__", "0.1.0")
needs("retsu", "^0.1")
"##;

const BIDAMA: &str = r##"use("retsu", [:first])

# The greeting for a program's arguments: the first one, or the world.
def greeting(args)
  who = first(args)
  if who == nil
    "hello, world"
  else
    "hello, #{who}"
  end
end

# The program: what `main.b` runs.
def main(args)
  write_stdout("#{greeting(args)}\n")
end

test "with no arguments it greets the world"
  assert greeting([]) == "hello, world"
end

test "it greets the first argument and ignores the rest"
  assert greeting(["blue", "red"]) == "hello, blue"
end

test "an empty name is still a name"
  assert greeting([""]) == "hello, "
end
"##;

const SCRIPT: &str = r##"#!/usr/bin/env blue
# `./__FILE__ ARGS` or `blue __FILE__ ARGS`; `blue new` made it executable.
use("retsu", [:size])

write_stdout("hello, #{argv_get(0, "world")} (#{size(argv())} argument(s))\n")
"##;

/// Make `shape` at `path`, and say what was made and how to run it.
pub fn new(path: &Path, shape: Shape) -> Result<String, String> {
    if path.exists() {
        return Err(format!("{} already exists", path.display()));
    }
    let file_name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .ok_or_else(|| format!("`{}` names no file or directory", path.display()))?;
    match shape {
        Shape::Script => {
            write(path, &SCRIPT.replace("__FILE__", &file_name))?;
            executable(path)?;
            Ok(format!(
                "created {p}, executable\nrun it   ./{p}  (or blue {p})",
                p = path.display()
            ))
        }
        Shape::Bidama => {
            let name = bidama_name(&file_name)?;
            bidama(path, &name)?;
            Ok(format!(
                "created {p}/: Bluefile, Bluefile.lock, {name}.b\ntest it  blue test {p}/{name}.b",
                p = path.display()
            ))
        }
        Shape::Program => {
            let name = bidama_name(&file_name)?;
            let fill = |t: &str| t.replace("__NAME__", &name);
            std::fs::create_dir_all(path).map_err(|e| format!("{}: {e}", path.display()))?;
            write(&path.join("Bluefile"), &fill(PROGRAM_BLUEFILE))?;
            write(&path.join("flake.nix"), &fill(FLAKE))?;
            write(&path.join("main.b"), &fill(MAIN))?;
            lock(path)?;
            bidama(&path.join("bidamas").join(&name), &name)?;
            Ok(format!(
                "created {p}/: Bluefile, Bluefile.lock, flake.nix, main.b, bidamas/{name}/\n\
                 run it   blue {p}/main.b\n\
                 test it  blue test {p}/bidamas/{name}/{name}.b",
                p = path.display()
            ))
        }
    }
}

/// A bidama's directory: its Bluefile, its lock and its source with tests.
fn bidama(dir: &Path, name: &str) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    write(
        &dir.join("Bluefile"),
        &BIDAMA_BLUEFILE.replace("__NAME__", name),
    )?;
    write(&dir.join(format!("{name}.b")), BIDAMA)?;
    lock(dir)
}

/// The name of the bidama a program or package is made around: one
/// identifier, not `blue`, and not a package the standard distribution already
/// has, which it would shadow in every program that uses both.
fn bidama_name(name: &str) -> Result<String, String> {
    if name == blue_lang_syntax::BUILTIN_QUALIFIER {
        return Err(format!(
            "`{name}` cannot name a bidama: `{name}::` names the builtins"
        ));
    }
    if blue_lang_syntax::qualified(&blue_lang_syntax::qualify(name, "x")).is_none() {
        return Err(format!(
            "`{name}` cannot name a bidama: use one lowercase identifier, such as `{}`",
            name.replace(['-', '.'], "")
        ));
    }
    if blue_lang_pkg::embedded::Standard.has(name) {
        return Err(format!(
            "`{name}` is a standard bidama already; a package of that name would shadow it"
        ));
    }
    Ok(name.to_string())
}

/// `blue lock DIR`, which for a Bluefile with no `source` reaches no network.
fn lock(dir: &Path) -> Result<(), String> {
    let bluefile = dir.join(blue_lang_pkg::MANIFEST_FILE);
    let src =
        std::fs::read_to_string(&bluefile).map_err(|e| format!("{}: {e}", bluefile.display()))?;
    let lock = blue_lang_pkg::lock::lock(&src, &crate::prefetch::NixPrefetch)
        .map_err(|e| e.to_string())?;
    let text = blue_lang_pkg::lock::render(&lock).map_err(|e| e.to_string())?;
    write(&dir.join(blue_lang_pkg::lock::LOCK_FILE), &text)
}

fn write(path: &Path, text: &str) -> Result<(), String> {
    std::fs::write(path, text).map_err(|e| format!("{}: {e}", path.display()))
}

#[cfg(unix)]
fn executable(path: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("{}: {e}", path.display()))
}

#[cfg(not(unix))]
fn executable(_path: &Path) -> Result<(), String> {
    Ok(())
}
