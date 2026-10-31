//! A project's own execution bounds: `bounds({steps:, call_depth:,
//! alloc_bytes:})` in its root Bluefile. `blue lock` records them in the
//! capabilities record ([`crate::capabilities::CapabilityRecord`]), and every
//! door that holds the project (`blue run`, `blue test`, an appliance) meets
//! them with the process's bounds, the operator's `BlueConfig`, so a project
//! can narrow a bound and never widen one.

use std::num::{NonZeroU64, NonZeroUsize};

use blue_lang_runtime::ExecutionBounds;
use serde::{Deserialize, Serialize};
use tatara_lisp_eval::value::MapKey;
use tatara_lisp_eval::Value;

/// The bounds a project declares; a key it leaves out is the operator's
/// alone.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Bounds {
    /// Evaluation steps a run, and each test, may take.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub steps: Option<NonZeroUsize>,
    /// Nested calls alive at once.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub call_depth: Option<NonZeroUsize>,
    /// Live bytes one evaluation, and each process it spawns, may hold.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub alloc_bytes: Option<NonZeroU64>,
}

impl Bounds {
    /// The keys a Bluefile names the bounds by, in declaration order.
    pub const KEYS: &'static [&'static str] = &["steps", "call_depth", "alloc_bytes"];

    /// The bounds `settings`, a map from [`Self::KEYS`] to positive
    /// integers, declares.
    ///
    /// # Errors
    ///
    /// Settings that are not a map, a map that names no bound, a key outside
    /// [`Self::KEYS`], or a value that is not a positive integer.
    pub fn of_settings(settings: &Value) -> Result<Self, String> {
        let keys = Self::KEYS.join(", ");
        let Value::Map(map) = settings else {
            return Err(format!(
                "settings must be a map of {keys}, got {}",
                settings.type_name()
            ));
        };
        let mut bounds = Self {
            steps: None,
            call_depth: None,
            alloc_bytes: None,
        };
        for (k, v) in map.iter() {
            let key = match k {
                MapKey::Keyword(s) | MapKey::Str(s) | MapKey::Symbol(s) => {
                    s.trim_start_matches(':').to_string()
                }
                _ => return Err(format!("a bound is named by a keyword, one of {keys}")),
            };
            let positive = match v {
                Value::Int(n) if *n > 0 => n.unsigned_abs(),
                Value::Int(n) => {
                    return Err(format!("`{key}` must be a positive integer, got {n}"))
                }
                other => {
                    return Err(format!(
                        "`{key}` must be a positive integer, got {}",
                        other.type_name()
                    ))
                }
            };
            let too_large = || format!("`{key}` is {positive}, past what this machine counts");
            match key.as_str() {
                "steps" => {
                    bounds.steps = usize::try_from(positive)
                        .ok()
                        .and_then(NonZeroUsize::new)
                        .map(Some)
                        .ok_or_else(too_large)?;
                }
                "call_depth" => {
                    bounds.call_depth = usize::try_from(positive)
                        .ok()
                        .and_then(NonZeroUsize::new)
                        .map(Some)
                        .ok_or_else(too_large)?;
                }
                "alloc_bytes" => bounds.alloc_bytes = NonZeroU64::new(positive),
                _ => return Err(format!("`{key}` is not a bound; it takes {keys}")),
            }
        }
        if bounds.is_empty() {
            return Err(format!("names no bound; give one of {keys}, or drop it"));
        }
        Ok(bounds)
    }

    /// Does it bound nothing?
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.steps.is_none() && self.call_depth.is_none() && self.alloc_bytes.is_none()
    }

    /// The bounds as the runtime meets them with the process's: each key
    /// left out is no bound.
    #[must_use]
    pub fn execution(self) -> ExecutionBounds {
        ExecutionBounds {
            max_steps: self.steps.map(NonZeroUsize::get),
            max_call_depth: self.call_depth.map_or(usize::MAX, NonZeroUsize::get),
            max_alloc_bytes: self.alloc_bytes.map(NonZeroU64::get),
            ..ExecutionBounds::UNBOUNDED
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn declared(settings: &str) -> Result<Bounds, String> {
        crate::read_bluefile(&format!(
            "package(\"app\", \"0.1.0\")\nbounds({settings})\n"
        ))
        .map(|bf| bf.project.bounds.expect("declared"))
        .map_err(|e| e.to_string())
    }

    #[test]
    fn each_key_is_optional_and_each_names_its_bound() {
        let b = declared("{steps: 100_000}").expect("steps alone");
        assert_eq!(b.steps.map(NonZeroUsize::get), Some(100_000));
        assert_eq!((b.call_depth, b.alloc_bytes), (None, None));
        let all =
            declared("{steps: 5, call_depth: 7, alloc_bytes: 67_108_864}").expect("all three");
        let e = all.execution();
        assert_eq!(e.max_steps, Some(5));
        assert_eq!(e.max_call_depth, 7);
        assert_eq!(e.max_alloc_bytes, Some(64 << 20));
    }

    #[test]
    fn a_key_left_out_is_no_bound_so_the_meet_is_the_operators() {
        let b = declared("{alloc_bytes: 1024}").expect("reads");
        let operator = ExecutionBounds {
            max_steps: Some(9),
            ..ExecutionBounds::DEFAULT
        };
        let met = operator.meet(b.execution());
        assert_eq!(met.max_steps, Some(9));
        assert_eq!(met.max_call_depth, operator.max_call_depth);
        assert_eq!(met.max_alloc_bytes, Some(1024));
        assert_eq!(met.guest_max_alloc_bytes, operator.guest_max_alloc_bytes);
    }

    #[test]
    fn a_bound_past_the_operators_does_not_widen_it() {
        let b = declared("{steps: 1_000_000, call_depth: 1_000_000, alloc_bytes: 1_073_741_824}")
            .expect("reads");
        let operator = ExecutionBounds {
            max_steps: Some(10),
            max_call_depth: 20,
            max_alloc_bytes: Some(30),
            guest_max_alloc_bytes: None,
        };
        assert_eq!(operator.meet(b.execution()), operator);
        assert_eq!(b.execution().meet(operator), operator);
    }

    #[test]
    fn zero_a_negative_a_float_an_unknown_key_and_an_empty_map_are_refused() {
        for (src, says) in [
            ("{steps: 0}", "`steps` must be a positive integer, got 0"),
            (
                "{call_depth: -3}",
                "`call_depth` must be a positive integer, got -3",
            ),
            (
                "{alloc_bytes: 1.5}",
                "`alloc_bytes` must be a positive integer",
            ),
            ("{memory: 5}", "`memory` is not a bound"),
            ("{}", "names no bound"),
            ("5", "settings must be a map"),
        ] {
            let why = declared(src).expect_err(src);
            assert!(
                why.contains(says) && why.contains("`bounds`"),
                "{src}: {why}"
            );
        }
    }

    #[test]
    fn a_second_declaration_is_refused() {
        let why = crate::read_bluefile(
            "package(\"app\", \"0.1.0\")\nbounds({steps: 5})\nbounds({call_depth: 5})\n",
        )
        .expect_err("twice");
        assert!(why.to_string().contains("twice"), "{why}");
    }

    #[test]
    fn a_record_is_consistent_only_with_the_bounds_its_bluefile_declares() {
        let bf = |extra: &str| {
            crate::read_bluefile(&format!("package(\"app\", \"0.1.0\")\n{extra}")).unwrap()
        };
        let record = |bounds: serde_json::Value| -> crate::capabilities::CapabilityRecord {
            let mut r = serde_json::json!({
                "unit": "definition",
                "floor": [],
                "packages": {"app": []},
            });
            if !bounds.is_null() {
                r["bounds"] = bounds;
            }
            serde_json::from_value(r).unwrap()
        };
        let declared = bf("bounds({steps: 5})\n");
        let consistent = crate::capabilities::consistent;
        assert!(crate::capabilities::declared(&declared));
        assert!(
            !consistent(&declared, None),
            "declared bounds need their record"
        );
        assert!(consistent(
            &declared,
            Some(&record(serde_json::json!({"steps": 5})))
        ));
        assert!(!consistent(
            &declared,
            Some(&record(serde_json::json!({"steps": 6})))
        ));
        assert!(!consistent(
            &declared,
            Some(&record(serde_json::Value::Null))
        ));
        assert!(!consistent(
            &bf(""),
            Some(&record(serde_json::json!({"steps": 5})))
        ));
        assert!(!consistent(
            &bf("allow([])\n"),
            Some(&record(serde_json::json!({"steps": 5})))
        ));
    }

    #[test]
    fn a_recorded_zero_does_not_read() {
        assert!(serde_json::from_str::<Bounds>(r#"{"steps":0}"#).is_err());
        assert!(serde_json::from_str::<Bounds>(r#"{"steps":3,"wall_ms":1}"#).is_err());
        let b: Bounds = serde_json::from_str(r#"{"alloc_bytes":4096}"#).expect("reads");
        assert_eq!(
            serde_json::to_string(&b).expect("writes"),
            r#"{"alloc_bytes":4096}"#
        );
    }
}
