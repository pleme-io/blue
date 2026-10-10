//! The two deploy words: `image(name, spec)` and `workload(name, spec)`.
//!
//! `theory/BLUE-TOOLING.md` T-J. A Bluefile states the facts; the fleet's own
//! tools do the work. An image lowers through substrate's hardened image
//! builders (`nix/project.nix`), distroless unless a deviation is declared
//! with its reason. A workload renders to Kubernetes objects committed as a
//! generated file ([`render`]) that a GitOps reconciler applies; blue reads a
//! cluster only to compare ([`diff`]) and never writes one.
//!
//! ## The words
//!
//! ```text
//! image("hello", {
//!   program: "hello.b",                          the blue program the image runs
//!   repository: "ghcr.io/pleme-io/blue-hello",  where CI publishes it; the tag is the package version
//!   args: ["--quiet"], assets: ["static"], ports: [8080],
//!   shell: true, tools: ["jq"], reason: "…"     a deviation from distroless, with its reason
//! })
//!
//! workload("hello", {
//!   image: "hello",                  a declared image, or a pinned ref (repo:tag, repo@sha256:…)
//!   namespace: "blue-hello",
//!   replicas: 2, ports: {http: 8080}, probe: "/healthz", probe_port: "http",
//!   cpu: "50m", memory: "64Mi", memory_limit: "128Mi",
//!   env: {"LOG" => "info"}, secrets: {"TOKEN" => "hello-secrets/token"},
//!   output: "deploy/hello.yaml"
//! })
//! ```
//!
//! ## Refusal is per entry
//!
//! A spec that breaks a rule is refused as a [`Refusal`] naming its word, its
//! entry and the rule ([`SpecError`]). The manifest keeps reading, so every
//! refused entry is reported in one pass; the Bluefile then fails to read, as
//! any malformed manifest does, because a lock that silently omitted a
//! declared entry would be a fact dropped in silence.
//!
//! **Honest tier:** parse-time-rejected at the manifest boundary. The lock's
//! types carry the rules that are structural (a deviation cannot exist
//! without its reason: [`Deviation::reason`] is not optional); the rest are
//! checks [`image_of`] and [`workload_of`] run before a value is built.

pub mod diff;
pub mod render;

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::Value;

use crate::bluefile::Project;

/// The user every substrate hardened base declares (`nonrootUid`): the image
/// runs as it, and a workload of a declared image runs its pod as it.
pub const NONROOT_UID: u32 = 65532;

/// Where a workload's rendered objects are committed unless `output` says.
pub const DEFAULT_OUTPUT_DIR: &str = "deploy";

/// An OCI image a project builds from one of its blue programs.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Image {
    /// The blue program the image runs, relative to the Bluefile.
    pub program: String,
    /// Where the image is published, without a tag; the tag is the package
    /// version.
    pub repository: String,
    /// The program's own arguments.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub args: Vec<String>,
    /// Project paths the program reads at run time, under `/app`, its
    /// working directory.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub assets: Vec<String>,
    /// TCP ports the program listens on, recorded in the image config.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub ports: Vec<u16>,
    /// Anything beyond distroless. Absent is the enforced default.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub deviation: Option<Deviation>,
}

/// What an image carries beyond distroless, and why. The reason is a field,
/// not an option: a deviation without one cannot be written into a lock.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Deviation {
    /// A `/bin/sh` (substrate's glibc-only dash).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub shell: bool,
    /// nixpkgs attributes the program invokes, on the image's PATH.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<String>,
    pub reason: String,
}

/// A Deployment (and its Service) for an image.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Workload {
    /// A declared image's name, or a pinned reference.
    pub image: String,
    pub namespace: String,
    pub replicas: u32,
    /// Port name to container port; a Service exposes each.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub ports: BTreeMap<String, u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub probe: Option<Probe>,
    #[serde(default, skip_serializing_if = "Resources::is_empty")]
    pub resources: Resources,
    /// Plain environment values.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub env: BTreeMap<String, String>,
    /// Environment variables read from Secrets.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub secrets: BTreeMap<String, SecretRef>,
    /// Where the rendered objects are committed, relative to the Bluefile.
    pub output: String,
}

/// Liveness and readiness, against a named port.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase", deny_unknown_fields)]
pub enum Probe {
    Http { path: String, port: String },
    Tcp { port: String },
}

/// Requests and the memory limit. No CPU limit: the fleet sets none by
/// default (`helm-k8s-charts`, "never set default resource limits"), and
/// breathe carves what a workload is given.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Resources {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cpu: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_limit: Option<String>,
}

impl Resources {
    #[must_use]
    pub fn is_empty(&self) -> bool {
        *self == Resources::default()
    }
}

/// One key of one Secret.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SecretRef {
    pub secret: String,
    pub key: String,
}

/// One refused entry: the word, the entry's name, and the rule it broke.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
#[error("`{word}(\"{name}\", …)`: {error}")]
pub struct Refusal {
    pub word: &'static str,
    pub name: String,
    pub error: SpecError,
}

/// Why an image or workload spec is refused.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum SpecError {
    #[error("the spec must be a map ({{program: …}}), got {got}")]
    NotAMap { got: &'static str },
    #[error("`{field}` is not a field here; the fields are {}", .allowed.join(", "))]
    UnknownField {
        field: String,
        allowed: &'static [&'static str],
    },
    #[error("`{field}` is required")]
    Missing { field: &'static str },
    #[error("`{field}` must be {expected}, got {got}")]
    Type {
        field: &'static str,
        expected: &'static str,
        got: &'static str,
    },
    #[error("`{field}` must be a relative path inside the project, got `{got}`")]
    Path { field: &'static str, got: String },
    #[error("`{got}` is not a name Kubernetes and nix accept (lowercase letters, digits and `-`, at most 63, starting and ending alphanumeric)")]
    Name { got: String },
    #[error("`repository` must be a registry path without a tag or digest (the tag is the package version), got `{got}`")]
    Repository { got: String },
    #[error("`{field}`: {got} is not a TCP port (1 to 65535)")]
    Port { field: &'static str, got: i64 },
    #[error("`{got}` is not a port name (lowercase letters, digits and `-`, at most 15, with a letter)")]
    PortName { got: String },
    #[error("port {port} is declared twice")]
    DuplicatePort { port: u16 },
    #[error("`{deviation}` leaves distroless, and only a `reason` says why; add one")]
    DeviationWithoutReason { deviation: &'static str },
    #[error("`reason` explains a deviation, and this image declares none (no `shell`, no `tools`)")]
    ReasonWithoutDeviation,
    #[error("`reason` is empty")]
    EmptyReason,
    #[error("`{field}`: `{got}` is not a Kubernetes quantity (\"100m\", \"0.5\", \"128Mi\")")]
    Quantity { field: &'static str, got: String },
    #[error("`{got}` is not an environment variable name")]
    EnvName { got: String },
    #[error("secret for `{var}` must be \"secret-name/key\", got `{got}`")]
    SecretRef { var: String, got: String },
    #[error("`{var}` is in both `env` and `secrets`")]
    EnvCollision { var: String },
    #[error("an http probe's path starts with `/`, got `{got}`")]
    ProbePath { got: String },
    #[error("`probe` needs a port to reach, and `ports` is empty")]
    ProbeWithoutPort,
    #[error("`probe` could reach any of {}; name one with `probe_port`", .ports.join(", "))]
    ProbePortAmbiguous { ports: Vec<String> },
    #[error("`probe_port` names `{port}`, which `ports` does not declare")]
    UnknownProbePort { port: String },
    #[error("`probe_port` without a `probe`")]
    ProbePortWithoutProbe,
    #[error("`probe` is a path (\"/healthz\") or :tcp, got `{got}`")]
    ProbeKind { got: String },
    #[error("`replicas` must be 0 or more, got {got}")]
    Replicas { got: i64 },
    #[error("`{got}` names no image this Bluefile declares, and is not a pinned reference (repo:tag or repo@sha256:…, never :latest)")]
    ImageRef { got: String },
    #[error("`output` `{output}` is already written by {by}")]
    OutputTaken { output: String, by: String },
}

const IMAGE_FIELDS: &[&str] = &[
    "program",
    "repository",
    "args",
    "assets",
    "ports",
    "shell",
    "tools",
    "reason",
];

const WORKLOAD_FIELDS: &[&str] = &[
    "image",
    "namespace",
    "replicas",
    "ports",
    "probe",
    "probe_port",
    "cpu",
    "memory",
    "memory_limit",
    "env",
    "secrets",
    "output",
];

/// A spec map read field by field. Every key must be in `allowed`, so a
/// misspelled field is a refusal rather than a silent default.
struct Spec<'a> {
    fields: BTreeMap<String, &'a Value>,
}

impl<'a> Spec<'a> {
    fn of(value: &'a Value, allowed: &'static [&'static str]) -> Result<Self, SpecError> {
        let Value::Map(map) = value else {
            return Err(SpecError::NotAMap {
                got: value.type_name(),
            });
        };
        let mut fields = BTreeMap::new();
        for (k, v) in map.iter() {
            let key = match k {
                MapKey::Keyword(s) | MapKey::Str(s) | MapKey::Symbol(s) => s.to_string(),
                other => {
                    return Err(SpecError::Type {
                        field: "key",
                        expected: "a field name",
                        got: other.to_value().type_name(),
                    })
                }
            };
            if !allowed.contains(&key.as_str()) {
                return Err(SpecError::UnknownField {
                    field: key,
                    allowed,
                });
            }
            fields.insert(key, v);
        }
        Ok(Spec { fields })
    }

    fn get(&self, field: &str) -> Option<&'a Value> {
        self.fields.get(field).copied().filter(|v| !matches!(v, Value::Nil))
    }

    fn required(&self, field: &'static str) -> Result<&'a Value, SpecError> {
        self.get(field).ok_or(SpecError::Missing { field })
    }

    fn text(&self, field: &'static str) -> Result<Option<String>, SpecError> {
        self.get(field).map(|v| text_of(field, v)).transpose()
    }

    fn list(&self, field: &'static str) -> Result<Vec<&'a Value>, SpecError> {
        match self.get(field) {
            None => Ok(Vec::new()),
            Some(Value::List(items)) => Ok(items.iter().collect()),
            Some(v) => Err(SpecError::Type {
                field,
                expected: "a list",
                got: v.type_name(),
            }),
        }
    }

    fn texts(&self, field: &'static str) -> Result<Vec<String>, SpecError> {
        self.list(field)?
            .into_iter()
            .map(|v| text_of(field, v))
            .collect()
    }

    fn paths(&self, field: &'static str) -> Result<Vec<String>, SpecError> {
        self.texts(field)?
            .into_iter()
            .map(|p| project_path(field, p))
            .collect()
    }

    /// A map of text keys to values, keys sorted.
    fn map(&self, field: &'static str) -> Result<BTreeMap<String, &'a Value>, SpecError> {
        match self.get(field) {
            None => Ok(BTreeMap::new()),
            Some(Value::Map(map)) => map
                .iter()
                .map(|(k, v)| match k {
                    MapKey::Keyword(s) | MapKey::Str(s) | MapKey::Symbol(s) => {
                        Ok((s.to_string(), v))
                    }
                    other => Err(SpecError::Type {
                        field,
                        expected: "a map with text keys",
                        got: other.to_value().type_name(),
                    }),
                })
                .collect(),
            Some(v) => Err(SpecError::Type {
                field,
                expected: "a map",
                got: v.type_name(),
            }),
        }
    }

    fn flag(&self, field: &'static str) -> Result<bool, SpecError> {
        match self.get(field) {
            None => Ok(false),
            Some(Value::Bool(b)) => Ok(*b),
            Some(v) => Err(SpecError::Type {
                field,
                expected: "true or false",
                got: v.type_name(),
            }),
        }
    }
}

fn text_of(field: &'static str, v: &Value) -> Result<String, SpecError> {
    match v {
        Value::Str(s) => Ok(s.to_string()),
        _ => Err(SpecError::Type {
            field,
            expected: "a string",
            got: v.type_name(),
        }),
    }
}

fn int_of(field: &'static str, v: &Value) -> Result<i64, SpecError> {
    match v {
        Value::Int(n) => Ok(*n),
        _ => Err(SpecError::Type {
            field,
            expected: "an integer",
            got: v.type_name(),
        }),
    }
}

fn port_of(field: &'static str, v: &Value) -> Result<u16, SpecError> {
    let n = int_of(field, v)?;
    match u16::try_from(n) {
        Ok(p) if p > 0 => Ok(p),
        _ => Err(SpecError::Port { field, got: n }),
    }
}

/// The inside-the-project rule every Bluefile path follows.
fn project_path(field: &'static str, text: String) -> Result<String, SpecError> {
    let inside = !text.is_empty()
        && std::path::Path::new(&text).components().all(|c| {
            matches!(
                c,
                std::path::Component::Normal(_) | std::path::Component::CurDir
            )
        });
    if inside {
        Ok(text)
    } else {
        Err(SpecError::Path { field, got: text })
    }
}

/// An RFC 1123 label: what Kubernetes accepts as a name and a namespace, and
/// a valid nix attribute suffix.
#[must_use]
pub fn is_dns_label(s: &str) -> bool {
    let bytes = s.as_bytes();
    !bytes.is_empty()
        && bytes.len() <= 63
        && bytes
            .iter()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || *b == b'-')
        && bytes[0] != b'-'
        && bytes[bytes.len() - 1] != b'-'
}

fn is_port_name(s: &str) -> bool {
    is_dns_label(s)
        && s.len() <= 15
        && s.bytes().any(|b| b.is_ascii_lowercase())
        && !s.contains("--")
}

fn is_env_name(s: &str) -> bool {
    let mut bytes = s.bytes();
    matches!(bytes.next(), Some(b) if b.is_ascii_alphabetic() || b == b'_')
        && bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_')
}

/// A Kubernetes resource quantity: a decimal number and an optional suffix.
fn is_quantity(s: &str) -> bool {
    const SUFFIXES: &[&str] = &[
        "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "m", "k", "M", "G", "T", "P", "E", "",
    ];
    SUFFIXES.iter().any(|suffix| {
        s.strip_suffix(suffix).is_some_and(|number| {
            let mut parts = number.splitn(2, '.');
            let whole = parts.next().unwrap_or_default();
            let frac = parts.next();
            !whole.is_empty()
                && whole.bytes().all(|b| b.is_ascii_digit())
                && frac.is_none_or(|f| !f.is_empty() && f.bytes().all(|b| b.is_ascii_digit()))
        })
    })
}

/// A registry path with no tag and no digest: `host/path`, lowercase.
fn is_repository(s: &str) -> bool {
    let last = s.rsplit('/').next().unwrap_or_default();
    s.contains('/')
        && !last.contains(':')
        && !s.contains('@')
        && !s.starts_with('/')
        && !s.ends_with('/')
        && s.bytes().all(|b| {
            b.is_ascii_lowercase() || b.is_ascii_digit() || matches!(b, b'/' | b'.' | b'-' | b'_' | b':')
        })
}

/// A reference that names exactly one image: a digest, or a tag other than
/// `latest`. A mutable tag would let the cluster run something the commit
/// never named.
#[must_use]
pub fn is_pinned_ref(s: &str) -> bool {
    if let Some((repo, digest)) = s.split_once("@sha256:") {
        return is_repository(repo)
            && digest.len() == 64
            && digest.bytes().all(|b| b.is_ascii_hexdigit());
    }
    match s.rsplit_once(':') {
        Some((repo, tag)) => {
            is_repository(repo)
                && !tag.is_empty()
                && !tag.contains('/')
                && tag != "latest"
                && tag.len() <= 128
        }
        None => false,
    }
}

fn check_name(name: &str) -> Result<(), SpecError> {
    if is_dns_label(name) {
        Ok(())
    } else {
        Err(SpecError::Name {
            got: name.to_string(),
        })
    }
}

/// Read an `image(name, spec)` spec.
pub fn image_of(name: &str, spec: &Value) -> Result<Image, SpecError> {
    check_name(name)?;
    let s = Spec::of(spec, IMAGE_FIELDS)?;
    let program = project_path("program", text_of("program", s.required("program")?)?)?;
    let repository = text_of("repository", s.required("repository")?)?;
    if !is_repository(&repository) {
        return Err(SpecError::Repository { got: repository });
    }
    let mut ports = Vec::new();
    for v in s.list("ports")? {
        let p = port_of("ports", v)?;
        if ports.contains(&p) {
            return Err(SpecError::DuplicatePort { port: p });
        }
        ports.push(p);
    }
    let shell = s.flag("shell")?;
    let tools = s.texts("tools")?;
    let reason = s.text("reason")?;
    let deviation = match (shell || !tools.is_empty(), reason) {
        (false, None) => None,
        (false, Some(_)) => return Err(SpecError::ReasonWithoutDeviation),
        (true, None) => {
            return Err(SpecError::DeviationWithoutReason {
                deviation: if shell { "shell" } else { "tools" },
            })
        }
        (true, Some(r)) if r.trim().is_empty() => return Err(SpecError::EmptyReason),
        (true, Some(reason)) => Some(Deviation {
            shell,
            tools,
            reason,
        }),
    };
    Ok(Image {
        program,
        repository,
        args: s.texts("args")?,
        assets: s.paths("assets")?,
        ports,
        deviation,
    })
}

/// Read a `workload(name, spec)` spec. Whether `image` names a declared image
/// is a cross-entry fact, checked by [`check_entries`].
pub fn workload_of(name: &str, spec: &Value) -> Result<Workload, SpecError> {
    check_name(name)?;
    let s = Spec::of(spec, WORKLOAD_FIELDS)?;
    let image = text_of("image", s.required("image")?)?;
    let namespace = text_of("namespace", s.required("namespace")?)?;
    check_name(&namespace)?;
    let replicas = match s.get("replicas") {
        None => 1,
        Some(v) => {
            let n = int_of("replicas", v)?;
            u32::try_from(n).map_err(|_| SpecError::Replicas { got: n })?
        }
    };

    let mut ports = BTreeMap::new();
    let mut numbers = BTreeSet::new();
    for (port_name, v) in s.map("ports")? {
        if !is_port_name(&port_name) {
            return Err(SpecError::PortName { got: port_name });
        }
        let p = port_of("ports", v)?;
        if !numbers.insert(p) {
            return Err(SpecError::DuplicatePort { port: p });
        }
        ports.insert(port_name, p);
    }

    let probe_port = s.text("probe_port")?;
    let probe = match s.get("probe") {
        None => {
            if probe_port.is_some() {
                return Err(SpecError::ProbePortWithoutProbe);
            }
            None
        }
        Some(kind) => {
            let port = match probe_port {
                Some(p) if ports.contains_key(&p) => p,
                Some(p) => return Err(SpecError::UnknownProbePort { port: p }),
                None => match ports.keys().collect::<Vec<_>>().as_slice() {
                    [] => return Err(SpecError::ProbeWithoutPort),
                    [only] => (*only).clone(),
                    several => {
                        return Err(SpecError::ProbePortAmbiguous {
                            ports: several.iter().map(|p| (*p).clone()).collect(),
                        })
                    }
                },
            };
            Some(match kind {
                Value::Str(path) if path.starts_with('/') => Probe::Http {
                    path: path.to_string(),
                    port,
                },
                Value::Str(path) => {
                    return Err(SpecError::ProbePath {
                        got: path.to_string(),
                    })
                }
                Value::Keyword(k) if &**k == "tcp" => Probe::Tcp { port },
                other => {
                    return Err(SpecError::ProbeKind {
                        got: other.type_name().to_string(),
                    })
                }
            })
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

    let mut env = BTreeMap::new();
    for (var, v) in s.map("env")? {
        if !is_env_name(&var) {
            return Err(SpecError::EnvName { got: var });
        }
        env.insert(var, text_of("env", v)?);
    }
    let mut secrets = BTreeMap::new();
    for (var, v) in s.map("secrets")? {
        if !is_env_name(&var) {
            return Err(SpecError::EnvName { got: var });
        }
        if env.contains_key(&var) {
            return Err(SpecError::EnvCollision { var });
        }
        let text = text_of("secrets", v)?;
        let parsed = text
            .split_once('/')
            .filter(|(secret, key)| is_dns_label(secret) && is_secret_key(key));
        let Some((secret, key)) = parsed else {
            return Err(SpecError::SecretRef { var, got: text });
        };
        let (secret, key) = (secret.to_string(), key.to_string());
        secrets.insert(var, SecretRef { secret, key });
    }

    let output = match s.text("output")? {
        Some(o) => project_path("output", o)?,
        None => [DEFAULT_OUTPUT_DIR, "/", name, ".yaml"].concat(),
    };

    Ok(Workload {
        image,
        namespace,
        replicas,
        ports,
        probe,
        resources,
        env,
        secrets,
        output,
    })
}

fn is_secret_key(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 253
        && s
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'))
}

/// The facts that span entries, checked once the manifest has run: a
/// workload's image must be declared or pinned, and no two committed files
/// may share a path. `refused_images` are image entries already refused, so
/// a workload naming one is not refused a second time for the same cause.
#[must_use]
pub fn check_entries(project: &Project, refused_images: &BTreeSet<String>) -> Vec<Refusal> {
    let mut refusals = Vec::new();
    let mut outputs: BTreeMap<&str, String> = project
        .generated
        .iter()
        .map(|(g, spec)| (spec.output.as_str(), ["generate(\"", g, "\")"].concat()))
        .collect();
    if let Some(catalog) = &project.catalog {
        outputs.insert(catalog.as_str(), "catalog(…)".to_string());
    }
    for (name, w) in &project.workloads {
        let declared =
            project.images.contains_key(&w.image) || refused_images.contains(&w.image);
        if !declared && !is_pinned_ref(&w.image) {
            refusals.push(Refusal {
                word: "workload",
                name: name.clone(),
                error: SpecError::ImageRef {
                    got: w.image.clone(),
                },
            });
        }
        match outputs.get(w.output.as_str()) {
            Some(by) => refusals.push(Refusal {
                word: "workload",
                name: name.clone(),
                error: SpecError::OutputTaken {
                    output: w.output.clone(),
                    by: by.clone(),
                },
            }),
            None => {
                outputs.insert(&w.output, ["workload(\"", name, "\")"].concat());
            }
        }
    }
    refusals
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dns_label_is_what_kubernetes_accepts() {
        for ok in ["a", "hello", "blue-hello", "a1", &"a".repeat(63)] {
            assert!(is_dns_label(ok), "{ok}");
        }
        for bad in ["", "Hello", "-a", "a-", "a_b", "a.b", &"a".repeat(64)] {
            assert!(!is_dns_label(bad), "{bad}");
        }
    }

    #[test]
    fn a_quantity_is_a_decimal_and_a_suffix() {
        for ok in ["1", "100m", "0.5", "128Mi", "1Gi", "2k"] {
            assert!(is_quantity(ok), "{ok}");
        }
        for bad in ["", "m", "1.", ".5", "12 Mi", "1mi", "-1", "1Mx"] {
            assert!(!is_quantity(bad), "{bad}");
        }
    }

    /// A pinned reference names one image; a bare repository or `:latest`
    /// would let the cluster run what the commit never named.
    #[test]
    fn a_pinned_ref_is_a_digest_or_a_tag_other_than_latest() {
        let digest = "a".repeat(64);
        for ok in [
            "ghcr.io/pleme-io/x:1.0.0".to_string(),
            ["ghcr.io/pleme-io/x@sha256:", &digest].concat(),
            "localhost:5000/x:v2".to_string(),
        ] {
            assert!(is_pinned_ref(&ok), "{ok}");
        }
        for bad in [
            "ghcr.io/pleme-io/x",
            "ghcr.io/pleme-io/x:latest",
            "ghcr.io/pleme-io/x@sha256:abc",
            "x:1.0",
            "ghcr.io/Pleme/x:1",
        ] {
            assert!(!is_pinned_ref(bad), "{bad}");
        }
    }

    // ── the words, read through the Bluefile ──────────────────────────────

    use crate::bluefile::{read_bluefile, BluefileError};

    const IMAGE: &str =
        "image(\"hello\", {program: \"hello.b\", repository: \"ghcr.io/pleme-io/blue-hello\"})\n";

    fn project_of(body: &str) -> Project {
        let src = ["package(\"p\", \"0.3.0\")\n", body].concat();
        read_bluefile(&src)
            .unwrap_or_else(|e| panic!("{body}: {e}"))
            .project
    }

    /// Every refusal of a Bluefile that must be refused, as `(word, name, error)`.
    fn refusals_of(body: &str) -> Vec<(&'static str, String, SpecError)> {
        let src = ["package(\"p\", \"0.3.0\")\n", body].concat();
        match read_bluefile(&src) {
            Err(BluefileError::Refused { refusals }) => refusals
                .into_iter()
                .map(|r| (r.word, r.name, r.error))
                .collect(),
            Err(other) => panic!("{body}: expected refusals, got {other}"),
            Ok(_) => panic!("{body}: expected refusals, the Bluefile read"),
        }
    }

    fn only_refusal(body: &str) -> SpecError {
        match refusals_of(body).as_slice() {
            [(_, _, e)] => e.clone(),
            other => panic!("{body}: expected one refusal, got {other:?}"),
        }
    }

    #[test]
    fn an_image_is_distroless_unless_it_says_otherwise() {
        let p = project_of(IMAGE);
        assert_eq!(
            p.images["hello"],
            Image {
                program: "hello.b".into(),
                repository: "ghcr.io/pleme-io/blue-hello".into(),
                args: vec![],
                assets: vec![],
                ports: vec![],
                deviation: None,
            }
        );
    }

    #[test]
    fn an_image_records_its_args_assets_and_ports() {
        let p = project_of(
            "image(\"hello\", {program: \"src/hello.b\", repository: \"ghcr.io/pleme-io/h\", \
             args: [\"--port\", \"8080\"], assets: [\"static\"], ports: [8080, 9090]})\n",
        );
        let i = &p.images["hello"];
        assert_eq!(i.args, vec!["--port", "8080"]);
        assert_eq!(i.assets, vec!["static"]);
        assert_eq!(i.ports, vec![8080, 9090]);
    }

    /// The rule the word exists for: leaving distroless takes a reason.
    /// Red run, 2026-10-10: with the `(true, None)` arm returning
    /// `Some(Deviation { reason: String::new(), .. })` this test and
    /// `every_refused_entry_is_reported_in_one_pass_naming_itself` failed,
    /// this one with "expected refusals, the Bluefile read".
    #[test]
    fn a_shell_or_tools_without_a_reason_is_refused() {
        let base = "program: \"h.b\", repository: \"ghcr.io/pleme-io/h\"";
        for (extra, deviation) in [("shell: true", "shell"), ("tools: [\"jq\"]", "tools")] {
            let body = ["image(\"h\", {", base, ", ", extra, "})\n"].concat();
            assert_eq!(
                only_refusal(&body),
                SpecError::DeviationWithoutReason { deviation },
                "{body}"
            );
        }
        let body = ["image(\"h\", {", base, ", shell: true, reason: \"  \"})\n"].concat();
        assert_eq!(only_refusal(&body), SpecError::EmptyReason);
    }

    /// A reason with nothing to explain is a stale waiver, refused rather than
    /// carried.
    #[test]
    fn a_reason_without_a_deviation_is_refused() {
        let body = "image(\"h\", {program: \"h.b\", repository: \"ghcr.io/pleme-io/h\", reason: \"why\"})\n";
        assert_eq!(only_refusal(body), SpecError::ReasonWithoutDeviation);
    }

    #[test]
    fn a_deviation_with_its_reason_is_recorded() {
        let p = project_of(
            "image(\"h\", {program: \"h.b\", repository: \"ghcr.io/pleme-io/h\", \
             shell: true, tools: [\"jq\"], reason: \"the entrypoint pipes through jq\"})\n",
        );
        assert_eq!(
            p.images["h"].deviation,
            Some(Deviation {
                shell: true,
                tools: vec!["jq".into()],
                reason: "the entrypoint pipes through jq".into(),
            })
        );
    }

    #[test]
    fn a_misspelled_field_is_refused_naming_it() {
        let e = only_refusal("image(\"h\", {progam: \"h.b\", repository: \"ghcr.io/pleme-io/h\"})\n");
        assert!(
            matches!(e, SpecError::UnknownField { ref field, .. } if field == "progam"),
            "{e}"
        );
    }

    #[test]
    fn image_specs_are_refused_by_rule() {
        for (body, want) in [
            (
                "image(\"h\", {repository: \"ghcr.io/pleme-io/h\"})",
                SpecError::Missing { field: "program" },
            ),
            (
                "image(\"h\", {program: \"h.b\", repository: \"ghcr.io/pleme-io/h:1.0\"})",
                SpecError::Repository {
                    got: "ghcr.io/pleme-io/h:1.0".into(),
                },
            ),
            (
                "image(\"h\", {program: \"../h.b\", repository: \"ghcr.io/pleme-io/h\"})",
                SpecError::Path {
                    field: "program",
                    got: "../h.b".into(),
                },
            ),
            (
                "image(\"h\", {program: \"h.b\", repository: \"ghcr.io/pleme-io/h\", ports: [0]})",
                SpecError::Port {
                    field: "ports",
                    got: 0,
                },
            ),
            (
                "image(\"H_1\", {program: \"h.b\", repository: \"ghcr.io/pleme-io/h\"})",
                SpecError::Name { got: "H_1".into() },
            ),
            (
                "image(\"h\", \"h.b\")",
                SpecError::NotAMap { got: "string" },
            ),
        ] {
            assert_eq!(only_refusal(body), want, "{body}");
        }
    }

    #[test]
    fn a_workload_records_its_defaults() {
        let p = project_of(
            &[
                IMAGE,
                "workload(\"hello\", {image: \"hello\", namespace: \"blue\", ports: {http: 8080}, probe: \"/healthz\"})\n",
            ]
            .concat(),
        );
        let w = &p.workloads["hello"];
        assert_eq!(w.replicas, 1);
        assert_eq!(w.output, "deploy/hello.yaml");
        assert_eq!(
            w.probe,
            Some(Probe::Http {
                path: "/healthz".into(),
                port: "http".into()
            })
        );
    }

    #[test]
    fn a_workload_records_resources_env_and_secrets() {
        let p = project_of(
            &[
                IMAGE,
                "workload(\"hello\", {image: \"hello\", namespace: \"blue\", replicas: 0, \
                 cpu: \"50m\", memory: \"64Mi\", memory_limit: \"128Mi\", \
                 env: {\"LOG\" => \"info\"}, secrets: {\"TOKEN\" => \"hello-secrets/token\"}, \
                 ports: {http: 8080, metrics: 9090}, probe: :tcp, probe_port: \"metrics\", \
                 output: \"k8s/hello.yaml\"})\n",
            ]
            .concat(),
        );
        let w = &p.workloads["hello"];
        assert_eq!(w.replicas, 0);
        assert_eq!(w.resources.memory_limit.as_deref(), Some("128Mi"));
        assert_eq!(w.env["LOG"], "info");
        assert_eq!(w.secrets["TOKEN"].secret, "hello-secrets");
        assert_eq!(w.secrets["TOKEN"].key, "token");
        assert_eq!(
            w.probe,
            Some(Probe::Tcp {
                port: "metrics".into()
            })
        );
        assert_eq!(w.output, "k8s/hello.yaml");
    }

    /// Each invalid combination is refused with its own typed error.
    #[test]
    fn workload_combinations_are_refused_by_rule() {
        let w = |fields: &str| {
            [IMAGE, "workload(\"w\", {image: \"hello\", namespace: \"blue\", ", fields, "})\n"]
                .concat()
        };
        for (fields, want) in [
            ("probe: \"/healthz\"", SpecError::ProbeWithoutPort),
            (
                "ports: {a: 1, b: 2}, probe: \"/healthz\"",
                SpecError::ProbePortAmbiguous {
                    ports: vec!["a".into(), "b".into()],
                },
            ),
            (
                "ports: {a: 1}, probe: \"/h\", probe_port: \"b\"",
                SpecError::UnknownProbePort { port: "b".into() },
            ),
            (
                "ports: {a: 1}, probe: \"healthz\"",
                SpecError::ProbePath {
                    got: "healthz".into(),
                },
            ),
            ("ports: {a: 1}, probe_port: \"a\"", SpecError::ProbePortWithoutProbe),
            (
                "ports: {a: 1, b: 1}",
                SpecError::DuplicatePort { port: 1 },
            ),
            ("replicas: -1", SpecError::Replicas { got: -1 }),
            (
                "cpu: \"lots\"",
                SpecError::Quantity {
                    field: "cpu",
                    got: "lots".into(),
                },
            ),
            (
                "env: {\"A\" => \"1\"}, secrets: {\"A\" => \"s/k\"}",
                SpecError::EnvCollision { var: "A".into() },
            ),
            (
                "secrets: {\"A\" => \"no-key\"}",
                SpecError::SecretRef {
                    var: "A".into(),
                    got: "no-key".into(),
                },
            ),
            (
                "env: {\"A-B\" => \"1\"}",
                SpecError::EnvName { got: "A-B".into() },
            ),
            (
                "output: \"/etc/x.yaml\"",
                SpecError::Path {
                    field: "output",
                    got: "/etc/x.yaml".into(),
                },
            ),
        ] {
            assert_eq!(only_refusal(&w(fields)), want, "{fields}");
        }
        assert_eq!(
            only_refusal(&[IMAGE, "workload(\"w\", {image: \"hello\", namespace: \"Blue\"})\n"].concat()),
            SpecError::Name { got: "Blue".into() }
        );
    }

    /// The image a workload runs is a declared image or a pinned reference:
    /// a bare repository or `:latest` is refused.
    #[test]
    fn a_workload_image_is_declared_or_pinned() {
        let ok = project_of("workload(\"w\", {image: \"ghcr.io/x/y:1.2.3\", namespace: \"n\"})\n");
        assert_eq!(ok.workloads["w"].image, "ghcr.io/x/y:1.2.3");
        for image in ["nope", "ghcr.io/x/y", "ghcr.io/x/y:latest"] {
            let body = ["workload(\"w\", {image: \"", image, "\", namespace: \"n\"})\n"].concat();
            assert_eq!(
                only_refusal(&body),
                SpecError::ImageRef { got: image.into() },
                "{image}"
            );
        }
    }

    /// **Refusal is per entry.** Two bad entries and a good one: both bad ones
    /// are reported, each naming itself, and a workload of a refused image is
    /// not refused a second time for the image's fault.
    #[test]
    fn every_refused_entry_is_reported_in_one_pass_naming_itself() {
        let body = "image(\"bad\", {program: \"b.b\", repository: \"ghcr.io/x/b\", shell: true})\n\
                    image(\"good\", {program: \"g.b\", repository: \"ghcr.io/x/g\"})\n\
                    workload(\"uses-bad\", {image: \"bad\", namespace: \"n\"})\n\
                    workload(\"broken\", {image: \"good\", namespace: \"n\", replicas: -2})\n\
                    workload(\"fine\", {image: \"good\", namespace: \"n\"})\n";
        let refusals = refusals_of(body);
        assert_eq!(
            refusals,
            vec![
                (
                    "image",
                    "bad".to_string(),
                    SpecError::DeviationWithoutReason { deviation: "shell" }
                ),
                ("workload", "broken".to_string(), SpecError::Replicas { got: -2 }),
            ]
        );
        let src = ["package(\"p\", \"0.3.0\")\n", body].concat();
        let message = read_bluefile(&src).expect_err("refused").to_string();
        assert!(message.contains("`image(\"bad\", …)`"), "{message}");
        assert!(message.contains("`workload(\"broken\", …)`"), "{message}");
    }

    #[test]
    fn a_workload_output_may_not_overwrite_another_committed_file() {
        let e = only_refusal(
            "generate(\"g\", \"deploy/w.yaml\", \"g.b\")\n\
             workload(\"w\", {image: \"ghcr.io/x/y:1\", namespace: \"n\"})\n",
        );
        assert_eq!(
            e,
            SpecError::OutputTaken {
                output: "deploy/w.yaml".into(),
                by: "generate(\"g\")".into()
            }
        );
    }

    /// A project that declares neither word serializes neither key, so every
    /// lock written before them keeps its bytes.
    #[test]
    fn a_project_without_images_or_workloads_has_neither_key() {
        let v = serde_json::to_value(project_of("tool(\"jq\")\n")).expect("json");
        assert!(v.get("images").is_none() && v.get("workloads").is_none(), "{v}");
    }

    #[test]
    fn env_names_are_c_identifiers() {
        assert!(is_env_name("LOG_LEVEL"));
        assert!(is_env_name("_x1"));
        assert!(!is_env_name("1X"));
        assert!(!is_env_name("A-B"));
        assert!(!is_env_name(""));
    }
}
