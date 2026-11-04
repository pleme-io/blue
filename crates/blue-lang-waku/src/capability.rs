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
//! `Other(String)` arm, and the type and every reading of it are generated from
//! one table, each reading an exhaustive `match`. A capability is one row, and a
//! row cannot omit its label, import, names, implications or providers. The pure
//! rows come first, so [`crate::imports_of`] emits a stable table.
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
//! | [`Capability::Assertion`] | `blue_lang_syntax::LOWERED_ASSERT`, `LOWERED_ASSERT_PANICS` |
//! | [`Capability::CoreForms`] | the heads `blue-lang-syntax` lowers control flow to |
//! | [`Capability::ManifestDeclaration`] | the Bluefile vocabulary (`blue_lang_pkg::bluefile`'s word table) |
//! | the host bundles | `blue_lang_runtime::sys`'s four installers, `net`'s, `entropy`'s, `wire`'s, `threshold`'s, `storage`'s, `audio`'s and `display`'s |
//!
//! The last row is the one that could rot, and it is gated rather than trusted:
//! `blue-lang-cli`'s `tests/capability_surface.rs` installs the sys layer into a
//! bare interpreter, diffs the reserved names, and fails if a single one is
//! unclaimed or mis-claimed. That is independent evidence — a real interpreter
//! resolving a symbol — not this file checking itself.

use crate::Reach;

macro_rules! capability_table {
    (
        pure { $( $(#[$pure_meta:meta])* $pure:ident $pure_label:literal => $pure_names:expr; )+ }
        host { $( $(#[$host_meta:meta])* $host:ident $host_label:literal import $field:literal => $host_names:expr, implies [$($implied:ident),*], providers [$($provider:literal),*]; )+ }
    ) => {
        /// One thing a frame may grant the right to **name**.
        ///
        /// **Closed by construction.** There is no `Other(String)`, and there will not
        /// be one: the arm would restore every property this type exists to remove.
        #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
        pub enum Capability {
            $( $(#[$pure_meta])* $pure, )+
            $( $(#[$host_meta])* $host, )+
        }

        impl Capability {
            /// How many capabilities the table holds.
            pub const COUNT: usize = Self::ALL.len();

            /// Every capability, in table order.
            pub const ALL: [Capability; [$(stringify!($pure),)+ $(stringify!($host),)+].len()] =
                [$(Capability::$pure,)+ $(Capability::$host,)+];

            /// Every host capability's label, in table order.
            pub const HOST_LABELS: &'static [&'static str] = &[$($host_label,)+];

            /// How the capability reads to an operator.
            #[must_use]
            pub fn label(self) -> &'static str {
                match self {
                    $(Capability::$pure => $pure_label,)+
                    $(Capability::$host => $host_label,)+
                }
            }

            fn names_source(self) -> Names {
                match self {
                    $(Capability::$pure => $pure_names,)+
                    $(Capability::$host => Names::Fixed($host_names),)+
                }
            }

            /// **The lowering.** The import a module minted from a frame granting this
            /// capability must carry, and `None` for a capability that reaches no host:
            /// there is nothing to import for arithmetic.
            #[must_use]
            pub fn import(self) -> Option<Import> {
                match self {
                    $(Capability::$pure => None,)+
                    $(Capability::$host => Some(Import { module: HOST_MODULE, field: $field }),)+
                }
            }

            /// The capabilities a grant of this one holds as well.
            #[must_use]
            pub fn implied(self) -> &'static [Capability] {
                match self {
                    $(Capability::$pure => &[],)+
                    $(Capability::$host => &[$(Capability::$implied),*],)+
                }
            }

            /// The providers this capability can be bound to; empty for one blue
            /// cannot provide without the host.
            #[must_use]
            pub fn provider_kinds(self) -> &'static [&'static str] {
                match self {
                    $(Capability::$pure => &[],)+
                    $(Capability::$host => &[$($provider),*],)+
                }
            }
        }
    };
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
const INTERPOLATION_NAMES: &[&str] = &[
    blue_lang_syntax::LOWERED_CONCAT,
    "join_lines",
    "unlines",
    "line_break",
];
const ASSERTION_NAMES: &[&str] = &[
    blue_lang_syntax::LOWERED_ASSERT,
    blue_lang_syntax::LOWERED_ASSERT_PANICS,
];
/// The Bluefile vocabulary. `blue_lang_pkg::bluefile`'s word table records
/// each of these, and `the_word_table_is_the_manifest_capability` there fails
/// when the two disagree — a name here with no recorder would pass the frame
/// and die unbound; a recorder with no name here could never be reached.
const MANIFEST_NAMES: &[&str] = &[
    "package",
    "needs",
    "posture",
    "source",
    "packages",
    "run",
    "tool",
    "check",
    "app",
    "catalog",
    "generate",
    "image",
    "workload",
    "rule",
    "service",
    "frontend",
    "vm_check",
    "registry",
    "receipt",
    "query",
    "reach",
    "allow",
    "virtualize",
    "floors",
    "bounds",
];

/// `blue_lang_runtime::sys::install_process`, 2026-08-13.
const PROCESS_NAMES: &[&str] = &[
    "exec_check",
    "exec_ok?",
    "exec_capture",
    "exec_with_stdin",
    "exec_exchange",
    "exec_with_env",
    "exec_into",
    "exit_with",
    "sh_exec",
];
/// `blue_lang_runtime::sys::install_fs`, 2026-08-13.
const FILESYSTEM_NAMES: &[&str] = &[
    "read_file",
    "read_bytes",
    "read_u32s",
    "write_file",
    "write_bytes",
    "write_program",
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
    "rename_file",
    "rm_rf",
    "path_join",
    "path_basename",
    "path_dirname",
    "path_extension",
    "cwd",
];
/// `blue_lang_runtime::sys::install_env`, 2026-08-13.
const ENVIRONMENT_NAMES: &[&str] = &["getenv", "env_required", "argv", "argv_get", "self_exe"];
/// `blue_lang_runtime::net::install_net`, 2026-10-27.
const NETWORK_NAMES: &[&str] = &[
    "nats_connect",
    "nats_publish",
    "nats_request",
    "nats_subscribe",
    "nats_next_message",
    "nats_unsubscribe",
    "nats_close",
    "nats_inbox",
    "http_request",
    "tcp_connect_ms",
    "http_listen",
    "http_listener_port",
    "http_next_request",
    "http_respond",
    "pg_connect",
    "pg_query",
    "pg_execute",
    "pg_close",
    "resp_connect",
    "resp_command",
    "resp_pipeline",
    "resp_next",
    "resp_close",
];
const ENTROPY_NAMES: &[&str] = &["random_bytes"];
const COMM_FLASH_NAMES: &[&str] = &[
    "flash_open",
    "flash_put",
    "flash_next",
    "flash_stats",
    "flash_close",
];
const COMM_SCAVENGER_NAMES: &[&str] = &[
    "tide_open",
    "tide_put",
    "tide_release",
    "tide_send",
    "tide_next",
    "tide_stats",
    "tide_close",
    "evict",
    "accept",
];
const MPC_THRESHOLD_NAMES: &[&str] = &[
    "threshold_deal",
    "threshold_dkg_start",
    "threshold_dkg_exchange",
    "threshold_dkg_finish",
    "threshold_commit",
    "threshold_sign",
    "threshold_aggregate",
    "threshold_share_export",
    "threshold_share_import",
];
const STORAGE_APPEND_NAMES: &[&str] = &["append_log", "read_log"];
const AUDIO_OUT_NAMES: &[&str] = &["play_audio", "audio_out_format"];
const AUDIO_IN_NAMES: &[&str] = &["capture_audio", "audio_in_format"];
const DISPLAY_NAMES: &[&str] = &[
    "canvas_open",
    "canvas_clear",
    "canvas_fill_rect",
    "canvas_text",
    "canvas_present",
    "canvas_pixel",
    "canvas_close",
];
const KERNEL_BPF_NAMES: &[&str] = &[
    "bpf_syscall",
    "perf_event_open",
    "fd_open",
    "fd_ioctl",
    "fd_close",
    "fd_number",
    "ringbuf_open",
    "ringbuf_next",
];
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

capability_table! {
    pure {
        /// The heads blue lowers control flow to.
        ///
        /// These are `match` arms in tatara's evaluator rather than bindings, so
        /// omitting one would not actually withhold it — they are here because
        /// `check_reach` reports a head like any other symbol and the frame has to
        /// answer. See `crate::walk_binder`'s note on why that question is left
        /// open there.
        CoreForms "core-forms" => Names::Fixed(CORE_FORM_NAMES);
        /// Every callee in `blue_lang_syntax::INFIX`, **read from that table**.
        ///
        /// The repo's rule is that `INFIX` is one table and both directions read
        /// it. A hand-copied operator list here would be the third copy that
        /// disagreed — which is exactly how `==` shipped with a precedence and no
        /// callee.
        Operators "operators" => Names::InfixCallees;
        /// The pure aggregate constructors: the list constructor and the callee a
        /// `{...}` literal lowers to.
        Collections "collections" => Names::Fixed(COLLECTION_NAMES);
        /// The callee string interpolation lowers to.
        Interpolation "interpolation" => Names::Fixed(INTERPOLATION_NAMES);
        /// The callee `assert e` lowers to.
        ///
        /// Blue **owns** this name rather than delegating it — the runtime must not
        /// bind it, which `blue-lang-test`'s `no_lowered_name_is_shadowed_by_the_runtime`
        /// gates. Granting it is granting the right to *name* it, which is a
        /// different question from who defines it.
        Assertion "assertion" => Names::Fixed(ASSERTION_NAMES);
        /// The words a Bluefile is *for* — the project facts a manifest records.
        ///
        /// `package`/`needs`/`posture` since the Bluefile landed; `source`,
        /// `packages`, `run`, `tool`, `check`, `app` and `catalog` since
        /// `theory/BLUE-STRUCTURE.md` P1b (2026-09-23), so a project states every
        /// fact its build needs without writing nix. Each name has exactly one
        /// recorder in `blue_lang_pkg::bluefile`, and a gate there fails if the
        /// two lists disagree in either direction.
        ManifestDeclaration "manifest-declaration" => Names::Fixed(MANIFEST_NAMES);
    }
    host {
        /// Running another program. `blue_lang_runtime::sys::install_process`.
        ///
        /// Note for whoever wires the engine border (M2): **WASI has no subprocess
        /// spawn at any preview level**, so this capability has no WASI lowering to
        /// inherit. Its import is blue's own, which is why [`HOST_MODULE`] is a blue
        /// module name and not `wasi_snapshot_preview1`.
        Process "process" import "process" => PROCESS_NAMES, implies [], providers [];
        /// The filesystem. `blue_lang_runtime::sys::install_fs`.
        ///
        /// At the granularity the runtime itself groups. Four of its names
        /// (`path_join`, `path_basename`, `path_dirname`, `path_extension`) are
        /// pure string arithmetic that happens to live in the fs installer — they
        /// are host-gated in blue's actual build, so classifying them here is what
        /// is true rather than what is tidy. Splitting read from write is a later
        /// variant, and adding one is safe precisely because of the `E0004`.
        FileSystem "filesystem" import "fs" => FILESYSTEM_NAMES, implies [StorageAppend], providers ["in_memory_overlay", "null_sink"];
        /// The environment and the argument vector. `…::install_env`.
        Environment "environment" import "env" => ENVIRONMENT_NAMES, implies [], providers [];
        /// Time and sleeping. `…::install_clock`.
        Clock "clock" import "clock" => CLOCK_NAMES, implies [], providers ["deterministic_stepped"];
        /// Sockets: NATS and HTTP over TCP. `blue_lang_runtime::net::install_net`,
        /// called from the sys installer.
        ///
        /// Distinct from [`Capability::Process`] and [`Capability::FileSystem`]
        /// because a frame that may read files has not thereby been allowed to
        /// reach another machine.
        Network "network" import "net" => NETWORK_NAMES, implies [], providers [];
        Entropy "entropy" import "entropy" => ENTROPY_NAMES, implies [], providers ["seeded_prng"];
        CommFlash "comm-flash" import "comm-flash" => COMM_FLASH_NAMES, implies [], providers ["loopback"];
        CommScavenger "comm-scavenger" import "comm-scavenger" => COMM_SCAVENGER_NAMES, implies [], providers ["loopback"];
        MpcThreshold "mpc-threshold" import "mpc-threshold" => MPC_THRESHOLD_NAMES, implies [], providers ["seeded"];
        StorageAppend "storage-append" import "storage-append" => STORAGE_APPEND_NAMES, implies [], providers ["in_memory"];
        AudioOut "audio-out" import "audio-out" => AUDIO_OUT_NAMES, implies [], providers ["recording_sink"];
        AudioIn "audio-in" import "audio-in" => AUDIO_IN_NAMES, implies [], providers ["seeded_noise", "monitor"];
        Display "display" import "display" => DISPLAY_NAMES, implies [], providers ["framebuffer"];
        KernelBpf "kernel-bpf" import "kernel-bpf" => KERNEL_BPF_NAMES, implies [], providers [];
    }
}

impl Capability {
    #[must_use]
    pub fn host_named(name: &str) -> Option<Capability> {
        let name = name.trim_start_matches(':');
        Self::host_effects()
            .into_iter()
            .find(|c| c.label() == name || c.label().replace('-', "_") == name)
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
    pub fn closed(&self) -> Reach {
        match self {
            Reach::Unrestricted => Reach::Unrestricted,
            Reach::Only(caps) => {
                let mut out = caps.clone();
                let mut todo: Vec<Capability> = caps.iter().copied().collect();
                while let Some(c) = todo.pop() {
                    for i in c.implied() {
                        if out.insert(*i) {
                            todo.push(*i);
                        }
                    }
                }
                Reach::Only(out)
            }
        }
    }

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

    /// Anti-vacuity for every "for every capability…" test below, each of which
    /// passes trivially over an empty `ALL`. Floors, so a new row needs no edit
    /// here; the pure and host parts add up, and the labels are the table's.
    #[test]
    fn the_universe_is_closed_and_counted() {
        assert_eq!(Capability::ALL.len(), Capability::COUNT);
        let host = Capability::host_effects();
        assert!(host.len() >= 14, "the host rows shrank to {}", host.len());
        let pure = Capability::ALL
            .into_iter()
            .filter(|c| !c.is_host_effect())
            .count();
        assert!(pure >= 6, "the pure rows shrank to {pure}");
        assert_eq!(pure + host.len(), Capability::COUNT);
        let labels: Vec<&str> = host.iter().map(|c| c.label()).collect();
        assert_eq!(labels, Capability::HOST_LABELS);
        assert!(
            Capability::ALL
                .into_iter()
                .take(pure)
                .all(|c| !c.is_host_effect()),
            "the pure rows come first, so an import table stays stable"
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
        // The floor: 107 distinct names on 2026-10-31, the four audio and
        // seven canvas words past the 96 of the log words (94 with the
        // threshold words; 85 on 2026-10-30; 73 on 2026-09-23, plus the
        // twelve wire words; 66 on 2026-08-13, plus the seven Bluefile words
        // P1b added).
        assert!(
            owner.len() >= 107,
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
            blue_lang_syntax::LOWERED_ASSERT_PANICS,
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

    #[test]
    fn a_host_capability_is_named_by_its_label_or_its_snake_case() {
        for c in Capability::host_effects() {
            assert_eq!(Capability::host_named(c.label()), Some(c));
            assert_eq!(
                Capability::host_named(&format!(":{}", c.label().replace('-', "_"))),
                Some(c)
            );
        }
        assert_eq!(
            Capability::host_named("comm_flash"),
            Some(Capability::CommFlash)
        );
        assert_eq!(
            Capability::host_named("comm-scavenger"),
            Some(Capability::CommScavenger)
        );
        assert_eq!(
            Capability::host_named(":mpc_threshold"),
            Some(Capability::MpcThreshold)
        );
        assert_eq!(
            Capability::host_named("mpc-threshold"),
            Some(Capability::MpcThreshold)
        );
        assert_eq!(
            Capability::host_named(":storage_append"),
            Some(Capability::StorageAppend)
        );
        assert_eq!(
            Capability::host_named("storage-append"),
            Some(Capability::StorageAppend)
        );
        assert_eq!(Capability::host_named("storage"), None);
        assert_eq!(Capability::host_named("append"), None);
        assert_eq!(
            Capability::host_named(":audio_out"),
            Some(Capability::AudioOut)
        );
        assert_eq!(
            Capability::host_named("audio-in"),
            Some(Capability::AudioIn)
        );
        assert_eq!(
            Capability::host_named(":display"),
            Some(Capability::Display)
        );
        assert_eq!(Capability::host_named("audio"), None);
        assert_eq!(Capability::host_named("speaker"), None);
        assert_eq!(Capability::host_named("gpu"), None);
        assert_eq!(Capability::host_named("canvas"), None);
        assert_eq!(Capability::host_named("mpc"), None);
        assert_eq!(Capability::host_named("threshold"), None);
        assert_eq!(Capability::host_named("core-forms"), None);
        assert_eq!(Capability::host_named("comm"), None);
        assert_eq!(Capability::host_named("comm_tide"), None);
    }

    #[test]
    fn a_grant_of_the_filesystem_holds_the_append_only_store_and_never_the_reverse() {
        let fs = Reach::only([Capability::FileSystem]).closed();
        assert!(fs.grants(Capability::StorageAppend));
        assert!(fs.permits("append_log") && fs.permits("read_log"));
        let log = Reach::only([Capability::StorageAppend]).closed();
        assert_eq!(log, Reach::only([Capability::StorageAppend]));
        for name in ["write_file", "rm", "rm_rf", "rename_file", "append_file"] {
            assert!(!log.permits(name), "{name}");
        }
        assert!(log.leq(&fs) && !fs.leq(&log));
        assert_eq!(fs.meet(&log), log);
        assert_eq!(Reach::Unrestricted.closed(), Reach::Unrestricted);
        assert_eq!(Reach::nothing().closed(), Reach::nothing());
        for c in Capability::ALL {
            let once = Reach::only([c]).closed();
            assert_eq!(once.closed(), once, "{}", c.label());
            for i in c.implied() {
                assert!(i.is_host_effect() && c.is_host_effect(), "{}", c.label());
                assert_ne!(*i, c, "{}", c.label());
                assert!(!i.implied().contains(&c), "{}", c.label());
            }
        }
    }

    // ── RED RUNS, recorded ────────────────────────────────────────────────
    //
    // 1. **A misspelled capability does not type-check.**
    //    `Reach::only(["read-flie"])` was legal before M0. Verified 2026-08-13
    //    by adding exactly that line to `imports::tests`: `E0271`, expected
    //    `Capability`, found `&str`. Reverted.
    //
    // 2. **A row cannot omit a decision.** Verified 2026-11-04: a host row with
    //    no `import` fails the table's macro at compile time with no rule
    //    expected; a variant with no row does not exist. Reverted.
    //
    // Red runs 4–5 (the derivation) are recorded in `crate::imports`; 6–9 (the
    // pure/host classification, checked against a real interpreter) in
    // `blue-lang-cli`'s `tests/capability_surface.rs`.
}
