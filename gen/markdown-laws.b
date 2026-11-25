use("bunsho", %i[extract inlines law_failures parse walk])
use("hon", %i[doc_pages path_in])
use("moji", %i[after_first before_first drop_chars text_of])
use("retsu", %i[find_first first flat_map last push])

LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
DIGITS = "0123456789"

BOUND_WORDS = %w[
  and
  begin
  case
  do
  else
  elsif
  end
  ensure
  false
  fn
  if
  nil
  not
  or
  rescue
  true
  when
]

def root()
  getenv("GEN_ROOT", ".")
end

@doc """
name_start?: Whether a character can begin a blue name: a letter or `_`.

    name_start?("a") #=> true
"""
def name_start?(c)
  c != nil and contains?(LETTERS, c)
end

@doc """
digit?: Whether a character is a decimal digit.

    digit?("7") #=> true
"""
def digit?(c)
  c != nil and contains?(DIGITS, c)
end

@doc """
string_end: The index just past the closing quote of the string literal whose body starts at `i` of `cs`.

    string_end(chars("\"ab\" x"), 1) #=> 4
"""
def string_end(cs, i)
  c = cs[i]
  if c.nil?
    i
  elsif c == "\\"
    string_end(cs, i + 2)
  elsif c == "\""
    i + 1
  else
    string_end(cs, i + 1)
  end
end

@doc """
number_end: The index just past the number that starts at `i` of `cs`; a `.` belongs to it only before a digit, so a sentence's full stop does not.

    number_end(chars("3.5, 2."), 0) #=> 3
"""
def number_end(cs, i)
  c = cs[i]
  if name_start?(c) or digit?(c) or c == "." and digit?(cs[i + 1])
    number_end(cs, i + 1)
  else
    i
  end
end

@doc """
name_end: The index just past the name that starts at `i` of `cs`: its letters and digits, a `::` joining the next level, and a last `?` or `!`.

    name_end(chars("retsu::is_empty(xs)"), 0) #=> 15
"""
def name_end(cs, i)
  c = cs[i]
  if name_start?(c) or digit?(c)
    name_end(cs, i + 1)
  elsif c == ":" and cs[i + 1] == ":" and name_start?(cs[i + 2])
    name_end(cs, i + 2)
  elsif c == "?" or c == "!"
    i + 1
  else
    i
  end
end

@doc """
bracket_end: The index just past the `]` that closes the `[` at `i` of `cs`, strings skipped whole; the length of `cs` when none does.

    bracket_end(chars("[1, [\"]\"]] is"), 0, 0) #=> 10
"""
def bracket_end(cs, i, depth)
  c = cs[i]
  if c.nil?
    i
  elsif c == "\""
    bracket_end(cs, string_end(cs, i + 1), depth)
  elsif c == "["
    bracket_end(cs, i + 1, depth + 1)
  elsif c == "]" and depth == 1
    i + 1
  elsif c == "]"
    bracket_end(cs, i + 1, depth - 1)
  else
    bracket_end(cs, i + 1, depth)
  end
end

@doc """
free_names: The names a blue expression reads that the language does not give it: a name not a keyword, a map key, a field after `.` or a word of the language, and not a call of one of the `known` builtins. Text in a string literal names nothing.

    free_names("list?(nil) == [\"x\"] and f(1)", ["list?"]) #=> ["f"]
"""
def free_names(code, known)
  names_from(chars(code), 0, [], known)
end

@doc """
names_from: free_names over the characters of `cs` from `i`, each free name pushed onto `out`; a string that interpolates reads what its `#{…}` reads, so it counts as one free name.

    names_from(chars("get(m, {a: \"#\u{7b}n}\"})"), 0, [], ["get"]) #=> ["m", "#\u{7b}…}"]
"""
def names_from(cs, i, out, known)
  c = cs[i]
  if c.nil?
    out
  elsif c == "\""
    e = string_end(cs, i + 1)
    names_from(
      cs,
      e,
      if contains?(text_of(cs, i, e), "#\u{7b}")
        push(out, "#\u{7b}…}")
      else
        out
      end,
      known
    )
  elsif digit?(c)
    names_from(cs, number_end(cs, i), out, known)
  elsif name_start?(c)
    e = name_end(cs, i)
    word = text_of(cs, i, e)
    before = cs[i - 1]
    bound = member?(word, BOUND_WORDS) or
      before == ":" or
      before == "." or
      cs[e] == "(" and member?(word, known) or
      cs[e] == ":" and cs[e + 1] != ":"
    names_from(
      cs,
      e,
      if bound
        out
      else
        push(out, word)
      end,
      known
    )
  else
    names_from(cs, i + 1, out, known)
  end
end

@doc """
literal_prefix: The blue literal a text starts with, as written: a string, a list, a keyword, a number, true, false or nil; nil when it starts with none.

    literal_prefix("3.5, while") #=> "3.5"
"""
def literal_prefix(text)
  cs = chars(text)
  c = cs[0]
  e = if c == "\""
    string_end(cs, 1)
  elsif c == "["
    bracket_end(cs, 0, 0)
  elsif c == ":" and name_start?(cs[1])
    name_end(cs, 1)
  elsif c == "-" and digit?(cs[1])
    number_end(cs, 1)
  elsif digit?(c)
    number_end(cs, 0)
  elsif name_start?(c)
    name_end(cs, 0)
  else
    0
  end
  word = text_of(cs, 0, e)
  if e == 0 or name_start?(c) and not member?(word, %w[false nil true])
    nil
  else
    word
  end
end

@doc """
call_before: The call that ends just before index `p` of `cs`, `name(arguments)` with a bare or qualified name, or nil when the text there is not one.

    call_before(chars("so f(g(1), 2) is 3"), 13) #=> "f(g(1), 2)"
"""
def call_before(cs, p)
  if cs[p - 1] != ")"
    nil
  else
    open = paren_open(cs, p - 1, 0)
    at = name_start_before(cs, open)
    if open < 1 or at.nil?
      nil
    else
      text_of(cs, at, p)
    end
  end
end

@doc """
paren_open: The index of the `(` that the `)` at `i` of `cs` closes, scanning back; -1 when none does.

    paren_open(chars("f(g(1))"), 6, 0) #=> 1
"""
def paren_open(cs, i, depth)
  c = cs[i]
  if c.nil? or i < 0
    -1
  elsif c == ")"
    paren_open(cs, i - 1, depth + 1)
  elsif c == "(" and depth == 1
    i
  elsif c == "("
    paren_open(cs, i - 1, depth - 1)
  else
    paren_open(cs, i - 1, depth)
  end
end

@doc """
name_start_before: The index where the name that ends just before index `open` of `cs` starts, or nil when no whole name ends there.

    name_start_before(chars("x list?(nil)"), 7) #=> 2
"""
def name_start_before(cs, open)
  at = name_back(cs, open)
  before = cs[at - 1]
  if at >= open or
      not name_start?(cs[at]) or
      before == "." or
      before == ":" or
      digit?(before)
    nil
  else
    at
  end
end

@doc """
name_back: The index the name characters ending before index `i` of `cs` start at, a last `?` or `!` and `::` joins included.

    name_back(chars("a kyohi::ok?("), 12) #=> 2
"""
def name_back(cs, i)
  c = cs[i - 1]
  if (c == "?" or c == "!") and name_start?(cs[i - 2])
    name_back(cs, i - 1)
  elsif i > 0 and (name_start?(c) or digit?(c))
    name_back(cs, i - 1)
  elsif c == ":" and cs[i - 2] == ":" and name_start?(cs[i - 3])
    name_back(cs, i - 2)
  else
    i
  end
end

def declared_inputs(at)
  get(
    get(
      get(
        json_read(read_file(path_join(at, "Bluefile.lock")))["manifest"],
        "checks"
      ),
      "markdown-laws"
    ),
    "inputs"
  )
end

def leaves_project?(target)
  target == "" or
    starts_with?(target, "/") or
    starts_with?(target, "mailto:") or
    contains?(target, "://")
end

def anchors_in(text)
  map((h) -> h[:anchor], extract(parse(text), :heading))
end

def link_failure(at, inputs, page, link)
  target = link[:target]
  file = before_first(target, "#")
  anchor = after_first(target, "#")
  rel = if file == ""
    first(page)
  else
    path_in(path_dirname(first(page)), file)
  end
  top = first(split(rel, "/"))
  path = path_join(at, rel)
  where = "#{first(page)}:#{to_s(link[:line])}"
  if leaves_project?(target) or top == ".."
    nil
  elsif not member?(top, inputs)
    "#{where}: `#{target}` leads into `#{top}`, which this check does not read; list `#{top}` in the inputs of check(\"markdown-laws\", …)"
  elsif not path_exists(path)
    "#{where}: `#{target}` reaches no file"
  elsif anchor != "" and
      ends_with?(path, ".md") and
      not member?(anchor, anchors_in(read_file(path)))
    "#{where}: `#{target}` names no heading `#{anchor}`"
  end
end

def link_failures(at, inputs, pages)
  flat_map(
    pages,
    fn(page)
      filter(
        (f) -> f != nil,
        map(
          (l) -> link_failure(at, inputs, page, l),
          extract(parse(last(page)), %i[link image])
        )
      )
    end
  )
end

VERBS = [" is ", " gives ", " answers ", " returns "]

@doc """
claim_after: The result the text after an expression states: [:raises] when it reads `raises`, [:is, v] when it reads `is`, `gives`, `answers` or `returns` and a literal v, or the verb and then `code`, a code span holding one; nil when it states none.

    claim_after(" gives false, and", nil) #=> [:is, "false"]
"""
def claim_after(text, code)
  t = replace(text, line_break, " ")
  verb = find_first((w) -> starts_with?(t, w), VERBS)
  if starts_with?(t, " raises")
    [:raises]
  elsif verb != nil
    rest = drop_chars(t, length(verb))
    v = if trim(rest) == "" and code != nil
      code
    else
      literal_prefix(rest)
    end
    if v != nil and literal_prefix(v) == v
      [:is, v]
    end
  end
end

@doc """
spots_of: Every index of `word` in `text` at or after `from`, in order, pushed onto `out`.

    spots_of("a is b is c", " is ", 0, []) #=> [1, 6]
"""
def spots_of(text, word, from, out)
  p = text_index(text, word, from)
  if p < 0
    out
  else
    spots_of(text, word, p + 1, push(out, p))
  end
end

@doc """
call_claims: The results plain text states about the calls it names, as [call, claim]: each `name(arguments)` followed by `is` and a literal, or by `raises`.

    call_claims("so round(2.5) is 3, and f(x) raises.") #=> [["round(2.5)", [:is, "3"]], ["f(x)", [:raises]]]
"""
def call_claims(text)
  t = replace(text, line_break, " ")
  cs = chars(t)
  spots = sort_keyed(
    (p) -> p,
    flat_map(push(VERBS, " raises"), (w) -> spots_of(t, w, 0, []))
  )
  flat_map(
    spots,
    fn(p)
      call = call_before(cs, p)
      claim = claim_after(drop_chars(t, p), nil)
      if call.nil? or claim.nil?
        []
      else
        [[call, claim]]
      end
    end
  )
end

@doc """
claims_in: The results a run of inline nodes states, as [expression, claim]: a code span followed by `is` and a literal or by `raises`, and in plain text a call followed by the same.

    claims_in(inlines("`list?(nil)` is false", 1)) #=> [["list?(nil)", [:is, "false"]]]
"""
def claims_in(nodes)
  flat_map(
    range(length(nodes)),
    fn(i)
      n = nodes[i]
      after = nodes[i + 1]
      later = nodes[i + 2]
      if n[:kind] == :text
        call_claims(n[:text])
      elsif n[:kind] == :inline_code and after != nil and after[:kind] == :text
        code = if later != nil and later[:kind] == :inline_code
          later[:text]
        end
        claim = claim_after(after[:text], code)
        if claim.nil?
          []
        else
          [[n[:text], claim]]
        end
      else
        []
      end
    end
  )
end

@doc """
page_claims: The results a Markdown page states, as [line, expression, claim], read from every paragraph, heading and table cell; code blocks state none.

    page_claims(join_lines(["# A", "", "`7 / 2` is 3.5."])) #=> [[3, "7 / 2", [:is, "3.5"]]]
"""
def page_claims(text)
  flat_map(
    filter(
      (n) -> member?(n[:kind], %i[heading paragraph table]),
      walk(parse(text))
    ),
    fn(block)
      line = if block[:at].nil?
        0
      else
        block[:at][0]
      end
      runs = if block[:kind] == :table
        filter((n) -> n[:kind] == :table_cell, walk(block))
      else
        [block]
      end
      flat_map(
        runs,
        (r) -> map((c) -> [line, first(c), last(c)], claims_in(walk(r)))
      )
    end
  )
end

@doc """
stated_facts: The results pages and reference lines state about expressions of the language, as [where, expression, claim]: the runtime facts a spec row must hold. Its words are literals and the `known` builtins: an expression with a free variable states a rule, not a fact; a bare literal states nothing; one that calls a definition of its own example, or a bidama's word (`a::b`), is held by that code's tests, since a one-line row has no `use`. A page is [path, text] and a reference line [where, text].

    stated_facts([["a.md", "`f(x)` is 1, `f(1)` is 2 and `g(1)` is 3"]], [], ["f"]) #=> [["a.md:1", "f(1)", [:is, "2"]]]
"""
def stated_facts(pages, lines, known)
  stated = append(
    flat_map(
      pages,
      fn(p)
        map((c) -> ["#{first(p)}:#{c[0]}", c[1], c[2]], page_claims(last(p)))
      end
    ),
    flat_map(
      lines,
      fn(l)
        map(
          (c) -> [first(l), first(c), last(c)],
          claims_in(inlines(last(l), 1))
        )
      end
    )
  )
  filter(
    (s) -> free_names(s[1], known) == [] and literal_prefix(s[1]) != s[1],
    stated
  )
end

@doc """
row_value: The value a spec row's expectation states, as its text, when it is `value("…")`; nil for any other expectation.

    row_value("value(\"[1, 2]\")") #=> "[1, 2]"
"""
def row_value(expect)
  if starts_with?(expect, "value(\"") and ends_with?(expect, "\")")
    json_parse(text_of(chars(expect), 6, length(expect) - 1))
  end
end

@doc """
fact_failure: Why a stated result fails the spec rows, or nil when a row agrees: no row runs the expression, or each row that does expects another result.

    fact_failure("a.md:3", "7 / 2", [:is, "3.5"], [{id: "d", src: "7 / 2", expect: "value(\"3.5\")"}]) #=> nil
"""
def fact_failure(where, code, claim, rows)
  mine = filter((r) -> r[:src] == code, rows)
  raises = first(claim) == :raises
  stated = if raises
    "raises"
  else
    "is #{last(claim)}"
  end
  agrees = any?(
    fn(r)
      if raises
        starts_with?(r[:expect], "fails(")
      else
        row_value(r[:expect]) == last(claim)
      end
    end,
    mine
  )
  if mine == []
    "#{where}: `#{code}` #{stated} states a runtime fact no spec row runs; add a row whose program is `#{code}` (spec/README.md)"
  elsif not agrees
    "#{where}: `#{code}` #{stated}, but spec row #{first(mine)[:id]} expects #{first(mine)[:expect]}"
  end
end

@doc """
fact_failures: Why each runtime fact the pages and reference lines state over the `known` builtins fails the spec rows, a row being {id:, src:, expect:}.

    fact_failures([["a.md", "`list?(nil)` is true"]], [], [{id: "l", src: "list?(nil)", expect: "value(\"false\")"}], ["list?"]) #=> ["a.md:1: `list?(nil)` is true, but spec row l expects value(\"false\")"]
"""
def fact_failures(pages, lines, rows, known)
  filter(
    (f) -> f != nil,
    map(
      (s) -> fact_failure(s[0], s[1], s[2], rows),
      stated_facts(pages, lines, known)
    )
  )
end

@doc """
blue_says: The text the blue running this check prints for `args`; raises when no blue runs it or the command fails, since a gate that cannot read its evidence must not pass.

    length(blue_says(["doc", "--rows"])) > 1000 #=> true
"""
def blue_says(args)
  if self_exe.nil?
    raise(
      :blind,
      "markdown-laws reads `blue #{join(args, " ")}`, and no blue runs this check"
    )
  end
  cap = exec_capture(self_exe, *args)
  if cap.status != 0
    raise(:blind, "`blue #{join(args, " ")}` failed: #{cap.stderr}")
  end
  cap.stdout
end

@doc """
spec_rows: Every conformance row whose program is a string, as {id:, src:, expect:}, from `blue doc --rows`, which parses spec/rows/ as the conformance runner does.

    length(spec_rows) > 400 #=> true
"""
def spec_rows()
  map(
    (r) -> {id: r["id"], src: r["src"], expect: r["expect"]},
    json_read(blue_says(%w[doc --rows]))
  )
end

@doc """
reference: What `blue reference` prints, read: the names, forms, keywords and operators the running blue holds, each with its line.

    length(reference["names"]) > 400 #=> true
"""
def reference()
  json_read(blue_says(["reference"]))
end

@doc """
builtin_names: The names a reference binds in every program, with no `use`.

    builtin_names({"names" => [{"name" => "abs"}]}) #=> ["abs"]
"""
def builtin_names(ref)
  map((n) -> n["name"], ref["names"])
end

@doc """
reference_lines: Every line a reference holds about a name, a form, a keyword or an operator, as [where, text]: the lines docs/REFERENCE.md, `blue doc` and the language server show.

    reference_lines({"names" => [{"name" => "abs", "doc" => "a"}], "forms" => [], "keywords" => [], "operators" => []}) #=> [["blue reference `abs`", "a"]]
"""
def reference_lines(ref)
  append(
    map((n) -> ["blue reference `#{n["name"]}`", n["doc"]], ref["names"]),
    map(
      (f) -> ["blue reference form `#{f["example"]}`", f["doc"]],
      ref["forms"]
    ),
    map(
      (k) -> ["blue reference keyword `#{k["word"]}`", k["doc"]],
      ref["keywords"]
    ),
    map(
      (o) -> ["blue reference operator `#{o["op"]}`", o["doc"]],
      ref["operators"]
    )
  )
end

@doc """
fact_pages: The pages whose results the runtime-fact law reads: every page under docs/ and bidamas/AUTHORING.md, the verified idiom.

    length(fact_pages(root)) > 30 #=> true
"""
def fact_pages(at)
  push(
    doc_pages(at),
    ["bidamas/AUTHORING.md", read_file(path_join(at, "bidamas/AUTHORING.md"))]
  )
end

test "every runtime fact a page or a reference line states is a spec row that agrees"
  ref = reference
  pages = fact_pages(root)
  lines = reference_lines(ref)
  known = builtin_names(ref)
  found = fact_failures(pages, lines, spec_rows, known)
  if found != []
    write_stderr(unlines(found))
  end
  assert length(stated_facts(pages, lines, known)) >= 20
  assert found == []
end

test "a fact no row runs and a fact its row contradicts are each refused, and agreeing facts pass"
  rows = [
    {id: "lists.nil.list_p", src: "list?(nil)", expect: "value(\"false\")"},
    {id: "numbers.div.float", src: "7 / 2", expect: "value(\"3.5\")"},
    {
      id: "lists.nil.length_raises",
      src: "length(nil)",
      expect: "fails(:eval, \"got nil\")"
    },
    {id: "numbers.round", src: "round(2.5)", expect: "value(\"3\")"}
  ]
  page = join_lines(
    [
      "# Traps",
      "",
      "- `list?(nil)` is",
      "  true, `7 / 2` is 3.5 and `length(nil)` raises.",
      "- `1 + 1` is 2, and `get(m, :k)` is nil.",
      "- `7 / 2` is `3.5`, and `nil` is not `[]`."
    ]
  )
  lines = [
    [
      "blue reference `round`",
      "Halves away: round(2.5) is 3, round(x) is 4, and round(2.5) is 2."
    ]
  ]
  known = %w[get length list? round]
  found = fact_failures([["docs/a.md", page]], lines, rows, known)
  assert length(stated_facts([["docs/a.md", page]], lines, known)) == 7
  assert found ==
    [
      "docs/a.md:3: `list?(nil)` is true, but spec row lists.nil.list_p expects value(\"false\")",
      "docs/a.md:5: `1 + 1` is 2 states a runtime fact no spec row runs; add a row whose program is `1 + 1` (spec/README.md)",
      "blue reference `round`: `round(2.5)` is 2, but spec row numbers.round expects value(\"3\")"
    ]
end

test "a name the expression reads is free unless it is a builtin's call, a keyword, a key, a field or a word of the language"
  assert free_names(
    "[nil == [], nil.nil?, :k, {a: 1}, abs(1), not true]",
    ["abs"]
  ) == []
  assert free_names("get(m, \"m\") rescue fallback", ["get"]) == %w[m fallback]
  assert free_names("kyohi::ok(1) and grade(50)", ["abs"]) ==
    %w[kyohi::ok grade]
  assert literal_prefix("[\"a\", \"b\", \"\"]. An empty") ==
    "[\"a\", \"b\", \"\"]"
  assert literal_prefix("-3, round") == "-3"
  assert literal_prefix("the value").nil?
  assert call_claims("throw(error(k, m)) is written raise(k, m)") == []
  assert claim_after(" is ", "\"000fff\"") == [:is, "\"000fff\""]
  assert row_value("fails(:eval, \"got nil\")").nil?
end

test "both Markdown laws hold on every page under docs/"
  pages = doc_pages(root)
  found = law_failures(pages)
  if found != []
    write_stderr(unlines(map((f) -> "#{first(f)}: #{to_s(last(f))}", found)))
  end
  assert length(pages) > 30
  assert found == []
end

test "every relative link under docs/ reaches a file, and every anchor a heading"
  pages = doc_pages(root)
  found = link_failures(root, declared_inputs(root), pages)
  if found != []
    write_stderr(unlines(found))
  end
  inside = filter(
    (l) -> not leaves_project?(l[:target]),
    flat_map(pages, (p) -> extract(parse(last(p)), %i[link image]))
  )
  assert length(pages) > 30
  assert length(inside) > 200
  assert found == []
end

test "a link to nowhere, an anchor to no heading and a path this check does not read are each refused, and a good one passes"
  dir = path_join(temp_dir("links"), "links")
  mkdir_p(path_join(dir, "docs"))
  mkdir_p(path_join(dir, "unread"))
  write_file(path_join(dir, "docs/b.md"), "# Real heading")
  write_file(path_join(dir, "unread/c.md"), "# C")
  text = join_lines(
    [
      "# A",
      "[good](b.md#real-heading) [web](https://example.org) [self](#a)",
      "[gone](missing.md) [lost](b.md#no-such-heading) [unseen](../unread/c.md)"
    ]
  )
  write_file(path_join(dir, "docs/a.md"), text)
  found = link_failures(dir, ["docs"], [["docs/a.md", text]])
  rm_rf(dir)
  assert length(found) == 3
  assert contains?(found[0], "`missing.md` reaches no file")
  assert contains?(found[1], "names no heading `no-such-heading`")
  assert contains?(
    found[2],
    "leads into `unread`, which this check does not read"
  )
end
