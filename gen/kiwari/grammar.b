use("kiwari", [:blue, :render])

# tree-sitter-blue/grammar.js, rendered from blue's grammar spec (bidamas/kiwari).
write_file(
  getenv("GEN_OUT", "tree-sitter-blue/grammar.js"),
  render(blue(), "grammar.js")
)
