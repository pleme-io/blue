use std::path::{Path, PathBuf};
use std::sync::Mutex;

use blue_lang_pkg::lock::{Lock, LOCK_FILE};

use crate::CliError;

#[derive(Clone, Copy)]
pub(crate) enum Word {
    Check,
    Generate,
}

impl Word {
    fn spelled(self) -> &'static str {
        match self {
            Word::Check => "check",
            Word::Generate => "generate",
        }
    }
}

struct Declared {
    note: String,
    root: PathBuf,
}

static DECLARED: Mutex<Option<Declared>> = Mutex::new(None);

pub(crate) fn hold(file: &Path, word: Word) -> Result<(), CliError> {
    match std::env::var("BLUE_INPUTS").as_deref() {
        Err(_) | Ok("declared") => {}
        Ok("checkout") => return Ok(()),
        Ok(other) => {
            return Err(CliError::Usage(format!(
                "BLUE_INPUTS is \"{other}\"; it takes declared (the default) or checkout"
            )))
        }
    }
    if std::env::var_os("GEN_ROOT").is_some() {
        return Ok(());
    }
    let Some((project, name, inputs)) = declaration(file, word) else {
        return Ok(());
    };
    let root = std::env::temp_dir().join(format!(
        "blue-inputs-{}-{}",
        name.replace(|c: char| !c.is_ascii_alphanumeric(), "-"),
        std::process::id()
    ));
    let made = farm(&project, &root, &inputs).map_err(|why| {
        let _ = std::fs::remove_dir_all(&root);
        CliError::Usage(format!("{} `{name}`: {why}", word.spelled()))
    })?;
    std::env::set_var("GEN_ROOT", &made);
    let read = if inputs.is_empty() {
        "no project path".to_string()
    } else {
        inputs
            .iter()
            .map(|i| format!("`{i}`"))
            .collect::<Vec<_>>()
            .join(", ")
    };
    let note = format!(
        "{} ran as {}(\"{name}\"), so GEN_ROOT held only what it declares ({read}), as nix runs it; BLUE_INPUTS=checkout reads the whole checkout",
        file.display(),
        word.spelled()
    );
    *DECLARED
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(Declared { note, root: made });
    Ok(())
}

pub(crate) fn release(failed: bool) {
    let held = DECLARED
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take();
    if let Some(d) = held {
        if failed {
            eprintln!("blue: {}", d.note);
        }
        let _ = std::fs::remove_dir_all(&d.root);
    }
}

fn declaration(file: &Path, word: Word) -> Option<(PathBuf, String, Vec<String>)> {
    let file = std::fs::canonicalize(file).ok()?;
    let project = file
        .ancestors()
        .skip(1)
        .find(|d| d.join(LOCK_FILE).is_file())?
        .to_path_buf();
    let rel = file
        .strip_prefix(&project)
        .ok()?
        .components()
        .map(|c| c.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("/");
    let lock: Lock =
        serde_json::from_str(&std::fs::read_to_string(project.join(LOCK_FILE)).ok()?).ok()?;
    let p = lock.manifest.project;
    let (name, inputs) = match word {
        Word::Check => p
            .checks
            .into_iter()
            .find(|(_, c)| c.file == rel)
            .map(|(n, c)| (n, c.inputs))?,
        Word::Generate => p
            .generated
            .into_iter()
            .find(|(_, g)| g.program == rel)
            .map(|(n, g)| (n, g.inputs))?,
    };
    Some((project, name, inputs))
}

fn farm(project: &Path, root: &Path, inputs: &[String]) -> Result<PathBuf, String> {
    let _ = std::fs::remove_dir_all(root);
    let (store, top) = (root.join("store"), root.join("root"));
    for dir in [&store, &top] {
        std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    }
    let tracked = tracked(project);
    for (i, input) in inputs.iter().enumerate() {
        let from = project.join(input);
        if !from.exists() {
            return Err(format!(
                "it declares the input `{input}`, and {} does not exist",
                from.display()
            ));
        }
        let base = Path::new(input)
            .file_name()
            .map_or_else(|| input.clone(), |n| n.to_string_lossy().into_owned());
        let copy = store.join(format!("{i}-{base}"));
        let files: Vec<(PathBuf, PathBuf)> = match &tracked {
            Some(all) if from.is_dir() => {
                let under = format!("{}/", input.trim_end_matches('/'));
                all.iter()
                    .filter_map(|f| {
                        f.strip_prefix(&under)
                            .map(|rest| (project.join(f), copy.join(rest)))
                    })
                    .filter(|(src, _)| src.is_file())
                    .collect()
            }
            Some(all) if all.iter().any(|f| f == input) => vec![(from.clone(), copy.clone())],
            Some(_) => Vec::new(),
            None if from.is_dir() => walk(&from)
                .into_iter()
                .filter_map(|src| {
                    let rest = src.strip_prefix(&from).ok()?.to_path_buf();
                    Some((src, copy.join(rest)))
                })
                .collect(),
            None => vec![(from.clone(), copy.clone())],
        };
        if files.is_empty() {
            return Err(format!(
                "it declares the input `{input}`, and git tracks no file there, so the nix sandbox would see none; run git add on it"
            ));
        }
        for (src, dst) in &files {
            if let Some(parent) = dst.parent() {
                std::fs::create_dir_all(parent)
                    .map_err(|e| format!("{}: {e}", parent.display()))?;
            }
            std::fs::copy(src, dst).map_err(|e| format!("{}: {e}", src.display()))?;
        }
        let to = top.join(input);
        if let Some(parent) = to.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
        }
        std::os::unix::fs::symlink(&copy, &to).map_err(|e| format!("{}: {e}", to.display()))?;
    }
    std::fs::canonicalize(&top).map_err(|e| format!("{}: {e}", top.display()))
}

fn tracked(project: &Path) -> Option<Vec<String>> {
    let out = std::process::Command::new("git")
        .arg("-C")
        .arg(project)
        .args(["ls-files", "-z"])
        .env_remove("GIT_DIR")
        .env_remove("GIT_WORK_TREE")
        .env_remove("GIT_INDEX_FILE")
        .output()
        .ok()
        .filter(|o| o.status.success())?;
    Some(
        out.stdout
            .split(|b| *b == 0)
            .filter(|f| !f.is_empty())
            .map(|f| String::from_utf8_lossy(f).into_owned())
            .collect(),
    )
}

fn walk(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut dirs = vec![dir.to_path_buf()];
    while let Some(d) = dirs.pop() {
        for entry in std::fs::read_dir(&d).into_iter().flatten().flatten() {
            let path = entry.path();
            if path.is_dir() {
                dirs.push(path);
            } else if path.is_file() {
                out.push(path);
            }
        }
    }
    out
}
