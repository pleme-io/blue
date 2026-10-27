# Macros: defmacro, quote, unquote and unquote_splice. A macro rewrites its
# unevaluated form. Hygiene and a bounded, host-free expansion phase are the
# destination (G3); those rows are pending.

row(
  "macros.expand",
  join_lines(
    [
      "defmacro double(x)",
      "  quote",
      "    unquote(x) + unquote(x)",
      "  end",
      "end",
      "",
      "double(21)"
    ]
  ),
  value("42"),
  covers("keyword:defmacro", "keyword:quote", "keyword:unquote"),
  covers("builtin:quasiquote")
)

row(
  "macros.operates_on_the_form",
  join_lines(
    [
      "defmacro square(e)",
      "  quote",
      "    unquote(e) * unquote(e)",
      "  end",
      "end",
      "",
      "square(2 + 3)"
    ]
  ),
  value("25")
)

row(
  "macros.compose",
  join_lines(
    [
      "defmacro double(x)",
      "  quote",
      "    unquote(x) + unquote(x)",
      "  end",
      "end",
      "",
      "double(double(5))"
    ]
  ),
  value("20")
)

row(
  "macros.splice",
  join_lines(
    [
      "defmacro sum_of(xs)",
      "  quote",
      "    length([unquote_splice(xs)])",
      "  end",
      "end",
      "",
      "sum_of([1, 2, 3])"
    ]
  ),
  value("4"),
  covers("keyword:unquote_splice")
)

row(
  "macros.quote_is_data",
  join_lines(["quote", "  f(1)", "end"]),
  value("[f, 1]")
)

row(
  "macros.macroexpand",
  join_lines(
    [
      "defmacro twice(x)",
      "  quote",
      "    unquote(x) + unquote(x)",
      "  end",
      "end",
      "",
      "macroexpand(quote",
      "  twice(1)",
      "end)"
    ]
  ),
  value("[+, 1, 1]"),
  covers("builtin:macroexpand")
)

row(
  "macros.hygiene",
  join_lines(
    [
      "defmacro twice(e)",
      "  quote",
      "    x = unquote(e)",
      "    x + x",
      "  end",
      "end",
      "",
      "x = 10",
      "y = twice(x + 1)",
      "x"
    ]
  ),
  value("10"),
  pending("G3")
)

row(
  "macros.no_host_at_expansion",
  join_lines(
    ["defmacro peek()", "  read_file(\"/etc/hosts\")", "end", "", "peek()"]
  ),
  fails(:eval, "capability"),
  pending("G3"),
  host()
)

row(
  "macros.generated_names_are_seen",
  join_lines(
    [
      "defmacro field(name, i)",
      "  quote",
      "    def unquote(name)(xs)",
      "      nth(unquote(i), xs)",
      "    end",
      "  end",
      "end",
      "",
      "field(px, 0)",
      "px([7, 8])"
    ]
  ),
  value("7"),
  pending("G3")
)
