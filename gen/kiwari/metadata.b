use("kiwari", [:blue, :render])

# tree-sitter-blue/tree-sitter.json, rendered from blue's grammar spec (bidamas/kiwari).
write_file(
  getenv("GEN_OUT", "tree-sitter-blue/tree-sitter.json"),
  render(blue(), "tree-sitter.json")
)
