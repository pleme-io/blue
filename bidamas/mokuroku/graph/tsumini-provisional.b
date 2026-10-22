space("tsumini?", {status: :provisional})

verb(
  "tsumini?",
  "build",
  {
    kind: :effect,
    shape: "build(spec, opts) -> image",
    laterals: ["cache", "error", "process"],
    fleet: nil,
    today: "absent",
    meaning: "make an image from a spec, no daemon",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "check",
  {
    kind: :effect,
    shape: "check(ref, policy) -> [finding]",
    laterals: ["validate"],
    fleet: "lacre",
    today: "absent",
    meaning: "refuse an image holding a shell, root user or extras",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "combine",
  {
    kind: :effect,
    shape: "combine(refs, name) -> digest",
    laterals: ["idempotent"],
    fleet: "multi-arch-image-release",
    today: "absent",
    meaning: "one multi-arch index from per-arch images",
    wave: 1,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "copy",
  {
    kind: :effect,
    shape: "copy(from, to, opts) -> digest",
    laterals: ["idempotent", "retry"],
    fleet: "multi-arch-image-release",
    today: "absent",
    meaning: "move an image between registries without unpacking",
    wave: 1,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "delete",
  {
    kind: :effect,
    shape: "delete(ref) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "remove a tag or manifest",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "diff",
  {
    kind: :effect,
    shape: "diff(a, b) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "files and packages that differ between images",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "export",
  {
    kind: :effect,
    shape: "export(ref, dir) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "unpack an image's filesystem",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "gc",
  {
    kind: :effect,
    shape: "gc(repo, opts) -> {freed:}",
    laterals: ["idempotent", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "drop untagged and unreferenced blobs",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "info",
  {
    kind: :effect,
    shape: "info(ref) -> record",
    laterals: ["cache", "error"],
    fleet: nil,
    today: "absent",
    meaning: "manifest, config and size of an image",
    wave: 1,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "layers",
  {
    kind: :effect,
    shape: "layers(ref) -> [layer]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "layer digests, sizes and commands",
    wave: 1,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "list",
  {
    kind: :effect,
    shape: "list(repo, opts) -> [tag]",
    laterals: ["error", "ratelimit"],
    fleet: nil,
    today: "absent",
    meaning: "tags in a repository, all pages",
    wave: 1,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "pull",
  {
    kind: :effect,
    shape: "pull(ref, dir, opts) -> image",
    laterals: ["cache", "deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "fetch an image by digest",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "push",
  {
    kind: :effect,
    shape: "push(image, ref, opts) -> digest",
    laterals: ["deadline", "idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "upload an image, return its digest",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "render",
  {
    kind: :pure,
    shape: "render(spec) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "image spec in the build tool's own syntax",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "resolve",
  {
    kind: :effect,
    shape: "resolve(ref) -> digest",
    laterals: ["cache", "error"],
    fleet: nil,
    today: "absent",
    meaning: "turn a tag into its digest",
    wave: 1,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "run",
  {
    kind: :effect,
    shape: "run(ref, args, opts) -> result",
    laterals: ["capability", "deadline", "process"],
    fleet: nil,
    today: "absent",
    meaning: "run an image once and return its result",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tsumini?",
  "tag",
  {
    kind: :effect,
    shape: "tag(ref, name) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "add a tag to a digest",
    wave: 1,
    origin: "E"
  }
)

edge("tsumini?::check", :composes, "kyoukyuu?::scan", "vulnerability gate")
edge("tsumini?::diff", :composes, "tsumini?::layers", "compare layers")
edge("tsumini?::gc", :composes, "tsumini?::list", "find unreferenced")
edge("tsumini?::copy", :composes, "tsumini?::pull", "read side")
edge("tsumini?::combine", :composes, "tsumini?::push", "push an index")
edge("tsumini?::copy", :composes, "tsumini?::push", "write side")
edge("tsumini?::push", :guards, "kyoukyuu?::attest", "attest the pushed digest")
edge("tsumini?::copy", :guards, "kyoukyuu?::verify", "verify on the way")
edge("tsumini?::build", :guards, "tsumini?::check", "policy runs on result")
edge("tsumini?::export", :inverse, "tsumini?::build", "image to files")
edge("tsumini?::tag", :inverse, "tsumini?::delete", "remove a name")
edge("tsumini?::build", :inverse, "tsumini?::export", "image to files")
edge("tsumini?::push", :inverse, "tsumini?::pull", "write versus read")
edge("tsumini?::pull", :inverse, "tsumini?::push", "write versus read")
edge("tsumini?::delete", :inverse, "tsumini?::tag", "remove a name")
edge("tsumini?::layers", :pairs, "tsumini?::diff", "layers compared")
edge("tsumini?::list", :pairs, "tsumini?::gc", "tags to prune")
edge("tsumini?::combine", :pairs, "tsumini?::tag", "index then name")
edge("tsumini?::resolve", :refines, "core::get", "tag to digest")
edge("tsumini?::info", :refines, "core::info", "manifest and config")
edge("tsumini?::layers", :refines, "core::list", "layers of an image")
edge("tsumini?::list", :refines, "core::list", "tags")
edge("tsumini?::tag", :refines, "core::put", "name a digest")
edge("tsumini?::pull", :refines, "core::read", "image content")
edge("tsumini?::render", :refines, "core::render", "spec to text")
edge("tsumini?::run", :refines, "core::run", "image as a command")
edge("tsumini?::build", :refines, "hyouka::build", "image from a store closure")
edge("tsumini?::check", :refines, "kijun::check", "rules for images")
edge("tsumini?::layers", :requires, "tsumini?::info", "manifest names layers")
edge("tsumini?::run", :requires, "tsumini?::pull", "image must be local")
edge("tsumini?::combine", :requires, "tsumini?::resolve", "per-arch digests")
edge("tsumini?::pull", :requires, "tsumini?::resolve", "pull by digest")

edge(
  "tsumini?::tag",
  :requires,
  "tsumini?::resolve",
  "target digest must exist"
)
