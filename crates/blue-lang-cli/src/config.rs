//! blue's typed configuration surface — [`shikumi::TieredConfig`], two fields.
//!
//! ```text
//! blue config bare        # zero-opinion floor
//! blue config default     # the prescribed defaults, which are the constants
//! blue config env         # resolved from BLUE_TIER
//! blue config default --diff bare
//! ```
//!
//! # The rule that decides what may live here
//!
//! **A knob is admissible only if it is a BOUND, never a preference.** Raising
//! or lowering either field below changes no program's meaning: the same source
//! either resolves/parses, or is refused for exceeding a limit. Nothing in
//! between. That is what makes exposing them safe — a bound cannot freeze a
//! design guess as a public interface, because there is no design to guess at.
//! A *preference* (how something should look, which semantics to pick) would
//! do exactly that, so preferences do not go in this file.
//!
//! Each field also had to already have a **shipped, overridable default in
//! code**. Both do, and the `prescribed_default()` below returns those
//! constants *by name* rather than copying their values — so the config cannot
//! drift from what the code actually does.
//!
//! # Why exactly two, and not the three the waiver used to name
//!
//! blue's `pending-shikumi: M1` waiver claimed three knobs were "blocked on an
//! unsettled design". Measured 2026-08-01, two of those three are not blocked —
//! they are **settled against being configurable at all**, which is a different
//! and much stronger statement:
//!
//! * **Formatter width** — settled AGAINST. `blue_lang_fmt`'s module docs say
//!   it outright: "There is no configuration type in this crate, and that is
//!   the feature… there is nowhere to put a knob." `theory/BLUE.md` §0 makes
//!   FORM an axis with exactly one way to write a thing, and the content-
//!   addressed identity of §V.16.1 rests on that single rendering. A width
//!   option would forfeit both. Typing it would be a regression, not progress.
//!
//! * **Posture ceiling** — settled elsewhere. §V.24 moved ceilings to the
//!   ROOT, as a Bluefile input: `blue_lang_waku::Waku` deliberately carries no
//!   ceiling ("a frame is a *position*, and narrowing is something the root
//!   does to it"), and `blue_lang_bidama::resolve(bidama, ceiling)` takes it as
//!   an argument. A daemon-level ceiling knob would re-introduce the
//!   package-declares-a-ceiling shape §V.24 names as Cargo's documented
//!   anti-pattern.
//!
//! * **Execution budget** — genuinely unsettled, and the reason is concrete
//!   rather than philosophical: **no default constant exists anywhere in blue**
//!   to expose (`Budget` matches zero lines in `blue-lang-runtime`,
//!   `blue-lang-test` and `blue-lang-cli`). There is nothing to make
//!   overridable yet. This is what `pending-shikumi: M2` now carries.
//!
//! # Tier honesty
//!
//! The two-field surface is **only-mitigated** against a fourth knob creeping
//! in — `the_surface_is_exactly_two_knobs` is an exhaustive destructure, so
//! adding a field is an `E0027` compile error in the test binary rather than
//! something structurally unrepresentable. It forces acknowledgement, not
//! justification.

use serde::{Deserialize, Serialize};
use shikumi::{ConfigTier, TieredConfig};

/// The environment variable naming which tier to materialize.
pub const TIER_ENV: &str = "BLUE_TIER";

/// The environment variable naming a YAML config file.
///
/// This is the name substrate's module trio derives from `blue`
/// (`mkModuleTrio` uppercases and appends `_CONFIG`), so the nix side and this
/// constant have to agree — `blue_config_env_matches_the_module_trio` pins it.
pub const CONFIG_ENV: &str = "BLUE_CONFIG";

/// Every bound the `blue` binary reads from configuration.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub struct BlueConfig {
    /// Search steps the version solver may take before reporting.
    ///
    /// Read by `blue deps`, which passes it to `Solver::with_max_steps`. The
    /// solver does not learn incompatibilities, so a pathological graph can
    /// search a long time; the bound makes that *report* rather than hang.
    /// Raising it never changes which resolution is correct — only how long
    /// blue is willing to look for it.
    pub solver_max_steps: usize,

    /// Expression/statement nesting the parser accepts before refusing.
    ///
    /// Read by every `blue` subcommand that parses, via
    /// `blue_lang_runtime::parse_with_depth`. Without a bound, deep input does
    /// not fail — it **aborts the process** with a stack overflow that
    /// `catch_unwind` cannot catch. Raising it never changes what a program
    /// means; it only moves the line between "typed `Err`" and "SIGABRT",
    /// which is why the default sits far below the measured overflow point.
    pub max_expr_depth: usize,
}

impl Default for BlueConfig {
    fn default() -> Self {
        <Self as TieredConfig>::prescribed_default()
    }
}

impl TieredConfig for BlueConfig {
    fn bare() -> Self {
        Self {
            solver_max_steps: 0,
            max_expr_depth: 0,
        }
    }

    fn prescribed_default() -> Self {
        // The CONSTANTS, never copies of their values. A literal here would be
        // a second place for each bound to be stated, and the two would drift
        // the first time someone tuned one — the `INFIX`-table defect wearing
        // a config hat.
        Self {
            solver_max_steps: blue_lang_pkg::DEFAULT_MAX_STEPS,
            max_expr_depth: blue_lang_syntax::MAX_EXPR_DEPTH,
        }
    }
}

/// Resolve the config the `blue` binary should run with.
///
/// Precedence, highest first:
///
/// 1. `BLUE_TIER` — an explicit operator override, so it wins outright.
/// 2. `BLUE_CONFIG` naming a file that exists — the YAML the module trio
///    deploys, overlaid on the prescribed defaults.
/// 3. The prescribed defaults.
///
/// A `BLUE_CONFIG` pointing at a file that is **absent** falls through to (3)
/// rather than failing: the module trio writes the YAML on activation, and a
/// binary that refuses to start between activations would be worse than one
/// that runs on its own defaults.
#[must_use]
pub fn resolve() -> BlueConfig {
    BlueConfig::resolve_tier(tier_from_env())
}

fn tier_from_env() -> ConfigTier {
    if std::env::var_os(TIER_ENV).is_some() {
        return ConfigTier::from_env(TIER_ENV);
    }
    match std::env::var_os(CONFIG_ENV) {
        Some(raw) => {
            let path = std::path::PathBuf::from(raw);
            if path.is_file() {
                ConfigTier::Custom(path)
            } else {
                ConfigTier::Default
            }
        }
        None => ConfigTier::Default,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The gate on "exactly two knobs".
    ///
    /// An exhaustive destructure: a third field makes this `E0027 pattern does
    /// not mention field`, so the test binary stops compiling and `cargo test`
    /// goes red. Red run recorded 2026-08-01 by adding a `formatter_width`
    /// field — `error[E0027]: pattern does not mention field
    /// `formatter_width`` — then removing it.
    ///
    /// Tier-honest: this catches an addition, it does not make one
    /// unrepresentable. Whoever updates the pattern has to have read the rule
    /// in this module's docs, which is the whole mechanism.
    #[test]
    fn the_surface_is_exactly_two_knobs() {
        let BlueConfig {
            solver_max_steps: _,
            max_expr_depth: _,
        } = BlueConfig::prescribed_default();
    }

    #[test]
    fn bare_is_zero_opinion() {
        let b = BlueConfig::bare();
        assert_eq!(b.solver_max_steps, 0);
        assert_eq!(b.max_expr_depth, 0);
    }

    /// The prescribed tier IS the shipped constants — not a copy of them.
    ///
    /// This is the test that makes the config non-decorative in the other
    /// direction: tune `DEFAULT_MAX_STEPS` or `MAX_EXPR_DEPTH` and the
    /// prescribed tier follows automatically, because it never held a literal.
    #[test]
    fn prescribed_default_is_the_constants_themselves() {
        let d = BlueConfig::prescribed_default();
        assert_eq!(d.solver_max_steps, blue_lang_pkg::DEFAULT_MAX_STEPS);
        assert_eq!(d.max_expr_depth, blue_lang_syntax::MAX_EXPR_DEPTH);
        assert_eq!(d.solver_max_steps, 100_000, "the shipped value, pinned");
        assert_eq!(d.max_expr_depth, 256, "the shipped value, pinned");
    }

    #[test]
    fn bare_and_default_differ() {
        assert_ne!(BlueConfig::bare(), BlueConfig::prescribed_default());
    }

    #[test]
    fn default_trait_delegates_to_prescribed() {
        assert_eq!(BlueConfig::default(), BlueConfig::prescribed_default());
    }

    #[test]
    fn resolve_tier_dispatches_through_shikumi() {
        assert_eq!(
            BlueConfig::resolve_tier(ConfigTier::Bare),
            BlueConfig::bare()
        );
        assert_eq!(
            BlueConfig::resolve_tier(ConfigTier::Default),
            BlueConfig::prescribed_default()
        );
    }

    /// The progressive fold — the canonical shikumi resolution path — reaches
    /// the same answer as the tier selector, and attributes each leaf.
    #[test]
    fn the_progressive_fold_resolves_the_prescribed_tier() {
        let resolved = BlueConfig::resolve_progressive();
        assert_eq!(*resolved.value(), BlueConfig::prescribed_default());
    }

    /// The nix module trio and this struct must agree on the YAML key names.
    ///
    /// They are a **silent** contract otherwise: serde ignores unknown keys, so
    /// renaming a field here would leave the deployed YAML setting nothing at
    /// all, and blue would run on defaults while an operator read their own
    /// config file and believed it. Reading `flake.nix` is crude, and it is the
    /// only thing on either side that can see both.
    ///
    /// Red run recorded 2026-08-01: a `#[serde(rename = "max_expression_depth")]`
    /// on `max_expr_depth` — the wire-name drift this exists to catch, in its
    /// purest form — turned this red with
    /// ``flake.nix must emit the `max_expression_depth` key``.
    #[test]
    fn every_field_is_emitted_by_the_module_trio() {
        let json =
            serde_json::to_value(BlueConfig::prescribed_default()).expect("BlueConfig serializes");
        let keys: Vec<String> = json
            .as_object()
            .expect("BlueConfig is a struct, so a JSON object")
            .keys()
            .cloned()
            .collect();
        assert_eq!(keys.len(), 2, "two knobs, per this module's docs");

        let flake =
            std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../../flake.nix"))
                .expect("the workspace flake is two directories up from this crate");
        for key in keys {
            assert!(
                flake.contains(&key),
                "flake.nix must emit the `{key}` key in its shikumiDefaults — \
                 otherwise the deployed YAML sets nothing and blue silently \
                 runs on defaults"
            );
        }
    }

    /// The env-var name has to match what `mkModuleTrio` derives from the tool
    /// name, or the deployed YAML is never found.
    #[test]
    fn blue_config_env_matches_the_module_trio() {
        // substrate/lib/module-trio.nix:248 — uppercase, `-` → `_`, + "_CONFIG".
        assert_eq!(CONFIG_ENV, "BLUE_CONFIG");
        assert_eq!(TIER_ENV, "BLUE_TIER");
    }

    /// `blue.b` — blue configured in blue — lowers to what shikumi accepts.
    ///
    /// shikumi's `sexp_to_value_root` takes the first top-level form, drops a
    /// leading head symbol, and requires the remainder to be a kwargs list:
    /// non-empty, even length, every even slot an `Atom::Keyword`. That
    /// predicate is re-stated here against the tree blue's OWN parser produces,
    /// which is the honest form of the claim available from inside this repo —
    /// see the note below on why the provider is not called directly.
    ///
    /// **Executed evidence, recorded because this test cannot produce it:**
    /// the shipped `shikumi::blue_provider::load_from_str` was run against this
    /// exact source on 2026-08-01 and returned
    /// `Dict({"max_expr_depth": Num(I64(…)), "solver_max_steps": Num(I64(…))})`,
    /// which then resolved through `BlueConfig::resolve_progressive_with` into
    /// a populated `BlueConfig`. Three near-miss surface forms were measured to
    /// FAIL in the same run; `blue.b`'s header records which and why.
    ///
    /// **Why the provider is not a dependency here.** shikumi's `blue` feature
    /// pins `blue-lang-syntax = "0.0.2"` from crates.io. Turning it on inside
    /// this workspace resolves a SECOND copy of blue's parser beside the local
    /// path dep, so the assertion would be about a published 0.0.2 rather than
    /// the 0.0.9 this repo ships and tests — a test that measures the wrong
    /// parser is worse than one that measures the shape. Closing that gap is
    /// shikumi's bump to make, not blue's.
    #[test]
    fn blue_dot_b_lowers_to_a_shape_shikumi_accepts() {
        let src = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../../blue.b"))
            .expect("blue.b sits at the workspace root");
        let forms = blue_lang_syntax::parse_program(&src).expect("blue.b must parse");
        assert_eq!(forms.len(), 1, "shikumi reads the FIRST form and only it");

        let blue_lang_syntax::Sexp::List(items) = &forms[0] else {
            panic!("a config form must be a list, got {:?}", forms[0]);
        };
        // `sexp_to_value_root`: a leading Symbol is the head and is dropped.
        // For a map literal that head is `hash-map`.
        let start = match items.first() {
            Some(blue_lang_syntax::Sexp::Atom(blue_lang_syntax::Atom::Symbol(s))) => {
                assert_eq!(s, blue_lang_syntax::LOWERED_MAP);
                1
            }
            other => panic!("expected a head symbol, got {other:?}"),
        };
        let rest = &items[start..];

        // `is_kwargs_list`, restated.
        assert!(!rest.is_empty(), "an empty body maps to an empty dict");
        assert_eq!(rest.len() % 2, 0, "kwargs pair up");
        let keys: Vec<&str> = rest
            .iter()
            .step_by(2)
            .map(|s| match s {
                blue_lang_syntax::Sexp::Atom(blue_lang_syntax::Atom::Keyword(k)) => k.as_str(),
                other => panic!(
                    "every key must be a KEYWORD — a string key is `Atom::Str` and \
                     shikumi's kwargs test rejects it. Got {other:?}"
                ),
            })
            .collect();
        assert_eq!(keys, vec!["solver_max_steps", "max_expr_depth"]);

        // And the values are the prescribed bounds, so the file documents the
        // shipped defaults rather than drifting from them.
        let ints: Vec<i64> = rest
            .iter()
            .skip(1)
            .step_by(2)
            .map(|s| match s {
                blue_lang_syntax::Sexp::Atom(blue_lang_syntax::Atom::Int(n)) => *n,
                other => panic!("a bound must be an integer, got {other:?}"),
            })
            .collect();
        let d = BlueConfig::prescribed_default();
        assert_eq!(
            ints,
            vec![d.solver_max_steps as i64, d.max_expr_depth as i64],
            "blue.b must state the shipped defaults"
        );
    }

    /// An absent `BLUE_CONFIG` target degrades to the prescribed tier rather
    /// than erroring — see [`resolve`]'s docs for why that is the right choice.
    #[test]
    fn a_missing_config_file_falls_through_to_the_prescribed_tier() {
        let missing = std::path::PathBuf::from("/nonexistent/blue/blue.yaml");
        assert!(!missing.is_file(), "precondition");
        // Exercised through the same predicate `tier_from_env` applies, without
        // mutating process-global env (which would race other tests).
        let tier = if missing.is_file() {
            ConfigTier::Custom(missing)
        } else {
            ConfigTier::Default
        };
        assert_eq!(
            BlueConfig::resolve_tier(tier),
            BlueConfig::prescribed_default()
        );
    }
}
