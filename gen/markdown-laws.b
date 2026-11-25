use("bunsho", %i[extract inlines law_failures parse plain_text walk])
use("hon", %i[doc_pages path_in])
use("moji", %i[after_first before_first drop_chars made_of text_of])
use("retsu", %i[find_first first flat_map last push])
use("shuugou", [:frequencies])

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
inline_runs: Every run of inline nodes a Markdown page holds, as [line, nodes]: each paragraph's and heading's, and each table cell's under its table's first line; a code block holds none.

    length(inline_runs(join_lines(["# A", "", "b", "", "| c | d |", "|---|---|"]))) #=> 4
"""
def inline_runs(text)
  inline_runs_of(parse(text))
end

@doc """
inline_runs_of: inline_runs over a page already parsed.

    length(inline_runs_of(parse("a `b` c"))) #=> 1
"""
def inline_runs_of(tree)
  flat_map(
    filter((n) -> member?(n[:kind], %i[heading paragraph table]), walk(tree)),
    fn(block)
      line = if block[:at].nil?
        0
      else
        block[:at][0]
      end
      if block[:kind] == :table
        map(
          (c) -> [line, walk(c)],
          filter((n) -> n[:kind] == :table_cell, walk(block))
        )
      else
        [[line, walk(block)]]
      end
    end
  )
end

@doc """
page_claims: The results a Markdown page states, as [line, expression, claim], read from every run of inline nodes it holds.

    page_claims(join_lines(["# A", "", "`7 / 2` is 3.5."])) #=> [[3, "7 / 2", [:is, "3.5"]]]
"""
def page_claims(text)
  flat_map(
    inline_runs(text),
    (r) -> map((c) -> [first(r), first(c), last(c)], claims_in(last(r)))
  )
end

REPO_TOPS = %w[
  bench
  bidamas
  crates
  docs
  eval
  examples
  gen
  kernel
  native
  nix
  rules
  spec
  tree-sitter-blue
]

@doc """
row_state: The state a status table's row claims: :not when its text holds ❌, since a row not built may name the file that will make it, :claimed when it holds ✅ or ⏳, and nil when it holds none.

    row_state("tls ⏳ in progress crates/x.rs") #=> :claimed
"""
def row_state(text)
  if contains?(text, "❌")
    :not
  elsif contains?(text, "✅") or contains?(text, "⏳")
    :claimed
  end
end

@doc """
cited_path: The repository path a code span cites, its `:line` and `#anchor` dropped, when its first segment is a top-level directory of the repository; nil for any other span.

    cited_path("crates/blue-lang-check/src/form_rules.rs:212") #=> "crates/blue-lang-check/src/form_rules.rs"
"""
def cited_path(code)
  bare = before_first(before_first(code, "#"), ":")
  if contains?(bare, "/") and
      member?(before_first(bare, "/"), REPO_TOPS) and
      not any?((c) -> contains?(bare, c), [" ", "*", "{", "<", "…", "$", "("])
    bare
  end
end

@doc """
status_rows: The rows of every table of a Markdown page, as [line, state, code spans]: the source line, the state row_state reads from the row's text, and its code spans in order.

    status_rows(join_lines(["| a | b |", "|---|---|", "| `x/y` | ✅ |"])) #=> [[1, nil, []], [3, :claimed, ["x/y"]]]
"""
def status_rows(text)
  flat_map(
    filter((n) -> n[:kind] == :table, walk(parse(text))),
    fn(t)
      start = t[:at][0]
      rows = filter((n) -> n[:kind] == :table_row, walk(t))
      map(
        fn(i)
          nodes = filter(
            (n) -> member?(n[:kind], %i[text inline_code]),
            walk(rows[i])
          )
          line = if i == 0
            start
          else
            start + i + 1
          end
          [
            line,
            row_state(join(map((n) -> n[:text], nodes), " ")),
            map((n) -> n[:text], built_codes(nodes))
          ]
        end,
        range(length(rows))
      )
    end
  )
end

@doc """
built_codes: The code spans of a row's text and code nodes that come before its first `not built`: what the row cites as made, not what its `Not built:` clause names as still to make.

    built_codes(inlines("`a/b`; Not built: `c/d`", 1)) #=> [{kind: :inline_code, text: "a/b"}]
"""
def built_codes(nodes)
  stop = find_first(
    fn(i)
      nodes[i][:kind] == :text and
        contains?(downcase(nodes[i][:text]), "not built")
    end,
    range(length(nodes))
  )
  filter((n) -> n[:kind] == :inline_code, take(stop or length(nodes), nodes))
end

@doc """
claimed_paths: The repository paths the ✅ and ⏳ rows of the pages' status tables cite, as [where, path], a page being [path, text].

    claimed_paths([["d.md", join_lines(["| a | b |", "|---|---|", "| ✅ | `docs/x.md` |", "| ❌ | `docs/y.md` |"])]]) #=> [["d.md:3", "docs/x.md"]]
"""
def claimed_paths(pages)
  flat_map(
    pages,
    fn(p)
      flat_map(
        filter((r) -> r[1] == :claimed, status_rows(last(p))),
        fn(r)
          map(
            (path) -> ["#{first(p)}:#{to_s(r[0])}", path],
            filter((c) -> c != nil, map(cited_path, r[2]))
          )
        end
      )
    end
  )
end

@doc """
evidence_failures: Why each repository path a ✅ or ⏳ row cites fails: it leads into a directory this check does not read (`inputs`), or it reaches no file under `at`.

    evidence_failures(".", ["docs"], [["d.md", join_lines(["| a |", "|---|", "| ⏳ `gen/x.b` |"])]]) #=> ["d.md:3: `gen/x.b` leads into `gen`, which this check does not read; list `gen` in the inputs of check(\"markdown-laws\", …)"]
"""
def evidence_failures(at, inputs, pages)
  flat_map(
    claimed_paths(pages),
    fn(c)
      where = first(c)
      path = last(c)
      top = before_first(path, "/")
      if not member?(top, inputs)
        [
          "#{where}: `#{path}` leads into `#{top}`, which this check does not read; list `#{top}` in the inputs of check(\"markdown-laws\", …)"
        ]
      elsif not path_exists(path_join(at, path))
        ["#{where}: `#{path}` is cited by a ✅ or ⏳ row and reaches no file"]
      else
        []
      end
    end
  )
end

@doc """
row_id?: Whether a code span has a spec row id's shape: lower-case words joined by dots.

    row_id?("fn.deep_recursion.catchable") #=> true
"""
def row_id?(text)
  contains?(text, ".") and
    made_of(text, "abcdefghijklmnopqrstuvwxyz0123456789_.?!") and
    not starts_with?(text, ".") and
    not ends_with?(text, ".")
end

@doc """
citation?: Whether the code span at `i` of a run of inline nodes cites a spec row: a row id after `row ` or `rows `, or one that continues such a list after `, `, ` and ` or `, and `.

    citation?(inlines("spec rows `a.b` and `c.d`", 1), 3) #=> true
"""
def citation?(nodes, i)
  n = nodes[i]
  before = nodes[i - 1]
  if n.nil? or
      before.nil? or
      n[:kind] != :inline_code or
      before[:kind] != :text or
      not row_id?(n[:text])
    false
  else
    t = downcase(replace(before[:text], line_break, " "))
    ends_with?(" #{t}", " row ") or
      ends_with?(" #{t}", " rows ") or
      member?(t, [", ", " and ", ", and "]) and citation?(nodes, i - 2)
  end
end

@doc """
citation_failures: Each spec row a page cites that spec/rows/ does not hold, a page being [path, text] and `ids` every row id.

    citation_failures([["d.md", "Rows `a.b` and `c.d`."]], ["a.b"]) #=> ["d.md:1: spec row `c.d` is cited, and spec/rows/ holds no row with that id"]
"""
def citation_failures(pages, ids)
  flat_map(
    pages,
    fn(p)
      flat_map(
        inline_runs(last(p)),
        fn(r)
          nodes = last(r)
          map(
            fn(i)
              "#{first(p)}:#{to_s(first(r))}: spec row `#{nodes[i][:text]}` is cited, and spec/rows/ holds no row with that id"
            end,
            filter(
              (i) -> citation?(nodes, i) and not member?(nodes[i][:text], ids),
              range(length(nodes))
            )
          )
        end
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
spec_rows: Every conformance row, as {id:, src:, expect:}, from `blue doc --rows`, which reads spec/rows/ and each row's program as the conformance runner does.

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

test "every path a ✅ or ⏳ row cites reaches a file, and every spec row a page cites exists"
  pages = fact_pages(root)
  ids = map((r) -> r[:id], spec_rows)
  found = append(
    evidence_failures(root, declared_inputs(root), pages),
    citation_failures(pages, ids)
  )
  if found != []
    write_stderr(unlines(found))
  end
  assert length(claimed_paths(pages)) >= 150
  assert member?("fn.deep_recursion", ids)
  assert found == []
end

test "a cited path that reaches nothing or leads where the check does not read, and a cited row that does not exist, are refused; a ❌ row and good citations pass"
  dir = path_join(temp_dir("evidence"), "evidence")
  mkdir_p(path_join(dir, "docs"))
  write_file(path_join(dir, "docs/b.md"), "# B")
  text = join_lines(
    [
      "| Item | State | What makes it true |",
      "|---|---|---|",
      "| a | ✅ built | `docs/b.md` and `docs/gone.md:12` |",
      "| c | ⏳ in progress | `gen/x.b` |",
      "| d | ❌ not built | `docs/later.md` |",
      "",
      "Spec rows `x.y` and `p.q` hold it; `r.s` is a field."
    ]
  )
  pages = [["docs/a.md", text]]
  found = append(
    evidence_failures(dir, ["docs"], pages),
    citation_failures(pages, ["x.y"])
  )
  rm_rf(dir)
  assert found ==
    [
      "docs/a.md:3: `docs/gone.md` is cited by a ✅ or ⏳ row and reaches no file",
      "docs/a.md:4: `gen/x.b` leads into `gen`, which this check does not read; list `gen` in the inputs of check(\"markdown-laws\", …)",
      "docs/a.md:7: spec row `p.q` is cited, and spec/rows/ holds no row with that id"
    ]
end

@doc """
digits_end: The index just past the run of decimal digits that starts at `i` of `cs`.

    digits_end(chars("R14 (U9)"), 1) #=> 3
"""
def digits_end(cs, i)
  if digit?(cs[i])
    digits_end(cs, i + 1)
  else
    i
  end
end

@doc """
r_id_at: The R id a text starts with: `R`, its digits and at most one lower-case letter, when no letter or digit follows; nil otherwise.

    r_id_at("R6b folds into R7") #=> "R6b"
"""
def r_id_at(text)
  cs = chars(text)
  if cs[0] != "R" or not digit?(cs[1])
    nil
  else
    d = digits_end(cs, 1)
    e = if cs[d] != nil and contains?("abcdefghijklmnopqrstuvwxyz", cs[d])
      d + 1
    else
      d
    end
    if not name_start?(cs[e]) and not digit?(cs[e])
      text_of(cs, 0, e)
    end
  end
end

@doc """
r_id_of: The R id a heading starts with, or a table row's first cell; nil for any other node, and for one that starts with none.

    r_id_of(first(parse("### R0 — a")[:children])) #=> "R0"
"""
def r_id_of(n)
  head = if n[:kind] == :heading
    n
  elsif n[:kind] == :table_row
    first(n[:children] or [])
  end
  if head != nil
    r_id_at(trim(plain_text(head[:children] or [])))
  end
end

@doc """
r_ids_defined: The R ids a parsed page defines: each heading, and each table row whose first cell, that starts with one.

    r_ids_defined(parse(join_lines(["### R0 — a", "", "| # | x |", "|---|---|", "| R1 | a |", "| R2: b | c |"]))) #=> ["R0", "R1", "R2"]
"""
def r_ids_defined(tree)
  filter((id) -> id != nil, map(r_id_of, walk(tree)))
end

@doc """
r_ids_repeated: Each R id that two rows of one table of R ids start with, as [line, id], the line the table opens on. A table of R ids allocates them, every row below its header starting with one, so there one id names one row. A ledger that mixes series (`S0`, `L1`, `R6a (first slice)`) gives an item a row per slice, and a heading and a row that start with one id are its section and its row: neither allocates an id twice.

    r_ids_repeated(parse(join_lines(["### R1 — a", "", "| # | x |", "|---|---|", "| R1 | a |", "| R2 (b) | c |", "| R2 (d) | e |"]))) #=> [[3, "R2"]]
"""
def r_ids_repeated(tree)
  flat_map(
    extract(tree, :table),
    fn(t)
      rows = drop(1, t[:children])
      ids = filter((id) -> id != nil, map(r_id_of, rows))
      if length(ids) < length(rows)
        []
      else
        map(
          (f) -> [t[:at][0], first(f)],
          filter((f) -> last(f) > 1, frequencies(ids))
        )
      end
    end
  )
end

@doc """
doc_name: The name a page goes by in an R id's qualifier: its file name without `.md`.

    doc_name("docs/PURE-BLUE.md") #=> "PURE-BLUE"
"""
def doc_name(path)
  before_first(last(split(path, "/")), ".md")
end

@doc """
qualifier_word: The page name a word of prose holds, with a bracket, `docs/`, `.md` and a possessive taken off, or nil when it holds none of `names`.

    qualifier_word("(docs/PERFORMANCE.md", ["PERFORMANCE"]) #=> "PERFORMANCE"
"""
def qualifier_word(word, names)
  bare = before_first(
    before_first(
      replace(replace(replace(word, "(", ""), "[", ""), "docs/", ""),
      ".md"
    ),
    "'"
  )
  if member?(bare, names)
    bare
  end
end

@doc """
r_tokens: Each R id a run of prose names, as [index, id, page]: the page is the one a word before the id names (past `ruling` or `rule`), or one after it as `of PAGE`, or the one the list it continues carries (after `, `, ` and `, ` to ` or `-`); nil when the id is bare.

    r_tokens("PERFORMANCE R5 and R11, then R2 of ROADMAP", ["PERFORMANCE", "ROADMAP"]) #=> [[12, "R5", "PERFORMANCE"], [19, "R11", "PERFORMANCE"], [29, "R2", "ROADMAP"]]
"""
def r_tokens(text, names)
  cs = chars(text)
  found = filter(
    (x) -> x != nil,
    map(
      fn(i)
        if cs[i] == "R" and not name_start?(cs[i - 1]) and not digit?(cs[i - 1])
          id = r_id_at(text_of(cs, i, length(cs)))
          if id != nil
            [i, id]
          end
        end
      end,
      range(length(cs))
    )
  )
  reduce(
    fn(acc, x)
      i = first(x)
      id = last(x)
      prior = last(acc)
      gap = if prior != nil
        text_of(cs, prior[0] + length(prior[1]), i)
      end
      words = filter((w) -> w != "", split(text_of(cs, 0, i), " "))
      said = if member?(last(words), %w[ruling rule rulings rules])
        words[length(words) - 2]
      else
        last(words)
      end
      after = filter(
        (w) -> w != "",
        split(text_of(cs, i + length(id), length(cs)), " ")
      )
      of = if first(after) == "of"
        qualifier_word(after[1] or "", names)
      end
      page = if gap != nil and
          member?(gap, [", ", " and ", ", and ", " to ", "-", " or "])
        prior[2]
      else
        qualifier_word(said or "", names) or of
      end
      push(acc, [i, id, page])
    end,
    [],
    found
  )
end

@doc """
r_tables: Each page's path and the R ids it defines, as [path, ids], pages being [path, parsed tree].

    r_tables([["docs/A.md", parse(join_lines(["| R1 | x |", "|---|---|"]))]]) #=> [["docs/A.md", ["R1"]]]
"""
def r_tables(trees)
  map((t) -> [first(t), r_ids_defined(last(t))], trees)
end

@doc """
defines?: Whether a page's R ids hold `id`, an id naming the family its lettered rows split it into (R6 for R6a, R6b and R6c).

    defines?(["R5", "R6a", "R6b"], "R6") #=> true
"""
def defines?(ids, id)
  member?(id, ids) or
    any?(
      fn(d)
        starts_with?(d, id) and
          length(d) == length(id) + 1 and
          contains?("abcdefghijklmnopqrstuvwxyz", last(chars(d)))
      end,
      ids
    )
end

@doc """
ids_of: The R ids the page at `path` defines, [] for a page that defines none or does not exist.

    ids_of([["docs/A.md", ["R1"]]], "docs/B.md") #=> []
"""
def ids_of(tables, path)
  last(find_first((t) -> first(t) == path, tables) or [path, []])
end

@doc """
ids_named: The R ids the pages a qualifier names define, a page's name being its file name without `.md`; [] when no such page defines any.

    ids_named([["docs/A.md", ["R1"]], ["docs/x/A.md", ["R2"]], ["docs/B.md", ["R3"]]], "A") #=> ["R1", "R2"]
"""
def ids_named(tables, name)
  flat_map(filter((t) -> doc_name(first(t)) == name, tables), last)
end

@doc """
front_value: The value of a front matter key of a parsed page, or nil.

    front_value(parse(join_lines(["---", "r_ids: PERFORMANCE.md", "---", "# A"])), "r_ids") #=> "PERFORMANCE.md"
"""
def front_value(tree, key)
  last(find_first((kv) -> first(kv) == key, tree[:front] or []) or [key, nil])
end

@doc """
r_id_failure: Why one R id of a page fails, or [] when it names a row: an id qualified by a page that defines no such row; a bare id on a page whose own ids, or the ids its front matter's `r_ids:` names, do not hold it; a bare id where the page has neither.

    r_id_failure("a.md:3", [0, "R2", nil], ["a.md", ["R1"]], []) #=> ["a.md:3: R2 is not an R id of a.md (R1); name the page an id from elsewhere comes from, as in PERFORMANCE R2"]
"""
def r_id_failure(where, token, table, tables)
  id = token[1]
  page = token[2]
  if page != nil and defines?(ids_named(tables, page), id)
    []
  elsif page != nil
    ["#{where}: #{page} #{id} names no row: #{page} defines no #{id}"]
  elsif table.nil?
    [
      "#{where}: a bare #{id} on a page with no R ids of its own; name the page that defines it (PERFORMANCE #{id}), or name that page in the front matter (r_ids: PERFORMANCE.md)"
    ]
  elsif not defines?(last(table), id)
    [
      "#{where}: #{id} is not an R id of #{first(table)} (#{join(last(table), ", ")}); name the page an id from elsewhere comes from, as in PERFORMANCE #{id}"
    ]
  else
    []
  end
end

@doc """
r_id_failures: Why each R id the pages define or their prose names fails, a page being [path, text]: two rows of one table of R ids that start with one id are refused, and a page names bare its own ids and those of the page its front matter names in `r_ids:` (a sub-page and its parent), and any other page's ids after that page's name (`PERFORMANCE R7`), so one id never means two rows. A page's own ids are its path's, so two pages of one file name keep their own. Code spans and code blocks name nothing.

    r_id_failures([["docs/D.md", "D names R3, and `R5` is code."]]) #=> ["docs/D.md:1: a bare R3 on a page with no R ids of its own; name the page that defines it (PERFORMANCE R3), or name that page in the front matter (r_ids: PERFORMANCE.md)"]
"""
def r_id_failures(pages)
  trees = map((p) -> [first(p), parse(last(p))], pages)
  tables = r_tables(trees)
  names = map((t) -> doc_name(first(t)), filter((t) -> last(t) != [], tables))
  flat_map(
    trees,
    fn(t)
      path = first(t)
      tree = last(t)
      own = ids_of(tables, path)
      declared = front_value(tree, "r_ids")
      table = if declared != nil
        [declared, append(own, ids_named(tables, doc_name(declared)))]
      elsif own != []
        [path, own]
      end
      repeated = map(
        fn(r)
          "#{path}:#{to_s(first(r))}: two rows of this table start with #{last(r)}; one id names one row, so give the later one the next free id"
        end,
        r_ids_repeated(tree)
      )
      named = flat_map(
        inline_runs_of(tree),
        fn(run)
          where = "#{path}:#{to_s(first(run))}"
          flat_map(
            filter((n) -> n[:kind] == :text, last(run)),
            fn(n)
              flat_map(
                r_tokens(replace(n[:text], line_break, " "), names),
                (token) -> r_id_failure(where, token, table, tables)
              )
            end
          )
        end
      )
      append(repeated, named)
    end
  )
end

test "every R id a page names is one row of one page"
  pages = doc_pages(root)
  found = r_id_failures(pages)
  if found != []
    write_stderr(unlines(found))
  end
  tables = r_tables(map((p) -> [first(p), parse(last(p))], pages))
  assert length(filter((t) -> last(t) != [], tables)) >= 8
  assert member?("R19", ids_of(tables, "docs/PERFORMANCE.md"))
  assert member?("R6", ids_named(tables, "PERFORMANCE"))
  assert found == []
end

test "an id a page does not define, a qualified id its page lacks and a bare id with no table are refused; a declared table and code pass"
  pages = [
    [
      "docs/A.md",
      join_lines(
        [
          "| # | x |",
          "|---|---|",
          "| R1 | a |",
          "",
          "See R1, R2 and B R1, and B R9."
        ]
      )
    ],
    ["docs/B.md", join_lines(["| # | y |", "|---|---|", "| R1 | b |"])],
    [
      "docs/C.md",
      join_lines(["---", "r_ids: B.md", "---", "", "C cites R1 and R4."])
    ],
    ["docs/D.md", "D names R3, and `R5` is code."]
  ]
  assert r_id_failures(pages) ==
    [
      "docs/A.md:5: R2 is not an R id of docs/A.md (R1); name the page an id from elsewhere comes from, as in PERFORMANCE R2",
      "docs/A.md:5: B R9 names no row: B defines no R9",
      "docs/C.md:5: R4 is not an R id of B.md (R1); name the page an id from elsewhere comes from, as in PERFORMANCE R4",
      "docs/D.md:1: a bare R3 on a page with no R ids of its own; name the page that defines it (PERFORMANCE R3), or name that page in the front matter (r_ids: PERFORMANCE.md)"
    ]
end

test "an id two rows of a table of R ids start with is refused; a heading and a row share one, a ledger's slices share one, and pages of one file name keep their own ids"
  pages = [
    [
      "docs/A.md",
      join_lines(
        [
          "### R1 — a",
          "",
          "| # | x |",
          "|---|---|",
          "| R1 | a |",
          "| R2 (U9) | b |",
          "| R2 (U10) | c |",
          "",
          "A cites R1 and R2.",
          "",
          "| Rung | built |",
          "|---|---|",
          "| S0 | f |",
          "| R1 (first slice) | g |",
          "| R1 (second slice) | h |"
        ]
      )
    ],
    [
      "docs/x/E.md",
      join_lines(
        ["| # | x |", "|---|---|", "| R3 | d |", "", "E cites R3 and R4."]
      )
    ],
    [
      "docs/y/E.md",
      join_lines(["| # | y |", "|---|---|", "| R4 | e |", "", "E cites R4."])
    ]
  ]
  assert r_id_failures(pages) ==
    [
      "docs/A.md:3: two rows of this table start with R2; one id names one row, so give the later one the next free id",
      "docs/x/E.md:5: R4 is not an R id of docs/x/E.md (R3); name the page an id from elsewhere comes from, as in PERFORMANCE R4"
    ]
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
