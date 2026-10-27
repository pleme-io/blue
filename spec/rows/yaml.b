# YAML: deeta::parse(text, :yaml) reads YAML 1.2 by the core schema into blue
# values; a mapping is a map keyed by text. The WASM surface has no loader, so
# it misses every `use` until G16 gives it one.

row(
  "yaml.block.mapping",
  join_lines(
    [
      "use(\"deeta\")",
      "deeta::parse(\"a: 1\\nb:\\n  - x\\n  - true\\n  - ~\\n\", :yaml)"
    ]
  ),
  value("{\"a\" => 1, \"b\" => [\"x\", true, nil]}"),
  pending("G16", "wasm")
)

row(
  "yaml.flow.collections",
  join_lines(
    ["use(\"deeta\")", "deeta::parse(\"{a: [1, 'b'], c: {d: 2.5}}\", :yaml)"]
  ),
  value("{\"a\" => [1, \"b\"], \"c\" => {\"d\" => 2.5}}"),
  pending("G16", "wasm")
)

row(
  "yaml.block.scalars",
  join_lines(
    [
      "use(\"deeta\")",
      "deeta::parse(\"l: |\\n  a\\n  b\\nf: >-\\n  a\\n  b\\n\", :yaml)"
    ]
  ),
  value("{\"f\" => \"a b\", \"l\" => \"a\\nb\\n\"}"),
  pending("G16", "wasm")
)

row(
  "yaml.anchor.alias",
  join_lines(
    ["use(\"deeta\")", "deeta::parse(\"a: &x [1]\\nb: *x\\n\", :yaml)"]
  ),
  value("{\"a\" => [1], \"b\" => [1]}"),
  pending("G16", "wasm")
)

row(
  "yaml.stream.documents",
  join_lines(
    [
      "use(\"deeta\")",
      "deeta::parse(\"--- 1\\n--- two\\n\", :yaml, {documents: :all})"
    ]
  ),
  value("[1, \"two\"]"),
  pending("G16", "wasm")
)

row(
  "yaml.stream.empty",
  join_lines(["use(\"deeta\")", "deeta::parse(\"\", :yaml)"]),
  value("nil"),
  pending("G16", "wasm")
)

row(
  "yaml.refuses.indentation",
  join_lines(["use(\"deeta\")", "deeta::parse(\"a: 1\\n  b: 2\\n\", :yaml)"]),
  fails(:eval, "2:4: unexpected text after a value")
)

row(
  "yaml.refuses.collection_key",
  join_lines(["use(\"deeta\")", "deeta::parse(\"? [a]\\n: b\\n\", :yaml)"]),
  fails(:eval, "a mapping key is a scalar in blue")
)
