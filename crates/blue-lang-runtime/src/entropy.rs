//! Random bytes from the operating system, as `random_bytes(n)`.
//!
//! Installed by [`crate::sys::install_sys_stdlib`] and granted to a frame only
//! through `Capability::Entropy`. The source is the kernel's non-blocking
//! device, read with std alone: no C, no `-sys` crate.

use std::fs::File;
use std::io::Read;
use std::path::Path;

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

pub const MAX_BYTES: usize = 1 << 20;
pub const SOURCE: &str = "/dev/urandom";

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum EntropyError {
    #[error("random_bytes: the count must be an integer; got {got}")]
    NotACount { got: &'static str },
    #[error("random_bytes: the count is {count}; it must be 0..={MAX_BYTES}")]
    CountOutOfRange { count: i64 },
    #[error("random_bytes: the entropy source {path} could not be read: {reason}")]
    Unavailable { path: String, reason: String },
}

pub fn count_of(v: &Value) -> Result<usize, EntropyError> {
    match v {
        Value::Int(n) => usize::try_from(*n)
            .ok()
            .filter(|n| *n <= MAX_BYTES)
            .ok_or(EntropyError::CountOutOfRange { count: *n }),
        other => Err(EntropyError::NotACount {
            got: other.type_name(),
        }),
    }
}

pub fn fill_from<R: Read>(
    reader: &mut R,
    source: &str,
    count: usize,
) -> Result<Vec<u8>, EntropyError> {
    let mut bytes = vec![0u8; count];
    reader
        .read_exact(&mut bytes)
        .map_err(|e| EntropyError::Unavailable {
            path: source.to_string(),
            reason: e.to_string(),
        })?;
    Ok(bytes)
}

pub fn random_vec_from(path: &Path, count: usize) -> Result<Vec<u8>, EntropyError> {
    let name = path.display().to_string();
    let mut file = File::open(path).map_err(|e| EntropyError::Unavailable {
        path: name.clone(),
        reason: e.to_string(),
    })?;
    fill_from(&mut file, &name, count)
}

pub fn random_vec(count: usize) -> Result<Vec<u8>, EntropyError> {
    random_vec_from(Path::new(SOURCE), count)
}

pub fn install_entropy<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "random_bytes",
        Arity::Exact(1),
        |a: &[Value], _h: &mut H, span| {
            let raised =
                |e: EntropyError| EvalError::native_fn("random_bytes", e.to_string(), span);
            let count = count_of(&a[0]).map_err(raised)?;
            let bytes = random_vec(count).map_err(raised)?;
            Ok(Value::list(
                bytes.into_iter().map(|b| Value::Int(i64::from(b))),
            ))
        },
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(src: &str) -> Value {
        crate::run(src)
            .unwrap_or_else(|e| panic!("{src:?}: {e}"))
            .value
    }

    fn run_err(src: &str) -> String {
        crate::run(src)
            .map(|r| r.value)
            .expect_err("must raise")
            .to_string()
    }

    fn bytes_of(v: Value) -> Vec<i64> {
        let Value::List(items) = v else {
            panic!("expected a list, got {v:?}")
        };
        items
            .iter()
            .map(|i| match i {
                Value::Int(n) => *n,
                other => panic!("not an integer: {other:?}"),
            })
            .collect()
    }

    #[test]
    fn a_draw_has_the_requested_length_of_byte_integers() {
        for n in [1usize, 16, 32, 1000] {
            let got = bytes_of(run(&format!("random_bytes({n})")));
            assert_eq!(got.len(), n);
            assert!(got.iter().all(|b| (0..=255).contains(b)));
        }
    }

    #[test]
    fn zero_bytes_is_the_empty_list() {
        assert!(bytes_of(run("random_bytes(0)")).is_empty());
    }

    #[test]
    fn the_largest_draw_is_allowed() {
        assert_eq!(
            bytes_of(run(&format!("random_bytes({MAX_BYTES})"))).len(),
            MAX_BYTES
        );
    }

    #[test]
    fn a_draw_is_not_constant_and_two_draws_differ() {
        let a = bytes_of(run("random_bytes(64)"));
        let b = bytes_of(run("random_bytes(64)"));
        assert!(a.iter().any(|x| *x != a[0]), "64 identical bytes: {a:?}");
        assert_ne!(a, b);
    }

    #[test]
    fn every_byte_value_appears_in_a_large_draw() {
        let seen: std::collections::BTreeSet<i64> =
            bytes_of(run("random_bytes(65536)")).into_iter().collect();
        assert_eq!(seen.len(), 256);
    }

    #[test]
    fn a_negative_count_is_refused() {
        let e = run_err("random_bytes(-1)");
        assert!(e.contains("-1") && e.contains("0..="), "{e}");
    }

    #[test]
    fn a_count_over_the_limit_is_refused() {
        let e = run_err(&format!("random_bytes({})", MAX_BYTES + 1));
        assert!(e.contains(&(MAX_BYTES + 1).to_string()), "{e}");
    }

    #[test]
    fn a_count_that_is_not_an_integer_is_refused() {
        for src in [
            "random_bytes(\"8\")",
            "random_bytes(nil)",
            "random_bytes(2.5)",
        ] {
            let e = run_err(src);
            assert!(e.contains("must be an integer"), "{src}: {e}");
        }
    }

    #[test]
    fn a_missing_source_is_a_named_error_not_zeros() {
        let e = random_vec_from(Path::new("/nonexistent/entropy"), 4).expect_err("must fail");
        assert!(matches!(e, EntropyError::Unavailable { .. }));
        assert!(e.to_string().contains("/nonexistent/entropy"), "{e}");
    }

    #[test]
    fn a_source_that_ends_early_is_an_error_not_a_short_draw() {
        let mut short: &[u8] = &[1, 2, 3];
        let e = fill_from(&mut short, "short", 8).expect_err("must fail");
        assert!(matches!(e, EntropyError::Unavailable { .. }));
        let mut exact: &[u8] = &[1, 2, 3];
        assert_eq!(
            fill_from(&mut exact, "exact", 3).expect("fills"),
            vec![1, 2, 3]
        );
    }

    #[test]
    fn the_arity_is_one() {
        assert!(run_err("random_bytes()").contains("random_bytes"));
        assert!(run_err("random_bytes(1, 2)").contains("random_bytes"));
    }
}
