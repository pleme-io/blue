use("deeta", [:get_or])
use("kiwari")
use("moji", [:checked])
use("retsu", [:first, :is_empty, :last, :rest])
use("shomei")
use("tesuto", [:raises?])

def graphql()
  {
    name: "graphql",
    word: "name",
    extras: [kiwari::pat("[\\s,\\uFEFF]"), kiwari::ref("comment")],
    conflicts: [],
    infix: [],
    unary: [],
    pipe: nil,
    reserved: {surface: [], block: []},
    closers: ["}", ")", "]"],
    keywords_painted: keyword_roles,
    punctuation: punctuation_roles,
    rules: graphql_rules
  }
end

def punctuation_roles()
  [
    ["{", "punctuation.bracket"],
    ["}", "punctuation.bracket"],
    ["(", "punctuation.bracket"],
    [")", "punctuation.bracket"],
    ["[", "punctuation.bracket"],
    ["]", "punctuation.bracket"],
    [":", "punctuation.delimiter"],
    ["=", "punctuation.delimiter"],
    ["!", "punctuation.special"],
    ["$", "punctuation.special"],
    ["@", "punctuation.special"],
    ["&", "punctuation.delimiter"],
    ["|", "punctuation.delimiter"],
    ["...", "punctuation.special"]
  ]
end

def directive_locations()
  [
    "QUERY",
    "MUTATION",
    "SUBSCRIPTION",
    "FIELD",
    "FRAGMENT_DEFINITION",
    "FRAGMENT_SPREAD",
    "INLINE_FRAGMENT",
    "VARIABLE_DEFINITION",
    "SCHEMA",
    "SCALAR",
    "OBJECT",
    "FIELD_DEFINITION",
    "ARGUMENT_DEFINITION",
    "INTERFACE",
    "UNION",
    "ENUM",
    "ENUM_VALUE",
    "INPUT_OBJECT",
    "INPUT_FIELD_DEFINITION"
  ]
end

def keyword_roles()
  append(
    map(
      (k) -> [k, "keyword"],
      [
        "query",
        "mutation",
        "subscription",
        "fragment",
        "on",
        "schema",
        "scalar",
        "type",
        "implements",
        "interface",
        "union",
        "enum",
        "input",
        "directive",
        "repeatable",
        "extend"
      ]
    ),
    map(
      (k) -> [k, "constant.builtin"],
      append(["true", "false", "null"], directive_locations)
    )
  )
end

def l(text)
  kiwari::lit(text)
end

def r(name)
  kiwari::ref(name)
end

def o(item)
  kiwari::opt(item)
end

def s(items)
  kiwari::seq(items)
end

def described(items)
  s(append([o(r("description"))], items))
end

def braced(open, item, close)
  s([l(open), kiwari::rep1(item), l(close)])
end

def separated(sep, item)
  s([o(l(sep)), item, kiwari::rep(s([l(sep), item]))])
end

def graphql_rules()
  rule = (name, body, lower) -> kiwari::rule(name, body, lower)
  [
    rule("document", kiwari::rep1(r("_definition")), "document"),
    rule(
      "_definition",
      kiwari::choice(
        [
          r("operation_definition"),
          r("fragment_definition"),
          r("schema_definition"),
          r("scalar_type_definition"),
          r("object_type_definition"),
          r("interface_type_definition"),
          r("union_type_definition"),
          r("enum_type_definition"),
          r("input_object_type_definition"),
          r("directive_definition"),
          r("type_system_extension")
        ]
      ),
      nil
    ),
    rule(
      "operation_definition",
      kiwari::choice(
        [
          r("selection_set"),
          s(
            [
              r("operation_type"),
              o(r("name")),
              o(r("variable_definitions")),
              o(r("directives")),
              r("selection_set")
            ]
          )
        ]
      ),
      "operation"
    ),
    rule(
      "operation_type",
      kiwari::choice([l("query"), l("mutation"), l("subscription")]),
      nil
    ),
    rule("selection_set", braced("{", r("_selection"), "}"), nil),
    rule(
      "_selection",
      kiwari::choice([r("field"), r("fragment_spread"), r("inline_fragment")]),
      nil
    ),
    rule(
      "field",
      s(
        [
          o(r("alias")),
          r("name"),
          o(r("arguments")),
          o(r("directives")),
          o(r("selection_set"))
        ]
      ),
      "field"
    ),
    rule("alias", s([r("name"), l(":")]), nil),
    rule("arguments", braced("(", r("argument"), ")"), nil),
    rule("argument", s([r("name"), l(":"), r("_value")]), nil),
    rule(
      "fragment_spread",
      s([l("..."), r("name"), o(r("directives"))]),
      "spread"
    ),
    rule(
      "inline_fragment",
      s(
        [
          l("..."),
          o(r("type_condition")),
          o(r("directives")),
          r("selection_set")
        ]
      ),
      "inline"
    ),
    rule(
      "fragment_definition",
      s(
        [
          l("fragment"),
          r("name"),
          r("type_condition"),
          o(r("directives")),
          r("selection_set")
        ]
      ),
      "fragment"
    ),
    rule("type_condition", s([l("on"), r("name")]), nil),
    rule(
      "_value",
      kiwari::choice(
        [
          r("variable"),
          r("int_value"),
          r("float_value"),
          r("string_value"),
          r("boolean_value"),
          r("null_value"),
          r("enum_value"),
          r("list_value"),
          r("object_value")
        ]
      ),
      nil
    ),
    rule("variable", s([l("$"), r("name")]), "var"),
    rule("int_value", kiwari::pat("-?(0|[1-9][0-9]*)"), "int"),
    rule(
      "float_value",
      kiwari::pat("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?"),
      "float"
    ),
    rule(
      "string_value",
      kiwari::choice(
        [
          kiwari::pat("\"\"\"([^\"]|\"[^\"]|\"\"[^\"]|\\\\\"\"\")*\"\"\""),
          kiwari::pat("\"([^\"\\\\\\n]|\\\\.)*\"")
        ]
      ),
      "string"
    ),
    rule("boolean_value", kiwari::choice([l("true"), l("false")]), "boolean"),
    rule("null_value", l("null"), "null"),
    rule("enum_value", r("name"), "enum"),
    rule("list_value", s([l("["), kiwari::rep(r("_value")), l("]")]), "list"),
    rule(
      "object_value",
      s([l("{"), kiwari::rep(r("object_field")), l("}")]),
      "object"
    ),
    rule("object_field", s([r("name"), l(":"), r("_value")]), nil),
    rule(
      "variable_definitions",
      braced("(", r("variable_definition"), ")"),
      nil
    ),
    rule(
      "variable_definition",
      s(
        [
          r("variable"),
          l(":"),
          r("_type"),
          o(r("default_value")),
          o(r("directives"))
        ]
      ),
      nil
    ),
    rule("default_value", s([l("="), r("_value")]), nil),
    rule(
      "_type",
      kiwari::choice([r("named_type"), r("list_type"), r("non_null_type")]),
      nil
    ),
    rule("named_type", r("name"), "named"),
    rule("list_type", s([l("["), r("_type"), l("]")]), "list_of"),
    rule(
      "non_null_type",
      s([kiwari::choice([r("named_type"), r("list_type")]), l("!")]),
      "non_null"
    ),
    rule("directives", kiwari::rep1(r("directive")), nil),
    rule("directive", s([l("@"), r("name"), o(r("arguments"))]), nil),
    rule(
      "schema_definition",
      described(
        [
          l("schema"),
          o(r("directives")),
          braced("{", r("root_operation_type_definition"), "}")
        ]
      ),
      "schema"
    ),
    rule(
      "root_operation_type_definition",
      s([r("operation_type"), l(":"), r("named_type")]),
      nil
    ),
    rule("description", r("string_value"), nil),
    rule(
      "scalar_type_definition",
      described([l("scalar"), r("name"), o(r("directives"))]),
      "scalar"
    ),
    rule(
      "object_type_definition",
      described(
        [
          l("type"),
          r("name"),
          o(r("implements_interfaces")),
          o(r("directives")),
          o(r("fields_definition"))
        ]
      ),
      "object"
    ),
    rule(
      "implements_interfaces",
      s([l("implements"), separated("&", r("named_type"))]),
      nil
    ),
    rule("fields_definition", braced("{", r("field_definition"), "}"), nil),
    rule(
      "field_definition",
      described(
        [
          r("name"),
          o(r("arguments_definition")),
          l(":"),
          r("_type"),
          o(r("directives"))
        ]
      ),
      nil
    ),
    rule(
      "arguments_definition",
      braced("(", r("input_value_definition"), ")"),
      nil
    ),
    rule(
      "input_value_definition",
      described(
        [
          r("name"),
          l(":"),
          r("_type"),
          o(r("default_value")),
          o(r("directives"))
        ]
      ),
      nil
    ),
    rule(
      "interface_type_definition",
      described(
        [
          l("interface"),
          r("name"),
          o(r("implements_interfaces")),
          o(r("directives")),
          o(r("fields_definition"))
        ]
      ),
      "interface"
    ),
    rule(
      "union_type_definition",
      described(
        [
          l("union"),
          r("name"),
          o(r("directives")),
          o(s([l("="), separated("|", r("named_type"))]))
        ]
      ),
      "union"
    ),
    rule(
      "enum_type_definition",
      described(
        [
          l("enum"),
          r("name"),
          o(r("directives")),
          o(braced("{", r("enum_value_definition"), "}"))
        ]
      ),
      "enum"
    ),
    rule(
      "enum_value_definition",
      described([r("enum_value"), o(r("directives"))]),
      nil
    ),
    rule(
      "input_object_type_definition",
      described(
        [
          l("input"),
          r("name"),
          o(r("directives")),
          o(braced("{", r("input_value_definition"), "}"))
        ]
      ),
      "input"
    ),
    rule(
      "directive_definition",
      described(
        [
          l("directive"),
          l("@"),
          r("name"),
          o(r("arguments_definition")),
          o(l("repeatable")),
          l("on"),
          separated("|", r("directive_location"))
        ]
      ),
      "directive"
    ),
    rule(
      "directive_location",
      kiwari::choice(map(l, directive_locations)),
      nil
    ),
    rule(
      "type_system_extension",
      s(
        [
          l("extend"),
          kiwari::choice(
            [
              r("schema_definition"),
              r("scalar_type_definition"),
              r("object_type_definition"),
              r("interface_type_definition"),
              r("union_type_definition"),
              r("enum_type_definition"),
              r("input_object_type_definition")
            ]
          )
        ]
      ),
      nil
    ),
    rule("name", kiwari::pat("[_A-Za-z][_0-9A-Za-z]*"), nil),
    rule("comment", kiwari::token(kiwari::pat("#[^\\r\\n]*")), nil)
  ]
end

def kinds()
  distinct(
    filter((k) -> k != nil, map((x) -> get(x, :lower), get(graphql, :rules)))
  )
end

def table(keys)
  reduce((m, k) -> assoc(m, k, true), {}, keys)
end

def name_start_chars()
  append(chars("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"), ["_"])
end

def digit_chars()
  chars("0123456789")
end

def lexer(text)
  cs = chars(text)
  singles = filter(
    (p) -> length(p) == 1,
    map((p) -> first(p), punctuation_roles)
  )
  {
    text:,
    cs:,
    n: length(cs),
    punct: table(singles),
    start: table(name_start_chars),
    part: table(append(name_start_chars, digit_chars)),
    digit: table(digit_chars),
    blank: table([" ", "\t", ",", "\r", "\u{feff}"])
  }
end

def at(x, i)
  nth(i, get(x, :cs))
end

def slice(x, i, j)
  join(map((k) -> nth(k, get(x, :cs)), range(i, j)), "")
end

def lex_error(line, col, message)
  raise(
    :parse_error,
    "#{line}:#{col}: #{message}",
    {data: {line:, column: col}}
  )
end

def tokens(text)
  x = lexer(text)
  lex_from(x, 0, 1, 0, [], [])
end

def lex_from(x, i, line, ls, cur, done)
  if i >= get(x, :n)
    append(*append(done, [cur]))
  else
    c = at(x, i)
    if c == "\n"
      lex_from(x, i + 1, line + 1, i + 1, cur, done)
    elsif get(get(x, :blank), c)
      lex_from(x, i + 1, line, ls, cur, done)
    elsif c == "#"
      j = text_index(get(x, :text), "\n", i)
      lex_from(
        x,
        if j < 0
          get(x, :n)
        else
          j
        end,
        line,
        ls,
        cur,
        done
      )
    else
      t = token_at(x, i, c, line, i - ls + 1)
      next_ls = if get(t, :lines) > 0
        get(t, :ls)
      else
        ls
      end
      tok = {kind: get(t, :kind), value: get(t, :value), line:, col: i - ls + 1}
      if length(cur) >= 256
        lex_from(
          x,
          get(t, :end),
          line + get(t, :lines),
          next_ls,
          [tok],
          append(done, [cur])
        )
      else
        lex_from(
          x,
          get(t, :end),
          line + get(t, :lines),
          next_ls,
          append(cur, [tok]),
          done
        )
      end
    end
  end
end

def simple(kind, value, stop)
  {kind:, value:, end: stop, lines: 0, ls: 0}
end

def token_at(x, i, c, line, col)
  if get(get(x, :punct), c)
    simple(:punct, c, i + 1)
  elsif c == "."
    if at(x, i + 1) == "." and at(x, i + 2) == "."
      simple(:punct, "...", i + 3)
    else
      lex_error(line, col, "expected \"...\", found \".\"")
    end
  elsif get(get(x, :start), c)
    j = name_end(x, i + 1)
    simple(:name, slice(x, i, j), j)
  elsif c == "-" or get(get(x, :digit), c)
    number_at(x, i, line, col)
  elsif c == "\""
    if at(x, i + 1) == "\"" and at(x, i + 2) == "\""
      block_at(x, i, line, col)
    else
      string_at(x, i, line, col)
    end
  else
    lex_error(line, col, "unexpected character #{json_stringify(c)}")
  end
end

def name_end(x, i)
  if i < get(x, :n) and get(get(x, :part), at(x, i))
    name_end(x, i + 1)
  else
    i
  end
end

def digits_end(x, i)
  if i < get(x, :n) and get(get(x, :digit), at(x, i))
    digits_end(x, i + 1)
  else
    i
  end
end

def number_at(x, i, line, col)
  a = if at(x, i) == "-"
    i + 1
  else
    i
  end
  b = digits_end(x, a)
  if b == a
    lex_error(line, col, "expected a digit after \"-\"")
  elsif at(x, a) == "0" and b > a + 1
    lex_error(line, col, "an integer cannot start with 0")
  end
  frac = if at(x, b) == "."
    e = digits_end(x, b + 1)
    if e == b + 1
      lex_error(line, col, "expected a digit after \".\"")
    end
    e
  else
    b
  end
  stop = if member?(at(x, frac), ["e", "E"])
    k = if member?(at(x, frac + 1), ["+", "-"])
      frac + 2
    else
      frac + 1
    end
    e = digits_end(x, k)
    if e == k
      lex_error(line, col, "expected a digit in the exponent")
    end
    e
  else
    frac
  end
  after = at(x, stop)
  if after == "." or get(get(x, :start), after)
    lex_error(
      line,
      col,
      "a number cannot be followed by #{json_stringify(after)}"
    )
  end
  simple(
    if stop == b
      :int
    else
      :float
    end,
    slice(x, i, stop),
    stop
  )
end

def string_end(x, j, line, col)
  k = text_index(get(x, :text), "\"", j)
  if k < 0
    lex_error(line, col, "unterminated string")
  elsif odd?(backslashes(x, k - 1, 0))
    string_end(x, k + 1, line, col)
  else
    k
  end
end

def backslashes(x, i, n)
  if i >= 0 and at(x, i) == "\\"
    backslashes(x, i - 1, n + 1)
  else
    n
  end
end

def string_at(x, i, line, col)
  k = string_end(x, i + 1, line, col)
  raw = slice(x, i + 1, k)
  if contains?(raw, "\n") or contains?(raw, "\r")
    lex_error(line, col, "unterminated string")
  end
  simple(:string, unescape(raw, line, col), k + 1)
end

def unescape(raw, line, col)
  if not contains?(raw, "\\")
    raw
  else
    json = replace(braced_escapes(raw, line, col), "\t", "\\t")
    json_read("\"#{json}\"") rescue
      lex_error(line, col, "invalid escape sequence in a string")
  end
end

def braced_escapes(raw, line, col)
  i = text_index(raw, "\\u{", 0)
  if i < 0
    raw
  else
    j = text_index(raw, "}", i)
    if j < 0
      lex_error(line, col, "unterminated \\u{ escape")
    end
    cs = chars(raw)
    hex = join(map((k) -> nth(k, cs), range(i + 3, j)), "")
    head = join(map((k) -> nth(k, cs), range(0, i)), "")
    tail = join(map((k) -> nth(k, cs), range(j + 1, length(cs))), "")
    "#{head}#{utf16_escape(hex, line, col)}#{braced_escapes(tail, line, col)}"
  end
end

def hex_value(hex, line, col)
  digits = chars(downcase(hex))
  if is_empty(digits) or length(digits) > 6
    lex_error(line, col, "invalid \\u{#{hex}} escape")
  end
  reduce(
    fn(acc, d)
      v = position(d, chars("0123456789abcdef"))
      if v < 0
        lex_error(line, col, "invalid \\u{#{hex}} escape")
      end
      acc * 16 + v
    end,
    0,
    digits
  )
end

def hex4(n)
  ds = chars("0123456789ABCDEF")
  join(map((k) -> nth(floor(n / expt(16, k)) % 16, ds), [3, 2, 1, 0]), "")
end

def utf16_escape(hex, line, col)
  v = hex_value(hex, line, col)
  if v > 1_114_111 or v >= 55296 and v <= 57343
    lex_error(line, col, "\\u{#{hex}} is not a Unicode scalar value")
  elsif v > 65535
    w = v - 65536
    "\\u#{hex4(55296 + floor(w / 1024))}\\u#{hex4(56320 + w % 1024)}"
  else
    "\\u#{hex4(v)}"
  end
end

def block_end(x, j, line, col)
  k = text_index(get(x, :text), "\"\"\"", j)
  if k < 0
    lex_error(line, col, "unterminated block string")
  elsif at(x, k - 1) == "\\"
    block_end(x, k + 3, line, col)
  else
    k
  end
end

def block_at(x, i, line, col)
  k = block_end(x, i + 3, line, col)
  raw = slice(x, i + 3, k)
  nl = length(split(raw, "\n")) - 1
  last_nl = text_last_index(raw, "\n", length(raw))
  {
    kind: :string,
    value: block_value(replace(raw, "\\\"\"\"", "\"\"\"")),
    end: k + 3,
    lines: nl,
    ls: i + 3 + last_nl + 1
  }
end

def indent_of(line)
  length(line) - length(moji::trim(line, {side: :start, chars: " \t"}))
end

def least(xs)
  reduce(
    fn(a, b)
      if b < a
        b
      else
        a
      end
    end,
    xs
  )
end

def blank?(line)
  indent_of(line) == length(line)
end

def block_value(raw)
  lines = split(replace(replace(raw, "\r\n", "\n"), "\r", "\n"), "\n")
  indents = map(indent_of, filter((x) -> not blank?(x), rest(lines)))
  common = if is_empty(indents)
    0
  else
    least(indents)
  end
  dedented = cons(
    first(lines),
    map((x) -> join(drop(common, chars(x)), ""), rest(lines))
  )
  join(trim_blank(dedented), "\n")
end

def trim_blank(lines)
  kept = drop_blank(lines)
  reverse(drop_blank(reverse(kept)))
end

def drop_blank(lines)
  if is_empty(lines)
    lines
  elsif blank?(first(lines))
    drop_blank(rest(lines))
  else
    lines
  end
end

def eof()
  {kind: :eof, value: "end of input", line: 0, col: 0}
end

def tok(p, i)
  if i < get(p, :n)
    nth(i, get(p, :toks))
  else
    last_tok = if get(p, :n) > 0
      nth(get(p, :n) - 1, get(p, :toks))
    else
      {line: 1, col: 0}
    end
    assoc(
      assoc(eof, :line, get(last_tok, :line)),
      :col,
      get(last_tok, :col) + 1
    )
  end
end

def shown(t)
  if get(t, :kind) == :eof
    "end of input"
  elsif get(t, :kind) == :string
    "a string"
  else
    json_stringify(get(t, :value))
  end
end

def fail(p, i, wanted)
  t = tok(p, i)
  lex_error(
    get(t, :line),
    get(t, :col),
    "expected #{wanted}, found #{shown(t)}"
  )
end

def punct?(p, i, v)
  t = tok(p, i)
  get(t, :kind) == :punct and get(t, :value) == v
end

def word?(p, i, v)
  t = tok(p, i)
  get(t, :kind) == :name and get(t, :value) == v
end

def expect(p, i, v)
  if punct?(p, i, v)
    i + 1
  else
    fail(p, i, json_stringify(v))
  end
end

def keyword(p, i, v)
  if word?(p, i, v)
    i + 1
  else
    fail(p, i, json_stringify(v))
  end
end

def name_at(p, i)
  t = tok(p, i)
  if get(t, :kind) == :name
    get(t, :value)
  else
    fail(p, i, "a name")
  end
end

def mark(p, i, node)
  if get(p, :spans)
    t = tok(p, i)
    assoc(node, :at, [get(t, :line), get(t, :col)])
  else
    node
  end
end

def many(p, i, item, close, acc)
  if punct?(p, i, close)
    [acc, i + 1]
  elsif get(tok(p, i), :kind) == :eof
    fail(p, i, json_stringify(close))
  else
    got = item(p, i)
    many(p, second(got), item, close, append(acc, [first(got)]))
  end
end

def one_or_more(p, i, open, item, close)
  j = expect(p, i, open)
  if punct?(p, j, close)
    fail(p, j, "an item before #{json_stringify(close)}")
  end
  many(p, j, item, close, [])
end

def optional_list(p, i, open, item, close)
  if punct?(p, i, open)
    one_or_more(p, i, open, item, close)
  else
    [[], i]
  end
end

def document_of(p, i, acc)
  if i >= get(p, :n)
    if is_empty(acc)
      fail(p, i, "a definition")
    end
    {kind: :document, definitions: acc}
  else
    got = definition(p, i)
    document_of(p, second(got), append(acc, [first(got)]))
  end
end

def definition(p, i)
  t = tok(p, i)
  v = get(t, :value)
  if punct?(p, i, "{")
    operation(p, i)
  elsif get(t, :kind) == :string
    type_system(p, i + 1, v)
  elsif get(t, :kind) != :name
    fail(p, i, "a definition")
  elsif member?(v, ["query", "mutation", "subscription"])
    operation(p, i)
  elsif v == "fragment"
    fragment_definition(p, i)
  elsif v == "extend"
    extension(p, i + 1)
  else
    type_system(p, i, nil)
  end
end

def operation(p, i)
  if punct?(p, i, "{")
    sel = selection_set(p, i)
    [
      mark(
        p,
        i,
        {
          kind: :operation,
          operation: :query,
          name: nil,
          variables: [],
          directives: [],
          selections: first(sel)
        }
      ),
      second(sel)
    ]
  else
    op = keyword_of(get(tok(p, i), :value))
    j = i + 1
    name = if get(tok(p, j), :kind) == :name
      get(tok(p, j), :value)
    end
    j = if name.nil?
      j
    else
      j + 1
    end
    vars = optional_list(p, j, "(", variable_definition, ")")
    dirs = directives(p, second(vars), false)
    sel = selection_set(p, second(dirs))
    [
      mark(
        p,
        i,
        {
          kind: :operation,
          operation: op,
          name:,
          variables: first(vars),
          directives: first(dirs),
          selections: first(sel)
        }
      ),
      second(sel)
    ]
  end
end

def keyword_of(v)
  case v
  when "query"
    :query
  when "mutation"
    :mutation
  when "subscription"
    :subscription
  end
end

def variable_definition(p, i)
  j = expect(p, i, "$")
  name = name_at(p, j)
  k = expect(p, j + 1, ":")
  ty = type_ref(p, k)
  dv = default_value(p, second(ty))
  dirs = directives(p, second(dv), true)
  [
    mark(
      p,
      i,
      {name:, type: first(ty), default: first(dv), directives: first(dirs)}
    ),
    second(dirs)
  ]
end

def default_value(p, i)
  if punct?(p, i, "=")
    value(p, i + 1, true)
  else
    [nil, i]
  end
end

def type_ref(p, i)
  base = if punct?(p, i, "[")
    inner = type_ref(p, i + 1)
    [{kind: :list_of, of: first(inner)}, expect(p, second(inner), "]")]
  else
    [{kind: :named, name: name_at(p, i)}, i + 1]
  end
  if punct?(p, second(base), "!")
    [{kind: :non_null, of: first(base)}, second(base) + 1]
  else
    base
  end
end

def directives(p, i, constant)
  directives_from(p, i, constant, [])
end

def directives_from(p, i, constant, acc)
  if punct?(p, i, "@")
    name = name_at(p, i + 1)
    args = arguments(p, i + 2, constant)
    directives_from(
      p,
      second(args),
      constant,
      append(acc, [mark(p, i, {name:, arguments: first(args)})])
    )
  else
    [acc, i]
  end
end

def arguments(p, i, constant)
  optional_list(p, i, "(", (q, j) -> argument(q, j, constant), ")")
end

def argument(p, i, constant)
  name = name_at(p, i)
  j = expect(p, i + 1, ":")
  v = value(p, j, constant)
  [mark(p, i, {name:, value: first(v)}), second(v)]
end

def value(p, i, constant)
  t = tok(p, i)
  k = get(t, :kind)
  v = get(t, :value)
  if k == :int
    [{kind: :int, text: v}, i + 1]
  elsif k == :float
    [{kind: :float, text: v}, i + 1]
  elsif k == :string
    [{kind: :string, value: v}, i + 1]
  elsif k == :name
    if v == "true" or v == "false"
      [{kind: :boolean, value: v == "true"}, i + 1]
    elsif v == "null"
      [{kind: :null}, i + 1]
    else
      [{kind: :enum, name: v}, i + 1]
    end
  elsif punct?(p, i, "$")
    if constant
      fail(p, i, "a constant value")
    end
    [{kind: :var, name: name_at(p, i + 1)}, i + 2]
  elsif punct?(p, i, "[")
    items = many(p, i + 1, (q, j) -> value(q, j, constant), "]", [])
    [{kind: :list, items: first(items)}, second(items)]
  elsif punct?(p, i, "{")
    fields = many(p, i + 1, (q, j) -> object_field(q, j, constant), "}", [])
    [{kind: :object, fields: first(fields)}, second(fields)]
  else
    fail(p, i, "a value")
  end
end

def object_field(p, i, constant)
  name = name_at(p, i)
  j = expect(p, i + 1, ":")
  v = value(p, j, constant)
  [{name:, value: first(v)}, second(v)]
end

def selection_set(p, i)
  one_or_more(p, i, "{", selection, "}")
end

def selection(p, i)
  if punct?(p, i, "...")
    if word?(p, i + 1, "on") or punct?(p, i + 1, "{") or punct?(p, i + 1, "@")
      inline_fragment(p, i)
    else
      spread(p, i)
    end
  else
    field(p, i)
  end
end

def spread(p, i)
  name = name_at(p, i + 1)
  dirs = directives(p, i + 2, false)
  [mark(p, i, {kind: :spread, name:, directives: first(dirs)}), second(dirs)]
end

def inline_fragment(p, i)
  on = if word?(p, i + 1, "on")
    name_at(p, i + 2)
  end
  j = if on.nil?
    i + 1
  else
    i + 3
  end
  dirs = directives(p, j, false)
  sel = selection_set(p, second(dirs))
  [
    mark(
      p,
      i,
      {kind: :inline, on:, directives: first(dirs), selections: first(sel)}
    ),
    second(sel)
  ]
end

def field(p, i)
  first_name = name_at(p, i)
  aliased = punct?(p, i + 1, ":")
  name = if aliased
    name_at(p, i + 2)
  else
    first_name
  end
  j = if aliased
    i + 3
  else
    i + 1
  end
  args = arguments(p, j, false)
  dirs = directives(p, second(args), false)
  sel = if punct?(p, second(dirs), "{")
    selection_set(p, second(dirs))
  else
    [[], second(dirs)]
  end
  [
    mark(
      p,
      i,
      {
        kind: :field,
        alias: if aliased
          first_name
        end,
        name:,
        arguments: first(args),
        directives: first(dirs),
        selections: first(sel)
      }
    ),
    second(sel)
  ]
end

def fragment_definition(p, i)
  name = name_at(p, i + 1)
  if name == "on"
    fail(p, i + 1, "a fragment name other than \"on\"")
  end
  j = keyword(p, i + 2, "on")
  on = name_at(p, j)
  dirs = directives(p, j + 1, false)
  sel = selection_set(p, second(dirs))
  [
    mark(
      p,
      i,
      {
        kind: :fragment,
        name:,
        on:,
        directives: first(dirs),
        selections: first(sel)
      }
    ),
    second(sel)
  ]
end

def type_system(p, i, description)
  v = get(tok(p, i), :value)
  if get(tok(p, i), :kind) != :name
    fail(p, i, "a type system definition")
  end
  got = type_body(p, i, v)
  if v == "schema" and is_empty(get(first(got), :operations))
    fail(p, second(got), "\"{\"")
  end
  [
    mark(
      p,
      i,
      assoc(assoc(first(got), :description, description), :extend, false)
    ),
    second(got)
  ]
end

def extension(p, i)
  v = get(tok(p, i), :value)
  if v == "directive" or get(tok(p, i), :kind) != :name
    fail(p, i, "a type system extension")
  end
  got = type_body(p, i, v)
  node = first(got)
  if not extends_something?(node)
    fail(p, second(got), "directives or definitions in the extension")
  end
  [mark(p, i, assoc(dissoc(node, :description), :extend, true)), second(got)]
end

def extends_something?(node)
  any?(
    (k) -> not is_empty(get(node, k)),
    filter(
      (k) -> get(node, k) != nil,
      [:directives, :operations, :interfaces, :fields, :members, :values]
    )
  )
end

def type_body(p, i, v)
  if v == "schema"
    schema_definition(p, i)
  elsif v == "scalar"
    name = name_at(p, i + 1)
    dirs = directives(p, i + 2, true)
    [{kind: :scalar, name:, directives: first(dirs)}, second(dirs)]
  elsif v == "type" or v == "interface"
    object_like(p, i, v)
  elsif v == "union"
    union_definition(p, i)
  elsif v == "enum"
    enum_definition(p, i)
  elsif v == "input"
    name = name_at(p, i + 1)
    dirs = directives(p, i + 2, true)
    fields = optional_list(p, second(dirs), "{", input_value, "}")
    [
      {kind: :input, name:, directives: first(dirs), fields: first(fields)},
      second(fields)
    ]
  elsif v == "directive"
    directive_definition(p, i)
  else
    fail(p, i, "a type system definition")
  end
end

def schema_definition(p, i)
  dirs = directives(p, i + 1, true)
  ops = optional_list(p, second(dirs), "{", root_operation, "}")
  [
    {kind: :schema, directives: first(dirs), operations: first(ops)},
    second(ops)
  ]
end

def root_operation(p, i)
  v = get(tok(p, i), :value)
  if get(tok(p, i), :kind) != :name or keyword_of(v).nil?
    fail(p, i, "query, mutation or subscription")
  end
  j = expect(p, i + 1, ":")
  [{operation: keyword_of(v), type: name_at(p, j)}, j + 1]
end

def object_like(p, i, v)
  name = name_at(p, i + 1)
  ifaces = if word?(p, i + 2, "implements")
    separated_names(p, i + 3, "&")
  else
    [[], i + 2]
  end
  dirs = directives(p, second(ifaces), true)
  fields = optional_list(p, second(dirs), "{", field_definition, "}")
  [
    {
      kind: if v == "type"
        :object
      else
        :interface
      end,
      name:,
      interfaces: first(ifaces),
      directives: first(dirs),
      fields: first(fields)
    },
    second(fields)
  ]
end

def separated_names(p, i, sep)
  j = if punct?(p, i, sep)
    i + 1
  else
    i
  end
  more_names(p, j + 1, sep, [name_at(p, j)])
end

def more_names(p, i, sep, acc)
  if punct?(p, i, sep)
    more_names(p, i + 2, sep, append(acc, [name_at(p, i + 1)]))
  else
    [acc, i]
  end
end

def field_definition(p, i)
  desc = description_at(p, i)
  j = second(desc)
  name = name_at(p, j)
  args = optional_list(p, j + 1, "(", input_value, ")")
  k = expect(p, second(args), ":")
  ty = type_ref(p, k)
  dirs = directives(p, second(ty), true)
  [
    mark(
      p,
      j,
      {
        name:,
        description: first(desc),
        arguments: first(args),
        type: first(ty),
        directives: first(dirs)
      }
    ),
    second(dirs)
  ]
end

def description_at(p, i)
  t = tok(p, i)
  if get(t, :kind) == :string
    [get(t, :value), i + 1]
  else
    [nil, i]
  end
end

def input_value(p, i)
  desc = description_at(p, i)
  j = second(desc)
  name = name_at(p, j)
  k = expect(p, j + 1, ":")
  ty = type_ref(p, k)
  dv = default_value(p, second(ty))
  dirs = directives(p, second(dv), true)
  [
    mark(
      p,
      j,
      {
        name:,
        description: first(desc),
        type: first(ty),
        default: first(dv),
        directives: first(dirs)
      }
    ),
    second(dirs)
  ]
end

def union_definition(p, i)
  name = name_at(p, i + 1)
  dirs = directives(p, i + 2, true)
  members = if punct?(p, second(dirs), "=")
    separated_names(p, second(dirs) + 1, "|")
  else
    [[], second(dirs)]
  end
  [
    {kind: :union, name:, directives: first(dirs), members: first(members)},
    second(members)
  ]
end

def enum_definition(p, i)
  name = name_at(p, i + 1)
  dirs = directives(p, i + 2, true)
  values = optional_list(p, second(dirs), "{", enum_value, "}")
  [
    {kind: :enum, name:, directives: first(dirs), values: first(values)},
    second(values)
  ]
end

def enum_value(p, i)
  desc = description_at(p, i)
  j = second(desc)
  name = name_at(p, j)
  if member?(name, ["true", "false", "null"])
    fail(p, j, "an enum value other than true, false or null")
  end
  dirs = directives(p, j + 1, true)
  [
    mark(p, j, {name:, description: first(desc), directives: first(dirs)}),
    second(dirs)
  ]
end

def directive_definition(p, i)
  j = expect(p, i + 1, "@")
  name = name_at(p, j)
  args = optional_list(p, j + 1, "(", input_value, ")")
  repeatable = word?(p, second(args), "repeatable")
  k = if repeatable
    second(args) + 1
  else
    second(args)
  end
  m = keyword(p, k, "on")
  locs = separated_names(p, m, "|")
  bad = filter((x) -> not member?(x, directive_locations), first(locs))
  if not is_empty(bad)
    fail(p, m, "a directive location, not #{first(bad)}")
  end
  [
    {
      kind: :directive,
      name:,
      arguments: first(args),
      repeatable:,
      locations: first(locs)
    },
    second(locs)
  ]
end

def pad(ind)
  join(map((_) -> "  ", range(ind)), "")
end

def deeper(ind)
  if ind.nil?
    nil
  else
    ind + 1
  end
end

def nl(ind, space)
  if ind.nil?
    if space
      " "
    else
      ""
    end
  else
    "\n#{pad(ind)}"
  end
end

def commas(ind, open, close, items, f)
  if is_empty(items)
    "#{open}#{close}"
  else
    inner = deeper(ind)
    body = join(map((x) -> f(inner, x), items), ",#{nl(inner, true)}")
    trailing = if ind.nil?
      ""
    else
      ","
    end
    "#{open}#{nl(inner, false)}#{body}#{trailing}#{nl(ind, false)}#{close}"
  end
end

def curly(ind, items, f)
  if is_empty(items)
    "{}"
  else
    inner = deeper(ind)
    body = join(map((x) -> f(inner, x), items), nl(inner, true))
    "{#{nl(inner, true)}#{body}#{nl(ind, true)}}"
  end
end

def control_chars()
  map(
    (k) -> [json_read("\"\\u#{hex4(k)}\""), k],
    filter((k) -> k != 9, range(0, 32))
  )
end

def quoted(text)
  escaped = replace(replace(text, "\\", "\\\\"), "\"", "\\\"")
  named = [["\n", "\\n"], ["\r", "\\r"], ["\u{8}", "\\b"], ["\u{c}", "\\f"]]
  escaped = reduce(
    (acc, e) -> replace(acc, first(e), second(e)),
    escaped,
    named
  )
  escaped = reduce(
    fn(acc, e)
      if contains?(acc, first(e))
        replace(acc, first(e), "\\u#{hex4(second(e))}")
      else
        acc
      end
    end,
    escaped,
    control_chars
  )
  "\"#{escaped}\""
end

def byte_length(text)
  reduce(
    fn(n, c)
      if compare(c, "\u{80}") < 0
        n + 1
      elsif compare(c, "ࠀ") < 0
        n + 2
      elsif compare(c, "𐀀") < 0
        n + 3
      else
        n + 4
      end
    end,
    0,
    chars(text)
  )
end

def block_able?(text)
  lines = split(text, "\n")
  if contains?(text, "\r")
    false
  elsif blank?(first(lines))
    false
  elsif length(lines) > 1 and blank?(last(lines))
    false
  else
    indents = map(indent_of, filter((x) -> not blank?(x), lines))
    is_empty(indents) or least(indents) == 0
  end
end

def block(ind, text)
  multi = contains?(text, "\n") or
    byte_length(text) > 70 or
    ends_with?(text, "\"") or
    ends_with?(text, "\\")
  esc = (line) -> replace(line, "\"\"\"", "\\\"\"\"")
  if not multi
    "\"\"\"#{esc(text)}\"\"\""
  else
    lines = map(
      fn(line)
        if line == ""
          "\n"
        else
          "#{nl(ind, false)}#{esc(line)}"
        end
      end,
      split(text, "\n")
    )
    "\"\"\"#{join(lines, "")}#{nl(ind, false)}\"\"\""
  end
end

def string_text(ind, described, text)
  if ind != nil and (described or contains?(text, "\n")) and block_able?(text)
    block(ind, text)
  else
    quoted(text)
  end
end

def description_text(ind, d)
  if d.nil?
    ""
  else
    "#{string_text(ind, true, d)}#{nl(ind, true)}"
  end
end

def type_text(t)
  k = get(t, :kind)
  if k == :named
    get(t, :name)
  elsif k == :list_of
    "[#{type_text(get(t, :of))}]"
  else
    "#{type_text(get(t, :of))}!"
  end
end

def value_text(ind, v)
  k = get(v, :kind)
  if k == :null
    "null"
  elsif k == :boolean
    if get(v, :value)
      "true"
    else
      "false"
    end
  elsif k == :enum
    get(v, :name)
  elsif k == :var
    "$#{get(v, :name)}"
  elsif k == :int or k == :float
    get(v, :text)
  elsif k == :string
    string_text(ind, false, get(v, :value))
  elsif k == :list
    commas(ind, "[", "]", get(v, :items), value_text)
  else
    commas(
      ind,
      "{",
      "}",
      get(v, :fields),
      (i, f) -> "#{get(f, :name)}: #{value_text(i, get(f, :value))}"
    )
  end
end

def arguments_text(args)
  if is_empty(args)
    ""
  else
    commas(
      nil,
      "(",
      ")",
      args,
      (i, a) -> "#{get(a, :name)}: #{value_text(i, get(a, :value))}"
    )
  end
end

def directives_text(dirs)
  join(
    map((d) -> " @#{get(d, :name)}#{arguments_text(get(d, :arguments))}", dirs),
    ""
  )
end

def default_text(ind, dv)
  if dv.nil?
    ""
  else
    " = #{value_text(ind, dv)}"
  end
end

def variables_text(vars)
  if is_empty(vars)
    ""
  else
    commas(
      nil,
      "(",
      ")",
      vars,
      fn(i, x)
        "$#{get(x, :name)}: #{type_text(get(x, :type))}#{default_text(i, get(x, :default))}#{directives_text(get(x, :directives))}"
      end
    )
  end
end

def input_value_text(ind, x)
  "#{description_text(ind, get(x, :description))}#{get(x, :name)}: #{type_text(get(x, :type))}#{default_text(ind, get(x, :default))}#{directives_text(get(x, :directives))}"
end

def arguments_definition_text(ind, args)
  if is_empty(args)
    ""
  elsif any?(
    (a) -> get(a, :description) != nil or not is_empty(get(a, :directives)),
    args
  )
    commas(ind, "(", ")", args, input_value_text)
  else
    commas(nil, "(", ")", args, input_value_text)
  end
end

def field_definition_text(ind, f)
  "#{description_text(ind, get(f, :description))}#{get(f, :name)}#{arguments_definition_text(ind, get(f, :arguments))}: #{type_text(get(f, :type))}#{directives_text(get(f, :directives))}"
end

def enum_value_text(ind, v)
  "#{description_text(ind, get(v, :description))}#{get(v, :name)}#{directives_text(get(v, :directives))}"
end

def selection_text(ind, sel)
  k = get(sel, :kind)
  if k == :field
    head = if get(sel, :alias).nil?
      ""
    else
      "#{get(sel, :alias)}: "
    end
    "#{head}#{get(sel, :name)}#{arguments_text(get(sel, :arguments))}#{directives_text(get(sel, :directives))}#{selections_suffix(ind, get(sel, :selections))}"
  elsif k == :spread
    "...#{get(sel, :name)}#{directives_text(get(sel, :directives))}"
  else
    head = if get(sel, :on).nil?
      "..."
    else
      "... on #{get(sel, :on)}"
    end
    "#{head}#{directives_text(get(sel, :directives))} #{curly(ind, get(sel, :selections), selection_text)}"
  end
end

def selections_suffix(ind, sels)
  if is_empty(sels)
    ""
  else
    " #{curly(ind, sels, selection_text)}"
  end
end

def block_suffix(ind, items, f)
  if is_empty(items)
    ""
  else
    " #{curly(ind, items, f)}"
  end
end

def extend_prefix(ind, d)
  if get(d, :extend)
    "extend "
  else
    description_text(ind, get(d, :description))
  end
end

def definition_text(ind, d, leading)
  k = get(d, :kind)
  dirs = directives_text(get(d, :directives))
  if k == :operation
    shorthand = leading and
      get(d, :operation) == :query and
      get(d, :name).nil? and
      is_empty(get(d, :variables)) and
      is_empty(get(d, :directives))
    body = curly(ind, get(d, :selections), selection_text)
    if shorthand
      body
    else
      named = if get(d, :name).nil?
        ""
      else
        " #{get(d, :name)}"
      end
      "#{get(d, :operation)}#{named}#{variables_text(get(d, :variables))}#{dirs} #{body}"
    end
  elsif k == :fragment
    "fragment #{get(d, :name)} on #{get(d, :on)}#{dirs} #{curly(ind, get(d, :selections), selection_text)}"
  elsif k == :directive
    rep = if get(d, :repeatable)
      " repeatable"
    else
      ""
    end
    "#{description_text(ind, get(d, :description))}directive @#{get(d, :name)}#{arguments_definition_text(ind, get(d, :arguments))}#{rep} on #{join(get(d, :locations), " | ")}"
  elsif k == :schema
    ops = get(d, :operations)
    body = if get(d, :extend) and is_empty(ops)
      ""
    else
      " #{curly(ind, ops, (_i, o) -> "#{get(o, :operation)}: #{get(o, :type)}")}"
    end
    "#{extend_prefix(ind, d)}schema#{dirs}#{body}"
  elsif k == :scalar
    "#{extend_prefix(ind, d)}scalar #{get(d, :name)}#{dirs}"
  elsif k == :object or k == :interface
    word = if k == :object
      "type"
    else
      "interface"
    end
    ifaces = if is_empty(get(d, :interfaces))
      ""
    else
      " implements #{join(get(d, :interfaces), " & ")}"
    end
    "#{extend_prefix(ind, d)}#{word} #{get(d, :name)}#{ifaces}#{dirs}#{block_suffix(ind, get(d, :fields), field_definition_text)}"
  elsif k == :union
    members = if is_empty(get(d, :members))
      ""
    else
      " = #{join(get(d, :members), " | ")}"
    end
    "#{extend_prefix(ind, d)}union #{get(d, :name)}#{dirs}#{members}"
  elsif k == :enum
    "#{extend_prefix(ind, d)}enum #{get(d, :name)}#{dirs}#{block_suffix(ind, get(d, :values), enum_value_text)}"
  else
    "#{extend_prefix(ind, d)}input #{get(d, :name)}#{dirs}#{block_suffix(ind, get(d, :fields), input_value_text)}"
  end
end

def document_text(ind, doc)
  defs = get(doc, :definitions)
  texts = map(
    (i) -> definition_text(ind, nth(i, defs), i == 0),
    range(length(defs))
  )
  if ind.nil?
    join(texts, " ")
  elsif is_empty(texts)
    ""
  else
    "#{join(texts, "\n\n")}\n"
  end
end

def parse(text, opts?)
  opts = checked(opts, [:spans])
  toks = tokens(text)
  p = {toks:, n: length(toks), spans: get_or(opts, :spans, false)}
  document_of(p, 0, [])
end

def render(document, format?, opts?)
  checked(opts, [])
  f = format or :graphql
  if f == :graphql
    document_text(0, document)
  elsif f == :compact
    document_text(nil, document)
  else
    raise(
      :bad_option,
      "render: the format must be :graphql or :compact, got #{f}"
    )
  end
end

def builtin_sdl()
  join(
    [
      "scalar Int",
      "scalar Float",
      "scalar String",
      "scalar Boolean",
      "scalar ID",
      "directive @skip(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT",
      "directive @include(if: Boolean!) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT",
      "directive @deprecated(reason: String = \"No longer supported\") on FIELD_DEFINITION | ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION | ENUM_VALUE",
      "directive @specifiedBy(url: String!) on SCALAR",
      "type __Schema { description: String types: [__Type!]! queryType: __Type! mutationType: __Type subscriptionType: __Type directives: [__Directive!]! }",
      "type __Type { kind: __TypeKind! name: String description: String fields(includeDeprecated: Boolean = false): [__Field!] interfaces: [__Type!] possibleTypes: [__Type!] enumValues(includeDeprecated: Boolean = false): [__EnumValue!] inputFields(includeDeprecated: Boolean = false): [__InputValue!] ofType: __Type specifiedByURL: String isOneOf: Boolean }",
      "enum __TypeKind { SCALAR OBJECT INTERFACE UNION ENUM INPUT_OBJECT LIST NON_NULL }",
      "type __Field { name: String! description: String args(includeDeprecated: Boolean = false): [__InputValue!]! type: __Type! isDeprecated: Boolean! deprecationReason: String }",
      "type __InputValue { name: String! description: String type: __Type! defaultValue: String isDeprecated: Boolean! deprecationReason: String }",
      "type __EnumValue { name: String! description: String isDeprecated: Boolean! deprecationReason: String }",
      "type __Directive { name: String! description: String locations: [__DirectiveLocation!]! args(includeDeprecated: Boolean = false): [__InputValue!]! isRepeatable: Boolean! }",
      "enum __DirectiveLocation { #{join(directive_locations, " ")} }"
    ],
    "\n"
  )
end

def finding(rule, message, node)
  {rule:, message:, at: get(node, :at)}
end

def type_kinds()
  [:scalar, :object, :interface, :union, :enum, :input]
end

def definitions_of(schema)
  if schema.nil?
    []
  else
    get(schema, :definitions)
  end
end

def merged(base, ext)
  reduce(
    (acc, k) -> assoc(acc, k, append(get(acc, k), get(ext, k))),
    base,
    filter(
      (k) -> get(ext, k) != nil,
      [:directives, :operations, :interfaces, :fields, :members, :values]
    )
  )
end

def add_definition(state, d)
  k = get(d, :kind)
  name = get(d, :name)
  if k == :directive
    previous = get(get(state, :directives), name)
    if previous != nil and not get(previous, :builtin)
      note(
        state,
        finding(
          "directive-unique",
          "the directive @#{name} is defined more than once",
          d
        )
      )
    else
      assoc(state, :directives, assoc(get(state, :directives), name, d))
    end
  elsif k == :schema
    if get(state, :schema) != nil
      note(
        state,
        finding("schema-unique", "the schema is defined more than once", d)
      )
    else
      assoc(state, :schema, d)
    end
  else
    previous = get(get(state, :types), name)
    if previous.nil?
      assoc(state, :types, assoc(get(state, :types), name, d))
    else
      note(
        state,
        finding("type-unique", "the type #{name} is defined more than once", d)
      )
    end
  end
end

def add_extension(state, d)
  k = get(d, :kind)
  if k == :schema
    if get(state, :schema).nil?
      assoc(state, :schema_ext, append(get(state, :schema_ext), [d]))
    else
      assoc(state, :schema, merged(get(state, :schema), d))
    end
  else
    name = get(d, :name)
    base = get(get(state, :types), name)
    if base.nil?
      note(
        state,
        finding(
          "extension-orphan",
          "the extended type #{name} is not defined",
          d
        )
      )
    elsif get(base, :kind) != k
      note(
        state,
        finding(
          "extension-kind",
          "#{name} is a #{get(base, :kind)}, extended as a #{k}",
          d
        )
      )
    else
      assoc(state, :types, assoc(get(state, :types), name, merged(base, d)))
    end
  end
end

def note(state, f)
  assoc(state, :problems, append(get(state, :problems), [f]))
end

def builtins()
  map((d) -> assoc(d, :builtin, true), get(parse(builtin_sdl), :definitions))
end

def implicit_roots(types)
  filter(
    (o) -> get(o, :type) != nil,
    map(
      fn(op)
        name = get(
          {query: "Query", mutation: "Mutation", subscription: "Subscription"},
          op
        )
        if get(types, name) != nil
          {operation: op, type: name}
        else
          {operation: op, type: nil}
        end
      end,
      [:query, :mutation, :subscription]
    )
  )
end

def schema_index(schema)
  defs = definitions_of(schema)
  user = filter(
    (d) -> get(d, :kind) != :operation and get(d, :kind) != :fragment,
    defs
  )
  state = {types: {}, directives: {}, schema: nil, schema_ext: [], problems: []}
  state = reduce(add_definition, state, builtins)
  state = reduce(
    add_definition,
    state,
    filter((d) -> not get(d, :extend), user)
  )
  state = reduce(add_extension, state, filter((d) -> get(d, :extend), user))
  executable = filter(
    (d) -> get(d, :kind) == :operation or get(d, :kind) == :fragment,
    defs
  )
  state = reduce(
    fn(st, d)
      note(
        st,
        finding(
          "type-system-only",
          "a schema holds no #{get(d, :kind)} definition",
          d
        )
      )
    end,
    state,
    executable
  )
  state = if get(state, :schema).nil? and not is_empty(get(state, :schema_ext))
    reduce(
      fn(st, d)
        note(
          st,
          finding(
            "extension-orphan",
            "the schema is extended but never defined",
            d
          )
        )
      end,
      state,
      get(state, :schema_ext)
    )
  else
    state
  end
  roots = if get(state, :schema).nil?
    implicit_roots(get(state, :types))
  else
    get(get(state, :schema), :operations)
  end
  assoc(
    assoc(
      state,
      :roots,
      reduce((m, o) -> assoc(m, get(o, :operation), get(o, :type)), {}, roots)
    ),
    :user,
    user
  )
end

def type_named(s, name)
  get(get(s, :types), name)
end

def base_name(t)
  if get(t, :kind) == :named
    get(t, :name)
  else
    base_name(get(t, :of))
  end
end

def kind_of(s, name)
  t = type_named(s, name)
  if t.nil?
    nil
  else
    get(t, :kind)
  end
end

def input_kind?(k)
  member?(k, [:scalar, :enum, :input])
end

def output_kind?(k)
  member?(k, [:scalar, :object, :interface, :union, :enum])
end

def composite?(k)
  member?(k, [:object, :interface, :union])
end

def by_name(xs, name)
  find(xs, (x) -> get(x, :name) == name)
end

def duplicates(names)
  distinct(filter((n) -> length(filter((m) -> m == n, names)) > 1, names))
end

def schema_problems(s)
  user = get(s, :user)
  append(
    get(s, :problems),
    retsu::flat_map(user, (d) -> definition_problems(s, d)),
    root_problems(s)
  )
end

def root_problems(s)
  retsu::flat_map(
    map_entries(get(s, :roots)),
    fn(e)
      name = second(e)
      if name.nil?
        []
      elsif kind_of(s, name) != :object
        [
          finding(
            "root-type",
            "the #{first(e)} root #{name} is not an object type",
            {}
          )
        ]
      else
        []
      end
    end
  )
end

def known_type_problems(s, t, node, what)
  name = base_name(t)
  if type_named(s, name).nil?
    [finding("type-known", "#{what} names the undefined type #{name}", node)]
  else
    []
  end
end

def location_of(d)
  case get(d, :kind)
  when :schema
    "SCHEMA"
  when :scalar
    "SCALAR"
  when :object
    "OBJECT"
  when :interface
    "INTERFACE"
  when :union
    "UNION"
  when :enum
    "ENUM"
  when :input
    "INPUT_OBJECT"
  end
end

def definition_problems(s, d)
  k = get(d, :kind)
  if k == :directive
    retsu::flat_map(
      get(d, :arguments),
      fn(a)
        input_value_problems(s, a, "ARGUMENT_DEFINITION", "@#{get(d, :name)}")
      end
    )
  else
    own = directive_problems(s, get(d, :directives), location_of(d), {}, nil)
    append(own, member_problems(s, d))
  end
end

def member_problems(s, d)
  k = get(d, :kind)
  name = get(d, :name)
  if k == :object or k == :interface
    append(
      retsu::flat_map(
        get(d, :fields),
        (f) -> field_definition_problems(s, f, name)
      ),
      retsu::flat_map(
        get(d, :interfaces),
        fn(i)
          if kind_of(s, i) != :interface
            [
              finding(
                "implements-interface",
                "#{name} implements #{i}, which is not an interface",
                d
              )
            ]
          else
            []
          end
        end
      )
    )
  elsif k == :union
    retsu::flat_map(
      get(d, :members),
      fn(m)
        if kind_of(s, m) != :object
          [
            finding(
              "union-member",
              "the union #{name} lists #{m}, which is not an object type",
              d
            )
          ]
        else
          []
        end
      end
    )
  elsif k == :enum
    retsu::flat_map(
      get(d, :values),
      (v) -> directive_problems(s, get(v, :directives), "ENUM_VALUE", {}, nil)
    )
  elsif k == :input
    retsu::flat_map(
      get(d, :fields),
      (f) -> input_value_problems(s, f, "INPUT_FIELD_DEFINITION", name)
    )
  else
    []
  end
end

def field_definition_problems(s, f, owner)
  where = "#{owner}.#{get(f, :name)}"
  known = known_type_problems(s, get(f, :type), f, where)
  kind = append(
    known,
    if is_empty(known) and
        not output_kind?(kind_of(s, base_name(get(f, :type))))
      [
        finding(
          "output-type",
          "#{where} has the input type #{base_name(get(f, :type))}",
          f
        )
      ]
    else
      []
    end
  )
  append(
    kind,
    directive_problems(s, get(f, :directives), "FIELD_DEFINITION", {}, nil),
    retsu::flat_map(
      get(f, :arguments),
      (a) -> input_value_problems(s, a, "ARGUMENT_DEFINITION", where)
    )
  )
end

def input_value_problems(s, a, location, owner)
  where = "#{owner}(#{get(a, :name)})"
  known = known_type_problems(s, get(a, :type), a, where)
  kind = append(
    known,
    if is_empty(known) and not input_kind?(kind_of(s, base_name(get(a, :type))))
      [
        finding(
          "input-type",
          "#{where} has the output type #{base_name(get(a, :type))}",
          a
        )
      ]
    else
      []
    end
  )
  defaults = if get(s, :defaults) and get(a, :default) != nil and is_empty(kind)
    value_problems(s, get(a, :default), get(a, :type), a, where, {})
  else
    []
  end
  append(
    kind,
    defaults,
    directive_problems(s, get(a, :directives), location, {}, nil)
  )
end

def int32?(text)
  n = to_int(text)
  n != nil and n >= -2_147_483_648 and n <= 2_147_483_647
end

def value_problems(s, v, t, node, where, vars)
  k = get(v, :kind)
  if k == :var
    []
  elsif get(t, :kind) == :non_null
    if k == :null
      [finding("value-type", "#{where} cannot be null", node)]
    else
      value_problems(s, v, get(t, :of), node, where, vars)
    end
  elsif k == :null
    []
  elsif get(t, :kind) == :list_of
    if k == :list
      retsu::flat_map(
        get(v, :items),
        (x) -> value_problems(s, x, get(t, :of), node, where, vars)
      )
    else
      value_problems(s, v, get(t, :of), node, where, vars)
    end
  else
    named_value_problems(s, v, get(t, :name), node, where, vars)
  end
end

def named_value_problems(s, v, name, node, where, vars)
  k = get(v, :kind)
  d = type_named(s, name)
  bad = [
    finding(
      "value-type",
      "#{where} takes a #{name}, not #{render_value(v)}",
      node
    )
  ]
  if d.nil?
    []
  elsif name == "Int"
    if k == :int and int32?(get(v, :text))
      []
    else
      bad
    end
  elsif name == "Float"
    if k == :int or k == :float
      []
    else
      bad
    end
  elsif name == "String"
    if k == :string
      []
    else
      bad
    end
  elsif name == "Boolean"
    if k == :boolean
      []
    else
      bad
    end
  elsif name == "ID"
    if k == :string or k == :int
      []
    else
      bad
    end
  elsif get(d, :kind) == :enum
    if k == :enum and by_name(get(d, :values), get(v, :name)) != nil
      []
    else
      bad
    end
  elsif get(d, :kind) == :input
    if k != :object
      bad
    else
      object_problems(s, v, d, node, where, vars)
    end
  elsif get(d, :kind) == :scalar
    []
  else
    bad
  end
end

def render_value(v)
  value_text(nil, v)
end

def object_problems(s, v, d, node, where, vars)
  given = get(v, :fields)
  names = map((f) -> get(f, :name), given)
  unknown = retsu::flat_map(
    given,
    fn(f)
      def_field = by_name(get(d, :fields), get(f, :name))
      if def_field.nil?
        [
          finding(
            "value-type",
            "#{where} has no input field #{get(f, :name)} on #{get(d, :name)}",
            node
          )
        ]
      else
        value_problems(
          s,
          get(f, :value),
          get(def_field, :type),
          node,
          "#{where}.#{get(f, :name)}",
          vars
        )
      end
    end
  )
  missing = retsu::flat_map(
    get(d, :fields),
    fn(f)
      if get(get(f, :type), :kind) == :non_null and
          get(f, :default).nil? and
          not member?(get(f, :name), names)
        [
          finding(
            "value-type",
            "#{where} is missing the required input field #{get(f, :name)}",
            node
          )
        ]
      else
        []
      end
    end
  )
  dups = map(
    fn(n)
      finding(
        "value-type",
        "#{where} gives the input field #{n} more than once",
        node
      )
    end,
    duplicates(names)
  )
  append(unknown, missing, dups)
end

def argument_problems(s, args, defs, node, where, vars)
  names = map((a) -> get(a, :name), args)
  given = retsu::flat_map(
    args,
    fn(a)
      d = by_name(defs, get(a, :name))
      if d.nil?
        [
          finding(
            "argument-exists",
            "#{where} has no argument #{get(a, :name)}",
            a
          )
        ]
      else
        value_problems(
          s,
          get(a, :value),
          get(d, :type),
          a,
          "#{where}(#{get(a, :name)})",
          vars
        )
      end
    end
  )
  missing = retsu::flat_map(
    defs,
    fn(d)
      supplied = by_name(args, get(d, :name))
      required = get(get(d, :type), :kind) == :non_null and
        get(d, :default).nil?
      if required and
          (supplied.nil? or get(get(supplied, :value), :kind) == :null)
        [
          finding(
            "argument-required",
            "#{where} needs the argument #{get(d, :name)}",
            node
          )
        ]
      else
        []
      end
    end
  )
  dups = map(
    fn(n)
      finding("argument-unique", "#{where} is given #{n} more than once", node)
    end,
    duplicates(names)
  )
  append(given, missing, dups)
end

def directive_problems(s, dirs, location, vars, _ctx)
  names = map((d) -> get(d, :name), dirs)
  each = retsu::flat_map(
    dirs,
    fn(d)
      def_dir = get(get(s, :directives), get(d, :name))
      if def_dir.nil?
        [
          finding(
            "directive-known",
            "the directive @#{get(d, :name)} is not defined",
            d
          )
        ]
      elsif not member?(location, get(def_dir, :locations))
        [
          finding(
            "directive-location",
            "@#{get(d, :name)} cannot be used on #{location}",
            d
          )
        ]
      else
        argument_problems(
          s,
          get(d, :arguments),
          get(def_dir, :arguments),
          d,
          "@#{get(d, :name)}",
          vars
        )
      end
    end
  )
  repeated = retsu::flat_map(
    duplicates(names),
    fn(n)
      def_dir = get(get(s, :directives), n)
      if def_dir != nil and not get(def_dir, :repeatable)
        [
          finding(
            "directive-repeat",
            "@#{n} is not repeatable and is used more than once",
            {}
          )
        ]
      else
        []
      end
    end
  )
  append(each, repeated)
end

def string_type()
  {kind: :non_null, of: {kind: :named, name: "String"}}
end

def field_def(s, parent, name, is_root)
  d = type_named(s, parent)
  if name == "__typename"
    {name:, arguments: [], type: string_type}
  elsif name == "__schema" and is_root
    {
      name:,
      arguments: [],
      type: {kind: :non_null, of: {kind: :named, name: "__Schema"}}
    }
  elsif name == "__type" and is_root
    {
      name:,
      arguments: [
        {name: "name", type: string_type, default: nil, directives: []}
      ],
      type: {kind: :named, name: "__Type"}
    }
  elsif d.nil? or get(d, :fields).nil?
    nil
  else
    by_name(get(d, :fields), name)
  end
end

def possible_types(s, name)
  d = type_named(s, name)
  k = get(d, :kind)
  if k == :object
    [name]
  elsif k == :union
    get(d, :members)
  elsif k == :interface
    map(
      (t) -> get(t, :name),
      filter(
        fn(t)
          get(t, :kind) == :object and member?(name, get(t, :interfaces) or [])
        end,
        map((e) -> second(e), map_entries(get(s, :types)))
      )
    )
  else
    []
  end
end

def overlap?(s, a, b)
  bs = possible_types(s, b)
  any?((t) -> member?(t, bs), possible_types(s, a))
end

def selection_problems(ex, sels, parent, where)
  retsu::flat_map(sels, (sel) -> one_selection_problems(ex, sel, parent, where))
end

def one_selection_problems(ex, sel, parent, where)
  s = get(ex, :s)
  k = get(sel, :kind)
  if k == :field
    field_problems(ex, sel, parent, where)
  elsif k == :spread
    frag = get(get(ex, :frags), get(sel, :name))
    dirs = directive_problems(
      s,
      get(sel, :directives),
      "FRAGMENT_SPREAD",
      {},
      nil
    )
    if frag.nil?
      append(
        [
          finding(
            "fragment-known",
            "the fragment #{get(sel, :name)} is not defined",
            sel
          )
        ],
        dirs
      )
    elsif type_named(s, get(frag, :on)) != nil and
        composite?(kind_of(s, get(frag, :on))) and
        not overlap?(s, parent, get(frag, :on))
      append(
        [
          finding(
            "fragment-spread-possible",
            "...#{get(sel, :name)} on #{get(frag, :on)} can never apply to #{parent}",
            sel
          )
        ],
        dirs
      )
    else
      dirs
    end
  else
    on = get(sel, :on) or parent
    dirs = directive_problems(
      s,
      get(sel, :directives),
      "INLINE_FRAGMENT",
      {},
      nil
    )
    if type_named(s, on).nil?
      append(
        [
          finding(
            "fragment-type",
            "the type condition #{on} is not defined",
            sel
          )
        ],
        dirs
      )
    elsif not composite?(kind_of(s, on))
      append(
        [
          finding(
            "fragment-type",
            "the type condition #{on} is not an object, interface or union",
            sel
          )
        ],
        dirs
      )
    elsif not overlap?(s, parent, on)
      append(
        [
          finding(
            "fragment-spread-possible",
            "... on #{on} can never apply to #{parent}",
            sel
          )
        ],
        dirs
      )
    else
      append(dirs, selection_problems(ex, get(sel, :selections), on, where))
    end
  end
end

def field_problems(ex, sel, parent, where)
  s = get(ex, :s)
  name = get(sel, :name)
  path = "#{where}.#{name}"
  d = field_def(s, parent, name, parent == get(ex, :root))
  if d.nil?
    [finding("field-exists", "#{parent} has no field #{name}", sel)]
  else
    base = base_name(get(d, :type))
    k = kind_of(s, base)
    args = argument_problems(
      s,
      get(sel, :arguments),
      get(d, :arguments),
      sel,
      path,
      {}
    )
    dirs = directive_problems(s, get(sel, :directives), "FIELD", {}, nil)
    leaf = if composite?(k) and is_empty(get(sel, :selections))
      [
        finding(
          "leaf-selection",
          "#{path} is a #{base} and needs a selection of its fields",
          sel
        )
      ]
    elsif not composite?(k) and not is_empty(get(sel, :selections))
      [
        finding(
          "leaf-selection",
          "#{path} is a #{base}, which has no fields to select",
          sel
        )
      ]
    else
      []
    end
    inner = if composite?(k)
      selection_problems(ex, get(sel, :selections), base, path)
    else
      []
    end
    append(args, dirs, leaf, inner)
  end
end

def spreads_in(sels)
  retsu::flat_map(
    sels,
    fn(sel)
      k = get(sel, :kind)
      if k == :spread
        [get(sel, :name)]
      else
        spreads_in(get(sel, :selections))
      end
    end
  )
end

def reachable(frags, names, seen)
  fresh = distinct(
    filter((n) -> not member?(n, seen) and get(frags, n) != nil, names)
  )
  if is_empty(fresh)
    seen
  else
    more = retsu::flat_map(
      fresh,
      (n) -> spreads_in(get(get(frags, n), :selections))
    )
    reachable(frags, more, append(seen, fresh))
  end
end

def cyclic?(frags, name)
  member?(
    name,
    reachable(frags, spreads_in(get(get(frags, name), :selections)), [])
  )
end

def usages_in_value(v, t, default_present)
  k = get(v, :kind)
  inner = if t.nil?
    nil
  elsif get(t, :kind) == :non_null
    get(t, :of)
  else
    t
  end
  if k == :var
    [{name: get(v, :name), type: t, default: default_present}]
  elsif k == :list
    item = if inner != nil and get(inner, :kind) == :list_of
      get(inner, :of)
    end
    retsu::flat_map(get(v, :items), (x) -> usages_in_value(x, item, false))
  elsif k == :object
    retsu::flat_map(
      get(v, :fields),
      (f) -> usages_in_value(get(f, :value), nil, false)
    )
  else
    []
  end
end

def usages_in_arguments(args, defs)
  retsu::flat_map(
    args,
    fn(a)
      d = if defs.nil?
        nil
      else
        by_name(defs, get(a, :name))
      end
      t = if d.nil?
        nil
      else
        get(d, :type)
      end
      usages_in_value(get(a, :value), t, d != nil and get(d, :default) != nil)
    end
  )
end

def usages_in_directives(s, dirs)
  retsu::flat_map(
    dirs,
    fn(d)
      def_dir = get(get(s, :directives), get(d, :name))
      usages_in_arguments(
        get(d, :arguments),
        if def_dir.nil?
          nil
        else
          get(def_dir, :arguments)
        end
      )
    end
  )
end

def usages(ex, sels, parent, seen)
  s = get(ex, :s)
  retsu::flat_map(
    sels,
    fn(sel)
      k = get(sel, :kind)
      own = usages_in_directives(s, get(sel, :directives))
      if k == :field
        d = if parent.nil?
          nil
        else
          field_def(s, parent, get(sel, :name), parent == get(ex, :root))
        end
        args = usages_in_arguments(
          get(sel, :arguments),
          if d.nil?
            nil
          else
            get(d, :arguments)
          end
        )
        next_parent = if d.nil?
          nil
        else
          base_name(get(d, :type))
        end
        append(own, args, usages(ex, get(sel, :selections), next_parent, seen))
      elsif k == :spread
        frag = get(get(ex, :frags), get(sel, :name))
        if frag.nil? or member?(get(sel, :name), seen)
          own
        else
          append(
            own,
            usages_in_directives(s, get(frag, :directives)),
            usages(
              ex,
              get(frag, :selections),
              get(frag, :on),
              append(seen, [get(sel, :name)])
            )
          )
        end
      else
        append(
          own,
          usages(ex, get(sel, :selections), get(sel, :on) or parent, seen)
        )
      end
    end
  )
end

def compatible?(var_type, loc_type)
  if get(loc_type, :kind) == :non_null
    get(var_type, :kind) == :non_null and
      compatible?(get(var_type, :of), get(loc_type, :of))
  elsif get(var_type, :kind) == :non_null
    compatible?(get(var_type, :of), loc_type)
  elsif get(loc_type, :kind) == :list_of
    get(var_type, :kind) == :list_of and
      compatible?(get(var_type, :of), get(loc_type, :of))
  elsif get(var_type, :kind) == :list_of
    false
  else
    get(var_type, :name) == get(loc_type, :name)
  end
end

def position_ok?(var_def, use)
  vt = get(var_def, :type)
  lt = get(use, :type)
  if lt.nil?
    true
  elsif get(lt, :kind) == :non_null and get(vt, :kind) != :non_null
    has_default = get(var_def, :default) != nil and
      get(get(var_def, :default), :kind) != :null
    (has_default or get(use, :default)) and compatible?(vt, get(lt, :of))
  else
    compatible?(vt, lt)
  end
end

def variable_problems(ex, op, where)
  s = get(ex, :s)
  vars = get(op, :variables)
  names = map((v) -> get(v, :name), vars)
  defs = retsu::flat_map(
    vars,
    fn(v)
      vname = "$#{get(v, :name)}"
      base = base_name(get(v, :type))
      ty = if type_named(s, base).nil?
        [finding("type-known", "#{vname} names the undefined type #{base}", v)]
      elsif not input_kind?(kind_of(s, base))
        [
          finding(
            "variable-input-type",
            "#{vname} has the output type #{base}",
            v
          )
        ]
      elsif get(v, :default) != nil
        value_problems(s, get(v, :default), get(v, :type), v, vname, {})
      else
        []
      end
      append(
        ty,
        directive_problems(
          s,
          get(v, :directives),
          "VARIABLE_DEFINITION",
          {},
          nil
        )
      )
    end
  )
  dups = map(
    fn(n)
      finding("variable-unique", "#{where} defines $#{n} more than once", op)
    end,
    duplicates(names)
  )
  used = append(
    usages_in_directives(s, get(op, :directives)),
    usages(ex, get(op, :selections), get(ex, :root), [])
  )
  used_names = distinct(map((u) -> get(u, :name), used))
  undefined = map(
    fn(n)
      finding(
        "variable-defined",
        "#{where} uses $#{n} and does not define it",
        op
      )
    end,
    filter((n) -> not member?(n, names), used_names)
  )
  unused = map(
    fn(v)
      finding(
        "variable-unused",
        "#{where} defines $#{get(v, :name)} and never uses it",
        v
      )
    end,
    filter((v) -> not member?(get(v, :name), used_names), vars)
  )
  positions = retsu::flat_map(
    used,
    fn(u)
      v = by_name(vars, get(u, :name))
      if v != nil and
          type_named(s, base_name(get(v, :type))) != nil and
          not position_ok?(v, u)
        [
          finding(
            "variable-position",
            "$#{get(u, :name)} of type #{type_text(get(v, :type))} is used where #{type_text(get(u, :type))} is expected",
            v
          )
        ]
      else
        []
      end
    end
  )
  append(defs, dups, undefined, unused, positions)
end

def root_fields(ex, sels, seen)
  retsu::flat_map(
    sels,
    fn(sel)
      k = get(sel, :kind)
      if k == :field
        [get(sel, :alias) or get(sel, :name)]
      elsif k == :spread
        frag = get(get(ex, :frags), get(sel, :name))
        if frag.nil? or member?(get(sel, :name), seen)
          []
        else
          root_fields(
            ex,
            get(frag, :selections),
            append(seen, [get(sel, :name)])
          )
        end
      else
        root_fields(ex, get(sel, :selections), seen)
      end
    end
  )
end

def operation_problems(ex, op)
  s = get(ex, :s)
  kind = get(op, :operation)
  where = get(op, :name) or "the anonymous #{kind}"
  root = get(get(s, :roots), kind)
  dirs = directive_problems(
    s,
    get(op, :directives),
    upcase(to_s(kind)),
    {},
    nil
  )
  if root.nil?
    append(
      [finding("root-operation", "the schema has no #{kind} root", op)],
      dirs
    )
  else
    rx = assoc(ex, :root, root)
    single = if kind == :subscription
      fields = distinct(root_fields(rx, get(op, :selections), []))
      if length(fields) != 1
        [
          finding(
            "subscription-single-root",
            "#{where} selects #{length(fields)} root fields; a subscription selects one",
            op
          )
        ]
      elsif starts_with?(first(fields), "__")
        [
          finding(
            "subscription-single-root",
            "#{where} selects the introspection field #{first(fields)}",
            op
          )
        ]
      else
        []
      end
    else
      []
    end
    append(
      dirs,
      single,
      variable_problems(rx, op, where),
      selection_problems(rx, get(op, :selections), root, where)
    )
  end
end

def fragment_problems(ex, frag)
  s = get(ex, :s)
  on = get(frag, :on)
  name = get(frag, :name)
  dirs = directive_problems(
    s,
    get(frag, :directives),
    "FRAGMENT_DEFINITION",
    {},
    nil
  )
  head = if type_named(s, on).nil?
    [
      finding(
        "fragment-type",
        "the fragment #{name} is on the undefined type #{on}",
        frag
      )
    ]
  elsif not composite?(kind_of(s, on))
    [
      finding(
        "fragment-type",
        "the fragment #{name} is on #{on}, which is not an object, interface or union",
        frag
      )
    ]
  else
    []
  end
  cycle = if cyclic?(get(ex, :frags), name)
    [finding("fragment-cycle", "the fragment #{name} spreads itself", frag)]
  else
    []
  end
  body = if is_empty(head) and is_empty(cycle)
    selection_problems(
      assoc(ex, :root, get(get(s, :roots), :query)),
      get(frag, :selections),
      on,
      name
    )
  else
    []
  end
  append(dirs, head, cycle, body)
end

def executable_problems(s, doc)
  defs = get(doc, :definitions)
  ops = filter((d) -> get(d, :kind) == :operation, defs)
  frag_list = filter((d) -> get(d, :kind) == :fragment, defs)
  frags = reduce((m, f) -> assoc(m, get(f, :name), f), {}, frag_list)
  ex = {s:, frags:, root: nil}
  type_defs = map(
    fn(d)
      finding(
        "executable-definition",
        "an executable document holds no #{get(d, :kind)} definition",
        d
      )
    end,
    filter(
      (d) -> get(d, :kind) != :operation and get(d, :kind) != :fragment,
      defs
    )
  )
  named = filter((n) -> n != nil, map((o) -> get(o, :name), ops))
  op_dups = map(
    fn(n)
      finding(
        "operation-unique",
        "the operation #{n} is defined more than once",
        {}
      )
    end,
    duplicates(named)
  )
  lone = if length(ops) > 1 and any?((o) -> get(o, :name).nil?, ops)
    [
      finding(
        "lone-anonymous",
        "an anonymous operation must be the only operation",
        {}
      )
    ]
  else
    []
  end
  frag_dups = map(
    fn(n)
      finding(
        "fragment-unique",
        "the fragment #{n} is defined more than once",
        {}
      )
    end,
    duplicates(map((f) -> get(f, :name), frag_list))
  )
  used = reachable(
    frags,
    retsu::flat_map(ops, (o) -> spreads_in(get(o, :selections))),
    []
  )
  unused = map(
    fn(f)
      finding(
        "fragment-unused",
        "the fragment #{get(f, :name)} is never used",
        f
      )
    end,
    filter((f) -> not member?(get(f, :name), used), frag_list)
  )
  append(
    type_defs,
    op_dups,
    lone,
    frag_dups,
    unused,
    retsu::flat_map(ops, (o) -> operation_problems(ex, o)),
    retsu::flat_map(frag_list, (f) -> fragment_problems(ex, f))
  )
end

def as_document(x)
  if string?(x)
    parse(x)
  elsif get(x, :kind) == :document
    x
  else
    {kind: :document, definitions: [x]}
  end
end

def schema_of(schema, opts?)
  opts = checked(opts, [:defaults])
  if get(schema, :kind) == :schema_of
    schema
  else
    s = assoc(
      schema_index(as_document(schema)),
      :defaults,
      get_or(opts, :defaults, false)
    )
    assoc(assoc(s, :kind, :schema_of), :findings, schema_problems(s))
  end
end

def check(subject, rules?, opts?)
  opts = checked(opts, [:defaults])
  doc = as_document(subject)
  if rules.nil?
    get(schema_of(doc, opts), :findings)
  else
    s = schema_of(rules, opts)
    if is_empty(get(s, :findings))
      executable_problems(s, doc)
    else
      get(s, :findings)
    end
  end
end

def validate(document, schema?, opts?)
  found = check(document, schema, opts)
  if is_empty(found)
    as_document(document)
  else
    shown = join(
      map((f) -> "#{get(f, :rule)}: #{get(f, :message)}", take(3, found)),
      "; "
    )
    raise(:invalid, "#{length(found)} finding(s): #{shown}", {data: found})
  end
end

def spec_selection(item)
  if string?(item) and starts_with?(item, "...")
    {kind: :spread, name: join(drop(3, chars(item)), ""), directives: []}
  elsif keyword?(item) or string?(item)
    {
      kind: :field,
      alias: nil,
      name: to_s(item),
      arguments: [],
      directives: [],
      selections: []
    }
  elsif map?(item)
    map(
      fn(e)
        {
          kind: :field,
          alias: nil,
          name: to_s(first(e)),
          arguments: [],
          directives: [],
          selections: flat_selections(second(e))
        }
      end,
      map_entries(item)
    )
  else
    raise(
      :bad_option,
      "fragment: a field is a name, \"...Name\" or {name: [fields]}, not #{item}"
    )
  end
end

def flat_selections(items)
  retsu::flat_map(
    items,
    fn(item)
      got = spec_selection(item)
      if map?(got)
        [got]
      else
        got
      end
    end
  )
end

def fragment(name, spec)
  spec = checked(spec, [:on, :fields])
  on = get(spec, :on)
  fields = get(spec, :fields)
  if not string?(on) or on == ""
    raise(:bad_option, "fragment: on: names the type, as a string")
  elsif not list?(fields) or is_empty(fields)
    raise(:bad_option, "fragment: fields: lists at least one field")
  end
  {
    kind: :fragment,
    name: to_s(name),
    on:,
    directives: [],
    selections: flat_selections(fields)
  }
end

def fragments_of(x)
  if list?(x)
    x
  else
    filter((d) -> get(d, :kind) == :fragment, get(as_document(x), :definitions))
  end
end

def compose(first, second)
  ops = filter(
    (d) -> get(d, :kind) == :operation,
    get(as_document(first), :definitions)
  )
  pool = append(
    filter(
      (d) -> get(d, :kind) == :fragment,
      get(as_document(first), :definitions)
    ),
    fragments_of(second)
  )
  frags = reduce((m, f) -> assoc(m, get(f, :name), f), {}, reverse(pool))
  names = reachable(
    frags,
    retsu::flat_map(ops, (o) -> spreads_in(get(o, :selections))),
    []
  )
  wanted = distinct(
    retsu::flat_map(ops, (o) -> spreads_in(get(o, :selections)))
  )
  missing = filter(
    (n) -> get(frags, n).nil?,
    distinct(
      append(
        wanted,
        retsu::flat_map(
          names,
          (n) -> spreads_in(get(get(frags, n), :selections))
        )
      )
    )
  )
  if not is_empty(missing)
    raise(
      :unknown_fragment,
      "compose: no fragment #{join(missing, ", ")} was given",
      {data: missing}
    )
  end
  {
    kind: :document,
    definitions: append(
      ops,
      map((n) -> get(frags, n), sort_keyed((n) -> n, names))
    )
  }
end

def response_key(sel)
  get(sel, :alias) or get(sel, :name)
end

def select_into(value, sels)
  if value.nil?
    nil
  elsif list?(value)
    map((v) -> select_into(v, sels), value)
  elsif not map?(value)
    value
  else
    reduce(
      fn(acc, sel)
        k = get(sel, :kind)
        if k == :field
          key = response_key(sel)
          if member?(key, map((e) -> first(e), map_entries(value)))
            v = get(value, key)
            assoc(
              acc,
              key,
              if is_empty(get(sel, :selections))
                v
              else
                select_into(v, get(sel, :selections))
              end
            )
          else
            acc
          end
        elsif k == :inline
          typename = get(value, "__typename")
          if get(sel, :on).nil? or typename.nil? or typename == get(sel, :on)
            {**acc, **select_into(value, get(sel, :selections))}
          else
            acc
          end
        else
          acc
        end
      end,
      {},
      sels
    )
  end
end

def select(value, fragment)
  select_into(value, get(fragment, :selections))
end

def hash(operation, algorithm?)
  shomei::hash(render(as_document(operation)), algorithm or :sha256)
end

def fixtures(dir)
  roots = append(
    split(getenv("BLUE_PATH", ""), ":"),
    [path_join(cwd, "bidamas"), cwd]
  )
  hits = filter(
    (p) -> is_dir?(p),
    map((r) -> path_join(r, "danpen/fixtures/#{dir}"), roots)
  )
  if is_empty(hits)
    raise(:no_fixture, dir)
  end
  files = sort_keyed(
    (f) -> f,
    filter((f) -> ends_with?(f, ".graphql"), walk_dir(first(hits)))
  )
  map((f) -> [f, read_file(f)], files)
end

def rule_of(path)
  name = replace(path_basename(path), ".graphql", "")
  rule = join(drop(1, split(name, "invalid-")), "invalid-")
  first(
    filter(
      (r) -> rule == r or starts_with?(rule, "#{r}-"),
      sort_keyed((r) -> -length(r), rule_names)
    )
  )
end

def rule_names()
  [
    "argument-exists",
    "argument-required",
    "argument-unique",
    "directive-known",
    "directive-location",
    "directive-repeat",
    "directive-unique",
    "executable-definition",
    "extension-kind",
    "extension-orphan",
    "field-exists",
    "fragment-cycle",
    "fragment-known",
    "fragment-spread-possible",
    "fragment-type",
    "fragment-unique",
    "fragment-unused",
    "implements-interface",
    "input-type",
    "leaf-selection",
    "lone-anonymous",
    "operation-unique",
    "output-type",
    "parse",
    "root-operation",
    "root-type",
    "schema-unique",
    "subscription-single-root",
    "type-known",
    "type-system-only",
    "type-unique",
    "union-member",
    "value-type",
    "variable-defined",
    "variable-input-type",
    "variable-position",
    "variable-unique",
    "variable-unused"
  ]
end

def rules_found(text, schema)
  map((f) -> get(f, :rule), check(parse(text), schema))
rescue e
  if e.kind == :parse_error
    ["parse"]
  else
    raise(e)
  end
end

def schema_named(name)
  hit = find(
    fixtures("schema"),
    (f) -> ends_with?(first(f), "/#{name}.graphql")
  )
  schema_of(parse(second(hit)))
end

def hand_schema()
  schema_named("hand")
end

def documents_named(prefix, dirs)
  retsu::flat_map(
    dirs,
    fn(dir)
      s = schema_named(dir)
      map(
        (f) -> [first(f), second(f), s],
        filter(
          (f) -> starts_with?(path_basename(first(f)), prefix),
          fixtures("executable/#{dir}")
        )
      )
    end
  )
end

test "the grammar paints every literal it uses and renders for tree-sitter"
  g = graphql
  assert kiwari::unpainted(g) == []
  assert contains?(kiwari::tree_sitter_js(g), "fragment_definition: $ =>")
  assert member?("...", kiwari::literals(g))
  assert member?("repeatable", kiwari::literals(g))
end

test "parse reads an operation into records"
  doc = parse("query Hero($e: Episode = JEDI) @cached { h: hero(episode: $e) { name } }")
  op = first(get(doc, :definitions))
  assert get(op, :kind) == :operation
  assert get(op, :operation) == :query
  assert get(op, :name) == "Hero"
  assert get(first(get(op, :variables)), :default) ==
    {kind: :enum, name: "JEDI"}
  f = first(get(op, :selections))
  assert get(f, :alias) == "h"
  assert get(f, :name) == "hero"
  assert get(first(get(f, :arguments)), :value) == {kind: :var, name: "e"}
  assert get(first(get(op, :directives)), :name) == "cached"
end

test "parse refuses malformed text with its line and column"
  assert raises?(:parse_error, () -> parse(""))
  assert raises?(:parse_error, () -> parse("query { a "))
  assert raises?(:parse_error, () -> parse("{ a(x: 01) }"))
  assert raises?(:parse_error, () -> parse("{ a(x: 1.) }"))
  assert raises?(:parse_error, () -> parse("{ a(x: \"open) }"))
  assert raises?(:parse_error, () -> parse("query ($v: Int = $w) { a }"))
  assert raises?(:parse_error, () -> parse("\"described\" query { a }"))
  e = begin
    parse("{\n  a\n  b(: 1)\n}")
  rescue err
    err
  end
  assert get(e.data, :line) == 3
  assert get(e.data, :column) == 5
end

test "strings decode escapes and block strings lose their common indent"
  doc = parse("{ a(s: \"caf\\u00e9 \\u{1F600} \\\"q\\\" \\\\ \\n\") }")
  v = get(
    get(
      first(get(first(first(get(doc, :definitions)).selections), :arguments)),
      :value
    ),
    :value
  )
  assert v == "café 😀 \"q\" \\ \n"
  assert block_value("\n    Hello,\n      World!\n\n    Yours,\n      GraphQL.\n  ") ==
    "Hello,\n  World!\n\nYours,\n  GraphQL."
  assert block_value("") == ""
  assert block_value("  one line  ") == "  one line  "
end

test "render prints apollo-compiler's canonical layout"
  doc = parse("query Q($a: Int = 1, $b: [String!]!) { x: f(a: $a, b: [\"p\", \"q\"]) @skip(if: false) { ...F ... on T { g } } }  fragment F on T { h }")
  assert render(doc) ==
    "query Q($a: Int = 1, $b: [String!]!) {\n  x: f(a: $a, b: [\"p\", \"q\"]) @skip(if: false) {\n    ...F\n    ... on T {\n      g\n    }\n  }\n}\n\nfragment F on T {\n  h\n}\n"
  assert render(doc, :compact) ==
    "query Q($a: Int = 1, $b: [String!]!) { x: f(a: $a, b: [\"p\", \"q\"]) @skip(if: false) { ...F ... on T { g } } } fragment F on T { h }"
  assert render(parse("{ a }")) == "{\n  a\n}\n"
  assert render(parse("\"\"\"  two\nlines\"\"\" scalar S")) ==
    "\"\"\"\n  two\nlines\n\"\"\"\nscalar S\n"
  assert render(parse("\"  \\nx\" scalar S")) == "\"  \\nx\"\nscalar S\n"
  assert render(parse("\"short\" scalar S")) == "\"\"\"short\"\"\"\nscalar S\n"
  assert render(parse("{ a(s: \"one\\ntwo\") }")) ==
    "{\n  a(s: \"one\\ntwo\")\n}\n"
  assert raises?(:bad_option, () -> render(doc, :json))
end

test "parse after render is the identity on every corpus document"
  docs = append(fixtures("schema"), fixtures("executable"))
  broken = filter(
    fn(f)
      tree = parse(second(f)) rescue nil
      if tree.nil?
        false
      else
        text = render(tree)
        parse(text) != tree or
          render(parse(text)) != text or
          parse(render(tree, :compact)) != tree
      end
    end,
    docs
  )
  assert map((f) -> first(f), broken) == []
  assert length(docs) >= 250
end

test "each invalid schema is found by the rule it is named for"
  docs = filter(
    (f) -> starts_with?(path_basename(first(f)), "invalid-"),
    fixtures("schema")
  )
  missed = filter(
    (f) -> not member?(rule_of(first(f)), rules_found(second(f), nil)),
    docs
  )
  assert map((f) -> path_basename(first(f)), missed) == []
  assert length(docs) >= 19
end

test "every rule a finding can name has an invalid fixture"
  named = map(
    (f) -> rule_of(first(f)),
    filter(
      (f) -> starts_with?(path_basename(first(f)), "invalid-"),
      append(fixtures("schema"), fixtures("executable"))
    )
  )
  assert filter((r) -> not member?(r, named), rule_names) == []
end

test "check carries the position of a finding when the document has spans"
  s = hand_schema
  found = check(parse("query {\n  hero {\n    mass\n  }\n}", {spans: true}), s)
  assert map((f) -> get(f, :at), found) == [[3, 5]]
  assert map((f) -> get(f, :at), check(parse("query { hero { mass } }"), s)) ==
    [nil]
end

test "SDL default values are checked only when asked"
  doc = parse("type Query { a(n: Int = \"ten\"): Int }")
  assert check(doc) == []
  assert map((f) -> get(f, :rule), check(doc, nil, {defaults: true})) ==
    ["value-type"]
  assert raises?(:bad_option, () -> check(doc, nil, {strict: true}))
end

test "validate answers the document or raises the findings"
  s = hand_schema
  doc = parse("{ hero { name } }")
  assert validate(doc, s) == doc
  e = begin
    validate(parse("{ hero { mass } }"), s)
  rescue err
    err
  end
  assert e.kind == :invalid
  assert map((f) -> get(f, :rule), e.data) == ["field-exists"]
end

test "a fragment declared in blue is the fragment parse reads"
  declared = fragment(
    :user_card,
    {on: "User", fields: [:id, :name, {avatar: [:url]}, "...More"]}
  )
  parsed = first(
    get(
      parse("fragment user_card on User { id name avatar { url } ...More }"),
      :definitions
    )
  )
  assert declared == parsed
  assert raises?(:bad_option, () -> fragment(:x, {on: "User", fields: []}))
  assert raises?(:bad_option, () -> fragment(:x, {fields: [:id]}))
  assert raises?(
    :bad_option,
    () -> fragment(:x, {on: "User", fields: [:id], extra: 1})
  )
end

test "compose joins an operation with the fragments it reaches, by name"
  op = parse("query Hero { hero { ...B ...A } }")
  frags = [
    fragment(:C, {on: "Character", fields: [:id]}),
    fragment(:B, {on: "Character", fields: [:name, "...C"]}),
    fragment(:A, {on: "Character", fields: [:appearsIn]}),
    fragment(:Z, {on: "Character", fields: [:id]})
  ]
  doc = compose(op, frags)
  assert map((d) -> get(d, :name), get(doc, :definitions)) ==
    ["Hero", "A", "B", "C"]
  assert compose(op, reverse(frags)) == doc
  assert check(doc, hand_schema) == []
  assert raises?(:unknown_fragment, () -> compose(op, take(2, frags)))
  assert get(compose(parse("{ hero { id } }"), frags), :definitions) ==
    get(parse("{ hero { id } }"), :definitions)
end

test "select reads only the fields a fragment declares"
  card = fragment(
    :card,
    {on: "Human", fields: [:name, {friends: [:name]}, "...Secret"]}
  )
  data = {
    "name" => "Luke",
    "height" => 1.72,
    "friends" => [
      {"name" => "Han", "id" => "1"},
      {"name" => "Leia", "id" => "2"}
    ],
    "secret" => "masked"
  }
  assert select(data, card) ==
    {"name" => "Luke", "friends" => [{"name" => "Han"}, {"name" => "Leia"}]}
  assert select(nil, card).nil?
  assert select({}, card) == {}
  aliased = first(
    get(
      parse("fragment F on Human { n: name ... on Droid { role } ... on Human { height } }"),
      :definitions
    )
  )
  assert select(
    {"n" => "R", "role" => "x", "height" => 2, "__typename" => "Human"},
    aliased
  ) == {"n" => "R", "height" => 2}
end

test "hash is the sha256 of the canonical text, as shasum computes it"
  assert hash(parse("query Q { a }")) ==
    "ebe140cc901fd22769c2396de48f111460ff16619c348023409bbc47fa4a19e1"
  assert hash(parse("query   Q {\n\n a }")) == hash(parse("query Q { a }"))
  assert hash("{ hero { name } }") ==
    "acc088d6d5fdba669a03cf99c1564e10730ec3ccda96ad7943bd57c7237b2aef"
  assert hash(parse("query Q { a }"), :blake3) != hash(parse("query Q { a }"))
  assert raises?(:bad_option, () -> hash(parse("{ a }"), :md5))
end

def kinds_in(x)
  if map?(x)
    own = if keyword?(get(x, :kind))
      [to_s(get(x, :kind))]
    else
      []
    end
    append(own, retsu::flat_map(map_entries(x), (e) -> kinds_in(second(e))))
  elsif list?(x) and x != nil
    retsu::flat_map(x, kinds_in)
  else
    []
  end
end

test "every record kind the parser makes is a kind a grammar rule lowers to"
  doc = parse("query Q($v: [Int!] = [1]) { a(x: {y: null, z: ENUM}, w: 1.5, s: \"t\", b: true, v: $v) ...F ... on T { b } }\nfragment F on T { c }\nscalar S\ntype T { c: Int }\ninterface I { c: Int }\nunion U = T\nenum E { A }\ninput In { a: Int }\ndirective @d on FIELD\nschema { query: T }")
  seen = distinct(kinds_in(doc))
  assert filter((k) -> not member?(k, kinds), seen) == []
  assert filter((k) -> not member?(k, seen), kinds) == []
  assert length(seen) == 24
end

test "check finds nothing in a sound schema or document"
  assert get(hand_schema, :findings) == []
  assert get(schema_named("kensa"), :findings) == []
  sound = append(
    documents_named("valid-", ["hand", "tiny"]),
    documents_named("", ["kensa"])
  )
  assert length(sound) >= 10
  noisy = filter((f) -> check(parse(nth(1, f)), nth(2, f)) != [], sound)
  assert map((f) -> path_basename(first(f)), noisy) == []
end

test "each invalid document is found by the rule it is named for"
  docs = documents_named("invalid-", ["hand", "tiny"])
  missed = filter(
    (f) -> not member?(rule_of(first(f)), rules_found(nth(1, f), nth(2, f))),
    docs
  )
  assert map((f) -> path_basename(first(f)), missed) == []
  assert length(docs) >= 31
end
