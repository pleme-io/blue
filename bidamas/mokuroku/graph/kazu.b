space("kazu", {status: :ratified})

verb(
  "kazu",
  "abs",
  {
    kind: :pure,
    shape: "abs(n) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "atan2",
  {
    kind: :pure,
    shape: "atan2(y, x) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "angle of a point from the x axis",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "ceil",
  {
    kind: :pure,
    shape: "ceil(n) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "least integer not below n",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "clamp",
  {
    kind: :pure,
    shape: "clamp(n, low, high) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "convert",
  {
    kind: :pure,
    shape: "convert(quantity, unit) -> quantity",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "a quantity in another unit of the same dimension",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kazu",
  "cos",
  {
    kind: :pure,
    shape: "cos(radians) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "cosine",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "dimension",
  {
    kind: :pure,
    shape: "dimension(expr) -> dimension",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "prove that units add up: meters plus seconds is refused",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kazu",
  "divmod",
  {
    kind: :pure,
    shape: "divmod(a, b) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "partial:kazu",
    meaning: "quotient and remainder; zero divisor raises",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "exp",
  {
    kind: :pure,
    shape: "exp(n) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "e raised to n",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "finite?",
  {
    kind: :pure,
    shape: "finite?(n) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a number is neither infinite nor NaN",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "floor",
  {
    kind: :pure,
    shape: "floor(n) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "greatest integer not above n",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "gcd",
  {
    kind: :pure,
    shape: "gcd(a, b) -> int",
    laterals: [],
    fleet: nil,
    today: "partial:kazu",
    meaning: "greatest common divisor",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "lcm",
  {
    kind: :pure,
    shape: "lcm(a, b) -> int",
    laterals: [],
    fleet: nil,
    today: "partial:kazu",
    meaning: "least common multiple",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "lerp",
  {
    kind: :pure,
    shape: "lerp(a, b, t) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "logarithm",
  {
    kind: :pure,
    shape: "logarithm(n, base) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "logarithm in a base; natural by default",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "max",
  {
    kind: :pure,
    shape: "max(a, b) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "min",
  {
    kind: :pure,
    shape: "min(a, b) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "mod",
  {
    kind: :pure,
    shape: "mod(a, b) -> int",
    laterals: ["error"],
    fleet: nil,
    today: "partial:kazu",
    meaning: "remainder that takes the sign of b",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "near?",
  {
    kind: :pure,
    shape: "near?(a, b, tolerance) -> Bool",
    laterals: [],
    fleet: nil,
    today: "partial:kazu",
    meaning: "whether two numbers differ by at most a tolerance",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "nth_root",
  {
    kind: :pure,
    shape: "nth_root(n, degree) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "n-th root",
    wave: 2,
    origin: "A"
  }
)

verb(
  "kazu",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, opts) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "text to integer or float; junk raises",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "pow",
  {
    kind: :pure,
    shape: "pow(base, exponent) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "product",
  {
    kind: :pure,
    shape: "product(numbers) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "quantity",
  {
    kind: :decl,
    shape: "quantity(n, unit) -> quantity",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "a number with a physical unit and dimension",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kazu",
  "render",
  {
    kind: :pure,
    shape: "render(n, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "number to text: fixed, scientific, percent, grouped",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "round",
  {
    kind: :pure,
    shape: "round(n, opts) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:kazu",
    meaning: "round to places by a named mode",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "signum",
  {
    kind: :pure,
    shape: "signum(n) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "sin",
  {
    kind: :pure,
    shape: "sin(radians) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "sine",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "sqrt",
  {
    kind: :pure,
    shape: "sqrt(n) -> number",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "square root; negative raises domain error",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "sum",
  {
    kind: :pure,
    shape: "sum(numbers) -> number",
    laterals: [],
    fleet: nil,
    today: "exists:kazu",
    wave: 0,
    origin: "A"
  }
)

verb(
  "kazu",
  "tan",
  {
    kind: :pure,
    shape: "tan(radians) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "tangent",
    wave: 1,
    origin: "A"
  }
)

verb(
  "kazu",
  "whole",
  {
    kind: :pure,
    shape: "whole(n) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "integer part of n, toward zero",
    wave: 1,
    origin: "A"
  }
)

edge("kazu::near?", :composes, "kazu::abs", "difference within tolerance")
edge("kazu::tan", :composes, "kazu::cos", "sin over cos")
edge("kazu::mod", :composes, "kazu::floor", "a minus b times floor")
edge("kazu::lcm", :composes, "kazu::gcd", "a times b over gcd")
edge("kazu::clamp", :composes, "kazu::max", "lower bound")
edge("kazu::clamp", :composes, "kazu::min", "upper bound")
edge("kazu::divmod", :composes, "kazu::mod", "quotient and remainder")
edge("kazu::nth_root", :composes, "kazu::pow", "exponent is 1/degree")
edge("kazu::tan", :composes, "kazu::sin", "sin over cos")
edge("kazu::round", :generalizes, "kazu::floor", "floor is a mode")
edge("kazu::dimension", :guards, "kazu::convert", "dimensions match")
edge("kazu::finite?", :guards, "kazu::parse", "reject NaN and infinity")
edge("kazu::logarithm", :inverse, "kazu::exp", "undoes exp")
edge("kazu::exp", :inverse, "kazu::logarithm", "undoes exp")
edge("kazu::render", :inverse, "kazu::parse", "text and number round-trip")
edge("kazu::parse", :inverse, "kazu::render", "text and number round-trip")
edge("kazu::floor", :pairs, "kazu::ceil", "round down and up")
edge("kazu::lerp", :pairs, "kazu::clamp", "t held in 0..1")
edge("kazu::sin", :pairs, "kazu::cos", "quarter-turn apart")
edge("kazu::gcd", :pairs, "kazu::lcm", "lcm uses gcd")
edge("kazu::exp", :pairs, "kazu::logarithm", "growth and its inverse")
edge("kazu::min", :pairs, "kazu::max", "the two ends")
edge("kazu::pow", :pairs, "kazu::nth_root", "power and inverse")
edge("kazu::sum", :pairs, "kazu::product", "add and multiply folds")
edge("kazu::abs", :pairs, "kazu::signum", "magnitude and direction")
edge("kazu::atan2", :pairs, "kazu::tan", "angle from slope")
edge("kazu::ceil", :pairs, "kazu::whole", "toward zero versus up")
edge("kazu::atan2", :pairs, "kikagaku::angle", "angle from components")
edge("kazu::round", :pairs, "seimitsu?::rescale", "float versus exact rounding")
edge("kazu::sqrt", :refines, "kazu::nth_root", "degree two")
edge("kazu::whole", :refines, "kazu::round", "mode toward zero")
edge("kazu::product", :refines, "retsu::reduce", "fold with multiply")
edge("kazu::sum", :refines, "retsu::reduce", "fold with add")
edge("kazu::quantity", :requires, "kazu::dimension", "units must add up")
edge("kazu::convert", :requires, "kazu::quantity", "between units")
