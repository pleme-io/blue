@moduledoc """
yomi (読み): blue's reader, written in blue (F1 of
docs/pure-blue/front-tower-conformance.md). This first slice is the lexer:
`lex(src)` gives the tokens and byte spans `crates/blue-lang-syntax/src/lex.rs`
gives, each token `[kind, start, end, payload]`, and refuses (`:lex`) what it
refuses. It also owns the operator table both lexers read.

    lex("f(1)") #=> [[:ident, 0, 1, "f"], [:lparen, 1, 2, nil], [:int, 2, 3, 1], [:rparen, 3, 4, nil], [:eof, 4, 4, nil]]
"""

use("deeta", %i[code_point_text radix_value])

use("kazu")

use("kyohi")

use("retsu", %i[first last rest])

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
text_of: The text of bytes s up to e.

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
gap?: Whether a byte separates the words of a word list.

    gap?(10) #=> true
"""
def gap?(c)
  member?(c, [32, 9, 13, 10])
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
  j = run_end(b, n, i, gap?)
  if j >= n
    raise(:lex, "unterminated word list")
  elsif b[j] == 93
    [[:words, start, j + 1, [flavor, reverse(acc)]], j + 1]
  else
    e = run_end(b, n, j, (c) -> not (c == 93 or gap?(c)))
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
  assert not gap?(65)
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
