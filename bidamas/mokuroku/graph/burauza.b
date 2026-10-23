space("burauza", {status: :ratified})

verb(
  "burauza",
  "apply",
  {
    kind: :effect,
    shape: "apply(app, patches) -> nil",
    laterals: ["capability", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "change the live page by a patch list",
    wave: 2,
    origin: "I"
  }
)

verb(
  "burauza",
  "install",
  {
    kind: :effect,
    shape: "install(app, opts) -> registration",
    laterals: ["capability", "config"],
    fleet: nil,
    today: "absent",
    meaning: "register the service worker and manifest so the app installs",
    wave: 2,
    origin: "I"
  }
)

verb(
  "burauza",
  "listen",
  {
    kind: :effect,
    shape: "listen(root, opts) -> handle",
    laterals: ["capability", "cancel"],
    fleet: nil,
    today: "absent",
    meaning: "forward page events under a root to the app",
    wave: 2,
    origin: "I"
  }
)

verb(
  "burauza",
  "mount",
  {
    kind: :effect,
    shape: "mount(page, selector, tree) -> app",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "render a tree into the page element a selector names",
    wave: 2,
    origin: "I"
  }
)

verb(
  "burauza",
  "request",
  {
    kind: :effect,
    shape: "request(url, input, opts) -> response",
    laterals: ["capability", "deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "one HTTP request through the browser fetch import",
    wave: 2,
    origin: "I"
  }
)

verb(
  "burauza",
  "save",
  {
    kind: :effect,
    shape: "save(cache, store, opts) -> nil",
    laterals: ["capability", "cache", "serialize"],
    fleet: nil,
    today: "absent",
    meaning: "keep cache entries in IndexedDB across reloads",
    wave: 2,
    origin: "I"
  }
)

edge("burauza::apply", :composes, "gamen?::diff", "the patch list")
edge("burauza::mount", :composes, "gamen?::render", "tree to page nodes")
edge("burauza::listen", :composes, "gamen?::send", "each page event to the app")

edge(
  "burauza::mount",
  :pairs,
  "burauza::listen",
  "events from the mounted root"
)

edge("burauza::install", :pairs, "burauza::save", "offline shell and data")
edge("burauza::request", :pairs, "danpen::hash", "persisted id instead of text")
edge("burauza::save", :pairs, "kyasshu::normalize", "entities kept offline")
edge("burauza::apply", :refines, "gamen?::apply", "the browser surface")
edge("burauza::save", :refines, "kyasshu::save", "IndexedDB as the disk")

edge(
  "burauza::request",
  :refines,
  "tsuushin::request",
  "the browser fetch import"
)

edge("burauza::apply", :requires, "burauza::mount", "a live root")

edge(
  "burauza::install",
  :requires,
  "burauza::request",
  "fetches the worker script"
)
