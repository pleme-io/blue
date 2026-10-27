@moduledoc """
nisshi (日誌) — an event log: append-only JSON Lines, hash-chained, optionally signed, replayed into lifecycle states.

A logbook (日誌, as in 航海日誌, a ship's log): dated entries, in order,
never rewritten. One stream (one file) per kind of entity; each line is one
record of one event for one entity. `el_append` judges the event against a
raifusaikuru lifecycle and writes it, admitted or refused; `el_read` replays
a stream into every entity's state; `el_verify` walks the chain and names
the first line that is not what was written. Nothing here knows any domain:
a product declares its lifecycles and gets its telemetry from this.

## The plan (stage 1 of the blue development cycle, written before the code)

Reuse map, read from source on 2026-09-24:

  judge and fold an event      raifusaikuru  lc_admit_step, lc_step, lc_initial
  genesis, link, first break   shomei        chain_genesis, chain_link, chain_first_break
  sign and verify a hash       shomei        sign_message, verify_message, is_hash_hex
  read a field, totally        deeta         is_doc, get_str, get_int, as_json
  order keys, look up pairs    junjo, shuugou  sort_stable_by, lookup, set_equal
  JSON text of a scalar        runtime       json_stringify (escaping is its job)
  parse a line                 runtime       json_parse
  the file                     runtime       append_file, read_file, file_size, path_exists
  an index by entity or name   runtime       a map: get, assoc

Four primitives were FIXED where they live rather than routed around, each
found by a measurement here:

  range           blue-lang-runtime  was a Lisp recursion in tatara-lisp's stdlib
                                     and aborted near 5,000 elements, so
                                     chain_first_break could not verify a 5,000-line
                                     chain; now native (destination: tatara-lisp's own
                                     range becomes a loop, and blue's is deleted)
  is_hash_hex     shomei             a lambda per character, 97% of every chain_link;
                                     31 → 12 µs
  contains,       retsu              a tail-copying recursion, quadratic; a five-name
  index_of                           lookup 14.7 → 3.7 µs, and 20,000 elements
                                     664 → 5 ms
  lc_admit_step   raifusaikuru       NEW: admission and next state from one
                                     judgement, so append judges an event once, not twice

## The record

One line per record, canonical JSON (below), keys in code-point order:

  entity   the entity's id, a string
  hash     the chain link: shomei's chain_link(prev, body), 64 hex
  links    [{"id", "kind"}, …]: declared references to other entities, in
           the order given, carried faithfully (duplicates kept)
  payload  the event's payload, an object
  prev     the hash of the line before, or the stream's genesis
  refusal  null, or {"detail": [text], "kind": text} when refused
  seq      the entity's record number: 0, 1, 2 … over ALL its records,
           admitted and refused, so (entity, seq) names one line
  sig      null, or Ed25519 over the hash's 64 hex characters (shomei)
  status   "admitted" or "refused"
  time     the event's time, a whole number on the caller's clock
  type     the event's type

The BODY is the record without prev, hash and sig: entity, links, payload,
refusal, seq, status, time and type. The chain hashes the body's canonical
text, so a change to any of them breaks the chain, and chain_link binds
prev. The genesis is chain_genesis("nisshi/1\n" + label): the format and
the stream's label are both in the first hash. Recomputable with any BLAKE3
tool from shomei's two documented lines; the tests pin values from b3sum.

Canonical JSON (`el_canon`): no whitespace; object keys in code-point
order; strings, integers, finite floats, true/false and null as
json_stringify writes them; a non-empty list of [name, value] pairs is an
object and any other list an array, which is the runtime's own rule
(json.rs `looks_like_object`). A line is canonical when it is exactly the
rendering of the record it parses to, and el_verify checks that too.

## The rules

**append is the only function that writes, and read the only other I/O.**
Everything else is pure, with time, keys and labels passed in.

**A refused event is written, never dropped.** It carries its refusal (the
kind lc_admit gave and the detail as text) and counts in its entity's seq.
It is an attempt, not a fact of the lifecycle, so it is folded into no
state: replay steps only admitted records.

**An observed event is a fact, not an attempt** (`el_observe`, 2026-09-25).
A load a fryer's current sensor saw while its controller reported locked
happened; refusing it would erase the one record that says the guard was
bypassed. So el_observe writes a gated event whose guard refuses as
admitted, and every replay applies it and keeps it in lc_breaches, which is
raifusaikuru's own rule for an event that happened anyway. What the fold
itself cannot take (no row, an unknown type, a missing key) stays refused.
The line is the same nisshi/1 record: a breach is a property of a record
under a definition, found by replay, as a stricter reader's breaches are.

**One fold, shared.** `el_absorb_record` is how append advances its log
value and how read rebuilds one. read steps an entity with lc_step; append
with the state lc_admit_step returned, which is lc_step's by construction
(both are lc_apply over one lc_judge), so the two cannot disagree, and the
identity test pins it. append returns the record exactly as a later read
parses it: it renders the line, parses it back, and refuses to write a line
that is not canonical or does not read back as the event it judged.

**Names normalise; values must survive.** JSON has no keywords, so a type
or payload key comes back as the definition's own name when the definition
declares it, and as text when it does not (the fold never reads an
undeclared one). A VALUE must be JSON already: a keyword, a map, a float
that is not finite or a key given twice raises :eventlog_value before
anything is written, because it would come back as something else and a
guard comparing it would silently change its answer. A definition naming
two events (or two keys of one event) with one text, :go and "go", is
refused (:eventlog_use) when a log is made from it: both would be written
"go".

**A malformed call raises; a domain refusal is written.** An event the
lifecycle refuses is data about the world and goes into the stream. An
event that is not an lc_ev, an empty entity id, a link that is not
[kind, id]: those are bugs in the caller, and raise before anything is
written.

**A stale log value cannot write.** A log value records the stream's size
when it was read or last appended; append refuses (:eventlog_stale) when
the file has changed since, so a second writer or an old value cannot fork
the chain.

**A broken stream cannot grow.** A line that is not a record marks the log's
fault, and append refuses (:eventlog_broken). `el_open`, the writer's door,
also verifies the chain and refuses a broken one: new valid records after a
break would hide it.

## Tiers

DETECTED by el_verify, at the exact position: a changed line (:hash), a
dropped or reordered line (:prev), bytes changed without changing meaning
(:not_canonical), a wrong record number (:seq), a line that is not a record
or a last line without its newline, which is a torn write (:unparseable),
and with a public key a missing or wrong signature (:unsigned, :signature).

DETECTED ONLY WITH A RECORDED HEAD: lines dropped from the END. A chain
proves every line follows the one before; nothing in it says where it
stops. Pass the head recorded elsewhere (a receipt, a second store, a
signed checkpoint) to el_verify and a truncation is :head.

NOT DETECTED without signatures: a stream rewritten from any line onward,
every later hash recomputed, by someone who can write the file. Signatures
(a forger lacks the key) and a head kept elsewhere are what close it.

NOT CHECKED: that a refused record would still be refused, or an admitted
one admitted, under the definition passed to read. Replay uses the
definition you give it: an admitted record it cannot accept lands in the
entity's lc_refused, and a tightened guard shows as a breach.

ONE WRITER per stream, enforced by the size check at append, not by a lock.

## What is deliberately absent

No clock, no randomness, no key storage: time, labels and keys are the
caller's. No analytics: `anaritikusu` loads the stream into DuckDB as it
stands, writes el_history's per-record states beside it, and generates its
models from the definitions. No encryption: shomei hashes and signs, and so
does this.

## The operations

  read     el_read(path, label, def)           the stream, replayed
           el_open(path, label, def, pub)      read + verify, or refuse
           el_from_text(text, path, bytes, label, def)   the pure part of read
  write    el_append(log, entity, event, links)  the log advanced; el_last is the record
           el_observe(log, entity, event, links) the same for a fact a device saw:
                                               a guard refusal is written admitted
           el_signing(log, secret_hex)         appends through it are signed
  verify   el_verify(log, pub, expected_head)  [:el_intact, count, head] or
                                               [:el_broken, position, kind, why]
  state    el_state(log, entity), el_seq_of, el_states, el_entities
           el_history(log)                     [record, state after it], each record
           el_state_at(log, entity, time)      the state as of a time (the fold's
                                               twin of anaritikusu's as-of join)#   records  el_records(log), el_by_entity(records), el_rec_* accessors
  pure     el_canon(value), el_canon_object(pairs), el_genesis(label),
           el_texts / el_body_text / el_line_text (the record builders),
           el_decode_line(def, position, line), el_lines (the builtin
           unlines joins them back)

## One line (the first of the b3sum test's stream, signed)

  {"entity":"item-1","hash":"9172aea16c9c2cb304ee3d624c0a79be88ca7537769f3386b64aa55b273dc412",
   "links":[],"payload":{"value":10},"prev":"0a42d546253d153e4253d118781c1b773338b3dd532373a12a83accd79e7cba2",
   "refusal":null,"seq":0,"sig":"7b5e4034…a80b","status":"admitted","time":1000,"type":"reading"}

(one line in the stream; wrapped and the signature shortened here.)

## Tests, and the red run that turned each one red (2026-09-24)

  the empty stream                        R8 read keeps the piece after the last newline
  identity: append → read, read → read,   R1 refused dropped · R2 replay folds refused ·
    and raifusaikuru's own fold as the     R14 groups newest first · R17 append skips
    differential                           the step
  a refused event is written and marked   R1 · R16 seq counts only admitted
  values checked independently (b3sum,    R3 the hash leaves the payload out · R1 · R16
    openssl)
  controls, one row per break kind        R5 no :prev · R6 no signatures · R9 torn line
                                           read whole · R10 no seq · R11 no canonical check
  append raises on what JSON cannot hold  R12 no round-trip check (the keyword key was
                                           written, 294 bytes)
  stale, written-through, broken writers  R7 no size check · R18 two names of one text
  links carried faithfully                R13 duplicate links merged
  canonical JSON, and serde agrees        R4 keys left unsorted (caught by append's own
                                           canonical guard) · R15 a key given twice
  grouping by entity                      R14

Added 2026-09-25 (NuPastel's measures, nupastel docs/plans/measures.md), 5
of 5 mutations red through the same kind of driver:

  an observed event is a fact             N1 a guard refusal written refused ·
                                           N2 every refusal admitted · N5 the
                                           state before the breach kept
  the state as of a time                  N3 the record at the time left out ·
                                           N4 refused records folded

18 of 18 mutations red, each applied by a driver that refuses a mutation
whose target text is absent. In the packages this one changed:
raifusaikuru's lc_admit_step test red when it stopped stepping; shomei's
tests red when is_hash_hex forgot a digit; the runtime's range test aborted
with the Lisp range restored. retsu's contains/index_of change is speed
only, which no behaviour test can turn red: its semantics tests pass on both.

## The benchmark (2026-09-24)

10,000 events (el_example_events(10000, 100): 100 items, 5,500 refused by
the guard), appended signed through el_append_all, then el_read and
el_verify with the public key and the recorded head. Apple M4 Pro, 14
cores, 48 GB, macOS 26.7, release build of blue 0.0.39, under a load
average of ~49 from other builds (times vary ±10% run to run; median of 3):

                 first version   measured hot paths fixed
  append         8.18 s          5.39 s    539 µs an event
  read           3.53 s          1.85 s    185 µs a record
  verify         2.22 s          1.79 s    179 µs a record (1.26 s unsigned)

The stream: 4.26 MB, intact; DuckDB, reading it as JSON Lines, counts the
same 10,000 lines, 100 entities, 5,500 refusals and a gapless seq per
entity. What moved it, by measured share of an append: two judgements
became one (lc_admit_step, ~180 µs); decoding read each field once and
restored names through a map built once per log (218 → 62 µs); and the three
primitive fixes above. What remains, in order: raifusaikuru's judgement (~144
µs of an append; 16 µs per atomic rule, through shuugou's lookup), Ed25519
verification (~52 µs a record), and shomei's chain_hashes, which builds
its list with cons and is quadratic (~0.2 s at 10,000).

## Words blue is missing (stage 5 candidates, not built)

- A RECORD: a positional list plus one `nth` accessor per field is written by
  hand here twice (a record of 13 fields, a log value of 14 slots rebuilt in
  full to change four) and throughout raifusaikuru (lc_d_*, the state, the
  permit). One declaration of named fields should give the constructor, the
  predicate, the accessors and a `with` that changes some fields.
- A CLOSED KIND SET with its coverage test: el_break_kinds and
  el_refusal_kinds here, lc_problem_kinds in raifusaikuru, each with a
  hand-written "every kind has a row" set_equal.
- A GUARD: this file raises in 23 places, most of them
  `if … throw(error(:kind, "…")) end`; as a function, its message would be
  built even when the check passes.
- DEFAULT ARGUMENTS: el_verify(log, nil, nil) and el_append(…, []) pass
  "none" by position.
- A RED-RUN WORD: the mutation driver that produced the table above
  (package, [name, old, new] → which tests go red) was a scratch program;
  stage 3 of the cycle asks for exactly this on every test.
- An O(1) append: push and cons copy (AUTHORING.md, "Growing a list is
  quadratic"); a runtime gap, not a word.

    lines("") #=> []
"""

use("deeta", [:as_json, :get_int, :get_str, :is_doc])
use("junjo", [:sort_stable_by])
use("kyohi")

use("raifusaikuru", [:lc_define])

use(
  "retsu",
  [
    :all_but_last,
    :as_list,
    :concat_lists,
    :contains,
    :count_where,
    :find_first,
    :first,
    :is_empty,
    :push,
    :remove_at,
    :repeat,
    :size,
    :take_n,
    :update_at
  ]
)

use(
  "shomei",
  [
    :chain_first_break,
    :chain_genesis,
    :chain_link,
    :is_hash_hex,
    :keypair_public,
    :keypair_secret,
    :sign_message,
    :signing_keypair,
    :verify_message
  ]
)

use("shuugou", [:lookup, :set_equal, :unique])

legacy_names("0.1.1", "el")

legacy_names(
  "0.1.2",
  [["refusal_detail", "kyohi::why"], ["refusal_kind", "kyohi::kind"]]
)

# ── the format ─────────────────────────────────────────────────────────────

@doc """
format: The format tag, bound into every stream's genesis.
"""
def format()
  "nisshi/1"
end

@doc """
genesis: The first hash of the stream named `label`. Two streams with different
labels, or of different formats, never share a first hash.

    genesis("nisshi-doc") #=> "0a42d546253d153e4253d118781c1b773338b3dd532373a12a83accd79e7cba2"
"""
def genesis(label)
  if string?(label) == false
    raise(
      :eventlog_use,
      "a stream label is a string, not #{raifusaikuru::show(label)}"
    )
  end
  chain_genesis(join_lines([format, label]))
end

@doc """
refusal_kinds: Every refusal kind a record can carry: lc_admit's. Closed.
"""
def refusal_kinds()
  [:unknown_event, :no_edge, :missing_payload, :bad_payload, :bad_field, :guard]
end

@doc """
break_kinds: Every break el_verify reports, in the order it prefers them when two fall on
one line. Closed: a test row exercises each.
"""
def break_kinds()
  [
    :unparseable,
    :prev,
    :hash,
    :not_canonical,
    :seq,
    :unsigned,
    :signature,
    :head
  ]
end

# ── canonical JSON ─────────────────────────────────────────────────────────

@doc """
key_text: A key as JSON text: a string itself, a keyword's or symbol's name.
"""
def key_text(k)
  if string?(k)
    k
  elsif keyword?(k) or symbol?(k)
    to_s(k)
  else
    raise(
      :eventlog_value,
      "an object key is a name (a string or a keyword), not #{raifusaikuru::show(k)}"
    )
  end
end

# waive B0013: `pair?` is a builtin nisshi also uses, so the prefix stays; nisshi::pair? names it too
@doc """
el_pair?: True for a [name, value] pair.
"""
def el_pair?(p)
  list?(p) and
    size(p) == 2 and
    (string?(first(p)) or keyword?(first(p)) or symbol?(first(p)))
end

@doc """
object?: True for a value JSON writes as an object: a non-empty list whose every
element is a [name, value] pair, the runtime's own rule.
"""
def object?(v)
  list?(v) and
    is_empty(v) == false and
    count_where((p) -> el_pair?(p) == false, v) == 0
end

@doc """
empty_object?: True for the value json_parse gives an empty object: a map that writes "{}".
"""
def empty_object?(v)
  v != nil and list?(v) == false and json_stringify(v) == "{}"
end

@doc """
canon: The canonical JSON text of a value. Raises :eventlog_value for what JSON
would not give back as itself: a keyword, a map, a float that is not
finite, a key given twice.

    canon([]) #=> "[]"
"""
def canon(v)
  if v.nil?
    "null"
  elsif list?(v)
    canon_list(v)
  elsif string?(v) or integer?(v) or boolean?(v)
    json_stringify(v)
  elsif number?(v)
    canon_float(v)
  elsif empty_object?(v)
    "{}"
  elsif keyword?(v) or symbol?(v)
    raise(
      :eventlog_value,
      "#{raifusaikuru::show(v)} is a keyword, which JSON gives back as the string \"#{to_s(v)}\"; write the string"
    )
  else
    raise(
      :eventlog_value,
      "#{raifusaikuru::show(v)} is not JSON data; write an object as a list of [key, value] pairs"
    )
  end
end

def canon_list(v)
  if object?(v)
    canon_object(v)
  else
    "[#{join(map(canon, v), ",")}]"
  end
end

def canon_float(x)
  t = json_stringify(x)
  if t == "null"
    raise(
      :eventlog_value,
      "#{to_s(x)} is not a finite number, and JSON cannot write it"
    )
  end
  t
end

@doc """
sorted_pairs: Pairs ordered by key text, in code-point order (what `compare` gives).
Raises when a pair is not [name, value] or two keys share one text.
"""
def sorted_pairs(pairs)
  checked = map(require_pair, as_list(pairs))
  sorted = sort_stable_by((p) -> key_text(first(p)), checked)
  texts = map((p) -> key_text(first(p)), sorted)
  dup = find_first((i) -> texts[i] == texts[i + 1], range(0, size(texts) - 1))
  if dup != nil
    raise(
      :eventlog_value,
      "key \"#{texts[dup]}\" is given twice; an object holds one value per key"
    )
  end
  sorted
end

def require_pair(p)
  if el_pair?(p) == false
    raise(
      :eventlog_value,
      "an object is a list of [key, value] pairs, and #{raifusaikuru::show(p)} is not one"
    )
  end
  p
end

@doc """
canon_object: The canonical text of an object given as [name, value] pairs; "{}" for none.

    canon_object([]) #=> "{}"
"""
def canon_object(pairs)
  "{#{join(map(canon_member, sorted_pairs(pairs)), ",")}}"
end

def canon_member(p)
  "#{json_stringify(key_text(first(p)))}:#{canon(p[1])}"
end

# ── names: what JSON keeps, and what the definition restores ──────────────

# The definition's names indexed by their text: a map from an event type's
# text to [type, keys], keys a map from a payload key's text to the key.
# Built once per log value, so restoring a name is a lookup, not a search.
# Raises :eventlog_use when two events, or two keys of one event, share a
# text: the log writes names as text and could not tell them apart.
def names(d)
  events = raifusaikuru::d_events(d)
  require_distinct(map((e) -> raifusaikuru::text(first(e)), events), "event")
  reduce(
    fn(m, e)
      assoc(m, raifusaikuru::text(first(e)), [first(e), key_index(e[1])])
    end,
    {},
    events
  )
end

def key_index(keys)
  require_distinct(
    map((k) -> raifusaikuru::text(k), as_list(keys)),
    "payload key"
  )
  reduce((m, k) -> assoc(m, raifusaikuru::text(k), k), {}, as_list(keys))
end

def require_distinct(texts, what)
  if size(unique(texts)) != size(texts)
    raise(
      :eventlog_use,
      "the definition has two of one #{what} name as text among #{raifusaikuru::show(texts)}; a log writes names as text and could not tell them apart"
    )
  end
end

@doc """
type_named: The type named by text `t`: the definition's own name, or the text itself.
"""
def type_named(names, t)
  hit = get(names, t)
  if hit.nil?
    t
  else
    first(hit)
  end
end

@doc """
key_named: The payload key named by text `k` for type `ty`: the key the definition
declares, or the text itself.
"""
def key_named(names, ty, k)
  hit = get(names, raifusaikuru::text(ty))
  key = if hit.nil?
    nil
  else
    get(hit[1], k)
  end
  if key.nil?
    k
  else
    key
  end
end

@doc """
normal_event: The event as the log holds it: its type and payload keys as the definition
names them (text where it names none), and every object in key order.
"""
def normal_event(names, ev)
  ty = type_named(names, raifusaikuru::text(raifusaikuru::ev_type(ev)))
  payload = map(
    (p) -> [key_named(names, ty, key_text(first(p))), normal_value(p[1])],
    sorted_pairs(raifusaikuru::ev_payload(ev))
  )
  raifusaikuru::ev(ty, raifusaikuru::ev_time(ev), payload)
end

@doc """
normal_value: A value with every object in it put in key order, which is all canonical
JSON changes about a value that survives it. Keys keep their kind, so a
keyword key still fails the round trip it cannot survive.
"""
def normal_value(v)
  if v.nil?
    nil
  elsif object?(v)
    map((p) -> [first(p), normal_value(p[1])], sorted_pairs(v))
  elsif list?(v)
    map(normal_value, v)
  else
    v
  end
end

# ── refusals and links ─────────────────────────────────────────────────────

@doc """
refusal_of: The refusal an admission verdict gives a record: nil when admitted, else
[kind, detail], the detail as text (the legal events, the missing keys, the
offending key or field, or the refusing rules).
"""
def refusal_of(verdict)
  if raifusaikuru::admitted?(verdict)
    nil
  else
    [
      raifusaikuru::reject_kind(verdict),
      detail_texts(
        raifusaikuru::reject_kind(verdict),
        raifusaikuru::reject_detail(verdict)
      )
    ]
  end
end

def detail_texts(kind, detail)
  if kind == :guard
    map((r) -> raifusaikuru::text(r), raifusaikuru::refused_rules(detail))
  elsif detail.nil?
    []
  elsif list?(detail)
    map((x) -> raifusaikuru::text(x), detail)
  else
    [raifusaikuru::text(detail)]
  end
end

def refusal_text(rf)
  if rf.nil?
    "null"
  else
    "{\"detail\":#{canon(rf[1])},\"kind\":#{json_stringify(raifusaikuru::text(first(rf)))}}"
  end
end

@doc """
normal_links: Links as the log holds them: [kind, id] pairs, the kind as text, in order.
"""
def normal_links(links)
  map(normal_link, as_list(links))
end

def normal_link(l)
  if list?(l) and
      size(l) == 2 and
      raifusaikuru::name?(first(l)) and
      string?(l[1])
    [raifusaikuru::text(first(l)), l[1]]
  else
    raise(
      :eventlog_value,
      "a link is [kind, id]: a name and a string, not #{raifusaikuru::show(l)}"
    )
  end
end

def links_text(links)
  "[#{join(map(link_text, links), ",")}]"
end

def link_text(l)
  "{\"id\":#{json_stringify(l[1])},\"kind\":#{json_stringify(first(l))}}"
end

# ── the record builders ────────────────────────────────────────────────────

@doc """
texts: The canonical text of each body field, in key order: entity, links,
payload, refusal, seq, status, time, type.
"""
def texts(entity, links, payload, refusal, seq, status, at, ty)
  [
    json_stringify(entity),
    links_text(links),
    canon_object(payload),
    refusal_text(refusal),
    to_s(seq),
    json_stringify(to_s(status)),
    to_s(at),
    json_stringify(raifusaikuru::text(ty))
  ]
end

@doc """
body_text: The text the chain hashes: the record without prev, hash and sig.
"""
def body_text(t)
  "{\"entity\":#{t[0]},\"links\":#{t[1]},\"payload\":#{t[2]},\"refusal\":#{t[3]},\"seq\":#{t[4]},\"status\":#{t[5]},\"time\":#{t[6]},\"type\":#{t[7]}}"
end

@doc """
line_text: The line a stream holds: every field, keys in code-point order.
"""
def line_text(t, prev, hash, sig)
  "{\"entity\":#{t[0]},\"hash\":\"#{hash}\",\"links\":#{t[1]},\"payload\":#{t[2]},\"prev\":\"#{prev}\",\"refusal\":#{t[3]},\"seq\":#{t[4]},\"sig\":#{sig_text(sig)},\"status\":#{t[5]},\"time\":#{t[6]},\"type\":#{t[7]}}"
end

def sig_text(sig)
  if sig.nil?
    "null"
  else
    json_stringify(sig)
  end
end

def status_for(refusal)
  if refusal.nil?
    :admitted
  else
    :refused
  end
end

# ── records ────────────────────────────────────────────────────────────────

@doc """
record: A record as read: [:el_record, position, seq, time, entity, type, payload,
links, status, refusal, prev, hash, sig, line]. position is the line's
index in the stream, from 0.
"""
def record(
  position,
  seq,
  at,
  entity,
  ty,
  payload,
  links,
  status,
  refusal,
  prev,
  hash,
  sig,
  line
)
  [
    :el_record,
    position,
    seq,
    at,
    entity,
    ty,
    payload,
    links,
    status,
    refusal,
    prev,
    hash,
    sig,
    line
  ]
end

def record?(x)
  first(x) == :el_record
end

# waive B0013: `position` is a builtin nisshi also uses, so the prefix stays; nisshi::position names it too
@doc """
el_position: The index of a record or a bad line in its stream, from 0.
"""
def el_position(x)
  x[1]
end

def rec_seq(r)
  r[2]
end

def rec_time(r)
  r[3]
end

def rec_entity(r)
  r[4]
end

@doc """
rec_type: The type: the definition's own name when it declares it, else text.
"""
def rec_type(r)
  r[5]
end

@doc """
rec_payload: The payload as [key, value] pairs in key order.
"""
def rec_payload(r)
  r[6]
end

@doc """
rec_links: The links as [kind, id] pairs, in the order they were given.
"""
def rec_links(r)
  r[7]
end

@doc """
rec_status: :admitted or :refused.
"""
def rec_status(r)
  r[8]
end

def rec_admitted?(r)
  r[8] == :admitted
end

@doc """
rec_refusal: nil, or [kind, detail] for a refused record.
"""
def rec_refusal(r)
  r[9]
end

def rec_prev(r)
  r[10]
end

def rec_hash(r)
  r[11]
end

@doc """
rec_sig: The signature's hex, or nil.
"""
def rec_sig(r)
  r[12]
end

@doc """
rec_line: The line exactly as the stream holds it.
"""
def rec_line(r)
  r[13]
end

@doc """
rec_event: The event a record holds, as raifusaikuru folds it.
"""
def rec_event(r)
  raifusaikuru::ev(rec_type(r), rec_time(r), rec_payload(r))
end

def texts_of(r)
  texts(
    rec_entity(r),
    rec_links(r),
    rec_payload(r),
    rec_refusal(r),
    rec_seq(r),
    rec_status(r),
    rec_time(r),
    rec_type(r)
  )
end

@doc """
body_of: The body text a record's hash covers, rendered from the record.
"""
def body_of(r)
  body_text(texts_of(r))
end

@doc """
line_of: The canonical line for a record: what its line must be, byte for byte.
"""
def line_of(r)
  line_text(texts_of(r), rec_prev(r), rec_hash(r), rec_sig(r))
end

@doc """
bad: A line that is not a record: [:el_bad_line, position, line, why].
"""
def bad(position, line, why)
  [:el_bad_line, position, line, why]
end

def bad_why(b)
  b[3]
end

# ── decoding a line ────────────────────────────────────────────────────────

@doc """
decode_line: A line read back as a record, or as a bad line saying why it is not one.
Total: nothing here raises, whatever the line holds.
"""
def decode_line(d, position, line)
  decode_named(names(d), position, line)
end

@doc """
decode_named: el_decode_line with the definition's names already indexed (el_names), as
read and append hold them.
"""
def decode_named(names, position, line)
  doc = json_parse(line) rescue :el_unreadable
  if doc == :el_unreadable
    bad(position, line, "not JSON")
  elsif is_doc(doc) == false
    bad(position, line, "not a JSON object")
  else
    decode_doc(names, position, line, doc)
  end
end

@doc """
decode_doc: Each field is read once, with deeta's total readers (nil for absent or of
the wrong type), then checked in order, stopping at the first problem.
"""
def decode_doc(names, position, line, doc)
  entity = get_str(doc, "entity", nil)
  seq = get_int(doc, "seq", nil)
  at = get_int(doc, "time", nil)
  ty_text = get_str(doc, "type", nil)
  status = get_str(doc, "status", nil)
  prev = get_str(doc, "prev", nil)
  hash = get_str(doc, "hash", nil)
  sig = as_json(doc, "sig")
  payload = as_json(doc, "payload")
  links = as_json(doc, "links")
  refusal = as_json(doc, "refusal")
  why = shape_problem(
    entity,
    seq,
    at,
    ty_text,
    status,
    prev,
    hash,
    sig,
    payload,
    links,
    refusal
  )
  if why != nil
    bad(position, line, "not a record: #{why}")
  else
    ty = type_named(names, ty_text)
    pairs = map(
      (p) -> [key_named(names, ty, first(p)), p[1]],
      payload_pairs(payload)
    )
    kinds = map((l) -> [get_str(l, "kind", ""), get_str(l, "id", "")], links)
    record(
      position,
      seq,
      at,
      entity,
      ty,
      pairs,
      kinds,
      status_of(status),
      refusal_from(refusal),
      prev,
      hash,
      sig,
      line
    )
  end
end

def payload_pairs(p)
  if object?(p)
    p
  else
    []
  end
end

def status_of(t)
  if t == "refused"
    :refused
  else
    :admitted
  end
end

def refusal_from(v)
  if v.nil?
    nil
  else
    [
      find_first(
        (k) -> raifusaikuru::text(k) == get_str(v, "kind", ""),
        refusal_kinds
      ),
      as_list(as_json(v, "detail"))
    ]
  end
end

@doc """
shape_problem: The first way a line's fields fail to make a record, as text, or nil.
"""
def shape_problem(
  entity,
  seq,
  at,
  ty_text,
  status,
  prev,
  hash,
  sig,
  payload,
  links,
  refusal
)
  if nonempty_string?(entity) == false
    "entity is not a non-empty string"
  elsif natural?(seq) == false
    "seq is not a whole number from 0"
  elsif integer?(at) == false
    "time is not a whole number"
  elsif nonempty_string?(ty_text) == false
    "type is not a non-empty string"
  elsif contains(["admitted", "refused"], status) == false
    "status is neither admitted nor refused"
  elsif is_hash_hex(prev) == false
    "prev is not a hash"
  elsif is_hash_hex(hash) == false
    "hash is not a hash"
  elsif sig_shape?(sig) == false
    "sig is neither null nor a string"
  elsif (object?(payload) or empty_object?(payload)) == false
    "payload is not an object"
  elsif links_shape?(links) == false
    "links is not a list of {id, kind} objects"
  elsif refusal_shape?(status, refusal) == false
    "refusal does not match status"
  end
end

def nonempty_string?(v)
  string?(v) and v != ""
end

def natural?(v)
  integer?(v) and v >= 0
end

def sig_shape?(v)
  v.nil? or string?(v)
end

def links_shape?(v)
  v != nil and list?(v) and count_where((l) -> link_shape?(l) == false, v) == 0
end

def link_shape?(l)
  object?(l) and
    string?(get_str(l, "kind", nil)) and
    string?(get_str(l, "id", nil))
end

def refusal_shape?(status, v)
  if status == "admitted"
    v.nil?
  else
    object?(v) and
      contains(
        map((k) -> raifusaikuru::text(k), refusal_kinds),
        get_str(v, "kind", nil)
      ) and
      texts_list?(as_json(v, "detail"))
  end
end

def texts_list?(v)
  v != nil and list?(v) and count_where((x) -> string?(x) == false, v) == 0
end

# ── the log value ──────────────────────────────────────────────────────────

@doc """
new: [:el_log, path, label, def, head, count, bytes, entities, index, last,
 records, signer, fault, names]. index maps an entity to [state, next seq].
records is the stream as read, or nil once the value has been appended to.
names is el_names(def).
"""
def new(path, label, d, bytes, records)
  [
    :el_log,
    path,
    label,
    d,
    genesis(label),
    0,
    bytes,
    [],
    {},
    nil,
    records,
    nil,
    nil,
    names(d)
  ]
end

def require_log(log)
  if (list?(log) and is_empty(log) == false and first(log) == :el_log) == false
    raise(:eventlog_use, "not a log value; get one from el_read or el_open")
  end
  log
end

def path(log)
  log[1]
end

@doc """
label: The label the stream's genesis is made from.
"""
def label(log)
  log[2]
end

# waive B0013: `def` is a reserved word, so the prefix stays; nisshi::def names it too
def el_def(log)
  log[3]
end

@doc """
head: The hash of the last record: what the next record's prev will be.
"""
def head(log)
  log[4]
end

# waive B0013: `count` is a builtin nisshi also uses, so the prefix stays; nisshi::count names it too
@doc """
el_count: How many lines the stream holds.
"""
def el_count(log)
  log[5]
end

@doc """
bytes: The stream's size in bytes when this value was read or last appended.
"""
def bytes(log)
  log[6]
end

@doc """
entities: The entities in the order they first appear.
"""
def entities(log)
  log[7]
end

def index(log)
  log[8]
end

# waive B0013: `last` is a builtin nisshi also uses, so the prefix stays; nisshi::last names it too
@doc """
el_last: The last record: after el_append, the record it wrote.
"""
def el_last(log)
  log[9]
end

@doc """
records: The records as read, in stream order, bad lines included. Raises once the
value has been appended to: a writer keeps no history, so read again.
"""
def records(log)
  require_log(log)
  if log[10].nil?
    raise(
      :eventlog_use,
      "this log value has been appended to, and a writer keeps no records; read the stream again"
    )
  end
  log[10]
end

def signer(log)
  log[11]
end

@doc """
fault: The position of the first line that is not a record, or nil.
"""
def fault(log)
  log[12]
end

def names_of(log)
  log[13]
end

@doc """
entry: An entity's [state, next seq]; an unseen entity is at its lifecycle's start.
"""
def entry(log, entity)
  have = get(index(log), entity)
  if have.nil?
    [raifusaikuru::initial(el_def(log)), 0]
  else
    have
  end
end

@doc """
state: An entity's lifecycle state: its admitted records, folded.
"""
def state(log, entity)
  first(entry(log, entity))
end

@doc """
seq_of: The seq an entity's next record will carry.
"""
def seq_of(log, entity)
  entry(log, entity)[1]
end

@doc """
states: Every entity's state, [entity, state], in the order entities first appear.
"""
def states(log)
  map((e) -> [e, state(log, e)], entities(log))
end

@doc """
signing: The log with a signing key: every record appended through it carries an
Ed25519 signature over its hash. The secret is a 32-byte seed in hex from
the caller; the log holds it in memory only.
"""
def signing(log, secret_hex)
  require_log(log)
  if is_hash_hex(secret_hex) == false
    raise(
      :eventlog_use,
      "a signing key is a 32-byte seed, as 64 lowercase hex characters"
    )
  end
  update_at(log, 11, secret_hex)
end

# ── one fold, shared by append and read ────────────────────────────────────

@doc """
absorb: Fold one line into the log, as read does. An admitted record steps its
entity's state (lc_step); a refused one only counts in its entity's seq; a
bad line marks the fault.
"""
def absorb(log, x)
  if record?(x)
    absorb_record(
      log,
      x,
      fold_record(el_def(log), state(log, rec_entity(x)), x)
    )
  else
    absorb_bad(log, x)
  end
end

@doc """
absorb_record: Advance the log past record `r`, its entity now in `state`. read passes
lc_step's state; append passes lc_admit_step's, which is lc_step's by
construction (both are lc_apply over one lc_judge), so they cannot differ.
"""
def absorb_record(log, r, state)
  e = rec_entity(r)
  have = get(index(log), e)
  next_seq = nisshi::next_seq(have)
  [
    :el_log,
    path(log),
    label(log),
    el_def(log),
    rec_hash(r),
    el_count(log) + 1,
    bytes(log),
    entities_with(entities(log), e, have != nil),
    assoc(index(log), e, [state, next_seq]),
    r,
    log[10],
    signer(log),
    fault(log),
    names_of(log)
  ]
end

def next_seq(have)
  if have.nil?
    1
  else
    have[1] + 1
  end
end

def absorb_bad(log, b)
  fault = if nisshi::fault(log).nil?
    el_position(b)
  else
    nisshi::fault(log)
  end
  update_at(update_at(log, 5, el_count(log) + 1), 12, fault)
end

def entities_with(entities, e, known)
  if known
    entities
  else
    push(entities, e)
  end
end

def fold_record(d, state, r)
  if rec_admitted?(r)
    raifusaikuru::step(d, state, rec_event(r))
  else
    state
  end
end

# ── read: the only I/O besides append ──────────────────────────────────────

@doc """
read: Read the stream at `path` (a missing file is an empty stream) and replay
every record into its entity's state. It verifies nothing; el_verify says
whether to trust what was read.
"""
def read(path, label, d)
  raifusaikuru::name(d)
  if path_exists(path)
    from_text(read_file(path), path, file_size(path), label, d)
  else
    from_text("", path, 0, label, d)
  end
end

@doc """
from_text: The log a stream's text reads as: el_read's work after the file is read.
Pure. A last line without its newline is a torn write, and a bad line.
"""
def from_text(text, path, bytes, label, d)
  lines = nisshi::lines(text)
  n = size(lines)
  torn = text != "" and ends_with?(text, line_break) == false
  names = nisshi::names(d)
  records = map(
    (i) -> decode_at(names, i, lines[i], torn and i == n - 1),
    range(0, n)
  )
  reduce(absorb, new(path, label, d, bytes, records), records)
end

def decode_at(names, i, line, is_torn)
  if is_torn
    bad(i, line, "no line terminator: the last write was cut short")
  else
    decode_named(names, i, line)
  end
end

@doc """
lines: A stream's lines: its text split on newlines, without the empty piece after
the final one.

    lines("") #=> []
"""
def lines(text)
  if text == ""
    []
  elsif ends_with?(text, line_break)
    all_but_last(split(text, line_break))
  else
    split(text, line_break)
  end
end

@doc """
open: The writer's door: read the stream, verify it (signatures too, given a
public key), and return the log ready to append to. A broken stream raises
:eventlog_broken naming the position and the kind of break.
"""
def open(path, label, d, public_hex)
  log = read(path, label, d)
  rep = verify(log, public_hex, nil)
  if intact?(rep) == false
    raise(
      :eventlog_broken,
      "#{path}: position #{to_s(break_position(rep))}, #{to_s(break_kind(rep))}: #{break_why(rep)}"
    )
  end
  log
end

# ── append: the only function that writes ──────────────────────────────────

# waive B0013: `append` is a builtin nisshi also uses, so the prefix stays; nisshi::append names it too
@doc """
el_append: Append `event` (an lc_ev) for `entity`, with `links` ([kind, id] pairs, []
for none), and return the log advanced past it; el_last is the new record,
exactly as a later read returns it. An admitted event steps the entity's
state. A refused one is written too, marked refused with its reason, and
steps nothing. Raises before writing when the event is malformed
(:eventlog_value), the log value is stale (:eventlog_stale) or the stream is
broken (:eventlog_broken).
"""
def el_append(log, entity, event, links)
  write(log, entity, event, links, false)
end

@doc """
observe: Append an event a device OBSERVED: it happened, whatever the guard said. A
fryer's current sensor that sees a load while the controller reports locked
has not made an attempt the log may refuse; it has recorded a fact. So a
gated event whose guard refuses is written ADMITTED, and every replay
applies it and keeps it in lc_breaches, which is raifusaikuru's own rule for
an event that happened anyway (lc_step). Everything else is el_append's:
an event the lifecycle cannot take at all (no row from the current state, an
unknown type, a missing key) is written refused, as the fold would refuse
it on replay. el_last(log) is the record, as a later read returns it.
"""
def observe(log, entity, event, links)
  write(log, entity, event, links, true)
end

@doc """
write: The one writer behind el_append (an attempt: a guard refusal is written
refused) and el_observe (a fact: a guard refusal is written admitted, and
the state after it carries the breach).
"""
def write(log, entity, event, links, observed)
  require_writable(log)
  require_entity(entity)
  require_event(event)
  d = el_def(log)
  path = nisshi::path(log)
  on_disk = bytes_on_disk(path)
  if on_disk != bytes(log)
    raise(
      :eventlog_stale,
      "#{path} holds #{to_s(on_disk)} bytes and this log value knows #{to_s(bytes(log))}: the stream changed since the value was read. Read it again."
    )
  end
  names = names_of(log)
  ev = normal_event(names, event)
  entry = nisshi::entry(log, entity)
  judged = raifusaikuru::admit_step(d, first(entry), ev)
  refusal = refusal_as(first(judged), observed)
  texts = nisshi::texts(
    entity,
    normal_links(links),
    raifusaikuru::ev_payload(ev),
    refusal,
    entry[1],
    status_for(refusal),
    raifusaikuru::ev_time(ev),
    raifusaikuru::ev_type(ev)
  )
  prev = head(log)
  hash = chain_link(prev, body_text(texts))
  line = line_text(texts, prev, hash, sign(signer(log), hash))
  r = decode_named(names, el_count(log), line)
  require_round_trip(r, line, ev)
  append_file(path, unlines([line]))
  absorb_record(
    update_at(update_at(log, 10, nil), 6, bytes_on_disk(path)),
    r,
    state_after(first(entry), judged, refusal)
  )
end

@doc """
refusal_as: The refusal a record is written with: an attempt's is el_refusal_of's; an
observed event's guard refusal is none, because the event happened (the
step lc_admit_step took applied it and recorded the breach).
"""
def refusal_as(verdict, observed)
  if observed and
      raifusaikuru::admitted?(verdict) == false and
      raifusaikuru::reject_kind(verdict) == :guard
    nil
  else
    refusal_of(verdict)
  end
end

@doc """
state_after: The entity's state after an append: the step's when admitted, unchanged
when refused.
"""
def state_after(state, judged, refusal)
  if refusal.nil?
    judged[1]
  else
    state
  end
end

def sign(secret, hash)
  if secret.nil?
    nil
  else
    sign_message(secret, hash)
  end
end

def bytes_on_disk(path)
  if path_exists(path)
    file_size(path)
  else
    0
  end
end

def require_writable(log)
  require_log(log)
  if path(log).nil?
    raise(
      :eventlog_use,
      "this log value was read from text, not a file, so it cannot be appended to"
    )
  end
  if fault(log) != nil
    raise(
      :eventlog_broken,
      "position #{to_s(fault(log))} of #{path(log)} is not a record; a broken stream cannot grow"
    )
  end
end

def require_entity(entity)
  if nonempty_string?(entity) == false
    raise(
      :eventlog_value,
      "an entity id is a non-empty string, not #{raifusaikuru::show(entity)}"
    )
  end
end

def require_event(ev)
  if (
      list?(ev) and
      size(ev) == 3 and
      raifusaikuru::name?(raifusaikuru::ev_type(ev)) and
      integer?(raifusaikuru::ev_time(ev)) and
      list?(ev[2])
    ) == false
    raise(
      :eventlog_value,
      "an event is lc_ev(type, time, payload): a name, a whole-number time and [key, value] pairs, not #{raifusaikuru::show(ev)}"
    )
  end
end

@doc """
require_round_trip: Refuse to write a line that does not read back as the record it renders
and the event that was judged.
"""
def require_round_trip(r, line, ev)
  if record?(r) == false
    raise(
      :eventlog_internal,
      "a rendered line did not parse as a record: #{bad_why(r)}"
    )
  end
  if line_of(r) != line
    raise(:eventlog_internal, "a rendered line is not canonical: #{line}")
  end
  if rec_event(r) != ev
    raise(
      :eventlog_value,
      "the event would not read back as written; JSON keeps strings, numbers, true/false, nil and lists, and a keyword inside a value (a key or an element) comes back as a string"
    )
  end
end

# ── verify ─────────────────────────────────────────────────────────────────

@doc """
verify: Walk the stream and report the first break, or that it is intact:
  [:el_intact, count, head]
  [:el_broken, position, kind, why]   kind is one of el_break_kinds()
With `public_hex`, every record must carry a signature that verifies under
it. With `expected_head` (a head recorded elsewhere), the stream must end
exactly there: the only way a line dropped from the END can be seen. Pure.
"""
def verify(log, public_hex, expected_head)
  require_log(log)
  if public_hex != nil and is_hash_hex(public_hex) == false
    raise(:eventlog_use, "a public key is 64 lowercase hex characters")
  end
  records = nisshi::records(log)
  bad = find_first((x) -> record?(x) == false, records)
  good = before_bad(records, bad)
  texts = map(texts_of, good)
  g = genesis(label(log))
  found = filter(
    (b) -> b != nil,
    [
      break_bad(bad),
      break_chain(g, good, texts),
      break_canon(good, texts),
      break_seq(good),
      break_sig(good, public_hex)
    ]
  )
  earliest = reduce(earlier, nil, found)
  head = head_of(g, good)
  if earliest != nil
    [:el_broken, earliest[0], earliest[1], earliest[2]]
  elsif expected_head != nil and expected_head != head
    [
      :el_broken,
      size(records),
      :head,
      "the stream ends at #{head}, not at the head recorded for it: lines are missing from its end, or were added after it"
    ]
  else
    [:el_intact, size(records), head]
  end
end

def before_bad(records, bad)
  if bad.nil?
    records
  else
    take_n(records, el_position(bad))
  end
end

def head_of(g, good)
  if is_empty(good)
    g
  else
    rec_hash(retsu::last(good))
  end
end

def earlier(best, b)
  if best.nil? or first(b) < first(best)
    b
  else
    best
  end
end

def break_bad(bad)
  if bad.nil?
    nil
  else
    [el_position(bad), :unparseable, bad_why(bad)]
  end
end

@doc """
break_chain: The first record the chain does not reproduce (shomei's chain_first_break),
named :prev when its prev is not the hash before it (a line is missing or
out of order) and :hash when its content changed.
"""
def break_chain(g, good, texts)
  p = chain_first_break(g, map(body_text, texts), map(rec_hash, good))
  if p.nil?
    nil
  elsif rec_prev(good[p]) != head_of(g, take_n(good, p))
    [
      p,
      :prev,
      "the record does not follow the one before it: a line is missing or out of order here"
    ]
  else
    [
      p,
      :hash,
      "the record's content does not match its hash: the line was changed after it was written"
    ]
  end
end

def break_canon(good, texts)
  i = find_first(
    (k) -> canonical_at?(good[k], texts[k]) == false,
    range(0, size(good))
  )
  if i.nil?
    nil
  else
    [
      el_position(good[i]),
      :not_canonical,
      "the line is not the canonical rendering of its record: its bytes changed (spacing, key order or escaping) after it was written"
    ]
  end
end

def canonical_at?(r, t)
  line_text(t, rec_prev(r), rec_hash(r), rec_sig(r)) == rec_line(r)
end

def break_seq(good)
  reduce(seq_step, [{}, nil], good)[1]
end

def seq_step(acc, r)
  if acc[1] != nil
    acc
  else
    seen = get(first(acc), rec_entity(r))
    expect = if seen.nil?
      0
    else
      seen
    end
    if rec_seq(r) == expect
      [assoc(first(acc), rec_entity(r), expect + 1), nil]
    else
      [
        first(acc),
        [
          el_position(r),
          :seq,
          "#{rec_entity(r)} expects seq #{to_s(expect)} here and the record says #{to_s(rec_seq(r))}"
        ]
      ]
    end
  end
end

def break_sig(good, public_hex)
  if public_hex.nil?
    nil
  else
    sig_break(find_first((r) -> sig_ok?(r, public_hex) == false, good))
  end
end

def sig_break(r)
  if r.nil?
    nil
  elsif rec_sig(r).nil?
    [el_position(r), :unsigned, "the record carries no signature"]
  else
    [
      el_position(r),
      :signature,
      "the signature does not verify under the given public key"
    ]
  end
end

def sig_ok?(r, public_hex)
  if string?(rec_sig(r))
    (verify_message(public_hex, rec_hash(r), rec_sig(r)) rescue false) == true
  else
    false
  end
end

@doc """
intact?: True for a report of an intact stream.
"""
def intact?(rep)
  first(rep) == :el_intact
end

@doc """
break_position: The position of a broken report's first break, from 0.
"""
def break_position(rep)
  rep[1]
end

def break_kind(rep)
  rep[2]
end

def break_why(rep)
  rep[3]
end

# ── history: the state after every record ──────────────────────────────────

@doc """
history: Every record with its entity's state after it, [record, state], in stream
order; bad lines are left out. The same fold as read (el_fold_record), so an
entity's last state here is el_state's, and a refused record's state is the
one before it. What a reader needs to see state change over time (an
analytics layer) without folding a second way. Reads el_records, so it takes
a value that was read, not one that was appended to.
"""
def history(log)
  d = el_def(log)
  records = filter(record?, nisshi::records(log))
  retsu::last(reduce((acc, r) -> history_step(d, acc, r), [{}, []], records))
end

@doc """
history_step: One record into the history: [states by entity, rows so far].
"""
def history_step(d, acc, r)
  e = rec_entity(r)
  have = get(first(acc), e)
  before = if have.nil?
    raifusaikuru::initial(d)
  else
    have
  end
  state = fold_record(d, before, r)
  [assoc(first(acc), e, state), push(acc[1], [r, state])]
end

@doc """
state_at: An entity's state AS OF `time`: its records at or before `time`, folded
the way read folds them (el_fold_record: admitted records step, refused ones
do not). What a reader needs to say what the log knew when something else
happened (the oil's state when an order was fried), and the fold's twin of
anaritikusu's as-of join, which answers the same question in SQL. An entity
with no record by then is at its lifecycle's start. Like that join, it
assumes an entity's times never decrease along its stream (neither checks
it). Reads el_records, so it takes a value that was read.

One question, one fold: a reader asking about many entities or times reads
el_history once instead (the state after every record, folded once) and
looks states up. Measured 2026-09-25 on NuPastel's journey lines, 200
orders: re-folding per question 2.56 s, looking up in one history 0.27 s.
"""
def state_at(log, entity, time)
  d = el_def(log)
  records = filter(
    (x) -> record?(x) and rec_entity(x) == entity and rec_time(x) <= time,
    nisshi::records(log)
  )
  reduce((s, r) -> fold_record(d, s, r), raifusaikuru::initial(d), records)
end

# ── grouping ───────────────────────────────────────────────────────────────

@doc """
by_entity: The records grouped by entity: [[entity, records]] in the order entities
first appear, each group in stream order. Bad lines are left out.

    by_entity([]) #=> []
"""
def by_entity(records)
  acc = reduce(group_add, [[], {}], filter(record?, as_list(records)))
  map((e) -> [e, reverse(get(acc[1], e))], first(acc))
end

def group_add(a, r)
  e = rec_entity(r)
  have = get(a[1], e)
  if have.nil?
    [push(first(a), e), assoc(a[1], e, [r])]
  else
    [first(a), assoc(a[1], e, cons(r, have))]
  end
end

# ── a worked stream ────────────────────────────────────────────────────────

@doc """
example_events: `n` events over `k` of raifusaikuru's example consumables, interleaved:
event i is item (i mod k)'s (i div k)-th step. Each item is read, opened,
then used, with a fresh reading every 25th step; every 10th event links a
batch. The guard refuses a use once 40 are spent or the reading is 4 h old,
so a long stream holds refusals as well as admissions. Time moves 10 s an
event. Each element is [entity, event, links].
"""
def example_events(n, k)
  map((i) -> example_event(i, k), range(0, n))
end

def example_event(i, k)
  [
    "item-#{to_s(i % k)}",
    example_step(floor(i / k), 1000 + i * 10),
    example_links(i)
  ]
end

def example_step(step, at)
  if step == 0
    raifusaikuru::ev(:reading, at, [[:value, 10]])
  elsif step == 1
    raifusaikuru::ev(:open, at, [])
  elsif step % 25 == 0
    raifusaikuru::ev(:reading, at, [[:value, 10 + step % 7]])
  else
    raifusaikuru::ev(:use, at, [])
  end
end

def example_links(i)
  if i % 10 == 0
    [[:batch, "B-#{to_s(floor(i / 100))}"]]
  else
    []
  end
end

@doc """
append_all: Append every [entity, event, links] in order.
"""
def append_all(log, items)
  reduce((l, x) -> el_append(l, first(x), x[1], x[2]), log, items)
end

@doc """
test_path: A fresh path under TMPDIR for a test's stream.
"""
def test_path(name)
  path_join(getenv("TMPDIR", "/tmp"), "nisshi-#{name}-#{to_s(now_ns)}.jsonl")
end

# ── tests ──────────────────────────────────────────────────────────────────

test "the empty stream: no file, an empty file and empty text all read as no records at the genesis, intact"
  d = raifusaikuru::example_consumable
  g = genesis("nisshi-test")
  p = test_path("empty")
  log = read(p, "nisshi-test", d)
  assert el_count(log) == 0
  assert head(log) == g
  assert records(log) == []
  assert entities(log) == []
  assert el_last(log).nil?
  assert state(log, "item-1") == raifusaikuru::initial(d)
  assert seq_of(log, "item-1") == 0
  assert verify(log, nil, nil) == [:el_intact, 0, g]
  assert verify(log, nil, g) == [:el_intact, 0, g]
  write_file(p, "")
  assert verify(read(p, "nisshi-test", d), nil, g) == [:el_intact, 0, g]
  rm(p)
  assert el_count(from_text("", nil, 0, "nisshi-test", d)) == 0
  assert lines("") == []
  assert genesis("other") != g
end

test "an identity: append then read gives back every record and every state, and reading twice is the same"
  d = raifusaikuru::example_consumable
  p = test_path("identity")
  items = concat_lists(
    example_events(60, 3),
    [
      ["item-z", raifusaikuru::ev(:use, 5000, []), []],
      ["item-0", raifusaikuru::ev(:fly, 5010, []), []]
    ]
  )
  steps = reduce(
    (acc, x) -> identity_step(acc, x),
    [read(p, "nisshi-test", d), []],
    items
  )
  log = first(steps)
  r1 = read(p, "nisshi-test", d)
  r2 = read(p, "nisshi-test", d)
  rm(p)
  assert el_count(r1) == 62
  assert records(r1) == steps[1]
  assert records(r2) == records(r1)
  assert states(r1) == states(log)
  assert states(r2) == states(r1)
  assert head(r1) == head(log)
  assert entities(r1) == ["item-0", "item-1", "item-2", "item-z"]
  # The differential: each state is what raifusaikuru alone folds from that
  # entity's admitted events.
  assert map(
    fn(grp)
      [
        first(grp),
        raifusaikuru::state_of(d, map(rec_event, filter(rec_admitted?, grp[1])))
      ]
    end,
    by_entity(records(r1))
  ) == states(r1)
  assert intact?(verify(r1, nil, head(log)))
end

def identity_step(acc, x)
  l = el_append(first(acc), first(x), x[1], x[2])
  [l, push(acc[1], el_last(l))]
end

test "a refused event is written, marked with its reason, counted in seq, and folded into nothing"
  d = raifusaikuru::example_consumable
  p = test_path("refused")
  l1 = el_append(
    read(p, "nisshi-test", d),
    "item-1",
    raifusaikuru::ev(:use, 1000, []),
    []
  )
  r = el_last(l1)
  assert rec_status(r) == :refused
  assert rec_refusal(r) == [:no_edge, ["open", "reading", "discard"]]
  assert state(l1, "item-1") == raifusaikuru::initial(d)
  assert seq_of(l1, "item-1") == 1
  assert el_count(l1) == 1
  l2 = append_all(
    l1,
    [
      ["item-1", raifusaikuru::ev(:reading, 1100, [[:value, 26]]), []],
      ["item-1", raifusaikuru::ev(:open, 1200, []), []],
      ["item-1", raifusaikuru::ev(:use, 1300, []), []]
    ]
  )
  assert rec_refusal(el_last(l2)) == [:guard, ["quality_ok"]]
  assert raifusaikuru::value(state(l2, "item-1"), :uses) == 0
  assert raifusaikuru::breaches(state(l2, "item-1")) == []
  assert raifusaikuru::refused(state(l2, "item-1")) == []
  l3 = el_append(l2, "item-1", raifusaikuru::ev(:fly, 1400, []), [])
  assert rec_refusal(el_last(l3)) == [:unknown_event, []]
  assert rec_type(el_last(l3)) == "fly"
  back = records(read(p, "nisshi-test", d))
  rm(p)
  assert map(rec_status, back) ==
    [:refused, :admitted, :admitted, :refused, :refused]
  assert map(rec_seq, back) == [0, 1, 2, 3, 4]
  assert retsu::last(back) == el_last(l3)
end

@doc """
doc_stream: The stream the b3sum test pins: three events for one item, signed with RFC
8032 TEST 1's key.
"""
def doc_stream(p)
  d = raifusaikuru::example_consumable
  log = signing(
    read(p, "nisshi-doc", d),
    "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  )
  append_all(
    log,
    [
      ["item-1", raifusaikuru::ev(:reading, 1000, [[:value, 10]]), []],
      ["item-1", raifusaikuru::ev(:use, 1100, []), []],
      ["item-1", raifusaikuru::ev(:open, 2000, []), [[:batch, "B-7"]]]
    ]
  )
end

test "values checked independently: the genesis and every hash by b3sum, the signature by openssl"
  # The bytes, from the documented format (shomei's two lines; the body keys
  # in code-point order), hashed with b3sum 1.8.2:
  #   genesis  "blue-chain/v1/genesis\nnisshi/1\nnisshi-doc"
  #   link i   "blue-chain/v1/link\n" + prev + "\n" + body i
  # and the signature over hash 0's 64 hex characters by `openssl pkeyutl
  # -sign -rawin` (OpenSSL 3.6.2) with RFC 8032 TEST 1's seed.
  p = test_path("doc")
  log = doc_stream(p)
  read_back = read(p, "nisshi-doc", raifusaikuru::example_consumable)
  back = records(read_back)
  rm(p)
  assert genesis("nisshi-doc") ==
    "0a42d546253d153e4253d118781c1b773338b3dd532373a12a83accd79e7cba2"
  assert map(rec_hash, back) ==
    [
      "9172aea16c9c2cb304ee3d624c0a79be88ca7537769f3386b64aa55b273dc412",
      "c0a4ffe9fe283b42e163c6ef6b722139699dc07dc1626520e65600acf08d062e",
      "f2b9bb297775ea19093808d056e5988ac629c6938dd7917d7c7f545d04f0c2a3"
    ]
  assert head(log) ==
    "f2b9bb297775ea19093808d056e5988ac629c6938dd7917d7c7f545d04f0c2a3"
  assert body_of(back[0]) ==
    "{\"entity\":\"item-1\",\"links\":[],\"payload\":{\"value\":10},\"refusal\":null,\"seq\":0,\"status\":\"admitted\",\"time\":1000,\"type\":\"reading\"}"
  assert body_of(back[1]) ==
    "{\"entity\":\"item-1\",\"links\":[],\"payload\":{},\"refusal\":{\"detail\":[\"open\",\"reading\",\"discard\"],\"kind\":\"no_edge\"},\"seq\":1,\"status\":\"refused\",\"time\":1100,\"type\":\"use\"}"
  assert body_of(back[2]) ==
    "{\"entity\":\"item-1\",\"links\":[{\"id\":\"B-7\",\"kind\":\"batch\"}],\"payload\":{},\"refusal\":null,\"seq\":2,\"status\":\"admitted\",\"time\":2000,\"type\":\"open\"}"
  assert rec_line(back[0]) ==
    "{\"entity\":\"item-1\",\"hash\":\"9172aea16c9c2cb304ee3d624c0a79be88ca7537769f3386b64aa55b273dc412\",\"links\":[],\"payload\":{\"value\":10},\"prev\":\"0a42d546253d153e4253d118781c1b773338b3dd532373a12a83accd79e7cba2\",\"refusal\":null,\"seq\":0,\"sig\":\"7b5e40341db5adfbcc2ba97c7ff76d5d47ba452a4a5eeb761a973340cda7099fe8906491d3e3e3c298106f3a48a9bd874f3a63b162cc148a08e939c16cd2a80b\",\"status\":\"admitted\",\"time\":1000,\"type\":\"reading\"}"
  assert verify(
    read_back,
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    head(log)
  ) == [:el_intact, 3, head(log)]
end

@doc """
control_lines: A signed stream of five records over two items, as its lines: the base the
controls below damage one way each.
"""
def control_lines(p, secret)
  log = signing(
    read(p, "nisshi-test", raifusaikuru::example_consumable),
    secret
  )
  items = [
    ["item-1", raifusaikuru::ev(:reading, 1000, [[:value, 10]]), []],
    ["item-1", raifusaikuru::ev(:open, 1100, []), []],
    ["item-1", raifusaikuru::ev(:use, 1200, []), []],
    ["item-1", raifusaikuru::ev(:use, 1300, []), []],
    ["item-2", raifusaikuru::ev(:reading, 1400, [[:value, 11]]), []]
  ]
  done = append_all(log, items)
  lines = nisshi::lines(read_file(p))
  rm(p)
  [lines, head(done)]
end

@doc """
control_rows: One damaged copy per break kind: [kind, text, public key, expected head,
position]. `k` and `other` are two keypairs; the stream is signed with `k`.
"""
def control_rows(lines, head, k, other)
  pub = keypair_public(k)
  line2 = lines[2]
  line3 = lines[3]
  r3 = decode_line(raifusaikuru::example_consumable, 3, line3)
  forged = replace(
    line3,
    rec_sig(r3),
    sign_message(keypair_secret(other), rec_hash(r3))
  )
  unsigned = replace(line3, "\"sig\":\"#{rec_sig(r3)}\"", "\"sig\":null")
  [
    [:unparseable, unlines(update_at(lines, 2, "not json")), pub, nil, 2],
    [:unparseable, join(lines, line_break), pub, nil, 4],
    [
      :hash,
      unlines(
        update_at(lines, 2, replace(line2, "\"time\":1200", "\"time\":1201"))
      ),
      pub,
      nil,
      2
    ],
    [:prev, unlines(remove_at(lines, 2)), pub, nil, 2],
    [
      :prev,
      unlines(update_at(update_at(lines, 1, line2), 2, lines[1])),
      pub,
      nil,
      1
    ],
    [
      :not_canonical,
      unlines(
        update_at(lines, 1, replace(lines[1], "{\"entity\"", "{ \"entity\""))
      ),
      pub,
      nil,
      1
    ],
    [:seq, unlines(wrong_seq_lines(lines, keypair_secret(k))), pub, nil, 4],
    [:unsigned, unlines(update_at(lines, 3, unsigned)), pub, nil, 3],
    [:signature, unlines(update_at(lines, 3, forged)), pub, nil, 3],
    [:signature, unlines(lines), keypair_public(other), nil, 0],
    [:head, unlines(all_but_last(lines)), pub, head, 4]
  ]
end

@doc """
wrong_seq_lines: The stream with its last record rewritten to claim seq 1 for item-2's first
record, re-hashed and re-signed: a writer's bug the chain alone accepts.
"""
def wrong_seq_lines(lines, secret)
  d = raifusaikuru::example_consumable
  r = decode_line(d, 4, lines[4])
  texts = nisshi::texts(
    rec_entity(r),
    rec_links(r),
    rec_payload(r),
    rec_refusal(r),
    1,
    rec_status(r),
    rec_time(r),
    rec_type(r)
  )
  hash = chain_link(rec_prev(r), body_text(texts))
  update_at(
    lines,
    4,
    line_text(texts, rec_prev(r), hash, sign_message(secret, hash))
  )
end

def control_verdict(row)
  rep = verify(
    from_text(row[1], nil, 0, "nisshi-test", raifusaikuru::example_consumable),
    row[2],
    row[3]
  )
  [break_kind(rep), break_position(rep)]
end

test "controls: a changed, dropped or reordered line, a wrong signature and every other break, each found at its position"
  k = signing_keypair("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  other = signing_keypair("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
  base = control_lines(test_path("controls"), keypair_secret(k))
  lines = first(base)
  head = base[1]
  intact = verify(
    from_text(
      unlines(lines),
      nil,
      0,
      "nisshi-test",
      raifusaikuru::example_consumable
    ),
    keypair_public(k),
    head
  )
  assert intact == [:el_intact, 5, head]
  rows = control_rows(lines, head, k, other)
  assert map(control_verdict, rows) == map((row) -> [first(row), row[4]], rows)
  # Dropping the LAST line is invisible without the recorded head.
  assert intact?(
    verify(
      from_text(
        unlines(all_but_last(lines)),
        nil,
        0,
        "nisshi-test",
        raifusaikuru::example_consumable
      ),
      keypair_public(k),
      nil
    )
  )
  # Every break kind has a row: a new kind without one fails here.
  assert set_equal(unique(map((row) -> first(row), rows)), break_kinds)
end

test "append raises before writing on what JSON cannot hold, and on a malformed call"
  d = raifusaikuru::example_consumable
  p = test_path("values")
  l0 = read(p, "nisshi-test", d)
  bad_calls = [
    fn()
      el_append(
        l0,
        "item-1",
        raifusaikuru::ev(:reading, 1000, [[:value, :high]]),
        []
      )
    end,
    fn()
      el_append(
        l0,
        "item-1",
        raifusaikuru::ev(:reading, 1000, [[:value, [[:grade, 1]]]]),
        []
      )
    end,
    fn()
      el_append(
        l0,
        "item-1",
        raifusaikuru::ev(:reading, 1000, [[:value, 1], [:value, 2]]),
        []
      )
    end,
    fn()
      el_append(
        l0,
        "item-1",
        raifusaikuru::ev(
          :reading,
          1000,
          [[:value, expt(10.0, 300) * expt(10.0, 300)]]
        ),
        []
      )
    end,
    fn()
      el_append(
        l0,
        "item-1",
        raifusaikuru::ev(:reading, 1000.5, [[:value, 1]]),
        []
      )
    end,
    () -> el_append(l0, "", raifusaikuru::ev(:open, 1000, []), []),
    fn()
      el_append(l0, "item-1", raifusaikuru::ev(:open, 1000, []), [[:batch, 7]])
    end,
    () -> el_append(l0, "item-1", [:open], [])
  ]
  assert map(
    fn(call)
      error?(
        begin
          call()
        rescue e
          e
        end
      )
    end,
    bad_calls
  ) == repeat(true, size(bad_calls))
  assert path_exists(p) == false
  # The control: the same call with a JSON value goes through.
  l1 = el_append(
    l0,
    "item-1",
    raifusaikuru::ev(:reading, 1000, [[:value, "high"]]),
    []
  )
  assert raifusaikuru::value(state(l1, "item-1"), :quality) == "high"
  rm(p)
end

test "a stale log value cannot write, a written-through value keeps no records, and a broken stream cannot grow"
  d = raifusaikuru::example_consumable
  p = test_path("writers")
  l0 = read(p, "nisshi-test", d)
  l1 = el_append(l0, "item-1", raifusaikuru::ev(:open, 1000, []), [])
  assert error?(
    begin
      el_append(l0, "item-1", raifusaikuru::ev(:open, 1100, []), [])
    rescue e
      e
    end
  )
  assert el_count(read(p, "nisshi-test", d)) == 1
  assert error?(
    begin
      records(l1)
    rescue e
      e
    end
  )
  l2 = el_append(l1, "item-1", raifusaikuru::ev(:use, 1100, []), [])
  assert el_count(l2) == 2
  append_file(p, unlines(["not a record"]))
  broken = read(p, "nisshi-test", d)
  assert fault(broken) == 2
  assert error?(
    begin
      el_append(broken, "item-1", raifusaikuru::ev(:use, 1200, []), [])
    rescue e
      e
    end
  )
  assert error?(
    begin
      open(p, "nisshi-test", d, nil)
    rescue e
      e
    end
  )
  assert el_count(read(p, "nisshi-test", d)) == 3
  rm(p)
  # The control: el_open on an intact stream opens it.
  p2 = test_path("writers-ok")
  el_append(
    read(p2, "nisshi-test", d),
    "item-1",
    raifusaikuru::ev(:open, 1000, []),
    []
  )
  assert el_count(open(p2, "nisshi-test", d, nil)) == 1
  rm(p2)
  # A definition naming two events :go and "go" is sound to raifusaikuru and
  # unusable here: both would be written "go".
  two = lc_define(
    :two,
    [
      raifusaikuru::states([:a, :b]),
      raifusaikuru::start(:a),
      raifusaikuru::terminals([:b]),
      raifusaikuru::event(:go, []),
      raifusaikuru::event("go", []),
      raifusaikuru::on(:a, :go, :b, []),
      raifusaikuru::on(:a, "go", :b, [])
    ]
  )
  assert error?(
    begin
      read(p2, "nisshi-test", two)
    rescue e
      e
    end
  )
end

test "links are carried faithfully: kinds as text, ids, order and duplicates, in the hash"
  d = raifusaikuru::example_consumable
  p = test_path("links")
  l1 = el_append(
    read(p, "nisshi-test", d),
    "order-1",
    raifusaikuru::ev(:reading, 1000, [[:value, 1]]),
    [[:pack, "P-17"], [:pack, "P-18"], ["oil", "O-3"], [:pack, "P-17"]]
  )
  want = [["pack", "P-17"], ["pack", "P-18"], ["oil", "O-3"], ["pack", "P-17"]]
  assert rec_links(el_last(l1)) == want
  assert contains?(
    rec_line(el_last(l1)),
    "\"links\":[{\"id\":\"P-17\",\"kind\":\"pack\"},{\"id\":\"P-18\",\"kind\":\"pack\"},{\"id\":\"O-3\",\"kind\":\"oil\"},{\"id\":\"P-17\",\"kind\":\"pack\"}]"
  )
  assert rec_links(first(records(read(p, "nisshi-test", d)))) == want
  lines = nisshi::lines(read_file(p))
  rm(p)
  # A link changed after writing breaks the hash.
  swapped = replace(first(lines), "O-3", "O-4")
  assert break_kind(
    verify(from_text(unlines([swapped]), nil, 0, "nisshi-test", d), nil, nil)
  ) == :hash
end

test "canonical JSON: sorted keys, no spaces, the runtime's shapes, and serde writes the same bytes"
  assert canon([["b", 1], ["a", [1, "x", nil, true, 1.5]]]) ==
    "{\"a\":[1,\"x\",null,true,1.5],\"b\":1}"
  assert canon([]) == "[]"
  assert canon_object([]) == "{}"
  assert canon([[:z, [["y", 2], ["x", 1]]]]) == "{\"z\":{\"x\":1,\"y\":2}}"
  assert canon(unlines(["é \"q\""])) == "\"é \\\"q\\\"\\n\""
  assert canon([nil]) == "[null]"
  assert error?(
    begin
      canon(:k)
    rescue e
      e
    end
  )
  assert error?(
    begin
      canon([["a", 1], ["a", 2]])
    rescue e
      e
    end
  )
  d = raifusaikuru::example_consumable
  p = test_path("canon")
  l1 = el_append(
    read(p, "nisshi-test", d),
    "item-é",
    raifusaikuru::ev(
      :reading,
      1000,
      [
        [:value, 10],
        ["note", unlines(["óleo \"novo\""])],
        ["tags", [["b", 2], ["a", [1.25, false]]]]
      ]
    ),
    []
  )
  line = rec_line(el_last(l1))
  rm(p)
  # serde_json, parsing and re-writing the line independently, gives back the
  # same bytes: the keys are in its order and the escapes are its escapes.
  assert json_stringify(json_parse(line)) == line
  assert line_of(decode_line(d, 0, line)) == line
  assert lookup(rec_payload(el_last(l1)), :value) == 10
  assert lookup(rec_payload(el_last(l1)), "tags") ==
    [["a", [1.25, false]], ["b", 2]]
end

test "history: the state after every record, from read's own fold"
  d = raifusaikuru::example_consumable
  # The empty case.
  assert history(from_text("", nil, 0, "nisshi-test", d)) == []
  # A value checked by hand: the doc stream is a reading (admitted), a use
  # while sealed (refused) and an open (admitted), so the phases after each
  # are sealed, sealed, open, and the refused use changes nothing.
  p = test_path("history")
  log = doc_stream(p)
  back = read(p, "nisshi-doc", d)
  rm(p)
  h = history(back)
  assert map((x) -> [rec_seq(first(x)), raifusaikuru::phase(x[1])], h) ==
    [[0, :sealed], [1, :sealed], [2, :open]]
  assert h[1][1] == h[0][1]
  # The identity: the last row per entity is el_state's, and every row is
  # raifusaikuru's own fold over that entity's admitted records so far.
  q = test_path("history-many")
  append_all(read(q, "nisshi-test", d), example_events(60, 3))
  many = read(q, "nisshi-test", d)
  rm(q)
  rows = history(many)
  assert size(rows) == 60
  assert map(
    (e) -> [e, retsu::last(filter((x) -> rec_entity(first(x)) == e, rows))[1]],
    entities(many)
  ) == states(many)
  assert count_where(
    fn(x)
      x[1] !=
        raifusaikuru::state_of(
          d,
          map(
            rec_event,
            filter(
              fn(r)
                rec_entity(r) == rec_entity(first(x)) and
                  rec_seq(r) <= rec_seq(first(x)) and
                  rec_admitted?(r)
              end,
              map((y) -> first(y), rows)
            )
          )
        )
    end,
    rows
  ) == 0
  # The control: a value that was appended to keeps no records to replay.
  assert error?(
    begin
      history(log)
    rescue e
      e
    end
  )
end

test "grouping by entity keeps first-appearance order and stream order, and leaves bad lines out"
  d = raifusaikuru::example_consumable
  recs = records(
    from_text(
      unlines(
        first(
          control_lines(
            test_path("group"),
            "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
          )
        )
      ),
      nil,
      0,
      "nisshi-test",
      d
    )
  )
  groups = by_entity(push(recs, bad(5, "x", "not JSON")))
  assert map((g) -> first(g), groups) == ["item-1", "item-2"]
  assert map(el_position, first(groups)[1]) == [0, 1, 2, 3]
  assert map(el_position, groups[1][1]) == [4]
  assert by_entity([]) == []
end

test "an observed event is a fact: a guard refusal is written admitted and replayed as a breach; what the fold refuses stays refused"
  d = raifusaikuru::example_consumable
  # The empty case: where the guard allows, observing and appending write the
  # same record, byte for byte.
  a = test_path("observe-a")
  o = test_path("observe-o")
  ok = [
    ["item-1", raifusaikuru::ev(:reading, 1000, [[:value, 10]]), []],
    ["item-1", raifusaikuru::ev(:open, 1100, []), []],
    ["item-1", raifusaikuru::ev(:use, 1200, []), []]
  ]
  append_all(read(a, "nisshi-test", d), ok)
  reduce(
    (l, x) -> observe(l, first(x), x[1], x[2]),
    read(o, "nisshi-test", d),
    ok
  )
  assert read_file(a) == read_file(o)
  rm(a)
  rm(o)
  # A value checked by hand: read 26 at 1000, opened at 1100, a use observed
  # at 1200. quality_ok refuses (26 is not below 24), but the use happened:
  # admitted, no refusal, uses 1, and the replay keeps the breach at fold
  # position 2 (the third admitted event), naming the rule.
  p = test_path("observe")
  base = append_all(
    read(p, "nisshi-test", d),
    [
      ["item-1", raifusaikuru::ev(:reading, 1000, [[:value, 26]]), []],
      ["item-1", raifusaikuru::ev(:open, 1100, []), []]
    ]
  )
  seen = observe(
    base,
    "item-1",
    raifusaikuru::ev(:use, 1200, []),
    [[:batch, "B-1"]]
  )
  r = el_last(seen)
  assert rec_status(r) == :admitted
  assert rec_refusal(r).nil?
  assert raifusaikuru::value(state(seen, "item-1"), :uses) == 1
  assert raifusaikuru::breaches(state(seen, "item-1")) ==
    [[2, :use, :use, [:quality_ok]]]
  # The identity: a later read replays the same state, breach included, and
  # it is raifusaikuru's own fold of the admitted events.
  back = read(p, "nisshi-test", d)
  assert states(back) == states(seen)
  assert state(back, "item-1") ==
    raifusaikuru::state_of(
      d,
      [
        raifusaikuru::ev(:reading, 1000, [[:value, 26]]),
        raifusaikuru::ev(:open, 1100, []),
        raifusaikuru::ev(:use, 1200, [])
      ]
    )
  assert intact?(verify(back, nil, head(seen)))
  # Controls: the same use as an attempt is refused by the guard; an observed
  # event with no row, and an unknown one, are refused as the fold refuses them.
  q = test_path("observe-attempt")
  tried = el_append(
    append_all(
      read(q, "nisshi-test", d),
      [
        ["item-1", raifusaikuru::ev(:reading, 1000, [[:value, 26]]), []],
        ["item-1", raifusaikuru::ev(:open, 1100, []), []]
      ]
    ),
    "item-1",
    raifusaikuru::ev(:use, 1200, []),
    []
  )
  assert rec_refusal(el_last(tried)) == [:guard, ["quality_ok"]]
  assert raifusaikuru::value(state(tried, "item-1"), :uses) == 0
  rm(q)
  sealed = observe(seen, "item-2", raifusaikuru::ev(:use, 1300, []), [])
  assert rec_refusal(el_last(sealed)) ==
    [:no_edge, ["open", "reading", "discard"]]
  assert state(sealed, "item-2") == raifusaikuru::initial(d)
  flown = observe(sealed, "item-1", raifusaikuru::ev(:fly, 1400, []), [])
  assert rec_refusal(el_last(flown)) == [:unknown_event, []]
  rm(p)
end

test "the state as of a time: the records at or before it, folded as read folds them"
  d = raifusaikuru::example_consumable
  p = test_path("state-at")
  doc_stream(p)
  log = read(p, "nisshi-doc", d)
  # The empty case: before the first record, and for an entity with none, the
  # lifecycle's start.
  assert state_at(log, "item-1", 999) == raifusaikuru::initial(d)
  assert state_at(log, "item-9", 5000) == raifusaikuru::initial(d)
  # By hand: the doc stream is a reading of 10 at 1000 (admitted), a use at
  # 1100 while sealed (refused) and an open at 2000 (admitted). At 1000 the
  # reading has folded; at 1500 the refused use has changed nothing; at 2000
  # the item is open.
  at1000 = state_at(log, "item-1", 1000)
  assert [
    raifusaikuru::phase(at1000),
    raifusaikuru::value(at1000, :quality),
    raifusaikuru::value(at1000, :read_at)
  ] == [:sealed, 10, 1000]
  assert state_at(log, "item-1", 1500) == at1000
  assert raifusaikuru::phase(state_at(log, "item-1", 2000)) == :open
  # The identity: at the last record's time it is el_state; at each record's
  # time it is el_history's state after that record.
  assert state_at(log, "item-1", 2000) == state(log, "item-1")
  assert map(
    (x) -> state_at(log, rec_entity(first(x)), rec_time(first(x))),
    history(log)
  ) == map((x) -> x[1], history(log))
  # The control: a value that was appended to keeps no records.
  q = test_path("state-at-writer")
  w = el_append(
    read(q, "nisshi-test", d),
    "item-1",
    raifusaikuru::ev(:open, 10, []),
    []
  )
  assert error?(
    begin
      state_at(w, "item-1", 10)
    rescue e
      e
    end
  )
  rm(p)
  rm(q)
end

test "canon takes back every value json_parse gives, the empty object included"
  assert canon(json_parse("{}")) == "{}"
  assert canon(json_parse("{\"b\": {}, \"a\": [{}]}")) ==
    "{\"a\":[{}],\"b\":{}}"
  assert canon(json_parse("[]")) == "[]"
  assert (canon({a: 1}) rescue :raised) == :raised
end

test "entry is the lifecycle start at seq 0 for an entity never seen"
  d = raifusaikuru::example_consumable
  p = test_path("entry-unseen")
  log = read(p, "nisshi-test", d)
  assert entry(log, "item-1") == [raifusaikuru::initial(d), 0]
  assert entry(log, "") == [raifusaikuru::initial(d), 0]
  assert path_exists(p) == false
end

test "entry is an entity's state and next seq, and agrees with state and seq_of"
  d = raifusaikuru::example_consumable
  p = test_path("entry-seen")
  log = append_all(
    read(p, "nisshi-test", d),
    [
      ["a", raifusaikuru::ev(:reading, 1000, [[:value, 10]]), []],
      ["b", raifusaikuru::ev(:reading, 1010, [[:value, 10]]), []],
      ["a", raifusaikuru::ev(:open, 1020, []), []]
    ]
  )
  rm(p)
  assert entry(log, "a")[1] == 2
  assert entry(log, "b")[1] == 1
  assert first(entry(log, "a")) == state(log, "a")
  assert entry(log, "a")[1] == seq_of(log, "a")
  assert first(entry(log, "a")) != first(entry(log, "b"))
  assert entry(log, "c") == [raifusaikuru::initial(d), 0]
end

test "entry counts a refused event in seq and leaves the state as it was"
  d = raifusaikuru::example_consumable
  p = test_path("entry-refused")
  log = el_append(
    read(p, "nisshi-test", d),
    "a",
    raifusaikuru::ev(:fly, 1000, []),
    []
  )
  rm(p)
  assert entry(log, "a") == [raifusaikuru::initial(d), 1]
end
