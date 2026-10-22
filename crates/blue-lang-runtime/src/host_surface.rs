use std::path::{Path, PathBuf};

pub const FILE: &str = "blue-host.json";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostName {
    pub name: String,
    pub params: Vec<String>,
    pub required: usize,
}

impl HostName {
    #[must_use]
    pub fn nullary(&self) -> bool {
        self.params.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Surface {
    pub file: PathBuf,
    pub functions: Vec<HostName>,
}

#[derive(Debug, thiserror::Error)]
pub enum SurfaceError {
    #[error("{file}: {reason}")]
    Unreadable { file: String, reason: String },
}

#[must_use]
pub fn find(entry: &Path) -> Option<PathBuf> {
    entry
        .ancestors()
        .skip(1)
        .map(|dir| dir.join(FILE))
        .find(|candidate| candidate.is_file())
}

pub fn near(entry: &Path) -> Result<Option<Surface>, SurfaceError> {
    find(entry).map(|file| read(&file)).transpose()
}

pub fn read(file: &Path) -> Result<Surface, SurfaceError> {
    let shown = file.display().to_string();
    let unreadable = |reason: String| SurfaceError::Unreadable {
        file: shown.clone(),
        reason,
    };
    let text = std::fs::read_to_string(file).map_err(|e| unreadable(e.to_string()))?;
    parse(&text)
        .map(|functions| Surface {
            file: file.to_path_buf(),
            functions,
        })
        .map_err(unreadable)
}

pub fn parse(text: &str) -> Result<Vec<HostName>, String> {
    let doc: serde_json::Value = serde_json::from_str(text).map_err(|e| e.to_string())?;
    let functions = doc
        .get("functions")
        .and_then(serde_json::Value::as_array)
        .ok_or("expected an object with a `functions` list")?;
    functions
        .iter()
        .enumerate()
        .map(|(i, f)| {
            let name = f
                .get("name")
                .and_then(serde_json::Value::as_str)
                .ok_or(format!("functions[{i}] has no string `name`"))?;
            let params = f
                .get("params")
                .and_then(serde_json::Value::as_array)
                .ok_or(format!("{name} has no `params` list"))?
                .iter()
                .map(|p| p.as_str().map(str::to_owned))
                .collect::<Option<Vec<_>>>()
                .ok_or(format!("{name}'s params are not all strings"))?;
            let required = f
                .get("required")
                .and_then(serde_json::Value::as_u64)
                .and_then(|n| usize::try_from(n).ok())
                .unwrap_or(params.len());
            if required > params.len() {
                return Err(format!(
                    "{name} requires {required} of {} params",
                    params.len()
                ));
            }
            Ok(HostName {
                name: name.to_owned(),
                params,
                required,
            })
        })
        .collect()
}

#[must_use]
pub fn render<'a>(
    functions: impl IntoIterator<Item = (&'a str, &'a [&'a str], usize, &'a str)>,
) -> String {
    let functions: Vec<serde_json::Value> = functions
        .into_iter()
        .map(|(name, params, required, doc)| {
            serde_json::json!({
                "name": name,
                "params": params,
                "required": required,
                "doc": doc,
            })
        })
        .collect();
    let mut out = serde_json::to_string_pretty(&serde_json::json!({ "functions": functions }))
        .unwrap_or_default();
    out.push('\n');
    out
}
