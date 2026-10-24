space("tesuto?", {status: :provisional})

verb(
  "tesuto?",
  "affected",
  {
    kind: :pure,
    shape: "affected(changes, graph) -> [test]",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "the tests that depend on changed code",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "assert",
  {
    kind: :effect,
    shape: "assert(expr) -> nil",
    laterals: ["error", "test"],
    fleet: "blue-lang-test",
    today: "rust:blue-lang-test",
    meaning: "fail the test with a structural diff when expr is false",
    wave: 0,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "calls",
  {
    kind: :pure,
    shape: "calls(spy) -> [call]",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "the recorded calls of a spy, in order",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "case",
  {
    kind: :decl,
    shape: "case(name, f) -> test",
    laterals: ["test"],
    fleet: "blue-lang-test",
    today: "rust:blue-lang-test",
    meaning: "declare one named test",
    wave: 0,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "conforms?",
  {
    kind: :effect,
    shape: "conforms?(provider, contract) -> verdict",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "whether a provider meets a contract",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "contract",
  {
    kind: :decl,
    shape: "contract(consumer, provider, interactions) -> contract",
    laterals: ["test", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare what a consumer expects of a provider",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "cover",
  {
    kind: :effect,
    shape: "cover(target, opts) -> coverage",
    laterals: ["resource", "test"],
    fleet: nil,
    today: "absent",
    meaning: "run tests and record which code ran",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "fake",
  {
    kind: :effect,
    shape: "fake(target, impl, f) -> value",
    laterals: ["capability", "test"],
    fleet: nil,
    today: "absent",
    meaning: "replace a dependency by a fake while f runs",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "fixture",
  {
    kind: :effect,
    shape: "fixture(name) -> content",
    laterals: ["test"],
    fleet: "pleme-testing",
    today: "absent",
    meaning: "read a file kept beside the test",
    wave: 0,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "flaky?",
  {
    kind: :pure,
    shape: "flaky?(history, test) -> Bool",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "whether a test both passed and failed on one revision",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "freeze",
  {
    kind: :effect,
    shape: "freeze(instant, f) -> value",
    laterals: ["test", "time"],
    fleet: nil,
    today: "absent",
    meaning: "run f with the clock fixed at an instant",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "fuzz",
  {
    kind: :effect,
    shape: "fuzz(target, opts) -> [crash]",
    laterals: ["deadline", "resource", "test"],
    fleet: "caixa-cargo-fuzz",
    today: "absent",
    meaning: "feed generated inputs until something fails or time ends",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "list",
  {
    kind: :effect,
    shape: "list(target, opts) -> [test]",
    laterals: ["test"],
    fleet: "blue-lang-test",
    today: "absent",
    meaning: "the tests under a target without running them",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b) -> coverage",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "combine coverage from several runs or shards",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> report",
    laterals: ["serialize", "test"],
    fleet: nil,
    today: "absent",
    meaning: "a JUnit or TAP report to a record",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "quarantine",
  {
    kind: :effect,
    shape: "quarantine(test, reason, until) -> nil",
    laterals: ["switch", "test"],
    fleet: nil,
    today: "absent",
    meaning: "skip a flaky test by a dated, counted entry",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "raises?",
  {
    kind: :pure,
    shape: "raises?(kind, f) -> Bool",
    laterals: ["error", "test"],
    fleet: "blue-lang-test",
    today: "exists:tesuto",
    wave: 0,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "render",
  {
    kind: :pure,
    shape: "render(report, format) -> text",
    laterals: ["serialize", "test"],
    fleet: nil,
    today: "absent",
    meaning: "a test report as text, JUnit or TAP",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "rerun",
  {
    kind: :effect,
    shape: "rerun(test, n) -> [result]",
    laterals: ["retry", "test"],
    fleet: nil,
    today: "absent",
    meaning: "run one test again n times and keep every result",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "run",
  {
    kind: :effect,
    shape: "run(target, opts) -> report",
    laterals: ["deadline", "process", "test"],
    fleet: "blue-lang-test",
    today: "rust:blue-lang-test",
    meaning: "run every test under a target in parallel",
    wave: 0,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "shard",
  {
    kind: :pure,
    shape: "shard(tests, n, i) -> [test]",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "the i-th of n balanced groups of tests",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "snapshot",
  {
    kind: :effect,
    shape: "snapshot(value, opts) -> nil",
    laterals: ["serialize", "test"],
    fleet: "blue-lang-test",
    today: "exists:tesuto",
    wave: 0,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "spy",
  {
    kind: :effect,
    shape: "spy(target, f) -> spy",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "wrap a function so its calls are recorded",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "uncovered",
  {
    kind: :pure,
    shape: "uncovered(coverage) -> [span]",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "code that no test reached",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tesuto?",
  "watch",
  {
    kind: :stream,
    shape: "watch(paths, opts) -> nil",
    laterals: ["cancel", "test"],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "rerun tests when a watched file changes",
    wave: 0,
    origin: "F",
    contract: "watch(paths, f, opts) -> nil"
  }
)

edge("tesuto?::fuzz", :composes, "genin?::shrink", "crashes are shrunk")
edge("tesuto?::run", :composes, "tesuto?::case", "runs the declared tests")

edge(
  "tesuto?::flaky?",
  :composes,
  "tesuto?::rerun",
  "decides from repeated results"
)

edge("tesuto?::affected", :guards, "tesuto?::run", "selects what run must run")
edge("tesuto?::list", :guards, "tesuto?::run", "lists what run would run")
edge("tesuto?::shard", :guards, "tesuto?::run", "splits the run")
edge("tesuto?::fake", :guards, "tesuto?::spy", "a spy wraps the fake")
edge("tesuto?::render", :inverse, "tesuto?::parse", "report to text and back")

edge(
  "tesuto?::run",
  :inverse,
  "tesuto?::quarantine",
  "skips what run would run"
)

edge("tesuto?::parse", :inverse, "tesuto?::render", "report to text and back")

edge(
  "tesuto?::quarantine",
  :inverse,
  "tesuto?::run",
  "skips what run would run"
)

edge("tesuto?::watch", :lifts, "tesuto?::run", "reruns on change")
edge("tesuto?::fixture", :pairs, "fairu::with_temp_dir", "files for a test")
edge("tesuto?::conforms?", :pairs, "habu::get", "checks a remote provider")
edge("tesuto?::parse", :pairs, "habu::list", "CI reports come from runs")
edge("tesuto?::rerun", :pairs, "habu::rerun", "CI rerun versus test rerun")
edge("tesuto?::run", :pairs, "hadome::judge", "runs report ratcheted counts")
edge("tesuto?::cover", :pairs, "heni::run", "coverage and mutation score")

edge(
  "tesuto?::snapshot",
  :pairs,
  "hinagata?::fresh?",
  "a golden file is a snapshot of output"
)

edge("tesuto?::watch", :pairs, "kaihatsu?::watch", "the same loop")
edge("tesuto?::fuzz", :pairs, "okite::generate", "both draw inputs")
edge("tesuto?::case", :pairs, "okite::law", "a law is a generated test")

edge(
  "tesuto?::affected",
  :pairs,
  "rebyuu?::ready?",
  "only affected checks are required"
)

edge("tesuto?::render", :pairs, "rebyuu?::ready?", "reports feed readiness")

edge(
  "tesuto?::contract",
  :pairs,
  "rirezu?::breaking?",
  "breaking changes break contracts"
)

edge("tesuto?::list", :pairs, "tesuto?::affected", "list what is selected")
edge("tesuto?::uncovered", :pairs, "tesuto?::affected", "gaps versus impact")
edge("tesuto?::spy", :pairs, "tesuto?::calls", "spy records, calls reads")

edge(
  "tesuto?::snapshot",
  :pairs,
  "tesuto?::fixture",
  "files kept beside the test"
)

edge("tesuto?::fake", :pairs, "tesuto?::freeze", "freeze is a fake clock")
edge("tesuto?::shard", :pairs, "tesuto?::merge", "shards then merged reports")
edge("tesuto?::flaky?", :pairs, "tesuto?::parse", "history comes from reports")

edge(
  "tesuto?::assert",
  :pairs,
  "tesuto?::raises?",
  "raises? is a form of assert"
)

edge("tesuto?::run", :pairs, "tesuto?::shard", "big runs are sharded")
edge("tesuto?::merge", :refines, "jisho::merge", "merge for coverage records")
edge("tesuto?::fuzz", :refines, "okite::holds?", "unguided input, not a law")

edge(
  "tesuto?::conforms?",
  :refines,
  "tesuto?::assert",
  "a contract is an assertion"
)

edge(
  "tesuto?::raises?",
  :refines,
  "tesuto?::assert",
  "asserts an error of that kind"
)

edge("tesuto?::snapshot", :refines, "tesuto?::assert", "stored expected value")
edge("tesuto?::spy", :refines, "tesuto?::fake", "a fake that records")
edge("tesuto?::cover", :refines, "tesuto?::run", "run with instruments")
edge("tesuto?::rerun", :refines, "tesuto?::run", "run again n times")
edge("tesuto?::assert", :requires, "deeta::diff", "failure prints the diff")

edge(
  "tesuto?::quarantine",
  :requires,
  "hadome::waive",
  "a counted dated exception"
)

edge("tesuto?::freeze", :requires, "jikan::now", "fixes the clock now reads")

edge(
  "tesuto?::affected",
  :requires,
  "kenshutsu?::call_graph",
  "dependency edges"
)

edge("tesuto?::case", :requires, "tesuto?::assert", "a test holds assertions")

edge(
  "tesuto?::contract",
  :requires,
  "tesuto?::conforms?",
  "declared to be checked"
)

edge("tesuto?::merge", :requires, "tesuto?::cover", "combines coverage")
edge("tesuto?::uncovered", :requires, "tesuto?::cover", "reads coverage")
edge("tesuto?::quarantine", :requires, "tesuto?::flaky?", "only flaky tests")
edge("tesuto?::shard", :requires, "tesuto?::list", "splits the listed tests")
