use std::collections::HashSet;
use std::io::Write as _;
use std::path::PathBuf;

use blue_lang_mondou::def_hash::{DefHash, TestIdentities};
use blue_lang_mondou::store::{self, Identity};

pub(crate) const ENV: &str = "BLUE_TEST_CACHE";

pub(crate) fn parse(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "" | "off" | "0" | "false" | "no" => Some(false),
        "on" | "1" | "true" | "yes" => Some(true),
        _ => None,
    }
}

pub(crate) struct TestCache {
    file: PathBuf,
    build: Identity,
    passed: HashSet<String>,
}

impl TestCache {
    pub(crate) fn open(no_cache: bool, reports_what_ran: bool) -> Result<Option<Self>, String> {
        let on = match std::env::var(ENV) {
            Err(_) => false,
            Ok(v) => parse(&v)
                .ok_or_else(|| format!("{ENV} is \"{v}\"; it takes on or off (the default)"))?,
        };
        if !on || no_cache || reports_what_ran {
            return Ok(None);
        }
        let Some(root) = store::cache_root() else {
            return Ok(None);
        };
        let build = Identity::of_this_build();
        let file = root.join("test").join(DefHash(build.0).hex());
        let passed = std::fs::read_to_string(&file)
            .map(|t| t.lines().map(str::to_string).collect())
            .unwrap_or_default();
        Ok(Some(Self {
            file,
            build,
            passed,
        }))
    }

    pub(crate) fn key(&self, ids: &TestIdentities, test: usize, bounds: &str) -> Option<String> {
        let own = ids.tests.get(&test)?;
        let id = Identity::from_parts(&[
            b"blue test cache v1",
            &self.build.0,
            own.as_bytes(),
            ids.preamble.as_bytes(),
            bounds.as_bytes(),
        ]);
        Some(DefHash(id.0).hex())
    }

    pub(crate) fn passed(&self, key: &str) -> bool {
        self.passed.contains(key)
    }

    pub(crate) fn record(&self, keys: &[String]) {
        let fresh: Vec<&String> = keys.iter().filter(|k| !self.passed(k)).collect();
        if fresh.is_empty() {
            return;
        }
        let mut text = String::new();
        for k in fresh {
            text.push_str(k);
            text.push('\n');
        }
        let written = self
            .file
            .parent()
            .map_or(Ok(()), std::fs::create_dir_all)
            .and_then(|()| {
                std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&self.file)
            })
            .and_then(|mut f| f.write_all(text.as_bytes()));
        if let Err(e) = written {
            eprintln!(
                "blue: the test cache could not be written to {}: {e}",
                self.file.display()
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse;

    #[test]
    fn the_cache_is_off_unless_named_on() {
        for off in ["", "off", "0", "false", "no"] {
            assert_eq!(parse(off), Some(false), "{off}");
        }
        for on in ["on", "1", "true", "YES"] {
            assert_eq!(parse(on), Some(true), "{on}");
        }
        assert_eq!(parse("store"), None);
    }
}
