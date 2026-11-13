@moduledoc """
kyasshu (キャッシュ) — cache: the normalized entity store of the frontend data runtime.

One key function (`Type:id`, the key hanabi's entity cache uses) is derived
from a GraphQL schema. `normalize` splits a response into entities, `merge`
keeps one copy of each, and `read` answers the masked fields of one
fragment. The ttl, stale, persist and evict rules of each fragment are
kousei entries. An optimistic write is pending until `settle` confirms it or
rolls it back, and `request` asks a server by persisted hash only.

    key(["User", 7]) #=> "User:7"
"""

use("deeta", [:get_or])
use("eigyou/tsuushin")
use("fairu")
use("gamen")
use("isshou/raifusaikuru")
use("kousei")
use("kyohi", [:refusal])
use("moji", [:checked])
use("ran")
use("retsu", %i[find_first first is_empty push size])
use("tesuto", [:raises?])
use("toriyose/danpen")

@doc """
key_format names the version of the key table, so a reader can refuse a table another layout wrote.

    key_format #=> "kyasshu-keys/1"
"""
def key_format()
  "kyasshu-keys/1"
end

@doc """
separator joins the parts of one cache key, the colon hanabi's entity cache uses.

    separator #=> ":"
"""
def separator()
  ":"
end

@doc """
root_key stamps the root fields of a response, which belong to no entity.

    root_key #=> "ROOT"
"""
def root_key()
  "ROOT"
end

@doc """
key: one canonical cache key built from ordered parts.

    key(["User", 7]) #=> "User:7"
"""
def key(parts)
  if not list?(parts) or is_empty(parts)
    raise(:bad_option, "key: parts is a list of at least one part")
  end
  if any?((p) -> p.nil? or to_s(p) == "", parts)
    raise(:bad_option, "key: a part is nil or empty")
  end
  blue::join(map(to_s, parts), separator)
end

@doc """
table? tells a ready key table apart from a schema still to read.

    table?(schema(sdl)) #=> true
    table?(sdl) #=> false
"""
def table?(x)
  map?(x) and x[:format] == key_format
end

@doc """
entity_type? tells whether a schema type is cached as its own entity: an object, not introspection, with an id.

    entity_type?({kind: :object, name: "User", fields: [{name: "id"}]}) #=> true
    entity_type?({kind: :object, name: "Note", fields: [{name: "text"}]}) #=> false
"""
def entity_type?(d)
  d[:kind] == :object and
    not starts_with?(d[:name], "__") and
    any?((f) -> f[:name] == "id", d[:fields] or [])
end

@doc """
table_of builds the key table from a parsed schema: every entity type keyed by its id.

    table_of(toriyose::danpen::schema_of(sdl))[:cached_types] #=> ["Comment", "Post", "User"]
"""
def table_of(s)
  types = sort_keyed(
    (t) -> t,
    map(
      (d) -> d[:name],
      filter(entity_type?, map(second, map_entries(s[:types])))
    )
  )
  {
    format: key_format,
    separator:,
    cached_types: types,
    key_fields: reduce((m, t) -> assoc(m, t, ["id"]), {}, types)
  }
end

@doc """
schema: the entity key table a GraphQL schema implies.

    schema(sdl)[:key_fields]["User"] #=> ["id"]
"""
def schema(subject)
  table_of(toriyose::danpen::schema_of(subject))
end

@doc """
context holds what a walk needs: the key table, and the parsed schema when one was given.

    context(schema(sdl))[:types] #=> nil
    context(sdl)[:table] == schema(sdl) #=> true
"""
def context(schema)
  if table?(schema)
    {table: schema, types: nil}
  else
    s = toriyose::danpen::schema_of(schema)
    {table: table_of(s), types: s}
  end
end

@doc """
ref? tells a reference to an entity apart from a value held in place.

    ref?({"__ref" => "User:7"}) #=> true
    ref?({"__ref" => "User:7", "id" => "7"}) #=> false
"""
def ref?(x)
  map?(x) and x["__ref"] != nil and size(map_entries(x)) == 1
end

@doc """
combined lays a newer value over an older one, field by field, and keeps the fields only the older one has.

    combined({"a" => 1}, {"b" => 2}) #=> {"a" => 1, "b" => 2}
    combined({"a" => 1}, {"a" => 3}) #=> {"a" => 3}
"""
def combined(x, y)
  if map?(x) and map?(y) and not ref?(x) and not ref?(y)
    reduce(
      (acc, e) -> assoc(acc, first(e), combined(get(acc, first(e)), second(e))),
      x,
      map_entries(y)
    )
  else
    y
  end
end

@doc """
entities_merged joins two entity tables so each key keeps one combined copy.

    entities_merged({"User:1" => {"id" => "1"}}, {"User:1" => {"name" => "Ann"}}) #=> {"User:1" => {"id" => "1", "name" => "Ann"}}
"""
def entities_merged(a, b)
  reduce(
    (acc, e) -> assoc(acc, first(e), combined(get(acc, first(e)), second(e))),
    a or {},
    map_entries(b or {})
  )
end

@doc """
field_type finds the type a field of a parent type holds, so a walk can key a nested value that carries no typename.

    field_type(context(sdl), "Post", "author") #=> "User"
    field_type(context(schema(sdl)), "Post", "author") #=> nil
"""
def field_type(ctx, parent, name)
  s = ctx[:types]
  f = if s.nil? or parent.nil?
    nil
  else
    toriyose::danpen::field_def(s, parent, name, false)
  end
  if f.nil?
    nil
  else
    toriyose::danpen::base_name(f[:type])
  end
end

@doc """
entity_key gives the cache key of a record of a cached type, or nil when the record lacks a key field.

    entity_key(context(sdl), "User", {"id" => "u7"}) #=> "User:u7"
    entity_key(context(sdl), "Note", {"text" => "t"}) #=> nil
"""
def entity_key(ctx, t, rec)
  fields = get(ctx[:table][:key_fields], t)
  if t.nil? or fields.nil?
    nil
  else
    values = map((f) -> get(rec, f), fields)
    if any?((v) -> v.nil?, values)
      nil
    else
      key(cons(t, values))
    end
  end
end

@doc """
walk splits one value into what stays in place, with references, and the entities it found.

    first(walk(ada, "User", context(sdl))) #=> {"__ref" => "User:u7"}
"""
def walk(value, type, ctx)
  if value.nil?
    [nil, {}]
  elsif list?(value)
    reduce(
      fn(acc, x)
        w = walk(x, type, ctx)
        [push(first(acc), first(w)), entities_merged(second(acc), second(w))]
      end,
      [[], {}],
      value
    )
  elsif map?(value)
    t = value["__typename"] or type
    r = reduce(
      fn(acc, e)
        w = walk(second(e), field_type(ctx, t, first(e)), ctx)
        [
          assoc(first(acc), first(e), first(w)),
          entities_merged(second(acc), second(w))
        ]
      end,
      [{}, {}],
      map_entries(value)
    )
    k = entity_key(ctx, t, first(r))
    if k.nil?
      r
    else
      [
        {"__ref" => k},
        entities_merged(second(r), {k => assoc(first(r), "__typename", t)})
      ]
    end
  else
    [value, {}]
  end
end

@doc """
payload takes the data of a GraphQL response, or the value itself when it holds no data field.

    payload({"data" => {"a" => 1}}) #=> {"a" => 1}
    payload({"a" => 1}) #=> {"a" => 1}
"""
def payload(response)
  if map?(response) and response["data"] != nil
    response["data"]
  else
    response
  end
end

@doc """
normalize: split a response into entities keyed by Type:id.

    normalize({"data" => {}}, sdl) #=> {root: {}, entities: {}, stamps: {}, writes: []}
"""
def normalize(response, schema, opts?)
  o = checked(opts, [:now])
  ctx = context(schema)
  data = payload(response)
  if not map?(data)
    raise(:bad_option, "normalize: a response is a record of root fields")
  end
  root_type = if ctx[:types].nil?
    nil
  else
    ctx[:types][:roots][:query]
  end
  r = walk(data, root_type, ctx)
  now = o[:now]
  stamps = if now.nil?
    {}
  else
    reduce(
      (m, k) -> assoc(m, k, now),
      {root_key => now},
      map(first, map_entries(second(r)))
    )
  end
  {root: first(r), entities: second(r), stamps:, writes: []}
end

@doc """
merge: combine two stores keeping one copy per entity.

    merge(nil, blank) #=> blank
    merge(blank, nil) #=> blank
"""
def merge(a, b)
  if a.nil?
    b
  elsif b.nil?
    a
  else
    {
      root: combined(a[:root], b[:root]),
      entities: entities_merged(a[:entities], b[:entities]),
      stamps: {**a[:stamps], **b[:stamps]},
      writes: append(a[:writes], b[:writes])
    }
  end
end

@doc """
overlay lays every pending optimistic write over a store, so a read sees them.

    overlay(blank) #=> blank
"""
def overlay(store)
  reduce(
    (acc, w) -> merge(acc, w[:patch]),
    assoc(store, :writes, []),
    store[:writes]
  )
end

@doc """
hooks tells danpen's select how to follow references through a store and to miss on an absent field.

    h = hooks(blank)
    f = h[:start]
    f({"__ref" => "User:7"}) #=> {"__ref" => "User:7"}
"""
def hooks(v)
  ents = v[:entities]
  {
    resolve: fn(x)
      if ref?(x)
        e = get(ents, x["__ref"])
        if e.nil?
          raise(:miss, "#{x["__ref"]} is not in the store")
        end
        assoc(e, "__ref", x["__ref"])
      else
        x
      end
    end,
    absent: (_acc, field) -> raise(:miss, "#{field} is not in the store"),
    start: fn(x)
      if x["__ref"].nil?
        {}
      else
        {"__ref" => x["__ref"]}
      end
    end
  }
end

@doc """
selections_of takes the selections of a fragment or operation that a read answers.

    size(selections_of(user_card)) #=> 2
"""
def selections_of(f)
  if not map?(f) or f[:selections].nil?
    raise(:bad_option, "fragment: a danpen fragment or operation")
  end
  f[:selections]
end

@doc """
start_value picks where a read starts: the root, or the entity an `at:` names.

    start_value(blank, "User:7") #=> {"__ref" => "User:7"}
    start_value(blank, nil) #=> {}
"""
def start_value(v, at)
  if at.nil?
    v[:root]
  elsif string?(at)
    {"__ref" => at}
  elsif map?(at) and at["__ref"] != nil
    {"__ref" => at["__ref"]}
  else
    raise(:bad_option, "at: an entity key, or a value read with one")
  end
end

@doc """
null_at? tells a read given `at: nil` apart from a read given no `at:`.

    null_at?({at: nil}) #=> true
    null_at?({}) #=> false
"""
def null_at?(o)
  any?((e) -> first(e) == :at and second(e).nil?, map_entries(o))
end

@doc """
fetched reads the fields of a fragment from a store, or nil when the store misses one.

    fetched(normalize(response, sdl), {fragment: user_card, at: "User:u7"})["name"] #=> "Ada"
    fetched(normalize(response, sdl), {fragment: user_card, at: "User:nobody"}) #=> nil
"""
def fetched(v, o)
  if null_at?(o)
    nil
  else
    toriyose::danpen::select_into(
      start_value(v, o[:at]),
      selections_of(o[:fragment]),
      hooks(v)
    )
  end
rescue e
  if e.kind == :miss
    nil
  else
    raise(e)
  end
end

@doc """
refs_in lists every entity a read value references, so its age can be checked.

    refs_in({"a" => {"__ref" => "User:1"}, "b" => [{"__ref" => "Post:2"}]}) #=> ["User:1", "Post:2"]
"""
def refs_in(x)
  if map?(x)
    own = if x["__ref"].nil?
      []
    else
      [x["__ref"]]
    end
    append(own, retsu::flat_map(map(second, map_entries(x)), refs_in))
  elsif list?(x) and x != nil
    retsu::flat_map(x, refs_in)
  else
    []
  end
end

@doc """
rules_for finds the policy rules of the fragment a read names.

    rules_for({fragment: user_card}) #=> {}
"""
def rules_for(o)
  p = o[:policy]
  if p.nil?
    {}
  else
    get_or(p[:fragments], o[:fragment][:name], {})
  end
end

@doc """
aged? tells whether any entity a read touched is older than its fragment's ttl.

    aged?(blank, {}, {fragment: user_card}) #=> false
"""
def aged?(v, data, o)
  ttl = rules_for(o)[:ttl]
  if ttl.nil?
    false
  else
    now = o[:now]
    if now.nil?
      raise(:bad_option, "a fragment with a ttl is read with now:")
    end
    keys = if o[:at].nil?
      cons(root_key, refs_in(data))
    else
      refs_in(data)
    end
    stamps = v[:stamps]
    any?(
      fn(k)
        t = get(stamps, k)
        t.nil? or now - t >= ttl
      end,
      distinct(keys)
    )
  end
end

@doc """
read_options lists the options a read and a staleness check accept.

    read_options #=> [:fragment, :at, :now, :policy]
"""
def read_options()
  %i[fragment at now policy]
end

@doc """
read: the masked fields of one fragment read from the store.

    read(normalize(response, sdl), {fragment: user_card, at: "User:u7"})["name"] #=> "Ada"
    read(nil, {fragment: user_card}) #=> nil
"""
def read(store, opts)
  o = checked(opts, read_options)
  if o[:fragment].nil?
    raise(:bad_option, "read: fragment: names what to read")
  end
  if store.nil?
    nil
  else
    v = overlay(store)
    data = fetched(v, o)
    if data.nil?
      nil
    elsif aged?(v, data, o) and rules_for(o)[:stale] != :revalidate
      nil
    else
      data
    end
  end
end

@doc """
stale?: whether a fragment read is older than its ttl.

    stale?(normalize(response, sdl), {fragment: user_card, at: "User:u7"}) #=> false
"""
def stale?(store, opts)
  o = checked(opts, read_options)
  if store.nil? or o[:fragment].nil?
    false
  else
    v = overlay(store)
    data = fetched(v, o)
    data != nil and aged?(v, data, o)
  end
end

@doc """
rule_kinds holds the kousei schema of each fragment rule: ttl, stale, persist and evict.

    size(map_entries(rule_kinds)) #=> 4
"""
def rule_kinds()
  {
    ttl: [
      kousei::required(kousei::field(:seconds, kousei::int_in(1, 31_536_000)))
    ],
    stale: [
      kousei::required(kousei::field(:mode, kousei::one_of([:revalidate])))
    ],
    persist: [
      kousei::required(kousei::field(:to, kousei::one_of([:indexeddb])))
    ],
    evict: [
      kousei::required(kousei::field(:after, kousei::int_in(0, 31_536_000)))
    ]
  }
end

@doc """
rule_value takes the one setting of a kousei rule entry.

    rule_value(kousei::entry(:ttl, "user_card", {seconds: 60})) #=> 60
"""
def rule_value(e)
  second(first(map_entries(kousei::value_of(e))))
end

@doc """
policy: per fragment ttl, stale, persist and evict rules from kousei entries.

    p = policy([user_card], [kousei::entry(:ttl, "user_card", {seconds: 60})])
    p[:fragments]["user_card"][:ttl] #=> 60
"""
def policy(fragments, entries)
  if not list?(fragments)
    raise(:bad_option, "policy: fragments is a list of danpen fragments")
  end
  j = kousei::judge(rule_kinds, entries)
  names = map((f) -> f[:name], fragments)
  known = filter((e) -> member?(kousei::name_of(e), names), j[:accepted])
  stray = filter((e) -> not member?(kousei::name_of(e), names), j[:accepted])
  base = reduce(
    fn(m, f)
      assoc(
        m,
        f[:name],
        {on: f[:on], ttl: nil, stale: nil, persist: nil, evict: nil}
      )
    end,
    {},
    fragments
  )
  table = reduce(
    fn(m, e)
      n = kousei::name_of(e)
      assoc(m, n, assoc(get(m, n), kousei::kind_of(e), rule_value(e)))
    end,
    base,
    known
  )
  {
    fragments: table,
    off: j[:off],
    refusals: append(
      j[:refusals],
      map(
        fn(e)
          refusal(
            :unknown_fragment,
            "#{kousei::kind_of(e)} #{kousei::name_of(e)}: no fragment of that name"
          )
        end,
        stray
      )
    )
  }
end

@doc """
types_with gives each entity type the smallest value one of its fragments sets for a rule.

    p = policy([user_card], [kousei::entry(:ttl, "user_card", {seconds: 60})])
    types_with(p, :ttl) #=> {"User" => 60}
    types_with(nil, :ttl) #=> {}
"""
def types_with(p, kind)
  if p.nil?
    {}
  else
    reduce(
      fn(m, r)
        v = get(r, kind)
        t = r[:on]
        if v.nil?
          m
        elsif get(m, t).nil? or v < get(m, t)
          assoc(m, t, v)
        else
          m
        end
      end,
      {},
      map(second, map_entries(p[:fragments]))
    )
  end
end

@doc """
kept keeps only the entities a test admits, with their stamps.

    kept(normalize(response, sdl), (_k, _e) -> false)[:entities] #=> {}
"""
def kept(store, keeps)
  pairs = filter(
    (e) -> keeps(first(e), second(e)),
    map_entries(store[:entities])
  )
  ents = reduce((m, e) -> assoc(m, first(e), second(e)), {}, pairs)
  stamps = filter(
    (e) -> first(e) == root_key or get(ents, first(e)) != nil,
    map_entries(store[:stamps])
  )
  {
    **store,
    entities: ents,
    stamps: reduce((m, e) -> assoc(m, first(e), second(e)), {}, stamps)
  }
end

@doc """
snapshot: the entities persisted fragments read, to keep across restarts.

    snapshot(normalize(response, sdl))[:entities] #=> {}
"""
def snapshot(store, opts?)
  o = checked(opts, [:policy])
  types = types_with(o[:policy], :persist)
  s = kept(store, (_k, e) -> get(types, e["__typename"]) != nil)
  {
    root: {},
    entities: s[:entities],
    stamps: dissoc(s[:stamps], root_key),
    writes: []
  }
end

@doc """
sweep: drop the entities older than their fragment evict limit.

    sweep(blank, {now: 1}) #=> blank
"""
def sweep(store, opts)
  o = checked(opts, %i[now policy])
  now = o[:now]
  if not number?(now)
    raise(:bad_option, "sweep: now: is the time to sweep at")
  end
  after = types_with(o[:policy], :evict)
  stamps = store[:stamps]
  kept(
    store,
    fn(k, e)
      limit = get(after, e["__typename"])
      t = get(stamps, k)
      limit.nil? or t != nil and now - t < limit
    end
  )
end

@doc """
declare a mutation and the entity types it touches.

    declare(:rename, {touches: ["User"]}) #=> {mutation: "rename", touches: ["User"], operation: nil}
"""
def declare(name, spec)
  s = checked(spec, %i[touches operation])
  touches = s[:touches]
  if not list?(touches) or
      is_empty(touches) or
      any?((t) -> not string?(t), touches)
    raise(
      :bad_option,
      "declare: touches: lists the entity types a mutation writes"
    )
  end
  {
    mutation: to_s(name),
    touches: sort_keyed((t) -> t, distinct(touches)),
    operation: s[:operation]
  }
end

@doc """
touched lists the entity types a patch writes.

    touched(renamed("u7", "x")) #=> ["User"]
"""
def touched(patch)
  sort_keyed(
    (t) -> t,
    distinct(
      map((e) -> second(e)["__typename"], map_entries(patch[:entities] or {}))
    )
  )
end

@doc """
write_machine is the lifecycle of one optimistic write: pending until confirmed or rolled back.

    isshou::raifusaikuru::phase(isshou::raifusaikuru::initial(write_machine)) #=> :pending
"""
def write_machine()
  isshou::raifusaikuru::lc_define(
    :optimistic_write,
    [
      isshou::raifusaikuru::states(%i[pending confirmed rolled_back]),
      isshou::raifusaikuru::start(:pending),
      isshou::raifusaikuru::terminals(%i[confirmed rolled_back]),
      isshou::raifusaikuru::event(:confirm, []),
      isshou::raifusaikuru::event(:roll_back, []),
      isshou::raifusaikuru::on(:pending, :confirm, :confirmed, []),
      isshou::raifusaikuru::on(:pending, :roll_back, :rolled_back, [])
    ]
  )
end

@doc """
blank is the empty store a first write starts from.

    blank #=> {root: {}, entities: {}, stamps: {}, writes: []}
"""
def blank()
  {root: {}, entities: {}, stamps: {}, writes: []}
end

@doc """
write: lay a pending optimistic write over the store.

    m = declare(:rename, {touches: ["User"]})
    s = write(nil, {id: "w1", mutation: m, patch: renamed("u7", "Ada L.")})
    read(s, {fragment: user_card, at: "User:u7"})["name"] #=> "Ada L."
"""
def write(store, change)
  c = checked(change, %i[id mutation patch])
  s = store or blank
  id = c[:id]
  m = c[:mutation]
  patch = c[:patch]
  if id.nil?
    raise(:bad_option, "write: id: names the pending write")
  elsif not map?(m) or m[:mutation].nil?
    raise(:bad_option, "write: mutation: is a declared mutation")
  elsif not map?(patch) or patch[:entities].nil?
    raise(:bad_option, "write: patch: is a normalized response")
  elsif find_first((w) -> w[:id] == id, s[:writes]) != nil
    raise(:conflict, "write: #{to_s(id)} is already pending")
  end
  assoc(
    s,
    :writes,
    push(
      s[:writes],
      {
        id:,
        mutation: m,
        patch: assoc(patch, :writes, []),
        state: isshou::raifusaikuru::initial(write_machine)
      }
    )
  )
end

@doc """
outcome_event turns a settle outcome into the event the write machine takes.

    outcome_event(:confirmed) #=> :confirm
    outcome_event(:rolled_back) #=> :roll_back
"""
def outcome_event(outcome)
  if outcome == :confirmed
    :confirm
  elsif outcome == :rolled_back
    :roll_back
  else
    raise(:bad_option, "settle: the outcome is :confirmed or :rolled_back")
  end
end

@doc """
settle: end an optimistic write as confirmed or rolled back.

    m = declare(:rename, {touches: ["User"]})
    s = write(blank, {id: "w1", mutation: m, patch: renamed("u7", "x")})
    settle(s, "w1", :rolled_back) #=> blank
"""
def settle(store, id, outcome)
  event = outcome_event(outcome)
  writes = (store or blank)[:writes]
  w = find_first((x) -> x[:id] == id, writes)
  if w.nil?
    raise(:conflict, "settle: no pending write #{to_s(id)}")
  end
  step = isshou::raifusaikuru::admit_step(
    write_machine,
    w[:state],
    isshou::raifusaikuru::ev(event, 0, [])
  )
  if not isshou::raifusaikuru::admitted?(first(step))
    raise(
      :conflict,
      "settle: write #{to_s(id)} cannot #{to_s(event)} from #{to_s(isshou::raifusaikuru::phase(w[:state]))}"
    )
  end
  rest = filter((x) -> x[:id] != id, writes)
  if isshou::raifusaikuru::phase(second(step)) == :confirmed
    assoc(merge(assoc(store, :writes, []), w[:patch]), :writes, rest)
  else
    assoc(store, :writes, rest)
  end
end

@doc """
persisted_body builds the request body that names an operation by its hash and sends no query text.

    persisted_body(page_query, nil)["operationName"] #=> "Post"
    persisted_body(page_query, nil)["query"] #=> nil
"""
def persisted_body(doc, variables)
  op = find_first((d) -> d[:kind] == :operation, doc[:definitions])
  body = {
    "extensions" => {
      "persistedQuery" => {
        "version" => 1,
        "sha256Hash" => toriyose::danpen::hash(doc)
      }
    },
    "variables" => variables or {}
  }
  if op != nil and op[:name] != nil
    assoc(body, "operationName", op[:name])
  else
    body
  end
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
request: run an operation on a server by its persisted hash only.

    t = echoed(200, {"data" => {"ok" => true}})
    request("http://h.example/graphql", {operation: page_query}, {transport: t}) #=> {"data" => {"ok" => true}}
"""
def request(target, input, opts?)
  i = checked(input, %i[operation variables])
  o = checked(opts, %i[headers timeout_ms transport])
  if i[:operation].nil?
    raise(:bad_option, "request: operation: is the document to run")
  end
  doc = toriyose::danpen::as_document(i[:operation])
  r = eigyou::tsuushin::request(
    "POST",
    target,
    {
      json: persisted_body(doc, i[:variables]),
      headers: o[:headers],
      timeout_ms: o[:timeout_ms],
      transport: o[:transport]
    }
  )
  status = r[:status]
  if status < 200 or status >= 300
    raise(
      :request_error,
      "request: #{target} answered #{to_s(status)}",
      {data: r}
    )
  end
  reply = json_read(r[:body])
  errors = reply["errors"] or []
  if any?((e) -> e["message"] == "PersistedQueryNotFound", errors)
    raise(
      :not_persisted,
      "request: #{target} holds no operation #{toriyose::danpen::hash(doc)}, and no query text is sent",
      {data: toriyose::danpen::hash(doc)}
    )
  end
  if reply["data"].nil? and not is_empty(errors)
    raise(
      :graphql,
      blue::join(map((e) -> e["message"], errors), "; "),
      {data: errors}
    )
  end
  reply
end

@doc """
sdl is the blog schema the tests and examples cache: posts, comments and users.

    starts_with?(sdl, "type Query") #=> true
"""
def sdl()
  join_lines(
    [
      "type Query { post(id: ID!): Post posts: [Post!]! }",
      "type Mutation { rename(id: ID!, name: String!): User }",
      "type Post { id: ID! title: String! author: User comments: [Comment!]! }",
      "type Comment { id: ID! body: String! author: User }",
      "type User { id: ID! name: String! }",
      "type Note { text: String }"
    ]
  )
end

@doc """
user_card is the fragment a user view reads: the user's id and name.

    read(normalize(response, sdl), {fragment: user_card, at: "User:u8"})["name"] #=> "Lin"
"""
def user_card()
  toriyose::danpen::fragment(:user_card, {on: "User", fields: %i[id name]})
end

@doc """
comment_item is the fragment a comment view reads, with its author through user_card.

    read(normalize(response, sdl), {fragment: comment_item, at: "Comment:c2"})["body"] #=> "Why?"
"""
def comment_item()
  toriyose::danpen::fragment(
    :comment_item,
    {on: "Comment", fields: [:id, :body, {author: ["...user_card"]}]}
  )
end

@doc """
post_page is the fragment a post view reads, nesting comment_item and user_card.

    read(normalize(response, sdl), {fragment: post_page, at: "Post:p1"})["title"] #=> "Fragments"
"""
def post_page()
  toriyose::danpen::fragment(
    :post_page,
    {
      on: "Post",
      fields: [
        :id,
        :title,
        {author: ["...user_card"]},
        {comments: ["...comment_item"]}
      ]
    }
  )
end

@doc """
page_query is the post page operation, composed with the fragments it spreads.

    operation_of(page_query)[:name] #=> "Post"
"""
def page_query()
  text = "query Post($id: ID!) { post(id: $id) { ...post_page } }"
  toriyose::danpen::compose(
    toriyose::danpen::parse(text),
    [post_page, comment_item, user_card]
  )
end

@doc """
operation_of takes the first operation of a document, the thing a root read answers.

    read(normalize(response, sdl), {fragment: operation_of(page_query)}) #=> {"post" => {"__ref" => "Post:p1"}}
"""
def operation_of(doc)
  first(toriyose::danpen::definitions_of_kind(doc, :operation))
end

@doc """
ada is one user the sample response holds twice, to show one shared entity.

    ada["name"] #=> "Ada"
"""
def ada()
  {"id" => "u7", "name" => "Ada"}
end

@doc """
response is the sample post page response the tests normalize.

    response["data"]["post"]["id"] #=> "p1"
"""
def response()
  {
    "data" => {
      "post" => {
        "id" => "p1",
        "title" => "Fragments",
        "author" => ada,
        "comments" => [
          {"id" => "c1", "body" => "Agreed", "author" => ada},
          {
            "id" => "c2",
            "body" => "Why?",
            "author" => {"id" => "u8", "name" => "Lin"}
          }
        ]
      }
    }
  }
end

@doc """
renamed is the normalized response of a rename mutation, used as an optimistic patch.

    renamed("u7", "x")[:entities]["User:u7"]["name"] #=> "x"
"""
def renamed(id, name)
  normalize(
    {
      "data" => {
        "rename" => {"__typename" => "User", "id" => id, "name" => name}
      }
    },
    sdl
  )
end

@doc """
entity_keys lists the keys of a store's entities in order, for comparing stores.

    entity_keys(normalize(response, sdl)) #=> ["Comment:c1", "Comment:c2", "Post:p1", "User:u7", "User:u8"]
"""
def entity_keys(s)
  sort_keyed((k) -> k, map(first, map_entries(s[:entities])))
end

@doc """
unref removes the reference marks a store read adds, so a read compares with a plain selection.

    unref({"__ref" => "User:1", "id" => "1"}) #=> {"id" => "1"}
"""
def unref(x)
  if map?(x)
    reduce(
      (m, e) -> assoc(m, first(e), unref(second(e))),
      {},
      filter((e) -> first(e) != "__ref", map_entries(x))
    )
  elsif list?(x) and x != nil
    map(unref, x)
  else
    x
  end
end

@doc """
users is the pool drawn responses pick authors from.

    size(users) #=> 3
"""
def users()
  [
    {"id" => "u1", "name" => "Ann"},
    {"id" => "u2", "name" => "Bo"},
    {"id" => "u3", "name" => "Cy"}
  ]
end

@doc """
drawn_user draws an author from users for a seed, or nil for a missing author.

    member?(drawn_user(1), push(users, nil)) #=> true
"""
def drawn_user(seed)
  if ran::next_uniform(seed, 4) == 0
    nil
  else
    ran::pick(ran::stream_seed(seed, 1), users)
  end
end

@doc """
drawn_post draws a post with its comments for a seed and a post id.

    drawn_post(0, "p1")["title"] #=> "Tp1"
"""
def drawn_post(seed, pid)
  n = ran::next_uniform(ran::stream_seed(seed, 2), 4)
  {
    "id" => pid,
    "title" => "T#{pid}",
    "author" => drawn_user(ran::stream_seed(seed, 3)),
    "comments" => map(
      fn(i)
        cid = "#{pid}-#{to_s(i)}"
        {
          "id" => cid,
          "body" => "B#{cid}",
          "author" => drawn_user(ran::stream_seed(seed, 10 + i))
        }
      end,
      range(0, n)
    )
  }
end

@doc """
drawn_response draws a posts response for a seed, for the normalize then read property.

    list?(drawn_response(0)["data"]["posts"]) #=> true
"""
def drawn_response(seed)
  pids = take(
    ran::next_uniform(ran::stream_seed(seed, 5), 5),
    ran::shuffle(seed, %w[p1 p2 p3 p4])
  )
  {
    "data" => {
      "posts" => map((pid) -> drawn_post(ran::stream_seed(seed, 7), pid), pids)
    }
  }
end

@doc """
posts_query is the operation that selects every field a drawn response holds.

    r = drawn_response(3)
    unref(read(normalize(r, sdl), {fragment: posts_query})) == toriyose::danpen::select(r["data"], posts_query) #=> true
"""
def posts_query()
  text = "{ posts { id title author { id name } comments { id body author { id name } } } }"
  operation_of(toriyose::danpen::parse(text))
end

@doc """
server_text is the program of the stand-in server: it answers one request with a canned reply and records what it was sent.

    starts_with?(server_text, "dir = argv_get(0)") #=> true
"""
def server_text()
  unlines(
    [
      "dir = argv_get(0)",
      "l = http_listen(\"127.0.0.1:0\")",
      "write_file(path_join(dir, \"port\"), to_s(http_listener_port(l)))",
      "req = http_next_request(l, 20000)",
      "http_respond(",
      "  req,",
      "  200,",
      "  {\"content-type\" => \"application/json\"},",
      "  read_file(path_join(dir, \"reply.json\"))",
      ")",
      "write_file(path_join(dir, \"seen.json\"), get(req, :body))",
      "more = http_next_request(l, 300)",
      "write_file(path_join(dir, \"more\"), to_s(more != nil))"
    ]
  )
end

@doc """
waited waits for a file the stand-in server writes, and gives up with a timeout after a number of tries.

    contains?(server_text, "more = http_next_request(l, 300)") #=> true
"""
def waited(path, tries)
  if is_file?(path)
    read_file(path)
  elsif tries < 1
    raise(:timeout, "#{path} never appeared")
  else
    sleep_ms(50)
    waited(path, tries - 1)
  end
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
hanabi_double starts the stand-in server for a reply in its own process, and gives the directory it writes to.

    contains?(server_text, "req = http_next_request(l, 20000)") #=> true
"""
def hanabi_double(reply)
  dir = tesuto::scratch
  mkdir_p(dir)
  write_program(path_join(dir, "server.b"), server_text)
  write_file(path_join(dir, "reply.json"), reply)
  sh_exec(
    "'#{self_exe}' run '#{path_join(dir, "server.b")}' -- '#{dir}' >/dev/null 2>&1 &"
  )
  dir
end

@doc """
user_view is the component that shows one user through the user_card fragment.

    gamen::render(page_of(normalize(response, sdl)), :html, {refuse: :page}) == page_html #=> true
"""
def user_view()
  gamen::component(
    :user_view,
    {
      props: {store: :required, ref: :required},
      view: fn(p, _s)
        u = read(p[:store], {fragment: user_card, at: p[:ref]})
        gamen::view(:span, {}, [u["name"]])
      end
    }
  )
end

@doc """
comment_view is the component that shows one comment through the comment_item fragment.

    gamen::render(page_of(normalize(response, sdl)), :html, {refuse: :page}) == page_html #=> true
"""
def comment_view()
  gamen::component(
    :comment_view,
    {
      props: {store: :required, ref: :required},
      view: fn(p, _s)
        c = read(p[:store], {fragment: comment_item, at: p[:ref]})
        gamen::view(
          :li,
          {},
          [
            gamen::view(user_view, {store: p[:store], ref: c["author"]}),
            ": #{c["body"]}"
          ]
        )
      end
    }
  )
end

@doc """
post_view is the component that shows one post through the post_page fragment.

    gamen::render(page_of(normalize(response, sdl)), :html, {refuse: :page}) == page_html #=> true
"""
def post_view()
  gamen::component(
    :post_view,
    {
      props: {store: :required, ref: :required},
      view: fn(p, _s)
        s = p[:store]
        post = read(s, {fragment: post_page, at: p[:ref]})
        gamen::view(
          :article,
          {},
          [
            gamen::view(:h1, {}, [post["title"]]),
            gamen::view(
              :p,
              {},
              ["by ", gamen::view(user_view, {store: s, ref: post["author"]})]
            ),
            gamen::view(
              :ul,
              {},
              map(
                (c) -> gamen::view(comment_view, {store: s, ref: c}),
                post["comments"]
              )
            )
          ]
        )
      end
    }
  )
end

@doc """
page_of builds the post page from a store, each view reading its own fragment.

    gamen::check(page_of(normalize(response, sdl))) #=> []
"""
def page_of(store)
  root = read(store, {fragment: operation_of(page_query)})
  post = read(store, {fragment: post_page, at: root["post"]})
  gamen::page(
    {
      title: post["title"],
      body: [
        gamen::view(
          :main,
          {},
          [gamen::view(post_view, {store:, ref: root["post"]})]
        )
      ]
    }
  )
end

@doc """
fake is a transport that answers with what it was sent and a reply, so a test sees the request body.

    t = fake(200, {"ok" => true})
    request("http://h.example/graphql", {operation: page_query}, {transport: t})["reply"] #=> {"ok" => true}
"""
def fake(status, reply)
  fn(_method, _url, _headers, body, _timeout_ms)
    {
      status:,
      headers: [],
      body: json_stringify({"sent" => json_read(body), "reply" => reply})
    }
  end
end

@doc """
echoed is a transport that answers with a status and a reply only.

    t = echoed(200, {"data" => {}})
    request("http://h.example/graphql", {operation: page_query}, {transport: t}) #=> {"data" => {}}
"""
def echoed(status, reply)
  fn(_method, _url, _headers, _body, _timeout_ms)
    {status:, headers: [], body: json_stringify(reply)}
  end
end

test "key joins its parts with a colon, as hanabi's entity cache keys an entity"
  assert key(%w[User u7]) == "User:u7"
  assert key(["User", 7]) == "User:7"
  assert key(%w[Pair a b]) == "Pair:a:b"
  assert raises?(:bad_option, () -> key([]))
  assert raises?(:bad_option, () -> key(["User", nil]))
  assert raises?(:bad_option, () -> key("User:7"))
end

test "schema keys every object type with an id, and the generated table is kensa's"
  t = schema(sdl)
  assert t[:cached_types] == %w[Comment Post User]
  assert t[:key_fields] ==
    {"Comment" => ["id"], "Post" => ["id"], "User" => ["id"]}
  assert t[:separator] == ":"
  assert t[:format] == "kyasshu-keys/1"
  assert schema(toriyose::danpen::parse(sdl)) == t
  kensa = find_first(
    (f) -> ends_with?(first(f), "/kensa.graphql"),
    toriyose::danpen::fixtures("schema")
  )
  generated = find_first(
    is_file?,
    fairu::on_blue_path("toriyose/kyasshu/keys/kensa.json")
  )
  assert read_file(generated) ==
    unlines([json_stringify(schema(second(kensa)))])
  assert json_read(read_file(generated))["separator"] == ":"
end

test "normalize splits a response into one entity per Type:id"
  s = normalize(response, sdl)
  assert entity_keys(s) == %w[Comment:c1 Comment:c2 Post:p1 User:u7 User:u8]
  assert s[:root] == {"post" => {"__ref" => "Post:p1"}}
  assert s[:entities]["Post:p1"] ==
    {
      "__typename" => "Post",
      "id" => "p1",
      "title" => "Fragments",
      "author" => {"__ref" => "User:u7"},
      "comments" => [{"__ref" => "Comment:c1"}, {"__ref" => "Comment:c2"}]
    }
  assert normalize({"data" => {}}, sdl) ==
    {root: {}, entities: {}, stamps: {}, writes: []}
  bare = normalize({"post" => {"id" => "p1", "title" => "x"}}, schema(sdl))
  assert entity_keys(bare) == []
  typed = normalize(
    {"post" => {"__typename" => "Post", "id" => "p1"}},
    schema(sdl)
  )
  assert entity_keys(typed) == ["Post:p1"]
  assert entity_keys(
    normalize({"n" => {"__typename" => "Note", "text" => "t"}}, sdl)
  ) == []
  assert normalize(response, sdl, {now: 5})[:stamps] ==
    {
      "ROOT" => 5,
      "Comment:c1" => 5,
      "Comment:c2" => 5,
      "Post:p1" => 5,
      "User:u7" => 5,
      "User:u8" => 5
    }
  assert raises?(:bad_option, () -> normalize([], sdl))
end

test "two components share one entity copy"
  s = normalize(response, sdl)
  assert size(filter((k) -> starts_with?(k, "User:u7"), entity_keys(s))) == 1
  post = read(s, {fragment: post_page, at: "Post:p1"})
  first_comment = read(s, {fragment: comment_item, at: first(post["comments"])})
  by_post = read(s, {fragment: user_card, at: post["author"]})
  by_comment = read(s, {fragment: user_card, at: first_comment["author"]})
  assert by_post == by_comment
  assert by_post == {"__ref" => "User:u7", "id" => "u7", "name" => "Ada"}
  s2 = merge(s, renamed("u7", "Ada L."))
  assert read(s2, {fragment: user_card, at: post["author"]})["name"] == "Ada L."
  assert read(s2, {fragment: user_card, at: first_comment["author"]})["name"] ==
    "Ada L."
  assert post["author"] == {"__ref" => "User:u7"}
  assert merge(s, s) == s
  assert merge(nil, s) == s
  assert merge(s, nil) == s
end

test "normalize then read gives back what the query selects, for any response"
  q = posts_query
  checked = map(
    fn(seed)
      r = drawn_response(seed)
      unref(read(normalize(r, sdl), {fragment: q})) ==
        toriyose::danpen::select(r["data"], q)
    end,
    range(0, 120)
  )
  assert filter((ok) -> not ok, checked) == []
  assert size(
    filter(
      (seed) -> size(drawn_response(seed)["data"]["posts"]) > 1,
      range(0, 120)
    )
  ) > 20
end

test "a read misses when the store lacks an entity or a field"
  s = normalize(response, sdl)
  assert read(s, {fragment: user_card, at: "User:nobody"}).nil?
  wide = toriyose::danpen::fragment(
    :wide,
    {on: "User", fields: %i[id name email]}
  )
  assert read(s, {fragment: wide, at: "User:u7"}).nil?
  assert read(nil, {fragment: user_card}).nil?
  assert read(s, {fragment: operation_of(page_query), at: nil}).nil?
  assert read(s, {fragment: operation_of(page_query)}) ==
    {"post" => {"__ref" => "Post:p1"}}
  assert raises?(:bad_option, () -> read(s, {at: "User:u7"}))
  assert raises?(:bad_option, () -> read(s, {fragment: user_card, at: 7}))
  assert raises?(:bad_option, () -> read(s, {fragment: user_card, when: 1}))
end

test "policy takes each rule as a kousei entry, configured off alone and refused alone"
  p = policy(
    [user_card, comment_item, post_page],
    [
      kousei::entry(:ttl, "user_card", {seconds: 60}),
      kousei::entry(:stale, "user_card", {mode: :revalidate}),
      kousei::entry(:persist, "user_card", {to: :indexeddb}),
      kousei::entry(:evict, "comment_item", {after: 300}),
      kousei::entry(:ttl, "ghost", {seconds: 5}),
      kousei::entry(:ttl, "post_page", {seconds: 0}),
      kousei::off(:stale, "user_card")
    ]
  )
  assert p[:fragments]["user_card"] ==
    {on: "User", ttl: 60, stale: nil, persist: :indexeddb, evict: nil}
  assert p[:fragments]["comment_item"][:evict] == 300
  assert p[:fragments]["post_page"][:ttl].nil?
  assert map(first, p[:refusals]) == %i[invalid unknown_fragment]
  assert map(kousei::kind_of, p[:off]) == [:stale]
  assert raises?(:bad_option, () -> policy(user_card, []))
end

test "ttl and stale revalidate decide what a read serves"
  s = normalize(response, sdl, {now: 1000})
  ttl = kousei::entry(:ttl, "user_card", {seconds: 60})
  p = policy([user_card], [ttl])
  at = "User:u7"
  assert read(s, {fragment: user_card, at:, now: 1059, policy: p}) != nil
  assert read(s, {fragment: user_card, at:, now: 1060, policy: p}).nil?
  assert stale?(s, {fragment: user_card, at:, now: 1059, policy: p}) == false
  assert stale?(s, {fragment: user_card, at:, now: 1060, policy: p}) == true
  swr = policy(
    [user_card],
    [ttl, kousei::entry(:stale, "user_card", {mode: :revalidate})]
  )
  assert read(s, {fragment: user_card, at:, now: 5000, policy: swr})["name"] ==
    "Ada"
  assert stale?(s, {fragment: user_card, at:, now: 5000, policy: swr}) == true
  off = policy([user_card], [ttl, kousei::off(:ttl, "user_card")])
  assert read(s, {fragment: user_card, at:, now: 99999, policy: off}) != nil
  assert stale?(s, {fragment: user_card, at:, now: 99999, policy: off}) == false
  assert read(
    normalize(response, sdl),
    {fragment: user_card, at:, now: 1, policy: p}
  ).nil?
  assert stale?(
    s,
    {fragment: user_card, at: "User:nobody", now: 5000, policy: p}
  ) == false
  assert raises?(
    :bad_option,
    () -> read(s, {fragment: user_card, at:, policy: p})
  )
end

test "persist snapshots the entities persisted fragments read, never a pending write"
  s = normalize(response, sdl, {now: 1000})
  p = policy(
    [user_card],
    [kousei::entry(:persist, "user_card", {to: :indexeddb})]
  )
  snap = snapshot(s, {policy: p})
  assert entity_keys(snap) == %w[User:u7 User:u8]
  assert snap[:root] == {}
  assert snap[:stamps] == {"User:u7" => 1000, "User:u8" => 1000}
  pending = write(
    s,
    {
      id: "w1",
      mutation: declare(:rename, {touches: ["User"]}),
      patch: renamed("u7", "Ada L.")
    }
  )
  assert snapshot(pending, {policy: p}) == snap
  assert entity_keys(snapshot(s)) == []
  off = policy(
    [user_card],
    [
      kousei::entry(:persist, "user_card", {to: :indexeddb}),
      kousei::off(:persist, "user_card")
    ]
  )
  assert entity_keys(snapshot(s, {policy: off})) == []
end

test "evict sweeps the entities older than their fragment's limit"
  s = normalize(response, sdl, {now: 1000})
  p = policy(
    [comment_item],
    [kousei::entry(:evict, "comment_item", {after: 300})]
  )
  assert sweep(s, {now: 1299, policy: p}) == s
  swept = sweep(s, {now: 1300, policy: p})
  assert entity_keys(swept) == %w[Post:p1 User:u7 User:u8]
  assert swept[:stamps]["Comment:c1"].nil?
  assert read(swept, {fragment: post_page, at: "Post:p1"}).nil?
  assert read(swept, {fragment: user_card, at: "User:u7"}) != nil
  assert read(swept, {fragment: comment_item, at: "Comment:c1"}).nil?
  assert sweep(s, {now: 99999}) == s
  assert raises?(:bad_option, () -> sweep(s, {policy: p}))
end

test "an optimistic write is pending until settled, and a rollback restores the exact prior store"
  s0 = normalize(response, sdl, {now: 1000})
  rename = declare(:rename, {touches: ["User"]})
  patch = renamed("u7", "Ada L.")
  s1 = write(s0, {id: "w1", mutation: rename, patch:})
  assert read(s1, {fragment: user_card, at: "User:u7"})["name"] == "Ada L."
  assert read(s0, {fragment: user_card, at: "User:u7"})["name"] == "Ada"
  assert s1[:entities]["User:u7"] == s0[:entities]["User:u7"]
  assert settle(s1, "w1", :rolled_back) == s0
  kept_write = settle(s1, "w1", :confirmed)
  assert kept_write[:writes] == []
  assert kept_write[:entities]["User:u7"]["name"] == "Ada L."
  assert raises?(:conflict, () -> settle(kept_write, "w1", :rolled_back))
  assert raises?(
    :conflict,
    () -> write(s1, {id: "w1", mutation: rename, patch:})
  )
  assert raises?(:bad_option, () -> settle(s1, "w1", :maybe))
  other = {id: "w2", mutation: rename, patch: renamed("u8", "Lin K.")}
  s2 = write(s1, other)
  assert settle(s2, "w1", :rolled_back) == write(s0, other)
  assert read(s2, {fragment: user_card, at: "User:u8"})["name"] == "Lin K."
end

test "the write machine has no way out of a settled state"
  d = write_machine
  rolled = isshou::raifusaikuru::state_of(
    d,
    [isshou::raifusaikuru::ev(:roll_back, 0, [])]
  )
  assert isshou::raifusaikuru::phase(rolled) == :rolled_back
  assert isshou::raifusaikuru::admitted?(
    isshou::raifusaikuru::admit(
      d,
      rolled,
      isshou::raifusaikuru::ev(:confirm, 0, [])
    )
  ) == false
  assert isshou::raifusaikuru::admitted?(
    isshou::raifusaikuru::admit(
      d,
      isshou::raifusaikuru::initial(d),
      isshou::raifusaikuru::ev(:confirm, 0, [])
    )
  )
  assert isshou::raifusaikuru::phase(
    get(
      first(
        get(
          write(
            nil,
            {
              id: 1,
              mutation: declare(:m, {touches: ["User"]}),
              patch: renamed("u7", "x")
            }
          ),
          :writes
        )
      ),
      :state
    )
  ) == :pending
end

test "declare names the types a mutation touches, and touched reads them off a patch"
  m = declare(:rename, {touches: %w[User User]})
  assert m == {mutation: "rename", touches: ["User"], operation: nil}
  assert touched(renamed("u7", "x")) == m[:touches]
  assert touched(normalize(response, sdl)) == %w[Comment Post User]
  assert raises?(:bad_option, () -> declare(:rename, {touches: []}))
  assert raises?(:bad_option, () -> declare(:rename, {touches: [:User]}))
  assert raises?(:bad_option, () -> declare(:rename, {}))
end

test "request posts the persisted hash and no query text through tsuushin"
  r = request(
    "http://h.example/graphql",
    {operation: page_query, variables: {"id" => "p1"}},
    {transport: fake(200, {"ok" => true})}
  )
  sent = r["sent"]
  assert sent["extensions"]["persistedQuery"]["sha256Hash"] ==
    toriyose::danpen::hash(page_query)
  assert sent["extensions"]["persistedQuery"]["version"] == 1
  assert sent["query"].nil?
  assert sent["operationName"] == "Post"
  assert sent["variables"] == {"id" => "p1"}
  missing = {"errors" => [{"message" => "PersistedQueryNotFound"}]}
  assert raises?(
    :not_persisted,
    fn()
      request(
        "http://h.example/graphql",
        {operation: page_query},
        {transport: echoed(200, missing)}
      )
    end
  )
  assert raises?(
    :request_error,
    fn()
      request(
        "http://h.example/graphql",
        {operation: page_query},
        {transport: echoed(502, {})}
      )
    end
  )
  assert raises?(
    :graphql,
    fn()
      request(
        "http://h.example/graphql",
        {operation: page_query},
        {transport: echoed(200, {"errors" => [{"message" => "boom"}]})}
      )
    end
  )
  assert raises?(:bad_option, () -> request("http://h.example/graphql", {}))
end

@doc """
page_html is the HTML the post page must render to.

    starts_with?(page_html, "<!doctype html>") #=> true
"""
def page_html()
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta content=\"width=device-width, initial-scale=1\" name=\"viewport\"><title>Fragments</title></head><body><main><article><h1>Fragments</h1><p>by <span>Ada</span></p><ul><li><span>Ada</span>: Agreed</li><li><span>Lin</span>: Why?</li></ul></article></main></body></html>"
end

@doc """
ssr renders the post page on a server from one request, and checks it.

    t = echoed(200, response)
    first(ssr("http://h.example/graphql", {transport: t})) == page_html #=> true
"""
def ssr(url, opts)
  got = request(url, {operation: page_query, variables: {"id" => "p1"}}, opts)
  store = normalize(got, sdl, {now: 0})
  [
    gamen::render(page_of(store), :html, {refuse: :page}),
    gamen::check(page_of(store))
  ]
end

@doc """
mailbox drains the messages this process holds, in order.

    mailbox([]) #=> []
"""
def mailbox(acc)
  m = receive(:_, 0, :none)
  if m == :none
    acc
  else
    mailbox(push(acc, m))
  end
end

@doc """
persisted? tells whether a request body names the page query by hash and sends no query text.

    persisted?(persisted_body(page_query, nil)) #=> true
"""
def persisted?(body)
  body["extensions"]["persistedQuery"]["sha256Hash"] ==
    toriyose::danpen::hash(page_query) and body["query"].nil?
end

test "an SSR page with nested fragments renders from one request"
  me = self
  counted = fn(_method, _url, _headers, body, _timeout_ms)
    send(me, [:sent, body])
    {status: 200, headers: [], body: json_stringify(response)}
  end
  out = ssr("http://hanabi.test/graphql", {transport: counted})
  sent = mailbox([])
  assert first(out) == page_html
  assert second(out) == []
  assert size(sent) == 1
  assert persisted?(json_read(second(first(sent))))
end

test "the SSR request crosses a real socket to a separate server"
  if self_exe != nil
    dir = hanabi_double(json_stringify(response))
    port = waited(path_join(dir, "port"), 400)
    out = ssr("http://127.0.0.1:#{port}/graphql", {})
    assert first(out) == page_html
    assert persisted?(json_read(waited(path_join(dir, "seen.json"), 400)))
    assert waited(path_join(dir, "more"), 400) == "false"
    rm_rf(dir)
  end
end
