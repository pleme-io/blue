@moduledoc """
sutoriimu (ストリーム) — NATS JetStream over the runtime's NATS words.

ensure_stream declares a stream, publish waits for the stream's ack, durable
declares a durable pull consumer with explicit acks, fetch pulls a batch, and
ack and nak settle each message. The outbox writes a change and its events
in one Postgres transaction and drain moves the events to the stream after
the commit. consumer runs a handler for every message under a supervisor: a
message the handler raises on is nak'd and the worker crashes, so the
supervisor restarts it and the stream delivers the message again.

    api("orders", "INFO") #=> "$JS.API.STREAM.INFO.orders"
"""

use("kyohi", [:host_handle])
use("retsu", [:first, :is_empty, :size])
use("tesuto", [:raises?])

@doc """
nats_url: a nats:// url, else a :bad_option raise.

    nats_url("nats://127.0.0.1:4222") #=> "nats://127.0.0.1:4222"
"""
def nats_url(url)
  if not string?(url) or not starts_with?(url, "nats://")
    raise(:bad_option, "a consumer takes a nats:// url")
  end
  url
end

@doc """
api: the JetStream API subject for a stream verb.

    api("s", "CREATE") #=> "$JS.API.STREAM.CREATE.s"
"""
def api(stream, verb)
  "$JS.API.STREAM.#{verb}.#{stream}"
end

@doc """
name_ok?: whether a stream, consumer or table name has no dot, space or wildcard.

    name_ok?("orders") #=> true
"""
def name_ok?(name)
  string?(name) and
    name != "" and
    not contains?(name, ".") and
    not contains?(name, " ") and
    not contains?(name, "*") and
    not contains?(name, ">")
end

@doc """
need_name: a name that is ok, else a :bad_option raise naming what it names.

    need_name("stream", "orders") #=> "orders"
"""
def need_name(what, name)
  if not name_ok?(name)
    raise(:bad_option, "a #{what} name is text with no dot, space or wildcard")
  end
  name
end

@doc """
answer: a JetStream API reply read as a record; an error reply raises :jetstream.

    get(answer(json_stringify({seq: 3})), "seq") #=> 3
"""
def answer(text)
  r = json_read(text)
  e = get(r, "error")
  if e != nil
    raise(
      :jetstream,
      "#{to_s(get(e, "err_code"))}: #{to_s(get(e, "description"))}"
    )
  end
  r
end

@doc """
stream_config: the JetStream config of a file-backed stream over subjects.

    stream_config("s", ["s.>"]) #=> {name: "s", subjects: ["s.>"], storage: "file"}
"""
def stream_config(name, subjects)
  {name:, subjects:, storage: "file"}
end

@doc """
ensure_stream: declare a stream over subjects, created when absent; its info.

    raises?(:bad_option, () -> ensure_stream(nil, "a.b", ["x"])) #=> true
"""
def ensure_stream(c, name, subjects)
  need_name("stream", name)
  if not list?(subjects) or is_empty(subjects)
    raise(:bad_option, "a stream takes at least one subject")
  end
  declared(c, name, json_stringify(stream_config(name, subjects)))
end

@doc """
declared: create a stream, or update it when its name is already in use.

    raises?(:bad_option, () -> declared(nil, "s", "{}")) #=> true
"""
def declared(c, name, body)
  answer(
    nats_request(host_handle(c, "sutoriimu"), api(name, "CREATE"), body, 5000)
  )
rescue e
  if e.kind == :jetstream and contains?(e.message, "10058")
    answer(nats_request(c, api(name, "UPDATE"), body, 5000))
  else
    raise(e)
  end
end

@doc """
publish: publish to a stream's subject and wait for its ack: {stream:, seq:}.

    raises?(:bad_option, () -> publish(nil, "s.x", "p", 100)) #=> true
"""
def publish(c, subject, payload, wait_ms)
  r = answer(
    nats_request(host_handle(c, "sutoriimu"), subject, payload, wait_ms)
  )
  {stream: get(r, "stream"), seq: get(r, "seq")}
end

@doc """
consumer_config: the config of a durable consumer with explicit acks.

    get(get(consumer_config("s", "d", "s.>", 1), :config), :ack_wait) #=> 1000000
"""
def consumer_config(stream, name, filter, ack_wait_ms)
  {
    stream_name: stream,
    config: {
      durable_name: name,
      ack_policy: "explicit",
      filter_subject: filter,
      ack_wait: ack_wait_ms * 1_000_000
    }
  }
end

@doc """
durable: declare a durable pull consumer with explicit acks on a stream.

    raises?(:bad_option, () -> durable(nil, "s", "a b", "s.>", 1000)) #=> true
"""
def durable(c, stream, name, filter, ack_wait_ms)
  need_name("stream", stream)
  need_name("consumer", name)
  answer(
    nats_request(
      c,
      "$JS.API.CONSUMER.CREATE.#{stream}.#{name}",
      json_stringify(consumer_config(stream, name, filter, ack_wait_ms)),
      5000
    )
  )
end

@doc """
deliveries: how many times JetStream has delivered a message, read from its ack subject.

    deliveries("$JS.ACK.s.c.2.9.9.1700000000000000000.0") #=> 2
"""
def deliveries(reply)
  parts = split(reply or "", ".")
  at = if size(parts) == 9
    4
  elsif size(parts) >= 11
    6
  end
  if at.nil?
    nil
  else
    to_int(nth(at, parts))
  end
end

@doc """
delivered: a pulled message with its delivery count.

    get(delivered({subject: "s", payload: "p", reply: nil}), :deliveries) #=> nil
"""
def delivered(m)
  {
    subject: get(m, :subject),
    payload: get(m, :payload),
    reply: get(m, :reply),
    deliveries: deliveries(get(m, :reply))
  }
end

@doc """
pull_request: the body of a pull for a batch, expiring after wait_ms.

    json_read(pull_request(2, 1)) #=> {"batch" => 2, "expires" => 1000000}
"""
def pull_request(batch, wait_ms)
  json_stringify({batch:, expires: wait_ms * 1_000_000})
end

@doc """
gather: messages read from a pull's inbox until the batch is full, a status arrives or time runs out.

    gather(nil, 0, 10, []) #=> []
"""
def gather(sub, batch, wait_ms, got)
  if size(got) >= batch
    got
  else
    m = nats_next_message(sub, wait_ms + 500)
    if m.nil? or get(m, :status) != nil
      got
    else
      gather(sub, batch, wait_ms, append(got, [delivered(m)]))
    end
  end
end

@doc """
fetch: up to batch messages from a durable consumer, waiting at most wait_ms.

    raises?(:bad_option, () -> fetch(nil, "s", "d", 1, 100)) #=> true
"""
def fetch(c, stream, name, batch, wait_ms)
  inbox = nats_inbox(host_handle(c, "sutoriimu"))
  sub = nats_subscribe(c, inbox)
  nats_publish(
    c,
    "$JS.API.CONSUMER.MSG.NEXT.#{stream}.#{name}",
    pull_request(batch, wait_ms),
    inbox
  )
  got = gather(sub, batch, wait_ms, [])
  nats_unsubscribe(sub)
  got
end

@doc """
ack: tell the stream a message is done.

    raises?(:bad_option, () -> ack(nil, {reply: "r"})) #=> true
"""
def ack(c, m)
  nats_publish(host_handle(c, "sutoriimu"), get(m, :reply), "+ACK")
end

@doc """
nak: tell the stream to deliver a message again, after delay_ms when it is not nil.

    raises?(:bad_option, () -> nak(nil, {reply: "r"}, nil)) #=> true
"""
def nak(c, m, delay_ms)
  body = if delay_ms.nil?
    "-NAK"
  else
    "-NAK #{json_stringify({delay: delay_ms * 1_000_000})}"
  end
  nats_publish(host_handle(c, "sutoriimu"), get(m, :reply), body)
end

@doc """
outbox_ddl: the table the outbox writes to.

    contains?(outbox_ddl("blue_outbox"), "CREATE TABLE IF NOT EXISTS") #=> true
"""
def outbox_ddl(table)
  need_name("table", table)
  "CREATE TABLE IF NOT EXISTS \"#{table}\" (id bigserial PRIMARY KEY, subject text NOT NULL, payload text NOT NULL, created_at timestamptz NOT NULL DEFAULT now())"
end

@doc """
outbox_insert: the statement that records one event in the outbox.

    outbox_insert("ob") #=> "INSERT INTO \"ob\" (subject, payload) VALUES ($1, $2)"
"""
def outbox_insert(table)
  "INSERT INTO \"#{table}\" (subject, payload) VALUES ($1, $2)"
end

@doc """
in_transaction: run f between BEGIN and COMMIT, rolling back and raising again when it raises.

    raises?(:bad_option, () -> in_transaction(nil, () -> 1)) #=> true
"""
def in_transaction(pg, f)
  pg_execute(host_handle(pg, "sutoriimu"), "BEGIN")
  out = f()
  pg_execute(pg, "COMMIT")
  out
rescue e
  if foreign?(pg)
    pg_execute(pg, "ROLLBACK")
  end
  raise(e)
end

@doc """
write_with_outbox: run a change and record its events in the same transaction; the change's rows.

    raises?(:bad_option, () -> write_with_outbox(nil, "a b", ["SELECT 1", []], [])) #=> true
"""
def write_with_outbox(pg, table, change, events)
  need_name("table", table)
  in_transaction(
    pg,
    fn()
      rows = get(pg_query(pg, first(change), nth(1, change)), :rows)
      map(
        (ev) -> pg_query(pg, outbox_insert(table), [first(ev), nth(1, ev)]),
        events
      )
      rows
    end
  )
end

@doc """
drain_select: the statement that locks the next batch of outbox events.

    contains?(drain_select("ob", 5), "LIMIT 5") #=> true
"""
def drain_select(table, batch)
  "SELECT id, subject, payload FROM \"#{table}\" ORDER BY id LIMIT #{to_s(batch)} FOR UPDATE SKIP LOCKED"
end

@doc """
drain_delete: the statement that removes drained events by id.

    drain_delete("ob", [3]) #=> "DELETE FROM \"ob\" WHERE id IN (3)"
"""
def drain_delete(table, ids)
  "DELETE FROM \"#{table}\" WHERE id IN (#{join(map(to_s, ids), ", ")})"
end

@doc """
drain: publish up to batch outbox events to the stream, each acked, and delete them; how many moved.

    raises?(:bad_option, () -> drain(nil, nil, "a.b", 10, 100)) #=> true
"""
def drain(pg, js, table, batch, wait_ms)
  need_name("table", table)
  in_transaction(
    pg,
    fn()
      rows = get(pg_query(pg, drain_select(table, batch), []), :rows)
      map(
        (r) -> publish(js, get(r, "subject"), get(r, "payload"), wait_ms),
        rows
      )
      if not is_empty(rows)
        pg_execute(pg, drain_delete(table, map((r) -> get(r, "id"), rows)))
      end
      size(rows)
    end
  )
end

@doc """
settle: run the handler on one message and ack it; nak and raise again when the handler raises.

    raises?(:bad_option, () -> settle(nil, (_m) -> 1, {reply: "r"})) #=> true
"""
def settle(c, handler, m)
  handler(m)
  ack(c, m)
rescue e
  nak(c, m, nil)
  raise(e)
end

@doc """
work: a worker's loop: fetch, run the handler on each message, ack it; a raise naks and ends the worker.

    raises?(:bad_option, () -> work("x", "s", "d", (_m) -> 1, 1, 1)) #=> true
"""
def work(url, stream, name, handler, batch, wait_ms)
  c = nats_connect(nats_url(url))
  loop = fn()
    map((m) -> settle(c, handler, m), fetch(c, stream, name, batch, wait_ms))
    loop()
  end
  loop()
end

@doc """
consumer: a supervisor running workers for a durable consumer; each worker restarted when its handler raises.

    raises?(:bad_option, () -> consumer("x", "s", "d", (_m) -> 1, {})) #=> true
"""
def consumer(url, stream, name, handler, opts)
  nats_url(url)
  workers = get(opts, :workers) or 1
  batch = get(opts, :batch) or 10
  wait_ms = get(opts, :wait_ms) or 1000
  supervisor(
    :one_for_one,
    map(
      (_i) -> [() -> work(url, stream, name, handler, batch, wait_ms), []],
      range(workers)
    ),
    get(opts, :max_restarts) or 5
  )
end

test "an API reply with an error raises :jetstream naming the code"
  assert get(answer("{\"stream\":\"s\",\"seq\":2}"), "seq") == 2
  caught = begin
    answer("{\"error\":{\"code\":404,\"err_code\":10059,\"description\":\"stream not found\"}}")
  rescue e
    e
  end
  assert caught.kind == :jetstream
  assert contains?(caught.message, "10059") == true
end

test "names with a dot, a space or a wildcard are refused"
  assert name_ok?("orders") == true
  assert raises?(:bad_option, () -> need_name("stream", "a.b"))
  assert raises?(:bad_option, () -> need_name("stream", "a b"))
  assert raises?(:bad_option, () -> need_name("stream", "a>"))
  assert raises?(:bad_option, () -> need_name("stream", ""))
end

test "a consumer acks explicitly and waits in nanoseconds"
  c = consumer_config("s", "d", "s.>", 30000)
  assert get(get(c, :config), :ack_policy) == "explicit"
  assert get(get(c, :config), :ack_wait) == 30_000_000_000
  assert json_read(pull_request(5, 200)) ==
    {"batch" => 5, "expires" => 200_000_000}
end

test "deliveries reads both ack subject forms and nothing else"
  assert deliveries("$JS.ACK.s.c.3.1.1.1.0") == 3
  assert deliveries("$JS.ACK.dom.acc.s.c.4.1.1.1.0.tok") == 4
  assert deliveries("other").nil?
  assert deliveries(nil).nil?
end

test "the outbox statements quote the table and list the drained ids"
  assert outbox_insert("ob") ==
    "INSERT INTO \"ob\" (subject, payload) VALUES ($1, $2)"
  assert drain_delete("ob", [1, 2]) == "DELETE FROM \"ob\" WHERE id IN (1, 2)"
  assert contains?(drain_select("ob", 3), "SKIP LOCKED") == true
  assert raises?(:bad_option, () -> outbox_ddl("a\"b c"))
end
