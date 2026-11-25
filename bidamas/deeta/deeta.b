@moduledoc """
deeta (データ) — JSON data, read safely.

The runtime's JSON surface (`json_parse`, `json_stringify`, `json_get`,
`json_get_or`) is installed unconditionally and is not total: `json_get` on a
value that is not a document raises a type error, and its success value is
nil for BOTH a missing key and a key whose value is null. A widget that reads
a heartbeat or a config every thirty seconds should not be in the business of
guarding `is this a list` at every read — that is this package's job.

This package deliberately depends on nothing. Everything it needs is the
runtime's own surface — layer 4's json primitives and the tatara type-check
predicates — so there are no `use()` lines and nothing for the distribution
gate to resolve. An accessor package that pulled in the list and string
libraries would make its seam depend on their whole surface for a few lines
of guards.

# The one rule this package holds

**Total where the primitive is not.** Every accessor answers its `default`
for every non-value: a non-document, a missing key, a key whose value is
null, and a value of the wrong type are all "this field is not a usable
<type>" and all answer the same thing. `as_json` is the raw reader for the
caller who wants the value whole, null and all.

# What is deliberately absent

**No missing-vs-null distinction, and it is named rather than buried.** The
runtime returns `Value::Nil` for a missing key AND for a present null, so
`as_json` cannot tell them apart and neither can a caller. (The one primitive
that differs is `json_get_or`, whose default is reached for a MISSING key but
NOT for a present null — a trap, which is why the typed accessors re-check
the value's type instead of trusting any default. The test below pins it.)
The sentinela widget's `head_rev` can be absent or null and both read as the
em dash, so conflation is fine there; a caller who genuinely needs the
difference must walk the alist itself with car/cdr before reaching an
accessor.

**No re-wrap of `json_parse` / `json_stringify`.** They already carry blue's
names, and raising is their contract: a doc that will not parse is a bug in
the producer, and fabricating a default here would turn that bug into a
plausible answer.

**No error handling, because blue has none.** `json_get` raises only on a
non-document, and `is_doc` is checked before every call, so the raising path
is unreachable from the document accessors — the guards are what remove it.
`get_or`, the Map reader, is `get` with a default and raises where `get` does.

**`get_bool` is not here.** Nothing the fleet's widgets read emits a boolean
field; the heartbeat carries a string, an int, and a number. Add it when a
caller needs it, guarding on whatever boolean predicate the runtime offers.

    yaml([]) #=> "[]\n"
"""

use("kazu", [:max])
use("kyohi", [:raised])
use("retsu", %i[first last rest])

@doc """
is_doc: True when `v` is a JSON object read for its fields.

A non-empty object parses to an association list, so the test is `list?`.
nil is excluded first, and the exclusion does double duty: `null?` is also
true of the empty list, so a document with no entries — nil, `[]` — is not a
doc. (An empty OBJECT parses to a Map, which is not a list at all; it has no
fields, so reading it as not-a-doc and answering the default is correct.)

    is_doc(42) #=> false
"""
def is_doc(v)
  list?(v) and not null?(v)
end

@doc """
as_json: The raw value at `key`, or nil when there is none to give.

nil answers for a non-document, a missing key, AND a key whose value is null
— `json_get` returns the same nil for the last two, and this pass-through
cannot distinguish them. Branch on nil first, and do not try to tell
"absent" from "null" through the result; the caller who needs that difference
walks the alist itself.
"""
def as_json(doc, key)
  if is_doc(doc)
    json_get(doc, key)
  end
end

@doc """
get_str: The string at `key`, or `default` when the field is not a string.

Missing, null, wrong type, and a non-document all answer the default — the
accessor is total, which is its whole reason to exist. `json_get_or` is NOT
enough for this (see the header): its default is bypassed by a present null,
so the value's type is checked here instead.

    get_str("not a doc", "k", "d") #=> "d"
"""
def get_str(doc, key, default)
  get_if(doc, key, string?, default)
end

@doc """
get_int: The integer at `key`, or `default` when the field is not an integer.

A float is not an integer and answers the default; `get_number` is the form
that accepts both.

    get_int(nil, "k", 7) #=> 7
"""
def get_int(doc, key, default)
  get_if(doc, key, integer?, default)
end

@doc """
get_number: The number at `key` — integer or float — or `default` when the field is not
a number.

    get_number(42, "k", 0) #=> 0
"""
def get_number(doc, key, default)
  get_if(doc, key, number?, default)
end

@doc """
get_if(doc, key, pred, default) is the value at key when pred holds of it, and
default otherwise, for a missing field, a null and a non-document too.

    get_if(json_parse("{\"n\":3}"), "n", integer?, 0) #=> 3
"""
def get_if(doc, key, pred, default)
  v = as_json(doc, key)
  if pred(v)
    v
  else
    default
  end
end

@doc """
get_or: The value of a blue Map (`{max_iter: 3}`) at `key`, or `default` when the
key is missing or nil: the one reader here of a Map rather than a document,
for option maps. It is `get` with a default, so like `get` it refuses a value
that is not a Map; it does not share the documents' totality.

kinji's and kakou's `opt` were this definition, twice; both are bridges to it
(`legacy_names`) until their 0.2.0.

    get_or({a: 1}, :a, 9) #=> 1
"""
def get_or(m, key, default)
  v = get(m, key)
  if v.nil?
    default
  else
    v
  end
end

@doc """
json_at: The value at a dotted path, `json_at(doc, "spec.items.0.name")`, or nil when any step is absent.

    json_at(json_parse("{\"\":5}"), "") #=> 5
"""
def json_at(doc, path)
  path_from(doc, split(path, "."))
end

def path_from(v, keys)
  if null?(keys)
    v
  elsif v.nil?
    nil
  else
    path_from(step_into(v, first(keys)), rest(keys))
  end
end

def step_into(v, key)
  index = to_int(key)
  if index != nil and list?(v) and not is_doc_pair?(first(v))
    v[index]
  elsif map?(v)
    get(v, key)
  else
    json_get(v, key) rescue nil
  end
end

def is_doc_pair?(x)
  list?(x) and count(x) == 2 and string?(x[0])
end

test "json_at walks objects, lists by index, and both kinds of parse"
  doc = json_parse("{\"spec\":{\"variables\":{\"owner\":\"pleme-io\"},\"items\":[{\"name\":\"a\"},{\"name\":\"b\"}]}}")
  assert json_at(doc, "spec.variables.owner") == "pleme-io"
  assert json_at(doc, "spec.items.1.name") == "b"
  assert json_at(json_read("{\"a\":{\"b\":2}}"), "a.b") == 2
end

test "json_at answers nil for every path that is not there"
  doc = json_parse("{\"spec\":{\"n\":1,\"s\":\"x\"}}")
  assert json_at(doc, "spec.variables").nil?
  assert json_at(doc, "spec.n.deeper").nil?
  assert json_at(doc, "spec.s.deeper").nil?
  assert json_at(nil, "a").nil?
  assert json_at(doc, "spec.items.9").nil?
end

test "json_at of the empty path is the document"
  assert json_at([1], "").nil?
  assert json_at(json_parse("{\"\":5}"), "") == 5
end

test "get_or reads a Map, and its default answers a missing or nil key"
  assert get_or({a: 1}, :a, 9) == 1
  assert get_or({a: 1}, :b, 9) == 9
  assert get_or({a: nil}, :a, 9) == 9
  assert get_or({a: false}, :a, 9) == false
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
  assert as_json("not a doc", "k").nil?
end

test "as_json returns the raw value, objects included, for one-level reads"
  doc = json_parse("{\"a\":{\"b\":7},\"n\":null,\"s\":\"x\"}")
  # A nested object comes back whole as an alist, which the typed accessors
  # answer as their default but as_json hands over for a further read.
  sub = as_json(doc, "a")
  assert is_doc(sub) == true
  assert get_int(sub, "b", 0) == 7
  assert as_json(doc, "n").nil?
  assert as_json(doc, "s") == "x"
  assert as_json(doc, "missing").nil?
end

test "json_get_or's default is NOT reached for a present null"
  # The trap the header warns about, pinned: json_get_or answers its default
  # only for a MISSING key; a key present with null returns nil and bypasses
  # it. That is why the typed accessors re-check the value's type.
  doc = json_parse("{\"a\":null,\"b\":1}")
  assert json_get_or(doc, :a, 42).nil?
  assert json_get_or(doc, :b, 42) == 1
  assert json_get_or(doc, :missing, 42) == 42
  assert get_int(doc, "a", 42) == 42
end

test "round-trip through stringify preserves what the accessors read"
  doc = json_parse("{\"outcome\":\"ok\",\"count\":2}")
  again = json_parse(json_stringify(doc))
  assert get_str(again, "outcome", "—") == "ok"
  assert get_int(again, "count", 0) == 2
end

def plain_key?(k)
  cs = chars(k)
  cs != [] and
    member?(
      first(cs),
      chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
    ) and
    every?(
      fn(c)
        member?(
          c,
          chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        )
      end,
      cs
    ) and
    not member?(k, %w[true false null yes no on off y n])
end

def scalar_text(v)
  if v.nil?
    "null"
  elsif v == true
    "true"
  elsif v == false
    "false"
  elsif number?(v)
    to_s(v)
  else
    json_stringify(to_s(v))
  end
end

def collection?(v)
  v != nil and (map?(v) or list?(v))
end

def pretty_at(v, pad)
  inner = "#{pad}  "
  if collection?(v) and map?(v)
    es = map_entries(v)
    if es == []
      "{}"
    else
      body = join(
        map(
          fn(e)
            "#{inner}#{json_stringify(to_s(first(e)))}: #{pretty_at(second(e), inner)}"
          end,
          es
        ),
        unlines([","])
      )
      join_lines(["{", body, "#{pad}}"])
    end
  elsif collection?(v)
    if v == []
      "[]"
    else
      body = join(
        map((x) -> "#{inner}#{pretty_at(x, inner)}", v),
        unlines([","])
      )
      join_lines(["[", body, "#{pad}]"])
    end
  else
    scalar_text(v)
  end
end

def pretty(v)
  unlines([pretty_at(v, "")])
end

def yaml_key(k)
  t = to_s(k)
  if plain_key?(t)
    t
  else
    json_stringify(t)
  end
end

def empty_collection?(v)
  collection?(v) and (v == [] or map_entries_or_nil(v) == [])
end

def map_entries_or_nil(v)
  if map?(v)
    map_entries(v)
  end
end

def yaml_inline(v)
  if collection?(v) and map?(v)
    "{}"
  elsif collection?(v)
    "[]"
  else
    scalar_text(v)
  end
end

def yaml_lines(v, pad)
  if collection?(v) and map?(v)
    flatten(
      map((e) -> yaml_entry(yaml_key(first(e)), second(e), pad), map_entries(v))
    )
  else
    flatten(map((x) -> yaml_item(x, pad), v))
  end
end

def yaml_entry(key, v, pad)
  if collection?(v) and not empty_collection?(v)
    append(["#{pad}#{key}:"], yaml_lines(v, "#{pad}  "))
  else
    ["#{pad}#{key}: #{yaml_inline(v)}"]
  end
end

def yaml_item(x, pad)
  if collection?(x) and not empty_collection?(x)
    lines = yaml_lines(x, "#{pad}  ")
    head = "#{pad}- #{join(drop(length(pad) + 2, chars(first(lines))), "")}"
    cons(head, rest(lines))
  else
    ["#{pad}- #{yaml_inline(x)}"]
  end
end

def yaml(v)
  if collection?(v) and not empty_collection?(v)
    unlines([join(yaml_lines(v, ""), line_break)])
  else
    unlines([yaml_inline(v)])
  end
end

@doc """
toml_key: a TOML key, quoted when it needs to be.

    toml_key("a") #=> "a"
    toml_key("a b") #=> "\"a b\""
"""
def toml_key(k)
  yaml_key(k)
end

@doc """
table_list?: whether a value is a list TOML writes as an array of tables.

    table_list?([{a: 1}]) #=> true
    table_list?([1]) #=> false
"""
def table_list?(v)
  list?(v) and v != [] and every?(map?, v)
end

@doc """
toml_value: a scalar or a list of scalars as TOML, refused for what TOML cannot hold there.

    toml_value([1, 2], "x") #=> "[1, 2]"
    (toml_value(nil, "x") rescue :refused) #=> :refused
"""
def toml_value(v, name)
  if v == []
    "[]"
  elsif list?(v)
    "[#{join(map((x) -> toml_value(x, name), v), ", ")}]"
  elsif map?(v)
    raise(:render_error, "TOML has no table inside an array here: #{name}")
  elsif v.nil?
    raise(:render_error, "TOML has no null: #{name}")
  else
    scalar_text(v)
  end
end

@doc """
toml_scalar_lines: `key = value` lines from entries.

    toml_scalar_lines([[:a, 1]]) #=> ["a = 1"]
"""
def toml_scalar_lines(rows)
  map(
    (e) -> "#{toml_key(first(e))} = #{toml_value(second(e), to_s(first(e)))}",
    rows
  )
end

@doc """
toml_section: the blocks of one table: its own lines under its header, then the tables below it.

    toml_section([[:a, 1]], [], "") #=> [["a = 1"]]
"""
def toml_section(entries, path, header)
  rows = filter(
    (e) -> not map?(second(e)) and not table_list?(second(e)),
    entries
  )
  tables = filter((e) -> map?(second(e)), entries)
  lists = filter((e) -> table_list?(second(e)), entries)
  own = if path == [] or rows != [] or tables == [] and lists == []
    if path == []
      [toml_scalar_lines(rows)]
    else
      [append([header], toml_scalar_lines(rows))]
    end
  else
    []
  end
  below = flat_map_list(
    append(
      map(
        (e) -> toml_table(second(e), append(path, [toml_key(first(e))])),
        tables
      ),
      map(
        (e) -> toml_array(second(e), append(path, [toml_key(first(e))])),
        lists
      )
    )
  )
  filter((block) -> block != [], append(own, below))
end

@doc """
flat_map_list: lists of blocks joined into one list of blocks.

    flat_map_list([[1], [2]]) #=> [1, 2]
"""
def flat_map_list(xss)
  reduce((acc, xs) -> append(acc, xs), [], xss)
end

@doc """
toml_table: a map's blocks at a path.

    toml_table({a: 1}, []) #=> [["a = 1"]]
"""
def toml_table(m, path)
  live = filter((e) -> not second(e).nil?, map_entries(m))
  toml_section(live, path, "[#{join(path, ".")}]")
end

@doc """
toml_array: a list of maps as array-of-tables blocks at a path.

    toml_array([{a: 1}], ["r"]) #=> [["[[r]]", "a = 1"]]
"""
def toml_array(rows, path)
  flat_map_list(
    map(
      fn(row)
        live = filter((e) -> not second(e).nil?, map_entries(row))
        toml_section(live, path, "[[#{join(path, ".")}]]")
      end,
      rows
    )
  )
end

@doc """
toml: a map as TOML text, keys sorted, each nested map a `[table]`, each list of maps an `[[array of tables]]`, an absent value left out. A value TOML cannot hold raises :render_error.

    toml({}) #=> ""
    toml({a: 1, b: "x"}) #=> "a = 1\nb = \"x\"\n"
    toml({s: {t: {u: true}}}) #=> "[s.t]\nu = true\n"
    toml({xs: [1, 2]}) #=> "xs = [1, 2]\n"
"""
def toml(v)
  if not map?(v)
    raise(:render_error, "TOML's top level is a table, got #{to_s(v)}")
  end
  blocks = toml_table(v, [])
  if blocks == []
    ""
  else
    unlines(
      [
        join(
          map((block) -> join(block, line_break), blocks),
          "#{line_break}#{line_break}"
        )
      ]
    )
  end
end

test "toml writes tables after the scalars that come before them, in sorted key order"
  got = toml({z: 1, a: {k: "v"}, m: 2, b: {c: {d: 3}}})
  assert got ==
    unlines(["m = 2", "z = 1", "", "[a]", "k = \"v\"", "", "[b.c]", "d = 3"])
end

test "toml writes an array of tables, an empty array and an empty table"
  assert toml({rows: [{a: 1}, {a: 2}]}) ==
    unlines(["[[rows]]", "a = 1", "", "[[rows]]", "a = 2"])
  assert toml({xs: []}) == unlines(["xs = []"])
  assert toml({t: {}}) == unlines(["[t]"])
end

test "toml leaves an absent value out, quotes a key that needs it, and escapes a string"
  assert toml({a: nil, b: 1}) == unlines(["b = 1"])
  assert toml({"a b" => 1}) == unlines(["\"a b\" = 1"])
  assert toml({s: "q\"x"}) == unlines(["s = \"q\\\"x\""])
end

test "toml refuses what TOML cannot hold"
  top = begin
    toml([1])
  rescue :render_error
    :refused
  end
  assert top == :refused
  assert (toml({xs: [nil]}) rescue :refused) == :refused
  assert (toml({xs: [1, {a: 1}]}) rescue :refused) == :refused
end

test "pretty prints maps sorted, lists in order, scalars as JSON"
  assert pretty({}) == unlines(["{}"])
  assert pretty([]) == unlines(["[]"])
  assert pretty(nil) == unlines(["null"])
  assert pretty({"b" => [1, true], "a" => "x\"y"}) ==
    unlines(
      [
        "{",
        "  \"a\": \"x\\\"y\",",
        "  \"b\": [",
        "    1,",
        "    true",
        "  ]",
        "}"
      ]
    )
  assert json_read(pretty({"k" => {"n" => 1.5, "z" => nil}})) ==
    {"k" => {"n" => 1.5, "z" => nil}}
end

test "a float reads back a Float from the YAML, JSON and TOML deeta writes"
  xs = [
    1.0,
    10000000000000000.0,
    -25000000000000000.0,
    1.0e21,
    1.5e300,
    0.0000003,
    2.5e-300
  ]
  assert to_s(parse(yaml({"k" => xs}), :yaml)["k"]) == to_s(xs)
  assert to_s(json_read(pretty({"k" => xs}))["k"]) == to_s(xs)
  assert every?(float?, parse(yaml({"k" => xs}), :yaml)["k"])
  assert toml({k: xs}) ==
    unlines(
      ["k = [1.0, 10000000000000000.0, -25000000000000000.0, 1.0e21, 1.5e300, 0.0000003, 2.5e-300]"]
    )
end

test "yaml writes block maps and lists, quoting every string"
  assert yaml({}) == unlines(["{}"])
  assert yaml([]) == unlines(["[]"])
  assert yaml("a") == unlines(["\"a\""])
  assert yaml({"a" => 1, "b" => {"c" => "d"}}) ==
    unlines(["a: 1", "b:", "  c: \"d\""])
  assert yaml({"l" => [1, {"x" => true, "z" => []}], "e" => {}}) ==
    unlines(["e: {}", "l:", "  - 1", "  - x: true", "    z: []"])
  assert yaml({"has space" => nil, "true" => false}) ==
    unlines(["\"has space\": null", "\"true\": false"])
end

test "a key is plain only when YAML cannot read it as something else"
  assert plain_key?("replicaCount") == true
  assert plain_key?("app.kubernetes.io/name") == false
  assert plain_key?("9lives") == false
  assert plain_key?("yes") == false
  assert plain_key?("") == false
end

@doc """
parse: text to value; the format is an argument.

    parse("", :yaml, {documents: :all}) #=> []
"""
def parse(text, format, opts?)
  options = if opts.nil?
    {}
  else
    opts
  end
  unknown = filter((e) -> first(e) != :documents, map_entries(options))
  if unknown != []
    raise(
      :bad_option,
      "parse takes the option documents:, not #{to_s(first(first(unknown)))}"
    )
  end
  if format == :json
    json_read(text)
  elsif format == :xml
    xml_document(text)
  elsif format == :yaml
    one_or_all(yaml_documents(text), options[:documents])
  elsif format == :nix
    nix_document(text)
  else
    raise(
      :bad_option,
      "parse reads :json, :yaml, :xml and :nix, not #{to_s(format)}"
    )
  end
end

def one_or_all(docs, documents)
  if documents == :all
    docs
  elsif docs == []
    nil
  elsif count(docs) == 1
    first(docs)
  else
    raise(
      :parse_error,
      "the stream holds #{count(docs)} documents; parse(text, :yaml, {documents: :all}) reads every one"
    )
  end
end

def yaml_documents(text)
  y = text_rows(text)
  map((d) -> first(compose_node(d, {})), stream_documents(y, 0, []))
end

def text_rows(text)
  t = replace(replace(text, unlines(["\r"]), line_break), "\r", line_break)
  u = if starts_with?(t, "\u{feff}")
    join(drop(1, chars(t)), "")
  else
    t
  end
  ls = split(u, line_break)
  kept = if last(ls) == ""
    butlast(ls)
  else
    ls
  end
  rows = map(chars, kept)
  {rows:, nr: count(rows), handles: default_handles}
end

def default_handles()
  {"!" => "!", "!!" => "tag:yaml.org,2002:"}
end

def at_char(y, r, c)
  row = y[:rows][r]
  if row.nil?
    nil
  elsif c >= count(row)
    line_break
  else
    row[c]
  end
end

def blank_char?(ch)
  ch == " " or ch == "\t"
end

def line_end?(ch)
  ch.nil? or ch == line_break
end

def separator?(ch)
  line_end?(ch) or blank_char?(ch)
end

def flow_indicator?(ch)
  member?(ch, [",", "[", "]", "{", "}"])
end

def skip_blanks(y, r, c)
  if blank_char?(at_char(y, r, c))
    skip_blanks(y, r, c + 1)
  else
    c
  end
end

def comment_at?(y, r, c)
  at_char(y, r, c) == "#" and (c == 0 or blank_char?(at_char(y, r, c - 1)))
end

def next_content(y, r, c)
  k = skip_blanks(y, r, c)
  ch = at_char(y, r, k)
  if ch.nil?
    [y[:nr], 0]
  elsif ch == line_break or comment_at?(y, r, k)
    next_content(y, r + 1, 0)
  else
    [r, k]
  end
end

def marker_line?(y, r, ch)
  at_char(y, r, 0) == ch and
    at_char(y, r, 1) == ch and
    at_char(y, r, 2) == ch and
    separator?(at_char(y, r, 3))
end

def content_level(y, r, c)
  if r >= y[:nr]
    -1
  elsif c == 0 and (marker_line?(y, r, "-") or marker_line?(y, r, "."))
    -1
  else
    c
  end
end

def yaml_fail(r, c, message)
  raise(
    :parse_error,
    "#{r + 1}:#{c + 1}: #{message}",
    {data: {line: r + 1, column: c + 1}}
  )
end

def row_slice(y, r, a, b)
  join(take(b - a, drop(a, y[:rows][r])), "")
end

def leading_spaces(y, r, c)
  if at_char(y, r, c) == " "
    leading_spaces(y, r, c + 1)
  else
    c
  end
end

def rest_of_line(y, r, c)
  k = skip_blanks(y, r, c)
  if line_end?(at_char(y, r, k)) or comment_at?(y, r, k)
    k
  else
    yaml_fail(r, k, "unexpected text after a value")
  end
end

def word_end(y, r, c)
  ch = at_char(y, r, c)
  if separator?(ch) or flow_indicator?(ch)
    c
  else
    word_end(y, r, c + 1)
  end
end

def verbatim_end(y, r, c)
  ch = at_char(y, r, c)
  if ch == ">"
    c + 1
  elsif line_end?(ch)
    yaml_fail(r, c, "a verbatim tag is not closed with \">\"")
  else
    verbatim_end(y, r, c + 1)
  end
end

def node_properties(y, r, c, props)
  ch = at_char(y, r, c)
  if ch == "&"
    e = word_end(y, r, c + 1)
    if e == c + 1
      yaml_fail(r, c, "an anchor needs a name")
    elsif props[:anchor] != nil
      yaml_fail(r, c, "a node takes one anchor")
    end
    node_properties(
      y,
      r,
      skip_blanks(y, r, e),
      assoc(props, :anchor, row_slice(y, r, c + 1, e))
    )
  elsif ch == "!"
    e = if at_char(y, r, c + 1) == "<"
      verbatim_end(y, r, c + 2)
    else
      word_end(y, r, c + 1)
    end
    if props[:tag] != nil
      yaml_fail(r, c, "a node takes one tag")
    end
    node_properties(
      y,
      r,
      skip_blanks(y, r, e),
      assoc(props, :tag, expand_tag(y, r, c, row_slice(y, r, c, e)))
    )
  else
    {props:, c:}
  end
end

def expand_tag(y, r, c, raw)
  cs = chars(raw)
  if starts_with?(raw, "!<")
    join(butlast(drop(2, cs)), "")
  elsif raw == "!"
    "!"
  else
    j = position("!", rest(cs))
    handle = if j >= 0
      join(take(j + 2, cs), "")
    else
      "!"
    end
    prefix = get(y[:handles], handle)
    if prefix.nil?
      yaml_fail(r, c, "the tag handle #{handle} is not declared")
    end
    "#{prefix}#{join(drop(count(chars(handle)), cs), "")}"
  end
end

def merged_properties(r, c, a, b)
  if a[:anchor] != nil and b[:anchor] != nil or
      a[:tag] != nil and b[:tag] != nil
    yaml_fail(r, c, "a node takes one anchor and one tag")
  end
  {
    anchor: if b[:anchor].nil?
      a[:anchor]
    else
      b[:anchor]
    end,
    tag: if b[:tag].nil?
      a[:tag]
    else
      b[:tag]
    end
  }
end

def bare?(props)
  props[:anchor].nil? and props[:tag].nil?
end

def scalar_node(text, plain, props)
  {kind: :scalar, text:, plain:, tag: props[:tag], anchor: props[:anchor]}
end

def with_properties(node, props)
  assoc(assoc(node, :tag, props[:tag]), :anchor, props[:anchor])
end

def block_indicator?(y, r, c, ch)
  at_char(y, r, c) == ch and separator?(at_char(y, r, c + 1))
end

def block_node(y, r, c, n, ctx, outer)
  c1 = skip_blanks(y, r, c)
  p = node_properties(y, r, c1, {})
  line = p[:props]
  c2 = p[:c]
  ch = at_char(y, r, c2)
  collection_here = member?(ctx, %i[fresh fresh_map seq explicit])
  tabbed = member?("\t", chars(row_slice(y, r, c, c2)))
  if line_end?(ch) or comment_at?(y, r, c2)
    later_node(y, r, c2, n, ctx, merged_properties(r, c1, outer, line))
  elsif block_indicator?(y, r, c2, "-") or block_indicator?(y, r, c2, "?")
    if not collection_here
      yaml_fail(r, c2, "a block collection cannot start on this line")
    elsif tabbed
      yaml_fail(
        r,
        c,
        "a tab cannot separate an indicator from a block collection"
      )
    elsif not bare?(line)
      yaml_fail(
        r,
        c1,
        "properties need their own line before a block collection"
      )
    elsif ch == "-"
      block_sequence(y, r, c2, outer)
    else
      block_mapping(y, r, c2, outer)
    end
  elsif ch == "|" or ch == ">"
    block_scalar(y, r, c2, n, merged_properties(r, c1, outer, line))
  elsif block_indicator?(y, r, c2, ":") or implicit_key?(y, r, c2)
    if not collection_here
      yaml_fail(r, c2, "a mapping cannot start on this line")
    elsif tabbed and ctx == :explicit
      yaml_fail(
        r,
        c,
        "a tab cannot separate an indicator from a block collection"
      )
    else
      block_mapping(y, r, c1, outer)
    end
  else
    qn = if ctx == :seq
      n - 1
    else
      n
    end
    v = inline_node(
      y,
      r,
      c2,
      n,
      qn,
      merged_properties(r, c1, outer, line),
      false
    )
    {node: v[:node], r: v[:r], c: rest_of_line(y, v[:r], v[:c])}
  end
end

def later_node(y, r, c, n, ctx, props)
  at = next_content(y, r, c)
  r2 = first(at)
  c2 = second(at)
  m = content_level(y, r2, c2)
  beside = member?(ctx, %i[map fresh_map explicit])
  if m > n
    if leading_spaces(y, r2, 0) <= n
      yaml_fail(r2, 0, "a tab cannot indent a block")
    end
    block_node(
      y,
      r2,
      c2,
      n,
      if beside
        :fresh_map
      else
        :fresh
      end,
      props
    )
  elsif m == n and beside and block_indicator?(y, r2, c2, "-")
    block_sequence(y, r2, c2, props)
  else
    {node: scalar_node("", true, props), r:, c:}
  end
end

def block_sequence(y, r, m, props)
  s = sequence_items(y, r, m, [])
  {
    node: with_properties({kind: :seq, items: s[:items]}, props),
    r: s[:r],
    c: s[:c]
  }
end

def sequence_items(y, r, m, items)
  item = block_node(y, r, m + 1, m, :seq, {})
  all = append(items, [item[:node]])
  at = next_content(y, item[:r], item[:c])
  r2 = first(at)
  c2 = second(at)
  level = content_level(y, r2, c2)
  if level == m and block_indicator?(y, r2, c2, "-")
    sequence_items(y, r2, m, all)
  elsif level > m
    yaml_fail(r2, c2, "this line is indented deeper than its sequence")
  else
    {items: all, r: r2, c: c2}
  end
end

def block_mapping(y, r, m, props)
  s = mapping_entries(y, r, m, [])
  {
    node: with_properties({kind: :map, pairs: s[:pairs]}, props),
    r: s[:r],
    c: s[:c]
  }
end

def mapping_entries(y, r, m, pairs)
  e = mapping_entry(y, r, m)
  all = append(pairs, [e[:pair]])
  at = next_content(y, e[:r], e[:c])
  r2 = first(at)
  c2 = second(at)
  level = content_level(y, r2, c2)
  if level == m
    mapping_entries(y, r2, m, all)
  elsif level > m
    yaml_fail(r2, c2, "this line is indented deeper than its mapping")
  else
    {pairs: all, r: r2, c: c2}
  end
end

def mapping_entry(y, r, m)
  if block_indicator?(y, r, m, "?")
    k = block_node(y, r, m + 1, m, :explicit, {})
    at = next_content(y, k[:r], k[:c])
    r2 = first(at)
    c2 = second(at)
    if content_level(y, r2, c2) == m and block_indicator?(y, r2, c2, ":")
      v = block_node(y, r2, m + 1, m, :explicit, {})
      {pair: [k[:node], v[:node]], r: v[:r], c: v[:c]}
    else
      {pair: [k[:node], scalar_node("", true, {})], r: k[:r], c: k[:c]}
    end
  else
    p = node_properties(y, r, m, {})
    kc = p[:c]
    k = if block_indicator?(y, r, kc, ":")
      {node: scalar_node("", true, p[:props]), r:, c: kc}
    else
      inline_node(y, r, kc, m, m, p[:props], true)
    end
    if k[:r] != r
      yaml_fail(r, kc, "a mapping key must sit on one line")
    end
    c3 = skip_blanks(y, r, k[:c])
    if block_indicator?(y, r, c3, ":")
      v = block_node(y, r, c3 + 1, m, :map, {})
      {pair: [k[:node], v[:node]], r: v[:r], c: v[:c]}
    else
      yaml_fail(r, c3, "a mapping key needs \":\" after it")
    end
  end
end

def implicit_key?(y, r, c)
  k = inline_node(y, r, c, -1, -1, {}, true)
  k[:r] == r and block_indicator?(y, r, skip_blanks(y, r, k[:c]), ":")
rescue _
  false
end

def inline_node(y, r, c, n, qn, props, single)
  ch = at_char(y, r, c)
  if ch == "*"
    if not bare?(props)
      yaml_fail(r, c, "an alias takes no anchor and no tag")
    end
    e = word_end(y, r, c + 1)
    {node: {kind: :alias, name: row_slice(y, r, c + 1, e)}, r:, c: e}
  elsif ch == "\"" or ch == "'"
    q = quoted_run(y, r, c + 1, "", "", ch == "\"", qn)
    {node: scalar_node(q[:text], false, props), r: q[:r], c: q[:c]}
  elsif ch == "[" or ch == "{"
    f = flow_collection(y, r, c, n)
    {node: with_properties(f[:node], props), r: f[:r], c: f[:c]}
  elsif plain_start?(y, r, c, false)
    e = plain_end(y, r, c, false)
    p = if single
      {text: row_slice(y, r, c, e), r:, c: e}
    else
      plain_continued(y, r, e, n, false, row_slice(y, r, c, e))
    end
    {node: scalar_node(p[:text], true, props), r: p[:r], c: p[:c]}
  else
    yaml_fail(r, c, "#{json_stringify(to_s(ch))} cannot start a value")
  end
end

def plain_start?(y, r, c, flow)
  ch = at_char(y, r, c)
  nx = at_char(y, r, c + 1)
  if separator?(ch)
    false
  elsif member?(ch, %w[- ? :])
    not separator?(nx) and not (flow and flow_indicator?(nx))
  else
    not member?(
      ch,
      [
        ",",
        "[",
        "]",
        "{",
        "}",
        "#",
        "&",
        "*",
        "!",
        "|",
        ">",
        "'",
        "\"",
        "%",
        "@",
        "`"
      ]
    )
  end
end

def plain_end(y, r, c, flow)
  plain_trim(y, r, c, plain_scan(y, r, c, flow))
end

def plain_scan(y, r, j, flow)
  ch = at_char(y, r, j)
  nx = at_char(y, r, j + 1)
  if line_end?(ch)
    j
  elsif ch == ":" and (separator?(nx) or flow and flow_indicator?(nx))
    j
  elsif comment_at?(y, r, j)
    j
  elsif flow and flow_indicator?(ch)
    j
  else
    plain_scan(y, r, j + 1, flow)
  end
end

def plain_trim(y, r, c, j)
  if j > c and blank_char?(at_char(y, r, j - 1))
    plain_trim(y, r, c, j - 1)
  else
    j
  end
end

def line_breaks(k)
  join(map((_) -> line_break, range(k)), "")
end

def next_text_line(y, r, empties)
  if r >= y[:nr]
    {r:, c: 0, empties:}
  else
    k = skip_blanks(y, r, 0)
    if at_char(y, r, k) == line_break
      next_text_line(y, r + 1, empties + 1)
    else
      {r:, c: k, empties:}
    end
  end
end

def plain_continued(y, r, e, n, flow, text)
  done = {text:, r:, c: e}
  if not line_end?(at_char(y, r, skip_blanks(y, r, e)))
    done
  else
    nl = next_text_line(y, r + 1, 0)
    r2 = nl[:r]
    c2 = nl[:c]
    if r2 >= y[:nr] or
        content_level(y, r2, c2) < 0 or
        leading_spaces(y, r2, 0) <= n or
        comment_at?(y, r2, c2)
      done
    else
      e2 = plain_end(y, r2, c2, flow)
      if e2 == c2
        done
      else
        joint = if nl[:empties] == 0
          " "
        else
          line_breaks(nl[:empties])
        end
        plain_continued(
          y,
          r2,
          e2,
          n,
          flow,
          "#{text}#{joint}#{row_slice(y, r2, c2, e2)}"
        )
      end
    end
  end
end

def quoted_break(y, r, qn)
  nl = next_text_line(y, r, 0)
  inside = nl[:r] < y[:nr]
  if inside and nl[:c] == 0 and content_level(y, nl[:r], 0) < 0
    yaml_fail(nl[:r], 0, "a document marker cannot sit inside a quoted scalar")
  elsif inside and qn >= 0 and leading_spaces(y, nl[:r], 0) <= qn
    yaml_fail(
      nl[:r],
      0,
      "a quoted scalar's lines are indented deeper than its block"
    )
  end
  nl
end

def quoted_word_end(y, r, c, double)
  ch = at_char(y, r, c)
  if separator?(ch) or ch == "'" or double and (ch == "\"" or ch == "\\")
    c
  else
    quoted_word_end(y, r, c + 1, double)
  end
end

def quoted_run(y, r, c, out, ws, double, qn)
  ch = at_char(y, r, c)
  if ch.nil?
    yaml_fail(r, c, "a quoted scalar is not closed")
  elsif double and ch == "\""
    {text: "#{out}#{ws}", r:, c: c + 1}
  elsif not double and ch == "'"
    if at_char(y, r, c + 1) == "'"
      quoted_run(y, r, c + 2, "#{out}#{ws}'", "", double, qn)
    else
      {text: "#{out}#{ws}", r:, c: c + 1}
    end
  elsif double and ch == "\\"
    if at_char(y, r, c + 1) == line_break
      nl = quoted_break(y, r + 1, qn)
      quoted_run(
        y,
        nl[:r],
        nl[:c],
        "#{out}#{ws}#{line_breaks(nl[:empties])}",
        "",
        double,
        qn
      )
    else
      x = escape_at(y, r, c + 1)
      quoted_run(y, r, x[:c], "#{out}#{ws}#{x[:text]}", "", double, qn)
    end
  elsif blank_char?(ch)
    quoted_run(y, r, c + 1, out, "#{ws}#{ch}", double, qn)
  elsif ch == line_break
    nl = quoted_break(y, r + 1, qn)
    joint = if nl[:empties] == 0
      " "
    else
      line_breaks(nl[:empties])
    end
    quoted_run(y, nl[:r], nl[:c], "#{out}#{joint}", "", double, qn)
  else
    e = quoted_word_end(y, r, c + 1, double)
    quoted_run(y, r, e, "#{out}#{ws}#{row_slice(y, r, c, e)}", "", double, qn)
  end
end

def simple_escapes()
  {
    "0" => code_point_text(0),
    "a" => code_point_text(7),
    "b" => code_point_text(8),
    "t" => "\t",
    "\t" => "\t",
    "n" => line_break,
    "v" => code_point_text(11),
    "f" => code_point_text(12),
    "r" => code_point_text(13),
    "e" => code_point_text(27),
    " " => " ",
    "\"" => "\"",
    "/" => "/",
    "\\" => "\\",
    "N" => code_point_text(133),
    "_" => code_point_text(160),
    "L" => code_point_text(8232),
    "P" => code_point_text(8233)
  }
end

def escape_at(y, r, c)
  ch = at_char(y, r, c)
  simple = get(simple_escapes, to_s(ch))
  width = get({"x" => 2, "u" => 4, "U" => 8}, to_s(ch))
  if simple != nil
    {text: simple, c: c + 1}
  elsif width != nil
    digits = row_slice(y, r, c + 1, c + 1 + width)
    v = radix_value(digits, 16)
    t = if count(chars(digits)) == width and v != nil
      code_point_text(v)
    end
    if t.nil?
      yaml_fail(r, c - 1, "\\#{ch}#{digits} is not a Unicode scalar value")
    end
    {text: t, c: c + 1 + width}
  else
    yaml_fail(r, c - 1, "\\#{to_s(ch)} is not an escape")
  end
end

def radix_value(s, base)
  reduce(
    fn(acc, ch)
      d = position(downcase(ch), chars("0123456789abcdef"))
      if acc.nil? or d < 0 or d >= base
        nil
      else
        acc * base + d
      end
    end,
    0,
    chars(s)
  )
end

def code_point_text(v)
  if v < 0 or v > 1_114_111 or v >= 55296 and v <= 57343
    nil
  elsif v < 128
    bytes_text([v])
  elsif v < 2048
    bytes_text([192 + floor(v / 64), 128 + v % 64])
  elsif v < 65536
    bytes_text([224 + floor(v / 4096), 128 + floor(v / 64) % 64, 128 + v % 64])
  else
    bytes_text(
      [
        240 + floor(v / 262_144),
        128 + floor(v / 4096) % 64,
        128 + floor(v / 64) % 64,
        128 + v % 64
      ]
    )
  end
end

def flow_collection(y, r, c, n)
  if at_char(y, r, c) == "["
    flow_items(y, r, c + 1, n, [], true)
  else
    flow_items(y, r, c + 1, n, [], false)
  end
end

def flow_space(y, r, c, n)
  at = next_content(y, r, c)
  r2 = first(at)
  c2 = second(at)
  if r2 >= y[:nr]
    yaml_fail(r, c, "a flow collection is not closed")
  elsif r2 > r and content_level(y, r2, c2) < 0
    yaml_fail(r2, 0, "a document marker cannot sit inside a flow collection")
  elsif r2 > r and leading_spaces(y, r2, 0) <= n
    yaml_fail(
      r2,
      c2,
      "a flow collection's lines are indented deeper than its block"
    )
  end
  at
end

def flow_items(y, r, c, n, items, in_seq)
  close = if in_seq
    "]"
  else
    "}"
  end
  at = flow_space(y, r, c, n)
  r1 = first(at)
  c1 = second(at)
  if at_char(y, r1, c1) == close
    flow_done(items, in_seq, r1, c1 + 1)
  elsif at_char(y, r1, c1) == ","
    yaml_fail(r1, c1, "a flow collection has no empty entries")
  else
    e = flow_entry(y, r1, c1, n, in_seq)
    all = append(items, [e[:node]])
    after = flow_space(y, e[:r], e[:c], n)
    r2 = first(after)
    c2 = second(after)
    ch = at_char(y, r2, c2)
    if ch == ","
      flow_items(y, r2, c2 + 1, n, all, in_seq)
    elsif ch == close
      flow_done(all, in_seq, r2, c2 + 1)
    else
      yaml_fail(r2, c2, "expected \",\" or \"#{close}\" in a flow collection")
    end
  end
end

def flow_done(items, in_seq, r, c)
  node = if in_seq
    {kind: :seq, items:, tag: nil, anchor: nil}
  else
    {kind: :map, pairs: items, tag: nil, anchor: nil}
  end
  {node:, r:, c:}
end

def json_like?(node)
  node[:kind] == :seq or
    node[:kind] == :map or
    node[:kind] == :scalar and not node[:plain]
end

def flow_entry(y, r, c, n, in_seq)
  explicit = at_char(y, r, c) == "?" and
    (separator?(at_char(y, r, c + 1)) or flow_indicator?(at_char(y, r, c + 1)))
  k = if explicit
    at = flow_space(y, r, c + 1, n)
    flow_node(y, first(at), second(at), n)
  else
    flow_node(y, r, c, n)
  end
  at = flow_space(y, k[:r], k[:c], n)
  r2 = first(at)
  c2 = second(at)
  nx = at_char(y, r2, c2 + 1)
  same_line = explicit or not in_seq or r2 == k[:r]
  if at_char(y, r2, c2) == ":" and
      same_line and
      (separator?(nx) or flow_indicator?(nx) or json_like?(k[:node]))
    after = flow_space(y, r2, c2 + 1, n)
    vch = at_char(y, first(after), second(after))
    v = if member?(vch, [",", "]", "}"])
      {node: scalar_node("", true, {}), r: first(after), c: second(after)}
    else
      flow_node(y, first(after), second(after), n)
    end
    flow_pair(k[:node], v[:node], in_seq, v[:r], v[:c])
  elsif in_seq and not explicit
    k
  else
    flow_pair(k[:node], scalar_node("", true, {}), in_seq, k[:r], k[:c])
  end
end

def flow_pair(key, value, in_seq, r, c)
  node = if in_seq
    {kind: :map, pairs: [[key, value]], tag: nil, anchor: nil}
  else
    [key, value]
  end
  {node:, r:, c:}
end

def flow_node(y, r, c, n)
  p = node_properties(y, r, c, {})
  props = p[:props]
  at = if not bare?(props) and line_end?(at_char(y, r, p[:c]))
    flow_space(y, r, p[:c], n)
  else
    [r, p[:c]]
  end
  r1 = first(at)
  c1 = second(at)
  ch = at_char(y, r1, c1)
  nx = at_char(y, r1, c1 + 1)
  if ch.nil? or
      member?(ch, [",", "]", "}"]) or
      ch == ":" and (separator?(nx) or flow_indicator?(nx))
    {node: scalar_node("", true, props), r: r1, c: c1}
  elsif member?(ch, ["[", "{", "*", "\"", "'"])
    inline_node(y, r1, c1, n, n, props, true)
  elsif plain_start?(y, r1, c1, true)
    e = plain_end(y, r1, c1, true)
    t = plain_continued(y, r1, e, n, true, row_slice(y, r1, c1, e))
    {node: scalar_node(t[:text], true, props), r: t[:r], c: t[:c]}
  else
    yaml_fail(r1, c1, "#{json_stringify(to_s(ch))} cannot start a value")
  end
end

def block_header(y, r, c, digit, chomp)
  ch = at_char(y, r, c)
  if chomp.nil? and (ch == "+" or ch == "-")
    block_header(
      y,
      r,
      c + 1,
      digit,
      if ch == "+"
        :keep
      else
        :strip
      end
    )
  elsif digit.nil? and member?(ch, chars("123456789"))
    block_header(y, r, c + 1, to_int(ch), chomp)
  else
    {
      digit:,
      chomp: if chomp.nil?
        :clip
      else
        chomp
      end,
      c:
    }
  end
end

def auto_indent(y, r, n, widest)
  if r >= y[:nr]
    n + 1
  else
    sp = leading_spaces(y, r, 0)
    if at_char(y, r, sp) == line_break
      auto_indent(y, r + 1, n, max(widest, sp))
    elsif at_char(y, r, sp) == "\t" and sp <= n
      yaml_fail(r, sp, "a tab cannot indent a block scalar")
    elsif sp <= n or sp == 0 and content_level(y, r, 0) < 0
      n + 1
    elsif widest > sp
      yaml_fail(
        r,
        0,
        "a leading empty line is indented deeper than the first text line"
      )
    else
      sp
    end
  end
end

def block_lines(y, r, ind, acc, lead)
  if r >= y[:nr] or ind == 0 and content_level(y, r, 0) < 0
    {lines: acc, r:}
  else
    width = count(y[:rows][r])
    sp = leading_spaces(y, r, 0)
    if sp == width and (lead or width <= ind)
      block_lines(y, r + 1, ind, append(acc, [nil]), lead)
    elsif sp >= ind and width > ind
      block_lines(
        y,
        r + 1,
        ind,
        append(acc, [row_slice(y, r, ind, width)]),
        false
      )
    else
      {lines: acc, r:}
    end
  end
end

def trailing_nils(xs, k)
  if count(xs) > 0 and last(xs).nil?
    trailing_nils(butlast(xs), k + 1)
  else
    k
  end
end

def indented_line?(l)
  blank_char?(first(chars(l)))
end

def folded_text(body)
  first(
    reduce(
      fn(acc, l)
        out = acc[0]
        prev = acc[1]
        k = acc[2]
        if l.nil?
          [out, prev, k + 1]
        elsif prev.nil?
          ["#{out}#{line_breaks(k)}#{l}", l, 0]
        elsif indented_line?(prev) or indented_line?(l)
          [join_lines([out, "#{line_breaks(k)}#{l}"]), l, 0]
        elsif k == 0
          ["#{out} #{l}", l, 0]
        else
          ["#{out}#{line_breaks(k)}#{l}", l, 0]
        end
      end,
      ["", nil, 0],
      body
    )
  )
end

def chomped(text, has_body, trailing, chomp)
  if chomp == :strip
    text
  elsif chomp == :keep and has_body
    join_lines([text, line_breaks(trailing)])
  elsif chomp == :keep
    line_breaks(trailing)
  elsif has_body
    unlines([text])
  else
    ""
  end
end

def block_scalar(y, r, c, n, props)
  h = block_header(y, r, c + 1, nil, nil)
  k = skip_blanks(y, r, h[:c])
  if not (line_end?(at_char(y, r, k)) or comment_at?(y, r, k))
    yaml_fail(r, k, "a block scalar's header ends its line")
  end
  ind = if h[:digit].nil?
    auto_indent(y, r + 1, n, 0)
  else
    max(n, 0) + h[:digit]
  end
  b = block_lines(y, r + 1, ind, [], h[:digit].nil?)
  ls = b[:lines]
  t = trailing_nils(ls, 0)
  body = take(count(ls) - t, ls)
  text = if at_char(y, r, c) == ">"
    folded_text(body)
  else
    join(map((l) -> to_s(l), body), line_break)
  end
  {
    node: scalar_node(chomped(text, body != [], t, h[:chomp]), false, props),
    r: b[:r],
    c: 0
  }
end

def compose_node(node, anchors)
  kind = node[:kind]
  out = if kind == :alias
    found = get(anchors, node[:name])
    if found.nil?
      raise(:parse_error, "the alias *#{node[:name]} names no anchor before it")
    end
    [first(found), anchors]
  elsif kind == :scalar
    [resolve_scalar(node), anchors]
  elsif kind == :seq
    reduce(
      fn(acc, item)
        c = compose_node(item, second(acc))
        [append(first(acc), [first(c)]), second(c)]
      end,
      [[], anchors],
      node[:items]
    )
  else
    composed_pairs(node[:pairs], anchors)
  end
  name = node[:anchor]
  if name.nil?
    out
  else
    [first(out), assoc(second(out), name, [first(out)])]
  end
end

def composed_pairs(pairs, anchors)
  done = reduce(
    fn(acc, pair)
      kc = compose_node(first(pair), acc[2])
      vc = compose_node(second(pair), second(kc))
      key = key_text(first(kc))
      if get(acc[1], key) != nil
        refuse_document(
          :duplicate_key,
          "the key #{json_stringify(key)} appears twice in one mapping"
        )
      end
      [assoc(acc[0], key, first(vc)), assoc(acc[1], key, true), second(vc)]
    end,
    [{}, {}, anchors],
    pairs
  )
  [done[0], done[2]]
end

def key_text(v)
  if string?(v)
    v
  elsif v.nil?
    "null"
  elsif v == true
    "true"
  elsif v == false
    "false"
  elsif number?(v)
    to_s(v)
  else
    refuse_document(
      :complex_key,
      "a mapping key is a scalar in blue; this one is #{to_s(v)}"
    )
  end
end

def refuse_document(reason, message)
  raise(:parse_error, message, {data: {reason:}})
end

def core_tag(name)
  "tag:yaml.org,2002:#{name}"
end

def resolve_scalar(node)
  tag = node[:tag]
  t = node[:text]
  v = if tag.nil? and node[:plain]
    core_value(t)
  elsif tag.nil? or tag == "!" or tag == core_tag("str")
    t
  elsif tag == core_tag("null")
    if member?(t, null_words)
      nil
    else
      :bad
    end
  elsif tag == core_tag("bool")
    if member?(t, true_words)
      true
    elsif member?(t, false_words)
      false
    else
      :bad
    end
  elsif tag == core_tag("int")
    int_value(t)
  elsif tag == core_tag("float")
    float_value(t)
  else
    t
  end
  if v == :bad or v.nil? and member?(tag, [core_tag("int"), core_tag("float")])
    refuse_document(:bad_value, "#{json_stringify(t)} is not a #{tag}")
  end
  v
end

def null_words()
  ["", "~", "null", "Null", "NULL"]
end

def true_words()
  %w[true True TRUE]
end

def false_words()
  %w[false False FALSE]
end

def core_value(t)
  if member?(t, null_words)
    nil
  elsif member?(t, true_words)
    true
  elsif member?(t, false_words)
    false
  else
    i = int_value(t)
    f = float_value(t)
    if i != nil
      i
    elsif f != nil
      f
    else
      t
    end
  end
end

def digits?(s)
  s != "" and every?((ch) -> member?(ch, chars("0123456789")), chars(s))
end

def unsigned(t)
  if starts_with?(t, "-") or starts_with?(t, "+")
    join(drop(1, chars(t)), "")
  else
    t
  end
end

def int_value(t)
  rest_text = join(drop(2, chars(t)), "")
  if starts_with?(t, "0o") and
      digits?(rest_text) and
      count(chars(rest_text)) <= 20
    radix_value(rest_text, 8)
  elsif starts_with?(t, "0x") and
      rest_text != "" and
      count(chars(rest_text)) <= 15
    radix_value(rest_text, 16)
  elsif digits?(unsigned(t))
    to_int(t)
  end
end

def float_value(t)
  if member?(t, %w[.inf .Inf .INF +.inf +.Inf +.INF])
    to_float("inf")
  elsif member?(t, %w[-.inf -.Inf -.INF])
    to_float("-inf")
  elsif member?(t, %w[.nan .NaN .NAN])
    to_float("nan")
  elsif float_text?(unsigned(t))
    to_float(t)
  end
end

def float_text?(body)
  parts = split(replace(body, "E", "e"), "e")
  count(parts) <= 2 and
    mantissa?(first(parts)) and
    (count(parts) == 1 or digits?(unsigned(second(parts))))
end

def mantissa?(m)
  ps = split(m, ".")
  if count(ps) == 1
    digits?(m)
  elsif count(ps) == 2
    first(ps) == "" and digits?(second(ps)) or
      digits?(first(ps)) and (second(ps) == "" or digits?(second(ps)))
  else
    false
  end
end

def stream_documents(y, r, docs)
  at = next_content(y, r, 0)
  r1 = first(at)
  c1 = second(at)
  y0 = assoc(y, :handles, default_handles)
  if r1 >= y[:nr]
    docs
  elsif c1 == 0 and at_char(y, r1, 0) == "%"
    d = directives(y0, r1, default_handles, false)
    explicit_document(assoc(y, :handles, d[:handles]), d[:r], docs)
  elsif c1 == 0 and marker_line?(y, r1, "-")
    explicit_document(y0, r1, docs)
  elsif c1 == 0 and marker_line?(y, r1, ".")
    rest_of_line(y, r1, 3)
    stream_documents(y, r1 + 1, docs)
  else
    document_end(y, block_node(y0, r1, c1, -1, :fresh, {}), docs)
  end
end

def explicit_document(y, r, docs)
  document_end(y, block_node(y, r, 3, -1, :doc, {}), docs)
end

def document_end(y, res, docs)
  all = append(docs, [res[:node]])
  at = next_content(y, res[:r], res[:c])
  r2 = first(at)
  c2 = second(at)
  if r2 >= y[:nr]
    all
  elsif c2 == 0 and marker_line?(y, r2, "-")
    stream_documents(y, r2, all)
  elsif c2 == 0 and marker_line?(y, r2, ".")
    rest_of_line(y, r2, 3)
    stream_documents(y, r2 + 1, all)
  else
    yaml_fail(r2, c2, "the document has ended; this text has no place in it")
  end
end

def directives(y, r, handles, seen)
  at = next_content(y, r, 0)
  r1 = first(at)
  here = r1 < y[:nr] and second(at) == 0
  if here and at_char(y, r1, 0) == "%"
    all_words = filter(
      (w) -> w != "",
      split(replace(row_slice(y, r1, 0, count(y[:rows][r1])), "\t", " "), " ")
    )
    cut = position(true, map((w) -> starts_with?(w, "#"), all_words))
    words = if cut < 0
      all_words
    else
      take(cut, all_words)
    end
    name = first(words)
    version = split(to_s(second(words)), ".")
    if name == "%YAML" and seen
      yaml_fail(r1, 0, "a document takes one %YAML directive")
    elsif name == "%YAML" and
        (
          count(words) != 2 or
          count(version) != 2 or
          not every?(digits?, version)
        )
      yaml_fail(r1, 0, "%YAML takes one version, as 1.2")
    elsif name == "%YAML"
      directives(y, r1 + 1, handles, true)
    elsif name == "%TAG" and count(words) == 3
      directives(y, r1 + 1, assoc(handles, second(words), third(words)), seen)
    elsif name == "%TAG"
      yaml_fail(r1, 0, "%TAG takes a handle and a prefix")
    else
      directives(y, r1 + 1, handles, seen)
    end
  elsif here and marker_line?(y, r1, "-")
    {handles:, r: r1}
  else
    yaml_fail(r1, second(at), "directives are followed by \"---\"")
  end
end

def refused_kind(text)
  parse(text, :yaml)
rescue e
  if e.data.nil?
    e.kind
  else
    get_or(e.data, :reason, e.kind)
  end
end

test "parse :yaml reads block maps, sequences and plain scalars by the core schema"
  assert parse(
    unlines(["a: 1", "b:", "  - x", "  - 2.5", "  - true", "  - ~", "c: 0x1f"]),
    :yaml
  ) == {"a" => 1, "b" => ["x", 2.5, true, nil], "c" => 31}
  assert parse(unlines(["key:", "- a", "- b", "next: yes"]), :yaml) ==
    {"key" => %w[a b], "next" => "yes"}
  assert parse(unlines(["- a: 1", "  b: 2", "- - c"]), :yaml) ==
    [{"a" => 1, "b" => 2}, ["c"]]
  assert parse(unlines(["plain", "  folded", "", "  text"]), :yaml) ==
    join_lines(["plain folded", "text"])
  assert parse("[0o17, 0x1F, -12, +3, 1e3, .5, -.inf, 0o8]", :yaml) ==
    [15, 31, -12, 3, 1000.0, 0.5, to_float("-inf"), "0o8"]
end

test "parse :yaml reads flow collections and quoted scalars with their escapes"
  assert parse("{a: [1, 'it''s'], \"b\": {c: d}, e: [x: y]}", :yaml) ==
    {"a" => [1, "it's"], "b" => {"c" => "d"}, "e" => [{"x" => "y"}]}
  assert parse("\"tab\\there \\u00e9 \\x41\"", :yaml) == "tab\there é A"
  assert parse(join_lines(["'one", "", "  two '"]), :yaml) ==
    join_lines(["one", "two "])
  assert parse("[\"a \", 'b ']", :yaml) == ["a ", "b "]
  assert refused_kind(join_lines(["[ a", "  : b ]"])) == :parse_error
end

test "parse :yaml reads literal and folded block scalars under each chomping"
  assert parse(
    unlines(
      ["a: |", "  one", "  two", "", "b: >-", "  one", "  two", "", "  three"]
    ),
    :yaml
  ) == {"a" => unlines(%w[one two]), "b" => join_lines(["one two", "three"])}
  assert parse(
    unlines(["- |+", "  kept", "", "- |2-", "    indented"]),
    :yaml
  ) == [unlines(["kept", ""]), "  indented"]
end

test "parse :yaml composes anchors, aliases and tags"
  assert parse(
    unlines(["base: &b {x: 1}", "use: *b", "n: !!str 12", "f: !!float 3"]),
    :yaml
  ) == {"base" => {"x" => 1}, "use" => {"x" => 1}, "n" => "12", "f" => 3.0}
  assert refused_kind(unlines(["a: *nowhere"])) == :parse_error
  assert refused_kind(unlines(["a: !!int twelve"])) == :bad_value
end

test "parse :yaml reads one document, every document when asked, and nil for none"
  assert parse("", :yaml).nil?
  assert parse(unlines(["# only a comment"]), :yaml).nil?
  assert parse(
    unlines(["--- first", "--- second", "..."]),
    :yaml,
    {documents: :all}
  ) == %w[first second]
  assert parse("", :yaml, {documents: :all}) == []
  assert refused_kind(unlines(["--- a", "--- b"])) == :parse_error
end

test "parse :yaml refuses a broken stream with its line and column"
  r = begin
    parse(unlines(["a: 1", "  b: 2"]), :yaml)
  rescue e
    e.message
  end
  assert starts_with?(r, "2:")
  assert refused_kind(unlines(["a: b: c"])) == :parse_error
  assert refused_kind(unlines(["[a, b"])) == :parse_error
  assert refused_kind(unlines(["\"open"])) == :parse_error
end

test "parse refuses a collection key, a repeated key and an unknown format"
  assert refused_kind(unlines(["? [a]", ": b"])) == :complex_key
  assert refused_kind(unlines(["a: 1", "a: 2"])) == :duplicate_key
  assert (parse("a", :toml) rescue :refused) == :refused
  assert (parse("a", :yaml, {document: 1}) rescue :refused) == :refused
end

test "parse :json reads JSON into maps, as json_read does"
  assert parse("{\"a\": [1, null]}", :json) == {"a" => [1, nil]}
  assert parse("{\"a\": [1, null]}", :yaml) == {"a" => [1, nil]}
end

test "get_if keeps the value only when pred holds"
  doc = json_parse("{\"n\":3,\"f\":3.5,\"k\":\"v\",\"z\":null}")
  assert get_if(nil, "k", string?, "d") == "d"
  assert get_if(doc, "k", (_v) -> true, "d") == "v"
  assert get_if(doc, "n", integer?, 0) == 3
  assert get_if(doc, "f", integer?, 0) == 0
  assert get_if(doc, "z", (v) -> not v.nil?, 7) == 7
end

@doc """
read: A JSON text as blue values, in the shapes `json_parse` gives, read by blue
itself (R6a of docs/PURE-BLUE.md): an object as a list of [key, value] pairs (an
empty one as the empty map), an array as a list, null as nil, and a number as
`json_number` reads it, which refuses each text `json_parse` refuses.

    read("{\"a\": [1, 2.5, null, true]}") #=> [["a", [1, 2.5, nil, true]]]
    read("[]") #=> []
"""
def read(text)
  got = json_value(skip_ws(chars(text)))
  if not empty?(skip_ws(got[1]))
    raise(:json, "deeta::read: trailing characters after the value")
  end
  got[0]
end

@doc """
skip_ws: The characters past any JSON whitespace at the front.

    skip_ws(chars("  x")) #=> ["x"]
"""
def skip_ws(cs)
  if not empty?(cs) and member?(first(cs), [" ", line_break, "\t", "\r"])
    skip_ws(rest(cs))
  else
    cs
  end
end

@doc """
json_value: One JSON value read from the front of the characters, with what follows it.

    json_value(chars("1 ]"))[0] #=> 1
"""
def json_value(cs)
  if empty?(cs)
    raise(:json, "deeta::read: EOF while parsing a value")
  end
  c = first(cs)
  if c == "{"
    json_object(skip_ws(rest(cs)), [])
  elsif c == "["
    json_array(skip_ws(rest(cs)), [])
  elsif c == "\""
    json_string(rest(cs), [])
  elsif c == "t"
    [true, json_word(cs, "true")]
  elsif c == "f"
    [false, json_word(cs, "false")]
  elsif c == "n"
    [nil, json_word(cs, "null")]
  else
    json_number(cs, [])
  end
end

@doc """
json_word: The characters past the literal word (true, false, null), refused when it is not there.

    json_word(chars("true,"), "true") #=> [","]
"""
def json_word(cs, word)
  json_word_from(cs, chars(word), word)
end

@doc """
json_word_from: json_word, one character of the word at a time.

    json_word_from(chars("ab"), chars("a"), "a") #=> ["b"]
"""
def json_word_from(cs, want, word)
  if empty?(want)
    cs
  elsif empty?(cs) or first(cs) != first(want)
    raise(:json, "deeta::read: expected #{word}")
  else
    json_word_from(rest(cs), rest(want), word)
  end
end

@doc """
json_object: An object read after its opening brace: the pairs so far are in acc, latest first.

    json_object(chars("\"a\": 1}"), [])[0] #=> [["a", 1]]
"""
def json_object(cs, acc)
  if acc == [] and not empty?(cs) and first(cs) == "}"
    [{}, rest(cs)]
  elsif empty?(cs) or first(cs) != "\""
    raise(:json, "deeta::read: expected a string key")
  else
    key = json_string(rest(cs), [])
    after = skip_ws(key[1])
    if empty?(after) or first(after) != ":"
      raise(:json, "deeta::read: expected : after a key")
    end
    value = json_value(skip_ws(rest(after)))
    more = skip_ws(value[1])
    pairs = cons([key[0], value[0]], acc)
    if not empty?(more) and first(more) == ","
      json_object(skip_ws(rest(more)), pairs)
    elsif not empty?(more) and first(more) == "}"
      [object_pairs(pairs), rest(more)]
    else
      raise(:json, "deeta::read: expected , or } in an object")
    end
  end
end

@doc """
object_pairs: An object's pairs as `json_parse` gives them, from the pairs read latest
first: one per key, the last a key took, ordered by key.

    object_pairs([["a", 2], ["b", 1], ["a", 1]]) #=> [["a", 2], ["b", 1]]
"""
def object_pairs(latest_first)
  sort_keyed((p) -> p[0], last_of_each(latest_first, [], []))
end

@doc """
last_of_each: The pairs with one per key, the first seen of each in the given order.

    last_of_each([["a", 2], ["a", 1]], [], []) #=> [["a", 2]]
"""
def last_of_each(pairs, seen, kept)
  if empty?(pairs)
    kept
  elsif member?(first(pairs)[0], seen)
    last_of_each(rest(pairs), seen, kept)
  else
    last_of_each(
      rest(pairs),
      cons(first(pairs)[0], seen),
      cons(first(pairs), kept)
    )
  end
end

@doc """
json_array: An array read after its opening bracket: the items so far are in acc, latest first.

    json_array(chars("1]"), [])[0] #=> [1]
"""
def json_array(cs, acc)
  if acc == [] and not empty?(cs) and first(cs) == "]"
    [[], rest(cs)]
  else
    value = json_value(cs)
    more = skip_ws(value[1])
    items = cons(value[0], acc)
    if not empty?(more) and first(more) == ","
      json_array(skip_ws(rest(more)), items)
    elsif not empty?(more) and first(more) == "]"
      [reverse(items), rest(more)]
    else
      raise(:json, "deeta::read: expected , or ] in an array")
    end
  end
end

@doc """
json_string: A string read after its opening quote: the characters so far are in acc, latest first.

    json_string(chars("ab\""), [])[0] #=> "ab"
"""
def json_string(cs, acc)
  if empty?(cs)
    raise(:json, "deeta::read: EOF while parsing a string")
  end
  c = first(cs)
  if c == "\""
    [join(reverse(acc), ""), rest(cs)]
  elsif c == "\\"
    json_escape(rest(cs), acc)
  else
    json_string(rest(cs), cons(c, acc))
  end
end

@doc """
json_escape: One escape read after its backslash, the string read on from there.

    json_escape(chars("/\""), [])[0] #=> "/"
"""
def json_escape(cs, acc)
  if empty?(cs)
    raise(:json, "deeta::read: EOF in an escape")
  end
  c = first(cs)
  simple = {
    "\"" => "\"",
    "\\" => "\\",
    "/" => "/",
    "b" => "\u{8}",
    "f" => "\u{c}",
    "n" => line_break,
    "r" => "\r",
    "t" => "\t"
  }
  if c == "u"
    unit = hex4(rest(cs))
    json_unit(unit[0], unit[1], acc)
  elsif get(simple, c) != nil
    json_string(rest(cs), cons(get(simple, c), acc))
  else
    raise(:json, "deeta::read: unknown escape \\#{c}")
  end
end

@doc """
json_unit: The text of one \\u unit, joined with the low half that follows a high surrogate.

    json_unit(65, chars("\""), [])[0] #=> "A"
"""
def json_unit(code, cs, acc)
  if code >= 55296 and
      code <= 56319 and
      length(cs) >= 6 and
      first(cs) == "\\" and
      first(rest(cs)) == "u"
    low = hex4(drop(2, cs))
    joined = 65536 + (code - 55296) * 1024 + (low[0] - 56320)
    json_string(low[1], cons(code_point_text(joined), acc))
  else
    json_string(cs, cons(code_point_text(code), acc))
  end
end

@doc """
hex4: The value of the four hex digits at the front, with what follows them.

    hex4(chars("00e9"))[0] #=> 233
"""
def hex4(cs)
  digits = join(
    [first(cs), first(rest(cs)), first(drop(2, cs)), first(drop(3, cs))],
    ""
  )
  v = radix_value(digits, 16)
  if v.nil?
    raise(:json, "deeta::read: \\u#{digits} is not four hex digits")
  end
  [v, drop(4, cs)]
end

@doc """
json_number: A number read from its characters, as json_parse reads it: a
Float with a fraction or exponent, past what an Int holds, or for -0, else an
Int; text JSON does not write as a number, or a number no Float holds, raises
:json.

    json_number(chars("12,"), [])[0] #=> 12
    json_number(chars("9223372036854775808"), [])[0] #=> 9223372036854775808.0
    to_s(json_number(chars("-0"), [])[0]) #=> "-0.0"
    (json_number(chars("1e400"), []) rescue :refused) #=> :refused
    (json_number(chars("01"), []) rescue :refused) #=> :refused
"""
def json_number(cs, acc)
  if not empty?(cs) and member?(first(cs), chars("-+0123456789.eE"))
    json_number(rest(cs), cons(first(cs), acc))
  else
    text = join(reverse(acc), "")
    if text == ""
      raise(:json, "deeta::read: expected a value")
    elsif not json_number_text?(text)
      raise(:json, "deeta::read: #{text} is not a JSON number")
    end
    floating = text == "-0" or any?((c) -> member?(c, %w[. e E]), acc)
    whole = if floating
      nil
    else
      to_int(text)
    end
    n = if whole.nil?
      to_float(text)
    else
      whole
    end
    if n - n != 0
      raise(:json, "deeta::read: #{text} is out of range")
    end
    [n, cs]
  end
end

@doc """
json_number_text?: Whether the text is a number as JSON writes one (RFC 8259):
a minus or none, then 0 or digits that do not start with 0, then a point and
digits or none, then an e or E, a sign or none and digits, or none.

    json_number_text?("-0.5e+3") #=> true
    json_number_text?("01") #=> false
    json_number_text?("1.") #=> false
    json_number_text?("+1") #=> false
"""
def json_number_text?(text)
  body = if starts_with?(text, "-")
    join(drop(1, chars(text)), "")
  else
    text
  end
  at_e = split(downcase(body), "e")
  at_point = split(at_e[0], ".")
  whole = at_point[0]
  count(at_e) <= 2 and
    count(at_point) <= 2 and
    (whole == "0" or digits?(whole) and not starts_with?(whole, "0")) and
    (count(at_point) == 1 or digits?(at_point[1])) and
    (count(at_e) == 1 or digits?(unsigned(at_e[1])))
end

test "read gives the values json_parse gives, on every JSON shape", {
  kind: :unit
}
  samples = [
    "42",
    "-2e3",
    "1.5",
    "true",
    "null",
    "\"x\\ny\\u00e9\\ud83d\\ude00\\t\\\"\\/\"",
    "[]",
    "{}",
    "[[], {}, [1, [2]]]",
    "{\"a\": 1, \"b\": [1.5, -2e3, null, true, false], \"c\": {\"d\": \"e\"}}",
    "  [ 1 , 2 ]  "
  ]
  assert filter((t) -> read(t) != json_parse(t), samples) == []
  assert (read("{") rescue :refused) == :refused
  assert (read("[1, 2") rescue :refused) == :refused
  assert (read("[1] x") rescue :refused) == :refused
end

test "read gives a Float past i64 and refuses a number no Float holds", {
  kind: :unit
}
  assert float?(read("9223372036854775808"))
  assert float?(read("-9223372036854775809"))
  assert integer?(read("9223372036854775807"))
  assert to_s(read("[18446744073709551616]")) ==
    to_s(json_parse("[18446744073709551616]"))
  assert (read("1e400") rescue :refused) == :refused
  assert (read("[1, -1e400]") rescue :refused) == :refused
  assert (read("[1, 2-]") rescue :refused) == :refused
end

test "read gives -0 as -0.0 and refuses each number json_parse refuses", {
  kind: :unit
}
  texts = [
    "-0",
    "[-0]",
    "{\"a\": -0}",
    "-0.0",
    "-0e0",
    "0",
    "+1",
    "01",
    "-01",
    "00",
    "1.",
    ".5",
    "-.5",
    "1.e5",
    "1e",
    "1e+",
    "1E+2",
    "1e05",
    "-",
    "--1"
  ]
  assert filter(
    fn(t)
      to_s([read(t) rescue :refused]) != to_s([json_parse(t) rescue :refused])
    end,
    texts
  ) == []
  assert to_s(read("[-0, 0]")) == "[-0.0, 0]"
  assert (read("+1") rescue :refused) == :refused
end

test "each step of read takes what it reads and gives back the rest", {
  kind: :unit
}
  assert skip_ws(chars("  x")) == ["x"]
  assert json_value(chars("1 ]"))[0] == 1
  assert json_word(chars("true,"), "true") == [","]
  assert json_word_from(chars("ab"), chars("a"), "a") == ["b"]
  assert json_object(chars("\"a\": 1}"), [])[0] == [["a", 1]]
  assert last_of_each([["a", 2], ["a", 1]], [], []) == [["a", 2]]
  assert json_array(chars("1]"), [])[0] == [1]
  assert json_string(chars("ab\""), [])[0] == "ab"
  assert json_escape(chars("n\""), [])[0] == line_break
  assert json_unit(233, chars("\""), [])[0] == "é"
  assert hex4(chars("00e9"))[0] == 233
  assert json_number(chars("12,"), [])[0] == 12
  assert json_number_text?("-0.5e+3")
  assert not json_number_text?("1.")
  assert object_pairs([["b", 1], ["a", 2]]) == [["a", 2], ["b", 1]]
end

@doc """
write: A blue value as compact JSON text, written by blue itself (R6a of
docs/PURE-BLUE.md), exactly as `json_write` writes it: every list an array, a
map an object with its keys in byte order, a keyword or symbol as its name, a
float as Rust's shortest text, and anything JSON cannot hold as null.

    write([["a", 1], ["b", 2.5]]) #=> "[[\"a\",1],[\"b\",2.5]]"
"""
def write(v)
  json_text(v, false)
end

@doc """
stringify: A blue value as compact JSON text, exactly as `json_stringify`
writes it: like `write`, except a list whose every element is a [name, value]
pair is an object, the shape `read` gives an object.

    stringify([["b", 1], ["a", nil]]) #=> "{\"a\":null,\"b\":1}"
"""
def stringify(v)
  json_text(v, true)
end

@doc """
json_text: The JSON text of a value; pairs says whether a list of pairs is an object.

    json_text([true, nil], false) #=> "[true,null]"
"""
def json_text(v, pairs)
  if v.nil?
    "null"
  elsif v == true
    "true"
  elsif v == false
    "false"
  elsif integer?(v)
    to_s(v)
  elsif float?(v)
    float_text(v)
  elsif string?(v) or symbol?(v) or keyword?(v)
    quoted(to_s(v))
  elsif map?(v)
    object_text(map((e) -> [json_key(e[0]), e[1]], map_entries(v)), pairs)
  elsif list?(v) and pairs and object_like?(v)
    object_text(map((p) -> [to_s(p[0]), p[1]], v), pairs)
  elsif list?(v)
    "[#{join(map((x) -> json_text(x, pairs), v), ",")}]"
  else
    "null"
  end
end

@doc """
object_like?: Whether a list is a non-empty list of [name, value] pairs, a name
being a string, symbol or keyword.

    object_like?([["a", 1], [:b, 2]]) #=> true
"""
def object_like?(xs)
  xs != [] and
    not any?(
      fn(p)
        not (
          list?(p) and
          count(p) == 2 and
          (string?(p[0]) or symbol?(p[0]) or keyword?(p[0]))
        )
      end,
      xs
    )
end

@doc """
object_text: An object's JSON text from its [key, value] entries: the last value
of a repeated key kept, the keys in byte order.

    object_text([["b", 1], ["a", 2], ["b", 3]], true) #=> "{\"a\":2,\"b\":3}"
"""
def object_text(entries, pairs)
  kept = sort_keyed((e) -> e[0], last_of_each(reverse(entries), [], []))
  body = map((e) -> "#{quoted(e[0])}:#{json_text(e[1], pairs)}", kept)
  "{#{join(body, ",")}}"
end

@doc """
json_key: A map key as the object key json_write gives it: nil as null, a name
as itself, a finite float as Rust's Display writes it (plain digits, never an
exponent, a whole value with no point), anything else as its text.

    json_key(nil) #=> "null"
    json_key(1.5) #=> "1.5"
    json_key(1.0e21) #=> "1000000000000000000000"
"""
def json_key(k)
  if k.nil?
    "null"
  elsif float?(k) and k - k == 0.0
    dec = decimal_parts(k)
    "#{dec.sign}#{display_text(dec.digits, dec.point)}"
  else
    to_s(k)
  end
end

@doc """
quoted: A string as a JSON string literal: quote and backslash escaped, the
five short control escapes, any other control character as \\u00XX.

    quoted("ab") #=> "\"ab\""
"""
def quoted(s)
  "\"#{join(map(escape_char, chars(s)), "")}\""
end

@doc """
escape_char: One character as it stands inside a JSON string literal.

    escape_char("a") #=> "a"
"""
def escape_char(c)
  short = {
    "\"" => "\\\"",
    "\\" => "\\\\",
    "\u{8}" => "\\b",
    "\u{c}" => "\\f",
    line_break => "\\n",
    "\r" => "\\r",
    "\t" => "\\t"
  }
  b = text_bytes(c)
  if get(short, c) != nil
    get(short, c)
  elsif count(b) == 1 and first(b) < 32
    "\\u00#{hex_encode(b)}"
  else
    c
  end
end

@doc """
float_text: A float as serde_json writes it: the shortest digits that read back
to the same float, laid out plain when the point falls within sixteen digits,
as 0.000ddd down to five zeros, else as d.ddde±x; a NaN or an infinity as null.

    float_text(1.0e20) #=> "1e+20"
    float_text(1.5e300) #=> "1.5e+300"
    float_text(2.5e-300) #=> "2.5e-300"
"""
def float_text(x)
  if x - x != 0.0
    "null"
  else
    dec = decimal_parts(x)
    "#{dec.sign}#{ryu_text(dec.digits, dec.point)}"
  end
end

@doc """
decimal_parts: A finite float as its sign, its significant digits given last
first, and the place of its decimal point counted from its first significant
digit, read from to_s's shortest digits; a zero has no digits.

    decimal_parts(-1.5) #=> {sign: "-", digits: ["5", "1"], point: 1}
    decimal_parts(0.001) #=> {sign: "", digits: ["1"], point: -2}
    decimal_parts(1.0e21).point #=> 22
"""
def decimal_parts(x)
  parts = split(to_s(x), "e")
  shift = if count(parts) == 2
    to_int(second(parts))
  else
    0
  end
  t = chars(first(parts))
  neg = first(t) == "-"
  body = if neg
    rest(t)
  else
    t
  end
  whole = take(count_leading((c) -> c != ".", body), body)
  all = filter((c) -> c != ".", body)
  lead = count_leading((c) -> c == "0", all)
  sign = if neg
    "-"
  else
    ""
  end
  {
    sign:,
    digits: drop_zeros(reverse(drop(lead, all))),
    point: count(whole) - lead + shift
  }
end

@doc """
drop_zeros: Characters with the zeros at the front dropped.

    drop_zeros(chars("001")) #=> ["1"]
"""
def drop_zeros(cs)
  drop(count_leading((c) -> c == "0", cs), cs)
end

@doc """
count_leading: How many characters at the front satisfy pred.

    count_leading((c) -> c == "0", chars("001")) #=> 2
"""
def count_leading(pred, cs)
  if not empty?(cs) and pred(first(cs))
    1 + count_leading(pred, rest(cs))
  else
    0
  end
end

@doc """
zero_text: A run of m zeros as text.

    zero_text(3) #=> "000"
"""
def zero_text(m)
  if m <= 0
    ""
  else
    "0#{zero_text(m - 1)}"
  end
end

@doc """
ryu_text: Significant digits, given last first, laid out with the decimal point
point places after the first digit's place, the way ryu does; no digits is 0.0.

    ryu_text(chars("21"), 3) #=> "120.0"
    ryu_text([], 0) #=> "0.0"
"""
def ryu_text(last_first, point)
  d = reverse(last_first)
  n = count(d)
  text = join(d, "")
  if d == []
    "0.0"
  elsif point >= n and point <= 16
    "#{text}#{zero_text(point - n)}.0"
  elsif point > 0 and point <= 16
    "#{join(take(point, d), "")}.#{join(drop(point, d), "")}"
  elsif point > -5 and point <= 0
    "0.#{zero_text(-point)}#{text}"
  else
    frac = if n > 1
      ".#{join(rest(d), "")}"
    else
      ""
    end
    exp = point - 1
    plus = if exp > 0
      "+"
    else
      ""
    end
    "#{first(d)}#{frac}e#{plus}#{exp}"
  end
end

@doc """
display_text: Significant digits, given last first, laid out with the decimal
point point places after the first digit's place, the way Rust's Display writes
a float: never an exponent, a whole value with no point, and no digits as 0.

    display_text(chars("51"), 1) #=> "1.5"
    display_text(chars("1"), 22) #=> "1000000000000000000000"
    display_text(chars("1"), -7) #=> "0.00000001"
    display_text([], 0) #=> "0"
"""
def display_text(last_first, point)
  d = reverse(last_first)
  n = count(d)
  text = join(d, "")
  if d == []
    "0"
  elsif point >= n
    "#{text}#{zero_text(point - n)}"
  elsif point > 0
    "#{join(take(point, d), "")}.#{join(drop(point, d), "")}"
  else
    "0.#{zero_text(-point)}#{text}"
  end
end

test "write and stringify give the text json_write and json_stringify give", {
  kind: :unit
}
  negative_zero = -1.0 * 0.0
  samples = [
    nil,
    true,
    false,
    0,
    -12,
    12_345_678_901_234_567,
    1.0,
    -2000.0,
    0.1,
    1000000000000000.0,
    10000000000000000.0,
    100000000000000000000.0,
    0.0000003,
    0.00001,
    0.0001,
    123456.789,
    0.00000012345,
    1.25e21,
    to_float("1.5e300"),
    to_float("2.5e-300"),
    0.0,
    "",
    join_lines(["tab\there", "\"q\"\\/é😀\u{1}\u{1f}\u{7f}"]),
    :sym,
    [],
    {},
    [[], ["a"]],
    [["a", 1], ["b", 2]],
    [["a", 1], [2, 2]],
    [["a", 1], ["a", 2]],
    [[:a, [["b", 1]]]],
    ["a", 1],
    [["a", 1, 2]],
    {b: 1, a: {"z" => nil, "y" => [true, 1.5, -0.25]}},
    {"x" => [["b", 1]], y: {z: [[:q, 1]]}},
    {1 => 2, nil => 3, true => 4, 1.5 => 5, "a" => 0},
    {
      1.0e21 => 1,
      1.0e-8 => 2,
      1.5e300 => 3,
      10000000000000000.0 => 4,
      2.5e-300 => 5,
      negative_zero => 6,
      0.0 => 7
    }
  ]
  assert filter((v) -> write(v) != json_write(v), samples) == []
  assert filter((v) -> stringify(v) != json_stringify(v), samples) == []
end

test "each step of write gives its own part of the text", {kind: :unit}
  assert json_text([1, "a"], false) == "[1,\"a\"]"
  assert object_like?([["a", 1]])
  assert not object_like?([])
  assert object_text([["b", 1], ["a", 2]], true) == "{\"a\":2,\"b\":1}"
  assert json_key(true) == "true"
  assert json_key(1.0) == "1"
  assert json_key(1.0e21) == "1000000000000000000000"
  assert json_key(1.0e-8) == "0.00000001"
  assert json_key(-1.0 * 0.0) == "-0"
  assert quoted("x") == "\"x\""
  assert escape_char(line_break) == "\\n"
  assert escape_char("\u{1}") == "\\u0001"
  assert float_text(0.0000003) == "3e-7"
  assert decimal_parts(0.0).digits == []
  assert decimal_parts(-1.0 * 0.0).sign == "-"
  assert decimal_parts(2.5e-300).point == -299
  assert drop_zeros(chars("0012")) == %w[1 2]
  assert ryu_text(chars("1"), 21) == "1e+20"
  assert display_text(chars("52"), -299) == "0.#{zero_text(299)}25"
  assert count_leading((c) -> c == "0", chars("0a")) == 1
  assert zero_text(0) == ""
end

test "read refuses each malformed JSON at the step that meets it, and reads each edge"
  bad = [
    "",
    "tru",
    "nul",
    "{",
    "{1: 2}",
    "{\"a\" 1}",
    "{\"a\": 1 2}",
    "\"abc",
    "\"\\",
    "\"\\q\"",
    "\"\\u12G4\"",
    "x"
  ]
  assert map((t) -> read(t) rescue :refused, bad) == map((_t) -> :refused, bad)
  assert read("{}") == {}
  assert read("\"\\u0041\\n\"") == unlines(["A"])
  assert read("-1.5e2") == -150.0
  ran = now_ms > 0
  zero = to_float(now_ms * 0)
  assert write(ran) == "true"
  assert write(zero) == "0.0"
  assert write(zero) == json_write(zero)
  huge = exp(to_float(now_ms))
  assert write(huge) == "null"
  assert write(huge) == json_write(huge)
  assert write(() -> now_ms) == "null"
end

@doc """
text_of: The text of bytes s up to e of a byte list.

    text_of(text_bytes("abc"), 1, 3) #=> "bc"
"""
def text_of(b, s, e)
  bytes_text(map((i) -> b[i], range(s, e)))
end

@doc """
run_end: The first index from i whose byte fails pred, or n.

    run_end([1, 1, 2], 3, 0, (c) -> c == 1) #=> 2
"""
def run_end(b, n, i, pred)
  if i < n and pred(b[i])
    run_end(b, n, i + 1, pred)
  else
    i
  end
end

@doc """
bytes_at?: Whether the bytes of lit stand at index i.

    bytes_at?(text_bytes("<!--x"), 5, 0, "<!--") #=> true
"""
def bytes_at?(b, n, i, lit)
  want = text_bytes(lit)
  i + count(want) <= n and
    not any?((k) -> b[i + k] != want[k], range(0, count(want)))
end

@doc """
find_bytes: The first index from i where the bytes of lit stand, or nil.

    find_bytes(text_bytes("a-->b"), 5, 0, "-->") #=> 1
"""
def find_bytes(b, n, i, lit)
  if i + count(text_bytes(lit)) > n
    nil
  elsif bytes_at?(b, n, i, lit)
    i
  else
    find_bytes(b, n, i + 1, lit)
  end
end

@doc """
xml_document: An XML document's root element, read by blue itself (R6c of
docs/PURE-BLUE.md) as `xml_parse` reads it: a map {name, attributes, children,
text}, attributes a map of strings, text the element's own text (with element
children, only the runs that are not all white space). Malformed text raises
:xml_malformed; an entity other than the five predefined ones and character
references raises :xml_refused, and a DOCTYPE never declares one.

    xml_document("<r a=\"1\"><c/></r>")[:attributes] #=> {"a" => "1"}
"""
def xml_document(text)
  b = text_bytes(text)
  xml_step(b, count(b), 0, [], nil)
end

@doc """
xml_malformed: Raise :xml_malformed with a reason.

    raised(() -> xml_malformed("x")) #=> :xml_malformed
"""
def xml_malformed(why)
  raise(:xml_malformed, why)
end

@doc """
space_byte?: Whether a byte is white space: a space, tab, line feed or carriage return.

    space_byte?(9) #=> true
"""
def space_byte?(c)
  member?(c, [32, 9, 10, 13])
end

@doc """
xml_close: An open element [name, attributes, children, texts] (children and
texts latest first) as the element map.

    xml_close(["c", {}, [], ["b", "a"]])[:text] #=> "ab"
"""
def xml_close(open)
  kids = reverse(open[2])
  texts = reverse(open[3])
  kept = if kids == []
    texts
  else
    filter((t) -> trim(t) != "", texts)
  end
  {name: open[0], attributes: open[1], children: kids, text: join(kept, "")}
end

@doc """
xml_attach: The stack and root after a finished element: added to the open
parent's children, or the root when no element is open.

    xml_attach([], {name: "r"}, nil)[1] #=> {name: "r"}
"""
def xml_attach(stack, done, root)
  if stack == []
    [stack, done]
  else
    top = first(stack)
    [cons([top[0], top[1], cons(done, top[2]), top[3]], rest(stack)), root]
  end
end

@doc """
xml_add_text: The stack with a text run added to the open element, refusing
text outside the root unless it is white space (what names the run).

    xml_add_text([["r", {}, [], []]], "t", "text")[0][3] #=> ["t"]
"""
def xml_add_text(stack, t, what)
  if stack == []
    if what == "text" and trim(t) == ""
      stack
    else
      xml_malformed("#{what} outside the root element")
    end
  else
    top = first(stack)
    cons([top[0], top[1], top[2], cons(t, top[3])], rest(stack))
  end
end

@doc """
xml_step: The document read on from byte pos with the open elements (innermost
first) and the root so far.

    xml_step(text_bytes("<r/>"), 4, 0, [], nil)[:name] #=> "r"
"""
def xml_step(b, n, pos, stack, root)
  if pos >= n
    if stack != []
      xml_malformed("<#{first(stack)[0]}> is never closed")
    elsif root.nil?
      xml_malformed("the document has no root element")
    else
      root
    end
  elsif b[pos] == 60
    xml_markup(b, n, pos, stack, root)
  else
    e = run_end(b, n, pos, (c) -> c != 60)
    xml_step(b, n, e, xml_text_runs(b, pos, e, stack), root)
  end
end

@doc """
xml_text_runs: The stack after the character data from s to e, split at each
reference the way the reader splits it: literal runs and resolved references.

    xml_text_runs(text_bytes("a&amp;b"), 0, 7, [["r", {}, [], []]])[0][3] #=> ["b", "&", "a"]
"""
def xml_text_runs(b, s, e, stack)
  if s >= e
    stack
  else
    amp = run_end(b, e, s, (c) -> c != 38)
    with_text = if amp > s
      xml_add_text(stack, text_of(b, s, amp), "text")
    else
      stack
    end
    if amp >= e
      with_text
    else
      semi = run_end(b, e, amp, (c) -> c != 59)
      if semi >= e
        xml_malformed("an unterminated reference")
      end
      ref = xml_reference(text_of(b, amp + 1, semi))
      xml_text_runs(b, semi + 1, e, xml_add_text(with_text, ref, "a reference"))
    end
  end
end

@doc """
xml_reference: The text of a reference's name: a character reference or one of
the five predefined entities; any other entity is refused.

    xml_reference("#x41") #=> "A"
"""
def xml_reference(name)
  cs = chars(name)
  predefined = {
    "lt" => "<",
    "gt" => ">",
    "amp" => "&",
    "apos" => "'",
    "quot" => "\""
  }
  if cs != [] and first(cs) == "#"
    digits = rest(cs)
    hex = digits != [] and first(digits) == "x"
    v = if hex
      radix_value(join(rest(digits), ""), 16)
    else
      radix_value(join(digits, ""), 10)
    end
    legal = v != nil and
      name != "#" and
      name != "#x" and
      (member?(v, [9, 10, 13]) or v >= 32 and v != 65534 and v != 65535)
    t = if legal
      code_point_text(v)
    end
    if t.nil?
      xml_malformed("&#{name}; is not a legal character reference")
    end
    t
  elsif get(predefined, name) != nil
    get(predefined, name)
  else
    raise(
      :xml_refused,
      "entity &#{name}; is not expanded: blue reads only the five predefined entities and character references, never a DTD entity"
    )
  end
end

@doc """
xml_markup: The document read on from a `<`: a comment, CDATA, a DOCTYPE, a
declaration or processing instruction, an end tag or a start tag.

    xml_markup(text_bytes("<!--c--><r/>"), 12, 0, [], nil)[:name] #=> "r"
"""
def xml_markup(b, n, pos, stack, root)
  if bytes_at?(b, n, pos, "<!--")
    close = find_bytes(b, n, pos + 4, "-->")
    if close.nil?
      xml_malformed("an unterminated comment")
    end
    if find_bytes(b, close, pos + 4, "--") != nil
      xml_malformed("a comment holds --")
    end
    xml_step(b, n, close + 3, stack, root)
  elsif bytes_at?(b, n, pos, "<![CDATA[")
    close = find_bytes(b, n, pos + 9, "]]>")
    if close.nil?
      xml_malformed("an unterminated CDATA section")
    end
    xml_step(
      b,
      n,
      close + 3,
      xml_add_text(stack, text_of(b, pos + 9, close), "CDATA"),
      root
    )
  elsif bytes_at?(b, n, pos, "<!DOCTYPE")
    xml_doctype(b, n, pos, stack, root)
  elsif bytes_at?(b, n, pos, "<?")
    close = find_bytes(b, n, pos + 2, "?>")
    if close.nil?
      xml_malformed("an unterminated processing instruction")
    end
    xml_step(b, n, close + 2, stack, root)
  elsif bytes_at?(b, n, pos, "</")
    xml_end_tag(b, n, pos, stack, root)
  else
    xml_start_tag(b, n, pos, stack, root)
  end
end

@doc """
xml_doctype: Past a DOCTYPE, which may stand only before the root and never
declares an entity.

    xml_doctype(text_bytes("<!DOCTYPE r><r/>"), 16, 0, [], nil)[:name] #=> "r"
"""
def xml_doctype(b, n, pos, stack, root)
  if root != nil or stack != []
    xml_malformed("a DOCTYPE after the root element began")
  end
  bracket = run_end(b, n, pos, (c) -> c != 91 and c != 62)
  close = if bracket < n and b[bracket] == 91
    inner = find_bytes(b, n, bracket, "]")
    if inner.nil?
      nil
    else
      run_end(b, n, inner, (c) -> c != 62)
    end
  else
    bracket
  end
  if close.nil? or close >= n
    xml_malformed("an unterminated DOCTYPE")
  end
  if contains?(text_of(b, pos, close), "<!ENTITY")
    raise(
      :xml_refused,
      "the DOCTYPE declares an entity: blue never expands or fetches DTD entities"
    )
  end
  xml_step(b, n, close + 1, stack, root)
end

@doc """
xml_name_end: Where an element or attribute name from i ends.

    xml_name_end(text_bytes("ab c"), 4, 0) #=> 2
"""
def xml_name_end(b, n, i)
  run_end(b, n, i, (c) -> not (space_byte?(c) or member?(c, [47, 62, 61])))
end

@doc """
xml_end_tag: Past an end tag, which closes the innermost open element of the
same name.

    xml_end_tag(text_bytes("</r>"), 4, 0, [["r", {}, [], []]], nil)[:name] #=> "r"
"""
def xml_end_tag(b, n, pos, stack, root)
  close = run_end(b, n, pos, (c) -> c != 62)
  if close >= n
    xml_malformed("an unterminated end tag")
  end
  name = trim(text_of(b, pos + 2, close))
  if stack == []
    xml_malformed("an end tag with no start")
  end
  if first(stack)[0] != name
    xml_malformed("</#{name}> closes <#{first(stack)[0]}>")
  end
  done = xml_attach(rest(stack), xml_close(first(stack)), root)
  xml_step(b, n, close + 1, done[0], done[1])
end

@doc """
xml_start_tag: Past a start tag: its name and attributes, then either an empty
element closed at once or an element left open.

    xml_start_tag(text_bytes("<r a='1'/>"), 10, 0, [], nil)[:attributes] #=> {"a" => "1"}
"""
def xml_start_tag(b, n, pos, stack, root)
  if root != nil and stack == []
    xml_malformed("a second root element")
  end
  ne = xml_name_end(b, n, pos + 1)
  if ne == pos + 1
    xml_malformed("a tag with no name")
  end
  got = xml_attributes(b, n, ne, {})
  open = [text_of(b, pos + 1, ne), got[0], [], []]
  if got[2]
    done = xml_attach(stack, xml_close(open), root)
    xml_step(b, n, got[1], done[0], done[1])
  else
    xml_step(b, n, got[1], cons(open, stack), root)
  end
end

@doc """
xml_attributes: A start tag's attributes from i, with where the tag ends and
whether it closed itself.

    xml_attributes(text_bytes(" a=\"x\">"), 7, 0, {}) #=> [{"a" => "x"}, 7, false]
"""
def xml_attributes(b, n, i, attrs)
  j = run_end(b, n, i, space_byte?)
  if j >= n
    xml_malformed("an unterminated start tag")
  elsif b[j] == 62
    [attrs, j + 1, false]
  elsif b[j] == 47 and j + 1 < n and b[j + 1] == 62
    [attrs, j + 2, true]
  else
    ke = xml_name_end(b, n, j)
    eq = run_end(b, n, ke, space_byte?)
    if ke == j or eq >= n or b[eq] != 61
      xml_malformed("an attribute without a value")
    end
    q = run_end(b, n, eq + 1, space_byte?)
    if q >= n or b[q] != 34 and b[q] != 39
      xml_malformed("an attribute value without quotes")
    end
    close = run_end(b, n, q + 1, (c) -> c != b[q])
    if close >= n
      xml_malformed("an unterminated attribute value")
    end
    key = text_of(b, j, ke)
    if get(attrs, key) != nil
      xml_malformed("a duplicate attribute #{key}")
    end
    value = xml_unescape(b, q + 1, close)
    xml_attributes(b, n, close + 1, assoc(attrs, key, value))
  end
end

@doc """
xml_unescape: An attribute value's text from s to e with its references resolved.

    xml_unescape(text_bytes("1 &amp; 2"), 0, 9) #=> "1 & 2"
"""
def xml_unescape(b, s, e)
  runs = xml_text_runs(b, s, e, [["", {}, [], []]])
  join(reverse(first(runs)[3]), "")
end

@doc """
nix_document: Nix source read by blue itself (R6c of docs/PURE-BLUE.md) as
`nix_parse` reads it: {root, errors}, root rnix's lossless syntax tree (a node
{kind, start, end, children}, a token {kind, start, end, text}, offsets in
characters). Source rnix reports an error in raises :nix_malformed, so errors
is always [].

    nix_document("x")[:root][:children][0][:kind] #=> "NODE_IDENT"
"""
def nix_document(text)
  cs = chars(text)
  n = count(cs)
  toks = nix_tokens(cs, n, 0, [[:plain]], [])
  ends = [{kind: nil, start: n, end: n}, {kind: nil, start: n, end: n}]
  t = [append(toks, ends), nix_levels]
  s = nix_eat(t, nix_expr(t, [0, [], 0, [["NODE_ROOT", 0]], 0]))
  if nix_peek(t, s) != nil
    nix_malformed("input after the expression")
  end
  {root: first(nix_close(s)[1]), errors: []}
end

@doc """
nix_malformed: Raise :nix_malformed with a reason.

    raised(() -> nix_malformed("x")) #=> :nix_malformed
"""
def nix_malformed(why)
  raise(:nix_malformed, why)
end

@doc """
nix_text: The text of characters s up to e of a character list.

    nix_text(chars("abc"), 1, 3) #=> "bc"
"""
def nix_text(cs, s, e)
  join(map((i) -> cs[i], range(s, e)), "")
end

@doc """
nix_space?: Whether a character is white space as Rust's char::is_whitespace
has it, the rule rnix's tokenizer reads.

    nix_space?(code_point_text(12288)) #=> true
"""
def nix_space?(c)
  member?(c, [" ", line_break, "\t", "\r", "\u{b}", "\u{c}"]) or
    c != nil and
      count(text_bytes(c)) > 1 and
      member?(
        c,
        map(
          code_point_text,
          [
            133,
            160,
            5760,
            8192,
            8193,
            8194,
            8195,
            8196,
            8197,
            8198,
            8199,
            8200,
            8201,
            8202,
            8232,
            8233,
            8239,
            8287,
            12288
          ]
        )
      )
end

@doc """
nix_class?: Whether a character is of a class rnix's tokenizer reads: :path
(may stand in a path), :uri (one of the further URI characters), :ident (may
continue an identifier), :start (may open one) or :digit.

    nix_class?(:path, "+") #=> true
"""
def nix_class?(kind, c)
  letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  sets = {
    path: concat(letters, "0123456789/_.+-"),
    uri: "%?:@&=$,!~*'",
    ident: concat(letters, "0123456789_-'"),
    start: concat(letters, "_"),
    digit: "0123456789"
  }
  c != nil and contains?(get(sets, kind), c)
end

@doc """
nix_uri_char?: Whether a character may stand in a Nix URI.

    nix_uri_char?("?") #=> true
"""
def nix_uri_char?(c)
  nix_class?(:path, c) or nix_class?(:uri, c)
end

@doc """
nix_tokens: The tokens of the characters from i on, as rnix's tokenizer cuts
them, with the context stack ctx (innermost first) and acc latest first.

    nix_tokens(chars("a"), 1, 0, [[:plain]], [])[0][:kind] #=> "TOKEN_IDENT"
"""
def nix_tokens(cs, n, i, ctx, acc)
  got = nix_next(cs, n, i, ctx)
  if got.nil?
    reverse(acc)
  else
    j = got[1]
    tok = {kind: got[0], start: i, end: j, text: nix_text(cs, i, j)}
    nix_tokens(cs, n, j, got[2], cons(tok, acc))
  end
end

@doc """
nix_next: The next token from i as [kind, end, context], nil at the end; the
context says whether a string, an interpolation or a path is open.

    nix_next(chars("${"), 2, 0, [[:interpol_start]])[0] #=> "TOKEN_INTERPOL_START"
"""
def nix_next(cs, n, i, ctx)
  top = first(ctx)
  mode = top[0]
  if mode == :interpol_start
    ["TOKEN_INTERPOL_START", i + 2, cons([:interpol, 0], rest(ctx))]
  elsif mode == :path
    nix_path_more(cs, n, i, ctx, top[1])
  elsif mode == :body
    got = nix_lex_string(cs, n, i, top[1], ctx)
    if got[1] == i
      nix_next(cs, n, i, got[2])
    else
      got
    end
  elsif mode == :string_end
    nix_string_end(cs, i, rest(ctx))
  else
    nix_plain(cs, n, i, ctx)
  end
end

@doc """
nix_path_more: The next piece of an open path: an interpolation, more path
characters, or the path closed and the token read plainly.

    nix_path_more(chars("/b"), 2, 0, [[:path, "TOKEN_PATH_ABS"], [:plain]], "TOKEN_PATH_ABS")[0] #=> "TOKEN_PATH_ABS"
"""
def nix_path_more(cs, n, i, ctx, kind)
  if cs[i] == "$" and cs[i + 1] == "{"
    ["TOKEN_INTERPOL_START", i + 2, cons([:interpol, 0], ctx)]
  elsif nix_class?(:path, cs[i])
    nix_path_check(cs, n, i, i, kind, ctx)
  else
    nix_plain(cs, n, i, rest(ctx))
  end
end

@doc """
nix_path_check: A path token from start, its characters read on from p: open
for an interpolation, refused (TOKEN_ERROR) when it ends in / or holds //, or
closed.

    nix_path_check(chars("a/"), 2, 0, 0, "TOKEN_PATH_REL", [[:path, "TOKEN_PATH_REL"]])[0] #=> "TOKEN_ERROR"
"""
def nix_path_check(cs, n, start, p, kind, ctx)
  q = run_end(cs, n, p, (x) -> nix_class?(:path, x))
  if cs[q] == "$" and cs[q + 1] == "{"
    [kind, q, cons([:interpol_start], ctx)]
  elsif cs[q - 1] == "/" or
      any?((k) -> cs[k] == "/" and cs[k + 1] == "/", range(start, q - 1))
    ["TOKEN_ERROR", q, ctx]
  else
    [kind, q, rest(ctx)]
  end
end

@doc """
nix_lex_string: The next run of a string's body from p (multi says an
indented string): its content up to the close or an interpolation, or
TOKEN_ERROR at the end of the input.

    nix_lex_string(chars("a\""), 2, 0, false, [[:body, false]])[0] #=> "TOKEN_STRING_CONTENT"
"""
def nix_lex_string(cs, n, p, multi, ctx)
  stop = nix_string_stop(cs, p, multi, ctx)
  if stop.nil?
    nix_lex_string(cs, n, nix_string_skip(cs, n, p, multi), multi, ctx)
  else
    stop
  end
end

@doc """
nix_string_stop: The token a string's body ends with at p, nil when the body
goes on: the end of the input, the close (" or ''), or an interpolation.

    nix_string_stop(chars("''x"), 0, true, [[:body, true]])[0] #=> "TOKEN_STRING_CONTENT"
"""
def nix_string_stop(cs, p, multi, ctx)
  c = cs[p]
  closes = if multi
    c == "'" and cs[p + 1] == "'" and not member?(cs[p + 2], ["'", "$", "\\"])
  else
    c == "\""
  end
  if c.nil?
    ["TOKEN_ERROR", p, rest(ctx)]
  elsif closes
    ["TOKEN_STRING_CONTENT", p, cons([:string_end], rest(ctx))]
  elsif c == "$" and cs[p + 1] == "{"
    ["TOKEN_STRING_CONTENT", p, cons([:interpol_start], ctx)]
  end
end

@doc """
nix_string_skip: Where a string's body goes on after the character at p: past
an escape (a backslash and a character; three quotes, or two and a dollar; two
quotes, a backslash and a character), past two dollars, or past the one
character.

    nix_string_skip(chars("''$"), 3, 0, true) #=> 3
"""
def nix_string_skip(cs, n, p, multi)
  c = cs[p]
  quoted = multi and c == "'" and cs[p + 1] == "'"
  width = if not multi and c == "\\"
    2
  elsif quoted and cs[p + 2] == "\\"
    4
  elsif quoted
    3
  elsif c == "$" and cs[p + 1] == "$"
    2
  else
    1
  end
  kazu::min(p + width, n)
end

@doc """
nix_string_end: The token that closes a string at i: " or ''.

    nix_string_end(chars("''"), 0, [])[1] #=> 2
"""
def nix_string_end(cs, i, ctx)
  if cs[i] == "\""
    ["TOKEN_STRING_END", i + 1, ctx]
  else
    ["TOKEN_STRING_END", i + 2, ctx]
  end
end

@doc """
nix_plain: The next token from i outside a string or path: white space, a
comment, an ellipsis, or a symbol, word, number or path.

    nix_plain(chars("# c"), 3, 0, [[:plain]])[0] #=> "TOKEN_COMMENT"
"""
def nix_plain(cs, n, i, ctx)
  c = cs[i]
  ws = run_end(cs, n, i, nix_space?)
  if c.nil?
    nil
  elsif ws > i
    ["TOKEN_WHITESPACE", ws, ctx]
  elsif c == "#"
    ["TOKEN_COMMENT", run_end(cs, n, i, (x) -> x != line_break), ctx]
  elsif c == "/" and cs[i + 1] == "*"
    nix_block_comment(cs, n, i + 2, ctx)
  elsif nix_text(cs, i, kazu::min(i + 3, n)) == "..."
    ["TOKEN_ELLIPSIS", i + 3, ctx]
  else
    nix_symbol(cs, n, i, ctx, nix_shape(cs, n, i))
  end
end

@doc """
nix_block_comment: A /* comment read on from p: closed by */, or TOKEN_ERROR
at the end of the input.

    nix_block_comment(chars("/* a */"), 7, 2, [])[1] #=> 7
"""
def nix_block_comment(cs, n, p, ctx)
  m = kazu::min(run_end(cs, n, p, (x) -> x != "*") + 1, n)
  if cs[m].nil?
    ["TOKEN_ERROR", m, ctx]
  elsif cs[m] == "/"
    ["TOKEN_COMMENT", m + 1, ctx]
  else
    nix_block_comment(cs, n, m, ctx)
  end
end

@doc """
nix_shape: What the text at i looks like before it is read, as rnix's
tokenizer guesses it: :abs, :home, :rel, :search, :uri, or nil.

    nix_shape(chars("<nixpkgs>"), 9, 0) #=> :search
"""
def nix_shape(cs, n, i)
  c = cs[i]
  c1 = cs[i + 1]
  if c == "/"
    if c1 == "$" and cs[i + 2] == "{" or c1 != "/" and nix_class?(:path, c1)
      :abs
    end
  elsif c == "~" and c1 == "/"
    :home
  else
    nix_shape_rest(cs, n, i, c == "<")
  end
end

@doc """
nix_shape_rest: The guess for text not opening with / or ~/: what follows the
run of path characters (and < and / when it opens with <) decides.

    nix_shape_rest(chars("a:b"), 3, 0, false) #=> :uri
"""
def nix_shape_rest(cs, n, i, store)
  j = run_end(
    cs,
    n,
    i,
    (x) -> (x == "<" or x == "/") and store or x != "/" and nix_class?(:path, x)
  )
  a = cs[j]
  b = cs[j + 1]
  if a == "/" and b != nil and b != "/" and b != "*" and not nix_space?(b)
    :rel
  elsif a == ">"
    :search
  elsif a == ":" and
      nix_uri_char?(b) and
      not any?((k) -> cs[k] == "_", range(i, j))
    :uri
  end
end

@doc """
nix_symbol: The token at i that is not white space, a comment or an
ellipsis, given the shape guessed for it.

    nix_symbol(chars("//"), 2, 0, [[:plain]], nil)[0] #=> "TOKEN_UPDATE"
"""
def nix_symbol(cs, n, i, ctx, shape)
  c = cs[i]
  c1 = cs[i + 1]
  pair = get(nix_pairs, nix_text(cs, i, kazu::min(i + 2, n)))
  single = get(nix_singles, c)
  if c == "/" and c1 == "/"
    ["TOKEN_UPDATE", i + 2, ctx]
  elsif c == "~" and c1 == "/"
    nix_path_check(
      cs,
      n,
      i,
      i + 2,
      "TOKEN_PATH_HOME",
      nix_path_ctx(ctx, "HOME")
    )
  elsif c == "~"
    ["TOKEN_ERROR", kazu::min(i + 2, n), ctx]
  elsif c == "/" and (shape == :abs or nix_class?(:path, c1))
    nix_path_check(cs, n, i, i + 1, "TOKEN_PATH_ABS", nix_path_ctx(ctx, "ABS"))
  elsif shape == :rel
    nix_path_check(cs, n, i, i + 1, "TOKEN_PATH_REL", nix_path_ctx(ctx, "REL"))
  elsif c == "<" and shape == :search and c1 != "|"
    nix_search_path(cs, n, i, ctx)
  elsif pair != nil
    [pair, i + 2, ctx]
  elsif c == "." and nix_class?(:digit, c1)
    nix_exponent(
      cs,
      n,
      run_end(cs, n, i + 1, (x) -> nix_class?(:digit, x)),
      ctx
    )
  elsif single != nil
    [single, i + 1, ctx]
  else
    nix_symbol_rest(cs, n, i, ctx, shape)
  end
end

@doc """
nix_symbol_rest: The token at i that no operator table names: a brace, an
interpolation, a string, a word, a number, or TOKEN_ERROR.

    nix_symbol_rest(chars("12"), 2, 0, [[:plain]], nil)[0] #=> "TOKEN_INTEGER"
"""
def nix_symbol_rest(cs, n, i, ctx, shape)
  c = cs[i]
  c1 = cs[i + 1]
  if c == "{"
    ["TOKEN_L_BRACE", i + 1, nix_bracket(ctx, 1)]
  elsif c == "}" and first(ctx) == [:interpol, 0]
    ["TOKEN_INTERPOL_END", i + 1, rest(ctx)]
  elsif c == "}"
    ["TOKEN_R_BRACE", i + 1, nix_bracket(ctx, -1)]
  elsif c == "$" and c1 == "{"
    ["TOKEN_INTERPOL_START", i + 2, cons([:interpol, 0], ctx)]
  elsif c == "\""
    ["TOKEN_STRING_START", i + 1, cons([:body, false], ctx)]
  elsif c == "'" and c1 == "'"
    ["TOKEN_STRING_START", i + 2, cons([:body, true], ctx)]
  elsif nix_class?(:start, c)
    nix_word(cs, n, i, ctx, shape == :uri)
  elsif nix_class?(:digit, c)
    nix_number(cs, n, i, ctx)
  else
    ["TOKEN_ERROR", i + 1, ctx]
  end
end

@doc """
nix_path_ctx: The context with a path of the named kind opened.

    nix_path_ctx([], "ABS") #=> [[:path, "TOKEN_PATH_ABS"]]
"""
def nix_path_ctx(ctx, kind)
  cons([:path, concat("TOKEN_PATH_", kind)], ctx)
end

@doc """
nix_bracket: The context after a brace inside an interpolation, its open
brace count moved by d; outside one, the context unchanged.

    nix_bracket([[:interpol, 1]], -1) #=> [[:interpol, 0]]
"""
def nix_bracket(ctx, d)
  top = first(ctx)
  if top[0] == :interpol
    cons([:interpol, top[1] + d], rest(ctx))
  else
    ctx
  end
end

@doc """
nix_pairs: The two-character operators, by their text.

    nix_pairs["++"] #=> "TOKEN_CONCAT"
"""
def nix_pairs()
  {
    "==" => "TOKEN_EQUAL",
    "!=" => "TOKEN_NOT_EQUAL",
    "++" => "TOKEN_CONCAT",
    "->" => "TOKEN_IMPLICATION",
    "<|" => "TOKEN_PIPE_LEFT",
    "&&" => "TOKEN_AND_AND",
    "|>" => "TOKEN_PIPE_RIGHT",
    "||" => "TOKEN_OR_OR",
    "<=" => "TOKEN_LESS_OR_EQ",
    ">=" => "TOKEN_MORE_OR_EQ"
  }
end

@doc """
nix_singles: The one-character symbols, by their text.

    nix_singles["@"] #=> "TOKEN_AT"
"""
def nix_singles()
  {
    "=" => "TOKEN_ASSIGN",
    "!" => "TOKEN_INVERT",
    "[" => "TOKEN_L_BRACK",
    "]" => "TOKEN_R_BRACK",
    "@" => "TOKEN_AT",
    ":" => "TOKEN_COLON",
    "," => "TOKEN_COMMA",
    "." => "TOKEN_DOT",
    "?" => "TOKEN_QUESTION",
    ";" => "TOKEN_SEMICOLON",
    "(" => "TOKEN_L_PAREN",
    ")" => "TOKEN_R_PAREN",
    "+" => "TOKEN_ADD",
    "-" => "TOKEN_SUB",
    "*" => "TOKEN_MUL",
    "/" => "TOKEN_DIV",
    "<" => "TOKEN_LESS",
    ">" => "TOKEN_MORE"
  }
end

@doc """
nix_search_path: A <path> from the < at i: TOKEN_LESS when no path character
follows, TOKEN_ERROR when > does not close it.

    nix_search_path(chars("<a>"), 3, 0, [])[0] #=> "TOKEN_PATH_SEARCH"
"""
def nix_search_path(cs, n, i, ctx)
  p = run_end(cs, n, i + 1, (x) -> nix_class?(:path, x))
  if p == i + 1
    ["TOKEN_LESS", p, ctx]
  elsif cs[p] != ">"
    ["TOKEN_ERROR", kazu::min(p + 1, n), ctx]
  else
    ["TOKEN_PATH_SEARCH", p + 1, ctx]
  end
end

@doc """
nix_word: An identifier, keyword or (uri) URI from i.

    nix_word(chars("let"), 3, 0, [], false)[0] #=> "TOKEN_LET"
"""
def nix_word(cs, n, i, ctx, uri)
  j = run_end(
    cs,
    n,
    i + 1,
    (x) -> nix_class?(:ident, x) or uri and nix_uri_char?(x)
  )
  keywords = {
    "assert" => "TOKEN_ASSERT",
    "else" => "TOKEN_ELSE",
    "if" => "TOKEN_IF",
    "in" => "TOKEN_IN",
    "inherit" => "TOKEN_INHERIT",
    "let" => "TOKEN_LET",
    "or" => "TOKEN_OR",
    "rec" => "TOKEN_REC",
    "then" => "TOKEN_THEN",
    "with" => "TOKEN_WITH"
  }
  word = get(keywords, nix_text(cs, i, j))
  if uri
    ["TOKEN_URI", j, ctx]
  elsif word != nil
    [word, j, ctx]
  else
    ["TOKEN_IDENT", j, ctx]
  end
end

@doc """
nix_number: An integer or float from the digit at i; a 0 not followed by .
reads digits only, as rnix reads it.

    nix_number(chars("1.5"), 3, 0, [])[0] #=> "TOKEN_FLOAT"
"""
def nix_number(cs, n, i, ctx)
  p = run_end(cs, n, i + 1, (x) -> nix_class?(:digit, x))
  if cs[p] == "." and (cs[i] != "0" or cs[i + 1] == ".")
    nix_exponent(
      cs,
      n,
      run_end(cs, n, p + 1, (x) -> nix_class?(:digit, x)),
      ctx
    )
  else
    ["TOKEN_INTEGER", p, ctx]
  end
end

@doc """
nix_exponent: A float read on from p, its exponent if any; an exponent with
no digit is TOKEN_ERROR.

    nix_exponent(chars("1.5e-3"), 6, 3, [])[1] #=> 6
"""
def nix_exponent(cs, n, p, ctx)
  q = if member?(cs[p + 1], %w[- +])
    p + 2
  else
    p + 1
  end
  r = run_end(cs, n, q, (x) -> nix_class?(:digit, x))
  if not member?(cs[p], %w[e E])
    ["TOKEN_FLOAT", p, ctx]
  elsif r == q
    ["TOKEN_ERROR", r, ctx]
  else
    ["TOKEN_FLOAT", r, ctx]
  end
end

@doc """
nix_levels: The binary operator levels of rnix's parser, loosest first:
each [how it binds, its operators]; :invert and :hasattr are the two levels
that are not binary.

    nix_levels[0] #=> [:right, ["TOKEN_PIPE_LEFT"]]
"""
def nix_levels()
  [
    [:right, ["TOKEN_PIPE_LEFT"]],
    [:left, ["TOKEN_PIPE_RIGHT"]],
    [:right, ["TOKEN_IMPLICATION"]],
    [:left, ["TOKEN_OR_OR"]],
    [:left, ["TOKEN_AND_AND"]],
    [:non, %w[TOKEN_EQUAL TOKEN_NOT_EQUAL]],
    [:non, %w[TOKEN_LESS TOKEN_LESS_OR_EQ TOKEN_MORE TOKEN_MORE_OR_EQ]],
    [:right, ["TOKEN_UPDATE"]],
    [:invert, []],
    [:left, %w[TOKEN_ADD TOKEN_SUB]],
    [:left, %w[TOKEN_MUL TOKEN_DIV]],
    [:right, ["TOKEN_CONCAT"]],
    [:hasattr, []]
  ]
end

@doc """
nix_skip: The index of the first token from i that is not white space or a
comment.

    nix_skip([[{kind: "TOKEN_WHITESPACE"}, {kind: nil}]], 0) #=> 1
"""
def nix_skip(t, i)
  run_end(
    t[0],
    count(t[0]),
    i,
    (x) -> x[:kind] == "TOKEN_WHITESPACE" or x[:kind] == "TOKEN_COMMENT"
  )
end

@doc """
nix_peek: The kind of the next token that is not trivia, nil at the end.

    nix_peek([[{kind: nil}]], [0, [], 0, [], 0]) #=> nil
"""
def nix_peek(t, s)
  t[0][nix_skip(t, s[0])][:kind]
end

@doc """
nix_emit: The parser state with one token or node added to the open node.

    nix_emit([0, [], 0, [], 0], {kind: "x"})[2] #=> 1
"""
def nix_emit(s, x)
  [s[0] + 1, cons(x, s[1]), s[2] + 1, s[3], s[4]]
end

@doc """
nix_eat: The state with the white space and comments before the next token
added to the open node.

    nix_eat([[{kind: "TOKEN_WHITESPACE"}, {kind: nil}]], [0, [], 0, [], 0])[0] #=> 1
"""
def nix_eat(t, s)
  reduce((acc, k) -> nix_emit(acc, t[0][k]), s, range(s[0], nix_skip(t, s[0])))
end

@doc """
nix_bump: The state with the next token taken, kind its kind in the tree
(nil keeps it); the end of the input is refused.

    nix_bump([[{kind: "TOKEN_IDENT"}, {kind: nil}]], [0, [], 0, [], 0], nil)[2] #=> 1
"""
def nix_bump(t, s, kind)
  e = nix_eat(t, s)
  tok = t[0][e[0]]
  if tok[:kind].nil?
    nix_malformed("unexpected end of input")
  elsif kind.nil?
    nix_emit(e, tok)
  else
    nix_emit(e, assoc(tok, :kind, kind))
  end
end

@doc """
nix_open: The state with a node of kind opened after the trivia before it.

    nix_open([[{kind: nil}]], [0, [], 0, [], 0], "NODE_X")[3] #=> [["NODE_X", 0]]
"""
def nix_open(t, s, kind)
  e = nix_eat(t, s)
  nix_open_at(e, e[2], kind)
end

@doc """
nix_open_at: The state with a node of kind opened at checkpoint cp, so it
takes the children made since.

    nix_open_at([0, [], 0, [], 0], 0, "NODE_X")[3] #=> [["NODE_X", 0]]
"""
def nix_open_at(s, cp, kind)
  [s[0], s[1], s[2], cons([kind, cp], s[3]), s[4]]
end

@doc """
nix_close: The state with the innermost open node closed over the children
made since it opened.

    nix_close([1, [{start: 0, end: 1}], 1, [["NODE_X", 0]], 0])[1][0][:kind] #=> "NODE_X"
"""
def nix_close(s)
  top = first(s[3])
  k = s[2] - top[1]
  kids = reverse(take(k, s[1]))
  node = {
    kind: top[0],
    start: first(kids)[:start],
    end: last(kids)[:end],
    children: kids
  }
  [s[0], cons(node, drop(k, s[1])), top[1] + 1, rest(s[3]), s[4]]
end

@doc """
nix_mark: The state after the trivia, and the checkpoint a later node may
open at.

    nix_mark([[{kind: nil}]], [0, [], 0, [], 0])[1] #=> 0
"""
def nix_mark(t, s)
  e = nix_eat(t, s)
  [e, e[2]]
end

@doc """
nix_want: The next kind when it is one of allowed; anything else, the end of
the input among them, is refused.

    raised(() -> nix_want([[{kind: nil}]], [0, [], 0, [], 0], ["TOKEN_IDENT"])) #=> :nix_malformed
"""
def nix_want(t, s, allowed)
  k = nix_peek(t, s)
  if not member?(k, allowed)
    nix_malformed(
      concat("wanted one of ", join(allowed, ", "), ", got ", to_s(k))
    )
  end
  k
end

@doc """
nix_expect: The state with the next token taken, refused unless it is kind.

    nix_expect([[{kind: "TOKEN_IDENT"}, {kind: nil}]], [0, [], 0, [], 0], "TOKEN_IDENT")[0] #=> 1
"""
def nix_expect(t, s, kind)
  nix_want(t, s, [kind])
  nix_bump(t, s, nil)
end

@doc """
nix_ident: The state with an identifier taken as NODE_IDENT.

    nix_document("a")[:root][:children][0][:children][0][:text] #=> "a"
"""
def nix_ident(t, s)
  nix_want(t, s, ["TOKEN_IDENT"])
  nix_close(nix_bump(t, nix_open(t, s, "NODE_IDENT"), nil))
end

@doc """
nix_expr: The state with one expression read, as rnix's parse_expr reads it:
let, with, if and assert, else the operator levels; deeper than 512 is refused.

    nix_document("with a; b")[:root][:children][0][:kind] #=> "NODE_WITH"
"""
def nix_expr(t, s)
  depth = s[4]
  if depth >= 512
    nix_malformed("nested too deeply to parse")
  end
  d = [s[0], s[1], s[2], s[3], depth + 1]
  k = nix_peek(t, d)
  out = if k == "TOKEN_LET"
    nix_let(t, d)
  elsif k == "TOKEN_IF"
    nix_if(t, d)
  elsif k == "TOKEN_WITH" or k == "TOKEN_ASSERT"
    nix_scoped(t, d, replace(k, "TOKEN_", "NODE_"))
  else
    nix_level(t, d, 0)[0]
  end
  [out[0], out[1], out[2], out[3], depth]
end

@doc """
nix_if: The state after `if c then a else b`.

    nix_document("if a then b else c")[:root][:children][0][:kind] #=> "NODE_IF_ELSE"
"""
def nix_if(t, s)
  o = nix_bump(t, nix_open(t, s, "NODE_IF_ELSE"), nil)
  o2 = nix_expect(t, nix_expr(t, o), "TOKEN_THEN")
  o3 = nix_expect(t, nix_expr(t, o2), "TOKEN_ELSE")
  nix_close(nix_expr(t, o3))
end

@doc """
nix_scoped: The state after `with e; body` or `assert e; body`, a node of kind.

    nix_document("assert a; b")[:root][:children][0][:kind] #=> "NODE_ASSERT"
"""
def nix_scoped(t, s, kind)
  o = nix_bump(t, nix_open(t, s, kind), nil)
  nix_close(nix_expr(t, nix_expect(t, nix_expr(t, o), "TOKEN_SEMICOLON")))
end

@doc """
nix_let: The state with a let read: `let { … }` (NODE_LEGACY_LET) or
`let … in e` (NODE_LET_IN).

    nix_document("let { a = 1; }")[:root][:children][0][:kind] #=> "NODE_LEGACY_LET"
"""
def nix_let(t, s)
  m = nix_mark(t, s)
  cp = m[1]
  b = nix_bump(t, m[0], nil)
  if nix_peek(t, b) == "TOKEN_L_BRACE"
    o = nix_bump(t, nix_open_at(b, cp, "NODE_LEGACY_LET"), nil)
    nix_close(nix_set(t, o, "TOKEN_R_BRACE"))
  else
    o = nix_set(t, nix_open_at(b, cp, "NODE_LET_IN"), "TOKEN_IN")
    nix_close(nix_expr(t, o))
  end
end

@doc """
nix_level: [state, checkpoint] after the operator level n and every tighter
one is read (nix_levels names them).

    nix_document("a -> b")[:root][:children][0][:kind] #=> "NODE_BIN_OP"
"""
def nix_level(t, s, n)
  level = t[1][n]
  shape = level[0]
  tighter = (t2, s2) -> nix_level(t2, s2, n + 1)
  if shape == :invert
    nix_unary(t, s, "TOKEN_INVERT", tighter)
  elsif shape == :hasattr
    got = nix_unary(t, s, "TOKEN_SUB", nix_apply)
    [nix_has(t, got[0], got[1]), got[1]]
  else
    got = tighter(t, s)
    [nix_binary(t, got[0], got[1], n, level), got[1]]
  end
end

@doc """
nix_binary: The state after the operators of level n that follow the
operand begun at cp: one (:non), many leftward (:left) or nested rightward
(:right).

    nix_document("a // b // c")[:root][:children][0][:children][4][:kind] #=> "NODE_BIN_OP"
"""
def nix_binary(t, s, cp, n, level)
  shape = level[0]
  next_level = if shape == :right
    n
  else
    n + 1
  end
  if member?(nix_peek(t, s), level[1])
    o = nix_bump(t, nix_open_at(s, cp, "NODE_BIN_OP"), nil)
    done = nix_close(nix_level(t, o, next_level)[0])
    if shape == :left
      nix_binary(t, done, cp, n, level)
    else
      done
    end
  else
    s
  end
end

@doc """
nix_unary: [state, checkpoint] after a run of the prefix operator op (- or !)
and what operand reads after it.

    nix_document("!a")[:root][:children][0][:kind] #=> "NODE_UNARY_OP"
"""
def nix_unary(t, s, op, operand)
  if nix_peek(t, s) == op
    m = nix_mark(t, s)
    o = nix_bump(t, nix_open(t, m[0], "NODE_UNARY_OP"), nil)
    [nix_close(nix_unary(t, o, op, operand)[0]), m[1]]
  else
    operand(t, s)
  end
end

@doc """
nix_has: The state after each `? attrpath` that follows the operand at cp.

    nix_document("a ? b")[:root][:children][0][:kind] #=> "NODE_HAS_ATTR"
"""
def nix_has(t, s, cp)
  if nix_peek(t, s) == "TOKEN_QUESTION"
    o = nix_bump(t, nix_open_at(s, cp, "NODE_HAS_ATTR"), nil)
    nix_has(t, nix_close(nix_attrpath(t, o)), cp)
  else
    s
  end
end

@doc """
nix_apply: [state, checkpoint] after a function applied to each argument that
follows it.

    nix_document("f a")[:root][:children][0][:kind] #=> "NODE_APPLY"
"""
def nix_apply(t, s)
  got = nix_simple(t, s)
  [nix_arguments(t, got[0], got[1]), got[1]]
end

@doc """
nix_arguments: The state after the arguments that follow the function at cp,
each wrapping what came before in NODE_APPLY.

    nix_document("f a b")[:root][:children][0][:children][0][:kind] #=> "NODE_APPLY"
"""
def nix_arguments(t, s, cp)
  args = %w[
    TOKEN_REC
    TOKEN_L_BRACE
    TOKEN_L_BRACK
    TOKEN_L_PAREN
    TOKEN_STRING_START
    TOKEN_IDENT
    TOKEN_CUR_POS
    TOKEN_FLOAT
    TOKEN_INTEGER
    TOKEN_PATH_ABS
    TOKEN_PATH_REL
    TOKEN_PATH_HOME
    TOKEN_PATH_SEARCH
    TOKEN_URI
  ]
  if member?(nix_peek(t, s), args)
    o = nix_simple(t, nix_open_at(s, cp, "NODE_APPLY"))[0]
    nix_arguments(t, nix_close(o), cp)
  else
    s
  end
end

@doc """
nix_simple: [state, checkpoint] after one primary expression and the
selection or `or` that follows it.

    nix_document("a.b or c")[:root][:children][0][:kind] #=> "NODE_SELECT"
"""
def nix_simple(t, s)
  k = nix_peek(t, s)
  m = nix_mark(t, s)
  e = m[0]
  paths = %w[TOKEN_PATH_ABS TOKEN_PATH_REL TOKEN_PATH_HOME TOKEN_PATH_SEARCH]
  body = if k == "TOKEN_L_PAREN"
    o = nix_expr(t, nix_bump(t, nix_open(t, e, "NODE_PAREN"), nil))
    nix_close(nix_bump(t, o, nil))
  elsif k == "TOKEN_REC"
    o = nix_bump(t, nix_open(t, e, "NODE_ATTR_SET"), nil)
    nix_close(nix_set(t, nix_expect(t, o, "TOKEN_L_BRACE"), "TOKEN_R_BRACE"))
  elsif k == "TOKEN_L_BRACE"
    nix_brace(t, e)
  elsif k == "TOKEN_L_BRACK"
    o = nix_items(t, nix_bump(t, nix_open(t, e, "NODE_LIST"), nil))
    nix_close(nix_bump(t, o, nil))
  elsif k == "TOKEN_STRING_START"
    nix_string(t, e)
  elsif k == "TOKEN_IDENT"
    nix_name(t, e, m[1])
  elsif member?(k, paths)
    nix_path(t, e, k)
  elsif member?(k, %w[TOKEN_FLOAT TOKEN_INTEGER TOKEN_URI])
    nix_close(nix_bump(t, nix_open(t, e, "NODE_LITERAL"), nil))
  else
    nix_malformed(concat("unexpected ", to_s(k), ", wanted an expression"))
  end
  [nix_select(t, body, m[1]), m[1]]
end

@doc """
nix_select: The state after the `.attrpath` (and `or default`) or the bare
`or` that follows the expression at cp.

    nix_document("a or")[:root][:children][0][:kind] #=> "NODE_APPLY"
"""
def nix_select(t, s, cp)
  k = nix_peek(t, s)
  if k == "TOKEN_DOT"
    o = nix_attrpath(t, nix_bump(t, nix_open_at(s, cp, "NODE_SELECT"), nil))
    if nix_peek(t, o) == "TOKEN_OR"
      nix_close(nix_simple(t, nix_bump(t, o, nil))[0])
    else
      nix_close(o)
    end
  elsif k == "TOKEN_OR"
    o = nix_open(t, nix_open_at(s, cp, "NODE_APPLY"), "NODE_IDENT")
    nix_close(nix_close(nix_bump(t, o, "TOKEN_IDENT")))
  else
    s
  end
end

@doc """
nix_items: The state after a list's items, up to its ].

    nix_document("[ a b ]")[:root][:children][0][:kind] #=> "NODE_LIST"
"""
def nix_items(t, s)
  k = nix_peek(t, s)
  if k != nil and k != "TOKEN_R_BRACK"
    nix_items(t, nix_simple(t, s)[0])
  else
    s
  end
end

@doc """
nix_brace: The state after a {: a lambda's pattern when the two tokens after
it look like one, as rnix looks, else an attribute set.

    nix_document("{ a }: a")[:root][:children][0][:kind] #=> "NODE_LAMBDA"
"""
def nix_brace(t, s)
  j = nix_skip(t, s[0])
  a = nix_skip(t, j + 1)
  b = nix_skip(t, a + 1)
  look = [t[0][a][:kind], t[0][b][:kind]]
  patterns = [
    %w[TOKEN_IDENT TOKEN_COMMA],
    %w[TOKEN_IDENT TOKEN_QUESTION],
    %w[TOKEN_IDENT TOKEN_R_BRACE],
    %w[TOKEN_ELLIPSIS TOKEN_R_BRACE],
    %w[TOKEN_R_BRACE TOKEN_COLON],
    %w[TOKEN_R_BRACE TOKEN_AT]
  ]
  if member?(look, patterns)
    o = nix_open(t, nix_open(t, s, "NODE_LAMBDA"), "NODE_PATTERN")
    p = nix_close(nix_pattern(t, nix_bump(t, o, nil), false))
    nix_close(nix_expr(t, nix_expect(t, p, "TOKEN_COLON")))
  else
    o = nix_bump(t, nix_open(t, s, "NODE_ATTR_SET"), nil)
    nix_close(nix_set(t, o, "TOKEN_R_BRACE"))
  end
end

@doc """
nix_pattern: The state after a pattern's entries and its } (and an `@ name`;
bound says the name came before, so a second one is refused).

    raised(() -> nix_document("a @ { } @ b: a")) #=> :nix_malformed
"""
def nix_pattern(t, s, bound)
  o = if member?(nix_peek(t, s), [nil, "TOKEN_R_BRACE"])
    nix_bump(t, s, nil)
  else
    nix_entries(t, s)
  end
  if nix_peek(t, o) != "TOKEN_AT"
    o
  elsif bound
    nix_malformed("a pattern bound twice")
  else
    b = nix_bump(t, nix_open(t, o, "NODE_PAT_BIND"), nil)
    nix_close(nix_ident(t, b))
  end
end

@doc """
nix_entries: The state after a pattern's entries, each `name` or
`name ? default`, through its } (and a `...`).

    nix_document("{ a ? 1, ... }: a")[:root][:children][0][:kind] #=> "NODE_LAMBDA"
"""
def nix_entries(t, s)
  k = nix_want(t, s, %w[TOKEN_R_BRACE TOKEN_ELLIPSIS TOKEN_IDENT])
  if k == "TOKEN_R_BRACE"
    nix_bump(t, s, nil)
  elsif k == "TOKEN_ELLIPSIS"
    nix_expect(t, nix_bump(t, s, nil), "TOKEN_R_BRACE")
  else
    o = nix_ident(t, nix_open(t, s, "NODE_PAT_ENTRY"))
    d = if nix_peek(t, o) == "TOKEN_QUESTION"
      nix_expr(t, nix_bump(t, o, nil))
    else
      o
    end
    e = nix_close(d)
    if nix_peek(t, e) == "TOKEN_COMMA"
      nix_entries(t, nix_bump(t, e, nil))
    else
      nix_expect(t, e, "TOKEN_R_BRACE")
    end
  end
end

@doc """
nix_set: The state after a set's entries (`path = e;` and `inherit …;`) and
the until token that closes them.

    nix_document("{ inherit a; }")[:root][:children][0][:children][2][:kind] #=> "NODE_INHERIT"
"""
def nix_set(t, s, until)
  k = nix_peek(t, s)
  if k.nil? or k == until
    nix_bump(t, s, nil)
  else
    nix_set(t, nix_binding(t, s, k), until)
  end
end

@doc """
nix_binding: The state after one entry of a set, whose first token is of
kind k: `inherit …;` or `path = e;`.

    nix_document("{ a = 1; }")[:root][:children][0][:children][2][:kind] #=> "NODE_ATTRPATH_VALUE"
"""
def nix_binding(t, s, k)
  if k == "TOKEN_INHERIT"
    nix_inherit(t, s)
  else
    o = nix_attrpath(t, nix_open(t, s, "NODE_ATTRPATH_VALUE"))
    v = nix_expr(t, nix_expect(t, o, "TOKEN_ASSIGN"))
    nix_close(nix_expect(t, v, "TOKEN_SEMICOLON"))
  end
end

@doc """
nix_inherit: The state after `inherit (from) names;`.

    nix_document("{ inherit (a) b; }")[:root][:children][0][:children][2][:children][2][:kind] #=> "NODE_INHERIT_FROM"
"""
def nix_inherit(t, s)
  o = nix_bump(t, nix_open(t, s, "NODE_INHERIT"), nil)
  from = if nix_peek(t, o) == "TOKEN_L_PAREN"
    f = nix_expr(t, nix_bump(t, nix_open(t, o, "NODE_INHERIT_FROM"), nil))
    nix_close(nix_expect(t, f, "TOKEN_R_PAREN"))
  else
    o
  end
  nix_close(nix_expect(t, nix_inherited(t, from), "TOKEN_SEMICOLON"))
end

@doc """
nix_inherited: The state after the names an inherit takes, up to its ;.

    nix_document("{ inherit a \"b\"; }")[:root][:children][0][:kind] #=> "NODE_ATTR_SET"
"""
def nix_inherited(t, s)
  k = nix_peek(t, s)
  if k != nil and k != "TOKEN_SEMICOLON"
    nix_inherited(t, nix_attr(t, s))
  else
    s
  end
end

@doc """
nix_attrpath: The state after an attribute path, its parts joined by dots.

    nix_document("{ a.b = 1; }")[:root][:children][0][:children][2][:children][0][:kind] #=> "NODE_ATTRPATH"
"""
def nix_attrpath(t, s)
  nix_close(nix_attrs(t, nix_open(t, s, "NODE_ATTRPATH")))
end

@doc """
nix_attrs: The state after one attribute and every `.attribute` after it.

    nix_document("a.b.c")[:root][:children][0][:children][2][:kind] #=> "NODE_ATTRPATH"
"""
def nix_attrs(t, s)
  o = nix_attr(t, s)
  if nix_peek(t, o) == "TOKEN_DOT"
    nix_attrs(t, nix_bump(t, o, nil))
  else
    o
  end
end

@doc """
nix_attr: The state after one attribute: an interpolation (NODE_DYNAMIC), a
string, or a name (`or` read as a name).

    nix_document("a.or")[:root][:children][0][:kind] #=> "NODE_SELECT"
"""
def nix_attr(t, s)
  k = nix_peek(t, s)
  if k == "TOKEN_INTERPOL_START"
    o = nix_bump(t, nix_open(t, s, "NODE_DYNAMIC"), nil)
    nix_close(nix_bump(t, nix_interpolated(t, o), nil))
  elsif k == "TOKEN_STRING_START"
    nix_string(t, s)
  else
    nix_want(t, s, %w[TOKEN_IDENT TOKEN_OR TOKEN_CUR_POS])
    nix_close(nix_bump(t, nix_open(t, s, "NODE_IDENT"), "TOKEN_IDENT"))
  end
end

@doc """
nix_interpolated: The state after the expressions of a dynamic attribute, up
to its }.

    nix_document("a.${b}")[:root][:children][0][:kind] #=> "NODE_SELECT"
"""
def nix_interpolated(t, s)
  k = nix_peek(t, s)
  if k != nil and k != "TOKEN_INTERPOL_END"
    nix_interpolated(t, nix_expr(t, s))
  else
    s
  end
end

@doc """
nix_string: The state after a string: its contents and interpolations.

    nix_document("\"a\"")[:root][:children][0][:kind] #=> "NODE_STRING"
"""
def nix_string(t, s)
  o = nix_expect(t, nix_open(t, s, "NODE_STRING"), "TOKEN_STRING_START")
  nix_close(nix_expect(t, nix_parts(t, o), "TOKEN_STRING_END"))
end

@doc """
nix_parts: The state after a string's contents and interpolations, up to its
end.

    nix_document("''a''")[:root][:children][0][:children][1][:kind] #=> "TOKEN_STRING_CONTENT"
"""
def nix_parts(t, s)
  k = nix_want(
    t,
    s,
    %w[TOKEN_STRING_END TOKEN_STRING_CONTENT TOKEN_INTERPOL_START]
  )
  if k == "TOKEN_STRING_END"
    s
  else
    nix_parts(t, nix_piece(t, s, k))
  end
end

@doc """
nix_piece: The state after one piece of a string or path whose kind is k: an
interpolation, or the token taken as it is.

    nix_piece([[{kind: "TOKEN_STRING_CONTENT"}, {kind: nil}]], [0, [], 0, [], 0], "TOKEN_STRING_CONTENT")[2] #=> 1
"""
def nix_piece(t, s, k)
  if k == "TOKEN_INTERPOL_START"
    nix_interpol(t, s)
  else
    nix_bump(t, s, nil)
  end
end

@doc """
nix_interpol: The state after an interpolation, `${` e `}` (NODE_INTERPOL).

    nix_document("\"${a}\"")[:root][:children][0][:children][1][:kind] #=> "NODE_INTERPOL"
"""
def nix_interpol(t, s)
  o = nix_expr(t, nix_bump(t, nix_open(t, s, "NODE_INTERPOL"), nil))
  nix_close(nix_expect(t, o, "TOKEN_INTERPOL_END"))
end

@doc """
nix_path: The state after a path of token kind k, with the interpolations and
pieces of a path that interpolates (a search path never does).

    nix_document("./a/${b}")[:root][:children][0][:kind] #=> "NODE_PATH_REL"
"""
def nix_path(t, s, k)
  o = nix_bump(t, nix_open(t, s, replace(k, "TOKEN_", "NODE_")), nil)
  if k != "TOKEN_PATH_SEARCH" and nix_peek(t, o) == "TOKEN_INTERPOL_START"
    nix_close(nix_path_parts(t, nix_interpol(t, o)))
  else
    nix_close(o)
  end
end

@doc """
nix_path_parts: The state after the pieces and interpolations that follow an
interpolating path with nothing between them.

    nix_document("/${a}/b${c}")[:root][:children][0][:children][3][:kind] #=> "NODE_INTERPOL"
"""
def nix_path_parts(t, s)
  k = t[0][s[0]][:kind]
  pieces = %w[
    TOKEN_PATH_ABS
    TOKEN_PATH_REL
    TOKEN_PATH_HOME
    TOKEN_INTERPOL_START
  ]
  if member?(k, pieces)
    nix_path_parts(t, nix_piece(t, s, k))
  else
    s
  end
end

@doc """
nix_name: The state after an identifier at cp: a lambda's parameter
(`x: e`), its bound pattern (`x @ { … }: e`), __curPos, or a name.

    nix_document("x: x")[:root][:children][0][:children][0][:kind] #=> "NODE_IDENT_PARAM"
"""
def nix_name(t, s, cp)
  ahead = t[0][nix_skip(t, nix_skip(t, s[0]) + 1)][:kind]
  if ahead == "TOKEN_COLON"
    l = nix_open_at(nix_ident(t, s), cp, "NODE_LAMBDA")
    p = nix_close(nix_open_at(l, cp, "NODE_IDENT_PARAM"))
    nix_close(nix_expr(t, nix_expect(t, p, "TOKEN_COLON")))
  elsif ahead == "TOKEN_AT"
    l = nix_open_at(nix_ident(t, s), cp, "NODE_LAMBDA")
    b = nix_open_at(nix_open_at(l, cp, "NODE_PATTERN"), cp, "NODE_PAT_BIND")
    p = nix_close(nix_expect(t, b, "TOKEN_AT"))
    q = nix_close(nix_pattern(t, nix_expect(t, p, "TOKEN_L_BRACE"), true))
    nix_close(nix_expr(t, nix_expect(t, q, "TOKEN_COLON")))
  elsif t[0][s[0]][:text] == "__curPos"
    nix_close(nix_bump(t, nix_open(t, s, "NODE_CUR_POS"), "TOKEN_CUR_POS"))
  else
    nix_ident(t, s)
  end
end

volatile(nix_text)
volatile(nix_string_stop)
volatile(nix_string_end)
volatile(nix_path_check)
volatile(nix_plain)
volatile(nix_skip)
volatile(nix_emit)
volatile(nix_close)
volatile(nix_open_at)
volatile(nix_shape_rest)
volatile(nix_exponent)
volatile(nix_search_path)
volatile(nix_block_comment)

test "nix_document gives nix_parse's tree for every construct", {kind: :unit}
  samples = [
    "{ a = 1; }",
    "x",
    unlines(["# c", "{ a.b = 1; /* x */ c = \"é ${d}\"; }"]),
    concat("a", code_point_text(160), "b"),
    "/**/x /* a * b */",
    "a/*c*/b",
    "{ ... }: 1",
    "{ a, b ? 1, ... }: a",
    "{ a, }: a",
    "{ }: 1",
    "{}@a: a",
    "{ a }@b: a",
    "a@{ b }: b",
    "a @ { }: a",
    "x: y: x",
    "/a/b",
    "/${a}/b",
    "./a/${b}c${d}",
    "./a${b}${c}",
    "./a ${b}",
    "~/a/b",
    "<nixpkgs/lib>",
    "a <<b>",
    "a/b",
    "1/2",
    "a // b // c",
    "https://e.org/a?b=c&d=%20",
    "a_b:c",
    "[ 0 01 01.5 0.5 1.5e3 1.5e-3 1.5E+3 .5 1. 1.e5 ]",
    "a == b",
    "a != b",
    "a ++ b ++ c",
    "a -> b -> c",
    "f <| g <| a",
    "a |> f |> g",
    "a && b && c",
    "a || b",
    "a <= b",
    "a >= b",
    "a < b",
    "a > b",
    "a + b - c",
    "a * b / c",
    "!!a",
    "--a",
    "-a.b",
    "a ? b.c ? d",
    "a.b or c",
    "a.b.c or d e",
    "a or",
    "f a or b",
    "a.or",
    "a.${b}.\"c\"",
    "\"${ { a = 1; }.a }\"",
    "\"a\\\"b\\\\\"",
    "\"$$ { $\"",
    "\"a${b}c${d}\"",
    "\"\"",
    "''a ''' b ''$ c ''\\n d $$ ' e''",
    "''${a}''",
    "''''",
    "let a = 1; b = a; in a + b",
    "let { a = 1; body = a; }",
    "with a; b",
    "assert a; b",
    "if a then b else c",
    "{ }",
    "rec { a = 1; }",
    "{ inherit a b; inherit (c) d \"e\"; inherit ${f}; }",
    "{ a.b.c = 1; \"x\" = 2; ${y} = 3; }",
    "[ ]",
    "[ 1 [ 2 ] (3) ]",
    "(a)",
    "__curPos",
    "f a b c",
    "f { a = 1; } [ 2 ] (3) \"s\" ./p <q> 1.5 x",
    "(a ~)",
    "(1]",
    "a: { b }: c @ { }: d"
  ]
  assert filter((t) -> nix_document(t) != nix_parse(t), samples) == []
  assert parse("x: x", :nix) == nix_parse("x: x")
end

test "nix_document refuses what nix_parse finds errors in", {kind: :unit}
  bad = [
    "{ a = ; }",
    "",
    "   ",
    "/* a",
    "a/",
    "./a//b",
    "~",
    "~x",
    "<a<b>",
    "1.5e",
    "a & b",
    "a | b",
    "$a",
    "'a",
    "\"abc",
    "\"a\\",
    "''abc",
    "''a''\\",
    "a; b",
    "a )",
    "{ a = 1 }",
    "a @ { } @ b: a",
    "a@{",
    "{ a, b",
    "{ a b }: a",
    "{ inherit a",
    "{ inherit (a b; }",
    "a.${b",
    "a.${b c",
    "[ 1",
    "(a",
    "f (",
    "\"${a\"",
    "{ a.1 = 2; }",
    "a.",
    "let a = 1;",
    "if a then b",
    "x:",
    "a + ",
    "a == b == c",
    "\"a\" \"",
    "./${a",
    "{ ... b }: a",
    "{ a ? }: a"
  ]
  assert filter((t) -> nix_parse(t)[:errors] == [], bad) == []
  assert filter((t) -> raised(() -> nix_document(t)) != :nix_malformed, bad) ==
    []
  deep = concat(join(map((_i) -> "(", range(0, 520)), ""), "a")
  assert raised(() -> nix_document(deep)) == :nix_malformed
  assert nix_parse(deep)[:errors] != []
end

test "each step of the Nix reader does its own part", {kind: :unit}
  cs = chars("a")
  assert nix_text(cs, 0, 1) == "a"
  assert nix_space?(" ") and nix_space?(code_point_text(8287))
  assert not nix_space?("x") and not nix_space?(code_point_text(233))
  assert not nix_class?(:path, nil) and not nix_class?(:path, "@")
  assert nix_uri_char?("~") and not nix_uri_char?(nil)
  assert not nix_class?(:ident, nil) and not nix_class?(:ident, ".")
  assert not nix_class?(:digit, nil) and not nix_class?(:digit, "a")
  assert nix_tokens(chars(""), 0, 0, [[:plain]], []) == []
  assert nix_bracket([[:plain]], 1) == [[:plain]]
  assert nix_path_ctx([], "REL") == [[:path, "TOKEN_PATH_REL"]]
  assert nix_pairs["->"] == "TOKEN_IMPLICATION"
  assert nix_singles["/"] == "TOKEN_DIV"
  assert nix_shape(chars("//"), 2, 0).nil?
  assert nix_shape(chars("~/a"), 3, 0) == :home
  assert nix_shape(chars("a/ "), 3, 0).nil?
  assert nix_string_skip(chars("x"), 1, 0, false) == 1
  assert nix_string_stop(chars("a"), 0, true, [[:body, true]]).nil?
  assert raised(() -> nix_malformed("no")) == :nix_malformed
  assert nix_levels[12] == [:hasattr, []]
  s = [0, [], 0, [], 0]
  t = [
    [{kind: "TOKEN_COMMENT", start: 0, end: 1}, {kind: nil}, {kind: nil}],
    []
  ]
  assert nix_skip(t, 0) == 1
  assert nix_peek(t, s).nil?
  assert nix_eat(t, s)[2] == 1
  assert raised(() -> nix_bump(t, s, nil)) == :nix_malformed
  assert nix_mark(t, s)[1] == 1
  assert nix_open(t, s, "NODE_X")[3] == [["NODE_X", 1]]
  assert nix_open_at(s, 0, "NODE_Y")[3] == [["NODE_Y", 0]]
  assert nix_emit(s, {kind: "x"})[1] == [{kind: "x"}]
  assert nix_close(nix_eat(t, nix_open_at(s, 0, "NODE_X")))[1][0][:end] == 1
end

test "each step of the Nix tokenizer cuts its own token", {kind: :unit}
  ctx = [[:plain]]
  assert nix_next(chars("a"), 1, 0, ctx)[0] == "TOKEN_IDENT"
  assert nix_path_more(chars(" "), 1, 0, [[:path, "X"], [:plain]], "X")[0] ==
    "TOKEN_WHITESPACE"
  assert nix_path_check(chars("a//b"), 4, 0, 0, "K", ctx)[0] == "TOKEN_ERROR"
  assert nix_lex_string(chars("a${"), 3, 0, false, ctx)[1] == 1
  assert nix_string_end(chars("\""), 0, ctx)[1] == 1
  assert nix_plain(chars("..."), 3, 0, ctx)[0] == "TOKEN_ELLIPSIS"
  assert nix_block_comment(chars("*"), 1, 0, ctx)[0] == "TOKEN_ERROR"
  assert nix_shape_rest(chars("a/b"), 3, 0, false) == :rel
  assert nix_symbol(chars("=="), 2, 0, ctx, nil)[0] == "TOKEN_EQUAL"
  assert nix_symbol_rest(chars("&"), 1, 0, ctx, nil)[0] == "TOKEN_ERROR"
  assert nix_search_path(chars("<<"), 2, 0, ctx)[0] == "TOKEN_LESS"
  assert nix_word(chars("a:b"), 3, 0, ctx, true)[0] == "TOKEN_URI"
  assert nix_number(chars("01."), 3, 0, ctx)[1] == 2
  assert nix_exponent(chars("1.e"), 3, 2, ctx)[0] == "TOKEN_ERROR"
end

test "each step of the Nix parser reads its own construct", {kind: :unit}
  t = fn(src)
    cs = chars(src)
    n = count(cs)
    ends = [{kind: nil, start: n, end: n}, {kind: nil, start: n, end: n}]
    [append(nix_tokens(cs, n, 0, [[:plain]], []), ends), nix_levels]
  end
  s = [0, [], 0, [["NODE_ROOT", 0]], 0]
  top = (st) -> st[1][0][:kind]
  assert nix_want(t("a"), s, ["TOKEN_IDENT"]) == "TOKEN_IDENT"
  assert nix_expect(t(";"), s, "TOKEN_SEMICOLON")[0] == 1
  assert top(nix_ident(t("a"), s)) == "NODE_IDENT"
  assert top(nix_expr(t("a"), s)) == "NODE_IDENT"
  assert top(nix_if(t("if a then b else c"), s)) == "NODE_IF_ELSE"
  assert top(nix_scoped(t("with a; b"), s, "NODE_WITH")) == "NODE_WITH"
  assert top(nix_let(t("let in a"), s)) == "NODE_LET_IN"
  assert top(nix_level(t("a || b"), s, 3)[0]) == "NODE_BIN_OP"
  assert top(nix_binary(t("+ b"), nix_ident(t("a"), s), 0, 9, nix_levels[9])) ==
    "NODE_IDENT"
  assert top(nix_unary(t("-a"), s, "TOKEN_SUB", nix_apply)[0]) ==
    "NODE_UNARY_OP"
  assert nix_has(t("a"), s, 0) == s
  assert top(nix_apply(t("f x"), s)[0]) == "NODE_APPLY"
  assert nix_arguments(t(";"), s, 0) == s
  assert top(nix_simple(t("[ ]"), s)[0]) == "NODE_LIST"
  assert nix_select(t(";"), s, 0) == s
  assert nix_items(t("]"), s) == s
  assert top(nix_brace(t("{ a = 1; }"), s)) == "NODE_ATTR_SET"
  assert nix_pattern(t("}"), s, false)[0] == 1
  assert nix_entries(t("... }"), s)[0] == 3
  assert nix_set(t("}"), s, "TOKEN_R_BRACE")[0] == 1
  assert top(nix_binding(t("inherit a;"), s, "TOKEN_INHERIT")) == "NODE_INHERIT"
  assert top(nix_inherit(t("inherit (a) b;"), s)) == "NODE_INHERIT"
  assert nix_inherited(t(";"), s) == s
  assert top(nix_attrpath(t("a.b"), s)) == "NODE_ATTRPATH"
  assert nix_attrs(t("a.b"), s)[0] == 3
  assert top(nix_attr(t("or"), s)) == "NODE_IDENT"
  assert top(nix_interpolated(t("a"), s)) == "NODE_IDENT"
  assert top(nix_string(t("\"a\""), s)) == "NODE_STRING"
  assert nix_parts(t("\"\""), [1, [], 0, s[3], 0])[0] == 1
  assert top(nix_piece(t("${a}"), s, "TOKEN_INTERPOL_START")) == "NODE_INTERPOL"
  assert top(nix_interpol(t("${a}"), s)) == "NODE_INTERPOL"
  assert top(nix_path(t("<a>"), s, "TOKEN_PATH_SEARCH")) == "NODE_PATH_SEARCH"
  assert nix_path_parts(t(" "), s) == s
  assert top(nix_name(t("__curPos"), s, 0)) == "NODE_CUR_POS"
end

test "xml_document gives the element map xml_parse gives", {kind: :unit}
  samples = [
    "<r a=\"1 &amp; 2\"><c>x &lt; y</c><c/></r>",
    unlines(
      [
        "<?xml version=\"1.0\"?>",
        "<!-- c --><r>",
        "  <a x='1' y=\"2\">t</a>",
        "  <b/>",
        "</r>"
      ]
    ),
    "<r>a<![CDATA[<b>]]>c&#65;&#x42;</r>",
    "<!DOCTYPE r><r b=\"&quot;\" a=\"&lt;\">t &amp; u<c/></r>",
    "<r> <a/> &amp; <b/> </r>",
    "<ns:r xmlns:ns=\"u\"><ns:c/></ns:r>"
  ]
  assert filter((t) -> xml_document(t) != xml_parse(t), samples) == []
  assert parse("<r/>", :xml)[:name] == "r"
end

test "xml_document refuses what xml_parse refuses, with its kind", {kind: :unit}
  bad = ["<a><b></a>", "<a>", "", "<a/><b/>", "x<a/>", "<a b=1/>", "<a>&q;</a>"]
  kinds = map((t) -> raised(() -> xml_document(t)), bad)
  assert kinds == map((t) -> raised(() -> xml_parse(t)), bad)
  assert raised(
    fn()
      xml_document("<!DOCTYPE r [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><r>&x;</r>")
    end
  ) == :xml_refused
end

test "each step of the XML reader does its own part", {kind: :unit}
  b = text_bytes("<r/>")
  assert text_of(b, 1, 2) == "r"
  assert run_end(b, 4, 0, (c) -> c == 60) == 1
  assert not bytes_at?(b, 4, 3, "/>")
  assert find_bytes(b, 4, 0, "!").nil?
  assert raised(() -> xml_malformed("no")) == :xml_malformed
  assert not space_byte?(65)
  assert xml_close(["r", {}, [{name: "c"}], [" ", "t"]])[:text] == "t"
  assert xml_attach([["p", {}, [], []]], {name: "c"}, nil)[0][0][2] ==
    [{name: "c"}]
  assert raised(() -> xml_add_text([], "t", "text")) == :xml_malformed
  assert xml_step(b, 4, 0, [], nil)[:children] == []
  assert xml_text_runs(b, 0, 0, []) == []
  assert xml_reference("amp") == "&"
  assert xml_markup(b, 4, 0, [], nil)[:name] == "r"
  assert raised(() -> xml_doctype(b, 4, 0, [], {name: "r"})) == :xml_malformed
  assert xml_name_end(b, 4, 1) == 2
  assert raised(() -> xml_end_tag(text_bytes("</r>"), 4, 0, [], nil)) ==
    :xml_malformed
  assert xml_start_tag(b, 4, 0, [], nil)[:name] == "r"
  assert xml_attributes(text_bytes("/>"), 2, 0, {}) == [{}, 2, true]
  assert xml_unescape(text_bytes("&#33;"), 0, 5) == "!"
end

test "xml_document refuses each malformed shape with its own tag", {kind: :unit}
  malformed = [
    "<r>a&amp</r>",
    "<r>&#;</r>",
    "<r>&#xZZ;</r>",
    "<r><!--a",
    "<r><!--a--b--></r>",
    "<r><![CDATA[x",
    "<r><?pi",
    "<r/><!DOCTYPE r>",
    "<!DOCTYPE r [x",
    "<r></r",
    "</r>",
    "<r></s>",
    "<r/><s/>",
    "<>",
    "<r ",
    "<r a>",
    "<r a=1/>",
    "<r a='1/>",
    "<r a='1' a='2'/>"
  ]
  assert filter(
    (t) -> raised(() -> xml_document(t)) != :xml_malformed,
    malformed
  ) == []
  assert raised(() -> xml_document("<r>&foo;</r>")) == :xml_refused
  assert raised(() -> xml_document("<!DOCTYPE r [<!ENTITY e 'x'>]><r/>")) ==
    :xml_refused
  assert xml_document("<?xml version='1.0'?><!DOCTYPE r [ ]><r/>")[:name] == "r"
end
