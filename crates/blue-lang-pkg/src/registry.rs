use blue_lang_runtime::hosted::{load_hosted_in_frame, FramedError, Hosted};
use blue_lang_runtime::json::{json_to_value, value_to_json};
use blue_lang_runtime::uses::{Entry, Loader};
use serde::{Deserialize, Serialize};
use tatara_lisp_eval::vm::Budget;
use tatara_lisp_eval::Value;

use crate::lock::ManifestRecord;

pub const PACKAGE: &str = "touroku";

pub const FLAKEHUB_SCHEME: &str = "flakehub:";

#[derive(Debug, thiserror::Error)]
pub enum RegistryError {
    #[error("touroku does not load: {0}")]
    Load(#[from] FramedError),
    #[error("touroku::{name}: {message}")]
    Call { name: String, message: String },
    #[error("touroku::{name} answered a value this host does not read: {value}")]
    Shape {
        name: String,
        value: serde_json::Value,
    },
    #[error("could not serialize the manifest: {0}")]
    Json(#[from] serde_json::Error),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Refusal {
    pub kind: String,
    pub why: String,
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} ({})", self.why, self.kind)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Rendered {
    pub output: String,
    pub text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Request {
    pub api: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Resolved {
    pub version: String,
    pub revision: String,
    pub fetch: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Answer {
    pub status: u16,
    pub body: String,
}

pub trait FlakeHub {
    fn get(&self, url: &str) -> Answer;
    fn credential(&self) -> Option<String>;
}

pub struct Touroku {
    hosted: Hosted<()>,
}

fn budget() -> Budget {
    Budget {
        fuel: Some(200_000_000),
        max_depth: Some(blue_lang_runtime::execution_bounds().max_call_depth),
        quantum: None,
    }
}

fn text(v: &serde_json::Value, key: &str) -> Option<String> {
    v.get(key)
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
}

fn refusal_of(v: &serde_json::Value) -> Option<Refusal> {
    if let (Some(kind), Some(why)) = (text(v, "kind"), text(v, "why")) {
        return Some(Refusal { kind, why });
    }
    let pair = v.as_array()?;
    Some(Refusal {
        kind: pair.first()?.as_str()?.to_string(),
        why: pair.get(1)?.as_str()?.to_string(),
    })
}

fn refusals_of(v: Option<&serde_json::Value>) -> Vec<Refusal> {
    v.and_then(serde_json::Value::as_array)
        .map(|xs| xs.iter().filter_map(refusal_of).collect())
        .unwrap_or_default()
}

fn str_value(s: &str) -> Value {
    json_to_value(&serde_json::Value::String(s.to_string()))
}

impl Touroku {
    pub fn load(loader: &dyn Loader) -> Result<Self, RegistryError> {
        let source = format!("use(\"{PACKAGE}\")\n");
        let hosted = load_hosted_in_frame(
            Entry::anonymous(&source),
            loader,
            &mut (),
            |_| {},
            &blue_lang_runtime::project_rules::permits,
            budget(),
        )?;
        Ok(Self { hosted })
    }

    fn call(&mut self, name: &str, args: Vec<Value>) -> Result<serde_json::Value, RegistryError> {
        let qualified = format!("{PACKAGE}::{name}");
        self.hosted
            .call_budgeted(&qualified, args, &mut (), budget())
            .map(|v| value_to_json(&v))
            .map_err(|e| RegistryError::Call {
                name: name.to_string(),
                message: e.to_string(),
            })
    }

    pub fn backends(
        &mut self,
        manifest: &ManifestRecord,
    ) -> Result<(Vec<String>, Vec<Refusal>), RegistryError> {
        let json = serde_json::to_string(manifest)?;
        let v = self.call("backends_text", vec![str_value(&json)])?;
        let standing = v
            .get("standing")
            .and_then(serde_json::Value::as_array)
            .map(|xs| {
                xs.iter()
                    .filter_map(|x| x.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default();
        Ok((standing, refusals_of(v.get("refusals"))))
    }

    pub fn render(
        &mut self,
        manifest: &ManifestRecord,
        backend: &str,
    ) -> Result<Result<Rendered, Vec<Refusal>>, RegistryError> {
        let json = serde_json::to_string(manifest)?;
        let v = self.call("render_text", vec![str_value(&json), str_value(backend)])?;
        match (text(&v, "output"), text(&v, "text")) {
            (Some(output), Some(text)) => Ok(Ok(Rendered { output, text })),
            _ if v.get("refusals").is_some() => Ok(Err(refusals_of(v.get("refusals")))),
            _ => Err(RegistryError::Shape {
                name: "render_text".to_string(),
                value: v,
            }),
        }
    }

    pub fn request(&mut self, url: &str) -> Result<Result<Request, Refusal>, RegistryError> {
        let v = self.call("flakehub_request", vec![str_value(url)])?;
        if let Some(r) = v.get("refused").and_then(refusal_of) {
            return Ok(Err(r));
        }
        text(&v, "api")
            .map(|api| Ok(Request { api }))
            .ok_or(RegistryError::Shape {
                name: "flakehub_request".to_string(),
                value: v,
            })
    }

    pub fn flakehub_pin(
        &mut self,
        name: &str,
        url: &str,
        answer: &Answer,
        credential: Option<&str>,
    ) -> Result<Result<Resolved, Refusal>, RegistryError> {
        let v = self.call(
            "flakehub_pin",
            vec![
                str_value(name),
                str_value(url),
                Value::Int(i64::from(answer.status)),
                str_value(&answer.body),
                credential.map_or(Value::Nil, str_value),
            ],
        )?;
        if let Some(r) = v.get("refused").and_then(refusal_of) {
            return Ok(Err(r));
        }
        match (text(&v, "version"), text(&v, "revision"), text(&v, "fetch")) {
            (Some(version), Some(revision), Some(fetch)) => Ok(Ok(Resolved {
                version,
                revision,
                fetch,
            })),
            _ => Err(RegistryError::Shape {
                name: "flakehub_pin".to_string(),
                value: v,
            }),
        }
    }

    pub fn sui_verdict(
        &mut self,
        origin: Option<&str>,
        status: i32,
    ) -> Result<(String, String), RegistryError> {
        let v = self.call(
            "sui_verdict",
            vec![
                origin.map_or(Value::Nil, str_value),
                Value::Int(i64::from(status)),
            ],
        )?;
        match (text(&v, "state"), text(&v, "why")) {
            (Some(state), Some(why)) => Ok((state, why)),
            _ => Err(RegistryError::Shape {
                name: "sui_verdict".to_string(),
                value: v,
            }),
        }
    }
}

#[must_use]
pub fn is_flakehub(url: &str) -> bool {
    url.starts_with(FLAKEHUB_SCHEME)
}
