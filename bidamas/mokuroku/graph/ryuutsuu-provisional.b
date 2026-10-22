space("ryuutsuu?", {status: :provisional})

verb(
  "ryuutsuu?",
  "channels",
  {
    kind: :effect,
    shape: "channels(name) -> [channel]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "stable, beta and nightly pointers",
    wave: 3,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "fetch",
  {
    kind: :effect,
    shape: "fetch(name, channel, opts) -> archive",
    laterals: ["cache", "deadline", "retry", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "download and verify a distributable",
    wave: 3,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "install",
  {
    kind: :effect,
    shape: "install(archive, dest, opts) -> installed",
    laterals: ["capability", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "put a program where the user runs it",
    wave: 3,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "installed",
  {
    kind: :effect,
    shape: "installed(opts) -> [record]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "programs installed and their versions",
    wave: 3,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "manifest",
  {
    kind: :pure,
    shape: "manifest(artifacts) -> record",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "names, sizes and hashes of a release",
    wave: 2,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "mirror",
  {
    kind: :effect,
    shape: "mirror(from, to) -> nil",
    laterals: ["idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "copy releases to another host",
    wave: 4,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "pack",
  {
    kind: :effect,
    shape: "pack(files, format, opts) -> archive",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "bundle a binary and its files",
    wave: 2,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "publish",
  {
    kind: :effect,
    shape: "publish(archive, channel, opts) -> record",
    laterals: ["idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "put a distributable on a channel",
    wave: 2,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "sign",
  {
    kind: :effect,
    shape: "sign(archive, key) -> signature",
    laterals: ["capability"],
    fleet: "tameshi",
    today: "absent",
    meaning: "sign a distributable",
    wave: 2,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "uninstall",
  {
    kind: :effect,
    shape: "uninstall(name, opts) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "remove an installed program",
    wave: 3,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "upgrade",
  {
    kind: :effect,
    shape: "upgrade(name, opts) -> record",
    laterals: ["idempotent", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "move an installed program to its channel head",
    wave: 3,
    origin: "E"
  }
)

verb(
  "ryuutsuu?",
  "verify",
  {
    kind: :effect,
    shape: "verify(archive, opts) -> verdict",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "signature and hash of a distributable",
    wave: 2,
    origin: "E"
  }
)

edge(
  "ryuutsuu?::upgrade",
  :composes,
  "ryuutsuu?::channels",
  "find channel head"
)

edge("ryuutsuu?::mirror", :composes, "ryuutsuu?::fetch", "read origin")
edge("ryuutsuu?::upgrade", :composes, "ryuutsuu?::install", "replace in place")

edge(
  "ryuutsuu?::pack",
  :composes,
  "ryuutsuu?::manifest",
  "archive and its record"
)

edge(
  "ryuutsuu?::publish",
  :composes,
  "ryuutsuu?::manifest",
  "channel lists manifest"
)

edge("ryuutsuu?::mirror", :composes, "ryuutsuu?::publish", "write copy")
edge("ryuutsuu?::fetch", :composes, "ryuutsuu?::verify", "check on arrival")
edge("ryuutsuu?::manifest", :composes, "shomei::hash", "hashes of artifacts")
edge("ryuutsuu?::sign", :composes, "shomei::sign", "signature of archive")
edge("ryuutsuu?::uninstall", :inverse, "ryuutsuu?::install", "remove a program")
edge("ryuutsuu?::install", :inverse, "ryuutsuu?::uninstall", "remove a program")
edge("ryuutsuu?::publish", :pairs, "rirezu?::publish", "binaries in a release")
edge("ryuutsuu?::install", :pairs, "ryuutsuu?::installed", "install then list")

edge(
  "ryuutsuu?::channels",
  :pairs,
  "ryuutsuu?::upgrade",
  "update follows a channel"
)

edge("ryuutsuu?::channels", :refines, "core::list", "channel pointers")
edge("ryuutsuu?::installed", :refines, "core::list", "programs present")
edge("ryuutsuu?::fetch", :refines, "core::read", "download")
edge("ryuutsuu?::pack", :refines, "core::render", "archive from files")
edge("ryuutsuu?::verify", :refines, "shomei::verify?", "hash and signature")

edge(
  "ryuutsuu?::install",
  :requires,
  "ryuutsuu?::fetch",
  "archive must be local"
)

edge("ryuutsuu?::publish", :requires, "ryuutsuu?::sign", "signed before upload")
