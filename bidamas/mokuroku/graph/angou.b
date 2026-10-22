space("angou", {status: :ratified})

verb(
  "angou",
  "bezout",
  {
    kind: :pure,
    shape: "bezout(a, b) -> record",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "gcd with the coefficients that build it",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "crack",
  {
    kind: :pure,
    shape: "crack(text, cipher) -> [candidate]",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:angou",
    meaning: "plaintext guesses ranked by letter frequency",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "crt",
  {
    kind: :pure,
    shape: "crt(congruences) -> int",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:angou",
    meaning: "number matching several remainders at once",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "decipher",
  {
    kind: :pure,
    shape: "decipher(text, key, cipher) -> text",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "classical cipher backward",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "divisors",
  {
    kind: :pure,
    shape: "divisors(n) -> [int]",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "every divisor in ascending order",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "encipher",
  {
    kind: :pure,
    shape: "encipher(text, key, cipher) -> text",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "classical cipher forward: caesar, vigenere, atbash, rail fence, substitution",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "factor",
  {
    kind: :pure,
    shape: "factor(n) -> [int]",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "prime factors with multiplicity",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "frequency",
  {
    kind: :pure,
    shape: "frequency(text) -> [count]",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "letter counts a to z, case folded",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "inverse_mod",
  {
    kind: :pure,
    shape: "inverse_mod(a, modulus) -> int or nil",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "multiplicative inverse, nil when none exists",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "period",
  {
    kind: :pure,
    shape: "period(a, modulus) -> int",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "smallest power of a that equals one",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "power_mod",
  {
    kind: :pure,
    shape: "power_mod(base, exponent, modulus) -> int",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "modular exponentiation by repeated squaring",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "prime?",
  {
    kind: :pure,
    shape: "prime?(n) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "n is prime by trial division",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "primitive_root",
  {
    kind: :pure,
    shape: "primitive_root(prime) -> int",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "smallest generator of the units modulo a prime",
    wave: 0,
    origin: "D"
  }
)

verb(
  "angou",
  "totient",
  {
    kind: :pure,
    shape: "totient(n) -> int",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:angou",
    meaning: "count of integers below n coprime to it",
    wave: 0,
    origin: "D"
  }
)

edge(
  "angou::inverse_mod",
  :composes,
  "angou::bezout",
  "coefficient of the extended gcd"
)

edge("angou::crack", :composes, "angou::decipher", "try every key")
edge("angou::divisors", :composes, "angou::factor", "products of prime powers")
edge("angou::totient", :composes, "angou::factor", "product over prime factors")

edge(
  "angou::crack",
  :composes,
  "angou::frequency",
  "score candidates by letter counts"
)

edge(
  "angou::crt",
  :composes,
  "angou::inverse_mod",
  "combine congruences with inverses"
)

edge(
  "angou::primitive_root",
  :composes,
  "angou::period",
  "order equals totient"
)

edge("angou::period", :composes, "angou::power_mod", "try powers until one")
edge("angou::factor", :composes, "angou::prime?", "trial division by primes")

edge(
  "angou::power_mod",
  :composes,
  "angou::totient",
  "exponent reduces modulo totient"
)

edge(
  "angou::bezout",
  :generalizes,
  "angou::inverse_mod",
  "inverse is one coefficient"
)

edge("angou::encipher", :inverse, "angou::decipher", "undoes the same cipher")
edge("angou::decipher", :inverse, "angou::encipher", "undoes the same cipher")

edge(
  "angou::prime?",
  :refines,
  "angou::factor",
  "prime when only itself factors"
)

edge(
  "angou::frequency",
  :requires,
  "angou::encipher",
  "statistics break classical ciphers"
)

edge("angou::period", :requires, "angou::totient", "divides the totient")
