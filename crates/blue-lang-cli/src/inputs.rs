use std::path::{Path, PathBuf};
use std::sync::Mutex;

use blue_lang_mondou::def_hash::DefHash;
use blue_lang_mondou::store::{self, Identity, Store};
use blue_lang_pkg::lock::{Lock, LOCK_FILE};

use crate::CliError;

pub(crate) const GEN_CACHE: &str = "BLUE_GEN_CACHE";

struct Pending {
    store: Store,
    bucket: DefHash,
    rest: [u8; 32],
    program: PathBuf,
    out: PathBuf,
    redo: Box<dyn Fn() -> [u8; 32] + Send>,
}

fn key_of(rest: &[u8; 32], program: &Path) -> [u8; 32] {
    Identity::from_parts(&[b"blue gen v1", rest, &content(program).unwrap_or_default()]).0
}

static PENDING: Mutex<Option<Pending>> = Mutex::new(None);

fn gen_cache_on() -> Result<bool, CliError> {
    match std::env::var(GEN_CACHE) {
        Err(_) => Ok(true),
        Ok(v) => match crate::test_cache::parse(&v) {
            Some(on) => Ok(on),
            None => Err(CliError::Usage(format!(
                "{GEN_CACHE} is \"{v}\"; it takes on (the default) or off"
            ))),
        },
    }
}

fn content(path: &Path) -> Option<[u8; 32]> {
    std::fs::read(path)
        .ok()
        .map(|bytes| Identity::from_parts(&[b"blue gen file v1", &bytes]).0)
}

fn tree(project: &Path, tracked: Option<&[String]>, input: &str) -> [u8; 32] {
    let from = project.join(input);
    let mut files: Vec<String> = match tracked {
        Some(all) => {
            let under = format!("{}/", input.trim_end_matches('/'));
            all.iter()
                .filter(|f| f.as_str() == input || f.starts_with(&under))
                .cloned()
                .collect()
        }
        None if from.is_dir() => walk(&from)
            .into_iter()
            .filter_map(|f| {
                f.strip_prefix(project)
                    .ok()
                    .map(|r| r.to_string_lossy().into_owned())
            })
            .collect(),
        None => vec![input.to_string()],
    };
    files.sort();
    let hashed: Vec<Vec<u8>> = files
        .iter()
        .flat_map(|f| {
            [
                f.as_bytes().to_vec(),
                content(&project.join(f)).map_or_else(Vec::new, |h| h.to_vec()),
            ]
        })
        .collect();
    Identity::from_parts(&hashed.iter().map(Vec::as_slice).collect::<Vec<_>>()).0
}

pub(crate) fn current(file: &Path, args: &[String]) -> Result<bool, CliError> {
    if !gen_cache_on()? || std::env::var_os("GEN_ROOT").is_some() {
        return Ok(false);
    }
    let Some(out) = std::env::var_os("GEN_OUT").filter(|o| !o.is_empty()) else {
        return Ok(false);
    };
    let Some((project, name, inputs)) = declaration(file, Word::Generate) else {
        return Ok(false);
    };
    let Some(store) = store::open_tier("gen") else {
        return Ok(false);
    };
    let out = std::env::current_dir()
        .map(|d| d.join(&out))
        .unwrap_or_else(|_| PathBuf::from(&out));
    let lock: Option<Lock> = std::fs::read_to_string(project.join(LOCK_FILE))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok());
    let packages = lock
        .map(|l| l.manifest.project.packages)
        .unwrap_or_default();
    let fixed: Vec<Vec<u8>> = vec![
        store.identity().0.to_vec(),
        name.into_bytes(),
        out.to_string_lossy().into_owned().into_bytes(),
        args.join("\0").into_bytes(),
        std::env::var("BLUE_PATH").unwrap_or_default().into_bytes(),
    ];
    let redo = move || {
        let tracked = tracked(&project);
        let mut parts = fixed.clone();
        for root in inputs
            .iter()
            .map(|i| ("input", i))
            .chain(packages.iter().map(|p| ("package", p)))
        {
            parts.push(root.0.as_bytes().to_vec());
            parts.push(root.1.as_bytes().to_vec());
            parts.push(tree(&project, tracked.as_deref(), root.1).to_vec());
        }
        Identity::from_parts(&parts.iter().map(Vec::as_slice).collect::<Vec<_>>()).0
    };
    let rest = redo();
    let key = key_of(&rest, file);
    let bucket =
        DefHash(Identity::from_parts(&[b"blue gen output v1", out.to_string_lossy().as_bytes()]).0);
    let written = content(&out);
    if written.is_some()
        && store.load(&bucket).entries.get(&key).is_some_and(|stored| {
            Some(stored.value.as_slice()) == written.as_ref().map(<[u8; 32]>::as_slice)
        })
    {
        eprintln!(
            "blue: {} is current: {} and its inputs hash as the run that wrote it ({GEN_CACHE}=off runs it)",
            out.display(),
            file.display()
        );
        return Ok(true);
    }
    *PENDING
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(Pending {
        store,
        bucket,
        rest,
        program: file.to_path_buf(),
        out,
        redo: Box::new(redo),
    });
    Ok(false)
}

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
    let root = blue_lang_runtime::scratch::held(&format!("blue-inputs-{name}"))
        .map_err(|e| CliError::Usage(format!("{} `{name}`: {e}", word.spelled())))?;
    let made = farm(&project, &root, &inputs).map_err(|why| {
        blue_lang_runtime::scratch::release(&root);
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
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(Declared { note, root });
    Ok(())
}

pub(crate) fn release(failed: bool) {
    let pending = PENDING
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take();
    if let Some(p) = pending.filter(|p| !failed && (p.redo)() == p.rest) {
        if let Some(written) = content(&p.out) {
            if p.store
                .append(
                    &p.bucket,
                    &[(
                        key_of(&p.rest, &p.program),
                        std::time::Duration::ZERO,
                        written.to_vec(),
                    )],
                )
                .is_ok()
            {
                let _ = p.store.evict();
            }
        }
    }
    let held = DECLARED
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take();
    if let Some(d) = held {
        if failed {
            eprintln!("blue: {}", d.note);
        }
        blue_lang_runtime::scratch::release(&d.root);
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
