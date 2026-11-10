use std::collections::HashSet;
use std::time::Duration;

use blue_lang_mondou::def_hash::{DefHash, TestIdentities};
use blue_lang_mondou::store::{self, Identity, Store};

pub(crate) const ENV: &str = "BLUE_TEST_CACHE";

pub(crate) fn parse(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "" | "on" | "1" | "true" | "yes" => Some(true),
        "off" | "0" | "false" | "no" => Some(false),
        _ => None,
    }
}

pub(crate) struct TestCache {
    store: Store,
    bucket: DefHash,
    passed: HashSet<String>,
}

impl TestCache {
    pub(crate) fn open(no_cache: bool, reports_what_ran: bool) -> Result<Option<Self>, String> {
        let on = match std::env::var(ENV) {
            Err(_) => true,
            Ok(v) => parse(&v)
                .ok_or_else(|| format!("{ENV} is \"{v}\"; it takes on (the default) or off"))?,
        };
        if !on || no_cache || reports_what_ran {
            return Ok(None);
        }
        let Some(store) = store::open_tier("test") else {
            return Ok(None);
        };
        let bucket = DefHash(store.identity().0);
        let passed = store
            .load(&bucket)
            .entries
            .into_keys()
            .map(|k| DefHash(k).hex())
            .collect();
        Ok(Some(Self {
            store,
            bucket,
            passed,
        }))
    }

    pub(crate) fn key(&self, ids: &TestIdentities, test: usize, bounds: &str) -> Option<String> {
        let own = ids.tests.get(&test)?;
        let id = Identity::from_parts(&[
            b"blue test cache v1",
            &self.store.identity().0,
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
        let fresh: Vec<([u8; 32], Duration, Vec<u8>)> = keys
            .iter()
            .filter(|k| !self.passed(k))
            .filter_map(|k| DefHash::from_hex(k))
            .map(|k| (k.0, Duration::ZERO, Vec::new()))
            .collect();
        if fresh.is_empty() {
            return;
        }
        match self.store.append(&self.bucket, &fresh) {
            Ok(_) => {
                let _ = self.store.evict();
            }
            Err(e) => eprintln!(
                "blue: the test cache could not be written to {}: {e}",
                self.store.dir().display()
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse;

    #[test]
    fn the_cache_is_on_unless_named_off() {
        for off in ["off", "0", "false", "no", "OFF"] {
            assert_eq!(parse(off), Some(false), "{off}");
        }
        for on in ["", "on", "1", "true", "YES"] {
            assert_eq!(parse(on), Some(true), "{on}");
        }
        assert_eq!(parse("store"), None);
    }
}
