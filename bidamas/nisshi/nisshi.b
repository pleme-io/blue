use("retsu")
use("shuugou")
use("junjo")
use("deeta")
use("shomei")
use("raifusaikuru")
# nisshi (日誌) — an event log: append-only JSON Lines, hash-chained, optionally signed, replayed into lifecycle states.
#
# A logbook (日誌, as in 航海日誌, a ship's log): dated entries, in order,
# never rewritten. One stream (one file) per kind of entity; each line is one
# record of one event for one entity. `el_append` judges the event against a
# raifusaikuru lifecycle and writes it, admitted or refused; `el_read` replays
# a stream into every entity's state; `el_verify` walks the chain and names
# the first line that is not what was written. Nothing here knows any domain:
# a product declares its lifecycles and gets its telemetry from this.
#
# ## The plan (stage 1 of the blue development cycle, written before the code)
#
# Reuse map, read from source on 2026-09-24:
#
#   judge and fold an event      raifusaikuru  lc_admit_step, lc_step, lc_initial
#   genesis, link, first break   shomei        chain_genesis, chain_link, chain_first_break
#   sign and verify a hash       shomei        sign_message, verify_message, is_hash_hex
#   read a field, totally        deeta         is_doc, get_str, get_int, as_json
#   order keys, look up pairs    junjo, shuugou  sort_stable_by, lookup, set_equal
#   JSON text of a scalar        runtime       json_stringify (escaping is its job)
#   parse a line                 runtime       json_parse
#   the file                     runtime       append_file, read_file, file_size, path_exists
#   an index by entity or name   runtime       a map: get, assoc
#
# Four primitives were FIXED where they live rather than routed around, each
# found by a measurement here:
#
#   range           blue-lang-runtime  was a Lisp recursion in tatara-lisp's stdlib
#                                      and aborted near 5,000 elements, so
#                                      chain_first_break could not verify a 5,000-line
#                                      chain; now native (destination: tatara-lisp's own
#                                      range becomes a loop, and blue's is deleted)
#   is_hash_hex     shomei             a lambda per character, 97% of every chain_link;
#                                      31 → 12 µs
#   contains,       retsu              a tail-copying recursion, quadratic; a five-name
#   index_of                           lookup 14.7 → 3.7 µs, and 20,000 elements
#                                      664 → 5 ms
#   lc_admit_step   raifusaikuru       NEW: admission and next state from one
#                                      judgement, so append judges an event once, not twice
#
# ## The record
#
# One line per record, canonical JSON (below), keys in code-point order:
#
#   entity   the entity's id, a string
#   hash     the chain link: shomei's chain_link(prev, body), 64 hex
#   links    [{"id", "kind"}, …]: declared references to other entities, in
#            the order given, carried faithfully (duplicates kept)
#   payload  the event's payload, an object
#   prev     the hash of the line before, or the stream's genesis
#   refusal  null, or {"detail": [text], "kind": text} when refused
#   seq      the entity's record number: 0, 1, 2 … over ALL its records,
#            admitted and refused, so (entity, seq) names one line
#   sig      null, or Ed25519 over the hash's 64 hex characters (shomei)
#   status   "admitted" or "refused"
#   time     the event's time, a whole number on the caller's clock
#   type     the event's type
#
# The BODY is the record without prev, hash and sig: entity, links, payload,
# refusal, seq, status, time and type. The chain hashes the body's canonical
# text, so a change to any of them breaks the chain, and chain_link binds
# prev. The genesis is chain_genesis("nisshi/1\n" + label): the format and
# the stream's label are both in the first hash. Recomputable with any BLAKE3
# tool from shomei's two documented lines; the tests pin values from b3sum.
#
# Canonical JSON (`el_canon`): no whitespace; object keys in code-point
# order; strings, integers, finite floats, true/false and null as
# json_stringify writes them; a non-empty list of [name, value] pairs is an
# object and any other list an array, which is the runtime's own rule
# (json.rs `looks_like_object`). A line is canonical when it is exactly the
# rendering of the record it parses to, and el_verify checks that too.
#
# ## The rules
#
# **append is the only function that writes, and read the only other I/O.**
# Everything else is pure, with time, keys and labels passed in.
#
# **A refused event is written, never dropped.** It carries its refusal (the
# kind lc_admit gave and the detail as text) and counts in its entity's seq.
# It is an attempt, not a fact of the lifecycle, so it is folded into no
# state: replay steps only admitted records.
#
# **One fold, shared.** `el_absorb_record` is how append advances its log
# value and how read rebuilds one. read steps an entity with lc_step; append
# with the state lc_admit_step returned, which is lc_step's by construction
# (both are lc_apply over one lc_judge), so the two cannot disagree, and the
# identity test pins it. append returns the record exactly as a later read
# parses it: it renders the line, parses it back, and refuses to write a line
# that is not canonical or does not read back as the event it judged.
#
# **Names normalise; values must survive.** JSON has no keywords, so a type
# or payload key comes back as the definition's own name when the definition
# declares it, and as text when it does not (the fold never reads an
# undeclared one). A VALUE must be JSON already: a keyword, a map, a float
# that is not finite or a key given twice raises :eventlog_value before
# anything is written, because it would come back as something else and a
# guard comparing it would silently change its answer. A definition naming
# two events (or two keys of one event) with one text, :go and "go", is
# refused (:eventlog_use) when a log is made from it: both would be written
# "go".
#
# **A malformed call raises; a domain refusal is written.** An event the
# lifecycle refuses is data about the world and goes into the stream. An
# event that is not an lc_ev, an empty entity id, a link that is not
# [kind, id]: those are bugs in the caller, and raise before anything is
# written.
#
# **A stale log value cannot write.** A log value records the stream's size
# when it was read or last appended; append refuses (:eventlog_stale) when
# the file has changed since, so a second writer or an old value cannot fork
# the chain.
#
# **A broken stream cannot grow.** A line that is not a record marks the log's
# fault, and append refuses (:eventlog_broken). `el_open`, the writer's door,
# also verifies the chain and refuses a broken one: new valid records after a
# break would hide it.
#
# ## Tiers
#
# DETECTED by el_verify, at the exact position: a changed line (:hash), a
# dropped or reordered line (:prev), bytes changed without changing meaning
# (:not_canonical), a wrong record number (:seq), a line that is not a record
# or a last line without its newline, which is a torn write (:unparseable),
# and with a public key a missing or wrong signature (:unsigned, :signature).
#
# DETECTED ONLY WITH A RECORDED HEAD: lines dropped from the END. A chain
# proves every line follows the one before; nothing in it says where it
# stops. Pass the head recorded elsewhere (a receipt, a second store, a
# signed checkpoint) to el_verify and a truncation is :head.
#
# NOT DETECTED without signatures: a stream rewritten from any line onward,
# every later hash recomputed, by someone who can write the file. Signatures
# (a forger lacks the key) and a head kept elsewhere are what close it.
#
# NOT CHECKED: that a refused record would still be refused, or an admitted
# one admitted, under the definition passed to read. Replay uses the
# definition you give it: an admitted record it cannot accept lands in the
# entity's lc_refused, and a tightened guard shows as a breach.
#
# ONE WRITER per stream, enforced by the size check at append, not by a lock.
#
# ## What is deliberately absent
#
# No clock, no randomness, no key storage: time, labels and keys are the
# caller's. No analytics: DuckDB reads the stream as it stands, and the
# lifecycle-analytics step of the plan derives its models from the
# definitions. No encryption: shomei hashes and signs, and so does this.
#
# ## The operations
#
#   read     el_read(path, label, def)           the stream, replayed
#            el_open(path, label, def, pub)      read + verify, or refuse
#            el_from_text(text, path, bytes, label, def)   the pure part of read
#   write    el_append(log, entity, event, links)  the log advanced; el_last is the record
#            el_signing(log, secret_hex)         appends through it are signed
#   verify   el_verify(log, pub, expected_head)  [:el_intact, count, head] or
#                                                [:el_broken, position, kind, why]
#   state    el_state(log, entity), el_seq_of, el_states, el_entities
#   records  el_records(log), el_by_entity(records), el_rec_* accessors
#   pure     el_canon(value), el_canon_object(pairs), el_genesis(label),
#            el_texts / el_body_text / el_line_text (the record builders),
#            el_decode_line(def, position, line), el_lines / el_unlines
#
# ## One line (the first of the b3sum test's stream, signed)
#
#   {"entity":"item-1","hash":"9172aea16c9c2cb304ee3d624c0a79be88ca7537769f3386b64aa55b273dc412",
#    "links":[],"payload":{"value":10},"prev":"0a42d546253d153e4253d118781c1b773338b3dd532373a12a83accd79e7cba2",
#    "refusal":null,"seq":0,"sig":"7b5e4034…a80b","status":"admitted","time":1000,"type":"reading"}
#
# (one line in the stream; wrapped and the signature shortened here.)
#
# ## Tests, and the red run that turned each one red (2026-09-24)
#
#   the empty stream                        R8 read keeps the piece after the last newline
#   identity: append → read, read → read,   R1 refused dropped · R2 replay folds refused ·
#     and raifusaikuru's own fold as the     R14 groups newest first · R17 append skips
#     differential                           the step
#   a refused event is written and marked   R1 · R16 seq counts only admitted
#   values checked independently (b3sum,    R3 the hash leaves the payload out · R1 · R16
#     openssl)
#   controls, one row per break kind        R5 no :prev · R6 no signatures · R9 torn line
#                                            read whole · R10 no seq · R11 no canonical check
#   append raises on what JSON cannot hold  R12 no round-trip check (the keyword key was
#                                            written, 294 bytes)
#   stale, written-through, broken writers  R7 no size check · R18 two names of one text
#   links carried faithfully                R13 duplicate links merged
#   canonical JSON, and serde agrees        R4 keys left unsorted (caught by append's own
#                                            canonical guard) · R15 a key given twice
#   grouping by entity                      R14
#
# 18 of 18 mutations red, each applied by a driver that refuses a mutation
# whose target text is absent. In the packages this one changed:
# raifusaikuru's lc_admit_step test red when it stopped stepping; shomei's
# tests red when is_hash_hex forgot a digit; the runtime's range test aborted
# with the Lisp range restored. retsu's contains/index_of change is speed
# only, which no behaviour test can turn red: its semantics tests pass on both.
#
# ## The benchmark (2026-09-24)
#
# 10,000 events (el_example_events(10000, 100): 100 items, 5,500 refused by
# the guard), appended signed through el_append_all, then el_read and
# el_verify with the public key and the recorded head. Apple M4 Pro, 14
# cores, 48 GB, macOS 26.7, release build of blue 0.0.39, under a load
# average of ~49 from other builds (times vary ±10% run to run; median of 3):
#
#                  first version   measured hot paths fixed
#   append         8.18 s          5.39 s    539 µs an event
#   read           3.53 s          1.85 s    185 µs a record
#   verify         2.22 s          1.79 s    179 µs a record (1.26 s unsigned)
#
# The stream: 4.26 MB, intact; DuckDB, reading it as JSON Lines, counts the
# same 10,000 lines, 100 entities, 5,500 refusals and a gapless seq per
# entity. What moved it, by measured share of an append: two judgements
# became one (lc_admit_step, ~180 µs); decoding read each field once and
# restored names through a map built once per log (218 → 62 µs); and the three
# primitive fixes above. What remains, in order: raifusaikuru's judgement (~144
# µs of an append; 16 µs per atomic rule, through shuugou's lookup), Ed25519
# verification (~52 µs a record), and shomei's chain_hashes, which builds
# its list with cons and is quadratic (~0.2 s at 10,000).
#
# ## Words blue is missing (stage 5 candidates, not built)
#
# - A RECORD: a positional list plus one `nth` accessor per field is written by
#   hand here twice (a record of 13 fields, a log value of 14 slots rebuilt in
#   full to change four) and throughout raifusaikuru (lc_d_*, the state, the
#   permit). One declaration of named fields should give the constructor, the
#   predicate, the accessors and a `with` that changes some fields.
# - A CLOSED KIND SET with its coverage test: el_break_kinds and
#   el_refusal_kinds here, lc_problem_kinds in raifusaikuru, each with a
#   hand-written "every kind has a row" set_equal.
# - A GUARD: this file raises in 23 places, most of them
#   `if … throw(error(:kind, "…")) end`; as a function, its message would be
#   built even when the check passes.
# - DEFAULT ARGUMENTS: el_verify(log, nil, nil) and el_append(…, []) pass
#   "none" by position.
# - A RED-RUN WORD: the mutation driver that produced the table above
#   (package, [name, old, new] → which tests go red) was a scratch program;
#   stage 3 of the cycle asks for exactly this on every test.
# - An O(1) append: push and cons copy (AUTHORING.md, "Growing a list is
#   quadratic"); a runtime gap, not a word.

# ── the format ─────────────────────────────────────────────────────────────

# The format tag, bound into every stream's genesis.
def el_format()
  "nisshi/1"
end

# The first hash of the stream named `label`. Two streams with different
# labels, or of different formats, never share a first hash.
def el_genesis(label)
  if string?(label) == false
    throw(error(:eventlog_use, "a stream label is a string, not #{lc_show(label)}"))
  end
  chain_genesis("#{el_format()}\n#{label}")
end

# Every refusal kind a record can carry: lc_admit's. Closed.
def el_refusal_kinds()
  [:unknown_event, :no_edge, :missing_payload, :bad_payload, :bad_field, :guard]
end

# Every break el_verify reports, in the order it prefers them when two fall on
# one line. Closed: a test row exercises each.
def el_break_kinds()
  [:unparseable, :prev, :hash, :not_canonical, :seq, :unsigned, :signature, :head]
end

# ── canonical JSON ─────────────────────────────────────────────────────────

# A key as JSON text: a string itself, a keyword's or symbol's name.
def el_key_text(k)
  if string?(k)
    k
  elsif keyword?(k) || symbol?(k)
    to_s(k)
  else
    throw(error(:eventlog_value, "an object key is a name (a string or a keyword), not #{lc_show(k)}"))
  end
end

# True for a [name, value] pair.
def el_pair?(p)
  list?(p) && (size(p) == 2) && (string?(first(p)) || keyword?(first(p)) || symbol?(first(p)))
end

# True for a value JSON writes as an object: a non-empty list whose every
# element is a [name, value] pair, the runtime's own rule.
def el_object?(v)
  list?(v) && (is_empty(v) == false) && (count_where(fn(p) el_pair?(p) == false end, v) == 0)
end

# True for the value json_parse gives an empty object: a map that writes "{}".
def el_empty_object?(v)
  (v != nil) && (list?(v) == false) && (json_stringify(v) == "{}")
end

# The canonical JSON text of a value. Raises :eventlog_value for what JSON
# would not give back as itself: a keyword, a map, a float that is not
# finite, a key given twice.
def el_canon(v)
  if v == nil
    "null"
  elsif list?(v)
    el_canon_list(v)
  elsif string?(v) || integer?(v) || boolean?(v)
    json_stringify(v)
  elsif number?(v)
    el_canon_float(v)
  elsif keyword?(v) || symbol?(v)
    throw(error(:eventlog_value, "#{lc_show(v)} is a keyword, which JSON gives back as the string \"#{to_s(v)}\"; write the string"))
  else
    throw(error(:eventlog_value, "#{lc_show(v)} is not JSON data; write an object as a list of [key, value] pairs"))
  end
end

def el_canon_list(v)
  if el_object?(v)
    el_canon_object(v)
  else
    "[#{join(map(fn(x) el_canon(x) end, v), ",")}]"
  end
end

def el_canon_float(x)
  t = json_stringify(x)
  if t == "null"
    throw(error(:eventlog_value, "#{to_s(x)} is not a finite number, and JSON cannot write it"))
  end
  t
end

# Pairs ordered by key text, in code-point order (what `compare` gives).
# Raises when a pair is not [name, value] or two keys share one text.
def el_sorted_pairs(pairs)
  checked = map(fn(p) el_require_pair(p) end, as_list(pairs))
  sorted = sort_stable_by(fn(p) el_key_text(first(p)) end, checked)
  texts = map(fn(p) el_key_text(first(p)) end, sorted)
  dup = find_first(fn(i) nth(i, texts) == nth(i + 1, texts) end, range(0, size(texts) - 1))
  if dup != nil
    throw(error(:eventlog_value, "key \"#{nth(dup, texts)}\" is given twice; an object holds one value per key"))
  end
  sorted
end

def el_require_pair(p)
  if el_pair?(p) == false
    throw(error(:eventlog_value, "an object is a list of [key, value] pairs, and #{lc_show(p)} is not one"))
  end
  p
end

# The canonical text of an object given as [name, value] pairs; "{}" for none.
def el_canon_object(pairs)
  "{#{join(map(fn(p) el_canon_member(p) end, el_sorted_pairs(pairs)), ",")}}"
end

def el_canon_member(p)
  "#{json_stringify(el_key_text(first(p)))}:#{el_canon(nth(1, p))}"
end

# ── names: what JSON keeps, and what the definition restores ──────────────

# The definition's names indexed by their text: a map from an event type's
# text to [type, keys], keys a map from a payload key's text to the key.
# Built once per log value, so restoring a name is a lookup, not a search.
# Raises :eventlog_use when two events, or two keys of one event, share a
# text: the log writes names as text and could not tell them apart.
def el_names(d)
  events = lc_d_events(d)
  el_require_distinct(map(fn(e) lc_text(first(e)) end, events), "event")
  reduce(fn(m, e) assoc(m, lc_text(first(e)), [first(e), el_key_index(nth(1, e))]) end, {}, events)
end

def el_key_index(keys)
  el_require_distinct(map(fn(k) lc_text(k) end, as_list(keys)), "payload key")
  reduce(fn(m, k) assoc(m, lc_text(k), k) end, {}, as_list(keys))
end

def el_require_distinct(texts, what)
  if size(unique(texts)) != size(texts)
    throw(error(:eventlog_use, "the definition has two of one #{what} name as text among #{lc_show(texts)}; a log writes names as text and could not tell them apart"))
  end
end

# The type named by text `t`: the definition's own name, or the text itself.
def el_type_named(names, t)
  hit = get(names, t)
  if hit == nil
    t
  else
    first(hit)
  end
end

# The payload key named by text `k` for type `ty`: the key the definition
# declares, or the text itself.
def el_key_named(names, ty, k)
  hit = get(names, lc_text(ty))
  key = if hit == nil
    nil
  else
    get(nth(1, hit), k)
  end
  if key == nil
    k
  else
    key
  end
end

# The event as the log holds it: its type and payload keys as the definition
# names them (text where it names none), and every object in key order.
def el_normal_event(names, ev)
  ty = el_type_named(names, lc_text(lc_ev_type(ev)))
  payload = map(fn(p) [el_key_named(names, ty, el_key_text(first(p))), el_normal_value(nth(1, p))] end, el_sorted_pairs(lc_ev_payload(ev)))
  lc_ev(ty, lc_ev_time(ev), payload)
end

# A value with every object in it put in key order, which is all canonical
# JSON changes about a value that survives it. Keys keep their kind, so a
# keyword key still fails the round trip it cannot survive.
def el_normal_value(v)
  if v == nil
    nil
  elsif el_object?(v)
    map(fn(p) [first(p), el_normal_value(nth(1, p))] end, el_sorted_pairs(v))
  elsif list?(v)
    map(fn(x) el_normal_value(x) end, v)
  else
    v
  end
end

# ── refusals and links ─────────────────────────────────────────────────────

# The refusal an admission verdict gives a record: nil when admitted, else
# [kind, detail], the detail as text (the legal events, the missing keys, the
# offending key or field, or the refusing rules).
def el_refusal_of(verdict)
  if lc_admitted?(verdict)
    nil
  else
    [lc_reject_kind(verdict), el_detail_texts(lc_reject_kind(verdict), lc_reject_detail(verdict))]
  end
end

def el_detail_texts(kind, detail)
  if kind == :guard
    map(fn(r) lc_text(r) end, lc_refused_rules(detail))
  elsif detail == nil
    []
  elsif list?(detail)
    map(fn(x) lc_text(x) end, detail)
  else
    [lc_text(detail)]
  end
end

# A refusal's kind, one of el_refusal_kinds().
def el_refusal_kind(rf)
  first(rf)
end

# A refusal's detail, as text.
def el_refusal_detail(rf)
  nth(1, rf)
end

def el_refusal_text(rf)
  if rf == nil
    "null"
  else
    "{\"detail\":#{el_canon(nth(1, rf))},\"kind\":#{json_stringify(lc_text(first(rf)))}}"
  end
end

# Links as the log holds them: [kind, id] pairs, the kind as text, in order.
def el_normal_links(links)
  map(fn(l) el_normal_link(l) end, as_list(links))
end

def el_normal_link(l)
  if list?(l) && (size(l) == 2) && lc_name?(first(l)) && string?(nth(1, l))
    [lc_text(first(l)), nth(1, l)]
  else
    throw(error(:eventlog_value, "a link is [kind, id]: a name and a string, not #{lc_show(l)}"))
  end
end

def el_links_text(links)
  "[#{join(map(fn(l) el_link_text(l) end, links), ",")}]"
end

def el_link_text(l)
  "{\"id\":#{json_stringify(nth(1, l))},\"kind\":#{json_stringify(first(l))}}"
end

# ── the record builders ────────────────────────────────────────────────────

# The canonical text of each body field, in key order: entity, links,
# payload, refusal, seq, status, time, type.
def el_texts(entity, links, payload, refusal, seq, status, at, ty)
  [json_stringify(entity), el_links_text(links), el_canon_object(payload), el_refusal_text(refusal), to_s(seq), json_stringify(to_s(status)), to_s(at), json_stringify(lc_text(ty))]
end

# The text the chain hashes: the record without prev, hash and sig.
def el_body_text(t)
  "{\"entity\":#{nth(0, t)},\"links\":#{nth(1, t)},\"payload\":#{nth(2, t)},\"refusal\":#{nth(3, t)},\"seq\":#{nth(4, t)},\"status\":#{nth(5, t)},\"time\":#{nth(6, t)},\"type\":#{nth(7, t)}}"
end

# The line a stream holds: every field, keys in code-point order.
def el_line_text(t, prev, hash, sig)
  "{\"entity\":#{nth(0, t)},\"hash\":\"#{hash}\",\"links\":#{nth(1, t)},\"payload\":#{nth(2, t)},\"prev\":\"#{prev}\",\"refusal\":#{nth(3, t)},\"seq\":#{nth(4, t)},\"sig\":#{el_sig_text(sig)},\"status\":#{nth(5, t)},\"time\":#{nth(6, t)},\"type\":#{nth(7, t)}}"
end

def el_sig_text(sig)
  if sig == nil
    "null"
  else
    json_stringify(sig)
  end
end

def el_status_for(refusal)
  if refusal == nil
    :admitted
  else
    :refused
  end
end

# ── records ────────────────────────────────────────────────────────────────

# A record as read: [:el_record, position, seq, time, entity, type, payload,
# links, status, refusal, prev, hash, sig, line]. position is the line's
# index in the stream, from 0.
def el_record(position, seq, at, entity, ty, payload, links, status, refusal, prev, hash, sig, line)
  [:el_record, position, seq, at, entity, ty, payload, links, status, refusal, prev, hash, sig, line]
end

def el_record?(x)
  first(x) == :el_record
end

# The index of a record or a bad line in its stream, from 0.
def el_position(x)
  nth(1, x)
end

def el_rec_seq(r)
  nth(2, r)
end

def el_rec_time(r)
  nth(3, r)
end

def el_rec_entity(r)
  nth(4, r)
end

# The type: the definition's own name when it declares it, else text.
def el_rec_type(r)
  nth(5, r)
end

# The payload as [key, value] pairs in key order.
def el_rec_payload(r)
  nth(6, r)
end

# The links as [kind, id] pairs, in the order they were given.
def el_rec_links(r)
  nth(7, r)
end

# :admitted or :refused.
def el_rec_status(r)
  nth(8, r)
end

def el_rec_admitted?(r)
  nth(8, r) == :admitted
end

# nil, or [kind, detail] for a refused record.
def el_rec_refusal(r)
  nth(9, r)
end

def el_rec_prev(r)
  nth(10, r)
end

def el_rec_hash(r)
  nth(11, r)
end

# The signature's hex, or nil.
def el_rec_sig(r)
  nth(12, r)
end

# The line exactly as the stream holds it.
def el_rec_line(r)
  nth(13, r)
end

# The event a record holds, as raifusaikuru folds it.
def el_rec_event(r)
  lc_ev(el_rec_type(r), el_rec_time(r), el_rec_payload(r))
end

def el_texts_of(r)
  el_texts(el_rec_entity(r), el_rec_links(r), el_rec_payload(r), el_rec_refusal(r), el_rec_seq(r), el_rec_status(r), el_rec_time(r), el_rec_type(r))
end

# The body text a record's hash covers, rendered from the record.
def el_body_of(r)
  el_body_text(el_texts_of(r))
end

# The canonical line for a record: what its line must be, byte for byte.
def el_line_of(r)
  el_line_text(el_texts_of(r), el_rec_prev(r), el_rec_hash(r), el_rec_sig(r))
end

# A line that is not a record: [:el_bad_line, position, line, why].
def el_bad(position, line, why)
  [:el_bad_line, position, line, why]
end

def el_bad_why(b)
  nth(3, b)
end

# ── decoding a line ────────────────────────────────────────────────────────

# A line read back as a record, or as a bad line saying why it is not one.
# Total: nothing here raises, whatever the line holds.
def el_decode_line(d, position, line)
  el_decode_named(el_names(d), position, line)
end

# el_decode_line with the definition's names already indexed (el_names), as
# read and append hold them.
def el_decode_named(names, position, line)
  doc = try(json_parse(line), catch(e(), :el_unreadable))
  if doc == :el_unreadable
    el_bad(position, line, "not JSON")
  elsif is_doc(doc) == false
    el_bad(position, line, "not a JSON object")
  else
    el_decode_doc(names, position, line, doc)
  end
end

# Each field is read once, with deeta's total readers (nil for absent or of
# the wrong type), then checked in order, stopping at the first problem.
def el_decode_doc(names, position, line, doc)
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
  why = el_shape_problem(entity, seq, at, ty_text, status, prev, hash, sig, payload, links, refusal)
  if why != nil
    el_bad(position, line, "not a record: #{why}")
  else
    ty = el_type_named(names, ty_text)
    pairs = map(fn(p) [el_key_named(names, ty, first(p)), nth(1, p)] end, el_payload_pairs(payload))
    kinds = map(fn(l) [get_str(l, "kind", ""), get_str(l, "id", "")] end, links)
    el_record(position, seq, at, entity, ty, pairs, kinds, el_status_of(status), el_refusal_from(refusal), prev, hash, sig, line)
  end
end

def el_payload_pairs(p)
  if el_object?(p)
    p
  else
    []
  end
end

def el_status_of(t)
  if t == "refused"
    :refused
  else
    :admitted
  end
end

def el_refusal_from(v)
  if v == nil
    nil
  else
    [find_first(fn(k) lc_text(k) == get_str(v, "kind", "") end, el_refusal_kinds()), as_list(as_json(v, "detail"))]
  end
end

# The first way a line's fields fail to make a record, as text, or nil.
def el_shape_problem(entity, seq, at, ty_text, status, prev, hash, sig, payload, links, refusal)
  if el_nonempty_string?(entity) == false
    "entity is not a non-empty string"
  elsif el_natural?(seq) == false
    "seq is not a whole number from 0"
  elsif integer?(at) == false
    "time is not a whole number"
  elsif el_nonempty_string?(ty_text) == false
    "type is not a non-empty string"
  elsif contains(["admitted", "refused"], status) == false
    "status is neither admitted nor refused"
  elsif is_hash_hex(prev) == false
    "prev is not a hash"
  elsif is_hash_hex(hash) == false
    "hash is not a hash"
  elsif el_sig_shape?(sig) == false
    "sig is neither null nor a string"
  elsif (el_object?(payload) || el_empty_object?(payload)) == false
    "payload is not an object"
  elsif el_links_shape?(links) == false
    "links is not a list of {id, kind} objects"
  elsif el_refusal_shape?(status, refusal) == false
    "refusal does not match status"
  else
    nil
  end
end

def el_nonempty_string?(v)
  string?(v) && (v != "")
end

def el_natural?(v)
  integer?(v) && (v >= 0)
end

def el_sig_shape?(v)
  (v == nil) || string?(v)
end

def el_links_shape?(v)
  (v != nil) && list?(v) && (count_where(fn(l) el_link_shape?(l) == false end, v) == 0)
end

def el_link_shape?(l)
  el_object?(l) && string?(get_str(l, "kind", nil)) && string?(get_str(l, "id", nil))
end

def el_refusal_shape?(status, v)
  if status == "admitted"
    v == nil
  else
    el_object?(v) && contains(map(fn(k) lc_text(k) end, el_refusal_kinds()), get_str(v, "kind", nil)) && el_texts_list?(as_json(v, "detail"))
  end
end

def el_texts_list?(v)
  (v != nil) && list?(v) && (count_where(fn(x) string?(x) == false end, v) == 0)
end

# ── the log value ──────────────────────────────────────────────────────────

# [:el_log, path, label, def, head, count, bytes, entities, index, last,
#  records, signer, fault, names]. index maps an entity to [state, next seq].
# records is the stream as read, or nil once the value has been appended to.
# names is el_names(def).
def el_new(path, label, d, bytes, records)
  [:el_log, path, label, d, el_genesis(label), 0, bytes, [], {}, nil, records, nil, nil, el_names(d)]
end

def el_require_log(log)
  if (list?(log) && (is_empty(log) == false) && (first(log) == :el_log)) == false
    throw(error(:eventlog_use, "not a log value; get one from el_read or el_open"))
  end
  log
end

def el_path(log)
  nth(1, log)
end

# The label the stream's genesis is made from.
def el_label(log)
  nth(2, log)
end

def el_def(log)
  nth(3, log)
end

# The hash of the last record: what the next record's prev will be.
def el_head(log)
  nth(4, log)
end

# How many lines the stream holds.
def el_count(log)
  nth(5, log)
end

# The stream's size in bytes when this value was read or last appended.
def el_bytes(log)
  nth(6, log)
end

# The entities in the order they first appear.
def el_entities(log)
  nth(7, log)
end

def el_index(log)
  nth(8, log)
end

# The last record: after el_append, the record it wrote.
def el_last(log)
  nth(9, log)
end

# The records as read, in stream order, bad lines included. Raises once the
# value has been appended to: a writer keeps no history, so read again.
def el_records(log)
  el_require_log(log)
  if nth(10, log) == nil
    throw(error(:eventlog_use, "this log value has been appended to, and a writer keeps no records; read the stream again"))
  end
  nth(10, log)
end

def el_signer(log)
  nth(11, log)
end

# The position of the first line that is not a record, or nil.
def el_fault(log)
  nth(12, log)
end

def el_names_of(log)
  nth(13, log)
end

# An entity's [state, next seq]; an unseen entity is at its lifecycle's start.
def el_entry(log, entity)
  have = get(el_index(log), entity)
  if have == nil
    [lc_initial(el_def(log)), 0]
  else
    have
  end
end

# An entity's lifecycle state: its admitted records, folded.
def el_state(log, entity)
  first(el_entry(log, entity))
end

# The seq an entity's next record will carry.
def el_seq_of(log, entity)
  nth(1, el_entry(log, entity))
end

# Every entity's state, [entity, state], in the order entities first appear.
def el_states(log)
  map(fn(e) [e, el_state(log, e)] end, el_entities(log))
end

# The log with a signing key: every record appended through it carries an
# Ed25519 signature over its hash. The secret is a 32-byte seed in hex from
# the caller; the log holds it in memory only.
def el_signing(log, secret_hex)
  el_require_log(log)
  if is_hash_hex(secret_hex) == false
    throw(error(:eventlog_use, "a signing key is a 32-byte seed, as 64 lowercase hex characters"))
  end
  update_at(log, 11, secret_hex)
end

# ── one fold, shared by append and read ────────────────────────────────────

# Fold one line into the log, as read does. An admitted record steps its
# entity's state (lc_step); a refused one only counts in its entity's seq; a
# bad line marks the fault.
def el_absorb(log, x)
  if el_record?(x)
    el_absorb_record(log, x, el_fold_record(el_def(log), el_state(log, el_rec_entity(x)), x))
  else
    el_absorb_bad(log, x)
  end
end

# Advance the log past record `r`, its entity now in `state`. read passes
# lc_step's state; append passes lc_admit_step's, which is lc_step's by
# construction (both are lc_apply over one lc_judge), so they cannot differ.
def el_absorb_record(log, r, state)
  e = el_rec_entity(r)
  have = get(el_index(log), e)
  next_seq = el_next_seq(have)
  [:el_log, el_path(log), el_label(log), el_def(log), el_rec_hash(r), el_count(log) + 1, el_bytes(log), el_entities_with(el_entities(log), e, have != nil), assoc(el_index(log), e, [state, next_seq]), r, nth(10, log), el_signer(log), el_fault(log), el_names_of(log)]
end

def el_next_seq(have)
  if have == nil
    1
  else
    nth(1, have) + 1
  end
end

def el_absorb_bad(log, b)
  fault = if el_fault(log) == nil
    el_position(b)
  else
    el_fault(log)
  end
  update_at(update_at(log, 5, el_count(log) + 1), 12, fault)
end

def el_entities_with(entities, e, known)
  if known
    entities
  else
    push(entities, e)
  end
end

def el_fold_record(d, state, r)
  if el_rec_admitted?(r)
    lc_step(d, state, el_rec_event(r))
  else
    state
  end
end

# ── read: the only I/O besides append ──────────────────────────────────────

# Read the stream at `path` (a missing file is an empty stream) and replay
# every record into its entity's state. It verifies nothing; el_verify says
# whether to trust what was read.
def el_read(path, label, d)
  lc_name(d)
  if path_exists(path)
    el_from_text(read_file(path), path, file_size(path), label, d)
  else
    el_from_text("", path, 0, label, d)
  end
end

# The log a stream's text reads as: el_read's work after the file is read.
# Pure. A last line without its newline is a torn write, and a bad line.
def el_from_text(text, path, bytes, label, d)
  lines = el_lines(text)
  n = size(lines)
  torn = (text != "") && (ends_with?(text, "\n") == false)
  names = el_names(d)
  records = map(fn(i) el_decode_at(names, i, nth(i, lines), torn && (i == n - 1)) end, range(0, n))
  reduce(fn(l, x) el_absorb(l, x) end, el_new(path, label, d, bytes, records), records)
end

def el_decode_at(names, i, line, is_torn)
  if is_torn
    el_bad(i, line, "no line terminator: the last write was cut short")
  else
    el_decode_named(names, i, line)
  end
end

# A stream's lines: its text split on newlines, without the empty piece after
# the final one.
def el_lines(text)
  if text == ""
    []
  elsif ends_with?(text, "\n")
    all_but_last(split(text, "\n"))
  else
    split(text, "\n")
  end
end

# Lines back into a stream's text, each ended by a newline.
def el_unlines(lines)
  join(map(fn(l) "#{l}\n" end, lines), "")
end

# The writer's door: read the stream, verify it (signatures too, given a
# public key), and return the log ready to append to. A broken stream raises
# :eventlog_broken naming the position and the kind of break.
def el_open(path, label, d, public_hex)
  log = el_read(path, label, d)
  rep = el_verify(log, public_hex, nil)
  if el_intact?(rep) == false
    throw(error(:eventlog_broken, "#{path}: position #{to_s(el_break_position(rep))}, #{to_s(el_break_kind(rep))}: #{el_break_why(rep)}"))
  end
  log
end

# ── append: the only function that writes ──────────────────────────────────

# Append `event` (an lc_ev) for `entity`, with `links` ([kind, id] pairs, []
# for none), and return the log advanced past it; el_last is the new record,
# exactly as a later read returns it. An admitted event steps the entity's
# state. A refused one is written too, marked refused with its reason, and
# steps nothing. Raises before writing when the event is malformed
# (:eventlog_value), the log value is stale (:eventlog_stale) or the stream is
# broken (:eventlog_broken).
def el_append(log, entity, event, links)
  el_require_writable(log)
  el_require_entity(entity)
  el_require_event(event)
  d = el_def(log)
  path = el_path(log)
  on_disk = el_bytes_on_disk(path)
  if on_disk != el_bytes(log)
    throw(error(:eventlog_stale, "#{path} holds #{to_s(on_disk)} bytes and this log value knows #{to_s(el_bytes(log))}: the stream changed since the value was read. Read it again."))
  end
  names = el_names_of(log)
  ev = el_normal_event(names, event)
  entry = el_entry(log, entity)
  judged = lc_admit_step(d, first(entry), ev)
  refusal = el_refusal_of(first(judged))
  texts = el_texts(entity, el_normal_links(links), lc_ev_payload(ev), refusal, nth(1, entry), el_status_for(refusal), lc_ev_time(ev), lc_ev_type(ev))
  prev = el_head(log)
  hash = chain_link(prev, el_body_text(texts))
  line = el_line_text(texts, prev, hash, el_sign(el_signer(log), hash))
  r = el_decode_named(names, el_count(log), line)
  el_require_round_trip(r, line, ev)
  append_file(path, "#{line}\n")
  el_absorb_record(update_at(update_at(log, 10, nil), 6, el_bytes_on_disk(path)), r, el_state_after(first(entry), judged, refusal))
end

# The entity's state after an append: the step's when admitted, unchanged
# when refused.
def el_state_after(state, judged, refusal)
  if refusal == nil
    nth(1, judged)
  else
    state
  end
end

def el_sign(secret, hash)
  if secret == nil
    nil
  else
    sign_message(secret, hash)
  end
end

def el_bytes_on_disk(path)
  if path_exists(path)
    file_size(path)
  else
    0
  end
end

def el_require_writable(log)
  el_require_log(log)
  if el_path(log) == nil
    throw(error(:eventlog_use, "this log value was read from text, not a file, so it cannot be appended to"))
  end
  if el_fault(log) != nil
    throw(error(:eventlog_broken, "position #{to_s(el_fault(log))} of #{el_path(log)} is not a record; a broken stream cannot grow"))
  end
end

def el_require_entity(entity)
  if el_nonempty_string?(entity) == false
    throw(error(:eventlog_value, "an entity id is a non-empty string, not #{lc_show(entity)}"))
  end
end

def el_require_event(ev)
  if (list?(ev) && (size(ev) == 3) && lc_name?(lc_ev_type(ev)) && integer?(lc_ev_time(ev)) && list?(nth(2, ev))) == false
    throw(error(:eventlog_value, "an event is lc_ev(type, time, payload): a name, a whole-number time and [key, value] pairs, not #{lc_show(ev)}"))
  end
end

# Refuse to write a line that does not read back as the record it renders
# and the event that was judged.
def el_require_round_trip(r, line, ev)
  if el_record?(r) == false
    throw(error(:eventlog_internal, "a rendered line did not parse as a record: #{el_bad_why(r)}"))
  end
  if el_line_of(r) != line
    throw(error(:eventlog_internal, "a rendered line is not canonical: #{line}"))
  end
  if el_rec_event(r) != ev
    throw(error(:eventlog_value, "the event would not read back as written; JSON keeps strings, numbers, true/false, nil and lists, and a keyword inside a value (a key or an element) comes back as a string"))
  end
end

# ── verify ─────────────────────────────────────────────────────────────────

# Walk the stream and report the first break, or that it is intact:
#   [:el_intact, count, head]
#   [:el_broken, position, kind, why]   kind is one of el_break_kinds()
# With `public_hex`, every record must carry a signature that verifies under
# it. With `expected_head` (a head recorded elsewhere), the stream must end
# exactly there: the only way a line dropped from the END can be seen. Pure.
def el_verify(log, public_hex, expected_head)
  el_require_log(log)
  if (public_hex != nil) && (is_hash_hex(public_hex) == false)
    throw(error(:eventlog_use, "a public key is 64 lowercase hex characters"))
  end
  records = el_records(log)
  bad = find_first(fn(x) el_record?(x) == false end, records)
  good = el_before_bad(records, bad)
  texts = map(fn(r) el_texts_of(r) end, good)
  g = el_genesis(el_label(log))
  found = filter(fn(b) b != nil end, [el_break_bad(bad), el_break_chain(g, good, texts), el_break_canon(good, texts), el_break_seq(good), el_break_sig(good, public_hex)])
  earliest = reduce(fn(best, b) el_earlier(best, b) end, nil, found)
  head = el_head_of(g, good)
  if earliest != nil
    [:el_broken, nth(0, earliest), nth(1, earliest), nth(2, earliest)]
  elsif (expected_head != nil) && (expected_head != head)
    [:el_broken, size(records), :head, "the stream ends at #{head}, not at the head recorded for it: lines are missing from its end, or were added after it"]
  else
    [:el_intact, size(records), head]
  end
end

def el_before_bad(records, bad)
  if bad == nil
    records
  else
    take_n(records, el_position(bad))
  end
end

def el_head_of(g, good)
  if is_empty(good)
    g
  else
    el_rec_hash(last(good))
  end
end

def el_earlier(best, b)
  if (best == nil) || (first(b) < first(best))
    b
  else
    best
  end
end

def el_break_bad(bad)
  if bad == nil
    nil
  else
    [el_position(bad), :unparseable, el_bad_why(bad)]
  end
end

# The first record the chain does not reproduce (shomei's chain_first_break),
# named :prev when its prev is not the hash before it (a line is missing or
# out of order) and :hash when its content changed.
def el_break_chain(g, good, texts)
  p = chain_first_break(g, map(fn(t) el_body_text(t) end, texts), map(fn(r) el_rec_hash(r) end, good))
  if p == nil
    nil
  elsif el_rec_prev(nth(p, good)) != el_head_of(g, take_n(good, p))
    [p, :prev, "the record does not follow the one before it: a line is missing or out of order here"]
  else
    [p, :hash, "the record's content does not match its hash: the line was changed after it was written"]
  end
end

def el_break_canon(good, texts)
  i = find_first(fn(k) el_canonical_at?(nth(k, good), nth(k, texts)) == false end, range(0, size(good)))
  if i == nil
    nil
  else
    [el_position(nth(i, good)), :not_canonical, "the line is not the canonical rendering of its record: its bytes changed (spacing, key order or escaping) after it was written"]
  end
end

def el_canonical_at?(r, t)
  el_line_text(t, el_rec_prev(r), el_rec_hash(r), el_rec_sig(r)) == el_rec_line(r)
end

def el_break_seq(good)
  nth(1, reduce(fn(acc, r) el_seq_step(acc, r) end, [{}, nil], good))
end

def el_seq_step(acc, r)
  if nth(1, acc) != nil
    acc
  else
    seen = get(first(acc), el_rec_entity(r))
    expect = if seen == nil
      0
    else
      seen
    end
    if el_rec_seq(r) == expect
      [assoc(first(acc), el_rec_entity(r), expect + 1), nil]
    else
      [first(acc), [el_position(r), :seq, "#{el_rec_entity(r)} expects seq #{to_s(expect)} here and the record says #{to_s(el_rec_seq(r))}"]]
    end
  end
end

def el_break_sig(good, public_hex)
  if public_hex == nil
    nil
  else
    el_sig_break(find_first(fn(r) el_sig_ok?(r, public_hex) == false end, good))
  end
end

def el_sig_break(r)
  if r == nil
    nil
  elsif el_rec_sig(r) == nil
    [el_position(r), :unsigned, "the record carries no signature"]
  else
    [el_position(r), :signature, "the signature does not verify under the given public key"]
  end
end

def el_sig_ok?(r, public_hex)
  if string?(el_rec_sig(r))
    try(verify_message(public_hex, el_rec_hash(r), el_rec_sig(r)), catch(e(), false)) == true
  else
    false
  end
end

# True for a report of an intact stream.
def el_intact?(rep)
  first(rep) == :el_intact
end

# The position of a broken report's first break, from 0.
def el_break_position(rep)
  nth(1, rep)
end

def el_break_kind(rep)
  nth(2, rep)
end

def el_break_why(rep)
  nth(3, rep)
end

# ── grouping ───────────────────────────────────────────────────────────────

# The records grouped by entity: [[entity, records]] in the order entities
# first appear, each group in stream order. Bad lines are left out.
def el_by_entity(records)
  acc = reduce(fn(a, x) el_group_add(a, x) end, [[], {}], filter(fn(x) el_record?(x) end, as_list(records)))
  map(fn(e) [e, reverse(get(nth(1, acc), e))] end, first(acc))
end

def el_group_add(a, r)
  e = el_rec_entity(r)
  have = get(nth(1, a), e)
  if have == nil
    [push(first(a), e), assoc(nth(1, a), e, [r])]
  else
    [first(a), assoc(nth(1, a), e, cons(r, have))]
  end
end

# ── a worked stream ────────────────────────────────────────────────────────

# `n` events over `k` of raifusaikuru's example consumables, interleaved:
# event i is item (i mod k)'s (i div k)-th step. Each item is read, opened,
# then used, with a fresh reading every 25th step; every 10th event links a
# batch. The guard refuses a use once 40 are spent or the reading is 4 h old,
# so a long stream holds refusals as well as admissions. Time moves 10 s an
# event. Each element is [entity, event, links].
def el_example_events(n, k)
  map(fn(i) el_example_event(i, k) end, range(0, n))
end

def el_example_event(i, k)
  [ "item-#{to_s(i % k)}", el_example_step(floor(i / k), 1000 + (i * 10)), el_example_links(i) ]
end

def el_example_step(step, at)
  if step == 0
    lc_ev(:reading, at, [[:value, 10]])
  elsif step == 1
    lc_ev(:open, at, [])
  elsif (step % 25) == 0
    lc_ev(:reading, at, [[:value, 10 + (step % 7)]])
  else
    lc_ev(:use, at, [])
  end
end

def el_example_links(i)
  if (i % 10) == 0
    [[:batch, "B-#{to_s(floor(i / 100))}"]]
  else
    []
  end
end

# Append every [entity, event, links] in order.
def el_append_all(log, items)
  reduce(fn(l, x) el_append(l, first(x), nth(1, x), nth(2, x)) end, log, items)
end

# A fresh path under TMPDIR for a test's stream.
def el_test_path(name)
  path_join(getenv("TMPDIR", "/tmp"), "nisshi-#{name}-#{to_s(now_ns())}.jsonl")
end

# ── tests ──────────────────────────────────────────────────────────────────

test "the empty stream: no file, an empty file and empty text all read as no records at the genesis, intact"
  d = lc_example_consumable()
  g = el_genesis("nisshi-test")
  p = el_test_path("empty")
  log = el_read(p, "nisshi-test", d)
  assert el_count(log) == 0
  assert el_head(log) == g
  assert el_records(log) == []
  assert el_entities(log) == []
  assert el_last(log) == nil
  assert el_state(log, "item-1") == lc_initial(d)
  assert el_seq_of(log, "item-1") == 0
  assert el_verify(log, nil, nil) == [:el_intact, 0, g]
  assert el_verify(log, nil, g) == [:el_intact, 0, g]
  write_file(p, "")
  assert el_verify(el_read(p, "nisshi-test", d), nil, g) == [:el_intact, 0, g]
  rm(p)
  assert el_count(el_from_text("", nil, 0, "nisshi-test", d)) == 0
  assert el_lines("") == []
  assert el_genesis("other") != g
end

test "an identity: append then read gives back every record and every state, and reading twice is the same"
  d = lc_example_consumable()
  p = el_test_path("identity")
  items = concat_lists(el_example_events(60, 3), [["item-z", lc_ev(:use, 5000, []), []], ["item-0", lc_ev(:fly, 5010, []), []]])
  steps = reduce(fn(acc, x) el_identity_step(acc, x) end, [el_read(p, "nisshi-test", d), []], items)
  log = first(steps)
  r1 = el_read(p, "nisshi-test", d)
  r2 = el_read(p, "nisshi-test", d)
  rm(p)
  assert el_count(r1) == 62
  assert el_records(r1) == nth(1, steps)
  assert el_records(r2) == el_records(r1)
  assert el_states(r1) == el_states(log)
  assert el_states(r2) == el_states(r1)
  assert el_head(r1) == el_head(log)
  assert el_entities(r1) == ["item-0", "item-1", "item-2", "item-z"]
  # The differential: each state is what raifusaikuru alone folds from that
  # entity's admitted events.
  assert map(fn(grp) [first(grp), lc_state_of(d, map(fn(r) el_rec_event(r) end, filter(fn(r) el_rec_admitted?(r) end, nth(1, grp))))] end, el_by_entity(el_records(r1))) == el_states(r1)
  assert el_intact?(el_verify(r1, nil, el_head(log)))
end

def el_identity_step(acc, x)
  l = el_append(first(acc), first(x), nth(1, x), nth(2, x))
  [l, push(nth(1, acc), el_last(l))]
end

test "a refused event is written, marked with its reason, counted in seq, and folded into nothing"
  d = lc_example_consumable()
  p = el_test_path("refused")
  l1 = el_append(el_read(p, "nisshi-test", d), "item-1", lc_ev(:use, 1000, []), [])
  r = el_last(l1)
  assert el_rec_status(r) == :refused
  assert el_rec_refusal(r) == [:no_edge, ["open", "reading", "discard"]]
  assert el_state(l1, "item-1") == lc_initial(d)
  assert el_seq_of(l1, "item-1") == 1
  assert el_count(l1) == 1
  l2 = el_append_all(l1, [["item-1", lc_ev(:reading, 1100, [[:value, 26]]), []], ["item-1", lc_ev(:open, 1200, []), []], ["item-1", lc_ev(:use, 1300, []), []]])
  assert el_rec_refusal(el_last(l2)) == [:guard, ["quality_ok"]]
  assert lc_value(el_state(l2, "item-1"), :uses) == 0
  assert lc_breaches(el_state(l2, "item-1")) == []
  assert lc_refused(el_state(l2, "item-1")) == []
  l3 = el_append(l2, "item-1", lc_ev(:fly, 1400, []), [])
  assert el_rec_refusal(el_last(l3)) == [:unknown_event, []]
  assert el_rec_type(el_last(l3)) == "fly"
  back = el_records(el_read(p, "nisshi-test", d))
  rm(p)
  assert map(fn(x) el_rec_status(x) end, back) == [:refused, :admitted, :admitted, :refused, :refused]
  assert map(fn(x) el_rec_seq(x) end, back) == [0, 1, 2, 3, 4]
  assert last(back) == el_last(l3)
end

# The stream the b3sum test pins: three events for one item, signed with RFC
# 8032 TEST 1's key.
def el_doc_stream(p)
  d = lc_example_consumable()
  log = el_signing(el_read(p, "nisshi-doc", d), "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  el_append_all(log, [["item-1", lc_ev(:reading, 1000, [[:value, 10]]), []], ["item-1", lc_ev(:use, 1100, []), []], ["item-1", lc_ev(:open, 2000, []), [[:batch, "B-7"]]]])
end

test "values checked independently: the genesis and every hash by b3sum, the signature by openssl"
  # The bytes, from the documented format (shomei's two lines; the body keys
  # in code-point order), hashed with b3sum 1.8.2:
  #   genesis  "blue-chain/v1/genesis\nnisshi/1\nnisshi-doc"
  #   link i   "blue-chain/v1/link\n" + prev + "\n" + body i
  # and the signature over hash 0's 64 hex characters by `openssl pkeyutl
  # -sign -rawin` (OpenSSL 3.6.2) with RFC 8032 TEST 1's seed.
  p = el_test_path("doc")
  log = el_doc_stream(p)
  read_back = el_read(p, "nisshi-doc", lc_example_consumable())
  back = el_records(read_back)
  rm(p)
  assert el_genesis("nisshi-doc") == "0a42d546253d153e4253d118781c1b773338b3dd532373a12a83accd79e7cba2"
  assert map(fn(r) el_rec_hash(r) end, back) == ["9172aea16c9c2cb304ee3d624c0a79be88ca7537769f3386b64aa55b273dc412", "c0a4ffe9fe283b42e163c6ef6b722139699dc07dc1626520e65600acf08d062e", "f2b9bb297775ea19093808d056e5988ac629c6938dd7917d7c7f545d04f0c2a3"]
  assert el_head(log) == "f2b9bb297775ea19093808d056e5988ac629c6938dd7917d7c7f545d04f0c2a3"
  assert el_body_of(nth(0, back)) == "{\"entity\":\"item-1\",\"links\":[],\"payload\":{\"value\":10},\"refusal\":null,\"seq\":0,\"status\":\"admitted\",\"time\":1000,\"type\":\"reading\"}"
  assert el_body_of(nth(1, back)) == "{\"entity\":\"item-1\",\"links\":[],\"payload\":{},\"refusal\":{\"detail\":[\"open\",\"reading\",\"discard\"],\"kind\":\"no_edge\"},\"seq\":1,\"status\":\"refused\",\"time\":1100,\"type\":\"use\"}"
  assert el_body_of(nth(2, back)) == "{\"entity\":\"item-1\",\"links\":[{\"id\":\"B-7\",\"kind\":\"batch\"}],\"payload\":{},\"refusal\":null,\"seq\":2,\"status\":\"admitted\",\"time\":2000,\"type\":\"open\"}"
  assert el_rec_line(nth(0, back)) == "{\"entity\":\"item-1\",\"hash\":\"9172aea16c9c2cb304ee3d624c0a79be88ca7537769f3386b64aa55b273dc412\",\"links\":[],\"payload\":{\"value\":10},\"prev\":\"0a42d546253d153e4253d118781c1b773338b3dd532373a12a83accd79e7cba2\",\"refusal\":null,\"seq\":0,\"sig\":\"7b5e40341db5adfbcc2ba97c7ff76d5d47ba452a4a5eeb761a973340cda7099fe8906491d3e3e3c298106f3a48a9bd874f3a63b162cc148a08e939c16cd2a80b\",\"status\":\"admitted\",\"time\":1000,\"type\":\"reading\"}"
  assert el_verify(read_back, "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", el_head(log)) == [:el_intact, 3, el_head(log)]
end

# A signed stream of five records over two items, as its lines: the base the
# controls below damage one way each.
def el_control_lines(p, secret)
  log = el_signing(el_read(p, "nisshi-test", lc_example_consumable()), secret)
  items = [["item-1", lc_ev(:reading, 1000, [[:value, 10]]), []], ["item-1", lc_ev(:open, 1100, []), []], ["item-1", lc_ev(:use, 1200, []), []], ["item-1", lc_ev(:use, 1300, []), []], ["item-2", lc_ev(:reading, 1400, [[:value, 11]]), []]]
  done = el_append_all(log, items)
  lines = el_lines(read_file(p))
  rm(p)
  [lines, el_head(done)]
end

# One damaged copy per break kind: [kind, text, public key, expected head,
# position]. `k` and `other` are two keypairs; the stream is signed with `k`.
def el_control_rows(lines, head, k, other)
  pub = keypair_public(k)
  line2 = nth(2, lines)
  line3 = nth(3, lines)
  r3 = el_decode_line(lc_example_consumable(), 3, line3)
  forged = replace(line3, el_rec_sig(r3), sign_message(keypair_secret(other), el_rec_hash(r3)))
  unsigned = replace(line3, "\"sig\":\"#{el_rec_sig(r3)}\"", "\"sig\":null")
  [[:unparseable, el_unlines(update_at(lines, 2, "not json")), pub, nil, 2], [:unparseable, join(lines, "\n"), pub, nil, 4], [:hash, el_unlines(update_at(lines, 2, replace(line2, "\"time\":1200", "\"time\":1201"))), pub, nil, 2], [:prev, el_unlines(remove_at(lines, 2)), pub, nil, 2], [:prev, el_unlines(update_at(update_at(lines, 1, line2), 2, nth(1, lines))), pub, nil, 1], [:not_canonical, el_unlines(update_at(lines, 1, replace(nth(1, lines), "{\"entity\"", "{ \"entity\""))), pub, nil, 1], [:seq, el_unlines(el_wrong_seq_lines(lines, keypair_secret(k))), pub, nil, 4], [:unsigned, el_unlines(update_at(lines, 3, unsigned)), pub, nil, 3], [:signature, el_unlines(update_at(lines, 3, forged)), pub, nil, 3], [:signature, el_unlines(lines), keypair_public(other), nil, 0], [:head, el_unlines(all_but_last(lines)), pub, head, 4]]
end

# The stream with its last record rewritten to claim seq 1 for item-2's first
# record, re-hashed and re-signed: a writer's bug the chain alone accepts.
def el_wrong_seq_lines(lines, secret)
  d = lc_example_consumable()
  r = el_decode_line(d, 4, nth(4, lines))
  texts = el_texts(el_rec_entity(r), el_rec_links(r), el_rec_payload(r), el_rec_refusal(r), 1, el_rec_status(r), el_rec_time(r), el_rec_type(r))
  hash = chain_link(el_rec_prev(r), el_body_text(texts))
  update_at(lines, 4, el_line_text(texts, el_rec_prev(r), hash, sign_message(secret, hash)))
end

def el_control_verdict(row)
  rep = el_verify(el_from_text(nth(1, row), nil, 0, "nisshi-test", lc_example_consumable()), nth(2, row), nth(3, row))
  [el_break_kind(rep), el_break_position(rep)]
end

test "controls: a changed, dropped or reordered line, a wrong signature and every other break, each found at its position"
  k = signing_keypair("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  other = signing_keypair("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
  base = el_control_lines(el_test_path("controls"), keypair_secret(k))
  lines = first(base)
  head = nth(1, base)
  intact = el_verify(el_from_text(el_unlines(lines), nil, 0, "nisshi-test", lc_example_consumable()), keypair_public(k), head)
  assert intact == [:el_intact, 5, head]
  rows = el_control_rows(lines, head, k, other)
  assert map(fn(row) el_control_verdict(row) end, rows) == map(fn(row) [first(row), nth(4, row)] end, rows)
  # Dropping the LAST line is invisible without the recorded head.
  assert el_intact?(el_verify(el_from_text(el_unlines(all_but_last(lines)), nil, 0, "nisshi-test", lc_example_consumable()), keypair_public(k), nil))
  # Every break kind has a row: a new kind without one fails here.
  assert set_equal(unique(map(fn(row) first(row) end, rows)), el_break_kinds())
end

test "append raises before writing on what JSON cannot hold, and on a malformed call"
  d = lc_example_consumable()
  p = el_test_path("values")
  l0 = el_read(p, "nisshi-test", d)
  bad_calls = [fn() el_append(l0, "item-1", lc_ev(:reading, 1000, [[:value, :high]]), []) end, fn() el_append(l0, "item-1", lc_ev(:reading, 1000, [[:value, [[:grade, 1]]]]), []) end, fn() el_append(l0, "item-1", lc_ev(:reading, 1000, [[:value, 1], [:value, 2]]), []) end, fn() el_append(l0, "item-1", lc_ev(:reading, 1000, [[:value, expt(10.0, 300) * expt(10.0, 300)]]), []) end, fn() el_append(l0, "item-1", lc_ev(:reading, 1000.5, [[:value, 1]]), []) end, fn() el_append(l0, "", lc_ev(:open, 1000, []), []) end, fn() el_append(l0, "item-1", lc_ev(:open, 1000, []), [[:batch, 7]]) end, fn() el_append(l0, "item-1", [:open], []) end]
  assert map(fn(call) error?(try(call(), catch(e(), e))) end, bad_calls) == repeat(true, size(bad_calls))
  assert path_exists(p) == false
  # The control: the same call with a JSON value goes through.
  l1 = el_append(l0, "item-1", lc_ev(:reading, 1000, [[:value, "high"]]), [])
  assert lc_value(el_state(l1, "item-1"), :quality) == "high"
  rm(p)
end

test "a stale log value cannot write, a written-through value keeps no records, and a broken stream cannot grow"
  d = lc_example_consumable()
  p = el_test_path("writers")
  l0 = el_read(p, "nisshi-test", d)
  l1 = el_append(l0, "item-1", lc_ev(:open, 1000, []), [])
  assert error?(try(el_append(l0, "item-1", lc_ev(:open, 1100, []), []), catch(e(), e)))
  assert el_count(el_read(p, "nisshi-test", d)) == 1
  assert error?(try(el_records(l1), catch(e(), e)))
  l2 = el_append(l1, "item-1", lc_ev(:use, 1100, []), [])
  assert el_count(l2) == 2
  append_file(p, "not a record\n")
  broken = el_read(p, "nisshi-test", d)
  assert el_fault(broken) == 2
  assert error?(try(el_append(broken, "item-1", lc_ev(:use, 1200, []), []), catch(e(), e)))
  assert error?(try(el_open(p, "nisshi-test", d, nil), catch(e(), e)))
  assert el_count(el_read(p, "nisshi-test", d)) == 3
  rm(p)
  # The control: el_open on an intact stream opens it.
  p2 = el_test_path("writers-ok")
  el_append(el_read(p2, "nisshi-test", d), "item-1", lc_ev(:open, 1000, []), [])
  assert el_count(el_open(p2, "nisshi-test", d, nil)) == 1
  rm(p2)
  # A definition naming two events :go and "go" is sound to raifusaikuru and
  # unusable here: both would be written "go".
  two = lc_define(:two, [lc_states([:a, :b]), lc_start(:a), lc_terminals([:b]), lc_event(:go, []), lc_event("go", []), lc_on(:a, :go, :b, []), lc_on(:a, "go", :b, [])])
  assert error?(try(el_read(p2, "nisshi-test", two), catch(e(), e)))
end

test "links are carried faithfully: kinds as text, ids, order and duplicates, in the hash"
  d = lc_example_consumable()
  p = el_test_path("links")
  l1 = el_append(el_read(p, "nisshi-test", d), "order-1", lc_ev(:reading, 1000, [[:value, 1]]), [[:pack, "P-17"], [:pack, "P-18"], ["oil", "O-3"], [:pack, "P-17"]])
  want = [["pack", "P-17"], ["pack", "P-18"], ["oil", "O-3"], ["pack", "P-17"]]
  assert el_rec_links(el_last(l1)) == want
  assert contains?(el_rec_line(el_last(l1)), "\"links\":[{\"id\":\"P-17\",\"kind\":\"pack\"},{\"id\":\"P-18\",\"kind\":\"pack\"},{\"id\":\"O-3\",\"kind\":\"oil\"},{\"id\":\"P-17\",\"kind\":\"pack\"}]")
  assert el_rec_links(first(el_records(el_read(p, "nisshi-test", d)))) == want
  lines = el_lines(read_file(p))
  rm(p)
  # A link changed after writing breaks the hash.
  swapped = replace(first(lines), "O-3", "O-4")
  assert el_break_kind(el_verify(el_from_text(el_unlines([swapped]), nil, 0, "nisshi-test", d), nil, nil)) == :hash
end

test "canonical JSON: sorted keys, no spaces, the runtime's shapes, and serde writes the same bytes"
  assert el_canon([["b", 1], ["a", [1, "x", nil, true, 1.5]]]) == "{\"a\":[1,\"x\",null,true,1.5],\"b\":1}"
  assert el_canon([]) == "[]"
  assert el_canon_object([]) == "{}"
  assert el_canon([[:z, [["y", 2], ["x", 1]]]]) == "{\"z\":{\"x\":1,\"y\":2}}"
  assert el_canon("é \"q\"\n") == "\"é \\\"q\\\"\\n\""
  assert el_canon([nil]) == "[null]"
  assert error?(try(el_canon(:k), catch(e(), e)))
  assert error?(try(el_canon([["a", 1], ["a", 2]]), catch(e(), e)))
  d = lc_example_consumable()
  p = el_test_path("canon")
  l1 = el_append(el_read(p, "nisshi-test", d), "item-é", lc_ev(:reading, 1000, [[:value, 10], ["note", "óleo \"novo\"\n"], ["tags", [["b", 2], ["a", [1.25, false]]]]]), [])
  line = el_rec_line(el_last(l1))
  rm(p)
  # serde_json, parsing and re-writing the line independently, gives back the
  # same bytes: the keys are in its order and the escapes are its escapes.
  assert json_stringify(json_parse(line)) == line
  assert el_line_of(el_decode_line(d, 0, line)) == line
  assert lookup(el_rec_payload(el_last(l1)), :value) == 10
  assert lookup(el_rec_payload(el_last(l1)), "tags") == [["a", [1.25, false]], ["b", 2]]
end

test "grouping by entity keeps first-appearance order and stream order, and leaves bad lines out"
  d = lc_example_consumable()
  recs = el_records(el_from_text(el_unlines(first(el_control_lines(el_test_path("group"), "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"))), nil, 0, "nisshi-test", d))
  groups = el_by_entity(push(recs, el_bad(5, "x", "not JSON")))
  assert map(fn(g) first(g) end, groups) == ["item-1", "item-2"]
  assert map(fn(r) el_position(r) end, nth(1, first(groups))) == [0, 1, 2, 3]
  assert map(fn(r) el_position(r) end, nth(1, nth(1, groups))) == [4]
  assert el_by_entity([]) == []
end
