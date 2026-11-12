use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use crate::pipeline::RunError;
use crate::uses::{Entry, Frontend, Loader, PackageMove};

pub const FORMAT: &str = "blue-source-bundle";
pub const VERSION: u64 = 1;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SourceBundle {
    pub path: String,
    pub entry: String,
    pub packages: BTreeMap<String, Vec<(String, String)>>,
    pub children: BTreeMap<String, Vec<String>>,
    pub needs: BTreeMap<String, BTreeSet<String>>,
    pub versions: BTreeMap<String, String>,
}

impl SourceBundle {
    #[must_use]
    pub fn to_json(&self) -> String {
        let packages: serde_json::Map<String, serde_json::Value> = self
            .packages
            .iter()
            .map(|(name, files)| {
                let files = files
                    .iter()
                    .map(|(label, text)| serde_json::json!([label, text]))
                    .collect();
                (name.clone(), serde_json::Value::Array(files))
            })
            .collect();
        let children: serde_json::Map<String, serde_json::Value> = self
            .children
            .iter()
            .filter(|(_, below)| !below.is_empty())
            .map(|(name, below)| (name.clone(), serde_json::json!(below)))
            .collect();
        serde_json::json!({
            "format": FORMAT,
            "version": VERSION,
            "path": self.path,
            "entry": self.entry,
            "packages": packages,
            "children": children,
            "needs": self.needs,
            "versions": self.versions,
        })
        .to_string()
    }

    pub fn parse(text: &str) -> Result<Self, String> {
        let j: serde_json::Value =
            serde_json::from_str(text).map_err(|e| format!("a bundle is JSON: {e}"))?;
        if j.get("format").and_then(serde_json::Value::as_str) != Some(FORMAT) {
            return Err(format!("not a {FORMAT}"));
        }
        if j.get("version").and_then(serde_json::Value::as_u64) != Some(VERSION) {
            return Err(format!("a {FORMAT} of version {VERSION} only"));
        }
        let path = j
            .get("path")
            .and_then(serde_json::Value::as_str)
            .ok_or("a bundle names its entry's path")?
            .to_string();
        let entry = j
            .get("entry")
            .and_then(serde_json::Value::as_str)
            .ok_or("a bundle names its entry text")?
            .to_string();
        let mut packages = BTreeMap::new();
        for (name, files) in j
            .get("packages")
            .and_then(serde_json::Value::as_object)
            .ok_or("a bundle holds its packages")?
        {
            let files = files
                .as_array()
                .ok_or_else(|| format!("package {name}: a list of [label, text]"))?
                .iter()
                .map(|pair| match pair.as_array().map(Vec::as_slice) {
                    Some([serde_json::Value::String(l), serde_json::Value::String(t)]) => {
                        Ok((l.clone(), t.clone()))
                    }
                    _ => Err(format!("package {name}: a list of [label, text]")),
                })
                .collect::<Result<Vec<_>, _>>()?;
            packages.insert(name.clone(), files);
        }
        let mut children = BTreeMap::new();
        if let Some(map) = j.get("children").and_then(serde_json::Value::as_object) {
            for (name, below) in map {
                let below = below
                    .as_array()
                    .and_then(|xs| {
                        xs.iter()
                            .map(|x| x.as_str().map(str::to_string))
                            .collect::<Option<Vec<_>>>()
                    })
                    .ok_or_else(|| format!("children of {name}: a list of names"))?;
                children.insert(name.clone(), below);
            }
        }
        let needs = match j.get("needs") {
            None => BTreeMap::new(),
            Some(v) => serde_json::from_value(v.clone())
                .map_err(|e| format!("needs: a map of names to lists of names: {e}"))?,
        };
        let versions = match j.get("versions") {
            None => BTreeMap::new(),
            Some(v) => serde_json::from_value(v.clone())
                .map_err(|e| format!("versions: a map of names to versions: {e}"))?,
        };
        Ok(Self {
            path,
            entry,
            packages,
            children,
            needs,
            versions,
        })
    }
}

impl Loader for SourceBundle {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        self.packages
            .get(name)
            .cloned()
            .ok_or_else(|| format!("cannot load bidama \"{name}\": this bundle does not hold it"))
    }

    fn available(&self) -> Vec<String> {
        self.packages.keys().cloned().collect()
    }

    fn children(&self, name: &str) -> Vec<String> {
        self.children.get(name).cloned().unwrap_or_default()
    }

    fn needs(&self, package: &str, _entry_dir: Option<&Path>) -> Option<BTreeSet<String>> {
        self.needs.get(package).cloned()
    }

    fn version(&self, package: &str, _entry_dir: Option<&Path>) -> Option<String> {
        self.versions.get(package).cloned()
    }
}

struct Recording<'a> {
    inner: &'a dyn Loader,
    packages: RefCell<BTreeMap<String, Vec<(String, String)>>>,
    children: RefCell<BTreeMap<String, Vec<String>>>,
    needs: RefCell<BTreeMap<String, BTreeSet<String>>>,
    versions: RefCell<BTreeMap<String, String>>,
}

impl Loader for Recording<'_> {
    fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
        let files = self.inner.load(name)?;
        self.packages
            .borrow_mut()
            .insert(name.to_string(), files.clone());
        Ok(files)
    }

    fn entry_package(&self, path: &Path) -> Option<String> {
        self.inner.entry_package(path)
    }

    fn needs(&self, package: &str, entry_dir: Option<&Path>) -> Option<BTreeSet<String>> {
        let got = self.inner.needs(package, entry_dir);
        if let Some(n) = &got {
            self.needs
                .borrow_mut()
                .insert(package.to_string(), n.clone());
        }
        got
    }

    fn version(&self, package: &str, entry_dir: Option<&Path>) -> Option<String> {
        let got = self.inner.version(package, entry_dir);
        if let Some(v) = &got {
            self.versions
                .borrow_mut()
                .insert(package.to_string(), v.clone());
        }
        got
    }

    fn parse(&self, src: &str) -> Result<Vec<tatara_lisp::Spanned>, blue_lang_syntax::ParseError> {
        self.inner.parse(src)
    }

    fn available(&self) -> Vec<String> {
        self.inner.available()
    }

    fn frontend(&self, entry: &Path) -> Option<Frontend> {
        self.inner.frontend(entry)
    }

    fn children(&self, name: &str) -> Vec<String> {
        let below = self.inner.children(name);
        if !below.is_empty() {
            self.children
                .borrow_mut()
                .insert(name.to_string(), below.clone());
        }
        below
    }

    fn moved(&self, name: &str) -> Option<PackageMove> {
        self.inner.moved(name)
    }
}

pub fn bundle_of(entry: Entry<'_>, loader: &dyn Loader) -> Result<SourceBundle, RunError> {
    let recording = Recording {
        inner: loader,
        packages: RefCell::default(),
        children: RefCell::default(),
        needs: RefCell::default(),
        versions: RefCell::default(),
    };
    crate::pipeline::check_entry_cached(
        entry,
        &recording,
        None,
        crate::pipeline::Checking::Program,
        None,
    )?;
    Ok(SourceBundle {
        path: entry
            .path
            .map(|p| p.display().to_string())
            .unwrap_or_default(),
        entry: entry.text.to_string(),
        packages: recording.packages.into_inner(),
        children: recording.children.into_inner(),
        needs: recording.needs.into_inner(),
        versions: recording.versions.into_inner(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Two;

    impl Loader for Two {
        fn load(&self, name: &str) -> Result<Vec<(String, String)>, String> {
            match name {
                "aa" => Ok(vec![(
                    "aa/aa.b".into(),
                    "use(\"bb\", [:two])\ndef one()\n  two - 1\nend\n".into(),
                )]),
                "bb" => Ok(vec![("bb/bb.b".into(), "def two()\n  2\nend\n".into())]),
                other => Err(format!("no {other}")),
            }
        }
    }

    const ENTRY: &str = "use(\"aa\", [:one])\ndef main()\n  one + 41\nend\n";

    #[test]
    fn a_bundle_holds_every_bidama_the_entry_reaches_and_round_trips() {
        let entry = Entry {
            path: Some(Path::new("main.b")),
            text: ENTRY,
        };
        let bundle = bundle_of(entry, &Two).expect("bundles");
        assert_eq!(bundle.path, "main.b");
        assert_eq!(
            bundle.packages.keys().cloned().collect::<Vec<_>>(),
            vec!["aa".to_string(), "bb".to_string()]
        );
        let back = SourceBundle::parse(&bundle.to_json()).expect("parses");
        assert_eq!(back, bundle);
    }

    #[test]
    fn a_program_runs_from_its_bundle_alone_as_it_runs_from_its_loader() {
        let entry = Entry {
            path: Some(Path::new("main.b")),
            text: ENTRY,
        };
        let bundle = bundle_of(entry, &Two).expect("bundles");
        let run = |loader: &dyn Loader| {
            crate::pipeline::run_framed_accounted(
                entry,
                crate::Inputs::new(),
                loader,
                None,
                None,
                &crate::Account::default(),
            )
            .expect("runs")
            .value
        };
        let direct = run(&Two);
        let bundled = run(&bundle);
        assert!(matches!(direct, tatara_lisp_eval::Value::Int(42)));
        assert!(matches!(bundled, tatara_lisp_eval::Value::Int(42)));
    }

    #[test]
    fn a_bundle_refuses_a_bidama_it_does_not_hold_and_text_that_is_not_one() {
        let empty = SourceBundle::default();
        let err = empty.load("gamen").expect_err("refused");
        assert!(err.contains("gamen"), "{err}");
        assert!(SourceBundle::parse("{\"format\":\"other\"}").is_err());
        assert!(SourceBundle::parse("not json").is_err());
        let wrong = "{\"format\":\"blue-source-bundle\",\"version\":1,\"path\":\"m.b\",\"entry\":\"1\",\"packages\":{\"a\":[[\"x\"]]}}";
        assert!(SourceBundle::parse(wrong)
            .expect_err("short pair")
            .contains("label"));
    }
}
