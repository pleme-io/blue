@moduledoc """
kodou (鼓動) — the dual-pulse wire: a Flash channel paced by ibuki's token bucket and a Tide channel paced by ibuki's LEDBAT controller from the one-way delay each acknowledgement measures, over one UDP socket the host frames (0x02 Flash, 0x01 Tide); and the gossip of crash proofs on it: an alert on Flash, the artifact on Tide when a peer asks for it, verified by its content hash and kept in kensa's `kensa-immunity.v1` file.

The host words are `flash_*` (the comm_flash capability) and `tide_*` (comm_scavenger); the clock paces both, so under a stepped clock a run repeats. The host refuses a frame past 1280 bytes; the rate is this bidama's, so a program that calls `flash_put` itself is not paced. The design and its tiers: `theory/IBUKI.md`.

    parts("abcdef", 4) #=> ["abcd", "ef"]
"""

use("ibuki", %i[flash flash_send tide tide_ack])
use("jisho", %i[delete has?])
use("kyohi", [:raised])
use("moji", %i[after_first before_first checked drop_chars take_chars])
use("retsu", %i[first is_empty last push size])

@doc """
schema: the immunity file's schema, as kensa reads it.

    schema #=> "kensa-immunity.v1"
"""
def schema()
  "kensa-immunity.v1"
end

@doc """
kensa_capabilities: the host capabilities a `kensa-immunity.v1` entry can name; a crash that breached any other is refused, so one entry never makes the whole file unreadable.

    member?("comm-flash", kensa_capabilities) #=> false
"""
def kensa_capabilities()
  %w[process filesystem environment clock network entropy]
end

@doc """
part_room: the bytes of artifact text one Tide part carries, under the 1271 a Tide frame holds less the part's header.

    part_room #=> 1180
"""
def part_room()
  1180
end

@doc """
link: one end of the wire bound to `addr`, with the channels `channels:` names (`%i[flash tide]`), a Flash bucket from `flash:` and a Tide controller from `tide:` (ibuki's defaults), and the Tide ring's bounds from `ring:`.

    link("127.0.0.1:0", {channels: [:tide]}).flight #=> 0
"""
def link(addr, opts)
  checked(opts, %i[channels flash ring tide])
  channels = opts[:channels] or %i[flash tide]
  if is_empty(channels) or
      not every?((c) -> member?(c, %i[flash tide]), channels)
    raise(
      :bad_option,
      "a link's channels are :flash and :tide, got #{to_s(channels)}"
    )
  end
  w = if member?(:flash, channels)
    flash_open(addr)
  end
  wire = if member?(:tide, channels)
    tide_open(w or addr, opts[:ring] or {})
  else
    w
  end
  {
    wire:,
    channels:,
    flash: flash(opts[:flash] or {}),
    tide: tide(opts[:tide] or {}),
    flight: 0,
    evicted: 0,
    sent: nil
  }
end

@doc """
address: the host:port a link's socket is bound to, which a peer sends to.

    starts_with?(address(link("127.0.0.1:0", {})), "127.0.0.1:") #=> true
"""
def address(l)
  if member?(:tide, l.channels)
    tide_stats(l.wire).address
  else
    flash_stats(l.wire).address
  end
end

@doc """
emit: the link after one Flash frame to `peer`, sent when the bucket holds its bytes (the payload and its framing byte) and after waiting out the bucket when it does not; `sent:` names when and how many bytes. A frame past the MTU is a :bad_option raise and sends nothing.

    emit(link("127.0.0.1:0", {}), "127.0.0.1:9", "hi").sent.bytes #=> 3
"""
def emit(l, peer, payload)
  bytes = length(text_bytes(payload)) + 1
  at = now_ms
  r = flash_send(l.flash, bytes, at)
  if r.verdict == :refused
    raise(:bad_option, r.why)
  elsif r.verdict == :wait
    sleep_ms(r.wait_ms)
    emit({**l, flash: r.bucket}, peer, payload)
  else
    flash_put(l.wire, peer, payload)
    {**l, flash: r.bucket, sent: {at_ms: at, bytes:}}
  end
end

@doc """
queue: the link with one Tide data frame for `peer` in the host's ring, counting the oldest frames the ring evicted to hold it.

    queue(link("127.0.0.1:0", {}), "127.0.0.1:9", "bulk").evicted #=> 0
"""
def queue(l, peer, body)
  {**l, evicted: l.evicted + tide_put(l.wire, peer, "d#{body}")}
end

@doc """
pump: the link after the ring released what the Tide window allows: the controller's window less the bytes in flight, each frame stamped with the clock.

    pump(link("127.0.0.1:0", {})).flight #=> 0
"""
def pump(l)
  room = blue::max(0, l.tide.cwnd - l.flight)
  {**l, flight: l.flight + tide_release(l.wire, room, now_ms)}
end

@doc """
acked: the link after an acknowledgement of `bytes` that measured `delay_ms` of one-way delay: the controller moves its window, and the bytes leave flight.

    acked(link("127.0.0.1:0", {}), 0, 1280).flight #=> 0
"""
def acked(l, delay_ms, bytes)
  {
    **l,
    tide: tide_ack(l.tide, {delay_ms:, bytes:, now_ms:, flight: l.flight}),
    flight: blue::max(0, l.flight - bytes)
  }
end

@doc """
take: the next Tide frame within `timeout_ms`: a data frame is acknowledged at once with the delay it measured and its body delivered; an acknowledgement moves the window; `idle:` when none came.

    take(link("127.0.0.1:0", {}), 0).idle #=> true
"""
def take(l, timeout_ms)
  f = tide_next(l.wire, timeout_ms)
  if f.nil?
    {link: l, from: nil, body: nil, idle: true}
  elsif starts_with?(f.payload, "d")
    t = now_ms
    tide_send(
      l.wire,
      f.from,
      "a#{json_stringify({delay_ms: t - f.sent_ms, bytes: f.bytes})}",
      t
    )
    {link: l, from: f.from, body: drop_chars(f.payload, 1), idle: false}
  else
    ack = ack_of(f.payload)
    moved = if ack.nil?
      l
    else
      acked(l, ack.delay_ms, ack.bytes)
    end
    {link: moved, from: f.from, body: nil, idle: false}
  end
end

@doc """
ack_of: the delay and bytes an acknowledgement's payload names, or nil for anything that is not one.

    ack_of("a{\"bytes\":9,\"delay_ms\":4}") #=> {delay_ms: 4, bytes: 9}
"""
def ack_of(payload)
  doc = if starts_with?(payload, "a")
    json_read(drop_chars(payload, 1)) rescue nil
  end
  if map?(doc) and integer?(doc["delay_ms"]) and integer?(doc["bytes"])
    {delay_ms: doc["delay_ms"], bytes: doc["bytes"]}
  end
end

@doc """
parts: a text cut into pieces of at most `room` UTF-8 bytes, never inside a character.

    parts("ab", 1) #=> ["a", "b"]
"""
def parts(text, room)
  cut = reduce(
    fn(acc, c)
      b = length(text_bytes(c))
      if acc.bytes + b > room and acc.cur != ""
        {done: push(acc.done, acc.cur), cur: c, bytes: b}
      else
        {**acc, cur: "#{acc.cur}#{c}", bytes: acc.bytes + b}
      end
    end,
    {done: [], cur: "", bytes: 0},
    chars(text)
  )
  if cut.cur == ""
    cut.done
  else
    push(cut.done, cut.cur)
  end
end

@doc """
part_body: the Tide body of the `index`th of `count` parts of the artifact named `hash`.

    part_body("b3:#{blake3_hex("")}", 0, 1, "x") == "Pb3:#{blake3_hex("")}:0:1:x" #=> true
"""
def part_body(hash, index, count, part)
  "P#{hash}:#{to_s(index)}:#{to_s(count)}:#{part}"
end

@doc """
read_body: a gossip body read back: `{kind: :want, hash:}`, `{kind: :part, hash:, index:, count:, part:}`, or nil for anything else.

    read_body("Wb3:#{blake3_hex("")}").kind #=> :want
"""
def read_body(body)
  rest = drop_chars(body, 1)
  hash = take_chars(rest, 67)
  if not hash_ok?(hash)
    nil
  elsif starts_with?(body, "W") and length(rest) == 67
    {kind: :want, hash:}
  elsif starts_with?(body, "P") and starts_with?(drop_chars(rest, 67), ":")
    tail = drop_chars(rest, 68)
    index = to_int(before_first(tail, ":"))
    after = after_first(tail, ":")
    count = to_int(before_first(after, ":"))
    if index.nil? or count.nil? or index < 0 or index >= count
      nil
    else
      {kind: :part, hash:, index:, count:, part: after_first(after, ":")}
    end
  end
end

@doc """
hash_ok?: whether a text is a BLAKE3 hash as kensa writes one: `b3:` and 64 lowercase hex digits.

    hash_ok?("b3:#{blake3_hex("x")}") #=> true
"""
def hash_ok?(h)
  string?(h) and
    length(h) == 67 and
    starts_with?(h, "b3:") and
    every?(
      (c) -> member?(c, chars("0123456789abcdef")),
      chars(drop_chars(h, 3))
    )
end

@doc """
crash_hash: a crash's content address: `b3:` and the BLAKE3 hash of its canonical JSON, the digest tameshi and kensa compute.

    crash_hash("{}") == "b3:#{blake3_hex("{}")}" #=> true
"""
def crash_hash(canon)
  "b3:#{blake3_hex(canon)}"
end

@doc """
violation_of: what a crash breached: its `violation` block when it has one (blue-trace version 3), else the capability breach its tape ends on (`class`, `capability`, `host`), or nil.

    violation_of({"tape" => []}) #=> nil
"""
def violation_of(doc)
  v = doc["violation"]
  if map?(v)
    {class: v["class"], capability: v["capability"], host: v["host"]}
  else
    breaches = filter(
      fn(e)
        f = if map?(e)
          e["fatal"]
        end
        map?(f) and f["kind"] == "capability-breach"
      end,
      doc["tape"] or []
    )
    if is_empty(breaches)
      nil
    else
      e = last(breaches)
      message = e["fatal"]["message"] or ""
      {
        class: "LatticeCeilingBreach",
        capability: before_first(
          after_first(message, "reaches the host ("),
          ")"
        ),
        host: e["call"]
      }
    end
  end
end

@doc """
alert_of: the Flash alert a crash's canonical JSON makes: its crash hash, the crashed definition's def_hash, its violation class and its size.

    alert_of("{\"def_hash\":\"d\",\"tape\":[]}").class #=> nil
"""
def alert_of(canon)
  doc = json_read(canon)
  v = violation_of(doc)
  {
    crash_hash: crash_hash(canon),
    def_hash: doc["def_hash"],
    class: if v.nil?
      nil
    else
      v.class
    end,
    bytes: length(text_bytes(canon))
  }
end

@doc """
entry_of: the `kensa-immunity.v1` entry a crash's canonical JSON makes, or a :refused raise naming why: a crash that breached no lattice ceiling, a capability the file cannot name, or a def_hash that is not one.

    raised(() -> entry_of("{\"tape\":[]}")) #=> :refused
"""
def entry_of(canon)
  doc = json_read(canon)
  h = crash_hash(canon)
  v = violation_of(doc)
  d = doc["def_hash"]
  if v.nil? or v.class != "LatticeCeilingBreach"
    raise(
      :refused,
      "crash #{h} names no LatticeCeilingBreach, the one violation kensa immunizes"
    )
  end
  if not member?(v.capability, kensa_capabilities)
    raise(
      :refused,
      "crash #{h} breached #{to_s(v.capability)}, which kensa-immunity.v1 cannot name; it names #{join(kensa_capabilities, ", ")}"
    )
  end
  if not hash_ok?(d)
    raise(
      :refused,
      "crash #{h} has def_hash #{to_s(d)}, not b3: and 64 hex digits"
    )
  end
  e = {
    "capability" => v.capability,
    "class" => v.class,
    "crash_hash" => h,
    "def_hash" => d
  }
  named = if string?(doc["definition"])
    assoc(e, "definition", doc["definition"])
  else
    e
  end
  if string?(v.host)
    assoc(named, "host", v.host)
  else
    named
  end
end

@doc """
be32: a count as four big-endian bytes.

    be32(258) #=> [0, 0, 1, 2]
"""
def be32(n)
  [
    floor(n / 16_777_216) % 256,
    floor(n / 65536) % 256,
    floor(n / 256) % 256,
    n % 256
  ]
end

@doc """
length_prefixed: texts as one byte list, each its UTF-8 length in four big-endian bytes then its bytes, so no two lists of texts encode alike (tameshi's `length_prefixed`).

    length_prefixed(["ab"]) #=> [0, 0, 0, 2, 97, 98]
"""
def length_prefixed(fields)
  reduce(
    fn(acc, f)
      b = text_bytes(f)
      append(acc, be32(length(b)), b)
    end,
    [],
    fields
  )
end

@doc """
immunity_digest: the digest a `kensa-immunity.v1` file carries over its entries: BLAKE3 over the schema and the canonical entries, length-prefixed.

    hash_ok?(immunity_digest([])) #=> true
"""
def immunity_digest(entries)
  "b3:#{blake3_hex(length_prefixed([schema, json_stringify(entries)]))}"
end

@doc """
immunity_text: the canonical text of a `kensa-immunity.v1` file holding `entries`.

    starts_with?(immunity_text([]), "{\"digest\":\"b3:") #=> true
"""
def immunity_text(entries)
  json_stringify(
    {
      "digest" => immunity_digest(entries),
      "entries" => entries,
      "schema" => schema
    }
  )
end

@doc """
immunity_entries: the entries of a `kensa-immunity.v1` file's text, empty for nil, or a :refused raise when its schema, its order or its digest does not read.

    immunity_entries(immunity_text([])) #=> []
"""
def immunity_entries(text)
  if text.nil?
    []
  else
    doc = json_read(text)
    entries = doc["entries"] or []
    hashes = map((e) -> e["crash_hash"], entries)
    if doc["schema"] != schema
      raise(
        :refused,
        "immunity: schema #{to_s(doc["schema"])} is not #{schema}"
      )
    end
    if not every?(
      (i) -> compare(hashes[i], hashes[i + 1]) < 0,
      range(blue::max(0, size(hashes) - 1))
    )
      raise(
        :refused,
        "immunity: entries are not sorted by crash hash, each once"
      )
    end
    if immunity_digest(entries) != doc["digest"]
      raise(
        :refused,
        "immunity: its digest does not match its entries; it changed after it was written"
      )
    end
    entries
  end
end

@doc """
immunity_add: entries with one more, sorted by crash hash; the same entries when one already holds its crash hash.

    immunity_add([{"crash_hash" => "b"}], {"crash_hash" => "a"}) #=> [{"crash_hash" => "a"}, {"crash_hash" => "b"}]
"""
def immunity_add(entries, entry)
  h = entry["crash_hash"]
  if every?((e) -> e["crash_hash"] != h, entries)
    sort_keyed((e) -> e["crash_hash"], push(entries, entry))
  else
    entries
  end
end

@doc """
immunize: the entry a crash's canonical JSON makes, appended to the `kensa-immunity.v1` file at `path` (created when absent) after the file's own digest is checked.

    raised(() -> immunize("/nonexistent/kodou/immunity.json", "{\"tape\":[]}")) #=> :refused
"""
def immunize(path, canon)
  e = entry_of(canon)
  held = if path_exists(path)
    read_file(path)
  end
  write_file(path, immunity_text(immunity_add(immunity_entries(held), e)))
  e
end

@doc """
node: a gossip node on a link, keeping its immunity file at `immunity`: the crashes it holds to serve, the alerts it wants the artifact of, the parts it has of each, and the crash hashes its file already holds.

    node(link("127.0.0.1:0", {}), "/nonexistent/immunity.json").known #=> []
"""
def node(l, immunity)
  held = if path_exists(immunity)
    immunity_entries(read_file(immunity))
  else
    []
  end
  {
    link: l,
    immunity:,
    held: {},
    wanted: {},
    got: {},
    known: map((e) -> e["crash_hash"], held),
    refused: [],
    idle: true
  }
end

@doc """
publish: the node after alerting `peer` on Flash to a crash it read (`text`, any `.bluecrash`), holding the crash's canonical JSON to serve when the peer asks.

    size(map_entries(publish(node(link("127.0.0.1:0", {}), "/nonexistent/i.json"), "127.0.0.1:9", "{\"tape\":[]}").held)) #=> 1
"""
def publish(n, peer, text)
  canon = json_canonical(text)
  a = alert_of(canon)
  {
    **n,
    link: emit(n.link, peer, "A#{json_stringify(a)}"),
    held: assoc(n.held, a.crash_hash, canon)
  }
end

@doc """
heed: the node after the next Flash frame within `timeout_ms`: an alert for a crash it neither holds, wants nor is immune to is wanted, and the want goes to its sender on Tide.

    heed(node(link("127.0.0.1:0", {}), "/nonexistent/i.json"), 0).wanted #=> {}
"""
def heed(n, timeout_ms)
  f = flash_next(n.link.wire, timeout_ms)
  a = if f.nil? or not starts_with?(f.payload, "A")
    nil
  else
    json_read(drop_chars(f.payload, 1)) rescue nil
  end
  h = if map?(a)
    a["crash_hash"]
  end
  if not hash_ok?(h) or
      has?(n.held, h) or
      has?(n.wanted, h) or
      member?(h, n.known)
    n
  else
    {
      **n,
      link: pump(queue(n.link, f.from, "W#{h}")),
      wanted: assoc(n.wanted, h, a)
    }
  end
end

@doc """
tend: the node after the next Tide frame within `timeout_ms`: a want for a crash it holds queues every part to the asker; a part of a wanted crash is kept, and the last part verifies the whole against its hash and the alert and immunizes it; `idle:` when no frame came.

    tend(node(link("127.0.0.1:0", {}), "/nonexistent/i.json"), 0).idle #=> true
"""
def tend(n, timeout_ms)
  t = take(n.link, timeout_ms)
  moved = {**n, link: t.link, idle: t.idle}
  m = if t.body.nil?
    nil
  else
    read_body(t.body)
  end
  if m.nil?
    moved
  elsif m.kind == :want
    served(moved, t.from, m.hash)
  elsif has?(moved.wanted, m.hash)
    gathered(moved, m)
  else
    moved
  end
end

@doc """
served: the node after queueing every part of the crash `hash` it holds for `peer` and pumping the window; the same node when it holds no such crash.

    served(node(link("127.0.0.1:0", {}), "/nonexistent/i.json"), "127.0.0.1:9", "b3:x").link.flight #=> 0
"""
def served(n, peer, hash)
  canon = get(n.held, hash)
  if canon.nil?
    n
  else
    ps = parts(canon, part_room)
    queued = reduce(
      (l, i) -> queue(l, peer, part_body(hash, i, size(ps), ps[i])),
      n.link,
      range(size(ps))
    )
    {**n, link: pump(queued)}
  end
end

@doc """
gathered: the node after keeping one part of a wanted crash; with every part in hand the artifact is checked (its hash, its canonical form, the alert's def_hash and class) and immunized, or refused with why.

    gathered(node(link("127.0.0.1:0", {}), "/nonexistent/i.json"), {hash: "h", index: 0, count: 2, part: "x"}).got #=> {"h" => {"0" => "x"}}
"""
def gathered(n, m)
  have = assoc(get(n.got, m.hash) or {}, to_s(m.index), m.part)
  if size(map_entries(have)) < m.count
    {**n, got: assoc(n.got, m.hash, have)}
  else
    text = join(map((i) -> get(have, to_s(i)) or "", range(m.count)), "")
    a = get(n.wanted, m.hash)
    why = refusal_of(text, m.hash, a)
    rest = {**n, got: delete(n.got, m.hash), wanted: delete(n.wanted, m.hash)}
    if why.nil?
      immunize(n.immunity, text)
      {**rest, known: push(n.known, m.hash)}
    else
      {**rest, refused: push(n.refused, why)}
    end
  end
end

@doc """
refusal_of: why an artifact gathered for the alert `a` is refused, or nil: its hash, its canonical form, the alert's def_hash and class, and the entry it makes must all hold.

    starts_with?(refusal_of("{}", "b3:x", {}), "the artifact hashes to") #=> true
"""
def refusal_of(text, hash, a)
  got = crash_hash(text)
  canon = json_canonical(text) rescue nil
  if got != hash
    "the artifact hashes to #{got}, not #{hash}"
  elsif canon != text
    "the artifact is not canonical JSON, so its hash is not the crash hash kensa computes"
  else
    alert = alert_of(text)
    unmade = begin
      entry_of(text)
      nil
    rescue e
      e.message
    end
    if a["def_hash"] != alert.def_hash or a["class"] != alert.class
      "the alert for #{hash} names a def_hash or class its artifact does not"
    elsif not unmade.nil?
      "crash #{hash} makes no kensa-immunity.v1 entry: #{unmade}"
    end
  end
end

@doc """
step: the node after one round: up to `rounds` Flash frames heeded and up to `rounds` Tide frames tended, each waiting at most `timeout_ms`, then the window pumped.

    step(node(link("127.0.0.1:0", {}), "/nonexistent/i.json"), 0, 2).refused #=> []
"""
def step(n, timeout_ms, rounds)
  heeded = reduce((acc, _i) -> heed(acc, 0), n, range(rounds))
  tended = reduce(
    fn(acc, i)
      if i > 0 and acc.idle
        acc
      else
        tend(acc, timeout_ms)
      end
    end,
    heeded,
    range(rounds)
  )
  {**tended, link: pump(tended.link)}
end

test "a part body reads back, and a body that is no gossip reads as nil"
  h = crash_hash("{}")
  m = read_body(part_body(h, 2, 3, "x:y"))
  assert m == {kind: :part, hash: h, index: 2, count: 3, part: "x:y"}
  assert read_body("W#{h}") == {kind: :want, hash: h}
  assert read_body("W#{h}x").nil?
  assert read_body(part_body(h, 3, 3, "x")).nil?
  assert read_body(part_body("b3:nothex", 0, 1, "x")).nil?
  assert read_body("P#{h}x0:1:y").nil?
  assert read_body("").nil?
  assert read_body("Z#{h}").nil?
end

test "parts never cut a character and never pass their room"
  s = "aé€😀b"
  ps = parts(s, 4)
  assert join(ps, "") == s
  assert every?((p) -> length(text_bytes(p)) <= 4, ps)
  assert ps == %w[aé € 😀 b]
  assert parts("", 4) == []
  long = join(map((i) -> to_s(i % 10), range(5000)), "")
  assert join(parts(long, part_room), "") == long
  assert size(parts(long, part_room)) == 5
end

test "a v2 crash's breach is read off its tape, a v3 crash's from its violation block"
  v2 = {
    "tape" => [
      {"call" => "receive", "value" => nil},
      {
        "call" => "is_file?",
        "fatal" => {
          "kind" => "capability-breach",
          "message" => "`is_file?` reaches the host (filesystem), which this process's frame does not grant"
        }
      }
    ]
  }
  assert violation_of(v2) ==
    {class: "LatticeCeilingBreach", capability: "filesystem", host: "is_file?"}
  v3 = {
    "violation" => {
      "class" => "LatticeCeilingBreach",
      "capability" => "network",
      "host" => "http_request"
    }
  }
  assert violation_of(v3).capability == "network"
  assert violation_of({"tape" => [{"call" => "now_ms", "raised" => "x"}]}).nil?
  assert violation_of({}).nil?
end

@doc """
fixture_crash: the canonical JSON of a blue-trace version 3 crash of `%root/reader` that breached `capability` through `read_file`, for the tests beside this file.

    hash_ok?(crash_hash(fixture_crash("filesystem", "d"))) #=> true
"""
def fixture_crash(capability, def_hash)
  json_canonical(
    json_stringify(
      {
        "format" => "blue-trace",
        "version" => 3,
        "definition" => "%root/reader",
        "def_hash" => def_hash,
        "exit" => {"kind" => "fatal"},
        "frame" => nil,
        "violation" => {
          "class" => "LatticeCeilingBreach",
          "capability" => capability,
          "host" => "read_file"
        }
      }
    )
  )
end

test "an entry is kensa's shape, keys and all, and a crash it cannot name is refused alone"
  d = crash_hash("def")
  c = fixture_crash("filesystem", d)
  e = entry_of(c)
  assert map(first, map_entries(e)) ==
    %w[capability class crash_hash def_hash definition host]
  assert e["crash_hash"] == crash_hash(c)
  assert e["host"] == "read_file"
  assert raised(() -> entry_of(fixture_crash("comm-flash", d))) == :refused
  assert raised(() -> entry_of(fixture_crash("filesystem", "b3:short"))) ==
    :refused
  assert raised(() -> entry_of(json_canonical("{\"tape\":[]}"))) == :refused
  bare = json_canonical(
    "{\"def_hash\":\"#{d}\",\"violation\":{\"class\":\"LatticeCeilingBreach\",\"capability\":\"clock\"}}"
  )
  assert map(first, map_entries(entry_of(bare))) ==
    %w[capability class crash_hash def_hash]
end

test "the immunity digest is tameshi's length-prefixed BLAKE3 over the schema and the canonical entries"
  assert be32(0) == [0, 0, 0, 0]
  assert be32(16_777_216 * 3 + 65536 * 2 + 256 + 7) == [3, 2, 1, 7]
  assert length_prefixed([]) == []
  assert length_prefixed(["", "é"]) == [0, 0, 0, 0, 0, 0, 0, 2, 195, 169]
  bytes = append(
    [0, 0, 0, 17],
    text_bytes("kensa-immunity.v1"),
    [0, 0, 0, 2],
    text_bytes("[]")
  )
  assert immunity_digest([]) == "b3:#{blake3_hex(bytes)}"
  assert immunity_text([]) ==
    "{\"digest\":\"#{immunity_digest([])}\",\"entries\":[],\"schema\":\"kensa-immunity.v1\"}"
end

test "an immunity file grows by entries in crash-hash order, once each, and an edited file is refused"
  d = crash_hash("def")
  a = entry_of(fixture_crash("filesystem", d))
  b = entry_of(fixture_crash("network", d))
  both = immunity_add(immunity_add([], a), b)
  assert immunity_add(both, a) == both
  assert map((e) -> e["crash_hash"], both) ==
    sort_keyed((h) -> h, [a["crash_hash"], b["crash_hash"]])
  text = immunity_text(both)
  assert json_stringify(immunity_entries(text)) == json_stringify(both)
  assert immunity_entries(nil) == []
  edited = replace(text, "\"network\"", "\"clock\"")
  assert raised(() -> immunity_entries(edited)) == :refused
  assert raised(
    () -> immunity_entries(replace(text, "kensa-immunity.v1", "v0"))
  ) == :refused
  dir = getenv("TMPDIR", "/tmp")
  path = path_join(dir, "kodou-immunity-#{to_s(now_ns)}.json")
  immunize(path, fixture_crash("filesystem", d))
  immunize(path, fixture_crash("filesystem", d))
  immunize(path, fixture_crash("network", d))
  assert immunity_entries(read_file(path)) == immunity_entries(text)
  rm(path)
end

test "an acknowledgement reads back only when it names its delay and bytes"
  assert ack_of("a{\"bytes\":9,\"delay_ms\":4}") == {delay_ms: 4, bytes: 9}
  assert ack_of("a{\"bytes\":9}").nil?
  assert ack_of("a{").nil?
  assert ack_of("d{\"bytes\":9,\"delay_ms\":4}").nil?
end

test "a Flash frame crosses loopback paced by the bucket, and a frame past the MTU sends nothing"
  a = link("127.0.0.1:0", {channels: [:flash]})
  b = link("127.0.0.1:0", {})
  sent = emit(a, address(b), "alert")
  assert sent.sent.bytes == 6
  got = flash_next(b.wire, 2000)
  assert got.payload == "alert"
  assert got.from == address(a)
  big = join(map((_i) -> "x", range(1280)), "")
  assert raised(() -> emit(a, address(b), big)) == :bad_option
  assert flash_stats(a.wire).sent == 1
  assert raised(() -> link("127.0.0.1:0", {channels: []})) == :bad_option
  assert raised(() -> link("127.0.0.1:0", {channels: [:radio]})) == :bad_option
end

test "a Tide frame is acknowledged with the delay it measured, and the acknowledgement grows the window"
  a = link("127.0.0.1:0", {})
  b = link("127.0.0.1:0", {})
  sent = pump(queue(a, address(b), "bulk"))
  assert sent.flight == 14
  t = take(b, 2000)
  assert t.body == "bulk"
  assert t.from == address(a)
  back = take(sent, 2000)
  assert back.body.nil? and not back.idle
  assert back.link.flight == 0
  assert size(back.link.tide.current) == 1
  assert size(sent.tide.current) == 0
  assert take(b, 0).idle
end

test "the Tide window holds what is past it in the ring until acknowledgements free it"
  a = link("127.0.0.1:0", {})
  queued = reduce(
    (l, _i) -> queue(l, "127.0.0.1:9", join(map((_k) -> "x", range(1000)), "")),
    a,
    range(5)
  )
  once = pump(queued)
  assert once.flight == 2020
  assert pump(once).flight == 2020
  assert tide_stats(once.wire).queued == 3
  freed = pump(acked(once, 0, 1010))
  assert freed.tide.cwnd == 3065
  assert freed.flight == 3030
  assert tide_stats(freed.wire).queued == 1
end

test "a gossiped crash arrives, verifies against its hash and lands in the immunity file once"
  dir = getenv("TMPDIR", "/tmp")
  path = path_join(dir, "kodou-gossip-#{to_s(now_ns)}.json")
  la = link("127.0.0.1:0", {})
  lb = link("127.0.0.1:0", {})
  c = fixture_crash("filesystem", crash_hash("def"))
  a = publish(node(la, path_join(dir, "kodou-none.json")), address(lb), c)
  b = node(lb, path)
  rounds = reduce(
    fn(acc, _i)
      nb = step(last(acc), 50, 8)
      [step(first(acc), 50, 8), nb]
    end,
    [a, step(b, 50, 8)],
    range(6)
  )
  got = last(rounds)
  assert got.known == [crash_hash(c)]
  assert got.refused == []
  assert map((e) -> e["crash_hash"], immunity_entries(read_file(path))) ==
    [crash_hash(c)]
  again = step(
    {**got, link: emit(la, address(lb), "A#{json_stringify(alert_of(c))}")},
    50,
    4
  )
  assert again.wanted == {}
  rm(path)
end

test "an artifact that does not match its alert or its hash is refused, not immunized"
  d = crash_hash("def")
  c = fixture_crash("filesystem", d)
  a = json_read(json_stringify(alert_of(c)))
  assert refusal_of(c, crash_hash(c), a).nil?
  assert starts_with?(
    refusal_of(c, crash_hash("other"), a),
    "the artifact hashes to"
  )
  spaced = replace(c, ",", ", ")
  assert starts_with?(
    refusal_of(spaced, crash_hash(spaced), a),
    "the artifact is not canonical"
  )
  lying = assoc(a, "def_hash", crash_hash("someone else"))
  assert contains?(
    refusal_of(c, crash_hash(c), lying),
    "names a def_hash or class"
  )
  wire = fixture_crash("comm-flash", d)
  assert contains?(
    refusal_of(
      wire,
      crash_hash(wire),
      json_read(json_stringify(alert_of(wire)))
    ),
    "makes no kensa-immunity.v1 entry"
  )
end
