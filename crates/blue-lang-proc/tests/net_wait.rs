#![cfg(unix)]

mod support;

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::sync::Arc;
use std::time::{Duration, Instant};

use blue_lang_proc::readiness::Pollable;
use blue_lang_proc::{ClockKind, Frame, NodeConfig};
use blue_lang_waku::Capability;
use support::{configure, show};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

struct Sock(UnixStream);

fn sock(v: &Value) -> Option<Arc<Sock>> {
    match v {
        Value::Foreign(any) => Arc::downcast::<Sock>(any.clone()).ok(),
        _ => None,
    }
}

fn fd_of(v: &Value) -> Option<Pollable> {
    sock(v).map(|s| -> Pollable { Arc::new(s.0.try_clone().expect("clone")) })
}

fn with_socks(mut interp: Interpreter<()>) -> Interpreter<()> {
    interp.register_fn(
        "sock_pair",
        Arity::Exact(0),
        |_: &[Value], _h: &mut (), _| {
            let (a, b) = UnixStream::pair().expect("pair");
            Ok(Value::list([
                Value::Foreign(Arc::new(Sock(a))),
                Value::Foreign(Arc::new(Sock(b))),
            ]))
        },
    );
    interp.register_fn(
        "sock_later",
        Arity::Exact(1),
        |args: &[Value], _h: &mut (), span| {
            let Value::Int(ms) = args[0] else {
                return Err(EvalError::native_fn("sock_later", "not milliseconds", span));
            };
            let (a, mut b) = UnixStream::pair().expect("pair");
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_millis(ms.unsigned_abs()));
                b.write_all(b"go").expect("write");
                std::thread::sleep(Duration::from_millis(200));
            });
            Ok(Value::Foreign(Arc::new(Sock(a))))
        },
    );
    interp.register_fn(
        "sock_put",
        Arity::Exact(2),
        |args: &[Value], _h: &mut (), span| {
            let s = sock(&args[0])
                .ok_or_else(|| EvalError::native_fn("sock_put", "not a sock", span))?;
            let Value::Str(text) = &args[1] else {
                return Err(EvalError::native_fn("sock_put", "not a string", span));
            };
            (&s.0).write_all(text.as_bytes()).expect("write");
            Ok(Value::Nil)
        },
    );
    interp.register_fn(
        "sock_take",
        Arity::Exact(1),
        |args: &[Value], _h: &mut (), span| {
            let s = sock(&args[0])
                .ok_or_else(|| EvalError::native_fn("sock_take", "not a sock", span))?;
            let mut buf = [0u8; 64];
            let n = (&s.0).read(&mut buf).expect("read");
            Ok(Value::Str(Arc::from(
                String::from_utf8_lossy(&buf[..n]).as_ref(),
            )))
        },
    );
    interp
}

fn config(frame: Option<Frame>) -> NodeConfig {
    let mut config = NodeConfig::new(Arc::new(|| {
        with_socks(blue_lang_runtime::interpreter_hostless())
    }));
    config.budget.quantum = Some(50);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.fd_of = Some(fd_of);
    config.frame = frame;
    config
}

fn run_in(frame: Option<Frame>, src: &str) -> (String, Duration) {
    let (root, _node) = configure(config(frame));
    let mut root = with_socks(root);
    let started = Instant::now();
    let out = show(&mut root, src);
    (out, started.elapsed())
}

fn run(src: &str) -> String {
    run_in(None, src).0
}

#[test]
fn a_wait_with_nothing_ready_times_out_on_the_virtual_clock_in_no_wall_time() {
    let (out, wall) = run_in(
        None,
        "[a, b] = sock_pair()\n[net_wait([[a, :read]], 30000), node_time()]",
    );
    assert_eq!(out, "(() 30000)");
    assert!(wall < Duration::from_secs(2), "took {wall:?}");
}

#[test]
fn a_written_socket_is_ready_to_read_and_says_which_handle() {
    let out = run("[a, b] = sock_pair()\nsock_put(b, \"hi\")\n\
         [[h, r]] = net_wait([[a, :read], [b, :read]], 1000)\n[r, sock_take(h), node_time()]");
    assert_eq!(out, "(:read \"hi\" 0)");
}

#[test]
fn a_writable_socket_answers_write_and_both_answers_each() {
    let out = run("[a, b] = sock_pair()\nsock_put(b, \"x\")\n\
         [[_, r1], [_, r2]] = net_wait([[a, :both]], 0)\n[r1, r2]");
    assert_eq!(out, "(:read :write)");
}

#[test]
fn a_process_waiting_on_a_socket_parks_and_never_holds_the_node() {
    let src = "me = self()\n\
         spawn(fn() a = sock_later(300)\n  net_wait([[a, :read]])\n  send(me, [:net, sock_take(a), node_time()]) end)\n\
         spawn(fn() sleep_for(250)\n  send(me, [:slow, node_time()]) end)\n\
         spawn(fn() send(me, [:fast, node_time()]) end)\n\
         [receive(), receive(), receive()]";
    let first = run(src);
    assert_eq!(first, "((:fast 0) (:slow 250) (:net \"go\" 250))");
    for _ in 0..3 {
        assert_eq!(run(src), first, "the same program gives the same answer");
    }
}

#[test]
fn a_process_wait_times_out_in_virtual_time_among_other_timers() {
    let out = run(
        "me = self()\n\
         spawn(fn() [a, b] = sock_pair()\n  send(me, [:net, net_wait([[a, :read]], 400), node_time()]) end)\n\
         spawn(fn() sleep_for(100)\n  send(me, [:timer, node_time()]) end)\n\
         [receive(), receive()]",
    );
    assert_eq!(out, "((:timer 100) (:net () 400))");
}

#[test]
fn a_deadline_around_the_wait_raises_timeout_at_the_deadline() {
    let out = run(
        "[a, b] = sock_pair()\n\
         begin\n  deadline(150, fn() net_wait([[a, :read]]) end)\nrescue :timeout as e\n  [e.kind, node_time()]\nend",
    );
    assert_eq!(out, "(:timeout 150)");
}

#[test]
fn a_frame_that_withholds_the_network_refuses_net_wait_as_a_breach() {
    let frame = Frame {
        granted: Vec::new(),
        provided: Vec::new(),
        withheld: vec![Capability::Network],
    };
    let (out, _) = run_in(
        Some(frame),
        "[a, b] = sock_pair()\nnet_wait([[a, :read]], 0)",
    );
    assert!(out.contains("does not grant"), "{out}");
    assert!(out.contains("net_wait"), "{out}");
}

#[test]
fn a_value_that_is_no_handle_is_refused_by_name() {
    let out = run("net_wait([[1, :read]], 0)");
    assert!(out.contains("not a handle net_wait can wait on"), "{out}");
    let out = run("[a, b] = sock_pair()\nnet_wait([[a, :sideways]], 0)");
    assert!(out.contains("interest"), "{out}");
}
