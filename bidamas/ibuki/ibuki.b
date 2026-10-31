@moduledoc """
ibuki (息吹) — the plane an app docks into, as pure decisions: the five structural classes and a docking check over the reach `blue lock` measured, the Flash channel's token bucket, the Tide channel's LEDBAT controller, and a Strand, a last-writer-wins map whose every transition is a hash-linked record of its input and output roots.

Every word answers a new value and reaches no host; time is passed in as `now_ms`. The design and what is not built: `theory/IBUKI.md`.

    dock({state: :merge}, {capabilities: {floor: [], packages: {}}}).class #=> :strand
"""

use("jisho", [:has?])
use("kyohi", %i[raised refusal])
use("moji", [:checked])
use("ran", %i[seeds take_ints])
use("retsu", %i[first is_empty last size])
use("shomei", %i[chain genesis hash_message intact? is_hash_hex])
use("shuugou", %i[difference intersection ordered subset?])

@doc """
classes: the five structural classes of the plane, in order, each with the host capabilities its ceiling admits.

    map((c) -> c.name, classes) #=> %i[crystal strand airlock nomad synod]
"""
def classes()
  [
    {
      name: :crystal,
      numeral: "I",
      ceiling: [],
      holds: "a pure computation, cached by its def_hash"
    },
    {
      name: :strand,
      numeral: "II",
      ceiling: ["filesystem"],
      holds: "a convergent state whose transitions are hash-linked records"
    },
    {
      name: :airlock,
      numeral: "III",
      ceiling: %w[clock entropy network],
      holds: "a two-party rendezvous held to the meet of both ceilings, with no disk"
    },
    {
      name: :nomad,
      numeral: "IV",
      ceiling: %w[clock network],
      holds: "a process on idle capacity that yields and moves with its code and state"
    },
    {
      name: :synod,
      numeral: "V",
      ceiling: %w[entropy network],
      holds: "a k-of-n authority whose key is never whole on one machine"
    }
  ]
end

@doc """
class_named: the class record of a class name, or a :not_found raise naming the five.

    class_named(:nomad).numeral #=> "IV"
"""
def class_named(name)
  c = retsu::find_first((k) -> k.name == name, classes)
  if c.nil?
    raise(
      :not_found,
      "no class #{to_s(name)}; the classes are crystal, strand, airlock, nomad and synod"
    )
  end
  c
end

@doc """
threshold_ok: a k-of-n threshold when 1 <= k <= n and n >= 2, else a :bad_option raise.

    threshold_ok([2, 3]) #=> [2, 3]
"""
def threshold_ok(t)
  if not list?(t) or t.nil? or size(t) != 2
    raise(:bad_option, "a threshold is a pair [k, n], got #{to_s(t)}")
  end
  k = first(t)
  n = last(t)
  if not integer?(k) or not integer?(n) or n < 2 or k < 1 or k > n
    raise(
      :bad_option,
      "a threshold [k, n] needs 1 <= k <= n and n >= 2, got #{to_s(t)}"
    )
  end
  t
end

@doc """
classify: the class a program's shape belongs to: a threshold makes a synod, two parties an airlock, moving a nomad, merged state a strand, and none of these a crystal.

    classify({state: :merge}) #=> :strand
"""
def classify(shape)
  checked(shape, %i[migrates parties state threshold])
  parties = shape[:parties] or 1
  if not shape[:threshold].nil?
    threshold_ok(shape[:threshold])
    :synod
  elsif parties == 2
    :airlock
  elsif parties != 1
    raise(
      :bad_option,
      "#{to_s(parties)} parties without a threshold is no class: a rendezvous has two, a synod names [k, n]"
    )
  elsif shape[:migrates] == true
    :nomad
  elsif shape[:state] == :merge
    :strand
  else
    :crystal
  end
end

@doc """
reach: the host capabilities a locked program reaches through the host: the join of floors `blue lock` recorded, less each capability a provider serves for the whole program or for every package whose floor needs it.

    reach({capabilities: {floor: %w[clock network], provided: {clock: {provider: "deterministic-stepped"}}}}) #=> ["network"]
"""
def reach(lock)
  caps = json_read(json_stringify(lock))["capabilities"]
  if caps.nil?
    raise(
      :not_found,
      "the lock has no capabilities record: declare allow(...) at the root and run blue lock"
    )
  end
  floors = map_entries(caps["packages"] or {})
  served = map(
    first,
    filter(
      fn(e)
        scope = last(e)["for"]
        needers = map(first, filter((p) -> member?(first(e), last(p)), floors))
        scope.nil? or subset?(needers, scope)
      end,
      map_entries(caps["provided"] or {})
    )
  )
  ordered(difference(caps["floor"] or [], served))
end

@doc """
admit: the refusals of a reach under a class's ceiling, one :denied per capability past it; empty when the reach fits.

    admit(:crystal, []) #=> []
"""
def admit(name, reached)
  ceiling = class_named(name).ceiling
  map(
    fn(cap)
      refusal(
        :denied,
        "#{to_s(name)} reaches #{cap}, past its ceiling #{to_s(ceiling)}"
      )
    end,
    ordered(difference(reached, ceiling))
  )
end

@doc """
dock: the docking verdict for a shape and a lock: its class, the reach the lock measured, and the refusals of that reach under the class's ceiling.

    dock({}, {capabilities: {floor: ["network"]}}).refusals #=> [[:denied, "crystal reaches network, past its ceiling []"]]
"""
def dock(shape, lock)
  name = classify(shape)
  reached = reach(lock)
  {class: name, reach: reached, refusals: admit(name, reached)}
end

@doc """
airlock_frame: the frame two parties meet in: the capabilities both ceilings grant, never the filesystem.

    airlock_frame(%w[clock filesystem network], %w[network filesystem]) #=> ["network"]
"""
def airlock_frame(a, b)
  ordered(difference(intersection(a, b), ["filesystem"]))
end

@doc """
flash: a Flash channel's token bucket: `rate` bytes a second (16384), a `burst` it may spend at once (one second's worth), packets of at most `mtu` bytes (1280), starting full at `at_ms` (0).

    flash({}).mtu #=> 1280
"""
def flash(opts)
  checked(opts, %i[at_ms burst mtu rate])
  rate = opts[:rate] or 16384
  mtu = opts[:mtu] or 1280
  burst = opts[:burst] or rate
  if not integer?(rate) or rate < 1
    raise(
      :bad_option,
      "a Flash rate is a positive Int of bytes a second, got #{to_s(rate)}"
    )
  end
  if not integer?(mtu) or mtu < 1 or mtu > 1280
    raise(
      :bad_option,
      "a Flash MTU is 1 to 1280 bytes, the IPv6 minimum link MTU, got #{to_s(mtu)}"
    )
  end
  if not integer?(burst) or burst < mtu
    raise(
      :bad_option,
      "a Flash burst below the MTU never sends a full packet, got #{to_s(burst)}"
    )
  end
  at = opts[:at_ms] or 0
  {rate:, mtu:, burst:, tokens: burst * 1000, at_ms: at}
end

@doc """
refill: a bucket's tokens, in thousandths of a byte, at `now_ms`; a clock that steps back adds nothing.

    refill(flash({}), 99).tokens #=> 16384000
"""
def refill(bucket, now_ms)
  elapsed = blue::max(0, now_ms - bucket.at_ms)
  {
    **bucket,
    tokens: blue::min(
      bucket.burst * 1000,
      bucket.tokens + bucket.rate * elapsed
    ),
    at_ms: blue::max(now_ms, bucket.at_ms)
  }
end

@doc """
flash_send: the bucket's verdict on a packet at `now_ms`: :sent with the spent bucket, :wait with the milliseconds until it can send, or :refused past the MTU.

    flash_send(flash({}), 1280, 0).verdict #=> :sent
"""
def flash_send(bucket, bytes, now_ms)
  b = refill(bucket, now_ms)
  cost = bytes * 1000
  if bytes > b.mtu
    {
      verdict: :refused,
      bucket: b,
      why: "#{to_s(bytes)} bytes is past the Flash MTU of #{to_s(b.mtu)}"
    }
  elsif cost <= b.tokens
    {verdict: :sent, bucket: {**b, tokens: b.tokens - cost}}
  else
    {verdict: :wait, bucket: b, wait_ms: ceiling((cost - b.tokens) / b.rate)}
  end
end

@doc """
tide: a Tide channel's LEDBAT controller (RFC 6817): a `target_ms` of queuing delay (100), `gain` (1), `mss` (1280), `min_cwnd` and `init_cwnd` packets (2), `allowed_increase` packets an ack (1), `base_minutes` of base-delay history (10), a `filter` of current delays (4), and `collapse_ms` (2): at that queuing delay the window falls to its floor; `collapse_ms: nil` configures it off.

    tide({}).cwnd #=> 2560
"""
def tide(opts)
  checked(
    opts,
    %i[
      allowed_increase
      base_minutes
      collapse_ms
      filter
      gain
      init_cwnd
      min_cwnd
      mss
      target_ms
    ]
  )
  mss = opts[:mss] or 1280
  min_cwnd = opts[:min_cwnd] or 2
  init_cwnd = opts[:init_cwnd] or 2
  target = opts[:target_ms] or 100
  if not integer?(min_cwnd) or min_cwnd < 1
    raise(
      :bad_option,
      "a Tide window under one packet never sends, so it never measures delay again; got min_cwnd #{to_s(min_cwnd)}"
    )
  end
  if not integer?(target) or target < 1
    raise(
      :bad_option,
      "a Tide target is a positive Int of milliseconds, got #{to_s(target)}"
    )
  end
  if init_cwnd < min_cwnd
    raise(
      :bad_option,
      "a Tide's initial window #{to_s(init_cwnd)} is under its floor #{to_s(min_cwnd)}"
    )
  end
  collapse = if has?(opts, :collapse_ms)
    opts[:collapse_ms]
  else
    2
  end
  {
    target_ms: target,
    gain: opts[:gain] or 1,
    mss:,
    min_cwnd:,
    allowed_increase: opts[:allowed_increase] or 1,
    base_minutes: opts[:base_minutes] or 10,
    filter: opts[:filter] or 4,
    collapse_ms: collapse,
    cwnd: init_cwnd * mss,
    base: [],
    current: []
  }
end

@doc """
newest: the last `keep` items of a list, all of them when it is shorter.

    newest([1, 2, 3], 2) #=> [2, 3]
"""
def newest(xs, keep)
  retsu::drop_n(xs, blue::max(0, size(xs) - keep))
end

@doc """
base_update: the per-minute minima of one-way delay, the newest `keep` minutes, after a sample at `minute`.

    base_update([[0, 50]], 0, 40, 10) #=> [[0, 40]]
"""
def base_update(base, minute, delay, keep)
  if is_empty(base) or first(last(base)) != minute
    newest(retsu::push(base, [minute, delay]), keep)
  else
    retsu::push(
      retsu::all_but_last(base),
      [minute, blue::min(last(last(base)), delay)]
    )
  end
end

@doc """
floor_window: the smallest window a Tide keeps, in bytes.

    floor_window(tide({})) #=> 2560
"""
def floor_window(t)
  t.min_cwnd * t.mss
end

@doc """
queuing: the queuing delay a Tide last measured: the least of its current delays less its base delay, nil before any sample.

    queuing(tide_ack(tide({}), {delay_ms: 30, bytes: 1280, now_ms: 0})) #=> 0
"""
def queuing(t)
  if is_empty(t.current)
    nil
  else
    apply(blue::min, t.current) - apply(blue::min, map(last, t.base))
  end
end

@doc """
tide_ack: the Tide after an ack of `bytes` with a one-way `delay_ms` at `now_ms`: the window moves toward the target queuing delay, at most `allowed_increase` packets past `flight`, never under its floor, and falls to the floor at `collapse_ms`.

    tide_ack(tide({collapse_ms: nil}), {delay_ms: 50, bytes: 1280, now_ms: 0}).cwnd #=> 3200
"""
def tide_ack(t, ack)
  checked(ack, %i[bytes delay_ms flight now_ms])
  measured = {
    **t,
    base: base_update(
      t.base,
      floor(ack.now_ms / 60000),
      ack.delay_ms,
      t.base_minutes
    ),
    current: newest(retsu::push(t.current, ack.delay_ms), t.filter)
  }
  q = queuing(measured)
  lowest = floor_window(t)
  if not t.collapse_ms.nil? and q >= t.collapse_ms
    {**measured, cwnd: lowest}
  else
    flight = ack[:flight] or t.cwnd
    grown = t.cwnd +
      floor(
        t.gain * (t.target_ms - q) * ack.bytes * t.mss / (t.target_ms * t.cwnd)
      )
    {
      **measured,
      cwnd: blue::max(
        lowest,
        blue::min(grown, flight + t.allowed_increase * t.mss)
      )
    }
  end
end

@doc """
tide_loss: the Tide after a loss: its window halved, never under its floor.

    tide_loss({**tide({}), cwnd: 12800}).cwnd #=> 6400
"""
def tide_loss(t)
  {**t, cwnd: blue::min(t.cwnd, blue::max(floor(t.cwnd / 2), floor_window(t)))}
end

@doc """
wins?: whether one register cell beats another: the later `at`, then the greater writer, then the greater value text, so every two replicas pick the same cell.

    wins?({at: 2, by: "a", v: 1}, {at: 1, by: "z", v: 9}) #=> true
"""
def wins?(a, b)
  if b.nil?
    true
  elsif a.at != b.at
    a.at > b.at
  elsif a.by != b.by
    compare(a.by, b.by) > 0
  else
    compare(json_stringify(a.v), json_stringify(b.v)) > 0
  end
end

@doc """
put: a last-writer-wins map with one key written, when the cell wins over the one it holds.

    put({}, "k", 1, 5, "r1")["k"].v #=> 1
"""
def put(state, key, value, at, by)
  if not string?(key) or not integer?(at) or not string?(by)
    raise(
      :bad_option,
      "a write is a text key, an Int stamp and a text writer, got #{to_s([key, at, by])}"
    )
  end
  cell = {at:, by:, v: value}
  if wins?(cell, get(state, key))
    assoc(state, key, cell)
  else
    state
  end
end

@doc """
merge: two last-writer-wins maps joined: each key holds the winning cell of either; commutative, associative and idempotent.

    merge({}, {}) #=> {}
"""
def merge(a, b)
  reduce(
    fn(acc, e)
      if wins?(last(e), get(acc, first(e)))
        assoc(acc, first(e), last(e))
      else
        acc
      end
    end,
    a,
    map_entries(b)
  )
end

@doc """
state_root: the Merkle root of a map's cells in key order, written b3:<hex>.

    state_root({}) == "b3:#{shomei::root([])}" #=> true
"""
def state_root(state)
  "b3:#{shomei::root(map(json_stringify, map_entries(state)))}"
end

@doc """
strand: an empty Strand under a protocol label (`lww-map/1`), naming its transition's engine `def_hash`: the caller's, else the engine's identity of `step` as `def_hash` reads it, which is nil where the engine identifies no program.

    strand({}).seq #=> 0
"""
def strand(opts)
  checked(opts, %i[def_hash protocol])
  d = opts[:def_hash] or def_hash(step)
  if not d.nil? and
      not (
        string?(d) and
        starts_with?(d, "b3:") and
        is_hash_hex(replace(d, "b3:", ""))
      )
    raise(:bad_option, "a def_hash is b3:<64 hex>, got #{to_s(d)}")
  end
  protocol = opts[:protocol] or "lww-map/1"
  start = genesis("ibuki-strand/#{protocol}")
  {
    protocol:,
    def_hash: d,
    genesis: start,
    head: start,
    seq: 0,
    state: {},
    record: nil
  }
end

@doc """
written: the map one Strand op leaves: a :put written in, a :merge joined, anything else a :bad_option raise.

    written({}, {op: :merge, state: {}}) #=> {}
"""
def written(state, op)
  if op.op == :put
    put(state, op.key, op.value, op.at, op.by)
  elsif op.op == :merge
    merge(state, op.state)
  else
    raise(:bad_option, "a Strand op is :put or :merge, got #{to_s(op.op)}")
  end
end

@doc """
steps_between: how many keys hold a different cell after a transition than before it.

    steps_between({}, put({}, "k", 1, 1, "r")) #=> 1
"""
def steps_between(before, after)
  size(filter((e) -> get(before, first(e)) != last(e), map_entries(after)))
end

@doc """
step: the Strand after one op, `{op: :put, key:, value:, at:, by:}` or `{op: :merge, state:}`, with the record that links it: its input and output roots, the op's hash, the cells it wrote and the previous head.

    step(strand({}), {op: :put, key: "k", value: 1, at: 1, by: "r"}).record.steps #=> 1
"""
def step(s, op)
  after = written(s.state, op)
  record = {
    format: "ibuki-strand",
    version: 1,
    protocol: s.protocol,
    def_hash: s.def_hash,
    seq: s.seq + 1,
    prev: s.head,
    op: "b3:#{hash_message(json_stringify(op))}",
    input_root: state_root(s.state),
    output_root: state_root(after),
    steps: steps_between(s.state, after)
  }
  {
    **s,
    head: chain(s.head, json_stringify(record)),
    seq: s.seq + 1,
    state: after,
    record:
  }
end

@doc """
records: every record a run of ops writes onto a Strand, in order.

    records(strand({}), []) #=> []
"""
def records(s, ops)
  last(
    reduce(
      fn(acc, op)
        moved = step(first(acc), op)
        [moved, retsu::push(last(acc), moved.record)]
      end,
      [s, []],
      ops
    )
  )
end

@doc """
replay: the Strand after every op, in order.

    replay(strand({}), []).seq #=> 0
"""
def replay(s, ops)
  reduce(step, s, ops)
end

@doc """
verify?: whether records link from a Strand's genesis to `head`, each naming the head before it.

    verify?(strand({}), [], strand({}).head) #=> true
"""
def verify?(s, rs, head)
  heads = reduce(
    (acc, r) -> retsu::push(acc, chain(last(acc), json_stringify(r))),
    [s.genesis],
    rs
  )
  prevs_ok = every?((i) -> rs[i].prev == heads[i], range(size(rs)))
  prevs_ok and intact?(s.genesis, map(json_stringify, rs), head)
end

@doc """
random_state: a last-writer-wins map drawn from a seed: n writes over `keys` keys by three writers.

    size(map_entries(random_state(3, 4, 2))) <= 2 #=> true
"""
def random_state(seed, n, keys)
  ks = take_ints(seed, keys, n)
  ats = take_ints(seeds(seed, 2)[1], 5, n)
  bys = take_ints(seeds(seed, 3)[2], 3, n)
  vs = take_ints(seeds(seed, 4)[3], 4, n)
  reduce(
    (acc, i) -> put(acc, "k#{ks[i]}", vs[i], ats[i], "r#{bys[i]}"),
    {},
    range(n)
  )
end

test "the five classes are in order with their numerals and ceilings"
  assert map((c) -> c.numeral, classes) == %w[I II III IV V]
  assert class_named(:crystal).ceiling == []
  assert class_named(:airlock).ceiling == %w[clock entropy network]
  assert raised(() -> class_named(:planet)) == :not_found
end

test "a shape classifies by threshold, then parties, then moving, then merged state"
  assert classify({}) == :crystal
  assert classify({state: :none}) == :crystal
  assert classify({state: :merge}) == :strand
  assert classify({migrates: true, state: :merge}) == :nomad
  assert classify({parties: 2, migrates: true}) == :airlock
  assert classify({parties: 5, threshold: [3, 5]}) == :synod
  assert raised(() -> classify({parties: 3})) == :bad_option
  assert raised(() -> classify({threshold: [4, 3]})) == :bad_option
  assert raised(() -> classify({threshold: [1, 1]})) == :bad_option
  assert raised(() -> classify({colour: :blue})) == :bad_option
end

test "reach is the recorded floor less its providers, and a scoped provider counts unless it serves every package that needs it"
  lock = json_read(
    json_stringify(
      {
        capabilities: {
          ceiling: [],
          floor: %w[clock entropy network],
          packages: {app: %w[clock entropy network]},
          provided: {
            clock: {provider: "deterministic-stepped", at_ms: 0, step_ms: 1},
            entropy: {provider: "seeded-prng", seed: "s", for: ["rede"]}
          }
        }
      }
    )
  )
  assert reach(lock) == %w[entropy network]
  scoped = {
    capabilities: {
      floor: %w[entropy network],
      packages: {app: ["network"], shomei: ["entropy"]},
      provided: {entropy: {provider: "seeded-prng", seed: "s", for: ["shomei"]}}
    }
  }
  assert reach(scoped) == ["network"]
  assert reach({capabilities: {floor: []}}) == []
  assert raised(() -> reach({})) == :not_found
end

test "admit refuses each capability past a class ceiling and nothing within it"
  assert admit(:crystal, []) == []
  assert admit(:strand, ["filesystem"]) == []
  assert map(first, admit(:crystal, %w[network clock])) == %i[denied denied]
  assert last(first(admit(:airlock, ["filesystem"]))) ==
    "airlock reaches filesystem, past its ceiling [\"clock\", \"entropy\", \"network\"]"
end

test "dock refuses exactly when the measured reach leaves the class ceiling"
  shapes = [
    {},
    {state: :merge},
    {parties: 2},
    {migrates: true},
    {threshold: [2, 3]}
  ]
  labels = %w[clock entropy environment filesystem network process]
  assert every?(
    fn(s)
      shape = shapes[first(take_ints(s, 5, 1))]
      reached = ordered(map((i) -> labels[i], take_ints(seeds(s, 2)[1], 6, 3)))
      d = dock(shape, {capabilities: {floor: reached}})
      is_empty(d.refusals) == subset?(reached, class_named(d.class).ceiling)
    end,
    seeds(31, 60)
  )
end

test "an airlock frame is the meet of both ceilings without the disk"
  a = %w[clock filesystem network]
  b = %w[entropy filesystem network]
  assert airlock_frame(a, b) == ["network"]
  assert airlock_frame(a, b) == airlock_frame(b, a)
  assert subset?(airlock_frame(a, b), a) and subset?(airlock_frame(a, b), b)
  assert airlock_frame([], a) == []
  assert airlock_frame(a, a) == %w[clock network]
end

test "a full Flash bucket sends one burst of MTU packets, then names the wait exactly"
  sent = reduce((b, _i) -> flash_send(b, 1280, 0).bucket, flash({}), range(12))
  assert sent.tokens == 1_024_000
  w = flash_send(sent, 1280, 0)
  assert w.verdict == :wait
  assert w.wait_ms == 16
  assert flash_send(w.bucket, 1280, 15).verdict == :wait
  assert flash_send(w.bucket, 1280, 16).verdict == :sent
end

test "the Flash refuses a packet past its MTU and a bucket that cannot hold one"
  assert flash_send(flash({}), 1281, 0).verdict == :refused
  assert flash_send(flash({}), 0, 0).verdict == :sent
  assert raised(() -> flash({mtu: 1500})) == :bad_option
  assert raised(() -> flash({burst: 1000})) == :bad_option
  assert raised(() -> flash({rate: 0})) == :bad_option
  assert raised(() -> flash({colour: 1})) == :bad_option
  assert refill(flash({at_ms: 50}), 10).at_ms == 50
  spent = flash_send(flash({}), 1280, 100).bucket
  assert refill(spent, 40) == spent
end

test "no run of Flash sends spends more than its burst and its rate over the time"
  assert every?(
    fn(s)
      sizes = take_ints(s, 1400, 40)
      gaps = take_ints(seeds(s, 2)[1], 40, 40)
      out = reduce(
        fn(acc, i)
          now = acc[2] + gaps[i] * gaps[i] * 2
          r = flash_send(first(acc), sizes[i], now)
          spent = if r.verdict == :sent
            sizes[i]
          else
            0
          end
          [
            r.bucket,
            acc[1] + spent,
            now,
            last(acc) and r.bucket.tokens >= 0 and r.bucket.tokens <= 16_384_000
          ]
        end,
        [flash({}), 0, 0, true],
        range(40)
      )
      out[1] * 1000 <= 16384 * 1000 + 16384 * out[2] and last(out)
    end,
    seeds(7, 50)
  )
end

test "LEDBAT grows under the target, shrinks over it, and halves on a loss"
  t = tide({collapse_ms: nil})
  assert t.cwnd == 2560
  grown = tide_ack(t, {delay_ms: 50, bytes: 1280, now_ms: 0})
  assert grown.cwnd == 3200
  assert queuing(grown) == 0
  over = tide_ack(
    {**grown, current: []},
    {delay_ms: 250, bytes: 1280, now_ms: 10}
  )
  assert queuing(over) == 200
  assert over.cwnd == 2688
  assert tide_loss({**t, cwnd: 12800}).cwnd == 6400
  assert tide_loss(t).cwnd == 2560
  stretch = tide_ack(t, {delay_ms: 50, bytes: 12800, now_ms: 0})
  assert stretch.cwnd == 3840
  limited = tide_ack(t, {delay_ms: 50, bytes: 1280, now_ms: 0, flight: 1280})
  assert limited.cwnd == 2560
  assert queuing(t).nil?
end

test "the Tide collapses to its floor at two milliseconds of queuing, and configured off it grows"
  base = tide_ack(tide({}), {delay_ms: 50, bytes: 1280, now_ms: 0})
  assert base.cwnd == 3200
  held = tide_ack({**base, current: []}, {delay_ms: 52, bytes: 1280, now_ms: 1})
  assert held.cwnd == 2560
  under = tide_ack(
    {**base, current: []},
    {delay_ms: 51, bytes: 1280, now_ms: 1}
  )
  assert under.cwnd > base.cwnd
  off = tide_ack(
    {**base, collapse_ms: nil, current: []},
    {delay_ms: 52, bytes: 1280, now_ms: 1}
  )
  assert off.cwnd > base.cwnd
end

test "the base delay is the least of the last base_minutes minutes"
  t = tide_ack(tide({}), {delay_ms: 10, bytes: 1280, now_ms: 0})
  later = reduce(
    (acc, m) -> tide_ack(acc, {delay_ms: 50, bytes: 1280, now_ms: m * 60000}),
    t,
    range(1, 11)
  )
  assert size(later.base) == 10
  assert apply(blue::min, map(last, later.base)) == 50
  kept = reduce(
    (acc, m) -> tide_ack(acc, {delay_ms: 50, bytes: 1280, now_ms: m * 60000}),
    t,
    range(1, 10)
  )
  assert apply(blue::min, map(last, kept.base)) == 10
  assert base_update([], 3, 7, 10) == [[3, 7]]
end

test "a Tide window never falls under its floor nor grows past one packet an ack"
  assert every?(
    fn(s)
      delays = take_ints(s, 300, 60)
      packets = take_ints(seeds(s, 3)[2], 10, 60)
      losses = take_ints(seeds(s, 2)[1], 9, 60)
      last(
        reduce(
          fn(acc, i)
            t = first(acc)
            moved = if losses[i] == 0
              tide_loss(t)
            else
              tide_ack(
                t,
                {
                  delay_ms: delays[i],
                  bytes: 1280 * (packets[i] + 1),
                  now_ms: i * 5000
                }
              )
            end
            [
              moved,
              last(acc) and moved.cwnd >= 2560 and moved.cwnd <= t.cwnd + 1280
            ]
          end,
          [tide({collapse_ms: nil}), true],
          range(60)
        )
      )
    end,
    seeds(13, 40)
  )
  assert raised(() -> tide({min_cwnd: 0})) == :bad_option
  assert raised(() -> tide({init_cwnd: 1})) == :bad_option
  assert raised(() -> tide({target_ms: 0})) == :bad_option
end

test "last writer wins, ties broken by writer and then value, and a stale write changes nothing"
  s = put({}, "k", "a", 5, "r1")
  assert put(s, "k", "b", 6, "r1")["k"].v == "b"
  assert put(s, "k", "b", 4, "r9") == s
  assert put(s, "k", "b", 5, "r2")["k"].v == "b"
  assert put(s, "k", "b", 5, "r0") == s
  assert put(s, "k", "b", 5, "r1")["k"].v == "b"
  assert put(put(s, "k", "b", 5, "r1"), "k", "a", 5, "r1")["k"].v == "b"
  assert raised(() -> put({}, :k, 1, 1, "r")) == :bad_option
end

test "merge is commutative, associative and idempotent over random maps"
  assert every?(
    fn(s)
      a = random_state(s, 6, 4)
      b = random_state(seeds(s, 2)[1], 6, 4)
      c = random_state(seeds(s, 3)[2], 6, 4)
      merge(a, b) == merge(b, a) and
        merge(merge(a, b), c) == merge(a, merge(b, c)) and
        merge(a, a) == a and
        merge(a, {}) == a
    end,
    seeds(5, 60)
  )
end

test "two replicas that take the same writes in any order hold the same root"
  assert every?(
    fn(s)
      ks = take_ints(s, 3, 8)
      ats = take_ints(seeds(s, 2)[1], 4, 8)
      ops = map(
        fn(i)
          {op: :put, key: "k#{ks[i]}", value: i, at: ats[i], by: "r#{i % 2}"}
        end,
        range(8)
      )
      forward = replay(strand({}), ops)
      backward = replay(strand({}), reverse(ops))
      state_root(forward.state) == state_root(backward.state)
    end,
    seeds(17, 40)
  )
end

test "each Strand record binds its input and output roots and links to the head before it"
  ops = [
    {op: :put, key: "a", value: 1, at: 1, by: "r1"},
    {op: :put, key: "a", value: 0, at: 0, by: "r2"},
    {op: :merge, state: put({}, "b", 2, 3, "r2")}
  ]
  s = strand({})
  rs = records(s, ops)
  done = replay(s, ops)
  assert size(rs) == 3
  assert first(rs).input_root == state_root({})
  assert first(rs).output_root == rs[1].input_root
  assert rs[1].steps == 0
  assert rs[1].output_root == rs[1].input_root
  assert last(rs).steps == 1
  assert last(rs).output_root == state_root(done.state)
  assert verify?(s, rs, done.head)
  assert not verify?(s, [first(rs), {**rs[1], steps: 1}, last(rs)], done.head)
  assert not verify?(s, [first(rs), last(rs)], done.head)
  forged = [first(rs), {**rs[1], prev: s.genesis}, last(rs)]
  assert not verify?(
    s,
    forged,
    shomei::head(s.genesis, map(json_stringify, forged))
  )
  assert replay(s, ops).head == done.head
  assert records(s, []) == []
end

test "a Strand names its def_hash only in the b3 shape, and an unknown op is refused"
  h = "b3:#{hash_message("ibuki")}"
  assert step(
    strand({def_hash: h}),
    {op: :put, key: "k", value: 1, at: 1, by: "r"}
  ).record.def_hash == h
  assert raised(() -> strand({def_hash: "sha256:00"})) == :bad_option
  assert raised(() -> step(strand({}), {op: :delete})) == :bad_option
  assert strand({}).genesis != strand({protocol: "lww-map/2"}).genesis
end

test "a Strand names the engine's def_hash of step when the caller names none"
  h = def_hash(step)
  assert string?(h) and is_hash_hex(replace(h, "b3:", ""))
  assert strand({}).def_hash == h
  assert step(
    strand({}),
    {op: :put, key: "k", value: 1, at: 1, by: "r"}
  ).record.def_hash == h
  mine = "b3:#{hash_message("ibuki")}"
  assert strand({def_hash: mine}).def_hash == mine
  assert strand({def_hash: nil}).def_hash == h
end

test "the property helpers can say no"
  assert random_state(3, 6, 4) == random_state(3, 6, 4)
  assert random_state(3, 6, 4) != random_state(4, 6, 4)
  assert size(map_entries(random_state(9, 20, 2))) <= 2
end
