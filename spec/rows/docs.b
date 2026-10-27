# Documentation: `@doc` and `@moduledoc` are typed children of the tree that
# leave the program's meaning alone, have one formatting, and whose examples
# run as tests on every evaluator.

row(
  "docs.doc.documents_a_def",
  unlines(
    [
      "@doc \"\"\"",
      "inc adds one to a number.",
      "",
      "    inc(1) #=> 2",
      "\"\"\"",
      "def inc(n)",
      "  n + 1",
      "end",
      "",
      "inc(41)"
    ]
  ),
  value("42"),
  covers(
    join_lines(
      [
        "form:@doc \"\"\"",
        "inc adds one to a number.",
        "",
        "    inc(1) #=> 2",
        "\"\"\"",
        "def inc(n)",
        "  n + 1",
        "end"
      ]
    )
  )
)

row(
  "docs.moduledoc.documents_a_file",
  unlines(
    [
      "@moduledoc \"\"\"",
      "m holds one value.",
      "",
      "    x #=> 1",
      "\"\"\"",
      "",
      "x = 1",
      "x"
    ]
  ),
  value("1"),
  covers(
    join_lines(
      [
        "form:@moduledoc \"\"\"",
        "kazu holds the number verbs.",
        "",
        "    kazu::clamp(9, 1, 5) #=> 5",
        "\"\"\""
      ]
    )
  )
)

row(
  "docs.doc.one_formatting",
  unlines(
    [
      "@doc   \"\"\"",
      "    inc adds one.   ",
      "",
      "        inc(1) #=> 2",
      "    \"\"\"",
      "",
      "def inc(n)",
      "  n + 1",
      "end"
    ]
  ),
  formats(
    unlines(
      [
        "@doc \"\"\"",
        "inc adds one.",
        "",
        "    inc(1) #=> 2",
        "\"\"\"",
        "def inc(n)",
        "  n + 1",
        "end"
      ]
    )
  )
)

row(
  "docs.doctest.examples_hold",
  unlines(
    [
      "@doc \"\"\"",
      "inc adds one to a number.",
      "",
      "    inc(1) #=> 2",
      "    x = inc(2)",
      "    inc(x) #=> 4",
      "\"\"\"",
      "def inc(n)",
      "  n + 1",
      "end"
    ]
  ),
  value("[true, true]"),
  doctests()
)

row(
  "docs.doctest.a_wrong_example_is_false",
  unlines(
    [
      "@doc \"\"\"",
      "inc adds one to a number.",
      "",
      "    inc(1) #=> 3",
      "\"\"\"",
      "def inc(n)",
      "  n + 1",
      "end"
    ]
  ),
  value("[false]"),
  doctests()
)

row(
  "docs.doc.documents_a_definition",
  unlines(["@doc \"\"\"", "x", "\"\"\"", "println(1)"]),
  fails(:parse, "documents the definition below it")
)

row(
  "docs.moduledoc.leads_the_file",
  unlines(["x = 1", "", "@moduledoc \"\"\"", "m", "\"\"\""]),
  fails(:parse, "first form")
)

row(
  "docs.B0056",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "def kagi()",
      "  1",
      "end"
    ]
  ),
  diagnoses(["B0056"]),
  covers("rule:B0056"),
  bidama("kagi")
)

row(
  "docs.B0057",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is one.",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end"
    ]
  ),
  diagnoses(["B0057"]),
  covers("rule:B0057"),
  bidama("kagi")
)

row(
  "docs.B0058",
  unlines(
    [
      "@doc \"\"\"",
      "kagi is one.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end"
    ]
  ),
  diagnoses(["B0058"]),
  covers("rule:B0058"),
  bidama("kagi")
)

row(
  "docs.B0059",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi: TODO",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end"
    ]
  ),
  diagnoses(["B0059"]),
  covers("rule:B0059"),
  bidama("kagi")
)

row(
  "docs.B0060",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is one.",
      "",
      "Returns: an Int.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end"
    ]
  ),
  diagnoses(["B0060"]),
  covers("rule:B0060"),
  bidama("kagi")
)

row(
  "docs.documented_bidama_is_clean",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is one.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end"
    ]
  ),
  diagnoses([]),
  bidama("kagi")
)

row(
  "docs.a_script_is_not_judged",
  unlines(["def kagi()", "  1", "end"]),
  diagnoses([])
)
