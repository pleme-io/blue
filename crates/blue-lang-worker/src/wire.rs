use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Request {
    pub id: u64,
    pub call: String,
    #[serde(default)]
    pub args: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Refusal {
    pub kind: String,
    pub why: String,
}

impl Refusal {
    #[must_use]
    pub fn new(kind: &str, why: impl Into<String>) -> Self {
        Self {
            kind: kind.to_owned(),
            why: why.into(),
        }
    }
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.kind, self.why)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Reply {
    Answer { id: u64, value: serde_json::Value },
    Refused { id: u64, refused: Refusal },
    LoadRefused { load_refused: Refusal },
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn every_reply_round_trips_through_one_line() {
        for reply in [
            Reply::Answer {
                id: 1,
                value: json!("text"),
            },
            Reply::Answer {
                id: 2,
                value: json!(null),
            },
            Reply::Refused {
                id: 3,
                refused: Refusal::new("raised", "boom"),
            },
            Reply::LoadRefused {
                load_refused: Refusal::new("load", "no"),
            },
        ] {
            let line = serde_json::to_string(&reply).unwrap();
            assert!(!line.contains('\n'));
            assert_eq!(serde_json::from_str::<Reply>(&line).unwrap(), reply);
        }
    }

    #[test]
    fn a_request_takes_no_args_by_default_and_a_bad_line_is_an_error() {
        let r: Request = serde_json::from_str(r#"{"id":7,"call":"render"}"#).unwrap();
        assert_eq!(r.args, Vec::<serde_json::Value>::new());
        assert!(serde_json::from_str::<Request>("{").is_err());
    }

    #[test]
    fn a_refusal_prints_its_kind_and_its_reason() {
        assert_eq!(Refusal::new("load", "no").to_string(), "load: no");
    }
}
