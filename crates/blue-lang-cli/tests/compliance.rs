//! A test that declares the controls it verifies and the definition it
//! targets, run by `blue test` under a pure frame, hands tameshi the
//! evidence for an Attested Verification Tuple: the facts tameshi's runner
//! reads, and each test's controls, target `def_hash` and own `def_hash`
//! beside them. Every shape is read back through tameshi 0.1.7's own strict
//! types.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use tameshi::forensics::evidence::{EvidenceLedger, LeafStatus};
use tameshi::receipt::runner::{receipt_from_run, run_command, ReceiptRequest, RunFacts};
use tameshi::receipt::{
    ControlId, DrvPath, Receipt, ReceiptParts, ReceiptSchema, Runner, Sandbox, Status, Target,
    TargetKind, TestRef, B3,
};

const AC_6: &str = "NIST_SP_800_53R5_AC_6";
const SANDBOX: &str = "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-blue-test-run.drv";

fn blue() -> Command {
    let mut c = Command::new(env!("CARGO_BIN_EXE_blue"));
    c.env_remove("BLUE_PATH")
        .env_remove("BLUE_CONFIG")
        .env_remove("BLUE_TIER")
        .env_remove("BLUE_LANG")
        .env_remove("BLUE_MEMO")
        .env_remove("TAMESHI_FACTS")
        .env("BLUE_TRACE_DIR", "");
    c
}

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/compliance")
        .join(name)
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("blue-compliance-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scratch dir");
    dir.canonicalize().expect("canonical scratch dir")
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

fn json(path: &Path) -> serde_json::Value {
    serde_json::from_slice(&std::fs::read(path).expect("written")).expect("json")
}

/// `blue test --allow none --facts DIR/facts.json FILE`: the run, the facts
/// tameshi reads, and the evidence beside them.
fn tested(dir: &Path, file: &str) -> (Output, Vec<u8>, serde_json::Value) {
    let facts = dir.join("facts.json");
    let o = blue()
        .args(["test", "--allow", "none", "--facts"])
        .arg(&facts)
        .arg(fixture(file))
        .output()
        .expect("blue test");
    let evidence = json(&dir.join("blue-test-evidence.json"));
    (o, std::fs::read(&facts).expect("facts"), evidence)
}

/// The fixture's `parse_token` hashed as the engine hashes it, apart from
/// the path `blue test` takes.
fn engine_def_hash(file: &str, key: &str) -> String {
    let path = fixture(file);
    let text = std::fs::read_to_string(&path).expect("fixture");
    let checked = blue_lang_runtime::pipeline::check_entry(
        blue_lang_runtime::uses::Entry {
            path: Some(&path),
            text: &text,
        },
        &blue_lang_pkg::load_path::LoadPath::for_entry(&path),
        None,
        blue_lang_runtime::pipeline::Checking::WithTests,
    )
    .expect("checks");
    let lowered = blue_lang_runtime::pipeline::lower(&checked.program, &checked.names);
    blue_lang_mondou::hash_checked(&checked.program, &lowered)
        .of_key(key)
        .expect("defined")
        .hash
        .to_string()
}

fn the_only_test(evidence: &serde_json::Value) -> &serde_json::Value {
    let tests = evidence["files"][0]["tests"].as_array().expect("tests");
    assert_eq!(tests.len(), 1, "{evidence}");
    &tests[0]
}

#[test]
fn an_isolation_test_under_a_pure_frame_passes_and_names_its_control_target_and_no_host_io() {
    let dir = scratch("pass");
    let (o, facts, evidence) = tested(&dir, "token.b");
    assert!(o.status.success(), "{}", text(&o));
    assert!(
        text(&o).contains("1 test(s): 1 passed, 0 failed"),
        "{}",
        text(&o)
    );
    let read: RunFacts = serde_json::from_slice(&facts).expect("tameshi reads the facts");
    let frame = read.frame.expect("a frame");
    assert_eq!(frame.host_io, 0);
    assert!(frame.granted.is_empty(), "{frame:?}");
    assert!(
        frame.withheld.contains(&"filesystem".to_string()),
        "{frame:?}"
    );
    let tally = read.assertions.expect("a tally");
    assert_eq!((tally.passed, tally.failed), (1, 0));
    assert!(read.steps.is_some_and(|s| s > 0));
    let test = the_only_test(&evidence);
    assert_eq!(test["controls"], serde_json::json!([AC_6]));
    assert_eq!(test["definition"], "%root/parse_token");
    let target: Target = serde_json::from_value(test["target"].clone()).expect("a tameshi Target");
    assert_eq!(target.kind, TargetKind::BlueDef);
    assert_eq!(
        target.hash.to_string(),
        engine_def_hash("token.b", "%root/parse_token")
    );
    let test_ref: TestRef =
        serde_json::from_value(test["test"].clone()).expect("a tameshi TestRef");
    assert_eq!(test_ref.runner, Runner::Blue);
    assert_ne!(test_ref.hash, target.hash, "the test is not its target");
    assert_eq!(test["host_io"], 0);
    assert_eq!(test["status"], "PASS");
}

#[test]
fn a_body_that_does_not_breach_fails_and_a_bare_breach_ends_its_test_past_a_rescue() {
    let dir = scratch("red");
    let (o, facts, evidence) = tested(&dir, "token_red.b");
    let out = text(&o);
    assert!(!o.status.success(), "{out}");
    assert!(out.contains("2 test(s): 0 passed, 2 failed"), "{out}");
    assert!(
        out.contains("FAIL a parse that reaches no host does not breach")
            && out.contains("assert_panics pure_token(\"{}\")")
            && out.contains("ended: returned {}"),
        "{out}"
    );
    assert!(
        out.contains("ERROR a breach outside assert_panics ends the test")
            && out.contains("capability breach: `read_file`"),
        "{out}"
    );
    let read: RunFacts = serde_json::from_slice(&facts).expect("tameshi reads the facts");
    let tally = read.assertions.expect("a tally");
    assert_eq!((tally.passed, tally.failed), (0, 2));
    let statuses: Vec<&str> = evidence["files"][0]["tests"]
        .as_array()
        .expect("tests")
        .iter()
        .map(|t| t["status"].as_str().unwrap_or_default())
        .collect();
    assert_eq!(statuses, ["FAIL", "FAIL"]);
    let ambient = blue()
        .arg("test")
        .arg(fixture("token_red.b"))
        .output()
        .expect("blue test");
    assert!(
        text(&ambient).contains("2 test(s): 1 passed, 1 failed"),
        "without the pure frame the rescue swallows the read: {}",
        text(&ambient)
    );
}

#[test]
fn the_facts_become_a_receipt_whose_ac_6_leaf_the_ledger_proves() {
    let dir = scratch("ledger");
    let (o, facts, evidence) = tested(&dir, "token.b");
    assert!(o.status.success(), "{}", text(&o));
    let read: RunFacts = serde_json::from_slice(&facts).expect("tameshi reads the facts");
    let test = the_only_test(&evidence);
    let controls: Vec<ControlId> =
        serde_json::from_value(test["controls"].clone()).expect("tameshi control ids");
    let status: Status = serde_json::from_value(test["status"].clone()).expect("a status");
    let receipt = Receipt::new(ReceiptParts {
        schema: ReceiptSchema,
        controls,
        target: serde_json::from_value(test["target"].clone()).expect("a target"),
        test: serde_json::from_value(test["test"].clone()).expect("a test"),
        status,
        assertions: read.assertions.expect("a tally"),
        steps: read.steps,
        frame: read.frame,
        output_digest: B3(tameshi::hash::Blake3Hash::digest(&o.stdout)),
        sandbox: Sandbox {
            derivation: DrvPath::new(SANDBOX).expect("a derivation path"),
            network: false,
            system: "aarch64-darwin".to_string(),
        },
    })
    .expect("a valid receipt");
    assert_eq!(receipt.status(), Status::Pass);
    let mut ledger = EvidenceLedger::new();
    let leaves = ledger.fold_receipt(receipt).expect("folds");
    let ac_6 = leaves
        .iter()
        .find(|l| l.control.as_str() == AC_6)
        .expect("an AC-6 leaf");
    assert_eq!(ac_6.status, LeafStatus::Pass);
    let proof = ledger.prove(&ac_6.leaf.0).expect("a proof");
    assert!(proof.verify_against(&ledger.root(), &ac_6.leaf.0));
}

#[test]
fn tameshis_runner_runs_blue_test_with_tameshi_facts_and_reads_a_passing_receipt() {
    let dir = scratch("runner");
    let (work, out) = (dir.join("work"), dir.join("out"));
    std::fs::create_dir_all(&work).expect("work");
    let argv: Vec<String> = [
        env!("CARGO_BIN_EXE_blue"),
        "test",
        "--allow",
        "none",
        fixture("token.b").to_str().expect("utf-8"),
    ]
    .iter()
    .map(|s| (*s).to_string())
    .collect();
    let record = run_command(&argv, &work, &out, false).expect("tameshi runs it");
    assert_eq!(record.exit_code, Some(0), "{record:?}");
    let evidence = json(&work.join("blue-test-evidence.json"));
    let test = the_only_test(&evidence);
    let receipt = receipt_from_run(
        &out,
        ReceiptRequest {
            controls: serde_json::from_value(test["controls"].clone()).expect("ids"),
            target: serde_json::from_value(test["target"].clone()).expect("a target"),
            test: serde_json::from_value(test["test"].clone()).expect("a test"),
            derivation: DrvPath::new(SANDBOX).expect("a derivation path"),
            system: "aarch64-darwin".to_string(),
        },
    )
    .expect("a receipt");
    assert_eq!(receipt.status(), Status::Pass);
    assert_eq!(receipt.parts().frame.as_ref().map(|f| f.host_io), Some(0));
    assert_eq!(receipt.assertions().passed, 1);
}
