space("shinsuu", {status: :ratified})

verb(
  "shinsuu",
  "align",
  {
    kind: :pure,
    shape: "align(n, boundary) -> n",
    laterals: [],
    fleet: nil,
    today: "partial:shinsuu",
    meaning: "round up to a multiple of a boundary",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "bit_at",
  {
    kind: :pure,
    shape: "bit_at(n, i) -> 0 or 1",
    laterals: [],
    fleet: nil,
    today: "exists:shinsuu",
    wave: 0,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "checksum",
  {
    kind: :pure,
    shape: "checksum(data, algorithm) -> n",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "a CRC or Adler checksum of bytes, algorithm named",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "from_base",
  {
    kind: :pure,
    shape: "from_base(text, base) -> n",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:shinsuu",
    wave: 0,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "from_bytes",
  {
    kind: :pure,
    shape: "from_bytes(bytes, order) -> n",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "an integer read from bytes of either byte order",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "from_size",
  {
    kind: :pure,
    shape: "from_size(text) -> n",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "bytes read from text such as 10MiB",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "from_varint",
  {
    kind: :pure,
    shape: "from_varint(bytes) -> {value, rest}",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "read one variable-length integer from the front of bytes",
    wave: 2,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "luhn?",
  {
    kind: :pure,
    shape: "luhn?(n) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:shinsuu",
    wave: 0,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "popcount",
  {
    kind: :pure,
    shape: "popcount(n) -> n",
    laterals: [],
    fleet: nil,
    today: "exists:shinsuu",
    wave: 0,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "to_base",
  {
    kind: :pure,
    shape: "to_base(n, base) -> text",
    laterals: [],
    fleet: nil,
    today: "exists:shinsuu",
    wave: 0,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "to_bytes",
  {
    kind: :pure,
    shape: "to_bytes(n, width, order) -> bytes",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "an integer as fixed-width bytes, big or little endian",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "to_size",
  {
    kind: :pure,
    shape: "to_size(n) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "bytes written as text such as 4.2 GiB",
    wave: 1,
    origin: "B"
  }
)

verb(
  "shinsuu",
  "to_varint",
  {
    kind: :pure,
    shape: "to_varint(n) -> bytes",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "an integer in variable-length LEB128 bytes",
    wave: 2,
    origin: "B"
  }
)

edge(
  "shinsuu::checksum",
  :guards,
  "asshuku?::decompress",
  "frame check before use"
)

edge(
  "shinsuu::to_base",
  :inverse,
  "shinsuu::from_base",
  "text back to a number"
)

edge(
  "shinsuu::to_bytes",
  :inverse,
  "shinsuu::from_bytes",
  "bytes back to a number"
)

edge("shinsuu::to_size", :inverse, "shinsuu::from_size", "text back to bytes")

edge(
  "shinsuu::to_varint",
  :inverse,
  "shinsuu::from_varint",
  "bytes back to a number"
)

edge(
  "shinsuu::from_base",
  :inverse,
  "shinsuu::to_base",
  "text back to a number"
)

edge(
  "shinsuu::from_bytes",
  :inverse,
  "shinsuu::to_bytes",
  "bytes back to a number"
)

edge("shinsuu::from_size", :inverse, "shinsuu::to_size", "text back to bytes")

edge(
  "shinsuu::from_varint",
  :inverse,
  "shinsuu::to_varint",
  "bytes back to a number"
)

edge("shinsuu::to_bytes", :pairs, "asshuku?::pack", "archive header fields")
edge("shinsuu::align", :pairs, "fairu::space", "block rounding of sizes")
edge("shinsuu::to_size", :pairs, "fairu::usage", "prints what usage measures")

edge(
  "shinsuu::popcount",
  :pairs,
  "sakuin::distance",
  "hamming distance of bits"
)

edge(
  "shinsuu::from_size",
  :pairs,
  "settei::validate",
  "quota settings are sizes"
)

edge("shinsuu::popcount", :pairs, "shinsuu::bit_at", "bit counting and probing")
edge("shinsuu::align", :pairs, "shinsuu::to_size", "block sizes in storage")

edge(
  "shinsuu::checksum",
  :pairs,
  "shomei::hash",
  "cheap integrity beside strong"
)

edge("shinsuu::luhn?", :refines, "shinsuu::checksum", "one check-digit scheme")
edge("shinsuu::to_varint", :refines, "shinsuu::to_bytes", "variable width form")
