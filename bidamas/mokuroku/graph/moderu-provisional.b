space("moderu?", {status: :provisional})

verb(
  "moderu?",
  "ask",
  {
    kind: :effect,
    shape: "ask(model, prompt, opts) -> reply",
    laterals: ["cache", "deadline", "ratelimit", "retry", "trace"],
    fleet: "arnes-anthropic",
    today: "partial:chokkan",
    meaning: "one call to a model; reply holds text, tool uses, usage",
    wave: 2,
    origin: "G"
  }
)

verb(
  "moderu?",
  "classify",
  {
    kind: :effect,
    shape: "classify(model, input, labels, opts) -> {label, confidence}",
    laterals: ["cache", "deadline", "retry"],
    fleet: "chokkan",
    today: "partial:chokkan",
    meaning: "one label from a closed set, with confidence",
    wave: 2,
    origin: "G",
    contract: "classify(model, input, opts) -> {label, confidence}"
  }
)

verb(
  "moderu?",
  "cost",
  {
    kind: :pure,
    shape: "cost(usage, price) -> money",
    laterals: [],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "what a usage record costs at a price",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "embed",
  {
    kind: :effect,
    shape: "embed(model, texts, opts) -> vectors",
    laterals: ["cache", "deadline", "ratelimit", "retry"],
    fleet: "codesearch",
    today: "absent",
    meaning: "vectors for texts, one per text",
    wave: 2,
    origin: "G"
  }
)

verb(
  "moderu?",
  "example",
  {
    kind: :decl,
    shape: "example(input, output) -> example",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "declare one worked case for few-shot prompting",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "extract",
  {
    kind: :effect,
    shape: "extract(model, text, shape) -> record",
    laterals: ["deadline", "retry", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "a record of the given shape pulled from text",
    wave: 2,
    origin: "G",
    contract: "extract(model, text, opts) -> record"
  }
)

verb(
  "moderu?",
  "fit",
  {
    kind: :pure,
    shape: "fit(prompt, window, opts) -> prompt",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "cut a prompt to a token budget, newest kept",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "info",
  {
    kind: :pure,
    shape: "info(model) -> {window, price, tier, tools?}",
    laterals: [],
    fleet: "arnes-anthropic",
    today: "absent",
    meaning: "what a model can take and costs",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "ledger",
  {
    kind: :decl,
    shape: "ledger(path, opts) -> ledger",
    laterals: ["serialize"],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "declare the append-only record of usage",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "list",
  {
    kind: :pure,
    shape: "list(catalog) -> models",
    laterals: [],
    fleet: "arnes-anthropic",
    today: "absent",
    meaning: "the models a catalog serves",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "message",
  {
    kind: :decl,
    shape: "message(role, content) -> message",
    laterals: [],
    fleet: "arnes-core",
    today: "absent",
    meaning: "declare one turn: user, assistant or tool",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "model",
  {
    kind: :decl,
    shape: "model(provider, id, opts) -> model",
    laterals: ["config", "validate"],
    fleet: "arnes-anthropic",
    today: "absent",
    meaning: "declare a model: window, price, tier",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "prefix",
  {
    kind: :pure,
    shape: "prefix(prompt, prefix) -> prompt",
    laterals: ["cache"],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "mark the stable prefix that a provider may cache",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "prompt",
  {
    kind: :decl,
    shape: "prompt(parts) -> prompt",
    laterals: ["validate"],
    fleet: "arnes-core",
    today: "absent",
    meaning: "declare a prompt from system, messages and examples",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "render",
  {
    kind: :pure,
    shape: "render(prompt, format) -> text or messages",
    laterals: ["serialize"],
    fleet: "arnes-core",
    today: "absent",
    meaning: "a prompt in a provider wire form",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "stream",
  {
    kind: :stream,
    shape: "stream(model, prompt, f, opts) -> reply",
    laterals: ["cancel", "deadline", "trace"],
    fleet: "arnes-anthropic",
    today: "absent",
    meaning: "call f for each delta of a reply",
    wave: 2,
    origin: "G"
  }
)

verb(
  "moderu?",
  "tokens",
  {
    kind: :pure,
    shape: "tokens(model, text) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "how many tokens a text costs in a model",
    wave: 1,
    origin: "G"
  }
)

verb(
  "moderu?",
  "total",
  {
    kind: :pure,
    shape: "total(ledger, by) -> totals",
    laterals: [],
    fleet: "arnes-loop",
    today: "absent",
    meaning: "tokens, cost and cache hits per model or session",
    wave: 1,
    origin: "G"
  }
)

edge("moderu?::total", :composes, "moderu?::cost", "sum of costs")
edge("moderu?::prompt", :composes, "moderu?::example", "plus worked cases")
edge("moderu?::prompt", :composes, "moderu?::message", "a prompt is turns")
edge("moderu?::list", :generalizes, "moderu?::info", "catalog of models")
edge("moderu?::ask", :guards, "moderu?::fit", "window checked first")
edge("moderu?::stream", :lifts, "moderu?::ask", "ask as deltas")
edge("moderu?::render", :pairs, "bunsho?::fill", "templates fill slots")
edge("moderu?::classify", :pairs, "chokkan::choice", "same job, two surfaces")
edge("moderu?::embed", :pairs, "kensaku?::similarity", "vectors then closeness")
edge("moderu?::fit", :pairs, "moderu?::prefix", "cut after the cached prefix")
edge("moderu?::ledger", :pairs, "moderu?::total", "record and sum")
edge("moderu?::classify", :refines, "moderu?::ask", "ask with labels")
edge("moderu?::extract", :refines, "moderu?::ask", "ask with a shape")
edge("moderu?::ask", :requires, "dairi?::budget", "spend is capped")
edge("moderu?::prefix", :requires, "moderu?::ask", "provider caches the prefix")
edge("moderu?::ledger", :requires, "moderu?::cost", "entries carry cost")
edge("moderu?::cost", :requires, "moderu?::info", "price comes from the model")
edge("moderu?::model", :requires, "moderu?::info", "a model has facts")
edge("moderu?::info", :requires, "moderu?::list", "facts from the catalog")
edge("moderu?::embed", :requires, "moderu?::model", "embedding model")

edge(
  "moderu?::tokens",
  :requires,
  "moderu?::model",
  "tokenizer belongs to a model"
)

edge("moderu?::example", :requires, "moderu?::prompt", "part of a prompt")
edge("moderu?::message", :requires, "moderu?::prompt", "part of a prompt")
edge("moderu?::prefix", :requires, "moderu?::prompt", "marks a prompt prefix")
edge("moderu?::render", :requires, "moderu?::prompt", "needs a prompt")
edge("moderu?::ask", :requires, "moderu?::render", "wire form of the prompt")
edge("moderu?::fit", :requires, "moderu?::tokens", "count before cut")
edge("moderu?::stream", :requires, "moderu?::tokens", "usage counted per delta")

edge(
  "moderu?::extract",
  :requires,
  "saiten?::check",
  "shape check of the record"
)
