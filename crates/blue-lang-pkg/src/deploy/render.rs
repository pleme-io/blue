//! A workload, rendered: the Kubernetes objects a GitOps reconciler applies.
//!
//! ## Why objects, and not values for a fleet chart
//!
//! The fleet's application charts (`pleme-microservice`, `pleme-worker`, over
//! the `pleme-lib` library) render liveness and readiness as HTTP GETs
//! unconditionally. No blue program can answer one today: blue's `net` speaks
//! HTTP and NATS as a client and has no listener. A HelmRelease of those charts
//! would render a workload that never becomes Ready. So the rendering is the
//! objects themselves, typed here, with the probe a field (`http`, `tcp`, or
//! none), committed as a generated file that a Flux Kustomization applies.
//! When blue can serve HTTP, a chart rendering joins as a field of the
//! workload; this one stays.
//!
//! The file holds one `v1` `List`, as JSON. JSON is YAML, so the file is
//! named `.yaml` and every Kubernetes tool, kustomize and Flux read it as
//! written; JSON because `serde_json` is the typed emitter this workspace
//! already carries.

use std::collections::BTreeMap;

use serde::Serialize;

use super::{Probe, Workload, NONROOT_UID};
use crate::lock::ManifestRecord;

/// Why a workload could not be rendered from a lock.
#[derive(Debug, thiserror::Error)]
pub enum RenderError {
    #[error("no workload `{name}`; this lock declares {}", if .known.is_empty() { "none".to_string() } else { .known.join(", ") })]
    Unknown { name: String, known: Vec<String> },
    #[error("could not render JSON: {0}")]
    Json(#[from] serde_json::Error),
}

/// The objects one workload renders to.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct List {
    api_version: &'static str,
    kind: &'static str,
    pub items: Vec<Object>,
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
pub enum Object {
    Deployment(Deployment),
    Service(Service),
}

impl Object {
    /// What `kubectl get` names this object by: its resource, name and
    /// namespace.
    #[must_use]
    pub fn target(&self) -> Target<'_> {
        let (resource, meta) = match self {
            Object::Deployment(d) => ("deployment.apps", &d.metadata),
            Object::Service(s) => ("service", &s.metadata),
        };
        Target {
            resource,
            name: &meta.name,
            namespace: &meta.namespace,
        }
    }
}

/// An object's address in a cluster.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Target<'a> {
    pub resource: &'static str,
    pub name: &'a str,
    pub namespace: &'a str,
}

impl std::fmt::Display for Target<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} {}/{}", self.resource, self.namespace, self.name)
    }
}

type Labels = BTreeMap<&'static str, String>;

#[derive(Debug, Serialize)]
pub struct Metadata {
    name: String,
    namespace: String,
    labels: Labels,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Deployment {
    api_version: &'static str,
    kind: &'static str,
    metadata: Metadata,
    spec: DeploymentSpec,
}

#[derive(Debug, Serialize)]
struct DeploymentSpec {
    replicas: u32,
    selector: Selector,
    template: PodTemplate,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Selector {
    match_labels: Labels,
}

#[derive(Debug, Serialize)]
struct PodTemplate {
    metadata: PodMetadata,
    spec: PodSpec,
}

#[derive(Debug, Serialize)]
struct PodMetadata {
    labels: Labels,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct PodSpec {
    security_context: PodSecurityContext,
    containers: Vec<Container>,
    volumes: Vec<Volume>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct PodSecurityContext {
    run_as_non_root: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    run_as_user: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    run_as_group: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    fs_group: Option<u32>,
    seccomp_profile: SeccompProfile,
}

#[derive(Debug, Serialize)]
struct SeccompProfile {
    #[serde(rename = "type")]
    kind: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Container {
    name: String,
    image: String,
    image_pull_policy: &'static str,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    ports: Vec<ContainerPort>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    env: Vec<EnvVar>,
    #[serde(skip_serializing_if = "ResourceRequirements::is_empty")]
    resources: ResourceRequirements,
    #[serde(skip_serializing_if = "Option::is_none")]
    liveness_probe: Option<ProbeSpec>,
    #[serde(skip_serializing_if = "Option::is_none")]
    readiness_probe: Option<ProbeSpec>,
    security_context: ContainerSecurityContext,
    volume_mounts: Vec<VolumeMount>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ContainerPort {
    name: String,
    container_port: u16,
    protocol: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EnvVar {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    value_from: Option<EnvSource>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EnvSource {
    secret_key_ref: KeyRef,
}

#[derive(Debug, Serialize)]
struct KeyRef {
    name: String,
    key: String,
}

#[derive(Debug, Default, Serialize)]
struct ResourceRequirements {
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    requests: BTreeMap<&'static str, String>,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    limits: BTreeMap<&'static str, String>,
}

impl ResourceRequirements {
    fn is_empty(&self) -> bool {
        self.requests.is_empty() && self.limits.is_empty()
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ProbeSpec {
    #[serde(skip_serializing_if = "Option::is_none")]
    http_get: Option<HttpGet>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tcp_socket: Option<TcpSocket>,
    period_seconds: u32,
}

#[derive(Debug, Serialize)]
struct HttpGet {
    path: String,
    port: String,
}

#[derive(Debug, Serialize)]
struct TcpSocket {
    port: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ContainerSecurityContext {
    allow_privilege_escalation: bool,
    read_only_root_filesystem: bool,
    capabilities: Capabilities,
}

#[derive(Debug, Serialize)]
struct Capabilities {
    drop: Vec<&'static str>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Volume {
    name: &'static str,
    empty_dir: EmptyDir,
}

#[derive(Debug, Serialize)]
struct EmptyDir {}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct VolumeMount {
    name: &'static str,
    mount_path: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Service {
    api_version: &'static str,
    kind: &'static str,
    metadata: Metadata,
    spec: ServiceSpec,
}

#[derive(Debug, Serialize)]
struct ServiceSpec {
    #[serde(rename = "type")]
    kind: &'static str,
    selector: Labels,
    ports: Vec<ServicePort>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ServicePort {
    name: String,
    port: u16,
    target_port: String,
    protocol: &'static str,
}

/// The reference a workload's container runs: a declared image at the
/// package version, or the pinned reference as written.
struct ImageRef<'a> {
    repository: &'a str,
    tag: Option<&'a str>,
}

impl std::fmt::Display for ImageRef<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.tag {
            Some(tag) => write!(f, "{}:{tag}", self.repository),
            None => f.write_str(self.repository),
        }
    }
}

/// Every workload a lock declares, by name.
#[must_use]
pub fn workloads(manifest: &ManifestRecord) -> Vec<&str> {
    manifest
        .project
        .workloads
        .keys()
        .map(String::as_str)
        .collect()
}

/// Render one workload of a lock to its objects.
pub fn render(manifest: &ManifestRecord, name: &str) -> Result<List, RenderError> {
    let w = manifest
        .project
        .workloads
        .get(name)
        .ok_or_else(|| RenderError::Unknown {
            name: name.to_string(),
            known: workloads(manifest).into_iter().map(String::from).collect(),
        })?;
    Ok(objects(manifest, name, w))
}

/// Render one workload to the bytes its `output` file holds.
pub fn render_text(manifest: &ManifestRecord, name: &str) -> Result<String, RenderError> {
    let mut text = serde_json::to_string_pretty(&render(manifest, name)?)?;
    text.push('\n');
    Ok(text)
}

fn objects(manifest: &ManifestRecord, name: &str, w: &Workload) -> List {
    let declared = manifest.project.images.get(&w.image);
    let image = match declared {
        Some(image) => ImageRef {
            repository: &image.repository,
            tag: Some(&manifest.version),
        },
        None => ImageRef {
            repository: &w.image,
            tag: None,
        },
    };

    let selector: Labels = [
        ("app.kubernetes.io/name", name.to_string()),
        ("app.kubernetes.io/part-of", manifest.name.clone()),
    ]
    .into_iter()
    .collect();
    let mut labels = selector.clone();
    labels.insert("app.kubernetes.io/managed-by", "blue".to_string());
    if declared.is_some() {
        labels.insert("app.kubernetes.io/version", manifest.version.clone());
    }
    let metadata = || Metadata {
        name: name.to_string(),
        namespace: w.namespace.clone(),
        labels: labels.clone(),
    };

    let probe = |period_seconds| {
        w.probe.as_ref().map(|p| match p {
            Probe::Http { path, port } => ProbeSpec {
                http_get: Some(HttpGet {
                    path: path.clone(),
                    port: port.clone(),
                }),
                tcp_socket: None,
                period_seconds,
            },
            Probe::Tcp { port } => ProbeSpec {
                http_get: None,
                tcp_socket: Some(TcpSocket { port: port.clone() }),
                period_seconds,
            },
        })
    };

    let env = w
        .env
        .iter()
        .map(|(k, v)| EnvVar {
            name: k.clone(),
            value: Some(v.clone()),
            value_from: None,
        })
        .chain(w.secrets.iter().map(|(k, s)| EnvVar {
            name: k.clone(),
            value: None,
            value_from: Some(EnvSource {
                secret_key_ref: KeyRef {
                    name: s.secret.clone(),
                    key: s.key.clone(),
                },
            }),
        }))
        .collect();

    let mut resources = ResourceRequirements::default();
    if let Some(cpu) = &w.resources.cpu {
        resources.requests.insert("cpu", cpu.clone());
    }
    if let Some(memory) = &w.resources.memory {
        resources.requests.insert("memory", memory.clone());
    }
    if let Some(limit) = &w.resources.memory_limit {
        resources.limits.insert("memory", limit.clone());
    }

    let uid = declared.map(|_| NONROOT_UID);
    let deployment = Deployment {
        api_version: "apps/v1",
        kind: "Deployment",
        metadata: metadata(),
        spec: DeploymentSpec {
            replicas: w.replicas,
            selector: Selector {
                match_labels: selector.clone(),
            },
            template: PodTemplate {
                metadata: PodMetadata {
                    labels: labels.clone(),
                },
                spec: PodSpec {
                    security_context: PodSecurityContext {
                        run_as_non_root: true,
                        run_as_user: uid,
                        run_as_group: uid,
                        fs_group: uid,
                        seccomp_profile: SeccompProfile {
                            kind: "RuntimeDefault",
                        },
                    },
                    containers: vec![Container {
                        name: name.to_string(),
                        image: image.to_string(),
                        image_pull_policy: "IfNotPresent",
                        ports: w
                            .ports
                            .iter()
                            .map(|(n, p)| ContainerPort {
                                name: n.clone(),
                                container_port: *p,
                                protocol: "TCP",
                            })
                            .collect(),
                        env,
                        resources,
                        liveness_probe: probe(10),
                        readiness_probe: probe(5),
                        security_context: ContainerSecurityContext {
                            allow_privilege_escalation: false,
                            read_only_root_filesystem: true,
                            capabilities: Capabilities { drop: vec!["ALL"] },
                        },
                        volume_mounts: vec![VolumeMount {
                            name: "tmp",
                            mount_path: "/tmp",
                        }],
                    }],
                    volumes: vec![Volume {
                        name: "tmp",
                        empty_dir: EmptyDir {},
                    }],
                },
            },
        },
    };

    let mut items = vec![Object::Deployment(deployment)];
    if !w.ports.is_empty() {
        items.push(Object::Service(Service {
            api_version: "v1",
            kind: "Service",
            metadata: metadata(),
            spec: ServiceSpec {
                kind: "ClusterIP",
                selector,
                ports: w
                    .ports
                    .iter()
                    .map(|(n, p)| ServicePort {
                        name: n.clone(),
                        port: *p,
                        target_port: n.clone(),
                        protocol: "TCP",
                    })
                    .collect(),
            },
        }));
    }
    List {
        api_version: "v1",
        kind: "List",
        items,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bluefile::read_bluefile;
    use serde_json::{json, Value};

    fn manifest(body: &str) -> ManifestRecord {
        let src = ["package(\"hello-project\", \"0.3.0\")\n", body].concat();
        ManifestRecord::of(&read_bluefile(&src).expect("read"))
    }

    fn rendered(body: &str, name: &str) -> Value {
        serde_json::to_value(render(&manifest(body), name).expect("render")).expect("json")
    }

    const DECLARED: &str = "image(\"hello\", {program: \"h.b\", repository: \"ghcr.io/pleme-io/blue-hello\"})\n\
        workload(\"hello\", {image: \"hello\", namespace: \"blue\", replicas: 2, ports: {http: 8080}, \
        probe: \"/healthz\", memory: \"64Mi\", env: {\"LOG\" => \"info\"}, secrets: {\"TOKEN\" => \"s/token\"}})\n";

    /// A declared image runs at the package version, as the substrate base's
    /// non-root user, behind a Service for its ports.
    #[test]
    fn a_workload_of_a_declared_image_renders_a_deployment_and_a_service() {
        let v = rendered(DECLARED, "hello");
        assert_eq!(v["kind"], "List");
        let deployment = &v["items"][0];
        assert_eq!(deployment["kind"], "Deployment");
        assert_eq!(deployment["metadata"]["namespace"], "blue");
        assert_eq!(deployment["spec"]["replicas"], 2);
        let pod = &deployment["spec"]["template"]["spec"];
        assert_eq!(pod["securityContext"]["runAsUser"], NONROOT_UID);
        let c = &pod["containers"][0];
        assert_eq!(c["image"], "ghcr.io/pleme-io/blue-hello:0.3.0");
        assert_eq!(
            c["livenessProbe"]["httpGet"],
            json!({"path": "/healthz", "port": "http"})
        );
        assert_eq!(c["resources"], json!({"requests": {"memory": "64Mi"}}));
        assert_eq!(
            c["env"],
            json!([
                {"name": "LOG", "value": "info"},
                {"name": "TOKEN", "valueFrom": {"secretKeyRef": {"name": "s", "key": "token"}}}
            ])
        );
        assert_eq!(c["securityContext"]["readOnlyRootFilesystem"], true);
        let service = &v["items"][1];
        assert_eq!(service["kind"], "Service");
        assert_eq!(
            service["spec"]["ports"],
            json!([{"name": "http", "port": 8080, "targetPort": "http", "protocol": "TCP"}])
        );
        assert_eq!(
            service["spec"]["selector"],
            deployment["spec"]["selector"]["matchLabels"]
        );
    }

    /// A pinned image is not blue's, so its user is not assumed; with no
    /// ports there is no Service and no probe.
    #[test]
    fn a_workload_of_a_pinned_image_assumes_nothing_about_it() {
        let v = rendered(
            "workload(\"w\", {image: \"ghcr.io/x/y:1.2.3\", namespace: \"n\"})\n",
            "w",
        );
        let items = v["items"].as_array().expect("items");
        assert_eq!(items.len(), 1, "no ports, no Service");
        let pod = &items[0]["spec"]["template"]["spec"];
        assert_eq!(pod["securityContext"].get("runAsUser"), None);
        assert_eq!(pod["containers"][0]["image"], "ghcr.io/x/y:1.2.3");
        assert_eq!(pod["containers"][0].get("livenessProbe"), None);
        assert_eq!(
            items[0]["metadata"]["labels"].get("app.kubernetes.io/version"),
            None
        );
    }

    #[test]
    fn rendering_an_undeclared_workload_names_the_declared_ones() {
        let err = render(&manifest(DECLARED), "nope").expect_err("unknown");
        assert_eq!(
            err.to_string(),
            "no workload `nope`; this lock declares hello"
        );
    }

    /// The bytes are a pure function of the lock: the freshness gate compares
    /// them, so two renders must agree.
    #[test]
    fn rendering_is_deterministic_and_ends_in_a_newline() {
        let m = manifest(DECLARED);
        let a = render_text(&m, "hello").expect("render");
        assert_eq!(a, render_text(&m, "hello").expect("render"));
        assert!(a.ends_with("}\n"));
    }
}
