@moduledoc """
gurafu (グラフ) — directed graphs as values: build them, ask them, order them.

A graph is a record of its nodes and, for each node, the sorted nodes its
edges point to. Nodes are text, keywords or numbers, one kind per graph,
ordered by compare. Every word is pure and answers a new value. An edge
`[a, b]` points from a to b, so a dependency graph points from the upstream
to the downstream and `topo` lists upstreams first. `topo` refuses a graph
with a cycle and names the cycle; `cycle` answers that cycle, or nil.

    topo(graph([["b", "c"], ["a", "b"]], {})) #=> ["a", "b", "c"]
"""

use("moji", [:checked])
use("ran", [:seeds, :take_ints])
use("retsu", [:first, :is_empty, :last, :size])
use("shuugou", [:ordered])
use("tesuto", [:raises?])

@doc """
edge_ok: an edge when it is a pair of nodes, else a :bad_option raise.

    edge_ok(["a", "b"]) #=> ["a", "b"]
"""
def edge_ok(e)
  if not list?(e) or e.nil? or size(e) != 2
    raise(:bad_option, "an edge is a pair [from, to], got #{to_s(e)}")
  end
  e
end

@doc """
graph: a graph from edge pairs; `nodes:` adds nodes with no edge, and `directed: false` adds each edge both ways.

    nodes(graph([["a", "b"]], {nodes: ["c"]})) #=> ["a", "b", "c"]
"""
def graph(edges, opts)
  checked(opts, [:directed, :nodes])
  given = map(edge_ok, edges)
  pairs = if opts[:directed] == false
    append(given, map((e) -> [e[1], first(e)], given))
  else
    given
  end
  ns = ordered(append(opts[:nodes] or [], retsu::flat_map(pairs, (e) -> e)))
  grouped = reduce(
    fn(acc, e)
      assoc(acc, first(e), retsu::push(get(acc, first(e)) or [], e[1]))
    end,
    {},
    pairs
  )
  {
    nodes: ns,
    out: reduce(
      (acc, n) -> assoc(acc, n, ordered(get(grouped, n) or [])),
      {},
      ns
    )
  }
end

@doc """
nodes: every node of a graph, sorted.

    nodes(graph([["b", "a"]], {})) #=> ["a", "b"]
"""
def nodes(g)
  g[:nodes]
end

@doc """
neighbors: the nodes one edge away from a node, sorted; [] for a node the graph does not hold.

    neighbors(graph([["a", "c"], ["a", "b"]], {}), "a") #=> ["b", "c"]
"""
def neighbors(g, node)
  get(g[:out], node) or []
end

@doc """
edges: every edge of a graph as a [from, to] pair, sorted.

    edges(graph([["b", "a"], ["a", "b"]], {})) #=> [["a", "b"], ["b", "a"]]
"""
def edges(g)
  retsu::flat_map(nodes(g), (n) -> map((t) -> [n, t], neighbors(g, n)))
end

@doc """
has_edge?: whether a graph holds the edge from one node to another.

    has_edge?(graph([["a", "b"]], {}), "b", "a") #=> false
"""
def has_edge?(g, from, to)
  member?(to, neighbors(g, from))
end

@doc """
add_node: a graph that also holds a node.

    nodes(add_node(graph([], {}), "a")) #=> ["a"]
"""
def add_node(g, node)
  graph(edges(g), {nodes: retsu::push(nodes(g), node)})
end

@doc """
add_edge: a graph that also holds the edge from one node to another, adding both nodes.

    edges(add_edge(graph([], {}), "a", "b")) #=> [["a", "b"]]
"""
def add_edge(g, from, to)
  graph(retsu::push(edges(g), [from, to]), {nodes: nodes(g)})
end

@doc """
remove_edge: a graph without one edge; its nodes stay.

    nodes(remove_edge(graph([["a", "b"]], {}), "a", "b")) #=> ["a", "b"]
"""
def remove_edge(g, from, to)
  graph(filter((e) -> e != [from, to], edges(g)), {nodes: nodes(g)})
end

@doc """
remove_node: a graph without a node and every edge at it.

    edges(remove_node(graph([["a", "b"], ["b", "c"]], {}), "b")) #=> []
"""
def remove_node(g, node)
  graph(
    filter((e) -> not member?(node, e), edges(g)),
    {nodes: filter((n) -> n != node, nodes(g))}
  )
end

@doc """
reverse: a graph with every edge turned around.

    edges(reverse(graph([["a", "b"]], {}))) #=> [["b", "a"]]
"""
def reverse(g)
  graph(map((e) -> [e[1], first(e)], edges(g)), {nodes: nodes(g)})
end

@doc """
subgraph: a graph restricted to some nodes and the edges between them.

    edges(subgraph(graph([["a", "b"], ["b", "c"]], {}), ["a", "b"])) #=> [["a", "b"]]
"""
def subgraph(g, keep)
  kept = filter((n) -> member?(n, keep), nodes(g))
  graph(
    filter((e) -> member?(first(e), kept) and member?(e[1], kept), edges(g)),
    {nodes: kept}
  )
end

@doc """
leaves: the nodes no edge leaves, sorted.

    leaves(graph([["a", "b"], ["a", "c"]], {})) #=> ["b", "c"]
"""
def leaves(g)
  filter((n) -> is_empty(neighbors(g, n)), nodes(g))
end

@doc """
spread: the nodes found by following edges out of a frontier, given those already seen.

    spread(graph([["a", "b"]], {}), ["a"], {}) #=> ["b"]
"""
def spread(g, frontier, seen)
  if is_empty(frontier)
    ordered(map(first, map_entries(seen)))
  else
    fresh = ordered(
      filter(
        (t) -> get(seen, t).nil?,
        retsu::flat_map(frontier, (n) -> neighbors(g, n))
      )
    )
    spread(g, fresh, reduce((acc, t) -> assoc(acc, t, true), seen, fresh))
  end
end

@doc """
reachable: every node a start node reaches by one edge or more, sorted; the start is in it only when it lies on a cycle.

    reachable(graph([["a", "b"], ["b", "c"]], {}), "a") #=> ["b", "c"]
"""
def reachable(g, start)
  spread(g, [start], {})
end

@doc """
in_degrees: for each node, how many edges reach it.

    in_degrees(graph([["a", "b"]], {})) #=> {"a" => 0, "b" => 1}
"""
def in_degrees(g)
  reduce(
    (acc, e) -> assoc(acc, e[1], get(acc, e[1]) + 1),
    reduce((acc, n) -> assoc(acc, n, 0), {}, nodes(g)),
    edges(g)
  )
end

@doc """
peel: the layers of a graph from a ready layer on, each node placed once every edge into it is placed.

    peel(graph([["a", "b"]], {}), {"a" => 0, "b" => 1}, ["a"], []) #=> [["a"], ["b"]]
"""
def peel(g, indeg, ready, done)
  if is_empty(ready)
    done
  else
    nexts = retsu::flat_map(ready, (n) -> neighbors(g, n))
    left = reduce((acc, t) -> assoc(acc, t, get(acc, t) - 1), indeg, nexts)
    peel(
      g,
      left,
      ordered(filter((t) -> get(left, t) == 0, nexts)),
      retsu::push(done, ready)
    )
  end
end

@doc """
layers: the acyclic part of a graph in layers: sources first, then each node one layer past its deepest upstream, each layer sorted.

    layers(graph([["a", "c"], ["b", "c"], ["c", "d"]], {})) #=> [["a", "b"], ["c"], ["d"]]
"""
def layers(g)
  indeg = in_degrees(g)
  peel(g, indeg, filter((n) -> get(indeg, n) == 0, nodes(g)), [])
end

@doc """
back_walk: a cycle found by following predecessors among nodes that all have one, from the path walked so far.

    back_walk(graph([["a", "b"], ["b", "a"]], {}), ["a"], {"a" => 0, "b" => true}) #=> ["a", "b"]
"""
def back_walk(back, path, seen)
  at = last(path)
  before = first(neighbors(back, at))
  i = get(seen, before)
  if integer?(i)
    loop = drop(i, path)
    forward = append([first(loop)], blue::reverse(drop(1, loop)))
    turned = position(first(ordered(forward)), forward)
    append(drop(turned, forward), take(turned, forward))
  else
    back_walk(back, retsu::push(path, before), assoc(seen, before, size(path)))
  end
end

@doc """
cycle: one cycle of a graph as its nodes in edge order, starting at the smallest, or nil when the graph has none.

    cycle(graph([["b", "c"], ["c", "b"], ["a", "b"]], {})) #=> ["b", "c"]
"""
def cycle(g)
  placed = reduce(
    (acc, n) -> assoc(acc, n, true),
    {},
    retsu::flat_map(layers(g), (l) -> l)
  )
  stuck = filter((n) -> get(placed, n).nil?, nodes(g))
  if not is_empty(stuck)
    start = first(stuck)
    back_walk(
      subgraph(reverse(g), stuck),
      [start],
      assoc(reduce((acc, n) -> assoc(acc, n, true), {}, stuck), start, 0)
    )
  end
end

@doc """
cycle_text: a cycle written as its path back to where it starts.

    cycle_text(["a", "b"]) #=> "a -> b -> a"
"""
def cycle_text(c)
  join(map(to_s, retsu::push(c, first(c))), " -> ")
end

@doc """
topo: every node ordered so each edge points forward, in layers from the sources, each layer sorted; a cycle is refused with :refused, naming it.

    topo(graph([["c", "d"], ["a", "c"], ["b", "c"]], {})) #=> ["a", "b", "c", "d"]
"""
def topo(g)
  c = cycle(g)
  if c != nil
    raise(:refused, "a cycle: #{cycle_text(c)}", {data: {cycle: c}})
  end
  retsu::flat_map(layers(g), (l) -> l)
end

@doc """
depth: how many edges lie on the longest path from a source to a node; a cycle is refused as topo refuses it.

    depth(graph([["a", "b"], ["b", "c"], ["a", "c"]], {}), "c") #=> 2
"""
def depth(g, node)
  topo(g)
  position(true, map((l) -> member?(node, l), layers(g)))
end

@doc """
random_edges: n edges over nodes 0 to size - 1 drawn from a seed; with `forward: true` each edge points from a smaller node to a larger one.

    size(random_edges(7, 5, 4, false)) #=> 4
"""
def random_edges(seed, nodes_count, n, forward)
  froms = take_ints(seed, nodes_count, n)
  tos = take_ints(seeds(seed, 2)[1], nodes_count, n)
  map(
    fn(i)
      a = froms[i]
      b = tos[i]
      if forward and a >= b
        [b, a + 1]
      else
        [a, b]
      end
    end,
    range(n)
  )
end

@doc """
respects?: whether an order puts the start of every edge of a graph before its end.

    respects?(graph([["a", "b"]], {}), ["b", "a"]) #=> false
"""
def respects?(g, order)
  every?((e) -> position(first(e), order) < position(e[1], order), edges(g))
end

@doc """
real_cycle?: whether a list of nodes is a cycle of a graph: each one has an edge to the next, and the last to the first.

    real_cycle?(graph([["a", "b"], ["b", "a"]], {}), ["a", "b"]) #=> true
"""
def real_cycle?(g, c)
  not is_empty(c) and
    every?((i) -> has_edge?(g, c[i], c[(i + 1) % size(c)]), range(size(c)))
end

@doc """
acyclic?: whether no node of a graph reaches itself, judged by reachable alone.

    acyclic?(graph([["a", "a"]], {})) #=> false
"""
def acyclic?(g)
  every?((n) -> not member?(n, reachable(g, n)), nodes(g))
end

test "the empty graph has no nodes, no edges, an empty order and no cycle"
  g = graph([], {})
  assert nodes(g) == []
  assert edges(g) == []
  assert topo(g) == []
  assert cycle(g).nil?
  assert leaves(g) == []
  assert reachable(g, "a") == []
end

test "graph sorts nodes and targets and drops repeated edges"
  g = graph([["b", "a"], ["a", "c"], ["a", "b"], ["a", "c"]], {})
  assert nodes(g) == ["a", "b", "c"]
  assert edges(g) == [["a", "b"], ["a", "c"], ["b", "a"]]
  assert neighbors(g, "a") == ["b", "c"]
  assert neighbors(g, "z") == []
  assert has_edge?(g, "b", "a")
  assert not has_edge?(g, "c", "a")
end

test "an undirected graph holds each edge both ways, and a bad edge or option is refused"
  g = graph([["a", "b"]], {directed: false})
  assert edges(g) == [["a", "b"], ["b", "a"]]
  assert raises?(:bad_option, () -> graph([["a"]], {}))
  assert raises?(:bad_option, () -> graph(["ab"], {}))
  assert raises?(:bad_option, () -> graph([], {weights: true}))
end

test "add and remove are inverses on edges and nodes"
  g = graph([["a", "b"]], {})
  assert add_edge(remove_edge(g, "a", "b"), "a", "b") == g
  assert remove_node(add_node(g, "z"), "z") == g
  assert nodes(add_edge(g, "c", "d")) == ["a", "b", "c", "d"]
  assert remove_node(g, "a") == graph([], {nodes: ["b"]})
end

test "reverse twice is the graph, and reverse turns reach into reach-from"
  g = graph([["a", "b"], ["b", "c"], ["x", "c"]], {})
  assert reverse(reverse(g)) == g
  assert reachable(reverse(g), "c") == ["a", "b", "x"]
  assert reachable(g, "a") == ["b", "c"]
  assert reachable(g, "c") == []
end

test "subgraph keeps chosen nodes and only the edges between them"
  g = graph([["a", "b"], ["b", "c"], ["c", "a"]], {})
  assert subgraph(g, ["a", "c"]) == graph([["c", "a"]], {})
  assert subgraph(g, []) == graph([], {})
end

test "leaves are the nodes with no edge out, isolated nodes included"
  g = graph([["a", "b"], ["b", "c"]], {nodes: ["z"]})
  assert leaves(g) == ["c", "z"]
end

test "topo is stable on ties: layer by layer, by name within a layer"
  g = graph([["b", "d"], ["a", "d"], ["c", "e"], ["d", "e"]], {})
  assert topo(g) == ["a", "b", "c", "d", "e"]
  assert layers(g) == [["a", "b", "c"], ["d"], ["e"]]
  assert topo(graph([], {nodes: ["c", "a", "b"]})) == ["a", "b", "c"]
  assert depth(g, "e") == 2
  assert depth(g, "c") == 0
end

test "a cycle is a refusal naming the cycle"
  g = graph([["a", "b"], ["b", "c"], ["c", "a"], ["x", "a"]], {})
  assert cycle(g) == ["a", "b", "c"]
  assert raises?(:refused, () -> topo(g))
  e = begin
    topo(g)
  rescue err
    err
  end
  assert e.message == "a cycle: a -> b -> c -> a"
  assert e.data[:cycle] == ["a", "b", "c"]
  assert cycle(graph([["k", "k"]], {})) == ["k"]
  assert cycle(graph([["b", "c"], ["c", "b"], ["c", "a"]], {})) == ["b", "c"]
  assert raises?(:refused, () -> depth(g, "x"))
end

test "a cycle downstream of a long chain is found, and a long chain orders"
  chain = map((i) -> [i, i + 1], range(2000))
  assert size(topo(graph(chain, {}))) == 2001
  assert cycle(graph(retsu::push(chain, [2000, 1500]), {})) == range(1500, 2001)
end

test "topo respects every edge of random acyclic graphs"
  assert every?(
    fn(s)
      g = graph(random_edges(s, 12, 20, true), {})
      respects?(g, topo(g)) and
        size(topo(g)) == size(nodes(g)) and
        cycle(g).nil?
    end,
    seeds(11, 40)
  )
end

test "cycle is found exactly when one exists, judged by reachable"
  assert every?(
    fn(s)
      g = graph(random_edges(s, 8, 9, false), {})
      c = cycle(g)
      if acyclic?(g)
        c.nil? and respects?(g, topo(g))
      else
        real_cycle?(g, c) and raises?(:refused, () -> topo(g))
      end
    end,
    seeds(23, 60)
  )
end

test "the property helpers can say no"
  g = graph([["a", "b"]], {})
  assert not respects?(g, ["b", "a"])
  assert not real_cycle?(g, ["a", "b"])
  assert not real_cycle?(g, [])
  assert acyclic?(g)
  assert not acyclic?(add_edge(g, "b", "a"))
  assert random_edges(3, 4, 6, true) == random_edges(3, 4, 6, true)
  assert every?((e) -> first(e) < e[1], random_edges(5, 4, 30, true))
end
