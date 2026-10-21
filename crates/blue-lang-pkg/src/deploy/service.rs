use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use tatara_lisp_eval::Value;

use super::{
    check_name, int_of, is_quantity, is_repository, port_of, project_path, text_of, Resources,
    Spec, SpecError, DEFAULT_OUTPUT_DIR,
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Setting {
    Bool(bool),
    Int(i64),
    Text(String),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Service {
    pub program: String,
    pub repository: String,
    pub port: u16,
    pub probe: String,
    pub namespace: String,
    pub replicas: u32,
    #[serde(default, skip_serializing_if = "Resources::is_empty")]
    pub resources: Resources,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub assets: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub config: BTreeMap<String, Setting>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub flags: BTreeMap<String, bool>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub schema: BTreeMap<String, BTreeMap<String, String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(default, skip_serializing_if = "Slo::is_empty")]
    pub slo: Slo,
    pub output: String,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Slo {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub availability: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latency: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latency_ms: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window_days: Option<u32>,
}

impl Eq for Slo {}

impl Slo {
    #[must_use]
    pub fn is_empty(&self) -> bool {
        *self == Self::default()
    }
}

pub const SLO_FIELDS: &[&str] = &["availability", "latency", "latency_ms", "window_days"];

fn percent_of(field: &'static str, v: &Value) -> Result<f64, SpecError> {
    #[allow(clippy::cast_precision_loss)]
    let x = match v {
        Value::Int(n) => *n as f64,
        Value::Float(f) => *f,
        other => {
            return Err(SpecError::Type {
                field,
                expected: "a percentage",
                got: other.type_name(),
            })
        }
    };
    if x > 0.0 && x < 100.0 {
        Ok(x)
    } else {
        Err(SpecError::SloObjective {
            field,
            got: x.to_string(),
        })
    }
}

fn bounded_of(field: &'static str, v: &Value, max: i64) -> Result<u32, SpecError> {
    let n = int_of(field, v)?;
    if (1..=max).contains(&n) {
        u32::try_from(n).map_err(|_| SpecError::SloObjective {
            field,
            got: n.to_string(),
        })
    } else {
        Err(SpecError::SloObjective {
            field,
            got: n.to_string(),
        })
    }
}

fn slo_of(v: Option<&Value>) -> Result<Slo, SpecError> {
    let Some(v) = v else {
        return Ok(Slo::default());
    };
    let s = Spec::of(v, SLO_FIELDS)?;
    Ok(Slo {
        availability: s
            .get("availability")
            .map(|x| percent_of("availability", x))
            .transpose()?,
        latency: s
            .get("latency")
            .map(|x| percent_of("latency", x))
            .transpose()?,
        latency_ms: s
            .get("latency_ms")
            .map(|x| bounded_of("latency_ms", x, 60_000))
            .transpose()?,
        window_days: s
            .get("window_days")
            .map(|x| bounded_of("window_days", x, 90))
            .transpose()?,
    })
}

pub const SERVICE_FIELDS: &[&str] = &[
    "program",
    "repository",
    "port",
    "probe",
    "namespace",
    "replicas",
    "cpu",
    "memory",
    "memory_limit",
    "assets",
    "config",
    "flags",
    "schema",
    "owner",
    "slo",
    "output",
];

pub const RESERVED_SETTINGS: &[&str] = &[
    "listen", "health", "flags", "config", "tier", "defaults", "database",
];

pub const COLUMN_TYPES: &[&str] = &[
    "text",
    "integer",
    "bigint",
    "boolean",
    "timestamptz",
    "uuid",
    "jsonb",
    "double",
];

pub const DEFAULT_PROBE: &str = "/healthz";

#[must_use]
pub fn is_setting_name(s: &str) -> bool {
    let bytes = s.as_bytes();
    !bytes.is_empty()
        && bytes.len() <= 63
        && bytes[0].is_ascii_lowercase()
        && bytes
            .iter()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || *b == b'_')
        && !s.contains("__")
        && !s.ends_with('_')
}

#[must_use]
pub fn is_column_type(s: &str) -> bool {
    COLUMN_TYPES.contains(&s.strip_suffix('?').unwrap_or(s))
}

fn setting_of(key: &str, v: &Value) -> Result<Setting, SpecError> {
    match v {
        Value::Bool(b) => Ok(Setting::Bool(*b)),
        Value::Int(n) => Ok(Setting::Int(*n)),
        Value::Str(s) => Ok(Setting::Text(s.to_string())),
        other => Err(SpecError::SettingType {
            key: key.to_string(),
            got: other.type_name(),
        }),
    }
}

fn setting_name(key: String) -> Result<String, SpecError> {
    if !is_setting_name(&key) {
        return Err(SpecError::SettingName { got: key });
    }
    Ok(key)
}

pub fn service_of(name: &str, spec: &Value) -> Result<Service, SpecError> {
    check_name(name)?;
    let s = Spec::of(spec, SERVICE_FIELDS)?;
    let program = project_path("program", text_of("program", s.required("program")?)?)?;
    let repository = text_of("repository", s.required("repository")?)?;
    if !is_repository(&repository) {
        return Err(SpecError::Repository { got: repository });
    }
    let port = port_of("port", s.required("port")?)?;
    let probe = s
        .text("probe")?
        .unwrap_or_else(|| DEFAULT_PROBE.to_string());
    if !probe.starts_with('/') {
        return Err(SpecError::ProbePath { got: probe });
    }
    let namespace = s.text("namespace")?.unwrap_or_else(|| name.to_string());
    check_name(&namespace)?;
    let replicas = match s.get("replicas") {
        None => 1,
        Some(v) => {
            let n = int_of("replicas", v)?;
            u32::try_from(n).map_err(|_| SpecError::Replicas { got: n })?
        }
    };
    let quantity = |field: &'static str| -> Result<Option<String>, SpecError> {
        match s.text(field)? {
            Some(q) if !is_quantity(&q) => Err(SpecError::Quantity { field, got: q }),
            q => Ok(q),
        }
    };
    let resources = Resources {
        cpu: quantity("cpu")?,
        memory: quantity("memory")?,
        memory_limit: quantity("memory_limit")?,
    };

    let mut config = BTreeMap::new();
    for (key, v) in s.map("config")? {
        let key = setting_name(key)?;
        if RESERVED_SETTINGS.contains(&key.as_str()) {
            return Err(SpecError::ReservedSetting { key });
        }
        let value = setting_of(&key, v)?;
        config.insert(key, value);
    }
    let mut flags = BTreeMap::new();
    for (key, v) in s.map("flags")? {
        let key = setting_name(key)?;
        match v {
            Value::Bool(b) => {
                flags.insert(key, *b);
            }
            other => {
                return Err(SpecError::FlagType {
                    key,
                    got: other.type_name(),
                })
            }
        }
    }

    let mut schema = BTreeMap::new();
    for (table, cols) in s.map("schema")? {
        if !is_setting_name(&table) {
            return Err(SpecError::TableName { got: table });
        }
        let Value::Map(cols) = cols else {
            return Err(SpecError::TableColumns {
                table,
                got: cols.type_name(),
            });
        };
        let mut columns = BTreeMap::new();
        for (k, ty) in cols.iter() {
            let column = match k {
                tatara_lisp_eval::value::MapKey::Keyword(c)
                | tatara_lisp_eval::value::MapKey::Str(c)
                | tatara_lisp_eval::value::MapKey::Symbol(c) => c.to_string(),
                _ => {
                    return Err(SpecError::ColumnName {
                        table,
                        got: String::from("a non-text key"),
                    })
                }
            };
            if !is_setting_name(&column) || column == "id" {
                return Err(SpecError::ColumnName { table, got: column });
            }
            let ty = text_of("schema", ty)?;
            if !is_column_type(&ty) {
                return Err(SpecError::ColumnType {
                    column: [table.as_str(), ".", column.as_str()].concat(),
                    got: ty,
                });
            }
            columns.insert(column, ty);
        }
        if columns.is_empty() {
            return Err(SpecError::TableColumns {
                table,
                got: "an empty map",
            });
        }
        schema.insert(table, columns);
    }

    let owner = s.text("owner")?;
    if let Some(o) = &owner {
        check_name(o)?;
    }
    let slo = slo_of(s.get("slo"))?;

    let output = match s.text("output")? {
        Some(o) => project_path("output", o)?,
        None => [DEFAULT_OUTPUT_DIR, "/", name].concat(),
    };

    Ok(Service {
        program,
        repository,
        port,
        probe,
        namespace,
        replicas,
        resources,
        assets: s.paths("assets")?,
        config,
        flags,
        schema,
        owner,
        slo,
        output,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bluefile::{read_bluefile, BluefileError};
    use crate::deploy::Refusal;

    fn read(body: &str) -> Result<crate::bluefile::Project, Vec<Refusal>> {
        let src = ["package(\"p\", \"0.3.0\")\n", body].concat();
        match read_bluefile(&src) {
            Ok(b) => Ok(b.project),
            Err(BluefileError::Refused { refusals }) => Err(refusals),
            Err(other) => panic!("{body}: {other}"),
        }
    }

    fn refused(body: &str) -> Vec<String> {
        read(body)
            .expect_err(body)
            .into_iter()
            .map(|r| r.to_string())
            .collect()
    }

    const MINIMAL: &str =
        "service(\"hello\", {program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080})\n";

    #[test]
    fn a_minimal_service_takes_every_default() {
        let p = read(MINIMAL).unwrap();
        let s = &p.services["hello"];
        assert_eq!(s.probe, "/healthz");
        assert_eq!(s.namespace, "hello");
        assert_eq!(s.replicas, 1);
        assert_eq!(s.output, "deploy/hello");
        assert!(s.config.is_empty() && s.flags.is_empty() && s.schema.is_empty());
        assert!(s.slo.is_empty() && s.owner.is_none());
        assert!(!serde_json::to_string(s).unwrap().contains("slo"));
    }

    #[test]
    fn an_slo_override_is_recorded_and_round_trips() {
        let p = read(
            "service(\"hello\", {program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080, \
             owner: \"edge\", slo: {availability: 99.9, latency_ms: 250, window_days: 7}})\n",
        )
        .unwrap();
        let s = &p.services["hello"];
        assert_eq!(s.owner.as_deref(), Some("edge"));
        assert_eq!(s.slo.availability, Some(99.9));
        assert_eq!(s.slo.latency_ms, Some(250));
        assert_eq!(s.slo.latency, None);
        let back: Service = serde_json::from_str(&serde_json::to_string(s).unwrap()).unwrap();
        assert_eq!(&back, s);
    }

    #[test]
    fn settings_flags_and_tables_are_recorded_typed() {
        let p = read(
            "service(\"hello\", {program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080, \
             config: {greeting: \"olá\", times: 2, loud: false}, flags: {shout: true}, \
             schema: {greetings: {text: \"text\", note: \"text?\"}}})\n",
        )
        .unwrap();
        let s = &p.services["hello"];
        assert_eq!(s.config["greeting"], Setting::Text("olá".into()));
        assert_eq!(s.config["times"], Setting::Int(2));
        assert_eq!(s.config["loud"], Setting::Bool(false));
        assert!(s.flags["shout"]);
        assert_eq!(s.schema["greetings"]["note"], "text?");
        let json = serde_json::to_string(s).unwrap();
        let back: Service = serde_json::from_str(&json).unwrap();
        assert_eq!(&back, s);
    }

    #[test]
    fn every_broken_rule_is_refused_by_name() {
        let base = "program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080";
        let cases = [
            ("config: {listen: 1}", "reserved"),
            ("config: {Bad: 1}", "not a setting name"),
            ("config: {a__b: 1}", "not a setting name"),
            ("config: {l: [1]}", "must be text, an integer or true/false"),
            ("flags: {shout: 1}", "must be true or false"),
            ("schema: {t: {id: \"text\"}}", "is every table's key"),
            ("schema: {t: {c: \"varchar\"}}", "is not a column type"),
            ("schema: {t: {}}", "must map column names to types"),
            ("schema: {T: {c: \"text\"}}", "is not a table name"),
            ("probe: \"healthz\"", "starts with `/`"),
            ("prot: 1", "is not a field here"),
            ("slo: {availability: 100}", "objective"),
            ("slo: {latency: 0}", "objective"),
            ("slo: {latency_ms: 0}", "objective"),
            ("slo: {window_days: 91}", "objective"),
            ("slo: {availability: \"high\"}", "a percentage"),
            ("slo: {burn: 1}", "is not a field here"),
            ("owner: \"Team A\"", "not"),
        ];
        for (extra, needle) in cases {
            let body = ["service(\"hello\", {", base, ", ", extra, "})\n"].concat();
            let errs = refused(&body);
            assert!(errs.iter().any(|e| e.contains(needle)), "{extra}: {errs:?}");
        }
        let missing = refused(
            "service(\"hello\", {program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\"})\n",
        );
        assert!(
            missing.iter().any(|e| e.contains("`port` is required")),
            "{missing:?}"
        );
    }

    #[test]
    fn a_service_may_not_share_an_image_name_or_an_output() {
        let errs = refused(
            &[
                MINIMAL,
                "image(\"hello\", {program: \"hello.b\", repository: \"ghcr.io/pleme-io/x\"})\n",
            ]
            .concat(),
        );
        assert!(
            errs.iter()
                .any(|e| e.contains("both a service and an image")),
            "{errs:?}"
        );
        let errs = refused(
            &[
                MINIMAL,
                "generate(\"g\", \"deploy/hello/chart/x\", \"g.b\")\n",
            ]
            .concat(),
        );
        assert!(
            errs.iter().any(|e| e.contains("already written by")),
            "{errs:?}"
        );
        assert!(
            read(&[MINIMAL, "generate(\"g\", \"deploy/hellothere\", \"g.b\")\n"].concat()).is_ok()
        );
    }

    #[test]
    fn names_and_types_follow_their_rules() {
        for ok in ["a", "greeting", "max_retries", "v2"] {
            assert!(is_setting_name(ok), "{ok}");
        }
        for bad in ["", "A", "1a", "a__b", "a_", "a-b", &"a".repeat(64)] {
            assert!(!is_setting_name(bad), "{bad}");
        }
        assert!(is_column_type("text?") && is_column_type("double"));
        assert!(!is_column_type("text??") && !is_column_type("varchar"));
    }
}
