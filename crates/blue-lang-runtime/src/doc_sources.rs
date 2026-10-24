//! Where `blue check --fix` finds a definition's intent outside its own file:
//! the verb graph (`bidamas/mokuroku/graph/*.b`), read once per graph
//! directory as data and never run.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

type Meanings = HashMap<(String, String), String>;

/// The verb graph's meanings, `(bidama, verb) -> meaning`, for the bidama
/// file at `path`: the `mokuroku/graph` directory of the nearest ancestor
/// that has one. Empty when no ancestor does.
#[must_use]
pub fn graph_meanings(path: &Path) -> Arc<Meanings> {
    static CACHE: OnceLock<Mutex<HashMap<PathBuf, Arc<Meanings>>>> = OnceLock::new();
    let Some(dir) = path
        .ancestors()
        .skip(1)
        .map(|a| a.join("mokuroku").join("graph"))
        .find(|g| g.is_dir())
    else {
        return Arc::new(Meanings::new());
    };
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(hit) = cache.lock().ok().and_then(|c| c.get(&dir).cloned()) {
        return hit;
    }
    let mut files: Vec<PathBuf> = std::fs::read_dir(&dir)
        .map(|rd| {
            rd.filter_map(Result::ok)
                .map(|e| e.path())
                .filter(|p| p.extension().is_some_and(|e| e == "b"))
                .collect()
        })
        .unwrap_or_default();
    files.sort();
    let texts: Vec<String> = files
        .iter()
        .filter_map(|p| std::fs::read_to_string(p).ok())
        .collect();
    let meanings = Arc::new(blue_lang_check::doc_rules::graph_meanings(&texts));
    if let Ok(mut c) = cache.lock() {
        c.insert(dir, meanings.clone());
    }
    meanings
}
