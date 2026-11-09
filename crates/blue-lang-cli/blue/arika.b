use("eigyou/kyuuji", %i[mcp_answer mcp_handler mcp_server mcp_tool serve])

use("khipu", %i[decoded encoded iri literal pattern question typed var])

use("kyohi", [:raised])
use("moji", %i[capitalize drop_chars])
use("retsu", %i[first flat_map is_empty push size])
use("sakuin", %i[invert score])
use("shomei", [:ct_root])

LIMIT = 12

def meaning(tier)
  if tier == "T0"
    "an exact copy of"
  elsif tier == "T1"
    "the code of"
  else
    "through a wrapper, the code of"
  end
end

def import_line(h)
  "use(\"#{h["package"]}\", [:#{h["name"]}])"
end

def advice(h)
  if h["fix"] == "import"
    "use the word: #{import_line(h)}"
  else
    "a domain word: move the shape down to a foundation bidama, then both use it; until then #{import_line(h)}"
  end
end

def hit_line(file, d, h)
  id = h["id"] or h["word"]
  "#{file}:#{to_s(d["line"])}: def #{d["name"]} is #{meaning(h["tier"])} #{h["word"]} (#{h["tier"]}, #{id}); #{advice(h)}"
end

def hit_lines(facts)
  flat_map(
    facts["defs"],
    (d) -> map((h) -> hit_line(facts["file"], d, h), d["hits"])
  )
end

def like_text(facts)
  if facts["outcome"] == "blind"
    ["arika: blind on #{facts["file"]}: #{facts["why"]}"]
  elsif facts["outcome"] == "empty"
    [
      "arika: no blue word has the shape of a definition in #{facts["file"]} (#{to_s(size(facts["defs"]))} checked)"
    ]
  else
    hit_lines(facts)
  end
end

def like_hook(facts)
  if facts["outcome"] == "found"
    append(
      map((l) -> "arika: #{l}", hit_lines(facts)),
      ["arika: this is advice; nothing is blocked"]
    )
  else
    []
  end
end

def bare(word)
  retsu::last(split(word, "::"))
end

def catalog_row(line)
  cells = split(line, "|")
  if size(cells) < 3 or not starts_with?(trim(cells[1]), "`")
    nil
  else
    code = split(trim(cells[1]), "`")[1]
    word = first(split(code, "("))
    gloss = trim(cells[size(cells) - 2])
    if contains?(word, "::")
      {"word" => word, "gloss" => gloss}
    end
  end
end

def catalog_rows(text)
  filter((r) -> r != nil, map(catalog_row, split(text, line_break)))
end

def has?(text, q)
  contains?(downcase(text), downcase(q))
end

def by_name(words, q)
  filter((w) -> w["word"] == q or bare(w["word"]) == q, words)
end

def by_part(words, q)
  filter(
    (w) -> has?(bare(w["word"]), q) and bare(w["word"]) != q and w["word"] != q,
    words
  )
end

def by_old(moves, q)
  filter((m) -> m["old"] == q or bare(m["old"]) == q, moves)
end

def by_gloss(rows, q)
  filter((r) -> has?(r["gloss"], q) and not has?(bare(r["word"]), q), rows)
end

def kind(w)
  if w["foundation"]
    "foundation"
  else
    "domain"
  end
end

def word_matches(facts, rows)
  q = facts["query"]
  {
    "query" => q,
    "names" => by_name(facts["words"], q),
    "old" => by_old(facts["moves"], q),
    "parts" => take(LIMIT, by_part(facts["words"], q)),
    "glosses" => take(LIMIT, by_gloss(rows, q)),
    "catalog" => if facts["catalog"].nil?
      "blind"
    else
      "found"
    end,
    "blind" => facts["blind"]
  }
end

def word_text(m)
  q = m["query"]
  out = append(
    append(
      map((w) -> "T5 name    #{w["word"]} (#{kind(w)})", m["names"]),
      map(
        (o) -> "T5 old     #{o["old"]} is #{o["word"]} since #{o["since"]}",
        m["old"]
      )
    ),
    append(
      map((w) -> "T5 part    #{w["word"]} (#{kind(w)})", m["parts"]),
      map((r) -> "T5 gloss   #{r["word"]}: #{r["gloss"]}", m["glosses"])
    )
  )
  tail = if m["catalog"] == "blind"
    ["arika: glosses blind: no CATALOG.md beside the bidamas on the load path"]
  else
    []
  end
  if is_empty(out)
    append(["arika: no blue word is named or glossed `#{q}`"], tail)
  else
    append(out, tail)
  end
end

def read_catalog(facts)
  if facts["glosses"] != nil
    facts["glosses"]
  elsif facts["catalog"].nil?
    []
  else
    catalog_rows(read_file(facts["catalog"]))
  end
end

def main()
  if size(argv) > 0 and argv[0] == "tools"
    write_stdout(unlines([json_stringify(tool_list)]))
    true
  elsif size(argv) > 3 and member?(argv[0], FACT_VERBS)
    over_facts(argv[0], argv[1], json_read(argv[2]), json_read(argv[3]))
  elsif size(argv) < 3
    true
  elsif argv[0] == "emit"
    emit(argv[1], json_read(argv[2]), argv[3])
  elsif size(argv) > 3
    answer(argv[0], argv[1], json_read(argv[2]), stale(json_read(argv[3])))
  else
    answer(argv[0], argv[1], json_read(argv[2]), nil)
  end
end

def answer(verb, mode, facts, why)
  if why != nil
    refuse(mode, facts, why)
  elsif verb == "like" and mode == "--json"
    write_stdout(unlines([json_stringify(facts)]))
  elsif verb == "like" and mode == "--hook"
    out = like_hook(facts)
    if not is_empty(out)
      write_stdout(unlines(out))
    end
  elsif verb == "like"
    write_stdout(unlines(like_text(facts)))
  elsif verb == "word"
    m = word_matches(facts, read_catalog(facts))
    if mode == "--json"
      write_stdout(unlines([json_stringify(m)]))
    else
      write_stdout(unlines(word_text(m)))
    end
  else
    raise(
      :usage,
      "usage: blue arika like FILE[:LINE] | blue arika word NAME | blue arika emit ROOT"
    )
  end
  true
end

def refusal(facts, why)
  {
    "outcome" => "blind",
    "file" => facts["file"],
    "query" => facts["query"],
    "why" => why,
    "defs" => [],
    "snapshot_root" => facts["snapshot_root"]
  }
end

def refuse(mode, facts, why)
  r = refusal(facts, why)
  if mode == "--json"
    write_stdout(unlines([json_stringify(r)]))
  else
    write_stdout(unlines(["arika: blind: #{why}"]))
  end
end

def stale(check)
  root = "b3:#{snapshot_root_of(units_of(check["rows"]))}"
  if root == check["root"]
    nil
  else
    "the facts hash to #{root}, not the header's #{check["root"]}; the index is stale: rebuild the facts (nix build .#arika-facts) or regenerate the header (nix run .#regen)"
  end
end

def leaf_of(row)
  blake3_hex(json_stringify(row))
end

def unit_of(entry)
  rows = entry[1]
  {
    "leaves" => size(rows),
    "package" => entry[0],
    "unit_root" => "b3:#{ct_root(map(leaf_of, rows))}",
    "rows" => rows
  }
end

def units_of(rows)
  map(unit_of, map_entries(blue::group_by(rows, (r) -> r["package"])))
end

def hex_of(b3)
  retsu::last(split(b3, ":"))
end

def snapshot_root_of(units)
  ct_root(map((u) -> hex_of(u["unit_root"]), units))
end

def unit_line(u)
  "{\"leaves\":#{to_s(u["leaves"])},\"package\":#{json_stringify(u["package"])},\"unit_root\":\"#{u["unit_root"]}\"}"
end

def header_text(facts, units)
  head = "{\"blind\":#{json_stringify(facts["blind"])},\"definitions\":#{to_s(facts["definitions"])},\"format\":\"arika/1\",\"leaves\":#{to_s(size(facts["rows"]))},\"repo\":#{json_stringify(facts["repo"])},\"snapshot_root\":\"b3:#{snapshot_root_of(units)}\",\"units\":["
  "#{head}#{line_break}#{join(map(unit_line, units), ",#{line_break}")}#{line_break}]}#{line_break}"
end

def facts_text(units)
  unlines(map(json_stringify, flat_map(units, (u) -> u["rows"])))
end

def covered!(facts)
  if size(facts["rows"]) != facts["definitions"]
    raise(
      :arika_coverage,
      "the emitter gave #{to_s(size(facts["rows"]))} rows for #{to_s(facts["definitions"])} definitions; every definition the engine sees is one leaf"
    )
  end
end

def emit(header, facts, facts_out)
  covered!(facts)
  units = units_of(facts["rows"])
  write_file(header, header_text(facts, units))
  if facts_out != ""
    write_file(facts_out, facts_text(units))
  end
  write_stdout(
    unlines(
      [
        "arika: wrote #{header}: #{to_s(size(facts["rows"]))} words in #{to_s(size(units))} units, #{to_s(size(facts["blind"]))} files blind"
      ]
    )
  )
  true
end

@doc """
FACT_VERBS is the verbs answered from the facts alone: each takes the facts' check (root and rows) and refuses stale facts as blind.

    member?("find", FACT_VERBS) #=> true
"""
FACT_VERBS = %w[find get uses groups changed golden quads ask mcp serve]

@doc """
BLUE_IRI is the IRI space blue's own facts are written in.

    BLUE_IRI #=> "urn:blue:"
"""
BLUE_IRI = "urn:blue:"

@doc """
RDF_TYPE is rdf:type.

    RDF_TYPE #=> "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
"""
RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

@doc """
XSD_INTEGER is xsd:integer.

    ends_with?(XSD_INTEGER, "#integer") #=> true
"""
XSD_INTEGER = "http://www.w3.org/2001/XMLSchema#integer"

@doc """
MIN_GROUP is the smallest definition, in nodes, `groups` puts in a group: B0070's threshold, below which a shared shape is too small to name a word.

    MIN_GROUP #=> 12
"""
MIN_GROUP = 12

@doc """
node is the IRI of one thing of `kind` in blue's space, its name encoded.

    node("def", "retsu::first") #=> iri("urn:blue:def:retsu::first")
"""
def node(kind, name)
  iri("#{BLUE_IRI}#{kind}:#{encoded(name)}")
end

@doc """
prop is the IRI of one of blue's predicates.

    prop("reaches") #=> iri("urn:blue:p:reaches")
"""
def prop(name)
  iri("#{BLUE_IRI}p:#{name}")
end

@doc """
fact is one quad in the snapshot's graph.

    fact(node("def", "a::x"), prop("gloss"), literal("x"), nil)[:o] #=> literal("x")
"""
def fact(s, p, o, g)
  khipu::quad(s, p, o, g)
end

@doc """
test_node is the IRI of one test: its file and line.

    test_node({"file" => "a/a.b", "line" => 3}) #=> iri("urn:blue:test:a/a.b:3")
"""
def test_node(t)
  node("test", "#{t["file"]}:#{to_s(t["line"])}")
end

@doc """
test_quads are what one test says about the definition it names: it is a test (a block or a doc example), its name, and that it exercises `d`.

    size(test_quads({"file" => "a.b", "line" => 1, "name" => "t", "doc" => false}, node("def", "a::x"), nil)) #=> 3
"""
def test_quads(t, d, g)
  n = test_node(t)
  kind = if t["doc"]
    "DocExample"
  else
    "Test"
  end
  [
    fact(n, iri(RDF_TYPE), node("class", kind), g),
    fact(n, prop("name"), literal(t["name"]), g),
    fact(n, prop("exercises"), d, g)
  ]
end

@doc """
row_quads are one definition's facts as quads: its kind, package, file, line and hash, its gloss, every capability it reaches, every word it calls, and every test that names it.

    size(row_quads({"word" => "a::x", "kind" => "function", "package" => "a", "file" => "a.b", "line" => 1, "def_hash" => "b3:0", "gloss" => nil, "reach" => ["network"], "calls" => [], "tests" => []}, nil)) #=> 6
"""
def row_quads(row, g)
  d = node("def", row["word"])
  base = [
    fact(d, iri(RDF_TYPE), node("class", capitalize(row["kind"])), g),
    fact(d, prop("package"), node("package", row["package"]), g),
    fact(d, prop("file"), literal(row["file"]), g),
    fact(d, prop("line"), typed(to_s(row["line"]), XSD_INTEGER), g),
    fact(d, prop("defHash"), literal(row["def_hash"]), g)
  ]
  glossed = if row["gloss"].nil?
    base
  else
    push(base, fact(d, prop("gloss"), literal(row["gloss"]), g))
  end
  append(
    append(
      append(
        glossed,
        map(
          (c) -> fact(d, prop("reaches"), node("capability", c), g),
          row["reach"] or []
        )
      ),
      map((w) -> fact(d, prop("calls"), node("def", w), g), row["calls"] or [])
    ),
    flat_map(row["tests"] or [], (t) -> test_quads(t, d, g))
  )
end

@doc """
rule_quads are one check rule's facts: it is a rule, its slug, severity and law.

    size(rule_quads({"code" => "B0070", "slug" => "reuse", "severity" => "warning", "law" => "use the word"}, nil)) #=> 4
"""
def rule_quads(rule, g)
  r = node("rule", rule["code"])
  [
    fact(r, iri(RDF_TYPE), node("class", "Rule"), g),
    fact(r, prop("slug"), literal(rule["slug"]), g),
    fact(r, prop("severity"), literal(rule["severity"]), g),
    fact(r, prop("law"), literal(rule["law"]), g)
  ]
end

@doc """
blue_quads: blue's definitions, tests, docs and rules as quads in the graph of the snapshot root. A test that names several words says it is a test once per word; the store holds each statement once.

    blue_quads([], [], "b3:00") #=> []
"""
def blue_quads(rows, rules, root)
  g = node("snapshot", root)
  append(
    flat_map(rows, (r) -> row_quads(r, g)),
    flat_map(rules, (r) -> rule_quads(r, g))
  )
end

@doc """
untested_question asks which definitions reach `capability` and are named by no test or doc example.

    untested_question("network")[:vars] #=> ["d"]
"""
def untested_question(capability)
  question(
    ["d"],
    [pattern(var("d"), prop("reaches"), node("capability", capability))],
    [[pattern(var("t"), prop("exercises"), var("d"))]],
    {}
  )
end

@doc """
question_named is the khipu question a name stands for, or nil: `untested-CAPABILITY` is untested_question.

    question_named("untested-network")[:vars] #=> ["d"]
"""
def question_named(name)
  if starts_with?(name, "untested-")
    untested_question(drop_chars(name, 9))
  end
end

@doc """
word_of is the word a definition IRI names.

    word_of(node("def", "a::<=>")) #=> "a::<=>"
"""
def word_of(t)
  decoded(drop_chars(t[:value], size(chars("#{BLUE_IRI}def:"))))
end

@doc """
find_docs are the documents `find` indexes, one per word: its name with underscores as spaces, its package and its gloss.

    find_docs([{"word" => "retsu::running_sum", "name" => "running_sum", "package" => "retsu", "gloss" => "totals"}]) #=> [["retsu::running_sum", "running sum retsu totals"]]
"""
def find_docs(rows)
  map(
    fn(r)
      [
        r["word"],
        "#{replace(r["name"], "_", " ")} #{r["package"]} #{r["gloss"] or ""}"
      ]
    end,
    first_rows(rows)
  )
end

@doc """
first_rows keeps the first row of each word.

    size(first_rows([{"word" => "a"}, {"word" => "a"}])) #=> 1
"""
def first_rows(rows)
  map((e) -> first(e[1]), map_entries(blue::group_by(rows, (r) -> r["word"])))
end

@doc """
row_brief is a row as an answer names it: word, id, gloss, file and line.

    row_brief({"word" => "a::x", "id" => "i", "gloss" => nil, "file" => "a.b", "line" => 2})["line"] #=> 2
"""
def row_brief(r)
  {
    "word" => r["word"],
    "id" => r["id"],
    "gloss" => r["gloss"],
    "file" => r["file"],
    "line" => r["line"]
  }
end

@doc """
by_word is the first row of each word, by word.

    by_word([{"word" => "a"}])["a"] #=> {"word" => "a"}
"""
def by_word(rows)
  reduce((m, r) -> assoc(m, r["word"], r), {}, reverse(rows))
end

@doc """
find_answer: The words whose name, package or gloss match `text`, ranked by BM25 (sakuin), at most `limit`.

    find_answer("x", 5, [])["hits"] #=> []
"""
def find_answer(text, limit, rows)
  index = invert(find_docs(rows), {})
  words = by_word(rows)
  {
    "query" => text,
    "hits" => map(
      fn(h)
        assoc(
          row_brief(get(words, h[:id])),
          "score",
          round(h[:score] * 1000) / 1000.0
        )
      end,
      score(index, [text], {limit:})
    )
  }
end

@doc """
resolve_word is the word a readable id or a word names, or nil.

    resolve_word("blue:blue:a::x@0123", [{"word" => "a::x", "id" => "blue:blue:a::x@0123"}]) #=> "a::x"
"""
def resolve_word(target, rows)
  found = retsu::find_first(
    (r) -> r["word"] == target or r["id"] == target,
    rows
  )
  if found != nil
    found["word"]
  end
end

@doc """
get_answer: Every row of a word (by word or readable id); none when nothing has that name.

    get_answer("a::x", [{"word" => "a::x", "id" => "i"}])["rows"] #=> [{"word" => "a::x", "id" => "i"}]
"""
def get_answer(target, rows)
  w = resolve_word(target, rows)
  {
    "query" => target,
    "word" => w,
    "rows" => filter((r) -> r["word"] == w, rows)
  }
end

@doc """
uses_answer: The definitions that call a word (by word or readable id), each once.

    uses_answer("a::x", [{"word" => "a::y", "id" => "j", "gloss" => nil, "file" => "a.b", "line" => 1, "calls" => ["a::x"]}])["callers"][0]["word"] #=> "a::y"
"""
def uses_answer(target, rows)
  w = resolve_word(target, rows) or target
  {
    "query" => target,
    "word" => w,
    "callers" => map(
      row_brief,
      first_rows(filter((r) -> member?(w, r["calls"] or []), rows))
    )
  }
end

@doc """
groups_answer: The functions of `min` nodes or more that share one computed shape across two or more words (T2, B0070's own question across the whole tree), largest group first.

    groups_answer(12, [])["groups"] #=> []
"""
def groups_answer(min, rows)
  eligible = filter(
    fn(r)
      r["kind"] == "function" and r["shape"] != nil and (r["size"] or 0) >= min
    end,
    first_rows(rows)
  )
  groups = filter(
    (g) -> size(g["words"]) > 1,
    map(
      fn(e)
        {
          "shape" => e[0],
          "size" => first(e[1])["size"],
          "words" => map((r) -> r["word"], e[1])
        }
      end,
      map_entries(blue::group_by(eligible, (r) -> r["shape"]))
    )
  )
  {"min" => min, "groups" => sort_keyed((g) -> -size(g["words"]), groups)}
end

@doc """
changed_answer: How a package's words moved between two sets of facts: words added, words removed, and words whose definition hash moved, each saying whether its code moved or only its doc or names.

    changed_answer("a", [], [{"word" => "a::x", "package" => "a"}])["added"] #=> ["a::x"]
"""
def changed_answer(package, old_rows, new_rows)
  olds = by_word(filter((r) -> r["package"] == package, old_rows))
  news = by_word(filter((r) -> r["package"] == package, new_rows))
  both = filter((e) -> get(olds, e[0]) != nil, map_entries(news))
  moved = filter((e) -> get(olds, e[0])["def_hash"] != e[1]["def_hash"], both)
  {
    "package" => package,
    "added" => map(
      first,
      filter((e) -> get(olds, e[0]).nil?, map_entries(news))
    ),
    "removed" => map(
      first,
      filter((e) -> get(news, e[0]).nil?, map_entries(olds))
    ),
    "moved" => map(
      fn(e)
        {"word" => e[0], "code" => get(olds, e[0])["shape"] != e[1]["shape"]}
      end,
      moved
    )
  }
end

@doc """
ask_answer: The words a named khipu question answers over blue's quads, which it writes to the store at `store` and asks through DuckDB. An unknown name is refused.

    raised(() -> ask_answer("nope", "/x", [], [], "b3:00")) #=> :arika_question
"""
def ask_answer(name, store, rows, rules, root)
  q = question_named(name)
  if q.nil?
    raise(
      :arika_question,
      "no question named #{name}; the questions are untested-CAPABILITY (network, filesystem, process, ...)"
    )
  end
  s = khipu::load(store, blue_quads(rows, rules, root))
  {
    "question" => name,
    "quads" => s[:quads],
    "answers" => map((a) -> word_of(a["d"]), khipu::ask(s, q))
  }
end

@doc """
golden_answer: Each golden question asked through `find`, and the ones whose expected word is no longer the top hit (G5): `[intent, word]` pairs in, `{asked, lost}` out.

    golden_answer([["running", "a::running_sum"]], [fixture_row("a", "running_sum", [], [], [])])["lost"] #=> []
"""
def golden_answer(questions, rows)
  index = invert(find_docs(rows), {})
  tops = map(
    (q) -> [q[0], q[1], (first(score(index, [q[0]], {limit: 1})) or {})[:id]],
    questions
  )
  {
    "asked" => size(questions),
    "lost" => map(
      (t) -> {"intent" => t[0], "want" => t[1], "found" => t[2]},
      filter((t) -> t[1] != t[2], tops)
    )
  }
end

@doc """
TOOLS is the arika service's schema in blue: each tool's name, the verb it answers with, what it answers, and its arguments. The MCP tool list (`blue arika tools`, docs/arika-tools.json) is rendered from it and nothing else.

    size(TOOLS) #=> 6
"""
TOOLS = [
  {
    name: "blue_word_find",
    verb: "find",
    about: "Blue words whose name, package or doc gloss match an intent, ranked by BM25",
    args: [
      {
        name: "text",
        type: "string",
        required: true,
        about: "the intent, in words"
      },
      {
        name: "limit",
        type: "integer",
        required: false,
        about: "at most this many hits (default 12)"
      }
    ]
  },
  {
    name: "blue_word_get",
    verb: "get",
    about: "Every fact of one blue word: id, hashes, shape, gloss, file, line, calls, reach, tests",
    args: [
      {
        name: "word",
        type: "string",
        required: true,
        about: "pkg::name or a readable id"
      }
    ]
  },
  {
    name: "blue_word_uses",
    verb: "uses",
    about: "The blue definitions that call a word",
    args: [
      {
        name: "word",
        type: "string",
        required: true,
        about: "pkg::name or a readable id"
      }
    ]
  },
  {
    name: "blue_word_groups",
    verb: "groups",
    about: "Functions that share one computed shape across words: copies a word could replace",
    args: [
      {
        name: "min",
        type: "integer",
        required: false,
        about: "the smallest size in nodes (default 12)"
      }
    ]
  },
  {
    name: "blue_word_changes",
    verb: "changed",
    about: "How a package's words moved since an older facts file: added, removed, code or doc moved",
    args: [
      {
        name: "package",
        type: "string",
        required: true,
        about: "the package path"
      },
      {
        name: "since",
        type: "string",
        required: true,
        about: "the older facts.jsonl, on the server"
      }
    ]
  },
  {
    name: "blue_word_ask",
    verb: "ask",
    about: "A named question over blue's knowledge graph: untested-CAPABILITY is the definitions that reach the capability and that no test names",
    args: [
      {
        name: "question",
        type: "string",
        required: true,
        about: "untested-network, untested-filesystem, ..."
      }
    ]
  }
]

@doc """
tool_schema is a tool's arguments as a JSON Schema object.

    tool_schema(TOOLS[2])["required"] #=> ["word"]
"""
def tool_schema(t)
  {
    "type" => "object",
    "properties" => reduce(
      fn(m, a)
        assoc(m, a[:name], {"type" => a[:type], "description" => a[:about]})
      end,
      {},
      t[:args]
    ),
    "required" => map((a) -> a[:name], filter((a) -> a[:required], t[:args])),
    "additionalProperties" => false
  }
end

@doc """
tool_list is the MCP tool list rendered from TOOLS.

    first(tool_list)["name"] #=> "blue_word_find"
"""
def tool_list()
  map((t) -> mcp_tool(t[:name], t[:about], tool_schema(t)), TOOLS)
end

@doc """
tool_call answers one tool call from the facts, through the verb its TOOLS row names.

    tool_call("blue_word_groups", {}, {"rows" => [], "rules" => [], "root" => "b3:00"})["groups"] #=> []
"""
def tool_call(name, args, ctx)
  t = retsu::find_first((x) -> x[:name] == name, TOOLS)
  verb_answer(t[:verb], args, ctx)
end

@doc """
verb_answer is one fact verb's answer, its arguments read as the CLI and the tools both give them.

    verb_answer("groups", {}, {"rows" => [], "rules" => [], "root" => "b3:00"})["min"] #=> 12
"""
def verb_answer(verb, q, ctx)
  rows = ctx["rows"]
  out = if verb == "find"
    find_answer(q["text"], q["limit"] or LIMIT, rows)
  elsif verb == "get"
    get_answer(q["word"], rows)
  elsif verb == "uses"
    uses_answer(q["word"], rows)
  elsif verb == "groups"
    groups_answer(q["min"] or MIN_GROUP, rows)
  elsif verb == "changed"
    changed_answer(q["package"], facts_rows(q["since"]), rows)
  elsif verb == "golden"
    golden_answer(q["questions"], rows)
  else
    ask_answer(q["question"], ctx["store"], rows, ctx["rules"], ctx["root"])
  end
  assoc(out, "snapshot_root", ctx["root"])
end

@doc """
facts_rows reads a facts file: one JSON row per line.

    facts_rows(nil) #=> []
"""
def facts_rows(path)
  if path.nil?
    []
  else
    map(json_read, filter((l) -> l != "", split(read_file(path), line_break)))
  end
end

@doc """
arika_server is the MCP server over one set of facts: TOOLS, answered by tool_call.

    arika_server({"rows" => [], "rules" => [], "root" => "b3:00"})[:name] #=> "arika"
"""
def arika_server(ctx)
  mcp_server(
    "arika",
    "0.1.0",
    tool_list,
    (name, args) -> tool_call(name, args, ctx)
  )
end

@doc """
fresh_root is the root the facts hash to, or the refusal when the header names another: nil header means the facts were built in this process.

    fresh_root({"root" => nil, "rows" => []})[:root] #=> "b3:#{ct_root([])}"
"""
def fresh_root(check)
  root = "b3:#{snapshot_root_of(units_of(check["rows"]))}"
  if check["root"].nil? or check["root"] == root
    {root:}
  else
    {why: stale(check), root: check["root"]}
  end
end

@doc """
fact_lines is a fact verb's answer as text.

    fact_lines("groups", {"groups" => []}) #=> ["arika: no shape is shared by two words"]
"""
def fact_lines(verb, a)
  if verb == "find"
    lines_or(
      map(
        fn(h)
          "#{h["word"]}  #{h["gloss"] or ""}  (#{h["file"]}:#{to_s(h["line"])})"
        end,
        a["hits"]
      ),
      "arika: no word matches `#{a["query"]}`"
    )
  elsif verb == "get"
    lines_or(map(json_stringify, a["rows"]), "arika: no word `#{a["query"]}`")
  elsif verb == "uses"
    lines_or(
      map(
        (c) -> "#{c["word"]}  (#{c["file"]}:#{to_s(c["line"])})",
        a["callers"]
      ),
      "arika: nothing calls #{a["word"]}"
    )
  elsif verb == "groups"
    lines_or(
      map(
        (g) -> "#{to_s(g["size"])} nodes: #{join(g["words"], ", ")}",
        a["groups"]
      ),
      "arika: no shape is shared by two words"
    )
  elsif verb == "golden"
    lines_or(
      map(
        fn(l)
          "lost     #{l["intent"]}: #{l["want"]}, found #{to_s(l["found"])}"
        end,
        a["lost"]
      ),
      "arika: #{to_s(a["asked"])} golden questions keep their top hit"
    )
  elsif verb == "changed"
    append(
      append(
        map((w) -> "added    #{w}", a["added"]),
        map((w) -> "removed  #{w}", a["removed"])
      ),
      map(
        fn(m)
          "moved    #{m["word"]} (#{if m["code"]
  "code"
else
  "doc or names only"
end})"
        end,
        a["moved"]
      )
    )
  else
    lines_or(a["answers"], "arika: no definition answers #{a["question"]}")
  end
end

@doc """
lines_or is the lines, or the one line saying there are none.

    lines_or([], "none") #=> ["none"]
"""
def lines_or(lines, none)
  if is_empty(lines)
    [none]
  else
    lines
  end
end

@doc """
over_facts answers a fact verb: refused as blind when the facts are stale; `quads` writes N-Quads, `mcp` answers one JSON-RPC request, `serve` serves the tools over Streamable HTTP; the rest print their answer as text or JSON.

    over_facts("groups", "--json", {}, {"root" => nil, "rows" => []}) #=> true
"""
def over_facts(verb, mode, q, check)
  fresh = fresh_root(check)
  if fresh[:why] != nil
    refuse(mode, q, fresh[:why])
  else
    ctx = {
      "rows" => check["rows"],
      "rules" => q["rules"] or [],
      "root" => fresh[:root],
      "store" => q["store"]
    }
    if verb == "quads"
      lines = map(
        (x) -> khipu::write_quad(x, ""),
        blue_quads(ctx["rows"], ctx["rules"], ctx["root"])
      )
      write_file(q["out"], unlines(distinct(lines)))
      write_stdout(unlines(["arika: wrote #{q["out"]}"]))
    elsif verb == "mcp"
      out = mcp_answer(arika_server(ctx), q["request"])
      if out != nil
        write_stdout(unlines([json_stringify(out)]))
      end
    elsif verb == "serve"
      serve(q["addr"], "/healthz", mcp_handler(arika_server(ctx)))
    else
      a = verb_answer(verb, q, ctx)
      if mode == "--json"
        write_stdout(unlines([json_stringify(a)]))
      else
        write_stdout(unlines(fact_lines(verb, a)))
      end
    end
  end
  true
end

def hit(tier, fix)
  {
    "word" => "retsu::running_sum",
    "package" => "retsu",
    "name" => "running_sum",
    "foundation" => fix == "import",
    "fix" => fix,
    "tier" => tier,
    "id" => "blue:blue:retsu::running_sum@0123456789ab"
  }
end

def found(hits)
  {
    "outcome" => "found",
    "file" => "a.b",
    "defs" => [{"name" => "totals", "line" => 3, "hits" => hits}]
  }
end

test "a found copy names the word, its id and the import line"
  l = first(like_text(found([hit("T1", "import")])))
  assert contains?(l, "a.b:3: def totals is the code of retsu::running_sum")
  assert contains?(l, "T1, blue:blue:retsu::running_sum@0123456789ab")
  assert contains?(l, "use(\"retsu\", [:running_sum])")
end

test "each tier reads as what it proves"
  assert contains?(
    first(like_text(found([hit("T0", "import")]))),
    "an exact copy of"
  )
  assert contains?(
    first(like_text(found([hit("T2", "import")]))),
    "through a wrapper"
  )
end

test "a domain word says move down"
  assert contains?(
    first(like_text(found([hit("T1", "move_down")]))),
    "move the shape down"
  )
end

test "the hook is silent unless a word is found, and never claims to block"
  assert like_hook({"outcome" => "empty", "defs" => []}) == []
  assert like_hook({"outcome" => "blind", "why" => "x"}) == []
  out = like_hook(found([hit("T1", "import")]))
  assert size(out) == 2
  assert retsu::last(out) == "arika: this is advice; nothing is blocked"
end

test "blind is said, never read as empty"
  l = first(
    like_text({"outcome" => "blind", "file" => "a.b", "why" => "no parse"})
  )
  assert contains?(l, "blind")
end

test "a catalogue row reads as its word and gloss; a package row is no word"
  row = "| `retsu::running_sum(xs)` |  |  |  | running_sum: Running totals |"
  assert catalog_row(row) ==
    {"word" => "retsu::running_sum", "gloss" => "running_sum: Running totals"}
  assert catalog_row("| [`retsu`](#retsu) | 0.1.0 | — | 1 | 2 | lists |").nil?
  assert catalog_row("# Bidama catalogue").nil?
end

test "a word is found by name, old spelling, part and gloss, in that order"
  facts = {
    "query" => "sum",
    "words" => [
      {"word" => "kazu::sum", "foundation" => true},
      {"word" => "retsu::running_sum", "foundation" => true},
      {"word" => "ran::roll", "foundation" => false}
    ],
    "moves" => [
      {"old" => "angou::sum", "word" => "kazu::sum", "since" => "0.1.1"}
    ],
    "catalog" => "CATALOG.md",
    "blind" => []
  }
  rows = [{"word" => "ran::roll", "gloss" => "roll: the sum of dice"}]
  m = word_matches(facts, rows)
  assert map((w) -> w["word"], m["names"]) == ["kazu::sum"]
  assert map((o) -> o["word"], m["old"]) == ["kazu::sum"]
  assert map((w) -> w["word"], m["parts"]) == ["retsu::running_sum"]
  assert map((r) -> r["word"], m["glosses"]) == ["ran::roll"]
  out = word_text(m)
  assert first(out) == "T5 name    kazu::sum (foundation)"
end

test "facts that hash to the header's root pass; one changed fact is refused"
  rows = [
    {"package" => "a", "word" => "a::x", "gloss" => "x"},
    {"package" => "b", "word" => "b::y", "gloss" => "y"}
  ]
  root = "b3:#{snapshot_root_of(units_of(rows))}"
  assert stale({"root" => root, "rows" => rows}).nil?
  edited = [rows[0], {"package" => "b", "word" => "b::y", "gloss" => "z"}]
  assert contains?(stale({"root" => root, "rows" => edited}), "stale")
end

test "no catalogue makes the gloss tier blind, not empty"
  facts = {
    "query" => "zzz",
    "words" => [],
    "moves" => [],
    "catalog" => nil,
    "blind" => []
  }
  out = word_text(word_matches(facts, []))
  assert contains?(retsu::last(out), "glosses blind")
end

@doc """
fixture_row is a facts row for the tests: a function of `package`, with its reach, calls and tests.

    fixture_row("a", "x", [], [], [])["word"] #=> "a::x"
"""
def fixture_row(package, name, reach, calls, tests)
  {
    "word" => "#{package}::#{name}",
    "id" => "blue:blue:#{package}::#{name}@000000000000",
    "package" => package,
    "name" => name,
    "kind" => "function",
    "def_hash" => "b3:#{name}",
    "shape" => "b3:shape-#{name}",
    "size" => 20,
    "file" => "#{package}/#{package}.b",
    "line" => 1,
    "gloss" => "#{name}: a fixture word",
    "reach" => reach,
    "calls" => calls,
    "tests" => tests,
    "legacy" => []
  }
end

@doc """
a_test is a test block entry of a facts row, for the tests.

    a_test("t")["doc"] #=> false
"""
def a_test(name)
  {"file" => "a/a.b", "line" => 9, "name" => name, "doc" => false}
end

test "a definition that reaches the network with no test is answered; a test removes it"
  store = path_join(getenv("TMPDIR", "/tmp"), "arika-test-untested.jsonl")
  rows = [
    fixture_row("a", "fetch", ["network"], [], []),
    fixture_row("a", "post", ["network"], [], [a_test("posts")]),
    fixture_row("a", "pure", [], [], []),
    fixture_row("a", "wrap", ["network"], ["a::fetch"], [])
  ]
  answer = ask_answer("untested-network", store, rows, [], "b3:00")
  assert answer["answers"] == %w[a::fetch a::wrap]
  tested = [
    fixture_row("a", "fetch", ["network"], [], [a_test("fetches")]),
    rows[1],
    rows[2],
    rows[3]
  ]
  assert get(
    ask_answer("untested-network", store, tested, [], "b3:00"),
    "answers"
  ) == ["a::wrap"]
end

test "rules and doc examples are quads, and every quad is in the snapshot's graph"
  rule = {
    "code" => "B0070",
    "slug" => "reuse",
    "severity" => "warning",
    "law" => "x"
  }
  doc = {
    "file" => "a/a.b",
    "line" => 2,
    "name" => "@doc fetch example 1",
    "doc" => true
  }
  qs = blue_quads([fixture_row("a", "fetch", [], [], [doc])], [rule], "b3:00")
  assert every?((q) -> q[:g] == node("snapshot", "b3:00"), qs)
  assert member?(node("class", "DocExample"), map((q) -> q[:o], qs))
  assert member?(node("rule", "B0070"), map((q) -> q[:s], qs))
end

test "find ranks a word by its gloss and name; groups and changes read the rows"
  rows = [
    fixture_row("a", "running_sum", [], [], []),
    fixture_row("b", "fetch", [], [], [])
  ]
  assert first(find_answer("running", 3, rows)["hits"])["word"] ==
    "a::running_sum"
  same = [
    rows[0],
    assoc(
      fixture_row("b", "totals", [], [], []),
      "shape",
      "b3:shape-running_sum"
    )
  ]
  assert first(groups_answer(12, same)["groups"])["words"] ==
    %w[a::running_sum b::totals]
  assert groups_answer(30, same)["groups"] == []
  newer = [
    assoc(rows[1], "def_hash", "b3:other"),
    fixture_row("b", "new", [], [], [])
  ]
  c = changed_answer("b", rows, newer)
  assert c["added"] == ["b::new"]
  assert c["moved"] == [{"word" => "b::fetch", "code" => false}]
  assert get(
    nth(
      0,
      get(
        uses_answer(
          "a::fetch",
          [fixture_row("a", "wrap", [], ["a::fetch"], [])]
        ),
        "callers"
      )
    ),
    "word"
  ) == "a::wrap"
end

test "the MCP tools are rendered from TOOLS and answered by their verbs"
  names = map((t) -> t["name"], tool_list)
  assert names == map((t) -> t[:name], TOOLS)
  ctx = {
    "rows" => [fixture_row("a", "running_sum", [], [], [])],
    "rules" => [],
    "root" => "b3:00"
  }
  call = {
    "jsonrpc" => "2.0",
    "id" => 1,
    "method" => "tools/call",
    "params" => {
      "name" => "blue_word_find",
      "arguments" => {"text" => "running"}
    }
  }
  out = mcp_answer(arika_server(ctx), call)
  assert first(out["result"]["structuredContent"]["hits"])["word"] ==
    "a::running_sum"
end
