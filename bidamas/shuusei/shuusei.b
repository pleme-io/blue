@moduledoc """
shuusei (修正) — amending declared data: put a value at a path, delete it, merge into it, upsert a list element, and amend a keyed set of objects by judged patch entries.

Everything is a pure function from data to data; the input is never changed.
A path is deeta's dotted text, `spec.template.spec.containers.0.image`, where
an integer segment indexes a list. The Kubernetes layer is one keying function,
`object_key`, so the same calls amend Flux values or Terraform JSON.

`amend` takes patch entries declared with `kousei`. Each is checked, can be
configured off or tuned, and is refused alone: a bad op, a target that is not
in the set, a second patch to a path another already took. The patches that
stand are applied in order; a refused one changes nothing.

    deep_merge(1, 2) #=> 2
"""

use("deeta", [:json_at])

use(
  "kousei",
  [
    :entry,
    :field,
    :judge,
    :off,
    :one_of,
    :overlay,
    :refuse,
    :required,
    :text,
    :tune,
    :value_of
  ]
)

use("kyohi", [:kinds])

use("retsu", [:first, :rest, :size])

def segments(path)
  split(path, ".")
end

@doc """
index_of_segment: A list index segment, or nil when the segment names a map key.
"""
def index_of_segment(k)
  to_int(k)
end

def replace_at(xs, i, v)
  map(
    fn(j)
      if j == i
        v
      else
        xs[j]
      end
    end,
    range(0, size(xs))
  )
end

def without_index(xs, i)
  map((j) -> xs[j], filter((j) -> j != i, range(0, size(xs))))
end

def in_range?(xs, i)
  i >= 0 and i < size(xs)
end

def put_keys(v, keys, value)
  if null?(keys)
    value
  else
    k = first(keys)
    i = index_of_segment(k)
    if list?(v) and i != nil
      if in_range?(v, i)
        replace_at(v, i, put_keys(v[i], rest(keys), value))
      else
        raise(:path, "list index #{k} is out of range")
      end
    else
      base = if map?(v)
        v
      else
        {}
      end
      assoc(base, k, put_keys(get(base, k), rest(keys), value))
    end
  end
end

@doc """
put: `doc` with `value` at `path`; absent map keys on the way are created.
"""
def put(doc, path, value)
  put_keys(doc, segments(path), value)
end

def drop_keys(v, keys)
  if null?(keys)
    v
  elsif size(keys) == 1
    k = first(keys)
    i = index_of_segment(k)
    if list?(v) and i != nil
      if in_range?(v, i)
        without_index(v, i)
      else
        v
      end
    elsif map?(v)
      dissoc(v, k)
    else
      v
    end
  else
    below = path_below(v, first(keys))
    if below.nil?
      v
    else
      put_keys(v, [first(keys)], drop_keys(below, rest(keys)))
    end
  end
end

def path_below(v, k)
  json_at(v, k)
end

@doc """
delete: `doc` without the value at `path`; absent already is no change.
"""
def delete(doc, path)
  drop_keys(doc, segments(path))
end

@doc """
deep_merge: Maps merge key by key and everything else is replaced by `b`.

    deep_merge(1, 2) #=> 2
"""
def deep_merge(a, b)
  if map?(a) and map?(b)
    reduce(
      (acc, p) -> assoc(acc, p[0], deep_merge(get(acc, p[0]), p[1])),
      a,
      map_entries(b)
    )
  else
    b
  end
end

@doc """
merge: `patch` merged into the map at `path`, keeping the keys it does not name.
"""
def merge(doc, path, patch)
  put(doc, path, deep_merge(json_at(doc, path), patch))
end

def position_of(xs, key, item)
  hits = filter((j) -> get(xs[j], key) == get(item, key), range(0, size(xs)))
  if size(hits) == 0
    nil
  else
    first(hits)
  end
end

@doc """
upsert: The list at `path` with `item` in it: it replaces the element whose `key` field matches, or is appended. Doing it twice is doing it once.
"""
def upsert(doc, path, key, item)
  current = json_at(doc, path)
  xs = if current.nil?
    []
  else
    current
  end
  if not list?(xs)
    raise(:path, "#{path} is not a list")
  else
    at = position_of(xs, key, item)
    if at.nil?
      put(doc, path, append(xs, [item]))
    else
      put(doc, path, replace_at(xs, at, item))
    end
  end
end

# --- keyed sets of objects --------------------------------------------------

@doc """
object_key: The identity of a Kubernetes object: [kind, namespace, name].

    object_key(web) #=> ["Deployment", "shop", "web"]
"""
def object_key(obj)
  ns = json_at(obj, "metadata.namespace")
  [
    json_at(obj, "kind"),
    if ns.nil?
      ""
    else
      ns
    end,
    json_at(obj, "metadata.name")
  ]
end

def anything()
  (_v) -> nil
end

def patch_table()
  [
    required(field(:kind, text)),
    required(field(:name, text)),
    field(:namespace, text),
    required(field(:op, one_of(["set", "delete", "merge", "upsert"]))),
    required(field(:path, text)),
    field(:value, anything),
    field(:key, text)
  ]
end

def patch_schema()
  {patch: patch_table}
end

def target_of(v)
  ns = v[:namespace]
  [
    v[:kind],
    if ns.nil?
      ""
    else
      ns
    end,
    v[:name]
  ]
end

@doc """
shape_whys: What the field table cannot say: the ops that need a value or a key.
"""
def shape_whys(v)
  op = v[:op]
  if (op == "set" or op == "merge" or op == "upsert") and v[:value].nil?
    ["#{op} needs a value"]
  elsif op == "upsert" and v[:key].nil?
    ["upsert needs a key"]
  elsif op == "merge" and not map?(v[:value])
    ["merge needs a map value"]
  else
    []
  end
end

def apply_op(obj, v)
  op = v[:op]
  if op == "set"
    put(obj, v[:path], v[:value])
  elsif op == "delete"
    delete(obj, v[:path])
  elsif op == "merge"
    merge(obj, v[:path], v[:value])
  else
    upsert(obj, v[:path], v[:key], v[:value])
  end
end

def claim_of(v)
  [target_of(v), v[:path]]
end

def position_of_object(objects, keyer, tkey)
  hits = filter((j) -> keyer(objects[j]) == tkey, range(0, size(objects)))
  if size(hits) == 0
    nil
  else
    first(hits)
  end
end

def one_step(keyer, state, e)
  v = value_of(e)
  objects = state[:objects]
  at = position_of_object(objects, keyer, target_of(v))
  shape = shape_whys(v)
  claimed = state[:claims]
  if size(shape) > 0
    refused_step(state, refuse(:invalid, e, first(shape)))
  elsif at.nil?
    refused_step(
      state,
      refuse(:unknown_target, e, "no object #{target_of(v)} in the set")
    )
  elsif contains_claim?(claimed, claim_of(v))
    refused_step(
      state,
      refuse(
        :collision,
        e,
        "#{v[:path]} on #{target_of(v)} is already amended; the first stands"
      )
    )
  else
    done = begin
      apply_op(objects[at], v)
    rescue :path as bad
      bad
    end
    if map?(done) or list?(done)
      {
        objects: replace_at(objects, at, done),
        claims: append(claimed, [claim_of(v)]),
        refusals: state[:refusals],
        applied: state[:applied] + 1
      }
    else
      refused_step(state, refuse(:path, e, "#{done}"))
    end
  end
end

def refused_step(state, r)
  assoc(state, :refusals, append(state[:refusals], [r]))
end

def contains_claim?(claims, claim)
  size(filter((c) -> c == claim, claims)) > 0
end

@doc """
amend: Patch entries are `entry(:patch, name, {kind:, name:, namespace:, op:, path:, value:, key:})` from kousei, with its `off` and `tune` laid over them.
Returns `objects` (patched, same order), `applied`, `off` and `refusals`.

    amend([web, svc], object_key, []) #=> {objects: [web, svc], applied: 0, off: [], refusals: []}
"""
def amend(objects, keyer, entries)
  judged = judge(patch_schema, entries)
  start = {objects:, claims: [], refusals: [], applied: 0}
  end_state = reduce(
    (state, e) -> one_step(keyer, state, e),
    start,
    judged[:accepted]
  )
  {
    objects: end_state[:objects],
    applied: end_state[:applied],
    off: judged[:off],
    refusals: append(judged[:refusals], end_state[:refusals])
  }
end

# --- reading a change --------------------------------------------------------

def index_by(keyer, objects)
  reduce((acc, o) -> assoc(acc, to_s(keyer(o)), o), {}, objects)
end

@doc """
changed: Which objects were added, removed or changed, as [key, change] pairs sorted by key.
"""
def changed(before, after, keyer)
  b = index_by(keyer, before)
  a = index_by(keyer, after)
  names = map((p) -> p[0], map_entries(overlay(b, a)))
  filter(
    (r) -> r[1] != nil,
    map(
      fn(k)
        if get(b, k).nil?
          [k, :added]
        elsif get(a, k).nil?
          [k, :removed]
        elsif get(b, k) == get(a, k)
          [k, nil]
        else
          [k, :changed]
        end
      end,
      names
    )
  )
end

@doc """
read_objects: A `kind: List` document, or one object, read into the list of objects.

    read_objects(json_stringify(web)) #=> [web]
"""
def read_objects(text)
  doc = json_read(text)
  if json_at(doc, "kind") == "List"
    json_at(doc, "items")
  else
    [doc]
  end
end

@doc """
show_objects: The objects as one `kind: List` document, the committed shape.
"""
def show_objects(objects)
  json_stringify({"apiVersion" => "v1", "kind" => "List", "items" => objects})
end

def web()
  {
    "apiVersion" => "apps/v1",
    "kind" => "Deployment",
    "metadata" => {
      "name" => "web",
      "namespace" => "shop",
      "labels" => {"app" => "web"}
    },
    "spec" => {
      "replicas" => 1,
      "template" => {
        "spec" => {
          "containers" => [
            {"name" => "app", "image" => "web:1"},
            {"name" => "side", "image" => "side:1"}
          ]
        }
      }
    }
  }
end

def svc()
  {
    "apiVersion" => "v1",
    "kind" => "Service",
    "metadata" => {"name" => "web", "namespace" => "shop"},
    "spec" => {"ports" => [{"name" => "http", "port" => 80}]}
  }
end

def on_web(name, fields)
  entry(
    :patch,
    name,
    overlay({kind: "Deployment", name: "web", namespace: "shop"}, fields)
  )
end

test "put sets a value, creates missing map keys, indexes lists, and never touches its input"
  d = web
  assert json_at(put(d, "spec.replicas", 3), "spec.replicas") == 3
  assert json_at(d, "spec.replicas") == 1
  assert json_at(
    put(d, "metadata.annotations.owner", "shop"),
    "metadata.annotations.owner"
  ) == "shop"
  p = put(d, "spec.template.spec.containers.1.image", "side:2")
  assert json_at(p, "spec.template.spec.containers.1.image") == "side:2"
  assert json_at(p, "spec.template.spec.containers.0.image") == "web:1"
  assert put(d, "spec.replicas", 1) == d
  bad = begin
    put(d, "spec.template.spec.containers.9.image", "x")
  rescue :path as e
    e
  end
  assert bad.message == "list index 9 is out of range"
  edge = begin
    put(d, "spec.template.spec.containers.2.image", "x")
  rescue :path as e
    e
  end
  assert edge.message == "list index 2 is out of range"
  assert json_at(
    put(d, "spec.template.spec.containers.1.image", "x"),
    "spec.template.spec.containers.1.image"
  ) == "x"
end

test "delete removes a map key or a list element, and deleting what is absent is no change"
  d = web
  assert json_at(delete(d, "metadata.labels.app"), "metadata.labels") == {}
  assert json_at(
    delete(d, "spec.template.spec.containers.0"),
    "spec.template.spec.containers"
  ) == [{"name" => "side", "image" => "side:1"}]
  assert delete(d, "spec.nothing.here") == d
  assert delete(d, "spec.template.spec.containers.7") == d
  assert delete(delete(d, "spec.replicas"), "spec.replicas") ==
    delete(d, "spec.replicas")
  assert json_at(d, "spec.replicas") == 1
end

test "merge lays a map over a map and keeps the keys it does not name"
  d = web
  m = merge(d, "metadata.labels", {"tier" => "front"})
  assert json_at(m, "metadata.labels") == {"app" => "web", "tier" => "front"}
  deep = merge(d, "spec", {"template" => {"spec" => {"hostNetwork" => true}}})
  assert json_at(deep, "spec.template.spec.hostNetwork") == true
  assert json_at(deep, "spec.template.spec.containers.0.name") == "app"
  assert json_at(deep, "spec.replicas") == 1
  assert json_at(merge(d, "spec.replicas", {"a" => 1}), "spec.replicas") ==
    {"a" => 1}
end

test "upsert replaces the element with the same key or appends, and doing it twice is doing it once"
  d = web
  item = {"name" => "app", "image" => "web:2"}
  u = upsert(d, "spec.template.spec.containers", "name", item)
  assert size(json_at(u, "spec.template.spec.containers")) == 2
  assert json_at(u, "spec.template.spec.containers.0.image") == "web:2"
  assert upsert(u, "spec.template.spec.containers", "name", item) == u
  added = upsert(
    d,
    "spec.template.spec.containers",
    "name",
    {"name" => "log", "image" => "log:1"}
  )
  assert size(json_at(added, "spec.template.spec.containers")) == 3
  assert json_at(added, "spec.template.spec.containers.2.name") == "log"
  made = upsert(d, "spec.volumes", "name", {"name" => "v"})
  assert json_at(made, "spec.volumes.0.name") == "v"
  worse = begin
    upsert(d, "spec.replicas", "name", item)
  rescue :path as e
    e
  end
  assert worse.message == "spec.replicas is not a list"
end

test "object_key is kind, namespace and name, with an empty namespace when there is none"
  assert object_key(web) == ["Deployment", "shop", "web"]
  assert object_key(
    {"kind" => "Namespace", "metadata" => {"name" => "shop"}}
  ) == ["Namespace", "", "shop"]
end

test "amend applies the patches that stand, in order, and leaves every other object alone"
  r = amend(
    [web, svc],
    object_key,
    [
      on_web("scale", {op: "set", path: "spec.replicas", value: 3}),
      on_web(
        "tier",
        {op: "merge", path: "metadata.labels", value: {"tier" => "front"}}
      ),
      on_web(
        "image",
        {
          op: "upsert",
          path: "spec.template.spec.containers",
          key: "name",
          value: {"name" => "app", "image" => "web:2"}
        }
      )
    ]
  )
  assert r[:refusals] == []
  assert r[:applied] == 3
  w = r[:objects][0]
  assert json_at(w, "spec.replicas") == 3
  assert json_at(w, "metadata.labels.tier") == "front"
  assert json_at(w, "spec.template.spec.containers.0.image") == "web:2"
  assert r[:objects][1] == svc
  assert amend([web, svc], object_key, []) ==
    {objects: [web, svc], applied: 0, off: [], refusals: []}
end

test "a bad patch is refused alone by name and its siblings still apply"
  r = amend(
    [web, svc],
    object_key,
    [
      on_web("scale", {op: "set", path: "spec.replicas", value: 3}),
      on_web("explode", {op: "explode", path: "spec.replicas", value: 9}),
      on_web("novalue", {op: "set", path: "spec.paused"}),
      on_web(
        "nokey",
        {
          op: "upsert",
          path: "spec.template.spec.containers",
          value: {"name" => "x"}
        }
      ),
      on_web("flat", {op: "merge", path: "metadata.labels", value: 4}),
      entry(
        :patch,
        "ghost",
        {
          kind: "Deployment",
          name: "nope",
          namespace: "shop",
          op: "set",
          path: "spec.replicas",
          value: 1
        }
      ),
      on_web(
        "oob",
        {op: "set", path: "spec.template.spec.containers.9.image", value: "x"}
      )
    ]
  )
  assert r[:applied] == 1
  assert json_at(r[:objects][0], "spec.replicas") == 3
  assert kinds(r[:refusals]) ==
    [:invalid, :invalid, :invalid, :invalid, :unknown_target, :path]
  assert json_at(r[:objects][0], "spec.paused").nil?
end

test "two patches to one path collide and the first stands"
  r = amend(
    [web],
    object_key,
    [
      on_web("first", {op: "set", path: "spec.replicas", value: 2}),
      on_web("second", {op: "set", path: "spec.replicas", value: 9}),
      on_web("other", {op: "set", path: "spec.paused", value: true})
    ]
  )
  assert json_at(r[:objects][0], "spec.replicas") == 2
  assert json_at(r[:objects][0], "spec.paused") == true
  assert kinds(r[:refusals]) == [:collision]
  assert r[:applied] == 2
end

test "a patch configured off is kept and does nothing, and a tune changes its fields"
  entries = [on_web("scale", {op: "set", path: "spec.replicas", value: 3})]
  off_r = amend([web], object_key, append(entries, [off(:patch, "scale")]))
  assert size(off_r[:off]) == 1
  assert json_at(off_r[:objects][0], "spec.replicas") == 1
  tuned = amend(
    [web],
    object_key,
    append(entries, [tune(:patch, "scale", {value: 5})])
  )
  assert json_at(tuned[:objects][0], "spec.replicas") == 5
  retuned = amend(
    [web],
    object_key,
    append(entries, [tune(:patch, "scale", {op: "nope"})])
  )
  assert size(retuned[:refusals]) == 1
  assert json_at(retuned[:objects][0], "spec.replicas") == 3
end

test "changed names the objects that were added, removed or changed, and nothing else"
  before = [web, svc]
  after = [
    put(web, "spec.replicas", 2),
    {"kind" => "ConfigMap", "metadata" => {"name" => "c"}}
  ]
  c = changed(before, after, object_key)
  assert contains_pair?(c, ["[\"Deployment\", \"shop\", \"web\"]", :changed])
  assert contains_pair?(c, ["[\"Service\", \"shop\", \"web\"]", :removed])
  assert contains_pair?(c, ["[\"ConfigMap\", \"\", \"c\"]", :added])
  assert size(c) == 3
  assert changed(before, before, object_key) == []
end

def contains_pair?(xs, pair)
  size(filter((x) -> x == pair, xs)) > 0
end

test "a List document reads into objects and shows back as the same List"
  text = show_objects([web, svc])
  back = read_objects(text)
  assert back == [web, svc]
  assert read_objects(json_stringify(web)) == [web]
  assert json_at(json_read(text), "kind") == "List"
end

test "deep_merge merges maps key by key and lets b win everywhere else"
  assert deep_merge({"a" => 1, "b" => 2}, {"b" => 3, "c" => 4}) ==
    {"a" => 1, "b" => 3, "c" => 4}
  assert deep_merge(
    {"a" => {"x" => 1, "y" => 2}},
    {"a" => {"y" => 9, "z" => 3}}
  ) == {"a" => {"x" => 1, "y" => 9, "z" => 3}}
  assert deep_merge({"a" => {"x" => 1}}, {"a" => 5}) == {"a" => 5}
  assert deep_merge({"a" => 5}, {"a" => {"x" => 1}}) == {"a" => {"x" => 1}}
  assert deep_merge({"l" => [1, 2]}, {"l" => [3]}) == {"l" => [3]}
end

test "deep_merge with an empty side returns the other, and a scalar b replaces a map"
  assert deep_merge({}, {"a" => 1}) == {"a" => 1}
  assert deep_merge({"a" => 1}, {}) == {"a" => 1}
  assert deep_merge({}, {}) == {}
  assert deep_merge({"a" => 1}, 7) == 7
  assert deep_merge(7, {"a" => 1}) == {"a" => 1}
  assert deep_merge(1, 2) == 2
end

test "deep_merge leaves both inputs as they were"
  a = {"a" => {"x" => 1}}
  b = {"a" => {"y" => 2}}
  m = deep_merge(a, b)
  assert a == {"a" => {"x" => 1}}
  assert b == {"a" => {"y" => 2}}
  assert m == {"a" => {"x" => 1, "y" => 2}}
end
