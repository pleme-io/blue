use("kiwari", [:blue, :render])

# tree-sitter-blue/queries/highlights.scm, rendered from blue's grammar spec (bidamas/kiwari).
write_file(
  getenv("GEN_OUT", "tree-sitter-blue/queries/highlights.scm"),
  render(blue(), "highlights.scm")
)
