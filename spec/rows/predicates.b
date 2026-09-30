# Equality and the predicates: `==` is value equality (okite D0001), `!=` its
# negation (D0002), membership uses it (D0003), and every value has exactly one
# kind (D0010).

row("eq.numbers_by_value", "4 == 4.0", value("true"))

row(
  "eq.not_equal",
  "[1 != 2, 1 != 1.0]",
  value("[true, false]"),
  covers("op:!=", "okite:D0002")
)

row("eq.nil_only_nil", "[nil == false, nil == nil]", value("[false, true]"))

row(
  "eq.functions_by_identity",
  "f = fn(x) x end\ng = fn(x) x end\n[f == f, f == g]",
  value("[true, false]"),
  pending("G18", "vm")
)

row("eq.equal_p", "equal?([1], [1.0])", value("true"), covers("builtin:equal?"))
row("eq.eq_p", "eq?(:a, :a)", value("true"), covers("builtin:eq?"))

row(
  "pred.one_kind",
  "[nil?(nil), bool?(true), integer?(1), float?(1.0), string?(\"s\"), keyword?(:k), list?([]), map?({})]",
  value("[true, true, true, true, true, true, true, true]"),
  covers(
    "builtin:nil?",
    "builtin:bool?",
    "builtin:integer?",
    "builtin:float?",
    "builtin:string?",
    "builtin:keyword?"
  )
)

row(
  "pred.integer_not_float",
  "[integer?(1.0), float?(1)]",
  value("[false, false]")
)

row("pred.atom", "atom?(1)", value("true"), covers("builtin:atom?"))

row(
  "pred.boolean",
  "boolean?(false)",
  value("true"),
  covers("builtin:boolean?")
)

row("pred.cast", "cast(:int, 3)", value("3"), covers("builtin:cast"))

row(
  "pred.chan",
  "chan?(chan())",
  value("true"),
  covers("builtin:chan?", "builtin:chan")
)

row(
  "pred.empty",
  "[empty?([]), empty?([1])]",
  value("[true, false]"),
  covers("builtin:empty?")
)

row("pred.even", "even?(4)", value("true"), covers("builtin:even?"))
row("pred.foreign", "foreign?(1)", value("false"), covers("builtin:foreign?"))
row("pred.go", "go?(1)", value("false"), covers("builtin:go?"))
row("pred.is", "is?(3, :int)", value("true"), covers("builtin:is?"))

row(
  "pred.negative",
  "negative?(-1)",
  value("true"),
  covers("builtin:negative?")
)

row("pred.null", "null?(nil)", value("true"), covers("builtin:null?"))

row(
  "pred.number",
  "[number?(1), number?(1.5), number?(\"1\")]",
  value("[true, true, false]"),
  covers("builtin:number?")
)

row("pred.odd", "odd?(3)", value("true"), covers("builtin:odd?"))
row("pred.pair", "pair?([1])", value("true"), covers("builtin:pair?"))

row(
  "pred.positive",
  "positive?(0)",
  value("false"),
  covers("builtin:positive?")
)

row(
  "pred.procedure",
  "[procedure?(fn(x) x end), procedure?(1)]",
  value("[true, false]"),
  covers("builtin:procedure?"),
  pending("G18", "vm")
)

row(
  "pred.promise",
  "promise?(delay(1))",
  value("true"),
  covers("builtin:promise?", "builtin:delay")
)

row(
  "pred.some",
  "[some?(nil), some?(0)]",
  value("[false, true]"),
  covers("builtin:some?")
)

row("pred.symbol", "symbol?(:k)", value("false"), covers("builtin:symbol?"))
row("pred.the", "the(:int, 3)", value("3"), covers("builtin:the"))
row("pred.zero", "zero?(0)", value("true"), covers("builtin:zero?"))
# A symbol may end in `?` or `!`, as a name may, so an import list can name
# a predicate: `use("nisshi", [:pair?])`.
row("pred.keyword_bang", "[:done!, :pair?]", value("[:done!, :pair?]"))
row("pred.type_of", "type_of(1)", value(":int"), pending("G12"))
