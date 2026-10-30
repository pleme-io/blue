//! The capability lattice `blue lock` verifies. Each package's floor is the
//! set of host capabilities its code names (test blocks aside), or its
//! declared `reach`, which must cover them. The floors join over the
//! dependency closure, and the join must fit under the root's `ceiling`
//! widened by its `virtualize` providers: `⋁ floors ⊑ ceiling ∨ provided`.
//! A provider scoped `for:` some packages widens only the floors of those
//! packages and the packages they use. A breach names the path from the root
//! to the package that needs the capability.

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::path::Path;

use blue_lang_bidama::{resolve, Bidama, Conflict};
use blue_lang_waku::{Capability, Provided, Provision, Provisions, Reach, Waku, When, Where};
use serde::{Deserialize, Serialize};

use crate::load_path::{Found, LoadPath};
use crate::Bluefile;

/// The labels a Bluefile names host capabilities by, in `Capability::ALL`
/// order.
pub const HOST_LABELS: &[&str] = &[
    "process",
    "filesystem",
    "environment",
    "clock",
    "network",
    "entropy",
];

/// The host capability a Bluefile label names.
#[must_use]
pub fn host_capability(label: &str) -> Option<Capability> {
    Capability::host_effects()
        .into_iter()
        .find(|c| c.label() == label.trim_start_matches(':'))
}

/// The provider `settings` asks for `cap`, and the packages it serves:
/// `{using: :deterministic_stepped, at_ms:, step_ms:}` (both default 0) for
/// the clock, `{using: :seeded_prng, seed:}` for entropy, and
/// `{using: :in_memory_overlay}` or `{using: :null_sink}` for the
/// filesystem. `for: %w[pkg …]` serves only those packages and every package
/// they use; without it the provider serves the whole program.
///
/// # Errors
///
/// A capability with no pure provider, a `using` that names none of its
/// providers (the error lists them), a field the provider does not take, a
/// field of the wrong kind, or an empty `for`.
pub fn provision_of(
    cap: Capability,
    settings: &tatara_lisp_eval::Value,
) -> Result<Provided, String> {
    use tatara_lisp_eval::value::MapKey;
    use tatara_lisp_eval::Value;
    let kinds = Provision::kinds_for(cap);
    if kinds.is_empty() {
        return Err(format!(
            "{} has no pure provider; virtualize clock, entropy or filesystem",
            cap.label()
        ));
    }
    let legal = || {
        kinds
            .iter()
            .map(|k| format!(":{k}"))
            .collect::<Vec<_>>()
            .join(", ")
    };
    let Value::Map(map) = settings else {
        return Err(format!(
            "settings must be a map, got {}",
            settings.type_name()
        ));
    };
    let mut fields = BTreeMap::new();
    for (k, v) in map.iter() {
        let key = match k {
            MapKey::Keyword(s) | MapKey::Str(s) | MapKey::Symbol(s) => {
                s.trim_start_matches(':').to_string()
            }
            _ => return Err("a setting is named by a keyword".into()),
        };
        fields.insert(key, v.clone());
    }
    let using = match fields.remove("using") {
        Some(Value::Keyword(u) | Value::Str(u)) => u.trim_start_matches(':').to_string(),
        Some(other) => {
            return Err(format!(
                "`using` names a provider, got {}; {} takes {}",
                other.type_name(),
                cap.label(),
                legal()
            ))
        }
        None => {
            return Err(format!(
                "{} needs `using:`, one of {}",
                cap.label(),
                legal()
            ))
        }
    };
    let unknown = || {
        format!(
            "`using: :{using}` is not a {} provider; it takes {}",
            cap.label(),
            legal()
        )
    };
    if !kinds.contains(&using.as_str()) {
        return Err(unknown());
    }
    let scope = match fields.remove("for") {
        None => None,
        Some(Value::List(items)) if !items.is_empty() => Some(
            items
                .iter()
                .map(|v| match v {
                    Value::Str(s) => Ok(s.to_string()),
                    other => Err(format!(
                        "`for` names packages as strings (%w[rede]), got {}",
                        other.type_name()
                    )),
                })
                .collect::<Result<BTreeSet<String>, String>>()?,
        ),
        Some(Value::List(_)) => {
            return Err("`for` names no package; drop it to serve the whole program".into())
        }
        Some(other) => {
            return Err(format!(
                "`for` is a list of package names (%w[rede]), got {}",
                other.type_name()
            ))
        }
    };
    let takes: &[&str] = match using.as_str() {
        "deterministic_stepped" => &["at_ms", "step_ms"],
        "seeded_prng" => &["seed"],
        _ => &[],
    };
    if let Some(extra) = fields.keys().find(|k| !takes.contains(&k.as_str())) {
        let besides = if takes.is_empty() {
            "nothing besides `using` and `for`".to_string()
        } else {
            takes.join(", ")
        };
        return Err(format!(
            "`{extra}` is not a {using} setting; it takes {besides}"
        ));
    }
    let int = |f: &str| match fields.get(f) {
        None => Ok(0),
        Some(Value::Int(n)) => Ok(*n),
        Some(other) => Err(format!(
            "`{f}` must be an integer, got {}",
            other.type_name()
        )),
    };
    let provision = match using.as_str() {
        "deterministic_stepped" => Provision::DeterministicStepped {
            at_ms: int("at_ms")?,
            step_ms: int("step_ms")?,
        },
        "seeded_prng" => match fields.get("seed") {
            Some(Value::Str(s)) => Provision::SeededPrng {
                seed: s.to_string(),
            },
            Some(other) => {
                return Err(format!(
                    "`seed` must be a string, got {}",
                    other.type_name()
                ))
            }
            None => return Err("seeded_prng needs a `seed`".into()),
        },
        "in_memory_overlay" => Provision::InMemoryOverlay,
        "null_sink" => Provision::NullSink,
        _ => return Err(unknown()),
    };
    Ok(Provided { provision, scope })
}

fn capability_of_name(name: &str) -> Option<Capability> {
    Capability::host_effects()
        .into_iter()
        .find(|c| c.grants(name))
}

fn labels(caps: &BTreeSet<Capability>) -> Vec<String> {
    caps.iter().map(|c| c.label().to_string()).collect()
}

/// The host capabilities the blue code under `dir` names, test blocks
/// aside. A subdirectory with its own Bluefile is another package and is
/// not read.
///
/// # Errors
///
/// A file that cannot be read or parsed, named with its path.
pub fn reached(dir: &Path) -> Result<BTreeSet<Capability>, String> {
    let mut out = BTreeSet::new();
    let mut pending = vec![dir.to_path_buf()];
    while let Some(at) = pending.pop() {
        let entries = std::fs::read_dir(&at).map_err(|e| format!("{}: {e}", at.display()))?;
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if path.is_dir() {
                let skipped = name.starts_with('.') || name == "target" || name == "result";
                if !skipped && !path.join(crate::MANIFEST_FILE).is_file() {
                    pending.push(path);
                }
            } else if path.extension().is_some_and(|e| e == "b") {
                let text = std::fs::read_to_string(&path)
                    .map_err(|e| format!("{}: {e}", path.display()))?;
                let forms = blue_lang_syntax::parse_program_tree(&text)
                    .map_err(|e| format!("{}: {e}", path.display()))?;
                let code: Vec<_> = forms
                    .into_iter()
                    .filter(|f| {
                        f.as_list()
                            .and_then(|l| l.first())
                            .and_then(|h| h.as_symbol())
                            != Some("deftest")
                    })
                    .collect();
                let names = blue_lang_waku::free_names(&code, &|n| capability_of_name(n).is_none());
                out.extend(names.iter().filter_map(|n| capability_of_name(n)));
            }
        }
    }
    Ok(out)
}

/// One package in the closure.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Node {
    pub floor: BTreeSet<Capability>,
    pub needs: Vec<String>,
}

/// The root and every package it reaches through `use`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Graph {
    pub root: String,
    pub nodes: BTreeMap<String, Node>,
}

/// Why the lattice could not be verified.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CapabilityError {
    #[error("{0}")]
    Read(String),
    /// A declared `reach` that misses a capability the package's code names.
    #[error("`{package}` declares reach [{}] but its code reaches {}; add it to `reach(...)`", .declared.join(", "), .missing.join(", "))]
    Undeclared {
        package: String,
        declared: Vec<String>,
        missing: Vec<String>,
    },
    /// The join of the floors does not fit under the ceiling.
    #[error("{}", .0.iter().map(ToString::to_string).collect::<Vec<_>>().join("\n"))]
    Breach(Vec<Breach>),
    /// A provider's `for:` names a package the root does not reach.
    #[error("`virtualize(:{capability}, …)` is for `{package}`, which [{root}] does not use; name a package it uses")]
    Scope {
        capability: String,
        package: String,
        root: String,
    },
}

/// One capability one package needs that the ceiling withholds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Breach {
    /// The packages from the root to the one that needs it.
    pub path: Vec<String>,
    pub needs: Capability,
    /// The ceiling with its whole-program providers, as labels.
    pub ceiling: Vec<String>,
    /// The packages a scoped provider of `needs` is for; empty when it has
    /// none.
    pub provided_for: Vec<String>,
}

impl std::fmt::Display for Breach {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let last = self.path.len().saturating_sub(1);
        let hops: Vec<String> = self
            .path
            .iter()
            .enumerate()
            .map(|(i, p)| {
                if i == last {
                    format!("[{p}: needs '{}']", self.needs.label())
                } else {
                    format!("[{p}]")
                }
            })
            .collect();
        write!(
            f,
            "{} violates ceiling [{}]",
            hops.join(" -> "),
            self.ceiling.join(", ")
        )?;
        if !self.provided_for.is_empty() {
            write!(
                f,
                " ({} is virtualized only for [{}] and what they use)",
                self.needs.label(),
                self.provided_for.join(", ")
            )?;
        }
        Ok(())
    }
}

fn floor_of(
    name: &str,
    dir: &Path,
    bf: Option<&Bluefile>,
) -> Result<BTreeSet<Capability>, CapabilityError> {
    let code = reached(dir).map_err(CapabilityError::Read)?;
    let Some(declared) = bf.and_then(|b| b.project.reach.as_ref()) else {
        return Ok(code);
    };
    let declared: BTreeSet<Capability> =
        declared.iter().filter_map(|l| host_capability(l)).collect();
    let missing: BTreeSet<Capability> = code.difference(&declared).copied().collect();
    if missing.is_empty() {
        Ok(declared)
    } else {
        Err(CapabilityError::Undeclared {
            package: name.to_string(),
            declared: labels(&declared),
            missing: labels(&missing),
        })
    }
}

/// The closure of the project at `dir`: its own code, then every package its
/// code uses, breadth first, each read once.
///
/// # Errors
///
/// A package that cannot be read, or one whose declared `reach` misses a
/// capability its code names.
pub fn graph(dir: &Path, root: &Bluefile, loader: &LoadPath) -> Result<Graph, CapabilityError> {
    let mut nodes = BTreeMap::new();
    let mut queue = VecDeque::new();
    let root_needs: Vec<String> = crate::needs::used_by(dir)
        .into_iter()
        .filter(|n| *n != root.name)
        .collect();
    queue.extend(root_needs.iter().cloned());
    nodes.insert(
        root.name.clone(),
        Node {
            floor: floor_of(&root.name, dir, Some(root))?,
            needs: root_needs,
        },
    );
    while let Some(name) = queue.pop_front() {
        if nodes.contains_key(&name) {
            continue;
        }
        let Some(Found::Dir(pkg)) = loader.select(&name).found else {
            nodes.insert(
                name,
                Node {
                    floor: BTreeSet::new(),
                    needs: Vec::new(),
                },
            );
            continue;
        };
        let bf = std::fs::read_to_string(pkg.join(crate::MANIFEST_FILE))
            .ok()
            .and_then(|t| crate::read_bluefile(&t).ok());
        let needs: Vec<String> = crate::needs::used_by(&pkg)
            .into_iter()
            .filter(|n| *n != name)
            .collect();
        queue.extend(needs.iter().cloned());
        let floor = floor_of(&name, &pkg, bf.as_ref())?;
        nodes.insert(name, Node { floor, needs });
    }
    Ok(Graph {
        root: root.name.clone(),
        nodes,
    })
}

impl Graph {
    /// The packages from the root to `name`, by the first route a breadth
    /// first walk finds.
    #[must_use]
    pub fn path_to(&self, name: &str) -> Vec<String> {
        let mut parent: BTreeMap<&str, &str> = BTreeMap::new();
        let mut queue = VecDeque::from([self.root.as_str()]);
        let mut seen = BTreeSet::from([self.root.as_str()]);
        while let Some(at) = queue.pop_front() {
            if at == name {
                break;
            }
            for next in self
                .nodes
                .get(at)
                .map(|n| n.needs.as_slice())
                .unwrap_or_default()
            {
                if seen.insert(next.as_str()) {
                    parent.insert(next.as_str(), at);
                    queue.push_back(next.as_str());
                }
            }
        }
        let mut path = vec![name.to_string()];
        let mut at = name;
        while let Some(p) = parent.get(at) {
            path.push((*p).to_string());
            at = p;
        }
        path.reverse();
        path
    }

    /// `named` and every package they reach through `use`.
    #[must_use]
    pub fn reached_from(&self, named: &BTreeSet<String>) -> BTreeSet<String> {
        let mut out = named.clone();
        let mut queue: Vec<&str> = named.iter().map(String::as_str).collect();
        while let Some(at) = queue.pop() {
            for next in self
                .nodes
                .get(at)
                .map(|n| n.needs.as_slice())
                .unwrap_or_default()
            {
                if out.insert(next.clone()) {
                    queue.push(next.as_str());
                }
            }
        }
        out
    }
}

/// The capabilities record `Bluefile.lock` carries when the root declares a
/// ceiling or a provider.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CapabilityRecord {
    /// The root's ceiling; absent when it declares none (every capability).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ceiling: Option<Vec<String>>,
    /// Each virtualized capability's provider, with the packages it is for.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub provided: BTreeMap<String, Provided>,
    /// The join of every floor in the closure.
    pub floor: Vec<String>,
    /// Each package's floor.
    pub packages: BTreeMap<String, Vec<String>>,
}

/// The root's ceiling as a reach: `Unrestricted` when it declares none.
#[must_use]
pub fn ceiling_of(bf: &Bluefile) -> Reach {
    bf.project.allow.as_ref().map_or(Reach::Unrestricted, |c| {
        Reach::only(c.iter().filter_map(|l| host_capability(l)).chain(pure()))
    })
}

fn pure() -> impl Iterator<Item = Capability> {
    Capability::ALL.into_iter().filter(|c| !c.is_host_effect())
}

/// The root's providers.
#[must_use]
pub fn provisions_of(bf: &Bluefile) -> Provisions {
    let mut ps = Provisions::default();
    for p in bf.project.virtualized.values() {
        let _ = ps.add(p.clone());
    }
    ps
}

/// Verify `⋁ floors ⊑ ceiling ∨ provided` over `graph`. A scoped provider
/// counts only for the packages it is for and the packages they use: it is
/// taken out of their floors before the join, and a package outside it that
/// needs its capability breaches.
///
/// # Errors
///
/// [`CapabilityError::Scope`] for a `for:` package the root does not reach;
/// [`CapabilityError::Breach`], one row per package and capability past the
/// ceiling, each with its path from the root.
pub fn verify(
    graph: &Graph,
    ceiling: &Reach,
    provisions: &Provisions,
) -> Result<CapabilityRecord, CapabilityError> {
    let widened = provisions.widen(ceiling);
    let bound = Waku {
        reach: widened.clone(),
        when: When::Anytime,
        place: Where::Shared,
    };
    let mut served: BTreeMap<String, BTreeSet<Capability>> = BTreeMap::new();
    let mut scoped_for: BTreeMap<Capability, Vec<String>> = BTreeMap::new();
    for (cap, named) in provisions.scoped() {
        if let Some(stray) = named.iter().find(|n| !graph.nodes.contains_key(*n)) {
            return Err(CapabilityError::Scope {
                capability: cap.label().to_string(),
                package: stray.clone(),
                root: graph.root.clone(),
            });
        }
        for p in graph.reached_from(named) {
            served.entry(p).or_default().insert(cap);
        }
        scoped_for.insert(cap, named.iter().cloned().collect());
    }
    let unserved = |name: &str, node: &Node| -> BTreeSet<Capability> {
        match served.get(name) {
            Some(s) => node.floor.difference(s).copied().collect(),
            None => node.floor.clone(),
        }
    };
    let bidamas: Vec<Bidama> = graph
        .nodes
        .iter()
        .map(|(name, node)| {
            Bidama::new(
                name.clone(),
                Waku {
                    reach: Reach::only(unserved(name, node)),
                    when: When::Sealed,
                    place: Where::Arena,
                },
            )
        })
        .collect();
    let shown_ceiling = |r: &Reach| match r {
        Reach::Unrestricted => vec!["every capability".to_string()],
        Reach::Only(caps) => caps
            .iter()
            .filter(|c| c.is_host_effect())
            .map(|c| c.label().to_string())
            .collect(),
    };
    match resolve(&bidamas, &bound) {
        Ok(_) => {
            let joined: BTreeSet<Capability> = graph
                .nodes
                .values()
                .flat_map(|n| n.floor.iter().copied())
                .collect();
            Ok(CapabilityRecord {
                ceiling: match ceiling {
                    Reach::Unrestricted => None,
                    Reach::Only(_) => Some(shown_ceiling(ceiling)),
                },
                provided: provisions
                    .iter()
                    .map(|p| (p.provision.capability().label().to_string(), p.clone()))
                    .collect(),
                floor: labels(&joined),
                packages: graph
                    .nodes
                    .iter()
                    .map(|(n, node)| (n.clone(), labels(&node.floor)))
                    .collect(),
            })
        }
        Err(conflict) => {
            let culprits = match &conflict {
                Conflict::Capability { culprits } => culprits.clone(),
                other => other.culprits().to_vec(),
            };
            let mut breaches = Vec::new();
            for name in culprits {
                let Some(node) = graph.nodes.get(&name) else {
                    continue;
                };
                for cap in unserved(&name, node)
                    .into_iter()
                    .filter(|c| !widened.grants(*c))
                {
                    breaches.push(Breach {
                        path: graph.path_to(&name),
                        needs: cap,
                        ceiling: shown_ceiling(&widened),
                        provided_for: scoped_for.get(&cap).cloned().unwrap_or_default(),
                    });
                }
            }
            Err(CapabilityError::Breach(breaches))
        }
    }
}

/// Does `record` state the lattice `bf` declares, offline: present exactly
/// when `bf` declares `allow` or a provider, the same ceiling and providers,
/// every package floor inside the join and the join under the ceiling and
/// providers.
#[must_use]
pub fn consistent(bf: &Bluefile, record: Option<&CapabilityRecord>) -> bool {
    let Some(r) = record else {
        return !declared(bf);
    };
    let provided: BTreeMap<String, Provided> = bf
        .project
        .virtualized
        .iter()
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    let floor: BTreeSet<&String> = r.floor.iter().collect();
    let fits = match &r.ceiling {
        None => true,
        Some(c) => r
            .floor
            .iter()
            .all(|f| c.contains(f) || r.provided.contains_key(f)),
    };
    declared(bf)
        && r.ceiling == bf.project.allow
        && r.provided == provided
        && fits
        && r.packages.values().flatten().all(|f| floor.contains(f))
}

/// Does the root at `bf` ask for the lattice to be verified?
#[must_use]
pub fn declared(bf: &Bluefile) -> bool {
    bf.project.allow.is_some() || !bf.project.virtualized.is_empty()
}

/// What `blue run` holds the program at `entry` to when its project declares
/// `allow` or a provider: the ceiling as its frame, and the providers.
/// `None` when the project declares neither, or there is no project.
#[must_use]
pub fn hold_for(entry: &Path) -> Option<blue_lang_runtime::Hold> {
    let dir = entry
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let dir = dir.canonicalize().unwrap_or_else(|_| dir.to_path_buf());
    let project = crate::load_path::project_of(&dir)?;
    let text = std::fs::read_to_string(project.join(crate::MANIFEST_FILE)).ok()?;
    let bf = crate::read_bluefile(&text).ok()?;
    declared(&bf).then(|| blue_lang_runtime::Hold {
        frame: Waku {
            reach: ceiling_of(&bf),
            when: When::Anytime,
            place: Where::Process,
        },
        provisions: provisions_of(&bf),
    })
}

/// Verify the project at `dir` when its Bluefile declares a ceiling or a
/// provider; `None` when it declares neither.
///
/// # Errors
///
/// As [`graph`] and [`verify`].
pub fn check_dir(dir: &Path, bf: &Bluefile) -> Result<Option<CapabilityRecord>, CapabilityError> {
    if !declared(bf) {
        return Ok(None);
    }
    let loader = LoadPath::for_dir(dir).unpinned();
    let g = graph(dir, bf, &loader)?;
    verify(&g, &ceiling_of(bf), &provisions_of(bf)).map(Some)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn node(floor: &[Capability], needs: &[&str]) -> Node {
        Node {
            floor: floor.iter().copied().collect(),
            needs: needs.iter().map(ToString::to_string).collect(),
        }
    }

    fn sample() -> Graph {
        Graph {
            root: "app".into(),
            nodes: BTreeMap::from([
                ("app".into(), node(&[Capability::FileSystem], &["dep-a"])),
                ("dep-a".into(), node(&[], &["dep-b"])),
                ("dep-b".into(), node(&[Capability::Network], &[])),
            ]),
        }
    }

    fn reach(caps: &[Capability]) -> Reach {
        Reach::only(caps.iter().copied().chain(pure()))
    }

    #[test]
    fn host_labels_are_the_host_effects_in_order() {
        let from_type: Vec<&str> = Capability::host_effects()
            .iter()
            .map(|c| c.label())
            .collect();
        assert_eq!(HOST_LABELS, from_type.as_slice());
        assert_eq!(host_capability(":clock"), Some(Capability::Clock));
        assert_eq!(
            host_capability("operators"),
            None,
            "a pure bundle is no host capability"
        );
        assert_eq!(host_capability("disk"), None);
    }

    #[test]
    fn a_breach_names_the_path_from_the_root_to_the_package_that_needs_it() {
        let err = verify(
            &sample(),
            &reach(&[Capability::FileSystem, Capability::Clock]),
            &Provisions::default(),
        )
        .expect_err("dep-b needs the network");
        assert_eq!(
            err.to_string(),
            "[app] -> [dep-a] -> [dep-b: needs 'network'] violates ceiling [filesystem, clock]"
        );
    }

    #[test]
    fn the_join_fits_under_a_ceiling_that_covers_every_floor() {
        let record = verify(
            &sample(),
            &reach(&[Capability::FileSystem, Capability::Network]),
            &Provisions::default(),
        )
        .expect("fits");
        assert_eq!(record.floor, ["filesystem", "network"]);
        assert_eq!(record.packages["dep-a"], Vec::<String>::new());
        assert_eq!(
            record.ceiling,
            Some(vec!["filesystem".into(), "network".into()])
        );
    }

    #[test]
    fn no_ceiling_admits_every_floor() {
        let record = verify(&sample(), &Reach::Unrestricted, &Provisions::default()).expect("fits");
        assert_eq!(record.ceiling, None);
    }

    #[test]
    fn a_provider_satisfies_a_floor_the_ceiling_withholds() {
        let mut g = sample();
        g.nodes.get_mut("dep-b").unwrap().floor = BTreeSet::from([Capability::Clock]);
        let ceiling = reach(&[Capability::FileSystem]);
        assert!(verify(&g, &ceiling, &Provisions::default()).is_err());
        let mut ps = Provisions::default();
        ps.add(Provision::DeterministicStepped {
            at_ms: 0,
            step_ms: 1,
        })
        .unwrap();
        let record = verify(&g, &ceiling, &ps).expect("the virtual clock covers dep-b");
        assert!(record.provided.contains_key("clock"));
    }

    fn clock_for(packages: &[&str]) -> Provisions {
        let mut ps = Provisions::default();
        ps.add(Provided {
            provision: Provision::DeterministicStepped {
                at_ms: 0,
                step_ms: 1,
            },
            scope: Some(packages.iter().map(ToString::to_string).collect()),
        })
        .unwrap();
        ps
    }

    #[test]
    fn a_scoped_provider_widens_only_the_packages_it_is_for_and_what_they_use() {
        let mut g = sample();
        g.nodes.get_mut("app").unwrap().floor = BTreeSet::new();
        g.nodes.get_mut("dep-b").unwrap().floor = BTreeSet::from([Capability::Clock]);
        let ceiling = reach(&[]);
        for scope in [&["dep-b"][..], &["dep-a"], &["app"]] {
            let record = verify(&g, &ceiling, &clock_for(scope))
                .unwrap_or_else(|e| panic!("for {scope:?}: {e}"));
            assert_eq!(record.packages["dep-b"], ["clock"]);
            assert_eq!(record.floor, ["clock"], "the join is what the code names");
            assert_eq!(
                record.provided["clock"].scope,
                Some(scope.iter().map(ToString::to_string).collect())
            );
        }

        g.nodes.get_mut("dep-a").unwrap().floor = BTreeSet::from([Capability::Clock]);
        let err = verify(&g, &ceiling, &clock_for(&["dep-b"]))
            .expect_err("dep-a is outside the scope and needs the clock");
        assert_eq!(
            err.to_string(),
            "[app] -> [dep-a: needs 'clock'] violates ceiling [] (clock is virtualized only for [dep-b] and what they use)"
        );
        verify(&g, &ceiling, &clock_for(&["dep-a"])).expect("dep-a uses dep-b");
    }

    #[test]
    fn a_scope_that_names_a_package_the_root_does_not_use_is_refused() {
        let err = verify(&sample(), &Reach::Unrestricted, &clock_for(&["nowhere"]))
            .expect_err("nowhere is not in the closure");
        assert_eq!(
            err.to_string(),
            "`virtualize(:clock, …)` is for `nowhere`, which [app] does not use; name a package it uses"
        );
    }

    fn virtualized(settings: &str) -> Result<BTreeMap<String, Provided>, String> {
        crate::read_bluefile(&format!(
            "package(\"app\", \"0.1.0\")\nvirtualize({settings})\n"
        ))
        .map(|bf| bf.project.virtualized)
        .map_err(|e| e.to_string())
    }

    #[test]
    fn each_provider_is_named_by_using_with_its_settings_beside_it() {
        let cases = [
            (
                ":clock, {using: :deterministic_stepped, at_ms: 5, step_ms: 2}",
                Provision::DeterministicStepped {
                    at_ms: 5,
                    step_ms: 2,
                },
            ),
            (
                ":clock, {using: :deterministic_stepped}",
                Provision::DeterministicStepped {
                    at_ms: 0,
                    step_ms: 0,
                },
            ),
            (
                ":entropy, {using: :seeded_prng, seed: \"s\"}",
                Provision::SeededPrng { seed: "s".into() },
            ),
            (
                ":filesystem, {using: :in_memory_overlay}",
                Provision::InMemoryOverlay,
            ),
            (":filesystem, {using: :null_sink}", Provision::NullSink),
        ];
        for (settings, want) in cases {
            let got = virtualized(settings).unwrap_or_else(|e| panic!("{settings}: {e}"));
            let p = &got[want.capability().label()];
            assert_eq!(p.provision, want, "{settings}");
            assert_eq!(p.scope, None, "{settings}");
        }
        for cap in Capability::host_effects() {
            for kind in Provision::kinds_for(cap) {
                let settings = match *kind {
                    "seeded_prng" => format!(":{}, {{using: :{kind}, seed: \"s\"}}", cap.label()),
                    _ => format!(":{}, {{using: :{kind}}}", cap.label()),
                };
                let got = virtualized(&settings).unwrap_or_else(|e| panic!("{settings}: {e}"));
                assert_eq!(got[cap.label()].provision.name(), *kind);
            }
        }
        let scoped =
            virtualized(":clock, {using: :deterministic_stepped, for: %w[rede porta]}").unwrap();
        assert_eq!(
            scoped["clock"].scope,
            Some(BTreeSet::from(["porta".to_string(), "rede".to_string()]))
        );
    }

    #[test]
    fn an_unknown_or_missing_using_is_refused_naming_the_legal_ones() {
        for (settings, says) in [
            (
                ":clock, {using: :wall}",
                "`using: :wall` is not a clock provider; it takes :deterministic_stepped",
            ),
            (
                ":clock, {using: :seeded_prng, seed: \"s\"}",
                "`using: :seeded_prng` is not a clock provider; it takes :deterministic_stepped",
            ),
            (
                ":filesystem, {using: :memory}",
                "`using: :memory` is not a filesystem provider; it takes :in_memory_overlay, :null_sink",
            ),
            (
                ":filesystem, {mode: :memory}",
                "filesystem needs `using:`, one of :in_memory_overlay, :null_sink",
            ),
            (
                ":filesystem, {using: :null_sink, mode: :null}",
                "`mode` is not a null_sink setting; it takes nothing besides `using` and `for`",
            ),
            (
                ":clock, {using: :deterministic_stepped, seed: \"s\"}",
                "`seed` is not a deterministic_stepped setting; it takes at_ms, step_ms",
            ),
            (
                ":entropy, {using: :seeded_prng}",
                "seeded_prng needs a `seed`",
            ),
            (
                ":clock, {using: :deterministic_stepped, for: []}",
                "`for` names no package; drop it to serve the whole program",
            ),
            (
                ":clock, {using: :deterministic_stepped, for: \"rede\"}",
                "`for` is a list of package names (%w[rede])",
            ),
            (":network, {using: :x}", "network has no pure provider"),
        ] {
            let err = virtualized(settings).expect_err(settings);
            assert!(err.contains(says), "{settings}: {err}");
        }
    }

    #[test]
    fn the_lock_records_a_provider_by_its_kebab_label_with_its_scope_beside_it() {
        let every = [
            Provision::DeterministicStepped {
                at_ms: 5,
                step_ms: 0,
            },
            Provision::SeededPrng { seed: "s".into() },
            Provision::InMemoryOverlay,
            Provision::NullSink,
        ];
        for p in every {
            let json = serde_json::to_value(Provided::from(p.clone())).unwrap();
            assert_eq!(json["provider"], p.label(), "{json}");
            assert!(json.get("for").is_none(), "{json}");
            assert_eq!(
                serde_json::from_value::<Provided>(json).unwrap(),
                Provided::from(p)
            );
        }
        let scoped = Provided {
            provision: Provision::DeterministicStepped {
                at_ms: 5,
                step_ms: 0,
            },
            scope: Some(BTreeSet::from(["rede".to_string()])),
        };
        let json = serde_json::to_value(&scoped).unwrap();
        assert_eq!(
            json,
            serde_json::json!({"provider": "deterministic-stepped", "at_ms": 5, "step_ms": 0, "for": ["rede"]})
        );
        assert_eq!(serde_json::from_value::<Provided>(json).unwrap(), scoped);
        for stale in [
            serde_json::json!({"provider": "seeded-prng", "seed": "s", "mode": "x"}),
            serde_json::json!({"provider": "stepped-clock", "at_ms": 0, "step_ms": 0}),
            serde_json::json!({"provider": "memory-fs"}),
        ] {
            assert!(
                serde_json::from_value::<Provided>(stale.clone()).is_err(),
                "{stale}"
            );
        }
    }

    #[test]
    fn every_capability_past_the_ceiling_is_its_own_row() {
        let mut g = sample();
        g.nodes.get_mut("app").unwrap().floor =
            BTreeSet::from([Capability::Process, Capability::FileSystem]);
        let err = verify(
            &g,
            &reach(&[Capability::FileSystem]),
            &Provisions::default(),
        )
        .unwrap_err();
        let CapabilityError::Breach(rows) = err else {
            panic!()
        };
        let shown: Vec<String> = rows.iter().map(ToString::to_string).collect();
        assert_eq!(
            shown,
            [
                "[app: needs 'process'] violates ceiling [filesystem]",
                "[app] -> [dep-a] -> [dep-b: needs 'network'] violates ceiling [filesystem]",
            ]
        );
    }

    #[test]
    fn a_package_floor_is_what_its_code_names_and_tests_do_not_count() {
        let dir = std::env::temp_dir().join(format!("blue-reach-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("inner")).unwrap();
        std::fs::create_dir_all(dir.join("other")).unwrap();
        std::fs::write(
            dir.join("a.b"),
            "def stamp()\n  now_ms\nend\n\ntest \"x\"\n  assert getenv(\"HOME\") != nil\nend\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("inner/b.b"),
            "def get(u)\n  http_request(u)\nend\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("other/Bluefile"),
            "package(\"other\", \"0.1.0\")\n",
        )
        .unwrap();
        std::fs::write(dir.join("other/c.b"), "def r(p)\n  read_file(p)\nend\n").unwrap();
        let caps = reached(&dir).unwrap();
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(
            caps,
            BTreeSet::from([Capability::Clock, Capability::Network])
        );
    }
}
