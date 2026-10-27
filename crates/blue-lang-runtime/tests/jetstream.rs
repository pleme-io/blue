#![cfg(feature = "sys")]

mod peers;

use peers::run_bidamas;
use tatara_lisp_eval::Value;

fn ok(src: &str) -> Value {
    run_bidamas(src).unwrap_or_else(|e| panic!("{src}\n{e}"))
}

fn shown(v: &Value) -> String {
    format!("{v:?}")
}

fn strs(xs: &[&str]) -> Value {
    Value::list(
        xs.iter()
            .map(|x| Value::Str((*x).into()))
            .collect::<Vec<_>>(),
    )
}

fn head(port: u16) -> String {
    format!(
        "use(\"sutoriimu\")\nurl = \"nats://127.0.0.1:{port}\"\nc = nats_connect(url)\n\
         sutoriimu::ensure_stream(c, \"orders\", [\"orders.>\"])\n"
    )
}

#[test]
fn a_publish_is_acked_with_its_sequence_and_a_stream_redeclares() {
    let Some(n) = peers::nats(true) else { return };
    let out = ok(&format!(
        "{}a = sutoriimu::publish(c, \"orders.created\", \"1\", 2000)\n\
         b = sutoriimu::publish(c, \"orders.created\", \"2\", 2000)\n\
         sutoriimu::ensure_stream(c, \"orders\", [\"orders.>\"])\n\
         [get(a, :stream), get(a, :seq), get(b, :seq)]",
        head(n.port)
    ));
    assert_eq!(
        shown(&out),
        shown(&Value::list(vec![
            Value::Str("orders".into()),
            Value::Int(1),
            Value::Int(2),
        ]))
    );
}

#[test]
fn a_durable_consumer_redelivers_a_nak_and_not_an_ack() {
    let Some(n) = peers::nats(true) else { return };
    let out = ok(&format!(
        "{}sutoriimu::durable(c, \"orders\", \"billing\", \"orders.>\", 30000)\n\
         sutoriimu::publish(c, \"orders.created\", \"a\", 2000)\n\
         sutoriimu::publish(c, \"orders.created\", \"b\", 2000)\n\
         first_batch = sutoriimu::fetch(c, \"orders\", \"billing\", 10, 500)\n\
         sutoriimu::ack(c, nth(0, first_batch))\n\
         sutoriimu::nak(c, nth(1, first_batch))\n\
         again = sutoriimu::fetch(c, \"orders\", \"billing\", 10, 500)\n\
         sutoriimu::ack(c, nth(0, again))\n\
         empty = sutoriimu::fetch(c, \"orders\", \"billing\", 10, 300)\n\
         [map((m) -> get(m, :payload), first_batch), map((m) -> get(m, :payload), again), get(nth(0, again), :deliveries), length(empty)]",
        head(n.port)
    ));
    assert_eq!(
        shown(&out),
        shown(&Value::list(vec![
            strs(&["a", "b"]),
            strs(&["b"]),
            Value::Int(2),
            Value::Int(0),
        ]))
    );
}

#[test]
fn the_outbox_commits_with_the_change_and_drains_to_the_stream() {
    let Some(n) = peers::nats(true) else { return };
    let Some(pg) = peers::postgres() else { return };
    let out = ok(&format!(
        "{}pg = pg_connect(\"postgres://blue@127.0.0.1:{}/postgres\")\n\
         pg_execute(pg, sutoriimu::outbox_ddl(\"outbox\"))\n\
         pg_execute(pg, \"CREATE TABLE orders (id int PRIMARY KEY, total int)\")\n\
         sutoriimu::write_with_outbox(pg, \"outbox\", [\"INSERT INTO orders VALUES ($1, $2)\", [1, 10]], [[\"orders.created\", \"1\"]])\n\
         failed = begin\n  sutoriimu::write_with_outbox(pg, \"outbox\", [\"INSERT INTO orders VALUES ($1, $2)\", [1, 20]], [[\"orders.created\", \"dup\"]])\nrescue e\n  e.kind\nend\n\
         rows = length(get(pg_query(pg, \"SELECT * FROM outbox\", []), :rows))\n\
         sutoriimu::durable(c, \"orders\", \"audit\", \"orders.>\", 30000)\n\
         moved = sutoriimu::drain(pg, c, \"outbox\", 10, 2000)\n\
         left = length(get(pg_query(pg, \"SELECT * FROM outbox\", []), :rows))\n\
         got = sutoriimu::fetch(c, \"orders\", \"audit\", 10, 500)\n\
         [rows, failed != nil, moved, left, map((m) -> get(m, :payload), got)]",
        head(n.port),
        pg.port
    ));
    assert_eq!(
        shown(&out),
        shown(&Value::list(vec![
            Value::Int(1),
            Value::Bool(true),
            Value::Int(1),
            Value::Int(0),
            strs(&["1"]),
        ]))
    );
}

#[test]
fn a_supervised_consumer_restarts_after_a_handler_raises_and_gets_the_message_again() {
    let Some(n) = peers::nats(true) else { return };
    let out = ok(&format!(
        "{}sutoriimu::durable(c, \"orders\", \"ship\", \"orders.>\", 30000)\n\
         map((p) -> sutoriimu::publish(c, \"orders.created\", p, 2000), [\"a\", \"boom\", \"b\"])\n\
         parent = self()\n\
         handler = fn(m)\n  if get(m, :payload) == \"boom\" and get(m, :deliveries) == 1\n    raise(:poison, \"first delivery\")\n  end\n  send(parent, [get(m, :payload), get(m, :deliveries)])\nend\n\
         sutoriimu::consumer(url, \"orders\", \"ship\", handler, {{batch: 1, wait_ms: 200}})\n\
         take = fn(acc)\n  if length(acc) == 3\n    acc\n  else\n    take(append(acc, [receive(:_, 10000, :none)]))\n  end\nend\n\
         take([])",
        head(n.port)
    ));
    assert_eq!(
        shown(&out),
        shown(&Value::list(vec![
            Value::list(vec![Value::Str("a".into()), Value::Int(1)]),
            Value::list(vec![Value::Str("boom".into()), Value::Int(2)]),
            Value::list(vec![Value::Str("b".into()), Value::Int(1)]),
        ]))
    );
}
