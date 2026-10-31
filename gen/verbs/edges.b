use("mokuroku", [:graph_table])

write_file(
  getenv("GEN_OUT", "docs/verbs/merged/edges.tsv"),
  graph_table(
    path_join(getenv("GEN_ROOT", "."), "bidamas/mokuroku/graph"),
    "edges.tsv"
  )
)
