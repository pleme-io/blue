use std::sync::Arc;

use blue_lang_kernel::{Answer, Fd, Refusal, Ring, Slot};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

use crate::crypto::message_bytes;
use crate::errors::raise_kind;
use crate::net::record;
use crate::sys::arg_int;

type Span = tatara_lisp::Span;

fn refused(refusal: &Refusal, span: Span) -> EvalError {
    let kind = match refusal {
        Refusal::Absent(_) => "unsupported",
        Refusal::Bad(_) => "bad_option",
        Refusal::Errno { .. } => "kernel_refused",
    };
    let data = match refusal {
        Refusal::Errno { errno, .. } => record(vec![("errno", Value::Int(i64::from(*errno)))]),
        Refusal::Absent(_) | Refusal::Bad(_) => Value::Nil,
    };
    crate::errors::raise_kind_with(kind, refusal.to_string(), data, span)
}

fn bad(word: &str, why: String, span: Span) -> EvalError {
    raise_kind("bad_option", format!("{word}: {why}"), span)
}

fn bytes_value(bytes: &[u8]) -> Value {
    Value::list(bytes.iter().map(|b| Value::Int(i64::from(*b))))
}

fn fd_of(v: &Value, word: &'static str, span: Span) -> Result<Arc<Fd>, EvalError> {
    if let Value::Foreign(any) = v {
        if let Ok(fd) = Arc::downcast::<Fd>(any.clone()) {
            return Ok(fd);
        }
    }
    Err(bad(
        word,
        format!("expected a kernel file descriptor, got {}", v.type_name()),
        span,
    ))
}

fn ring_of(v: &Value, word: &'static str, span: Span) -> Result<Arc<Ring>, EvalError> {
    if let Value::Foreign(any) = v {
        if let Ok(ring) = Arc::downcast::<Ring>(any.clone()) {
            return Ok(ring);
        }
    }
    Err(bad(
        word,
        format!("expected a ring from ringbuf_open, got {}", v.type_name()),
        span,
    ))
}

fn items(v: &Value, what: &str, word: &'static str, span: Span) -> Result<Vec<Value>, EvalError> {
    match v {
        Value::List(xs) => Ok(xs.iter().cloned().collect()),
        Value::Nil => Ok(Vec::new()),
        other => Err(bad(
            word,
            format!("{what} is a list, got {}", other.type_name()),
            span,
        )),
    }
}

fn size_of(v: &Value, word: &'static str, span: Span) -> Result<usize, EvalError> {
    let n = arg_int(v, word, span)?;
    usize::try_from(n).map_err(|_| bad(word, format!("a size is not negative, got {n}"), span))
}

fn bytes_of(v: &Value, word: &'static str, span: Span) -> Result<Vec<u8>, EvalError> {
    message_bytes(v).map_err(|e| bad(word, e.to_string(), span))
}

fn slot_of(v: &Value, word: &'static str, span: Span) -> Result<Slot, EvalError> {
    let parts = items(v, "a field", word, span)?;
    let [at, kind, value] = parts.as_slice() else {
        return Err(bad(word, "a field is [offset, kind, value]".into(), span));
    };
    let at = size_of(at, word, span)?;
    let Value::Keyword(kind) = kind else {
        return Err(bad(
            word,
            format!("a field's kind is a keyword, got {}", kind.type_name()),
            span,
        ));
    };
    Ok(match &**kind {
        "u8" | "u16" | "u32" | "u64" => Slot::Int {
            at,
            width: match &**kind {
                "u8" => 1,
                "u16" => 2,
                "u32" => 4,
                _ => 8,
            },
            value: arg_int(value, word, span)?.cast_unsigned(),
        },
        "bytes" => Slot::Bytes {
            at,
            bytes: bytes_of(value, word, span)?,
        },
        "in" => Slot::In {
            at,
            bytes: bytes_of(value, word, span)?,
        },
        "out" => Slot::Out {
            at,
            capacity: size_of(value, word, span)?,
        },
        "inout" => Slot::InOut {
            at,
            bytes: bytes_of(value, word, span)?,
        },
        "strings" => Slot::Strings {
            at,
            strings: items(value, "the names", word, span)?
                .iter()
                .map(|n| crate::sys::arg_str(n, word, span).map(|t| t.to_string()))
                .collect::<Result<Vec<_>, _>>()?,
        },
        "fd" => Slot::Descriptor {
            at,
            fd: fd_of(value, word, span)?,
        },
        other => {
            return Err(bad(
                word,
                format!("no field kind :{other}; the kinds are :u8 :u16 :u32 :u64 :bytes :in :out :inout :strings :fd"),
                span,
            ));
        }
    })
}

fn answer_value(a: Answer) -> Value {
    record(vec![
        ("ret", Value::Int(a.ret)),
        (
            "errno",
            a.errno.map_or(Value::Nil, |e| Value::Int(i64::from(e))),
        ),
        ("attr", bytes_value(&a.attr)),
        ("out", Value::list(a.out.iter().map(|o| bytes_value(o)))),
        (
            "fd",
            a.fd.map_or(Value::Nil, |fd| Value::Foreign(Arc::new(fd))),
        ),
    ])
}

pub fn install_kernel<H: 'static>(interp: &mut Interpreter<H>) {
    interp.register_fn(
        "bpf_syscall",
        Arity::Exact(4),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "bpf_syscall";
            let command = u32::try_from(arg_int(&a[0], W, span)?)
                .map_err(|_| bad(W, "a command is a non-negative 32-bit value".into(), span))?;
            let size = size_of(&a[1], W, span)?;
            let slots = items(&a[2], "the fields", W, span)?
                .iter()
                .map(|s| slot_of(s, W, span))
                .collect::<Result<Vec<_>, _>>()?;
            let fd_result = matches!(a[3], Value::Bool(true));
            blue_lang_kernel::bpf(command, size, &slots, fd_result)
                .map(answer_value)
                .map_err(|r| refused(&r, span))
        },
    );
    interp.register_fn(
        "perf_event_open",
        Arity::Exact(6),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "perf_event_open";
            let size = size_of(&a[0], W, span)?;
            let slots = items(&a[1], "the fields", W, span)?
                .iter()
                .map(|s| slot_of(s, W, span))
                .collect::<Result<Vec<_>, _>>()?;
            let int32 = |v: &Value| -> Result<i32, EvalError> {
                i32::try_from(arg_int(v, W, span)?)
                    .map_err(|_| bad(W, "a pid or cpu is a 32-bit value".into(), span))
            };
            let group = match &a[4] {
                Value::Nil => None,
                other => Some(fd_of(other, W, span)?),
            };
            let flags = arg_int(&a[5], W, span)?.cast_unsigned();
            blue_lang_kernel::perf_event_open(
                size,
                &slots,
                int32(&a[2])?,
                int32(&a[3])?,
                group.as_deref(),
                flags,
            )
            .map(|fd| Value::Foreign(Arc::new(fd)))
            .map_err(|r| refused(&r, span))
        },
    );
    interp.register_fn(
        "fd_ioctl",
        Arity::Exact(3),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "fd_ioctl";
            let fd = fd_of(&a[0], W, span)?;
            let request = arg_int(&a[1], W, span)?.cast_unsigned();
            let argument = arg_int(&a[2], W, span)?.cast_unsigned();
            blue_lang_kernel::ioctl(&fd, request, argument)
                .map(Value::Int)
                .map_err(|r| refused(&r, span))
        },
    );
    interp.register_fn(
        "fd_close",
        Arity::Exact(1),
        |a: &[Value], _: &mut H, span| {
            fd_of(&a[0], "fd_close", span)?.close();
            Ok(Value::Nil)
        },
    );
    interp.register_fn(
        "fd_number",
        Arity::Exact(1),
        |a: &[Value], _: &mut H, span| {
            Ok(fd_of(&a[0], "fd_number", span)?
                .number()
                .map_or(Value::Nil, |n| Value::Int(i64::from(n))))
        },
    );
    interp.register_fn(
        "ringbuf_open",
        Arity::Exact(2),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "ringbuf_open";
            Ring::open(fd_of(&a[0], W, span)?, size_of(&a[1], W, span)?)
                .map(|ring| Value::Foreign(Arc::new(ring)))
                .map_err(|r| refused(&r, span))
        },
    );
    interp.register_fn(
        "ringbuf_next",
        Arity::Exact(2),
        |a: &[Value], _: &mut H, span| {
            const W: &str = "ringbuf_next";
            let ring = ring_of(&a[0], W, span)?;
            let wait = i32::try_from(arg_int(&a[1], W, span)?).map_err(|_| {
                bad(
                    W,
                    "a timeout is a 32-bit count of milliseconds".into(),
                    span,
                )
            })?;
            ring.next(wait)
                .map(|sample| sample.map_or(Value::Nil, |s| bytes_value(&s)))
                .map_err(|r| refused(&r, span))
        },
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kernel() -> Interpreter<()> {
        let mut interp = crate::interpreter_hostless();
        install_kernel(&mut interp);
        interp
    }

    fn eval(src: &str) -> Result<Value, EvalError> {
        let forms = tatara_lisp::read_spanned(src).expect("reads");
        kernel().eval_program(&forms, &mut ())
    }

    fn kind(src: &str) -> String {
        match eval(src) {
            Err(EvalError::User {
                value: Value::Error(e),
                ..
            }) => e.tag.to_string(),
            other => panic!("{src}: {other:?}"),
        }
    }

    #[test]
    fn a_malformed_field_is_refused_by_name_before_any_call() {
        assert_eq!(
            kind("(bpf_syscall 0 8 (list (list 0 :nope 1)) false)"),
            "bad_option"
        );
        assert_eq!(
            kind("(bpf_syscall 0 8 (list (list 0 :u32)) false)"),
            "bad_option"
        );
        assert_eq!(kind("(bpf_syscall -1 8 (list) false)"), "bad_option");
        assert_eq!(
            kind("(bpf_syscall 0 2 (list (list 0 :u32 1)) false)"),
            "bad_option"
        );
        assert_eq!(kind("(fd_close 3)"), "bad_option");
        assert_eq!(kind("(ringbuf_next 3 0)"), "bad_option");
    }

    #[cfg(not(target_os = "linux"))]
    #[test]
    fn off_linux_each_call_raises_unsupported() {
        assert_eq!(kind("(bpf_syscall 0 8 (list) false)"), "unsupported");
        assert_eq!(
            kind("(perf_event_open 8 (list) 0 0 (get (hash-map) :none) 0)"),
            "unsupported"
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn on_linux_a_bad_command_answers_with_its_errno() {
        let v = eval("(get (bpf_syscall 9999 8 (list) false) :errno)").expect("answers");
        assert!(matches!(v, Value::Int(n) if n > 0), "{v:?}");
    }
}
