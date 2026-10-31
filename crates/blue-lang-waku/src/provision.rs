//! A host capability bound to a pure provider instead of the host.
//!
//! A frame that virtualizes a capability grants its names, so a package whose
//! floor needs the capability resolves under a ceiling that withholds it, but
//! no call reaches the host: the clock steps, entropy is a seeded stream, the
//! filesystem lives in memory or nowhere. [`Provision::kinds_for`] is
//! exhaustive over [`Capability`], so a new capability lands with its answer.
//!
//! A provider serves the whole program, or only the packages it names
//! ([`Provided::scope`]) and every package they use.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::{Capability, Reach};

/// One pure provider for one host capability. A Bluefile names it after
/// `using:` ([`Provision::name`]); the lock records its kebab-case label.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "provider", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Provision {
    /// The clock reads `at_ms`; each reading advances it by `step_ms`, and a
    /// sleep advances it by its length and returns at once.
    DeterministicStepped { at_ms: i64, step_ms: i64 },
    /// `random_bytes` reads one BLAKE3 stream keyed by `seed`.
    SeededPrng { seed: String },
    /// An isolated tree on an empty base that the run's writes fill; no read
    /// or write reaches the host.
    InMemoryOverlay,
    /// Every write succeeds and is dropped; every read finds nothing.
    NullSink,
}

impl Provision {
    #[must_use]
    pub fn capability(&self) -> Capability {
        match self {
            Provision::DeterministicStepped { .. } => Capability::Clock,
            Provision::SeededPrng { .. } => Capability::Entropy,
            Provision::InMemoryOverlay | Provision::NullSink => Capability::FileSystem,
        }
    }

    /// The provider as a Bluefile names it: `using: :deterministic_stepped`.
    #[must_use]
    pub fn name(&self) -> &'static str {
        match self {
            Provision::DeterministicStepped { .. } => "deterministic_stepped",
            Provision::SeededPrng { .. } => "seeded_prng",
            Provision::InMemoryOverlay => "in_memory_overlay",
            Provision::NullSink => "null_sink",
        }
    }

    /// The provider as the lock records it: [`Provision::name`] in kebab case.
    #[must_use]
    pub fn label(&self) -> &'static str {
        match self {
            Provision::DeterministicStepped { .. } => "deterministic-stepped",
            Provision::SeededPrng { .. } => "seeded-prng",
            Provision::InMemoryOverlay => "in-memory-overlay",
            Provision::NullSink => "null-sink",
        }
    }

    /// The providers `cap` can be bound to, by [`Provision::name`]; empty for
    /// a capability blue cannot provide without the host.
    #[must_use]
    pub fn kinds_for(cap: Capability) -> &'static [&'static str] {
        match cap {
            Capability::Clock => &["deterministic_stepped"],
            Capability::Entropy => &["seeded_prng"],
            Capability::FileSystem => &["in_memory_overlay", "null_sink"],
            Capability::Process
            | Capability::Environment
            | Capability::Network
            | Capability::CommFlash
            | Capability::CommScavenger
            | Capability::CoreForms
            | Capability::Operators
            | Capability::Collections
            | Capability::Interpolation
            | Capability::Assertion
            | Capability::ManifestDeclaration => &[],
        }
    }

    /// The capability whose provider answers the host name `name`, if any.
    #[must_use]
    pub fn capability_of(name: &str) -> Option<Capability> {
        Capability::host_effects()
            .into_iter()
            .find(|c| !Provision::kinds_for(*c).is_empty() && c.grants(name))
    }
}

/// A provider and the packages it serves.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Provided {
    #[serde(flatten)]
    pub provision: Provision,
    /// The packages whose code reaches the provider, each with every package
    /// it uses; absent for the whole program.
    #[serde(rename = "for", default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<BTreeSet<String>>,
}

impl From<Provision> for Provided {
    fn from(provision: Provision) -> Self {
        Self {
            provision,
            scope: None,
        }
    }
}

/// The capabilities a frame provides purely, at most one provider each.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Provisions(BTreeMap<Capability, Provided>);

/// Why a provision was refused.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProvisionError {
    /// A second provider for a capability that already has one.
    Twice(Capability),
    /// The provider's capability is also granted from the host.
    AlsoGranted(Capability),
}

impl std::fmt::Display for ProvisionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProvisionError::Twice(c) => {
                write!(f, "{} is virtualized twice; keep one provider", c.label())
            }
            ProvisionError::AlsoGranted(c) => write!(
                f,
                "{} is both granted from the host and virtualized; keep one",
                c.label()
            ),
        }
    }
}

impl Provisions {
    /// Add `p`, refusing a second provider for its capability.
    ///
    /// # Errors
    ///
    /// [`ProvisionError::Twice`] when the capability already has a provider.
    pub fn add(&mut self, p: impl Into<Provided>) -> Result<(), ProvisionError> {
        let p = p.into();
        let cap = p.provision.capability();
        if self.0.contains_key(&cap) {
            return Err(ProvisionError::Twice(cap));
        }
        self.0.insert(cap, p);
        Ok(())
    }

    /// Refuse a whole-program provider whose capability `granted` also
    /// grants: the host would never be reached. A scoped provider may share
    /// its capability with the host, which answers every package outside it.
    ///
    /// # Errors
    ///
    /// [`ProvisionError::AlsoGranted`] naming the first such capability.
    pub fn disjoint_from(&self, granted: &Reach) -> Result<(), ProvisionError> {
        let mut whole = self
            .0
            .iter()
            .filter(|(_, p)| p.scope.is_none())
            .map(|(c, _)| c);
        match whole.find(|c| granted.grants(**c)) {
            Some(c) if *granted != Reach::Unrestricted => Err(ProvisionError::AlsoGranted(*c)),
            _ => Ok(()),
        }
    }

    #[must_use]
    pub fn get(&self, cap: Capability) -> Option<&Provided> {
        self.0.get(&cap)
    }

    pub fn iter(&self) -> impl Iterator<Item = &Provided> {
        self.0.values()
    }

    /// Each scoped provider's capability and the packages it names.
    pub fn scoped(&self) -> impl Iterator<Item = (Capability, &BTreeSet<String>)> {
        self.0
            .iter()
            .filter_map(|(c, p)| p.scope.as_ref().map(|s| (*c, s)))
    }

    #[must_use]
    pub fn capabilities(&self) -> Vec<Capability> {
        self.0.keys().copied().collect()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// `reach` with every whole-program provider's capability added: what
    /// any code may need and still resolve. A scoped provider widens only
    /// the packages it serves ([`Provisions::scoped`]).
    #[must_use]
    pub fn widen(&self, reach: &Reach) -> Reach {
        reach.join(&Reach::only(
            self.0
                .iter()
                .filter(|(_, p)| p.scope.is_none())
                .map(|(c, _)| *c),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn every() -> Vec<Provision> {
        vec![
            Provision::DeterministicStepped {
                at_ms: 0,
                step_ms: 1,
            },
            Provision::SeededPrng { seed: "s".into() },
            Provision::InMemoryOverlay,
            Provision::NullSink,
        ]
    }

    fn scoped(p: Provision, packages: &[&str]) -> Provided {
        Provided {
            provision: p,
            scope: Some(packages.iter().map(ToString::to_string).collect()),
        }
    }

    #[test]
    fn every_provider_is_listed_under_its_capability_and_no_other() {
        for p in every() {
            for cap in Capability::ALL {
                assert_eq!(
                    Provision::kinds_for(cap).contains(&p.name()),
                    cap == p.capability(),
                    "{} under {}",
                    p.name(),
                    cap.label()
                );
            }
        }
        let listed: usize = Capability::ALL
            .iter()
            .map(|c| Provision::kinds_for(*c).len())
            .sum();
        assert_eq!(listed, every().len());
    }

    #[test]
    fn the_lock_label_is_the_bluefile_name_in_kebab_case() {
        for p in every() {
            assert_eq!(p.label(), p.name().replace('_', "-"));
        }
    }

    #[test]
    fn only_host_effects_can_be_virtualized_and_not_process_network_environment_or_the_wire() {
        for cap in Capability::ALL {
            let can = !Provision::kinds_for(cap).is_empty();
            assert!(!can || cap.is_host_effect(), "{}", cap.label());
        }
        for cap in [
            Capability::Process,
            Capability::Network,
            Capability::Environment,
            Capability::CommFlash,
            Capability::CommScavenger,
        ] {
            assert!(Provision::kinds_for(cap).is_empty(), "{}", cap.label());
        }
        assert_eq!(Provision::capability_of("now_ms"), Some(Capability::Clock));
        assert_eq!(
            Provision::capability_of("path_join"),
            Some(Capability::FileSystem)
        );
        assert_eq!(Provision::capability_of("getenv"), None);
        assert_eq!(Provision::capability_of("flash_put"), None);
        assert_eq!(Provision::capability_of("tide_release"), None);
        assert_eq!(Provision::capability_of("map"), None);
    }

    #[test]
    fn a_capability_takes_one_provider_and_not_one_the_host_grants() {
        let mut ps = Provisions::default();
        ps.add(Provision::InMemoryOverlay).unwrap();
        assert_eq!(
            ps.add(Provision::NullSink),
            Err(ProvisionError::Twice(Capability::FileSystem))
        );
        ps.add(Provision::DeterministicStepped {
            at_ms: 5,
            step_ms: 0,
        })
        .unwrap();
        assert_eq!(
            ps.capabilities(),
            vec![Capability::FileSystem, Capability::Clock]
        );
        assert_eq!(
            ps.disjoint_from(&Reach::only([Capability::Clock])),
            Err(ProvisionError::AlsoGranted(Capability::Clock))
        );
        assert_eq!(
            ps.disjoint_from(&Reach::only([Capability::Network])),
            Ok(())
        );
        assert_eq!(ps.disjoint_from(&Reach::Unrestricted), Ok(()));
        let mut only = Provisions::default();
        only.add(scoped(Provision::SeededPrng { seed: "x".into() }, &["a"]))
            .unwrap();
        assert_eq!(
            only.disjoint_from(&Reach::only([Capability::Entropy])),
            Ok(()),
            "a scoped provider shares its capability with the host"
        );
    }

    #[test]
    fn widening_adds_exactly_the_whole_program_providers() {
        let mut ps = Provisions::default();
        ps.add(Provision::SeededPrng { seed: "x".into() }).unwrap();
        ps.add(scoped(
            Provision::DeterministicStepped {
                at_ms: 0,
                step_ms: 1,
            },
            &["rede"],
        ))
        .unwrap();
        let ceiling = Reach::only([Capability::FileSystem]);
        assert_eq!(
            ps.widen(&ceiling),
            Reach::only([Capability::FileSystem, Capability::Entropy])
        );
        assert_eq!(Provisions::default().widen(&ceiling), ceiling);
        let named: Vec<_> = ps.scoped().collect();
        assert_eq!(named.len(), 1);
        assert_eq!(named[0].0, Capability::Clock);
        assert!(named[0].1.contains("rede"));
    }
}
