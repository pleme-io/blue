# Parse errors that name the fix: the parser refuses the shapes Ruby and
# Elixir authors reach for and says what blue writes instead. Every evaluator
# stops at the same stage with the same message.

row(
  "parse.command_call",
  "a = f x",
  fails(:parse, "a call needs parentheses: write `f(x)`")
)

row(
  "parse.then",
  "x = if c then 1 else 2 end",
  fails(:parse, "blue's `if` has no `then`")
)

row("parse.semicolon", "x = 1\ny = 2; z = 3", fails(:parse, "new line"))
row("parse.unterminated", "if a\n  1", fails(:parse, "unterminated"))

row(
  "parse.brace_block",
  "xs.each { |x| x }",
  fails(:parse, "blue has no brace blocks")
)

row(
  "parse.keyword_rebind",
  "if = 1",
  fails(:parse, "expected an expression, found `=`")
)

row("parse.def_needs_name", "def", fails(:parse, "expected a name after `def`"))
row("parse.interpolation", "\"#\u{7b}1 +}\"", fails(:parse, "in interpolation"))

row(
  "parse.stray_end",
  "end",
  fails(:parse, "nothing open here for it to close")
)

row("parse.keyword_literal", ":done", value(":done"), covers("form::done"))

row(
  "parse.test_blocks_ignored_by_run",
  "test \"never runs here\"\n  assert 1 == 2\nend\n\n:ran",
  value(":ran"),
  covers("keyword:test", "keyword:assert")
)

row(
  "parse.qualified_name",
  "sp_mod::sp_twice",
  fails(:check, "B0001"),
  pending("namespaces")
)
