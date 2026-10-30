//! `blue test`'s witness: the types every loose definition's calls showed,
//! recorded in the store under `$XDG_CACHE_HOME/blue/witness`
//! (`blue_lang_mondou::witness`), where the language server reads them to
//! offer `blueshift: lock invariants`.
//!
//! On by default: watching a call changes nothing it does. `BLUE_WITNESS=off`
//! turns it off. A store that cannot be opened (a read-only home, a build
//! sandbox) records nothing, and the run is the same either way.

use std::sync::Arc;

use blue_lang_mondou::witness::{Witness, Witnesses};
use blue_lang_runtime::observe::CallObserver;

pub(crate) const ENV: &str = "BLUE_WITNESS";

/// Whether `BLUE_WITNESS`'s value leaves the witness on.
pub(crate) fn on(value: Option<&str>) -> bool {
    !matches!(
        value.map(|v| v.trim().to_ascii_lowercase()).as_deref(),
        Some("off" | "0" | "false" | "no")
    )
}

/// Whether this command records a witness.
pub(crate) fn enabled() -> bool {
    on(std::env::var(ENV).ok().as_deref())
}

/// A witness over a program about to run (`lowered`, before erasure),
/// wrapping `inner` when a tool already watches it.
pub(crate) fn over(
    lowered: &[blue_lang_syntax::Spanned],
    program: &blue_lang_runtime::uses::ResolvedProgram,
    inner: Option<Arc<dyn CallObserver>>,
) -> Arc<Witness> {
    let hashes = blue_lang_mondou::hash_checked(program, lowered);
    Arc::new(Witness::new(lowered, &hashes, inner))
}

/// Write what the run showed. A failure costs the editor evidence, never the
/// run its result, so it is not an error.
pub(crate) fn finish(witness: &Witness) {
    let seen = witness.witnessed();
    if seen.is_empty() {
        return;
    }
    if let Some(store) = Witnesses::open_default() {
        let _ = store.record(&seen);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_witness_is_on_unless_the_environment_turns_it_off() {
        assert!(on(None));
        assert!(on(Some("on")));
        assert!(on(Some("")));
        assert!(!on(Some("off")));
        assert!(!on(Some(" OFF ")));
        assert!(!on(Some("0")));
        assert!(!on(Some("no")));
    }
}
