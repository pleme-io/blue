//! Receipts on disk: each named by the BLAKE3 hash of its bytes, and checked
//! by recomputing that name.
//!
//! The format is `blue_lang_proc::receipt`'s; this module adds the content
//! address, as `blue_lang_proc::trace::crash_hash` does for a crash trace,
//! with the same canonical text and the same hash. A node hands each held actor's
//! receipt to [`sink`]; a door writes the run's receipt with [`of_run`] and
//! [`write`]; `blue receipt verify` calls [`verify`].

use std::path::{Path, PathBuf};

use blue_lang_proc::receipt::{canonical, FORMAT};
use blue_lang_proc::{Receipt, ReceiptSink, Subject};

use crate::pipeline::{Run, RunError};
use crate::{Account, Hold};

/// The definition key a run's own identity is filed under: the hash of a
/// definition whose body is every top-level form of the program, in order,
/// then the call to `main`.
pub const RUN: &str = "%run";

/// The extension every receipt file carries after its hash.
pub const EXTENSION: &str = "receipt.json";

/// The file name `bytes` must have: `<blake3 hex>.receipt.json`.
#[must_use]
pub fn name_of(bytes: &[u8]) -> String {
    format!("{}.{EXTENSION}", blake3::hash(bytes).to_hex())
}

/// Write `receipt` into `dir`, creating it, under its content address.
///
/// # Errors
///
/// When the directory or the file cannot be written.
pub fn write(dir: &Path, receipt: &Receipt) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(dir)?;
    let bytes = receipt.bytes();
    let path = dir.join(name_of(&bytes));
    std::fs::write(&path, bytes)?;
    Ok(path)
}

/// A node's receipt sink writing into `dir`; a receipt that cannot be
/// written is said on stderr and costs the run nothing.
#[must_use]
pub fn sink(dir: PathBuf) -> ReceiptSink {
    std::sync::Arc::new(move |r: &Receipt| {
        if let Err(e) = write(&dir, r) {
            eprintln!(
                "blue: a receipt could not be written to {}: {e}",
                dir.display()
            );
        }
    })
}

/// Check that `path` is a receipt whose name is the hash of its bytes, and
/// that the bytes are its canonical JSON. Answers `b3:<hex>`.
///
/// # Errors
///
/// Naming what failed: the file, its name, its JSON, its format, its form.
pub fn verify(path: &Path) -> Result<String, String> {
    let shown = path.display();
    let bytes = std::fs::read(path).map_err(|e| format!("{shown}: {e}"))?;
    let expected = name_of(&bytes);
    let named = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or_default();
    if named != expected {
        return Err(format!(
            "{shown}: named {named}, but its bytes hash to {expected}"
        ));
    }
    let j: serde_json::Value =
        serde_json::from_slice(&bytes).map_err(|e| format!("{shown}: not JSON: {e}"))?;
    if j.get("format").and_then(serde_json::Value::as_str) != Some(FORMAT) {
        return Err(format!("{shown}: not a {FORMAT}"));
    }
    if canonical(&j).as_bytes() != bytes.as_slice() {
        return Err(format!("{shown}: not canonical JSON"));
    }
    Ok(format!(
        "b3:{}",
        expected.trim_end_matches(&format!(".{EXTENSION}"))
    ))
}

/// How a run ended, as a receipt names it: its kind and its text.
#[must_use]
pub fn exit_of(outcome: &Result<Run, RunError>) -> (&'static str, String) {
    match outcome {
        Ok(_) => ("normal", "normal".into()),
        Err(RunError::Eval(f)) if f.breach => ("fatal", f.message.clone()),
        Err(RunError::Eval(f)) => ("crashed", f.message.clone()),
        Err(e) => ("refused", e.to_string()),
    }
}

/// The receipt of a run held to `hold`, of which `account` was given, that
/// ended as `exit` says: every host call the run and its processes made.
#[must_use]
pub fn of_run(hold: &Hold, account: &Account, exit: (&str, String)) -> Receipt {
    Receipt {
        subject: Subject::Run,
        definition: Some(RUN.to_string()),
        def_hash: account.identities.of(RUN),
        frame: hold.frame(),
        host_io: account.host_io.total(),
        exit_kind: exit.0.to_string(),
        exit_text: exit.1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("blue-receipt-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn receipt() -> Receipt {
        let hold = Hold::from(blue_lang_waku::Waku::bottom());
        let account = Account::default();
        account.host_io.tally();
        of_run(&hold, &account, ("normal", "normal".into()))
    }

    #[test]
    fn a_written_receipt_verifies_under_the_hash_of_its_bytes() {
        let dir = scratch("ok");
        let path = write(&dir, &receipt()).expect("write");
        let name = path.file_name().and_then(|n| n.to_str()).expect("name");
        assert_eq!(name.len(), 64 + 1 + EXTENSION.len(), "{name}");
        let hash = verify(&path).expect("verifies");
        assert_eq!(hash, format!("b3:{}", &name[..64]));
        let again = write(&dir, &receipt()).expect("write again");
        assert_eq!(again, path, "the same receipt is the same file");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn any_edit_of_one_byte_fails_verification() {
        let dir = scratch("edit");
        let path = write(&dir, &receipt()).expect("write");
        let bytes = std::fs::read(&path).expect("read");
        for i in [0, bytes.len() / 2, bytes.len() - 1] {
            let mut edited = bytes.clone();
            edited[i] ^= 1;
            std::fs::write(&path, &edited).expect("edit");
            let err = verify(&path).expect_err("an edit is refused");
            assert!(err.contains("hash to"), "{err}");
        }
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_file_named_by_its_hash_must_still_be_a_canonical_receipt() {
        let dir = scratch("form");
        std::fs::create_dir_all(&dir).expect("dir");
        for (text, why) in [
            (&b"{\"format\": \"blue-receipt\"}"[..], "not canonical"),
            (b"{\"format\":\"other\"}", "not a blue-receipt"),
            (b"not json", "not JSON"),
        ] {
            let path = dir.join(name_of(text));
            std::fs::write(&path, text).expect("write");
            let err = verify(&path).expect_err(why);
            assert!(err.contains(why), "{err}");
        }
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_nodes_sink_writes_each_receipt_under_its_content_address() {
        let dir = scratch("sink");
        let r = receipt();
        sink(dir.clone())(&r);
        let path = dir.join(name_of(&r.bytes()));
        assert_eq!(std::fs::read(&path).expect("written"), r.bytes());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_run_ends_normal_fatal_crashed_or_refused() {
        let fault = |breach| -> Result<Run, RunError> {
            Err(RunError::Eval(Box::new(crate::observe::Fault {
                message: "m".into(),
                breach,
                ..crate::observe::Fault::default()
            })))
        };
        assert_eq!(exit_of(&fault(true)), ("fatal", "m".to_string()));
        assert_eq!(exit_of(&fault(false)), ("crashed", "m".to_string()));
        assert_eq!(
            exit_of(&Err(RunError::Parse("p".into()))),
            ("refused", "parse error: p".to_string())
        );
        assert_eq!(
            exit_of(&crate::pipeline::run("1 + 1")),
            ("normal", "normal".to_string())
        );
    }

    #[test]
    fn a_pure_runs_receipt_withholds_every_host_capability() {
        let j: serde_json::Value = serde_json::from_slice(&receipt().bytes()).expect("json");
        assert_eq!(j["subject"], "run");
        assert_eq!(j["definition"], RUN);
        assert_eq!(j["frame"]["granted"], serde_json::json!([]));
        assert_eq!(
            j["frame"]["withheld"],
            serde_json::json!([
                "process",
                "filesystem",
                "environment",
                "clock",
                "network",
                "entropy",
                "comm-flash",
                "comm-scavenger",
                "mpc-threshold"
            ])
        );
        assert_eq!(j["frame"]["host_io"], 1, "the ledger's total, as given");
    }
}
