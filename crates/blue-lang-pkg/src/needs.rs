use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use blue_lang_runtime::uses::Loader;

use crate::version::{Range, Version};

pub fn uses_in<'a>(sources: impl IntoIterator<Item = &'a str>) -> BTreeSet<String> {
    sources
        .into_iter()
        .filter_map(|text| blue_lang_syntax::parse_program_tree(text).ok())
        .flat_map(|forms| {
            forms
                .iter()
                .filter_map(blue_lang_syntax::scope::use_target)
                .map(|i| i.package)
                .collect::<Vec<_>>()
        })
        .collect()
}

#[must_use]
pub fn used_by(dir: &Path) -> BTreeSet<String> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return BTreeSet::new();
    };
    let texts: Vec<String> = entries
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("b"))
        .filter_map(|p| std::fs::read_to_string(p).ok())
        .collect();
    uses_in(texts.iter().map(String::as_str))
}

#[must_use]
pub fn compatible(v: Version) -> Range {
    Range::Caret(match v {
        Version {
            major: 0, minor: 0, ..
        } => v,
        Version {
            major: 0, minor, ..
        } => Version {
            major: 0,
            minor,
            patch: 0,
        },
        Version { major, .. } => Version {
            major,
            minor: 0,
            patch: 0,
        },
    })
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{}: {}", bluefile.display(), refusal(unused, absent))]
pub struct NeedsError {
    pub bluefile: PathBuf,
    pub unused: Vec<String>,
    pub absent: Vec<String>,
}

#[must_use]
pub fn refusal(unused: &[String], absent: &[String]) -> String {
    unused
        .iter()
        .map(|n| format!(
            "`needs(\"{n}\", …)` names a package no file of this bidama uses; delete the row or `use(\"{n}\")` (`blue check --fix` on a file of the bidama deletes the row)"
        ))
        .chain(absent.iter().map(|n| format!(
            "a file uses \"{n}\", and no root on the load path holds a bidama of that name; add its root to the project's `packages(...)` or to BLUE_PATH, or remove the `use`"
        )))
        .collect::<Vec<_>>()
        .join("; ")
}

pub fn derive(
    dir: &Path,
    bf: &crate::Bluefile,
    loader: &dyn Loader,
) -> Result<BTreeMap<String, Range>, NeedsError> {
    if crate::load_path::bidama_of(bf).is_none() {
        return Ok(bf.manifest.needs.clone());
    }
    let mut used = used_by(dir);
    used.remove(&bf.name);
    let mut err = NeedsError {
        bluefile: dir.join(crate::MANIFEST_FILE),
        unused: bf
            .manifest
            .needs
            .keys()
            .filter(|n| !used.contains(*n))
            .cloned()
            .collect(),
        absent: Vec::new(),
    };
    let mut out = BTreeMap::new();
    for name in used {
        if let Some(range) = bf.manifest.needs.get(&name) {
            out.insert(name, *range);
            continue;
        }
        match loader
            .version(&name, None)
            .and_then(|v| Version::parse(&v).ok())
        {
            Some(v) => {
                out.insert(name, compatible(v));
            }
            None => err.absent.push(name),
        }
    }
    if err.unused.is_empty() && err.absent.is_empty() {
        Ok(out)
    } else {
        Err(err)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pruned {
    pub bluefile: String,
    pub removed: Vec<String>,
}

fn needs_line(line: &str) -> Option<String> {
    let rest = line.trim_start().strip_prefix("needs(\"")?;
    Some(rest.split('"').next()?.to_string())
}

pub fn prune(dir: &Path) -> Result<Option<Pruned>, String> {
    let path = dir.join(crate::MANIFEST_FILE);
    let text = std::fs::read_to_string(&path)
        .map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    let bf = crate::read_bluefile(&text).map_err(|e| format!("{}: {e}", path.display()))?;
    if crate::load_path::bidama_of(&bf).is_none() {
        return Ok(None);
    }
    let used = used_by(dir);
    let removed: Vec<String> = bf
        .manifest
        .needs
        .keys()
        .filter(|n| !used.contains(*n))
        .cloned()
        .collect();
    if removed.is_empty() {
        return Ok(None);
    }
    let mut bluefile = text
        .lines()
        .filter(|l| needs_line(l).is_none_or(|n| !removed.contains(&n)))
        .collect::<Vec<_>>()
        .join("\n");
    bluefile.push('\n');
    Ok(Some(Pruned { bluefile, removed }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str, files: &[(&str, &str)]) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("blue-needs-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        for (rel, text) in files {
            let p = root.join(rel);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, text).unwrap();
        }
        root
    }

    fn derived(root: &Path, pkg: &str) -> Result<BTreeMap<String, String>, NeedsError> {
        let d = root.join("dist").join(pkg);
        let bf =
            crate::read_bluefile(&std::fs::read_to_string(d.join("Bluefile")).unwrap()).unwrap();
        let lp = crate::load_path::LoadPath::new([root.join("dist")]);
        derive(&d, &bf, &lp).map(|m| m.into_iter().map(|(k, r)| (k, r.to_string())).collect())
    }

    #[test]
    fn a_use_is_a_need_and_a_hand_row_only_narrows_it() {
        let root = dir(
            "derive",
            &[
                ("dist/kagi/Bluefile", "package(\"kagi\", \"0.3.2\")\n"),
                ("dist/kagi/kagi.b", "def k()\n  1\nend\n"),
                ("dist/tobi/Bluefile", "package(\"tobi\", \"1.4.0\")\n"),
                ("dist/tobi/tobi.b", "def t()\n  1\nend\n"),
                (
                    "dist/user/Bluefile",
                    "package(\"user\", \"0.1.0\")\nneeds(\"tobi\", \"^1.4\")\n",
                ),
                (
                    "dist/user/user.b",
                    "use(\"kagi\")\nuse(\"tobi\")\n\nkagi::k + tobi::t\n",
                ),
            ],
        );
        let got = derived(&root, "user").unwrap();
        assert_eq!(got["kagi"], "^0.3.0");
        assert_eq!(got["tobi"], "^1.4.0");
        assert_eq!(got.len(), 2);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn an_unused_row_and_an_absent_package_are_refused_by_name() {
        let root = dir(
            "refuse",
            &[
                (
                    "dist/user/Bluefile",
                    "package(\"user\", \"0.1.0\")\nneeds(\"gone\", \"^0.1\")\ntool(\"git\")\n",
                ),
                ("dist/user/user.b", "use(\"nowhere\")\n\nnowhere::x\n"),
            ],
        );
        let err = derived(&root, "user").unwrap_err();
        assert_eq!(err.unused, vec!["gone".to_string()]);
        assert_eq!(err.absent, vec!["nowhere".to_string()]);
        let msg = err.to_string();
        assert!(
            msg.contains("delete the row") && msg.contains("remove the `use`"),
            "{msg}"
        );
        let pruned = prune(&root.join("dist/user")).unwrap().expect("a row goes");
        assert_eq!(pruned.removed, vec!["gone".to_string()]);
        assert_eq!(
            pruned.bluefile,
            "package(\"user\", \"0.1.0\")\ntool(\"git\")\n"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_projects_needs_are_its_rows() {
        let root = dir(
            "project",
            &[(
                "dist/proj/Bluefile",
                "package(\"my-proj\", \"0.1.0\")\nneeds(\"kagi\", \"^0.1\")\npackages(\"bidamas\")\n",
            )],
        );
        let got = derived(&root, "proj").unwrap();
        assert_eq!(got["kagi"], "^0.1.0");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn the_compatible_range_of_a_version_is_its_caret_class() {
        let r = |s| compatible(Version::parse(s).unwrap()).to_string();
        assert_eq!(r("0.1.7"), "^0.1.0");
        assert_eq!(r("2.3.4"), "^2.0.0");
        assert_eq!(r("0.0.3"), "^0.0.3");
    }

    #[test]
    fn every_bidama_of_the_distribution_derives() {
        let dist = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../bidamas");
        let lp = crate::load_path::LoadPath::new([dist.clone()]);
        let mut refused = Vec::new();
        for entry in std::fs::read_dir(&dist).unwrap().filter_map(Result::ok) {
            let d = entry.path();
            let Ok(text) = std::fs::read_to_string(d.join(crate::MANIFEST_FILE)) else {
                continue;
            };
            let bf = crate::read_bluefile(&text).unwrap();
            if let Err(e) = derive(&d, &bf, &lp) {
                refused.push(e.to_string());
            }
        }
        assert!(refused.is_empty(), "{refused:#?}");
    }
}
