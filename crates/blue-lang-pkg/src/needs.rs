use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use blue_lang_runtime::uses::Loader;

#[must_use]
pub fn used_by(dir: &Path) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    let Ok(entries) = std::fs::read_dir(dir) else {
        return out;
    };
    for entry in entries.filter_map(Result::ok) {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("b") {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(&path) else {
            continue;
        };
        let Ok(forms) = blue_lang_syntax::parse_program_tree(&text) else {
            continue;
        };
        out.extend(
            forms
                .iter()
                .filter_map(blue_lang_syntax::scope::use_target)
                .map(|i| i.package),
        );
    }
    out
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reconciled {
    pub bluefile: String,
    pub added: Vec<String>,
    pub removed: Vec<String>,
}

fn needs_line(line: &str) -> Option<String> {
    let rest = line.trim_start().strip_prefix("needs(\"")?;
    Some(rest.split('"').next()?.to_string())
}

pub fn reconcile(dir: &Path, loader: &dyn Loader) -> Result<Option<Reconciled>, String> {
    let path = dir.join(crate::MANIFEST_FILE);
    let text = std::fs::read_to_string(&path)
        .map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    let bf = crate::read_bluefile(&text).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut used = used_by(dir);
    used.remove(&bf.name);
    let have: BTreeSet<String> = bf.manifest.needs.keys().cloned().collect();
    let removed: Vec<String> = have.difference(&used).cloned().collect();
    let mut added: BTreeMap<String, String> = BTreeMap::new();
    for name in used.difference(&have) {
        let version = loader
            .version(name, None)
            .and_then(|v| crate::version::Version::parse(&v).ok())
            .ok_or_else(|| {
                format!(
                    "{}: a file uses \"{name}\" and no root on the load path holds it, so no `needs` row can be derived",
                    dir.display()
                )
            })?;
        added.insert(
            name.clone(),
            format!("^{}.{}", version.major, version.minor),
        );
    }
    if removed.is_empty() && added.is_empty() {
        return Ok(None);
    }
    let mut lines: Vec<String> = text
        .lines()
        .filter(|l| needs_line(l).is_none_or(|n| !removed.contains(&n)))
        .map(str::to_string)
        .collect();
    let anchor = lines
        .iter()
        .rposition(|l| needs_line(l).is_some())
        .or_else(|| {
            lines
                .iter()
                .position(|l| l.trim_start().starts_with("package("))
        })
        .map_or(lines.len(), |i| i + 1);
    for (offset, (name, range)) in added.iter().enumerate() {
        lines.insert(anchor + offset, format!("needs(\"{name}\", \"{range}\")"));
    }
    let mut bluefile = lines.join("\n");
    bluefile.push('\n');
    Ok(Some(Reconciled {
        bluefile,
        added: added.into_keys().collect(),
        removed,
    }))
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

    #[test]
    fn a_use_gains_its_row_and_an_unused_row_goes() {
        let root = dir(
            "reconcile",
            &[
                ("dist/kagi/Bluefile", "package(\"kagi\", \"0.3.2\")\n"),
                ("dist/kagi/kagi.b", "def k()\n  1\nend\n"),
                (
                    "dist/user/Bluefile",
                    "package(\"user\", \"0.1.0\")\nneeds(\"gone\", \"^0.1\")\ntool(\"git\")\n",
                ),
                ("dist/user/user.b", "use(\"kagi\")\n\nkagi::k\n"),
            ],
        );
        let lp = crate::load_path::LoadPath::new([root.join("dist")]);
        let r = reconcile(&root.join("dist/user"), &lp)
            .unwrap()
            .expect("a change");
        assert_eq!(r.added, vec!["kagi".to_string()]);
        assert_eq!(r.removed, vec!["gone".to_string()]);
        assert_eq!(
            r.bluefile,
            "package(\"user\", \"0.1.0\")\nneeds(\"kagi\", \"^0.3\")\ntool(\"git\")\n"
        );
        std::fs::write(root.join("dist/user/Bluefile"), &r.bluefile).unwrap();
        assert_eq!(reconcile(&root.join("dist/user"), &lp).unwrap(), None);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn every_bidama_of_the_distribution_already_agrees() {
        let dist = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../bidamas");
        let lp = crate::load_path::LoadPath::new([dist.clone()]);
        let mut disagree = Vec::new();
        for entry in std::fs::read_dir(&dist).unwrap().filter_map(Result::ok) {
            let d = entry.path();
            if !d.join(crate::MANIFEST_FILE).is_file() {
                continue;
            }
            match reconcile(&d, &lp) {
                Ok(None) => {}
                other => disagree.push(format!("{}: {other:?}", d.display())),
            }
        }
        assert!(disagree.is_empty(), "{disagree:#?}");
    }
}
