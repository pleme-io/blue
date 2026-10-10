use super::*;
use crate::uses::NoLoader;

fn session() -> Session {
    Session::new(Config::new(Box::new(NoLoader)))
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

fn file(name: &str, text: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "blue-session-{}-{}",
        std::process::id(),
        name.replace('.', "-")
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(name);
    std::fs::write(&path, text).unwrap();
    path
}

#[test]
fn an_expression_answers_its_value_as_blue_text() {
    let mut s = session();
    assert_eq!(value(s.eval("1 + 2", None, None)), "3");
    assert_eq!(value(s.eval("\"a\"", None, None)), "\"a\"");
    assert_eq!(value(s.eval("[1, :k, nil]", None, None)), "[1, :k, nil]");
    assert_eq!(value(s.eval("", None, None)), "nil");
}

#[test]
fn a_definition_stays_and_a_redefinition_reaches_every_caller() {
    let mut s = session();
    value(s.eval("def double(x)\n  x * 2\nend\n", None, None));
    value(s.eval("def twice_one()\n  double(1)\nend\n", None, None));
    assert_eq!(value(s.eval("double(4)", None, None)), "8");
    assert_eq!(value(s.eval("twice_one()", None, None)), "2");
    value(s.eval("def double(x)\n  x * 3\nend\n", None, None));
    assert_eq!(value(s.eval("twice_one()", None, None)), "3");
    assert_eq!(value(s.eval("double(4)", None, None)), "12");
}

#[test]
fn a_transient_expression_is_not_kept() {
    let mut s = session();
    value(s.eval("x = 4\nx + 1", None, None));
    assert_eq!(value(s.eval("x", None, None)), "4");
    assert_eq!(s.contexts[&None].forms.len(), 1);
}

#[test]
fn what_the_code_writes_is_captured() {
    let mut s = session();
    let o = s.eval("write_stdout(\"hi \")\nprintln(\"x\")\n7", None, None);
    assert_eq!(o.out, "hi \"x\"\n");
    assert_eq!(o.result, Ok("7".to_string()));
    assert_eq!(s.eval("1", None, None).out, "");
}

#[test]
fn an_unbound_name_is_refused_by_the_check_stage_at_its_place_in_the_code() {
    let mut s = session();
    let Stop::Error(f) = stop(s.eval("1\nnope(2)", None, None)) else {
        panic!("expected an error")
    };
    assert_eq!(f.code, "B0001");
    assert!(f.message.starts_with("<eval>:2:1:"), "{}", f.message);
}

#[test]
fn a_raise_is_a_runtime_error_and_the_session_survives_it() {
    let mut s = session();
    let Stop::Error(f) = stop(s.eval("throw(error(\"bad\"))", None, None)) else {
        panic!("expected an error")
    };
    assert_eq!(f.code, "runtime");
    assert!(f.message.contains("<eval>:1:"), "{}", f.message);
    assert_eq!(value(s.eval("2", None, None)), "2");
}

#[test]
fn a_parse_error_names_the_code() {
    let mut s = session();
    let Stop::Error(f) = stop(s.eval("1 +", None, None)) else {
        panic!("expected an error")
    };
    assert_eq!(f.code, "parse");
}

#[test]
fn the_budget_ends_a_runaway_as_exhausted() {
    let mut s = session();
    value(s.eval("def spin(n)\n  spin(n + 1)\nend\n", None, None));
    assert_eq!(
        stop(s.eval("spin(0)", None, Some(10_000))),
        Stop::Exhausted { limit: 10_000 }
    );
    assert_eq!(value(s.eval("1 + 1", None, None)), "2");
}

#[test]
fn the_interrupt_halts_a_running_evaluation() {
    let mut s = session();
    value(s.eval("def spin(n)\n  spin(n + 1)\nend\n", None, None));
    let flag = s.interrupt_flag();
    let setter = std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(100));
        flag.store(true, Ordering::SeqCst);
    });
    assert_eq!(stop(s.eval("spin(0)", None, None)), Stop::Interrupted);
    setter.join().unwrap();
    assert_eq!(value(s.eval("1 + 1", None, None)), "2");
}

#[cfg(feature = "sys")]
#[test]
fn reaching_the_host_is_volatile_under_the_pure_frame_directly_or_through_a_call() {
    let mut s = session();
    let refused = Stop::Volatile {
        reach: Capability::FileSystem,
        name: "read_file".to_string(),
    };
    assert_eq!(
        stop(s.eval("read_file(\"/etc/hosts\")", None, None)),
        refused
    );
    value(s.eval("def peek()\n  read_file(\"/etc/hosts\")\nend\n", None, None));
    assert_eq!(stop(s.eval("peek()", None, None)), refused);
    assert_eq!(
        stop(s.eval("try(now_ms(), catch(_e(), 0))", None, None)),
        Stop::Volatile {
            reach: Capability::Clock,
            name: "now_ms".to_string(),
        },
        "a caught refusal still reached the host"
    );
}

#[cfg(feature = "sys")]
#[test]
fn a_frame_granting_the_host_evaluates_it() {
    let path = file("granted.txt", "granted");
    let mut config = Config::new(Box::new(NoLoader));
    config.frame = frame_granting(&Capability::host_effects());
    let mut s = Session::new(config);
    let code = format!("read_file(\"{}\")", path.display());
    assert_eq!(value(s.eval(&code, None, None)), "\"granted\"");
}

#[test]
fn a_loaded_file_is_a_context_its_definitions_resolve_in() {
    let path = file(
        "ctx.b",
        "# Add one.\ndef inc1(x)\n  x + 1\nend\n\nwrite_stdout(\"ran\")\n",
    );
    let mut s = session();
    let o = s.load(&path, None, Load::Whole);
    assert_eq!(o.out, "ran");
    assert_eq!(o.result, Ok(vec!["inc1".to_string()]));
    assert_eq!(value(s.eval("inc1(1)", Some(&path), None)), "2");
    let Stop::Error(f) = stop(s.eval("inc1(1)", None, None)) else {
        panic!("the session's own context does not resolve a file's names")
    };
    assert_eq!(f.code, "B0001");
    let Stop::Error(f) = stop(s.eval("helper()", Some(&path), None)) else {
        panic!("expected an error")
    };
    assert_eq!(f.code, "B0001");
    let doc = s.doc("inc1", Some(&path)).expect("inc1 is documented");
    assert_eq!(doc.signature.as_deref(), Some("def inc1(x)"));
    assert_eq!(doc.doc.as_deref(), Some("Add one."));
    assert_eq!(doc.namespace, "this file");
}

#[test]
fn evaluating_in_an_unloaded_file_loads_its_definitions_only() {
    let path = file(
        "defs.b",
        "def three()\n  3\nend\n\nwrite_stdout(\"main\")\n",
    );
    let mut s = session();
    let o = s.eval("three()", Some(&path), None);
    assert_eq!(o.out, "", "the file's program did not run");
    assert_eq!(o.result, Ok("3".to_string()));
}

#[test]
fn a_buffer_text_loads_in_place_of_the_file_on_disk() {
    let path = file("buffer.b", "def v()\n  1\nend\n");
    let mut s = session();
    s.load(&path, Some("def v()\n  2\nend\n"), Load::Whole)
        .result
        .unwrap();
    assert_eq!(value(s.eval("v()", Some(&path), None)), "2");
}

#[test]
fn a_macro_call_expands_one_step_or_fully() {
    let mut s = session();
    value(s.eval(
        "defmacro twice(e)\n  quote\n    [unquote(e), unquote(e)]\n  end\nend\n",
        None,
        None,
    ));
    let one = s.expand("twice(1 + 1)", None, Step::One);
    assert_eq!(one.result, Ok("[1 + 1, 1 + 1]".to_string()));
    assert_eq!(value(s.eval("twice(1 + 1)", None, None)), "[2, 2]");
    let all = s.expand("defflow(slug, trim, downcase)", None, Step::All);
    let form = all.result.expect("defflow expands");
    assert_ne!(form, "defflow(slug, trim, downcase)", "{form}");
}

#[test]
fn completion_offers_the_contexts_names_and_the_builtins() {
    let mut s = session();
    value(s.eval("def lengthy(x)\n  x\nend\n", None, None));
    let items = s.complete("length", None);
    let names: Vec<&str> = items.iter().map(|i| i.name.as_str()).collect();
    assert!(names.contains(&"lengthy"), "{names:?}");
    assert!(names.contains(&"length"), "{names:?}");
    let builtin = items.iter().find(|i| i.name == "length").unwrap();
    assert_eq!(builtin.namespace, "builtin");
    assert!(builtin.doc.is_some());
    assert!(s.complete("zzz_none", None).is_empty());
    assert_eq!(s.doc("blue::length", None).unwrap().namespace, "builtin");
    assert!(s.doc("no_such_name", None).is_none());
}

#[test]
fn reset_forgets_every_definition() {
    let mut s = session();
    value(s.eval("def f()\n  1\nend\n", None, None));
    s.reset();
    let Stop::Error(f) = stop(s.eval("f()", None, None)) else {
        panic!("expected an error")
    };
    assert_eq!(f.code, "B0001");
}

#[test]
fn incomplete_input_is_told_from_a_wrong_one() {
    for open in ["def f(x)\n  x\n", "x = \"abc", "[1,", "f(1 +"] {
        assert!(incomplete(open), "{open:?}");
    }
    for done in ["1 + 2", "def f(x)\n  x\nend", ""] {
        assert!(!incomplete(done), "{done:?}");
    }
    assert!(
        !incomplete("1 + + )"),
        "a wrong token mid-line is an error, not more to read"
    );
}
