use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;

const ROOT: &str = "blue-scratch";
const LOCK: &str = "lock";
const PENDING: &str = "pending";
const LEGACY: &[&str] = &["blue-inputs-"];
const LEGACY_AGE: std::time::Duration = std::time::Duration::from_secs(24 * 60 * 60);

static NEXT: AtomicU64 = AtomicU64::new(0);
static REAPED: AtomicBool = AtomicBool::new(false);
static HELD: Mutex<Vec<Scratch>> = Mutex::new(Vec::new());

pub fn root() -> PathBuf {
    std::env::temp_dir().join(ROOT)
}

#[derive(Debug)]
pub struct Scratch {
    path: PathBuf,
    lock: PathBuf,
    owner: Option<File>,
}

impl Scratch {
    pub fn new(label: &str) -> std::io::Result<Scratch> {
        let root = root();
        std::fs::create_dir_all(&root)?;
        if !REAPED.swap(true, Ordering::SeqCst) {
            reap(&root);
        }
        let label = tidy(label);
        loop {
            let name = format!(
                "{label}-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::SeqCst)
            );
            let pending = root.join(format!("{name}.{PENDING}"));
            let owner = match OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&pending)
            {
                Ok(f) => f,
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            };
            owner.lock()?;
            let lock = root.join(format!("{name}.{LOCK}"));
            let path = root.join(&name);
            if lock.exists() || path.exists() {
                let _ = std::fs::remove_file(&pending);
                continue;
            }
            std::fs::rename(&pending, &lock)?;
            let made = Scratch {
                path,
                lock,
                owner: Some(owner),
            };
            std::fs::create_dir(&made.path)?;
            return Ok(made);
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
        let _ = std::fs::remove_file(&self.lock);
        self.owner.take();
    }
}

pub fn held(label: &str) -> std::io::Result<PathBuf> {
    let s = Scratch::new(label)?;
    let path = s.path.clone();
    HELD.lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .push(s);
    Ok(path)
}

pub fn release(path: &Path) {
    let mut held = HELD
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    held.retain(|s| s.path != path);
}

pub fn release_all() {
    let drained: Vec<Scratch> = std::mem::take(
        &mut *HELD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner),
    );
    drop(drained);
}

#[derive(Debug, Default)]
pub struct ReleaseOnDrop;

impl Drop for ReleaseOnDrop {
    fn drop(&mut self) {
        release_all();
    }
}

fn tidy(label: &str) -> String {
    let t: String = label
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect();
    if t.is_empty() {
        "scratch".into()
    } else {
        t
    }
}

pub fn reap(root: &Path) {
    let Ok(entries) = std::fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
            continue;
        };
        if ext != LOCK && ext != PENDING {
            continue;
        }
        let Ok(f) = OpenOptions::new().write(true).open(&path) else {
            continue;
        };
        if f.try_lock().is_err() {
            continue;
        }
        if ext == LOCK {
            let _ = std::fs::remove_dir_all(path.with_extension(""));
        }
        let _ = std::fs::remove_file(&path);
    }
    if let Some(tmp) = root.parent() {
        reap_legacy(tmp);
    }
}

fn reap_legacy(tmp: &Path) {
    let Ok(entries) = std::fs::read_dir(tmp) else {
        return;
    };
    let now = std::time::SystemTime::now();
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !LEGACY.iter().any(|p| name.starts_with(p)) {
            continue;
        }
        let old = entry
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|m| now.duration_since(m).ok())
            .is_some_and(|age| age >= LEGACY_AGE);
        if old {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_scratch_is_an_empty_directory_gone_when_dropped_with_its_lock() {
        let s = Scratch::new("unit drop").unwrap();
        let (dir, lock) = (s.path().to_path_buf(), s.lock.clone());
        assert!(dir.is_dir() && lock.is_file());
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 0);
        assert!(dir
            .file_name()
            .unwrap()
            .to_string_lossy()
            .starts_with("unit-drop-"));
        drop(s);
        assert!(!dir.exists() && !lock.exists());
    }

    #[test]
    fn a_live_owner_is_never_reaped_and_a_dead_one_is() {
        let live = Scratch::new("unit-live").unwrap();
        let mut dead = Scratch::new("unit-dead").unwrap();
        std::fs::write(dead.path().join("f"), "x").unwrap();
        let (dead_dir, dead_lock) = (dead.path.clone(), dead.lock.clone());
        dead.owner.take();
        dead.path = PathBuf::new();
        dead.lock = PathBuf::new();
        reap(&root());
        assert!(live.path().is_dir());
        assert!(!dead_dir.exists() && !dead_lock.exists());
    }

    #[test]
    fn a_held_directory_lives_until_release_all() {
        let p = held("unit-held").unwrap();
        assert!(p.is_dir());
        release(&p);
        assert!(!p.exists());
        let q = held("unit-held").unwrap();
        release_all();
        assert!(!q.exists());
    }
}
