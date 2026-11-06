use("retsu", %i[first flat_map is_empty size])

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
  if facts["catalog"].nil?
    []
  else
    catalog_rows(read_file(facts["catalog"]))
  end
end

def main()
  if size(argv) < 3
    true
  else
    answer(argv[0], argv[1], json_read(argv[2]))
  end
end

def answer(verb, mode, facts)
  if verb == "like" and mode == "--json"
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
    raise(:usage, "usage: blue arika like FILE[:LINE] | blue arika word NAME")
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
