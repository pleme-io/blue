@moduledoc """
kiibariu (キーバリュー) — Valkey and Redis over the runtime's RESP words.

connect opens a connection from a record: host, port (6379), password_file
(a path; a literal password is refused), tls (on unless set to false, and off
only on 127.0.0.1) and timeout_ms. get_key, set_key (with a TTL in milliseconds),
del, publish, subscribe and next_message are the cache and pub/sub verbs;
scan walks keys by pattern in batches.

Loose caches put the model version in the key (versioned_key), so a model
change moves reads to new keys and old ones expire by TTL. Strict caches
check every write and read against a schema (put, fetch) and evolve old
entries either on read (read_upgrading) or eagerly in batches that keep
each key's TTL (upgrade_eager).

    versioned_key("orders", "3f2a", :order, 7) #=> "orders:v3f2a:order:7"
"""

use("kyohi", %i[host_handle raised])
use("moji", %i[checked drop_chars])
use("retsu", %i[first is_empty size])
use("teeburu")

@doc """
default_port: the port Valkey and Redis listen on.

    default_port #=> 6379
"""
def default_port()
  6379
end

@doc """
settings: a connection record judged and given its defaults.

    get(settings({host: "127.0.0.1", tls: false}), :port) #=> 6379
"""
def settings(opts)
  checked(opts, %i[host port password_file tls timeout_ms])
  host = opts[:host]
  if not string?(host) or host == ""
    raise(:bad_option, "a connection takes host: non-empty text")
  end
  tls = opts[:tls]
  if tls != nil and not boolean?(tls)
    raise(:bad_option, "tls: is true or false")
  end
  file = opts[:password_file]
  if file != nil and not string?(file)
    raise(:bad_option, "password_file: is a path")
  end
  {
    host:,
    port: opts[:port] or default_port,
    password_file: file,
    tls: tls != false,
    timeout_ms: opts[:timeout_ms] or 5000
  }
end

@doc """
password: the password a password file holds, or nil when there is no file.

    password(nil) #=> nil
"""
def password(file)
  if file.nil?
    nil
  else
    trim(read_file(file))
  end
end

@doc """
connect: a connection opened from a settings record.

    raised(() -> connect({host: ""})) #=> :bad_option
"""
def connect(opts)
  s = settings(opts)
  resp_connect(
    s[:host],
    s[:port],
    password(s[:password_file]),
    s[:tls],
    s[:timeout_ms]
  )
end

@doc """
close: close a connection.

    raised(() -> close(nil)) #=> :bad_option
"""
def close(c)
  resp_close(host_handle(c, "kiibariu"))
end

@doc """
get_key: the text stored at a key, or nil.

    raised(() -> get_key(nil, "k")) #=> :bad_option
"""
def get_key(c, key)
  resp_command(host_handle(c, "kiibariu"), ["GET", key])
end

@doc """
ttl_ok?: whether a TTL is nil or a positive number of milliseconds.

    ttl_ok?(500) #=> true
"""
def ttl_ok?(ttl_ms)
  ttl_ms.nil? or integer?(ttl_ms) and ttl_ms > 0
end

@doc """
set_command: the SET command for a value and a TTL in milliseconds (nil: none).

    set_command("k", "v", 500) #=> ["SET", "k", "v", "PX", 500]
"""
def set_command(key, value, ttl_ms)
  if not ttl_ok?(ttl_ms)
    raise(:bad_option, "a TTL is a positive number of milliseconds or nil")
  end
  if ttl_ms.nil?
    ["SET", key, value]
  else
    ["SET", key, value, "PX", ttl_ms]
  end
end

@doc """
set_key: store text at a key, with a TTL in milliseconds or nil.

    raised(() -> set_key(nil, "k", "v", 0)) #=> :bad_option
"""
def set_key(c, key, value, ttl_ms)
  resp_command(c, set_command(key, value, ttl_ms))
  nil
end

@doc """
del: remove keys; how many existed.

    del(nil, []) #=> 0
"""
def del(c, keys)
  if is_empty(keys)
    0
  else
    resp_command(c, append(["DEL"], keys))
  end
end

@doc """
pttl: the milliseconds a key has left; -1 when it never expires, nil when the key is absent.

    raised(() -> pttl(nil, "k")) #=> :bad_option
"""
def pttl(c, key)
  left = resp_command(host_handle(c, "kiibariu"), ["PTTL", key])
  if left != -2
    left
  end
end

@doc """
publish: send a message on a channel; how many subscribers got it.

    raised(() -> publish(nil, "ch", "m")) #=> :bad_option
"""
def publish(c, channel, message)
  resp_command(host_handle(c, "kiibariu"), ["PUBLISH", channel, message])
end

@doc """
subscribe: turn a connection into a subscriber of channels.

    raised(() -> subscribe(nil, [])) #=> :bad_option
"""
def subscribe(c, channels)
  if is_empty(channels)
    raise(:bad_option, "subscribe takes at least one channel")
  end
  resp_command(c, append(["SUBSCRIBE"], channels))
  map((_ch) -> resp_next(c, 5000), drop(1, channels))
  nil
end

@doc """
pushed: a pushed pub/sub reply as {channel:, payload:}, nil for any other reply.

    pushed(["message", "ch", "hi"]) #=> {channel: "ch", payload: "hi"}
"""
def pushed(reply)
  if list?(reply) and size(reply) == 3 and first(reply) == "message"
    {channel: reply[1], payload: reply[2]}
  end
end

@doc """
next_message: {channel:, payload:} for the next message, or nil when none came in time.

    raised(() -> next_message(nil, 0)) #=> :bad_option
"""
def next_message(c, wait_ms)
  reply = resp_next(host_handle(c, "kiibariu"), wait_ms)
  if reply.nil?
    nil
  else
    pushed(reply) or next_message(c, wait_ms)
  end
end

@doc """
scan_step: one SCAN call; [next cursor, keys].

    raised(() -> scan_step(nil, "0", "*", 10)) #=> :bad_option
"""
def scan_step(c, cursor, pattern, batch)
  reply = resp_command(
    host_handle(c, "kiibariu"),
    ["SCAN", cursor, "MATCH", pattern, "COUNT", batch]
  )
  [first(reply), reply[1]]
end

@doc """
scan_each: call f with each batch of keys matching a pattern; how many keys were seen.

    raised(() -> scan_each(nil, "*", 10, (_k) -> nil)) #=> :bad_option
"""
def scan_each(c, pattern, batch, f)
  walk = fn(cursor, seen)
    step = scan_step(c, cursor, pattern, batch)
    keys = step[1]
    if not is_empty(keys)
      f(keys)
    end
    if first(step) == "0"
      seen + size(keys)
    else
      walk(first(step), seen + size(keys))
    end
  end
  walk("0", 0)
end

@doc """
scan: every key matching a pattern.

    raised(() -> scan(nil, "*", 10)) #=> :bad_option
"""
def scan(c, pattern, batch)
  found = [[]]
  scan_each(
    c,
    pattern,
    batch,
    (keys) -> set!(found, [append(first(found), keys)])
  )
  first(found)
end

@doc """
versioned_key: a cache key that carries the model version's hash.

    versioned_key("orders", "ab", :order, 1) #=> "orders:vab:order:1"
"""
def versioned_key(namespace, version_hash, entity, id)
  "#{prefix(namespace, version_hash, entity)}#{to_s(id)}"
end

@doc """
prefix: the part of a versioned key before the id.

    prefix("orders", "ab", :order) #=> "orders:vab:order:"
"""
def prefix(namespace, version_hash, entity)
  "#{namespace}:v#{version_hash}:#{to_s(entity)}:"
end

@doc """
field_types: the field types a strict schema names.

    field_types #=> [:text, :int, :float, :bool, :list, :record, :any]
"""
def field_types()
  %i[text int float bool list record any]
end

@doc """
of_type?: whether a value is of a schema field type, judged by teeburu's strict model check.

    of_type?(:int, "1") #=> false
"""
def of_type?(type, v)
  teeburu::holds?(type, v)
end

@doc """
check: the record when it holds to a strict schema (teeburu::kv_check: every field present and typed, no field the schema does not declare unless `strict: false`), else one :bad_value raise naming every finding.

    check({fields: {"n" => :int}}, {"n" => 1}) #=> {"n" => 1}
"""
def check(schema, rec)
  teeburu::kv_check(schema, rec)
end

@doc """
stored: a record checked against a schema and written as JSON.

    json_read(stored({fields: {"n" => :int}}, {"n" => 1})) #=> {"n" => 1}
"""
def stored(schema, rec)
  json_stringify(check(schema, rec))
end

@doc """
loaded: stored JSON read back and checked against a schema; nil stays nil.

    loaded({fields: {}}, nil) #=> nil
"""
def loaded(schema, text)
  if text.nil?
    nil
  else
    check(schema, json_read(text))
  end
end

@doc """
put: check a record against a schema and store it as JSON.

    raised(() -> put(nil, {fields: {"n" => :int}}, "k", {"n" => "1"}, nil)) #=> :bad_value
"""
def put(c, schema, key, rec, ttl_ms)
  set_key(c, key, stored(schema, rec), ttl_ms)
end

@doc """
fetch: the record at a key, checked against a schema; nil when absent.

    raised(() -> fetch(nil, {fields: {}}, "k")) #=> :bad_option
"""
def fetch(c, schema, key)
  loaded(schema, get_key(c, key))
end

@doc """
plan_ok: an upgrade plan with two different key prefixes, else a :bad_option raise.

    raised(() -> plan_ok({old: "a:", new: "a:"})) #=> :bad_option
"""
def plan_ok(plan)
  checked(plan, %i[from to old new transform])
  if not string?(plan[:old]) or
      not string?(plan[:new]) or
      plan[:old] == plan[:new]
    raise(
      :bad_option,
      "an upgrade takes old: and new: key prefixes that differ"
    )
  end
  plan
end

@doc """
kept_ttl: the TTL a rewrite keeps: a positive PTTL, else nil for no expiry.

    kept_ttl(-1) #=> nil
"""
def kept_ttl(ttl)
  if ttl > 0
    ttl
  end
end

@doc """
rewrite_commands: the SET of the upgraded record (keeping the TTL) and the DEL of the old key.

    rewrite_commands("n:1", "{}", 900, "o:1") #=> [["SET", "n:1", "{}", "PX", 900], ["DEL", "o:1"]]
"""
def rewrite_commands(new_key, text, ttl, old_key)
  [set_command(new_key, text, kept_ttl(ttl)), ["DEL", old_key]]
end

@doc """
upgraded: an old entry's JSON checked, transformed and checked against the new schema.

    upgraded({from: {fields: {}}, to: {fields: {"v" => :int}}, transform: (r) -> assoc(r, "v", 2)}, "{}") #=> {"v" => 2}
"""
def upgraded(plan, text)
  check(plan[:to], plan[:transform](check(plan[:from], json_read(text))))
end

@doc """
read_upgrading: the record for an id under the new schema, upgrading an old entry on the way.

    raised(() -> read_upgrading(nil, {old: "a:", new: "a:"}, 1)) #=> :bad_option
"""
def read_upgrading(c, plan, id)
  plan_ok(plan)
  new_key = "#{plan[:new]}#{to_s(id)}"
  hit = fetch(c, plan[:to], new_key)
  if hit != nil
    hit
  else
    old_key = "#{plan[:old]}#{to_s(id)}"
    old = resp_pipeline(c, [["GET", old_key], ["PTTL", old_key]])
    if first(old).nil?
      nil
    else
      rec = upgraded(plan, first(old))
      resp_pipeline(
        c,
        rewrite_commands(new_key, json_stringify(rec), old[1], old_key)
      )
      rec
    end
  end
end

@doc """
batch_rewrite: one SCAN batch of old keys rewritten under the new prefix; how many moved.

    batch_rewrite(nil, {}, []) #=> 0
"""
def batch_rewrite(c, plan, keys)
  reads = if is_empty(keys)
    []
  else
    resp_pipeline(c, append(*map((k) -> [["GET", k], ["PTTL", k]], keys)))
  end
  rows = filter(
    (r) -> r[1] != nil,
    map((i) -> [keys[i], reads[2 * i], reads[2 * i + 1]], range(size(keys)))
  )
  if not is_empty(rows)
    resp_pipeline(
      c,
      append(
        *map(
          fn(r)
            rewrite_commands(
              "#{plan[:new]}#{drop_chars(first(r), length(plan[:old]))}",
              json_stringify(upgraded(plan, r[1])),
              r[2],
              first(r)
            )
          end,
          rows
        )
      )
    )
  end
  size(rows)
end

@doc """
upgrade_eager: rewrite every old entry to the new schema in SCAN batches, keeping each TTL; how many moved.

    raised(() -> upgrade_eager(nil, {old: "a:", new: "a:"}, 10)) #=> :bad_option
"""
def upgrade_eager(c, plan, batch)
  plan_ok(plan)
  moved = [0]
  scan_each(
    c,
    "#{plan[:old]}*",
    batch,
    (keys) -> set!(moved, [first(moved) + batch_rewrite(c, plan, keys)])
  )
  first(moved)
end

test "settings default the port and the timeout and turn TLS on"
  s = settings({host: "cache"})
  assert s[:port] == 6379
  assert s[:tls] == true
  assert s[:timeout_ms] == 5000
  assert settings({host: "127.0.0.1", tls: false})[:tls] == false
end

test "settings refuse a literal password, a bad host and a bad tls"
  assert raised(() -> settings({host: "h", password: "x"})) == :bad_option
  assert raised(() -> settings({host: ""})) == :bad_option
  assert raised(() -> settings({host: "h", tls: "no"})) == :bad_option
  assert raised(() -> settings({host: "h", password_file: 3})) == :bad_option
end

test "a SET carries PX only with a TTL, and a bad TTL is refused"
  assert set_command("k", "v", nil) == %w[SET k v]
  assert set_command("k", "v", 10) == ["SET", "k", "v", "PX", 10]
  assert raised(() -> set_command("k", "v", 0)) == :bad_option
  assert raised(() -> set_command("k", "v", "5m")) == :bad_option
end

test "a versioned key moves when the version hash moves"
  assert versioned_key("orders", "a1", :order, 7) == "orders:va1:order:7"
  assert versioned_key("orders", "a1", :order, 7) !=
    versioned_key("orders", "b2", :order, 7)
end

test "check passes a matching record and refuses a missing or mistyped field"
  schema = {fields: {"id" => :int, "state" => :text}}
  assert check(schema, {"id" => 1, "state" => "new"}) ==
    {"id" => 1, "state" => "new"}
  assert raised(
    () -> check(schema, {"id" => 1, "state" => "new", "extra" => true})
  ) == :bad_value
  assert check(
    assoc(schema, :strict, false),
    {"id" => 1, "state" => "new", "extra" => true}
  ) == {"id" => 1, "state" => "new", "extra" => true}
  assert raised(() -> check(schema, {"id" => 1})) == :bad_value
  assert raised(() -> check(schema, {"id" => "1", "state" => "x"})) ==
    :bad_value
  assert raised(() -> check(schema, "text")) == :bad_value
  assert raised(() -> check({fields: {"a" => :blob}}, {"a" => 1})) ==
    :bad_option
end

test "a rewrite keeps a positive TTL and drops none"
  assert rewrite_commands("n", "t", 900, "o") ==
    [["SET", "n", "t", "PX", 900], %w[DEL o]]
  assert rewrite_commands("n", "t", -1, "o") == [%w[SET n t], %w[DEL o]]
end

test "an upgrade plan needs two different prefixes"
  assert raised(() -> plan_ok({old: "a:", new: "a:"})) == :bad_option
  assert raised(() -> plan_ok({old: "a:"})) == :bad_option
end

test "upgraded checks the old record, transforms it and checks the new one"
  plan = {
    from: {fields: {"total" => :int}},
    to: {fields: {"total" => :int, "currency" => :text}},
    old: "o:",
    new: "n:",
    transform: (r) -> assoc(r, "currency", "BRL")
  }
  assert upgraded(plan, "{\"total\":3}") == {"total" => 3, "currency" => "BRL"}
  assert raised(() -> upgraded(plan, "{\"total\":\"3\"}")) == :bad_value
  bad = assoc(plan, :transform, (r) -> r)
  assert raised(() -> upgraded(bad, "{\"total\":3}")) == :bad_value
end
