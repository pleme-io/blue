@moduledoc """
khipu — blue's knowledge graph (docs/KHIPU.md): RDF terms as a closed sum, quads, and N-Triples and N-Quads read and written. A literal with both a language tag and a datatype has no constructor, an IRI or a language tag that is not valid is refused where it is read, and a blank node carries the scope of the document it came from, so two documents' `_:b` are two nodes.

    write_term(iri("http://e/a"), "") #=> "<http://e/a>"
"""

use("deeta", %i[code_point_text radix_value])
use("kyohi", [:raised])
use("moji", %i[is_hex take_chars])
use("retsu", %i[first size])

@doc """
XSD_STRING is the datatype IRI a plain literal has.

    XSD_STRING #=> "http://www.w3.org/2001/XMLSchema#string"
"""
XSD_STRING = "http://www.w3.org/2001/XMLSchema#string"

@doc """
RDF_LANG_STRING is the datatype IRI a language-tagged literal has, so it is never written as a datatype.

    RDF_LANG_STRING #=> "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"
"""
RDF_LANG_STRING = "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"

@doc """
IRI_FORBIDDEN is the characters an N-Triples IRI never holds.

    size(IRI_FORBIDDEN) #=> 9
"""
IRI_FORBIDDEN = ["<", ">", "\"", "{", "}", "|", "^", "`", "\\"]

@doc """
control_or_space? tells whether one character is a space or an ASCII control character.

    control_or_space?(" ") #=> true
"""
def control_or_space?(c)
  b = text_bytes(c)
  size(b) == 1 and first(b) <= 32
end

@doc """
letter? tells whether one character is an ASCII letter.

    letter?("a") #=> true
"""
def letter?(c)
  b = text_bytes(c)
  size(b) == 1 and
    (first(b) >= 65 and first(b) <= 90 or first(b) >= 97 and first(b) <= 122)
end

@doc """
digit? tells whether one character is an ASCII digit.

    digit?("7") #=> true
"""
def digit?(c)
  b = text_bytes(c)
  size(b) == 1 and first(b) >= 48 and first(b) <= 57
end

@doc """
iri_problem: Why `text` is not an absolute IRI N-Triples accepts, or nil when it is one.

    iri_problem("http://e/a") #=> nil
"""
def iri_problem(text)
  cs = chars(text)
  colon = position(":", cs)
  if any?((c) -> control_or_space?(c) or member?(c, IRI_FORBIDDEN), cs)
    "an IRI holds no space, control character or any of <>\"{}|^`\\"
  elsif colon < 1 or not letter?(first(cs))
    "an IRI is absolute: a scheme, then `:`"
  elsif not every?(
    (c) -> letter?(c) or digit?(c) or member?(c, %w[+ - .]),
    take(colon, cs)
  )
    "an IRI's scheme is letters, digits, `+`, `-` and `.`"
  end
end

@doc """
lang_problem: Why `tag` is not a BCP 47 language tag, or nil when it is one: a primary subtag of 1 to 8 letters, then subtags of 1 to 8 letters or digits.

    lang_problem("en-GB") #=> nil
"""
def lang_problem(tag)
  subtags = split(tag, "-")
  primary = first(subtags)
  if primary == "" or length(primary) > 8 or not every?(letter?, chars(primary))
    "a language tag starts with 1 to 8 letters"
  elsif not every?(
    fn(s)
      s != "" and
        length(s) <= 8 and
        every?((c) -> letter?(c) or digit?(c), chars(s))
    end,
    drop(1, subtags)
  )
    "a language tag's subtags are 1 to 8 letters or digits"
  end
end

@doc """
refuse raises `:rdf_refused` with the reason.

    raised(() -> refuse("no")) #=> :rdf_refused
"""
def refuse(why)
  raise(:rdf_refused, why)
end

@doc """
iri: An IRI term; a text that is not an absolute IRI is refused.

    iri("http://e/a") #=> {term: :iri, value: "http://e/a"}
"""
def iri(text)
  why = iri_problem(text)
  if why != nil
    refuse("#{why}: <#{text}>")
  end
  {term: :iri, value: text}
end

@doc """
blank: A blank node: its label and the scope of the document it was read from.

    blank("doc1", "b")[:term] #=> :blank
"""
def blank(scope, label)
  if label == ""
    refuse("a blank node has a label")
  end
  {term: :blank, scope:, label:}
end

@doc """
literal: A plain literal; RDF 1.1 reads it as an `xsd:string`.

    literal("hi") #=> {term: :plain, value: "hi"}
"""
def literal(text)
  {term: :plain, value: text}
end

@doc """
lang: A language-tagged literal. Its datatype is `rdf:langString` by construction, so it has no datatype field; the tag is kept in lower case, as tags compare without case.

    lang("hi", "EN")[:tag] #=> "en"
"""
def lang(text, tag)
  why = lang_problem(tag)
  if why != nil
    refuse("#{why}: @#{tag}")
  end
  {term: :lang, value: text, tag: downcase(tag)}
end

@doc """
typed: A literal with a datatype IRI. `xsd:string` is the plain literal, and `rdf:langString` needs a tag, so it is refused here.

    typed("1", "http://www.w3.org/2001/XMLSchema#integer")[:term] #=> :typed
"""
def typed(text, datatype)
  iri(datatype)
  if datatype == XSD_STRING
    literal(text)
  elsif datatype == RDF_LANG_STRING
    refuse("rdf:langString takes a language tag; write lang(text, tag)")
  else
    {term: :typed, value: text, datatype:}
  end
end

@doc """
term? tells whether a value is one of the five terms.

    term?(literal("a")) #=> true
"""
def term?(t)
  map?(t) and member?(t[:term], %i[iri blank plain lang typed])
end

@doc """
quad: A statement in a graph. The subject is an IRI or a blank node, the predicate an IRI, the object any term, and the graph nil (the default graph), an IRI or a blank node.

    quad(iri("http://e/s"), iri("http://e/p"), literal("o"), nil)[:o] #=> literal("o")
"""
def quad(s, p, o, g)
  if not term?(s) or not member?(s[:term], %i[iri blank])
    refuse("a subject is an IRI or a blank node")
  end
  if not term?(p) or p[:term] != :iri
    refuse("a predicate is an IRI")
  end
  if not term?(o)
    refuse("an object is a term")
  end
  if g != nil and (not term?(g) or not member?(g[:term], %i[iri blank]))
    refuse("a graph is nil, an IRI or a blank node")
  end
  {s:, p:, o:, g:}
end

@doc """
escaped is a literal's text with its backslashes, quotes and line breaks escaped for N-Triples.

    length(escaped("\"")) #=> 2
"""
def escaped(text)
  replace(
    replace(
      replace(replace(text, "\\", "\\\\"), "\"", "\\\""),
      line_break,
      "\\n"
    ),
    "\r",
    "\\r"
  )
end

@doc """
write_term: A term in N-Triples. A blank node from `scope` keeps its label; one from another scope gets its scope's hash in front, so two documents' labels never meet.

    write_term(blank("d", "b"), "d") #=> "_:b"
"""
def write_term(t, scope)
  kind = t[:term]
  if kind == :iri
    "<#{t[:value]}>"
  elsif kind == :blank
    if t[:scope] == scope
      "_:#{t[:label]}"
    else
      "_:s#{take_chars(blake3_hex(t[:scope]), 8)}#{t[:label]}"
    end
  elsif kind == :plain
    "\"#{escaped(t[:value])}\""
  elsif kind == :lang
    "\"#{escaped(t[:value])}\"@#{t[:tag]}"
  else
    "\"#{escaped(t[:value])}\"^^<#{t[:datatype]}>"
  end
end

@doc """
write_quad: One N-Quads line, ending in ` .`; a quad in the default graph is an N-Triples line.

    write_quad(quad(iri("http://e/s"), iri("http://e/p"), iri("http://e/o"), nil), "") #=> "<http://e/s> <http://e/p> <http://e/o> ."
"""
def write_quad(q, scope)
  parts = [
    write_term(q[:s], scope),
    write_term(q[:p], scope),
    write_term(q[:o], scope)
  ]
  all = if q[:g].nil?
    parts
  else
    append(parts, [write_term(q[:g], scope)])
  end
  "#{join(all, " ")} ."
end

@doc """
write: Quads as N-Quads text, one line each.

    write([], "") #=> ""
"""
def write(quads, scope)
  unlines(map((q) -> write_quad(q, scope), quads))
end

@doc """
term_id: A term's content address: the BLAKE3 of its N-Triples form, its scope included for a blank node, so equal terms share an id on every machine.

    term_id(iri("http://e/a")) == term_id(iri("http://e/a")) #=> true
"""
def term_id(t)
  if t[:term] == :blank
    blake3_hex("#{t[:scope]}\u{1f}#{t[:label]}")
  else
    blake3_hex(write_term(t, ""))
  end
end

@doc """
at is the character at index i, or nil past the end.

    at(["a"], 1) #=> nil
"""
def at(cs, i)
  if i < size(cs)
    cs[i]
  end
end

@doc """
ok is a reading that succeeded: its value and the index after it.

    ok(1, 2) #=> {v: 1, i: 2}
"""
def ok(v, i)
  {v:, i:}
end

@doc """
no is a reading that was refused, with its reason.

    no("x") #=> {why: "x"}
"""
def no(why)
  {why:}
end

@doc """
skip_ws is the index of the first character at or after i that is not a space or a tab.

    skip_ws(chars("  a"), 0) #=> 2
"""
def skip_ws(cs, i)
  c = at(cs, i)
  if c == " " or c == "\t"
    skip_ws(cs, i + 1)
  else
    i
  end
end

@doc """
uchar reads a `\\u` or `\\U` escape whose letter is at i: the character it names.

    uchar(chars("u00e9"), 0)[:v] #=> "é"
"""
def uchar(cs, i)
  width = if at(cs, i) == "u"
    4
  else
    8
  end
  digits = join(take(width, drop(i + 1, cs)), "")
  if length(digits) != width or not is_hex(digits)
    no("\\u takes 4 hex digits and \\U takes 8")
  else
    t = code_point_text(radix_value(digits, 16))
    if t.nil?
      no("\\#{at(cs, i)}#{digits} is not a Unicode scalar value")
    else
      ok(t, i + 1 + width)
    end
  end
end

@doc """
iri_text reads an IRI's characters up to its closing `>`, escapes decoded.

    iri_text(chars("a>"), 0, [])[:v] #=> "a"
"""
def iri_text(cs, i, acc)
  c = at(cs, i)
  if c.nil?
    no("an IRI is closed by `>`")
  elsif c == ">"
    ok(join(acc, ""), i + 1)
  elsif c == "\\"
    if at(cs, i + 1) == "u" or at(cs, i + 1) == "U"
      r = uchar(cs, i + 1)
      if r[:why] != nil
        r
      else
        iri_text(cs, r[:i], append(acc, [r[:v]]))
      end
    else
      no("an IRI escapes only \\u and \\U")
    end
  else
    iri_text(cs, i + 1, append(acc, [c]))
  end
end

@doc """
read_iri reads `<...>` at i as an IRI term, refusing one that is not absolute.

    read_iri(chars("<http://e/a>"), 0)[:v] #=> iri("http://e/a")
"""
def read_iri(cs, i)
  r = iri_text(cs, i + 1, [])
  if r[:why] != nil
    r
  else
    why = iri_problem(r[:v])
    if why != nil
      no("#{why}: <#{r[:v]}>")
    else
      ok(iri(r[:v]), r[:i])
    end
  end
end

@doc """
label_char? tells whether a character can be part of a blank node label.

    label_char?("a") #=> true
"""
def label_char?(c)
  c != nil and
    not control_or_space?(c) and
    not member?(c, ["<", ">", "\"", "#", "^", "@"])
end

@doc """
label_end is the index just after the label characters that start at i.

    label_end(chars("ab c"), 0) #=> 2
"""
def label_end(cs, i)
  if label_char?(at(cs, i))
    label_end(cs, i + 1)
  else
    i
  end
end

@doc """
read_blank reads `_:label` at i as a blank node of `scope`; a final `.` ends the statement, not the label.

    read_blank(chars("_:b1."), 0, "d")[:v][:label] #=> "b1"
"""
def read_blank(cs, i, scope)
  start = i + 2
  stop = label_end(cs, start)
  back = if stop > start and at(cs, stop - 1) == "."
    stop - 1
  else
    stop
  end
  label = join(take(back - start, drop(start, cs)), "")
  if label == "" or starts_with?(label, "-") or starts_with?(label, ".")
    no("a blank node label starts with a letter, digit or `_`: _:#{label}")
  else
    ok(blank(scope, label), back)
  end
end

@doc """
ECHAR is each N-Triples escape letter and the character it stands for.

    get(ECHAR, "t") #=> "\t"
"""
ECHAR = {
  "t" => "\t",
  "b" => "\u{8}",
  "n" => line_break,
  "r" => "\r",
  "f" => "\u{c}",
  "\"" => "\"",
  "'" => "'",
  "\\" => "\\"
}

@doc """
string_text reads a literal's characters up to its closing quote, escapes decoded.

    string_text(chars("hi\""), 0, [])[:v] #=> "hi"
"""
def string_text(cs, i, acc)
  c = at(cs, i)
  if c.nil?
    no("a literal is closed by `\"`")
  elsif c == "\""
    ok(join(acc, ""), i + 1)
  elsif c == "\\"
    e = at(cs, i + 1)
    if e == "u" or e == "U"
      r = uchar(cs, i + 1)
      if r[:why] != nil
        r
      else
        string_text(cs, r[:i], append(acc, [r[:v]]))
      end
    elsif e != nil and get(ECHAR, e) != nil
      string_text(cs, i + 2, append(acc, [get(ECHAR, e)]))
    else
      no("\\#{to_s(e)} is not an escape")
    end
  else
    string_text(cs, i + 1, append(acc, [c]))
  end
end

@doc """
tag_end is the index just after the language tag characters that start at i.

    tag_end(chars("en-GB x"), 0) #=> 5
"""
def tag_end(cs, i)
  c = at(cs, i)
  if c != nil and (letter?(c) or digit?(c) or c == "-")
    tag_end(cs, i + 1)
  else
    i
  end
end

@doc """
read_literal reads a quoted literal at i with its tag or datatype, refusing one with both.

    read_literal(chars("\"a\"@en"), 0)[:v] #=> lang("a", "en")
"""
def read_literal(cs, i)
  r = string_text(cs, i + 1, [])
  if r[:why] != nil
    r
  elsif at(cs, r[:i]) == "@"
    stop = tag_end(cs, r[:i] + 1)
    tag = join(take(stop - r[:i] - 1, drop(r[:i] + 1, cs)), "")
    why = lang_problem(tag)
    if why != nil
      no("#{why}: @#{tag}")
    elsif at(cs, stop) == "^"
      no("a literal has a language tag or a datatype, never both")
    else
      ok(lang(r[:v], tag), stop)
    end
  elsif at(cs, r[:i]) == "^" and at(cs, r[:i] + 1) == "^"
    if at(cs, r[:i] + 2) != "<"
      no("a datatype is an IRI in <>")
    else
      d = read_iri(cs, r[:i] + 2)
      if d[:why] != nil
        d
      elsif d[:v][:value] == RDF_LANG_STRING
        no("rdf:langString takes a language tag")
      else
        ok(typed(r[:v], d[:v][:value]), d[:i])
      end
    end
  else
    ok(literal(r[:v]), r[:i])
  end
end

@doc """
read_node reads the term at i when its kind is one of `kinds`, and refuses any other.

    read_node(chars("<http://e/a>"), 0, "d", [:iri])[:v] #=> iri("http://e/a")
"""
def read_node(cs, i, scope, kinds)
  c = at(cs, i)
  if c == "<" and member?(:iri, kinds)
    read_iri(cs, i)
  elsif c == "_" and at(cs, i + 1) == ":" and member?(:blank, kinds)
    read_blank(cs, i, scope)
  elsif c == "\"" and member?(:literal, kinds)
    read_literal(cs, i)
  else
    no("expected #{join(map(to_s, kinds), " or ")} at column #{to_s(i + 1)}")
  end
end

@doc """
read_rest accepts what follows a statement's dot: nothing, or a comment.

    read_rest(chars("  # note"), 0)[:why] #=> nil
"""
def read_rest(cs, i)
  j = skip_ws(cs, i)
  c = at(cs, j)
  if c.nil? or c == "#"
    ok(nil, j)
  else
    no("unexpected `#{c}` after the statement")
  end
end

@doc """
then passes a refused reading through, and gives a successful one to f.

    then(no("x"), (r) -> r)[:why] #=> "x"
"""
def then(r, f)
  if r[:why] != nil
    r
  else
    f(r)
  end
end

@doc """
read_graph reads an N-Quads graph label at i, or nil when there is none or the text is N-Triples.

    read_graph(chars(" ."), 0, "d", true)[:v] #=> nil
"""
def read_graph(cs, i, scope, with_graphs)
  k = skip_ws(cs, i)
  if with_graphs and at(cs, k) != "."
    read_node(cs, k, scope, %i[iri blank])
  else
    ok(nil, k)
  end
end

@doc """
read_end requires the statement's dot at i, then nothing but a comment.

    read_end(chars(" ."), 0, 7)[:v] #=> 7
"""
def read_end(cs, i, made)
  dot = skip_ws(cs, i)
  if at(cs, dot) != "."
    no("a statement ends with `.`")
  else
    then(read_rest(cs, dot + 1), (_t) -> ok(made, dot + 1))
  end
end

@doc """
read_statement reads one line's subject, predicate, object, optional graph and dot as a quad.

    read_statement(chars("<http://e/s> <http://e/p> \"o\" ."), "d", false)[:v][:o] #=> literal("o")
"""
def read_statement(cs, scope, with_graphs)
  s = read_node(cs, skip_ws(cs, 0), scope, %i[iri blank])
  if s[:why] != nil
    return s
  end
  p = read_node(cs, skip_ws(cs, s[:i]), scope, [:iri])
  if p[:why] != nil
    return p
  end
  o = read_node(cs, skip_ws(cs, p[:i]), scope, %i[iri blank literal])
  if o[:why] != nil
    return o
  end
  g = read_graph(cs, o[:i], scope, with_graphs)
  if g[:why] != nil
    return g
  end
  read_end(cs, g[:i], quad(s[:v], p[:v], o[:v], g[:v]))
end

@doc """
blank_line? tells whether a line holds no statement: only spaces, or a comment.

    blank_line?(chars("  # c")) #=> true
"""
def blank_line?(cs)
  c = at(cs, skip_ws(cs, 0))
  c.nil? or c == "#"
end

@doc """
read: The statements of N-Triples (`with_graphs` false) or N-Quads text. Each line is judged alone: a bad line is a refusal with its line number and reason, and the lines around it are still read. `scope` names the document, for its blank nodes.

    size(read("<http://e/s> <http://e/p> <http://e/o> .", "d", false)[:quads]) #=> 1
"""
def read(text, scope, with_graphs)
  rows = split(replace(text, "\r", ""), line_break)
  numbered = map((n) -> [n + 1, chars(rows[n])], range(size(rows)))
  judged = map(
    (row) -> [row[0], read_statement(row[1], scope, with_graphs)],
    filter((row) -> not blank_line?(row[1]), numbered)
  )
  {
    quads: map((r) -> r[1][:v], filter((r) -> r[1][:why].nil?, judged)),
    refused: map(
      (r) -> {line: r[0], why: r[1][:why]},
      filter((r) -> r[1][:why] != nil, judged)
    )
  }
end

@doc """
rdf_refused? tells whether calling f raises `:rdf_refused`.

    rdf_refused?(() -> iri("x")) #=> true
"""
def rdf_refused?(f)
  raised(f) == :rdf_refused
end

@doc """
nt reads N-Triples text in the scope `t`.

    size(nt("<http://e/s> <http://e/p> \"o\" .")[:quads]) #=> 1
"""
def nt(text)
  read(text, "t", false)
end

@doc """
one is the single quad an N-Triples line reads to, asserting nothing was refused.

    one("<http://e/s> <http://e/p> \"o\" .")[:o] #=> literal("o")
"""
def one(text)
  r = nt(text)
  assert r[:refused] == []
  first(r[:quads])
end

@doc """
refused_why is the reason the single line of `text` is refused.

    contains?(refused_why("<rel> <http://e/p> <http://e/o> ."), "absolute") #=> true
"""
def refused_why(text)
  r = nt(text)
  assert size(r[:refused]) == 1
  first(r[:refused])[:why]
end

test "a literal with both a language tag and a datatype has no constructor and no reading"
  assert not member?(:datatype, map((e) -> e[0], map_entries(lang("a", "en"))))
  assert contains?(
    refused_why("<http://e/s> <http://e/p> \"a\"@en^^<http://e/t> ."),
    "never both"
  )
  assert rdf_refused?(() -> typed("a", RDF_LANG_STRING))
end

test "an IRI that is not absolute, or holds a forbidden character, is refused"
  assert rdf_refused?(() -> iri("relative/path"))
  assert rdf_refused?(() -> iri("http://e/a b"))
  assert rdf_refused?(() -> iri("http://e/<"))
  assert contains?(refused_why("<rel> <http://e/p> <http://e/o> ."), "absolute")
  assert contains?(
    refused_why("<http://e/s> <http://e/p> <http://e/a b> ."),
    "no space"
  )
end

test "a language tag that is not BCP 47 is refused"
  assert rdf_refused?(() -> lang("a", "123"))
  assert rdf_refused?(() -> lang("a", "en-"))
  assert lang("a", "en-GB")[:tag] == "en-gb"
  assert contains?(
    refused_why("<http://e/s> <http://e/p> \"a\"@9x ."),
    "language tag"
  )
end

test "xsd:string is the plain literal"
  assert typed("a", XSD_STRING) == literal("a")
  q = one("<http://e/s> <http://e/p> \"a\"^^<#{XSD_STRING}> .")
  assert q[:o] == literal("a")
end

test "escapes are read and written back"
  q = one("<http://e/s> <http://e/p> \"tab\\there \\\"q\\\" \\u00e9 \\U0001F600\" .")
  assert q[:o][:value] == "tab\there \"q\" é 😀"
  assert write_term(literal(join_lines(["a\"b\\c", "d"])), "") ==
    "\"a\\\"b\\\\c\\nd\""
  assert contains?(
    refused_why("<http://e/s> <http://e/p> \"\\q\" ."),
    "not an escape"
  )
  assert contains?(
    refused_why("<http://e/s> <http://e/p> \"\\uD800\" ."),
    "scalar"
  )
end

test "one bad line is refused alone; comments and blank lines are skipped"
  text = unlines(
    [
      "# a comment",
      "<http://e/a> <http://e/p> <http://e/b> .",
      "",
      "<http://e/a> <http://e/p> .",
      "<http://e/a> <http://e/p> \"c\" . # trailing comment"
    ]
  )
  r = nt(text)
  assert size(r[:quads]) == 2
  assert map((x) -> x[:line], r[:refused]) == [4]
end

test "a statement ends with a dot, and nothing follows it but a comment"
  assert contains?(
    refused_why("<http://e/a> <http://e/p> <http://e/b>"),
    "ends with"
  )
  assert contains?(
    refused_why("<http://e/a> <http://e/p> <http://e/b> . <x>"),
    "unexpected"
  )
end

test "blank nodes keep their document: two documents' _:b are two nodes"
  a = first(read("_:b <http://e/p> \"1\" .", "doc-a", false)[:quads])
  b = first(read("_:b <http://e/p> \"1\" .", "doc-b", false)[:quads])
  assert a[:s] != b[:s]
  assert term_id(a[:s]) != term_id(b[:s])
  assert write_term(a[:s], "doc-a") == "_:b"
  assert write_term(a[:s], "doc-b") != "_:b"
  dotted = first(nt("_:b.1 <http://e/p> _:c.")[:quads])
  assert dotted[:s][:label] == "b.1"
  assert dotted[:o][:label] == "c"
end

test "N-Quads reads a graph; N-Triples refuses a fourth term"
  text = "<http://e/s> <http://e/p> <http://e/o> <http://e/g> ."
  q = first(read(text, "t", true)[:quads])
  assert q[:g] == iri("http://e/g")
  assert size(nt(text)[:refused]) == 1
  assert rdf_refused?(
    () -> quad(literal("a"), iri("http://e/p"), literal("b"), nil)
  )
end

test "what is written reads back to the same quads"
  text = unlines(
    [
      "<http://e/s> <http://e/p> \"a\\nb\"@en <http://e/g> .",
      "_:x <http://e/p> \"1\"^^<http://www.w3.org/2001/XMLSchema#integer> .",
      "<http://e/s> <http://e/p> _:x ."
    ]
  )
  first_read = read(text, "t", true)
  again = read(write(first_read[:quads], "t"), "t", true)
  assert first_read[:refused] == []
  assert again[:quads] == first_read[:quads]
end

test "equal terms share an id"
  assert term_id(iri("http://e/a")) == term_id(iri("http://e/a"))
  assert term_id(literal("a")) != term_id(lang("a", "en"))
end
