space("gurafu?", {status: :provisional})

verb(
  "gurafu?",
  "add_edge",
  {
    kind: :pure,
    shape: "add_edge(graph, from, to, opts) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "graph with an edge added; weight optional",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "add_node",
  {
    kind: :pure,
    shape: "add_node(graph, node) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "graph with a node added",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "closure",
  {
    kind: :pure,
    shape: "closure(graph) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "graph with an edge for every reachable pair",
    wave: 3,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "color",
  {
    kind: :pure,
    shape: "color(graph, opts) -> map",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "give nodes colors so neighbors differ",
    wave: 4,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "components",
  {
    kind: :pure,
    shape: "components(graph) -> [set]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "groups of nodes joined by edges",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "cycle",
  {
    kind: :pure,
    shape: "cycle(graph) -> [node] or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "one cycle if the graph has any",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "degree",
  {
    kind: :pure,
    shape: "degree(graph, node) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "number of edges at a node",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "depth",
  {
    kind: :pure,
    shape: "depth(tree, node) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "edges from the root to a node",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "distances",
  {
    kind: :pure,
    shape: "distances(graph, from) -> map",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "cheapest cost from a node to every node",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "edges",
  {
    kind: :pure,
    shape: "edges(graph) -> [edge]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every edge, sorted",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "flow",
  {
    kind: :pure,
    shape: "flow(graph, from, to) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "largest flow between two nodes",
    wave: 4,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "fold",
  {
    kind: :pure,
    shape: "fold(tree, f) -> value",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "reduce a tree from the leaves up",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "graft",
  {
    kind: :pure,
    shape: "graft(tree, node, subtree) -> tree",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "tree with a subtree attached at a node",
    wave: 3,
    origin: "A",
    contract: "graft(tree, node) -> tree"
  }
)

verb(
  "gurafu?",
  "graph",
  {
    kind: :decl,
    shape: "graph(edges, opts) -> graph",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "build a graph from edges; directed or not",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "has_edge?",
  {
    kind: :pure,
    shape: "has_edge?(graph, from, to) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether the edge exists",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "kids",
  {
    kind: :pure,
    shape: "kids(tree, node) -> [node]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "direct children of a node",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "lca",
  {
    kind: :pure,
    shape: "lca(tree, a, b) -> node",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "nearest common ancestor of two nodes",
    wave: 3,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "leaves",
  {
    kind: :pure,
    shape: "leaves(tree) -> [node]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "nodes without children",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "neighbors",
  {
    kind: :pure,
    shape: "neighbors(graph, node) -> [node]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "nodes one edge away",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "nodes",
  {
    kind: :pure,
    shape: "nodes(graph) -> [node]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every node, sorted",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "parent",
  {
    kind: :pure,
    shape: "parent(tree, node) -> node or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "parent of a node, nil at the root",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "path",
  {
    kind: :pure,
    shape: "path(graph, from, to, opts) -> [node] or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "cheapest route between two nodes",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "prune",
  {
    kind: :pure,
    shape: "prune(tree, f) -> tree",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "tree without subtrees where f holds",
    wave: 3,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "reachable",
  {
    kind: :pure,
    shape: "reachable(graph, start) -> set",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every node a start node can reach",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "reduction",
  {
    kind: :pure,
    shape: "reduction(graph) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "smallest graph with the same reachability",
    wave: 3,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "remove_edge",
  {
    kind: :pure,
    shape: "remove_edge(graph, from, to) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "graph without one edge",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "remove_node",
  {
    kind: :pure,
    shape: "remove_node(graph, node) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "graph without a node and its edges",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "reverse",
  {
    kind: :pure,
    shape: "reverse(graph) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "graph with every edge turned around",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "root",
  {
    kind: :pure,
    shape: "root(tree) -> node",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the node without a parent",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "scc",
  {
    kind: :pure,
    shape: "scc(graph) -> [set]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "strongly connected groups of a directed graph",
    wave: 3,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "spanning",
  {
    kind: :pure,
    shape: "spanning(graph) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "cheapest tree that joins all nodes",
    wave: 3,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "subgraph",
  {
    kind: :pure,
    shape: "subgraph(graph, nodes) -> graph",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "graph restricted to some nodes",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "topo",
  {
    kind: :pure,
    shape: "topo(graph) -> [node]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "nodes ordered so every edge points forward",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "tree",
  {
    kind: :decl,
    shape: "tree(value, kids) -> tree",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "rooted tree: a value and its subtrees",
    wave: 2,
    origin: "A"
  }
)

verb(
  "gurafu?",
  "walk",
  {
    kind: :pure,
    shape: "walk(graph, start, order) -> [node]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "nodes in breadth-first or depth-first order",
    wave: 2,
    origin: "A",
    contract: "walk(graph, opts) -> [node]"
  }
)

edge("gurafu?::graph", :composes, "gurafu?::add_edge", "built edge by edge")

edge(
  "gurafu?::path",
  :composes,
  "gurafu?::distances",
  "cheapest cost then route"
)

edge("gurafu?::neighbors", :composes, "gurafu?::edges", "edges at a node")
edge("gurafu?::reverse", :composes, "gurafu?::edges", "swap each edge")
edge("gurafu?::fold", :composes, "gurafu?::kids", "children first")

edge(
  "gurafu?::leaves",
  :composes,
  "gurafu?::kids",
  "nodes whose kids are empty"
)

edge(
  "gurafu?::prune",
  :composes,
  "gurafu?::kids",
  "drop children where f holds"
)

edge("gurafu?::degree", :composes, "gurafu?::neighbors", "count of neighbors")

edge(
  "gurafu?::has_edge?",
  :composes,
  "gurafu?::neighbors",
  "target in neighbors"
)

edge(
  "gurafu?::walk",
  :composes,
  "gurafu?::neighbors",
  "visit neighbors in order"
)

edge("gurafu?::subgraph", :composes, "gurafu?::nodes", "keep chosen nodes")
edge("gurafu?::lca", :composes, "gurafu?::parent", "climb until the paths meet")
edge("gurafu?::depth", :composes, "gurafu?::path", "path length from the root")
edge("gurafu?::flow", :composes, "gurafu?::path", "augmenting paths")

edge(
  "gurafu?::closure",
  :composes,
  "gurafu?::reachable",
  "an edge to each reachable node"
)

edge(
  "gurafu?::components",
  :composes,
  "gurafu?::reachable",
  "reach from each unvisited node"
)

edge("gurafu?::cycle", :composes, "gurafu?::walk", "walk until a node repeats")
edge("gurafu?::reachable", :composes, "gurafu?::walk", "every visited node")
edge("gurafu?::path", :composes, "junban?::pop", "cheapest next node first")
edge("gurafu?::walk", :composes, "junban?::pop", "queue order sets BFS or DFS")

edge(
  "gurafu?::distances",
  :composes,
  "junban?::reprioritize",
  "lower a cost in the queue"
)

edge("gurafu?::fold", :generalizes, "retsu::reduce", "trees fold like lists")
edge("gurafu?::remove_edge", :inverse, "gurafu?::add_edge", "undoes add_edge")
edge("gurafu?::remove_node", :inverse, "gurafu?::add_node", "undoes add_node")
edge("gurafu?::prune", :inverse, "gurafu?::graft", "attach what prune cut")
edge("gurafu?::graft", :inverse, "gurafu?::prune", "attach what prune cut")
edge("gurafu?::add_edge", :inverse, "gurafu?::remove_edge", "undoes add_edge")
edge("gurafu?::add_node", :inverse, "gurafu?::remove_node", "undoes add_node")
edge("gurafu?::nodes", :pairs, "gurafu?::add_node", "read and build")

edge(
  "gurafu?::reduction",
  :pairs,
  "gurafu?::closure",
  "smallest and fullest same reach"
)

edge(
  "gurafu?::topo",
  :pairs,
  "gurafu?::cycle",
  "order or the cycle that blocks it"
)

edge("gurafu?::neighbors", :pairs, "gurafu?::degree", "which and how many")
edge("gurafu?::nodes", :pairs, "gurafu?::edges", "vertices and links")
edge("gurafu?::root", :pairs, "gurafu?::leaves", "the two ends of a tree")

edge(
  "gurafu?::closure",
  :pairs,
  "gurafu?::reachable",
  "all pairs versus one start"
)

edge("gurafu?::prune", :pairs, "gurafu?::subgraph", "cut a tree or a graph")

edge(
  "gurafu?::scc",
  :refines,
  "gurafu?::components",
  "components of a directed graph"
)

edge("gurafu?::tree", :refines, "gurafu?::graph", "acyclic, one parent each")

edge(
  "gurafu?::kids",
  :refines,
  "gurafu?::neighbors",
  "outgoing edges of a tree"
)

edge(
  "gurafu?::parent",
  :refines,
  "gurafu?::neighbors",
  "incoming edge of a tree"
)

edge("gurafu?::distances", :refines, "gurafu?::walk", "walk with costs")

edge(
  "gurafu?::spanning",
  :requires,
  "gurafu?::components",
  "connected component at a time"
)

edge("gurafu?::topo", :requires, "gurafu?::cycle", "only acyclic graphs order")
edge("gurafu?::color", :requires, "gurafu?::neighbors", "neighbors differ")
edge("gurafu?::root", :requires, "gurafu?::tree", "has no parent")
