# Strings: literals, escapes, interpolation, and the text built-ins.

row("strings.literal", "\"text\"", value("\"text\""), covers("form:\"text\""))
row("strings.escapes", "\"a\\tb\\n\"", value("\"a\\tb\\n\""))
row("strings.unicode_escape", "\"\\u{41}\"", value("\"A\""))

row(
  "strings.interpolation",
  "n = 3\n\"n = #\u{7b}n}!\"",
  value("\"n = 3!\""),
  covers("form:\"n = #\u{7b}n}!\"")
)

row(
  "strings.interpolation.to_s",
  "\"#\u{7b}[1, 2]} #\u{7b}nil} #\u{7b}1.0}\"",
  value("\"[1, 2]  1.0\""),
  covers("okite:D0006")
)

row("strings.equality", "\"ab\" == \"ab\"", value("true"))

row(
  "strings.chars",
  "chars(\"ab\")",
  value("[\"a\", \"b\"]"),
  covers("builtin:chars")
)

row(
  "strings.concat",
  "concat(\"a\", \"b\", \"c\")",
  value("\"abc\""),
  covers("builtin:concat"),
  covers("okite:D0007")
)

row("strings.concat.one", "concat(\"a\")", value("\"a\""))
row("strings.concat.renders", "concat(\"n\", 1, nil, 2.5)", value("\"n12.5\""))

row(
  "strings.contains",
  "contains?(\"hello\", \"ell\")",
  value("true"),
  covers("builtin:contains?")
)

row(
  "strings.downcase",
  "downcase(\"AbC\")",
  value("\"abc\""),
  covers("builtin:downcase")
)

row(
  "strings.ends_with",
  "ends_with?(\"file.b\", \".b\")",
  value("true"),
  covers("builtin:ends_with?")
)

row(
  "strings.join",
  "join([\"a\", \"b\"], \", \")",
  value("\"a, b\""),
  covers("builtin:join")
)

row(
  "strings.replace",
  "replace(\"a-b-c\", \"-\", \"+\")",
  value("\"a+b+c\""),
  covers("builtin:replace")
)

row(
  "strings.split",
  "split(\"a,b,,\", \",\")",
  value("[\"a\", \"b\", \"\", \"\"]"),
  covers("builtin:split"),
  covers("okite:D0012")
)

row("strings.split.empty", "split(\"\", \",\")", value("[\"\"]"))

row(
  "strings.split.join_undoes",
  "join(split(\"x|y\", \"|\"), \"|\")",
  value("\"x|y\"")
)

row(
  "strings.starts_with",
  "starts_with?(\"blue\", \"bl\")",
  value("true"),
  covers("builtin:starts_with?")
)

row("strings.string", "string(42)", value("\"42\""), covers("builtin:string"))

row(
  "strings.to_s.string",
  "to_s(\"a b\")",
  value("\"a b\""),
  covers("builtin:to_s"),
  covers("okite:D0005")
)

row("strings.to_s.nil", "to_s(nil)", value("\"\""))
row("strings.to_s.float", "to_s(1.0)", value("\"1.0\""))

row(
  "strings.to_s.list",
  "to_s([1, \"a\", nil, 2.0])",
  value("\"[1, \\\"a\\\", nil, 2.0]\"")
)

row(
  "strings.to_s.map_sorted",
  "to_s({b: 2, a: [1]})",
  value("\"{a: [1], b: 2}\"")
)

row("strings.trim", "trim(\"  x  \")", value("\"x\""), covers("builtin:trim"))

row(
  "strings.upcase",
  "upcase(\"abc\")",
  value("\"ABC\""),
  covers("builtin:upcase")
)

row("strings.multibyte", "chars(\"日本\")", value("[\"日\", \"本\"]"))
row("strings.no_index", "y = \"ab\"[0]", fails(:parse, "indexing"))
