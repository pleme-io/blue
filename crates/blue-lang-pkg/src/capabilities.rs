//! The capability lattice `blue lock` verifies. Each package's floor is the
//! set of host capabilities its code names (test blocks aside). The floors
//! join over the dependency closure, and the join must fit under the root's
//! `ceiling` widened by its `virtualize` providers:
//! `⋁ floors ⊑ ceiling ∨ provided`. A provider scoped `for:` some packages
//! widens only the floors of those packages and the packages they use.
//!
//! What a floor counts is the root's [`FloorUnit`], `floors(...)` in its
//! Bluefile. By default ([`FloorUnit::Definition`]) a package's floor is what
//! the definitions the root's code reaches name, read by mondou's reach
//! ([`blue_lang_mondou::reach::form_reach`]) over the program each root file
//! loads, so a pure caller of one pure word in a package that also holds a
//! host word inherits nothing; a declared `reach` bounds what they may name.
//! A breach names the definitions from the root to the one that names the
//! capability. With [`FloorUnit::Package`] a floor is everything the
//! package's code names, or its declared `reach`, which must cover it, and a
//! breach names the packages from the root.

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::path::{Path, PathBuf};

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
    "comm-flash",
    "comm-scavenger",
    "mpc-threshold",
];

/// The host capability a Bluefile label names: the label, or the label in
/// snake case as a symbol writes it (`:comm_flash`).
#[must_use]
pub fn host_capability(label: &str) -> Option<Capability> {
    Capability::host_named(label)
}

/// What a floor counts: the root's `floors(...)`, recorded in the lock as
/// `unit`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FloorUnit {
    /// The host capabilities the definitions the root's code reaches name,
    /// through every package it uses. The default.
    #[default]
    Definition,
    /// Every host capability each package in the closure names, whole, or
    /// its declared `reach`.
    Package,
}

impl FloorUnit {
    /// The labels a Bluefile names a unit by, in declaration order.
    pub const LABELS: &'static [&'static str] = &["definition", "package"];

    /// The unit a Bluefile label names.
    #[must_use]
    pub fn of_label(label: &str) -> Option<Self> {
        match label.trim_start_matches(':') {
            "definition" => Some(Self::Definition),
            "package" => Some(Self::Package),
            _ => None,
        }
    }

    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Self::Definition => "definition",
            Self::Package => "package",
        }
    }

    /// What a record written before `unit` existed counted: whole packages.
    fn recorded_before_units() -> Self {
        Self::Package
    }
}

/// The unit the root at `bf` counts its floors by.
#[must_use]
pub fn unit_of(bf: &Bluefile) -> FloorUnit {
    bf.project.floors.unwrap_or_default()
}

/// The provider `settings` asks for `cap`, and the packages it serves:
/// `{using: :deterministic_stepped, at_ms:, step_ms:}` (both default 0) for
/// the clock, `{using: :seeded_prng, seed:}` for entropy,
/// `{using: :in_memory_overlay}` or `{using: :null_sink}` for the
/// filesystem, `{using: :loopback}` for `comm_flash` and `comm_scavenger`,
/// and `{using: :seeded, seed:}` for `mpc_threshold`. `for: %w[pkg …]` serves
/// only those packages and every
/// package they use; without it the provider serves the whole program.
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
            "{} has no pure provider; virtualize clock, entropy, filesystem, comm_flash, comm_scavenger or mpc_threshold",
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
        "seeded_prng" | "seeded" => &["seed"],
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
        "seeded_prng" | "seeded" => match fields.get("seed") {
            Some(Value::Str(s)) if using == "seeded" => Provision::Seeded {
                seed: s.to_string(),
            },
            Some(Value::Str(s)) => Provision::SeededPrng {
                seed: s.to_string(),
            },
            Some(other) => {
                return Err(format!(
                    "`seed` must be a string, got {}",
                    other.type_name()
                ))
            }
            None => return Err(format!("{using} needs a `seed`")),
        },
        "in_memory_overlay" => Provision::InMemoryOverlay,
        "null_sink" => Provision::NullSink,
        "loopback" => match blue_lang_waku::Channel::of(cap) {
            Some(channel) => Provision::Loopback { channel },
            None => return Err(unknown()),
        },
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

/// The blue files of the package at `dir`, sorted. A subdirectory with its
/// own Bluefile is another package and is not read.
///
/// # Errors
///
/// A directory that cannot be read, named with its path.
pub fn sources_of(dir: &Path) -> Result<Vec<PathBuf>, String> {
    let mut out = Vec::new();
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
                out.push(path);
            }
        }
    }
    out.sort();
    Ok(out)
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
    for path in sources_of(dir)? {
        let text =
            std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
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
    Ok(out)
}

/// One package in the closure.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Node {
    pub floor: BTreeSet<Capability>,
    pub needs: Vec<String>,
    /// Under [`FloorUnit::Definition`], each capability of the floor and the
    /// hops from the root to the definition that names it
    /// (`app`, `porta::fetch`, `rede::get`). Empty under
    /// [`FloorUnit::Package`], where a breach names the packages.
    pub paths: BTreeMap<Capability, Vec<String>>,
}

impl Node {
    /// A package with `floor`, using `needs`, with no definition paths.
    #[must_use]
    pub fn of(floor: BTreeSet<Capability>, needs: Vec<String>) -> Self {
        Self {
            floor,
            needs,
            paths: BTreeMap::new(),
        }
    }
}

/// The root and every package it reaches through `use`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Graph {
    pub root: String,
    pub nodes: BTreeMap<String, Node>,
    /// What each floor counts.
    pub unit: FloorUnit,
    /// Under [`FloorUnit::Definition`], every reached definition that names
    /// a host capability on its own, as `package::name` (a package alone for
    /// the code at its top level), with what it names: the evidence the
    /// floors are joined from. Empty under [`FloorUnit::Package`].
    pub definitions: BTreeMap<String, BTreeSet<Capability>>,
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
    /// The hops from the root to what needs it: the packages, or under
    /// [`FloorUnit::Definition`] the definitions (`porta::fetch`).
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

fn declared_reach(bf: Option<&Bluefile>) -> Option<BTreeSet<Capability>> {
    let declared = bf?.project.reach.as_ref()?;
    Some(declared.iter().filter_map(|l| host_capability(l)).collect())
}

fn within_declared(
    name: &str,
    code: &BTreeSet<Capability>,
    declared: &BTreeSet<Capability>,
) -> Result<(), CapabilityError> {
    let missing: BTreeSet<Capability> = code.difference(declared).copied().collect();
    if missing.is_empty() {
        Ok(())
    } else {
        Err(CapabilityError::Undeclared {
            package: name.to_string(),
            declared: labels(declared),
            missing: labels(&missing),
        })
    }
}

fn floor_of(
    name: &str,
    dir: &Path,
    bf: Option<&Bluefile>,
) -> Result<BTreeSet<Capability>, CapabilityError> {
    let code = reached(dir).map_err(CapabilityError::Read)?;
    let Some(declared) = declared_reach(bf) else {
        return Ok(code);
    };
    within_declared(name, &code, &declared)?;
    Ok(declared)
}

/// One package of the closure as the walk found it.
struct Member {
    name: String,
    needs: Vec<String>,
    dir: Option<PathBuf>,
    bluefile: Option<Bluefile>,
}

/// The root, then every package its code uses, breadth first, each read
/// once. A compiled-in package is a leaf under [`FloorUnit::Package`], as it
/// always was; under [`FloorUnit::Definition`] its own `use`s are followed,
/// since its definitions are read like any other.
fn closure(dir: &Path, root: &Bluefile, loader: &LoadPath, unit: FloorUnit) -> Vec<Member> {
    let root_needs: Vec<String> = crate::needs::used_by(dir)
        .into_iter()
        .filter(|n| *n != root.name)
        .collect();
    let mut queue: VecDeque<String> = root_needs.iter().cloned().collect();
    let mut seen = BTreeSet::from([root.name.clone()]);
    let mut out = vec![Member {
        name: root.name.clone(),
        needs: root_needs,
        dir: Some(dir.to_path_buf()),
        bluefile: Some(root.clone()),
    }];
    while let Some(name) = queue.pop_front() {
        if !seen.insert(name.clone()) {
            continue;
        }
        let member = match loader.select(&name).found {
            Some(Found::Dir(pkg)) => {
                let bluefile = std::fs::read_to_string(pkg.join(crate::MANIFEST_FILE))
                    .ok()
                    .and_then(|t| crate::read_bluefile(&t).ok());
                let needs: Vec<String> = crate::needs::used_by(&pkg)
                    .into_iter()
                    .filter(|n| *n != name)
                    .collect();
                Member {
                    name,
                    needs,
                    dir: Some(pkg),
                    bluefile,
                }
            }
            Some(Found::Standard) if unit == FloorUnit::Definition => {
                use blue_lang_runtime::uses::Loader;
                let needs = crate::embedded::Standard
                    .needs(&name, None)
                    .unwrap_or_default()
                    .into_iter()
                    .collect();
                Member {
                    bluefile: crate::embedded::Standard.bluefile(&name),
                    name,
                    needs,
                    dir: None,
                }
            }
            _ => Member {
                name,
                needs: Vec::new(),
                dir: None,
                bluefile: None,
            },
        };
        queue.extend(member.needs.iter().cloned());
        out.push(member);
    }
    out
}

/// The closure of the project at `dir`: its own code, then every package its
/// code uses, breadth first, each read once, with each floor counted by the
/// root's [`FloorUnit`] ([`unit_of`]).
///
/// # Errors
///
/// A package that cannot be read, one whose declared `reach` misses a
/// capability its code names (under [`FloorUnit::Definition`], its reached
/// definitions), or under [`FloorUnit::Definition`] a root file whose
/// program does not load.
pub fn graph(dir: &Path, root: &Bluefile, loader: &LoadPath) -> Result<Graph, CapabilityError> {
    let unit = unit_of(root);
    let members = closure(dir, root, loader, unit);
    match unit {
        FloorUnit::Package => {
            let mut nodes = BTreeMap::new();
            for m in members {
                let floor = match &m.dir {
                    Some(at) => floor_of(&m.name, at, m.bluefile.as_ref())?,
                    None => BTreeSet::new(),
                };
                nodes.insert(m.name, Node::of(floor, m.needs));
            }
            Ok(Graph {
                root: root.name.clone(),
                nodes,
                unit,
                definitions: BTreeMap::new(),
            })
        }
        FloorUnit::Definition => definition_graph(dir, root, loader, members),
    }
}

fn definition_graph(
    dir: &Path,
    root: &Bluefile,
    loader: &LoadPath,
    members: Vec<Member>,
) -> Result<Graph, CapabilityError> {
    let evidence = reached_definitions(dir, &root.name, loader)?;
    let mut nodes = BTreeMap::new();
    for m in members {
        let floor = evidence.floors.get(&m.name).cloned().unwrap_or_default();
        if let Some(declared) = declared_reach(m.bluefile.as_ref()) {
            within_declared(&m.name, &floor, &declared)?;
        }
        nodes.insert(m.name, Node::of(floor, m.needs));
    }
    for (name, floor) in &evidence.floors {
        nodes
            .entry(name.clone())
            .or_insert_with(|| Node::of(floor.clone(), Vec::new()));
    }
    let mut graph = Graph {
        root: root.name.clone(),
        nodes,
        unit: FloorUnit::Definition,
        definitions: evidence.definitions,
    };
    for ((package, cap), chain) in evidence.chains {
        let hops = match chain.from {
            None => chain.hops,
            Some(from) => {
                let mut hops = graph.path_to(&from);
                hops.pop();
                hops.extend(chain.hops);
                hops
            }
        };
        if let Some(node) = graph.nodes.get_mut(&package) {
            node.paths.insert(cap, hops);
        }
    }
    Ok(graph)
}

/// The hops to one definition that names a capability: from the root's own
/// code (`from` is `None`), or from code at the top level of package `from`,
/// which runs when it loads.
struct Chain {
    from: Option<String>,
    hops: Vec<String>,
}

/// What the definitions the root's code reaches name, read over every root
/// file's program.
#[derive(Default)]
struct Evidence {
    floors: BTreeMap<String, BTreeSet<Capability>>,
    definitions: BTreeMap<String, BTreeSet<Capability>>,
    chains: BTreeMap<(String, Capability), Chain>,
}

/// Every root file is checked as `blue run` would check it (test blocks
/// dropped), with every package it loads, and lowered to the tree the
/// evaluator runs. The walk starts at every form the root's code holds and
/// at every form that runs when its file loads (a bare call, a value, a
/// macro), and follows each definition a form names
/// ([`blue_lang_mondou::reach::form_reach`]). A reached form's own host
/// capabilities join its package's floor. Code built at run time and
/// `eval`ed is outside any tree, so the run's hold catches it.
fn reached_definitions(
    dir: &Path,
    root: &str,
    loader: &LoadPath,
) -> Result<Evidence, CapabilityError> {
    use blue_lang_mondou::def_hash::DefKind;
    use blue_lang_runtime::pipeline::{check_entry, lower, namespace_of, Checking};
    use blue_lang_runtime::uses::{Entry, ResolvedProgram};
    let mut evidence = Evidence::default();
    for path in sources_of(dir).map_err(CapabilityError::Read)? {
        let text = std::fs::read_to_string(&path)
            .map_err(|e| CapabilityError::Read(format!("{}: {e}", path.display())))?;
        let checked = check_entry(
            Entry {
                path: Some(&path),
                text: &text,
            },
            loader,
            None,
            Checking::Program,
        )
        .map_err(|e| {
            CapabilityError::Read(format!(
                "{}: {e}; a floor of reached definitions reads the program each root file loads (`floors(:package)` counts each package whole)",
                path.display()
            ))
        })?;
        let program = &checked.program;
        let lowered = lower(program, &checked.names);
        let hashes = blue_lang_mondou::def_hash::hash_program(&lowered);
        let forms =
            blue_lang_mondou::reach::form_reach(&blue_lang_runtime::erase_types(&lowered), &hashes);
        let own = |i: usize| program.owner_of(i) == Some(ResolvedProgram::ENTRY);
        let package_of = |i: usize| match namespace_of(program, i) {
            blue_lang_check::Namespace::Bidama(p) if !own(i) => p,
            _ => root.to_string(),
        };
        let label_of = |i: usize| {
            let package = package_of(i);
            match hashes.at(i) {
                Some(def) => {
                    let name = def
                        .key
                        .split_once(blue_lang_syntax::QUALIFIER)
                        .map_or(def.key.as_str(), |(_, n)| n);
                    format!("{package}::{name}")
                }
                None => package,
            }
        };
        let loads = |i: usize| hashes.at(i).is_none_or(|d| d.kind != DefKind::Function);
        let starts = (0..forms.len())
            .filter(|&i| own(i))
            .chain((0..forms.len()).filter(|&i| !own(i) && loads(i)));
        let mut parent: Vec<Option<usize>> = vec![None; forms.len()];
        let mut seen = vec![false; forms.len()];
        let mut order = Vec::new();
        let mut queue = VecDeque::new();
        for i in starts {
            if !seen[i] {
                seen[i] = true;
                queue.push_back(i);
            }
        }
        while let Some(at) = queue.pop_front() {
            order.push(at);
            for &d in &forms[at].names {
                let next = hashes.defs()[d].top_level;
                if seen.get(next) == Some(&false) {
                    seen[next] = true;
                    parent[next] = Some(at);
                    queue.push_back(next);
                }
            }
        }
        for at in order {
            if forms[at].host.is_empty() {
                continue;
            }
            let package = package_of(at);
            let mut walk = vec![at];
            let mut back = at;
            while let Some(p) = parent[back] {
                walk.push(p);
                back = p;
            }
            walk.reverse();
            let start = walk[0];
            let chain = || {
                if !own(start) {
                    Chain {
                        from: Some(package_of(start)),
                        hops: walk.iter().map(|&i| label_of(i)).collect(),
                    }
                } else if walk.len() == 1 {
                    Chain {
                        from: None,
                        hops: vec![label_of(start)],
                    }
                } else {
                    Chain {
                        from: None,
                        hops: std::iter::once(root.to_string())
                            .chain(walk[1..].iter().map(|&i| label_of(i)))
                            .collect(),
                    }
                }
            };
            for &cap in forms[at].host.keys() {
                evidence
                    .floors
                    .entry(package.clone())
                    .or_default()
                    .insert(cap);
                evidence
                    .definitions
                    .entry(label_of(at))
                    .or_default()
                    .insert(cap);
                evidence
                    .chains
                    .entry((package.clone(), cap))
                    .or_insert_with(&chain);
            }
        }
    }
    Ok(evidence)
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
    /// What each floor counts; a record written before the field counted
    /// whole packages.
    #[serde(default = "FloorUnit::recorded_before_units")]
    pub unit: FloorUnit,
    /// The join of every floor in the closure.
    pub floor: Vec<String>,
    /// Each package's floor.
    pub packages: BTreeMap<String, Vec<String>>,
    /// Under [`FloorUnit::Definition`], each reached definition that names a
    /// host capability on its own (`rede::get`, or `rede` for code at its top
    /// level) and what it names: each package's floor is the join of its
    /// rows. Empty under [`FloorUnit::Package`].
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub definitions: BTreeMap<String, Vec<String>>,
}

/// The root's ceiling as a reach: `Unrestricted` when it declares none.
#[must_use]
pub fn ceiling_of(bf: &Bluefile) -> Reach {
    reach_of(bf.project.allow.as_deref()).unwrap_or_else(|_| Reach::only(pure()))
}

/// The reach a ceiling's labels grant, with every pure capability beside
/// them; `None`, no ceiling, is every capability.
///
/// # Errors
///
/// A label that names no host capability.
pub fn reach_of(ceiling: Option<&[String]>) -> Result<Reach, String> {
    let Some(labels) = ceiling else {
        return Ok(Reach::Unrestricted);
    };
    let host = labels
        .iter()
        .map(|l| {
            host_capability(l).ok_or_else(|| format!("ceiling names `{l}`, no host capability"))
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Reach::only(host.into_iter().chain(pure())))
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
/// ceiling, each with its path from the root: the node's definition path
/// under [`FloorUnit::Definition`], else the packages.
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
                unit: graph.unit,
                floor: labels(&joined),
                packages: graph
                    .nodes
                    .iter()
                    .map(|(n, node)| (n.clone(), labels(&node.floor)))
                    .collect(),
                definitions: graph
                    .definitions
                    .iter()
                    .map(|(d, caps)| (d.clone(), labels(caps)))
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
                        path: node
                            .paths
                            .get(&cap)
                            .cloned()
                            .unwrap_or_else(|| graph.path_to(&name)),
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
/// when `bf` declares `allow` or a provider, the same ceiling, providers and
/// unit, every package floor inside the join and the join under the ceiling
/// and providers. Under [`FloorUnit::Definition`] each package's floor is
/// exactly the join of its definitions' rows; under [`FloorUnit::Package`]
/// there are no rows.
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
        && r.unit == unit_of(bf)
        && fits
        && r.packages.values().flatten().all(|f| floor.contains(f))
        && evidenced(r)
}

fn evidenced(r: &CapabilityRecord) -> bool {
    match r.unit {
        FloorUnit::Package => r.definitions.is_empty(),
        FloorUnit::Definition => {
            let mut joined: BTreeMap<&str, BTreeSet<&String>> = BTreeMap::new();
            for (definition, caps) in &r.definitions {
                let package = definition
                    .split_once("::")
                    .map_or(definition.as_str(), |(p, _)| p);
                joined.entry(package).or_default().extend(caps);
            }
            joined.keys().all(|p| r.packages.contains_key(*p))
                && r.packages.iter().all(|(p, floor)| {
                    floor.iter().collect::<BTreeSet<_>>()
                        == joined.get(p.as_str()).cloned().unwrap_or_default()
                })
        }
    }
}

/// Does the root at `bf` ask for the lattice to be verified?
#[must_use]
pub fn declared(bf: &Bluefile) -> bool {
    bf.project.allow.is_some() || !bf.project.virtualized.is_empty()
}

/// What `blue run` holds the program at `entry` to when its project declares
/// `allow` or a provider: the ceiling as its frame, and the providers.
/// `None` when the project declares neither, or there is no project.
///
/// # Errors
///
/// The nearest Bluefile above `entry` that is not a bidama's cannot be read
/// or does not evaluate: the run is refused rather than held to nothing.
pub fn hold_for(entry: &Path) -> Result<Option<blue_lang_runtime::Hold>, String> {
    let dir = entry
        .parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let dir = dir.canonicalize().unwrap_or_else(|_| dir.to_path_buf());
    for at in dir.ancestors() {
        let path = at.join(crate::MANIFEST_FILE);
        if !path.is_file() {
            continue;
        }
        let refused = |why: String| {
            format!(
                "{}: {why}; blue run holds a program to its project's allow and virtualize, and does not run it with every capability while the Bluefile does not read",
                path.display()
            )
        };
        let text = std::fs::read_to_string(&path).map_err(|e| refused(e.to_string()))?;
        let bf = crate::read_bluefile(&text).map_err(|e| refused(e.to_string()))?;
        if !declared(&bf) && crate::load_path::bidama_of(&bf).is_some() {
            continue;
        }
        return Ok(declared(&bf).then(|| blue_lang_runtime::Hold {
            frame: Waku {
                reach: ceiling_of(&bf),
                when: When::Anytime,
                place: Where::Process,
            },
            provisions: provisions_of(&bf),
        }));
    }
    Ok(None)
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
        Node::of(
            floor.iter().copied().collect(),
            needs.iter().map(ToString::to_string).collect(),
        )
    }

    fn sample() -> Graph {
        Graph {
            root: "app".into(),
            nodes: BTreeMap::from([
                ("app".into(), node(&[Capability::FileSystem], &["dep-a"])),
                ("dep-a".into(), node(&[], &["dep-b"])),
                ("dep-b".into(), node(&[Capability::Network], &[])),
            ]),
            unit: FloorUnit::Package,
            definitions: BTreeMap::new(),
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
        assert_eq!(host_capability(":comm_flash"), Some(Capability::CommFlash));
        assert_eq!(
            host_capability("comm-scavenger"),
            Some(Capability::CommScavenger)
        );
        assert_eq!(
            host_capability(":mpc_threshold"),
            Some(Capability::MpcThreshold)
        );
        assert_eq!(
            host_capability("mpc-threshold"),
            Some(Capability::MpcThreshold)
        );
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
            (
                ":comm_flash, {using: :loopback}",
                Provision::Loopback {
                    channel: blue_lang_waku::Channel::Flash,
                },
            ),
            (
                ":comm_scavenger, {using: :loopback}",
                Provision::Loopback {
                    channel: blue_lang_waku::Channel::Tide,
                },
            ),
            (
                ":mpc_threshold, {using: :seeded, seed: \"synod\"}",
                Provision::Seeded {
                    seed: "synod".into(),
                },
            ),
        ];
        for (settings, want) in cases {
            let got = virtualized(settings).unwrap_or_else(|e| panic!("{settings}: {e}"));
            let p = &got[want.capability().label()];
            assert_eq!(p.provision, want, "{settings}");
            assert_eq!(p.scope, None, "{settings}");
        }
        for cap in Capability::host_effects() {
            for kind in Provision::kinds_for(cap) {
                let symbol = cap.label().replace('-', "_");
                let settings = match *kind {
                    "seeded_prng" | "seeded" => {
                        format!(":{symbol}, {{using: :{kind}, seed: \"s\"}}")
                    }
                    _ => format!(":{symbol}, {{using: :{kind}}}"),
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
            (
                ":comm_flash, {using: :loopback, channel: :tide}",
                "`channel` is not a loopback setting; it takes nothing besides `using` and `for`",
            ),
            (
                ":comm_scavenger, {using: :null_sink}",
                "`using: :null_sink` is not a comm-scavenger provider; it takes :loopback",
            ),
            (":mpc_threshold, {using: :seeded}", "seeded needs a `seed`"),
            (
                ":mpc_threshold, {using: :seeded_prng, seed: \"s\"}",
                "`using: :seeded_prng` is not a mpc-threshold provider; it takes :seeded",
            ),
            (
                ":entropy, {using: :seeded, seed: \"s\"}",
                "`using: :seeded` is not a entropy provider; it takes :seeded_prng",
            ),
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
            Provision::Loopback {
                channel: blue_lang_waku::Channel::Flash,
            },
            Provision::Seeded { seed: "s".into() },
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
        assert_eq!(
            serde_json::to_value(Provided::from(Provision::Loopback {
                channel: blue_lang_waku::Channel::Tide,
            }))
            .unwrap(),
            serde_json::json!({"provider": "loopback", "channel": "tide"})
        );
        for stale in [
            serde_json::json!({"provider": "seeded-prng", "seed": "s", "mode": "x"}),
            serde_json::json!({"provider": "stepped-clock", "at_ms": 0, "step_ms": 0}),
            serde_json::json!({"provider": "memory-fs"}),
            serde_json::json!({"provider": "loopback"}),
            serde_json::json!({"provider": "loopback", "channel": "network"}),
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
    fn under_definition_floors_a_breach_names_the_definitions_from_the_root() {
        let mut g = sample();
        g.unit = FloorUnit::Definition;
        g.nodes.get_mut("app").unwrap().floor = BTreeSet::new();
        g.nodes.get_mut("dep-b").unwrap().paths = BTreeMap::from([(
            Capability::Network,
            vec!["app".into(), "dep-a::wrap".into(), "dep-b::get".into()],
        )]);
        g.definitions =
            BTreeMap::from([("dep-b::get".into(), BTreeSet::from([Capability::Network]))]);
        let err = verify(&g, &reach(&[]), &Provisions::default()).expect_err("dep-b::get");
        assert_eq!(
            err.to_string(),
            "[app] -> [dep-a::wrap] -> [dep-b::get: needs 'network'] violates ceiling []"
        );
        let record =
            verify(&g, &reach(&[Capability::Network]), &Provisions::default()).expect("fits");
        assert_eq!(record.unit, FloorUnit::Definition);
        assert_eq!(
            record.definitions,
            BTreeMap::from([("dep-b::get".to_string(), vec!["network".to_string()])])
        );
    }

    fn root(extra: &str) -> Bluefile {
        crate::read_bluefile(&format!(
            "package(\"app\", \"0.1.0\")\nallow(%i[network])\n{extra}"
        ))
        .unwrap()
    }

    fn record(
        unit: &str,
        packages: serde_json::Value,
        definitions: serde_json::Value,
    ) -> CapabilityRecord {
        serde_json::from_value(serde_json::json!({
            "ceiling": ["network"],
            "unit": unit,
            "floor": ["network"],
            "packages": packages,
            "definitions": definitions,
        }))
        .unwrap()
    }

    #[test]
    fn a_consistent_record_states_the_unit_and_joins_each_floor_from_its_definitions() {
        let floors = serde_json::json!({"app": [], "rede": ["network"]});
        let rows = serde_json::json!({"rede::get": ["network"]});
        let by_definition = record("definition", floors.clone(), rows.clone());
        assert!(consistent(&root(""), Some(&by_definition)));
        assert!(
            !consistent(&root(""), None),
            "a declared ceiling needs its record"
        );
        let undeclared = crate::read_bluefile("package(\"app\", \"0.1.0\")\n").unwrap();
        assert!(consistent(&undeclared, None));
        assert!(!consistent(&undeclared, Some(&by_definition)));
        assert!(
            !consistent(&root("floors(:package)\n"), Some(&by_definition)),
            "the Bluefile counts packages; the record counted definitions"
        );
        assert!(
            !consistent(
                &root(""),
                Some(&record("definition", floors.clone(), serde_json::json!({})))
            ),
            "a floor with no definition behind it"
        );
        assert!(
            !consistent(
                &root(""),
                Some(&record(
                    "definition",
                    serde_json::json!({"app": [], "rede": []}),
                    rows.clone()
                ))
            ),
            "a definition row its package's floor leaves out"
        );
        assert!(
            !consistent(
                &root(""),
                Some(&record(
                    "definition",
                    floors.clone(),
                    serde_json::json!({"nowhere::get": ["network"]})
                ))
            ),
            "a row for a package outside the closure"
        );
        assert!(consistent(
            &root("floors(:package)\n"),
            Some(&record("package", floors.clone(), serde_json::json!({})))
        ));
        assert!(
            !consistent(
                &root("floors(:package)\n"),
                Some(&record("package", floors, rows))
            ),
            "whole packages carry no definition rows"
        );
    }

    #[test]
    fn a_record_written_before_units_reads_as_whole_packages() {
        let old: CapabilityRecord = serde_json::from_value(serde_json::json!({
            "ceiling": [],
            "floor": [],
            "packages": {"app": []}
        }))
        .unwrap();
        assert_eq!(old.unit, FloorUnit::Package);
        assert!(old.definitions.is_empty());
        assert!(
            !consistent(&root(""), Some(&old)),
            "a lock counted by package is stale under the definition default"
        );
        let json = serde_json::to_value(record(
            "definition",
            serde_json::json!({"app": []}),
            serde_json::json!({}),
        ))
        .unwrap();
        assert_eq!(json["unit"], "definition");
        assert!(json.get("definitions").is_none(), "{json}");
    }

    #[test]
    fn floors_names_a_unit_and_refuses_any_other() {
        assert_eq!(root("").project.floors, None);
        assert_eq!(unit_of(&root("")), FloorUnit::Definition);
        assert_eq!(unit_of(&root("floors(:package)\n")), FloorUnit::Package);
        assert_eq!(
            unit_of(&root("floors(:definition)\n")),
            FloorUnit::Definition
        );
        for label in FloorUnit::LABELS {
            assert_eq!(
                FloorUnit::of_label(label).map(FloorUnit::label),
                Some(*label)
            );
        }
        let refused = crate::read_bluefile("package(\"app\", \"0.1.0\")\nfloors(:module)\n")
            .expect_err("no such unit")
            .to_string();
        assert!(
            refused.contains("definition")
                && refused.contains("package")
                && refused.contains("module"),
            "{refused}"
        );
        let twice = crate::read_bluefile(
            "package(\"app\", \"0.1.0\")\nfloors(:package)\nfloors(:definition)\n",
        );
        assert!(twice.is_err(), "declared once");
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
