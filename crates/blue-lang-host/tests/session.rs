use std::sync::atomic::Ordering;

use blue_lang_host::{
    host, pure_frame, Arity, Capability, Host, NoLoader, Outcome, Paired, Session, SessionConfig,
    Stop, Value,
};

#[derive(Default)]
struct Counter {
    count: i64,
}

#[host]
impl Counter {
    fn bump(&mut self) -> i64 {
        self.count += 1;
        self.count
    }
}

fn session() -> Session<Counter> {
    let mut config = SessionConfig::new(Box::new(NoLoader));
    config.frame = pure_frame();
    Session::embedded(config, Counter::default(), |interp| {
        Counter::install_into(interp, |p: &mut Paired<Counter>| &mut p.app);
    })
}

fn value(o: Outcome<String>) -> String {
    match o.result {
        Ok(v) => v,
        Err(s) => panic!("expected a value, got {s:?}"),
    }
}

fn stop(o: Outcome<String>) -> Stop {
    match o.result {
        Ok(v) => panic!("expected a stop, got the value {v}"),
        Err(s) => s,
    }
}

#[test]
fn an_embedder_primitive_reaches_the_app_state() {
    let mut s = session();
    assert_eq!(value(s.eval("bump()", None, None)), "1");
    assert_eq!(value(s.eval("bump()", None, None)), "2");
    assert_eq!(s.app().count, 2);
    s.app_mut().count = 10;
    assert_eq!(value(s.eval("bump()", None, None)), "11");
}

#[test]
fn a_definition_persists_across_evals() {
    let mut s = session();
    value(s.eval("def f(x)\n  x + 1\nend", None, None));
    assert_eq!(value(s.eval("f(41)", None, None)), "42");
}

#[test]
fn a_redefinition_replaces_the_old_one() {
    let mut s = session();
    value(s.eval("def f()\n  1\nend", None, None));
    assert_eq!(value(s.eval("f()", None, None)), "1");
    value(s.eval("def f()\n  2\nend", None, None));
    assert_eq!(value(s.eval("f()", None, None)), "2");
}

#[test]
fn the_frame_binds_an_embedder_primitive_that_reaches_the_host() {
    let mut s = Session::embedded(
        SessionConfig::new(Box::new(NoLoader)),
        Counter::default(),
        |interp| {
            Counter::install_into(interp, |p: &mut Paired<Counter>| &mut p.app);
            interp.register_fn(
                "read_file",
                Arity::Exact(1),
                |_: &[Value], p: &mut Paired<Counter>, _| {
                    p.app.count = 100;
                    Ok(Value::Str("leaked".into()))
                },
            );
        },
    );
    assert_eq!(
        stop(s.eval("read_file(\"/etc/hosts\")", None, None)),
        Stop::Volatile {
            reach: Capability::FileSystem,
            name: "read_file".to_string(),
        }
    );
    assert_eq!(s.app().count, 0);
    assert_eq!(value(s.eval("bump()", None, None)), "1");
}

#[test]
fn reset_keeps_the_app_and_its_primitives_and_forgets_definitions() {
    let mut s = session();
    value(s.eval("bump()", None, None));
    value(s.eval("def f()\n  1\nend", None, None));
    s.reset();
    assert_eq!(s.app().count, 1);
    assert_eq!(value(s.eval("bump()", None, None)), "2");
    assert!(s.eval("f()", None, None).result.is_err());
}

#[test]
fn the_interrupt_halts_an_embedded_eval() {
    let mut s = session();
    value(s.eval("def spin(n)\n  spin(n + 1)\nend", None, None));
    let flag = s.interrupt_flag();
    let setter = std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(100));
        flag.store(true, Ordering::SeqCst);
    });
    assert_eq!(stop(s.eval("spin(0)", None, None)), Stop::Interrupted);
    setter.join().unwrap();
    assert_eq!(value(s.eval("bump()", None, None)), "1");
}
