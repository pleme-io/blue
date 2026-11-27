//! `blue-lang-ir` — the type-preserving mid-level IR of the stacked
//! backends plan (Phase 1, `docs/BACKENDS-PLAN.md`).
//!
//! A mid-level IR between the checked tree and every future backend:
//!
//! - **Lowered from the pipeline's output, never a parser fork.** The one
//!   entry point, [`lower`], takes the [`Checked`] value
//!   `blue_lang_runtime::pipeline::check_entry` produced — the resolved
//!   tree plus the check stage's diagnostics, seams and file table — and
//!   asks nothing else. The default parse → check → erase → run path is
//!   untouched; nothing in the runtime depends on this crate.
//! - **Type-preserving.** Exact static types survive: declared signatures,
//!   record field types, union arm layouts, and the expected type of every
//!   seam the check stage recorded. Expression types the checker infers
//!   but does not export stay `Dyn` — erased nothing, invented nothing.
//! - **SSA-friendly.** One value per instruction, joins as block
//!   parameters (Cranelift's shape, which Phase 4a compiles to directly),
//!   assignment as rebinding.
//! - **Seams explicit.** Every posture/backend crossing is a
//!   [`SeamCall`](module::Inst::SeamCall) instruction: host words under a
//!   capability, calls into a module of a different
//!   [`Posture`](posture::Posture), and the check stage's own recorded
//!   boundary checks. A backend cannot lower a crossing as local code,
//!   because the IR does not let it be written that way.
//! - **Refusal typed.** Constructs no phase models yet (rescue, eval, the
//!   process words, a named record update) fail lowering with a
//!   [`Refusal`] naming and locating them — never a silent approximation.
//!
//! `blue ir FILE` prints it; the lowering's own contract is pinned by the
//! tests in [`lower`].

pub mod lower;
pub mod module;
pub mod posture;
mod print;

pub use lower::{lower, Refusal};
pub use module::{
    Block, Callee, Const, FieldDef, Function, Inst, Module, Param, RecordDef, SeamKind, Terminator,
    UnionArm, UnionDef, ValueId,
};
pub use posture::Posture;
