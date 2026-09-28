# Blue's rules

Generated from `bidamas/okite/okite.b` by `rules.b`: do not edit.
Every rule is enforced by laws in okite; a rule without a passing law fails
the build.

**Blue values behave like Ruby's, except where a rule below says otherwise.**

- **D0001** `==` is value equality: numbers by value (4 == 4.0), strings, lists and maps by content, nil only equals nil.
- **D0002** `!=` is exactly `not(a == b)`.
- **D0003** `contains`, `index_of`, `count_of` and `distinct` use `==`.
- **D0004** `nil` and `[]` are different values; `is_empty` is true of both.
- **D0005** `to_s` gives text: a string is itself, nil is "", a float keeps its point (1.0).
- **D0006** A list or map renders as its blue literal, maps sorted by key: [1, "a"], {a: 1}. Interpolation uses to_s.
- **D0007** `concat` joins the text of one or more arguments, left to right.
- **D0008** `/` is float division (7 / 2 == 3.5). Deviation from Ruby, kept.
- **D0009** Map keys are exact: 1 and 1.0 are different keys.
- **D0010** Every value has exactly one kind, each with one predicate: nil?, bool?, integer?, float?, string?, keyword?, list?, map?.
- **D0011** The empty list is always []: no list operation returns nil for an empty result.
- **D0012** `split` keeps every field: n separators give n + 1 fields, and join undoes split. Deviation from Ruby.
