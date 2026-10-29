use(
  "mokuroku",
  %i[
    blue_path_roots
    graph_findings
    graph_findings_live
    graph_from_tsv
    graph_load
    graph_verdict
    unbound_probe
    untested_probe
  ]
)

use("retsu", %i[find_first reject size])

def graph_home()
  here = find_first(
    (r) -> path_exists(path_join(r, "mokuroku/graph")),
    blue_path_roots(getenv("BLUE_PATH", ""))
  )
  if here.nil?
    "bidamas/mokuroku/graph"
  else
    path_join(here, "mokuroku/graph")
  end
end

def fixture(name)
  d = path_join(graph_home, "fixtures/#{name}")
  graph_from_tsv(
    read_file(path_join(d, "verbs.tsv")),
    read_file(path_join(d, "edges.tsv")),
    read_file(path_join(d, "contracts.tsv"))
  )
end

def lines_of(g)
  map((f) -> "#{f[:kind]}\t#{f[:subject]}", graph_findings(g))
end

test "the committed graph loads without one refusal"
  g = graph_load(graph_home)
  assert g[:refusals] == []
  assert size(g[:verbs]) > 2000
  assert size(g[:edges]) > 4000
  assert size(g[:spaces]) > 100
  assert size(g[:vocab]) > 300
end

test "the committed graph breaks no gate beyond the debt it recorded"
  g = graph_load(graph_home)
  baseline = read_file(path_join(graph_home, "graph.baseline"))
  found = graph_findings_live(g, self_exe)
  assert size(found) > 0
  assert graph_verdict(found, baseline) == []
end

test "one bad row per gate is named by that gate"
  assert lines_of(fixture("red")) ==
    [
      "g1-meaning\tfairu::read fairu::slurp",
      "g2-vocab\tfairu::fetch",
      "g4-cycle\ta::x",
      "g4-cycle\ta::y",
      "g4-wave\tfairu::write -> deeta::read",
      "g7-inverse\tjisho::put",
      "g9-dangling\tfairu::rd",
      "g9-relation\tfairu::read frobs fairu::write"
    ]
end

test "the same fixture with its bad rows removed breaks no gate"
  assert lines_of(fixture("green")) == []
  assert fixture("green")[:refusals] == []
end

def live_lines_of(g)
  map((f) -> "#{f[:kind]}\t#{f[:subject]}", graph_findings_live(g, self_exe))
end

test "every exists row of the committed graph resolves in a live interpreter"
  g = graph_load(graph_home)
  assert unbound_probe(g, self_exe) == []
end

test "one exists row no bidama defines is named by the live probe, and no other row is"
  assert live_lines_of(fixture("unbound")) ==
    ["g10-unbound\tmoji::nothere", "g11-untested\tmoji::nothere"]
end

test "the same fixture with its unbound row removed breaks no gate"
  g = fixture("unbound")
  kept = assoc(g, :verbs, reject((r) -> r[:verb] == "nothere", g[:verbs]))
  assert live_lines_of(kept) == []
end

test "a probe with no blue to run it raises instead of reporting nothing"
  r = unbound_probe(fixture("unbound"), nil) rescue "caught"
  assert r == "caught"
  s = unbound_probe(fixture("unbound"), "/nonexistent/blue") rescue "caught"
  assert s == "caught"
end

def zed_root(tested)
  root = path_join(
    getenv("TMPDIR", "/tmp"),
    "verb-graph-zed-#{blake3_hex(tested)}"
  )
  rm_rf(root)
  mkdir_p(path_join(root, "zed"))
  write_file(
    path_join(root, "zed/Bluefile"),
    unlines(["package(\"zed\", \"0.1.0\")"])
  )
  write_program(
    path_join(root, "zed/zed.b"),
    join_lines(
      [
        "def lower(s)",
        "  s",
        "end",
        "",
        "def upper(s)",
        "  s",
        "end",
        "",
        "def title(s)",
        "  s",
        "end",
        "",
        tested
      ]
    )
  )
  root
end

def untested_lines(tested)
  root = zed_root(tested)
  found = untested_probe(fixture("untested"), [root])
  rm_rf(root)
  map((f) -> "#{f[:kind]}\t#{f[:subject]}", found)
end

test "one exists row with no unit test is named by the test probe, and no other row is"
  assert untested_lines(
    unlines(["test \"lower\"", "  assert lower(\"A\") == \"a\"", "end"])
  ) == ["g11-untested\tzed::upper"]
  assert untested_lines("") ==
    ["g11-untested\tzed::lower", "g11-untested\tzed::upper"]
end

test "the same package with a test for each exists row breaks no gate"
  assert untested_lines(
    unlines(
      [
        "test \"both\"",
        "  assert lower(\"A\") == \"a\"",
        "  assert upper(\"a\") == \"A\"",
        "end"
      ]
    )
  ) == []
end

test "a verb named only in a string, a comment or a def body is not tested"
  assert untested_lines(
    unlines(
      [
        "test \"words\"",
        "  # lower(x)",
        "  assert \"lower(x) upper(x)\" == \"lower(x) upper(x)\" # upper(y)",
        "end"
      ]
    )
  ) == ["g11-untested\tzed::lower", "g11-untested\tzed::upper"]
end

test "an untested exists row is debt the baseline holds and never lets grow"
  found = untested_probe(fixture("untested"), [zed_root("")])
  assert size(found) == 2
  assert size(graph_verdict(found, "")) > 0
  assert graph_verdict(found, unlines(["g11-untested: zed 2"])) == []
  assert size(graph_verdict(found, unlines(["g11-untested: zed 1"]))) > 0
end

test "every exists row of the committed graph is tested, beyond the debt recorded"
  g = graph_load(graph_home)
  baseline = read_file(path_join(graph_home, "graph.baseline"))
  found = untested_probe(g, blue_path_roots(getenv("BLUE_PATH", "")))
  assert graph_verdict(found, baseline) == []
end

test "a probe with no bidama to read raises instead of calling every verb untested"
  r = untested_probe(fixture("untested"), []) rescue "caught"
  assert r == "caught"
end
