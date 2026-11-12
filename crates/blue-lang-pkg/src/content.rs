use std::path::{Path, PathBuf};

pub const DOMAIN: &str = "blue-content/v1\n";

#[derive(Debug, thiserror::Error)]
#[error("cannot read {path}: {error}")]
pub struct ContentError {
    pub path: String,
    pub error: String,
}

fn failed(path: &Path, error: impl ToString) -> ContentError {
    ContentError {
        path: path.display().to_string(),
        error: error.to_string(),
    }
}

fn collect(dir: &Path, rel: &str, out: &mut Vec<(String, PathBuf)>) -> Result<(), ContentError> {
    for entry in std::fs::read_dir(dir).map_err(|e| failed(dir, e))? {
        let path = entry.map_err(|e| failed(dir, e))?.path();
        let Some(name) = path
            .file_name()
            .and_then(|n| n.to_str())
            .map(str::to_string)
        else {
            continue;
        };
        if name.starts_with('.') {
            continue;
        }
        let at = if rel.is_empty() {
            name
        } else {
            format!("{rel}/{name}")
        };
        if path.is_dir() {
            collect(&path, &at, out)?;
        } else if path.is_file() {
            out.push((at, path));
        }
    }
    Ok(())
}

pub fn rows(dir: &Path) -> Result<Vec<(String, String)>, ContentError> {
    let mut files = Vec::new();
    collect(dir, "", &mut files)?;
    files.sort();
    files
        .into_iter()
        .map(|(rel, path)| {
            let bytes = std::fs::read(&path).map_err(|e| failed(&path, e))?;
            Ok((rel, blake3::hash(&bytes).to_hex().to_string()))
        })
        .collect()
}

#[must_use]
pub fn root_of(rows: &[(String, String)]) -> String {
    let mut hasher = blake3::Hasher::new();
    hasher.update(DOMAIN.as_bytes());
    for (rel, hash) in rows {
        hasher.update(rel.as_bytes());
        hasher.update(b"\t");
        hasher.update(hash.as_bytes());
        hasher.update(b"\n");
    }
    format!("b3:{}", hasher.finalize().to_hex())
}

pub fn root(dir: &Path) -> Result<String, ContentError> {
    rows(dir).map(|r| root_of(&r))
}

#[cfg(test)]
mod tests {
    use super::*;

    use blue_lang_runtime::scratch::Scratch;

    fn tree(files: &[(&str, &str)]) -> Scratch {
        let dir = Scratch::new("blue-content").expect("mkdir");
        for (rel, text) in files {
            let path = dir.path().join(rel);
            std::fs::create_dir_all(path.parent().expect("parent")).expect("mkdir");
            std::fs::write(path, text).expect("write");
        }
        dir
    }

    #[test]
    fn the_root_is_the_domain_and_each_sorted_row() {
        let t = tree(&[("z.b", "z"), ("a/a.b", "a"), ("Bluefile", "b")]);
        let rows = rows(t.path()).expect("rows");
        let names: Vec<&str> = rows.iter().map(|(r, _)| r.as_str()).collect();
        assert_eq!(names, ["Bluefile", "a/a.b", "z.b"]);
        let mut text = String::from(DOMAIN);
        for (rel, body) in [("Bluefile", "b"), ("a/a.b", "a"), ("z.b", "z")] {
            text.push_str(&format!(
                "{rel}\t{}\n",
                blake3::hash(body.as_bytes()).to_hex()
            ));
        }
        assert_eq!(
            root(t.path()).expect("root"),
            format!("b3:{}", blake3::hash(text.as_bytes()).to_hex())
        );
    }

    #[test]
    fn one_byte_one_rename_and_one_new_file_each_move_the_root_and_a_dotfile_does_not() {
        let base = [("Bluefile", "package"), ("p.b", "def f()\n  1\nend\n")];
        let at = |t: &Scratch| root(t.path()).expect("root");
        let first = at(&tree(&base));
        assert_eq!(first, at(&tree(&base)));
        assert_ne!(first, at(&tree(&[base[0], ("p.b", "def f()\n  2\nend\n")])));
        assert_ne!(first, at(&tree(&[base[0], ("q.b", base[1].1)])));
        assert_ne!(first, at(&tree(&[base[0], base[1], ("x.json", "{}")])));
        assert_eq!(first, at(&tree(&[base[0], base[1], (".git/HEAD", "x")])));
    }
}
