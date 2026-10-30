space("mokei?", {status: :provisional})

verb(
  "mokei?",
  "ask",
  {
    kind: :effect,
    shape: "ask(model, prompt, opts) -> reply",
    laterals: %w[cache deadline ratelimit retry trace],
    fleet: "arnes-anthropic",
    today: "partial:chokkan",
    wave: 2,
    origin: "G"
  }
)

verb(
  "mokei?",
  "classify",
  {
    kind: :effect,
    shape: "classify(model, input, labels, opts) -> {label, confidence}",
    laterals: %w[cache deadline retry],
    fleet: "chokkan",
    today: "partial:chokkan",
    meaning: "one label from a closed set, with confidence",
    wave: 2,
    origin: "G",
    contract: "classify(model, input, opts) -> {label, confidence}"
  }
)

verb(
  "mokei?",
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
  "mokei?",
  "embed",
  {
    kind: :effect,
    shape: "embed(model, texts, opts) -> vectors",
    laterals: %w[cache deadline ratelimit retry],
    fleet: "codesearch",
    today: "absent",
    meaning: "vectors for texts, one per text",
    wave: 2,
    origin: "G"
  }
)

verb(
  "mokei?",
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
  "mokei?",
  "extract",
  {
    kind: :effect,
    shape: "extract(model, text, shape) -> record",
    laterals: %w[deadline retry validate],
    fleet: nil,
    today: "absent",
    meaning: "a record of the given shape pulled from text",
    wave: 2,
    origin: "G",
    contract: "extract(model, text, opts) -> record"
  }
)

verb(
  "mokei?",
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
  "mokei?",
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
  "mokei?",
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
  "mokei?",
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
  "mokei?",
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
  "mokei?",
  "model",
  {
    kind: :decl,
    shape: "model(provider, id, opts) -> model",
    laterals: %w[config validate],
    fleet: "arnes-anthropic",
    today: "absent",
    meaning: "declare a model: window, price, tier",
    wave: 1,
    origin: "G"
  }
)

verb(
  "mokei?",
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
  "mokei?",
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
  "mokei?",
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
  "mokei?",
  "stream",
  {
    kind: :stream,
    shape: "stream(model, prompt, f, opts) -> reply",
    laterals: %w[cancel deadline trace],
    fleet: "arnes-anthropic",
    today: "absent",
    meaning: "call f for each delta of a reply",
    wave: 2,
    origin: "G"
  }
)

verb(
  "mokei?",
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
  "mokei?",
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

edge("mokei?::total", :composes, "mokei?::cost", "sum of costs")
edge("mokei?::prompt", :composes, "mokei?::example", "plus worked cases")
edge("mokei?::prompt", :composes, "mokei?::message", "a prompt is turns")
edge("mokei?::list", :generalizes, "mokei?::info", "catalog of models")
edge("mokei?::ask", :guards, "mokei?::fit", "window checked first")
edge("mokei?::stream", :lifts, "mokei?::ask", "ask as deltas")
edge("mokei?::render", :pairs, "bunsho::fill", "templates fill slots")
edge("mokei?::classify", :pairs, "chokkan::choice", "same job, two surfaces")
edge("mokei?::embed", :pairs, "kensaku?::similarity", "vectors then closeness")
edge("mokei?::fit", :pairs, "mokei?::prefix", "cut after the cached prefix")
edge("mokei?::ledger", :pairs, "mokei?::total", "record and sum")
edge("mokei?::classify", :refines, "mokei?::ask", "ask with labels")
edge("mokei?::extract", :refines, "mokei?::ask", "ask with a shape")
edge("mokei?::ask", :requires, "dairi?::budget", "spend is capped")
edge("mokei?::prefix", :requires, "mokei?::ask", "provider caches the prefix")
edge("mokei?::ledger", :requires, "mokei?::cost", "entries carry cost")
edge("mokei?::cost", :requires, "mokei?::info", "price comes from the model")
edge("mokei?::model", :requires, "mokei?::info", "a model has facts")
edge("mokei?::info", :requires, "mokei?::list", "facts from the catalog")
edge("mokei?::embed", :requires, "mokei?::model", "embedding model")

edge(
  "mokei?::tokens",
  :requires,
  "mokei?::model",
  "tokenizer belongs to a model"
)

edge("mokei?::example", :requires, "mokei?::prompt", "part of a prompt")
edge("mokei?::message", :requires, "mokei?::prompt", "part of a prompt")
edge("mokei?::prefix", :requires, "mokei?::prompt", "marks a prompt prefix")
edge("mokei?::render", :requires, "mokei?::prompt", "needs a prompt")
edge("mokei?::ask", :requires, "mokei?::render", "wire form of the prompt")
edge("mokei?::fit", :requires, "mokei?::tokens", "count before cut")
edge("mokei?::stream", :requires, "mokei?::tokens", "usage counted per delta")

edge(
  "mokei?::extract",
  :requires,
  "saiten?::check",
  "shape check of the record"
)
