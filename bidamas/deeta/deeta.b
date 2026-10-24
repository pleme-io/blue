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

@doc """
is_doc: true when `v` is a JSON object read for its fields.

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
as_json: the raw value at `key`, or nil when there is none to give.

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
get_str: the string at `key`, or `default` when the field is not a string.

Missing, null, wrong type, and a non-document all answer the default — the
accessor is total, which is its whole reason to exist. `json_get_or` is NOT
enough for this (see the header): its default is bypassed by a present null,
so the value's type is checked here instead.

    get_str("not a doc", "k", "d") #=> "d"
"""
def get_str(doc, key, default)
  v = as_json(doc, key)
  if string?(v)
    v
  else
    default
  end
end

@doc """
get_int: the integer at `key`, or `default` when the field is not an integer.

A float is not an integer and answers the default; `get_number` is the form
that accepts both.

    get_int(nil, "k", 7) #=> 7
"""
def get_int(doc, key, default)
  v = as_json(doc, key)
  if integer?(v)
    v
  else
    default
  end
end

@doc """
get_number: the number at `key` — integer or float — or `default` when the field is not
a number.

    get_number(42, "k", 0) #=> 0
"""
def get_number(doc, key, default)
  v = as_json(doc, key)
  if number?(v)
    v
  else
    default
  end
end

@doc """
get_or: the value of a blue Map (`{max_iter: 3}`) at `key`, or `default` when the
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
json_at: the value at a dotted path, `json_at(doc, "spec.items.0.name")`, or nil when any step is absent.

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
    nth(index, v)
  elsif map?(v)
    get(v, key)
  else
    json_get(v, key) rescue nil
  end
end

def is_doc_pair?(x)
  list?(x) and count(x) == 2 and string?(first(x))
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
  assert json_get_or(doc, "a", 42).nil?
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
    not member?(
      k,
      ["true", "false", "null", "yes", "no", "on", "off", "y", "n"]
    )
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
        ",\n"
      )
      "{\n#{body}\n#{pad}}"
    end
  elsif collection?(v)
    if v == []
      "[]"
    else
      body = join(map((x) -> "#{inner}#{pretty_at(x, inner)}", v), ",\n")
      "[\n#{body}\n#{pad}]"
    end
  else
    scalar_text(v)
  end
end

def pretty(v)
  "#{pretty_at(v, "")}\n"
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
    "#{join(yaml_lines(v, ""), "\n")}\n"
  else
    "#{yaml_inline(v)}\n"
  end
end

test "pretty prints maps sorted, lists in order, scalars as JSON"
  assert pretty({}) == "{}\n"
  assert pretty([]) == "[]\n"
  assert pretty(nil) == "null\n"
  assert pretty({"b" => [1, true], "a" => "x\"y"}) ==
    "{\n  \"a\": \"x\\\"y\",\n  \"b\": [\n    1,\n    true\n  ]\n}\n"
  assert json_read(pretty({"k" => {"n" => 1.5, "z" => nil}})) ==
    {"k" => {"n" => 1.5, "z" => nil}}
end

test "yaml writes block maps and lists, quoting every string"
  assert yaml({}) == "{}\n"
  assert yaml([]) == "[]\n"
  assert yaml("a") == "\"a\"\n"
  assert yaml({"a" => 1, "b" => {"c" => "d"}}) == "a: 1\nb:\n  c: \"d\"\n"
  assert yaml({"l" => [1, {"x" => true, "z" => []}], "e" => {}}) ==
    "e: {}\nl:\n  - 1\n  - x: true\n    z: []\n"
  assert yaml({"has space" => nil, "true" => false}) ==
    "\"has space\": null\n\"true\": false\n"
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
  elsif format == :yaml
    one_or_all(yaml_documents(text), get(options, :documents))
  else
    raise(:bad_option, "parse reads :json and :yaml, not #{to_s(format)}")
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
  t = replace(replace(text, "\r\n", "\n"), "\r", "\n")
  u = if starts_with?(t, "\u{feff}")
    join(drop(1, chars(t)), "")
  else
    t
  end
  ls = split(u, "\n")
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
  row = nth(r, get(y, :rows))
  if row.nil?
    nil
  elsif c >= count(row)
    "\n"
  else
    nth(c, row)
  end
end

def blank_char?(ch)
  ch == " " or ch == "\t"
end

def line_end?(ch)
  ch.nil? or ch == "\n"
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
    [get(y, :nr), 0]
  elsif ch == "\n" or comment_at?(y, r, k)
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
  if r >= get(y, :nr)
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
  join(take(b - a, drop(a, nth(r, get(y, :rows)))), "")
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
    elsif get(props, :anchor) != nil
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
    if get(props, :tag) != nil
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
    prefix = get(get(y, :handles), handle)
    if prefix.nil?
      yaml_fail(r, c, "the tag handle #{handle} is not declared")
    end
    "#{prefix}#{join(drop(count(chars(handle)), cs), "")}"
  end
end

def merged_properties(r, c, a, b)
  if get(a, :anchor) != nil and get(b, :anchor) != nil or
      get(a, :tag) != nil and get(b, :tag) != nil
    yaml_fail(r, c, "a node takes one anchor and one tag")
  end
  {
    anchor: if get(b, :anchor).nil?
      get(a, :anchor)
    else
      get(b, :anchor)
    end,
    tag: if get(b, :tag).nil?
      get(a, :tag)
    else
      get(b, :tag)
    end
  }
end

def bare?(props)
  get(props, :anchor).nil? and get(props, :tag).nil?
end

def scalar_node(text, plain, props)
  {
    kind: :scalar,
    text:,
    plain:,
    tag: get(props, :tag),
    anchor: get(props, :anchor)
  }
end

def with_properties(node, props)
  assoc(assoc(node, :tag, get(props, :tag)), :anchor, get(props, :anchor))
end

def block_indicator?(y, r, c, ch)
  at_char(y, r, c) == ch and separator?(at_char(y, r, c + 1))
end

def block_node(y, r, c, n, ctx, outer)
  c1 = skip_blanks(y, r, c)
  p = node_properties(y, r, c1, {})
  line = get(p, :props)
  c2 = get(p, :c)
  ch = at_char(y, r, c2)
  collection_here = member?(ctx, [:fresh, :fresh_map, :seq, :explicit])
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
    {
      node: get(v, :node),
      r: get(v, :r),
      c: rest_of_line(y, get(v, :r), get(v, :c))
    }
  end
end

def later_node(y, r, c, n, ctx, props)
  at = next_content(y, r, c)
  r2 = first(at)
  c2 = second(at)
  m = content_level(y, r2, c2)
  beside = member?(ctx, [:map, :fresh_map, :explicit])
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
    node: with_properties({kind: :seq, items: get(s, :items)}, props),
    r: get(s, :r),
    c: get(s, :c)
  }
end

def sequence_items(y, r, m, items)
  item = block_node(y, r, m + 1, m, :seq, {})
  all = append(items, [get(item, :node)])
  at = next_content(y, get(item, :r), get(item, :c))
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
    node: with_properties({kind: :map, pairs: get(s, :pairs)}, props),
    r: get(s, :r),
    c: get(s, :c)
  }
end

def mapping_entries(y, r, m, pairs)
  e = mapping_entry(y, r, m)
  all = append(pairs, [get(e, :pair)])
  at = next_content(y, get(e, :r), get(e, :c))
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
    at = next_content(y, get(k, :r), get(k, :c))
    r2 = first(at)
    c2 = second(at)
    if content_level(y, r2, c2) == m and block_indicator?(y, r2, c2, ":")
      v = block_node(y, r2, m + 1, m, :explicit, {})
      {pair: [get(k, :node), get(v, :node)], r: get(v, :r), c: get(v, :c)}
    else
      {
        pair: [get(k, :node), scalar_node("", true, {})],
        r: get(k, :r),
        c: get(k, :c)
      }
    end
  else
    p = node_properties(y, r, m, {})
    kc = get(p, :c)
    k = if block_indicator?(y, r, kc, ":")
      {node: scalar_node("", true, get(p, :props)), r:, c: kc}
    else
      inline_node(y, r, kc, m, m, get(p, :props), true)
    end
    if get(k, :r) != r
      yaml_fail(r, kc, "a mapping key must sit on one line")
    end
    c3 = skip_blanks(y, r, get(k, :c))
    if block_indicator?(y, r, c3, ":")
      v = block_node(y, r, c3 + 1, m, :map, {})
      {pair: [get(k, :node), get(v, :node)], r: get(v, :r), c: get(v, :c)}
    else
      yaml_fail(r, c3, "a mapping key needs \":\" after it")
    end
  end
end

def implicit_key?(y, r, c)
  k = inline_node(y, r, c, -1, -1, {}, true)
  get(k, :r) == r and block_indicator?(y, r, skip_blanks(y, r, get(k, :c)), ":")
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
    {
      node: scalar_node(get(q, :text), false, props),
      r: get(q, :r),
      c: get(q, :c)
    }
  elsif ch == "[" or ch == "{"
    f = flow_collection(y, r, c, n)
    {node: with_properties(get(f, :node), props), r: get(f, :r), c: get(f, :c)}
  elsif plain_start?(y, r, c, false)
    e = plain_end(y, r, c, false)
    p = if single
      {text: row_slice(y, r, c, e), r:, c: e}
    else
      plain_continued(y, r, e, n, false, row_slice(y, r, c, e))
    end
    {
      node: scalar_node(get(p, :text), true, props),
      r: get(p, :r),
      c: get(p, :c)
    }
  else
    yaml_fail(r, c, "#{json_stringify(to_s(ch))} cannot start a value")
  end
end

def plain_start?(y, r, c, flow)
  ch = at_char(y, r, c)
  nx = at_char(y, r, c + 1)
  if separator?(ch)
    false
  elsif member?(ch, ["-", "?", ":"])
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
  join(map((_) -> "\n", range(k)), "")
end

def next_text_line(y, r, empties)
  if r >= get(y, :nr)
    {r:, c: 0, empties:}
  else
    k = skip_blanks(y, r, 0)
    if at_char(y, r, k) == "\n"
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
    r2 = get(nl, :r)
    c2 = get(nl, :c)
    if r2 >= get(y, :nr) or
        content_level(y, r2, c2) < 0 or
        leading_spaces(y, r2, 0) <= n or
        comment_at?(y, r2, c2)
      done
    else
      e2 = plain_end(y, r2, c2, flow)
      if e2 == c2
        done
      else
        joint = if get(nl, :empties) == 0
          " "
        else
          line_breaks(get(nl, :empties))
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
  inside = get(nl, :r) < get(y, :nr)
  if inside and get(nl, :c) == 0 and content_level(y, get(nl, :r), 0) < 0
    yaml_fail(
      get(nl, :r),
      0,
      "a document marker cannot sit inside a quoted scalar"
    )
  elsif inside and qn >= 0 and leading_spaces(y, get(nl, :r), 0) <= qn
    yaml_fail(
      get(nl, :r),
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
    if at_char(y, r, c + 1) == "\n"
      nl = quoted_break(y, r + 1, qn)
      quoted_run(
        y,
        get(nl, :r),
        get(nl, :c),
        "#{out}#{ws}#{line_breaks(get(nl, :empties))}",
        "",
        double,
        qn
      )
    else
      x = escape_at(y, r, c + 1)
      quoted_run(
        y,
        r,
        get(x, :c),
        "#{out}#{ws}#{get(x, :text)}",
        "",
        double,
        qn
      )
    end
  elsif blank_char?(ch)
    quoted_run(y, r, c + 1, out, "#{ws}#{ch}", double, qn)
  elsif ch == "\n"
    nl = quoted_break(y, r + 1, qn)
    joint = if get(nl, :empties) == 0
      " "
    else
      line_breaks(get(nl, :empties))
    end
    quoted_run(y, get(nl, :r), get(nl, :c), "#{out}#{joint}", "", double, qn)
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
    "n" => "\n",
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
  if r2 >= get(y, :nr)
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
    all = append(items, [get(e, :node)])
    after = flow_space(y, get(e, :r), get(e, :c), n)
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
  get(node, :kind) == :seq or
    get(node, :kind) == :map or
    get(node, :kind) == :scalar and not get(node, :plain)
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
  at = flow_space(y, get(k, :r), get(k, :c), n)
  r2 = first(at)
  c2 = second(at)
  nx = at_char(y, r2, c2 + 1)
  same_line = explicit or not in_seq or r2 == get(k, :r)
  if at_char(y, r2, c2) == ":" and
      same_line and
      (separator?(nx) or flow_indicator?(nx) or json_like?(get(k, :node)))
    after = flow_space(y, r2, c2 + 1, n)
    vch = at_char(y, first(after), second(after))
    v = if member?(vch, [",", "]", "}"])
      {node: scalar_node("", true, {}), r: first(after), c: second(after)}
    else
      flow_node(y, first(after), second(after), n)
    end
    flow_pair(get(k, :node), get(v, :node), in_seq, get(v, :r), get(v, :c))
  elsif in_seq and not explicit
    k
  else
    flow_pair(
      get(k, :node),
      scalar_node("", true, {}),
      in_seq,
      get(k, :r),
      get(k, :c)
    )
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
  props = get(p, :props)
  at = if not bare?(props) and line_end?(at_char(y, r, get(p, :c)))
    flow_space(y, r, get(p, :c), n)
  else
    [r, get(p, :c)]
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
    {
      node: scalar_node(get(t, :text), true, props),
      r: get(t, :r),
      c: get(t, :c)
    }
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
  if r >= get(y, :nr)
    n + 1
  else
    sp = leading_spaces(y, r, 0)
    if at_char(y, r, sp) == "\n"
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
  if r >= get(y, :nr) or ind == 0 and content_level(y, r, 0) < 0
    {lines: acc, r:}
  else
    width = count(nth(r, get(y, :rows)))
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
        out = nth(0, acc)
        prev = nth(1, acc)
        k = nth(2, acc)
        if l.nil?
          [out, prev, k + 1]
        elsif prev.nil?
          ["#{out}#{line_breaks(k)}#{l}", l, 0]
        elsif indented_line?(prev) or indented_line?(l)
          ["#{out}\n#{line_breaks(k)}#{l}", l, 0]
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
    "#{text}\n#{line_breaks(trailing)}"
  elsif chomp == :keep
    line_breaks(trailing)
  elsif has_body
    "#{text}\n"
  else
    ""
  end
end

def block_scalar(y, r, c, n, props)
  h = block_header(y, r, c + 1, nil, nil)
  k = skip_blanks(y, r, get(h, :c))
  if not (line_end?(at_char(y, r, k)) or comment_at?(y, r, k))
    yaml_fail(r, k, "a block scalar's header ends its line")
  end
  ind = if get(h, :digit).nil?
    auto_indent(y, r + 1, n, 0)
  else
    max(n, 0) + get(h, :digit)
  end
  b = block_lines(y, r + 1, ind, [], get(h, :digit).nil?)
  ls = get(b, :lines)
  t = trailing_nils(ls, 0)
  body = take(count(ls) - t, ls)
  text = if at_char(y, r, c) == ">"
    folded_text(body)
  else
    join(map((l) -> to_s(l), body), "\n")
  end
  {
    node: scalar_node(
      chomped(text, body != [], t, get(h, :chomp)),
      false,
      props
    ),
    r: get(b, :r),
    c: 0
  }
end

def compose_node(node, anchors)
  kind = get(node, :kind)
  out = if kind == :alias
    found = get(anchors, get(node, :name))
    if found.nil?
      raise(
        :parse_error,
        "the alias *#{get(node, :name)} names no anchor before it"
      )
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
      get(node, :items)
    )
  else
    composed_pairs(get(node, :pairs), anchors)
  end
  name = get(node, :anchor)
  if name.nil?
    out
  else
    [first(out), assoc(second(out), name, [first(out)])]
  end
end

def composed_pairs(pairs, anchors)
  done = reduce(
    fn(acc, pair)
      kc = compose_node(first(pair), nth(2, acc))
      vc = compose_node(second(pair), second(kc))
      key = key_text(first(kc))
      if get(nth(1, acc), key) != nil
        refuse_document(
          :duplicate_key,
          "the key #{json_stringify(key)} appears twice in one mapping"
        )
      end
      [
        assoc(nth(0, acc), key, first(vc)),
        assoc(nth(1, acc), key, true),
        second(vc)
      ]
    end,
    [{}, {}, anchors],
    pairs
  )
  [nth(0, done), nth(2, done)]
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
  tag = get(node, :tag)
  t = get(node, :text)
  v = if tag.nil? and get(node, :plain)
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
  ["true", "True", "TRUE"]
end

def false_words()
  ["false", "False", "FALSE"]
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
  if member?(t, [".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF"])
    to_float("inf")
  elsif member?(t, ["-.inf", "-.Inf", "-.INF"])
    to_float("-inf")
  elsif member?(t, [".nan", ".NaN", ".NAN"])
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
  if r1 >= get(y, :nr)
    docs
  elsif c1 == 0 and at_char(y, r1, 0) == "%"
    d = directives(y0, r1, default_handles, false)
    explicit_document(assoc(y, :handles, get(d, :handles)), get(d, :r), docs)
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
  all = append(docs, [get(res, :node)])
  at = next_content(y, get(res, :r), get(res, :c))
  r2 = first(at)
  c2 = second(at)
  if r2 >= get(y, :nr)
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
  here = r1 < get(y, :nr) and second(at) == 0
  if here and at_char(y, r1, 0) == "%"
    all_words = filter(
      (w) -> w != "",
      split(
        replace(row_slice(y, r1, 0, count(nth(r1, get(y, :rows)))), "\t", " "),
        " "
      )
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
  assert parse("a: 1\nb:\n  - x\n  - 2.5\n  - true\n  - ~\nc: 0x1f\n", :yaml) ==
    {"a" => 1, "b" => ["x", 2.5, true, nil], "c" => 31}
  assert parse("key:\n- a\n- b\nnext: yes\n", :yaml) ==
    {"key" => ["a", "b"], "next" => "yes"}
  assert parse("- a: 1\n  b: 2\n- - c\n", :yaml) ==
    [{"a" => 1, "b" => 2}, ["c"]]
  assert parse("plain\n  folded\n\n  text\n", :yaml) == "plain folded\ntext"
  assert parse("[0o17, 0x1F, -12, +3, 1e3, .5, -.inf, 0o8]", :yaml) ==
    [15, 31, -12, 3, 1000.0, 0.5, to_float("-inf"), "0o8"]
end

test "parse :yaml reads flow collections and quoted scalars with their escapes"
  assert parse("{a: [1, 'it''s'], \"b\": {c: d}, e: [x: y]}", :yaml) ==
    {"a" => [1, "it's"], "b" => {"c" => "d"}, "e" => [{"x" => "y"}]}
  assert parse("\"tab\\there \\u00e9 \\x41\"", :yaml) == "tab\there é A"
  assert parse("'one\n\n  two '", :yaml) == "one\ntwo "
  assert parse("[\"a \", 'b ']", :yaml) == ["a ", "b "]
  assert refused_kind("[ a\n  : b ]") == :parse_error
end

test "parse :yaml reads literal and folded block scalars under each chomping"
  assert parse(
    "a: |\n  one\n  two\n\nb: >-\n  one\n  two\n\n  three\n",
    :yaml
  ) == {"a" => "one\ntwo\n", "b" => "one two\nthree"}
  assert parse("- |+\n  kept\n\n- |2-\n    indented\n", :yaml) ==
    ["kept\n\n", "  indented"]
end

test "parse :yaml composes anchors, aliases and tags"
  assert parse(
    "base: &b {x: 1}\nuse: *b\nn: !!str 12\nf: !!float 3\n",
    :yaml
  ) == {"base" => {"x" => 1}, "use" => {"x" => 1}, "n" => "12", "f" => 3.0}
  assert refused_kind("a: *nowhere\n") == :parse_error
  assert refused_kind("a: !!int twelve\n") == :bad_value
end

test "parse :yaml reads one document, every document when asked, and nil for none"
  assert parse("", :yaml).nil?
  assert parse("# only a comment\n", :yaml).nil?
  assert parse("--- first\n--- second\n...\n", :yaml, {documents: :all}) ==
    ["first", "second"]
  assert parse("", :yaml, {documents: :all}) == []
  assert refused_kind("--- a\n--- b\n") == :parse_error
end

test "parse :yaml refuses a broken stream with its line and column"
  r = begin
    parse("a: 1\n  b: 2\n", :yaml)
  rescue e
    e.message
  end
  assert starts_with?(r, "2:")
  assert refused_kind("a: b: c\n") == :parse_error
  assert refused_kind("[a, b\n") == :parse_error
  assert refused_kind("\"open\n") == :parse_error
end

test "parse refuses a collection key, a repeated key and an unknown format"
  assert refused_kind("? [a]\n: b\n") == :complex_key
  assert refused_kind("a: 1\na: 2\n") == :duplicate_key
  assert (parse("a", :toml) rescue :refused) == :refused
  assert (parse("a", :yaml, {document: 1}) rescue :refused) == :refused
end

test "parse :json reads JSON into maps, as json_read does"
  assert parse("{\"a\": [1, null]}", :json) == {"a" => [1, nil]}
  assert parse("{\"a\": [1, null]}", :yaml) == {"a" => [1, nil]}
end
