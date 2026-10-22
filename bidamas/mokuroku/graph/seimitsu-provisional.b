space("seimitsu?", {status: :provisional})

verb(
  "seimitsu?",
  "big",
  {
    kind: :pure,
    shape: "big(value) -> big",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "integer without a size limit",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "decimal",
  {
    kind: :pure,
    shape: "decimal(text, opts) -> decimal",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "exact base-ten number with a scale",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "denominator",
  {
    kind: :pure,
    shape: "denominator(ratio) -> big",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "bottom of a fraction",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "exact",
  {
    kind: :pure,
    shape: "exact(float) -> ratio",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the exact fraction a float stores",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "mod_pow",
  {
    kind: :pure,
    shape: "mod_pow(base, exponent, modulus) -> big",
    laterals: [],
    fleet: nil,
    today: "exists:angou",
    meaning: "power modulo a number without overflow",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "numerator",
  {
    kind: :pure,
    shape: "numerator(ratio) -> big",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "top of a fraction",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "places",
  {
    kind: :pure,
    shape: "places(decimal) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "digits after the decimal point",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "ratio",
  {
    kind: :pure,
    shape: "ratio(numerator, denominator) -> ratio",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "exact fraction in lowest terms",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "rescale",
  {
    kind: :pure,
    shape: "rescale(decimal, places, mode) -> decimal",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "decimal with a new scale by a rounding mode",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "to_float",
  {
    kind: :pure,
    shape: "to_float(number) -> float",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "nearest float of an exact number",
    wave: 3,
    origin: "A"
  }
)

verb(
  "seimitsu?",
  "to_int",
  {
    kind: :pure,
    shape: "to_int(number, mode) -> big",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "whole number by a rounding mode",
    wave: 3,
    origin: "A"
  }
)

edge("seimitsu?::big", :guards, "seimitsu?::mod_pow", "exact exponent math")

edge(
  "seimitsu?::to_float",
  :inverse,
  "seimitsu?::exact",
  "float and its exact value"
)

edge(
  "seimitsu?::exact",
  :inverse,
  "seimitsu?::to_float",
  "float and its exact value"
)

edge("seimitsu?::to_float", :pairs, "kazu::parse", "exact to inexact")
edge("seimitsu?::numerator", :pairs, "seimitsu?::denominator", "the two halves")
edge("seimitsu?::ratio", :pairs, "seimitsu?::numerator", "top of the fraction")

edge(
  "seimitsu?::decimal",
  :pairs,
  "seimitsu?::places",
  "digits and their count"
)

edge(
  "seimitsu?::decimal",
  :pairs,
  "seimitsu?::ratio",
  "base ten and base n exact numbers"
)

edge(
  "seimitsu?::places",
  :pairs,
  "seimitsu?::rescale",
  "read and change the scale"
)

edge("seimitsu?::big", :pairs, "seimitsu?::to_int", "build and convert")
edge("seimitsu?::rescale", :refines, "kazu::round", "round to places")
edge("seimitsu?::to_int", :refines, "kazu::round", "round to a whole number")

edge(
  "seimitsu?::decimal",
  :requires,
  "seimitsu?::big",
  "digits are a big integer"
)

edge(
  "seimitsu?::mod_pow",
  :requires,
  "seimitsu?::big",
  "operands exceed 64 bits"
)

edge("seimitsu?::ratio", :requires, "seimitsu?::big", "parts are big integers")
