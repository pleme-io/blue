//! `blue image build`, `blue workload render` and `blue diff`: the doors to
//! the Bluefile's `image` and `workload` words (`blue_lang_pkg::deploy`).
//!
//! Each one hands the work to the tool that owns it. An image is built by
//! nix, through the project engine's `packages.image-<name>` (substrate's
//! hardened builders); this door only says which attribute and reads back
//! what was built. A workload is rendered from `Bluefile.lock`, the same bytes
//! nix gates fresh. A cluster is read with `kubectl get` and nothing else.
//!
//! **There is no `blue apply`, by design.** Applying is GitOps: the rendered
//! file is committed and a reconciler (a Flux Kustomization) converges the
//! cluster on it. `blue diff` shows what that commit would change, under an
//! explicit `--context`, because the operator's kubeconfig holds production
//! contexts and a default one is a guess.

use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};

use blue_lang_pkg::deploy::diff::{diff as compare, Change};
use blue_lang_pkg::deploy::render::{render_text, workloads, RenderError};
use blue_lang_pkg::lock::{Lock, ManifestRecord, LOCK_FILE};

/// `blue image …`.
#[derive(clap::Subcommand)]
pub enum ImageCmd {
    /// Build an `image(...)` through nix and report the tarball, its size and
    /// its layers. With no NAME, every image the Bluefile declares.
    ///
    /// Builds `<dir>#packages.<system>.image-<name>`, the project engine's
    /// lowering of the word. Images are Linux; off Linux the default system is
    /// x86_64-linux, built by a remote builder. Arguments after `--` go to
    /// `nix build` (`-- --override-input blue ../blue`).
    Build {
        name: Option<String>,
        /// The project directory: its Bluefile.lock and its flake.
        #[arg(long, default_value = ".")]
        dir: PathBuf,
        /// The Linux system to build for.
        #[arg(long)]
        system: Option<String>,
        #[arg(last = true)]
        nix_args: Vec<String>,
    },
}

/// `blue workload …`.
#[derive(clap::Subcommand)]
pub enum WorkloadCmd {
    /// Print a workload's rendered objects, or with `--write` rewrite every
    /// workload's committed `output` file. Reads Bluefile.lock, as nix does.
    Render {
        name: Option<String>,
        #[arg(long, default_value = LOCK_FILE)]
        lock: PathBuf,
        #[arg(long)]
        write: bool,
    },
}

/// `blue diff`.
#[derive(clap::Args)]
pub struct DiffArgs {
    /// One workload; every workload when omitted.
    name: Option<String>,
    /// The kubeconfig context to read. Required: there is no default.
    #[arg(long)]
    context: Option<String>,
    #[arg(long, default_value = LOCK_FILE)]
    lock: PathBuf,
    /// The kubectl to run.
    #[arg(long, default_value = "kubectl")]
    kubectl: PathBuf,
}

#[derive(Debug, thiserror::Error)]
pub enum DeployError {
    #[error(
        "`blue diff` reads a cluster, and names it: pass --context. The kubeconfig \
         may hold production contexts, so there is no default. (blue never applies; \
         a GitOps reconciler applies the committed files.)"
    )]
    NoContext,
    #[error("{path}: {source}")]
    Read {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{path}: {source}")]
    Write {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{path} is not readable JSON: {source}")]
    Json {
        path: String,
        #[source]
        source: serde_json::Error,
    },
    #[error("{0}")]
    Render(#[from] RenderError),
    #[error("the Bluefile declares no {what}")]
    None { what: &'static str },
    #[error("no {what} `{name}`; the Bluefile declares {}", .known.join(", "))]
    Unknown {
        what: &'static str,
        name: String,
        known: Vec<String>,
    },
    #[error("the Bluefile declares several workloads ({}); name one, or pass --write", .known.join(", "))]
    PickOne { known: Vec<String> },
    #[error("could not start `{program}`: {source}")]
    Spawn {
        program: String,
        #[source]
        source: std::io::Error,
    },
    #[error("nix build failed ({status})")]
    Nix { status: std::process::ExitStatus },
    #[error("nix build printed {got} path(s) for 2 attributes")]
    NixOutput { got: usize },
    #[error("{path} has no image entry with `Layers`")]
    Layers { path: String },
    #[error("{target}: kubectl get failed ({status}): {stderr}")]
    Kubectl {
        target: String,
        status: std::process::ExitStatus,
        stderr: String,
    },
    #[error("{path}: an item of kind `{kind}` is not one blue renders")]
    Kind { path: String, kind: String },
}

fn read(path: &Path) -> Result<String, DeployError> {
    std::fs::read_to_string(path).map_err(|source| DeployError::Read {
        path: path.display().to_string(),
        source,
    })
}

fn json<T: serde::de::DeserializeOwned>(path: &Path, text: &str) -> Result<T, DeployError> {
    serde_json::from_str(text).map_err(|source| DeployError::Json {
        path: path.display().to_string(),
        source,
    })
}

fn manifest_at(lock: &Path) -> Result<ManifestRecord, DeployError> {
    let lock_value: Lock = json(lock, &read(lock)?)?;
    Ok(lock_value.manifest)
}

/// The names a command acts on: the one named, or all of them.
fn select<'a>(
    what: &'static str,
    name: Option<&'a str>,
    known: Vec<&'a str>,
) -> Result<Vec<&'a str>, DeployError> {
    if known.is_empty() {
        return Err(DeployError::None { what });
    }
    match name {
        None => Ok(known),
        Some(n) if known.contains(&n) => Ok(vec![n]),
        Some(n) => Err(DeployError::Unknown {
            what,
            name: n.to_string(),
            known: known.into_iter().map(String::from).collect(),
        }),
    }
}

/// The Linux system an image is built for when `--system` is not given: the
/// host's own on Linux, else x86_64-linux.
fn default_system() -> &'static str {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("linux", "aarch64") => "aarch64-linux",
        _ => "x86_64-linux",
    }
}

/// A byte count as people read it.
struct Size(u64);

impl std::fmt::Display for Size {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mib = self.0 as f64 / (1024.0 * 1024.0);
        write!(f, "{mib:.1} MiB ({} bytes)", self.0)
    }
}

pub fn image(cmd: ImageCmd) -> Result<ExitCode, DeployError> {
    let ImageCmd::Build {
        name,
        dir,
        system,
        nix_args,
    } = cmd;
    let lock = dir.join(LOCK_FILE);
    let manifest = manifest_at(&lock)?;
    let known = manifest.project.images.keys().map(String::as_str).collect();
    let system: &str = system.as_deref().unwrap_or(default_system());
    let flake = std::fs::canonicalize(&dir).map_err(|source| DeployError::Read {
        path: dir.display().to_string(),
        source,
    })?;
    let flake = flake.display().to_string();
    for image in select("image", name.as_deref(), known)? {
        let attr = ["packages.", system, ".image-", image].concat();
        let tarball_attr = [flake.as_str(), "#", &attr].concat();
        let manifest_attr = [tarball_attr.as_str(), "-manifest"].concat();
        let out = Command::new("nix")
            .args(["build", "--no-link", "--print-out-paths"])
            .arg(&tarball_attr)
            .arg(&manifest_attr)
            .args(&nix_args)
            .stderr(Stdio::inherit())
            .output()
            .map_err(|source| DeployError::Spawn {
                program: "nix".into(),
                source,
            })?;
        if !out.status.success() {
            return Err(DeployError::Nix { status: out.status });
        }
        let stdout = String::from_utf8_lossy(&out.stdout);
        let paths: Vec<&str> = stdout.lines().filter(|l| !l.is_empty()).collect();
        let [tarball, docker_manifest] = paths.as_slice() else {
            return Err(DeployError::NixOutput { got: paths.len() });
        };
        let tarball = Path::new(tarball);
        let size = std::fs::metadata(tarball)
            .map_err(|source| DeployError::Read {
                path: tarball.display().to_string(),
                source,
            })?
            .len();
        let docker_manifest = Path::new(docker_manifest);
        let entries: Vec<serde_json::Value> =
            json(docker_manifest, &read(docker_manifest)?)?;
        let layers = entries
            .first()
            .and_then(|e| e.get("Layers"))
            .and_then(serde_json::Value::as_array)
            .ok_or_else(|| DeployError::Layers {
                path: docker_manifest.display().to_string(),
            })?
            .len();
        let spec = &manifest.project.images[image];
        println!("image {image} ({system})");
        println!("  tarball  {}", tarball.display());
        println!("  size     {}", Size(size));
        println!("  layers   {layers}");
        println!("  ref      {}:{}", spec.repository, manifest.version);
    }
    Ok(ExitCode::SUCCESS)
}

pub fn workload(cmd: WorkloadCmd) -> Result<ExitCode, DeployError> {
    let WorkloadCmd::Render { name, lock, write } = cmd;
    let manifest = manifest_at(&lock)?;
    let names = select("workload", name.as_deref(), workloads(&manifest))?;
    if write {
        let root = lock.parent().unwrap_or(Path::new("."));
        for w in names {
            let path = root.join(&manifest.project.workloads[w].output);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).map_err(|source| DeployError::Write {
                    path: parent.display().to_string(),
                    source,
                })?;
            }
            std::fs::write(&path, render_text(&manifest, w)?).map_err(|source| {
                DeployError::Write {
                    path: path.display().to_string(),
                    source,
                }
            })?;
            eprintln!("blue: wrote {}", path.display());
        }
        return Ok(ExitCode::SUCCESS);
    }
    let [one] = names.as_slice() else {
        return Err(DeployError::PickOne {
            known: names.into_iter().map(String::from).collect(),
        });
    };
    print!("{}", render_text(&manifest, one)?);
    Ok(ExitCode::SUCCESS)
}

/// The one cluster call `blue diff` makes. `get`, by construction: this is
/// the only place an argument list for kubectl is built.
fn kubectl_get<'a>(context: &'a str, resource: &'a str, name: &'a str, namespace: &'a str) -> [&'a str; 11] {
    [
        "--context",
        context,
        "get",
        resource,
        name,
        "--namespace",
        namespace,
        "--output",
        "json",
        "--ignore-not-found",
        "--show-managed-fields=false",
    ]
}

/// The resource `kubectl get` names a rendered kind by.
fn resource_of(kind: &str) -> Option<&'static str> {
    match kind {
        "Deployment" => Some("deployment.apps"),
        "Service" => Some("service"),
        _ => None,
    }
}

/// What one rendered object looks like against the cluster.
enum Verdict {
    Same,
    Absent,
    Differs(Vec<Change>),
}

/// `blue diff`: exit 0 when the cluster holds what the committed files
/// state, 1 when it does not, 2 when the comparison could not be made.
pub fn diff(args: DiffArgs) -> ExitCode {
    match run_diff(args) {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::from(1),
        Err(e) => {
            eprintln!("blue: {e}");
            ExitCode::from(2)
        }
    }
}

fn run_diff(args: DiffArgs) -> Result<bool, DeployError> {
    let context = match args.context.as_deref() {
        Some(c) if !c.trim().is_empty() => c,
        _ => return Err(DeployError::NoContext),
    };
    let manifest = manifest_at(&args.lock)?;
    let root = args.lock.parent().unwrap_or(Path::new("."));
    let mut same = true;
    for w in select("workload", args.name.as_deref(), workloads(&manifest))? {
        let path = root.join(&manifest.project.workloads[w].output);
        let committed = read(&path)?;
        if committed != render_text(&manifest, w)? {
            eprintln!(
                "blue: {} is stale against Bluefile.lock; comparing the committed file (`blue workload render --write` regenerates it)",
                path.display()
            );
        }
        let list: serde_json::Value = json(&path, &committed)?;
        let items = list
            .get("items")
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default();
        for item in &items {
            let text = |k: &[&str]| {
                k.iter()
                    .try_fold(item, |v, key| v.get(*key))
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or_default()
                    .to_string()
            };
            let kind = text(&["kind"]);
            let Some(resource) = resource_of(&kind) else {
                return Err(DeployError::Kind {
                    path: path.display().to_string(),
                    kind,
                });
            };
            let name = text(&["metadata", "name"]);
            let namespace = text(&["metadata", "namespace"]);
            let target = [resource, " ", &namespace, "/", &name].concat();
            let out = Command::new(&args.kubectl)
                .args(kubectl_get(context, resource, &name, &namespace))
                .stdin(Stdio::null())
                .output()
                .map_err(|source| DeployError::Spawn {
                    program: args.kubectl.display().to_string(),
                    source,
                })?;
            if !out.status.success() {
                return Err(DeployError::Kubectl {
                    target,
                    status: out.status,
                    stderr: String::from_utf8_lossy(&out.stderr).trim().to_string(),
                });
            }
            let verdict = verdict(item, &out.stdout).map_err(|source| DeployError::Json {
                path: target.clone(),
                source,
            })?;
            match verdict {
                Verdict::Same => println!("= {target}"),
                Verdict::Absent => {
                    same = false;
                    println!("+ {target}: not in the cluster; applying the commit creates it");
                }
                Verdict::Differs(changes) => {
                    same = false;
                    println!("~ {target}");
                    for c in changes {
                        println!("    {c}");
                    }
                }
            }
        }
    }
    Ok(same)
}

/// Compare one rendered object with what `kubectl get --ignore-not-found`
/// printed: nothing when the object is absent.
fn verdict(rendered: &serde_json::Value, live: &[u8]) -> Result<Verdict, serde_json::Error> {
    if live.iter().all(u8::is_ascii_whitespace) {
        return Ok(Verdict::Absent);
    }
    let live: serde_json::Value = serde_json::from_slice(live)?;
    let changes = compare(rendered, &live);
    Ok(if changes.is_empty() {
        Verdict::Same
    } else {
        Verdict::Differs(changes)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// **The read-only guarantee, pinned.** The one argument list blue builds
    /// for kubectl is a `get` under the named context, and no mutating verb
    /// appears in it.
    #[test]
    fn the_cluster_call_is_a_get_under_the_named_context() {
        let args = kubectl_get("dev", "deployment.apps", "hello", "blue");
        assert_eq!(&args[..3], &["--context", "dev", "get"]);
        for verb in [
            "apply", "create", "replace", "patch", "delete", "edit", "scale", "annotate", "label",
            "rollout", "set",
        ] {
            assert!(!args.contains(&verb), "{verb}");
        }
    }

    #[test]
    fn every_rendered_kind_has_a_resource() {
        assert_eq!(resource_of("Deployment"), Some("deployment.apps"));
        assert_eq!(resource_of("Service"), Some("service"));
        assert_eq!(resource_of("Secret"), None);
    }

    /// Against a fixture of what a cluster returns: absent, the same with the
    /// server's defaults added, and changed.
    #[test]
    fn a_verdict_reads_absent_same_and_changed() {
        let rendered = json!({"kind": "Deployment", "spec": {"replicas": 2}});
        assert!(matches!(verdict(&rendered, b""), Ok(Verdict::Absent)));
        assert!(matches!(verdict(&rendered, b"\n"), Ok(Verdict::Absent)));
        let live = br#"{"kind": "Deployment", "spec": {"replicas": 2, "strategy": {}}, "status": {"readyReplicas": 2}}"#;
        assert!(matches!(verdict(&rendered, live), Ok(Verdict::Same)));
        let live = br#"{"kind": "Deployment", "spec": {"replicas": 1}}"#;
        match verdict(&rendered, live) {
            Ok(Verdict::Differs(changes)) => {
                assert_eq!(changes.len(), 1);
                assert_eq!(changes[0].to_string(), "~ spec.replicas: 1 -> 2");
            }
            _ => panic!("expected a difference"),
        }
    }

    #[test]
    fn select_names_one_or_all_and_refuses_the_unknown() {
        assert_eq!(select("w", None, vec!["a", "b"]).unwrap(), vec!["a", "b"]);
        assert_eq!(select("w", Some("b"), vec!["a", "b"]).unwrap(), vec!["b"]);
        assert!(matches!(
            select("w", Some("c"), vec!["a"]),
            Err(DeployError::Unknown { .. })
        ));
        assert!(matches!(select("w", None, vec![]), Err(DeployError::None { .. })));
    }

    #[test]
    fn a_size_reads_in_mebibytes_and_bytes() {
        assert_eq!(Size(3 * 1024 * 1024 + 512 * 1024).to_string(), "3.5 MiB (3670016 bytes)");
    }
}
