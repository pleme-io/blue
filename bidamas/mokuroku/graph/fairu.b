space("fairu", {status: :ratified})

verb(
  "fairu",
  "absolute",
  {
    kind: :effect,
    shape: "absolute(path) -> path",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "the path made absolute against the current directory",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "append",
  {
    kind: :effect,
    shape: "append(path, content) -> nil",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "add to the end of a file, creating it",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "copy",
  {
    kind: :effect,
    shape: "copy(from, to, opts) -> nil",
    laterals: ["capability", "deadline", "error"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "place a copy of a file or tree at a destination",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "current",
  {
    kind: :effect,
    shape: "current() -> path",
    laterals: ["capability"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "the current working directory",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "delete",
  {
    kind: :effect,
    shape: "delete(path, opts) -> nil",
    laterals: ["capability", "error", "idempotent"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "make the path absent; absent counts as done",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "dir?",
  {
    kind: :effect,
    shape: "dir?(path) -> Bool",
    laterals: ["capability"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "whether the path is a directory",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "exists?",
  {
    kind: :effect,
    shape: "exists?(path) -> Bool",
    laterals: ["capability"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "whether the path is there; never raises",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "extension",
  {
    kind: :pure,
    shape: "extension(path) -> text",
    laterals: [],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "the final extension of a name, or empty",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "file?",
  {
    kind: :effect,
    shape: "file?(path) -> Bool",
    laterals: ["capability"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "whether the path is a regular file",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "glob",
  {
    kind: :effect,
    shape: "glob(pattern, opts) -> [path]",
    laterals: ["capability"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "the paths matching a pattern, sorted",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "home",
  {
    kind: :effect,
    shape: "home() -> path",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "the home directory of the user",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "info",
  {
    kind: :effect,
    shape: "info(path) -> {kind, size, modified, mode}",
    laterals: ["capability", "error", "time"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "the current state of a path as a record",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "join",
  {
    kind: :pure,
    shape: "join(*parts) -> path",
    laterals: [],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "join path parts with one separator",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "link",
  {
    kind: :effect,
    shape: "link(target, path, opts) -> nil",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "make a symbolic link; configured off by default",
    wave: 3,
    origin: "B"
  }
)

verb(
  "fairu",
  "list",
  {
    kind: :effect,
    shape: "list(dir, opts) -> [entry]",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "the entries of one directory, sorted",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "make_dir",
  {
    kind: :effect,
    shape: "make_dir(path, opts) -> nil",
    laterals: ["capability", "error", "idempotent"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "create a directory and its parents",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "match?",
  {
    kind: :pure,
    shape: "match?(pattern, path) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a glob pattern matches a path text",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "mode",
  {
    kind: :effect,
    shape: "mode(path, bits) -> nil",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "set permission bits; configured off by default",
    wave: 3,
    origin: "B"
  }
)

verb(
  "fairu",
  "move",
  {
    kind: :effect,
    shape: "move(from, to, opts) -> nil",
    laterals: ["capability", "error", "idempotent"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "rename atomically on one filesystem",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "name",
  {
    kind: :pure,
    shape: "name(path) -> text",
    laterals: [],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "the last part of a path",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "normalize",
  {
    kind: :pure,
    shape: "normalize(path) -> path",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the path with dot parts and doubled separators removed",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "parent",
  {
    kind: :pure,
    shape: "parent(path) -> path",
    laterals: [],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "the directory part of a path",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "parts",
  {
    kind: :pure,
    shape: "parts(path) -> [text]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the path split into its parts",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "place",
  {
    kind: :effect,
    shape: "place(app, tier) -> path",
    laterals: ["capability", "config"],
    fleet: "okiba",
    today: "absent",
    meaning: "the absolute config, state, data or cache path of an app",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "read",
  {
    kind: :effect,
    shape: "read(path, opts) -> text",
    laterals: ["capability", "deadline", "error"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "the whole text of a file",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "read_bytes",
  {
    kind: :effect,
    shape: "read_bytes(path, opts) -> bytes",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "the whole content of a file as bytes",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "relative",
  {
    kind: :pure,
    shape: "relative(path, base) -> path",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the path expressed relative to a base",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "same?",
  {
    kind: :effect,
    shape: "same?(a, b) -> Bool",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "whether two paths are one file on disk",
    wave: 2,
    origin: "B"
  }
)

verb(
  "fairu",
  "space",
  {
    kind: :effect,
    shape: "space(path) -> {total, free}",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "free and total bytes of the volume holding a path",
    wave: 2,
    origin: "B"
  }
)

verb(
  "fairu",
  "stem",
  {
    kind: :pure,
    shape: "stem(path) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the name without its final extension",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "stream",
  {
    kind: :stream,
    shape: "stream(path, f, opts) -> nil",
    laterals: ["cancel", "deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "call f per line or chunk without holding the file",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "sync",
  {
    kind: :effect,
    shape: "sync(path) -> nil",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "flush a file to stable storage",
    wave: 2,
    origin: "B"
  }
)

verb(
  "fairu",
  "touch",
  {
    kind: :effect,
    shape: "touch(path, opts) -> nil",
    laterals: ["capability", "idempotent", "time"],
    fleet: nil,
    today: "absent",
    meaning: "create an empty file or bump its modified time",
    wave: 2,
    origin: "B"
  }
)

verb(
  "fairu",
  "update",
  {
    kind: :effect,
    shape: "update(path, f, opts) -> text",
    laterals: ["error", "idempotent", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "read, change with f, write back; conflict if it moved",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "usage",
  {
    kind: :effect,
    shape: "usage(path) -> {bytes, files}",
    laterals: ["capability", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "bytes and files used under a path",
    wave: 2,
    origin: "B"
  }
)

verb(
  "fairu",
  "walk",
  {
    kind: :effect,
    shape: "walk(root, opts) -> [path]",
    laterals: ["cancel", "capability", "error"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "every file under a root, sorted",
    wave: 0,
    origin: "B"
  }
)

verb(
  "fairu",
  "watch",
  {
    kind: :stream,
    shape: "watch(path, f, opts) -> nil",
    laterals: ["cancel", "deadline", "time"],
    fleet: nil,
    today: "absent",
    meaning: "call f per change event until it returns stop",
    wave: 2,
    origin: "B"
  }
)

verb(
  "fairu",
  "with_extension",
  {
    kind: :pure,
    shape: "with_extension(path, ext) -> path",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the path with its extension replaced",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "with_temp_dir",
  {
    kind: :effect,
    shape: "with_temp_dir(f) -> value",
    laterals: ["cancel", "error", "resource"],
    fleet: "tatara-lisp",
    today: "absent",
    meaning: "run f in a fresh directory removed afterwards",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "with_temp_file",
  {
    kind: :effect,
    shape: "with_temp_file(f, opts) -> value",
    laterals: ["cancel", "error", "resource"],
    fleet: "tatara-lisp",
    today: "absent",
    meaning: "run f with a fresh file removed afterwards",
    wave: 1,
    origin: "B"
  }
)

verb(
  "fairu",
  "write",
  {
    kind: :effect,
    shape: "write(path, content, opts) -> nil",
    laterals: ["capability", "error", "idempotent"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "replace a whole file atomically, making parents",
    wave: 0,
    origin: "B"
  }
)

edge("fairu::move", :composes, "fairu::copy", "fallback across volumes")
edge("fairu::absolute", :composes, "fairu::current", "base of relative paths")
edge("fairu::move", :composes, "fairu::delete", "removes the source afterwards")

edge(
  "fairu::with_temp_dir",
  :composes,
  "fairu::delete",
  "removes it on every exit"
)

edge(
  "fairu::with_temp_file",
  :composes,
  "fairu::delete",
  "removes it on every exit"
)

edge("fairu::same?", :composes, "fairu::info", "compares file identity")

edge(
  "fairu::update",
  :composes,
  "fairu::info",
  "compares modified time for conflict"
)

edge("fairu::usage", :composes, "fairu::info", "size of each file")
edge("fairu::absolute", :composes, "fairu::join", "current directory plus path")
edge("fairu::normalize", :composes, "fairu::join", "rebuilds the cleaned path")
edge("fairu::place", :composes, "fairu::join", "app tier path from parts")

edge(
  "fairu::with_extension",
  :composes,
  "fairu::join",
  "joins stem and new extension"
)

edge("fairu::walk", :composes, "fairu::list", "recursion over listings")

edge(
  "fairu::with_temp_dir",
  :composes,
  "fairu::make_dir",
  "creates the directory"
)

edge(
  "fairu::write",
  :composes,
  "fairu::make_dir",
  "creates missing parent directories"
)

edge("fairu::glob", :composes, "fairu::match?", "pattern test per path")
edge("fairu::write", :composes, "fairu::move", "temp file then atomic rename")
edge("fairu::extension", :composes, "fairu::name", "tail of the name")
edge("fairu::stem", :composes, "fairu::name", "name without its extension")
edge("fairu::normalize", :composes, "fairu::parts", "drops dot parts")
edge("fairu::update", :composes, "fairu::read", "reads the old content")
edge("fairu::with_extension", :composes, "fairu::stem", "keeps the stem")
edge("fairu::copy", :composes, "fairu::stream", "chunked transfer of content")
edge("fairu::glob", :composes, "fairu::walk", "patterns select from a tree")
edge("fairu::usage", :composes, "fairu::walk", "adds up sizes over a tree")
edge("fairu::update", :composes, "fairu::write", "writes the changed content")
edge("fairu::with_temp_file", :composes, "fairu::write", "creates the file")

edge(
  "fairu::watch",
  :composes,
  "jikan::sleep",
  "polling interval between probes"
)

edge("fairu::place", :composes, "kankyou::get", "reads the XDG variables")
edge("fairu::dir?", :guards, "fairu::list", "list needs a directory")
edge("fairu::exists?", :guards, "fairu::read", "check before a read")
edge("fairu::file?", :guards, "fairu::stream", "stream needs a file")
edge("fairu::dir?", :guards, "fairu::walk", "walk needs a directory root")
edge("fairu::space", :guards, "fairu::write", "check room before a large write")
edge("fairu::relative", :inverse, "fairu::absolute", "path as seen from a base")
edge("fairu::make_dir", :inverse, "fairu::delete", "removes what make_dir made")
edge("fairu::write", :inverse, "fairu::delete", "makes absent what write made")
edge("fairu::parts", :inverse, "fairu::join", "parts rebuild the path")
edge("fairu::delete", :inverse, "fairu::make_dir", "removes what make_dir made")
edge("fairu::join", :inverse, "fairu::parts", "parts rebuild the path")
edge("fairu::absolute", :inverse, "fairu::relative", "path as seen from a base")
edge("fairu::delete", :inverse, "fairu::write", "makes absent what write made")
edge("fairu::watch", :lifts, "fairu::info", "stream of state changes")
edge("fairu::walk", :lifts, "fairu::list", "whole tree form of one directory")
edge("fairu::glob", :lifts, "fairu::match?", "one pattern over many paths")
edge("fairu::stream", :lifts, "fairu::read", "per-chunk form of whole read")
edge("fairu::current", :pairs, "fairu::absolute", "base for resolving")
edge("fairu::home", :pairs, "fairu::absolute", "tilde is always explicit")
edge("fairu::stem", :pairs, "fairu::extension", "together they split a name")
edge("fairu::match?", :pairs, "fairu::glob", "same pattern language")
edge("fairu::list", :pairs, "fairu::info", "entries and their state")
edge("fairu::mode", :pairs, "fairu::info", "info reads the bits mode sets")
edge("fairu::touch", :pairs, "fairu::info", "info reads the time touch bumps")
edge("fairu::name", :pairs, "fairu::parent", "together they split a path")
edge("fairu::usage", :pairs, "fairu::space", "used beside free")
edge("fairu::read", :pairs, "fairu::write", "read what write replaced")
edge("fairu::read_bytes", :pairs, "fairu::write", "whole-content in and out")
edge("fairu::sync", :pairs, "fairu::write", "makes the write durable")

edge(
  "fairu::update",
  :pairs,
  "rokku?::with_lock",
  "read-modify-write under a lock"
)

edge("fairu::dir?", :refines, "fairu::exists?", "exists and is a directory")
edge("fairu::file?", :refines, "fairu::exists?", "exists and is a regular file")

edge(
  "fairu::exists?",
  :refines,
  "fairu::info",
  "cheap form of the state lookup"
)

edge(
  "fairu::space",
  :refines,
  "fairu::info",
  "state of the volume not the path"
)

edge("fairu::read", :refines, "fairu::read_bytes", "text is bytes decoded")

edge(
  "fairu::with_temp_file",
  :refines,
  "fairu::with_temp_dir",
  "one file instead of a directory"
)

edge("fairu::append", :refines, "fairu::write", "grows the file in place")
edge("fairu::touch", :refines, "fairu::write", "empty write or time bump")
edge("fairu::copy", :requires, "fairu::exists?", "source must be there")
edge("fairu::link", :requires, "fairu::exists?", "target is checked first")

edge(
  "fairu::watch",
  :requires,
  "fairu::exists?",
  "the path must be there to watch"
)

edge("fairu::place", :requires, "fairu::home", "fallback root of every tier")
