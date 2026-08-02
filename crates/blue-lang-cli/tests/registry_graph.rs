//! The gate on blue's **registry** dependency graph.
//!
//! blue is thirteen crates that publish as thirteen separate packages, in
//! topological order, one registry at a time. That order only exists if the
//! graph cargo will see *on crates.io* is acyclic — and that graph is not the
//! graph `cargo build` sees.
//!
//! # The defect this exists to prevent, which already happened twice
//!
//! `[workspace.dependencies]` carries a `version` so the nine crates with
//! sibling **normal** deps can publish at all (a path-only normal dep is a hard
//! publish error). But one entry serves both dependency kinds, so
//! `blue-lang-fmt = { workspace = true }` in a `[dev-dependencies]` block
//! inherits that version too — and **cargo keeps a versioned dev-dependency in
//! the published manifest**, where it must resolve on the registry.
//!
//! `blue-lang-syntax` dev-depended on `blue-lang-fmt`; `blue-lang-fmt` depends
//! on `blue-lang-syntax`. Neither could ever go first. Measured on 2026-08-02:
//!
//! ```text
//! deferring 'blue-lang-syntax' — workspace sibling not on the registry yet:
//!   no matching package named `blue-lang-fmt` found
//! ERROR no progress this pass; aborting (likely circular dep or stuck
//!   registry index).
//! ```
//!
//! Every release from v0.0.13 to v0.0.19 aborted on that, and the four crates
//! that had reached the registry sat frozen at v0.0.12 while the workspace
//! version ran away from them. The comment on the offending line read
//! "Dev-only, so no cycle ships" — a belief, stated in the file, that this test
//! now replaces with a measurement.
//!
//! It happened twice because the first fix was applied to the *instance*:
//! `blue-lang-runtime`'s dev-dep on `blue-lang-pkg` was made path-only with an
//! accurate comment explaining exactly this, and the other six sibling dev-deps
//! were left versioned. A rule that lives only in a comment protects only the
//! file it is written in.
//!
//! # The rule
//!
//! **A dev-dependency on a workspace sibling is declared path-only, never
//! `{ workspace = true }`.** Cargo drops a version-less dev-dependency from the
//! published manifest entirely, so the edge exists for `cargo test` (where it
//! is legal and useful) and does not exist for the registry.
//!
//! # Tier
//!
//! **CI-gate-caught**, and not better. `Cargo.toml` is data; nothing in the
//! type system can refuse a cyclic manifest set, and cargo itself only reports
//! the cycle one crate at a time at publish time, hours after merge. This test
//! moves that to `cargo test`. It does not make the cycle unrepresentable.

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::process::Command;

/// Registry-visible edges: member → the siblings its published manifest names.
type Graph = BTreeMap<String, BTreeSet<String>>;

fn workspace_root() -> PathBuf {
    PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../.."))
}

/// The workspace manifests, straight from cargo.
///
/// `--no-deps` keeps this to the members' own manifests, so it neither resolves
/// nor touches the network; `--offline` makes that explicit rather than
/// incidental. A failure here is a hard failure — a gate that skips when it
/// cannot measure is not a gate.
fn metadata() -> serde_json::Value {
    let out = Command::new(env!("CARGO"))
        .args([
            "metadata",
            "--no-deps",
            "--format-version",
            "1",
            "--offline",
        ])
        .current_dir(workspace_root())
        .output()
        .expect("`cargo metadata` must be runnable; this gate may not skip");
    assert!(
        out.status.success(),
        "`cargo metadata` failed, so the registry graph could not be checked:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    serde_json::from_slice(&out.stdout).expect("`cargo metadata` emits JSON")
}

/// Every workspace member, and each one's sibling dependencies with the two
/// facts that decide whether the edge reaches the registry: the dependency
/// kind, and whether a version requirement was stated.
///
/// `cargo metadata` reports a path-only dependency as `req == "*"` — that is
/// precisely the shape cargo strips from a published manifest.
fn siblings() -> Vec<(String, Vec<(String, bool, bool)>)> {
    let meta = metadata();
    let packages = meta["packages"].as_array().expect("packages is an array");
    let members: BTreeSet<&str> = packages
        .iter()
        .map(|p| p["name"].as_str().expect("a package has a name"))
        .collect();

    packages
        .iter()
        .map(|p| {
            let name = p["name"].as_str().expect("a package has a name").to_owned();
            let deps = p["dependencies"]
                .as_array()
                .expect("dependencies is an array")
                .iter()
                .filter_map(|d| {
                    let dep = d["name"].as_str().expect("a dependency has a name");
                    if !members.contains(dep) {
                        return None;
                    }
                    // `kind` is null for a normal dep, "dev"/"build" otherwise.
                    let is_dev = d["kind"].as_str() == Some("dev");
                    let versioned = d["req"].as_str() != Some("*");
                    Some((dep.to_owned(), is_dev, versioned))
                })
                .collect();
            (name, deps)
        })
        .collect()
}

/// The graph cargo will resolve against crates.io.
///
/// A normal or build dependency is always in the published manifest. A dev
/// dependency is in it only when it carries a version.
fn registry_graph() -> Graph {
    siblings()
        .into_iter()
        .map(|(name, deps)| {
            let edges = deps
                .into_iter()
                .filter(|&(_, is_dev, versioned)| !is_dev || versioned)
                .map(|(dep, _, _)| dep)
                .collect();
            (name, edges)
        })
        .collect()
}

/// Depth-first search for a back edge, returning the cycle it closes.
fn find_cycle(graph: &Graph) -> Option<Vec<String>> {
    // `visiting` is the current DFS path (a back edge into it is the cycle);
    // `done` is everything already proven to reach no cycle.
    fn walk(
        graph: &Graph,
        node: &str,
        path: &mut Vec<String>,
        visiting: &mut BTreeSet<String>,
        done: &mut BTreeSet<String>,
    ) -> Option<Vec<String>> {
        if done.contains(node) {
            return None;
        }
        if visiting.contains(node) {
            let start = path
                .iter()
                .position(|n| n == node)
                .expect("a node being visited is on the path");
            let mut cycle = path[start..].to_vec();
            cycle.push(node.to_owned());
            return Some(cycle);
        }
        visiting.insert(node.to_owned());
        path.push(node.to_owned());
        for next in graph.get(node).into_iter().flatten() {
            if let Some(cycle) = walk(graph, next, path, visiting, done) {
                return Some(cycle);
            }
        }
        path.pop();
        visiting.remove(node);
        done.insert(node.to_owned());
        None
    }

    let mut visiting = BTreeSet::new();
    let mut done = BTreeSet::new();
    for node in graph.keys() {
        let mut path = Vec::new();
        if let Some(cycle) = walk(graph, node, &mut path, &mut visiting, &mut done) {
            return Some(cycle);
        }
    }
    None
}

/// The rule, stated directly: a sibling dev-dependency is path-only.
///
/// This is the actionable half. It names the exact line to change, which the
/// acyclicity test below cannot do — a cycle is a property of the whole graph,
/// but every cycle this repo has actually shipped was one versioned dev-dep.
#[test]
fn no_sibling_dev_dependency_carries_a_version() {
    let offenders: Vec<String> = siblings()
        .into_iter()
        .flat_map(|(name, deps)| {
            deps.into_iter()
                .filter(|&(_, is_dev, versioned)| is_dev && versioned)
                .map(move |(dep, _, _)| {
                    let mut s = String::new();
                    s.push_str(&name);
                    s.push_str("'s [dev-dependencies] on ");
                    s.push_str(&dep);
                    s
                })
        })
        .collect();

    assert!(
        offenders.is_empty(),
        "a workspace sibling in [dev-dependencies] must be declared path-only \
         (`{{ path = \"../<name>\" }}`), never `{{ workspace = true }}` — the \
         shared [workspace.dependencies] entry injects a version, cargo then \
         keeps the dev-dep in the published manifest, and it has to resolve on \
         crates.io. That is how blue stalled every release from v0.0.13 to \
         v0.0.19. Offending declarations:\n  {}",
        offenders.join("\n  ")
    );
}

/// The property the rule protects: the published graph can be topologically
/// ordered, so the releaser can publish one crate at a time.
///
/// Checked independently of the rule above so the gate is not merely restating
/// it — this also catches a cycle formed entirely out of normal dependencies.
#[test]
fn the_registry_dependency_graph_is_acyclic() {
    let graph = registry_graph();
    assert_eq!(
        graph.len(),
        13,
        "every workspace member must be in the graph; if this count is wrong \
         the rest of this test is measuring the wrong thing"
    );

    if let Some(cycle) = find_cycle(&graph) {
        let rendered: Vec<&str> = cycle.iter().map(String::as_str).collect();
        panic!(
            "blue's registry dependency graph has a cycle, so no publish order \
             exists and `rust-workspace-publish` will abort with \"no progress \
             this pass\":\n  {}",
            rendered.join(" -> ")
        );
    }
}
