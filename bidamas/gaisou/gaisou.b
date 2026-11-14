@moduledoc """
gaisou (外挿) — obligation extrapolation: relations between obligations, and candidate obligations, mined from evidence.

Each source is a list of sites, and each site the codes it owes. Pairs of codes that are owed together, never together, or one only where the other is, become edges; the history of the registry's debt gives the changes that paid one code and raised another. Every edge carries its counts and its denominator, and its tier is the number of independent sources that show it. The registry decides each edge (ratified, rejected, off); an edge it has not decided is a candidate. docs/OBLIGATION-GRAPH.md.

    pair_key("B0002", "B0001") #=> "B0001|B0002"
"""

use("jisho", [:tally])

use(
  "moji",
  %i[
    after_first
    before_first
    lines
    sorts_before
    starts_with
    strip_prefix
    strip_suffix
    trim
    words
  ]
)

use("retsu", %i[first flat_map is_empty last rest size take_n])
use("settei")

@doc """
settings: gaisou's core model: the thresholds an edge must meet and the kinds discovery leaves unmined.

    settei::defaults_of(settings)[:min_support] #=> 3
"""
def settings()
  {
    min_support: settei::knob(
      3,
      {
        min: 1,
        doc: "the fewest sites (or changes) an edge needs before it is proposed"
      }
    ),
    min_confidence: settei::knob(
      90,
      {
        min: 1,
        max: 100,
        unit: "percent",
        doc: "implies: the share of b's sites that also owe a"
      }
    ),
    min_lift: settei::knob(
      300,
      {
        min: 100,
        unit: "percent",
        doc: "co-occurs: the sites owing both, over what chance expects"
      }
    ),
    min_expected: settei::knob(
      2,
      {
        min: 1,
        doc: "exclusive: the co-occurrences chance must expect before a zero is evidence"
      }
    ),
    min_sources: settei::knob(
      2,
      {min: 1, doc: "the independent sources an edge needs to be corroborated"}
    ),
    min_waivers: settei::knob(
      5,
      {
        min: 2,
        doc: "the waivers of one code with one reason before the reason is a candidate obligation"
      }
    ),
    off: settei::knob(
      "",
      {
        doc: "relation kinds discovery leaves unmined, comma separated: implies, co-occurs, exclusive, trades, fixed-together"
      }
    )
  }
end

@doc """
pair_key: the key of an unordered pair of codes, the lesser first.

    pair_key("B0090", "B0056") #=> "B0056|B0090"
"""
def pair_key(a, b)
  if sorts_before(a, b)
    "#{a}|#{b}"
  else
    "#{b}|#{a}"
  end
end

@doc """
groups: the distinct codes each site owes, from [site, code] pairs, one sorted list per site, in site order.

    groups([["f:1", "B2"], ["f:1", "B1"], ["f:2", "B1"]]) #=> [["B1", "B2"], ["B1"]]
"""
def groups(pairs)
  by = reduce(
    (acc, p) -> assoc(acc, p[0], append(get(acc, p[0]) or [], [p[1]])),
    {},
    pairs
  )
  map(
    (k) -> sort_keyed((c) -> c, distinct(get(by, k))),
    sort_keyed((k) -> k, distinct(map(first, pairs)))
  )
end

@doc """
counts: from one source's sites, how many owe each code and each pair of codes, and the denominator.

    counts([["B1", "B2"], ["B1"]], 10)[:single]["B1"] #=> 2
"""
def counts(owed, n)
  {
    single: tally(flat_map(owed, (g) -> g)),
    pair: tally(
      flat_map(
        owed,
        fn(g)
          flat_map(
            g,
            fn(a)
              map((b) -> pair_key(a, b), filter((b) -> sorts_before(a, b), g))
            end
          )
        end
      )
    ),
    n:
  }
end

@doc """
percent: a over b, in whole percent, rounded down; 0 when b is 0.

    percent(6, 6) #=> 100
"""
def percent(a, b)
  if b == 0
    0
  else
    floor(a * 100 / b)
  end
end

@doc """
edge: one mined edge, with its source and the counts that show it.

    edge("implies", "B1", "B2", "census", "6 of 6 sites")[:key] #=> "implies B1 B2"
"""
def edge(kind, a, b, source, shown)
  {kind:, a:, b:, source:, shown:, key: "#{kind} #{a} #{b}"}
end

@doc """
pair_edges: the implies, co-occurs and exclusive edges one source's counts show, under the settings s.

    pair_edges("census", counts([["B1", "B2"]], 1), settei::defaults_of(settings)) #=> []
"""
def pair_edges(source, c, s)
  codes = sort_keyed((x) -> x, map(first, map_entries(c[:single])))
  n = c[:n]
  flat_map(
    codes,
    fn(a)
      flat_map(
        filter((b) -> b != a, codes),
        fn(b)
          na = get(c[:single], a)
          nb = get(c[:single], b)
          hits = get(c[:pair], pair_key(a, b)) or 0
          implied = if hits >= s[:min_support] and
              percent(hits, nb) >= s[:min_confidence] and
              na >= nb and
              a != b
            [
              edge(
                "implies",
                a,
                b,
                source,
                "#{to_s(hits)} of #{to_s(nb)} #{b} sites owe #{a} (#{to_s(percent(hits, nb))}%)"
              )
            ]
          else
            []
          end
          lift = if na * nb == 0
            0
          else
            floor(hits * n * 100 / (na * nb))
          end
          paired = if sorts_before(a, b) and
              hits >= s[:min_support] and
              lift >= s[:min_lift]
            [
              edge(
                "co-occurs",
                a,
                b,
                source,
                "#{to_s(hits)} sites owe both of #{to_s(n)}; #{to_s(floor(lift / 100))}x chance"
              )
            ]
          else
            []
          end
          expected = floor(na * nb / n)
          apart = if sorts_before(a, b) and
              hits == 0 and
              expected >= s[:min_expected]
            [
              edge(
                "exclusive",
                a,
                b,
                source,
                "0 of #{to_s(n)} sites owe both; chance expects #{to_s(expected)} (#{to_s(na)} and #{to_s(nb)})"
              )
            ]
          else
            []
          end
          append(append(implied, paired), apart)
        end
      )
    end
  )
end

@doc """
history_rows: the rows of a history file, each a map of code to debt; a line starting with # is skipped.

    history_rows("# seq origin debts") #=> []
"""
def history_rows(text)
  map(
    fn(l)
      cells = split(l, "\t")
      reduce(
        fn(acc, w)
          kv = split(w, "=")
          assoc(acc, kv[0], to_int(kv[1]))
        end,
        {},
        words(last(cells))
      )
    end,
    filter((l) -> trim(l) != "" and not starts_with(l, "#"), lines(text))
  )
end

@doc """
changes: the debt each code moved by between consecutive rows, for codes both rows hold; a change that moved nothing is dropped.

    changes([{"B1" => 3}, {"B1" => 2}]) #=> [{"B1" => -1}]
"""
def changes(rows)
  if size(rows) < 2
    []
  else
    filter(
      (c) -> not is_empty(map_entries(c)),
      map(
        fn(i)
          before = rows[i - 1]
          after = rows[i]
          reduce(
            fn(acc, e)
              was = get(before, first(e))
              if was.nil? or e[1] == was
                acc
              else
                assoc(acc, first(e), e[1] - was)
              end
            end,
            {},
            map_entries(after)
          )
        end,
        range(1, size(rows))
      )
    )
  end
end

@doc """
history_edges: the trades and fixed-together edges a list of changes shows: a fell while b rose, and a and b fell together.

    size(history_edges([{"B1" => -1, "B2" => 1}], {min_support: 1})) #=> 1
"""
def history_edges(moved, s)
  codes = sort_keyed(
    (x) -> x,
    distinct(flat_map(moved, (c) -> map(first, map_entries(c))))
  )
  flat_map(
    codes,
    fn(a)
      flat_map(
        filter((b) -> b != a, codes),
        fn(b)
          traded = size(
            filter((c) -> (get(c, a) or 0) < 0 and (get(c, b) or 0) > 0, moved)
          )
          together = size(
            filter((c) -> (get(c, a) or 0) < 0 and (get(c, b) or 0) < 0, moved)
          )
          t = if traded >= s[:min_support]
            [
              edge(
                "trades",
                a,
                b,
                "history",
                "#{to_s(traded)} of #{to_s(size(moved))} changes paid #{a} and raised #{b}"
              )
            ]
          else
            []
          end
          f = if sorts_before(a, b) and together >= s[:min_support]
            [
              edge(
                "fixed-together",
                a,
                b,
                "history",
                "#{to_s(together)} of #{to_s(size(moved))} changes paid both"
              )
            ]
          else
            []
          end
          append(t, f)
        end
      )
    end
  )
end

@doc """
registry_edges: the exclusive edges the registry states in its own text: a rule whose explanation hands a case to another (`… is B0090's`).

    registry_edges([{"code" => "B0095", "explanation" => "A call no test makes is B0090's."}])[0][:a] #=> "B0090"
"""
def registry_edges(rules)
  flat_map(
    rules,
    fn(r)
      parts = rest(split(join(words(r["explanation"]), " "), " is B"))
      flat_map(
        parts,
        fn(p)
          code = "B#{before_first(p, "'")}"
          if size(code) == 5 and code != r["code"]
            x = sort_keyed((c) -> c, [code, r["code"]])
            [
              edge(
                "exclusive",
                x[0],
                x[1],
                "registry",
                "#{r["code"]}'s explanation hands a case to #{code}"
              )
            ]
          else
            []
          end
        end
      )
    end
  )
end

@doc """
consumer_owed: the codes each consumer file owes, from the refused rows of a consumer sweep, kept to the codes named; the consumer's name is dropped.

    consumer_owed("refused: c:a.b:B1 2", ["B1"]) #=> [["B1"]]
"""
def consumer_owed(text, codes)
  pairs = flat_map(
    lines(text),
    fn(l)
      t = strip_suffix(strip_suffix(strip_prefix(trim(l), "\""), ","), "\"")
      if starts_with(t, "refused: ")
        cells = split(t, ":")
        code = first(words(last(cells)))
        if member?(code, codes)
          [[join(take_n(cells, size(cells) - 1), ":"), code]]
        else
          []
        end
      else
        []
      end
    end
  )
  groups(pairs)
end

@doc """
decide: every mined edge a source admissible for its kind shows, one row per edge with its sources, its tier, the admissible sources that hold both codes and show no edge (silent), those that lack a code (blind), and the registry's state; a kind the settings or the registry turn off is left out.

    decide([], [], [], {}, {min_sources: 2, off: ""}) #=> []
"""
def decide(edges, kinds, decided, seen, s)
  off = map(trim, split(s[:off], ","))
  live = filter((k) -> k["enabled"] and not member?(k["kind"], off), kinds)
  admits = reduce((acc, k) -> assoc(acc, k["kind"], k["sources"]), {}, live)
  kept = filter((e) -> member?(e[:source], get(admits, e[:kind]) or []), edges)
  keys = sort_keyed((k) -> k, distinct(map((e) -> e[:key], kept)))
  map(
    fn(k)
      mine = filter((e) -> e[:key] == k, kept)
      e = first(mine)
      sources = sort_keyed((x) -> x, distinct(map((m) -> m[:source], mine)))
      others = filter((x) -> not member?(x, sources), get(admits, e[:kind]))
      sees = fn(x)
        member?(e[:a], get(seen, x) or []) and
          member?(e[:b], get(seen, x) or [])
      end
      row = first(
        filter(
          (d) -> d["kind"] == e[:kind] and d["a"] == e[:a] and d["b"] == e[:b],
          decided
        )
      )
      {
        key: k,
        kind: e[:kind],
        a: e[:a],
        b: e[:b],
        sources:,
        silent: filter(sees, others),
        blind: filter((x) -> not sees(x), others),
        shown: map((m) -> "#{m[:source]}: #{m[:shown]}", mine),
        tier: if size(sources) >= s[:min_sources]
          "corroborated"
        else
          "observed"
        end,
        state: if row.nil?
          "candidate"
        else
          row["state"]
        end,
        why: if row.nil?
          nil
        else
          row["why"]
        end
      }
    end,
    keys
  )
end

@doc """
contradicted: each live row of the registry that the mined edges no longer show, by its key.

    contradicted([], [{"kind" => "implies", "a" => "B1", "b" => "B2", "live" => true}]) #=> ["implies B1 B2"]
"""
def contradicted(rows, decided)
  map(
    (d) -> "#{d["kind"]} #{d["a"]} #{d["b"]}",
    filter(
      fn(d)
        d["live"] and
          is_empty(
            filter((r) -> r[:key] == "#{d["kind"]} #{d["a"]} #{d["b"]}", rows)
          )
      end,
      decided
    )
  )
end

@doc """
reason_shape: a waiver reason with its dates and numbers dropped and its first eight words kept, so reasons written from one template read alike.

    reason_shape("debt recorded 2026-11-13: no test yet") #=> "debt recorded no test yet"
"""
def reason_shape(reason)
  join(
    take_n(
      filter(
        fn(w)
          w != "" and not member?(first(chars(w)), %w[0 1 2 3 4 5 6 7 8 9])
        end,
        map((w) -> trim(downcase(w)), split(reason, " "))
      ),
      8
    ),
    " "
  )
end

@doc """
candidates: candidate obligations: a ratcheted rule that is not an obligation yet relates to one, and a waiver reason repeated under one code, each with the registry's state for it.

    candidates([], [], [], [], {min_waivers: 2}) #=> []
"""
def candidates(rules, rows, waived, decided, s)
  obligations = map(
    (r) -> r["code"],
    filter((r) -> r["obligation"] != nil, rules)
  )
  ruled = flat_map(
    rules,
    fn(r)
      linked = filter(
        fn(e)
          e[:a] == r["code"] and member?(e[:b], obligations) or
            e[:b] == r["code"] and member?(e[:a], obligations)
        end,
        rows
      )
      if r["obligation"].nil? and r["debt"] > 0 and not is_empty(linked)
        [
          {
            kind: "unregistered-debt",
            code: r["code"],
            shown: "#{r["slug"]}: debt #{to_s(r["debt"])}, related to #{join(map((e) -> "#{e[:kind]} #{e[:a]} #{e[:b]}", linked), ", ")}"
          }
        ]
      else
        []
      end
    end
  )
  shapes = tally(map((w) -> "#{w[0]}\t#{reason_shape(w[1])}", waived))
  repeated = map(
    fn(e)
      {
        kind: "recurring-waiver",
        code: before_first(first(e), "\t"),
        shown: "#{to_s(e[1])} waivers read `#{after_first(first(e), "\t")}`"
      }
    end,
    sort_keyed(
      (e) -> first(e),
      filter((e) -> e[1] >= s[:min_waivers], map_entries(shapes))
    )
  )
  map(
    fn(c)
      d = first(
        filter((x) -> x["kind"] == c[:kind] and x["code"] == c[:code], decided)
      )
      if d.nil?
        assoc(assoc(c, :state, "candidate"), :why, nil)
      else
        assoc(assoc(c, :state, d["state"]), :why, d["why"])
      end
    end,
    append(ruled, repeated)
  )
end

@doc """
md_row: one Markdown table row from its cells, a pipe in a cell escaped.

    md_row(%w[a b]) #=> "| a | b |"
"""
def md_row(cells)
  "| #{join(map((c) -> replace(to_s(c), "|", "\\|"), cells), " | ")} |"
end

@doc """
render: the discovery report as Markdown: what was read, every edge by kind with its state and tier, the candidate obligations, and the live rows the corpus no longer shows.

    starts_with(render({sources: [], rows: [], candidates: [], contradicted: [], settings: {}}), "# Obligation discovery") #=> true
"""
def render(r)
  kinds = %w[exclusive implies co-occurs trades fixed-together]
  edge_lines = flat_map(
    kinds,
    fn(k)
      mine = filter((x) -> x[:kind] == k, r[:rows])
      if is_empty(mine)
        ["", "### #{k}", "", "No edge of this kind met the settings."]
      else
        append(
          [
            "",
            "### #{k}",
            "",
            md_row(%w[a b state tier evidence silent blind]),
            "|---|---|---|---|---|---|---|"
          ],
          map(
            fn(x)
              state = if x[:why].nil?
                x[:state]
              else
                "#{x[:state]}: #{x[:why]}"
              end
              md_row(
                [
                  x[:a],
                  x[:b],
                  state,
                  x[:tier],
                  join(x[:shown], "; "),
                  join(x[:silent], ", "),
                  join(x[:blind], ", ")
                ]
              )
            end,
            mine
          )
        )
      end
    end
  )
  cand = if is_empty(r[:candidates])
    ["No candidate obligation met the settings."]
  else
    append(
      [md_row(%w[kind code state evidence]), "|---|---|---|---|"],
      map(
        fn(c)
          state = if c[:why].nil?
            c[:state]
          else
            "#{c[:state]}: #{c[:why]}"
          end
          md_row([c[:kind], c[:code], state, c[:shown]])
        end,
        r[:candidates]
      )
    )
  end
  gone = if is_empty(r[:contradicted])
    ["Every live row of the registry is still shown by the corpus."]
  else
    map(
      (k) -> "- #{k}: live in the registry, no longer shown",
      r[:contradicted]
    )
  end
  unlines(
    append(
      append(
        append(
          [
            "# Obligation discovery",
            "",
            "Generated by `blue obligations discover` (gen/obligation-discovery.b); `checks.generated-obligation-discovery-fresh` fails when this file is stale. Design: [OBLIGATION-GRAPH.md](OBLIGATION-GRAPH.md).",
            "",
            "## Sources",
            "",
            md_row(%w[source sites denominator]),
            "|---|---|---|"
          ],
          map(
            (x) -> md_row([x[:source], x[:sites], x[:denominator]]),
            r[:sources]
          )
        ),
        append(
          ["", "## Settings", "", md_row(%w[setting value]), "|---|---|"],
          map(
            (e) -> md_row([to_s(first(e)), to_s(e[1])]),
            sort_keyed((e) -> to_s(first(e)), map_entries(r[:settings]))
          )
        )
      ),
      append(
        append(["", "## Edges"], edge_lines),
        append(
          ["", "## Candidate obligations", ""],
          append(cand, append(["", "## Contradicted", ""], gone))
        )
      )
    )
  )
end

test "a pair key puts the lesser code first, whichever order it is given"
  assert pair_key("B0002", "B0001") == "B0001|B0002"
  assert pair_key("B0001", "B0002") == "B0001|B0002"
end

test "the defaults are the documented thresholds"
  d = settei::defaults_of(settings)
  assert d[:min_support] == 3
  assert d[:min_confidence] == 90
  assert d[:min_sources] == 2
  assert d[:off] == ""
end

test "groups sorts each site's codes once"
  assert groups([%w[f:2 B1], %w[f:1 B2], %w[f:1 B1], %w[f:1 B1]]) ==
    [%w[B1 B2], ["B1"]]
end

test "counts holds each code, each pair and the denominator"
  c = counts([%w[B1 B2], ["B1"], %w[B2 B3]], 9)
  assert c[:single]["B1"] == 2
  assert c[:pair]["B1|B2"] == 1
  assert c[:pair]["B1|B3"].nil?
  assert c[:n] == 9
end

test "percent rounds down and is zero over nothing"
  assert percent(2, 3) == 66
  assert percent(1, 0) == 0
end

test "an edge is keyed by its kind and its ordered codes"
  e = edge("trades", "B2", "B1", "history", "x")
  assert e[:key] == "trades B2 B1"
  assert e[:source] == "history"
end

@doc """
loose: settings low enough for a small fixture to show every kind.

    loose[:min_support] #=> 2
"""
def loose()
  {
    min_support: 2,
    min_confidence: 90,
    min_lift: 150,
    min_expected: 2,
    min_sources: 2,
    min_waivers: 2,
    off: ""
  }
end

test "a code owed only where another is owed implies it, and the reverse does not hold"
  owed = [%w[B1 B2], %w[B1 B2], ["B1"], ["B1"], ["B3"], ["B3"], []]
  es = pair_edges("census", counts(owed, 20), loose)
  keys = map((e) -> e[:key], es)
  assert member?("implies B1 B2", keys)
  assert not member?("implies B2 B1", keys)
end

test "two codes never owed together though chance expects it are exclusive"
  owed = append(map((_i) -> ["B1"], range(10)), map((_i) -> ["B2"], range(10)))
  keys = map((e) -> e[:key], pair_edges("census", counts(owed, 20), loose))
  assert keys == ["exclusive B1 B2"]
  few = map(
    (e) -> e[:key],
    pair_edges("census", counts([["B1"], ["B2"]], 20), loose)
  )
  assert few == []
end

test "codes owed together far above chance co-occur"
  owed = append([%w[B1 B2], %w[B1 B2]], map((_i) -> [], range(40)))
  keys = map((e) -> e[:key], pair_edges("census", counts(owed, 42), loose))
  assert member?("co-occurs B1 B2", keys)
end

test "history rows parse, and changes keep only what moved between codes both rows hold"
  rows = history_rows(
    unlines(
      [
        "# seq origin debts",
        "1\tgit:a\tB1=5 B2=3",
        "2\tgit:b\tB1=4 B2=3 B3=9",
        "3\tregen\tB1=4 B2=4 B3=8"
      ]
    )
  )
  assert size(rows) == 3
  assert changes(rows) == [{"B1" => -1}, {"B2" => 1, "B3" => -1}]
  assert changes([rows[0]]) == []
end

test "a change that pays one code and raises another trades, and two paid together are fixed together"
  moved = [
    {"B1" => -1, "B2" => 2},
    {"B1" => -3, "B2" => 1},
    {"B1" => -1, "B3" => -1},
    {"B1" => -2, "B3" => -4}
  ]
  keys = map((e) -> e[:key], history_edges(moved, loose))
  assert keys == ["trades B1 B2", "fixed-together B1 B3"]
end

test "the registry hands a case to another rule, and a mention of itself or a non-code is no edge"
  rules = [
    {
      "code" => "B0095",
      "explanation" => "A definition no test calls is B0090's. Debt is held."
    },
    {
      "code" => "B0090",
      "explanation" => "This is B0090's own text, and this is Bob's."
    }
  ]
  es = registry_edges(rules)
  assert map((e) -> e[:key], es) == ["exclusive B0090 B0095"]
  assert first(es)[:source] == "registry"
end

test "consumer rows become per-file code lists with no consumer name kept"
  text = join_lines(
    [
      "\"refused: one:a/b.b:B0083 4\",",
      "\"refused: one:a/b.b:B0084 1\",",
      "\"refused: two:c.b:B0001 3\",",
      "\"refused: two:c.b:B0083 1\","
    ]
  )
  assert consumer_owed(text, %w[B0083 B0084]) == [%w[B0083 B0084], ["B0083"]]
  assert not contains?(to_s(consumer_owed(text, ["B0083"])), "one")
end

@doc """
kinds_on: every relation kind on, with every source admissible, as the registry JSON spells kinds.

    size(kinds_on) #=> 5
"""
def kinds_on()
  map(
    fn(k)
      {
        "kind" => k,
        "enabled" => true,
        "sources" => %w[census consumers history registry]
      }
    end,
    %w[implies co-occurs exclusive trades fixed-together]
  )
end

@doc """
seen_all: every source holding the fixture codes B1, B2 and B3.

    seen_all["census"] #=> ["B1", "B2", "B3"]
"""
def seen_all()
  {
    "census" => %w[B1 B2 B3],
    "consumers" => %w[B1 B2 B3],
    "history" => %w[B1 B2 B3],
    "registry" => %w[B1 B2 B3]
  }
end

test "an edge from a source its kind does not admit is dropped, and the other admissible sources are silent or blind"
  kinds = [
    {"kind" => "exclusive", "enabled" => true, "sources" => %w[census registry]}
  ]
  es = [
    edge("exclusive", "B1", "B2", "consumers", "file level"),
    edge("exclusive", "B1", "B3", "census", "x")
  ]
  rows = decide(
    es,
    kinds,
    [],
    {"census" => %w[B1 B3], "registry" => ["B1"]},
    loose
  )
  assert map((r) -> r[:key], rows) == ["exclusive B1 B3"]
  assert rows[0][:blind] == ["registry"]
  silent = decide(
    es,
    kinds,
    [],
    {"census" => %w[B1 B3], "registry" => %w[B1 B3]},
    loose
  )
  assert silent[0][:silent] == ["registry"]
  assert silent[0][:blind] == []
end

test "an edge two sources show is corroborated, one source is observed, and the registry's state is read"
  es = [
    edge("exclusive", "B1", "B2", "census", "x"),
    edge("exclusive", "B1", "B2", "registry", "y"),
    edge("implies", "B1", "B3", "census", "z")
  ]
  decided = [
    {
      "kind" => "implies",
      "a" => "B1",
      "b" => "B3",
      "state" => "rejected",
      "why" => "w"
    }
  ]
  rows = decide(es, kinds_on, decided, seen_all, loose)
  assert map((r) -> [r[:key], r[:tier], r[:state]], rows) ==
    [
      ["exclusive B1 B2", "corroborated", "candidate"],
      ["implies B1 B3", "observed", "rejected"]
    ]
  assert rows[0][:sources] == %w[census registry]
end

test "a kind configured off in the settings or the registry is not mined"
  es = [
    edge("implies", "B1", "B3", "census", "z"),
    edge("trades", "B1", "B2", "history", "t")
  ]
  off = decide(es, kinds_on, [], seen_all, assoc(loose, :off, "implies"))
  assert map((r) -> r[:kind], off) == ["trades"]
  registry_off = map(
    (k) -> assoc(k, "enabled", k["kind"] != "trades"),
    kinds_on
  )
  assert map((r) -> r[:kind], decide(es, registry_off, [], seen_all, loose)) ==
    ["implies"]
end

test "a live row the corpus no longer shows is contradicted, and one it shows is not"
  rows = decide(
    [edge("implies", "B1", "B3", "census", "z")],
    kinds_on,
    [],
    seen_all,
    loose
  )
  decided = [
    {"kind" => "implies", "a" => "B1", "b" => "B3", "live" => true},
    {"kind" => "exclusive", "a" => "B1", "b" => "B2", "live" => true},
    {"kind" => "trades", "a" => "B1", "b" => "B2", "live" => false}
  ]
  assert contradicted(rows, decided) == ["exclusive B1 B2"]
end

test "a waiver reason drops its dates and numbers and keeps eight words"
  assert reason_shape("Debt recorded 2026-11-13: no test of this file reaches it yet") ==
    "debt recorded no test of this file reaches"
end

test "a ratcheted rule related to an obligation is a candidate, and so is a reason repeated under one code"
  rules = [
    {"code" => "B1", "obligation" => "reach/x", "debt" => 3, "slug" => "x"},
    {"code" => "B9", "obligation" => nil, "debt" => 7, "slug" => "nine"},
    {"code" => "B8", "obligation" => nil, "debt" => 2, "slug" => "eight"}
  ]
  rows = [{key: "implies B9 B1", kind: "implies", a: "B9", b: "B1"}]
  waived = [
    ["B1", "debt 2026-01-01 a"],
    ["B1", "debt 2026-02-02 a"],
    %w[B1 other]
  ]
  cs = candidates(
    rules,
    rows,
    waived,
    [
      {
        "kind" => "recurring-waiver",
        "code" => "B1",
        "state" => "rejected",
        "why" => "bulk"
      }
    ],
    loose
  )
  assert map((c) -> [c[:kind], c[:code]], cs) ==
    [%w[unregistered-debt B9], %w[recurring-waiver B1]]
  assert contains?(cs[1][:shown], "2 waivers read `debt a`")
end

test "a markdown cell escapes a pipe, and the report names every section"
  assert md_row(%w[a b|c]) == "| a | b\\|c |"
  r = render(
    {
      sources: [{source: "census", sites: 2, denominator: "9 forms"}],
      rows: decide(
        [edge("implies", "B1", "B3", "census", "6 of 6")],
        kinds_on,
        [],
        seen_all,
        loose
      ),
      candidates: [],
      contradicted: ["exclusive B1 B2"],
      settings: {min_support: 2}
    }
  )
  assert contains?(r, "| census | 2 | 9 forms |")
  assert contains?(r, "| B1 | B3 | candidate | observed | census: 6 of 6 |")
  assert contains?(r, "exclusive B1 B2: live in the registry")
  assert contains?(r, "No edge of this kind met the settings.")
end
