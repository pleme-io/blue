@moduledoc """
danpen (断片) — GraphQL in blue: documents parsed into plain records, checked against a schema, composed from fragments, rendered and hashed.

The grammar is the October 2021 specification, held as a kiwari spec.
`parse` reads SDL and executable documents. `check` and `validate` judge a
document against a schema, and each rule has an invalid fixture.
`fragment`, `compose` and `select` build a view's operation and its masked
read. `render` writes apollo-compiler's canonical text, and `hash` is the
persisted-operation id of that text.

    render(parse("query   Q {  a  }"), :compact) #=> "query Q { a }"
"""

use("deeta", [:get_or])
use("fairu")
use("jisho", %i[get_any push_at])
use("kansuu", [:maybe])
use("kiwari")
use("kyohi", [:raised])
use("moji", %i[capitalize checked repeated])
use("retsu", %i[first is_empty last rest])
use("shomei")

@doc """
graphql is the October 2021 GraphQL grammar as a kiwari spec, with the keywords and punctuation an editor paints.

    graphql[:name] #=> "graphql"
    graphql[:closers] #=> ["}", ")", "]"]
"""
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

@doc """
punctuation_roles pairs each GraphQL punctuator with the highlight role an editor paints it in.

    first(punctuation_roles) #=> ["{", "punctuation.bracket"]
    length(punctuation_roles) #=> 14
"""
def punctuation_roles()
  [
    %w[{ punctuation.bracket],
    %w[} punctuation.bracket],
    %w[( punctuation.bracket],
    %w[) punctuation.bracket],
    ["[", "punctuation.bracket"],
    ["]", "punctuation.bracket"],
    %w[: punctuation.delimiter],
    %w[= punctuation.delimiter],
    %w[! punctuation.special],
    %w[$ punctuation.special],
    %w[@ punctuation.special],
    %w[& punctuation.delimiter],
    %w[| punctuation.delimiter],
    %w[... punctuation.special]
  ]
end

@doc """
directive_locations lists every place a directive definition may name after `on`.

    first(directive_locations) #=> "QUERY"
    length(directive_locations) #=> 19
"""
def directive_locations()
  %w[
    QUERY
    MUTATION
    SUBSCRIPTION
    FIELD
    FRAGMENT_DEFINITION
    FRAGMENT_SPREAD
    INLINE_FRAGMENT
    VARIABLE_DEFINITION
    SCHEMA
    SCALAR
    OBJECT
    FIELD_DEFINITION
    ARGUMENT_DEFINITION
    INTERFACE
    UNION
    ENUM
    ENUM_VALUE
    INPUT_OBJECT
    INPUT_FIELD_DEFINITION
  ]
end

@doc """
keyword_roles pairs each GraphQL keyword and builtin constant with its highlight role.

    first(keyword_roles) #=> ["query", "keyword"]
    last(keyword_roles) #=> ["INPUT_FIELD_DEFINITION", "constant.builtin"]
"""
def keyword_roles()
  append(
    map(
      (k) -> [k, "keyword"],
      %w[
        query
        mutation
        subscription
        fragment
        on
        schema
        scalar
        type
        implements
        interface
        union
        enum
        input
        directive
        repeatable
        extend
      ]
    ),
    map(
      (k) -> [k, "constant.builtin"],
      append(%w[true false null], directive_locations)
    )
  )
end

@doc """
l is the grammar's short word for a literal token.

    l("{") #=> {kind: :lit, text: "{"}
"""
def l(text)
  kiwari::lit(text)
end

@doc """
r is the grammar's short word for a reference to another rule.

    r("name") #=> {kind: :ref, name: "name"}
"""
def r(name)
  kiwari::ref(name)
end

@doc """
o is the grammar's short word for an optional item.

    o(r("name")) #=> {kind: :opt, item: {kind: :ref, name: "name"}}
"""
def o(item)
  kiwari::opt(item)
end

@doc """
s is the grammar's short word for a sequence of items.

    s([l("a")]) #=> {kind: :seq, items: [{kind: :lit, text: "a"}]}
"""
def s(items)
  kiwari::seq(items)
end

@doc """
described prefixes a type system rule with the optional description string GraphQL allows before it.

    first(described([l("a")])[:items]) #=> {kind: :opt, item: {kind: :ref, name: "description"}}
"""
def described(items)
  s(append([o(r("description"))], items))
end

@doc """
braced is one or more items between an open and a close literal, as in a selection set.

    length(braced("{", r("x"), "}")[:items]) #=> 3
"""
def braced(open, item, close)
  s([l(open), kiwari::rep1(item), l(close)])
end

@doc """
separated is one or more items joined by a separator that may also lead, as in `= | A | B`.

    first(separated("|", r("x"))[:items]) #=> {kind: :opt, item: {kind: :lit, text: "|"}}
"""
def separated(sep, item)
  s([o(l(sep)), item, kiwari::rep(s([l(sep), item]))])
end

@doc """
graphql_rules holds every rule of the GraphQL grammar, each with the record kind it lowers to.

    first(graphql_rules)[:name] #=> "document"
"""
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

@doc """
kinds names every record kind the grammar lowers to, once each, in rule order.

    first(kinds) #=> "document"
    length(kinds) #=> 24
"""
def kinds()
  distinct(filter((k) -> k != nil, map((x) -> x[:lower], graphql[:rules])))
end

@doc """
table turns a list of keys into a lookup map, so the lexer asks set membership in one step.

    table(["a", "b"]) #=> {"a" => true, "b" => true}
"""
def table(keys)
  reduce((m, k) -> assoc(m, k, true), {}, keys)
end

@doc """
name_start_chars holds the characters a GraphQL name may begin with.

    length(name_start_chars) #=> 53
    last(name_start_chars) #=> "_"
"""
def name_start_chars()
  append(chars("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"), ["_"])
end

@doc """
digit_chars holds the decimal digits a GraphQL number is written in.

    digit_chars #=> ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
"""
def digit_chars()
  chars("0123456789")
end

@doc """
lexer prepares text for tokenizing: its characters and the character sets each token class tests against.

    lexer("a,b")[:n] #=> 3
    get(lexer("a")[:punct], "{") #=> true
"""
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

@doc """
at reads the character at index `i` of a lexer's text, nil past its end.

    at(lexer("ab"), 1) #=> "b"
"""
def at(x, i)
  x[:cs][i]
end

@doc """
slice cuts the lexer's text from index `i` up to, not including, index `j`.

    slice(lexer("query"), 1, 3) #=> "ue"
"""
def slice(x, i, j)
  join(map((k) -> x[:cs][k], range(i, j)), "")
end

@doc """
lex_error raises a parse error that names the line and column where reading stopped.

    raised(() -> lex_error(2, 5, "unexpected character")) #=> :parse_error
"""
def lex_error(line, col, message)
  raise(
    :parse_error,
    "#{line}:#{col}: #{message}",
    {data: {line:, column: col}}
  )
end

@doc """
tokens reads GraphQL text into its tokens, each with its kind, value, line and column; blanks, commas and comments drop out.

    map((t) -> t[:value], tokens("a(x: 1)")) #=> ["a", "(", "x", ":", "1", ")"]
    tokens("{ a }")[1] #=> {kind: :name, value: "a", line: 1, col: 3}
"""
def tokens(text)
  x = lexer(text)
  lex_from(x, 0, 1, 0, [], [])
end

@doc """
lex_from is the tokenizing loop from index `i`, collecting tokens in chunks of 256 so a long document stays cheap to grow.

    length(lex_from(lexer("{ a }"), 0, 1, 0, [], [])) #=> 3
"""
def lex_from(x, i, line, ls, cur, done)
  if i >= x[:n]
    append(*append(done, [cur]))
  else
    c = at(x, i)
    if c == line_break
      lex_from(x, i + 1, line + 1, i + 1, cur, done)
    elsif get(x[:blank], c)
      lex_from(x, i + 1, line, ls, cur, done)
    elsif c == "#"
      j = text_index(x[:text], line_break, i)
      lex_from(
        x,
        if j < 0
          x[:n]
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
      next_ls = if t[:lines] > 0
        t[:ls]
      else
        ls
      end
      tok = {kind: t[:kind], value: t[:value], line:, col: i - ls + 1}
      if length(cur) >= 256
        lex_from(
          x,
          t[:end],
          line + t[:lines],
          next_ls,
          [tok],
          append(done, [cur])
        )
      else
        lex_from(
          x,
          t[:end],
          line + t[:lines],
          next_ls,
          append(cur, [tok]),
          done
        )
      end
    end
  end
end

@doc """
simple is a one-line token read up to index `stop`.

    simple(:name, "a", 1) #=> {kind: :name, value: "a", end: 1, lines: 0, ls: 0}
"""
def simple(kind, value, stop)
  {kind:, value:, end: stop, lines: 0, ls: 0}
end

@doc """
token_at reads the one token that starts with character `c` at index `i`, choosing the reader by that character.

    token_at(lexer("abc d"), 0, "a", 1, 1)[:value] #=> "abc"
    token_at(lexer("-1.5"), 0, "-", 1, 1)[:kind] #=> :float
"""
def token_at(x, i, c, line, col)
  if get(x[:punct], c)
    simple(:punct, c, i + 1)
  elsif c == "."
    if at(x, i + 1) == "." and at(x, i + 2) == "."
      simple(:punct, "...", i + 3)
    else
      lex_error(line, col, "expected \"...\", found \".\"")
    end
  elsif get(x[:start], c)
    j = name_end(x, i + 1)
    simple(:name, slice(x, i, j), j)
  elsif c == "-" or get(x[:digit], c)
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

@doc """
span_end: The index after the run of characters from `i` that the lexer's character set `set` (`:part`, `:digit`, ...) holds.

    span_end({cs: ["1", "2", "a"], n: 3, digit: {"1" => true, "2" => true}}, 0, :digit) #=> 2
"""
def span_end(x, i, set)
  if i < x[:n] and get(get(x, set), at(x, i))
    span_end(x, i + 1, set)
  else
    i
  end
end

@doc """
name_end is the index after the name characters that continue from `i`.

    name_end(lexer("ab1 c"), 0) #=> 3
"""
def name_end(x, i)
  span_end(x, i, :part)
end

@doc """
digits_end is the index after the digits that continue from `i`.

    digits_end(lexer("123x"), 0) #=> 3
"""
def digits_end(x, i)
  span_end(x, i, :digit)
end

@doc """
number_at reads an Int or Float token from `i`, refusing a leading zero, a bare sign and a name glued to the number.

    number_at(lexer("-1.5e3"), 0, 1, 1)[:kind] #=> :float
    number_at(lexer("42"), 0, 1, 1)[:value] #=> "42"
    raised(() -> number_at(lexer("01"), 0, 1, 1)) #=> :parse_error
"""
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
  stop = if member?(at(x, frac), %w[e E])
    k = if member?(at(x, frac + 1), %w[+ -])
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
  if after == "." or get(x[:start], after)
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

@doc """
string_end finds the index of the quote that closes a string, skipping quotes escaped by an odd run of backslashes.

    string_end(lexer("\"ab\" c"), 1, 1, 1) #=> 3
"""
def string_end(x, j, line, col)
  k = text_index(x[:text], "\"", j)
  if k < 0
    lex_error(line, col, "unterminated string")
  elsif odd?(backslashes(x, k - 1, 0))
    string_end(x, k + 1, line, col)
  else
    k
  end
end

@doc """
backslashes counts the backslashes that end at index `i`, so a caller knows whether the next quote is escaped.

    backslashes(lexer("a\\\\"), 2, 0) #=> 2
"""
def backslashes(x, i, n)
  if i >= 0 and at(x, i) == "\\"
    backslashes(x, i - 1, n + 1)
  else
    n
  end
end

@doc """
string_at reads a one-line string token from its opening quote at `i`, with its escapes decoded.

    string_at(lexer("\"hi\""), 0, 1, 1)[:value] #=> "hi"
"""
def string_at(x, i, line, col)
  k = string_end(x, i + 1, line, col)
  raw = slice(x, i + 1, k)
  if contains?(raw, line_break) or contains?(raw, "\r")
    lex_error(line, col, "unterminated string")
  end
  simple(:string, unescape(raw, line, col), k + 1)
end

@doc """
unescape decodes the escape sequences of a string's raw text, refusing one GraphQL does not define.

    unescape("a\\nb", 1, 1) #=> "a\nb"
    unescape("plain", 1, 1) #=> "plain"
"""
def unescape(raw, line, col)
  if not contains?(raw, "\\")
    raw
  else
    json = replace(braced_escapes(raw, line, col), "\t", "\\t")
    json_read("\"#{json}\"") rescue
      lex_error(line, col, "invalid escape sequence in a string")
  end
end

@doc """
braced_escapes rewrites each braced `\u{41}` escape as the JSON `A` form the decoder reads.

    braced_escapes("\\u{41}", 1, 1) #=> "\\u0041"
"""
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
    hex = join(map((k) -> cs[k], range(i + 3, j)), "")
    head = join(map((k) -> cs[k], range(0, i)), "")
    tail = join(map((k) -> cs[k], range(j + 1, length(cs))), "")
    "#{head}#{utf16_escape(hex, line, col)}#{braced_escapes(tail, line, col)}"
  end
end

@doc """
hex_value reads the hex digits of a braced escape as a number, refusing an empty, overlong or non-hex text.

    hex_value("ff", 1, 1) #=> 255
"""
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

@doc """
hex4 writes a number below 65536 as four uppercase hex digits.

    hex4(255) #=> "00FF"
"""
def hex4(n)
  ds = chars("0123456789ABCDEF")
  join(map((k) -> ds[floor(n / expt(16, k)) % 16], [3, 2, 1, 0]), "")
end

@doc """
utf16_escape writes one Unicode scalar value as JSON escapes, a surrogate pair above the basic plane.

    utf16_escape("41", 1, 1) #=> "\\u0041"
    utf16_escape("1F600", 1, 1) #=> "\\uD83D\\uDE00"
"""
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

@doc """
block_end finds the index of the triple quote that closes a block string, skipping an escaped one.

    block_end(lexer("\"\"\"ab\"\"\""), 3, 1, 1) #=> 5
"""
def block_end(x, j, line, col)
  k = text_index(x[:text], "\"\"\"", j)
  if k < 0
    lex_error(line, col, "unterminated block string")
  elsif at(x, k - 1) == "\\"
    block_end(x, k + 3, line, col)
  else
    k
  end
end

@doc """
block_at reads a block string token from `i`, counting the lines it spans so later columns stay right.

    block_at(lexer("\"\"\"ab\"\"\""), 0, 1, 1)[:value] #=> "ab"
"""
def block_at(x, i, line, col)
  k = block_end(x, i + 3, line, col)
  raw = slice(x, i + 3, k)
  nl = length(split(raw, line_break)) - 1
  last_nl = text_last_index(raw, line_break, length(raw))
  {
    kind: :string,
    value: block_value(replace(raw, "\\\"\"\"", "\"\"\"")),
    end: k + 3,
    lines: nl,
    ls: i + 3 + last_nl + 1
  }
end

@doc """
indent_of counts the spaces and tabs that lead a line.

    indent_of("  x") #=> 2
"""
def indent_of(line)
  length(line) - length(moji::trim(line, {side: :start, chars: " \t"}))
end

@doc """
least is the smallest of a non-empty list of numbers.

    least([3, 1, 2]) #=> 1
"""
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

@doc """
blank? is true for a line of only spaces and tabs.

    blank?("  ") #=> true
    blank?(" a") #=> false
"""
def blank?(line)
  indent_of(line) == length(line)
end

@doc """
block_value is a block string's value: the common indent of its later lines removed and its leading and trailing blank lines dropped.

    block_value("\n    a\n      b\n") #=> "a\n  b"
"""
def block_value(raw)
  lines = split(
    replace(replace(raw, unlines(["\r"]), line_break), "\r", line_break),
    line_break
  )
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
  join(trim_blank(dedented), line_break)
end

@doc """
trim_blank drops the blank lines at both ends of a list of lines.

    trim_blank(["", "a", " "]) #=> ["a"]
"""
def trim_blank(lines)
  kept = drop_blank(lines)
  reverse(drop_blank(reverse(kept)))
end

@doc """
drop_blank drops the blank lines at the start of a list of lines.

    drop_blank(["", "a", ""]) #=> ["a", ""]
"""
def drop_blank(lines)
  if is_empty(lines)
    lines
  elsif blank?(first(lines))
    drop_blank(rest(lines))
  else
    lines
  end
end

@doc """
eof is the token the parser sees past the last one, so an error there can say "end of input".

    eof[:kind] #=> :eof
"""
def eof()
  {kind: :eof, value: "end of input", line: 0, col: 0}
end

@doc """
tok is the token at index `i`, or an end-of-input token placed just after the last one.

    tok({toks: [], n: 0}, 0) #=> {kind: :eof, value: "end of input", line: 1, col: 1}
"""
def tok(p, i)
  if i < p[:n]
    p[:toks][i]
  else
    last_tok = if p[:n] > 0
      p[:toks][p[:n] - 1]
    else
      {line: 1, col: 0}
    end
    assoc(assoc(eof, :line, last_tok[:line]), :col, last_tok[:col] + 1)
  end
end

@doc """
shown is how a parse error names the token it found.

    shown({kind: :string, value: "x"}) #=> "a string"
    shown({kind: :name, value: "a"}) #=> "\"a\""
"""
def shown(t)
  if t[:kind] == :eof
    "end of input"
  elsif t[:kind] == :string
    "a string"
  else
    json_stringify(t[:value])
  end
end

@doc """
fail raises a parse error at the token at `i`, saying what was wanted and what was found.

    raised(() -> fail({toks: [], n: 0}, 0, "a name")) #=> :parse_error
"""
def fail(p, i, wanted)
  t = tok(p, i)
  lex_error(t[:line], t[:col], "expected #{wanted}, found #{shown(t)}")
end

@doc """
tok_is?: True when the token at `i` is of `kind` and reads `v`.

    tok_is?({toks: [{kind: :punct, value: "{"}], n: 1}, 0, :punct, "{") #=> true
"""
def tok_is?(p, i, kind, v)
  t = tok(p, i)
  t[:kind] == kind and t[:value] == v
end

@doc """
consume: The index after the token at `i` when it is of `kind` and reads `v`; otherwise a parse error naming `v`.

    consume({toks: [{kind: :name, value: "query"}], n: 1}, 0, :name, "query") #=> 1
"""
def consume(p, i, kind, v)
  if tok_is?(p, i, kind, v)
    i + 1
  else
    fail(p, i, json_stringify(v))
  end
end

@doc """
punct? is true when the token at `i` is the punctuator `v`.

    punct?({toks: tokens("{"), n: 1}, 0, "{") #=> true
"""
def punct?(p, i, v)
  tok_is?(p, i, :punct, v)
end

@doc """
word? is true when the token at `i` is the name `v`, as a keyword is read.

    word?({toks: tokens("on"), n: 1}, 0, "on") #=> true
"""
def word?(p, i, v)
  tok_is?(p, i, :name, v)
end

@doc """
expect steps past the punctuator `v` at `i`, or raises a parse error naming it.

    expect({toks: tokens("{ a"), n: 2}, 0, "{") #=> 1
"""
def expect(p, i, v)
  consume(p, i, :punct, v)
end

@doc """
keyword steps past the keyword `v` at `i`, or raises a parse error naming it.

    keyword({toks: tokens("on X"), n: 2}, 0, "on") #=> 1
"""
def keyword(p, i, v)
  consume(p, i, :name, v)
end

@doc """
name_at reads the name at `i`, or raises a parse error that wanted one.

    name_at({toks: tokens("a b"), n: 2}, 1) #=> "b"
    raised(() -> name_at({toks: tokens("{"), n: 1}, 0)) #=> :parse_error
"""
def name_at(p, i)
  t = tok(p, i)
  if t[:kind] == :name
    t[:value]
  else
    fail(p, i, "a name")
  end
end

@doc """
mark stamps a node with the line and column of the token at `i` when the parse asked for spans, and leaves it alone otherwise.

    mark({toks: tokens("a"), n: 1, spans: true}, 0, {name: "a"}) #=> {name: "a", at: [1, 1]}
    mark({toks: tokens("a"), n: 1, spans: false}, 0, {name: "a"}) #=> {name: "a"}
"""
def mark(p, i, node)
  if p[:spans]
    t = tok(p, i)
    assoc(node, :at, [t[:line], t[:col]])
  else
    node
  end
end

@doc """
many reads items with `item` until the punctuator `close`, answering the items and the index after `close`.

    one = (q, j) -> [name_at(q, j), j + 1]
    many({toks: tokens("a b }"), n: 3}, 0, one, "}", []) #=> [["a", "b"], 3]
"""
def many(p, i, item, close, acc)
  if punct?(p, i, close)
    [acc, i + 1]
  elsif tok(p, i)[:kind] == :eof
    fail(p, i, json_stringify(close))
  else
    got = item(p, i)
    many(p, second(got), item, close, append(acc, [first(got)]))
  end
end

@doc """
one_or_more reads a bracketed list that must hold at least one item, as GraphQL requires of every bracket it opens.

    one = (q, j) -> [name_at(q, j), j + 1]
    one_or_more({toks: tokens("(a b)"), n: 4}, 0, "(", one, ")") #=> [["a", "b"], 4]
    raised(() -> one_or_more({toks: tokens("()"), n: 2}, 0, "(", one, ")")) #=> :parse_error
"""
def one_or_more(p, i, open, item, close)
  j = expect(p, i, open)
  if punct?(p, j, close)
    fail(p, j, "an item before #{json_stringify(close)}")
  end
  many(p, j, item, close, [])
end

@doc """
optional_list reads a bracketed list when one opens at `i`, and answers an empty list without moving otherwise.

    one = (q, j) -> [name_at(q, j), j + 1]
    optional_list({toks: tokens("a"), n: 1}, 0, "(", one, ")") #=> [[], 0]
"""
def optional_list(p, i, open, item, close)
  if punct?(p, i, open)
    one_or_more(p, i, open, item, close)
  else
    [[], i]
  end
end

@doc """
document_of reads every definition from `i` to the end into a document, refusing an empty one.

    t = tokens("{ a } { b }")
    length(document_of({toks: t, n: length(t), spans: false}, 0, [])[:definitions]) #=> 2
"""
def document_of(p, i, acc)
  if i >= p[:n]
    if is_empty(acc)
      fail(p, i, "a definition")
    end
    {kind: :document, definitions: acc}
  else
    got = definition(p, i)
    document_of(p, second(got), append(acc, [first(got)]))
  end
end

@doc """
definition reads the one definition at `i`, choosing operation, fragment, extension or type system by its first token.

    t = tokens("scalar D")
    first(definition({toks: t, n: length(t), spans: false}, 0))[:kind] #=> :scalar
"""
def definition(p, i)
  t = tok(p, i)
  v = t[:value]
  if punct?(p, i, "{")
    operation(p, i)
  elsif t[:kind] == :string
    type_system(p, i + 1, v)
  elsif t[:kind] != :name
    fail(p, i, "a definition")
  elsif member?(v, %w[query mutation subscription])
    operation(p, i)
  elsif v == "fragment"
    fragment_definition(p, i)
  elsif v == "extend"
    extension(p, i + 1)
  else
    type_system(p, i, nil)
  end
end

@doc """
operation reads an operation at `i`, a bare selection set being an anonymous query.

    t = tokens("query Q { a }")
    p = {toks: t, n: length(t), spans: false}
    first(operation(p, 0))[:name] #=> "Q"
    second(operation(p, 0)) #=> 5
"""
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
    op = keyword_of(tok(p, i)[:value])
    j = i + 1
    name = if tok(p, j)[:kind] == :name
      tok(p, j)[:value]
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

@doc """
keyword_of turns an operation keyword into its operation type, nil for any other word.

    keyword_of("mutation") #=> :mutation
    keyword_of("type") #=> nil
"""
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

@doc """
variable_definition reads one `$name: Type = default` of an operation's variable list.

    t = tokens("$x: Int = 1")
    v = first(variable_definition({toks: t, n: length(t), spans: false}, 0))
    v[:name] #=> "x"
    v[:default] #=> {kind: :int, text: "1"}
"""
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

@doc """
default_value reads the constant after `=` when one is there, and answers nil without moving otherwise.

    t = tokens("= 1")
    default_value({toks: t, n: length(t), spans: false}, 0) #=> [{kind: :int, text: "1"}, 2]
"""
def default_value(p, i)
  if punct?(p, i, "=")
    value(p, i + 1, true)
  else
    [nil, i]
  end
end

@doc """
type_ref reads a type reference: a name, a list of a type, either made non-null by `!`.

    t = tokens("[Int]!")
    first(type_ref({toks: t, n: length(t)}, 0)) #=> {kind: :non_null, of: {kind: :list_of, of: {kind: :named, name: "Int"}}}
"""
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

@doc """
directives reads the directives at `i`, none being an empty list; `constant` refuses variables in their arguments.

    t = tokens("@a @b(x: 1)")
    map((d) -> d[:name], first(directives({toks: t, n: length(t), spans: false}, 0, true))) #=> ["a", "b"]
"""
def directives(p, i, constant)
  directives_from(p, i, constant, [])
end

@doc """
directives_from is the loop of `directives`, adding each directive read to `acc`.

    t = tokens("@a")
    directives_from({toks: t, n: length(t), spans: false}, 0, false, []) #=> [[{name: "a", arguments: []}], 2]
"""
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

@doc """
arguments reads a parenthesized argument list when one opens at `i`, and an empty list otherwise.

    t = tokens("(x: 1)")
    arguments({toks: t, n: length(t), spans: false}, 0, false) #=> [[{name: "x", value: {kind: :int, text: "1"}}], 5]
"""
def arguments(p, i, constant)
  optional_list(p, i, "(", (q, j) -> argument(q, j, constant), ")")
end

@doc """
argument reads one `name: value` argument.

    t = tokens("x: true")
    argument({toks: t, n: length(t), spans: false}, 0, false) #=> [{name: "x", value: {kind: :boolean, value: true}}, 3]
"""
def argument(p, i, constant)
  name = name_at(p, i)
  j = expect(p, i + 1, ":")
  v = value(p, j, constant)
  [mark(p, i, {name:, value: first(v)}), second(v)]
end

@doc """
value reads one input value at `i`; when `constant` is true a variable is a parse error, as in a default or a schema directive.

    t = tokens("[1, B]")
    first(value({toks: t, n: length(t)}, 0, true)) #=> {kind: :list, items: [{kind: :int, text: "1"}, {kind: :enum, name: "B"}]}
    v = tokens("$x")
    raised(() -> value({toks: v, n: length(v)}, 0, true)) #=> :parse_error
"""
def value(p, i, constant)
  t = tok(p, i)
  k = t[:kind]
  v = t[:value]
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

@doc """
object_field reads one `name: value` field of an input object value.

    t = tokens("a: null")
    object_field({toks: t, n: length(t)}, 0, true) #=> [{name: "a", value: {kind: :null}}, 3]
"""
def object_field(p, i, constant)
  name = name_at(p, i)
  j = expect(p, i + 1, ":")
  v = value(p, j, constant)
  [{name:, value: first(v)}, second(v)]
end

@doc """
selection_set reads a braced, non-empty list of selections.

    t = tokens("{ a }")
    second(selection_set({toks: t, n: length(t), spans: false}, 0)) #=> 3
"""
def selection_set(p, i)
  one_or_more(p, i, "{", selection, "}")
end

@doc """
selection reads one selection at `i`: a field, a fragment spread or an inline fragment.

    t = tokens("... on T { a }")
    first(selection({toks: t, n: length(t), spans: false}, 0))[:kind] #=> :inline
"""
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

@doc """
spread reads a named fragment spread `...Name` and its directives.

    t = tokens("...F @d")
    first(spread({toks: t, n: length(t), spans: false}, 0)) #=> {kind: :spread, name: "F", directives: [{name: "d", arguments: []}]}
"""
def spread(p, i)
  name = name_at(p, i + 1)
  dirs = directives(p, i + 2, false)
  [mark(p, i, {kind: :spread, name:, directives: first(dirs)}), second(dirs)]
end

@doc """
inline_fragment reads `... on Type { ... }`, the type condition being optional.

    t = tokens("... on T { a }")
    first(inline_fragment({toks: t, n: length(t), spans: false}, 0))[:on] #=> "T"
"""
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

@doc """
field reads one field selection: its alias, name, arguments, directives and sub-selections.

    t = tokens("x: a(n: 1)")
    f = first(field({toks: t, n: length(t), spans: false}, 0))
    f[:alias] #=> "x"
    f[:name] #=> "a"
"""
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

@doc """
fragment_definition reads `fragment Name on Type { ... }`, refusing a fragment named `on`.

    t = tokens("fragment F on T { a }")
    first(fragment_definition({toks: t, n: length(t), spans: false}, 0))[:on] #=> "T"
"""
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

@doc """
type_system reads one type system definition at `i` and attaches the description that came before it.

    t = tokens("scalar D")
    first(type_system({toks: t, n: length(t), spans: false}, 0, "d")) #=> {kind: :scalar, name: "D", directives: [], description: "d", extend: false}
"""
def type_system(p, i, description)
  v = tok(p, i)[:value]
  if tok(p, i)[:kind] != :name
    fail(p, i, "a type system definition")
  end
  got = type_body(p, i, v)
  if v == "schema" and is_empty(first(got)[:operations])
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

@doc """
extension reads the definition after `extend`, refusing one that adds nothing.

    t = tokens("type T @k")
    first(extension({toks: t, n: length(t), spans: false}, 0))[:extend] #=> true
"""
def extension(p, i)
  v = tok(p, i)[:value]
  if v == "directive" or tok(p, i)[:kind] != :name
    fail(p, i, "a type system extension")
  end
  got = type_body(p, i, v)
  node = first(got)
  if not extends_something?(node)
    fail(p, second(got), "directives or definitions in the extension")
  end
  [mark(p, i, assoc(dissoc(node, :description), :extend, true)), second(got)]
end

@doc """
extends_something? is true when an extension node adds at least one directive, operation, interface, field, member or value.

    extends_something?({kind: :scalar, directives: []}) #=> false
    extends_something?({kind: :object, fields: [{name: "a"}]}) #=> true
"""
def extends_something?(node)
  any?(
    (k) -> not is_empty(get(node, k)),
    filter(
      (k) -> get(node, k) != nil,
      %i[directives operations interfaces fields members values]
    )
  )
end

@doc """
type_body reads the body of a type system definition whose keyword `v` sits at `i`.

    t = tokens("enum E { A }")
    first(type_body({toks: t, n: length(t), spans: false}, 0, "enum"))[:kind] #=> :enum
"""
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

@doc """
schema_definition reads `schema { query: Q ... }`, the root operation types a schema names.

    t = tokens("schema { query: Q }")
    first(schema_definition({toks: t, n: length(t), spans: false}, 0))[:operations] #=> [{operation: :query, type: "Q"}]
"""
def schema_definition(p, i)
  dirs = directives(p, i + 1, true)
  ops = optional_list(p, second(dirs), "{", root_operation, "}")
  [
    {kind: :schema, directives: first(dirs), operations: first(ops)},
    second(ops)
  ]
end

@doc """
root_operation reads one `query: Type` entry of a schema definition.

    t = tokens("query: Q")
    root_operation({toks: t, n: length(t)}, 0) #=> [{operation: :query, type: "Q"}, 3]
"""
def root_operation(p, i)
  v = tok(p, i)[:value]
  if tok(p, i)[:kind] != :name or keyword_of(v).nil?
    fail(p, i, "query, mutation or subscription")
  end
  j = expect(p, i + 1, ":")
  [{operation: keyword_of(v), type: name_at(p, j)}, j + 1]
end

@doc """
object_like reads an object type or an interface, which share one shape: interfaces, directives and fields.

    t = tokens("interface I { a: Int }")
    first(object_like({toks: t, n: length(t), spans: false}, 0, "interface"))[:kind] #=> :interface
"""
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

@doc """
separated_names reads names joined by `sep`, a leading `sep` allowed, as in `implements & A & B`.

    t = tokens("& A & B")
    separated_names({toks: t, n: length(t)}, 0, "&") #=> [["A", "B"], 4]
"""
def separated_names(p, i, sep)
  j = if punct?(p, i, sep)
    i + 1
  else
    i
  end
  more_names(p, j + 1, sep, [name_at(p, j)])
end

@doc """
more_names is the loop of `separated_names`, adding each name after a `sep` to `acc`.

    t = tokens("| B | C")
    more_names({toks: t, n: length(t)}, 0, "|", ["A"]) #=> [["A", "B", "C"], 4]
"""
def more_names(p, i, sep, acc)
  if punct?(p, i, sep)
    more_names(p, i + 2, sep, append(acc, [name_at(p, i + 1)]))
  else
    [acc, i]
  end
end

@doc """
field_definition reads one field of an object or interface type, with its description and arguments.

    t = tokens("\"d\" a(x: Int): Int")
    f = first(field_definition({toks: t, n: length(t), spans: false}, 0))
    f[:description] #=> "d"
    f[:type] #=> {kind: :named, name: "Int"}
"""
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

@doc """
description_at reads the description string at `i` when there is one, and nil without moving otherwise.

    t = tokens("\"d\" a")
    description_at({toks: t, n: length(t)}, 0) #=> ["d", 1]
    description_at({toks: t, n: length(t)}, 1) #=> [nil, 1]
"""
def description_at(p, i)
  t = tok(p, i)
  if t[:kind] == :string
    [t[:value], i + 1]
  else
    [nil, i]
  end
end

@doc """
input_value reads one argument definition or input field: description, name, type, default and directives.

    t = tokens("x: Int = 1")
    first(input_value({toks: t, n: length(t), spans: false}, 0))[:default] #=> {kind: :int, text: "1"}
"""
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

@doc """
union_definition reads `union U = A | B`, its members optional so an extension can add directives alone.

    t = tokens("union U = A | B")
    union_definition({toks: t, n: length(t), spans: false}, 0) #=> [{kind: :union, name: "U", directives: [], members: ["A", "B"]}, 6]
"""
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

@doc """
enum_definition reads `enum E { A B }` and its values.

    t = tokens("enum E { A B }")
    e = first(enum_definition({toks: t, n: length(t), spans: false}, 0))
    map((v) -> v[:name], e[:values]) #=> ["A", "B"]
"""
def enum_definition(p, i)
  name = name_at(p, i + 1)
  dirs = directives(p, i + 2, true)
  values = optional_list(p, second(dirs), "{", enum_value, "}")
  [
    {kind: :enum, name:, directives: first(dirs), values: first(values)},
    second(values)
  ]
end

@doc """
enum_value reads one enum value, refusing `true`, `false` and `null` as its name.

    t = tokens("A @deprecated")
    second(enum_value({toks: t, n: length(t), spans: false}, 0)) #=> 3
    u = tokens("null")
    raised(() -> enum_value({toks: u, n: 1, spans: false}, 0)) #=> :parse_error
"""
def enum_value(p, i)
  desc = description_at(p, i)
  j = second(desc)
  name = name_at(p, j)
  if member?(name, %w[true false null])
    fail(p, j, "an enum value other than true, false or null")
  end
  dirs = directives(p, j + 1, true)
  [
    mark(p, j, {name:, description: first(desc), directives: first(dirs)}),
    second(dirs)
  ]
end

@doc """
directive_definition reads `directive @name(...) repeatable on LOCATION | ...`, refusing a location GraphQL does not define.

    t = tokens("directive @k repeatable on FIELD | QUERY")
    d = first(directive_definition({toks: t, n: length(t), spans: false}, 0))
    d[:repeatable] #=> true
    d[:locations] #=> ["FIELD", "QUERY"]
"""
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

@doc """
pad is the indentation of nesting depth `ind`, two spaces a level.

    pad(2) #=> "    "
"""
def pad(ind)
  repeated("  ", ind)
end

@doc """
deeper is the next nesting depth, staying nil for the compact one-line layout.

    deeper(1) #=> 2
    deeper(nil) #=> nil
"""
def deeper(ind)
  maybe(ind, nil, (i) -> i + 1)
end

@doc """
nl is the break between items: a newline and indent at depth `ind`, or in the compact layout a space when `space` asks for one.

    nl(1, false) #=> "\n  "
    nl(nil, true) #=> " "
"""
def nl(ind, space)
  if ind.nil?
    if space
      " "
    else
      ""
    end
  else
    join_lines(["", pad(ind)])
  end
end

@doc """
commas writes items between `open` and `close`, comma separated, one per line with a trailing comma when indented.

    commas(nil, "(", ")", ["a", "b"], (_i, x) -> x) #=> "(a, b)"
    commas(0, "[", "]", ["a"], (_i, x) -> x) #=> "[\n  a,\n]"
"""
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

@doc """
curly writes items as a braced block, one per line when indented and space separated when compact.

    curly(nil, ["a", "b"], (_i, x) -> x) #=> "{ a b }"
    curly(0, ["a"], (_i, x) -> x) #=> "{\n  a\n}"
"""
def curly(ind, items, f)
  if is_empty(items)
    "{}"
  else
    inner = deeper(ind)
    body = join(map((x) -> f(inner, x), items), nl(inner, true))
    "{#{nl(inner, true)}#{body}#{nl(ind, true)}}"
  end
end

@doc """
control_chars pairs each control character a quoted string must escape, tab aside, with its code.

    length(control_chars) #=> 31
    second(first(control_chars)) #=> 0
"""
def control_chars()
  map(
    (k) -> [json_read("\"\\u#{hex4(k)}\""), k],
    filter((k) -> k != 9, range(0, 32))
  )
end

@doc """
quoted writes text as a one-line GraphQL string, escaping quotes, backslashes and control characters.

    quoted("a\"b") #=> "\"a\\\"b\""
    quoted("x\ny") #=> "\"x\\ny\""
"""
def quoted(text)
  escaped = replace(replace(text, "\\", "\\\\"), "\"", "\\\"")
  named = [
    [line_break, "\\n"],
    ["\r", "\\r"],
    ["\u{8}", "\\b"],
    ["\u{c}", "\\f"]
  ]
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

@doc """
byte_length counts the UTF-8 bytes of text, the measure apollo-compiler uses to break a long block string.

    byte_length("aé") #=> 3
"""
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

@doc """
block_able? is true when text survives a round trip as a block string: no carriage return, no blank first or last line, no common indent.

    block_able?("a\nb") #=> true
    block_able?(" a") #=> false
"""
def block_able?(text)
  lines = split(text, line_break)
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

@doc """
block writes text as a block string, on its own lines at depth `ind` when it is long or spans lines.

    block(0, "hi") #=> "\"\"\"hi\"\"\""
    block(0, "a\nb") #=> "\"\"\"\na\nb\n\"\"\""
"""
def block(ind, text)
  multi = contains?(text, line_break) or
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
          line_break
        else
          "#{nl(ind, false)}#{esc(line)}"
        end
      end,
      split(text, line_break)
    )
    "\"\"\"#{join(lines, "")}#{nl(ind, false)}\"\"\""
  end
end

@doc """
string_text picks the block or quoted form for a string the way apollo-compiler does: block for a description or a multi-line value that allows it.

    string_text(0, true, "d") #=> "\"\"\"d\"\"\""
    string_text(nil, true, "d") #=> "\"d\""
"""
def string_text(ind, described, text)
  if ind != nil and
      (described or contains?(text, line_break)) and
      block_able?(text)
    block(ind, text)
  else
    quoted(text)
  end
end

@doc """
description_text writes a description followed by its break, or nothing when there is none.

    description_text(0, "d") #=> "\"\"\"d\"\"\"\n"
    description_text(0, nil) #=> ""
"""
def description_text(ind, d)
  if d.nil?
    ""
  else
    "#{string_text(ind, true, d)}#{nl(ind, true)}"
  end
end

@doc """
type_text writes a type reference back as GraphQL.

    type_text({kind: :non_null, of: {kind: :list_of, of: {kind: :named, name: "Int"}}}) #=> "[Int]!"
"""
def type_text(t)
  k = t[:kind]
  if k == :named
    t[:name]
  elsif k == :list_of
    "[#{type_text(t[:of])}]"
  else
    "#{type_text(t[:of])}!"
  end
end

@doc """
value_text writes an input value back as GraphQL at depth `ind`.

    value_text(nil, {kind: :list, items: [{kind: :int, text: "1"}, {kind: :var, name: "x"}]}) #=> "[1, $x]"
"""
def value_text(ind, v)
  k = v[:kind]
  if k == :null
    "null"
  elsif k == :boolean
    if v[:value]
      "true"
    else
      "false"
    end
  elsif k == :enum
    v[:name]
  elsif k == :var
    "$#{v[:name]}"
  elsif k == :int or k == :float
    v[:text]
  elsif k == :string
    string_text(ind, false, v[:value])
  elsif k == :list
    commas(ind, "[", "]", v[:items], value_text)
  else
    commas(
      ind,
      "{",
      "}",
      v[:fields],
      (i, f) -> "#{f[:name]}: #{value_text(i, f[:value])}"
    )
  end
end

@doc """
arguments_text writes a field's or directive's arguments on one line, nothing when there are none.

    arguments_text([{name: "x", value: {kind: :int, text: "1"}}]) #=> "(x: 1)"
    arguments_text([]) #=> ""
"""
def arguments_text(args)
  if is_empty(args)
    ""
  else
    commas(
      nil,
      "(",
      ")",
      args,
      (i, a) -> "#{a[:name]}: #{value_text(i, a[:value])}"
    )
  end
end

@doc """
directives_text writes directives, each after a space, to follow the thing they annotate.

    directives_text([{name: "skip", arguments: [{name: "if", value: {kind: :boolean, value: true}}]}]) #=> " @skip(if: true)"
"""
def directives_text(dirs)
  join(map((d) -> " @#{d[:name]}#{arguments_text(d[:arguments])}", dirs), "")
end

@doc """
default_text writes ` = value` for a default, nothing when there is none.

    default_text(nil, {kind: :null}) #=> " = null"
    default_text(nil, nil) #=> ""
"""
def default_text(ind, dv)
  if dv.nil?
    ""
  else
    " = #{value_text(ind, dv)}"
  end
end

@doc """
variables_text writes an operation's variable definitions on one line, nothing when there are none.

    op = first(parse("query($x: Int = 1) { a }")[:definitions])
    variables_text(op[:variables]) #=> "($x: Int = 1)"
"""
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
        "$#{x[:name]}: #{type_text(x[:type])}#{default_text(i, x[:default])}#{directives_text(x[:directives])}"
      end
    )
  end
end

@doc """
input_value_text writes one argument definition or input field with its description, default and directives.

    input_value_text(nil, {name: "x", description: nil, type: {kind: :named, name: "Int"}, default: nil, directives: []}) #=> "x: Int"
"""
def input_value_text(ind, x)
  "#{description_text(ind, x[:description])}#{x[:name]}: #{type_text(x[:type])}#{default_text(ind, x[:default])}#{directives_text(x[:directives])}"
end

@doc """
arguments_definition_text writes a field's argument definitions, one per line only when one carries a description or directive.

    t = first(parse("type T { a(x: Int): Int }")[:definitions])
    arguments_definition_text(0, first(t[:fields])[:arguments]) #=> "(x: Int)"
"""
def arguments_definition_text(ind, args)
  if is_empty(args)
    ""
  elsif any?(
    (a) -> a[:description] != nil or not is_empty(a[:directives]),
    args
  )
    commas(ind, "(", ")", args, input_value_text)
  else
    commas(nil, "(", ")", args, input_value_text)
  end
end

@doc """
field_definition_text writes one field of an object or interface type.

    t = first(parse("type T { a(x: Int): Int }")[:definitions])
    field_definition_text(0, first(t[:fields])) #=> "a(x: Int): Int"
"""
def field_definition_text(ind, f)
  "#{description_text(ind, f[:description])}#{f[:name]}#{arguments_definition_text(ind, f[:arguments])}: #{type_text(f[:type])}#{directives_text(f[:directives])}"
end

@doc """
enum_value_text writes one enum value with its description and directives.

    enum_value_text(0, {name: "A", description: nil, directives: []}) #=> "A"
"""
def enum_value_text(ind, v)
  "#{description_text(ind, v[:description])}#{v[:name]}#{directives_text(v[:directives])}"
end

@doc """
selection_text writes one field, spread or inline fragment with everything nested under it.

    op = first(parse("{ x: a(n: 1) { b } }")[:definitions])
    selection_text(nil, first(op[:selections])) #=> "x: a(n: 1) { b }"
"""
def selection_text(ind, sel)
  k = sel[:kind]
  if k == :field
    head = if sel[:alias].nil?
      ""
    else
      "#{sel[:alias]}: "
    end
    "#{head}#{sel[:name]}#{arguments_text(sel[:arguments])}#{directives_text(sel[:directives])}#{selections_suffix(ind, sel[:selections])}"
  elsif k == :spread
    "...#{sel[:name]}#{directives_text(sel[:directives])}"
  else
    head = if sel[:on].nil?
      "..."
    else
      "... on #{sel[:on]}"
    end
    "#{head}#{directives_text(sel[:directives])} #{curly(ind, sel[:selections], selection_text)}"
  end
end

@doc """
selections_suffix writes a field's sub-selections after a space, nothing for a leaf field.

    selections_suffix(nil, first(parse("{ a }")[:definitions])[:selections]) #=> " { a }"
    selections_suffix(nil, []) #=> ""
"""
def selections_suffix(ind, sels)
  if is_empty(sels)
    ""
  else
    " #{curly(ind, sels, selection_text)}"
  end
end

@doc """
block_suffix writes a definition's braced members with `f` after a space, nothing when there are none.

    block_suffix(nil, ["a"], (_i, x) -> x) #=> " { a }"
    block_suffix(nil, [], (_i, x) -> x) #=> ""
"""
def block_suffix(ind, items, f)
  if is_empty(items)
    ""
  else
    " #{curly(ind, items, f)}"
  end
end

@doc """
extend_prefix starts a type system definition: `extend ` for an extension, its description otherwise.

    extend_prefix(0, {extend: true}) #=> "extend "
    extend_prefix(0, {extend: false, description: nil}) #=> ""
"""
def extend_prefix(ind, d)
  if d[:extend]
    "extend "
  else
    description_text(ind, d[:description])
  end
end

@doc """
definition_text writes one definition; a plain query writes as its bare selection set only when it leads the document.

    definition_text(nil, first(parse("type T { a: Int }")[:definitions]), true) #=> "type T { a: Int }"
    definition_text(nil, first(parse("query { a }")[:definitions]), false) #=> "query { a }"
"""
def definition_text(ind, d, leading)
  k = d[:kind]
  dirs = directives_text(d[:directives])
  if k == :operation
    shorthand = leading and
      d[:operation] == :query and
      d[:name].nil? and
      is_empty(d[:variables]) and
      is_empty(d[:directives])
    body = curly(ind, d[:selections], selection_text)
    if shorthand
      body
    else
      named = if d[:name].nil?
        ""
      else
        " #{d[:name]}"
      end
      "#{d[:operation]}#{named}#{variables_text(d[:variables])}#{dirs} #{body}"
    end
  elsif k == :fragment
    "fragment #{d[:name]} on #{d[:on]}#{dirs} #{curly(ind, d[:selections], selection_text)}"
  elsif k == :directive
    rep = if d[:repeatable]
      " repeatable"
    else
      ""
    end
    "#{description_text(ind, d[:description])}directive @#{d[:name]}#{arguments_definition_text(ind, d[:arguments])}#{rep} on #{join(d[:locations], " | ")}"
  elsif k == :schema
    ops = d[:operations]
    body = if d[:extend] and is_empty(ops)
      ""
    else
      " #{curly(ind, ops, (_i, o) -> "#{o[:operation]}: #{o[:type]}")}"
    end
    "#{extend_prefix(ind, d)}schema#{dirs}#{body}"
  elsif k == :scalar
    "#{extend_prefix(ind, d)}scalar #{d[:name]}#{dirs}"
  elsif k == :object or k == :interface
    word = if k == :object
      "type"
    else
      "interface"
    end
    ifaces = if is_empty(d[:interfaces])
      ""
    else
      " implements #{join(d[:interfaces], " & ")}"
    end
    "#{extend_prefix(ind, d)}#{word} #{d[:name]}#{ifaces}#{dirs}#{block_suffix(ind, d[:fields], field_definition_text)}"
  elsif k == :union
    members = if is_empty(d[:members])
      ""
    else
      " = #{join(d[:members], " | ")}"
    end
    "#{extend_prefix(ind, d)}union #{d[:name]}#{dirs}#{members}"
  elsif k == :enum
    "#{extend_prefix(ind, d)}enum #{d[:name]}#{dirs}#{block_suffix(ind, d[:values], enum_value_text)}"
  else
    "#{extend_prefix(ind, d)}input #{d[:name]}#{dirs}#{block_suffix(ind, d[:fields], input_value_text)}"
  end
end

@doc """
document_text writes every definition of a document, a blank line apart, or on one line when compact.

    document_text(nil, parse("{ a } { b }")) #=> "{ a } query { b }"
    document_text(0, parse("scalar D")) #=> "scalar D\n"
"""
def document_text(ind, doc)
  defs = doc[:definitions]
  texts = map((i) -> definition_text(ind, defs[i], i == 0), range(length(defs)))
  if ind.nil?
    join(texts, " ")
  elsif is_empty(texts)
    ""
  else
    unlines([join(texts, unlines(["", ""]))])
  end
end

@doc """
parse: GraphQL SDL or operation text to a document tree.

    first(parse("query Q { a }")[:definitions])[:name] #=> "Q"
    raised(() -> parse("{ a ")) #=> :parse_error
"""
def parse(text, opts?)
  opts = checked(opts, [:spans])
  toks = tokens(text)
  p = {toks:, n: length(toks), spans: get_or(opts, :spans, false)}
  document_of(p, 0, [])
end

@doc """
render: a document tree to canonical GraphQL text.

    render(parse("{ a }")) #=> "{\n  a\n}\n"
"""
def render(document, format?, opts?)
  checked(opts, [])
  f = format or :graphql
  if f == :graphql
    document_text(0, document)
  elsif f == :compact
    document_text(nil, document)
  elsif f == :table
    table_text(document)
  else
    raise(
      :bad_option,
      "render: the format must be :graphql, :compact or :table, got #{f}"
    )
  end
end

@doc """
builtin_sdl is the SDL every schema holds without writing it: the five scalars, the four builtin directives and the introspection types.

    first(parse(builtin_sdl)[:definitions])[:name] #=> "Int"
"""
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
    line_break
  )
end

@doc """
finding is one validation result: the rule broken, a message, and the node's position when the parse kept spans.

    finding("type-unique", "the type T is defined more than once", {at: [1, 2]}) #=> {rule: "type-unique", message: "the type T is defined more than once", at: [1, 2]}
"""
def finding(rule, message, node)
  {rule:, message:, at: node[:at]}
end

@doc """
type_kinds lists the kinds of named type a schema can define.

    type_kinds #=> [:scalar, :object, :interface, :union, :enum, :input]
"""
def type_kinds()
  %i[scalar object interface union enum input]
end

@doc """
definitions_of is a document's definitions, none for a missing schema.

    definitions_of(nil) #=> []
    length(definitions_of(parse("scalar D"))) #=> 1
"""
def definitions_of(schema)
  maybe(schema, [], (s) -> s[:definitions])
end

@doc """
merged folds an extension into its base definition, appending each member list the extension carries.

    merged({fields: [1], directives: []}, {fields: [2]}) #=> {fields: [1, 2], directives: []}
"""
def merged(base, ext)
  reduce(
    (acc, k) -> assoc(acc, k, append(get(acc, k), get(ext, k))),
    base,
    filter(
      (k) -> get(ext, k) != nil,
      %i[directives operations interfaces fields members values]
    )
  )
end

@doc """
add_definition indexes one type, directive or schema definition, noting a finding when its name is already taken.

    st = {types: {}, directives: {}, schema: nil, problems: []}
    d = first(parse("scalar D")[:definitions])
    add_definition(st, d)[:types]["D"][:kind] #=> :scalar
    map((f) -> f[:rule], add_definition(add_definition(st, d), d)[:problems]) #=> ["type-unique"]
"""
def add_definition(state, d)
  k = d[:kind]
  name = d[:name]
  if k == :directive
    previous = get(state[:directives], name)
    if previous != nil and not previous[:builtin]
      note(
        state,
        finding(
          "directive-unique",
          "the directive @#{name} is defined more than once",
          d
        )
      )
    else
      assoc(state, :directives, assoc(state[:directives], name, d))
    end
  elsif k == :schema
    if state[:schema] != nil
      note(
        state,
        finding("schema-unique", "the schema is defined more than once", d)
      )
    else
      assoc(state, :schema, d)
    end
  else
    previous = get(state[:types], name)
    if previous.nil?
      assoc(state, :types, assoc(state[:types], name, d))
    else
      note(
        state,
        finding("type-unique", "the type #{name} is defined more than once", d)
      )
    end
  end
end

@doc """
add_extension merges an extension into the type it extends, noting a finding when that type is missing or of another kind.

    st = {types: {}, directives: {}, schema: nil, schema_ext: [], problems: []}
    ext = first(parse("extend type T @k")[:definitions])
    map((f) -> f[:rule], add_extension(st, ext)[:problems]) #=> ["extension-orphan"]
"""
def add_extension(state, d)
  k = d[:kind]
  if k == :schema
    if state[:schema].nil?
      assoc(state, :schema_ext, append(state[:schema_ext], [d]))
    else
      assoc(state, :schema, merged(state[:schema], d))
    end
  else
    name = d[:name]
    base = get(state[:types], name)
    if base.nil?
      note(
        state,
        finding(
          "extension-orphan",
          "the extended type #{name} is not defined",
          d
        )
      )
    elsif base[:kind] != k
      note(
        state,
        finding(
          "extension-kind",
          "#{name} is a #{base[:kind]}, extended as a #{k}",
          d
        )
      )
    else
      assoc(state, :types, assoc(state[:types], name, merged(base, d)))
    end
  end
end

@doc """
note records a finding in the indexing state.

    note({problems: []}, {rule: "r"}) #=> {problems: [{rule: "r"}]}
"""
def note(state, f)
  push_at(state, :problems, f)
end

@doc """
builtins are the builtin definitions, each flagged builtin so a user may redefine a builtin directive.

    length(builtins) #=> 17
    first(builtins)[:builtin] #=> true
"""
def builtins()
  map((d) -> assoc(d, :builtin, true), parse(builtin_sdl)[:definitions])
end

@doc """
implicit_roots finds the root operation types by their default names when a schema declares no `schema` block.

    implicit_roots({"Query" => {kind: :object}}) #=> [{operation: :query, type: "Query"}]
"""
def implicit_roots(types)
  filter(
    (o) -> o[:type] != nil,
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
      %i[query mutation subscription]
    )
  )
end

@doc """
schema_index indexes a schema document's types, directives and roots, with the findings met while indexing.

    schema_index(parse("type Query { a: Int }"))[:roots] #=> {query: "Query"}
"""
def schema_index(schema)
  defs = definitions_of(schema)
  user = filter((d) -> d[:kind] != :operation and d[:kind] != :fragment, defs)
  state = {types: {}, directives: {}, schema: nil, schema_ext: [], problems: []}
  state = reduce(add_definition, state, builtins)
  state = reduce(add_definition, state, filter((d) -> not d[:extend], user))
  state = reduce(add_extension, state, filter((d) -> d[:extend], user))
  executable = filter(
    (d) -> d[:kind] == :operation or d[:kind] == :fragment,
    defs
  )
  state = reduce(
    fn(st, d)
      note(
        st,
        finding(
          "type-system-only",
          "a schema holds no #{d[:kind]} definition",
          d
        )
      )
    end,
    state,
    executable
  )
  state = if state[:schema].nil? and not is_empty(state[:schema_ext])
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
      state[:schema_ext]
    )
  else
    state
  end
  roots = if state[:schema].nil?
    implicit_roots(state[:types])
  else
    state[:schema][:operations]
  end
  assoc(
    assoc(
      state,
      :roots,
      reduce((m, o) -> assoc(m, o[:operation], o[:type]), {}, roots)
    ),
    :user,
    user
  )
end

@doc """
type_named is the definition of the type `name` in an indexed schema, nil when it has none.

    type_named(schema_of("type Query { a: Int }"), "Query")[:kind] #=> :object
"""
def type_named(s, name)
  get(s[:types], name)
end

@doc """
base_name is the named type under any list and non-null wrapping.

    base_name({kind: :non_null, of: {kind: :list_of, of: {kind: :named, name: "T"}}}) #=> "T"
"""
def base_name(t)
  if t[:kind] == :named
    t[:name]
  else
    base_name(t[:of])
  end
end

@doc """
kind_in: The kind of the type `name` in a table of types by name, nil when the table has no such type.

    kind_in({"Q" => {kind: :object}}, "Q") #=> :object
"""
def kind_in(types, name)
  t = get(types, name)
  if t.nil?
    nil
  else
    t[:kind]
  end
end

@doc """
kind_of is the kind of the type `name` in an indexed schema, nil when it has none.

    kind_of(schema_of("type Query { a: Int }"), "Int") #=> :scalar
"""
def kind_of(s, name)
  kind_in(s[:types], name)
end

@doc """
input_kind? is true for the kinds an argument, input field or variable may have.

    input_kind?(:input) #=> true
    input_kind?(:object) #=> false
"""
def input_kind?(k)
  member?(k, %i[scalar enum input])
end

@doc """
output_kind? is true for the kinds a field may have.

    output_kind?(:union) #=> true
    output_kind?(:input) #=> false
"""
def output_kind?(k)
  member?(k, %i[scalar object interface union enum])
end

@doc """
composite? is true for the kinds that have fields to select.

    composite?(:interface) #=> true
    composite?(:enum) #=> false
"""
def composite?(k)
  member?(k, %i[object interface union])
end

@doc """
by_name finds the item named `name` in a list of named things, nil when none is.

    by_name([{name: "a"}, {name: "b"}], "b") #=> {name: "b"}
"""
def by_name(xs, name)
  find(xs, (x) -> x[:name] == name)
end

@doc """
duplicates lists, once each, the names that occur more than once.

    duplicates(["a", "b", "a"]) #=> ["a"]
"""
def duplicates(names)
  distinct(filter((n) -> length(filter((m) -> m == n, names)) > 1, names))
end

@doc """
schema_problems gathers every finding of an indexed schema: indexing, each definition and the roots.

    s = schema_of("type Query { a: Nope }")
    map((f) -> f[:message], schema_problems(s)) #=> ["Query.a names the undefined type Nope"]
"""
def schema_problems(s)
  user = s[:user]
  append(
    s[:problems],
    retsu::flat_map(user, (d) -> definition_problems(s, d)),
    root_problems(s)
  )
end

@doc """
root_problems finds each root operation type that is not an object type.

    s = schema_of("schema { query: E } enum E { A }")
    map((f) -> f[:message], root_problems(s)) #=> ["the query root E is not an object type"]
"""
def root_problems(s)
  retsu::flat_map(
    map_entries(s[:roots]),
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

@doc """
known_type_problems finds a type reference whose named type the schema does not define.

    s = schema_of("type Query { a: Int }")
    map((f) -> f[:rule], known_type_problems(s, {kind: :named, name: "Z"}, {}, "Query.z")) #=> ["type-known"]
"""
def known_type_problems(s, t, node, what)
  name = base_name(t)
  if type_named(s, name).nil?
    [finding("type-known", "#{what} names the undefined type #{name}", node)]
  else
    []
  end
end

@doc """
location_of names the directive location a type system definition sits at.

    location_of({kind: :input}) #=> "INPUT_OBJECT"
"""
def location_of(d)
  case d[:kind]
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

@doc """
definition_problems finds the faults of one type system definition: its directives and its members.

    s = schema_of("type Query { a: Int }")
    d = first(parse("type Q @nope { a: Int }")[:definitions])
    map((f) -> f[:rule], definition_problems(s, d)) #=> ["directive-known"]
"""
def definition_problems(s, d)
  k = d[:kind]
  if k == :directive
    retsu::flat_map(
      d[:arguments],
      (a) -> input_value_problems(s, a, "ARGUMENT_DEFINITION", "@#{d[:name]}")
    )
  else
    own = directive_problems(s, d[:directives], location_of(d), {}, nil)
    append(own, member_problems(s, d))
  end
end

@doc """
member_problems finds the faults of a definition's members: fields, implemented interfaces, union members, enum values or input fields.

    s = schema_of("type Query { a: Int } enum E { A }")
    d = first(parse("union Y = E")[:definitions])
    map((f) -> f[:message], member_problems(s, d)) #=> ["the union Y lists E, which is not an object type"]
"""
def member_problems(s, d)
  k = d[:kind]
  name = d[:name]
  if k == :object or k == :interface
    append(
      retsu::flat_map(d[:fields], (f) -> field_definition_problems(s, f, name)),
      retsu::flat_map(
        d[:interfaces],
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
      d[:members],
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
      d[:values],
      (v) -> directive_problems(s, v[:directives], "ENUM_VALUE", {}, nil)
    )
  elsif k == :input
    retsu::flat_map(
      d[:fields],
      (f) -> input_value_problems(s, f, "INPUT_FIELD_DEFINITION", name)
    )
  else
    []
  end
end

@doc """
field_definition_problems finds the faults of one field definition: an undefined or input type, its directives and its arguments.

    s = schema_of("type Query { a: Int } input I { n: Int }")
    f = first(first(parse("type Q { a: I }")[:definitions])[:fields])
    map((x) -> x[:message], field_definition_problems(s, f, "Q")) #=> ["Q.a has the input type I"]
"""
def field_definition_problems(s, f, owner)
  where = "#{owner}.#{f[:name]}"
  known = known_type_problems(s, f[:type], f, where)
  kind = append(
    known,
    if is_empty(known) and not output_kind?(kind_of(s, base_name(f[:type])))
      [
        finding(
          "output-type",
          "#{where} has the input type #{base_name(f[:type])}",
          f
        )
      ]
    else
      []
    end
  )
  append(
    kind,
    directive_problems(s, f[:directives], "FIELD_DEFINITION", {}, nil),
    retsu::flat_map(
      f[:arguments],
      (a) -> input_value_problems(s, a, "ARGUMENT_DEFINITION", where)
    )
  )
end

@doc """
input_value_problems finds the faults of one argument definition or input field: an undefined or output type, a default that does not fit when defaults are checked, and its directives.

    s = schema_of("type Query { a: Int } type T { c: Int }")
    a = {name: "x", type: {kind: :named, name: "T"}, default: nil, directives: []}
    map((f) -> f[:message], input_value_problems(s, a, "ARGUMENT_DEFINITION", "Query.b")) #=> ["Query.b(x) has the output type T"]
"""
def input_value_problems(s, a, location, owner)
  where = "#{owner}(#{a[:name]})"
  known = known_type_problems(s, a[:type], a, where)
  kind = append(
    known,
    if is_empty(known) and not input_kind?(kind_of(s, base_name(a[:type])))
      [
        finding(
          "input-type",
          "#{where} has the output type #{base_name(a[:type])}",
          a
        )
      ]
    else
      []
    end
  )
  defaults = if s[:defaults] and a[:default] != nil and is_empty(kind)
    value_problems(s, a[:default], a[:type], a, where, {})
  else
    []
  end
  append(
    kind,
    defaults,
    directive_problems(s, a[:directives], location, {}, nil)
  )
end

@doc """
int32? is true when an Int literal fits the 32-bit signed range GraphQL's Int allows.

    int32?("7") #=> true
    int32?("2147483648") #=> false
"""
def int32?(text)
  n = to_int(text)
  n != nil and n >= -2_147_483_648 and n <= 2_147_483_647
end

@doc """
value_problems finds where an input value does not fit the type it is given for; a variable is judged elsewhere, by its position.

    s = schema_of("type Query { a: Int }")
    t = {kind: :non_null, of: {kind: :named, name: "Int"}}
    map((f) -> f[:message], value_problems(s, {kind: :null}, t, {}, "Query.b(x)", {})) #=> ["Query.b(x) cannot be null"]
"""
def value_problems(s, v, t, node, where, vars)
  k = v[:kind]
  if k == :var
    []
  elsif t[:kind] == :non_null
    if k == :null
      [finding("value-type", "#{where} cannot be null", node)]
    else
      value_problems(s, v, t[:of], node, where, vars)
    end
  elsif k == :null
    []
  elsif t[:kind] == :list_of
    if k == :list
      retsu::flat_map(
        v[:items],
        (x) -> value_problems(s, x, t[:of], node, where, vars)
      )
    else
      value_problems(s, v, t[:of], node, where, vars)
    end
  else
    named_value_problems(s, v, t[:name], node, where, vars)
  end
end

@doc """
named_value_problems judges a value against one named type: the builtin scalars by their literal kinds, an enum by its values, an input object by its fields.

    s = schema_of("type Query { a: Int }")
    map((f) -> f[:message], named_value_problems(s, {kind: :string, value: "s"}, "Int", {}, "Query.b(x)", {})) #=> ["Query.b(x) takes a Int, not \"s\""]
"""
def named_value_problems(s, v, name, node, where, vars)
  k = v[:kind]
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
    if k == :int and int32?(v[:text])
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
  elsif d[:kind] == :enum
    if k == :enum and by_name(d[:values], v[:name]) != nil
      []
    else
      bad
    end
  elsif d[:kind] == :input
    if k != :object
      bad
    else
      object_problems(s, v, d, node, where, vars)
    end
  elsif d[:kind] == :scalar
    []
  else
    bad
  end
end

@doc """
render_value writes a value on one line, as a finding quotes it.

    render_value({kind: :list, items: [{kind: :enum, name: "A"}]}) #=> "[A]"
"""
def render_value(v)
  value_text(nil, v)
end

@doc """
object_problems judges an input object value against its input type: unknown, missing required and repeated fields.

    s = schema_of("type Query { a: Int } input I { n: Int! }")
    map((f) -> f[:message], object_problems(s, {kind: :object, fields: []}, type_named(s, "I"), {}, "v", {})) #=> ["v is missing the required input field n"]
"""
def object_problems(s, v, d, node, where, vars)
  given = v[:fields]
  names = map((f) -> f[:name], given)
  unknown = retsu::flat_map(
    given,
    fn(f)
      def_field = by_name(d[:fields], f[:name])
      if def_field.nil?
        [
          finding(
            "value-type",
            "#{where} has no input field #{f[:name]} on #{d[:name]}",
            node
          )
        ]
      else
        value_problems(
          s,
          f[:value],
          def_field[:type],
          node,
          "#{where}.#{f[:name]}",
          vars
        )
      end
    end
  )
  missing = retsu::flat_map(
    d[:fields],
    fn(f)
      if f[:type][:kind] == :non_null and
          f[:default].nil? and
          not member?(f[:name], names)
        [
          finding(
            "value-type",
            "#{where} is missing the required input field #{f[:name]}",
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

@doc """
argument_problems judges the arguments given against those defined: unknown, ill-typed, missing required and repeated arguments.

    s = schema_of("type Query { a: Int }")
    defs = [{name: "x", type: {kind: :non_null, of: {kind: :named, name: "Int"}}, default: nil}]
    map((f) -> f[:rule], argument_problems(s, [], defs, {}, "Query.b", {})) #=> ["argument-required"]
"""
def argument_problems(s, args, defs, node, where, vars)
  names = map((a) -> a[:name], args)
  given = retsu::flat_map(
    args,
    fn(a)
      d = by_name(defs, a[:name])
      if d.nil?
        [finding("argument-exists", "#{where} has no argument #{a[:name]}", a)]
      else
        value_problems(s, a[:value], d[:type], a, "#{where}(#{a[:name]})", vars)
      end
    end
  )
  missing = retsu::flat_map(
    defs,
    fn(d)
      supplied = by_name(args, d[:name])
      required = d[:type][:kind] == :non_null and d[:default].nil?
      if required and (supplied.nil? or supplied[:value][:kind] == :null)
        [
          finding(
            "argument-required",
            "#{where} needs the argument #{d[:name]}",
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

@doc """
directive_problems judges directives used at one location: undefined, misplaced, wrongly argued or repeated without being repeatable.

    s = schema_of("type Query { a: Int }")
    map((f) -> f[:message], directive_problems(s, [{name: "skip", arguments: []}], "FIELD", {}, nil)) #=> ["@skip needs the argument if"]
"""
def directive_problems(s, dirs, location, vars, _ctx)
  names = map((d) -> d[:name], dirs)
  each = retsu::flat_map(
    dirs,
    fn(d)
      def_dir = get(s[:directives], d[:name])
      if def_dir.nil?
        [
          finding(
            "directive-known",
            "the directive @#{d[:name]} is not defined",
            d
          )
        ]
      elsif not member?(location, def_dir[:locations])
        [
          finding(
            "directive-location",
            "@#{d[:name]} cannot be used on #{location}",
            d
          )
        ]
      else
        argument_problems(
          s,
          d[:arguments],
          def_dir[:arguments],
          d,
          "@#{d[:name]}",
          vars
        )
      end
    end
  )
  repeated = retsu::flat_map(
    duplicates(names),
    fn(n)
      def_dir = get(s[:directives], n)
      if def_dir != nil and not def_dir[:repeatable]
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

@doc """
string_type is the `String!` type the meta-field `__typename` has.

    type_text(string_type) #=> "String!"
"""
def string_type()
  {kind: :non_null, of: {kind: :named, name: "String"}}
end

@doc """
field_def finds the definition of field `name` on type `parent`, the introspection meta-fields included, nil when there is none.

    s = schema_of("type Query { a: Int } type T { c: String }")
    field_def(s, "T", "c", false)[:type] #=> {kind: :named, name: "String"}
    field_def(s, "Query", "__typename", true)[:type] #=> {kind: :non_null, of: {kind: :named, name: "String"}}
    field_def(s, "T", "zz", false) #=> nil
"""
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
  elsif d.nil? or d[:fields].nil?
    nil
  else
    by_name(d[:fields], name)
  end
end

@doc """
possible_types lists the object types a value of type `name` can be: itself, a union's members, or an interface's implementers.

    s = schema_of("type Query { a: Int } type T { c: Int } interface N { id: ID } type U implements N { id: ID } union X = T | U")
    possible_types(s, "N") #=> ["U"]
    possible_types(s, "X") #=> ["T", "U"]
"""
def possible_types(s, name)
  d = type_named(s, name)
  k = d[:kind]
  if k == :object
    [name]
  elsif k == :union
    d[:members]
  elsif k == :interface
    map(
      (t) -> t[:name],
      filter(
        (t) -> t[:kind] == :object and member?(name, t[:interfaces] or []),
        map((e) -> second(e), map_entries(s[:types]))
      )
    )
  else
    []
  end
end

@doc """
overlap? is true when some object type is possible for both `a` and `b`, so a fragment on one can apply inside the other.

    s = schema_of("type Query { a: Int } type T { c: Int } interface N { id: ID } type U implements N { id: ID } union X = T | U")
    overlap?(s, "X", "N") #=> true
    overlap?(s, "T", "N") #=> false
"""
def overlap?(s, a, b)
  bs = possible_types(s, b)
  any?((t) -> member?(t, bs), possible_types(s, a))
end

@doc """
selection_problems gathers the findings of every selection in a set made on type `parent`.

    ex = {s: schema_of("type Query { a: Int }"), frags: {}, root: "Query"}
    sels = first(parse("{ zz }")[:definitions])[:selections]
    map((f) -> f[:message], selection_problems(ex, sels, "Query", "q")) #=> ["Query has no field zz"]
"""
def selection_problems(ex, sels, parent, where)
  retsu::flat_map(sels, (sel) -> one_selection_problems(ex, sel, parent, where))
end

@doc """
one_selection_problems judges one selection on type `parent`: a field, a spread of a known fragment that can apply, or an inline fragment on a composite type.

    ex = {s: schema_of("type Query { a: Int }"), frags: {}, root: "Query"}
    sel = first(first(parse("{ ...F }")[:definitions])[:selections])
    map((f) -> f[:rule], one_selection_problems(ex, sel, "Query", "q")) #=> ["fragment-known"]
"""
def one_selection_problems(ex, sel, parent, where)
  s = ex[:s]
  k = sel[:kind]
  if k == :field
    field_problems(ex, sel, parent, where)
  elsif k == :spread
    frag = get(ex[:frags], sel[:name])
    dirs = directive_problems(s, sel[:directives], "FRAGMENT_SPREAD", {}, nil)
    if frag.nil?
      append(
        [
          finding(
            "fragment-known",
            "the fragment #{sel[:name]} is not defined",
            sel
          )
        ],
        dirs
      )
    elsif type_named(s, frag[:on]) != nil and
        composite?(kind_of(s, frag[:on])) and
        not overlap?(s, parent, frag[:on])
      append(
        [
          finding(
            "fragment-spread-possible",
            "...#{sel[:name]} on #{frag[:on]} can never apply to #{parent}",
            sel
          )
        ],
        dirs
      )
    else
      dirs
    end
  else
    on = sel[:on] or parent
    dirs = directive_problems(s, sel[:directives], "INLINE_FRAGMENT", {}, nil)
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
      append(dirs, selection_problems(ex, sel[:selections], on, where))
    end
  end
end

@doc """
field_problems judges one field selection: that it exists, its arguments and directives, and that it selects fields exactly when its type has them.

    ex = {s: schema_of("type Query { b(x: Int!): T } type T { c: String }"), frags: {}, root: "Query"}
    sel = first(first(parse("{ b(x: 1) }")[:definitions])[:selections])
    map((f) -> f[:message], field_problems(ex, sel, "Query", "q")) #=> ["q.b is a T and needs a selection of its fields"]
"""
def field_problems(ex, sel, parent, where)
  s = ex[:s]
  name = sel[:name]
  path = "#{where}.#{name}"
  d = field_def(s, parent, name, parent == ex[:root])
  if d.nil?
    [finding("field-exists", "#{parent} has no field #{name}", sel)]
  else
    base = base_name(d[:type])
    k = kind_of(s, base)
    args = argument_problems(s, sel[:arguments], d[:arguments], sel, path, {})
    dirs = directive_problems(s, sel[:directives], "FIELD", {}, nil)
    leaf = if composite?(k) and is_empty(sel[:selections])
      [
        finding(
          "leaf-selection",
          "#{path} is a #{base} and needs a selection of its fields",
          sel
        )
      ]
    elsif not composite?(k) and not is_empty(sel[:selections])
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
      selection_problems(ex, sel[:selections], base, path)
    else
      []
    end
    append(args, dirs, leaf, inner)
  end
end

@doc """
spreads_in names every fragment spread in a selection set, however deep.

    spreads_in(first(parse("{ ...A b { ...B } }")[:definitions])[:selections]) #=> ["A", "B"]
"""
def spreads_in(sels)
  retsu::flat_map(
    sels,
    fn(sel)
      k = sel[:kind]
      if k == :spread
        [sel[:name]]
      else
        spreads_in(sel[:selections])
      end
    end
  )
end

@doc """
reachable names every fragment the names spread, directly or through other fragments, each once.

    a = first(parse("fragment A on T { ...B }")[:definitions])
    b = first(parse("fragment B on T { c }")[:definitions])
    reachable({"A" => a, "B" => b}, ["A"], []) #=> ["A", "B"]
"""
def reachable(frags, names, seen)
  fresh = distinct(
    filter((n) -> not member?(n, seen) and get(frags, n) != nil, names)
  )
  if is_empty(fresh)
    seen
  else
    more = retsu::flat_map(fresh, (n) -> spreads_in(get(frags, n)[:selections]))
    reachable(frags, more, append(seen, fresh))
  end
end

@doc """
cyclic? is true when the fragment `name` spreads itself, directly or through others.

    a = first(parse("fragment A on T { ...A }")[:definitions])
    cyclic?({"A" => a}, "A") #=> true
"""
def cyclic?(frags, name)
  member?(name, reachable(frags, spreads_in(get(frags, name)[:selections]), []))
end

@doc """
usages_in_value finds each variable a value uses, with the type expected where it sits and whether that place has a default.

    t = {kind: :list_of, of: {kind: :named, name: "Int"}}
    usages_in_value({kind: :list, items: [{kind: :var, name: "v"}]}, t, false) #=> [{name: "v", type: {kind: :named, name: "Int"}, default: false}]
"""
def usages_in_value(v, t, default_present)
  k = v[:kind]
  inner = if t.nil?
    nil
  elsif t[:kind] == :non_null
    t[:of]
  else
    t
  end
  if k == :var
    [{name: v[:name], type: t, default: default_present}]
  elsif k == :list
    item = if inner != nil and inner[:kind] == :list_of
      inner[:of]
    end
    retsu::flat_map(v[:items], (x) -> usages_in_value(x, item, false))
  elsif k == :object
    retsu::flat_map(v[:fields], (f) -> usages_in_value(f[:value], nil, false))
  else
    []
  end
end

@doc """
usages_in_arguments finds the variables used in arguments, typed by the argument definitions when they are known.

    usages_in_arguments([{name: "x", value: {kind: :var, name: "v"}}], nil) #=> [{name: "v", type: nil, default: false}]
"""
def usages_in_arguments(args, defs)
  retsu::flat_map(
    args,
    fn(a)
      d = if defs.nil?
        nil
      else
        by_name(defs, a[:name])
      end
      t = if d.nil?
        nil
      else
        d[:type]
      end
      usages_in_value(a[:value], t, d != nil and d[:default] != nil)
    end
  )
end

@doc """
usages_in_directives finds the variables used in directive arguments, typed by the schema's directive definitions.

    s = schema_of("type Query { a: Int }")
    d = {name: "skip", arguments: [{name: "if", value: {kind: :var, name: "f"}}]}
    first(usages_in_directives(s, [d]))[:type] #=> {kind: :non_null, of: {kind: :named, name: "Boolean"}}
"""
def usages_in_directives(s, dirs)
  retsu::flat_map(
    dirs,
    fn(d)
      def_dir = get(s[:directives], d[:name])
      usages_in_arguments(
        d[:arguments],
        if def_dir.nil?
          nil
        else
          def_dir[:arguments]
        end
      )
    end
  )
end

@doc """
usages finds every variable a selection set uses, following fragment spreads once each, with the type expected at each use.

    ex = {s: schema_of("type Query { b(x: Int!): T } type T { c: String }"), frags: {}, root: "Query"}
    sels = first(parse("{ b(x: $v) { c } }")[:definitions])[:selections]
    usages(ex, sels, "Query", []) #=> [{name: "v", type: {kind: :non_null, of: {kind: :named, name: "Int"}}, default: false}]
"""
def usages(ex, sels, parent, seen)
  s = ex[:s]
  retsu::flat_map(
    sels,
    fn(sel)
      k = sel[:kind]
      own = usages_in_directives(s, sel[:directives])
      if k == :field
        d = if parent.nil?
          nil
        else
          field_def(s, parent, sel[:name], parent == ex[:root])
        end
        args = usages_in_arguments(
          sel[:arguments],
          if d.nil?
            nil
          else
            d[:arguments]
          end
        )
        next_parent = if d.nil?
          nil
        else
          base_name(d[:type])
        end
        append(own, args, usages(ex, sel[:selections], next_parent, seen))
      elsif k == :spread
        frag = get(ex[:frags], sel[:name])
        if frag.nil? or member?(sel[:name], seen)
          own
        else
          append(
            own,
            usages_in_directives(s, frag[:directives]),
            usages(ex, frag[:selections], frag[:on], append(seen, [sel[:name]]))
          )
        end
      else
        append(own, usages(ex, sel[:selections], sel[:on] or parent, seen))
      end
    end
  )
end

@doc """
compatible? is true when a variable of `var_type` may stand where `loc_type` is expected: non-null may narrow, never widen.

    int = {kind: :named, name: "Int"}
    compatible?({kind: :non_null, of: int}, int) #=> true
    compatible?(int, {kind: :non_null, of: int}) #=> false
"""
def compatible?(var_type, loc_type)
  if loc_type[:kind] == :non_null
    var_type[:kind] == :non_null and compatible?(var_type[:of], loc_type[:of])
  elsif var_type[:kind] == :non_null
    compatible?(var_type[:of], loc_type)
  elsif loc_type[:kind] == :list_of
    var_type[:kind] == :list_of and compatible?(var_type[:of], loc_type[:of])
  elsif var_type[:kind] == :list_of
    false
  else
    var_type[:name] == loc_type[:name]
  end
end

@doc """
position_ok? is true when a variable fits where it is used, a nullable variable with a default being allowed in a non-null place.

    int = {kind: :named, name: "Int"}
    position_ok?({type: int, default: {kind: :int, text: "1"}}, {type: {kind: :non_null, of: int}, default: false}) #=> true
    position_ok?({type: int, default: nil}, {type: {kind: :non_null, of: int}, default: false}) #=> false
"""
def position_ok?(var_def, use)
  vt = var_def[:type]
  lt = use[:type]
  if lt.nil?
    true
  elsif lt[:kind] == :non_null and vt[:kind] != :non_null
    has_default = var_def[:default] != nil and var_def[:default][:kind] != :null
    (has_default or use[:default]) and compatible?(vt, lt[:of])
  else
    compatible?(vt, lt)
  end
end

@doc """
variable_problems judges an operation's variables: their types and defaults, duplicates, uses with no definition, definitions with no use, and uses in the wrong position.

    ex = {s: schema_of("type Query { a: Int }"), frags: {}, root: "Query"}
    op = first(parse("query Q($v: Int) { a }")[:definitions])
    map((f) -> f[:message], variable_problems(ex, op, "Q")) #=> ["Q defines $v and never uses it"]
"""
def variable_problems(ex, op, where)
  s = ex[:s]
  vars = op[:variables]
  names = map((v) -> v[:name], vars)
  defs = retsu::flat_map(
    vars,
    fn(v)
      vname = "$#{v[:name]}"
      base = base_name(v[:type])
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
      elsif v[:default] != nil
        value_problems(s, v[:default], v[:type], v, vname, {})
      else
        []
      end
      append(
        ty,
        directive_problems(s, v[:directives], "VARIABLE_DEFINITION", {}, nil)
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
    usages_in_directives(s, op[:directives]),
    usages(ex, op[:selections], ex[:root], [])
  )
  used_names = distinct(map((u) -> u[:name], used))
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
        "#{where} defines $#{v[:name]} and never uses it",
        v
      )
    end,
    filter((v) -> not member?(v[:name], used_names), vars)
  )
  positions = retsu::flat_map(
    used,
    fn(u)
      v = by_name(vars, u[:name])
      if v != nil and
          type_named(s, base_name(v[:type])) != nil and
          not position_ok?(v, u)
        [
          finding(
            "variable-position",
            "$#{u[:name]} of type #{type_text(v[:type])} is used where #{type_text(u[:type])} is expected",
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

@doc """
root_fields lists the response keys an operation selects at its root, through fragments, so a subscription can be held to one.

    ex = {s: schema_of("type Query { a: Int }"), frags: {}, root: "Query"}
    root_fields(ex, first(parse("{ a x: b { c } }")[:definitions])[:selections], []) #=> ["a", "x"]
"""
def root_fields(ex, sels, seen)
  retsu::flat_map(
    sels,
    fn(sel)
      k = sel[:kind]
      if k == :field
        [sel[:alias] or sel[:name]]
      elsif k == :spread
        frag = get(ex[:frags], sel[:name])
        if frag.nil? or member?(sel[:name], seen)
          []
        else
          root_fields(ex, frag[:selections], append(seen, [sel[:name]]))
        end
      else
        root_fields(ex, sel[:selections], seen)
      end
    end
  )
end

@doc """
operation_problems judges one operation: its root exists, a subscription selects one root field, and its variables and selections hold.

    ex = {s: schema_of("type Query { a: Int } type Subscription { s: Int t: Int }"), frags: {}, root: nil}
    op = first(parse("subscription S { s t }")[:definitions])
    map((f) -> f[:rule], operation_problems(ex, op)) #=> ["subscription-single-root"]
"""
def operation_problems(ex, op)
  s = ex[:s]
  kind = op[:operation]
  where = op[:name] or "the anonymous #{kind}"
  root = get(s[:roots], kind)
  dirs = directive_problems(s, op[:directives], upcase(to_s(kind)), {}, nil)
  if root.nil?
    append(
      [finding("root-operation", "the schema has no #{kind} root", op)],
      dirs
    )
  else
    rx = assoc(ex, :root, root)
    single = if kind == :subscription
      fields = distinct(root_fields(rx, op[:selections], []))
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
      selection_problems(rx, op[:selections], root, where)
    )
  end
end

@doc """
fragment_problems judges one fragment definition: its type condition, a cycle through itself, and its selections.

    f = first(parse("fragment F on E { a }")[:definitions])
    ex = {s: schema_of("type Query { a: Int } enum E { A }"), frags: {"F" => f}, root: nil}
    map((x) -> x[:rule], fragment_problems(ex, f)) #=> ["fragment-type"]
"""
def fragment_problems(ex, frag)
  s = ex[:s]
  on = frag[:on]
  name = frag[:name]
  dirs = directive_problems(
    s,
    frag[:directives],
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
  cycle = if cyclic?(ex[:frags], name)
    [finding("fragment-cycle", "the fragment #{name} spreads itself", frag)]
  else
    []
  end
  body = if is_empty(head) and is_empty(cycle)
    selection_problems(
      assoc(ex, :root, s[:roots][:query]),
      frag[:selections],
      on,
      name
    )
  else
    []
  end
  append(dirs, head, cycle, body)
end

@doc """
executable_problems judges an executable document against an indexed schema: document-wide rules first, then each operation and fragment.

    s = schema_of("type Query { a: Int }")
    map((f) -> f[:rule], executable_problems(s, parse("{ a } { a }"))) #=> ["lone-anonymous"]
    executable_problems(s, parse("{ a }")) #=> []
"""
def executable_problems(s, doc)
  defs = doc[:definitions]
  ops = filter((d) -> d[:kind] == :operation, defs)
  frag_list = filter((d) -> d[:kind] == :fragment, defs)
  frags = reduce((m, f) -> assoc(m, f[:name], f), {}, frag_list)
  ex = {s:, frags:, root: nil}
  type_defs = map(
    fn(d)
      finding(
        "executable-definition",
        "an executable document holds no #{d[:kind]} definition",
        d
      )
    end,
    filter((d) -> d[:kind] != :operation and d[:kind] != :fragment, defs)
  )
  named = filter((n) -> n != nil, map((o) -> o[:name], ops))
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
  lone = if length(ops) > 1 and any?((o) -> o[:name].nil?, ops)
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
    duplicates(map((f) -> f[:name], frag_list))
  )
  used = reachable(
    frags,
    retsu::flat_map(ops, (o) -> spreads_in(o[:selections])),
    []
  )
  unused = map(
    fn(f)
      finding("fragment-unused", "the fragment #{f[:name]} is never used", f)
    end,
    filter((f) -> not member?(f[:name], used), frag_list)
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

@doc """
as_document accepts text, a document or one definition, and answers a document.

    as_document("{ a }")[:kind] #=> :document
    as_document({kind: :fragment}) #=> {kind: :document, definitions: [{kind: :fragment}]}
"""
def as_document(x)
  if string?(x)
    parse(x)
  elsif x[:kind] == :document
    x
  else
    {kind: :document, definitions: [x]}
  end
end

@doc """
schema_of indexes a schema once with its findings, so checking many documents against it does not index it again; an indexed schema passes through.

    s = schema_of("type Query { a: Int }")
    s[:findings] #=> []
    schema_of(s)[:roots] #=> {query: "Query"}
"""
def schema_of(schema, opts?)
  opts = checked(opts, [:defaults])
  if not string?(schema) and schema[:kind] == :schema_of
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

@doc """
check: masking, composition and entity-backed law findings for a program.

    check("{ a }", "type Query { a: Int }") #=> []
    map((f) -> f[:rule], check("{ b }", "type Query { a: Int }")) #=> ["field-exists"]
"""
def check(subject, rules?, opts?)
  opts = checked(opts, [:defaults])
  doc = as_document(subject)
  if rules.nil?
    schema_of(doc, opts)[:findings]
  else
    s = schema_of(rules, opts)
    if is_empty(s[:findings])
      executable_problems(s, doc)
    else
      s[:findings]
    end
  end
end

@doc """
validate: the document if every field and type is in the schema.

    validate("{ a }", "type Query { a: Int }")[:kind] #=> :document
    raised(() -> validate("{ b }", "type Query { a: Int }")) #=> :invalid
"""
def validate(document, schema?, opts?)
  found = check(document, schema, opts)
  if is_empty(found)
    as_document(document)
  else
    shown = join(
      map((f) -> "#{f[:rule]}: #{f[:message]}", take(3, found)),
      "; "
    )
    raise(:invalid, "#{length(found)} finding(s): #{shown}", {data: found})
  end
end

@doc """
spec_selection turns one item of a fragment's `fields:` into selections: a name is a field, `"...Name"` a spread, `{name: [...]}` fields with sub-selections.

    spec_selection("...F") #=> {kind: :spread, name: "F", directives: []}
    spec_selection(:a)[:name] #=> "a"
    map((x) -> x[:name], spec_selection({b: [:c]})) #=> ["b"]
"""
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

@doc """
flat_selections turns a whole `fields:` list into one flat selection list.

    map((x) -> x[:name], flat_selections([:a, {b: [:c]}, "...F"])) #=> ["a", "b", "F"]
"""
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

@doc """
fragment: declare a named field selection on one schema type.

    card = fragment(:user_card, {on: "User", fields: [:id, {avatar: [:url]}]})
    render(as_document(card), :compact) #=> "fragment user_card on User { id avatar { url } }"
    raised(() -> fragment(:f, {on: "User", fields: []})) #=> :bad_option
"""
def fragment(name, spec)
  spec = checked(spec, %i[on fields])
  on = spec[:on]
  fields = spec[:fields]
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

@doc """
definitions_of_kind: The definitions of a parsed document whose kind is `kind`, in document order.

    map((d) -> d[:name], definitions_of_kind(parse("query A { a } fragment f on Q { a }"), :operation)) #=> ["A"]
"""
def definitions_of_kind(doc, kind)
  filter((d) -> d[:kind] == kind, doc[:definitions])
end

@doc """
fragments_of accepts a list of fragments as given, or takes the fragment definitions out of text or a document.

    length(fragments_of("fragment F on T { a } { b }")) #=> 1
    fragments_of([]) #=> []
"""
def fragments_of(x)
  if list?(x)
    x
  else
    definitions_of_kind(as_document(x), :fragment)
  end
end

@doc """
operation_of writes the operation a root-type fragment stands for, named in PascalCase after it and spreading it.

    operation_of(fragment(:user_card, {on: "Query", fields: [:a]}))[:name] #=> "UserCard"
    raised(() -> operation_of(fragment(:f, {on: "User", fields: [:a]}))) #=> :bad_option
"""
def operation_of(frag)
  op = get(
    {
      "Query" => :query,
      "Mutation" => :mutation,
      "Subscription" => :subscription
    },
    frag[:on]
  )
  if op.nil?
    raise(
      :bad_option,
      "compose: fragment #{frag[:name]} is on #{frag[:on]}, not a root type"
    )
  end
  {
    kind: :operation,
    operation: op,
    name: join(map(capitalize, split(frag[:name], "_")), ""),
    variables: [],
    directives: [],
    selections: [{kind: :spread, name: frag[:name], directives: []}]
  }
end

@doc """
compose: one operation from the union of the fragments a view uses.

    home = fragment(:home, {on: "Query", fields: [{me: ["...card"]}]})
    card = fragment(:card, {on: "User", fields: [:id]})
    render(compose(home, [card]), :compact) #=> "query Home { ...home } fragment card on User { id } fragment home on Query { me { ...card } }"
    raised(() -> compose(home, [])) #=> :unknown_fragment
"""
def compose(first, second)
  doc = if map?(first) and first[:kind] == :fragment
    {kind: :document, definitions: [operation_of(first), first]}
  else
    as_document(first)
  end
  ops = filter((d) -> d[:kind] == :operation, doc[:definitions])
  pool = append(
    filter((d) -> d[:kind] == :fragment, doc[:definitions]),
    fragments_of(second)
  )
  frags = reduce((m, f) -> assoc(m, f[:name], f), {}, reverse(pool))
  names = reachable(
    frags,
    retsu::flat_map(ops, (o) -> spreads_in(o[:selections])),
    []
  )
  wanted = distinct(retsu::flat_map(ops, (o) -> spreads_in(o[:selections])))
  missing = filter(
    (n) -> get(frags, n).nil?,
    distinct(
      append(
        wanted,
        retsu::flat_map(names, (n) -> spreads_in(get(frags, n)[:selections]))
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

@doc """
response_key is the key a field's value has in a response: its alias, else its name.

    response_key({alias: "x", name: "a"}) #=> "x"
    response_key({alias: nil, name: "a"}) #=> "a"
"""
def response_key(sel)
  get_any(sel, %i[alias name])
end

@doc """
plain_hooks are the hooks `select` reads a plain value with: take each value as it is, skip an absent key, start from an empty map.

    plain_hooks[:resolve](1) #=> 1
    plain_hooks[:start](nil) #=> {}
"""
def plain_hooks()
  {resolve: (v) -> v, absent: (acc, _key) -> acc, start: (_v) -> {}}
end

@doc """
select_into reads only the selected keys of a value, through lists and nested selections, with hooks that let a caller resolve references or note absent keys.

    sels = first(parse("{ a }")[:definitions])[:selections]
    select_into({"a" => 1, "b" => 2}, sels) #=> {"a" => 1}
    select_into([{"a" => 1}, {"a" => 2}], sels) #=> [{"a" => 1}, {"a" => 2}]
"""
def select_into(value, sels, hooks?)
  h = hooks or plain_hooks
  v = h[:resolve](value)
  if v.nil?
    nil
  elsif list?(v)
    map((x) -> select_into(x, sels, h), v)
  elsif not map?(v)
    v
  else
    reduce(
      fn(acc, sel)
        k = sel[:kind]
        if k == :field
          key = response_key(sel)
          if member?(key, map((e) -> first(e), map_entries(v)))
            fv = get(v, key)
            assoc(
              acc,
              key,
              if is_empty(sel[:selections])
                fv
              else
                select_into(fv, sel[:selections], h)
              end
            )
          else
            h[:absent](acc, key)
          end
        elsif k == :inline
          typename = v["__typename"]
          if sel[:on].nil? or typename.nil? or typename == sel[:on]
            {**acc, **select_into(v, sel[:selections], h)}
          else
            acc
          end
        else
          acc
        end
      end,
      h[:start](v),
      sels
    )
  end
end

@doc """
select: only the fields a fragment declares, read from a value.

    card = fragment(:card, {on: "User", fields: [:id]})
    select({"id" => 1, "name" => "n"}, card) #=> {"id" => 1}
    select(nil, card) #=> nil
"""
def select(value, fragment)
  select_into(value, fragment[:selections])
end

@doc """
hash: the persisted-operation id of an operation's canonical text.

    hash(parse("query   Q {\n\n a }")) #=> hash(parse("query Q { a }"))
"""
def hash(operation, algorithm?)
  shomei::hash(render(as_document(operation)), algorithm or :sha256)
end

@doc """
schema_table reduces a valid schema to the field types of each composite type and the values of each enum, the data a client's masked read needs; an invalid schema raises.

    t = schema_table("type Query { a: Int t: T } type T { c: String } enum E { A B }")
    t[:types]["T"] #=> {"c" => "String"}
    t[:enums] #=> {"E" => ["A", "B"]}
    raised(() -> schema_table("type Query { a: Nope }")) #=> :invalid
"""
def schema_table(sdl)
  s = schema_of(as_document(sdl))
  found = s[:findings]
  if not is_empty(found)
    raise(
      :invalid,
      "the schema has #{length(found)} finding(s): #{first(found)[:message]}",
      {data: found}
    )
  end
  user = filter(
    (d) -> not d[:builtin],
    map((e) -> second(e), map_entries(s[:types]))
  )
  {
    types: reduce(
      fn(m, d)
        assoc(
          m,
          d[:name],
          reduce(
            (fm, f) -> assoc(fm, f[:name], base_name(f[:type])),
            {},
            d[:fields] or []
          )
        )
      end,
      {},
      filter((d) -> composite?(d[:kind]), user)
    ),
    enums: reduce(
      (m, d) -> assoc(m, d[:name], map((v) -> v[:name], d[:values])),
      {},
      filter((d) -> d[:kind] == :enum, user)
    )
  }
end

@doc """
table_entries writes a map's entries as blue map lines, sorted by key, for the `:table` rendering.

    table_entries({"b" => 2, "a" => 1}) #=> "    \"a\" => 1,\n    \"b\" => 2"
"""
def table_entries(m)
  join(
    map(
      (e) -> "    \"#{first(e)}\" => #{to_s(second(e))}",
      sort_keyed(first, map_entries(m))
    ),
    unlines([","])
  )
end

@doc """
table_text writes a schema's table as blue source, what `render(schema, :table)` answers.

    table_text(parse("type Query { a: Int }")) #=> "{\n  types: {\n    \"Query\" => {\"a\" => \"Int\"}\n  },\n  enums: {\n\n  }\n}\n"
"""
def table_text(document)
  t = schema_table(document)
  unlines(
    [
      "{",
      "  types: {",
      table_entries(t[:types]),
      "  },",
      "  enums: {",
      table_entries(t[:enums]),
      "  }",
      "}"
    ]
  )
end

@doc """
fixtures reads the `.graphql` files under one fixture directory on the blue path as `[path, text]` pairs in path order; an invalid fixture's file name names the rule its text breaks.

    pair = ["fixtures/schema/invalid-type-unique.graphql", "scalar D scalar D"]
    rules_found(second(pair), nil) #=> ["type-unique"]
"""
def fixtures(dir)
  hits = filter(is_dir?, fairu::on_blue_path("toriyose/danpen/fixtures/#{dir}"))
  if is_empty(hits)
    raise(:no_fixture, dir)
  end
  files = sort_keyed(
    (f) -> f,
    filter((f) -> ends_with?(f, ".graphql"), walk_dir(first(hits)))
  )
  map((f) -> [f, read_file(f)], files)
end

@doc """
rule_of reads which rule an invalid fixture proves from its file name, the longest rule name winning so `fragment-spread-possible` is not read as a shorter rule.

    rule_of("schema/invalid-argument-exists-2.graphql") #=> "argument-exists"
    rule_of("executable/invalid-fragment-spread-possible.graphql") #=> "fragment-spread-possible"
"""
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

@doc """
rule_names lists every rule a finding can name, plus `parse`, so each has an invalid fixture to prove it fires.

    length(rule_names) #=> 38
    member?("fragment-cycle", rule_names) #=> true
"""
def rule_names()
  %w[
    argument-exists
    argument-required
    argument-unique
    directive-known
    directive-location
    directive-repeat
    directive-unique
    executable-definition
    extension-kind
    extension-orphan
    field-exists
    fragment-cycle
    fragment-known
    fragment-spread-possible
    fragment-type
    fragment-unique
    fragment-unused
    implements-interface
    input-type
    leaf-selection
    lone-anonymous
    operation-unique
    output-type
    parse
    root-operation
    root-type
    schema-unique
    subscription-single-root
    type-known
    type-system-only
    type-unique
    union-member
    value-type
    variable-defined
    variable-input-type
    variable-position
    variable-unique
    variable-unused
  ]
end

@doc """
rules_found names the rules a document breaks against a schema, a parse failure counting as the rule `parse`.

    rules_found("{ a }", "type Query { b: Int }") #=> ["field-exists"]
    rules_found("{ a", nil) #=> ["parse"]
"""
def rules_found(text, schema)
  map((f) -> f[:rule], check(parse(text), schema))
rescue e
  if e.kind == :parse_error
    ["parse"]
  else
    raise(e)
  end
end

@doc """
schema_named indexes the schema fixture `fixtures/schema/NAME.graphql`, as `schema_of` indexes its text.

    schema_of(parse("type Query { a: Int }"))[:roots] #=> {query: "Query"}
"""
def schema_named(name)
  hit = find(
    fixtures("schema"),
    (f) -> ends_with?(first(f), "/#{name}.graphql")
  )
  schema_of(parse(second(hit)))
end

@doc """
hand_schema is the hand-written schema fixture the checker's tests judge documents against; it holds no findings.

    check("{ a }", schema_of("type Query { a: Int }")) #=> []
"""
def hand_schema()
  schema_named("hand")
end

@doc """
documents_named gathers the executable fixtures whose file name starts with `prefix` in each named directory, as `[path, text, schema]` rows checked against that directory's schema.

    row = ["executable/tiny/valid-a.graphql", "{ a }", schema_of("type Query { a: Int }")]
    check(row[1], row[2]) #=> []
"""
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
  op = first(doc[:definitions])
  assert op[:kind] == :operation
  assert op[:operation] == :query
  assert op[:name] == "Hero"
  assert first(op[:variables])[:default] == {kind: :enum, name: "JEDI"}
  f = first(op[:selections])
  assert f[:alias] == "h"
  assert f[:name] == "hero"
  assert first(f[:arguments])[:value] == {kind: :var, name: "e"}
  assert first(op[:directives])[:name] == "cached"
end

test "span_end stops at the first character its table lacks"
  x = {
    cs: ["a", "b", "1", " "],
    n: 4,
    part: {"a" => true, "b" => true, "1" => true},
    digit: {"1" => true}
  }
  assert span_end({cs: [], n: 0, digit: {}}, 0, :digit) == 0
  assert span_end(x, 0, :digit) == 0
  assert span_end(x, 0, :part) == 3
  assert span_end(x, 2, :digit) == 3
  assert name_end(x, 0) == 3
  assert digits_end(x, 2) == 3
end

test "tok_is? and consume read one token of a kind"
  p = {toks: [{kind: :punct, value: "{"}, {kind: :name, value: "query"}], n: 2}
  assert tok_is?(p, 0, :punct, "{")
  assert not tok_is?(p, 0, :name, "{")
  assert not tok_is?({toks: [], n: 0}, 0, :punct, "{")
  assert consume(p, 0, :punct, "{") == 1
  assert consume(p, 1, :name, "query") == 2
  assert expect(p, 0, "{") == 1
  assert keyword(p, 1, "query") == 2
  assert raised(() -> consume(p, 0, :name, "{")) == :parse_error
  assert raised(() -> consume({toks: [], n: 0}, 0, :punct, "}")) == :parse_error
end

test "kind_in reads a type's kind by name"
  assert kind_in({}, "Q").nil?
  assert kind_in({"Q" => {kind: :object}}, "Q") == :object
  assert kind_in({"Q" => {kind: :object}}, "R").nil?
  assert kind_of({types: {"E" => {kind: :enum}}}, "E") == :enum
end

test "definitions_of_kind keeps the definitions of one kind in order"
  d = parse("query A { a } fragment f on Q { a } query B { b }")
  assert definitions_of_kind({definitions: []}, :operation) == []
  assert map((x) -> x[:name], definitions_of_kind(d, :operation)) == %w[A B]
  assert map((x) -> x[:name], definitions_of_kind(d, :fragment)) == ["f"]
  assert length(definitions_of_kind(d, :operation)) + 1 ==
    length(d[:definitions])
end

test "parse refuses malformed text with its line and column"
  assert raised(() -> parse("")) == :parse_error
  assert raised(() -> parse("query { a ")) == :parse_error
  assert raised(() -> parse("{ a(x: 01) }")) == :parse_error
  assert raised(() -> parse("{ a(x: 1.) }")) == :parse_error
  assert raised(() -> parse("{ a(x: \"open) }")) == :parse_error
  assert raised(() -> parse("query ($v: Int = $w) { a }")) == :parse_error
  assert raised(() -> parse("\"described\" query { a }")) == :parse_error
  e = begin
    parse(join_lines(["{", "  a", "  b(: 1)", "}"]))
  rescue err
    err
  end
  assert e.data[:line] == 3
  assert e.data[:column] == 5
end

test "strings decode escapes and block strings lose their common indent"
  doc = parse("{ a(s: \"caf\\u00e9 \\u{1F600} \\\"q\\\" \\\\ \\n\") }")
  v = get(
    first(first(first(doc[:definitions]).selections)[:arguments])[:value],
    :value
  )
  assert v == unlines(["café 😀 \"q\" \\ "])
  assert block_value(
    join_lines(
      [
        "",
        "    Hello,",
        "      World!",
        "",
        "    Yours,",
        "      GraphQL.",
        "  "
      ]
    )
  ) == join_lines(["Hello,", "  World!", "", "Yours,", "  GraphQL."])
  assert block_value("") == ""
  assert block_value("  one line  ") == "  one line  "
end

test "render prints apollo-compiler's canonical layout"
  doc = parse("query Q($a: Int = 1, $b: [String!]!) { x: f(a: $a, b: [\"p\", \"q\"]) @skip(if: false) { ...F ... on T { g } } }  fragment F on T { h }")
  assert render(doc) ==
    unlines(
      [
        "query Q($a: Int = 1, $b: [String!]!) {",
        "  x: f(a: $a, b: [\"p\", \"q\"]) @skip(if: false) {",
        "    ...F",
        "    ... on T {",
        "      g",
        "    }",
        "  }",
        "}",
        "",
        "fragment F on T {",
        "  h",
        "}"
      ]
    )
  assert render(doc, :compact) ==
    "query Q($a: Int = 1, $b: [String!]!) { x: f(a: $a, b: [\"p\", \"q\"]) @skip(if: false) { ...F ... on T { g } } } fragment F on T { h }"
  assert render(parse("{ a }")) == unlines(["{", "  a", "}"])
  assert render(parse(join_lines(["\"\"\"  two", "lines\"\"\" scalar S"]))) ==
    unlines(["\"\"\"", "  two", "lines", "\"\"\"", "scalar S"])
  assert render(parse("\"  \\nx\" scalar S")) ==
    unlines(["\"  \\nx\"", "scalar S"])
  assert render(parse("\"short\" scalar S")) ==
    unlines(["\"\"\"short\"\"\"", "scalar S"])
  assert render(parse("{ a(s: \"one\\ntwo\") }")) ==
    unlines(["{", "  a(s: \"one\\ntwo\")", "}"])
  assert raised(() -> render(doc, :json)) == :bad_option
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
  found = check(
    parse(
      join_lines(["query {", "  hero {", "    mass", "  }", "}"]),
      {spans: true}
    ),
    s
  )
  assert map((f) -> f[:at], found) == [[3, 5]]
  assert map((f) -> f[:at], check(parse("query { hero { mass } }"), s)) == [nil]
end

test "check reads its rules from SDL text as from a parsed schema"
  sdl = "type Query { hero: Hero } type Hero { name: String }"
  assert check(parse("{ hero { name } }"), sdl) == []
  assert map((f) -> f[:rule], check(parse("{ hero { mass } }"), sdl)) ==
    map((f) -> f[:rule], check(parse("{ hero { mass } }"), parse(sdl)))
  assert is_empty(check(parse("{ hero { mass } }"), sdl)) == false
end

test "SDL default values are checked only when asked"
  doc = parse("type Query { a(n: Int = \"ten\"): Int }")
  assert check(doc) == []
  assert map((f) -> f[:rule], check(doc, nil, {defaults: true})) ==
    ["value-type"]
  assert raised(() -> check(doc, nil, {strict: true})) == :bad_option
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
  assert map((f) -> f[:rule], e.data) == ["field-exists"]
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
  assert raised(() -> fragment(:x, {on: "User", fields: []})) == :bad_option
  assert raised(() -> fragment(:x, {fields: [:id]})) == :bad_option
  assert raised(() -> fragment(:x, {on: "User", fields: [:id], extra: 1})) ==
    :bad_option
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
  assert map((d) -> d[:name], doc[:definitions]) == %w[Hero A B C]
  assert compose(op, reverse(frags)) == doc
  assert check(doc, hand_schema) == []
  assert raised(() -> compose(op, take(2, frags))) == :unknown_fragment
  assert compose(parse("{ hero { id } }"), frags)[:definitions] ==
    parse("{ hero { id } }")[:definitions]
end

test "compose writes a view's operation from its root fragment"
  card = fragment(:user_card, {on: "User", fields: [:name]})
  page = fragment(
    :profile_page,
    {on: "Query", fields: [{me: ["...user_card"]}]}
  )
  assert render(compose(page, [card]), :compact) ==
    "query ProfilePage { ...profile_page } fragment profile_page on Query { me { ...user_card } } fragment user_card on User { name }"
  assert raised(() -> compose(card, [])) == :bad_option
  assert raised(() -> compose(page, [])) == :unknown_fragment
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

test "select_into takes hooks that resolve a value, answer an absent field and start a record"
  people = {"u1" => {"id" => "u1", "name" => "Ada"}}
  hooks = {
    resolve: fn(x)
      if map?(x) and x["ref"] != nil
        get(people, x["ref"])
      else
        x
      end
    end,
    absent: (_acc, key) -> raise(:absent, key),
    start: (x) -> {"seen" => x["id"]}
  }
  sels = fragment(:f, {on: "Query", fields: [{who: [:name]}]})[:selections]
  assert select_into({"who" => {"ref" => "u1"}}, sels, hooks) ==
    {"seen" => nil, "who" => {"seen" => "u1", "name" => "Ada"}}
  assert raised(() -> select_into({}, sels, hooks)) == :absent
  assert select_into({}, sels) == {}
  assert select_into({"who" => {"ref" => "u1"}}, sels) == {"who" => {}}
end

test "a schema given as text is read as a schema"
  sdl = "type Query { a: Int }"
  assert check("{ a }", sdl) == []
  assert map((f) -> f[:rule], check("{ b }", sdl)) == ["field-exists"]
  assert validate("{ a }", sdl) == parse("{ a }")
end

test "hash is the sha256 of the canonical text, as shasum computes it"
  assert hash(parse("query Q { a }")) ==
    "ebe140cc901fd22769c2396de48f111460ff16619c348023409bbc47fa4a19e1"
  assert hash(parse(join_lines(["query   Q {", "", " a }"]))) ==
    hash(parse("query Q { a }"))
  assert hash("{ hero { name } }") ==
    "acc088d6d5fdba669a03cf99c1564e10730ec3ccda96ad7943bd57c7237b2aef"
  assert hash(parse("query Q { a }"), :blake3) != hash(parse("query Q { a }"))
  assert raised(() -> hash(parse("{ a }"), :md5)) == :bad_option
end

@doc """
kinds_in names the kind of every record in a parsed tree, outermost first, so a test can prove the parser emits each kind the grammar lowers to.

    kinds_in(parse("{ a }")) #=> ["document", "operation", "field"]
"""
def kinds_in(x)
  if map?(x)
    own = if keyword?(x[:kind])
      [to_s(x[:kind])]
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
  doc = parse(
    join_lines(
      [
        "query Q($v: [Int!] = [1]) { a(x: {y: null, z: ENUM}, w: 1.5, s: \"t\", b: true, v: $v) ...F ... on T { b } }",
        "fragment F on T { c }",
        "scalar S",
        "type T { c: Int }",
        "interface I { c: Int }",
        "union U = T",
        "enum E { A }",
        "input In { a: Int }",
        "directive @d on FIELD",
        "schema { query: T }"
      ]
    )
  )
  seen = distinct(kinds_in(doc))
  assert filter((k) -> not member?(k, kinds), seen) == []
  assert filter((k) -> not member?(k, seen), kinds) == []
  assert length(seen) == 24
end

test "the schema table is every composite type's fields and every enum's values"
  sdl = join_lines(
    [
      "type Query { me: User }",
      "type User { id: ID! tags: [Tone!]! friends: [User] }",
      "enum Tone { WARM COOL }",
      "union Any = User",
      "scalar Day"
    ]
  )
  t = schema_table(sdl)
  assert t[:types]["User"] ==
    {"id" => "ID", "tags" => "Tone", "friends" => "User"}
  assert t[:types]["Any"] == {}
  assert t[:types]["Day"].nil?
  assert t[:types]["String"].nil?
  assert t[:enums]["Tone"] == %w[WARM COOL]
  assert raised(() -> schema_table("type Q { a: Nope }")) == :invalid
end

test "render as a table is blue text that reads back as the table"
  text = render(
    parse(
      join_lines(
        [
          "type Query { me: User }",
          "type User { id: ID! }",
          "enum Tone { A B }"
        ]
      )
    ),
    :table
  )
  assert text ==
    unlines(
      [
        "{",
        "  types: {",
        "    \"Query\" => {\"me\" => \"User\"},",
        "    \"User\" => {\"id\" => \"ID\"}",
        "  },",
        "  enums: {",
        "    \"Tone\" => [\"A\", \"B\"]",
        "  }",
        "}"
      ]
    )
end

test "check finds nothing in a sound schema or document"
  assert hand_schema[:findings] == []
  assert schema_named("kensa")[:findings] == []
  sound = append(
    documents_named("valid-", %w[hand tiny]),
    documents_named("", ["kensa"])
  )
  assert length(sound) >= 10
  noisy = filter((f) -> check(parse(f[1]), f[2]) != [], sound)
  assert map((f) -> path_basename(first(f)), noisy) == []
end

test "each invalid document is found by the rule it is named for"
  docs = documents_named("invalid-", %w[hand tiny])
  missed = filter(
    (f) -> not member?(rule_of(first(f)), rules_found(f[1], f[2])),
    docs
  )
  assert map((f) -> path_basename(first(f)), missed) == []
  assert length(docs) >= 31
end

test "deeper and definitions_of pass nil through"
  assert deeper(nil).nil?
  assert deeper(0) == 1
  assert definitions_of(nil) == []
  assert definitions_of({definitions: [1]}) == [1]
end

test "response_key is the alias, else the field name"
  assert response_key({name: "a"}) == "a"
  assert response_key({alias: "b", name: "a"}) == "b"
end

test "pad indents two spaces a level"
  assert pad(0) == ""
  assert pad(2) == "    "
end

test "note records a problem at the end"
  assert note({}, "x") == {problems: ["x"]}
  assert note({problems: ["x"]}, "y") == {problems: %w[x y]}
end
