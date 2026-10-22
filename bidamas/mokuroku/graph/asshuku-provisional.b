space("asshuku?", {status: :provisional})

verb(
  "asshuku?",
  "append",
  {
    kind: :pure,
    shape: "append(archive, entries) -> bytes",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "add entries to the end of an archive",
    wave: 3,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "archive",
  {
    kind: :effect,
    shape: "archive(root, to, opts) -> nil",
    laterals: ["capability", "deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "pack a directory tree into an archive file",
    wave: 2,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "compress",
  {
    kind: :pure,
    shape: "compress(data, opts) -> bytes",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "shrink bytes with an algorithm named in opts",
    wave: 2,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "decompress",
  {
    kind: :pure,
    shape: "decompress(data, opts) -> bytes",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "restore bytes, refusing output past a size limit",
    wave: 2,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "delta",
  {
    kind: :pure,
    shape: "delta(base, target) -> bytes",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a binary difference that turns base into target",
    wave: 3,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "detect",
  {
    kind: :pure,
    shape: "detect(data) -> algorithm or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "name the compression or archive format from magic bytes",
    wave: 2,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "list",
  {
    kind: :pure,
    shape: "list(archive, opts) -> [{name, size, mode}]",
    laterals: ["error"],
    fleet: "hozon",
    today: "absent",
    meaning: "the entry headers of an archive without their content",
    wave: 2,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "pack",
  {
    kind: :pure,
    shape: "pack(entries, opts) -> bytes",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "bundle named entries into one tar or zip archive",
    wave: 2,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "patch",
  {
    kind: :pure,
    shape: "patch(base, delta) -> bytes",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "apply a binary delta to base",
    wave: 3,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "read",
  {
    kind: :pure,
    shape: "read(archive, name, opts) -> bytes",
    laterals: ["error"],
    fleet: "hozon",
    today: "absent",
    meaning: "one entry of an archive by name",
    wave: 2,
    origin: "B",
    contract: "read(archive, opts) -> bytes"
  }
)

verb(
  "asshuku?",
  "stream",
  {
    kind: :stream,
    shape: "stream(source, f, opts) -> nil",
    laterals: ["cancel", "deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "compress or decompress chunk by chunk, calling f per chunk",
    wave: 3,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "unpack",
  {
    kind: :pure,
    shape: "unpack(archive, opts) -> [entry]",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "every entry of an archive in memory, paths checked",
    wave: 2,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "unpack_to",
  {
    kind: :effect,
    shape: "unpack_to(archive, to, opts) -> [path]",
    laterals: ["capability", "error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "write an archive under a directory; traversal refused",
    wave: 2,
    origin: "B"
  }
)

verb(
  "asshuku?",
  "verify?",
  {
    kind: :pure,
    shape: "verify?(archive) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "whether every entry of an archive decodes and checks",
    wave: 2,
    origin: "B"
  }
)

edge("asshuku?::pack", :composes, "asshuku?::compress", "archive then compress")

edge(
  "asshuku?::unpack",
  :composes,
  "asshuku?::decompress",
  "decompress then split"
)

edge("asshuku?::archive", :composes, "asshuku?::pack", "packs the walked files")
edge("asshuku?::unpack_to", :composes, "asshuku?::unpack", "entries to write")
edge("asshuku?::verify?", :composes, "asshuku?::unpack", "decodes every entry")
edge("asshuku?::archive", :composes, "fairu::walk", "finds the files")
edge("asshuku?::unpack_to", :composes, "fairu::write", "writes each entry")

edge(
  "asshuku?::verify?",
  :composes,
  "shinsuu::checksum",
  "checks entry checksums"
)

edge(
  "asshuku?::detect",
  :guards,
  "asshuku?::decompress",
  "pick the algorithm first"
)

edge(
  "asshuku?::verify?",
  :guards,
  "asshuku?::unpack_to",
  "check before writing files"
)

edge(
  "asshuku?::unpack_to",
  :inverse,
  "asshuku?::archive",
  "tree back from the archive"
)

edge(
  "asshuku?::decompress",
  :inverse,
  "asshuku?::compress",
  "restores the original bytes"
)

edge(
  "asshuku?::compress",
  :inverse,
  "asshuku?::decompress",
  "restores the original bytes"
)

edge("asshuku?::patch", :inverse, "asshuku?::delta", "applies the difference")

edge(
  "asshuku?::unpack",
  :inverse,
  "asshuku?::pack",
  "entries back out of the archive"
)

edge("asshuku?::delta", :inverse, "asshuku?::patch", "applies the difference")

edge(
  "asshuku?::pack",
  :inverse,
  "asshuku?::unpack",
  "entries back out of the archive"
)

edge(
  "asshuku?::archive",
  :inverse,
  "asshuku?::unpack_to",
  "tree back from the archive"
)

edge("asshuku?::stream", :lifts, "asshuku?::compress", "chunked form")
edge("asshuku?::stream", :lifts, "asshuku?::decompress", "chunked form")

edge(
  "asshuku?::compress",
  :pairs,
  "asshuku?::detect",
  "detect names what compress used"
)

edge(
  "asshuku?::delta",
  :pairs,
  "asshuku?::patch",
  "difference and its application"
)

edge("asshuku?::list", :pairs, "asshuku?::read", "headers then one entry")
edge("asshuku?::delta", :pairs, "genbo?::chunk", "both feed deduplication")

edge(
  "asshuku?::append",
  :refines,
  "asshuku?::pack",
  "adds entries to an archive"
)

edge("asshuku?::list", :refines, "asshuku?::unpack", "headers only")
edge("asshuku?::read", :refines, "asshuku?::unpack", "one named entry")
