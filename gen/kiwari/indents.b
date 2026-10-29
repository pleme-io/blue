use("kiwari", %i[blue render])

# tree-sitter-blue/queries/indents.scm, rendered from blue's grammar spec (bidamas/kiwari).
write_file(
  getenv("GEN_OUT", "tree-sitter-blue/queries/indents.scm"),
  render(blue, "indents.scm")
)
