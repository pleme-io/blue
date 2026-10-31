//! The forensic half of a crash trace: the violation a node reads off an
//! exit, the place it names when the runtime gave it the program's files,
//! the version 2 traces it still reads, and the content address it writes a
//! trace under.

mod support;

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;

use blue_lang_proc::{Class, ClockKind, HostIo, NodeConfig, Source, Trace};
use blue_lang_runtime::Hold;
use support::{configure, show};

fn held() -> NodeConfig {
    let hold = Hold::from(blue_lang_runtime::session::frame_granting(&[]));
    let io = HostIo::new();
    let (h, i) = (hold.clone(), io.clone());
    let mut config = NodeConfig::new(Arc::new(move || {
        let mut child = blue_lang_runtime::interpreter_hostless();
        h.bind(&mut child, "this process's frame", &i);
        child
    }));
    config.budget.quantum = Some(100);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    config.frame = Some(hold.frame());
    config.host_io = io;
    config
}

const BREACHING: &str = "def probe(path)\n  is_file?(path)\nend\n\
     def reader(parent)\n  receive()\n  send(parent, probe(\"/etc/hosts\"))\nend\n\
     r = spawn(reader, [self()])\nm = monitor(r)\nsend(r, \"go\")\nreceive(:_, 5000)";

/// The text the support harness evaluates, which the spans index.
fn lowered(src: &str) -> String {
    blue_lang_syntax::parse_program(src)
        .expect("parses")
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn a_breach_names_the_place_of_its_call_when_the_node_has_the_files() {
    let config = held();
    let text = lowered(BREACHING);
    let source = Source {
        file: "probe.lisp".into(),
        text: Arc::from(text.as_str()),
    };
    config.places.defer(move || {
        BTreeMap::from([
            ("probe".to_string(), source.clone()),
            ("reader".to_string(), source),
        ])
    });
    let (mut root, node) = configure(config);
    let out = show(&mut root, BREACHING);
    assert!(out.contains("capability-breach"), "{out}");
    let trace = node.traces().pop().expect("a trace");
    let v = trace.violation.clone().expect("a violation");
    assert_eq!(v.class, Class::LatticeCeilingBreach);
    assert_eq!(v.host.as_deref(), Some("is_file?"));
    assert_eq!(v.entry, Some(trace.tape.len() - 1));
    let at = v.at.expect("a coordinate");
    assert_eq!(at.definition.as_deref(), Some("probe"));
    let call = text.find("(is_file? path)").expect("the call");
    assert_eq!(at.span.start, call, "the span of the breaching call");
    let line = text[..call].matches('\n').count() + 1;
    let place = at.place.expect("a place");
    assert_eq!((place.file.as_str(), place.line), ("probe.lisp", line));
    let defined = trace.defined_at.clone().expect("where reader is defined");
    assert_eq!(
        defined.line,
        text[..text.find("(define (reader").expect("def")]
            .matches('\n')
            .count()
            + 1
    );
    assert_eq!(trace.host_io, Some(0));
    let back = Trace::from_json(&trace.to_json()).expect("reads");
    assert_eq!(back.violation, trace.violation);
    assert_eq!(back.defined_at, trace.defined_at);
}

#[test]
fn a_runaway_is_a_thermodynamic_cycle_exhaustion() {
    let mut config = NodeConfig::new(Arc::new(blue_lang_runtime::interpreter_hostless));
    config.budget.quantum = Some(100);
    config.budget.fuel = Some(5_000);
    config.clock = ClockKind::Virtual;
    config.trace_dir = None;
    let (mut root, node) = configure(config);
    let out = show(
        &mut root,
        "def spin(n)\n  spin(n + 1)\nend\nsup = supervisor(:one_for_one, [[spin, [0]]], 0)\nm = monitor(sup)\nreceive(:_, 5000)",
    );
    assert!(out.contains("gave_up"), "{out}");
    let trace = node.traces().pop().expect("a trace");
    assert_eq!(trace.reason_kind, "runaway");
    let v = trace.violation.expect("a runaway is a violation");
    assert_eq!(v.class, Class::ThermodynamicCycleExhaustion);
    assert!(v.host.is_none() && v.capability.is_none() && v.at.is_none());
}

#[test]
fn a_version_2_trace_reads_with_its_violation_read_off_the_tape() {
    let (mut root, node) = configure(held());
    let _ = show(&mut root, BREACHING);
    let mut j = node.traces().pop().expect("a trace").to_json();
    assert_eq!(j["version"], 3);
    j["version"] = serde_json::json!(2);
    for k in ["violation", "defined_at", "frame"] {
        j.as_object_mut().expect("object").remove(k);
    }
    let last = j["tape"].as_array().expect("tape").len() - 1;
    j["tape"][last]["fatal"]
        .as_object_mut()
        .expect("fatal")
        .remove("at");
    let v2 = Trace::from_json(&j).expect("a version 2 trace reads");
    let v = v2.violation.expect("read off the exit and the tape");
    assert_eq!(v.class, Class::LatticeCeilingBreach);
    assert_eq!(v.host.as_deref(), Some("is_file?"));
    assert!(v.at.is_none(), "version 2 kept no span");
    assert!(v2.defined_at.is_none() && v2.host_io.is_none());
}

#[test]
fn a_trace_is_written_under_its_crash_hash_and_the_same_crash_is_the_same_file() {
    let (mut root, node) = configure(held());
    let _ = show(&mut root, BREACHING);
    let trace = node.traces().pop().expect("a trace");
    let dir: PathBuf =
        std::env::temp_dir().join(format!("blue-proc-forensics-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let path = trace.write_to(&dir).expect("written");
    assert_eq!(
        path.file_name().and_then(|n| n.to_str()),
        Some(format!("{}.bluecrash", trace.crash_hash()).as_str())
    );
    let bytes = std::fs::read(&path).expect("read");
    assert_eq!(bytes, trace.bytes());
    assert!(!bytes.contains(&b'\n'), "canonical: no whitespace");
    assert_eq!(trace.write_to(&dir).expect("again"), path);
    assert_eq!(std::fs::read_dir(&dir).expect("dir").count(), 1);
    let _ = std::fs::remove_dir_all(dir);
}
