//! `blue test --facts FILE`, and `TAMESHI_FACTS`: what a test run hands
//! tameshi for an Attested Verification Tuple.
//!
//! Two files, because tameshi's facts schema is closed. The facts file is
//! exactly what tameshi's runner reads (`tameshi::receipt::runner::RunFacts`,
//! which refuses any other field): the assertion tally, the evaluation steps
//! and the frame the tests ran under, `{"granted":[…],"withheld":[…],
//! "host_io":n}` (`Hold::frame_summary`). It has no place for a test's
//! controls or target, so `blue-test-evidence.json` beside it carries every
//! test: its controls as the ids tameshi names them
//! (`blue_lang_check::controls::oscal_id`), its target as a tameshi `Target`
//! (`{"kind":"blue-def","hash":<def_hash>}`), the test itself as a tameshi
//! `TestRef` (`{"runner":"blue","hash":<the test's def_hash>}`) and its
//! status as tameshi writes it. Both are canonical JSON: keys sorted, no
//! whitespace.

use std::path::{Path, PathBuf};

use blue_lang_mondou::def_hash::TestIdentities;
use blue_lang_runtime::Hold;
use blue_lang_test::{Outcome, Report, Tally};
use serde_json::{json, Value as Json};

/// The variable tameshi's runner names the facts file in.
pub const FACTS_ENV: &str = "TAMESHI_FACTS";
/// The evidence file, beside the facts file.
pub const EVIDENCE_FILE: &str = "blue-test-evidence.json";
/// The evidence file's schema tag.
pub const EVIDENCE_SCHEMA: &str = "blue-test-evidence.v1";

/// Where the facts go: `--facts`, else `TAMESHI_FACTS`, else nowhere.
pub fn path(flag: Option<PathBuf>) -> Option<PathBuf> {
    flag.or_else(|| {
        std::env::var_os(FACTS_ENV)
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
    })
}

/// One file's part of a run: its report when it checked, and its
/// identities.
pub struct FileEvidence<'a> {
    pub path: &'a Path,
    pub report: Option<&'a Report>,
    pub identities: Option<&'a TestIdentities>,
}

fn tally(t: Tally) -> Json {
    json!({ "passed": t.passed, "failed": t.failed })
}

fn status(passed: bool) -> &'static str {
    if passed {
        "PASS"
    } else {
        "FAIL"
    }
}

fn test_entry(outcome: &Outcome, ids: Option<&TestIdentities>) -> Json {
    let controls: Vec<Json> = outcome
        .declared
        .satisfies
        .iter()
        .map(|c| match blue_lang_check::controls::oscal_id(c) {
            Ok(id) => json!(id),
            Err(_) => Json::Null,
        })
        .collect();
    let definition = outcome.declared.target.clone();
    let target = definition
        .as_ref()
        .and_then(|key| ids.and_then(|i| i.definitions.get(key)))
        .map(|hash| json!({ "kind": "blue-def", "hash": hash }));
    let test = outcome
        .top_level
        .and_then(|i| ids.and_then(|ids| ids.tests.get(&i)))
        .map(|hash| json!({ "runner": "blue", "hash": hash }));
    json!({
        "name": outcome.name,
        "status": status(outcome.passed),
        "satisfies": outcome.declared.satisfies,
        "controls": controls,
        "definition": definition,
        "target": target,
        "test": test,
        "assertions": tally(outcome.assertions),
        "steps": outcome.steps,
        "host_io": outcome.host_io,
    })
}

/// The facts and the evidence of a run held to `hold`: what tameshi reads,
/// and every test with what it declares.
#[must_use]
pub fn render(hold: &Hold, files: &[FileEvidence<'_>]) -> (Json, Json) {
    let mut assertions = Tally::default();
    let (mut steps, mut host_io) = (0u64, 0u64);
    let mut entries = Vec::new();
    for f in files {
        let tests: Vec<Json> = match f.report {
            Some(r) => {
                assertions.passed += r.assertions.passed;
                assertions.failed += r.assertions.failed;
                steps += r.steps;
                host_io += r.host_io.unwrap_or(0);
                r.outcomes
                    .iter()
                    .map(|o| test_entry(o, f.identities))
                    .collect()
            }
            None => {
                assertions.failed += 1;
                Vec::new()
            }
        };
        entries.push(json!({
            "path": f.path.display().to_string(),
            "checked": f.report.is_some(),
            "tests": tests,
        }));
    }
    let frame = hold.frame_summary(host_io);
    let facts = json!({
        "assertions": tally(assertions),
        "steps": steps,
        "frame": frame,
    });
    let evidence = json!({
        "schema": EVIDENCE_SCHEMA,
        "runner": "blue",
        "assertions": tally(assertions),
        "steps": steps,
        "frame": frame,
        "files": entries,
    });
    (facts, evidence)
}

/// Write the facts to `facts` and the evidence beside it, creating the
/// directory.
///
/// # Errors
///
/// When either file cannot be written: evidence asked for and not written
/// fails the run rather than leaving tameshi to read nothing.
pub fn write(facts: &Path, hold: &Hold, files: &[FileEvidence<'_>]) -> Result<PathBuf, String> {
    let (facts_json, evidence_json) = render(hold, files);
    let dir = facts
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .map_or_else(|| PathBuf::from("."), Path::to_path_buf);
    std::fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let evidence = dir.join(EVIDENCE_FILE);
    for (path, j) in [(facts, &facts_json), (evidence.as_path(), &evidence_json)] {
        std::fs::write(path, blue_lang_proc::receipt::canonical(j))
            .map_err(|e| format!("{}: {e}", path.display()))?;
    }
    Ok(evidence)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outcome(passed: bool) -> Outcome {
        Outcome {
            name: "t".into(),
            top_level: Some(1),
            declared: blue_lang_test::Declared {
                satisfies: vec!["nist_ac_6".into()],
                target: Some("%root/f".into()),
            },
            passed,
            assertions: Tally {
                passed: u64::from(passed),
                failed: u64::from(!passed),
            },
            steps: 9,
            host_io: 0,
        }
    }

    #[test]
    fn the_facts_hold_only_what_tameshi_reads_and_the_evidence_names_each_test() {
        let report = Report {
            passed: 1,
            outcomes: vec![outcome(true)],
            assertions: Tally {
                passed: 1,
                failed: 0,
            },
            steps: 12,
            host_io: Some(0),
            ..Report::default()
        };
        let ids = TestIdentities {
            definitions: [("%root/f".to_string(), "b3:aa".to_string())].into(),
            tests: [(1, "b3:bb".to_string())].into(),
        };
        let hold = Hold::from(blue_lang_runtime::session::pure_frame());
        let (facts, evidence) = render(
            &hold,
            &[FileEvidence {
                path: Path::new("x.b"),
                report: Some(&report),
                identities: Some(&ids),
            }],
        );
        let mut keys: Vec<&str> = facts
            .as_object()
            .expect("an object")
            .keys()
            .map(String::as_str)
            .collect();
        keys.sort_unstable();
        assert_eq!(keys, ["assertions", "frame", "steps"]);
        assert_eq!(facts["frame"]["host_io"], 0);
        assert_eq!(facts["frame"]["granted"], json!([]));
        let test = &evidence["files"][0]["tests"][0];
        assert_eq!(test["controls"], json!(["NIST_SP_800_53R5_AC_6"]));
        assert_eq!(test["target"], json!({"kind": "blue-def", "hash": "b3:aa"}));
        assert_eq!(test["test"], json!({"runner": "blue", "hash": "b3:bb"}));
        assert_eq!(test["status"], "PASS");
    }

    #[test]
    fn a_file_that_did_not_check_is_a_failed_verification() {
        let hold = Hold::from(blue_lang_runtime::session::pure_frame());
        let (facts, evidence) = render(
            &hold,
            &[FileEvidence {
                path: Path::new("x.b"),
                report: None,
                identities: None,
            }],
        );
        assert_eq!(facts["assertions"], json!({"passed": 0, "failed": 1}));
        assert_eq!(evidence["files"][0]["checked"], false);
    }
}
