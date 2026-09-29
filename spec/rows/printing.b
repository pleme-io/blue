# Terminal output, observed through the `blue` binary: write_stdout is exact;
# println and friends print the Lisp rendering. One canonical rendering for
# every printer is the destination (G12).

row(
  "output.write_stdout",
  "write_stdout(\"hi\")",
  prints("hi"),
  covers("builtin:write_stdout")
)

row(
  "output.write_stdout.no_newline",
  "write_stdout(\"a\")\nwrite_stdout(\"b\\n\")",
  prints("ab\n")
)

row(
  "output.write_stderr",
  "write_stderr(\"to stderr\")",
  prints(""),
  covers("builtin:write_stderr")
)

row(
  "output.println",
  "println(\"a\", 1)",
  prints("\"a\" 1\n"),
  covers("builtin:println")
)

row("output.println.float", "println(1.0)", prints("1.0\n"), pending("G12"))
row("output.println.map", "println({a: 1})", prints("{a: 1}\n"), pending("G12"))
row("output.println.nil", "println(nil)", prints("nil\n"), pending("G12"))

row(
  "output.display",
  "display([1, \"a\"])",
  prints("[1, \"a\"]"),
  covers("builtin:display"),
  pending("G12")
)

row("output.print", "print(\"x\")", prints("\"x\"\n"), covers("builtin:print"))
row("output.newline", "newline()", prints("\n"), covers("builtin:newline"))
row("output.quiet_drops_value", "42", prints(""))
