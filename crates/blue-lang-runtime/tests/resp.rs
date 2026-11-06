#![cfg(feature = "sys")]

mod peers;

use peers::run_bidamas;
use tatara_lisp_eval::Value;

fn ok(src: &str) -> Value {
    run_bidamas(src).unwrap_or_else(|e| panic!("{src}\n{e}"))
}

fn err(src: &str) -> String {
    match run_bidamas(src) {
        Ok(v) => panic!("{src}\nmust raise, answered {v:?}"),
        Err(e) => e,
    }
}

fn shown(v: &Value) -> String {
    format!("{v:?}")
}

fn conn(port: u16, extra: &str) -> String {
    format!("use(\"chozou/kiibariu\")\nc = chozou::kiibariu::connect({{host: \"127.0.0.1\", port: {port}, tls: false{extra}}})\n")
}

#[test]
fn get_set_ttl_and_del_round_trip_with_a_password_file() {
    let Some(v) = peers::valkey(Some("hunter2")) else {
        return;
    };
    let pw = v.dir.join("pw");
    std::fs::write(&pw, "hunter2\n").unwrap();
    let head = conn(v.port, &format!(", password_file: \"{}\"", pw.display()));
    let out = ok(&format!(
        "{head}chozou::kiibariu::set_key(c, \"a\", \"1\", nil)\n\
         chozou::kiibariu::set_key(c, \"b\", \"2\", 60000)\n\
         t = chozou::kiibariu::pttl(c, \"b\")\n\
         [chozou::kiibariu::get_key(c, \"a\"), chozou::kiibariu::get_key(c, \"nope\"), t > 0 and t <= 60000, chozou::kiibariu::pttl(c, \"a\"), chozou::kiibariu::del(c, [\"a\", \"b\", \"z\"]), chozou::kiibariu::get_key(c, \"a\")]"
    ));
    assert_eq!(
        shown(&out),
        shown(&Value::list(vec![
            Value::Str("1".into()),
            Value::Nil,
            Value::Bool(true),
            Value::Int(-1),
            Value::Int(2),
            Value::Nil,
        ]))
    );
    let wrong = v.dir.join("wrong");
    std::fs::write(&wrong, "nope\n").unwrap();
    let e = err(&conn(
        v.port,
        &format!(", password_file: \"{}\"", wrong.display()),
    ));
    assert!(e.contains("resp_connect"), "{e}");
}

#[test]
fn tls_on_is_refused_by_name_and_off_only_on_loopback() {
    let e =
        err("use(\"chozou/kiibariu\")\nchozou::kiibariu::connect({host: \"127.0.0.1\", port: 1})");
    assert!(e.contains("no TLS transport"), "{e}");
    let e = err("resp_connect(\"10.0.0.1\", 6379, nil, false)");
    assert!(e.contains("only for 127.0.0.1"), "{e}");
}

#[test]
fn a_subscriber_receives_what_another_connection_publishes() {
    let Some(v) = peers::valkey(None) else { return };
    let head = conn(v.port, "");
    let out = ok(&format!(
        "{head}s = chozou::kiibariu::connect({{host: \"127.0.0.1\", port: {}, tls: false}})\n\
         chozou::kiibariu::subscribe(s, [\"orders\", \"other\"])\n\
         n = chozou::kiibariu::publish(c, \"orders\", \"created 7\")\n\
         m = chozou::kiibariu::next_message(s, 2000)\n\
         [n, get(m, :channel), get(m, :payload), chozou::kiibariu::next_message(s, 50)]",
        v.port
    ));
    assert_eq!(
        shown(&out),
        shown(&Value::list(vec![
            Value::Int(1),
            Value::Str("orders".into()),
            Value::Str("created 7".into()),
            Value::Nil,
        ]))
    );
}

#[test]
fn scan_walks_every_key_of_a_pattern_in_batches() {
    let Some(v) = peers::valkey(None) else { return };
    let head = conn(v.port, "");
    let out = ok(&format!(
        "{head}resp_pipeline(c, map((i) -> [\"SET\", \"k:#{{to_s(i)}}\", \"x\"], range(25)))\n\
         chozou::kiibariu::set_key(c, \"other\", \"y\", nil)\n\
         length(chozou::kiibariu::scan(c, \"k:*\", 4))"
    ));
    assert_eq!(shown(&out), shown(&Value::Int(25)));
}

const PLAN: &str = "from = {fields: {\"total\" => :int}}\n\
    to = {fields: {\"total\" => :int, \"currency\" => :text}}\n\
    plan = {from:, to:, old: chozou::kiibariu::prefix(\"orders\", \"h1\", :order), new: chozou::kiibariu::prefix(\"orders\", \"h2\", :order), transform: (r) -> assoc(r, \"currency\", \"BRL\")}\n";

#[test]
fn strict_put_and_fetch_check_the_schema_both_ways() {
    let Some(v) = peers::valkey(None) else { return };
    let head = conn(v.port, "");
    let out = ok(&format!(
        "{head}{PLAN}chozou::kiibariu::put(c, from, \"orders:vh1:order:1\", {{\"total\" => 5}}, nil)\n\
         get(chozou::kiibariu::fetch(c, from, \"orders:vh1:order:1\"), \"total\")"
    ));
    assert_eq!(shown(&out), shown(&Value::Int(5)));
    let e = err(&format!(
        "{head}{PLAN}chozou::kiibariu::put(c, from, \"k\", {{\"total\" => \"5\"}}, nil)"
    ));
    assert!(e.contains("field total"), "{e}");
    let e = err(&format!(
        "{head}{PLAN}chozou::kiibariu::set_key(c, \"k\", \"{{\\\"t\\\":1}}\", nil)\nchozou::kiibariu::fetch(c, from, \"k\")"
    ));
    assert!(e.contains("no field total"), "{e}");
}

#[test]
fn upgrade_on_read_moves_one_entry_and_keeps_its_ttl() {
    let Some(v) = peers::valkey(None) else { return };
    let head = conn(v.port, "");
    let out = ok(&format!(
        "{head}{PLAN}chozou::kiibariu::put(c, from, \"orders:vh1:order:7\", {{\"total\" => 3}}, 90000)\n\
         r = chozou::kiibariu::read_upgrading(c, plan, 7)\n\
         t = chozou::kiibariu::pttl(c, \"orders:vh2:order:7\")\n\
         [get(r, \"currency\"), chozou::kiibariu::get_key(c, \"orders:vh1:order:7\"), t > 80000 and t <= 90000, get(chozou::kiibariu::read_upgrading(c, plan, 7), \"currency\"), chozou::kiibariu::read_upgrading(c, plan, 8)]"
    ));
    assert_eq!(
        shown(&out),
        shown(&Value::list(vec![
            Value::Str("BRL".into()),
            Value::Nil,
            Value::Bool(true),
            Value::Str("BRL".into()),
            Value::Nil,
        ]))
    );
}

#[test]
fn eager_upgrade_rewrites_every_old_key_in_batches_keeping_ttls() {
    let Some(v) = peers::valkey(None) else { return };
    let head = conn(v.port, "");
    let out = ok(&format!(
        "{head}{PLAN}chozou::kiibariu::put(c, from, \"orders:vh1:order:0\", {{\"total\" => 0}}, nil)\n\
         map((i) -> chozou::kiibariu::put(c, from, \"orders:vh1:order:#{{to_s(i)}}\", {{\"total\" => i}}, 90000), drop(1, range(23)))\n\
         moved = chozou::kiibariu::upgrade_eager(c, plan, 5)\n\
         [moved, length(chozou::kiibariu::scan(c, \"orders:vh1:*\", 10)), length(chozou::kiibariu::scan(c, \"orders:vh2:*\", 10)), chozou::kiibariu::pttl(c, \"orders:vh2:order:0\"), chozou::kiibariu::pttl(c, \"orders:vh2:order:9\") > 80000, get(chozou::kiibariu::fetch(c, to, \"orders:vh2:order:9\"), \"total\")]"
    ));
    assert_eq!(
        shown(&out),
        shown(&Value::list(vec![
            Value::Int(23),
            Value::Int(0),
            Value::Int(23),
            Value::Int(-1),
            Value::Bool(true),
            Value::Int(9),
        ]))
    );
}
