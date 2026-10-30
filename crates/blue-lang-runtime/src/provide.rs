//! The pure providers a frame binds in place of the host
//! ([`blue_lang_waku::Provision`]): a stepped clock, a seeded entropy
//! stream, and a filesystem in memory or nowhere. Each interpreter gets its
//! own provider state, as each process owns its interpreter.

use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex, MutexGuard};

use blue_lang_waku::{Provision, Provisions};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::sys::{arg_int, arg_str};

/// Bind every provider in `provisions` into `interp`, over whatever the
/// host or a refusal bound to the same names.
pub fn provide<H: 'static>(interp: &mut Interpreter<H>, provisions: &Provisions) {
    for p in provisions.iter() {
        match p {
            Provision::SteppedClock { at_ms, step_ms } => clock(interp, *at_ms, *step_ms),
            Provision::SeededEntropy { seed } => entropy(interp, seed),
            Provision::MemoryFs => filesystem(interp, true),
            Provision::NullFs => filesystem(interp, false),
        }
    }
}

fn locked<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn str_value(s: impl Into<String>) -> Value {
    Value::Str(Arc::from(s.into()))
}

fn clock<H: 'static>(interp: &mut Interpreter<H>, at_ms: i64, step_ms: i64) {
    let t = Arc::new(Mutex::new(at_ms));
    let read = {
        let t = Arc::clone(&t);
        Arc::new(move || {
            let mut g = locked(&t);
            let now = *g;
            *g = g.saturating_add(step_ms);
            now
        })
    };
    let advance = Arc::new(move |ms: i64| {
        let mut g = locked(&t);
        *g = g.saturating_add(ms.max(0));
    });
    let r = Arc::clone(&read);
    interp.register_fn(
        "now_ms",
        Arity::Exact(0),
        move |_: &[Value], _: &mut H, _| Ok(Value::Int(r())),
    );
    let r = Arc::clone(&read);
    interp.register_fn("now", Arity::Exact(0), move |_: &[Value], _: &mut H, _| {
        Ok(Value::Int(r().div_euclid(1000)))
    });
    let r = Arc::clone(&read);
    interp.register_fn(
        "now_ns",
        Arity::Exact(0),
        move |_: &[Value], _: &mut H, _| Ok(Value::Int(r().saturating_mul(1_000_000))),
    );
    let r = Arc::clone(&read);
    interp.register_fn(
        "now_rfc3339",
        Arity::Exact(0),
        move |_: &[Value], _: &mut H, _| {
            Ok(str_value(crate::sys::format_rfc3339_utc(
                r().div_euclid(1000),
            )))
        },
    );
    let r = Arc::clone(&read);
    interp.register_fn(
        "elapsed_since",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let start = arg_int(&a[0], "elapsed_since", span)?;
            Ok(Value::Int(
                r().saturating_mul(1_000_000).saturating_sub(start),
            ))
        },
    );
    let adv = Arc::clone(&advance);
    interp.register_fn(
        "sleep",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            adv(arg_int(&a[0], "sleep", span)?.saturating_mul(1000));
            Ok(Value::Nil)
        },
    );
    interp.register_fn(
        "sleep_ms",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            advance(arg_int(&a[0], "sleep_ms", span)?);
            Ok(Value::Nil)
        },
    );
}

fn entropy<H: 'static>(interp: &mut Interpreter<H>, seed: &str) {
    let stream = Mutex::new(
        blake3::Hasher::new_derive_key("blue seeded-entropy 2026-10-30")
            .update(seed.as_bytes())
            .finalize_xof(),
    );
    interp.register_fn(
        "random_bytes",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let count = crate::entropy::count_of(&a[0])
                .map_err(|e| EvalError::native_fn("random_bytes", e.to_string(), span))?;
            let mut bytes = vec![0u8; count];
            locked(&stream).fill(&mut bytes);
            Ok(Value::list(
                bytes.into_iter().map(|b| Value::Int(i64::from(b))),
            ))
        },
    );
}

#[derive(Default)]
struct Tree {
    files: BTreeMap<String, String>,
    dirs: BTreeSet<String>,
}

impl Tree {
    fn is_dir(&self, p: &str) -> bool {
        p == "/" || self.dirs.contains(p)
    }

    fn parents(&mut self, p: &str) {
        let mut at = parent(p);
        while at != "/" {
            self.dirs.insert(at.clone());
            at = parent(&at);
        }
    }

    fn under<'a>(&'a self, root: &'a str) -> impl Iterator<Item = &'a String> + 'a {
        let prefix = if root == "/" {
            "/".to_string()
        } else {
            format!("{root}/")
        };
        self.files.keys().filter(move |f| f.starts_with(&prefix))
    }
}

fn absolute(p: &str) -> String {
    let parts: Vec<&str> = p
        .split('/')
        .filter(|s| !s.is_empty() && *s != ".")
        .collect();
    format!("/{}", parts.join("/"))
}

fn parent(p: &str) -> String {
    match p.rfind('/') {
        Some(0) | None => "/".to_string(),
        Some(i) => p[..i].to_string(),
    }
}

fn absent(word: &'static str, path: &str, span: tatara_lisp::Span) -> EvalError {
    EvalError::native_fn(
        word,
        format!("{path}: no such file or directory (virtual filesystem)"),
        span,
    )
}

fn segments_match(pattern: &[&str], path: &[&str]) -> bool {
    match (pattern.first(), path.first()) {
        (None, None) => true,
        (Some(&"**"), _) => {
            segments_match(&pattern[1..], path)
                || (!path.is_empty() && segments_match(pattern, &path[1..]))
        }
        (Some(p), Some(s)) => {
            crate::sys::glob_match(p, s) && segments_match(&pattern[1..], &path[1..])
        }
        _ => false,
    }
}

#[allow(clippy::too_many_lines)]
fn filesystem<H: 'static>(interp: &mut Interpreter<H>, keep: bool) {
    let tree = Arc::new(Mutex::new(Tree::default()));
    let path_of = |a: &Value, word: &'static str, span| -> Result<String, EvalError> {
        Ok(absolute(&arg_str(a, word, span)?))
    };

    let t = Arc::clone(&tree);
    interp.register_fn(
        "read_file",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "read_file", span)?;
            locked(&t)
                .files
                .get(&p)
                .map(|s| str_value(s.clone()))
                .ok_or_else(|| absent("read_file", &p, span))
        },
    );

    let write = {
        let t = Arc::clone(&tree);
        Arc::new(move |p: String, text: String, append: bool| {
            if keep {
                let mut g = locked(&t);
                g.parents(&p);
                let slot = g.files.entry(p).or_default();
                if !append {
                    slot.clear();
                }
                slot.push_str(&text);
            }
        })
    };
    let w = Arc::clone(&write);
    interp.register_fn(
        "write_file",
        Arity::Exact(2),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "write_file", span)?;
            w(p, arg_str(&a[1], "write_file", span)?.to_string(), false);
            Ok(Value::Nil)
        },
    );
    let w = Arc::clone(&write);
    interp.register_fn(
        "append_file",
        Arity::Exact(2),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "append_file", span)?;
            w(p, arg_str(&a[1], "append_file", span)?.to_string(), true);
            Ok(Value::Nil)
        },
    );
    let w = Arc::clone(&write);
    interp.register_fn(
        "write_program",
        Arity::Exact(2),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "write_program", span)?;
            let source = arg_str(&a[1], "write_program", span)?;
            let canonical = blue_lang_fmt::format_source_lossless(&source).map_err(|e| {
                EvalError::native_fn(
                    "write_program",
                    format!("{p}: the program does not parse: {e}"),
                    span,
                )
            })?;
            w(p, canonical, false);
            Ok(Value::Nil)
        },
    );

    let t = Arc::clone(&tree);
    interp.register_fn(
        "file_size",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "file_size", span)?;
            let len = locked(&t)
                .files
                .get(&p)
                .map(String::len)
                .ok_or_else(|| absent("file_size", &p, span))?;
            Ok(Value::Int(i64::try_from(len).unwrap_or(i64::MAX)))
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "file_mtime_ms",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "file_mtime_ms", span)?;
            if locked(&t).files.contains_key(&p) {
                Ok(Value::Int(0))
            } else {
                Err(absent("file_mtime_ms", &p, span))
            }
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "is_file?",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "is_file?", span)?;
            Ok(Value::Bool(locked(&t).files.contains_key(&p)))
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "is_dir?",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "is_dir?", span)?;
            Ok(Value::Bool(locked(&t).is_dir(&p)))
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "path_exists",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "path_exists", span)?;
            let g = locked(&t);
            Ok(Value::Bool(g.files.contains_key(&p) || g.is_dir(&p)))
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "ls",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "ls", span)?;
            let g = locked(&t);
            if !g.is_dir(&p) {
                return Err(absent("ls", &p, span));
            }
            let entries: BTreeSet<String> = g
                .files
                .keys()
                .chain(g.dirs.iter())
                .filter(|e| *e != &p && parent(e) == p)
                .cloned()
                .collect();
            Ok(Value::list(entries.into_iter().map(str_value)))
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "walk_dir",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "walk_dir", span)?;
            let g = locked(&t);
            Ok(Value::list(g.under(&p).cloned().map(str_value)))
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "glob",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let pattern = arg_str(&a[0], "glob", span)?;
            if pattern.starts_with('/') {
                return Ok(Value::list(Vec::<Value>::new()));
            }
            let wanted: Vec<&str> = pattern.split('/').filter(|s| !s.is_empty()).collect();
            let g = locked(&t);
            let hits: Vec<Value> = g
                .files
                .keys()
                .filter(|f| {
                    let rel: Vec<&str> = f.split('/').filter(|s| !s.is_empty()).collect();
                    segments_match(&wanted, &rel)
                })
                .map(|f| str_value(f.trim_start_matches('/')))
                .collect();
            Ok(Value::list(hits))
        },
    );
    for word in ["mkdir", "mkdir_p"] {
        let t = Arc::clone(&tree);
        interp.register_fn(
            word,
            Arity::Exact(1),
            move |a: &[Value], _: &mut H, span| {
                let p = path_of(&a[0], word, span)?;
                if keep && p != "/" {
                    let mut g = locked(&t);
                    g.parents(&p);
                    g.dirs.insert(p);
                }
                Ok(Value::Nil)
            },
        );
    }
    let t = Arc::clone(&tree);
    interp.register_fn(
        "rm",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "rm", span)?;
            locked(&t)
                .files
                .remove(&p)
                .map(|_| Value::Nil)
                .ok_or_else(|| absent("rm", &p, span))
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "rm_rf",
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let p = path_of(&a[0], "rm_rf", span)?;
            let mut g = locked(&t);
            let prefix = format!("{p}/");
            g.files.retain(|f, _| *f != p && !f.starts_with(&prefix));
            g.dirs.retain(|d| *d != p && !d.starts_with(&prefix));
            Ok(Value::Nil)
        },
    );
    let t = Arc::clone(&tree);
    interp.register_fn(
        "rename_file",
        Arity::Exact(2),
        move |a: &[Value], _: &mut H, span| {
            let from = path_of(&a[0], "rename_file", span)?;
            let to = path_of(&a[1], "rename_file", span)?;
            let mut g = locked(&t);
            let text = g
                .files
                .remove(&from)
                .ok_or_else(|| absent("rename_file", &from, span))?;
            g.parents(&to);
            g.files.insert(to, text);
            Ok(Value::Nil)
        },
    );
    interp.register_fn("cwd", Arity::Exact(0), |_: &[Value], _: &mut H, _| {
        Ok(str_value("/"))
    });
    crate::sys::install_path_words(interp);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(provisions: &[Provision], src: &str) -> Result<String, String> {
        let mut interp = crate::interpreter_hostless();
        let mut ps = Provisions::default();
        for p in provisions {
            ps.add(p.clone()).unwrap();
        }
        provide(&mut interp, &ps);
        let forms = tatara_lisp::read_spanned(src).map_err(|e| e.to_string())?;
        interp
            .eval_program(&forms, &mut ())
            .map(|v| v.to_string())
            .map_err(|e| e.to_string())
    }

    fn ok(provisions: &[Provision], src: &str) -> String {
        eval(provisions, src).unwrap_or_else(|e| panic!("{src}: {e}"))
    }

    #[test]
    fn a_stepped_clock_reads_its_start_and_steps_and_a_sleep_advances_without_waiting() {
        let c = [Provision::SteppedClock {
            at_ms: 1_000,
            step_ms: 10,
        }];
        assert_eq!(
            ok(&c, "(list (now_ms) (now_ms) (now_ms))"),
            "(1000 1010 1020)"
        );
        let started = std::time::Instant::now();
        assert_eq!(ok(&c, "(begin (sleep_ms 60000) (now_ms))"), "61000");
        assert!(started.elapsed() < std::time::Duration::from_secs(5));
        assert_eq!(ok(&c, "(begin (sleep 2) (now))"), "3");
        let fixed = [Provision::SteppedClock {
            at_ms: 86_400_000,
            step_ms: 0,
        }];
        assert_eq!(
            ok(&fixed, "(list (now_ms) (now_ms))"),
            "(86400000 86400000)"
        );
        assert_eq!(ok(&fixed, "(now_rfc3339)"), "\"1970-01-02T00:00:00Z\"");
        assert_eq!(ok(&fixed, "(elapsed_since (now_ns))"), "0");
    }

    #[test]
    fn seeded_entropy_is_one_stream_per_seed() {
        let a = [Provision::SeededEntropy { seed: "a".into() }];
        let b = [Provision::SeededEntropy { seed: "b".into() }];
        let first = ok(&a, "(random_bytes 8)");
        assert_eq!(
            first,
            ok(&a, "(random_bytes 8)"),
            "the same seed gives the same bytes"
        );
        assert_ne!(
            first,
            ok(&b, "(random_bytes 8)"),
            "another seed gives others"
        );
        let two = ok(&a, "(list (random_bytes 4) (random_bytes 4))");
        assert_ne!(
            two,
            format!("({0} {0})", ok(&a, "(random_bytes 4)")),
            "the stream moves on"
        );
        assert!(eval(&a, "(random_bytes -1)").is_err());
    }

    #[test]
    fn a_memory_filesystem_keeps_what_the_run_writes() {
        let m = [Provision::MemoryFs];
        assert_eq!(
            ok(&m, "(begin (write_file \"a/b.txt\" \"hi\") (append_file \"/a/b.txt\" \"!\") (list (read_file \"/a/b.txt\") (is_dir? \"/a\") (is_file? \"a/b.txt\") (file_size \"a/b.txt\") (ls \"/a\") (glob \"**/*.txt\") (cwd)))"),
            "(\"hi!\" #t #t 3 (\"/a/b.txt\") (\"a/b.txt\") \"/\")"
        );
        assert_eq!(
            ok(&m, "(begin (write_file \"x\" \"1\") (rename_file \"x\" \"d/y\") (list (path_exists \"x\") (read_file \"d/y\") (walk_dir \"/\") (begin (rm_rf \"d\") (walk_dir \"/\"))))"),
            "(#f \"1\" (\"/d/y\") ())"
        );
        assert!(eval(&m, "(read_file \"/etc/hosts\")")
            .unwrap_err()
            .contains("virtual filesystem"));
        assert!(eval(&m, "(rm \"nothing\")").is_err());
        assert_eq!(ok(&m, "(path_join \"a\" \"b\")"), "\"a/b\"");
    }

    #[test]
    fn a_null_filesystem_drops_every_write() {
        let n = [Provision::NullFs];
        assert_eq!(
            ok(&n, "(begin (write_file \"a\" \"x\") (mkdir_p \"d\") (list (path_exists \"a\") (is_dir? \"d\") (walk_dir \"/\")))"),
            "(#f #f ())"
        );
        assert!(eval(&n, "(read_file \"a\")").is_err());
    }

    #[test]
    fn a_provider_replaces_every_name_of_its_capability_and_no_other() {
        use blue_lang_waku::Capability;
        let mut interp = crate::interpreter_hostless();
        let refused: Vec<_> = [Capability::FileSystem, Capability::Environment]
            .into_iter()
            .flat_map(|c| c.names().into_iter().map(move |n| (n, c)))
            .collect();
        crate::refuse_host_names(&mut interp, &refused, "the test");
        let mut ps = Provisions::default();
        ps.add(Provision::MemoryFs).unwrap();
        provide(&mut interp, &ps);
        let breaches = |name: &str, interp: &mut Interpreter<()>| {
            let forms = tatara_lisp::read_spanned(&format!("({name})")).unwrap();
            matches!(interp.eval_program(&forms, &mut ()), Err(e) if crate::is_breach(&e))
        };
        for name in Capability::FileSystem.names() {
            assert!(!breaches(name, &mut interp), "{name} is provided");
        }
        assert!(breaches("getenv", &mut interp), "environment stays refused");
    }
}
