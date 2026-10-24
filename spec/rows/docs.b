# Documentation: `@doc` and `@moduledoc` are typed children of the tree that
# leave the program's meaning alone, have one formatting, and whose examples
# run as tests on every evaluator.

row(
  "docs.doc.documents_a_def",
  "@doc \"\"\"\ninc adds one to a number.\n\n    inc(1) #=> 2\n\"\"\"\ndef inc(n)\n  n + 1\nend\n\ninc(41)\n",
  value("42"),
  covers(
    "form:@doc \"\"\"\ninc adds one to a number.\n\n    inc(1) #=> 2\n\"\"\"\ndef inc(n)\n  n + 1\nend"
  )
)

row(
  "docs.moduledoc.documents_a_file",
  "@moduledoc \"\"\"\nm holds one value.\n\n    x #=> 1\n\"\"\"\n\nx = 1\nx\n",
  value("1"),
  covers(
    "form:@moduledoc \"\"\"\nkazu holds the number verbs.\n\n    kazu::clamp(9, 1, 5) #=> 5\n\"\"\""
  )
)

row(
  "docs.doc.one_formatting",
  "@doc   \"\"\"\n    inc adds one.   \n\n        inc(1) #=> 2\n    \"\"\"\n\ndef inc(n)\n  n + 1\nend\n",
  formats(
    "@doc \"\"\"\ninc adds one.\n\n    inc(1) #=> 2\n\"\"\"\ndef inc(n)\n  n + 1\nend\n"
  )
)

row(
  "docs.doctest.examples_hold",
  "@doc \"\"\"\ninc adds one to a number.\n\n    inc(1) #=> 2\n    x = inc(2)\n    inc(x) #=> 4\n\"\"\"\ndef inc(n)\n  n + 1\nend\n",
  value("[true, true]"),
  doctests()
)

row(
  "docs.doctest.a_wrong_example_is_false",
  "@doc \"\"\"\ninc adds one to a number.\n\n    inc(1) #=> 3\n\"\"\"\ndef inc(n)\n  n + 1\nend\n",
  value("[false]"),
  doctests()
)

row(
  "docs.doc.documents_a_definition",
  "@doc \"\"\"\nx\n\"\"\"\nprintln(1)\n",
  fails(:parse, "documents the definition below it")
)

row(
  "docs.moduledoc.leads_the_file",
  "x = 1\n\n@moduledoc \"\"\"\nm\n\"\"\"\n",
  fails(:parse, "first form")
)

row(
  "docs.B0056",
  "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\ndef kagi()\n  1\nend\n",
  diagnoses(["B0056"]),
  covers("rule:B0056"),
  bidama("kagi")
)

row(
  "docs.B0057",
  "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\n@doc \"\"\"\nkagi is one.\n\"\"\"\ndef kagi()\n  1\nend\n",
  diagnoses(["B0057"]),
  covers("rule:B0057"),
  bidama("kagi")
)

row(
  "docs.B0058",
  "@doc \"\"\"\nkagi is one.\n\n    kagi #=> 1\n\"\"\"\ndef kagi()\n  1\nend\n",
  diagnoses(["B0058"]),
  covers("rule:B0058"),
  bidama("kagi")
)

row(
  "docs.B0059",
  "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\n@doc \"\"\"\nkagi: TODO\n\n    kagi #=> 1\n\"\"\"\ndef kagi()\n  1\nend\n",
  diagnoses(["B0059"]),
  covers("rule:B0059"),
  bidama("kagi")
)

row(
  "docs.B0060",
  "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\n@doc \"\"\"\nkagi is one.\n\nReturns: an Int.\n\n    kagi #=> 1\n\"\"\"\ndef kagi()\n  1\nend\n",
  diagnoses(["B0060"]),
  covers("rule:B0060"),
  bidama("kagi")
)

row(
  "docs.documented_bidama_is_clean",
  "@moduledoc \"\"\"\nkagi holds one value.\n\n    kagi #=> 1\n\"\"\"\n\n@doc \"\"\"\nkagi is one.\n\n    kagi #=> 1\n\"\"\"\ndef kagi()\n  1\nend\n",
  diagnoses([]),
  bidama("kagi")
)

row(
  "docs.a_script_is_not_judged",
  "def kagi()\n  1\nend\n",
  diagnoses([])
)
