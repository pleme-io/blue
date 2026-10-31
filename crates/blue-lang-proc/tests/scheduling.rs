mod support;

use std::sync::Arc;

use blue_lang_proc::scheduling::{self, Priority, Scheduling};
use support::{node_with, show};
use tatara_lisp_eval::ffi::Arity;
use tatara_lisp_eval::{EvalError, Interpreter, Value};

fn probed(mut interp: Interpreter<()>) -> Interpreter<()> {
    interp.register_fn(
        "os_priority",
        Arity::Exact(0),
        |_: &[Value], _: &mut (), span| {
            let p: Priority = scheduling::current()
                .map_err(|why| EvalError::native_fn("os_priority", why, span))?;
            Ok(Value::list([
                Value::Int(i64::from(p.value)),
                Value::Bool(p.lowest),
            ]))
        },
    );
    interp
}

fn probing() -> (Interpreter<()>, Arc<blue_lang_proc::Node>) {
    let (root, node) = node_with(
        50,
        Arc::new(|| probed(blue_lang_runtime::interpreter_hostless())),
    );
    (probed(root), node)
}

const REPORTER: &str = "\
def reporter(msg, n)
  send(msg, os_priority())
  n + 1
end
";

#[test]
fn an_idle_process_reports_the_lowest_priority_the_os_gives_it_and_a_normal_one_the_spawners() {
    let (mut root, _) = probing();
    let out = show(
        &mut root,
        &format!(
            "{REPORTER}\
             idle = spawn_server(reporter, 0, {{scheduling: :idle}})\n\
             normal = spawn_server(reporter, 0, {{scheduling: :normal}})\n\
             plain = spawn_server(reporter, 0)\n\
             send(idle, self())\nfrom_idle = receive()\n\
             send(normal, self())\nfrom_normal = receive()\n\
             send(plain, self())\nfrom_plain = receive()\n\
             [os_priority(), from_idle, from_normal, from_plain]"
        ),
    );
    let root = scheduling::current().expect("the root reads its priority");
    let rendered = |p: Priority| format!("({} {})", p.value, if p.lowest { "#t" } else { "#f" });
    let lowest = if cfg!(target_vendor = "apple") {
        "(1 #t)".to_string()
    } else {
        "(19 #t)".to_string()
    };
    assert_eq!(
        out,
        format!(
            "({} {lowest} {} {})",
            rendered(root),
            rendered(root),
            rendered(root)
        ),
        "an :idle slice runs at the OS's lowest priority; :normal and no option run as the spawner does"
    );
    if !root.lowest {
        assert_ne!(
            rendered(root),
            lowest,
            "the spawner is not at the lowest priority, so the idle reading is the class's doing"
        );
    }
}

#[test]
fn an_idle_process_keeps_the_answers_a_normal_one_gives() {
    let (mut root, _) = probing();
    let program = |class: &str| {
        format!(
            "def sum(msg, n)\n  if msg == :get\n    n\n  else\n    n + msg\n  end\nend\n\
             def ask(msg, n)\n  send(nth(1, msg), sum(nth(0, msg), n))\n  sum(nth(0, msg), n)\nend\n\
             s = spawn_server(ask, 0, {{scheduling: {class}}})\n\
             map(fn(i) send(s, [i, self()])\nreceive() end, range(1, 200))"
        )
    };
    let idle = show(&mut root, &program(":idle"));
    let normal = show(&mut root, &program(":normal"));
    assert!(!idle.starts_with("error"), "{idle}");
    assert_eq!(idle, normal);
}

#[test]
fn the_realtime_class_is_refused_by_name_and_spawns_nothing() {
    let (mut root, node) = probing();
    let before = node.process_count();
    let out = show(
        &mut root,
        "def h(msg, n)\n  n\nend\n\
         begin\n  spawn_server(h, 0, {scheduling: :realtime})\nrescue :permission_denied as e\n  [e.kind, contains?(e.message, \":realtime\"), contains?(e.message, \"privileged\")]\nend",
    );
    assert_eq!(out, "(:permission_denied #t #t)");
    assert_eq!(
        node.process_count(),
        before,
        "a refused spawn starts nothing"
    );
    for word in ["spawn", "spawn_link"] {
        let out = show(
            &mut root,
            &format!(
                "def w()\n  1\nend\n\
                 begin\n  {word}(w, [], {{scheduling: :realtime}})\nrescue :permission_denied as e\n  e.kind\nend"
            ),
        );
        assert_eq!(out, ":permission_denied", "{word}");
    }
}

#[test]
fn a_class_or_option_blue_does_not_know_is_refused_by_name() {
    let (mut root, _) = probing();
    let out = show(
        &mut root,
        "def h(msg, n)\n  n\nend\n\
         a = begin\n  spawn_server(h, 0, {scheduling: :fast})\nrescue :bad_option as e\n  [e.kind, contains?(e.message, \":fast\")]\nend\n\
         b = begin\n  spawn_server(h, 0, {priority: :idle})\nrescue :bad_option as e\n  [e.kind, contains?(e.message, \"priority\")]\nend\n\
         c = begin\n  spawn_server(h, 0, :idle)\nrescue :bad_option as e\n  e.kind\nend\n\
         [a, b, c]",
    );
    assert_eq!(out, "((:bad_option #t) (:bad_option #t) :bad_option)");
}

#[test]
fn every_class_has_a_spelling_and_the_privileged_one_has_none() {
    for class in Scheduling::ALL {
        assert_eq!(Scheduling::named(class.label()), Ok(class));
    }
    assert_eq!(
        Scheduling::named("realtime"),
        Err(scheduling::Refusal::Privileged)
    );
    assert_eq!(Scheduling::default(), Scheduling::Normal);
}
