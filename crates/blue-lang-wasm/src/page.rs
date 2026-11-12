use blue_lang_runtime::bundle::SourceBundle;
use blue_lang_runtime::pipeline::{run_framed_accounted, RunError};
use blue_lang_runtime::uses::Entry;
use blue_lang_runtime::{Account, Hold, Inputs};
use tatara_lisp_eval::Value;

#[must_use]
pub fn value_text(v: &Value) -> String {
    match v {
        Value::Str(s) => s.to_string(),
        Value::Nil => "nil".to_string(),
        other => blue_lang_runtime::literal::literal(other)
            .unwrap_or_else(|| format!("<{}>", other.type_name())),
    }
}

#[must_use]
pub fn answer(bundle_text: &str) -> serde_json::Value {
    let bundle = match SourceBundle::parse(bundle_text) {
        Ok(b) => b,
        Err(e) => {
            return serde_json::json!({ "state": "refused", "error": e });
        }
    };
    blue_lang_runtime::set_node_clock(blue_lang_runtime::ClockKind::Virtual);
    let hold = Hold::from(blue_lang_runtime::session::frame_granting(&[]));
    let account = Account {
        identify: Some(blue_lang_mondou::def_hash::identify),
        ..Account::default()
    };
    let path = std::path::PathBuf::from(&bundle.path);
    let entry = Entry {
        path: Some(&path),
        text: &bundle.entry,
    };
    let outcome = run_framed_accounted(entry, Inputs::new(), &bundle, None, Some(&hold), &account);
    let receipt = blue_lang_runtime::receipt::of_run(
        &hold,
        &account,
        blue_lang_runtime::receipt::exit_of(&outcome),
    );
    let receipt_text = String::from_utf8_lossy(&receipt.bytes()).into_owned();
    match outcome {
        Ok(run) => serde_json::json!({
            "state": "ran",
            "value": value_text(&run.value),
            "receipt": receipt_text,
        }),
        Err(e) => serde_json::json!({
            "state": "failed",
            "error": failure(&e),
            "receipt": receipt_text,
        }),
    }
}

fn failure(e: &RunError) -> String {
    e.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bundle(entry: &str) -> String {
        SourceBundle {
            path: "main.b".to_string(),
            entry: entry.to_string(),
            ..SourceBundle::default()
        }
        .to_json()
    }

    #[test]
    fn a_bundle_answers_its_value_and_a_receipt_of_its_run() {
        let a = answer(&bundle("def main()\n  \"<p>#{to_s(6 * 7)}</p>\"\nend\n"));
        assert_eq!(a["state"], "ran", "{a}");
        assert_eq!(a["value"], "<p>42</p>");
        let receipt: serde_json::Value =
            serde_json::from_str(a["receipt"].as_str().expect("text")).expect("json");
        assert_eq!(receipt["format"], "blue-receipt");
        assert_eq!(receipt["exit"]["kind"], "normal");
        assert_eq!(receipt["frame"]["granted"], serde_json::json!([]));
        assert!(receipt["def_hash"]
            .as_str()
            .is_some_and(|h| h.starts_with("b3:")));
    }

    #[test]
    fn the_receipt_names_the_program_so_another_program_has_another() {
        let receipt_of = |src: &str| answer(&bundle(src))["receipt"].clone();
        assert_ne!(
            receipt_of("def main()\n  1\nend\n"),
            receipt_of("def main()\n  2\nend\n")
        );
        assert_eq!(
            receipt_of("def main()\n  1\nend\n"),
            receipt_of("def main()\n  1\nend\n")
        );
    }

    #[test]
    fn a_failing_run_is_a_receipt_that_says_so_and_a_bad_bundle_is_refused() {
        let a = answer(&bundle("def main()\n  no_such_fn()\nend\n"));
        assert_eq!(a["state"], "failed", "{a}");
        assert!(a["receipt"]
            .as_str()
            .is_some_and(|r| !r.contains("\"normal\"")));
        assert_eq!(answer("not json")["state"], "refused");
    }

    #[test]
    fn a_host_name_is_known_and_refused_by_the_frame_as_on_the_command_line() {
        let a = answer(&bundle("def main()\n  getenv(\"HOME\")\nend\n"));
        assert_eq!(a["state"], "failed", "{a}");
        let receipt: serde_json::Value =
            serde_json::from_str(a["receipt"].as_str().expect("text")).expect("json");
        assert_eq!(receipt["exit"]["kind"], "refused", "{receipt}");
        assert!(receipt["exit"]["text"]
            .as_str()
            .is_some_and(|t| t.contains("`getenv` reaches the host (environment)")));
    }
}
