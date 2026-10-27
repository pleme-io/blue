# Nix source as rnix's lossless syntax tree, pure and the same on every evaluator.

row(
  "nix.parse",
  join_lines(
    [
      "t = nix_parse(\"{ a = 1; }\")",
      "r = get(t, :root)",
      "[get(r, :kind), get(r, :start), get(r, :end), length(get(t, :errors)), get(first(get(r, :children)), :kind)]"
    ]
  ),
  value("[\"NODE_ROOT\", 0, 10, 0, \"NODE_ATTR_SET\"]"),
  covers("builtin:nix_parse")
)

row(
  "nix.parse.error",
  join_lines(
    [
      "e = first(get(nix_parse(\"{ a = ; }\"), :errors))",
      "[get(e, :start) >= 0, length(get(e, :message)) > 0]"
    ]
  ),
  value("[true, true]")
)
