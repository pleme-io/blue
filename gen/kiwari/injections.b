use("kiwari", [:blue, :render])

write_file(
  getenv("GEN_OUT", "tree-sitter-blue/queries/injections.scm"),
  render(blue, "injections.scm")
)
