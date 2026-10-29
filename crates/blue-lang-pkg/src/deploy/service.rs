use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::Value;

use super::runtime::{access_of, runtime_of, Access, Runtime};
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
    Texts(Vec<String>),
    Group(BTreeMap<String, Setting>),
    Unset,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Service {
    pub program: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub host: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub host_args: Vec<String>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache: Option<Cache>,
    #[serde(default, skip_serializing_if = "Slo::is_empty")]
    pub slo: Slo,
    #[serde(default)]
    pub access: Access,
    #[serde(default)]
    pub runtime: Runtime,
    pub output: String,
}

pub const DEFAULT_CACHE_PORT: u16 = 6379;

pub const CACHE_FIELDS: &[&str] = &["port"];

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Cache {
    pub port: u16,
}

fn cache_of(v: Option<&Value>) -> Result<Option<Cache>, SpecError> {
    let Some(v) = v else {
        return Ok(None);
    };
    let s = Spec::of(v, CACHE_FIELDS)?;
    let port = match s.get("port") {
        None => DEFAULT_CACHE_PORT,
        Some(p) => port_of("port", p)?,
    };
    Ok(Some(Cache { port }))
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
    "host",
    "host_args",
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
    "cache",
    "slo",
    "access",
    "runtime",
    "because",
    "output",
];

pub const RESERVED_SETTINGS: &[&str] = &[
    "listen", "health", "flags", "config", "tier", "defaults", "database", "cache",
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
        Value::Nil => Ok(Setting::Unset),
        Value::List(items) if items.iter().all(|i| matches!(i, Value::Str(_))) => {
            Ok(Setting::Texts(
                items
                    .iter()
                    .filter_map(|i| match i {
                        Value::Str(s) => Some(s.to_string()),
                        _ => None,
                    })
                    .collect(),
            ))
        }
        Value::Map(map) => map
            .iter()
            .map(|(k, v)| {
                let name = match k {
                    MapKey::Keyword(s) | MapKey::Str(s) | MapKey::Symbol(s) => {
                        setting_name(s.to_string())?
                    }
                    other => {
                        return Err(SpecError::SettingType {
                            key: key.to_string(),
                            got: other.to_value().type_name(),
                        })
                    }
                };
                let value = setting_of(&format!("{key}.{name}"), v)?;
                Ok((name, value))
            })
            .collect::<Result<BTreeMap<_, _>, _>>()
            .map(Setting::Group),
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
    let host = s.text("host")?;
    if let Some(h) = &host {
        check_name(h)?;
    }
    let host_args = s.texts("host_args")?;
    if host.is_none() && !host_args.is_empty() {
        return Err(SpecError::HostArgsWithoutHost);
    }
    if let Some(bad) = host_args.iter().find(|a| a.is_empty() || a.contains('\n')) {
        return Err(SpecError::HostArg { got: bad.clone() });
    }
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
    let cache = cache_of(s.get("cache"))?;
    let access = access_of(s.get("access"), port)?;
    let runtime = runtime_of(s.get("runtime"), s.get("because"), &access, host.as_deref())?;

    let output = match s.text("output")? {
        Some(o) => project_path("output", o)?,
        None => [DEFAULT_OUTPUT_DIR, "/", name].concat(),
    };

    Ok(Service {
        program,
        host,
        host_args,
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
        cache,
        slo,
        access,
        runtime,
        output,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bluefile::{read_bluefile, BluefileError};
    use crate::deploy::Refusal;
    use crate::deploy::{Effect, WasiGap};

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
    fn a_host_names_the_package_that_runs_the_program_and_round_trips() {
        let p = read(
            "service(\"hello\", {program: \"hello.b\", host: \"hello-host\", \
             host_args: [\"daemon\", \"--declaration\"], runtime: :native, because: :host_program, \
             repository: \"ghcr.io/pleme-io/hello\", port: 8080})\n",
        )
        .unwrap();
        let s = &p.services["hello"];
        assert_eq!(s.host.as_deref(), Some("hello-host"));
        assert_eq!(s.host_args, ["daemon", "--declaration"]);
        let back: Service = serde_json::from_str(&serde_json::to_string(s).unwrap()).unwrap();
        assert_eq!(&back, s);
    }

    #[test]
    fn without_a_host_the_lock_carries_no_host_keys() {
        let p = read(MINIMAL).unwrap();
        let s = &p.services["hello"];
        assert!(s.host.is_none() && s.host_args.is_empty());
        let json = serde_json::to_string(s).unwrap();
        assert!(!json.contains("host"));
    }

    #[test]
    fn a_broken_host_is_refused_by_name() {
        let base = "program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080";
        let cases = [
            ("host: \"Bad Name\"", "not a name"),
            ("host_args: [\"daemon\"]", "no effect without `host`"),
            ("host: \"h\", host_args: [\"\"]", "non-empty single-line"),
        ];
        for (extra, expect) in cases {
            let body = format!("service(\"hello\", {{{base}, {extra}}})\n");
            let got = refused(&body);
            assert!(
                got.iter().any(|r| r.contains(expect)),
                "{extra}: wanted `{expect}`, got {got:?}"
            );
        }
        let src = format!(
            "package(\"p\", \"0.3.0\")\nservice(\"hello\", {{{base}, host: \"h\", host_args: [\"a\\nb\"]}})\n"
        );
        let err = read_bluefile(&src)
            .err()
            .expect("a host argument with a line break is refused");
        assert!(err.to_string().contains("join_lines"), "{err}");
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
    fn a_setting_may_group_settings_list_text_or_be_unset() {
        let p = read(
            "service(\"hello\", {program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080, \
             config: {api: {exposure: \"internal\", auth: {mode: \"off\", jwks_url: nil}, \
             cors: {origins: [], hosts: [\"a\", \"b\"]}}}})\n",
        )
        .unwrap();
        let s = &p.services["hello"];
        let Setting::Group(api) = &s.config["api"] else {
            panic!("api is a group")
        };
        assert_eq!(api["exposure"], Setting::Text("internal".into()));
        let Setting::Group(auth) = &api["auth"] else {
            panic!("auth is a group")
        };
        assert_eq!(auth["jwks_url"], Setting::Unset);
        let Setting::Group(cors) = &api["cors"] else {
            panic!("cors is a group")
        };
        assert_eq!(cors["origins"], Setting::Texts(vec![]));
        assert_eq!(cors["hosts"], Setting::Texts(vec!["a".into(), "b".into()]));
        let json = serde_json::to_string(s).unwrap();
        let back: Service = serde_json::from_str(&json).unwrap();
        assert_eq!(&back, s);
    }

    #[test]
    fn a_cache_entry_is_recorded_with_its_port() {
        let base = "program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080";
        let none = read(&["service(\"hello\", {", base, "})\n"].concat()).unwrap();
        assert_eq!(none.services["hello"].cache, None);
        let bare = read(&["service(\"hello\", {", base, ", cache: {}})\n"].concat()).unwrap();
        assert_eq!(bare.services["hello"].cache, Some(Cache { port: 6379 }));
        let set =
            read(&["service(\"hello\", {", base, ", cache: {port: 6380}})\n"].concat()).unwrap();
        let s = &set.services["hello"];
        assert_eq!(s.cache, Some(Cache { port: 6380 }));
        let back: Service = serde_json::from_str(&serde_json::to_string(s).unwrap()).unwrap();
        assert_eq!(&back, s);
        assert!(
            refused(&["service(\"hello\", {", base, ", cache: {host: \"x\"}})\n"].concat())
                .iter()
                .any(|m| m.contains("is not a field here"))
        );
    }

    #[test]
    fn every_broken_rule_is_refused_by_name() {
        let base = "program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080";
        let cases = [
            ("config: {listen: 1}", "reserved"),
            ("config: {Bad: 1}", "not a setting name"),
            ("config: {a__b: 1}", "not a setting name"),
            ("config: {l: [1]}", "must be text, an integer, true/false"),
            ("config: {g: {Bad: 1}}", "not a setting name"),
            ("config: {g: {a__b: 1}}", "not a setting name"),
            ("config: {g: {l: [1]}}", "setting `g.l` must be text"),
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
    fn a_service_runs_as_wasm_with_the_default_access_unless_it_says_otherwise() {
        let p = read(MINIMAL).unwrap();
        let s = &p.services["hello"];
        assert_eq!(s.runtime, Runtime::Wasm);
        assert_eq!(s.access, Access::default_for(8080));
        let json = serde_json::to_string(s).unwrap();
        assert!(json.contains(r#""runtime":{"kind":"wasm"}"#), "{json}");
        assert!(json.contains(r#""listen":[8080]"#), "{json}");
        let back: Service = serde_json::from_str(&json).unwrap();
        assert_eq!(&back, s);
    }

    #[test]
    fn a_declared_access_is_recorded_and_wasm_still_carries_it() {
        let p = read(
            "service(\"hello\", {program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080, \
             access: {effects: [:network, :filesystem, :clock], egress: [\"db.data.svc:5432\"], \
             reads: [\"/etc/hello\"], writes: [\"/var/lib/hello\"], listen: [8080, 9090]}})\n",
        )
        .unwrap();
        let s = &p.services["hello"];
        assert_eq!(s.runtime, Runtime::Wasm);
        assert_eq!(
            s.access.effects,
            [Effect::Network, Effect::Filesystem, Effect::Clock]
        );
        assert_eq!(s.access.egress, ["db.data.svc:5432"]);
        assert_eq!(s.access.listen, [8080, 9090]);
        assert_eq!(s.access.writes, ["/var/lib/hello"]);
    }

    #[test]
    fn wasm_is_refused_by_name_when_the_service_needs_what_wasi_cannot_grant() {
        let base = "program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080";
        let cases = [
            (
                "access: {exec: [\"/bin/git\"]}",
                "its access declares exec /bin/git: WASI preview 2 has no process spawn or exec; state `runtime: :native, because: :process`",
            ),
            (
                "access: {effects: [:network, :process]}",
                "its access declares the :process effect",
            ),
            (
                "host: \"hello-host\"",
                "it runs the host program hello-host: the program is a native host binary",
            ),
            ("runtime: :native", "needs `because:` naming the WASI gap"),
            ("runtime: :native, because: :process", "names a gap nothing in this service needs"),
            ("because: :process", "explains a native runtime, and this service runs as wasm"),
            ("runtime: :oci", "is not a runtime"),
            ("runtime: :native, because: :gpu", "is not a WASI gap"),
            ("access: {effects: [:clock]}", "lacks the :network effect"),
            ("access: {writes: [\"/data\"]}", "writes need the :filesystem effect"),
            ("access: {egress: [\"db\"]}", "is not host:port"),
            ("access: {reads: [\"etc\"]}", "absolute paths"),
            ("access: {effects: [:gpu]}", "is not an effect"),
        ];
        for (extra, needle) in cases {
            let body = ["service(\"hello\", {", base, ", ", extra, "})\n"].concat();
            let errs = refused(&body);
            assert!(errs.iter().any(|e| e.contains(needle)), "{extra}: {errs:?}");
        }
    }

    #[test]
    fn native_stands_when_its_named_gap_is_real() {
        let base = "program: \"hello.b\", repository: \"ghcr.io/pleme-io/hello\", port: 8080";
        let cases = [
            (
                "access: {exec: [\"/bin/git\"]}, runtime: :native, because: :process",
                WasiGap::Process,
            ),
            (
                "host: \"hello-host\", runtime: :native, because: :host_program",
                WasiGap::HostProgram,
            ),
            ("runtime: :native, because: :device", WasiGap::Device),
        ];
        for (extra, gap) in cases {
            let body = ["service(\"hello\", {", base, ", ", extra, "})\n"].concat();
            let p = read(&body).unwrap();
            let s = &p.services["hello"];
            assert_eq!(s.runtime, Runtime::Native { because: gap }, "{extra}");
            let back: Service = serde_json::from_str(&serde_json::to_string(s).unwrap()).unwrap();
            assert_eq!(&back, s);
        }
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
