//! The closed capability universe — what a [`crate::Reach`] is a set *of*.
//!
//! `theory/BLUE-EXECUTION.md` M0. Before this module, `Reach::Only` carried
//! free `String`s, and two things followed from that one fact:
//!
//! - **A typo was silently restrictive.** `Reach::only(["read-flie"])`
//!   compiled, granted nothing, and read as though it granted something.
//! - **There was nothing to lower from.** An import table is a *total* function
//!   over the capabilities a frame may name, and a `BTreeSet<String>` has no
//!   totality: nothing can be exhaustive over the set of all strings, so the
//!   lowering could only ever be a hand-maintained list that drifts.
//!
//! Both are gone for the same reason: **[`Capability`] is closed.** There is no
//! `Other(String)` arm, and every function that reads a capability is an
//! exhaustive `match` with **no wildcard arm** — `next`, [`Capability::label`],
//! `names_source` and [`Capability::import`]. Adding a variant is an `E0004`
//! four times over, which is the whole point of closing the type: a capability
//! that lands without an import lowering **cannot compile**.
//!
//! ## A capability is a BUNDLE OF NAMES, and that is a correction
//!
//! `BLUE-EXECUTION.md` §IV.1 describes `Capability` as *"one variant per host
//! effect blue is willing to name"*. Measured against the tree on 2026-08-13,
//! that description is a third of the type it asks for. `Reach`'s own doc
//! comment says what it governs — *"what definitions a computation may
//! **name**"* — and its shipped consumers use it that way: `manifest_frame`
//! grants `package`/`needs`/`posture` plus nine control-flow heads plus every
//! `INFIX` callee, none of which is a host effect. A universe of host effects
//! alone could not express a single frame blue actually mints.
//!
//! So a `Capability` is **a named bundle of the identifiers a frame grants the
//! right to name**, and the host-effect bundles are the subset that lower to an
//! import. That keeps `check_reach` working unchanged, keeps `permits` a
//! question about a name, and still gives §IV.1 exactly what it wanted: a
//! closed set to be total over.
//!
//! ## Where the names come from — measured, never invented
//!
//! Every bundle is read off a table that already exists, because a second copy
//! of a name list is the defect this repo has shipped most often:
//!
//! | bundle | source |
//! |---|---|
//! | [`Capability::Operators`] | `blue_lang_syntax::INFIX`, the one operator table |
//! | [`Capability::Collections`] | `blue_lang_syntax::LOWERED_MAP` + the list constructor |
//! | [`Capability::Interpolation`] | `blue_lang_syntax::LOWERED_CONCAT` |
//! | [`Capability::Assertion`] | `blue_lang_syntax::LOWERED_ASSERT` |
//! | [`Capability::CoreForms`] | the heads `blue-lang-syntax` lowers control flow to |
//! | [`Capability::ManifestDeclaration`] | the three Bluefile primitives |
//! | the four host bundles | `blue_lang_runtime::sys`'s four installers |
//!
//! The last row is the one that could rot, and it is gated rather than trusted:
//! `blue-lang-cli`'s `tests/capability_surface.rs` installs the sys layer into a
//! bare interpreter, diffs the reserved names, and fails if a single one is
//! unclaimed or mis-claimed. That is independent evidence — a real interpreter
//! resolving a symbol — not this file checking itself.

use crate::Reach;

/// One thing a frame may grant the right to **name**.
///
/// **Closed by construction.** There is no `Other(String)`, and there will not
/// be one: the arm would restore every property this type exists to remove.
/// Adding a capability means adding four arms and one row to the chain below,
/// and the compiler asks for all five.
///
/// The ordering is deliberate and load-bearing in exactly one place: the pure
/// bundles come first, so [`crate::imports_of`] emits a stable table.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Capability {
    // ── pure: named inside the module, lowering to NO import ──────────────
    /// The heads blue lowers control flow to.
    ///
    /// These are `match` arms in tatara's evaluator rather than bindings, so
    /// omitting one would not actually withhold it — they are here because
    /// `check_reach` reports a head like any other symbol and the frame has to
    /// answer. See `crate::walk_binder`'s note on why that question is left
    /// open there.
    CoreForms,
    /// Every callee in `blue_lang_syntax::INFIX`, **read from that table**.
    ///
    /// The repo's rule is that `INFIX` is one table and both directions read
    /// it. A hand-copied operator list here would be the third copy that
    /// disagreed — which is exactly how `==` shipped with a precedence and no
    /// callee.
    Operators,
    /// The pure aggregate constructors: the list constructor and the callee a
    /// `{...}` literal lowers to.
    Collections,
    /// The callee string interpolation lowers to.
    Interpolation,
    /// The callee `assert e` lowers to.
    ///
    /// Blue **owns** this name rather than delegating it — the runtime must not
    /// bind it, which `blue-lang-test`'s `no_lowered_name_is_shadowed_by_the_runtime`
    /// gates. Granting it is granting the right to *name* it, which is a
    /// different question from who defines it.
    Assertion,
    /// The three primitives a Bluefile is *for*.
    ManifestDeclaration,

    // ── host effects: each lowers to exactly one import ───────────────────
    /// Running another program. `blue_lang_runtime::sys::install_process`.
    ///
    /// Note for whoever wires the engine border (M2): **WASI has no subprocess
    /// spawn at any preview level**, so this capability has no WASI lowering to
    /// inherit. Its import is blue's own, which is why [`HOST_MODULE`] is a blue
    /// module name and not `wasi_snapshot_preview1`.
    Process,
    /// The filesystem. `blue_lang_runtime::sys::install_fs`.
    ///
    /// At the granularity the runtime itself groups. Four of its names
    /// (`path_join`, `path_basename`, `path_dirname`, `path_extension`) are
    /// pure string arithmetic that happens to live in the fs installer — they
    /// are host-gated in blue's actual build, so classifying them here is what
    /// is true rather than what is tidy. Splitting read from write is a later
    /// variant, and adding one is safe precisely because of the `E0004`.
    FileSystem,
    /// The environment and the argument vector. `…::install_env`.
    Environment,
    /// Time and sleeping. `…::install_clock`.
    Clock,
}

/// The wasm import module every host capability lowers into.
///
/// **Blue's own, not `wasi_snapshot_preview1`, and that is a decision.**
/// `BLUE-EXECUTION.md` §I.2 measured `tatara-wasm`'s `WasiPreview::default()` at
/// `P2`, an arm every shipped engine in that crate rejects — the trap being that
/// modelling preview levels here would freeze a guess about an ABI blue has not
/// designed. Blue's host functions take strings, not file descriptors; mapping
/// them onto preview1's fd-based calls is real translation work and it belongs
/// to M2's engine border, not to M1's derivation. So the table names blue's own
/// interface and stays silent about who implements it.
pub const HOST_MODULE: &str = "blue:host";

/// One entry in a module's import table.
///
/// Deliberately just the two names a wasm import is keyed by. **No signature**:
/// a signature is a claim about an ABI, and the ABI is M2's. Adding one here
/// before the engine border exists would be a guess that reads as a fact.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Import {
    /// The wasm import module, always [`HOST_MODULE`] today.
    pub module: &'static str,
    /// The field within it — one per host capability.
    pub field: &'static str,
}

/// Where a bundle's names come from.
///
/// One exhaustive `match` produces this, and both [`Capability::names`] and
/// [`Capability::grants`] read it — so the two can never disagree about what a
/// bundle contains. Two matches would be two answers.
enum Names {
    /// A fixed list owned here or re-exported from `blue-lang-syntax`.
    Fixed(&'static [&'static str]),
    /// Every `blue_lang_syntax::INFIX` callee, read from the table itself.
    InfixCallees,
}

const CORE_FORM_NAMES: &[&str] = &[
    "define", "defmacro", "lambda", "let", "begin", "if", "cond", "else", "not",
];
const COLLECTION_NAMES: &[&str] = &["list", blue_lang_syntax::LOWERED_MAP];
const INTERPOLATION_NAMES: &[&str] = &[blue_lang_syntax::LOWERED_CONCAT];
const ASSERTION_NAMES: &[&str] = &[blue_lang_syntax::LOWERED_ASSERT];
const MANIFEST_NAMES: &[&str] = &["package", "needs", "posture"];

/// `blue_lang_runtime::sys::install_process`, 2026-08-13.
const PROCESS_NAMES: &[&str] = &[
    "exec_check",
    "exec_ok?",
    "exec_capture",
    "exec_with_stdin",
    "exec_with_env",
    "sh_exec",
];
/// `blue_lang_runtime::sys::install_fs`, 2026-08-13.
const FILESYSTEM_NAMES: &[&str] = &[
    "read_file",
    "write_file",
    "append_file",
    "file_size",
    "file_mtime_ms",
    "is_dir?",
    "is_file?",
    "path_exists",
    "glob",
    "walk_dir",
    "ls",
    "mkdir",
    "mkdir_p",
    "rm",
    "rm_rf",
    "path_join",
    "path_basename",
    "path_dirname",
    "path_extension",
    "cwd",
];
/// `blue_lang_runtime::sys::install_env`, 2026-08-13.
const ENVIRONMENT_NAMES: &[&str] = &["getenv", "env_required", "argv", "argv_get"];
/// `blue_lang_runtime::sys::install_clock`, 2026-08-13.
const CLOCK_NAMES: &[&str] = &[
    "now",
    "now_ms",
    "now_ns",
    "now_rfc3339",
    "sleep",
    "sleep_ms",
    "elapsed_since",
];

impl Capability {
    /// How many capabilities exist. A **floor with a date**: ten as of
    /// 2026-08-13, six pure and four host-effect. Stated so a count gate cannot
    /// pass over an empty set — `ALL.len() == 0` would satisfy every
    /// "for every capability…" test in this file.
    pub const COUNT: usize = 10;

    const FIRST: Self = Capability::CoreForms;

    /// Every capability, **derived from the chain below rather than listed**.
    ///
    /// Same shape as `blue_lang_bidama::quality::Quality::chain` — a hand-listed
    /// `ALL` is a second place a variant can be forgotten, and the forgetting is
    /// silent. This is the *second* use of that shape in the workspace; a third
    /// earns the extraction into a shared macro.
    pub const ALL: [Capability; Self::COUNT] = Self::chain();

    /// The successor in `ALL` order. Exhaustive, no wildcard.
    const fn next(self) -> Option<Self> {
        match self {
            Capability::CoreForms => Some(Capability::Operators),
            Capability::Operators => Some(Capability::Collections),
            Capability::Collections => Some(Capability::Interpolation),
            Capability::Interpolation => Some(Capability::Assertion),
            Capability::Assertion => Some(Capability::ManifestDeclaration),
            Capability::ManifestDeclaration => Some(Capability::Process),
            Capability::Process => Some(Capability::FileSystem),
            Capability::FileSystem => Some(Capability::Environment),
            Capability::Environment => Some(Capability::Clock),
            Capability::Clock => None,
        }
    }

    const fn chain() -> [Capability; Self::COUNT] {
        let mut out = [Self::FIRST; Self::COUNT];
        let mut i = 1;
        while i < Self::COUNT {
            out[i] = match out[i - 1].next() {
                Some(c) => c,
                None => panic!("the `next` chain is shorter than `Capability::COUNT`"),
            };
            i += 1;
        }
        // `.is_none()` rather than `matches!(…, None)`: the sibling this shape
        // was taken from writes the latter and carries a clippy
        // `redundant_pattern_matching` warning for it. Copying a pattern is not
        // a reason to copy its lint.
        assert!(
            out[Self::COUNT - 1].next().is_none(),
            "the `next` chain is longer than `Capability::COUNT` — a capability has no slot in `ALL`"
        );
        out
    }

    /// How the capability reads to an operator. Exhaustive, no wildcard.
    #[must_use]
    pub fn label(self) -> &'static str {
        match self {
            Capability::CoreForms => "core-forms",
            Capability::Operators => "operators",
            Capability::Collections => "collections",
            Capability::Interpolation => "interpolation",
            Capability::Assertion => "assertion",
            Capability::ManifestDeclaration => "manifest-declaration",
            Capability::Process => "process",
            Capability::FileSystem => "filesystem",
            Capability::Environment => "environment",
            Capability::Clock => "clock",
        }
    }

    /// Exhaustive, no wildcard. The single source both [`Self::names`] and
    /// [`Self::grants`] read.
    fn names_source(self) -> Names {
        match self {
            Capability::CoreForms => Names::Fixed(CORE_FORM_NAMES),
            Capability::Operators => Names::InfixCallees,
            Capability::Collections => Names::Fixed(COLLECTION_NAMES),
            Capability::Interpolation => Names::Fixed(INTERPOLATION_NAMES),
            Capability::Assertion => Names::Fixed(ASSERTION_NAMES),
            Capability::ManifestDeclaration => Names::Fixed(MANIFEST_NAMES),
            Capability::Process => Names::Fixed(PROCESS_NAMES),
            Capability::FileSystem => Names::Fixed(FILESYSTEM_NAMES),
            Capability::Environment => Names::Fixed(ENVIRONMENT_NAMES),
            Capability::Clock => Names::Fixed(CLOCK_NAMES),
        }
    }

    /// Every identifier this capability grants the right to name.
    #[must_use]
    pub fn names(self) -> Vec<&'static str> {
        match self.names_source() {
            Names::Fixed(list) => list.to_vec(),
            Names::InfixCallees => blue_lang_syntax::INFIX.iter().map(|i| i.callee).collect(),
        }
    }

    /// Does this capability grant the right to name `name`?
    #[must_use]
    pub fn grants(self, name: &str) -> bool {
        match self.names_source() {
            Names::Fixed(list) => list.contains(&name),
            Names::InfixCallees => blue_lang_syntax::INFIX.iter().any(|i| i.callee == name),
        }
    }

    /// **The lowering.** The import a module minted from a frame granting this
    /// capability must carry — and `None` for a capability that reaches no
    /// host, which is not a placeholder but the answer: there is nothing to
    /// import for arithmetic.
    ///
    /// Exhaustive, no wildcard, and this is the arm the design turns on. A new
    /// capability landing with no import decision is `E0004` here — the
    /// mechanism that makes the table *derived* rather than *maintained*.
    #[must_use]
    pub fn import(self) -> Option<Import> {
        match self {
            Capability::CoreForms
            | Capability::Operators
            | Capability::Collections
            | Capability::Interpolation
            | Capability::Assertion
            | Capability::ManifestDeclaration => None,
            Capability::Process => Some(Import {
                module: HOST_MODULE,
                field: "process",
            }),
            Capability::FileSystem => Some(Import {
                module: HOST_MODULE,
                field: "fs",
            }),
            Capability::Environment => Some(Import {
                module: HOST_MODULE,
                field: "env",
            }),
            Capability::Clock => Some(Import {
                module: HOST_MODULE,
                field: "clock",
            }),
        }
    }

    /// Does naming anything in this bundle reach outside the module?
    ///
    /// **Defined as "has an import", never as a second list.** The two facts
    /// are the same fact — the absence of the import *is* the enforcement — so
    /// giving them separate definitions would be giving them room to disagree.
    #[must_use]
    pub fn is_host_effect(self) -> bool {
        self.import().is_some()
    }

    /// Every host-effect capability, in [`Self::ALL`] order.
    #[must_use]
    pub fn host_effects() -> Vec<Capability> {
        Self::ALL
            .into_iter()
            .filter(|c| c.is_host_effect())
            .collect()
    }
}

impl Reach {
    /// Does this reach grant `cap`?
    ///
    /// The capability-level question, beside `permits`'s name-level one.
    #[must_use]
    pub fn grants(&self, cap: Capability) -> bool {
        match self {
            Reach::Unrestricted => true,
            Reach::Only(caps) => caps.contains(&cap),
        }
    }

    /// Does this reach grant anything that reaches outside the module?
    ///
    /// **Replaces the `IO_CAPABILITY` string probe.** `blue-lang-bidama` used
    /// to ask `reach.permits("io")` — a name no blue program can bind and no
    /// frame in the workspace granted except by being `Unrestricted`. Its own
    /// doc called that the model's one measured incompleteness and said the fix
    /// needed a closed capability universe blue did not have. It has one now.
    #[must_use]
    pub fn grants_any_host_effect(&self) -> bool {
        match self {
            Reach::Unrestricted => true,
            Reach::Only(caps) => caps.iter().any(|c| c.is_host_effect()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    /// **The floor, with the date.** Ten capabilities on 2026-08-13, six pure
    /// and four host-effect.
    ///
    /// Anti-vacuity for every "for every capability…" test below: each of them
    /// passes trivially over an empty `ALL`, and `ALL` is *derived* from the
    /// `next` chain, so a mis-edited chain could shrink it without any other
    /// test noticing.
    #[test]
    fn the_universe_is_closed_and_counted() {
        assert_eq!(Capability::ALL.len(), Capability::COUNT);
        assert_eq!(Capability::COUNT, 10, "the floor, measured 2026-08-13");
        assert_eq!(
            Capability::host_effects().len(),
            4,
            "process, filesystem, environment, clock"
        );
        assert_eq!(
            Capability::ALL
                .into_iter()
                .filter(|c| !c.is_host_effect())
                .count(),
            6
        );
    }

    /// `ALL` really enumerates distinct capabilities — a chain that revisited a
    /// variant would still have the right length.
    #[test]
    fn the_chain_visits_every_capability_exactly_once() {
        let seen: BTreeSet<Capability> = Capability::ALL.into_iter().collect();
        assert_eq!(seen.len(), Capability::COUNT);
    }

    /// **An empty bundle grants nothing while reading as a grant** — the same
    /// failure mode as the misspelled string this type replaced, one level up.
    #[test]
    fn no_capability_is_an_empty_bundle() {
        for c in Capability::ALL {
            assert!(
                !c.names().is_empty(),
                "{} grants no names at all",
                c.label()
            );
        }
    }

    /// Two bundles claiming one name would make [`imports_of`] ambiguous about
    /// which capability a program's use of that name needs.
    #[test]
    fn no_two_capabilities_grant_the_same_name() {
        let mut owner: std::collections::BTreeMap<&str, Capability> = Default::default();
        for c in Capability::ALL {
            for n in c.names() {
                if let Some(prev) = owner.insert(n, c) {
                    panic!(
                        "`{n}` is granted by both {} and {}",
                        prev.label(),
                        c.label()
                    );
                }
            }
        }
        // The floor: 66 distinct names on 2026-08-13.
        assert!(
            owner.len() >= 66,
            "the universe shrank to {} names",
            owner.len()
        );
    }

    /// `grants` and `names` must answer the same question — they read one
    /// source, and this is the test that the plumbing is actually shared.
    #[test]
    fn grants_agrees_with_names() {
        for c in Capability::ALL {
            for n in c.names() {
                assert!(
                    c.grants(n),
                    "{} names `{n}` but does not grant it",
                    c.label()
                );
            }
            assert!(!c.grants("no-such-name-anywhere"), "{}", c.label());
        }
    }

    /// The operator bundle is **read from `INFIX`**, not copied out of it.
    ///
    /// The gate that matters: if someone adds a row to the operator table, this
    /// bundle grows with it and no edit is needed here. Compared against the
    /// table itself rather than a number, so it cannot be satisfied by a stale
    /// count.
    #[test]
    fn the_operator_bundle_is_the_infix_table() {
        let from_table: BTreeSet<&str> = blue_lang_syntax::INFIX.iter().map(|i| i.callee).collect();
        let from_bundle: BTreeSet<&str> = Capability::Operators.names().into_iter().collect();
        assert_eq!(from_bundle, from_table);
        assert!(
            from_table.len() >= 13,
            "the INFIX table shrank to {}",
            from_table.len()
        );
    }

    /// Every name blue's parser lowers to is nameable by *some* capability.
    ///
    /// Otherwise a frame could never permit a program that uses string
    /// interpolation or a map literal: the program would escape its own frame
    /// on a name it never wrote. Read from the parser's constants, so a
    /// changed lowering fails here rather than at run time.
    #[test]
    fn every_lowered_name_is_claimed_by_some_capability() {
        for lowered in [
            blue_lang_syntax::LOWERED_ASSERT,
            blue_lang_syntax::LOWERED_MAP,
            blue_lang_syntax::LOWERED_CONCAT,
        ] {
            assert!(
                Capability::ALL.into_iter().any(|c| c.grants(lowered)),
                "blue lowers to `{lowered}` and no capability grants it"
            );
        }
    }

    /// Host-ness and having an import are one fact, and each host capability
    /// gets its **own** field — two capabilities sharing an import would make
    /// the table lose one of them.
    #[test]
    fn every_host_capability_has_a_distinct_import() {
        let fields: BTreeSet<&str> = Capability::host_effects()
            .into_iter()
            .map(|c| c.import().expect("a host effect has an import").field)
            .collect();
        assert_eq!(fields.len(), Capability::host_effects().len());
        for c in Capability::ALL {
            assert_eq!(c.is_host_effect(), c.import().is_some(), "{}", c.label());
            if let Some(i) = c.import() {
                assert_eq!(i.module, HOST_MODULE, "{}", c.label());
            }
        }
    }

    /// Labels are how an operator reads a frame; two capabilities with one
    /// label would print a frame nobody can act on.
    #[test]
    fn labels_are_distinct() {
        let labels: BTreeSet<&str> = Capability::ALL.into_iter().map(Capability::label).collect();
        assert_eq!(labels.len(), Capability::COUNT);
    }

    // ── RED RUNS, recorded ────────────────────────────────────────────────
    //
    // 1. **A misspelled capability does not type-check.**
    //    `Reach::only(["read-flie"])` was legal before M0. Verified 2026-08-13
    //    by adding exactly that line to `imports::tests`:
    //
    //        error[E0271]: type mismatch resolving
    //          `<[&str; 1] as IntoIterator>::Item == Capability`
    //          expected `Capability`, found `&str`
    //
    //    There is no runtime test for this and there cannot be one: the failure
    //    is the absence of a constructor, not a rejected value. The same error
    //    appeared unprompted at four call sites in `blue-lang-bidama` during the
    //    migration, which is the same evidence from a direction nobody staged.
    //    Reverted.
    //
    // 2. **A capability without an import lowering fails the build.** Verified
    //    2026-08-13: adding `Capability::RandomBytes` to the enum and nothing
    //    else produced `E0004: non-exhaustive patterns: `Capability::RandomBytes`
    //    not covered` at FOUR sites — `next` (:235), `label` (:273),
    //    `names_source` (:290) and `import` (:332) — so the variant cannot reach
    //    `imports_of` without a decision having been made about it. Reverted.
    //
    // 3. **The chain is not decorative.** Verified 2026-08-13: changing the
    //    `Capability::Environment => Some(Capability::Clock)` row to `None`
    //    failed the `const` evaluation of `chain()` —
    //    `error[E0080]: evaluation panicked: the `next` chain is shorter than
    //    `Capability::COUNT`` — at compile time, not in a test. Reverted.
    //
    // Red runs 4–5 (the derivation) are recorded in `crate::imports`; 6–9 (the
    // pure/host classification, checked against a real interpreter) in
    // `blue-lang-cli`'s `tests/capability_surface.rs`.
}
