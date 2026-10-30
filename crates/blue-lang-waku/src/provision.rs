//! A host capability bound to a pure provider instead of the host.
//!
//! A frame that virtualizes a capability grants its names, so a package whose
//! floor needs the capability resolves under a ceiling that withholds it, but
//! no call reaches the host: the clock steps, entropy is a seeded stream, the
//! filesystem lives in memory or nowhere. [`Provision::kinds_for`] is
//! exhaustive over [`Capability`], so a new capability lands with its answer.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::{Capability, Reach};

/// One pure provider for one host capability.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "provider", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Provision {
    /// The clock reads `at_ms`; each reading advances it by `step_ms`, and a
    /// sleep advances it by its length and returns at once.
    SteppedClock { at_ms: i64, step_ms: i64 },
    /// `random_bytes` reads one BLAKE3 stream keyed by `seed`.
    SeededEntropy { seed: String },
    /// An empty in-memory tree that the run's writes fill.
    MemoryFs,
    /// Every write succeeds and is dropped; every read finds nothing.
    NullFs,
}

impl Provision {
    #[must_use]
    pub fn capability(&self) -> Capability {
        match self {
            Provision::SteppedClock { .. } => Capability::Clock,
            Provision::SeededEntropy { .. } => Capability::Entropy,
            Provision::MemoryFs | Provision::NullFs => Capability::FileSystem,
        }
    }

    #[must_use]
    pub fn label(&self) -> &'static str {
        match self {
            Provision::SteppedClock { .. } => "stepped-clock",
            Provision::SeededEntropy { .. } => "seeded-entropy",
            Provision::MemoryFs => "memory-fs",
            Provision::NullFs => "null-fs",
        }
    }

    /// The providers `cap` can be bound to; empty for a capability blue
    /// cannot provide without the host.
    #[must_use]
    pub fn kinds_for(cap: Capability) -> &'static [&'static str] {
        match cap {
            Capability::Clock => &["stepped-clock"],
            Capability::Entropy => &["seeded-entropy"],
            Capability::FileSystem => &["memory-fs", "null-fs"],
            Capability::Process
            | Capability::Environment
            | Capability::Network
            | Capability::CoreForms
            | Capability::Operators
            | Capability::Collections
            | Capability::Interpolation
            | Capability::Assertion
            | Capability::ManifestDeclaration => &[],
        }
    }
}

/// The capabilities a frame provides purely, at most one provider each.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Provisions(BTreeMap<Capability, Provision>);

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
    pub fn add(&mut self, p: Provision) -> Result<(), ProvisionError> {
        let cap = p.capability();
        if self.0.contains_key(&cap) {
            return Err(ProvisionError::Twice(cap));
        }
        self.0.insert(cap, p);
        Ok(())
    }

    /// Refuse a provider whose capability `granted` also grants.
    ///
    /// # Errors
    ///
    /// [`ProvisionError::AlsoGranted`] naming the first such capability.
    pub fn disjoint_from(&self, granted: &Reach) -> Result<(), ProvisionError> {
        match self.0.keys().find(|c| granted.grants(**c)) {
            Some(c) if *granted != Reach::Unrestricted => Err(ProvisionError::AlsoGranted(*c)),
            _ => Ok(()),
        }
    }

    #[must_use]
    pub fn get(&self, cap: Capability) -> Option<&Provision> {
        self.0.get(&cap)
    }

    pub fn iter(&self) -> impl Iterator<Item = &Provision> {
        self.0.values()
    }

    #[must_use]
    pub fn capabilities(&self) -> Vec<Capability> {
        self.0.keys().copied().collect()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// `reach` with every provided capability added: what a floor may need
    /// and still resolve.
    #[must_use]
    pub fn widen(&self, reach: &Reach) -> Reach {
        reach.join(&Reach::only(self.0.keys().copied()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn every() -> Vec<Provision> {
        vec![
            Provision::SteppedClock {
                at_ms: 0,
                step_ms: 1,
            },
            Provision::SeededEntropy { seed: "s".into() },
            Provision::MemoryFs,
            Provision::NullFs,
        ]
    }

    #[test]
    fn every_provider_is_listed_under_its_capability_and_no_other() {
        for p in every() {
            for cap in Capability::ALL {
                assert_eq!(
                    Provision::kinds_for(cap).contains(&p.label()),
                    cap == p.capability(),
                    "{} under {}",
                    p.label(),
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
    fn only_host_effects_can_be_virtualized_and_not_process_network_or_environment() {
        for cap in Capability::ALL {
            let can = !Provision::kinds_for(cap).is_empty();
            assert!(!can || cap.is_host_effect(), "{}", cap.label());
        }
        for cap in [
            Capability::Process,
            Capability::Network,
            Capability::Environment,
        ] {
            assert!(Provision::kinds_for(cap).is_empty(), "{}", cap.label());
        }
    }

    #[test]
    fn a_capability_takes_one_provider_and_not_one_the_host_grants() {
        let mut ps = Provisions::default();
        ps.add(Provision::MemoryFs).unwrap();
        assert_eq!(
            ps.add(Provision::NullFs),
            Err(ProvisionError::Twice(Capability::FileSystem))
        );
        ps.add(Provision::SteppedClock {
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
    }

    #[test]
    fn widening_adds_exactly_the_provided_capabilities() {
        let mut ps = Provisions::default();
        ps.add(Provision::SeededEntropy { seed: "x".into() })
            .unwrap();
        let ceiling = Reach::only([Capability::FileSystem]);
        assert_eq!(
            ps.widen(&ceiling),
            Reach::only([Capability::FileSystem, Capability::Entropy])
        );
        assert_eq!(Provisions::default().widen(&ceiling), ceiling);
    }
}
