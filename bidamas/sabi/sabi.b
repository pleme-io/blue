use(
  "retsu",
  [
    :concat_lists,
    :contains,
    :count_where,
    :first,
    :flat_map,
    :is_empty,
    :repeat
  ]
)

legacy_names("0.1.1", "rs")

# sabi (錆): Rust source from blue data. Build the items as values, render once.
#
# Blue generates Rust the way the fleet's typed-emission rule asks: a program
# builds a TREE of Rust items (constants, enums, structs, impls, match arms), and
# one renderer turns the tree into text. No caller ever pastes Rust together
# from strings, so escaping, indentation and identifier checks live in exactly
# one place (this file) and are tested once.
#
# The first consumer is blue itself: blue-lang-syntax's character tables are
# authored in blue (crates/blue-lang-syntax/gen/kigou.b) and rendered into the
# crate's Rust by this package, with a freshness gate in `nix flake check`.
#
# Every node is a map with a `kind` and named fields. Constructors below are the
# only way nodes are made, so a renderer arm and its constructor stay together.
#
#   types   rs_ty(name)  rs_ty_ref(t)  rs_ty_slice(t)  rs_ty_tuple(ts)
#   exprs   rs_str  rs_char  rs_int  rs_bool  rs_slice  rs_tuple  rs_path
#           rs_match(scrutinee, arms) with rs_arm(pattern, expr)
#   items   rs_const  rs_enum(+ rs_variant)  rs_struct(+ rs_field)
#           rs_impl(+ rs_fn, rs_param, rs_self_param)
#   file    rs_file(source, items), rendered by render_rust

# ── types ──────────────────────────────────────────────────────────────────

def ty(name)
  {kind: :ty_name, name: name}
end

def ty_ref(inner)
  {kind: :ty_ref, inner: inner}
end

def ty_slice(inner)
  {kind: :ty_slice, inner: inner}
end

def ty_tuple(items)
  {kind: :ty_tuple, items: items}
end

def render_ty(t)
  k = get(t, :kind)
  if k == :ty_name
    get(t, :name)
  elsif k == :ty_ref
    "&#{render_ty(get(t, :inner))}"
  elsif k == :ty_slice
    "[#{render_ty(get(t, :inner))}]"
  else
    "(#{join(map(fn(i) render_ty(i) end, get(t, :items)), ", ")})"
  end
end

# ── expressions ────────────────────────────────────────────────────────────

def str(s)
  {kind: :str, value: s}
end

def char(c)
  {kind: :char, value: c}
end

def int(n)
  {kind: :int, value: n}
end

def bool(b)
  {kind: :bool, value: b}
end

# `&[a, b, …]`, one element per line.
def slice(items)
  {kind: :slice, items: items}
end

def tuple(items)
  {kind: :tuple, items: items}
end

# `A::B::C`.
def path(segments)
  {kind: :path, segments: segments}
end

# waive B0013: `match` is a builtin sabi also uses, so the prefix stays; sabi::match names it too
def rs_match(scrutinee, arms)
  {kind: :match, scrutinee: scrutinee, arms: arms}
end

def arm(pattern, expr)
  {kind: :arm, pattern: pattern, expr: expr}
end

# A Rust string literal's body: backslash first, so the escapes added after it
# are not themselves escaped.
def escape_str(s)
  replace(
    replace(
      replace(replace(replace(s, "\\", "\\\\"), "\"", "\\\""), "\n", "\\n"),
      "\t",
      "\\t"
    ),
    "\r",
    "\\r"
  )
end

def escape_char(c)
  if c == "'"
    "\\'"
  elsif c == "\\"
    "\\\\"
  elsif c == "\n"
    "\\n"
  elsif c == "\t"
    "\\t"
  else
    c
  end
end

def pad(level)
  join(repeat("    ", level), "")
end

# An expression at an indentation level (the level of the line it starts on).
def render_expr(e, level)
  k = get(e, :kind)
  if k == :str
    "\"#{escape_str(get(e, :value))}\""
  elsif k == :char
    "'#{escape_char(get(e, :value))}'"
  elsif k == :int
    to_s(get(e, :value))
  elsif k == :bool
    if get(e, :value)
      "true"
    else
      "false"
    end
  elsif k == :tuple
    "(#{join(map(fn(i) render_expr(i, level) end, get(e, :items)), ", ")})"
  elsif k == :path
    join(get(e, :segments), "::")
  elsif k == :slice
    rows = map(
      fn(i) "#{pad(level + 1)}#{render_expr(i, level + 1)}," end,
      get(e, :items)
    )
    "&[\n#{join(rows, "\n")}\n#{pad(level)}]"
  else
    arms = map(
      fn(a)
        "#{pad(level + 1)}#{render_expr(get(a, :pattern), level + 1)} => #{render_expr(get(a, :expr), level + 1)},"
      end,
      get(e, :arms)
    )
    "match #{render_expr(get(e, :scrutinee), level)} {\n#{join(arms, "\n")}\n#{pad(level)}}"
  end
end

# ── items ──────────────────────────────────────────────────────────────────

# waive B0013: `const` is a builtin sabi also uses, so the prefix stays; sabi::const names it too
def rs_const(name, ty, value, doc)
  {kind: :const, name: name, ty: ty, value: value, doc: doc}
end

def variant(name, doc)
  {kind: :variant, name: name, doc: doc}
end

def enum(name, derives, variants, doc)
  {kind: :enum, name: name, derives: derives, variants: variants, doc: doc}
end

def field(name, ty, doc)
  {kind: :field, name: name, ty: ty, doc: doc}
end

def struct(name, derives, fields, doc)
  {kind: :struct, name: name, derives: derives, fields: fields, doc: doc}
end

def param(name, ty)
  {kind: :param, name: name, ty: ty}
end

# `&self`.
def self_param()
  {kind: :self_param}
end

# waive B0013: `fn` is a reserved word, so the prefix stays; sabi::fn names it too
def rs_fn(name, params, ret, body, doc)
  {kind: :fn, name: name, params: params, ret: ret, body: body, doc: doc}
end

def impl(ty_name, fns)
  {kind: :impl, name: ty_name, fns: fns}
end

def doc_line(line, level, marker)
  if line == ""
    "#{pad(level)}#{marker}"
  else
    "#{pad(level)}#{marker} #{line}"
  end
end

def doc_lines(doc, level, marker)
  map(fn(line) doc_line(line, level, marker) end, doc)
end

def derive_line(derives, level)
  if is_empty(derives)
    []
  else
    ["#{pad(level)}#[derive(#{join(derives, ", ")})]"]
  end
end

def render_param(p)
  if get(p, :kind) == :self_param
    "&self"
  else
    "#{get(p, :name)}: #{render_ty(get(p, :ty))}"
  end
end

def render_fn(f, level)
  sig = "#{pad(level)}pub fn #{get(f, :name)}(#{join(map(fn(p) render_param(p) end, get(f, :params)), ", ")}) -> #{render_ty(get(f, :ret))} {"
  body = "#{pad(level + 1)}#{render_expr(get(f, :body), level + 1)}"
  join(
    concat_lists(
      doc_lines(get(f, :doc), level, "///"),
      [sig, body, "#{pad(level)}}"]
    ),
    "\n"
  )
end

def render_item(item)
  k = get(item, :kind)
  doc = doc_lines(get_or_empty(item, :doc), 0, "///")
  if k == :const
    join(
      concat_lists(
        doc,
        [
          "pub const #{get(item, :name)}: #{render_ty(get(item, :ty))} = #{render_expr(get(item, :value), 0)};"
        ]
      ),
      "\n"
    )
  elsif k == :enum
    variants = flat_map(
      fn(v)
        concat_lists(
          doc_lines(get(v, :doc), 1, "///"),
          ["    #{get(v, :name)},"]
        )
      end,
      get(item, :variants)
    )
    join(
      concat_lists(
        concat_lists(doc, derive_line(get(item, :derives), 0)),
        concat_lists(
          ["pub enum #{get(item, :name)} {"],
          concat_lists(variants, ["}"])
        )
      ),
      "\n"
    )
  elsif k == :struct
    fields = flat_map(
      fn(f)
        concat_lists(
          doc_lines(get(f, :doc), 1, "///"),
          ["    pub #{get(f, :name)}: #{render_ty(get(f, :ty))},"]
        )
      end,
      get(item, :fields)
    )
    join(
      concat_lists(
        concat_lists(doc, derive_line(get(item, :derives), 0)),
        concat_lists(
          ["pub struct #{get(item, :name)} {"],
          concat_lists(fields, ["}"])
        )
      ),
      "\n"
    )
  else
    fns = map(fn(f) render_fn(f, 1) end, get(item, :fns))
    join(
      concat_lists(
        ["impl #{get(item, :name)} {"],
        concat_lists([join(fns, "\n\n")], ["}"])
      ),
      "\n"
    )
  end
end

def get_or_empty(m, key)
  v = get(m, key)
  if v == nil
    []
  else
    v
  end
end

# ── identifiers ────────────────────────────────────────────────────────────

def keywords()
  [
    "as",
    "async",
    "await",
    "break",
    "const",
    "continue",
    "crate",
    "dyn",
    "else",
    "enum",
    "extern",
    "false",
    "fn",
    "for",
    "if",
    "impl",
    "in",
    "let",
    "loop",
    "match",
    "mod",
    "move",
    "mut",
    "pub",
    "ref",
    "return",
    "self",
    "Self",
    "static",
    "struct",
    "super",
    "trait",
    "true",
    "type",
    "unsafe",
    "use",
    "where",
    "while"
  ]
end

def ident_start_chars()
  chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
end

def ident_chars()
  concat_lists(ident_start_chars(), chars("0123456789"))
end

# An ASCII Rust identifier that is not a keyword.
def valid_ident?(s)
  cs = chars(s)
  if is_empty(cs)
    false
  elsif contains(ident_start_chars(), first(cs)) == false
    false
  elsif contains(keywords(), s)
    false
  else
    count_where(fn(c) contains(ident_chars(), c) == false end, cs) == 0
  end
end

# Every name an item declares.
def item_names(item)
  k = get(item, :kind)
  if k == :enum
    cons(get(item, :name), map(fn(v) get(v, :name) end, get(item, :variants)))
  elsif k == :struct
    cons(get(item, :name), map(fn(f) get(f, :name) end, get(item, :fields)))
  elsif k == :impl
    cons(get(item, :name), map(fn(f) get(f, :name) end, get(item, :fns)))
  else
    [get(item, :name)]
  end
end

# The names in a file that are not valid Rust identifiers. Empty when clean.
def invalid_names(file)
  filter(
    fn(n) valid_ident?(n) == false end,
    flat_map(fn(i) item_names(i) end, get(file, :items))
  )
end

# ── files ──────────────────────────────────────────────────────────────────

# `source` names the blue program that generated the file, for the header.
def file(source, items)
  {kind: :file, source: source, items: items}
end

def render_rust(file)
  header = "// @generated by #{get(file, :source)} (sabi). Do not edit: regenerate from the source."
  "#{header}\n\n#{join(map(fn(i) render_item(i) end, get(file, :items)), "\n\n")}\n"
end

# ── tests ──────────────────────────────────────────────────────────────────

test "a table constant renders one row per line"
  t = ty_ref(ty_slice(ty_tuple([ty("char"), ty_ref(ty("str"))])))
  c = rs_const(
    "PAIRS",
    t,
    slice([tuple([char("≠"), str("!=")]), tuple([char("×"), str("*")])]),
    ["Pairs."]
  )
  expected = "/// Pairs.\npub const PAIRS: &[(char, &str)] = &[\n    ('≠', \"!=\"),\n    ('×', \"*\"),\n];"
  assert render_item(c) == expected
end

test "strings and chars are escaped, backslash first"
  assert render_expr(str("a\"b\\c\nd"), 0) == "\"a\\\"b\\\\c\\nd\""
  assert render_expr(char("'"), 0) == "'\\''"
  assert render_expr(char("\\"), 0) == "'\\\\'"
end

test "an enum with an impl renders a derive, variants and a match"
  e = enum(
    "Mood",
    ["Debug", "Clone", "Copy"],
    [variant("Calm", ["Quiet."]), variant("Loud", [])],
    ["A mood."]
  )
  body = rs_match(
    path(["self"]),
    [
      arm(path(["Mood", "Calm"]), str("calm")),
      arm(path(["Mood", "Loud"]), str("loud"))
    ]
  )
  i = impl(
    "Mood",
    [
      rs_fn(
        "as_str",
        [self_param()],
        ty_ref(ty("'static str")),
        body,
        ["Its name."]
      )
    ]
  )
  out = render_rust(file("test.b", [e, i]))
  assert contains?(
    out,
    "#[derive(Debug, Clone, Copy)]\npub enum Mood {\n    /// Quiet.\n    Calm,\n    Loud,\n}"
  ) ==
    true
  assert contains?(
    out,
    "    pub fn as_str(&self) -> &'static str {\n        match self {\n            Mood::Calm => \"calm\",\n            Mood::Loud => \"loud\",\n        }\n    }"
  ) ==
    true
  assert starts_with?(out, "// @generated by test.b (sabi).") == true
end

test "a struct renders its fields"
  s = struct(
    "Point",
    ["Debug"],
    [field("x", ty("i64"), ["Across."]), field("y", ty("i64"), [])],
    []
  )
  assert render_item(s) ==
    "#[derive(Debug)]\npub struct Point {\n    /// Across.\n    pub x: i64,\n    pub y: i64,\n}"
end

test "identifiers are checked: a keyword, a leading digit and a hyphen are refused"
  assert valid_ident?("OPERATOR_ALIASES") == true
  assert valid_ident?("_x9") == true
  assert valid_ident?("match") == false
  assert valid_ident?("9lives") == false
  assert valid_ident?("max-replicas") == false
  assert valid_ident?("") == false
  bad = file(
    "t.b",
    [
      rs_const("fn", ty("i64"), int(1), []),
      rs_const("OK", ty("i64"), int(2), [])
    ]
  )
  assert invalid_names(bad) == ["fn"]
end

test "an empty doc emits no doc lines, and an empty doc line keeps the marker"
  assert render_item(rs_const("N", ty("i64"), int(3), [])) ==
    "pub const N: i64 = 3;"
  assert doc_lines(["a", "", "b"], 0, "///") == ["/// a", "///", "/// b"]
end
