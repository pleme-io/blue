@moduledoc """
happa (葉っぱ) — a template's leaves: split, graph, change, schedule and verdicts, as pure decisions.

A fat template's state splits into leaves by each address's leaf key (a
for_each key, a module, or the address itself), joined by reference edges.
The leaves form a graph whose edges point from an upstream to the leaf that
reads it. Content hashes say which leaves changed, `admit` says which work
runs next under the caps, `drift_due` spreads each leaf's drift plan over its
interval, and `health` and `judge` give one leaf's verdict and the parent's
partial state. Every word is pure: the clock, the addresses, the digests and
the leaf states come in as values, so the operator embeds this bidama with
every host effect refused. Records meant for a status field carry its
camelCase names.

    key("github_repository.repos[\"acude\"]") #=> {kind: :keyed, value: "acude"}
"""

use("gurafu")
use("kousei", %i[entry field off one_of required text])
use("moji", [:checked])
use("retsu", %i[first is_empty last size])
use("tesuto", [:raises?])

@doc """
text_of: the characters from one index up to another, joined.

    text_of(chars("abcd"), 1, 3) #=> "bc"
"""
def text_of(cs, from, to)
  join(take(to - from, drop(from, cs)), "")
end

@doc """
name_end: the first index at or after i that holds a dot or an opening bracket, or the end.

    name_end(chars("ab.c"), 0) #=> 2
"""
def name_end(cs, i)
  if i < size(cs) and cs[i] != "." and cs[i] != "["
    name_end(cs, i + 1)
  else
    i
  end
end

@doc """
quoted: a quoted index key read from i to its closing quote, with the index after the closing bracket.

    quoted("a[\"k\"]", chars("a[\"k\"]"), 3, "") #=> ["k", 6]
"""
def quoted(a, cs, i, buf)
  c = cs[i]
  if i >= size(cs)
    raise(:parse_error, "unterminated string in `#{a}`")
  elsif c == "\\"
    if i + 1 >= size(cs)
      raise(:parse_error, "unterminated string in `#{a}`")
    end
    quoted(a, cs, i + 2, "#{buf}#{cs[i + 1]}")
  elsif c == "\""
    if i + 1 >= size(cs) or cs[i + 1] != "]"
      raise(:parse_error, "unterminated index in `#{a}`")
    end
    [buf, i + 2]
  else
    quoted(a, cs, i + 1, "#{buf}#{c}")
  end
end

@doc """
bare: an unquoted index key read from i to its closing bracket, with the index after it.

    bare("a[3]", chars("a[3]"), 2) #=> ["3", 4]
"""
def bare(a, cs, i)
  close = position("]", drop(i, cs))
  if close < 0
    raise(:parse_error, "unterminated index in `#{a}`")
  end
  [text_of(cs, i, i + close), i + close + 1]
end

@doc """
steps_from: the steps of an address from index i on, each a name and its index key or nil.

    steps_from("a.b", chars("a.b"), 0, []) #=> [{name: "a", key: nil}, {name: "b", key: nil}]
"""
def steps_from(a, cs, i, acc)
  j = name_end(cs, i)
  name = text_of(cs, i, j)
  if name == ""
    raise(:parse_error, "empty segment in `#{a}`")
  end
  read = if j < size(cs) and cs[j] == "["
    if j + 1 < size(cs) and cs[j + 1] == "\""
      quoted(a, cs, j + 2, "")
    else
      bare(a, cs, j + 1)
    end
  else
    [nil, j]
  end
  next = read[1]
  done = retsu::push(acc, {name:, key: first(read)})
  if next >= size(cs)
    done
  elsif cs[next] == "."
    steps_from(a, cs, next + 1, done)
  else
    raise(:parse_error, "unexpected `#{cs[next]}` after an index in `#{a}`")
  end
end

@doc """
steps: an address read into its steps; a malformed address raises :parse_error, never a guess.

    size(steps("module.m[\"k\"].a.b[2]")) #=> 4
"""
def steps(address)
  if address == ""
    raise(:parse_error, "empty address")
  end
  steps_from(address, chars(address), 0, [])
end

@doc """
key: a resource address's leaf key: its first index key, else its top module, else the address itself.

    key("module.vpc.module.inner.aws_subnet.s") #=> {kind: :module, value: "module.vpc"}
"""
def key(address)
  ss = steps(address)
  keyed = filter((s) -> s[:key] != nil, ss)
  if not is_empty(keyed)
    {kind: :keyed, value: first(keyed)[:key]}
  elsif size(ss) >= 2 and first(ss)[:name] == "module"
    {kind: :module, value: "module.#{ss[1][:name]}"}
  else
    {kind: :address, value: address}
  end
end

@doc """
strip_index: an address with every index key dropped.

    strip_index("module.m[\"k\"].a.b[2]") #=> "module.m.a.b"
"""
def strip_index(address)
  join(map((s) -> s[:name], steps(address)), ".")
end

@doc """
data?: whether an address names a data source, at the top or inside a module.

    data?("module.m.data.aws_ami.x") #=> true
"""
def data?(address)
  rest = if starts_with?(address, "module.")
    tail = drop(7, chars(address))
    dot = position(".", tail)
    if dot < 0
      address
    else
      join(drop(dot + 1, tail), "")
    end
  else
    address
  end
  starts_with?(address, "data.") or starts_with?(rest, "data.")
end

@doc """
key_id: text that orders leaf keys as the operator does: keyed, then module, then address, then by value.

    key_id({kind: :module, value: "module.a"}) #=> "1:module.a"
"""
def key_id(k)
  rank = position(k[:kind], %i[keyed module address])
  "#{to_s(rank)}:#{k[:value]}"
end

@doc """
managed: the addresses that are not data sources.

    managed(["a.b", "data.x.y"]) #=> ["a.b"]
"""
def managed(addresses)
  filter((a) -> not data?(a), addresses)
end

@doc """
classify: whether a state is fat: more than one leaf key, or a cycle p95 over its budget.

    classify(["a.b[\"x\"]", "a.b[\"y\"]"], nil, nil)[:fat] #=> true
"""
def classify(addresses, p95_ms, budget_ms)
  n = size(distinct(map((a) -> key_id(key(a)), managed(addresses))))
  over = p95_ms != nil and budget_ms != nil and p95_ms > budget_ms
  reasons = append(
    if n > 1
      [{reason: "multipleLeafKeys", leafKeys: n}]
    else
      []
    end,
    if over
      [{reason: "cycleOverBudget", p95Ms: p95_ms, budgetMs: budget_ms}]
    else
      []
    end
  )
  {
    leafKeys: n,
    cycleP95Ms: p95_ms,
    budgetMs: budget_ms,
    fat: not is_empty(reasons),
    reasons:
  }
end

@doc """
root_of: the root a key's chain of parents ends at.

    root_of({"b" => "a", "a" => "a"}, "b") #=> "a"
"""
def root_of(parent, id)
  up = get(parent, id)
  if up == id
    id
  else
    root_of(parent, up)
  end
end

@doc """
joined: the parent map after one reference edge joins two leaves, the smaller key becoming the root.

    joined({"0:a" => "0:a", "0:b" => "0:b"}, ["0:b", "0:a"]) #=> {"0:a" => "0:a", "0:b" => "0:a"}
"""
def joined(parent, edge)
  a = first(edge)
  b = edge[1]
  if get(parent, a).nil? or get(parent, b).nil?
    parent
  else
    ra = root_of(parent, a)
    rb = root_of(parent, b)
    if ra == rb
      parent
    elsif compare(ra, rb) < 0
      assoc(parent, rb, ra)
    else
      assoc(parent, ra, rb)
    end
  end
end

@doc """
split: the leaves of a state: its managed addresses grouped by leaf key, then joined along reference edges between keys; a repeated address is refused.

    size(split(["r.a[\"x\"]", "q.a[\"x\"]", "r.a[\"y\"]"], [])) #=> 2
"""
def split(addresses, refs)
  own = managed(addresses)
  in_order = sort_keyed((x) -> x, own)
  dup = filter((i) -> in_order[i] == in_order[i + 1], range(size(own) - 1))
  if not is_empty(dup)
    raise(
      :refused,
      "address `#{in_order[first(dup)]}` appears more than once in the state"
    )
  end
  pairs = map(
    fn(a)
      k = key(a)
      [key_id(k), k, a]
    end,
    own
  )
  ids = sort_keyed((x) -> x, distinct(map(first, pairs)))
  key_by = reduce((acc, p) -> assoc(acc, first(p), p[1]), {}, pairs)
  addrs_by = reduce(
    fn(acc, p)
      assoc(acc, first(p), retsu::push(get(acc, first(p)) or [], p[2]))
    end,
    {},
    pairs
  )
  parent = reduce(
    joined,
    reduce((acc, i) -> assoc(acc, i, i), {}, ids),
    map((e) -> [key_id(first(e)), key_id(e[1])], refs)
  )
  rooted = map((i) -> [root_of(parent, i), i], ids)
  members_by = reduce(
    fn(acc, p)
      assoc(acc, first(p), retsu::push(get(acc, first(p)) or [], p[1]))
    end,
    {},
    rooted
  )
  roots = map(first, filter((p) -> first(p) == p[1], rooted))
  map(
    fn(r)
      members = get(members_by, r)
      {
        key: get(key_by, r),
        merged_from: map((i) -> get(key_by, i), filter((i) -> i != r, members)),
        addresses: sort_keyed(
          (x) -> x,
          retsu::flat_map(members, (i) -> get(addrs_by, i))
        )
      }
    end,
    roots
  )
end

@doc """
le64: a count as its eight little-endian bytes.

    le64(258) #=> [2, 1, 0, 0, 0, 0, 0, 0]
"""
def le64(n)
  map(
    (p) -> floor(n / p) % 256,
    [
      1,
      256,
      65536,
      16_777_216,
      4_294_967_296,
      1_099_511_627_776,
      281_474_976_710_656,
      72_057_594_037_927_936
    ]
  )
end

@doc """
multiset_hash: the BLAKE3 of a list of addresses taken as a multiset: the count, then each address sorted with its length, so order never matters and no two lists concatenate alike.

    multiset_hash(["b", "a"]) == multiset_hash(["a", "b"]) #=> true
"""
def multiset_hash(addresses)
  sorted = sort_keyed((x) -> x, addresses)
  blake3_hex(
    append(
      le64(size(sorted)),
      retsu::flat_map(
        sorted,
        fn(a)
          bs = text_bytes(a)
          append(le64(size(bs)), bs)
        end
      )
    )
  )
end

@doc """
bijection: whether the leaves hold exactly the managed addresses of the state before the split: equal multiset hashes and no address in two leaves.

    bijection(["a.b"], split(["a.b"], []))[:ok] #=> true
"""
def bijection(before, leaves)
  was = managed(before)
  now = retsu::flat_map(leaves, (l) -> l[:addresses])
  disjoint = size(distinct(now)) == size(now)
  hb = multiset_hash(was)
  ha = multiset_hash(now)
  {
    countBefore: size(was),
    countAfter: size(now),
    hashBefore: hb,
    hashAfter: ha,
    disjoint:,
    ok: disjoint and hb == ha
  }
end

@doc """
alnum?: whether a character is an ASCII letter or digit.

    alnum?("ç") #=> false
"""
def alnum?(c)
  between = (lo, hi) -> compare(c, lo) >= 0 and compare(c, hi) <= 0
  size(text_bytes(c)) == 1 and
    (between("a", "z") or between("A", "Z") or between("0", "9"))
end

@doc """
slug: a key as a DNS label part: ASCII letters and digits lowercased, every other run one dash, no dash at either end, and "leaf" when nothing is left.

    slug("Akeyless_Cursor") #=> "akeyless-cursor"
"""
def slug(raw)
  out = reduce(
    fn(acc, c)
      if alnum?(c)
        [retsu::push(first(acc), downcase(c)), false]
      elsif acc[1]
        acc
      else
        [retsu::push(first(acc), "-"), true]
      end
    end,
    [[], true],
    chars(raw)
  )
  t = trim(join(first(out), ""), {chars: "-"})
  if t == ""
    "leaf"
  else
    t
  end
end

@doc """
suffix: eight hex characters of the BLAKE3 of a key's kind and value, that tell apart keys whose slugs collide.

    size(chars(suffix({kind: :keyed, value: "a_b"}))) #=> 8
"""
def suffix(k)
  h = blake3_hex(append(text_bytes(to_s(k[:kind])), [0], text_bytes(k[:value])))
  join(take(8, chars(h)), "")
end

@doc """
name_cap: the longest object name a leaf may have, a DNS label's 63.

    name_cap #=> 63
"""
def name_cap()
  63
end

@doc """
names: the object name of each leaf key under a parent, in order: parent and slug, with a hash suffix when two keys share a slug or the name is too long.

    names("repos", [{kind: :keyed, value: "Akeyless_Cursor"}]) #=> ["repos-akeyless-cursor"]
"""
def names(parent, keys)
  plain = map((k) -> "#{parent}-#{slug(k[:value])}", keys)
  seen = reduce((acc, n) -> assoc(acc, n, (get(acc, n) or 0) + 1), {}, plain)
  map(
    fn(i)
      n = plain[i]
      shared = get(seen, n) > 1
      if shared or size(text_bytes(n)) > name_cap
        clipped = trim(
          join(take(name_cap - 9, chars(n)), ""),
          {side: :end, chars: "-"}
        )
        "#{clipped}-#{suffix(keys[i])}"
      else
        n
      end
    end,
    range(size(keys))
  )
end

@doc """
name: the object name of one leaf key among the keys of its parent.

    name("r", {kind: :keyed, value: "a_b"}, [{kind: :keyed, value: "a_b"}]) #=> "r-a-b"
"""
def name(parent, k, keys)
  names(parent, keys)[position(k, keys)]
end

@doc """
canonical: a value as canonical JSON text: object keys sorted, a comma after every member, so equal values give equal text.

    canonical({b: [1], a: "x"}) #=> "{\"a\":\"x\",\"b\":[1,],}"
"""
def canonical(v)
  if map?(v)
    members = map(
      (e) -> "#{json_stringify(to_s(first(e)))}:#{canonical(e[1])},",
      map_entries(v)
    )
    "{#{join(members, "")}}"
  elsif v != nil and list?(v)
    "[#{join(map((x) -> "#{canonical(x)},", v), "")}]"
  else
    json_stringify(v)
  end
end

@doc """
digest: the content hash of a leaf's inputs: the catalog's variables, the leaf's own and its references, each canonical, nil marking one absent.

    size(chars(digest({x: 1}, nil, nil))) #=> 32
"""
def digest(catalog, own, refs)
  text = join(
    map(
      fn(part)
        if part.nil?
          "~|"
        else
          "#{canonical(part)}|"
        end
      end,
      [catalog, own, refs]
    ),
    ""
  )
  join(take(32, chars(blake3_hex(text))), "")
end

@doc """
changed: the leaves whose recorded digest differs from the current one, sorted; a leaf with no recorded digest has not changed.

    changed({"a" => "d1", "b" => "d1"}, {"a" => "d0"}) #=> ["a"]
"""
def changed(current, recorded)
  sort_keyed(
    (x) -> x,
    map(
      first,
      filter(
        fn(e)
          was = get(recorded, first(e))
          was != nil and was != e[1]
        end,
        map_entries(current)
      )
    )
  )
end

@doc """
graph: the leaf graph from leaf names and [leaf, upstream] references, each edge pointing from the upstream to the leaf; a cycle is refused with :refused, naming the cycle and every leaf it holds.

    gurafu::topo(graph(["app", "db"], [["app", "db"]])) #=> ["db", "app"]
"""
def graph(leaves, refs)
  g = gurafu::graph(map((r) -> [r[1], first(r)], refs), {nodes: leaves})
  c = gurafu::cycle(g)
  if c != nil
    placed = retsu::flat_map(gurafu::layers(g), (l) -> l)
    stuck = filter((n) -> not member?(n, placed), gurafu::nodes(g))
    raise(
      :refused,
      "a leaf cycle: #{gurafu::cycle_text(c)}",
      {data: {cycle: c, stuck:}}
    )
  end
  g
end

@doc """
order: the apply order of a leaf graph, every leaf after its upstreams, in layers, each sorted by name.

    order(graph(["d", "b", "c", "a"], [["d", "b"], ["d", "c"], ["b", "a"], ["c", "a"]])) #=> ["a", "b", "c", "d"]
"""
def order(g)
  gurafu::topo(g)
end

@doc """
destroy_order: the reverse of the apply order: dependents before their upstreams.

    destroy_order(graph(["app", "db"], [["app", "db"]])) #=> ["app", "db"]
"""
def destroy_order(g)
  blue::reverse(order(g))
end

@doc """
upstreams: the leaves a leaf reads from, sorted.

    upstreams(graph(["a", "b"], [["a", "b"]]), "a") #=> ["b"]
"""
def upstreams(g, leaf)
  gurafu::neighbors(gurafu::reverse(g), leaf)
end

@doc """
dependents: every leaf that reads, directly or through others, from any of some leaves, sorted.

    dependents(graph(["a", "b", "c"], [["b", "a"], ["c", "b"]]), ["a"]) #=> ["b", "c"]
"""
def dependents(g, held)
  sort_keyed(
    (x) -> x,
    distinct(retsu::flat_map(held, (h) -> gurafu::reachable(g, h)))
  )
end

@doc """
blocked: which upstreams hold a leaf back: those not ready, where a mocked output lets a plan through but never an apply; sorted, each named once.

    blocked([{leaf: "u1", mock: true}], [], false) #=> []
"""
def blocked(ups, ready, applying)
  mocked = if applying
    []
  else
    map((u) -> u[:leaf], filter((u) -> u[:mock] == true, ups))
  end
  effective = append(ready, mocked)
  sort_keyed(
    (x) -> x,
    distinct(
      filter((n) -> not member?(n, effective), map((u) -> u[:leaf], ups))
    )
  )
end

@doc """
classes: the work classes in priority order: an approved apply, a changed leaf's plan, a leaf whose upstream became ready, a retry, a drift plan.

    first(classes) #=> :apply
"""
def classes()
  %i[apply change unblocked retry drift]
end

@doc """
ranked: candidates in the order they are offered a slot: by class, drift oldest first, then upstreams first by depth, then by name; with priority off, by arrival then name.

    map((c) -> c[:name], ranked([{name: "d", class: :drift, depth: 0, since: 1}, {name: "c", class: :change, depth: 0, since: 2}], :on)) #=> ["c", "d"]
"""
def ranked(candidates, priority)
  by_name = sort_keyed((c) -> c[:name], candidates)
  if priority == :off
    sort_keyed((c) -> c[:since], by_name)
  else
    age = fn(c)
      if c[:class] == :drift
        c[:since]
      else
        0
      end
    end
    sort_keyed(
      (c) -> position(c[:class], classes),
      sort_keyed(age, sort_keyed((c) -> c[:depth], by_name))
    )
  end
end

@doc """
drift_slots: how many of a scope's slots drift may hold: its share of the cap, at least one and, past a cap of one, never all; none when the share is zero.

    drift_slots(4, 500) #=> 2
"""
def drift_slots(scope_cap, share_permille)
  if share_permille == 0 or scope_cap == 0
    0
  else
    raw = floor(scope_cap * blue::min(share_permille, 1000) / 1000)
    hi = blue::max(scope_cap - 1, 1)
    blue::min(blue::max(raw, 1), hi)
  end
end

@doc """
bump: a count map with one key raised by one.

    bump({}, "s") #=> {"s" => 1}
"""
def bump(m, k)
  assoc(m or {}, k, (get(m or {}, k) or 0) + 1)
end

@doc """
fits?: whether one more candidate fits the scope cap, the drift reserve and the per-credential cap, given what is in flight.

    fits?({name: "a", scope: "s", class: :change}, {per_scope: 1}, {by_scope: {"s" => 1}}) #=> false
"""
def fits?(c, limits, f)
  cap = get(limits[:scope_caps] or {}, c[:scope]) or limits[:per_scope]
  in_scope = get(f[:by_scope] or {}, c[:scope]) or 0
  share = limits[:drift_share_permille] or 0
  drift_held = get(f[:drift_by_scope] or {}, c[:scope]) or 0
  cred = c[:credential]
  per_cred = limits[:per_credential] or 0
  in_scope < cap and
    not (
      c[:class] == :drift and
      share > 0 and
      drift_held >= drift_slots(cap, share)
    ) and
    not (
      cred != nil and
      per_cred > 0 and
      (get(f[:by_credential] or {}, cred) or 0) >= per_cred
    )
end

@doc """
admit: who runs next: candidates offered slots in ranked order under the global cap, each scope's cap, the drift reserve and the per-credential cap, given the work in flight; the names admitted, in order.

    admit([{name: "a", scope: "s", class: :change, depth: 0, since: 0}], {global: 1, per_scope: 1}, {}) #=> ["a"]
"""
def admit(candidates, limits, in_flight)
  start = {
    total: in_flight[:total] or 0,
    by_scope: in_flight[:by_scope] or {},
    drift_by_scope: in_flight[:drift_by_scope] or {},
    by_credential: in_flight[:by_credential] or {},
    out: []
  }
  done = reduce(
    fn(f, c)
      if f[:total] >= limits[:global] or not fits?(c, limits, f)
        f
      else
        {
          total: f[:total] + 1,
          by_scope: bump(f[:by_scope], c[:scope]),
          drift_by_scope: if c[:class] == :drift
            bump(f[:drift_by_scope], c[:scope])
          else
            f[:drift_by_scope]
          end,
          by_credential: if c[:credential].nil?
            f[:by_credential]
          else
            bump(f[:by_credential], c[:credential])
          end,
          out: retsu::push(f[:out], c[:name])
        }
      end
    end,
    start,
    ranked(candidates, limits[:priority] or :on)
  )
  done[:out]
end

@doc """
offsets: each leaf's place in a drift interval: the leaves ranked by the BLAKE3 of their names and spread evenly across it, so no stretch of the interval holds more than its share.

    offsets(["a"], 3600) #=> {"a" => 0}
"""
def offsets(names, interval)
  ranked = sort_keyed(
    (p) -> first(p),
    map((n) -> [blake3_hex(n), n], distinct(names))
  )
  n = blue::max(size(ranked), 1)
  iv = blue::max(interval, 1)
  reduce(
    (acc, i) -> assoc(acc, ranked[i][1], floor(i * iv / n)),
    {},
    range(size(ranked))
  )
end

@doc """
last_slot: the start of a leaf's most recent drift slot at a moment, or nil before its first slot.

    last_slot(10, 75, 60) #=> 70
"""
def last_slot(offset, now, interval)
  iv = blue::max(interval, 1)
  if now >= offset
    now - (now - offset) % iv
  end
end

@doc """
drift_due: the leaves whose drift slot has come since their last check, sorted by name; a leaf never checked is due from its first slot.

    drift_due([{name: "a", last_check: nil}], 0, 3600) #=> ["a"]
"""
def drift_due(leaves, now, interval)
  placed = offsets(map((l) -> l[:name], leaves), interval)
  due = filter(
    fn(l)
      slot = last_slot(get(placed, l[:name]), now, interval)
      last = l[:last_check]
      slot != nil and (last.nil? or last < slot)
    end,
    leaves
  )
  sort_keyed((x) -> x, distinct(map((l) -> l[:name], due)))
end

@doc """
skip_reasons: the typed world facts that let a fat template run as one, the annotation's values.

    first(skip_reasons) #=> "provider-singleton"
"""
def skip_reasons()
  %w[provider-singleton atomic-bootstrap external-contract shared-lifecycle]
end

@doc """
skip_annotation: the annotation a template declares its skip reason in.

    skip_annotation #=> "pangea.pleme.io/skip-leaf"
"""
def skip_annotation()
  "pangea.pleme.io/skip-leaf"
end

@doc """
skip_reason: the typed reason an annotation's value names before any colon, or nil when it names none.

    skip_reason(" shared-lifecycle: one UCI commit") #=> "shared-lifecycle"
"""
def skip_reason(raw)
  head = trim(first(blue::split(raw, ":")))
  if member?(head, skip_reasons)
    head
  end
end

@doc """
leaves_path: the leaf declaration a workspace's leaves are written in.

    leaves_path("pleme-io-opensource") #=> "workspaces/pleme-io-opensource/leaves.b"
"""
def leaves_path(workspace)
  "workspaces/#{workspace}/leaves.b"
end

@doc """
admission: whether a template is admitted: a leaf always; a fat one when admission is off, when it declares a typed skip reason, or when it already reconciled; a new fat one is refused naming its workspace's leaf declaration, and under :generate with a draft entry to commit.

    admission({fat: false}, nil, :enforce, true) #=> {verdict: "admit"}
"""
def admission(classification, skip, mode, never_reconciled, fix?)
  fix = fix or {}
  reason = if skip.nil?
    nil
  else
    skip_reason(skip)
  end
  if not classification[:fat]
    {verdict: "admit"}
  elsif mode == :off
    {verdict: "admitOff"}
  elsif reason != nil
    {verdict: "admitSkipped", reason:}
  elsif not never_reconciled
    {verdict: "admitGrandfathered"}
  else
    note = if skip.nil?
      "no #{skip_annotation} annotation"
    else
      "annotation #{skip_annotation}=`#{skip}` is not a typed world-fact reason"
    end
    path = leaves_path(fix[:workspace] or "<workspace>")
    head = "fat template refused at admission: #{to_s(classification[:leafKeys])} leaf key sets in one state (#{note}). Declare its leaves in pangea-architectures `#{path}` (one `leaves(...)` entry, rendered by `nix run .#render-leaves`; `pangea leaf plan` shows the split), or declare #{skip_annotation}=<#{join(skip_reasons, "|")}> (a world-fact, never time pressure), or set leaf.admission=off in the operator config"
    draft = if mode == :generate and fix[:draft] != nil
      join_lines(["", "entry for #{path}:", fix[:draft]])
    else
      ""
    end
    {verdict: "refuse", message: "#{head}#{draft}"}
  end
end

@doc """
ceil_div: whole-number division rounded up.

    ceil_div(1001, 1000) #=> 2
"""
def ceil_div(a, b)
  floor((a + b - 1) / b)
end

@doc """
p95: the nearest-rank 95th percentile of the newest 32 cycle times, or nil when there are none.

    p95(range(1, 21)) #=> 19
"""
def p95(samples)
  kept = drop(blue::max(size(samples) - 32, 0), samples)
  if is_empty(kept)
    nil
  else
    s = sort_keyed((x) -> x, kept)
    rank = blue::max(ceil_div(size(s) * 95, 100), 1)
    s[rank - 1]
  end
end

@doc """
bucket_up: a duration rounded up to the next whole second, so jitter under a second never moves the floor.

    bucket_up(1001) #=> 2000
"""
def bucket_up(ms)
  ceil_div(ms, 1000) * 1000
end

@doc """
without_nil: a record without the fields whose value is nil, as a status field omits them.

    without_nil({a: 1, b: nil}) #=> {a: 1}
"""
def without_nil(m)
  reduce(
    fn(acc, e)
      if e[1].nil?
        acc
      else
        assoc(acc, first(e), e[1])
      end
    end,
    {},
    map_entries(m)
  )
end

@doc """
ratchet: a template's next `status.leaf`: the leaf key count and cycle p95 measured, the floor that may only fall, and every regression past it (the p95 within a tolerance in percent).

    ratchet(nil, 5, true, 1000, 10)[:floor] #=> {cycleP95Ms: 1000, leafKeys: 5}
"""
def ratchet(prev, leaf_keys, fat, p95_ms, tolerance)
  p = if p95_ms.nil?
    nil
  else
    bucket_up(p95_ms)
  end
  floor_was = if prev.nil?
    nil
  else
    prev[:floor]
  end
  if floor_was.nil?
    without_nil(
      {
        leafKeys: leaf_keys,
        fat:,
        cycleP95Ms: p,
        floor: without_nil({leafKeys: leaf_keys, cycleP95Ms: p})
      }
    )
  else
    f = floor_was[:cycleP95Ms]
    grew = if leaf_keys > floor_was[:leafKeys]
      [{metric: "leafKeys", floor: floor_was[:leafKeys], now: leaf_keys}]
    else
      []
    end
    slow = if f != nil and p != nil and p > f + floor(f * tolerance / 100)
      [{metric: "cycleP95Ms", floor: f, now: p, tolerancePercent: tolerance}]
    else
      []
    end
    next_p = if f != nil and p != nil
      blue::min(f, p)
    else
      p or f
    end
    regressions = append(grew, slow)
    without_nil(
      {
        leafKeys: leaf_keys,
        fat:,
        cycleP95Ms: p,
        floor: without_nil(
          {
            leafKeys: blue::min(floor_was[:leafKeys], leaf_keys),
            cycleP95Ms: next_p
          }
        ),
        regressions: if is_empty(regressions)
          nil
        else
          regressions
        end
      }
    )
  end
end

@doc """
stall_after_ms: how long a planning or applying leaf may go without a heartbeat before it is stalled, unless the leaf says otherwise.

    stall_after_ms #=> 300000
"""
def stall_after_ms()
  300_000
end

@doc """
health: one leaf's verdict and alert verdict at a moment: rate limited until a time, failed, stalled when its heartbeat is older than its stall window, else its phase; failed and stalled leaves fire an alert.

    health({name: "a", phase: "Ready"}, 0) #=> {leaf: "a", state: {kind: "ready"}, alert: "none"}
"""
def health(leaf, now_ms)
  phase = leaf[:phase] or "Pending"
  beat = leaf[:heartbeat_at]
  window = leaf[:stall_after_ms] or stall_after_ms
  until_ms = leaf[:rate_limited_until]
  busy = member?(phase, %w[Planning Applying])
  state = if until_ms != nil and until_ms > now_ms
    {kind: "rateLimited", until: to_s(until_ms)}
  elsif phase == "Failed"
    without_nil(
      {kind: "failed", reason: leaf[:reason] or "Failed", since: leaf[:since]}
    )
  elsif busy and (beat.nil? or now_ms - beat > window)
    without_nil(
      {kind: "stalled", state: "heartbeatLost", since: beat and to_s(beat)}
    )
  elsif phase == "Ready"
    {kind: "ready"}
  elsif phase == "Applying"
    {kind: "applying"}
  else
    {kind: "planning"}
  end
  alert = if member?(state[:kind], %w[failed stalled])
    "firing"
  else
    "none"
  end
  {leaf: leaf[:name], state:, alert:}
end

@doc """
holding?: whether a leaf state holds its dependents back: failed, stalled or rate limited.

    holding?({kind: "stalled"}) #=> true
"""
def holding?(state)
  member?(state[:kind], %w[failed stalled rateLimited])
end

@doc """
counted: a status list capped at a number of names, with how many were left out.

    counted([1, 2, 3], 2) #=> [[1, 2], 1]
"""
def counted(xs, cap)
  [take(cap, xs), blue::max(size(xs) - cap, 0)]
end

@doc """
judge: the parent's partial state over its leaves: Partial when any leaf failed, stalled or is blocked by one that holds it, Converged when every leaf is ready, else Progressing; counts per state, and the held and blocked leaves named, up to a cap per list.

    judge([], 50)[:verdict] #=> "Converged"
"""
def judge(leaves, cap)
  sorted = sort_keyed((l) -> l[:name], leaves)
  known = map((l) -> l[:name], sorted)
  g = gurafu::graph(
    retsu::flat_map(
      sorted,
      fn(l)
        map(
          (u) -> [u, l[:name]],
          filter((u) -> member?(u, known), l[:upstreams] or [])
        )
      end
    ),
    {nodes: known}
  )
  back = gurafu::reverse(g)
  holds = filter((l) -> holding?(l[:state]), sorted)
  held_names = map((l) -> l[:name], holds)
  blocked_rows = retsu::flat_map(
    filter((l) -> not holding?(l[:state]), sorted),
    fn(l)
      by = filter(
        (n) -> member?(n, held_names),
        gurafu::reachable(back, l[:name])
      )
      if is_empty(by)
        []
      else
        [{leaf: l[:name], by:}]
      end
    end
  )
  blocked_names = map((b) -> b[:leaf], blocked_rows)
  free = filter((l) -> not member?(l[:name], blocked_names), sorted)
  of = (k) -> filter((l) -> l[:state][:kind] == k, free)
  failed = map(
    fn(l)
      without_nil(
        {leaf: l[:name], reason: l[:state][:reason], since: l[:state][:since]}
      )
    end,
    of("failed")
  )
  stalled = map(
    fn(l)
      without_nil(
        {leaf: l[:name], state: l[:state][:state], since: l[:state][:since]}
      )
    end,
    of("stalled")
  )
  limited = map(
    (l) -> {leaf: l[:name], until: l[:state][:until]},
    of("rateLimited")
  )
  counts = {
    ready: size(of("ready")),
    planning: size(of("planning")),
    applying: size(of("applying")),
    failed: size(failed),
    stalled: size(stalled),
    rateLimited: size(limited),
    blocked: size(blocked_rows)
  }
  lists = map(
    (xs) -> counted(xs, cap),
    [failed, stalled, limited, blocked_rows]
  )
  listed = fn(i)
    if is_empty(first(lists[i]))
      nil
    else
      first(lists[i])
    end
  end
  verdict = if counts[:failed] + counts[:stalled] + counts[:blocked] > 0
    "Partial"
  elsif counts[:ready] == size(sorted)
    "Converged"
  else
    "Progressing"
  end
  without_nil(
    {
      verdict:,
      total: size(sorted),
      counts:,
      failed: listed(0),
      stalled: listed(1),
      rateLimited: listed(2),
      blocked: listed(3),
      truncated: reduce((acc, p) -> acc + p[1], 0, lists)
    }
  )
end

@doc """
slice: a leaf's Terraform JSON cut from the whole render: only the resources and modules its addresses name, every other block kept whole.

    slice({"resource" => {"a" => {"x" => {}, "y" => {}}}}, ["a.x"]) #=> {"resource" => {"a" => {"x" => {}}}}
"""
def slice(rendered, addresses)
  stripped = map(strip_index, managed(addresses))
  modules = map(
    (a) -> steps(a)[1][:name],
    filter((a) -> starts_with?(a, "module."), managed(addresses))
  )
  pick = fn(block, keep?)
    reduce(
      fn(acc, e)
        if keep?(first(e))
          assoc(acc, first(e), e[1])
        else
          acc
        end
      end,
      {},
      map_entries(block)
    )
  end
  reduce(
    fn(acc, e)
      k = first(e)
      if k == "resource"
        kept = reduce(
          fn(by_type, t)
            names = pick(t[1], (n) -> member?("#{first(t)}.#{n}", stripped))
            if is_empty(map_entries(names))
              by_type
            else
              assoc(by_type, first(t), names)
            end
          end,
          {},
          map_entries(e[1])
        )
        assoc(acc, k, kept)
      elsif k == "module"
        assoc(acc, k, pick(e[1], (n) -> member?(n, modules)))
      else
        assoc(acc, k, e[1])
      end
    end,
    {},
    map_entries(rendered)
  )
end

@doc """
inputs: each leaf's input slice in the keyed form: the shared inputs and the collection cut to the one entry the leaf's key names; an entry with no key, or a key held twice, is refused.

    inputs({collection: "repos", key: "slug", shared: ["owner"]}, {"owner" => "o", "repos" => [{"slug" => "a"}]}) #=> {"a" => {"owner" => "o", "repos" => [{"slug" => "a"}]}}
"""
def inputs(declaration, values)
  checked(declaration, %i[collection key shared])
  coll = declaration[:collection]
  rows = get(values, coll)
  entries = if map?(rows)
    map(
      (e) -> [get(e[1], declaration[:key]) or first(e), e[1]],
      map_entries(rows)
    )
  elsif rows != nil and list?(rows)
    map((r) -> [get(r, declaration[:key]), r], rows)
  else
    raise(:bad_option, "leaf collection `#{coll}` is neither a list nor a map")
  end
  ks = map(first, entries)
  if member?(nil, ks)
    raise(:bad_key, "an entry of `#{coll}` has no `#{declaration[:key]}`")
  end
  if size(distinct(ks)) != size(ks)
    raise(:bad_key, "a key of `#{coll}` names two entries")
  end
  shared = reduce(
    (acc, f) -> assoc(acc, f, get(values, f)),
    {},
    declaration[:shared] or []
  )
  reduce(
    fn(acc, e)
      one = if map?(rows)
        {first(e) => e[1]}
      else
        [e[1]]
      end
      assoc(acc, first(e), assoc(shared, coll, one))
    end,
    {},
    entries
  )
end

@doc """
share_ok: a check that a value is a fraction from zero up to, not including, one.

    share_ok(1) #=> "1 is not a fraction in [0, 1)"
"""
def share_ok(v)
  if not number?(v) or v < 0 or v >= 1
    "#{to_s(v)} is not a fraction in [0, 1)"
  end
end

@doc """
count_ok: a check that a value is a whole number of at least a floor.

    count_ok(1)(0) #=> "0 is not a whole number of at least 1"
"""
def count_ok(lo)
  fn(v)
    if not integer?(v) or v < lo
      "#{to_s(v)} is not a whole number of at least #{to_s(lo)}"
    end
  end
end

@doc """
cap_schema: each leaf setting's fields: a cap, a share, a mode, the rate budget and the queue.

    size(map_entries(cap_schema)) #=> 10
"""
def cap_schema()
  {
    global: [required(field(:value, count_ok(1)))],
    workers: [required(field(:value, count_ok(1)))],
    per_workspace: [required(field(:value, count_ok(1)))],
    per_credential: [required(field(:value, count_ok(0)))],
    drift_share: [required(field(:value, share_ok))],
    priority: [required(field(:value, one_of(%i[on off])))],
    admission: [required(field(:value, one_of(%i[enforce off])))],
    engine: [required(field(:value, one_of(%i[blue rust])))],
    queue: [
      required(field(:value, one_of(%i[in_process jetstream]))),
      field(:nats_url, text)
    ],
    rate: [
      required(field(:budget_rph, count_ok(1))),
      required(field(:quota, share_ok)),
      field(:provider, text)
    ]
  }
end

@doc """
cap_defaults: the value each leaf setting takes when nothing declares it.

    cap_defaults[:global] #=> 16
"""
def cap_defaults()
  {
    global: 16,
    workers: 16,
    per_workspace: 4,
    per_credential: 8,
    drift_share: 0.5,
    priority: :on,
    admission: :enforce,
    engine: :blue,
    queue: :in_process,
    rate: {budget_rph: 5000, quota: 0.7}
  }
end

@doc """
cap_offs: the value each leaf setting takes when it is configured off: the monolithic or unpaced form, never a deletion.

    cap_offs[:drift_share] #=> 0
"""
def cap_offs()
  {
    global: 1,
    workers: 4,
    per_workspace: nil,
    per_credential: 0,
    drift_share: 0,
    priority: :off,
    admission: :off,
    engine: :rust,
    queue: :in_process,
    rate: {budget_rph: 5000, quota: 0}
  }
end

@doc """
setting: one leaf setting's entry: its kind is the setting, its name says where it came from.

    setting(:global, {value: 8}) #=> {entry: :global, name: "leaf", value: {value: 8}}
"""
def setting(kind, fields)
  entry(kind, "leaf", fields)
end

@doc """
caps: the leaf settings of §9 from a declaration of entries: each judged alone, a bad entry refused and its default kept, an entry configured off taking its off value; then the cross-entry rules, each refusing only its own entry.

    caps([setting(:global, {value: 8})])[:global] #=> 8
"""
def caps(declaration)
  j = kousei::judge(cap_schema, declaration)
  values = reduce(
    fn(acc, e)
      v = e[:value]
      assoc(
        acc,
        e[:entry],
        if e[:entry] == :rate or e[:entry] == :queue
          v
        else
          v[:value]
        end
      )
    end,
    cap_defaults,
    j[:accepted]
  )
  offed = reduce(
    (acc, e) -> assoc(acc, e[:entry], get(cap_offs, e[:entry])),
    values,
    j[:off]
  )
  queue = offed[:queue]
  q = if map?(queue)
    queue
  else
    {value: queue}
  end
  rate = offed[:rate]
  rules = [
    [
      offed[:workers] < offed[:global],
      :workers,
      "workers #{to_s(offed[:workers])} is below the global cap #{to_s(offed[:global])}, which would make the cap moot",
      cap_defaults[:workers]
    ],
    [
      q[:value] == :jetstream and q[:nats_url].nil?,
      :queue,
      "queue jetstream needs nats_url",
      :in_process
    ],
    [
      rate[:quota] == 0 and (rate[:provider] or "github") == "github",
      :rate,
      "an unpaced rate (quota 0) is refused for GitHub",
      cap_defaults[:rate]
    ]
  ]
  broken = filter(first, rules)
  fixed = reduce(
    (acc, r) -> assoc(acc, r[1], r[3]),
    assoc(offed, :queue, q[:value]),
    broken
  )
  assoc(
    assoc(
      assoc(
        fixed,
        :nats_url,
        if q[:value] == :jetstream and fixed[:queue] == :jetstream
          q[:nats_url]
        end
      ),
      :drift_share_permille,
      round(fixed[:drift_share] * 1000)
    ),
    :refusals,
    append(
      j[:refusals],
      map((r) -> [:invalid, "#{to_s(r[1])} leaf: #{r[2]}"], broken)
    )
  )
end

@doc """
same?: whether two values render as the same JSON, the form the operator's answers are recorded in.

    same?({kind: :keyed}, {"kind" => "keyed"}) #=> true
"""
def same?(a, b)
  json_stringify(a) == json_stringify(b)
end

@doc """
as_key: a recorded leaf key read back as happa writes it.

    as_key({"kind" => "module", "value" => "module.a"}) #=> {kind: :module, value: "module.a"}
"""
def as_key(k)
  {
    kind: nth(
      position(k["kind"], %w[keyed module address]),
      %i[keyed module address]
    ),
    value: k["value"]
  }
end

test "the empty state has no leaves, keys or work"
  assert split([], []) == []
  assert classify([], nil, nil)[:fat] == false
  assert bijection([], [])[:ok] == true
  assert changed({}, {}) == []
  assert admit([], {global: 4, per_scope: 4}, {}) == []
  assert drift_due([], 0, 1000) == []
  assert judge([], 50) ==
    {
      verdict: "Converged",
      total: 0,
      counts: {
        ready: 0,
        planning: 0,
        applying: 0,
        failed: 0,
        stalled: 0,
        rateLimited: 0,
        blocked: 0
      },
      truncated: 0
    }
  assert gurafu::nodes(graph([], [])) == []
end

test "a leaf key is the index key, else the top module, else the address"
  assert key("github_repository.repos[\"acude\"]") ==
    {kind: :keyed, value: "acude"}
  assert key("aws_instance.web[3]") == {kind: :keyed, value: "3"}
  assert key("module.net[\"east\"].aws_subnet.s[\"x\"]") ==
    {kind: :keyed, value: "east"}
  assert key("aws_s3_bucket.logs") ==
    {kind: :address, value: "aws_s3_bucket.logs"}
  assert key("x.y[\"a.b[1]\\\"c\"]") == {kind: :keyed, value: "a.b[1]\"c"}
  assert strip_index("module.m[\"k\"].a.b[2]") == "module.m.a.b"
  assert data?("data.aws_ami.x")
  assert not data?("aws_ami.x")
end

test "a malformed address raises, never a guess"
  assert raises?(:parse_error, () -> key(""))
  assert raises?(:parse_error, () -> key("a.b[\"x"))
  assert raises?(:parse_error, () -> key("a.b[1"))
  assert raises?(:parse_error, () -> key("a..b"))
  assert raises?(:parse_error, () -> key("a.b[1]c"))
end

test "split groups by key, joins along references and keeps the multiset"
  before = [
    "r.a[\"x\"]",
    "q.a[\"x\"]",
    "r.a[\"y\"]",
    "module.m.t.u",
    "plain.one",
    "data.z.w"
  ]
  leaves = split(
    before,
    [[{kind: :address, value: "plain.one"}, {kind: :module, value: "module.m"}]]
  )
  assert size(leaves) == 3
  assert map((l) -> l[:key], leaves) ==
    [
      {kind: :keyed, value: "x"},
      {kind: :keyed, value: "y"},
      {kind: :module, value: "module.m"}
    ]
  assert last(leaves)[:merged_from] == [{kind: :address, value: "plain.one"}]
  assert bijection(before, leaves)[:ok]
  dropped = [first(leaves), leaves[1], assoc(last(leaves), :addresses, [])]
  assert not bijection(before, dropped)[:ok]
  doubled = append(leaves, [{addresses: ["r.a[\"x\"]"]}])
  assert not bijection(before, doubled)[:disjoint]
  assert raises?(:refused, () -> split(%w[a.b a.b], []))
end

test "the multiset hash ignores order and cannot be forged by concatenation"
  assert multiset_hash(%w[a b c]) == multiset_hash(%w[c a b])
  assert multiset_hash(%w[a b c]) != multiset_hash(%w[a b d])
  assert multiset_hash(%w[ab c]) != multiset_hash(%w[a bc])
end

test "names are DNS labels, suffixed only when slugs collide or run long"
  assert names(
    "r",
    [{kind: :keyed, value: "a_b"}, {kind: :keyed, value: "a-b"}]
  ) != %w[r-a-b r-a-b]
  long = names(
    "r",
    [{kind: :keyed, value: join(map((_i) -> "x", range(100)), "")}]
  )
  assert size(chars(first(long))) <= 63
  assert names("r", [{kind: :keyed, value: "///"}]) == ["r-leaf"]
end

test "the digest ignores key order, sees values and keeps its three parts apart"
  assert digest({x: 1, y: {b: 2, a: 3}}, nil, nil) ==
    digest({y: {a: 3, b: 2}, x: 1}, nil, nil)
  assert digest({x: 1}, nil, nil) != digest({x: 2}, nil, nil)
  assert digest({k: 1}, nil, nil) != digest(nil, {k: 1}, nil)
  assert changed(
    {"new" => "d1", "same" => "d1", "moved" => "d1"},
    {"same" => "d1", "moved" => "d0"}
  ) == ["moved"]
end

test "the leaf graph orders upstreams first and refuses a cycle by name"
  g = graph(%w[app db vpc], [%w[app db], %w[db vpc]])
  assert order(g) == %w[vpc db app]
  assert destroy_order(g) == %w[app db vpc]
  assert upstreams(g, "app") == ["db"]
  assert dependents(g, ["vpc"]) == %w[app db]
  e = begin
    graph(%w[root x y], [%w[x root], %w[x y], %w[y x]])
  rescue err
    err
  end
  assert e.kind == :refused
  assert e.data[:stuck] == %w[x y]
  assert e.message == "a leaf cycle: x -> y -> x"
end

test "a mock lets a plan through but never an apply"
  assert blocked([{leaf: "u1", mock: true}], [], false) == []
  assert blocked([{leaf: "u1", mock: true}], [], true) == ["u1"]
  assert blocked([{leaf: "u2"}, {leaf: "u1"}], ["u1"], false) == ["u2"]
end

test "twenty drift-due leaves and one changed leaf with four slots admit the changed leaf first"
  drift = map(
    fn(i)
      {
        name: "drift-#{to_s(i)}",
        scope: "ws",
        credential: "gh",
        class: :drift,
        depth: 0,
        since: 100 - i
      }
    end,
    range(20)
  )
  changed_leaf = {
    name: "changed",
    scope: "ws",
    credential: "gh",
    class: :change,
    depth: 1,
    since: 0
  }
  limits = {
    global: 16,
    per_scope: 4,
    per_credential: 8,
    drift_share_permille: 500,
    priority: :on
  }
  got = admit(append(drift, [changed_leaf]), limits, {})
  assert first(got) == "changed"
  assert size(got) == 3
  assert drift_slots(1, 500) == 1
  assert drift_slots(10, 0) == 0
end

test "over an hour every leaf is due once, and no minute holds more than its share"
  interval = 3600
  leaves = map(
    (i) -> {name: "pleme-io-github-repos-#{to_s(i)}", last_check: nil},
    range(1023)
  )
  placed = offsets(map((l) -> l[:name], leaves), interval)
  firsts = map((e) -> e[1], map_entries(placed))
  per_minute = map(
    (m) -> size(filter((o) -> floor(o / 60) == m, firsts)),
    range(60)
  )
  assert reduce((a, b) -> a + b, 0, per_minute) == 1023
  assert every?((n) -> n <= ceil_div(1023, 60) + 1, per_minute)
  at = 1800
  assert size(drift_due(leaves, at, interval)) ==
    size(filter((o) -> o <= at, firsts))
  checked_now = map((l) -> assoc(l, :last_check, at), leaves)
  assert drift_due(checked_now, at, interval) == []
  assert drift_due(checked_now, at + 1, interval) ==
    map(first, filter((e) -> e[1] == at + 1, map_entries(placed)))
  assert size(drift_due(checked_now, at + interval, interval)) == 1023
  assert drift_due([], 10, 60) == []
end

test "admission refuses only a new fat template and names the remedies"
  fat = classify(["a.b[\"x\"]", "a.b[\"y\"]", "a.b[\"z\"]"], nil, nil)
  r = admission(fat, nil, :enforce, true)
  assert r[:verdict] == "refuse"
  assert contains?(r[:message], "pangea leaf plan")
  assert contains?(r[:message], "workspaces/<workspace>/leaves.b")
  g = admission(
    fat,
    nil,
    :generate,
    true,
    {workspace: "w", draft: "leaves(\"x\")"}
  )
  assert ends_with?(
    g[:message],
    join_lines(["", "entry for workspaces/w/leaves.b:", "leaves(\"x\")"])
  )
  assert contains?(r[:message], "3 leaf key sets")
  assert admission(fat, "provider-singleton: one account", :enforce, true) ==
    {verdict: "admitSkipped", reason: "provider-singleton"}
  assert admission(fat, nil, :off, true) == {verdict: "admitOff"}
  assert admission(fat, nil, :enforce, false) == {verdict: "admitGrandfathered"}
  assert contains?(
    admission(fat, "no-time", :enforce, true)[:message],
    "not a typed world-fact reason"
  )
end

test "the ratchet floor only falls, and a regression past tolerance is named"
  first_seen = ratchet(nil, 5, true, 1000, 10)
  assert first_seen[:floor] == {leafKeys: 5, cycleP95Ms: 1000}
  worse = ratchet(first_seen, 6, true, 1200, 10)
  assert map((r) -> r[:metric], worse[:regressions]) == %w[leafKeys cycleP95Ms]
  assert worse[:floor] == {leafKeys: 5, cycleP95Ms: 1000}
  assert ratchet(first_seen, 4, true, 1000, 10)[:floor][:leafKeys] == 4
  assert p95([]).nil?
  assert p95(range(100)) == 98
end

test "health names a stall, a failure and a rate limit, and only the first two fire"
  assert get(
    health({name: "a", phase: "Planning", heartbeat_at: 0}, 400_000),
    :state
  ) == {kind: "stalled", state: "heartbeatLost", since: "0"}
  assert get(
    health({name: "a", phase: "Planning", heartbeat_at: 300_000}, 400_000),
    :state
  ) == {kind: "planning"}
  assert get(
    health({name: "a", phase: "Failed", reason: "ImportAbsent"}, 0),
    :alert
  ) == "firing"
  limited = health(
    {name: "a", phase: "Planning", heartbeat_at: 0, rate_limited_until: 900},
    100
  )
  assert limited[:state] == {kind: "rateLimited", until: "900"}
  assert limited[:alert] == "none"
  assert health({name: "a", phase: "Applying", heartbeat_at: 10}, 20)[:state] ==
    {kind: "applying"}
end

test "one failed leaf makes the parent partial, names it and blocks only its dependents"
  r = judge(
    [
      {name: "a", state: {kind: "ready"}, upstreams: []},
      {
        name: "b",
        state: {kind: "failed", reason: "ImportAbsent"},
        upstreams: []
      },
      {name: "c", state: {kind: "ready"}, upstreams: ["b"]},
      {name: "d", state: {kind: "planning"}, upstreams: ["c"]}
    ],
    50
  )
  assert r[:verdict] == "Partial"
  assert r[:failed] == [{leaf: "b", reason: "ImportAbsent"}]
  assert r[:blocked] == [{leaf: "c", by: ["b"]}, {leaf: "d", by: ["b"]}]
  assert r[:counts][:ready] == 1
  assert get(
    judge([{name: "a", state: {kind: "planning"}, upstreams: []}], 50),
    :verdict
  ) == "Progressing"
end

test "slice keeps a leaf's own resources and inputs cut the collection to its entry"
  rendered = {
    "terraform" => {"required_providers" => {}},
    "resource" => {
      "github_repository" => {
        "acude" => {"name" => "acude"},
        "annai" => {"name" => "annai"}
      },
      "github_branch_protection" => {"acude_main" => {}}
    },
    "module" => {"teams" => {}, "vpc" => {}}
  }
  cut = slice(rendered, %w[github_repository.acude module.teams.github_team.t])
  assert cut ==
    {
      "module" => {"teams" => {}},
      "resource" => {"github_repository" => {"acude" => {"name" => "acude"}}},
      "terraform" => {"required_providers" => {}}
    }
  decl = {collection: "repos", key: "slug", shared: ["owner"]}
  got = inputs(
    decl,
    {"owner" => "o", "x" => 1, "repos" => [{"slug" => "a"}, {"slug" => "b"}]}
  )
  assert got["b"] == {"owner" => "o", "repos" => [{"slug" => "b"}]}
  assert raises?(
    :bad_key,
    () -> inputs(decl, {"repos" => [{"slug" => "a"}, {"slug" => "a"}]})
  )
  assert raises?(:bad_key, () -> inputs(decl, {"repos" => [{"name" => "a"}]}))
  assert raises?(:bad_option, () -> inputs(decl, {"repos" => "a"}))
end

test "each setting is judged alone: a bad one keeps its default, an off one its off value"
  c = caps(
    [
      setting(:global, {value: 0}),
      setting(:per_credential, {value: 2}),
      off(:drift_share, "leaf"),
      setting(:drift_share, {value: 0.25}),
      setting(:queue, {value: :jetstream}),
      setting(:rate, {budget_rph: 12500, quota: 0})
    ]
  )
  assert c[:global] == 16
  assert c[:per_credential] == 2
  assert c[:drift_share] == 0
  assert c[:drift_share_permille] == 0
  assert c[:queue] == :in_process
  assert c[:rate] == {budget_rph: 5000, quota: 0.7}
  assert size(c[:refusals]) == 3
  assert caps([])[:drift_share_permille] == 500
  assert caps([setting(:workers, {value: 4})])[:workers] == 16
  assert get(
    caps([setting(:queue, {value: :jetstream, nats_url: "nats://n:4222"})]),
    :nats_url
  ) == "nats://n:4222"
end

test "differential: every word equals its pangea-leaf source on the 1,024-repository address set"
  load = fn(file)
    roots = append(
      blue::split(getenv("BLUE_PATH", ""), ":"),
      [path_join(cwd, "bidamas"), cwd]
    )
    json_read(
      read_file(
        first(
          filter(
            is_file?,
            map((r) -> path_join(r, "happa/differential/#{file}"), roots)
          )
        )
      )
    )
  end
  input = load("inputs.json")
  want = load("oracle.json")
  addrs = input["addresses"]
  assert size(addrs) == 2061
  assert same?(map(key, addrs), want["keys"])
  assert map(
    fn(a)
      begin
        key(a)
      rescue e
        e.message
      end
    end,
    input["bad_addresses"]
  ) == want["bad_addresses"]
  leaves = split(
    addrs,
    map((r) -> [as_key(first(r)), as_key(r[1])], input["refs"])
  )
  assert size(leaves) == 1028
  assert same?(leaves, want["leaves"])
  assert same?(bijection(addrs, leaves), want["bijection"])
  ks = map((l) -> l[:key], leaves)
  named = names(input["base"], ks)
  assert same?(
    map((i) -> [ks[i], named[i]], range(size(ks))),
    want["names_of_leaves"]
  )
  assert same?(
    map(
      (c) -> classify(c["addresses"], c["p95"], c["budget"]),
      input["classify"]
    ),
    want["classify"]
  )
  assert same?(
    map((n) -> names(n["base"], map(as_key, n["keys"])), input["names"]),
    want["names"]
  )
  assert map((d) -> digest(first(d), d[1], d[2]), input["digests"]) ==
    want["digests"]
end

test "differential: change, schedule and verdict words equal their pangea-leaf sources"
  load = fn(file)
    roots = append(
      blue::split(getenv("BLUE_PATH", ""), ":"),
      [path_join(cwd, "bidamas"), cwd]
    )
    json_read(
      read_file(
        first(
          filter(
            is_file?,
            map((r) -> path_join(r, "happa/differential/#{file}"), roots)
          )
        )
      )
    )
  end
  input = load("inputs.json")
  want = load("oracle.json")
  assert map(
    fn(rows)
      current = reduce((acc, r) -> assoc(acc, first(r), r[2]), {}, rows)
      recorded = reduce(
        (acc, r) -> assoc(acc, first(r), r[1]),
        {},
        filter((r) -> r[1] != nil, rows)
      )
      changed(current, recorded)
    end,
    input["changed"]
  ) == want["changed"]
  assert map(
    fn(c)
      blocked(
        map((u) -> {leaf: u["template"], mock: u["has_mock"]}, c["upstreams"]),
        c["ready"],
        c["applying"]
      )
    end,
    input["blocked"]
  ) == want["blocked"]
  assert same?(
    map(
      fn(c)
        mode = nth(
          position(c["mode"], %w[generate enforce off]),
          %i[generate enforce off]
        )
        admission(
          {fat: c["leaf_keys"] > 1, leafKeys: c["leaf_keys"]},
          c["skip"],
          mode,
          c["never_reconciled"],
          {workspace: c["workspace"], draft: c["draft"]}
        )
      end,
      input["admission"]
    ),
    want["admission"]
  )
  assert map(
    fn(c)
      drift_due(
        map((l) -> {name: l["name"], last_check: l["last_check"]}, c["leaves"]),
        c["now"],
        c["interval"]
      )
    end,
    input["drift"]
  ) == want["drift"]
  assert same?(
    map(
      fn(c)
        prev = c["prev"]
        was = if prev.nil? or prev["floor"].nil?
          nil
        else
          {
            floor: {
              leafKeys: prev["floor"]["leafKeys"],
              cycleP95Ms: prev["floor"]["cycleP95Ms"]
            }
          }
        end
        ratchet(was, c["leaf_keys"], c["fat"], c["p95"], c["tolerance"])
      end,
      input["ratchet"]
    ),
    want["ratchet"]
  )
  assert map(p95, input["p95"]) == want["p95"]
  assert same?(
    map(
      fn(rows)
        names_in = distinct(
          retsu::flat_map(rows, (r) -> append([first(r)], r[1]))
        )
        refs = retsu::flat_map(rows, (r) -> map((u) -> [first(r), u], r[1]))
        begin
          {order: order(graph(names_in, refs))}
        rescue err
          {stuck: err.data[:stuck]}
        end
      end,
      input["dags"]
    ),
    want["dags"]
  )
  assert map(
    fn(c)
      k = c["caps"]
      f = c["in_flight"]
      limits = {
        global: k["global"],
        per_scope: k["per_scope"],
        scope_caps: k["scope_caps"] or {},
        per_credential: k["per_credential"] or 0,
        drift_share_permille: k["drift_share_permille"] or 500,
        priority: if k["priority"] == "off"
          :off
        else
          :on
        end
      }
      cands = map(
        fn(x)
          {
            name: x["name"],
            scope: x["scope"],
            credential: x["credential"],
            class: nth(
              position(x["class"], %w[apply change unblocked retry drift]),
              classes
            ),
            depth: x["depth"],
            since: x["since"]
          }
        end,
        c["candidates"]
      )
      admit(
        cands,
        limits,
        {
          total: f["total"] or 0,
          by_scope: f["by_scope"] or {},
          drift_by_scope: f["drift_by_scope"] or {},
          by_credential: f["by_credential"] or {}
        }
      )
    end,
    input["admit"]
  ) == want["admit"]
  assert same?(
    map(
      fn(c)
        judge(
          map(
            fn(l)
              s = l["state"]
              {
                name: l["name"],
                upstreams: l["upstreams"],
                state: without_nil(
                  {
                    kind: s["kind"],
                    reason: s["reason"],
                    since: s["since"],
                    state: s["state"],
                    until: s["until"]
                  }
                )
              }
            end,
            c["leaves"]
          ),
          c["cap"]
        )
      end,
      input["judge"]
    ),
    want["judge"]
  )
end
