# Numbers: literals, the arithmetic operators, the numeric built-ins, and the
# okite decisions about them. Integer overflow is an error on every evaluator
# and in every build profile (G5, tatara-lisp-eval 0.3.64); it used to wrap in
# a release build and panic in a debug one.

row("numbers.int.literal", "42", value("42"), covers("form:42"))
row("numbers.int.underscores", "1_000_000", value("1000000"))
row("numbers.int.negative", "-7", value("-7"), covers("form:-x"))
row("numbers.float.literal", "3.5", value("3.5"), covers("form:3.5"))
row("numbers.float.keeps_point", "2.0", value("2.0"))
row("numbers.float.exponent", "1e3", value("1000.0"))
row("numbers.float.exponent.signed", "2.5e-3", value("0.0025"))
row("numbers.add", "1 + 2", value("3"), covers("op:+"))
row("numbers.add.mixed", "1 + 0.5", value("1.5"))
row("numbers.sub", "10 - 4", value("6"), covers("op:-"))
row("numbers.sub.left_assoc", "1 - 2 - 3", value("-4"))
row("numbers.mul", "6 * 7", value("42"), covers("op:*"))
row("numbers.precedence", "2 + 3 * 4", value("14"))
row("numbers.parens", "(2 + 3) * 4", value("20"))
row("numbers.div.float", "7 / 2", value("3.5"), covers("op:/", "okite:D0008"))
row("numbers.div.exact_stays_int", "6 / 2", value("3"))
row("numbers.div.quarter", "1 / 4", value("0.25"))
row("numbers.div.by_zero", "1 / 0", fails(:eval, "division by zero"))
row("numbers.mod", "7 % 3", value("1"), covers("op:%"))
row("numbers.mod.euclidean", "-7 % 3", value("2"))

row("numbers.overflow.mul", "9223372036854775807 * 2", fails(:eval, "overflow"))

row("numbers.to_int.out_of_range", "to_int(1e300)", value("nil"))

row(
  "numbers.to_int_bang.out_of_range",
  "to_int!(1e300)",
  fails(:eval, "overflow")
)

row(
  "numbers.overflow.catchable",
  "try(9223372036854775807 * 2, catch(_e(), :caught))",
  value(":caught")
)

row("numbers.overflow.add", "9223372036854775807 + 1", fails(:eval, "overflow"))

row(
  "numbers.overflow.sub",
  "0 - 9223372036854775807 - 2",
  fails(:eval, "overflow")
)

row(
  "numbers.overflow.abs",
  "abs(0 - 9223372036854775807 - 1)",
  fails(:eval, "overflow"),
  covers("builtin:abs")
)

row("numbers.lt", "1 < 2", value("true"), covers("op:<"))
row("numbers.le", "2 <= 2", value("true"), covers("op:<="))
row("numbers.gt", "3 > 2", value("true"), covers("op:>"))
row("numbers.ge", "3 >= 4", value("false"), covers("op:>="))

row(
  "numbers.lt.string_refused",
  "\"a\" < \"b\"",
  fails(:eval, "expected number")
)

row("numbers.abs", "abs(-3)", value("3"), covers("builtin:abs"))
row("numbers.abs.float", "abs(-2.5)", value("2.5"))
row("numbers.acos", "acos(1)", value("0.0"), covers("builtin:acos"))
row("numbers.asin", "asin(0)", value("0.0"), covers("builtin:asin"))
row("numbers.atan", "atan(0)", value("0.0"), covers("builtin:atan"))
row("numbers.atan2", "atan2(0, 1)", value("0.0"), covers("builtin:atan2"))
row("numbers.ceiling", "ceiling(2.1)", value("3"), covers("builtin:ceiling"))

row(
  "numbers.compare",
  "[compare(1, 2), compare(2, 2), compare(\"b\", \"a\")]",
  value("[-1, 0, 1]"),
  covers("builtin:compare")
)

row("numbers.cos", "cos(0)", value("1.0"), covers("builtin:cos"))
row("numbers.dec", "dec(5)", value("4"), covers("builtin:dec"))
row("numbers.exp", "exp(0)", value("1.0"), covers("builtin:exp"))
row("numbers.expt", "expt(2, 10)", value("1024"), covers("builtin:expt"))
row("numbers.floor", "floor(7 / 2)", value("3"), covers("builtin:floor"))
row("numbers.gcd", "gcd(12, 18)", value("6"), covers("builtin:gcd"))
row("numbers.hypot", "hypot(3, 4)", value("5.0"), covers("builtin:hypot"))
row("numbers.inc", "inc(5)", value("6"), covers("builtin:inc"))
row("numbers.lcm", "lcm(4, 6)", value("12"), covers("builtin:lcm"))
row("numbers.log", "log(1)", value("0.0"), covers("builtin:log"))
row("numbers.log.base", "log(8, 2)", value("3.0"))
row("numbers.max", "max(1, 5, 3)", value("5"), covers("builtin:max"))
row("numbers.min", "min(4, 2, 8)", value("2"), covers("builtin:min"))
row("numbers.mod.builtin", "mod(-7, 3)", value("2"), covers("builtin:mod"))
row("numbers.modulo", "modulo(-7, 3)", value("2"), covers("builtin:modulo"))
row("numbers.rem", "rem(-7, 3)", value("2"), covers("builtin:rem"))
row("numbers.round", "round(2.5)", value("3"), covers("builtin:round"))
row("numbers.sin", "sin(0)", value("0.0"), covers("builtin:sin"))
row("numbers.sqrt", "sqrt(16)", value("4.0"), covers("builtin:sqrt"))
row("numbers.tan", "tan(0)", value("0.0"), covers("builtin:tan"))
row("numbers.to_float", "to_float(3)", value("3.0"), covers("builtin:to_float"))
row("numbers.to_int", "to_int(3.9)", value("3"), covers("builtin:to_int"))
row("numbers.to_int.string", "to_int(\"42\")", value("42"))

row(
  "numbers.to_int_bang",
  "to_int!(\"12\")",
  value("12"),
  covers("builtin:to_int!")
)

row(
  "numbers.truncate",
  "truncate(-3.7)",
  value("-3"),
  covers("builtin:truncate")
)
