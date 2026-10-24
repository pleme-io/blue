space("gamen?", {status: :provisional})

verb(
  "gamen?",
  "apply",
  {
    kind: :effect,
    shape: "apply(app, patches) -> nil",
    laterals: ["idempotent"],
    fleet: "madori",
    today: "absent",
    meaning: "make a surface show the patches",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "check",
  {
    kind: :pure,
    shape: "check(tree, rules) -> findings",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:gamen",
    meaning: "find accessibility and layout faults in a tree",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "choose",
  {
    kind: :effect,
    shape: "choose(items, opts) -> item or nil",
    laterals: ["deadline"],
    fleet: "egaku",
    today: "absent",
    meaning: "the human picks from a list",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "component",
  {
    kind: :decl,
    shape: "component(name, spec) -> component",
    laterals: ["switch", "validate"],
    fleet: "pleme-widget-spec",
    today: "exists:gamen",
    meaning: "declare a reusable view: props, state, events",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "contrast",
  {
    kind: :pure,
    shape: "contrast(a, b) -> ratio",
    laterals: [],
    fleet: nil,
    today: "exists:gamen",
    meaning: "WCAG contrast ratio of two colors",
    wave: 0,
    origin: "G"
  }
)

verb(
  "gamen?",
  "coverage",
  {
    kind: :pure,
    shape: "coverage(bundles) -> report",
    laterals: ["validate"],
    fleet: "namimado",
    today: "absent",
    meaning: "keys that a locale still lacks",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "describe",
  {
    kind: :pure,
    shape: "describe(node) -> {role, name, state}",
    laterals: [],
    fleet: "namimado",
    today: "absent",
    meaning: "the accessibility meaning of a node",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "diff",
  {
    kind: :pure,
    shape: "diff(old, new) -> patches",
    laterals: [],
    fleet: "egaku",
    today: "absent",
    meaning: "changes between two trees, as patches",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "direction",
  {
    kind: :pure,
    shape: "direction(locale) -> ltr or rtl",
    laterals: [],
    fleet: "pleme-i18n",
    today: "absent",
    meaning: "reading direction of a locale",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "focus",
  {
    kind: :effect,
    shape: "focus(app, target) -> nil",
    laterals: [],
    fleet: "egaku",
    today: "absent",
    meaning: "move keyboard focus to a node",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "get",
  {
    kind: :pure,
    shape: "get(subject, key) -> value or nil",
    laterals: [],
    fleet: "egaku",
    today: "absent",
    meaning: "read a state value, theme token or key binding; nil if absent",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "hydrate",
  {
    kind: :effect,
    shape: "hydrate(tree, root, opts) -> app",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "attach handlers and state to server-rendered markup",
    wave: 2,
    origin: "I"
  }
)

verb(
  "gamen?",
  "island",
  {
    kind: :decl,
    shape: "island(view, opts) -> node",
    laterals: ["switch"],
    fleet: nil,
    today: "absent",
    meaning: "mark a subtree that hydrates on its own in the browser",
    wave: 2,
    origin: "I"
  }
)

verb(
  "gamen?",
  "labels",
  {
    kind: :decl,
    shape: "labels(enum, entries) -> table",
    laterals: ["validate"],
    fleet: "lilitu",
    today: "exists:gamen",
    meaning: "display text keyed by each backend enum value",
    wave: 1,
    origin: "I"
  }
)

verb(
  "gamen?",
  "layout",
  {
    kind: :pure,
    shape: "layout(kind, children, opts) -> tree",
    laterals: [],
    fleet: "egaku",
    today: "exists:gamen",
    meaning: "place nodes in a size: stack, flex or grid",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "localize",
  {
    kind: :pure,
    shape: "localize(value, locale, opts) -> text",
    laterals: [],
    fleet: "pleme-i18n",
    today: "absent",
    meaning: "a number, date or money as a locale writes it",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "measure",
  {
    kind: :pure,
    shape: "measure(subject, space) -> size or number",
    laterals: [],
    fleet: "garasu",
    today: "absent",
    meaning: "natural size of a node, or a level of a signal",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "notify",
  {
    kind: :effect,
    shape: "notify(message, opts) -> nil",
    laterals: ["ratelimit"],
    fleet: "tsuuchi",
    today: "absent",
    meaning: "raise a desktop or phone notification",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "on",
  {
    kind: :decl,
    shape: "on(node, event, handler) -> node",
    laterals: [],
    fleet: "egaku",
    today: "absent",
    meaning: "bind a handler to an event of a node",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "order",
  {
    kind: :pure,
    shape: "order(tree) -> ids",
    laterals: [],
    fleet: "egaku",
    today: "absent",
    meaning: "tab order of the focusable nodes",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "paint",
  {
    kind: :pure,
    shape: "paint(text, style) -> text",
    laterals: [],
    fleet: "katsuji",
    today: "absent",
    meaning: "text with ink and attributes, never raw escape codes",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "plural",
  {
    kind: :pure,
    shape: "plural(n, locale, forms) -> text",
    laterals: [],
    fleet: "pleme-i18n",
    today: "absent",
    meaning: "the word form that suits n in a locale",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "progress",
  {
    kind: :stream,
    shape: "progress(total, opts) -> handle",
    laterals: [],
    fleet: "kazari",
    today: "absent",
    meaning: "a progress line that the program advances",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "prompt",
  {
    kind: :effect,
    shape: "prompt(question, opts) -> answer",
    laterals: ["deadline"],
    fleet: "egaku",
    today: "absent",
    meaning: "ask the human: text, yes-no or secret",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "put",
  {
    kind: :effect,
    shape: "put(subject, key, value) -> value",
    laterals: ["validate"],
    fleet: "egaku",
    today: "absent",
    meaning: "set a state value, theme token or key binding",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "render",
  {
    kind: :pure,
    shape: "render(tree, target, opts) -> output",
    laterals: ["serialize"],
    fleet: "pleme-widget-gen",
    today: "exists:gamen",
    meaning: "tree to html, ansi, svg or widget spec text",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "send",
  {
    kind: :effect,
    shape: "send(app, event) -> nil",
    laterals: [],
    fleet: "madori",
    today: "absent",
    meaning: "deliver one event to a running app",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "show",
  {
    kind: :effect,
    shape: "show(node, opts) -> nil",
    laterals: [],
    fleet: "kazari",
    today: "exists:gamen",
    meaning: "put a node on the terminal as styled output",
    wave: 0,
    origin: "G"
  }
)

verb(
  "gamen?",
  "start",
  {
    kind: :effect,
    shape: "start(app, surface, opts) -> handle",
    laterals: ["process", "resource"],
    fleet: "madori",
    today: "absent",
    meaning: "run an app on a terminal, window or page",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "state",
  {
    kind: :decl,
    shape: "state(initial, opts) -> store",
    laterals: ["serialize"],
    fleet: "egaku",
    today: "absent",
    meaning: "declare the store that holds a view state",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "stop",
  {
    kind: :effect,
    shape: "stop(handle, opts) -> nil",
    laterals: ["cancel", "resource"],
    fleet: "madori",
    today: "absent",
    meaning: "end a running app and free its surface",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gamen?",
  "style",
  {
    kind: :pure,
    shape: "style(node, theme) -> styled node",
    laterals: [],
    fleet: "ishou",
    today: "exists:gamen",
    meaning: "resolve semantic tokens on a node to colors and sizes",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "theme",
  {
    kind: :decl,
    shape: "theme(tokens, mode) -> theme",
    laterals: ["config"],
    fleet: "irodori",
    today: "exists:gamen",
    meaning: "declare a theme: Nord tokens for light and dark",
    wave: 0,
    origin: "G"
  }
)

verb(
  "gamen?",
  "translate",
  {
    kind: :pure,
    shape: "translate(key, locale, args) -> text",
    laterals: [],
    fleet: "pleme-i18n",
    today: "absent",
    meaning: "the message for a key in a locale",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "update",
  {
    kind: :effect,
    shape: "update(store, key, f) -> value",
    laterals: ["idempotent"],
    fleet: "egaku",
    today: "absent",
    meaning: "change a state value to f of the old value",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "view",
  {
    kind: :decl,
    shape: "view(kind, props, children) -> node",
    laterals: ["validate"],
    fleet: "egaku",
    today: "exists:gamen",
    meaning: "declare one UI node with props and children",
    wave: 1,
    origin: "G"
  }
)

verb(
  "gamen?",
  "watch",
  {
    kind: :stream,
    shape: "watch(store, f, opts) -> nil",
    laterals: ["cancel"],
    fleet: "egaku",
    today: "absent",
    meaning: "call f for every state change until stopped",
    wave: 2,
    origin: "G"
  }
)

edge(
  "gamen?::hydrate",
  :composes,
  "burauza::listen",
  "handlers on server markup"
)

edge("gamen?::check", :composes, "gamen?::contrast", "color pairs")
edge("gamen?::check", :composes, "gamen?::describe", "labels and roles")
edge("gamen?::update", :composes, "gamen?::get", "reads the old value")
edge("gamen?::render", :composes, "gamen?::layout", "place, then draw")
edge("gamen?::localize", :composes, "gamen?::plural", "counts in text")
edge("gamen?::translate", :composes, "gamen?::plural", "forms inside messages")
edge("gamen?::update", :composes, "gamen?::put", "writes f of old")
edge("gamen?::start", :composes, "gamen?::render", "first frame")
edge("gamen?::render", :composes, "gamen?::style", "tokens before output")

edge(
  "gamen?::component",
  :composes,
  "gamen?::view",
  "a component is views plus state"
)

edge(
  "gamen?::state",
  :generalizes,
  "gamen?::get",
  "reads and writes go through the store"
)

edge(
  "gamen?::theme",
  :generalizes,
  "gamen?::style",
  "style resolves theme tokens"
)

edge("gamen?::check", :guards, "gamen?::render", "no output with faults")
edge("gamen?::contrast", :guards, "gamen?::theme", "a theme must meet contrast")
edge("gamen?::coverage", :guards, "gamen?::translate", "every key has a text")
edge("gamen?::put", :inverse, "gamen?::get", "write is the other face of read")
edge("gamen?::get", :inverse, "gamen?::put", "write is the other face of read")
edge("gamen?::stop", :inverse, "gamen?::start", "ends the app")
edge("gamen?::start", :inverse, "gamen?::stop", "ends the app")
edge("gamen?::watch", :lifts, "gamen?::get", "get as a stream of changes")
edge("gamen?::progress", :lifts, "gamen?::show", "show as a stream of updates")

edge(
  "gamen?::labels",
  :pairs,
  "danpen::check",
  "enum mirrors refused, labels allowed"
)

edge("gamen?::diff", :pairs, "gamen?::apply", "patches go to a surface")
edge("gamen?::describe", :pairs, "gamen?::check", "facts then rules")
edge("gamen?::prompt", :pairs, "gamen?::choose", "ask in two forms")
edge("gamen?::hydrate", :pairs, "gamen?::island", "islands hydrate alone")
edge("gamen?::labels", :pairs, "gamen?::localize", "labels per locale")
edge("gamen?::send", :pairs, "gamen?::on", "an event needs a handler")
edge("gamen?::get", :pairs, "gamen?::put", "read and write of one key")
edge("gamen?::focus", :pairs, "gamen?::send", "focus changes are events")
edge("gamen?::start", :pairs, "gamen?::stop", "open and close an app")
edge("gamen?::watch", :pairs, "gamen?::update", "a change fires a watch")
edge("gamen?::choose", :refines, "gamen?::prompt", "a prompt with a closed set")
edge("gamen?::show", :refines, "gamen?::render", "render to the terminal")
edge("gamen?::notify", :refines, "gamen?::send", "an event for the person")
edge("gamen?::paint", :refines, "gamen?::style", "style applied to text")
edge("gamen?::island", :refines, "gamen?::view", "a view hydrated alone")
edge("gamen?::translate", :requires, "bunsho?::fill", "messages are templates")
edge("gamen?::apply", :requires, "byouga?::draw", "the GPU path of apply")

edge(
  "gamen?::view",
  :requires,
  "gamen?::component",
  "a view may be a component"
)

edge("gamen?::paint", :requires, "gamen?::contrast", "ink must be readable")
edge("gamen?::apply", :requires, "gamen?::diff", "patches come from a diff")

edge(
  "gamen?::layout",
  :requires,
  "gamen?::direction",
  "right to left flips layout"
)

edge("gamen?::notify", :requires, "gamen?::localize", "text in the user locale")
edge("gamen?::layout", :requires, "gamen?::measure", "sizes before positions")
edge("gamen?::progress", :requires, "gamen?::measure", "bar width from space")

edge(
  "gamen?::component",
  :requires,
  "gamen?::on",
  "a component declares its events"
)

edge("gamen?::choose", :requires, "gamen?::order", "choices keep an order")
edge("gamen?::focus", :requires, "gamen?::order", "focus moves along tab order")

edge(
  "gamen?::hydrate",
  :requires,
  "gamen?::render",
  "the server markup to attach to"
)

edge("gamen?::prompt", :requires, "gamen?::show", "a question is output first")
edge("gamen?::view", :requires, "gamen?::state", "a view reads state")
edge("gamen?::style", :requires, "gamen?::theme", "needs a theme")
edge("gamen?::coverage", :requires, "gamen?::translate", "reads message keys")
edge("gamen?::describe", :requires, "gamen?::view", "reads role and state")
edge("gamen?::measure", :requires, "gamen?::view", "a node has a size")
edge("gamen?::on", :requires, "gamen?::view", "binds to a node")
edge("gamen?::order", :requires, "gamen?::view", "reads the tree")
edge("gamen?::localize", :requires, "kinyuu?::render", "money text")
edge("gamen?::start", :requires, "ugoki?::clock", "redraws follow a clock")
