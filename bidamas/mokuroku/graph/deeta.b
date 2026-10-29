space("deeta", {status: :ratified})

verb(
  "deeta",
  "address",
  {
    kind: :pure,
    shape: "address(value, algorithm) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "hash of the canonical form: a content address",
    wave: 2,
    origin: "A"
  }
)

verb(
  "deeta",
  "canonical",
  {
    kind: :pure,
    shape: "canonical(value, opts) -> text",
    laterals: %w[idempotent serialize],
    fleet: nil,
    today: "absent",
    meaning: "one byte-exact form per value: sorted keys, no noise",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "convert",
  {
    kind: :pure,
    shape: "convert(text, from, to, opts) -> text",
    laterals: %w[error serialize],
    fleet: nil,
    today: "absent",
    meaning: "reparse in one format, render in another",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "decode",
  {
    kind: :pure,
    shape: "decode(text, encoding) -> bytes",
    laterals: ["error"],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "text in an encoding back to bytes",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "delete",
  {
    kind: :pure,
    shape: "delete(doc, path) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "new doc with the path removed",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "detect",
  {
    kind: :pure,
    shape: "detect(text, opts) -> format or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "guess the format of unlabelled text",
    wave: 2,
    origin: "A"
  }
)

verb(
  "deeta",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b, opts) -> [change]",
    laterals: [],
    fleet: nil,
    today: "partial:deeta",
    meaning: "structural changes between two docs",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "encode",
  {
    kind: :pure,
    shape: "encode(bytes, encoding) -> text",
    laterals: ["serialize"],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "bytes to base64, base64url, hex or url text",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "flatten",
  {
    kind: :pure,
    shape: "flatten(doc, opts) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "nested doc to one level of dotted keys",
    wave: 2,
    origin: "A",
    contract: "flatten(doc) -> record"
  }
)

verb(
  "deeta",
  "get",
  {
    kind: :pure,
    shape: "get(doc, path, opts) -> value or nil",
    laterals: [],
    fleet: nil,
    today: "partial:deeta",
    meaning: "value at a dotted path, nil when absent",
    wave: 0,
    origin: "A"
  }
)

verb(
  "deeta",
  "has?",
  {
    kind: :pure,
    shape: "has?(doc, path) -> Bool",
    laterals: [],
    fleet: nil,
    today: "partial:deeta",
    meaning: "whether the path is present",
    wave: 0,
    origin: "A"
  }
)

verb(
  "deeta",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b, opts) -> doc",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "combine two docs deeply; b wins",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "need",
  {
    kind: :pure,
    shape: "need(doc, path) -> value",
    laterals: ["error"],
    fleet: nil,
    today: "partial:deeta",
    meaning: "value at a path, raises not_found when absent",
    wave: 0,
    origin: "A"
  }
)

verb(
  "deeta",
  "pack",
  {
    kind: :pure,
    shape: "pack(value, format, opts) -> bytes",
    laterals: ["serialize"],
    fleet: "bencode",
    today: "absent",
    meaning: "value to a binary format: cbor, msgpack, bencode",
    wave: 3,
    origin: "A"
  }
)

verb(
  "deeta",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format, opts) -> value",
    laterals: %w[error serialize validate],
    fleet: "tatara-lisp-script",
    today: "exists:deeta",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "patch",
  {
    kind: :pure,
    shape: "patch(doc, changes) -> doc",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "apply change records (RFC 6902 JSON Patch)",
    wave: 2,
    origin: "A"
  }
)

verb(
  "deeta",
  "paths",
  {
    kind: :pure,
    shape: "paths(doc, opts) -> [path]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every leaf path, sorted",
    wave: 2,
    origin: "A"
  }
)

verb(
  "deeta",
  "put",
  {
    kind: :pure,
    shape: "put(doc, path, value) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "new doc with the value set at the path",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "query",
  {
    kind: :pure,
    shape: "query(doc, expression) -> [value]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "jq-style expression over a document",
    wave: 3,
    origin: "A"
  }
)

verb(
  "deeta",
  "read",
  {
    kind: :effect,
    shape: "read(path, opts) -> value",
    laterals: %w[capability error serialize],
    fleet: nil,
    today: "partial:deeta",
    meaning: "file to value, format taken from the extension",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "render",
  {
    kind: :pure,
    shape: "render(value, format, opts) -> text",
    laterals: %w[error serialize],
    fleet: "tatara-lisp-script",
    today: "partial:deeta",
    meaning: "value to stable canonical text",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "select",
  {
    kind: :pure,
    shape: "select(doc, paths) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "keep only the listed paths",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "stream",
  {
    kind: :stream,
    shape: "stream(source, format, f, opts) -> count",
    laterals: %w[cancel error resource],
    fleet: nil,
    today: "absent",
    meaning: "call f per record of NDJSON, CSV or a JSON array",
    wave: 2,
    origin: "A"
  }
)

verb(
  "deeta",
  "unflatten",
  {
    kind: :pure,
    shape: "unflatten(record, opts) -> doc",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "dotted keys back to a nested doc",
    wave: 2,
    origin: "A"
  }
)

verb(
  "deeta",
  "unpack",
  {
    kind: :pure,
    shape: "unpack(bytes, format, opts) -> value",
    laterals: %w[error validate],
    fleet: "bencode",
    today: "absent",
    meaning: "binary format back to a value",
    wave: 3,
    origin: "A"
  }
)

verb(
  "deeta",
  "update",
  {
    kind: :pure,
    shape: "update(doc, path, f) -> doc",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "new doc with f applied at the path",
    wave: 1,
    origin: "A"
  }
)

verb(
  "deeta",
  "walk",
  {
    kind: :pure,
    shape: "walk(doc, f) -> doc",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "apply f to every node, children first",
    wave: 2,
    origin: "A",
    contract: "walk(doc, opts) -> doc"
  }
)

verb(
  "deeta",
  "write",
  {
    kind: :effect,
    shape: "write(path, value, opts) -> nil",
    laterals: %w[capability error idempotent serialize],
    fleet: nil,
    today: "absent",
    meaning: "value to file atomically, format from extension",
    wave: 1,
    origin: "A"
  }
)

edge(
  "deeta::address",
  :composes,
  "deeta::canonical",
  "hash the canonical bytes"
)

edge(
  "deeta::pack",
  :composes,
  "deeta::canonical",
  "deterministic bytes need one order"
)

edge(
  "deeta::patch",
  :composes,
  "deeta::delete",
  "each change may remove a path"
)

edge("deeta::has?", :composes, "deeta::get", "get returns a value")
edge("deeta::select", :composes, "deeta::get", "read each listed path")
edge("deeta::update", :composes, "deeta::get", "read the old value")
edge("deeta::convert", :composes, "deeta::parse", "read the source format")
edge("deeta::read", :composes, "deeta::parse", "file text then parse")
edge("deeta::diff", :composes, "deeta::paths", "compares path by path")
edge("deeta::flatten", :composes, "deeta::paths", "one dotted key per path")
edge("deeta::patch", :composes, "deeta::put", "each change sets a path")
edge("deeta::select", :composes, "deeta::put", "builds the projected doc")
edge("deeta::unflatten", :composes, "deeta::put", "put each dotted path")
edge("deeta::update", :composes, "deeta::put", "store f(old)")
edge("deeta::convert", :composes, "deeta::render", "write the target format")
edge("deeta::write", :composes, "deeta::render", "value rendered, then stored")
edge("deeta::merge", :composes, "deeta::walk", "descends both docs together")

edge(
  "deeta::paths",
  :composes,
  "deeta::walk",
  "collects the leaves walk visits"
)

edge("deeta::query", :composes, "deeta::walk", "evaluates by visiting nodes")
edge("deeta::read", :composes, "fairu::read", "bytes come from the file")
edge("deeta::write", :composes, "fairu::write", "atomic file replacement")
edge("deeta::get", :composes, "jisho::get", "a path is a chain of key lookups")
edge("deeta::put", :composes, "jisho::put", "a path is a chain of key writes")

edge(
  "deeta::address",
  :composes,
  "shomei::hash",
  "digest of the canonical text"
)

edge(
  "deeta::parse",
  :generalizes,
  "bunpou?::parse",
  "each data format is a fixed grammar"
)

edge(
  "deeta::query",
  :generalizes,
  "deeta::get",
  "expressions beyond dotted paths"
)

edge("deeta::walk", :generalizes, "deeta::update", "visits every node")
edge("deeta::has?", :guards, "deeta::need", "check presence before demanding")
edge("deeta::detect", :guards, "deeta::parse", "picks the format parse needs")

edge(
  "deeta::unpack",
  :guards,
  "sukiima?::validate",
  "decoded bytes still need checking"
)

edge("deeta::encode", :inverse, "deeta::decode", "text and bytes round-trip")
edge("deeta::put", :inverse, "deeta::delete", "removes what put sets")
edge("deeta::patch", :inverse, "deeta::diff", "applies what diff finds")
edge("deeta::decode", :inverse, "deeta::encode", "text and bytes round-trip")
edge("deeta::unflatten", :inverse, "deeta::flatten", "rebuilds the nesting")
edge("deeta::unpack", :inverse, "deeta::pack", "value and bytes round-trip")
edge("deeta::render", :inverse, "deeta::parse", "text and value round-trip")
edge("deeta::diff", :inverse, "deeta::patch", "applies what diff finds")
edge("deeta::delete", :inverse, "deeta::put", "removes what put sets")
edge("deeta::write", :inverse, "deeta::read", "stores what read returns")
edge("deeta::parse", :inverse, "deeta::render", "text and value round-trip")
edge("deeta::flatten", :inverse, "deeta::unflatten", "rebuilds the nesting")
edge("deeta::pack", :inverse, "deeta::unpack", "value and bytes round-trip")
edge("deeta::read", :inverse, "deeta::write", "stores what read returns")
edge("deeta::stream", :lifts, "deeta::parse", "parse one record at a time")
edge("deeta::canonical", :pairs, "deeta::address", "hash needs canonical bytes")

edge(
  "deeta::render",
  :pairs,
  "deeta::canonical",
  "stable text is the canonical form"
)

edge(
  "deeta::detect",
  :pairs,
  "deeta::convert",
  "unknown input to a chosen format"
)

edge("deeta::merge", :pairs, "deeta::diff", "combine versus compare")
edge("deeta::put", :pairs, "deeta::get", "set what get reads")
edge("deeta::unpack", :pairs, "deeta::parse", "binary versus text input")
edge("deeta::get", :pairs, "deeta::put", "read and write one path")

edge(
  "deeta::stream",
  :pairs,
  "deeta::read",
  "whole file versus record at a time"
)

edge("deeta::pack", :pairs, "deeta::render", "binary versus text output")
edge("deeta::read", :pairs, "deeta::write", "the file round trip")

edge(
  "deeta::encode",
  :pairs,
  "moji::bytes",
  "text to bytes, then bytes to text"
)

edge(
  "deeta::decode",
  :pairs,
  "moji::from_bytes",
  "text to bytes, then bytes to text"
)

edge(
  "deeta::address",
  :pairs,
  "shomei::verify?",
  "check content against its address"
)

edge("deeta::diff", :refines, "chigai?::diff", "changes by path, not by line")
edge("deeta::patch", :refines, "chigai?::patch", "path-addressed hunks")
edge("deeta::need", :refines, "deeta::get", "raises instead of nil")

edge(
  "deeta::canonical",
  :refines,
  "deeta::render",
  "render with fixed key order"
)

edge("deeta::walk", :refines, "gurafu::walk", "documents are trees")
edge("deeta::merge", :refines, "jisho::merge", "deep merge for documents")
edge("deeta::select", :refines, "jisho::select", "paths instead of keys")
edge("deeta::canonical", :requires, "deeta::walk", "sorts every level")
