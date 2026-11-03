use("hadome", %i[failures judge measurement orphans parse render shrunk])
use("kyohi", [:why])
use("retsu", %i[first flat_map is_empty size])
use("shisutemu", [:read_or])

KIND = "reuse-copy"

REPORT = "--report"

def flag_value(args, flag)
  at = filter((i) -> args[i] == flag, range(size(args)))
  if is_empty(at) or first(at) + 1 >= size(args)
    nil
  else
    args[first(at) + 1]
  end
end

def homed(facts)
  map(
    (f) -> assoc(assoc(f, "copy_of", f["home"]), "fix", f["fix"]),
    filter((f) -> f["home"] != nil and not f["waived"], facts)
  )
end

def twin_groups(facts)
  free = filter((f) -> f["home"].nil? and not f["word"], facts)
  groups = map_entries(group_by(free, (f) -> f["shape"]))
  filter((g) -> size(distinct(map((f) -> f["scope"], g[1]))) > 1, groups)
end

def label(f)
  "#{f["scope"]}::#{f["name"]}"
end

def twins(facts)
  flat_map(
    twin_groups(facts),
    fn(g)
      names = join(map(label, take(3, g[1])), ", ")
      map(
        fn(f)
          assoc(assoc(f, "copy_of", "no home yet: #{names}"), "fix", "promote")
        end,
        g[1]
      )
    end
  )
end

def copies(facts)
  sort_keyed(
    (c) -> "#{c["scope"]}/#{c["file"]}/#{c["name"]}",
    append(homed(facts), twins(facts))
  )
end

def measures(cs)
  map(
    (e) -> measurement(e[0], size(e[1])),
    map_entries(group_by(cs, (c) -> c["scope"]))
  )
end

def finding_line(c)
  "  #{c["file"]}:#{to_s(c["line"])} def #{c["name"]} [#{c["fix"]}] is #{c["copy_of"]}"
end

def row_state(rows, m)
  j = judge(rows, KIND, m[:key], m[:size])
  {
    scope: m[:key],
    measured: m[:size],
    verdict: j[:verdict],
    recorded: j[:recorded]
  }
end

def in_scopes(cs, scopes)
  filter((c) -> member?(c["scope"], scopes), cs)
end

def header(report, cs)
  waived = size(filter((f) -> f["waived"], report["facts"]))
  "reuse: #{to_s(report["files"])} file(s), #{to_s(report["definitions"])} definition(s), #{to_s(size(cs))} copies, #{to_s(waived)} waived, #{to_s(size(report["blind"]))} blind"
end

def blind_lines(report)
  map((b) -> "blind: #{b["file"]}: #{b["why"]}", report["blind"])
end

def keep_comments(text)
  filter((l) -> starts_with?(l, "#"), split(text, line_break))
end

def recorded_text(old, receipt, ms)
  notes = append(
    keep_comments(old),
    if receipt.nil?
      []
    else
      ["# receipt: #{receipt}"]
    end
  )
  rows = render(KIND, ms)
  if is_empty(notes)
    rows
  else
    "#{unlines(notes)}#{rows}"
  end
end

def record(path, root, ms, receipt)
  old = read_or(path, "")
  rows = parse(old)
  raises = failures(rows, KIND, ms)
  if size(raises) > 0 and receipt.nil?
    write_stdout(
      unlines(
        append(
          map(why, raises),
          [
            "blue census: a raised or new row needs a reason: blue census --reuse #{root} --record --receipt \"<why>\""
          ]
        )
      )
    )
    false
  else
    write_file(path, recorded_text(old, receipt, ms))
    write_stdout(unlines(["recorded #{to_s(size(ms))} row(s) to #{path}"]))
    true
  end
end

def check(path, root, cs, ms, report, every)
  write_stdout(unlines(append([header(report, cs)], blind_lines(report))))
  if every
    write_stdout(unlines(map(finding_line, cs)))
  end
  text = read_or(path, nil)
  if text.nil?
    write_stdout(
      unlines(
        [
          "advisory: #{path} is absent, so nothing is enforced. Adopt it: blue census --reuse #{root} --record --receipt \"first measure\""
        ]
      )
    )
    true
  else
    judge_rows(parse(text), path, root, cs, ms, every)
  end
end

def judge_rows(rows, path, root, cs, ms, every)
  bad = failures(rows, KIND, ms)
  low = shrunk(rows, KIND, ms)
  gone = orphans(rows, KIND, map((m) -> m[:key], ms))
  states = map((m) -> row_state(rows, m), ms)
  broken = filter((s) -> s[:verdict] != :held, states)
  write_stdout(
    unlines(
      [
        "ratchet #{KIND}: #{to_s(size(ms))} scope(s), #{to_s(size(bad))} grew or new, #{to_s(size(low))} shrunk, #{to_s(size(gone))} gone"
      ]
    )
  )
  if size(low) + size(gone) > 0
    write_stdout(unlines(["bank it: blue census --reuse #{root} --record"]))
  end
  if size(bad) > 0
    write_stdout(unlines(map(why, bad)))
    if not every
      scopes = map((s) -> s[:scope], broken)
      write_stdout(unlines(map(finding_line, in_scopes(cs, scopes))))
    end
    write_stdout(
      unlines(
        [
          "fix: use the word, move the shape down, or promote it; an exception is `# waive B0070: <reason>`; a raise is blue census --reuse #{root} --record --receipt \"<why>\" against #{path}"
        ]
      )
    )
    false
  else
    true
  end
end

def json_row(s)
  {
    scope: s[:scope],
    measured: s[:measured],
    recorded: s[:recorded],
    verdict: to_s(s[:verdict])
  }
end

def as_json(path, cs, ms, report)
  text = read_or(path, nil)
  rows = parse(text or "")
  states = map((m) -> row_state(rows, m), ms)
  adopted = text != nil
  broken = if adopted
    map(json_row, filter((s) -> s[:verdict] != :held, states))
  else
    []
  end
  write_stdout(
    unlines(
      [
        json_stringify(
          {
            adopted:,
            baseline: path,
            files: report["files"],
            definitions: report["definitions"],
            copies: size(cs),
            waived: size(filter((f) -> f["waived"], report["facts"])),
            blind: report["blind"],
            broken:,
            shrunk: size(shrunk(rows, KIND, ms)),
            gone: size(orphans(rows, KIND, map((m) -> m[:key], ms))),
            findings: map(
              fn(c)
                {
                  scope: c["scope"],
                  file: c["file"],
                  line: c["line"],
                  name: c["name"],
                  fix: c["fix"],
                  home: c["copy_of"]
                }
              end,
              cs
            )
          }
        )
      ]
    )
  )
  size(broken) == 0
end

def main(args)
  if first(args) != REPORT
    true
  else
    report = json_read(args[1])
    root = args[2]
    path = args[3]
    flags = drop(4, args)
    cs = copies(report["facts"])
    ms = measures(cs)
    if member?("--record", flags)
      record(path, root, ms, flag_value(flags, "--receipt"))
    elsif member?("--json", flags)
      as_json(path, cs, ms, report)
    else
      check(path, root, cs, ms, report, member?("--findings", flags))
    end
  end
end

def fact(scope, name, shape)
  {
    "scope" => scope,
    "file" => "#{scope}.b",
    "line" => 1,
    "name" => name,
    "shape" => shape,
    "home" => nil,
    "fix" => nil,
    "word" => false,
    "waived" => false
  }
end

test "no facts is no copy and no row"
  assert copies([]) == []
  assert measures([]) == []
end

test "one shape in one scope is no copy"
  assert copies([fact("a", "x", "h"), fact("a", "y", "h")]) == []
end

test "one shape across two scopes is a copy in each, with no home yet"
  cs = copies([fact("a", "x", "h"), fact("b", "y", "h"), fact("b", "z", "k")])
  assert map((c) -> c["name"], cs) == %w[x y]
  assert first(cs)["fix"] == "promote"
  assert contains?(first(cs)["copy_of"], "a::x, b::y")
  assert map((m) -> [m[:key], m[:size]], measures(cs)) == [["a", 1], ["b", 1]]
end

test "a catalogue word is no twin, and its copy names it and is counted alone"
  word = assoc(fact("kazu", "sum", "h"), "word", true)
  copy = assoc(
    assoc(fact("a", "tally", "h"), "home", "kazu::sum"),
    "fix",
    "import"
  )
  cs = copies([word, copy])
  assert map((c) -> c["name"], cs) == ["tally"]
  assert first(cs)["copy_of"] == "kazu::sum"
end

test "a waived copy is no copy"
  copy = assoc(fact("a", "tally", "h"), "home", "kazu::sum")
  assert copies([assoc(copy, "waived", true)]) == []
end

test "a record keeps every note and adds the receipt"
  old = unlines(["# receipt: first", "reuse-copy: a 2"])
  text = recorded_text(old, "second", [measurement("a", 1)])
  assert text ==
    unlines(["# receipt: first", "# receipt: second", "reuse-copy: a 1"])
  assert recorded_text("", nil, [measurement("a", 1)]) ==
    unlines(["reuse-copy: a 1"])
end

main(argv)
