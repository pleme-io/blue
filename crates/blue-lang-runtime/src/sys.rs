//! Host-side system primitives — process, filesystem, environment, clock.
//!
//! This is the one part of the runtime that **cannot** be part of the
//! `wasm32-unknown-unknown` build: every primitive here is a host import —
//! a process to fork, a file to open, a clock to read. It is therefore gated
//! behind the `sys` cargo feature, OFF by default, and only `blue-lang-cli`
//! turns it on. The wasm consumer keeps its zero-host-import surface by
//! construction, not by luck.
//!
//! Names are snake_case. blue's identifiers cannot carry `-` (it is an
//! operator), so the substrate's `exec-capture` is spelled `exec_capture`
//! here — see `bidamas/AUTHORING.md`.
//!
//! ```text
//! exec_capture(cmd, arg…)    → ((:status N) (:stdout "…") (:stderr "…"))
//! exec_check(cmd, arg…)      → exit code (streams to parent)
//! exec_ok?(cmd, arg…)        → bool; true iff exit code is 0
//! sh_exec(script)            → capture form; script through `sh -c`
//! exec_with_stdin(payload, cmd, arg…) → capture form
//! exec_with_env(pairs, cmd, arg…)    → capture form
//!
//! read_file(path)            → contents as a string
//! write_file(path, contents) → nil
//! append_file(path, contents)→ nil
//! file_size(path)            → bytes
//! file_mtime_ms(path)        → unix milliseconds of last modification
//! is_dir?(path)              → bool
//! is_file?(path)             → bool
//! path_exists(path)          → bool
//! glob(pattern)              → list of matching paths
//! walk_dir(path)             → flat list of every file under path
//! ls(path)                   → list of entries directly inside path
//! mkdir(path) / mkdir_p(path)→ nil
//! rm(path) / rm_rf(path)     → nil
//! path_join(a, b…) / path_basename / path_dirname / path_extension / cwd
//!
//! getenv(name[, default])    → string or nil (or default)
//! env_required(name)         → string, or raises
//! argv()                     → list of strings
//! argv_get(n[, default])     → nth arg, or nil (or default)
//!
//! now() / now_ms() / now_ns()→ unix time in the named unit
//! now_rfc3339()              → "1970-01-01T00:00:00Z"
//! sleep(secs) / sleep_ms(ms) → nil, blocks
//! elapsed_since(start_ns)    → ns since start (from `now_ns`)
//! ```

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

/// Install blue's host-side system surface. Only reachable when the `sys`
/// cargo feature is on; the wasm consumer never enables it.
pub fn install_sys_stdlib<H: 'static>(interp: &mut Interpreter<H>) {
    install_process(interp);
    install_fs(interp);
    install_env(interp);
    install_clock(interp);
}

// ── process ──────────────────────────────────────────────────────────────

fn install_process<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "exec_check",
        Arity::AtLeast(1),
        |args: &[Value], _h: &mut H, span| {
            let (cmd, rest) = split_cmd(args, "exec_check", span)?;
            let status = Command::new(&*cmd)
                .args(rest.iter().map(|s| s.as_ref()))
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()
                .map_err(|e| EvalError::native_fn("exec_check", e.to_string(), span))?;
            Ok(Value::Int(status.code().unwrap_or(-1) as i64))
        },
    );

    interp.register_fn(
        "exec_ok?",
        Arity::AtLeast(1),
        |args: &[Value], _h: &mut H, span| {
            let (cmd, rest) = split_cmd(args, "exec_ok?", span)?;
            let status = Command::new(&*cmd)
                .args(rest.iter().map(|s| s.as_ref()))
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map_err(|e| EvalError::native_fn("exec_ok?", e.to_string(), span))?;
            Ok(Value::Bool(status.success()))
        },
    );

    interp.register_fn(
        "exec_capture",
        Arity::AtLeast(1),
        |args: &[Value], _h: &mut H, span| {
            let (cmd, rest) = split_cmd(args, "exec_capture", span)?;
            let out = Command::new(&*cmd)
                .args(rest.iter().map(|s| s.as_ref()))
                .stdin(Stdio::null())
                .output()
                .map_err(|e| EvalError::native_fn("exec_capture", e.to_string(), span))?;
            Ok(capture_result(&out))
        },
    );

    interp.register_fn(
        "exec_with_stdin",
        Arity::AtLeast(2),
        |args: &[Value], _h: &mut H, span| {
            use std::io::Write;
            let payload = arg_str(&args[0], "exec_with_stdin", span)?;
            let (cmd, rest) = split_cmd(&args[1..], "exec_with_stdin", span)?;
            let mut child = Command::new(&*cmd)
                .args(rest.iter().map(|s| s.as_ref()))
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .map_err(|e| EvalError::native_fn("exec_with_stdin", e.to_string(), span))?;
            // `take()` so the pipe is dropped before we wait — a tool reading
            // stdin to EOF deadlocks otherwise.
            if let Some(mut sink) = child.stdin.take() {
                sink.write_all(payload.as_bytes())
                    .map_err(|e| EvalError::native_fn("exec_with_stdin", e.to_string(), span))?;
            }
            let out = child
                .wait_with_output()
                .map_err(|e| EvalError::native_fn("exec_with_stdin", e.to_string(), span))?;
            Ok(capture_result(&out))
        },
    );

    interp.register_fn(
        "exec_with_env",
        Arity::AtLeast(2),
        |args: &[Value], _h: &mut H, span| {
            let pairs = env_pairs(&args[0], "exec_with_env", span)?;
            let (cmd, rest) = split_cmd(&args[1..], "exec_with_env", span)?;
            let mut c = Command::new(&*cmd);
            c.args(rest.iter().map(|s| s.as_ref()))
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());
            for (k, v) in &pairs {
                c.env(k.as_ref(), v.as_ref());
            }
            let out = c
                .output()
                .map_err(|e| EvalError::native_fn("exec_with_env", e.to_string(), span))?;
            Ok(capture_result(&out))
        },
    );

    interp.register_fn(
        "sh_exec",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let script = arg_str(&args[0], "sh_exec", span)?;
            let out = Command::new("sh")
                .arg("-c")
                .arg(&*script)
                .stdin(Stdio::null())
                .output()
                .map_err(|e| EvalError::native_fn("sh_exec", e.to_string(), span))?;
            Ok(capture_result(&out))
        },
    );
}

fn split_cmd(
    args: &[Value],
    fname: &'static str,
    span: tatara_lisp::Span,
) -> Result<(Arc<str>, Vec<Arc<str>>), EvalError> {
    let mut it = args.iter();
    let cmd = arg_str(
        it.next()
            .ok_or_else(|| EvalError::native_fn(fname, "expected at least 1 argument", span))?,
        fname,
        span,
    )?;
    let rest = it.map(|v| arg_str(v, fname, span)).collect::<Result<Vec<_>, _>>()?;
    Ok((cmd, rest))
}

/// Read an alist of `(KEY VALUE)` string pairs. Rejects a malformed entry
/// rather than skipping it — a silently-dropped pair would run the child
/// WITHOUT the credential and report success.
fn env_pairs(
    v: &Value,
    fname: &'static str,
    span: tatara_lisp::Span,
) -> Result<Vec<(Arc<str>, Arc<str>)>, EvalError> {
    let items = match v {
        Value::List(items) => items,
        _ => {
            return Err(EvalError::native_fn(
                fname,
                "first argument must be an alist of (KEY VALUE) pairs",
                span,
            ));
        }
    };
    let mut out = Vec::with_capacity(items.len());
    for it in items.iter() {
        match it {
            Value::List(kv) if kv.len() == 2 => {
                out.push((arg_str(&kv[0], fname, span)?, arg_str(&kv[1], fname, span)?));
            }
            _ => {
                return Err(EvalError::native_fn(
                    fname,
                    "each env entry must be a 2-element (KEY VALUE) list",
                    span,
                ));
            }
        }
    }
    Ok(out)
}

fn capture_result(out: &std::process::Output) -> Value {
    Value::list(vec![
        Value::list(vec![
            Value::Keyword(Arc::from("status")),
            Value::Int(out.status.code().unwrap_or(-1) as i64),
        ]),
        Value::list(vec![
            Value::Keyword(Arc::from("stdout")),
            Value::Str(Arc::from(String::from_utf8_lossy(&out.stdout).as_ref())),
        ]),
        Value::list(vec![
            Value::Keyword(Arc::from("stderr")),
            Value::Str(Arc::from(String::from_utf8_lossy(&out.stderr).as_ref())),
        ]),
    ])
}

// ── filesystem ───────────────────────────────────────────────────────────

fn install_fs<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "read_file",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "read_file", span)?;
            let contents = std::fs::read_to_string(&*path)
                .map_err(|e| EvalError::native_fn("read_file", format!("{path}: {e}"), span))?;
            Ok(Value::Str(Arc::from(contents)))
        },
    );

    interp.register_fn(
        "write_file",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "write_file", span)?;
            let contents = arg_str(&args[1], "write_file", span)?;
            std::fs::write(&*path, contents.as_bytes())
                .map_err(|e| EvalError::native_fn("write_file", format!("{path}: {e}"), span))?;
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "append_file",
        Arity::Exact(2),
        |args: &[Value], _h: &mut H, span| {
            use std::io::Write;
            let path = arg_str(&args[0], "append_file", span)?;
            let contents = arg_str(&args[1], "append_file", span)?;
            let mut f = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&*path)
                .map_err(|e| EvalError::native_fn("append_file", format!("{path}: {e}"), span))?;
            f.write_all(contents.as_bytes())
                .map_err(|e| EvalError::native_fn("append_file", format!("{path}: {e}"), span))?;
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "file_size",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "file_size", span)?;
            let meta = std::fs::metadata(&*path)
                .map_err(|e| EvalError::native_fn("file_size", format!("{path}: {e}"), span))?;
            Ok(Value::Int(meta.len() as i64))
        },
    );

    interp.register_fn(
        "file_mtime_ms",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "file_mtime_ms", span)?;
            let meta = std::fs::metadata(&*path)
                .map_err(|e| EvalError::native_fn("file_mtime_ms", format!("{path}: {e}"), span))?;
            let mtime = meta
                .modified()
                .map_err(|e| EvalError::native_fn("file_mtime_ms", format!("{path}: {e}"), span))?;
            let ms = mtime
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);
            Ok(Value::Int(ms))
        },
    );

    interp.register_fn(
        "is_dir?",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "is_dir?", span)?;
            Ok(Value::Bool(Path::new(&*path).is_dir()))
        },
    );

    interp.register_fn(
        "is_file?",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "is_file?", span)?;
            Ok(Value::Bool(Path::new(&*path).is_file()))
        },
    );

    interp.register_fn(
        "path_exists",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "path_exists", span)?;
            Ok(Value::Bool(Path::new(&*path).exists()))
        },
    );

    interp.register_fn(
        "glob",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let pattern = arg_str(&args[0], "glob", span)?;
            let entries =
                simple_glob(&pattern).map_err(|e| EvalError::native_fn("glob", e, span))?;
            Ok(Value::list(
                entries
                    .into_iter()
                    .map(|p| Value::Str(Arc::from(p.to_string_lossy().into_owned())))
                    .collect::<Vec<_>>(),
            ))
        },
    );

    interp.register_fn(
        "walk_dir",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let root = arg_str(&args[0], "walk_dir", span)?;
            let mut out = Vec::new();
            walk_collect(Path::new(&*root), &mut out)
                .map_err(|e| EvalError::native_fn("walk_dir", e.to_string(), span))?;
            Ok(Value::list(
                out.into_iter()
                    .map(|p| Value::Str(Arc::from(p.to_string_lossy().into_owned())))
                    .collect::<Vec<_>>(),
            ))
        },
    );

    interp.register_fn(
        "ls",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let dir = arg_str(&args[0], "ls", span)?;
            let mut entries: Vec<PathBuf> = std::fs::read_dir(&*dir)
                .map_err(|e| EvalError::native_fn("ls", format!("{dir}: {e}"), span))?
                .filter_map(|r| r.ok().map(|e| e.path()))
                .collect();
            entries.sort();
            Ok(Value::list(
                entries
                    .into_iter()
                    .map(|p| Value::Str(Arc::from(p.to_string_lossy().into_owned())))
                    .collect::<Vec<_>>(),
            ))
        },
    );

    interp.register_fn(
        "mkdir",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "mkdir", span)?;
            match std::fs::create_dir(&*path) {
                Ok(()) => Ok(Value::Nil),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => Ok(Value::Nil),
                Err(e) => Err(EvalError::native_fn("mkdir", format!("{path}: {e}"), span)),
            }
        },
    );

    interp.register_fn(
        "mkdir_p",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "mkdir_p", span)?;
            std::fs::create_dir_all(&*path)
                .map_err(|e| EvalError::native_fn("mkdir_p", format!("{path}: {e}"), span))?;
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "rm",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "rm", span)?;
            std::fs::remove_file(&*path)
                .map_err(|e| EvalError::native_fn("rm", format!("{path}: {e}"), span))?;
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "rm_rf",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let path = arg_str(&args[0], "rm_rf", span)?;
            if Path::new(&*path).is_dir() {
                std::fs::remove_dir_all(&*path)
                    .map_err(|e| EvalError::native_fn("rm_rf", format!("{path}: {e}"), span))?;
            } else if Path::new(&*path).exists() {
                std::fs::remove_file(&*path)
                    .map_err(|e| EvalError::native_fn("rm_rf", format!("{path}: {e}"), span))?;
            }
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "path_join",
        Arity::AtLeast(1),
        |args: &[Value], _h: &mut H, span| {
            let mut buf = PathBuf::new();
            for v in args {
                let s = arg_str(v, "path_join", span)?;
                buf.push(&*s);
            }
            Ok(Value::Str(Arc::from(buf.to_string_lossy().into_owned())))
        },
    );

    interp.register_fn(
        "path_basename",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let p = arg_str(&args[0], "path_basename", span)?;
            let base = Path::new(&*p)
                .file_name()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
            Ok(Value::Str(Arc::from(base)))
        },
    );

    interp.register_fn(
        "path_dirname",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let p = arg_str(&args[0], "path_dirname", span)?;
            let dir = Path::new(&*p)
                .parent()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
            Ok(Value::Str(Arc::from(dir)))
        },
    );

    interp.register_fn(
        "path_extension",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let p = arg_str(&args[0], "path_extension", span)?;
            let ext = Path::new(&*p)
                .extension()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
            Ok(Value::Str(Arc::from(ext)))
        },
    );

    interp.register_fn(
        "cwd",
        Arity::Exact(0),
        |_args: &[Value], _h: &mut H, span| {
            let d = std::env::current_dir()
                .map_err(|e| EvalError::native_fn("cwd", e.to_string(), span))?;
            Ok(Value::Str(Arc::from(d.to_string_lossy().into_owned())))
        },
    );
}

/// Walk a directory tree, collecting every file (not directories).
fn walk_collect(root: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    let mut stack = vec![root.to_path_buf()];
    while let Some(cur) = stack.pop() {
        if cur.is_file() {
            out.push(cur);
            continue;
        }
        if !cur.is_dir() {
            continue;
        }
        for entry in std::fs::read_dir(&cur)? {
            stack.push(entry?.path());
        }
    }
    Ok(())
}

/// Minimal glob engine supporting `*` (non-slash) and `**` (recursive).
fn simple_glob(pattern: &str) -> Result<Vec<PathBuf>, String> {
    let (prefix, remainder) = split_glob_prefix(pattern);
    let base = if prefix.is_empty() {
        PathBuf::from(".")
    } else {
        PathBuf::from(&prefix)
    };
    let parts: Vec<&str> = remainder.split('/').filter(|s| !s.is_empty()).collect();
    if parts.is_empty() {
        return Ok(vec![base]);
    }
    let mut out = Vec::new();
    walk_glob(&base, &parts, 0, &mut out);
    Ok(out)
}

fn split_glob_prefix(pattern: &str) -> (String, String) {
    let mut literal = String::new();
    let mut rest = String::new();
    let mut found_glob = false;
    for component in pattern.split('/') {
        if !found_glob && !component.contains('*') {
            if !literal.is_empty() {
                literal.push('/');
            }
            literal.push_str(component);
        } else {
            found_glob = true;
            if !rest.is_empty() {
                rest.push('/');
            }
            rest.push_str(component);
        }
    }
    if literal.is_empty() && !found_glob {
        literal = pattern.to_string();
    }
    (literal, rest)
}

fn walk_glob(dir: &Path, parts: &[&str], idx: usize, out: &mut Vec<PathBuf>) {
    if idx >= parts.len() {
        out.push(dir.to_path_buf());
        return;
    }
    let pat = parts[idx];
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    if pat == "**" {
        walk_glob(dir, parts, idx + 1, out);
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                walk_glob(&p, parts, idx, out);
            }
        }
        return;
    }
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_s = name.to_string_lossy();
        if glob_match(pat, &name_s) {
            let p = entry.path();
            if idx + 1 == parts.len() {
                out.push(p);
            } else if p.is_dir() {
                walk_glob(&p, parts, idx + 1, out);
            }
        }
    }
}

fn glob_match(pattern: &str, name: &str) -> bool {
    let mut pi = 0;
    let mut ni = 0;
    let pbytes = pattern.as_bytes();
    let nbytes = name.as_bytes();
    let mut star: Option<(usize, usize)> = None;
    while ni < nbytes.len() {
        if pi < pbytes.len() && (pbytes[pi] == b'?' || pbytes[pi] == nbytes[ni]) {
            pi += 1;
            ni += 1;
        } else if pi < pbytes.len() && pbytes[pi] == b'*' {
            star = Some((pi, ni));
            pi += 1;
        } else if let Some((sp, sn)) = star {
            pi = sp + 1;
            ni = sn + 1;
            star = Some((sp, ni));
        } else {
            return false;
        }
    }
    while pi < pbytes.len() && pbytes[pi] == b'*' {
        pi += 1;
    }
    pi == pbytes.len()
}

// ── environment ──────────────────────────────────────────────────────────

fn install_env<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "getenv",
        Arity::Range(1, 2),
        |args: &[Value], _h: &mut H, span| {
            let name = arg_str(&args[0], "getenv", span)?;
            match std::env::var(&*name) {
                Ok(v) => Ok(Value::Str(Arc::from(v))),
                Err(_) => Ok(args.get(1).cloned().unwrap_or(Value::Nil)),
            }
        },
    );

    interp.register_fn(
        "env_required",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let name = arg_str(&args[0], "env_required", span)?;
            std::env::var(&*name)
                .map(|v| Value::Str(Arc::from(v)))
                .map_err(|_| {
                    EvalError::native_fn(
                        "env_required",
                        format!("environment variable {name} is not set"),
                        span,
                    )
                })
        },
    );

    interp.register_fn(
        "argv",
        Arity::Exact(0),
        |_args: &[Value], _h: &mut H, _span| {
            let args = std::env::args().skip(1).collect::<Vec<_>>();
            Ok(Value::list(
                args.into_iter()
                    .map(|s| Value::Str(Arc::from(s)))
                    .collect::<Vec<_>>(),
            ))
        },
    );

    interp.register_fn(
        "argv_get",
        Arity::Range(1, 2),
        |args: &[Value], _h: &mut H, span| {
            let n = arg_int(&args[0], "argv_get", span)?;
            if n < 0 {
                return Err(EvalError::native_fn(
                    "argv_get",
                    format!("index must be >= 0, got {n}"),
                    span,
                ));
            }
            let all = std::env::args().skip(1).collect::<Vec<_>>();
            let idx = n as usize;
            if idx < all.len() {
                Ok(Value::Str(Arc::from(all[idx].clone())))
            } else {
                Ok(args.get(1).cloned().unwrap_or(Value::Nil))
            }
        },
    );
}

// ── clock ────────────────────────────────────────────────────────────────

fn install_clock<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "now",
        Arity::Exact(0),
        |_args: &[Value], _h: &mut H, _span| {
            Ok(Value::Int(
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_secs() as i64)
                    .unwrap_or(0),
            ))
        },
    );

    interp.register_fn(
        "now_ms",
        Arity::Exact(0),
        |_args: &[Value], _h: &mut H, _span| {
            Ok(Value::Int(
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(0),
            ))
        },
    );

    interp.register_fn(
        "now_ns",
        Arity::Exact(0),
        |_args: &[Value], _h: &mut H, _span| {
            Ok(Value::Int(
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.as_nanos() as i64)
                    .unwrap_or(0),
            ))
        },
    );

    interp.register_fn(
        "now_rfc3339",
        Arity::Exact(0),
        |_args: &[Value], _h: &mut H, _span| {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);
            Ok(Value::Str(Arc::from(format_rfc3339_utc(now))))
        },
    );

    interp.register_fn(
        "sleep",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let secs = arg_int(&args[0], "sleep", span)?;
            if secs > 0 {
                std::thread::sleep(Duration::from_secs(secs as u64));
            }
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "sleep_ms",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let ms = arg_int(&args[0], "sleep_ms", span)?;
            if ms > 0 {
                std::thread::sleep(Duration::from_millis(ms as u64));
            }
            Ok(Value::Nil)
        },
    );

    interp.register_fn(
        "elapsed_since",
        Arity::Exact(1),
        |args: &[Value], _h: &mut H, span| {
            let start_ns = arg_int(&args[0], "elapsed_since", span)?;
            let now_ns = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos() as i64)
                .unwrap_or(0);
            Ok(Value::Int(now_ns - start_ns))
        },
    );
}

/// Format a unix-seconds timestamp as RFC-3339 UTC (no external crate).
fn format_rfc3339_utc(unix_secs: i64) -> String {
    let (y, m, d, h, mi, s) = seconds_to_datetime(unix_secs);
    format!("{y:04}-{m:02}-{d:02}T{h:02}:{mi:02}:{s:02}Z")
}

fn seconds_to_datetime(unix_secs: i64) -> (i64, u32, u32, u32, u32, u32) {
    let days = unix_secs.div_euclid(86_400);
    let rem = unix_secs.rem_euclid(86_400);
    let h = (rem / 3600) as u32;
    let mi = ((rem % 3600) / 60) as u32;
    let s = (rem % 60) as u32;
    let (y, m, d) = days_to_ymd(days);
    (y, m, d, h, mi, s)
}

/// Days since 1970-01-01 → (year, month, day). Howard Hinnant "date
/// algorithm" civil-from-days.
fn days_to_ymd(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

// ── shared argument coercion ─────────────────────────────────────────────

fn arg_str(
    v: &Value,
    fname: &'static str,
    span: tatara_lisp::Span,
) -> Result<Arc<str>, EvalError> {
    match v {
        Value::Str(s) => Ok(s.clone()),
        other => Err(EvalError::native_fn(
            fname,
            format!("expected a string, got {}", other.type_name()),
            span,
        )),
    }
}

fn arg_int(v: &Value, fname: &'static str, span: tatara_lisp::Span) -> Result<i64, EvalError> {
    match v {
        Value::Int(n) => Ok(*n),
        other => Err(EvalError::native_fn(
            fname,
            format!("expected an integer, got {}", other.type_name()),
            span,
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::interpreter;

    /// A fresh per-test scratch file, cleaned up on drop. `sys` tests hit the
    /// real filesystem — that is the point of the module — so each test gets
    /// an owned path and nothing leaks.
    struct Scratch(PathBuf);

    impl Scratch {
        fn new(name: &str) -> Self {
            let mut p = std::env::temp_dir();
            p.push(format!("blue-sys-{name}-{}", std::process::id()));
            Scratch(p)
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
            let _ = std::fs::remove_file(&self.0);
        }
    }

    fn run(src: &str) -> Value {
        let mut interp = interpreter(&mut ());
        let forms = tatara_lisp::read_spanned(src).expect("read");
        interp
            .eval_program(&forms, &mut ())
            .unwrap_or_else(|e| panic!("{src:?}: {e}"))
    }

    fn run_err(src: &str) -> String {
        let mut interp = interpreter(&mut ());
        let forms = tatara_lisp::read_spanned(src).expect("read");
        interp
            .eval_program(&forms, &mut ())
            .expect_err("must raise")
            .to_string()
    }

    // ---- process --------------------------------------------------------

    #[test]
    fn exec_capture_returns_the_capture_form() {
        let v = run(r#"(exec_capture "printf" "hi")"#);
        let Value::List(entries) = v else {
            panic!("expected an alist, got {v:?}");
        };
        assert_eq!(entries.len(), 3, "status, stdout, stderr");
        let stdout = entries
            .iter()
            .find_map(|entry| {
                let Value::List(pair) = entry else { return None };
                if pair.len() == 2
                    && matches!(&pair[0], Value::Keyword(k) if &**k == "stdout")
                {
                    Some(pair[1].clone())
                } else {
                    None
                }
            })
            .expect("a :stdout entry");
        assert!(matches!(stdout, Value::Str(s) if &*s == "hi"));
    }

    #[test]
    fn exec_ok_is_true_on_success() {
        assert!(matches!(run(r#"(exec_ok? "true")"#), Value::Bool(true)));
        assert!(matches!(run(r#"(exec_ok? "false")"#), Value::Bool(false)));
    }

    #[test]
    fn sh_exec_runs_a_shell_script() {
        let v = run(r#"(sh_exec "printf 'x'")"#);
        let Value::List(entries) = v else {
            panic!("expected an alist, got {v:?}");
        };
        let stdout = entries.iter().find_map(|entry| {
            let Value::List(pair) = entry else { return None };
            if pair.len() == 2
                && matches!(&pair[0], Value::Keyword(k) if &**k == "stdout")
            {
                Some(pair[1].clone())
            } else {
                None
            }
        });
        assert!(matches!(stdout, Some(Value::Str(s)) if &*s == "x"));
    }

    #[test]
    fn exec_with_env_sets_children_only() {
        let v = run(
            r#"(exec_with_env (list (list "BLUE_SYS_TEST" "42")) "sh" "-c" "printf \"$BLUE_SYS_TEST\"")"#,
        );
        let Value::List(entries) = v else {
            panic!("expected an alist, got {v:?}");
        };
        let stdout = entries.iter().find_map(|entry| {
            let Value::List(pair) = entry else { return None };
            if pair.len() == 2 && matches!(&pair[0], Value::Keyword(k) if &**k == "stdout") {
                Some(pair[1].clone())
            } else {
                None
            }
        });
        assert!(matches!(stdout, Some(Value::Str(s)) if &*s == "42"));
    }

    #[test]
    fn exec_with_stdin_feeds_the_child() {
        let v = run(
            r#"(exec_with_stdin "payload" "sh" "-c" "cat")"#,
        );
        let Value::List(entries) = v else {
            panic!("expected an alist, got {v:?}");
        };
        let stdout = entries.iter().find_map(|entry| {
            let Value::List(pair) = entry else { return None };
            if pair.len() == 2 && matches!(&pair[0], Value::Keyword(k) if &**k == "stdout") {
                Some(pair[1].clone())
            } else {
                None
            }
        });
        assert!(matches!(stdout, Some(Value::Str(s)) if &*s == "payload"));
    }

    #[test]
    fn a_missing_binary_is_a_named_error() {
        let err = run_err(r#"(exec_capture "definitely-not-a-real-binary-xyz")"#);
        assert!(err.contains("exec_capture"), "must name the primitive: {err}");
    }

    // ---- filesystem -----------------------------------------------------

    #[test]
    fn write_then_read_round_trips() {
        let s = Scratch::new("roundtrip");
        run(&format!(
            r#"(write_file "{}" "hello world")"#,
            s.0.display()
        ));
        assert!(matches!(
            run(&format!(r#"(read_file "{}")"#, s.0.display())),
            Value::Str(v) if &*v == "hello world"
        ));
        assert!(matches!(
            run(&format!(r#"(file_size "{}")"#, s.0.display())),
            Value::Int(11)
        ));
        assert!(matches!(
            run(&format!(r#"(is_file? "{}")"#, s.0.display())),
            Value::Bool(true)
        ));
    }

    #[test]
    fn append_adds_to_the_end() {
        let s = Scratch::new("append");
        run(&format!(r#"(write_file "{}" "a")"#, s.0.display()));
        run(&format!(r#"(append_file "{}" "b")"#, s.0.display()));
        assert!(matches!(
            run(&format!(r#"(read_file "{}")"#, s.0.display())),
            Value::Str(v) if &*v == "ab"
        ));
    }

    #[test]
    fn predicates_distinguish_dirs_and_files() {
        assert!(matches!(
            run(&format!(r#"(is_dir? "{}")"#, std::env::temp_dir().display())),
            Value::Bool(true)
        ));
        assert!(matches!(
            run(&format!(r#"(is_file? "{}")"#, std::env::temp_dir().display())),
            Value::Bool(false)
        ));
        assert!(matches!(
            run(r#"(path_exists "/definitely/not/here/xyz")"#),
            Value::Bool(false)
        ));
    }

    #[test]
    fn file_mtime_ms_is_a_recent_unix_timestamp() {
        let s = Scratch::new("mtime");
        run(&format!(r#"(write_file "{}" "x")"#, s.0.display()));
        let ms = match run(&format!(r#"(file_mtime_ms "{}")"#, s.0.display())) {
            Value::Int(n) => n,
            other => panic!("expected Int, got {other:?}"),
        };
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        assert!(
            now - ms < 60_000,
            "mtime {ms} should be within a minute of now {now}"
        );
    }

    #[test]
    fn reading_a_missing_file_is_a_named_error() {
        let err = run_err(r#"(read_file "/definitely/not/here/xyz")"#);
        assert!(err.contains("read_file"), "must name the primitive: {err}");
    }

    #[test]
    fn path_ops_split_and_join() {
        assert!(matches!(
            run(r#"(path_join "a" "b" "c")"#),
            Value::Str(v) if v.ends_with("a/b/c")
        ));
        assert!(matches!(
            run(r#"(path_basename "/a/b/c.txt")"#),
            Value::Str(v) if &*v == "c.txt"
        ));
        assert!(matches!(
            run(r#"(path_dirname "/a/b/c.txt")"#),
            Value::Str(v) if &*v == "/a/b"
        ));
        assert!(matches!(
            run(r#"(path_extension "/a/b/c.txt")"#),
            Value::Str(v) if &*v == "txt"
        ));
    }

    // ---- environment ----------------------------------------------------

    #[test]
    fn getenv_reads_real_environment() {
        std::env::set_var("BLUE_SYS_TEST_ENV", "present");
        assert!(matches!(
            run(r#"(getenv "BLUE_SYS_TEST_ENV")"#),
            Value::Str(v) if &*v == "present"
        ));
        assert!(matches!(run(r#"(getenv "BLUE_SYS_TEST_MISSING")"#), Value::Nil));
        assert!(matches!(
            run(r#"(getenv "BLUE_SYS_TEST_MISSING" "fallback")"#),
            Value::Str(v) if &*v == "fallback"
        ));
        std::env::remove_var("BLUE_SYS_TEST_ENV");
    }

    #[test]
    fn env_required_raises_with_the_name() {
        let err = run_err(r#"(env_required "BLUE_SYS_TEST_MISSING")"#);
        assert!(
            err.contains("BLUE_SYS_TEST_MISSING"),
            "must name the variable: {err}"
        );
    }

    // ---- clock ----------------------------------------------------------

    #[test]
    fn now_ms_is_recent_and_monotonic() {
        let a = match run(r#"(now_ms)"#) {
            Value::Int(n) => n,
            other => panic!("expected Int, got {other:?}"),
        };
        let b = match run(r#"(now_ms)"#) {
            Value::Int(n) => n,
            other => panic!("expected Int, got {other:?}"),
        };
        assert!(b >= a);
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        assert!(
            (now - a).abs() < 60_000,
            "now_ms {a} should be near wall clock {now}"
        );
    }

    #[test]
    fn rfc3339_epoch_and_y2k() {
        assert_eq!(format_rfc3339_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(format_rfc3339_utc(946_684_800), "2000-01-01T00:00:00Z");
    }

    #[test]
    fn sleep_ms_blocks_then_returns_nil() {
        let start = SystemTime::now();
        assert!(matches!(run(r#"(sleep_ms 20)"#), Value::Nil));
        assert!(
            start.elapsed().unwrap_or_default().as_millis() >= 15,
            "sleep_ms must actually block"
        );
    }
}
