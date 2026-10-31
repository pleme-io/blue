//! The blue runtime — **one** definition of what a blue program runs against.
//!
//! Before this crate existed, every consumer hand-rolled its own
//! `Interpreter::new()` + `install_primitives(...)` pair — three of them, in
//! three crates — and they had silently drifted: none of them loaded the Lisp
//! stdlib. So `6 % 3` lowered correctly to `(mod 6 3)`, `mod` was genuinely
//! defined, and the program still died with `unbound symbol: mod`, because
//! the definition lived in a stdlib nobody loaded.
//!
//! That is the duplication tax in its usual shape: the bug is not in any one
//! copy, it is in there *being* copies. One function now owns the answer.
//!
//! ## Layers
//!
//! A blue interpreter is built in two layers, and both are required:
//!
//! 1. **Rust primitives** — arithmetic, comparison, list ops, I/O.
//! 2. **The full tatara stdlib** — primitives, higher-order functions
//!    (`map`/`filter`/`fold`), maps, channels, fibers, type-check, and
//!    everything tatara defines in tatara-lisp itself
//!    (`mod`, `rem`, `first`, `inc`, `even?`, the actor and transducer
//!    helpers, …). Loading it is not optional garnish: blue's own operator
//!    lowering depends on it.
//! 3. **blue's own core** ([`stdlib`]) — strings and number conversion, which
//!    tatara-lisp does not have in any form. A Ruby-surface language without
//!    `length` or `upcase` is not usable, and the semantics are Ruby's
//!    (characters, not bytes), which is why they are blue's and not the
//!    substrate's.
//! 4. **JSON** ([`json`]) and **cryptography** ([`crypto`]) — pure
//!    computation, installed unconditionally, so the wasm consumer keeps them.
//! 5. **The host layer** (`sys`, behind the `sys` feature) — every name in it
//!    is a host import.
//! 6. **Processes** ([`attach_node`]) — `spawn`, `send`, `receive` and the
//!    rest of `blue_lang_proc::node`'s words, bound to a node of the
//!    interpreter's own, so the program is that node's root process.

pub mod alloc;
pub mod collection;
pub mod crypto;
pub mod dispatch;
pub mod doc_sources;
pub mod docs;
pub mod domain;
#[cfg(feature = "sys")]
pub mod entropy;
pub mod erase;
pub mod errors;
pub mod host_surface;
pub mod hosted;
pub mod inputs;
pub mod json;
pub mod literal;
pub mod memory;
pub mod messages;
#[cfg(feature = "sys")]
pub mod net;
pub mod nix;
pub mod observe;
pub mod paths;
pub mod pipeline;
pub mod project_rules;
#[cfg(feature = "sys")]
pub mod provide;
pub mod receipt;
pub mod session;
pub mod spread;
pub mod stdlib;
#[cfg(feature = "sys")]
pub mod sys;
pub mod timings;
pub mod uses;
pub mod xml;

pub use erase::{erase_types, to_sexps};
pub use inputs::{declarations, install_input_primitives, Declaration, InputError, Inputs};
pub use pipeline::{
    parse, parse_tree_with_depth, parse_with_depth, run, run_with_inputs, Run, RunError,
};
pub use stdlib::install_blue_stdlib;

pub use blue_lang_proc::{Frame, HostIo, Identities, Places, Receipt};

use tatara_lisp_eval::{install_full_stdlib_with, Interpreter};

/// Build an interpreter with the complete blue runtime installed.
///
/// This is the *only* sanctioned way to obtain one. A caller that builds an
/// `Interpreter` directly gets a partial runtime, and the failure shows up as
/// an unbound symbol at the far end of a program.
pub fn interpreter<H: 'static>(host: &mut H) -> Interpreter<H> {
    let mut interp = Interpreter::new();
    // The FULL substrate, not just `install_primitives`.
    //
    // blue called `install_primitives` + `install_lisp_stdlib_with` and got
    // neither `install_hof` nor `install_map` — so `map`, `filter`, `fold` and
    // every map literal were UNBOUND SYMBOLS. A language with no higher-order
    // functions, in a workspace whose whole surface is Ruby's.
    //
    // Same shape as the stdlib gap this crate was created to fix: the substrate
    // has layers, and naming them one at a time is how one gets missed. Call
    // the composed installer.
    install_full_stdlib_with(&mut interp, host);
    // Layer 3: blue's own core — strings and number conversion, which
    // tatara-lisp does not carry at all. See `stdlib` for why the
    // character-counting semantics are blue's rather than the substrate's.
    stdlib::install_blue_stdlib(&mut interp);
    // Layer 4: blue's JSON surface — parse, stringify, read. Pure
    // computation, no host imports, so it is installed unconditionally; the
    // `wasm32-unknown-unknown` consumer keeps it. See `json` for why objects
    // arrive as alists rather than Maps.
    json::install_json_stdlib(&mut interp);
    // Layer 4b: cryptography — BLAKE3 and Ed25519. Pure for the same reason
    // JSON is: a deterministic function of its arguments, with the keypair's
    // seed supplied by the caller rather than drawn from an entropy source,
    // so it lowers to no import and the wasm consumer keeps it. See `crypto`.
    crypto::install_crypto_stdlib(&mut interp);
    nix::install_nix_stdlib(&mut interp);
    xml::install_xml_stdlib(&mut interp);
    // Layer 5: the host-side system surface — process, filesystem, env,
    // clock, network. Feature-gated: every sys primitive is a host import, so the
    // wasm consumer (which builds with `sys` OFF) keeps its zero-host-import
    // surface by construction. Only the CLI turns it on.
    #[cfg(feature = "sys")]
    sys::install_sys_stdlib(&mut interp);
    // Layer 6: processes. Bound here so every name oracle built from this
    // interpreter (the check stage, the LSP, `blue reference`) knows them.
    attach_node(&mut interp);
    // Last, so installing the stdlib is not metered against the program.
    apply_execution_bounds(&mut interp);
    interp
}

/// Give `interp` a process node of its own: its program becomes the node's
/// root, and `spawn` starts processes in this node and no other.
///
/// [`interpreter_hostless`] calls it on every fork, so two programs never
/// share processes. A door that forks an interpreter per unit of work (a test
/// per fork) calls it on each fork for the same reason.
pub fn attach_node<H: 'static>(interp: &mut Interpreter<H>) {
    dispatch::install(interp);
    blue_lang_proc::install(interp, blue_lang_proc::Node::new(node_config()));
}

/// [`attach_node`] for a program that runs under `frame`: every process it
/// starts is held to the same frame, so a host name the program may not call
/// is refused in its children too. Without this a spawned child would run on
/// the full runtime and a frame would be one `spawn` away from meaningless.
pub fn attach_node_in_frame<H: 'static>(interp: &mut Interpreter<H>, frame: &blue_lang_waku::Waku) {
    attach_node_held(interp, &Hold::from(frame.clone()));
}

/// [`attach_node_in_frame`] with the hold's providers bound in every child.
pub fn attach_node_held<H: 'static>(interp: &mut Interpreter<H>, hold: &Hold) {
    attach_node_accounted(interp, Some(hold), &Account::default());
}

/// Give `interp` a node whose processes are held to `hold`, when there is
/// one, and give `account` of them: each child's host calls tally into its
/// ledger, its identities name each trace's and receipt's definition, and
/// with a receipts directory every held process writes a receipt there when
/// an incarnation ends.
pub fn attach_node_accounted<H: 'static>(
    interp: &mut Interpreter<H>,
    hold: Option<&Hold>,
    account: &Account,
) {
    let mut config = node_config();
    config.host_io = account.host_io.clone();
    config.identities = account.identities.clone();
    config.places = account.places.clone();
    if let Some(hold) = hold {
        config.frame = Some(hold.frame());
        config.receipts = account.receipts.clone().map(receipt::sink);
        let held = hold.clone();
        let io = account.host_io.clone();
        config.child = std::sync::Arc::new(move || {
            let mut child = child_interpreter();
            held.bind(&mut child, "this process's frame", &io);
            child
        });
    }
    dispatch::install(interp);
    blue_lang_proc::install(interp, blue_lang_proc::Node::new(config));
}

/// The account a run gives of itself besides its value, filled while it runs
/// and read after it ends, whether it returned or raised.
#[derive(Clone, Default)]
pub struct Account {
    /// Host calls through granted host names, per process.
    pub host_io: HostIo,
    /// Each definition's `def_hash`, and the run's under [`receipt::RUN`].
    pub identities: Identities,
    /// How the identities are computed from the program, once it is lowered.
    /// Without one, no trace or receipt names a `def_hash`, and no trace
    /// names the file, line and column of a breaching call.
    pub identify: Option<Identify>,
    /// Each definition's file, read from the program when it identifies.
    pub places: Places,
    /// Where each held process writes its receipt; none are written without.
    pub receipts: Option<std::path::PathBuf>,
}

/// The table of a lowered program's identities, computed when first asked.
pub type Identified =
    Box<dyn FnOnce() -> std::collections::BTreeMap<String, String> + Send + 'static>;

/// Given a checked program, its lowered tree and the key of the entry's
/// `main` if it has one: each definition key with its `def_hash`, and
/// [`receipt::RUN`] with the run's, computed only when first asked.
/// `blue-lang-mondou` computes it; this crate only calls it.
pub type Identify = fn(
    &uses::ResolvedProgram,
    std::sync::Arc<Vec<tatara_lisp::Spanned>>,
    Option<String>,
) -> Identified;

/// What a run is held to: the frame it may reach the host through, and the
/// capabilities pure providers stand in for.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hold {
    pub frame: blue_lang_waku::Waku,
    pub provisions: blue_lang_waku::Provisions,
}

impl From<blue_lang_waku::Waku> for Hold {
    fn from(frame: blue_lang_waku::Waku) -> Self {
        Self {
            frame,
            provisions: blue_lang_waku::Provisions::default(),
        }
    }
}

/// The name a scoped provider binds the host name `word` under. No blue
/// source can write it, so only the references [`Hold::rebind_scoped`] moves
/// onto it reach the provider.
#[must_use]
pub fn provided_name(word: &str) -> String {
    format!("%provided/{word}")
}

impl Hold {
    /// Every host capability neither the frame grants nor a whole-program
    /// provider stands in for. A scoped provider's capability stays here:
    /// code outside its packages gets the frame's answer.
    #[must_use]
    pub fn withheld(&self) -> Vec<blue_lang_waku::Capability> {
        let reach = self.provisions.widen(&self.frame.reach);
        blue_lang_waku::Capability::host_effects()
            .into_iter()
            .filter(|cap| !reach.grants(*cap))
            .collect()
    }

    /// Every host capability a call can reach the host through: granted by
    /// the frame, and no whole-program provider standing in for it. A scoped
    /// provider's capability the frame grants is here: code outside its
    /// packages reaches the host.
    #[must_use]
    pub fn granted(&self) -> Vec<blue_lang_waku::Capability> {
        blue_lang_waku::Capability::host_effects()
            .into_iter()
            .filter(|cap| {
                self.frame.reach.grants(*cap)
                    && self.provisions.get(*cap).is_none_or(|p| p.scope.is_some())
            })
            .collect()
    }

    /// Every host name neither the frame grants nor a whole-program provider
    /// stands in for. A scoped provider's names stay here: code outside its
    /// packages gets the frame's answer.
    #[must_use]
    pub fn withheld_host_names(&self) -> Vec<(&'static str, blue_lang_waku::Capability)> {
        names_of(self.withheld())
    }

    /// Every host name a call can reach the host through.
    #[must_use]
    pub fn granted_host_names(&self) -> Vec<(&'static str, blue_lang_waku::Capability)> {
        names_of(self.granted())
    }

    /// The hold as an artifact names it.
    #[must_use]
    pub fn frame(&self) -> Frame {
        Frame {
            granted: self.granted(),
            provided: self.provisions.iter().cloned().collect(),
            withheld: self.withheld(),
        }
    }

    /// The frame block of a receipt for a run held here that made `host_io`
    /// host calls: exactly `{"granted":[…],"withheld":[…],"host_io":n}`.
    #[must_use]
    pub fn frame_summary(&self, host_io: u64) -> serde_json::Value {
        self.frame().block(host_io)
    }

    /// Bind the hold into `interp`: a breach for every withheld host name,
    /// then each whole-program provider over its capability's names and each
    /// scoped one under [`provided_name`], then a shim over every granted
    /// host name that tallies each call into `io`. A withheld or provided
    /// name gets no shim, so a pure frame tallies nothing.
    pub fn bind<H: 'static>(&self, interp: &mut Interpreter<H>, who: &'static str, io: &HostIo) {
        refuse_host_names(interp, &self.withheld_host_names(), who);
        #[cfg(feature = "sys")]
        provide::provide(interp, &self.provisions);
        count_host_names(interp, &self.granted_host_names(), io);
    }

    /// Move each scoped provider's host names, where a file of a package it
    /// serves writes them in `forms`, onto [`provided_name`]. A provider
    /// serves the packages its `for:` names and every package they `use`, by
    /// the imports `program` resolved; `forms` is `program`'s evaluated tree,
    /// top-level form for top-level form. Returns the host names the entry
    /// file may not write: [`Hold::withheld_host_names`] less those a scoped
    /// provider serves the entry's own package.
    pub fn rebind_scoped(
        &self,
        program: &uses::ResolvedProgram,
        forms: &mut [tatara_lisp::Spanned],
    ) -> Vec<(&'static str, blue_lang_waku::Capability)> {
        let served: Vec<(
            blue_lang_waku::Capability,
            std::collections::BTreeSet<String>,
        )> = self
            .provisions
            .scoped()
            .map(|(cap, named)| (cap, program.reached_from(named)))
            .collect();
        let serves = |package: Option<&str>, cap: blue_lang_waku::Capability| {
            package.is_some_and(|p| served.iter().any(|(c, s)| *c == cap && s.contains(p)))
        };
        if !served.is_empty() {
            uses::rename_written(program, forms, &|package, name| {
                let cap = blue_lang_waku::Provision::capability_of(name)?;
                serves(package, cap).then(|| provided_name(name))
            });
        }
        let entry = program
            .file(uses::ResolvedProgram::ENTRY)
            .and_then(|f| f.package.as_deref());
        self.withheld_host_names()
            .into_iter()
            .filter(|(_, cap)| !serves(entry, *cap))
            .collect()
    }
}

fn names_of(
    caps: Vec<blue_lang_waku::Capability>,
) -> Vec<(&'static str, blue_lang_waku::Capability)> {
    caps.into_iter()
        .flat_map(|cap| cap.names().into_iter().map(move |n| (n, cap)))
        .collect()
}

/// Shim each of `granted` that `interp` defines so a call that reaches it
/// tallies one host call into `io`. The shim is registered under its own
/// name and the host name rebound to it, so the original stays reachable by
/// its name and reports its own arity errors.
fn count_host_names<H: 'static>(
    interp: &mut Interpreter<H>,
    granted: &[(&'static str, blue_lang_waku::Capability)],
    io: &HostIo,
) {
    for &(name, _) in granted {
        let Some(original @ tatara_lisp_eval::Value::NativeFn(_)) = interp.lookup_global(name)
        else {
            continue;
        };
        let tatara_lisp_eval::Value::NativeFn(nf) = &original else {
            continue;
        };
        let arity = nf.arity;
        let io = io.clone();
        let shim = format!("%io:{name}");
        interp.register_higher_order_fn(
            shim.clone(),
            tatara_lisp_eval::ffi::Arity::Any,
            move |args: &[tatara_lisp_eval::Value],
                  host: &mut H,
                  caller: &tatara_lisp_eval::ffi::Caller<H>,
                  span| {
                if arity.check(args.len()).is_ok() {
                    io.tally();
                }
                caller.apply_value(&original, args.to_vec(), host, span)
            },
        );
        if let Some(v) = interp.lookup_global(&shim) {
            interp.define_global(name, v);
        }
    }
}

/// Every host name `frame` does not grant, with its capability.
#[must_use]
pub fn ungranted_host_names(
    frame: &blue_lang_waku::Waku,
) -> Vec<(&'static str, blue_lang_waku::Capability)> {
    Hold::from(frame.clone()).withheld_host_names()
}

/// The kind of the fatal error a capability breach raises: the node's, so a
/// crash trace classifies the breach this crate raises.
pub const BREACH: &str = blue_lang_proc::violation::BREACH;

/// The exit status a run that ended on a capability breach returns:
/// `EX_NOPERM` (sysexits.h). `blue run` and an appliance both answer it.
pub const BREACH_EXIT: u8 = 77;

/// The fatal error a call to `name` raises when `who` does not grant `cap`.
/// No `rescue` catches it: the run ends.
#[must_use]
pub fn breach(
    name: &str,
    cap: blue_lang_waku::Capability,
    who: &str,
    at: tatara_lisp::Span,
) -> tatara_lisp_eval::EvalError {
    tatara_lisp_eval::EvalError::fatal(
        BREACH,
        format!(
            "`{name}` reaches the host ({}), which {who} does not grant",
            cap.label()
        ),
        at,
    )
}

/// Is `e` a capability breach?
#[must_use]
pub fn is_breach(e: &tatara_lisp_eval::EvalError) -> bool {
    matches!(e, tatara_lisp_eval::EvalError::Fatal { kind, .. } if &**kind == BREACH)
}

/// Bind each of `refused` that `interp` defines to a breach naming `who`.
pub fn refuse_host_names<H: 'static>(
    interp: &mut Interpreter<H>,
    refused: &[(&'static str, blue_lang_waku::Capability)],
    who: &'static str,
) {
    refuse_host_names_noting(interp, refused, who, |_, _, _| {});
}

/// [`refuse_host_names`], calling `note` with the host, the capability and
/// the name before each breach is raised.
pub fn refuse_host_names_noting<H: 'static>(
    interp: &mut Interpreter<H>,
    refused: &[(&'static str, blue_lang_waku::Capability)],
    who: &'static str,
    note: fn(&mut H, blue_lang_waku::Capability, &'static str),
) {
    for &(name, cap) in refused {
        if interp.lookup_global(name).is_none() {
            continue;
        }
        interp.register_fn(
            name,
            tatara_lisp_eval::ffi::Arity::Any,
            move |_: &[tatara_lisp_eval::Value], host: &mut H, span| {
                note(host, cap, name);
                Err(breach(name, cap, who, span))
            },
        );
    }
}

/// The node every interpreter's processes run under: the execution bounds
/// per incarnation, a scheduling quantum, and the host's clock when there is
/// a host (a node with no host has a virtual clock: time passes only when
/// every process waits).
fn node_config() -> blue_lang_proc::NodeConfig {
    let b = execution_bounds();
    let mut config = blue_lang_proc::NodeConfig::new(std::sync::Arc::new(child_interpreter));
    config.budget = tatara_lisp_eval::vm::Budget {
        fuel: b.max_steps,
        max_depth: Some(b.max_call_depth),
        quantum: Some(blue_lang_proc::node::DEFAULT_QUANTUM),
    };
    config.meter = Some(memory::METER);
    config.clock = if cfg!(feature = "sys") {
        blue_lang_proc::ClockKind::Real
    } else {
        blue_lang_proc::ClockKind::Virtual
    };
    config
}

/// A fresh interpreter for a child process: the hostless base, forked. The
/// node adds its child words to it.
fn child_interpreter() -> Interpreter<()> {
    let mut interp = match HOSTLESS_BASE.lock() {
        Ok(base) => base.fork(),
        Err(_) => interpreter(&mut ()),
    };
    apply_execution_bounds(&mut interp);
    interp
}

/// The execution bounds every interpreter this crate builds runs under.
static EXECUTION_BOUNDS: std::sync::OnceLock<ExecutionBounds> = std::sync::OnceLock::new();

/// How much a blue program may do before it is refused: nested calls,
/// evaluation steps and live bytes.
///
/// Each is a BOUND in the sense `blue-lang-cli`'s `config` module admits: a
/// terminating program under bounds above its cost returns the same value, and
/// one that exceeds either is refused with a catchable `depth-exceeded` or
/// `fuel-exhausted` error naming the limit and the function — never a process
/// abort, which is what exceeding the host stack was before tatara-lisp-eval
/// 0.3.63. The walker and the VM run under the same bounds and refuse with the
/// same message. The two memory bounds refuse with a fatal `memory-exhausted`
/// ([`memory`]); a process past one exits a runaway.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExecutionBounds {
    /// Nested (non-tail) calls alive at once. Tail calls do not count.
    pub max_call_depth: usize,
    /// Evaluation steps per run; `None` is unbounded.
    pub max_steps: Option<usize>,
    /// Live bytes one evaluation of code its caller wrote may hold (`blue
    /// run`, an appliance); `None` is unbounded. Each process it spawns is
    /// held to the same bound, on its own account.
    pub max_alloc_bytes: Option<u64>,
    /// Live bytes one evaluation may hold at a door that runs code it did not
    /// write: a session (`eval`, `repl`, `serve`), live evaluation in the
    /// editor, a project rule. `None` is unbounded.
    pub guest_max_alloc_bytes: Option<u64>,
}

impl ExecutionBounds {
    /// Depth at tatara-lisp-eval's `DEFAULT_MAX_DEPTH`, steps unbounded.
    ///
    /// The two defaults differ for one reason: whether a program that works
    /// today keeps working. A recursion past 100k frames never worked — it
    /// aborted the process — so bounding depth removes no behaviour. A run
    /// longer than any finite step count did work (simulations, tools on
    /// nodes), so a default step bound would remove it; for a few hours of
    /// 2026-09-29 blue shipped 50M (~3 s) and did exactly that. A host that
    /// runs code it did not write, or a test that must see a runaway end,
    /// sets `max_steps` itself.
    ///
    /// Memory follows the same test, door by door: a run holding more than
    /// any finite count worked, so `max_alloc_bytes` is unbounded; a door
    /// that runs code it did not write never promised that, so
    /// `guest_max_alloc_bytes` is [`memory::GUEST_MAX_ALLOC_BYTES`].
    pub const DEFAULT: Self = Self {
        max_call_depth: tatara_lisp_eval::vm::DEFAULT_MAX_DEPTH,
        max_steps: None,
        max_alloc_bytes: None,
        guest_max_alloc_bytes: Some(memory::GUEST_MAX_ALLOC_BYTES),
    };
}

/// Name the bounds for this process. The CLI calls this once with the resolved
/// `BlueConfig`, before any interpreter is built; an embedder that never calls
/// it runs under [`ExecutionBounds::DEFAULT`]. Only the first call counts,
/// like `sys::set_program_args`.
pub fn set_execution_bounds(bounds: ExecutionBounds) {
    let _ = EXECUTION_BOUNDS.set(bounds);
}

/// The bounds interpreters are built with.
#[must_use]
pub fn execution_bounds() -> ExecutionBounds {
    EXECUTION_BOUNDS
        .get()
        .copied()
        .unwrap_or(ExecutionBounds::DEFAULT)
}

fn apply_execution_bounds<H: 'static>(interp: &mut Interpreter<H>) {
    let b = execution_bounds();
    // No quantum, so the tree-walker refuses nothing of this budget.
    let _ = interp.set_budget(tatara_lisp_eval::vm::Budget {
        fuel: b.max_steps,
        max_depth: Some(b.max_call_depth),
        quantum: None,
    });
}

/// The prebuilt hostless substrate, built once per process.
///
/// **Measured 2026-08-01, and this is the entire reason the fork exists.**
/// Profiling a trivial blue program found the run dominated by ONE thing:
///
/// ```text
/// parse                     9.6 µs
/// check                     1.6 µs
/// interpreter_hostless()  5 820 µs   <- 98.4% of the run
/// ```
///
/// Splitting that further: `Interpreter::new()` is 24 µs and
/// `install_full_stdlib_with` is the rest — the stdlib was being rebuilt from
/// scratch on every single `run()`, and blue's whole surface (`map`, `filter`,
/// string ops) lives in it, so no program could avoid the cost.
///
/// `fork` already existed upstream for exactly this, and blue simply was not
/// using it. tatara-lisp-eval's own `fork_cost.rs` opens with *"cheapness is
/// the entire reason it exists"* — the capability was built, documented and
/// guarded, and the consumer kept paying full price beside it.
///
/// | | per call |
/// |---|---|
/// | rebuild (`Interpreter::new` + `install_full_stdlib_with`) | **9.03 ms** |
/// | `fork()` of a prebuilt base | **0.102 ms** |
///
/// **88× on the dominant cost.** This is purgatory's computation-layer clause
/// made real: the stdlib is the most-reused computation in the language, and
/// it was being discarded and recomputed rather than resurrected.
///
/// Isolation is `fork`'s contract, not an assumption made here — its
/// correctness gates live upstream in `fork.rs`, and `fork_cost.rs` guards
/// against a future change that deep-copies (which would keep every
/// correctness test green while silently restoring the cost this removes).
static HOSTLESS_BASE: std::sync::LazyLock<std::sync::Mutex<Interpreter<()>>> =
    std::sync::LazyLock::new(|| {
        std::sync::Mutex::new(timings::stage(timings::Stage::Runtime, || {
            interpreter(&mut ())
        }))
    });

/// The common host-free case.
///
/// Forks the process-wide base rather than rebuilding the stdlib. Falls back to
/// a full build if the lock is poisoned: a poisoned lock means another thread
/// panicked mid-fork, and answering a correct-but-slow interpreter beats
/// propagating someone else's panic into an unrelated caller.
pub fn interpreter_hostless() -> Interpreter<()> {
    let mut interp = match HOSTLESS_BASE.lock() {
        Ok(base) => base.fork(),
        Err(_) => interpreter(&mut ()),
    };
    // Again after the fork: the base may have been built before the bounds
    // were named, and a fork inherits whatever its base had.
    apply_execution_bounds(&mut interp);
    // A node per fork: the base's own node would be shared by every program.
    attach_node(&mut interp);
    interp
}

/// Lift spanless forms into what the evaluator eats.
///
/// **No longer on the `blue run` path, and that is the point.**
/// [`erase::erase_types`] now takes and returns `Spanned`, so
/// `pipeline::run_in_surface` hands the evaluator the *parser's own* tree with
/// the author's positions on it — there is nothing left to lift. This
/// function survives for a caller that genuinely holds spanless `Sexp` and
/// has no position to preserve, and as the subject of the two tests below
/// that pin why the hop it replaced was unsafe.
///
/// `Interpreter::eval_program` takes `&[Spanned]`; blue's stages produced
/// `Sexp`. Two callers bridged that gap by *printing the tree and reading it
/// back* — `forms.map(ToString::to_string).join("\n")` into
/// `tatara_lisp::read_spanned`. Both stopped, and the round trip is gone from
/// the pipeline.
///
/// **Why it had to go.** Printing a tree we already hold and re-parsing it puts
/// the reader's lexer between blue and its own output, for nothing — and the
/// printer and the reader are **not inverses**. `Atom::Str`'s `Display` escapes
/// its payload and its own docs explain at length why; the `Atom::Symbol` arm
/// is a bare `write_str`. So a symbol whose text carries a separator prints as
/// several tokens and reads back as several symbols: a well-formed tree with a
/// different meaning, no error raised. Measured 2026-08-02 —
/// `pipeline::tests::the_round_trip_is_not_the_identity_in_general` pins which
/// separators are silent and which are loud. The only thing that kept this from
/// biting was blue happening not to emit those bytes. A stage that never
/// serialises cannot be mis-read.
///
/// **What is given up: spans.** The old path's spans pointed into the
/// re-printed lisp text, a buffer no human ever wrote and no diagnostic could
/// usefully cite — they were positions in blue's own output, not in the
/// author's source. `Span::synthetic` says the same thing honestly.
///
/// **Carrying real blue-source spans through erasure was the separate piece of
/// work, and it is done — but NOT the way this doc predicted.** It said the
/// work "would start from `Spanned::from_sexp_at`". It did not, and could not:
/// `from_sexp_at` is a *lift*, stamping ONE span across a whole subtree, so
/// starting there would have replaced a tree of synthetic spans with a tree of
/// identical wrong ones. The actual shape was to stop projecting in the first
/// place — erasure walks `Spanned` and keeps each node's own span, because it
/// only ever deletes (see [`erase`]). **A pointer at the nearest-looking API is
/// how a reader is sent to the wrong starting point**; the note is corrected
/// here rather than deleted, because the wrong lead was load-bearing enough to
/// be worth naming.
#[must_use]
pub fn lower_to_spanned(forms: &[tatara_lisp::Sexp]) -> Vec<tatara_lisp::Spanned> {
    forms
        .iter()
        .map(tatara_lisp::Spanned::from_sexp_synthetic)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tatara_lisp_eval::Value;

    fn eval(src: &str) -> Value {
        let forms = tatara_lisp::read_spanned(src).expect("read");
        let mut interp = interpreter_hostless();
        interp.eval_program(&forms, &mut ()).expect("eval")
    }

    /// Every layer is present. A test that only checked layer 1 is exactly
    /// what let the stdlib gap survive.
    #[test]
    fn both_layers_are_installed() {
        // Layer 1: a Rust primitive.
        assert!(matches!(eval("(+ 1 2)"), Value::Int(3)));
        // Layer 2: a stdlib definition, which is the layer that was missing.
        assert!(matches!(eval("(mod 7 3)"), Value::Int(1)));
        assert!(matches!(eval("(inc 41)"), Value::Int(42)));
        assert!(matches!(eval("(first (list 9 8))"), Value::Int(9)));
        // Layer 3: blue's own core — string and number conversion.
        assert!(matches!(eval(r#"(length "héllo")"#), Value::Int(5)));
        // Layer 4: the JSON surface.
        assert!(matches!(
            eval(r#"(json_parse "{\"outcome\":\"ok\"}")"#),
            Value::List(_)
        ));
        // Layer 4b: cryptography.
        assert!(matches!(eval(r#"(blake3_hex "")"#), Value::Str(_)));
    }

    #[cfg(feature = "sys")]
    mod held {
        use super::super::*;
        use blue_lang_waku::{Capability, Provided, Provision, Provisions};
        use tatara_lisp_eval::Value;

        fn held(host: &[Capability], provided: &[Provided]) -> (Hold, Interpreter<()>, HostIo) {
            let mut provisions = Provisions::default();
            for p in provided {
                provisions.add(p.clone()).expect("one provider each");
            }
            let hold = Hold {
                frame: session::frame_granting(host),
                provisions,
            };
            let mut interp = interpreter_hostless();
            let io = HostIo::new();
            hold.bind(&mut interp, "this test's frame", &io);
            (hold, interp, io)
        }

        fn call(interp: &mut Interpreter<()>, src: &str) -> Result<Value, String> {
            let forms = tatara_lisp::read_spanned(src).expect("read");
            interp
                .eval_program(&forms, &mut ())
                .map_err(|e| e.to_string())
        }

        #[test]
        fn a_pure_hold_shims_no_name_so_nothing_can_tally() {
            let (hold, mut interp, io) = held(&[], &[]);
            assert!(hold.granted_host_names().is_empty());
            for (name, _) in hold.withheld_host_names() {
                assert!(
                    interp.lookup_global(&format!("%io:{name}")).is_none(),
                    "`{name}` is withheld, so it has no counting shim"
                );
            }
            assert!(call(&mut interp, "(getenv \"HOME\")").is_err());
            assert!(call(&mut interp, "(now_ms)").is_err());
            assert_eq!(io.total(), 0);
        }

        #[test]
        fn a_granted_name_tallies_each_call_and_a_provided_or_withheld_one_none() {
            let (hold, mut interp, io) = held(
                &[Capability::Environment],
                &[Provision::DeterministicStepped {
                    at_ms: 10,
                    step_ms: 1,
                }
                .into()],
            );
            assert_eq!(hold.granted(), [Capability::Environment]);
            call(&mut interp, "(getenv \"HOME\")").expect("granted");
            call(&mut interp, "(argv)").expect("granted");
            assert_eq!(io.total(), 2, "two calls through granted names");
            assert_eq!(
                call(&mut interp, "(now_ms)").expect("provided").to_string(),
                "10"
            );
            assert!(call(&mut interp, "(read_file \"/etc/hosts\")").is_err());
            assert_eq!(io.total(), 2, "a provider and a breach reach no host");
            let wrong = call(&mut interp, "(getenv)").expect_err("arity");
            assert!(
                wrong.contains("getenv"),
                "the original names itself: {wrong}"
            );
            assert_eq!(
                io.total(),
                2,
                "a call refused for its arity reached no host"
            );
        }

        #[test]
        fn an_unrestricted_hold_shims_every_host_name_but_a_provided_one() {
            let hold = Hold {
                frame: blue_lang_waku::Waku::top(),
                provisions: {
                    let mut p = Provisions::default();
                    p.add(Provision::NullSink).expect("one");
                    p
                },
            };
            assert!(hold.withheld().is_empty());
            assert!(!hold.granted().contains(&Capability::FileSystem));
            assert_eq!(hold.granted().len(), Capability::host_effects().len() - 1);
            let f = hold.frame();
            assert_eq!(f.provided, [Provided::from(Provision::NullSink)]);
            assert_eq!(f.granted, hold.granted());
        }

        #[test]
        fn a_scoped_provider_binds_its_alias_uncounted_and_leaves_the_host_name_counted() {
            let scoped = Provided {
                provision: Provision::NullSink,
                scope: Some(std::collections::BTreeSet::from(["kazu".to_string()])),
            };
            let (hold, mut interp, io) =
                held(&[Capability::FileSystem], std::slice::from_ref(&scoped));
            assert_eq!(hold.granted(), [Capability::FileSystem]);
            assert_eq!(hold.frame().provided, [scoped]);
            let alias = provided_name("read_file");
            assert!(
                interp.lookup_global(&alias).is_some(),
                "the scoped alias is bound"
            );
            let _ = call(&mut interp, &format!("({alias} \"/etc/hosts\")"));
            assert_eq!(io.total(), 0, "the provider reaches no host");
            call(&mut interp, "(read_file \"/etc/hosts\")").expect("granted");
            assert_eq!(io.total(), 1, "code outside the scope reaches the host");
        }

        #[test]
        fn the_frame_summary_is_exactly_granted_withheld_and_host_io() {
            let (hold, _, _) = held(&[Capability::Clock], &[]);
            assert_eq!(
                blue_lang_proc::receipt::canonical(&hold.frame_summary(4)),
                r#"{"granted":["clock"],"host_io":4,"withheld":["process","filesystem","environment","network","entropy"]}"#
            );
        }
    }

    /// Anti-vacuity: a bare interpreter really does LACK layer 2, so the test
    /// above is measuring the runtime's contribution and not a property the
    /// interpreter has for free.
    #[test]
    fn a_bare_interpreter_lacks_the_stdlib() {
        let forms = tatara_lisp::read_spanned("(mod 7 3)").expect("read");
        let mut bare = Interpreter::new();
        tatara_lisp_eval::install_primitives(&mut bare);
        assert!(
            bare.eval_program(&forms, &mut ()).is_err(),
            "if a bare interpreter already resolved `mod`, this crate would be measuring nothing"
        );
    }
}
