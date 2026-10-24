# YAML: deeta::parse(text, :yaml) reads YAML 1.2 by the core schema into blue
# values; a mapping is a map keyed by text. The WASM surface has no loader, so
# it misses every `use` until G16 gives it one.

row(
  "yaml.block.mapping",
  "use(\"deeta\")\ndeeta::parse(\"a: 1\\nb:\\n  - x\\n  - true\\n  - ~\\n\", :yaml)",
  value("{\"a\" => 1, \"b\" => [\"x\", true, nil]}"),
  pending("G16", "wasm")
)

row(
  "yaml.flow.collections",
  "use(\"deeta\")\ndeeta::parse(\"{a: [1, 'b'], c: {d: 2.5}}\", :yaml)",
  value("{\"a\" => [1, \"b\"], \"c\" => {\"d\" => 2.5}}"),
  pending("G16", "wasm")
)

row(
  "yaml.block.scalars",
  "use(\"deeta\")\ndeeta::parse(\"l: |\\n  a\\n  b\\nf: >-\\n  a\\n  b\\n\", :yaml)",
  value("{\"f\" => \"a b\", \"l\" => \"a\\nb\\n\"}"),
  pending("G16", "wasm")
)

row(
  "yaml.anchor.alias",
  "use(\"deeta\")\ndeeta::parse(\"a: &x [1]\\nb: *x\\n\", :yaml)",
  value("{\"a\" => [1], \"b\" => [1]}"),
  pending("G16", "wasm")
)

row(
  "yaml.stream.documents",
  "use(\"deeta\")\ndeeta::parse(\"--- 1\\n--- two\\n\", :yaml, {documents: :all})",
  value("[1, \"two\"]"),
  pending("G16", "wasm")
)

row(
  "yaml.stream.empty",
  "use(\"deeta\")\ndeeta::parse(\"\", :yaml)",
  value("nil"),
  pending("G16", "wasm")
)

row(
  "yaml.refuses.indentation",
  "use(\"deeta\")\ndeeta::parse(\"a: 1\\n  b: 2\\n\", :yaml)",
  fails(:eval, "2:4: unexpected text after a value")
)

row(
  "yaml.refuses.collection_key",
  "use(\"deeta\")\ndeeta::parse(\"? [a]\\n: b\\n\", :yaml)",
  fails(:eval, "a mapping key is a scalar in blue")
)
