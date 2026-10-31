use std::collections::BTreeMap;
use std::io::{Read, Seek, SeekFrom, Write};
use std::sync::{Arc, Mutex, PoisonError};

use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::errors::raise_kind;
use crate::provide::Key;
use crate::sys::arg_str;

type Span = tatara_lisp::Span;

#[derive(Clone)]
enum Store {
    Host,
    Memory(Arc<Mutex<BTreeMap<String, String>>>),
}

fn line_of(record: &Value, span: Span) -> Result<String, EvalError> {
    match record {
        Value::Str(s) if s.contains('\n') => Err(raise_kind(
            "bad_option",
            "append_log: a record is one line, and this one holds a newline".into(),
            span,
        )),
        Value::Str(s) => Ok(format!("{s}\n")),
        other => Err(raise_kind(
            "bad_option",
            format!(
                "append_log: a record is a string, got {}",
                other.type_name()
            ),
            span,
        )),
    }
}

fn torn_tail(log: &str, span: Span) -> EvalError {
    raise_kind(
        "parse_error",
        format!("append_log: {log} ends in a torn record, so a record appended now would join it"),
        span,
    )
}

fn absent(word: &'static str, log: &str, span: Span) -> EvalError {
    raise_kind("not_found", format!("{word}: {log}: no such log"), span)
}

fn io_error(word: &'static str, log: &str, e: &std::io::Error, span: Span) -> EvalError {
    match e.kind() {
        std::io::ErrorKind::NotFound => absent(word, log, span),
        std::io::ErrorKind::PermissionDenied => {
            raise_kind("permission_denied", format!("{word}: {log}: {e}"), span)
        }
        std::io::ErrorKind::InvalidData => raise_kind(
            "parse_error",
            format!("{word}: {log}: the log is not UTF-8 text"),
            span,
        ),
        _ => EvalError::native_fn(word, format!("{log}: {e}"), span),
    }
}

fn records(log: &str, text: &str, span: Span) -> Result<Value, EvalError> {
    if text.is_empty() {
        return Ok(Value::list(Vec::<Value>::new()));
    }
    let Some(body) = text.strip_suffix('\n') else {
        return Err(raise_kind(
            "parse_error",
            format!(
                "read_log: {log} ends in a torn record after {} whole ones",
                text.matches('\n').count()
            ),
            span,
        ));
    };
    Ok(Value::list(
        body.split('\n').map(|r| Value::Str(Arc::from(r))),
    ))
}

impl Store {
    fn append(&self, log: &str, line: &str, span: Span) -> Result<(), EvalError> {
        const W: &str = "append_log";
        match self {
            Store::Host => {
                crate::sys::writable(log, W, span)?;
                let path = std::path::Path::new(log);
                if let Some(dir) = path.parent().filter(|d| !d.as_os_str().is_empty()) {
                    std::fs::create_dir_all(dir).map_err(|e| io_error(W, log, &e, span))?;
                }
                let mut f = std::fs::OpenOptions::new()
                    .create(true)
                    .read(true)
                    .append(true)
                    .open(path)
                    .map_err(|e| io_error(W, log, &e, span))?;
                let len = f.metadata().map_err(|e| io_error(W, log, &e, span))?.len();
                if len > 0 {
                    let mut last = [0u8; 1];
                    f.seek(SeekFrom::End(-1))
                        .and_then(|_| f.read_exact(&mut last))
                        .map_err(|e| io_error(W, log, &e, span))?;
                    if last[0] != b'\n' {
                        return Err(torn_tail(log, span));
                    }
                }
                f.write_all(line.as_bytes())
                    .map_err(|e| io_error(W, log, &e, span))
            }
            Store::Memory(logs) => {
                let mut g = logs.lock().unwrap_or_else(PoisonError::into_inner);
                let slot = g.entry(crate::provide::absolute(log)).or_default();
                if !slot.is_empty() && !slot.ends_with('\n') {
                    return Err(torn_tail(log, span));
                }
                slot.push_str(line);
                Ok(())
            }
        }
    }

    fn read(&self, log: &str, span: Span) -> Result<String, EvalError> {
        const W: &str = "read_log";
        match self {
            Store::Host => std::fs::read_to_string(log).map_err(|e| io_error(W, log, &e, span)),
            Store::Memory(logs) => logs
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .get(&crate::provide::absolute(log))
                .cloned()
                .ok_or_else(|| absent(W, log, span)),
        }
    }
}

fn install<H: 'static>(interp: &mut Interpreter<H>, key: Key, store: &Store) {
    let s = store.clone();
    interp.register_fn(
        key("append_log"),
        Arity::Exact(2),
        move |a: &[Value], _: &mut H, span| {
            let log = arg_str(&a[0], "append_log", span)?;
            let line = line_of(&a[1], span)?;
            s.append(&log, &line, span)?;
            Ok(Value::Nil)
        },
    );
    let s = store.clone();
    interp.register_fn(
        key("read_log"),
        Arity::Exact(1),
        move |a: &[Value], _: &mut H, span| {
            let log = arg_str(&a[0], "read_log", span)?;
            records(&log, &s.read(&log, span)?, span)
        },
    );
}

pub fn install_storage<H: 'static>(interp: &mut Interpreter<H>) {
    install(interp, String::from, &Store::Host);
}

pub fn provide_in_memory<H: 'static>(interp: &mut Interpreter<H>, key: Key) {
    install(interp, key, &Store::Memory(Arc::default()));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn host() -> Interpreter<()> {
        let mut interp = crate::interpreter_hostless();
        install_storage(&mut interp);
        interp
    }

    fn memory() -> Interpreter<()> {
        let mut interp = crate::interpreter_hostless();
        provide_in_memory(&mut interp, String::from);
        interp
    }

    fn eval(interp: &mut Interpreter<()>, src: &str) -> Result<Value, EvalError> {
        let forms = tatara_lisp::read_spanned(src).expect("reads");
        interp.eval_program(&forms, &mut ())
    }

    fn ok(interp: &mut Interpreter<()>, src: &str) -> String {
        eval(interp, src)
            .unwrap_or_else(|e| panic!("{src}: {e}"))
            .to_string()
    }

    fn kind(interp: &mut Interpreter<()>, src: &str) -> String {
        match eval(interp, src) {
            Err(EvalError::User {
                value: Value::Error(e),
                ..
            }) => e.tag.to_string(),
            other => panic!("{src}: {other:?}"),
        }
    }

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir =
            std::env::temp_dir().join(format!("blue-storage-unit-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn the_host_store_appends_one_line_a_record_and_reads_them_back_in_order() {
        let dir = scratch("order");
        let log = dir.join("a/b.log");
        let p = log.display();
        let mut i = host();
        ok(&mut i, &format!("(append_log \"{p}\" \"one\")"));
        ok(&mut i, &format!("(append_log \"{p}\" \"two\")"));
        ok(&mut i, &format!("(append_log \"{p}\" \"\")"));
        assert_eq!(
            ok(&mut i, &format!("(read_log \"{p}\")")),
            "(\"one\" \"two\" \"\")"
        );
        assert_eq!(std::fs::read_to_string(&log).unwrap(), "one\ntwo\n\n");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_record_that_is_not_one_line_of_text_is_refused_and_nothing_is_written() {
        for mut i in [host(), memory()] {
            let dir = scratch("line");
            let p = dir.join("l.log");
            let p = p.display();
            ok(&mut i, &format!("(append_log \"{p}\" \"kept\")"));
            assert_eq!(
                kind(&mut i, &format!("(append_log \"{p}\" \"a\nb\")")),
                "bad_option"
            );
            assert_eq!(
                kind(&mut i, &format!("(append_log \"{p}\" 7)")),
                "bad_option"
            );
            assert_eq!(ok(&mut i, &format!("(read_log \"{p}\")")), "(\"kept\")");
            let _ = std::fs::remove_dir_all(dir);
        }
    }

    #[test]
    fn a_torn_tail_is_refused_on_read_and_on_append_and_is_left_as_it_was() {
        let dir = scratch("torn");
        std::fs::create_dir_all(&dir).unwrap();
        let log = dir.join("t.log");
        std::fs::write(&log, "a\nb").unwrap();
        let p = log.display();
        let mut i = host();
        assert_eq!(kind(&mut i, &format!("(read_log \"{p}\")")), "parse_error");
        assert_eq!(
            kind(&mut i, &format!("(append_log \"{p}\" \"c\")")),
            "parse_error"
        );
        assert_eq!(std::fs::read_to_string(&log).unwrap(), "a\nb");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn an_absent_log_is_not_found_and_an_empty_one_holds_no_records() {
        for mut i in [host(), memory()] {
            let dir = scratch("absent");
            let p = dir.join("none.log");
            assert_eq!(
                kind(&mut i, &format!("(read_log \"{}\")", p.display())),
                "not_found"
            );
        }
        let dir = scratch("empty");
        std::fs::create_dir_all(&dir).unwrap();
        let log = dir.join("e.log");
        std::fs::write(&log, "").unwrap();
        assert_eq!(
            ok(&mut host(), &format!("(read_log \"{}\")", log.display())),
            "()"
        );
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn the_memory_store_keeps_its_logs_in_the_interpreter_and_writes_nothing_to_disk() {
        let dir = scratch("memory");
        let log = dir.join("m.log");
        let p = log.display();
        let mut i = memory();
        ok(&mut i, &format!("(append_log \"{p}\" \"one\")"));
        ok(&mut i, &format!("(append_log \"{p}\" \"two\")"));
        assert_eq!(
            ok(&mut i, &format!("(read_log \"{p}\")")),
            "(\"one\" \"two\")"
        );
        assert!(!dir.exists(), "no directory or log reached the host");
        assert_eq!(
            kind(&mut memory(), &format!("(read_log \"{p}\")")),
            "not_found",
            "another interpreter has its own store"
        );
    }
}
