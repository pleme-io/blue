space("souko?", {status: :provisional})

verb(
  "souko?",
  "close",
  {
    kind: :effect,
    shape: "close(store) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "release the store connection",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "copy",
  {
    kind: :effect,
    shape: "copy(from, to, opts) -> {etag, version}",
    laterals: ["deadline", "error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "copy an object inside or across stores",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "create",
  {
    kind: :effect,
    shape: "create(store, key, bytes, opts) -> {etag, version}",
    laterals: ["error", "idempotent"],
    fleet: "armazem",
    today: "absent",
    meaning: "put an object only if the key is absent",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "delete",
  {
    kind: :effect,
    shape: "delete(store, key) -> nil",
    laterals: ["error", "idempotent", "retry"],
    fleet: "armazem",
    today: "absent",
    meaning: "make the object absent; absent counts as done",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "download",
  {
    kind: :effect,
    shape: "download(store, key, path, opts) -> nil",
    laterals: ["cancel", "deadline", "error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "write an object to a file atomically",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "etag",
  {
    kind: :pure,
    shape: "etag(bytes, opts) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the etag a store would give this content",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "get",
  {
    kind: :effect,
    shape: "get(store, key, opts) -> bytes or nil",
    laterals: ["deadline", "error", "retry", "trace"],
    fleet: "armazem",
    today: "absent",
    meaning: "the object content, or nil when absent",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "has?",
  {
    kind: :effect,
    shape: "has?(store, key) -> Bool",
    laterals: ["deadline", "retry"],
    fleet: "armazem",
    today: "absent",
    meaning: "whether an object exists",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "info",
  {
    kind: :effect,
    shape: "info(store, key) -> {size, etag, modified, type, meta}",
    laterals: ["deadline", "error", "retry"],
    fleet: "armazem",
    today: "absent",
    meaning: "the object headers without its content",
    wave: 1,
    origin: "B",
    contract: "info(store, opts) -> {size, etag, modified, type, meta}"
  }
)

verb(
  "souko?",
  "lifecycle",
  {
    kind: :decl,
    shape: "lifecycle(store, rules) -> decl",
    laterals: ["config", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare expiry and tiering rules for a prefix",
    wave: 3,
    origin: "B"
  }
)

verb(
  "souko?",
  "list",
  {
    kind: :effect,
    shape: "list(store, opts) -> [{key, size, modified, etag}]",
    laterals: ["deadline", "error", "retry"],
    fleet: "armazem",
    today: "absent",
    meaning: "all objects under a prefix, every page, sorted",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "make_bucket",
  {
    kind: :effect,
    shape: "make_bucket(account, name, opts) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "create a bucket; existing counts as done",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "move",
  {
    kind: :effect,
    shape: "move(from, to, opts) -> nil",
    laterals: ["error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "copy then delete; not atomic, and says so",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "need",
  {
    kind: :effect,
    shape: "need(store, key, opts) -> bytes",
    laterals: ["deadline", "error", "retry"],
    fleet: "armazem",
    today: "absent",
    meaning: "the object content, raising not_found when absent",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "open",
  {
    kind: :effect,
    shape: "open(spec) -> store",
    laterals: ["capability", "config", "resource"],
    fleet: "armazem",
    today: "absent",
    meaning: "connect to an S3, R2, GCS or local object store",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "parse",
  {
    kind: :pure,
    shape: "parse(url) -> {scheme, bucket, key}",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "split an s3, gs or r2 URL into its parts",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "policy",
  {
    kind: :decl,
    shape: "policy(store, grants) -> decl",
    laterals: ["capability", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare who may read or write which prefix",
    wave: 3,
    origin: "B"
  }
)

verb(
  "souko?",
  "presign",
  {
    kind: :pure,
    shape: "presign(store, key, opts) -> url",
    laterals: ["capability", "time"],
    fleet: nil,
    today: "absent",
    meaning: "a time-limited URL granting one operation on an object",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "purge",
  {
    kind: :effect,
    shape: "purge(store, prefix, opts) -> count",
    laterals: ["cancel", "error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "delete every object under a prefix",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "put",
  {
    kind: :effect,
    shape: "put(store, key, bytes, opts) -> {etag, version}",
    laterals: ["deadline", "error", "idempotent", "retry"],
    fleet: "armazem",
    today: "absent",
    meaning: "create or replace an object",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "restore",
  {
    kind: :effect,
    shape: "restore(store, key, version) -> {etag, version}",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "make an earlier version the current object",
    wave: 3,
    origin: "B"
  }
)

verb(
  "souko?",
  "retain",
  {
    kind: :effect,
    shape: "retain(store, key, opts) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "hold an object against deletion until a date",
    wave: 3,
    origin: "B"
  }
)

verb(
  "souko?",
  "slice",
  {
    kind: :effect,
    shape: "slice(store, key, from, to) -> bytes",
    laterals: ["deadline", "error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "read a byte range of an object",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "stream",
  {
    kind: :stream,
    shape: "stream(store, key, f, opts) -> nil",
    laterals: ["cancel", "deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "call f per chunk of an object as it arrives",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "update",
  {
    kind: :effect,
    shape: "update(store, key, f, opts) -> {etag, version}",
    laterals: ["error", "idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "replace an object with f(old) using the etag precondition",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "upload",
  {
    kind: :effect,
    shape: "upload(store, key, path, opts) -> {etag, version}",
    laterals: ["cancel", "deadline", "error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "send a file as one object, in parts when large",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "url",
  {
    kind: :pure,
    shape: "url(store, key) -> url",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the plain address of an object",
    wave: 1,
    origin: "B"
  }
)

verb(
  "souko?",
  "usage",
  {
    kind: :effect,
    shape: "usage(store, prefix) -> {objects, bytes}",
    laterals: ["error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "object count and total bytes under a prefix",
    wave: 2,
    origin: "B"
  }
)

verb(
  "souko?",
  "versions",
  {
    kind: :effect,
    shape: "versions(store, key) -> [version]",
    laterals: ["error", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "every stored version of an object, newest first",
    wave: 3,
    origin: "B",
    contract: "versions(store) -> [version]"
  }
)

verb(
  "souko?",
  "watch",
  {
    kind: :stream,
    shape: "watch(store, f, opts) -> nil",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "call f per object change notice or poll difference",
    wave: 3,
    origin: "B"
  }
)

edge("souko?::upload", :composes, "fairu::stream", "reads the file in parts")
edge("souko?::download", :composes, "fairu::write", "atomic file write")

edge(
  "souko?::open",
  :composes,
  "himitsu::read",
  "credentials from a secret ref"
)

edge("souko?::etag", :composes, "shomei::hash", "content digest basis")

edge(
  "souko?::download",
  :composes,
  "shomei::hash_stream",
  "optional digest check"
)

edge("souko?::presign", :composes, "shomei::sign", "signs the request")
edge("souko?::move", :composes, "souko?::copy", "copies first")

edge(
  "souko?::restore",
  :composes,
  "souko?::copy",
  "old version copied to current"
)

edge("souko?::lifecycle", :composes, "souko?::delete", "expiry deletes by rule")
edge("souko?::move", :composes, "souko?::delete", "then deletes the source")

edge(
  "souko?::upload",
  :composes,
  "souko?::etag",
  "integrity check after sending"
)

edge("souko?::update", :composes, "souko?::get", "reads the old object")
edge("souko?::purge", :composes, "souko?::list", "finds the keys")
edge("souko?::usage", :composes, "souko?::list", "adds up listed sizes")
edge("souko?::open", :composes, "souko?::parse", "spec may be a URL")

edge(
  "souko?::update",
  :composes,
  "souko?::put",
  "writes with the etag precondition"
)

edge("souko?::download", :composes, "souko?::slice", "resumes by byte range")

edge(
  "souko?::presign",
  :composes,
  "souko?::url",
  "grants access to this address"
)

edge(
  "souko?::retain",
  :guards,
  "souko?::delete",
  "blocks deletion until a date"
)

edge("souko?::policy", :guards, "souko?::get", "decides who may read")
edge("souko?::parse", :guards, "souko?::open", "reject a bad address early")
edge("souko?::open", :inverse, "souko?::close", "releases the store")

edge(
  "souko?::put",
  :inverse,
  "souko?::delete",
  "delete makes absent what put made"
)

edge("souko?::upload", :inverse, "souko?::download", "object back to a file")
edge("souko?::close", :inverse, "souko?::open", "releases the store")
edge("souko?::url", :inverse, "souko?::parse", "parse reads what url builds")

edge(
  "souko?::delete",
  :inverse,
  "souko?::put",
  "delete makes absent what put made"
)

edge("souko?::download", :inverse, "souko?::upload", "object back to a file")
edge("souko?::parse", :inverse, "souko?::url", "parse reads what url builds")
edge("souko?::purge", :lifts, "souko?::delete", "many keys at once")
edge("souko?::stream", :lifts, "souko?::get", "chunked form")
edge("souko?::watch", :lifts, "souko?::list", "changes in the listing")
edge("souko?::info", :pairs, "souko?::get", "headers beside content")
edge("souko?::put", :pairs, "souko?::get", "store and fetch")
edge("souko?::list", :pairs, "souko?::info", "keys and their headers")
edge("souko?::lifecycle", :pairs, "souko?::policy", "rules beside grants")
edge("souko?::make_bucket", :pairs, "souko?::policy", "a bucket and its grants")
edge("souko?::versions", :pairs, "souko?::restore", "list then choose one")
edge("souko?::etag", :pairs, "souko?::update", "the precondition value")
edge("souko?::need", :refines, "souko?::get", "raises when absent")
edge("souko?::slice", :refines, "souko?::get", "part of the content")
edge("souko?::has?", :refines, "souko?::info", "head request only")
edge("souko?::versions", :refines, "souko?::list", "versions of one key")
edge("souko?::create", :refines, "souko?::put", "refuses to overwrite")
edge("souko?::upload", :refines, "souko?::put", "content comes from a file")
edge("souko?::copy", :requires, "souko?::has?", "source object must exist")
edge("souko?::get", :requires, "souko?::open", "needs a connected store")

edge(
  "souko?::make_bucket",
  :requires,
  "souko?::open",
  "account connection first"
)
