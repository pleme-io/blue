//! The posture axis the stacked backends compile for.
//!
//! [`Rung`](blue_lang_runtime::shift::Rung) is the ladder the check stage
//! already measures a file on; [`Posture`] extends it with the two compiled
//! zones the backends plan adds. The extension is one-directional on purpose:
//! a rung maps to a posture, and the two new zones are minted by their own
//! phases (heapless by Phase 3's static enforcement, kernel by the eBPF
//! backend), never inferred from a rung — a file cannot earn `Heapless` by
//! looking typed, because looking typed is not what being heapless means.

use blue_lang_runtime::shift::Rung;

/// The zone a module compiles for: the dynamic interpreter, the checked
/// interpreter, or one of the compiled postures.
///
/// Ordered loose→locked, extending `Rung`'s `Dynamic < Annotated < Checked <
/// Restricted`. `Annotated` folds into [`Posture::Checked`] here: to a backend
/// there is no third behaviour between "some values carry types" and "the
/// type walk covered the file" — the distinction matters to a reader of the
/// ladder, not to codegen.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Posture {
    /// No annotations; the tree-walking evaluator, types erased.
    Dynamic = 0,
    /// The type walk covers the module; the IR keeps its declared types.
    Checked = 1,
    /// Checked, and the macro phase reads only declared content-addressed
    /// inputs — a capability shift on top of the type shift.
    Restricted = 2,
    /// Compiler-managed data stacks, no heap, no Arc. Phase 3's posture;
    /// nothing lowers to it until that phase's enforcement exists.
    Heapless = 3,
    /// The eBPF zone. Phase 4/5's posture; minted by the kernel door, never
    /// inferred from source annotations.
    Kernel = 4,
}

impl Posture {
    /// The word `blue ir` prints.
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Posture::Dynamic => "dynamic",
            Posture::Checked => "checked",
            Posture::Restricted => "restricted",
            Posture::Heapless => "heapless",
            Posture::Kernel => "kernel",
        }
    }

    /// The posture a measured rung justifies. The two compiled zones have no
    /// source spelling yet, so no rung reaches them — by design, not by
    /// omission: minting them here would let an annotated file claim a
    /// guarantee nothing enforces.
    #[must_use]
    pub const fn from_rung(rung: Rung) -> Self {
        match rung {
            Rung::Dynamic => Posture::Dynamic,
            Rung::Annotated | Rung::Checked => Posture::Checked,
            Rung::Restricted => Posture::Restricted,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_rung_maps_and_none_reaches_a_compiled_zone() {
        assert_eq!(Posture::from_rung(Rung::Dynamic), Posture::Dynamic);
        assert_eq!(Posture::from_rung(Rung::Annotated), Posture::Checked);
        assert_eq!(Posture::from_rung(Rung::Checked), Posture::Checked);
        assert_eq!(Posture::from_rung(Rung::Restricted), Posture::Restricted);
        assert!(Posture::from_rung(Rung::Restricted) < Posture::Heapless);
        assert!(Posture::Heapless < Posture::Kernel);
    }
}
