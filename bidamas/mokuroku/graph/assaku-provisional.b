space("assaku?", {status: :provisional})

verb(
  "assaku?",
  "append",
  {
    kind: :effect,
    shape: "append(archive, entries) -> nil",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "add entries to an archive",
    wave: 3,
    origin: "A"
  }
)

verb(
  "assaku?",
  "compress",
  {
    kind: :pure,
    shape: "compress(bytes, algorithm, opts) -> bytes",
    laterals: ["error"],
    fleet: "caixa-flate2",
    today: "absent",
    meaning: "bytes shrunk by gzip, zstd, xz or deflate",
    wave: 3,
    origin: "A"
  }
)

verb(
  "assaku?",
  "decompress",
  {
    kind: :pure,
    shape: "decompress(bytes, algorithm, opts) -> bytes",
    laterals: ["error", "resource"],
    fleet: "caixa-flate2",
    today: "absent",
    meaning: "compressed bytes back to the original",
    wave: 3,
    origin: "A"
  }
)

verb(
  "assaku?",
  "detect",
  {
    kind: :pure,
    shape: "detect(bytes) -> algorithm or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "which codec a header announces",
    wave: 3,
    origin: "A"
  }
)

verb(
  "assaku?",
  "list",
  {
    kind: :effect,
    shape: "list(archive) -> [entry]",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "names, sizes and kinds inside an archive",
    wave: 3,
    origin: "A"
  }
)

verb(
  "assaku?",
  "pack",
  {
    kind: :effect,
    shape: "pack(path, entries, opts) -> nil",
    laterals: ["capability", "error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "write a tar or zip archive of named entries",
    wave: 3,
    origin: "A"
  }
)

verb(
  "assaku?",
  "ratio",
  {
    kind: :pure,
    shape: "ratio(bytes, algorithm) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "compressed size over original size",
    wave: 3,
    origin: "A"
  }
)

verb(
  "assaku?",
  "read",
  {
    kind: :effect,
    shape: "read(archive, entry) -> bytes",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "one entry's content",
    wave: 3,
    origin: "A",
    contract: "read(archive, opts) -> bytes"
  }
)

verb(
  "assaku?",
  "stream",
  {
    kind: :stream,
    shape: "stream(source, algorithm, f, opts) -> nil",
    laterals: ["cancel", "error", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "compress or decompress chunk by chunk",
    wave: 4,
    origin: "A"
  }
)

verb(
  "assaku?",
  "unpack",
  {
    kind: :effect,
    shape: "unpack(archive, destination, opts) -> [path]",
    laterals: ["capability", "error", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "unpack entries; paths that escape the target raise",
    wave: 3,
    origin: "A"
  }
)

verb(
  "assaku?",
  "verify",
  {
    kind: :pure,
    shape: "verify(archive) -> nil",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "check checksums and structure",
    wave: 3,
    origin: "A"
  }
)

edge(
  "assaku?::pack",
  :composes,
  "assaku?::compress",
  "entries compressed into the archive"
)

edge(
  "assaku?::ratio",
  :composes,
  "assaku?::compress",
  "compressed size over original"
)

edge("assaku?::unpack", :composes, "assaku?::decompress", "inflate each entry")
edge("assaku?::read", :composes, "assaku?::list", "entry must be listed")
edge("assaku?::unpack", :composes, "assaku?::read", "write each entry out")
edge("assaku?::pack", :composes, "fairu::write", "archive file is written")
edge("assaku?::unpack", :composes, "fairu::write", "entries become files")
edge("assaku?::verify", :composes, "shomei::hash", "checksum per entry")
edge("assaku?::detect", :guards, "assaku?::decompress", "pick the codec first")
edge("assaku?::list", :guards, "assaku?::unpack", "inspect before unpacking")
edge("assaku?::verify", :guards, "assaku?::unpack", "check before unpacking")
edge("assaku?::decompress", :inverse, "assaku?::compress", "bytes round-trip")
edge("assaku?::compress", :inverse, "assaku?::decompress", "bytes round-trip")

edge(
  "assaku?::unpack",
  :inverse,
  "assaku?::pack",
  "archive and files round-trip"
)

edge(
  "assaku?::pack",
  :inverse,
  "assaku?::unpack",
  "archive and files round-trip"
)

edge("assaku?::stream", :lifts, "assaku?::compress", "chunked form")
edge("assaku?::stream", :lifts, "assaku?::decompress", "chunked form")
edge("assaku?::list", :pairs, "assaku?::read", "names then content")
edge("assaku?::compress", :pairs, "deeta::pack", "compress after serializing")
edge("assaku?::append", :refines, "assaku?::pack", "add to an existing archive")

edge(
  "assaku?::read",
  :refines,
  "fairu::read",
  "an entry is a file in an archive"
)
