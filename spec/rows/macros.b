# Macros: defmacro, quote, unquote and unquote_splice. A macro rewrites its
# unevaluated form. Hygiene and a bounded, host-free expansion phase are the
# destination (G3); those rows are pending.

row(
  "macros.expand",
  "defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\n\ndouble(21)",
  value("42"),
  covers("keyword:defmacro", "keyword:quote", "keyword:unquote"),
  covers("builtin:quasiquote")
)

row(
  "macros.operates_on_the_form",
  "defmacro square(e)\n  quote\n    unquote(e) * unquote(e)\n  end\nend\n\nsquare(2 + 3)",
  value("25")
)

row(
  "macros.compose",
  "defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\n\ndouble(double(5))",
  value("20")
)

row(
  "macros.splice",
  "defmacro sum_of(xs)\n  quote\n    length([unquote_splice(xs)])\n  end\nend\n\nsum_of([1, 2, 3])",
  value("4"),
  covers("keyword:unquote_splice")
)

row("macros.quote_is_data", "quote\n  f(1)\nend", value("[f, 1]"))

row(
  "macros.macroexpand",
  "defmacro twice(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\n\nmacroexpand(quote\n  twice(1)\nend)",
  value("[+, 1, 1]"),
  covers("builtin:macroexpand")
)

row(
  "macros.hygiene",
  "defmacro twice(e)\n  quote\n    x = unquote(e)\n    x + x\n  end\nend\n\nx = 10\ny = twice(x + 1)\nx",
  value("10"),
  pending("G3")
)

row(
  "macros.no_host_at_expansion",
  "defmacro peek()\n  read_file(\"/etc/hosts\")\nend\n\npeek()",
  fails(:eval, "capability"),
  pending("G3"),
  host()
)

row(
  "macros.generated_names_are_seen",
  "defmacro field(name, i)\n  quote\n    def unquote(name)(xs)\n      nth(unquote(i), xs)\n    end\n  end\nend\n\nfield(px, 0)\npx([7, 8])",
  value("7"),
  pending("G3")
)
