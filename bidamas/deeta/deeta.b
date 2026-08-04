# deeta (データ) — JSON data, read safely.
#
# The runtime's JSON surface (`json_parse`, `json_stringify`, `json_get`,
# `json_get_or`) is installed unconditionally and is not total: `json_get` on a
# value that is not a document raises a type error, and its success value is
# nil for BOTH a missing key and a key whose value is null. A widget that reads
# a heartbeat or a config every thirty seconds should not be in the business of
# guarding `is this a list` at every read — that is this package's job.
#
# This package deliberately depends on nothing. Everything it needs is the
# runtime's own surface — layer 4's json primitives and the tatara type-check
# predicates — so there are no `use()` lines and nothing for the distribution
# gate to resolve. An accessor package that pulled in the list and string
# libraries would make its seam depend on their whole surface for a few lines
# of guards.
#
# # The one rule this package holds
#
# **Total where the primitive is not.** Every accessor answers its `default`
# for every non-value: a non-document, a missing key, a key whose value is
# null, and a value of the wrong type are all "this field is not a usable
# <type>" and all answer the same thing. `as_json` is the raw reader for the
# caller who wants the value whole, null and all.
#
# # What is deliberately absent
#
# **No missing-vs-null distinction, and it is named rather than buried.** The
# runtime returns `Value::Nil` for a missing key AND for a present null, so
# `as_json` cannot tell them apart and neither can a caller. (The one primitive
# that differs is `json_get_or`, whose default is reached for a MISSING key but
# NOT for a present null — a trap, which is why the typed accessors re-check
# the value's type instead of trusting any default. The test below pins it.)
# The sentinela widget's `head_rev` can be absent or null and both read as the
# em dash, so conflation is fine there; a caller who genuinely needs the
# difference must walk the alist itself with car/cdr before reaching an
# accessor.
#
# **No re-wrap of `json_parse` / `json_stringify`.** They already carry blue's
# names, and raising is their contract: a doc that will not parse is a bug in
# the producer, and fabricating a default here would turn that bug into a
# plausible answer.
#
# **No error handling, because blue has none.** `json_get` raises only on a
# non-document, and `is_doc` is checked before every call, so the raising path
# is unreachable from this package — the guards are what remove it.
#
# **`get_bool` is not here.** Nothing the fleet's widgets read emits a boolean
# field; the heartbeat carries a string, an int, and a number. Add it when a
# caller needs it, guarding on whatever boolean predicate the runtime offers.

# True when `v` is a JSON object read for its fields.
#
# A non-empty object parses to an association list, so the test is `list?`.
# nil is excluded first, and the exclusion does double duty: `null?` is also
# true of the empty list, so a document with no entries — nil, `[]` — is not a
# doc. (An empty OBJECT parses to a Map, which is not a list at all; it has no
# fields, so reading it as not-a-doc and answering the default is correct.)
def is_doc(v)
  list?(v) && not(null?(v))
end

# The raw value at `key`, or nil when there is none to give.
#
# nil answers for a non-document, a missing key, AND a key whose value is null
# — `json_get` returns the same nil for the last two, and this pass-through
# cannot distinguish them. Branch on nil first, and do not try to tell
# "absent" from "null" through the result; the caller who needs that difference
# walks the alist itself.
def as_json(doc, key)
  if is_doc(doc)
    json_get(doc, key)
  else
    nil
  end
end

# The string at `key`, or `default` when the field is not a string.
#
# Missing, null, wrong type, and a non-document all answer the default — the
# accessor is total, which is its whole reason to exist. `json_get_or` is NOT
# enough for this (see the header): its default is bypassed by a present null,
# so the value's type is checked here instead.
def get_str(doc, key, default)
  v = as_json(doc, key)
  if string?(v)
    v
  else
    default
  end
end

# The integer at `key`, or `default` when the field is not an integer.
#
# A float is not an integer and answers the default; `get_number` is the form
# that accepts both.
def get_int(doc, key, default)
  v = as_json(doc, key)
  if integer?(v)
    v
  else
    default
  end
end

# The number at `key` — integer or float — or `default` when the field is not
# a number.
def get_number(doc, key, default)
  v = as_json(doc, key)
  if number?(v)
    v
  else
    default
  end
end

test "is_doc is true for a parsed object and false for every other shape"
  assert is_doc(json_parse("{\"a\":1}")) == true
  assert is_doc(json_parse("{\"a\":1,\"b\":null}")) == true
  # nil is the empty list, and the empty array parses to it — neither is a doc.
  assert is_doc(nil) == false
  assert is_doc(json_parse("[]")) == false
  # An empty object parses to a Map; it has no fields, so it is not a doc.
  assert is_doc(json_parse("{}")) == false
  assert is_doc("text") == false
  assert is_doc(42) == false
end

test "get_str reads a string and answers the default for every other shape"
  doc = json_parse("{\"outcome\":\"ok\",\"phase\":\"idle\",\"head_rev\":null,\"count\":3}")
  assert get_str(doc, "outcome", "—") == "ok"
  assert get_str(doc, "phase", "—") == "idle"
  # Missing key and present null both answer the default.
  assert get_str(doc, "nope", "—") == "—"
  assert get_str(doc, "head_rev", "—") == "—"
  # Wrong type answers the default rather than leaking the number as text.
  assert get_str(doc, "count", "—") == "—"
end

test "get_int and get_number answer their kinds"
  doc = json_parse("{\"n\":3,\"f\":1.5,\"s\":\"three\",\"nil\":null}")
  assert get_int(doc, "n", 0) == 3
  # A float is not an integer — get_number is the accepting form.
  assert get_int(doc, "f", 0) == 0
  assert get_int(doc, "s", 0) == 0
  assert get_int(doc, "nil", 0) == 0
  assert get_int(doc, "nope", 0) == 0
  assert get_number(doc, "n", 0) == 3
  assert get_number(doc, "f", 0) == 1.5
  assert get_number(doc, "s", 0) == 0
  assert get_number(doc, "nil", 0) == 0
end

test "the accessors are total over non-documents"
  # json_get's raising path (a field read from a non-document) is never
  # reached: is_doc is checked first, so a garbage doc answers the default.
  assert get_str("not a doc", "k", "d") == "d"
  assert get_int(nil, "k", 7) == 7
  assert get_number(42, "k", 0) == 0
  assert get_str(json_parse("[]"), "k", "d") == "d"
  assert as_json("not a doc", "k") == nil
end

test "as_json returns the raw value, objects included, for one-level reads"
  doc = json_parse("{\"a\":{\"b\":7},\"n\":null,\"s\":\"x\"}")
  # A nested object comes back whole as an alist, which the typed accessors
  # answer as their default but as_json hands over for a further read.
  sub = as_json(doc, "a")
  assert is_doc(sub) == true
  assert get_int(sub, "b", 0) == 7
  assert as_json(doc, "n") == nil
  assert as_json(doc, "s") == "x"
  assert as_json(doc, "missing") == nil
end

test "json_get_or's default is NOT reached for a present null"
  # The trap the header warns about, pinned: json_get_or answers its default
  # only for a MISSING key; a key present with null returns nil and bypasses
  # it. That is why the typed accessors re-check the value's type.
  doc = json_parse("{\"a\":null,\"b\":1}")
  assert json_get_or(doc, "a", 42) == nil
  assert json_get_or(doc, "b", 42) == 1
  assert json_get_or(doc, "missing", 42) == 42
  assert get_int(doc, "a", 42) == 42
end

test "round-trip through stringify preserves what the accessors read"
  doc = json_parse("{\"outcome\":\"ok\",\"count\":2}")
  again = json_parse(json_stringify(doc))
  assert get_str(again, "outcome", "—") == "ok"
  assert get_int(again, "count", 0) == 2
end
