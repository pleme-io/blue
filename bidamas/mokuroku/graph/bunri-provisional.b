space("bunri?", {status: :provisional})

verb(
  "bunri?",
  "confine",
  {
    kind: :effect,
    shape: "confine(f, profile, opts) -> value",
    laterals: ["capability", "deadline", "error", "process"],
    fleet: "sui",
    today: "absent",
    meaning: "run a function or command inside a profile",
    wave: 2,
    origin: "D"
  }
)

verb(
  "bunri?",
  "drop",
  {
    kind: :effect,
    shape: "drop(privileges) -> nil",
    laterals: ["capability", "process"],
    fleet: nil,
    today: "absent",
    meaning: "give up privileges for good",
    wave: 3,
    origin: "D",
    contract: "drop(privileges, n) -> nil"
  }
)

verb(
  "bunri?",
  "egress",
  {
    kind: :decl,
    shape: "egress(rules) -> rules",
    laterals: ["capability", "config"],
    fleet: nil,
    today: "absent",
    meaning: "which hosts and ports a run may reach",
    wave: 2,
    origin: "D"
  }
)

verb(
  "bunri?",
  "elevate",
  {
    kind: :decl,
    shape: "elevate(profile, why, until) -> profile",
    laterals: ["log", "switch", "time"],
    fleet: "sekiban",
    today: "absent",
    meaning: "time-boxed, logged widening set by the root only",
    wave: 3,
    origin: "D"
  }
)

verb(
  "bunri?",
  "embed",
  {
    kind: :effect,
    shape: "embed(module, profile, opts) -> instance",
    laterals: ["capability", "resource"],
    fleet: "blue-lang-wasm",
    today: "absent",
    meaning: "run a WASM module with exactly the granted imports",
    wave: 3,
    origin: "D"
  }
)

verb(
  "bunri?",
  "exceeds",
  {
    kind: :pure,
    shape: "exceeds(observed, profile) -> [access]",
    laterals: ["trace", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "accesses a profile did not grant",
    wave: 3,
    origin: "D"
  }
)

verb(
  "bunri?",
  "filter",
  {
    kind: :decl,
    shape: "filter(syscalls) -> filter",
    laterals: ["capability", "config"],
    fleet: nil,
    today: "absent",
    meaning: "allow-list of system calls (seccomp)",
    wave: 4,
    origin: "D",
    contract: "filter(syscalls, f, opts) -> filter"
  }
)

verb(
  "bunri?",
  "learn",
  {
    kind: :effect,
    shape: "learn(command, opts) -> profile",
    laterals: ["process", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "run once, record what it touched, as a profile",
    wave: 3,
    origin: "D"
  }
)

verb(
  "bunri?",
  "limit",
  {
    kind: :decl,
    shape: "limit(resource, amount) -> limit",
    laterals: ["config", "deadline", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "cap CPU, memory, files or time for a run",
    wave: 2,
    origin: "D"
  }
)

verb(
  "bunri?",
  "profile",
  {
    kind: :decl,
    shape: "profile(name, allow, opts) -> profile",
    laterals: ["capability", "config"],
    fleet: "blue-lang-waku",
    today: "absent",
    meaning: "what a run may touch: paths, hosts, processes",
    wave: 1,
    origin: "D",
    contract: "profile(name, opts) -> profile"
  }
)

verb(
  "bunri?",
  "scrub_env",
  {
    kind: :pure,
    shape: "scrub_env(env, keep) -> env",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "environment with everything but the kept names removed",
    wave: 1,
    origin: "D"
  }
)

verb(
  "bunri?",
  "tighten",
  {
    kind: :pure,
    shape: "tighten(profile, observed) -> profile",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "narrowest profile that still permits what was observed",
    wave: 3,
    origin: "D"
  }
)

edge("bunri?::learn", :composes, "bunri?::confine", "run once while observing")

edge(
  "bunri?::exceeds",
  :composes,
  "bunri?::learn",
  "observations beyond the profile"
)

edge("bunri?::confine", :composes, "bunri?::limit", "limits applied to the run")

edge(
  "bunri?::confine",
  :composes,
  "bunri?::scrub_env",
  "clean environment for the child"
)

edge("bunri?::elevate", :composes, "nisshi::audit", "every elevation is logged")

edge(
  "bunri?::tighten",
  :composes,
  "waku::narrow",
  "meet of profile and observation"
)

edge("bunri?::limit", :guards, "bunri?::confine", "caps a run")
edge("bunri?::scrub_env", :guards, "bunri?::confine", "no stray secrets in env")

edge(
  "bunri?::confine",
  :guards,
  "kengen?::delegate",
  "delegation stays inside the profile"
)

edge(
  "bunri?::elevate",
  :inverse,
  "waku::narrow",
  "the only widening, root only"
)

edge(
  "bunri?::drop",
  :pairs,
  "bunri?::confine",
  "drop privileges before running work"
)

edge(
  "bunri?::profile",
  :pairs,
  "bunri?::egress",
  "egress is part of the profile"
)

edge(
  "bunri?::embed",
  :refines,
  "bunri?::confine",
  "a module instead of a process"
)

edge("bunri?::egress", :refines, "bunri?::profile", "network part of a profile")

edge(
  "bunri?::filter",
  :refines,
  "bunri?::profile",
  "system calls as a profile part"
)

edge(
  "bunri?::profile",
  :refines,
  "waku::frame",
  "a frame for processes and hosts"
)

edge("bunri?::tighten", :requires, "bunri?::learn", "narrow to what was seen")
edge("bunri?::confine", :requires, "bunri?::profile", "run inside a profile")
edge("bunri?::embed", :requires, "waku::imports", "only the granted imports")
