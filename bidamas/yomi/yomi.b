@moduledoc """
yomi (読み): blue's reader, written in blue (F1 of
docs/pure-blue/front-tower-conformance.md). `lex(src)` gives the tokens and
byte spans `crates/blue-lang-syntax/src/lex.rs` gives, each token
`[kind, start, end, payload]`, and refuses (`:lex`) what it refuses; it owns
the operator table both lexers read. `parse(src)` gives the tree
`parse_program_tree` gives, spans included, for the forms its slice reads, its
operators, powers and lowerings read from kiwari's grammar, and refuses
(`:parse`) the rest.

    lex("f(1)") #=> [[:ident, 0, 1, "f"], [:lparen, 1, 2, nil], [:int, 2, 3, 1], [:rparen, 3, 4, nil], [:eof, 4, 4, nil]]
"""

use("deeta", %i[code_point_text radix_value run_end space_byte? text_of])

use("kazu")

use("kiwari")

use("kyohi")

use("retsu", %i[all_but_last concat_lists first flat_map last rest])

legacy_names(
  "0.1.0",
  [
    ["text_of", "deeta::text_of", ""],
    ["run_end", "deeta::run_end", ""],
    ["gap?", "deeta::space_byte?", ""]
  ]
)

@doc """
operator_aliases: [symbol, the ASCII operator it spells, what it means], the
typographic spellings of blue's operators. Curated: every row is a symbol that
mathematics or ordinary typography already uses for exactly this operator, so a
reader needs no lookup. The lexer reads it here and `kigou.b` renders it for Rust.

    operator_aliases[0] #=> ["≠", "!=", "not equal"]
"""
def operator_aliases()
  [
    ["≠", "!=", "not equal"],
    ["≤", "<=", "less than or equal"],
    ["≥", ">=", "greater than or equal"],
    %w[× * multiplication],
    %w[÷ / division],
    ["−", "-", "minus sign (U+2212, not the ASCII hyphen)"],
    ["∧", "&&", "logical and"],
    ["∨", "||", "logical or"],
    ["¬", "!", "logical not"],
    ["≡", "==", "identical to"]
  ]
end

@doc """
lex: The tokens of blue source text, the end-of-file token last.

    lex("") #=> [[:eof, 0, 0, nil]]
"""
def lex(src)
  b = text_bytes(src)
  n = count(b)
  reverse(scan(b, n, bom_width(b), []))
end

@doc """
bom_width: How many bytes a leading byte order mark takes: 3 or 0.

    bom_width([239, 187, 191, 32]) #=> 3
"""
def bom_width(b)
  if count(b) >= 3 and b[0] == 239 and b[1] == 187 and b[2] == 191
    3
  else
    0
  end
end

@doc """
at: The byte at i, nil past the end.

    at([7], 1, 1) #=> nil
"""
def at(b, n, i)
  if i < n
    b[i]
  end
end

@doc """
scan: The tokens from byte pos on, pushed onto acc latest first.

    scan(text_bytes("x"), 1, 1, []) #=> [[:eof, 1, 1, nil]]
"""
def scan(b, n, pos, acc)
  if pos >= n
    cons([:eof, n, n, nil], acc)
  else
    got = token_at(b, n, pos)
    kept = if got[0].nil?
      acc
    else
      cons(got[0], acc)
    end
    scan(b, n, got[1], kept)
  end
end

@doc """
token_at: The token that starts at byte pos (nil for skipped space) and where
the next one starts.

    token_at(text_bytes(" "), 1, 0) #=> [nil, 1]
"""
def token_at(b, n, pos)
  c = b[pos]
  single = {
    40 => :lparen,
    41 => :rparen,
    91 => :lbracket,
    93 => :rbracket,
    123 => :lbrace,
    125 => :rbrace,
    44 => :comma,
    46 => :dot
  }
  if c == 10
    [[:newline, pos, pos + 1, nil], pos + 1]
  elsif c == 32 or c == 9 or c == 13
    [nil, pos + 1]
  elsif c == 35
    e = line_end(b, n, pos)
    [[:comment, pos, e, text_of(b, pos, e)], e]
  elsif c == 34
    string_at(b, n, pos)
  elsif c == 64
    doc_at(b, n, pos)
  elsif digit?(c)
    number_at(b, n, pos)
  elsif c == 58
    colon_at(b, n, pos)
  elsif get(single, c) != nil
    [[get(single, c), pos, pos + 1, nil], pos + 1]
  elsif c == 63
    [[:op, pos, pos + 1, "?"], pos + 1]
  elsif c >= 128
    wide_at(b, n, pos)
  elsif ident_start?(c)
    ident_at(b, n, pos)
  elsif c == 37 and word_list_at?(b, n, pos)
    words_at(b, n, pos)
  elsif op_char?(c)
    op_at(b, n, pos)
  elsif c == 59
    raise(
      :lex,
      "unexpected `;`: blue ends a statement at the end of the line, so put the next statement on a new line"
    )
  else
    raise(:lex, "unexpected character `#{text_of(b, pos, pos + 1)}`")
  end
end

@doc """
line_end: The index of the newline that ends the line holding i, or n.

    line_end(text_bytes("ab\nc"), 4, 0) #=> 2
"""
def line_end(b, n, i)
  if i >= n or b[i] == 10
    i
  else
    line_end(b, n, i + 1)
  end
end

@doc """
digit?: Whether a byte (or nil) is an ASCII digit.

    digit?(48) #=> true
"""
def digit?(c)
  c != nil and c >= 48 and c <= 57
end

@doc """
ident_start?: Whether a byte can begin a name: an ASCII letter or `_`.

    ident_start?(95) #=> true
"""
def ident_start?(c)
  c != nil and (c >= 65 and c <= 90 or c >= 97 and c <= 122 or c == 95)
end

@doc """
ident_continue?: Whether a byte can continue a name: a letter, digit, `_`, or
any byte of a non-ASCII character.

    ident_continue?(200) #=> true
"""
def ident_continue?(c)
  ident_start?(c) or digit?(c) or c != nil and c >= 128
end

@doc """
op_char?: Whether a byte is one of blue's operator characters `+-*/=<>!%&|`.

    op_char?(124) #=> true
"""
def op_char?(c)
  member?(c, [43, 45, 42, 47, 61, 60, 62, 33, 37, 38, 124])
end

@doc """
char_width: How many bytes the UTF-8 character led by byte c takes.

    char_width(226) #=> 3
"""
def char_width(c)
  if c < 128
    1
  elsif c < 224
    2
  elsif c < 240
    3
  else
    4
  end
end

@doc """
code_point: The Unicode scalar value of one character.

    code_point("é") #=> 233
"""
def code_point(ch)
  bs = text_bytes(ch)
  k = count(bs)
  if k == 1
    bs[0]
  elsif k == 2
    shift_left(bit_and(bs[0], 31), 6) + bit_and(bs[1], 63)
  elsif k == 3
    shift_left(bit_and(bs[0], 15), 12) +
      shift_left(bit_and(bs[1], 63), 6) +
      bit_and(bs[2], 63)
  else
    shift_left(bit_and(bs[0], 7), 18) +
      shift_left(bit_and(bs[1], 63), 12) +
      shift_left(bit_and(bs[2], 63), 6) +
      bit_and(bs[3], 63)
  end
end

@doc """
space?: Whether a scalar value is Unicode white space.

    space?(12288) #=> true
"""
def space?(cp)
  cp >= 9 and cp <= 13 or
    cp >= 8192 and cp <= 8202 or
    member?(cp, [32, 133, 160, 5760, 8232, 8233, 8239, 8287, 12288])
end

@doc """
rejected?: Whether a character is refused outside a string: a control
character, white space, or a byte order mark.

    rejected?("é") #=> false
"""
def rejected?(ch)
  cp = code_point(ch)
  cp < 32 or cp >= 127 and cp <= 159 or space?(cp) or cp == 65279
end

@doc """
alias_of: The ASCII operator a typographic symbol spells, or nil.

    alias_of("≠") #=> "!="
"""
def alias_of(ch)
  row = find(operator_aliases, (r) -> r[0] == ch)
  if row != nil
    row[1]
  end
end

@doc """
wide_at: The token a non-ASCII character starts: an operator alias, the start
of a name, or a refusal.

    wide_at(text_bytes("≤"), 3, 0) #=> [[:op, 0, 3, "<="], 3]
"""
def wide_at(b, n, pos)
  w = char_width(b[pos])
  ch = text_of(b, pos, pos + w)
  op = alias_of(ch)
  if op != nil
    [[:op, pos, pos + w, op], pos + w]
  elsif rejected?(ch)
    raise(
      :lex,
      "the character U+#{code_point(ch)} is not legal in blue source outside a string"
    )
  else
    ident_at(b, n, pos)
  end
end

@doc """
suffix?: Whether the byte at e ends a name as its `?`, or as its `!` when no
`=` follows.

    suffix?(text_bytes("!="), 2, 0) #=> false
"""
def suffix?(b, n, e)
  c = at(b, n, e)
  c == 63 or c == 33 and at(b, n, e + 1) != 61
end

@doc """
name_end: Where a name that runs from i ends, its `?` or `!` included.

    name_end(text_bytes("ok? x"), 5, 0) #=> 3
"""
def name_end(b, n, i)
  e = run_end(b, n, i, ident_continue?)
  if suffix?(b, n, e)
    e + 1
  else
    e
  end
end

@doc """
ident_at: A name, a label (a name and one colon), or true, false or nil.

    ident_at(text_bytes("a: 1"), 4, 0) #=> [[:label, 0, 2, "a"], 2]
"""
def ident_at(b, n, start)
  e = name_end(b, n, start)
  name = text_of(b, start, e)
  if at(b, n, e) == 58 and at(b, n, e + 1) != 58
    [[:label, start, e + 1, name], e + 1]
  elsif name == "true"
    [[:true, start, e, nil], e]
  elsif name == "false"
    [[:false, start, e, nil], e]
  elsif name == "nil"
    [[:nil, start, e, nil], e]
  else
    [[:ident, start, e, name], e]
  end
end

@doc """
colon_at: `::`, a symbol (a colon and a name), or a lone colon.

    colon_at(text_bytes(":ok"), 3, 0) #=> [[:sym, 0, 3, "ok"], 3]
"""
def colon_at(b, n, pos)
  if at(b, n, pos + 1) == 58
    [[:path_sep, pos, pos + 2, nil], pos + 2]
  elsif ident_start?(at(b, n, pos + 1))
    e = name_end(b, n, pos + 1)
    [[:sym, pos, e, text_of(b, pos + 1, e)], e]
  else
    [[:colon, pos, pos + 1, nil], pos + 1]
  end
end

@doc """
digits_end: Where a run of digits and underscores from i ends.

    digits_end(text_bytes("1_0x"), 4, 0) #=> 3
"""
def digits_end(b, n, i)
  run_end(b, n, i, (c) -> digit?(c) or c == 95)
end

@doc """
exponent_skip: How many bytes an exponent marker at e takes before its digits
(`e` 1, `e+` or `e-` 2), or 0 when none starts there.

    exponent_skip(text_bytes("e-5"), 3, 0) #=> 2
"""
def exponent_skip(b, n, e)
  c = at(b, n, e)
  d = at(b, n, e + 1)
  if c != 101 and c != 69
    0
  elsif digit?(d)
    1
  elsif (d == 43 or d == 45) and digit?(at(b, n, e + 2))
    2
  else
    0
  end
end

@doc """
number_at: An Int, or a Float when a fraction or an exponent follows.

    number_at(text_bytes("1.5e3"), 5, 0) #=> [[:float, 0, 5, 1500.0], 5]
"""
def number_at(b, n, start)
  e1 = digits_end(b, n, start)
  dotted = at(b, n, e1) == 46 and digit?(at(b, n, e1 + 1))
  e2 = if dotted
    digits_end(b, n, e1 + 1)
  else
    e1
  end
  skip = exponent_skip(b, n, e2)
  e3 = if skip > 0
    digits_end(b, n, e2 + skip)
  else
    e2
  end
  text = join(filter((ch) -> ch != "_", chars(text_of(b, start, e3))), "")
  if dotted or skip > 0
    [[:float, start, e3, to_float(text)], e3]
  else
    [[:int, start, e3, to_int(text)], e3]
  end
end

@doc """
word_list_at?: Whether `%w[` or `%i[` starts at i.

    word_list_at?(text_bytes("%i["), 3, 0) #=> true
"""
def word_list_at?(b, n, i)
  at(b, n, i) == 37 and
    (at(b, n, i + 1) == 119 or at(b, n, i + 1) == 105) and
    at(b, n, i + 2) == 91
end

@doc """
op_end: Where a run of operator characters from start ends, stopping before a
word list.

    op_end(text_bytes("=>x"), 3, 0, 0) #=> 2
"""
def op_end(b, n, start, i)
  if i < n and op_char?(b[i]) and not (i > start and word_list_at?(b, n, i))
    op_end(b, n, start, i + 1)
  else
    i
  end
end

@doc """
op_at: An operator, `=>` as a rocket and `|>` as a pipe.

    op_at(text_bytes("=>"), 2, 0) #=> [[:rocket, 0, 2, nil], 2]
"""
def op_at(b, n, start)
  e = op_end(b, n, start, start)
  text = text_of(b, start, e)
  if text == "=>"
    [[:rocket, start, e, nil], e]
  elsif text == "|>"
    [[:pipe, start, e, nil], e]
  else
    [[:op, start, e, text], e]
  end
end

@doc """
words_at: A word list, `%w[…]` of strings or `%i[…]` of names, each word with its span.

    words_at(text_bytes("%w[a]"), 5, 0) #=> [[:words, 0, 5, [:strings, [["a", 3, 4]]]], 5]
"""
def words_at(b, n, start)
  flavor = if b[start + 1] == 119
    :strings
  else
    :keywords
  end
  words_from(b, n, start, start + 3, flavor, [])
end

@doc """
words_from: The rest of a word list from i, the words so far in acc latest first.

    words_from(text_bytes("%i[]"), 4, 0, 3, :keywords, [])[1] #=> 4
"""
def words_from(b, n, start, i, flavor, acc)
  j = run_end(b, n, i, space_byte?)
  if j >= n
    raise(:lex, "unterminated word list")
  elsif b[j] == 93
    [[:words, start, j + 1, [flavor, reverse(acc)]], j + 1]
  else
    e = run_end(b, n, j, (c) -> not (c == 93 or space_byte?(c)))
    w = text_of(b, j, e)
    if not word_fits?(flavor, w)
      raise(:lex, "`#{w}` cannot be a word of this word list")
    end
    words_from(b, n, start, e, flavor, cons([w, j, e], acc))
  end
end

@doc """
word_char?: Whether a character may stand in a `%w[…]` word.

    word_char?(",") #=> false
"""
def word_char?(ch)
  cp = code_point(ch)
  not space?(cp) and
    not member?(ch, ["[", "]", ",", "\"", "'", "\\", "#"]) and
    (cp >= 33 and cp <= 126 or cp >= 128 and not rejected?(ch))
end

@doc """
word_fits?: Whether a word may stand in a word list of its flavor: any word
characters in `%w[…]`, a name `:name` could spell in `%i[…]`.

    word_fits?(:keywords, "ok?") #=> true
"""
def word_fits?(flavor, w)
  cs = chars(w)
  if flavor == :strings
    not any?((ch) -> not word_char?(ch), cs)
  else
    body = if count(cs) > 1 and member?(last(cs), %w[? !])
      take(count(cs) - 1, cs)
    else
      cs
    end
    first_byte = first(text_bytes(w))
    ident_start?(first_byte) and
      not any?(
        fn(ch)
          not (
            count(text_bytes(ch)) == 1 and
              ident_continue?(
                first(text_bytes(ch))
              ) or count(text_bytes(ch)) > 1 and word_char?(ch)
          )
        end,
        body
      )
  end
end

@doc """
push_bytes: acc with bytes i up to e pushed on, the last on top.

    push_bytes([], [1, 2, 3], 0, 2) #=> [2, 1]
"""
def push_bytes(acc, b, i, e)
  if i >= e
    acc
  else
    push_bytes(cons(b[i], acc), b, i + 1, e)
  end
end

@doc """
string_at: A string literal, or an interpolated one with its literal parts and
the source of each `#{…}`.

    string_at(text_bytes("\"hi\""), 4, 0) #=> [[:str, 0, 4, "hi"], 4]
"""
def string_at(b, n, start)
  string_from(b, n, start, start + 1, [], [], [])
end

@doc """
string_from: The rest of a string from i: the current part's bytes in buf,
the finished parts and expressions latest first.

    string_from(text_bytes("\"\""), 2, 0, 1, [], [], [])[1] #=> 2
"""
def string_from(b, n, start, i, buf, parts, exprs)
  if i >= n
    raise(:lex, "unterminated string literal")
  end
  c = b[i]
  if c == 35 and at(b, n, i + 1) == 123
    after = skip_interpolation(b, n, i + 2, 1)
    if after.nil?
      raise(:lex, concat(concat("unterminated `", "#"), "{` interpolation"))
    end
    string_from(
      b,
      n,
      start,
      after,
      [],
      cons(bytes_text(reverse(buf)), parts),
      cons(text_of(b, i + 2, after - 1), exprs)
    )
  elsif c == 34
    text = bytes_text(reverse(buf))
    if exprs == []
      [[:str, start, i + 1, text], i + 1]
    else
      [
        [:interp, start, i + 1, [reverse(cons(text, parts)), reverse(exprs)]],
        i + 1
      ]
    end
  elsif c == 92
    escape_at(b, n, start, i + 1, buf, parts, exprs)
  else
    string_from(
      b,
      n,
      start,
      i + char_width(c),
      push_bytes(buf, b, i, i + char_width(c)),
      parts,
      exprs
    )
  end
end

@doc """
escape_at: One escape after its backslash, the string read on from there.

    escape_at(text_bytes("\"\\n\""), 4, 0, 2, [], [], [])[0] #=> [:str, 0, 4, "\n"]
"""
def escape_at(b, n, start, i, buf, parts, exprs)
  if i >= n
    raise(:lex, "unterminated escape")
  end
  c = b[i]
  simple = {
    110 => 10,
    116 => 9,
    114 => 13,
    92 => 92,
    34 => 34,
    48 => 0,
    102 => 12,
    98 => 8,
    118 => 11,
    97 => 7,
    101 => 27
  }
  if get(simple, c) != nil
    string_from(b, n, start, i + 1, cons(get(simple, c), buf), parts, exprs)
  elsif c == 117
    if at(b, n, i + 1) != 123
      raise(:lex, "expected `{` after \\u")
    end
    close = run_end(b, n, i + 2, (x) -> x != 125)
    if close >= n
      raise(:lex, "unterminated \\u{...} escape")
    end
    hex = text_of(b, i + 2, close)
    v = if hex == ""
      nil
    else
      radix_value(hex, 16)
    end
    t = if v.nil?
      nil
    else
      code_point_text(v)
    end
    if t.nil?
      raise(:lex, "`#{hex}` is not a Unicode scalar value")
    end
    string_from(
      b,
      n,
      start,
      close + 1,
      push_bytes(buf, text_bytes(t), 0, count(text_bytes(t))),
      parts,
      exprs
    )
  else
    raise(:lex, "unknown escape \\#{text_of(b, i, i + 1)}")
  end
end

@doc """
skip_interpolation: The index just past the `}` that closes an interpolation
whose body starts at i, at the given brace depth, or nil when none does.

    skip_interpolation(text_bytes("a}"), 2, 0, 1) #=> 2
"""
def skip_interpolation(b, n, i, depth)
  if i >= n
    nil
  else
    c = b[i]
    if c == 123
      skip_interpolation(b, n, i + 1, depth + 1)
    elsif c == 125 and depth == 1
      i + 1
    elsif c == 125
      skip_interpolation(b, n, i + 1, depth - 1)
    elsif c == 34
      j = code_string_end(b, n, i + 1)
      if j != nil
        skip_interpolation(b, n, j, depth)
      end
    elsif c == 37 and
        (at(b, n, i + 1) == 119 or at(b, n, i + 1) == 105) and
        at(b, n, i + 2) == 91
      k = run_end(b, n, i + 3, (x) -> x != 93)
      if k < n
        skip_interpolation(b, n, k + 1, depth)
      end
    else
      skip_interpolation(b, n, i + 1, depth)
    end
  end
end

@doc """
code_string_end: The index just past a string inside interpolated code whose
body starts at i, or nil when it is not closed.

    code_string_end(text_bytes("a\"x"), 3, 0) #=> 2
"""
def code_string_end(b, n, i)
  if i >= n
    nil
  else
    c = b[i]
    if c == 34
      i + 1
    elsif c == 92
      code_string_end(b, n, i + 2)
    elsif c == 35 and at(b, n, i + 1) == 123
      k = skip_interpolation(b, n, i + 2, 1)
      if k != nil
        code_string_end(b, n, k)
      end
    else
      code_string_end(b, n, i + 1)
    end
  end
end

@doc """
doc_at: `@doc` or `@moduledoc` and its heredoc text, the closing line's
indentation taken off every line.

    doc_at(text_bytes("@doc \"\"\"\nhi\n\"\"\"\n"), 16, 0)[0] #=> [:doc, 0, 15, [false, "hi"]]
"""
def doc_at(b, n, start)
  we = run_end(b, n, start + 1, ident_continue?)
  word = text_of(b, start + 1, we)
  if word != "doc" and word != "moduledoc"
    raise(
      :lex,
      "unexpected `@#{word}`: blue's attributes are `@doc` and `@moduledoc`"
    )
  end
  p = run_end(b, n, we, (c) -> c == 32 or c == 9)
  le = line_end(b, n, p)
  opens = at(b, n, p) == 34 and at(b, n, p + 1) == 34 and at(b, n, p + 2) == 34
  rest_of_line = if le - p >= 3
    text_of(b, p + 3, le)
  else
    "x"
  end
  if not opens or trim(rest_of_line) != ""
    raise(:lex, "`@#{word}` takes a heredoc")
  end
  found = doc_lines(b, n, kazu::min(le + 1, n), [])
  lead = run_end(b, n, found[1], (c) -> c == 32 or c == 9)
  indent = text_of(b, found[1], lead)
  kept = map((line) -> doc_line(line, indent), found[0])
  text = join(trim_blank(reverse(trim_blank(reverse(kept)))), line_break)
  if contains?(text, "\"\"\"")
    raise(:lex, "a `@#{word}` text cannot hold three quotes")
  end
  [[:doc, start, lead + 3, [word == "moduledoc", text]], lead + 3]
end

@doc """
doc_lines: The heredoc's lines from at, up to the line that is only three
quotes, and where that line starts and ends.

    doc_lines(text_bytes("a\n\"\"\""), 5, 0, [])[0] #=> ["a"]
"""
def doc_lines(b, n, at, acc)
  if at >= n
    raise(:lex, "unterminated heredoc: no closing line of three quotes")
  end
  e = line_end(b, n, at)
  line = text_of(b, at, e)
  if trim(line) == "\"\"\""
    [reverse(acc), at, e]
  else
    doc_lines(b, n, kazu::min(e + 1, n + 1), cons(line, acc))
  end
end

@doc """
doc_line: One heredoc line with trailing space cut and the indent taken off.

    doc_line("  a  ", "  ") #=> "a"
"""
def doc_line(line, indent)
  cut = trim(line, {side: :end})
  if cut == ""
    ""
  elsif starts_with?(cut, indent)
    join(drop(count(chars(indent)), chars(cut)), "")
  else
    raise(:lex, "a heredoc line is indented less than its closing line")
  end
end

@doc """
trim_blank: Lines with the empty ones at the front dropped.

    trim_blank(["", "a", ""]) #=> ["a", ""]
"""
def trim_blank(lines)
  if lines != [] and first(lines) == ""
    trim_blank(rest(lines))
  else
    lines
  end
end

@doc """
parse: The forms of blue source text, each node `[start, end, kind, payload]`
as `blue ast --tree-json` prints `parse_program_tree`'s tree (kind `:list`,
`:sym`, `:kw`, `:str`, `:int`, `:float`, `:bool` or `:nil`). The engine is a
Pratt reader over `lex`'s tokens that reads its operators, binding powers,
reserved words and every node's lowering from kiwari's grammar (`reading`).
What the slice does not read yet is refused with `:parse`.

    parse("x = 1") #=> [[0, 5, :list, [[0, 1, :sym, "define"], [0, 1, :sym, "x"], [4, 5, :int, 1]]]]
"""
def parse(src)
  parse_tokens(reading, lex(src))
end

@doc """
reading: What the reader takes from kiwari's `blue()`: the infix rows, the
unary rows, the pipe, each rule's lowering by name, and the reserved words
(kiwari's surface and block words, and the rows' operators that are words).

    reading[:pipe][:power] #=> [0, 1]
"""
def reading()
  g = kiwari::blue
  ops = map((row) -> row[:op], concat_lists(g[:infix], g[:unary]))
  {
    infix: g[:infix],
    unary: g[:unary],
    pipe: g[:pipe],
    lower: reduce(
      (m, rule) -> assoc(m, rule[:name], rule[:lower]),
      {},
      g[:rules]
    ),
    reserved: concat_lists(
      concat_lists(g[:reserved][:surface], g[:reserved][:block]),
      filter((op) -> first(lex(op))[0] == :ident, ops)
    )
  }
end

@doc """
parse_tokens: The forms of a token list (comments included) under a reading.

    parse_tokens(reading, lex("7")) #=> [[0, 1, :int, 7]]
"""
def parse_tokens(r, all)
  toks = filter((t) -> t[0] != :comment, all)
  p = {
    toks:,
    last: count(toks) - 1,
    comments: map((t) -> t[1], filter((t) -> t[0] == :comment, all)),
    r:
  }
  program(p, 0, [])
end

@doc """
tok: The token at i, the end-of-file token past the end.

    tok({toks: lex("a"), last: 1}, 5)[0] #=> :eof
"""
def tok(p, i)
  p[:toks][kazu::min(i, p[:last])]
end

@doc """
ended: Where the last token before i ends: the end of what a production consumed.

    ended({toks: lex("ab c")}, 1) #=> 2
"""
def ended(p, i)
  p[:toks][i - 1][2]
end

@doc """
skip_newlines: The first index from i that is not a newline token.

    skip_newlines({toks: lex(join_lines(["", "a"])), last: 2}, 0) #=> 1
"""
def skip_newlines(p, i)
  if tok(p, i)[0] == :newline
    skip_newlines(p, i + 1)
  else
    i
  end
end

@doc """
touches?: Whether the token at i starts where the one before it ends.

    touches?({toks: lex("a[0]"), last: 4}, 1) #=> true
"""
def touches?(p, i)
  i > 0 and p[:toks][i - 1][2] == tok(p, i)[1]
end

@doc """
is?: Whether the token t is of kind k and spells w: `is?(t, :op, "=")`, `is?(t, :ident, "end")`.

    is?([:op, 0, 1, "="], :op, "=") #=> true
"""
def is?(t, k, w)
  t[0] == k and t[3] == w
end

@doc """
span_of: A token's span.

    span_of([:ident, 2, 3, "x"]) #=> [2, 3]
"""
def span_of(t)
  [t[1], t[2]]
end

@doc """
reserved?: Whether a name is one of the reading's reserved words.

    reserved?({r: {reserved: ["if"]}}, "if") #=> true
"""
def reserved?(p, name)
  member?(name, p[:r][:reserved])
end

@doc """
expect: The index after the token at i when it is of kind k; refused with
`:parse` otherwise.

    expect({toks: lex(")"), last: 1}, 0, :rparen) #=> 1
"""
def expect(p, i, k)
  if tok(p, i)[0] != k
    raise(:parse, "expected #{k}, found #{tok(p, i)[0]}")
  end
  i + 1
end

@doc """
expect_word: The index after the identifier w at i; refused with `:parse` otherwise.

    expect_word({toks: lex("end"), last: 1}, 0, "end") #=> 1
"""
def expect_word(p, i, w)
  if not is?(tok(p, i), :ident, w)
    raise(:parse, "expected `#{w}`")
  end
  i + 1
end

@doc """
outside: Refuse a form this slice of the reader does not read yet.

    kyohi::raised(() -> outside("`case`")) #=> :parse
"""
def outside(what)
  raise(:parse, join([what, "is outside yomi's parser slice"], " "))
end

@doc """
node: A concrete node: its kind, span, the span a synthesized atom of its
lowering takes (`anchor`), and its children, each `[field, child]`.

    node("list", [0, 2], [0, 1], [])[:anchor] #=> [0, 1]
"""
def node(kind, span, anchor, fields)
  {kind:, start: span[0], end: span[1], anchor:, fields:}
end

@doc """
leaf: A concrete node holding one token.

    leaf("identifier", [:ident, 0, 1, "x"])[:end] #=> 1
"""
def leaf(kind, t)
  assoc(node(kind, span_of(t), span_of(t), []), :tok, t)
end

@doc """
program: The lowered forms from token i on, onto acc latest first.

    program({toks: lex(""), last: 0}, 0, []) #=> []
"""
def program(p, i, acc)
  j = skip_newlines(p, i)
  t = tok(p, j)
  if t[0] == :eof
    map(bodies, reverse(acc))
  elsif t[0] == :doc
    got_form = documentation(p, j, acc == [])
    form = got_form[0]
    k = got_form[1]
    program(
      p,
      k,
      if form.nil?
        acc
      else
        cons(form, acc)
      end
    )
  else
    got_n = statement(p, j)
    n = got_n[0]
    k = got_n[1]
    end_of_statement(p, k, [])
    program(p, k, cons(lower_one(p[:r], n), acc))
  end
end

@doc """
documentation: A doc and what it documents, as `doc::strip` leaves it: a
module doc is dropped, a `@doc` gives its definition the doc's start.

    documentation({toks: [[:doc, 0, 5, [true, "m"]], [:eof, 5, 5, nil]], last: 1}, 0, true) #=> [nil, 1]
"""
def documentation(p, i, opening)
  t = tok(p, i)
  end_of_statement(p, i + 1, [])
  if t[3][0]
    if not opening
      raise(:parse, "`@moduledoc` is the first form of a file")
    end
    [nil, i + 1]
  else
    j = skip_newlines(p, i + 1)
    if tok(p, j)[0] == :doc or tok(p, j)[0] == :eof
      raise(
        :parse,
        "`@doc` documents the definition below it, and none follows"
      )
    end
    got_n = statement(p, j)
    n = got_n[0]
    k = got_n[1]
    end_of_statement(p, k, [])
    v = lower_one(p[:r], n)
    if not definition?(v)
      raise(:parse, "`@doc` documents a definition")
    end
    [[t[1], v[1], v[2], v[3]], k]
  end
end

@doc """
definition?: Whether a lowered form is a definition a `@doc` may document.

    definition?([0, 5, :list, [[0, 1, :sym, "define"]]]) #=> true
"""
def definition?(v)
  v[2] == :list and member?(v[3][0][3], %w[define define-typed])
end

@doc """
end_of_statement: Nothing, when the token at i ends a statement: a newline,
the end of the file, or one of the closing words; refused with `:parse` otherwise.

    end_of_statement({toks: lex("end"), last: 1}, 0, ["end"]) #=> nil
"""
def end_of_statement(p, i, closers)
  t = tok(p, i)
  if not (
    t[0] == :newline or
    t[0] == :eof or
    t[0] == :ident and member?(t[3], closers)
  )
    raise(:parse, "expected the end of the line, found #{t[0]}")
  end
end

@doc """
statement: A binding `name = value` or an expression, and the index after it.

    statement({toks: lex("x = 1"), last: 3, r: reading}, 0)[0][:kind] #=> "binding"
"""
def statement(p, i)
  t = tok(p, i)
  if t[0] == :ident and is?(tok(p, i + 1), :op, "=") and not reserved?(p, t[3])
    got_value = expr(p, skip_newlines(p, i + 2), 0)
    value = got_value[0]
    j = got_value[1]
    [
      node(
        "binding",
        [t[1], ended(p, j)],
        span_of(t),
        [["name", leaf("identifier", t)], ["value", value]]
      ),
      j
    ]
  else
    got_e = expr(p, i, 0)
    e = got_e[0]
    j = got_e[1]
    if is?(tok(p, j), :op, "=")
      outside("a destructuring binding")
    end
    [e, j]
  end
end

@doc """
expr: The expression at i binding at least as tightly as min_bp (a Pratt
loop over kiwari's binding powers), and the index after it.

    expr({toks: lex("a"), last: 1, r: reading}, 0, 0)[1] #=> 1
"""
def expr(p, i, min_bp)
  got_lhs = prefix(p, i)
  lhs = got_lhs[0]
  j = got_lhs[1]
  extend_expr(p, tok(p, i)[1], lhs, j, min_bp)
end

@doc """
extend_expr: lhs with every postfix and infix operator from i applied: a
send, a call, an index, then an infix row whose left power reaches min_bp.

    extend_expr({toks: lex("a"), last: 1, r: reading}, 0, nil, 1, 0) #=> [nil, 1]
"""
def extend_expr(p, start, lhs, i, min_bp)
  t = tok(p, i)
  if t[0] == :dot
    got_n = send(p, start, lhs, i)
    n = got_n[0]
    j = got_n[1]
    extend_expr(p, start, n, j, min_bp)
  elsif t[0] == :lparen
    got_args = arguments(p, i)
    args = got_args[0]
    j = got_args[1]
    n = node(
      "call",
      [start, ended(p, j)],
      args[:anchor],
      [["function", lhs], ["arguments", args]]
    )
    extend_expr(p, start, n, j, min_bp)
  elsif t[0] == :lbracket and touches?(p, i)
    got_n = index(p, start, lhs, i)
    n = got_n[0]
    j = got_n[1]
    extend_expr(p, start, n, j, min_bp)
  elsif is?(t, :op, "?") and touches?(p, i)
    outside("`?`")
  elsif is?(t, :ident, "rescue") and min_bp == 0
    outside("`rescue`")
  else
    infix(p, start, lhs, i, min_bp)
  end
end

@doc """
infix_row: The pipe or the infix row the token t spells, or nil.

    infix_row(reading, [:op, 0, 2, "&&"])[:callee] #=> "and"
"""
def infix_row(r, t)
  if t[0] == :pipe
    r[:pipe]
  elsif t[0] == :op or t[0] == :ident
    retsu::find_first((row) -> member?(t[3], spellings(row)), r[:infix])
  end
end

@doc """
spellings: A row's operator and its aliases.

    spellings({op: "-", aliases: ["−"]}) #=> ["-", "−"]
"""
def spellings(row)
  cons(row[:op], row[:aliases])
end

@doc """
infix: lhs joined by the infix operator at i, when its left power reaches
min_bp, then extended further.

    infix({toks: lex("a"), last: 1, r: reading}, 0, nil, 1, 0) #=> [nil, 1]
"""
def infix(p, start, lhs, i, min_bp)
  t = tok(p, i)
  row = infix_row(p[:r], t)
  if row.nil? or row[:power][0] < min_bp
    [lhs, i]
  else
    got_rhs = expr(p, skip_newlines(p, i + 1), row[:power][1])
    rhs = got_rhs[0]
    j = got_rhs[1]
    kind = if row[:callee].nil?
      "pipe_expression"
    else
      "binary_expression"
    end
    n = node(
      kind,
      [start, ended(p, j)],
      span_of(t),
      [["left", lhs], ["operator", leaf("operator", t)], ["right", rhs]]
    )
    extend_expr(p, start, n, j, min_bp)
  end
end

@doc """
literal_kind: The rule a literal token is read by, or nil.

    literal_kind(:interp) #=> "string"
"""
def literal_kind(k)
  case k
  when :int
    "integer"
  when :float
    "float"
  when :str
    "string"
  when :interp
    "string"
  when :sym
    "symbol"
  when :words
    "word_list"
  when :true
    "true"
  when :false
    "false"
  when :nil
    "nil"
  end
end

@doc """
prefix: The expression that starts at i, before any operator, and the index after it.

    prefix({toks: lex("1"), last: 1, r: reading}, 0)[0][:kind] #=> "integer"
"""
def prefix(p, i)
  t = tok(p, i)
  k = t[0]
  if literal_kind(k) != nil
    [leaf(literal_kind(k), t), i + 1]
  elsif k == :lparen
    paren(p, i)
  elsif k == :lbracket
    list_literal(p, i)
  elsif k == :lbrace
    map_literal(p, i)
  elsif k == :op
    unary(p, i)
  elsif k == :ident
    named_form(p, i)
  else
    raise(:parse, "expected an expression, found #{k}")
  end
end

@doc """
named_form: What an identifier at i starts: a qualified name, a form its
keyword opens, a negation, or a name.

    named_form({toks: lex("x"), last: 1, r: reading}, 0)[0][:kind] #=> "identifier"
"""
def named_form(p, i)
  t = tok(p, i)
  w = t[3]
  next_kind = tok(p, i + 1)[0]
  if next_kind == :path_sep
    qualified(p, i)
  elsif w == "if" or w == "unless"
    if_form(p, i, w)
  elsif w == "def"
    def_form(p, i)
  elsif w == "fn"
    lambda_form(p, i)
  elsif w == "not"
    not_form(p, i)
  elsif (w == "and" or w == "or") and next_kind == :lparen
    [leaf("identifier", t), i + 1]
  elsif w == "begin" and next_kind == :lparen and touches?(p, i + 1)
    [leaf("identifier", t), i + 1]
  elsif reserved?(p, w)
    outside("`#{w}`")
  else
    [leaf("identifier", t), i + 1]
  end
end

@doc """
qualified: `pkg::name` (or a path of levels) at i, one name.

    qualified({toks: lex("a::b"), last: 3, r: reading}, 0)[1] #=> 3
"""
def qualified(p, i)
  t = tok(p, i)
  if reserved?(p, t[3])
    raise(:parse, "`#{t[3]}` is a reserved word and cannot name a package")
  end
  qualified_from(p, t, t[3], i + 1)
end

@doc """
qualified_from: The rest of a qualified name from the `::` at i, its levels so far in path.

    qualified_from({toks: lex("a::b"), last: 3, r: reading}, [:ident, 0, 1, "a"], "a", 1)[0][:end] #=> 4
"""
def qualified_from(p, head, path, i)
  nt = tok(p, i + 1)
  name = case nt[0]
  when :ident
    nt[3]
  when :true
    "true"
  when :false
    "false"
  when :nil
    "nil"
  else
    raise(:parse, "expected a name after `::`")
  end
  if tok(p, i + 2)[0] == :path_sep
    if reserved?(p, name)
      raise(:parse, "`#{name}` is a reserved word and cannot name a level")
    end
    qualified_from(p, head, join([path, name], "/"), i + 2)
  else
    [
      node(
        "qualified_name",
        [head[1], nt[2]],
        span_of(head),
        [
          ["package", leaf("package", [:ident, head[1], nt[1], path])],
          ["name", leaf("identifier", [:ident, nt[1], nt[2], name])]
        ]
      ),
      i + 2
    ]
  end
end

@doc """
paren: An arrow lambda or a parenthesized expression at the `(` at i.

    paren({toks: lex("(a)"), last: 3, r: reading}, 0)[1] #=> 3
"""
def paren(p, i)
  t = tok(p, i)
  if arrow_ahead?(p, i + 1)
    arrow_lambda(p, i)
  else
    got_inner = expr(p, skip_newlines(p, i + 1), 0)
    inner = got_inner[0]
    j = got_inner[1]
    k = expect(p, skip_newlines(p, j), :rparen)
    [
      node(
        "parenthesized_expression",
        [t[1], ended(p, k)],
        span_of(t),
        [["expression", inner]]
      ),
      k
    ]
  end
end

@doc """
arrow_ahead?: Whether the tokens from i are a parameter list, `)`, then `->`.

    arrow_ahead?({toks: lex("a) -> a"), last: 4}, 0) #=> true
"""
def arrow_ahead?(p, i)
  close = if tok(p, i)[0] == :rparen
    i
  else
    arrow_close(p, i)
  end
  close != nil and is?(tok(p, close + 1), :op, "->")
end

@doc """
arrow_close: The index of the `)` that closes a list of names from i, or nil.

    arrow_close({toks: lex("a, *b)"), last: 5}, 0) #=> 4
"""
def arrow_close(p, i)
  j = if is?(tok(p, i), :op, "*")
    i + 1
  else
    i
  end
  after = tok(p, j + 1)[0]
  if tok(p, j)[0] != :ident
    nil
  elsif after == :comma
    arrow_close(p, j + 2)
  elsif after == :rparen
    j + 1
  end
end

@doc """
arrow_lambda: `(a, b) -> expr` at the `(` at i.

    arrow_lambda({toks: lex("() -> 1"), last: 4, r: reading}, 0)[1] #=> 4
"""
def arrow_lambda(p, i)
  t = tok(p, i)
  got_params = arrow_params(p, i + 1, [])
  params = got_params[0]
  j = got_params[1]
  got_body = expr(p, skip_newlines(p, j + 2), 0)
  body = got_body[0]
  k = got_body[1]
  [
    node(
      "arrow_lambda",
      [t[1], ended(p, k)],
      span_of(t),
      [
        ["parameters", node("parameters", span_of(t), span_of(t), params)],
        ["body", body]
      ]
    ),
    k
  ]
end

@doc """
arrow_params: An arrow lambda's names from i up to its `)`, and that `)`'s index.

    arrow_params({toks: lex("a, b)"), last: 4}, 0, [])[1] #=> 3
"""
def arrow_params(p, i, acc)
  t = tok(p, i)
  if t[0] == :rparen
    [reverse(acc), i]
  elsif t[0] == :ident
    j = if tok(p, i + 1)[0] == :comma
      i + 2
    else
      i + 1
    end
    arrow_params(p, j, cons(["parameter", leaf("identifier", t)], acc))
  else
    outside("a rest parameter")
  end
end

@doc """
lambda_form: `fn(a, b) … end` at the `fn` at i.

    lambda_form({toks: lex("fn end"), last: 2, r: reading}, 0)[1] #=> 2
"""
def lambda_form(p, i)
  t = tok(p, i)
  got_params = if tok(p, i + 1)[0] == :lparen
    names(p, skip_newlines(p, i + 2), [])
  else
    [[], i + 1]
  end
  params = got_params[0]
  j = got_params[1]
  got_b = body(p, j, ["end"])
  b = got_b[0]
  k = got_b[1]
  m = expect_word(p, k, "end")
  [
    node(
      "lambda",
      [t[1], ended(p, m)],
      span_of(t),
      [
        ["parameters", node("parameters", span_of(t), span_of(t), params)],
        ["body", b]
      ]
    ),
    m
  ]
end

@doc """
names: A `fn`'s parameter names from i through its `)`, and the index after it.

    names({toks: lex("a)"), last: 2}, 0, [])[1] #=> 2
"""
def names(p, i, acc)
  t = tok(p, i)
  if t[0] == :rparen
    [reverse(acc), i + 1]
  elsif t[0] != :ident
    outside("a rest parameter")
  else
    more = cons(["parameter", leaf("identifier", t)], acc)
    j = skip_newlines(p, i + 1)
    if tok(p, j)[0] == :comma
      names(p, skip_newlines(p, j + 1), more)
    else
      names(p, expect(p, j, :rparen) - 1, more)
    end
  end
end

@doc """
unary: A prefix operator at i and the operand it binds at its row's power.

    unary({toks: lex("-x"), last: 2, r: reading}, 0)[0][:kind] #=> "unary_expression"
"""
def unary(p, i)
  t = tok(p, i)
  row = retsu::find_first((u) -> member?(t[3], spellings(u)), p[:r][:unary])
  if row.nil?
    raise(:parse, "expected an expression, found `#{t[3]}`")
  end
  got_operand = expr(p, i + 1, row[:power])
  operand = got_operand[0]
  j = got_operand[1]
  [negation_node(p, t, operand, j), j]
end

@doc """
negation_node: The unary node of the operator token t over operand, ending before j.

    negation_node({toks: lex("!x")}, [:op, 0, 1, "!"], nil, 2)[:end] #=> 2
"""
def negation_node(p, t, operand, j)
  node(
    "unary_expression",
    [t[1], ended(p, j)],
    span_of(t),
    [["operator", leaf("operator", t)], ["operand", operand]]
  )
end

@doc """
not_form: `not x`, or `not(x)` touching its argument; `not(a, b)` is a call.

    not_form({toks: lex("not(x)"), last: 4, r: reading}, 0)[0][:kind] #=> "unary_expression"
"""
def not_form(p, i)
  t = tok(p, i)
  if tok(p, i + 1)[0] == :lparen and touches?(p, i + 1)
    got_args = arguments(p, i + 1)
    args = got_args[0]
    j = got_args[1]
    kids = args[:fields]
    if count(kids) == 1 and kids[0][1][:kind] != "splat"
      [negation_node(p, t, kids[0][1], j), j]
    else
      [
        node(
          "call",
          [t[1], ended(p, j)],
          args[:anchor],
          [["function", leaf("identifier", t)], ["arguments", args]]
        ),
        j
      ]
    end
  else
    unary(p, i)
  end
end

@doc """
is passed, which is where `apply` sits.

    arguments({toks: lex("()"), last: 2, r: reading}, 0)[1] #=> 2
"""
def arguments(p, i)
  open = tok(p, i)
  j = skip_newlines(p, i + 1)
  if tok(p, j)[0] == :rparen
    [argument_node(p, open, [], j + 1), j + 1]
  else
    argument_list(p, open, j, [])
  end
end

@doc """
argument_node: The arguments node over the children kids, ending before j.

    argument_node({toks: lex("()")}, [:lparen, 0, 1, nil], [], 2)[:end] #=> 2
"""
def argument_node(p, open, kids, j)
  splat = retsu::find_first((k) -> k[1][:kind] == "splat", kids)
  anchor = if splat.nil?
    span_of(open)
  else
    splat[1][:anchor]
  end
  node("arguments", [open[1], ended(p, j)], anchor, kids)
end

@doc """
argument_list: The arguments from i on, onto acc latest first: positional
ones, a splat last, or keyword entries with a `**` spread.

    argument_list({toks: lex("a)"), last: 2, r: reading}, [:lparen, 0, 0, nil], 0, [])[1] #=> 2
"""
def argument_list(p, open, i, acc)
  j = skip_newlines(p, i)
  t = tok(p, j)
  if acc != [] and first(acc)[1][:kind] == "splat"
    raise(:parse, "a splat `*xs` passes a list as the LAST arguments")
  end
  if is?(t, :op, "**") or t[0] == :label
    got_entries = map_entries(p, j, :rparen, [])
    entries = got_entries[0]
    k = got_entries[1]
    if not any?((e) -> e[0] == "spread", entries)
      raise(:parse, "a keyword entry in a call needs a `**` spread")
    end
    kw = node("keyword_arguments", [t[1], ended(p, k)], span_of(t), entries)
    [argument_node(p, open, reverse(cons([nil, kw], acc)), k), k]
  else
    got_e = if is?(t, :op, "*")
      got_v = expr(p, j + 1, 0)
      v = got_v[0]
      m = got_v[1]
      [node("splat", [t[1], ended(p, m)], span_of(t), [["list", v]]), m]
    else
      expr(p, j, 0)
    end
    e = got_e[0]
    k = got_e[1]
    more = cons([nil, e], acc)
    m = skip_newlines(p, k)
    if tok(p, m)[0] == :comma
      after = skip_newlines(p, m + 1)
      if tok(p, after)[0] == :rparen
        [argument_node(p, open, reverse(more), after + 1), after + 1]
      else
        argument_list(p, open, after, more)
      end
    else
      n = expect(p, m, :rparen)
      [argument_node(p, open, reverse(more), n), n]
    end
  end
end

@doc """
map_entries: Map entries from i through the closer, `[field, node]` each, and
the index after the closer.

    map_entries({toks: lex("a: 1}"), last: 3, r: reading}, 0, :rbrace, [])[1] #=> 3
"""
def map_entries(p, i, closer, acc)
  j = skip_newlines(p, i)
  got_entry = if is?(tok(p, j), :op, "**")
    spread(p, j)
  else
    map_entry(p, j, closer)
  end
  entry = got_entry[0]
  k = got_entry[1]
  more = cons(entry, acc)
  m = skip_newlines(p, k)
  if tok(p, m)[0] == :comma
    after = skip_newlines(p, m + 1)
    if tok(p, after)[0] == closer
      [reverse(more), after + 1]
    else
      map_entries(p, after, closer, more)
    end
  else
    [reverse(more), expect(p, m, closer)]
  end
end

@doc """
spread: `**m` at i; it spans from `**` to the end of m's own span.

    spread({toks: lex("**m"), last: 2, r: reading}, 0)[0][0] #=> "spread"
"""
def spread(p, i)
  t = tok(p, i)
  got_v = expr(p, i + 1, 0)
  v = got_v[0]
  j = got_v[1]
  lv = lower_one(p[:r], v)
  [["spread", node("spread", [t[1], lv[1]], span_of(t), [["map", v]])], j]
end

@doc """
map_entry: One `key: value`, `key:` or `k => v` entry at i.

    map_entry({toks: lex("a:}"), last: 2, r: reading}, 0, :rbrace)[0][1][:kind] #=> "pun_pair"
"""
def map_entry(p, i, closer)
  t = tok(p, i)
  if t[0] == :label
    key = leaf("label", t)
    k = skip_newlines(p, i + 1)
    after = tok(p, k)[0]
    if after == :comma or after == closer
      [[nil, node("pun_pair", span_of(t), span_of(t), [["key", key]])], k]
    else
      got_v = expr(p, k, 0)
      v = got_v[0]
      m = got_v[1]
      [
        [
          nil,
          node(
            "pair",
            [t[1], ended(p, m)],
            span_of(t),
            [["key", key], ["value", v]]
          )
        ],
        m
      ]
    end
  else
    got_key = expr(p, i, 0)
    key = got_key[0]
    k = got_key[1]
    m = expect(p, skip_newlines(p, k), :rocket)
    got_v = expr(p, skip_newlines(p, m), 0)
    v = got_v[0]
    n = got_v[1]
    [
      [
        nil,
        node(
          "rocket_pair",
          [t[1], ended(p, n)],
          span_of(t),
          [["key", key], ["value", v]]
        )
      ],
      n
    ]
  end
end

@doc """
list_literal: `[a, b]` at the `[` at i; `*rest` takes a list pattern's rest.

    list_literal({toks: lex("[]"), last: 2, r: reading}, 0)[1] #=> 2
"""
def list_literal(p, i)
  open = tok(p, i)
  j = skip_newlines(p, i + 1)
  got_kids = if tok(p, j)[0] == :rbracket
    [[], j + 1]
  else
    elements(p, j, [])
  end
  kids = got_kids[0]
  k = got_kids[1]
  [node("list", [open[1], ended(p, k)], span_of(open), kids), k]
end

@doc """
elements: A list literal's elements from i through its `]`, and the index after
it; a pattern's `*rest` is refused, patterns being outside this slice.

    elements({toks: lex("1]"), last: 2, r: reading}, 0, [])[1] #=> 2
"""
def elements(p, i, acc)
  j = skip_newlines(p, i)
  t = tok(p, j)
  if is?(t, :op, "*")
    outside("a list pattern's `*rest`")
  end
  got_e = expr(p, j, 0)
  e = got_e[0]
  k = got_e[1]
  more = cons([nil, e], acc)
  m = skip_newlines(p, k)
  if tok(p, m)[0] == :comma
    after = skip_newlines(p, m + 1)
    if tok(p, after)[0] == :rbracket
      [reverse(more), after + 1]
    else
      elements(p, after, more)
    end
  else
    [reverse(more), expect(p, m, :rbracket)]
  end
end

@doc """
map_literal: `{…}` at the `{` at i.

    map_literal({toks: lex("{}"), last: 2, r: reading}, 0)[1] #=> 2
"""
def map_literal(p, i)
  open = tok(p, i)
  j = skip_newlines(p, i + 1)
  got_kids = if tok(p, j)[0] == :rbrace
    [[], j + 1]
  else
    map_entries(p, j, :rbrace, [])
  end
  kids = got_kids[0]
  k = got_kids[1]
  [node("map", [open[1], ended(p, k)], span_of(open), kids), k]
end

@doc """
index: `x[k]` from the `[` at i: a keyword or string key reads a map, any
other key a list position.

    index({toks: lex("x[:a]"), last: 4, r: reading}, 0, nil, 1)[0][:fields][1][0] #=> "key"
"""
def index(p, start, object, i)
  open = tok(p, i)
  got_key = expr(p, skip_newlines(p, i + 1), 0)
  key = got_key[0]
  j = got_key[1]
  k = expect(p, skip_newlines(p, j), :rbracket)
  lk = lower_one(p[:r], key)
  role = if lk[2] == :kw or lk[2] == :str
    "key"
  else
    "position"
  end
  [
    node(
      "index",
      [start, ended(p, k)],
      span_of(open),
      [["object", object], [role, key]]
    ),
    k
  ]
end

@doc """
send: `recv.name` or `recv.name(args)` from the `.` at i.

    send({toks: lex("x.y"), last: 3, r: reading}, 0, nil, 1)[1] #=> 3
"""
def send(p, start, recv, i)
  dot = tok(p, i)
  nt = tok(p, i + 1)
  if nt[0] != :ident or reserved?(p, nt[3])
    raise(:parse, "expected a method name after `.`")
  end
  head = [["receiver", recv], ["method", leaf("identifier", nt)]]
  if tok(p, i + 2)[0] == :lparen
    got_args = arguments(p, i + 2)
    args = got_args[0]
    j = got_args[1]
    anchor = if args[:anchor] == span_of(tok(p, i + 2))
      span_of(dot)
    else
      args[:anchor]
    end
    [
      node(
        "send",
        [start, ended(p, j)],
        anchor,
        concat_lists(head, [["arguments", args]])
      ),
      j
    ]
  else
    [node("send", [start, nt[2]], span_of(dot), head), i + 2]
  end
end

@doc """
if_form: `if`, `unless` or `elsif` (kind) at i, through the `end` of its chain.

    if_form({toks: lex("if a end"), last: 3, r: reading}, 0, "if")[1] #=> 3
"""
def if_form(p, i, kind)
  t = tok(p, i)
  got_condition = expr(p, i + 1, 0)
  condition = got_condition[0]
  j = got_condition[1]
  got_then = body(p, j, %w[elsif else end])
  then = got_then[0]
  k = got_then[1]
  got_alt = else_part(p, k)
  alt = got_alt[0]
  m = got_alt[1]
  fields = [["condition", condition], ["consequence", then]]
  [
    node(
      kind,
      [t[1], ended(p, m)],
      span_of(t),
      if alt.nil?
        fields
      else
        concat_lists(fields, [["alternative", alt]])
      end
    ),
    m
  ]
end

@doc """
else_part: An `elsif` chain, an `else` body, or nothing, through `end`; an
`else` whose body is nil and holds no comment is dropped.

    else_part({toks: lex("end"), last: 1, r: reading}, 0) #=> [nil, 1]
"""
def else_part(p, i)
  t = tok(p, i)
  if is?(t, :ident, "elsif")
    if_form(p, i, "elsif")
  elsif not is?(t, :ident, "else")
    [nil, expect_word(p, i, "end")]
  else
    got_b = body(p, i + 1, ["end"])
    b = got_b[0]
    j = got_b[1]
    k = expect_word(p, j, "end")
    dropped = lower_one(p[:r], b)[2] == :nil and
      not any?((c) -> c >= t[1] and c < tok(p, j)[1], p[:comments])
    if dropped
      [nil, k]
    else
      [node("else", [t[1], ended(p, k)], span_of(t), [["body", b]]), k]
    end
  end
end

@doc """
body: The statements from i up to one of the closing words, as one body node
whose span is where the body starts (an empty body's nil sits there).

    body({toks: lex("end"), last: 1, r: reading}, 0, ["end"])[1] #=> 0
"""
def body(p, i, closers)
  at = [tok(p, i)[1], tok(p, i)[1]]
  got_stmts = statements(p, i, closers, [])
  stmts = got_stmts[0]
  j = got_stmts[1]
  [node("body", at, at, stmts), j]
end

@doc """
statements: Statements from i until a closing word, `[nil, node]` each, and
the index of that word.

    statements({toks: lex("end"), last: 1, r: reading}, 0, ["end"], []) #=> [[], 0]
"""
def statements(p, i, closers, acc)
  j = skip_newlines(p, i)
  t = tok(p, j)
  if t[0] == :eof
    raise(:parse, "unterminated block: expected `#{first(closers)}`")
  elsif t[0] == :ident and member?(t[3], closers)
    [reverse(acc), j]
  else
    got_s = statement(p, j)
    s = got_s[0]
    k = got_s[1]
    end_of_statement(p, k, closers)
    statements(p, k, closers, cons([nil, s], acc))
  end
end

@doc """
def_form: `def name(params) -> T … end` at the `def` at i.

    def_form({toks: lex("def f end"), last: 3, r: reading}, 0)[1] #=> 3
"""
def def_form(p, i)
  t = tok(p, i)
  nt = tok(p, i + 1)
  if nt[0] != :ident or reserved?(p, nt[3])
    raise(:parse, "expected a name after `def`")
  end
  got_params = if tok(p, i + 2)[0] == :lparen
    parameters(p, skip_newlines(p, i + 3), false, [])
  else
    [[], i + 2]
  end
  params = got_params[0]
  j = got_params[1]
  sig_end = ended(p, j)
  got_ret = if is?(tok(p, j), :op, "->")
    got_ty = type_expr(p, skip_newlines(p, j + 1))
    ty = got_ty[0]
    m = got_ty[1]
    [[["return_type", ty]], m]
  else
    [[], j]
  end
  ret = got_ret[0]
  k = got_ret[1]
  got_b = body(p, k, %w[rescue ensure end])
  b = got_b[0]
  m = got_b[1]
  n = expect_word(p, m, "end")
  fields = concat_lists(
    [
      ["name", leaf("identifier", nt)],
      ["parameters", node("parameters", span_of(t), span_of(t), params)]
    ],
    concat_lists(ret, [["body", b]])
  )
  [
    assoc(
      node("def", [t[1], ended(p, n)], span_of(t), fields),
      :close,
      sig_end
    ),
    n
  ]
end

@doc """
optional?: Whether a parameter name marks it optional: it ends in `?` and is more than `?`.

    optional?("a?") #=> true
"""
def optional?(name)
  ends_with?(name, "?") and name != "?"
end

@doc """
ends in `?` (optional), a later required one is refused.

    parameters({toks: lex("a)"), last: 2, r: reading}, 0, false, [])[1] #=> 2
"""
def parameters(p, i, seen, acc)
  t = tok(p, i)
  if t[0] == :rparen
    [reverse(acc), i + 1]
  elsif not (t[0] == :ident or t[0] == :label) or reserved?(p, t[3])
    outside("this parameter")
  elsif seen and not optional?(t[3])
    raise(
      :parse,
      "the required parameter `#{t[3]}` cannot follow an optional one"
    )
  else
    got_param = if t[0] == :ident
      [leaf("identifier", t), i + 1]
    else
      got_ty = type_expr(p, skip_newlines(p, i + 1))
      ty = got_ty[0]
      m = got_ty[1]
      [
        node(
          "typed_parameter",
          [t[1], ty[:end]],
          span_of(t),
          [["name", leaf("label", t)], ["type", ty]]
        ),
        m
      ]
    end
    param = got_param[0]
    k = got_param[1]
    more = cons(["parameter", param], acc)
    j = skip_newlines(p, k)
    again = seen or optional?(t[3])
    if tok(p, j)[0] == :comma
      parameters(p, skip_newlines(p, j + 1), again, more)
    else
      parameters(p, expect(p, j, :rparen) - 1, again, more)
    end
  end
end

@doc """
type_expr: A type at i: a name, a qualified name, or a constructor over types.

    type_expr({toks: lex("Int"), last: 1, r: reading}, 0)[1] #=> 1
"""
def type_expr(p, i)
  t = tok(p, i)
  if t[0] != :ident or reserved?(p, t[3])
    raise(:parse, "expected a type name")
  end
  after = tok(p, i + 1)[0]
  if after == :path_sep
    got_q = qualified(p, i)
    q = got_q[0]
    j = got_q[1]
    [node("type", [q[:start], q[:end]], span_of(t), [["name", q]]), j]
  elsif after == :lparen
    got_args = type_args(p, skip_newlines(p, i + 2), [])
    args = got_args[0]
    j = got_args[1]
    span = [t[1], ended(p, j)]
    [
      node(
        "type",
        span,
        span_of(t),
        [
          ["name", leaf("identifier", t)],
          ["arguments", node("arguments", span, span, args)]
        ]
      ),
      j
    ]
  else
    [
      node("type", span_of(t), span_of(t), [["name", leaf("identifier", t)]]),
      i + 1
    ]
  end
end

@doc """
type_args: A type constructor's arguments from i through its `)`, and the index after it.

    type_args({toks: lex(")"), last: 1, r: reading}, 0, []) #=> [[], 1]
"""
def type_args(p, i, acc)
  if tok(p, i)[0] == :rparen
    [reverse(acc), i + 1]
  else
    got_ty = type_expr(p, i)
    ty = got_ty[0]
    j = got_ty[1]
    more = cons([nil, ty], acc)
    k = skip_newlines(p, j)
    if tok(p, k)[0] == :comma
      type_args(p, skip_newlines(p, k + 1), more)
    else
      type_args(p, expect(p, k, :rparen) - 1, more)
    end
  end
end

@doc """
lower_one: What a concrete node means, one node of blue's tree.

    lower_one(reading, leaf("integer", [:int, 0, 1, 7])) #=> [0, 1, :int, 7]
"""
def lower_one(r, n)
  vs = lower(r, n)
  if count(vs) != 1
    raise(:parse, "#{n[:kind]} lowers to #{count(vs)} values, not one")
  end
  vs[0]
end

@doc """
lower: What a concrete node means, by its rule's lowering template in kiwari,
then the rewrites blue's parser makes beside the grammar (`rewritten`).

    lower(reading, leaf("identifier", [:ident, 0, 1, "x"])) #=> [[0, 1, :sym, "x"]]
"""
def lower(r, n)
  rewritten(n, ev(r, get(r[:lower], n[:kind]), n, false))
end

@doc """
child: The child filling a field, or nil.

    child({fields: [["a", 1]]}, "a") #=> 1
"""
def child(n, name)
  hit = retsu::find_first((f) -> f[0] == name, n[:fields])
  if hit != nil
    hit[1]
  end
end

@doc """
named: Every child of a node.

    named({fields: [["a", 1], [nil, 2]]}) #=> [1, 2]
"""
def named(n)
  map((f) -> f[1], n[:fields])
end

@doc """
walk: The nodes a template path reaches: a field name selects the children
filling it, `*` every child.

    walk({fields: [["a", {fields: [[nil, 3]]}]]}, ["a", "*"]) #=> [3]
"""
def walk(n, path)
  reduce(
    fn(at, step)
      flat_map(
        at,
        fn(m)
          if step == "*"
            named(m)
          else
            map((f) -> f[1], filter((f) -> f[0] == step, m[:fields]))
          end
        end
      )
    end,
    [n],
    path
  )
end

@doc """
text: The text a leaf names: its token's payload.

    text(leaf("label", [:label, 0, 2, "a"])) #=> "a"
"""
def text(n)
  n[:tok][3]
end

@doc """
atom: A node of blue's tree at a span.

    atom([1, 2], :sym, "x") #=> [1, 2, :sym, "x"]
"""
def atom(span, kind, payload)
  [span[0], span[1], kind, payload]
end

@doc """
ev: A lowering template evaluated on a concrete node: the sequence of nodes
of blue's tree it means. A synthesized atom takes the node's anchor; the
template's outer list takes the node's span, a nested one runs from its first
item to the node's `close` (a signature's `)`) or its last item.

    ev(reading, %w[sym x], node("k", [0, 3], [1, 2], []), false) #=> [[1, 2, :sym, "x"]]
"""
def ev(r, t, n, inner)
  h = t[0]
  if h == "sym"
    [atom(n[:anchor], :sym, t[1])]
  elsif h == "int"
    [atom(n[:anchor], :int, t[1])]
  elsif h == "nil"
    [atom(n[:anchor], :nil, nil)]
  elsif h == "list"
    [list_of(n, flat_map(rest(t), (x) -> ev(r, x, n, true)), inner)]
  elsif h == "seq"
    flat_map(rest(t), (x) -> ev(r, x, n, inner))
  elsif h == "field"
    c = child(n, t[1])
    if c != nil
      lower(r, c)
    elsif count(t) > 2
      ev(r, t[2], n, inner)
    else
      raise(:parse, "#{n[:kind]} has no `#{t[1]}`")
    end
  elsif h == "field?"
    c = child(n, t[1])
    if c.nil?
      []
    else
      lower(r, c)
    end
  elsif h == "each"
    flat_map(walk(n, t[1]), (c) -> ev(r, t[2], c, inner))
  elsif h == "each_param"
    each_param(r, t, n, inner)
  elsif h == "named"
    flat_map(named(n), (c) -> lower(r, c))
  elsif h == "block"
    block(t[1], n, flat_map(named(n), (c) -> lower(r, c)))
  elsif h == "symbol"
    [atom(n[:anchor], :sym, text(n))]
  elsif h == "param_symbol"
    [atom(n[:anchor], :sym, param_name(n))]
  elsif h == "symbol_of"
    c = child(n, t[1])
    [atom(c[:anchor], :sym, text(c))]
  elsif h == "keyword"
    [atom(n[:anchor], :kw, text(n))]
  elsif h == "lexeme"
    [lexeme(n[:tok])]
  elsif h == "interpolate"
    [interpolate(r, t[1], n[:tok])]
  elsif h == "qualify"
    [
      atom(
        [n[:start], n[:end]],
        :sym,
        join([text(child(n, t[1])), text(child(n, t[2]))], "/")
      )
    ]
  elsif h == "callee"
    op = child(n, t[1])
    [atom(op[:anchor], :sym, infix_row(r, op[:tok])[:callee])]
  elsif h == "unary"
    op = text(child(n, t[1]))
    row = retsu::find_first((u) -> member?(op, spellings(u)), r[:unary])
    ev(r, row[:head], n, inner)
  elsif h == "thread"
    [threaded(n, lower_one(r, child(n, t[1])), lower_one(r, child(n, t[2])))]
  elsif h == "if_any"
    if any?((path) -> walk(n, path) != [], t[1])
      ev(r, t[2], n, inner)
    else
      ev(r, t[3], n, inner)
    end
  elsif h == "if_kind"
    ev(
      r,
      if n[:kind] == t[1]
        t[2]
      else
        t[3]
      end,
      n,
      inner
    )
  elsif h == "runs"
    runs(r, t[1], t[2], n)
  else
    outside("the lowering `#{h}`")
  end
end

@doc """
list_of: A list node of items: an outer list spans its concrete node, a
nested one its first item to the node's `close` or its last item, an empty
nested one the anchor.

    list_of({start: 0, end: 4, anchor: [0, 1]}, [], true) #=> [0, 1, :list, []]
"""
def list_of(n, items, inner)
  span = if not inner
    [n[:start], n[:end]]
  elsif items == []
    n[:anchor]
  elsif n[:close] != nil
    [items[0][0], n[:close]]
  else
    [items[0][0], last(items)[1]]
  end
  atom(span, :list, items)
end

@doc """
block: A body's forms: nil at the body's span when none, the form when one,
else `(head …)` over them with a zero-width head at the first.

    block("begin", {start: 3, end: 3}, []) #=> [[3, 3, :nil, nil]]
"""
def block(head, n, items)
  if items == []
    [[n[:start], n[:end], :nil, nil]]
  elsif count(items) == 1
    items
  else
    s = items[0][0]
    e = reduce((m, x) -> kazu::max(m, x[1]), s, items)
    [[s, e, :list, cons([s, s, :sym, head], items)]]
  end
end

@doc """
param_name: A parameter's name: an optional one's `?` taken off.

    param_name(leaf("identifier", [:ident, 0, 2, "a?"])) #=> "a"
"""
def param_name(n)
  named_leaf = if n[:kind] == "typed_parameter"
    child(n, "name")
  else
    n
  end
  w = text(named_leaf)
  if optional?(w)
    join(all_but_last(chars(w)), "")
  else
    w
  end
end

@doc """
each_param: Each parameter on a path lowered by a template, the optional
marker before the first optional one.

    each_param(reading, ["each_param", ["*"], ["param_symbol"]], {fields: [[nil, leaf("identifier", [:ident, 0, 2, "a?"])]]}, true) #=> [[0, 2, :sym, "&optional"], [0, 2, :sym, "a"]]
"""
def each_param(r, t, n, inner)
  nth(
    0,
    reduce(
      fn(acc, c)
        mark = if not acc[1] and optional?(text(param_leaf(c)))
          [atom(c[:anchor], :sym, "&optional")]
        else
          []
        end
        [
          concat_lists(acc[0], concat_lists(mark, ev(r, t[2], c, inner))),
          acc[1] or mark != []
        ]
      end,
      [[], false],
      walk(n, t[1])
    )
  )
end

@doc """
param_leaf: The leaf that names a parameter.

    param_leaf({kind: "identifier"})[:kind] #=> "identifier"
"""
def param_leaf(c)
  if c[:kind] == "typed_parameter"
    child(c, "name")
  else
    c
  end
end

@doc """
lexeme: The value a literal token spells, at its span; a word list is
`(list …)` with `list` over its opening `%w[` and each word at its own span.

    lexeme([:true, 0, 4, nil]) #=> [0, 4, :bool, true]
"""
def lexeme(t)
  case t[0]
  when :int
    atom(span_of(t), :int, t[3])
  when :float
    atom(span_of(t), :float, t[3])
  when :true
    atom(span_of(t), :bool, true)
  when :false
    atom(span_of(t), :bool, false)
  when :nil
    atom(span_of(t), :nil, nil)
  else
    kind = if t[3][0] == :keywords
      :kw
    else
      :str
    end
    atom(
      span_of(t),
      :list,
      cons(
        [t[1], t[1] + 3, :sym, "list"],
        map((w) -> [w[1], w[2], kind, w[0]], t[3][1])
      )
    )
  end
end

@doc """
interpolate: A string token's meaning: the text, or its parts joined by join
around each interpolation; one holding a line break reads as its lines
(`lines_literal`). Every node takes the whole literal's span.

    interpolate(reading, "concat", [:str, 0, 3, "a"]) #=> [0, 3, :str, "a"]
"""
def interpolate(r, join, t)
  got_parts = if t[0] == :str
    [[t[3]], []]
  else
    t[3]
  end
  parts = got_parts[0]
  exprs = got_parts[1]
  if any?((x) -> contains?(x, line_break), parts)
    lines_literal(r, join, span_of(t), parts, exprs)
  else
    interpolation(r, join, span_of(t), parts, exprs)
  end
end

@doc """
interpolation: `(join (join part expr) part)` over the parts and the
expressions between them, every node at span.

    interpolation(reading, "concat", [0, 3], ["a"], []) #=> [0, 3, :str, "a"]
"""
def interpolation(r, join, span, parts, exprs)
  reduce(
    fn(acc, i)
      inner = [
        span[0],
        span[1],
        :list,
        [atom(span, :sym, join), acc, interpolated(r, span, exprs[i])]
      ]
      [
        span[0],
        span[1],
        :list,
        [atom(span, :sym, join), inner, atom(span, :str, parts[i + 1])]
      ]
    end,
    atom(span, :str, parts[0]),
    range(0, count(exprs))
  )
end

@doc """
interpolated: The one statement an interpolation's source holds, at span.

    interpolated(reading, [0, 5], "x") #=> [0, 5, :sym, "x"]
"""
def interpolated(r, span, raw)
  forms = parse_tokens(r, lex(raw))
  if count(forms) != 1
    raise(:parse, "an interpolation holds one expression")
  end
  respan(forms[0], span)
end

@doc """
respan: A tree with every node at span.

    respan([0, 1, :list, [[0, 1, :int, 1]]], [5, 6]) #=> [5, 6, :list, [[5, 6, :int, 1]]]
"""
def respan(v, span)
  payload = if v[2] == :list
    map((x) -> respan(x, span), v[3])
  else
    v[3]
  end
  [span[0], span[1], v[2], payload]
end

@doc """
lines_literal: A string holding a line break read as the lines it spells
(B0065): `line_break` alone, `unlines([…])` when it ends in one, else
`join_lines([…])`; a line that is one interpolation is that expression.

    lines_literal(reading, "concat", [0, 4], [line_break], []) #=> [0, 4, :sym, "line_break"]
"""
def lines_literal(r, join, span, parts, exprs)
  lines = reduce(
    fn(acc, i)
      pieces = split(parts[i], line_break)
      got_lits = last(acc)
      lits = got_lits[0]
      raws = got_lits[1]
      head = concat_lists(
        all_but_last(acc),
        [
          [
            concat_lists(
              all_but_last(lits),
              [concat(last(lits), first(pieces))]
            ),
            raws
          ]
        ]
      )
      grown = concat_lists(head, map((x) -> [[x], []], rest(pieces)))
      if i < count(exprs)
        got_ls = last(grown)
        ls = got_ls[0]
        rs = got_ls[1]
        concat_lists(
          all_but_last(grown),
          [[concat_lists(ls, [""]), concat_lists(rs, [exprs[i]])]]
        )
      else
        grown
      end
    end,
    [[[""], []]],
    range(0, count(parts))
  )
  empty? = (l) -> l[1] == [] and l[0] == [""]
  if count(lines) == 2 and every?(empty?, lines)
    atom(span, :sym, "line_break")
  else
    trailing? = empty?(last(lines))
    kept = if trailing?
      all_but_last(lines)
    else
      lines
    end
    head = if trailing?
      "unlines"
    else
      "join_lines"
    end
    items = map(
      fn(l)
        if l[1] == []
          atom(span, :str, l[0][0])
        elsif count(l[1]) == 1 and every?((x) -> x == "", l[0])
          interpolated(r, span, l[1][0])
        else
          interpolation(r, join, span, l[0], l[1])
        end
      end,
      kept
    )
    [
      span[0],
      span[1],
      :list,
      [
        atom(span, :sym, head),
        [span[0], span[1], :list, cons(atom(span, :sym, "list"), items)]
      ]
    ]
  end
end

@doc """
threaded: `x |> f(a)` as `(f x a)` and `x |> f` as `(f x)`, at the pipe's span.

    threaded({start: 0, end: 6}, [0, 1, :sym, "x"], [5, 6, :sym, "f"]) #=> [0, 6, :list, [[5, 6, :sym, "f"], [0, 1, :sym, "x"]]]
"""
def threaded(n, l, rv)
  items = if rv[2] == :list and rv[3] != []
    retsu::insert(rv[3], 1, l)
  else
    [rv, l]
  end
  [n[:start], n[:end], :list, items]
end

@doc """
runs: A map's entries as `(head …)` runs split by each `apart` entry: a run
before a spread spans its own entries with its head at the first; the last
run spans the node with its head at the anchor.

    runs(reading, "spread", "hash-map", node("map", [0, 2], [0, 1], [])) #=> []
"""
def runs(r, apart, head, n)
  got_out = reduce(
    fn(acc, c)
      if c[:kind] == apart
        [
          concat_lists(
            concat_lists(acc[0], flushed(head, acc[1])),
            lower(r, c)
          ),
          []
        ]
      else
        [acc[0], concat_lists(acc[1], lower(r, c))]
      end
    end,
    [[], []],
    named(n)
  )
  out = got_out[0]
  run = got_out[1]
  if run == []
    out
  else
    concat_lists(
      out,
      [
        atom(
          [n[:start], n[:end]],
          :list,
          cons(atom(n[:anchor], :sym, head), run)
        )
      ]
    )
  end
end

@doc """
flushed: A run before a spread as `(head …)` over its entries, or nothing.

    flushed("hash-map", [[1, 2, :kw, "a"], [4, 5, :int, 1]]) #=> [[1, 5, :list, [[1, 2, :sym, "hash-map"], [1, 2, :kw, "a"], [4, 5, :int, 1]]]]
"""
def flushed(head, run)
  if run == []
    []
  else
    [
      [
        run[0][0],
        last(run)[1],
        :list,
        cons([run[0][0], run[0][1], :sym, head], run)
      ]
    ]
  end
end

@doc """
rewritten: The rewrites blue's parser makes beside the grammar's lowering: a
nil comparison (`x == nil` is `x.nil?`), a negated comparison (`not (a == b)`
is `a != b`), and a pipe into `not`, a one-armed `if` or `==`.

    rewritten({kind: "integer"}, [[0, 1, :int, 1]]) #=> [[0, 1, :int, 1]]
"""
def rewritten(n, vs)
  k = n[:kind]
  if k == "binary_expression" or k == "call"
    [nil_tested(vs[0])]
  elsif k == "unary_expression"
    [negated(vs[0])]
  elsif k == "unless"
    v = vs[0]
    [[v[0], v[1], :list, cons(v[3][0], cons(negated(v[3][1]), drop(2, v[3])))]]
  elsif k == "pipe_expression"
    [piped(vs[0])]
  else
    vs
  end
end

@doc """
head_is?: Whether a node is a list of n items headed by the symbol h.

    head_is?([0, 3, :list, [[0, 1, :sym, "not"], [2, 3, :sym, "x"]]], "not", 2) #=> true
"""
def head_is?(v, h, n)
  v[2] == :list and count(v[3]) == n and v[3][0][2] == :sym and v[3][0][3] == h
end

@doc """
nil_test: `(blue-field x :nil?)` for a comparison of x with nil, its head and
keyword at the operator's span; nil when neither side alone is nil.

    nil_test([0, 8], [2, 4], [0, 1, :sym, "x"], [5, 8, :nil, nil]) #=> [0, 8, :list, [[2, 4, :sym, "blue-field"], [0, 1, :sym, "x"], [2, 4, :kw, "nil?"]]]
"""
def nil_test(span, op, a, b)
  subject = if b[2] == :nil and a[2] != :nil
    a
  elsif a[2] == :nil and b[2] != :nil
    b
  end
  if subject != nil
    [
      span[0],
      span[1],
      :list,
      [atom(op, :sym, "blue-field"), subject, atom(op, :kw, "nil?")]
    ]
  end
end

@doc """
nil_tested: An `equal?` of two operands as its nil test when it is one.

    nil_tested([0, 1, :int, 1]) #=> [0, 1, :int, 1]
"""
def nil_tested(v)
  hit = if head_is?(v, "equal?", 3)
    nil_test([v[0], v[1]], [v[3][0][0], v[3][0][1]], v[3][1], v[3][2])
  end
  if hit.nil?
    v
  else
    hit
  end
end

@doc """
negated: `(not (equal? a b))` as `(not= a b)` and `(not (not= a b))` as
`(equal? a b)` (then its nil test), at the negation's span.

    negated([0, 5, :list, [[0, 3, :sym, "not"], [4, 5, :sym, "x"]]]) #=> [0, 5, :list, [[0, 3, :sym, "not"], [4, 5, :sym, "x"]]]
"""
def negated(v)
  operand = if head_is?(v, "not", 2)
    v[3][1]
  end
  flips = {"equal?" => "not=", "not=" => "equal?"}
  to = if operand != nil and operand[2] == :list and count(operand[3]) == 3
    get(flips, operand[3][0][3])
  end
  if to.nil?
    v
  else
    h = operand[3][0]
    flipped = [
      v[0],
      v[1],
      :list,
      cons([h[0], h[1], :sym, to], rest(operand[3]))
    ]
    if to == "equal?"
      nil_tested(flipped)
    else
      flipped
    end
  end
end

@doc """
piped: A threaded pipe rewritten as blue's parser does: into `not`, a negation;
into a one-armed `if`, its nil else dropped; into `==`, its nil test.

    piped([0, 6, :list, [[5, 6, :sym, "f"], [0, 1, :sym, "x"]]]) #=> [0, 6, :list, [[5, 6, :sym, "f"], [0, 1, :sym, "x"]]]
"""
def piped(v)
  if head_is?(v, "not", 2)
    negated(v)
  elsif head_is?(v, "if", 4) and v[3][3][2] == :nil
    [v[0], v[1], :list, take(3, v[3])]
  else
    nil_tested(v)
  end
end

test "lex reads every kind of token with its span", {kind: :unit}
  src = concat(
    join_lines(["x = f(1, 2.5) # c", ":k a: \"s#"]),
    "{y}t\" %w[p q] ≠ |> => ::"
  )
  kinds = map((t) -> t[0], lex(src))
  assert kinds ==
    %i[
      ident
      op
      ident
      lparen
      int
      comma
      float
      rparen
      comment
      newline
      sym
      label
      interp
      words
      op
      pipe
      rocket
      path_sep
      eof
    ]
  assert lex("ok? x")[0] == [:ident, 0, 3, "ok?"]
  assert lex("a != b")[1] == [:op, 2, 4, "!="]
end

test "lex refuses what blue's lexer refuses, with :lex", {kind: :unit}
  assert kyohi::raised(() -> lex("\"open")) == :lex
  assert kyohi::raised(() -> token_at(text_bytes("a; b"), 4, 1)) == :lex
  assert kyohi::raised(
    () -> words_from(text_bytes("%i[1x]"), 6, 0, 3, :keywords, [])
  ) == :lex
  assert kyohi::raised(
    () -> string_from(text_bytes("\"open"), 5, 0, 1, [], [], [])
  ) == :lex
  assert kyohi::raised(
    () -> escape_at(text_bytes("\"\\q\""), 4, 0, 2, [], [], [])
  ) == :lex
  assert kyohi::raised(() -> wide_at(text_bytes("\u{a0}"), 2, 0)) == :lex
  assert kyohi::raised(() -> doc_at(text_bytes("@note"), 5, 0)) == :lex
  assert kyohi::raised(() -> doc_lines(text_bytes("a"), 1, 0, [])) == :lex
  assert kyohi::raised(() -> doc_line("a", "  ")) == :lex
end

test "each step of lex does its own part", {kind: :unit}
  b = text_bytes("x1")
  assert operator_aliases[1][1] == "<="
  assert bom_width([1]) == 0
  assert at(b, 2, 0) == 120
  assert scan(b, 2, 0, []) == [[:eof, 2, 2, nil], [:ident, 0, 2, "x1"]]
  assert token_at(text_bytes(line_break), 1, 0) == [[:newline, 0, 1, nil], 1]
  assert line_end(b, 2, 0) == 2
  assert text_of(b, 0, 1) == "x"
  assert run_end([1, 2], 2, 0, (c) -> c == 1) == 1
  assert not digit?(nil)
  assert not ident_start?(48)
  assert not ident_continue?(32)
  assert not op_char?(40)
  assert char_width(65) == 1
  assert code_point("A") == 65
  assert not space?(65)
  assert rejected?("\u{feff}")
  assert alias_of("x").nil?
  assert wide_at(text_bytes("é"), 2, 0) == [[:ident, 0, 2, "é"], 2]
  assert not suffix?(b, 2, 2)
  assert name_end(b, 2, 0) == 2
  assert ident_at(text_bytes("nil"), 3, 0) == [[:nil, 0, 3, nil], 3]
  assert colon_at(text_bytes("::"), 2, 0) == [[:path_sep, 0, 2, nil], 2]
  assert digits_end(b, 2, 1) == 2
  assert exponent_skip(b, 2, 0) == 0
  assert number_at(text_bytes("7"), 1, 0) == [[:int, 0, 1, 7], 1]
  assert not word_list_at?(b, 2, 0)
  assert op_end(text_bytes("+"), 1, 0, 0) == 1
  assert op_at(text_bytes("|>"), 2, 0) == [[:pipe, 0, 2, nil], 2]
  assert not space_byte?(65)
  assert words_at(text_bytes("%i[a]"), 5, 0)[0][3] == [:keywords, [["a", 3, 4]]]
  assert words_from(text_bytes("%w[]"), 4, 0, 3, :strings, [])[1] == 4
  assert word_char?("a")
  assert not word_fits?(:keywords, "1a")
  assert push_bytes([0], [5], 0, 1) == [5, 0]
  assert string_at(text_bytes("\"\""), 2, 0) == [[:str, 0, 2, ""], 2]
  assert string_from(text_bytes("\"a\""), 3, 0, 1, [], [], [])[0] ==
    [:str, 0, 3, "a"]
  assert escape_at(text_bytes("\"\\t\""), 4, 0, 2, [], [], [])[0] ==
    [:str, 0, 4, "\t"]
  assert skip_interpolation(text_bytes("}"), 1, 0, 1) == 1
  assert code_string_end(text_bytes("\"\""), 2, 1) == 2
  assert nth(
    3,
    doc_at(text_bytes(join_lines(["@doc \"\"\"", "\"\"\""])), 12, 0)[0]
  ) == [false, ""]
  assert doc_lines(text_bytes("\"\"\""), 3, 0, []) == [[], 0, 3]
  assert doc_line("", "  ") == ""
  assert trim_blank([]) == []
end

test "lex reads every escape, number form and name kind blue writes", {
  kind: :unit
}
  esc = lex("\"\\n\\t\\r\\\\\\\"\\0\\f\\b\\v\\a\\e\\u{41}\\u{e9}\"")[0]
  assert esc[3] == join_lines(["", "\t\r\\\"\u{0}\u{c}\u{8}\u{b}\u{7}\u{1b}Aé"])
  assert lex("\"é€😀\"")[0][3] == "é€😀"
  assert map((t) -> t[3], take(6, lex("1e5 1E+5 1e-5 2_000 1.5 3"))) ==
    [100000.0, 100000.0, 0.00001, 2000, 1.5, 3]
  assert map((t) -> t[0], take(3, lex("1ex"))) == %i[int ident eof]
  assert map((t) -> t[0], take(6, lex("true false nil a: b::c"))) ==
    %i[true false nil label ident path_sep]
  assert map((t) -> t[0], take(3, lex(": ?"))) == %i[colon op eof]
  assert lex("\t\r x")[0] == [:ident, 3, 4, "x"]
  assert lex("%i[x? y!]")[0][3] == [:keywords, [["x?", 3, 5], ["y!", 6, 8]]]
  assert lex("%w[€ 😀]")[0][3][1] == [["€", 3, 6], ["😀", 7, 11]]
  assert lex("+= %iq")[0] == [:op, 0, 2, "+="]
end

test "lex reads an interpolation through braces, strings and word lists", {
  kind: :unit
}
  o = concat("#", "{")
  q = "\""
  src = (parts) -> join(parts, "")
  assert lex(src([q, "a", o, "b}c", q]))[0][3] == [%w[a c], ["b"]]
  assert lex(src([q, o, " {b: 1} }", q]))[0][3][1] == [" {b: 1} "]
  assert lex(src([q, o, q, "s", q, "}", q]))[0][3][1] == [src([q, "s", q])]
  inner = src([q, "x", o, "y}", q])
  assert lex(src([q, o, inner, "}", q]))[0][3][1] == [inner]
  quoted = src([q, "\\", q, q])
  assert lex(src([q, o, quoted, "}", q]))[0][3][1] == [quoted]
  assert lex(src([q, o, "%w[}]}", q]))[0][3][1] == ["%w[}]"]
  assert kyohi::raised(() -> lex(src([q, o, "a"]))) == :lex
  assert kyohi::raised(() -> lex(src([q, o, q, "x"]))) == :lex
  assert kyohi::raised(() -> lex(src([q, o, q, o, "x", q]))) == :lex
  assert kyohi::raised(() -> lex(src([q, o, "%w[a"]))) == :lex
  assert code_string_end(text_bytes("ab"), 2, 0).nil?
end

test "lex refuses each malformed escape, word list and doc", {kind: :unit}
  assert kyohi::raised(() -> lex("\"\\u41\"")) == :lex
  assert kyohi::raised(() -> lex("\"\\u{41")) == :lex
  assert kyohi::raised(() -> lex("\"\\u{}\"")) == :lex
  assert kyohi::raised(() -> lex("\"\\u{d800}\"")) == :lex
  assert kyohi::raised(() -> lex("\"\\")) == :lex
  assert kyohi::raised(() -> lex("%w[a")) == :lex
  assert kyohi::raised(() -> lex("%w[a,b]")) == :lex
  assert kyohi::raised(() -> lex("$")) == :lex
  assert kyohi::raised(() -> lex("@doc x")) == :lex
  assert kyohi::raised(() -> lex("@doc \"\"\" x")) == :lex
  assert kyohi::raised(() -> lex("@doc")) == :lex
  three = join_lines(["@doc \"\"\"", "a \"\"\"", "\"\"\""])
  assert kyohi::raised(() -> lex(three)) == :lex
  heredoc = join_lines(["@moduledoc \"\"\"", "  a", "", "  b", "  \"\"\""])
  assert lex(heredoc)[0][3] == [true, join_lines(["a", "", "b"])]
end

@doc """
bodies: A form with each function body read as blue's `try_op` pass leaves it:
a body (and each branch of an `if` statement in it) re-sequenced, so an empty
or nil body is nil at its start.

    bodies([0, 9, :list, [[0, 3, :sym, "define"], [4, 5, :list, []], [6, 9, :nil, nil]]]) #=> [0, 9, :list, [[0, 3, :sym, "define"], [4, 5, :list, []], [6, 6, :nil, nil]]]
"""
def bodies(v)
  if v[2] != :list
    v
  else
    items = map(bodies, v[3])
    defines = count(items) >= 3 and
      items[0][2] == :sym and
      member?(items[0][3], %w[define define-typed]) and
      items[1][2] == :list
    if defines
      [
        v[0],
        v[1],
        :list,
        concat_lists(all_but_last(items), [branch(last(items))])
      ]
    else
      [v[0], v[1], :list, items]
    end
  end
end

@doc """
branch: A body re-sequenced from its statements, each `if` statement's branches in turn.

    branch([2, 5, :nil, nil]) #=> [2, 2, :nil, nil]
"""
def branch(b)
  forms = if b[2] == :list and head_is?(b, "begin", count(b[3]))
    rest(b[3])
  elsif b[2] == :nil
    []
  else
    [b]
  end
  stmts = map(
    fn(f)
      n = if f[2] == :list
        count(f[3])
      else
        0
      end
      if (n == 3 or n == 4) and head_is?(f, "if", n)
        [
          f[0],
          f[1],
          :list,
          concat_lists(take(2, f[3]), map(branch, drop(2, f[3])))
        ]
      else
        f
      end
    end,
    forms
  )
  if stmts == []
    [b[0], b[0], :nil, nil]
  elsif count(stmts) == 1
    stmts[0]
  else
    [b[0], b[1], :list, cons([b[0], b[0], :sym, "begin"], stmts)]
  end
end

@doc """
spanless: A node of `parse`'s tree with every span and kind taken off: the
payloads alone, a list as the list of its items'.

    spanless([0, 5, :list, [[0, 1, :sym, "f"], [2, 3, :int, 1]]]) #=> ["f", 1]
"""
def spanless(v)
  if v[2] == :list
    map(spanless, v[3])
  else
    v[3]
  end
end

test "parse reads literals, names, lambdas and operators as blue does", {
  kind: :unit
}
  read = (lines) -> map(spanless, parse(join_lines(lines)))
  assert read(
    [
      "x = 1 # c",
      ":k",
      "\"s\"",
      "1.5",
      "nil",
      "true",
      "false",
      "%w[a b]",
      "%i[c]"
    ]
  ) ==
    [
      ["define", "x", 1],
      "k",
      "s",
      1.5,
      nil,
      true,
      false,
      %w[list a b],
      %w[list c]
    ]
  assert read(%w[a::b::c k::true k::false k::nil]) ==
    %w[a/b/c k/true k/false k/nil]
  assert read(
    ["(1)", "(a)", "(x) -> x", "() -> 1", "(a, b) -> a", "(a + b)"]
  ) ==
    [
      1,
      "a",
      ["lambda", ["x"], "x"],
      ["lambda", [], 1],
      ["lambda", %w[a b], "a"],
      %w[+ a b]
    ]
  assert read(["fn(a,", "  b) a end", "fn end"]) ==
    [["lambda", %w[a b], "a"], ["lambda", [], nil]]
  assert read(
    [
      "-x",
      "!y",
      "not z",
      "not(a)",
      "not(a, b)",
      "not(*xs)",
      "and(a, b)",
      "begin(x)"
    ]
  ) ==
    [
      ["-", 0, "x"],
      %w[not y],
      %w[not z],
      %w[not a],
      %w[not a b],
      %w[apply not xs],
      %w[and a b],
      %w[begin x]
    ]
  assert read(["a + b * c", "a |> b", "a or b"]) ==
    [["+", "a", %w[* b c]], %w[b a], %w[or a b]]
end

test "parse reads calls, maps, lists, indexes and sends with blue's spans", {
  kind: :unit
}
  read = (lines) -> map(spanless, parse(join_lines(lines)))
  assert read(["f(*a)", "f()", "f(a,", ")", "f(a, b)", "f(**m, k: 1)"]) ==
    [
      %w[apply f a],
      ["f"],
      %w[f a],
      %w[f a b],
      ["f", ["blue-kwargs", %w[blue-splice m], ["hash-map", "k", 1]]]
    ]
  assert read(
    ["{a: 1, **m, b:, \"c\" => 2,}", "{}", "{**m}", "[1,", "]", "[]", "[1, 2]"]
  ) ==
    [
      [
        "blue-merge",
        ["hash-map", "a", 1],
        %w[blue-splice m],
        ["hash-map", "b", "b", "c", 2]
      ],
      ["hash-map"],
      ["blue-merge", %w[blue-splice m]],
      ["list", 1],
      ["list"],
      ["list", 1, 2]
    ]
  assert read(["x[:k]", "x[0]", "x.y", "x.y(1)", "x.y(*z)"]) ==
    [
      %w[get x k],
      ["nth", 0, "x"],
      %w[blue-field x y],
      ["y", "x", 1],
      %w[apply y x z]
    ]
  assert parse("x.y(*z)")[0][3][0] == [4, 5, :sym, "apply"]
  assert parse("{a: 1, **m}")[0][3][1] ==
    [1, 5, :list, [[1, 3, :sym, "hash-map"], [1, 3, :kw, "a"], [4, 5, :int, 1]]]
end

test "parse makes the rewrites blue's parser makes beside the grammar", {
  kind: :unit
}
  read = (lines) -> map(spanless, parse(join_lines(lines)))
  assert read(
    [
      "x |> f",
      "x |> f(1)",
      "x |> not()",
      "x |> equal?(nil)",
      "x |> g(if a",
      "  1",
      "end)",
      "x |> if a",
      "end"
    ]
  ) ==
    [
      %w[f x],
      ["f", "x", 1],
      %w[not x],
      %w[blue-field x nil?],
      ["g", "x", ["if", "a", 1]],
      %w[if x a]
    ]
  assert read(
    [
      "a == nil",
      "nil == a",
      "nil == nil",
      "equal?(a, nil)",
      "not (a == b)",
      "not (a != b)",
      "not (a != nil)",
      "not (f(a, b, c))"
    ]
  ) ==
    [
      %w[blue-field a nil?],
      %w[blue-field a nil?],
      ["equal?", nil, nil],
      %w[blue-field a nil?],
      %w[not= a b],
      %w[equal? a b],
      %w[blue-field a nil?],
      ["not", %w[f a b c]]
    ]
  assert read(
    [
      "if a",
      "  b",
      "elsif c",
      "  d",
      "else",
      "  e",
      "end",
      "if a",
      "else",
      "end",
      "if a",
      "else",
      "  # kept",
      "end",
      "unless a == b",
      "  c",
      "end"
    ]
  ) ==
    [
      ["if", "a", "b", %w[if c d e]],
      ["if", "a", nil],
      ["if", "a", nil, nil],
      ["if", %w[not= a b], "c"]
    ]
end

test "parse reads defs, typed signatures, docs and strings", {kind: :unit}
  read = (lines) -> map(spanless, parse(join_lines(lines)))
  assert read(
    [
      "def f(a, c: Int, b?, d?: m::T) -> List(Int, Str)",
      "  if a",
      "    nil",
      "  else",
      "    b",
      "    c",
      "  end",
      "  d",
      "end",
      "def g",
      "end",
      "def h() -> T() 1 end"
    ]
  ) ==
    [
      [
        "define-typed",
        ["f", %w[a dyn], %w[c Int], "&optional", %w[b dyn], %w[d m/T]],
        %w[List Int Str],
        ["begin", ["if", "a", nil, %w[begin b c]], "d"]
      ],
      ["define", ["g"], nil],
      ["define-typed", ["h"], ["T"], 1]
    ]
  o = concat("#", "{")
  q3 = "\"\"\""
  assert read(
    [
      "@moduledoc #{q3}",
      "m",
      q3,
      "@doc #{q3}",
      "d",
      q3,
      "x = 1",
      join(["\"a", o, "x}b\""], ""),
      "\"\\n\"",
      "\"a\\n\"",
      join(["\"a\\nb", o, "x}\\n", o, "y}\""], "")
    ]
  ) ==
    [
      ["define", "x", 1],
      ["concat", %w[concat a x], "b"],
      "line_break",
      ["unlines", %w[list a]],
      ["join_lines", ["list", "a", ["concat", %w[concat b x], ""], "y"]]
    ]
  assert parse(join_lines(["@doc #{q3}", "d", q3, "x = 1"]))[0][0] == 0
end

test "parse refuses with :parse what blue refuses or the slice lacks", {
  kind: :unit
}
  refused = (lines) -> kyohi::raised(() -> parse(join_lines(lines)))
  q3 = "\"\"\""
  cases = [
    ["(a"],
    ["def f", "  x", "rescue", "end"],
    ["x = 1", "@moduledoc #{q3}", "m", q3],
    ["@doc #{q3}", "d", q3],
    ["@doc #{q3}", "d", q3, "f(x)"],
    ["a b"],
    ["[a] = x"],
    ["f(x)?"],
    ["a rescue b"],
    [")"],
    ["begin (x)"],
    ["case x"],
    ["if::x"],
    ["a::1"],
    ["a::if::b"],
    ["(*a) -> a"],
    ["fn(*a) end"],
    ["+x"],
    ["f(*a, b)"],
    ["f(k: 1)"],
    ["f(a b)"],
    ["{a: 1 b}"],
    ["[*a]"],
    ["[1 2]"],
    ["x.1"],
    ["x.if"],
    ["if a"],
    ["def 1 end"],
    ["def f(*a) end"],
    ["def f(a?, b) end"],
    ["def f() -> 1 end"]
  ]
  assert filter((lines) -> refused(lines) != :parse, cases) == []
end

test "each step of parse does its own part", {kind: :unit}
  r = reading
  n = node("k", [0, 4], [1, 2], [["a", leaf("integer", [:int, 0, 1, 7])]])
  assert ev(r, ["nil"], n, false) == [[1, 2, :nil, nil]]
  assert ev(r, ["field", "b", %w[sym d]], n, false) == [[1, 2, :sym, "d"]]
  assert kyohi::raised(() -> ev(r, %w[field b], n, false)) == :parse
  assert kyohi::raised(() -> ev(r, ["nope"], n, false)) == :parse
  assert ev(r, ["if_kind", "k", %w[sym y], %w[sym z]], n, false) ==
    [[1, 2, :sym, "y"]]
  assert ev(r, ["if_kind", "j", %w[sym y], %w[sym z]], n, false) ==
    [[1, 2, :sym, "z"]]
  assert ev(r, ["list"], n, true) == [[1, 2, :list, []]]
  assert list_of(assoc(n, :close, 9), [[3, 4, :int, 1]], true) ==
    [3, 9, :list, [[3, 4, :int, 1]]]
  assert child(n, "b").nil?
  pair = node(
    "pair",
    [0, 4],
    [0, 2],
    [
      ["key", leaf("label", [:label, 0, 2, "a"])],
      ["value", leaf("integer", [:int, 3, 4, 1])]
    ]
  )
  assert kyohi::raised(() -> lower_one(r, pair)) == :parse
  assert kyohi::raised(() -> interpolated(r, [0, 1], join_lines(%w[a b]))) ==
    :parse
  assert literal_kind(:op).nil?
  assert infix_row(r, [:comma, 0, 1, nil]).nil?
  assert arrow_close({toks: lex("a + b)"), last: 4}, 0).nil?
  assert lexeme([:int, 0, 1, 2]) == [0, 1, :int, 2]
  assert lexeme([:false, 0, 5, nil]) == [0, 5, :bool, false]
  assert lexeme([:nil, 0, 3, nil]) == [0, 3, :nil, nil]
  assert param_name(leaf("identifier", [:ident, 0, 1, "a"])) == "a"
  typed = node(
    "typed_parameter",
    [0, 6],
    [0, 2],
    [["name", leaf("label", [:label, 0, 2, "a"])]]
  )
  assert param_name(typed) == "a"
  assert param_leaf(typed)[:kind] == "label"
  assert nil_test([0, 1], [0, 1], [0, 1, :nil, nil], [0, 1, :nil, nil]).nil?
  assert negated([0, 1, :sym, "x"]) == [0, 1, :sym, "x"]
  assert negated([0, 5, :list, [[0, 3, :sym, "not"], [4, 5, :int, 1]]])[3][1] ==
    [4, 5, :int, 1]
  assert threaded({start: 0, end: 6}, [0, 1, :sym, "x"], [5, 6, :list, []]) ==
    [0, 6, :list, [[5, 6, :list, []], [0, 1, :sym, "x"]]]
  assert flushed("h", []) == []
  assert bodies([0, 1, :int, 1]) == [0, 1, :int, 1]
  assert branch(
    [
      0,
      9,
      :list,
      [
        [0, 0, :sym, "begin"],
        [0, 1, :sym, "a"],
        [
          2,
          9,
          :list,
          [
            [2, 4, :sym, "if"],
            [5, 6, :sym, "c"],
            [7, 9, :nil, nil],
            [8, 9, :nil, nil]
          ]
        ]
      ]
    ]
  ) ==
    [
      0,
      9,
      :list,
      [
        [0, 0, :sym, "begin"],
        [0, 1, :sym, "a"],
        [
          2,
          9,
          :list,
          [
            [2, 4, :sym, "if"],
            [5, 6, :sym, "c"],
            [7, 7, :nil, nil],
            [8, 8, :nil, nil]
          ]
        ]
      ]
    ]
  assert definition?([0, 1, :int, 1]) == false
end
