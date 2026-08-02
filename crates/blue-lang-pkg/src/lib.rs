//! blue's package manager — the Bluefile, and the version solver under it.
//!
//! ## The Bluefile is a blue program
//!
//! There is **no new syntax**. A `Bluefile` is a `.b` file whose top level
//! calls three functions:
//!
//! ```text
//! package("myapp", "0.1.0")
//! needs("gaming", "^1.2")
//! needs("audio", ">=0.4.0")
//! ```
//!
//! blue *evaluates* it with those three installed as primitives and collects
//! what they declare. That is the "blue doubles as a configuration language"
//! tenet doing real work rather than being asserted: the manifest reader is the
//! interpreter, so a Bluefile can compute — a version can come from a variable,
//! a dependency list can come from a macro — and none of it needs a second
//! parser, a second grammar, or a TOML dialect that drifts from the language.
//!
//! ## What is here and what is not
//!
//! Resolution ([`solve`]) and the manifest surface are real and tested.
//! **Fetching is not**: nothing downloads, unpacks, or verifies an artifact.
//! `Registry` is a trait with an in-memory implementation, which is what makes
//! the solver testable — and it is also the seam a real registry client would
//! land behind. Stated plainly so nobody reads `blue deps` as installing
//! anything.

pub mod bluefile;
/// Git-backed resolution — a distribution is a directory of bidamas in a
/// checkout, not a package server. See the module docs for what it does and
/// does NOT claim.
pub mod git_registry;
pub mod solve;
pub mod version;

pub use bluefile::{read_bluefile, Bluefile, BluefileError};
pub use solve::{
    Conflict, Manifest, MapRegistry, Registry, Resolution, SolveError, Solver, DEFAULT_MAX_STEPS,
};
pub use version::{Range, Version, VersionError};
