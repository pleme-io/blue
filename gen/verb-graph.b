use(
  "mokuroku",
  [
    :blue_path_roots,
    :graph_findings,
    :graph_from_tsv,
    :graph_load,
    :graph_verdict
  ]
)

use("retsu", [:find_first, :size])

def graph_home()
  here = find_first(
    (r) -> path_exists(path_join(r, "mokuroku/graph")),
    blue_path_roots(getenv("BLUE_PATH", ""))
  )
  if here == nil
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
  map((f) -> "#{get(f, :kind)}\t#{get(f, :subject)}", graph_findings(g))
end

test "the committed graph loads without one refusal"
  g = graph_load(graph_home)
  assert get(g, :refusals) == []
  assert size(get(g, :verbs)) > 2000
  assert size(get(g, :edges)) > 4000
  assert size(get(g, :spaces)) > 100
  assert size(get(g, :vocab)) > 300
end

test "the committed graph breaks no gate beyond the debt it recorded"
  g = graph_load(graph_home)
  baseline = read_file(path_join(graph_home, "graph.baseline"))
  found = graph_findings(g)
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
  assert get(fixture("green"), :refusals) == []
end
