gap(
  "G1",
  :open,
  "a tatara-lisp word whose name holds a `-` has no blue spelling (the kebab wall), so `cond`, `keys` and `values` are unbound",
  opened("2026-09-29")
)

gap(
  "G2",
  :closed,
  "no data-definition surface: a record could only be faked with a macro",
  opened("2026-09-29"),
  closed("2026-11-06")
)

gap(
  "G3",
  :open,
  "macros expand out of order with the check stage and can reach the host at expansion",
  opened("2026-09-29")
)

gap(
  "G4",
  :open,
  "an error value does not print, compare or render as a value, and a catch-all swallows a bug as it swallows a refusal",
  opened("2026-09-29")
)

gap(
  "G5",
  :closed,
  "integer arithmetic wrapped silently",
  opened("2026-09-29"),
  closed("2026-11-06")
)

gap(
  "G6",
  :closed,
  "the main path had no execution bounds and no call stack",
  opened("2026-09-29"),
  closed("2026-11-06")
)

gap(
  "G7",
  :closed,
  "a persistent update copied the whole structure",
  opened("2026-09-29"),
  closed("2026-11-06")
)

gap(
  "G8",
  :open,
  "the typed contract is not enforced at its boundary, and the check stage stops at its first error",
  opened("2026-09-29"),
  owner("docs/SAFETY.md row 7")
)

gap(
  "G9",
  :open,
  "effects are declared and enforced nowhere on a program: a configured-off host word still binds",
  opened("2026-09-29"),
  owner("docs/SAFETY.md row 8")
)

gap(
  "G10",
  :open,
  "a package's identity and version decide nothing at load",
  opened("2026-09-29"),
  owner("docs/SAFETY.md row 13")
)

gap(
  "G11",
  :open,
  "tatara's channel words have no blue spelling, so a channel cannot be put to and taken from",
  opened("2026-09-29")
)

gap(
  "G12",
  :open,
  "values print more than one way, and a JSON object does not read back as the map it came from",
  opened("2026-09-29")
)

gap(
  "G13",
  :closed,
  "no destructuring, rest parameters or keyword arguments: rest parameters and `**` arguments landed first, and `case` patterns with a destructuring binding closed it (spec/rows/patterns.b)",
  opened("2026-09-29"),
  closed("2026-11-08"),
  owner("docs/HORIZON.md H1")
)

gap(
  "G14",
  :closed,
  "tooling could not observe a running program",
  opened("2026-09-29"),
  closed("2026-10-11")
)

gap(
  "G15",
  :closed,
  "most of the language had no executable specification",
  opened("2026-09-29"),
  closed("2026-09-29"),
  owner("spec/README.md")
)

gap(
  "G16",
  :open,
  "the wasm ABI runs no packages, and a primitive needs a Rust edit to cross it",
  opened("2026-09-29")
)

gap(
  "G17",
  :open,
  "lazy sequences do not compose with the list words, and realizing an endless one aborts the process",
  opened("2026-09-29")
)

gap(
  "G18",
  :open,
  "a closure is a foreign value on the VM, so it is not equal to itself and not a procedure",
  opened("2026-09-29")
)

gap(
  "G19",
  :open,
  "a VM failure is rendered by its wrapper, with a byte range for a place, and some words refuse in their own words",
  opened("2026-09-29")
)

gap(
  "G20",
  :open,
  "the wasm component holds no execution bounds, and its stack runs out before the call-depth budget",
  opened("2026-11-07"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G21",
  :open,
  "a host error on the component carries the platform's errno",
  opened("2026-11-07"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G22",
  :open,
  "a capability the component lacks refuses in its own words",
  opened("2026-11-07"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G23",
  :open,
  "`nats_connect` panics on the component for want of a pid, and only sometimes",
  opened("2026-11-07"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G24",
  :open,
  "the wasm component carries no TLS (ring's C has no wasm build), so an https or TLS connect is refused there in words of its own",
  opened("2026-11-16"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G25",
  :closed,
  "false and the empty list were both nil in native code",
  opened("2026-11-20"),
  closed("2026-11-21"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G26",
  :closed,
  "a map was an association list in native code",
  opened("2026-11-20"),
  closed("2026-11-21"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G27",
  :closed,
  "deep and tail recursion, an index past either end and the interpolation of a number crashed a native program",
  opened("2026-11-20"),
  closed("2026-11-21"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G28",
  :closed,
  "rest parameters and `drop` answered wrongly in native code",
  opened("2026-11-20"),
  closed("2026-11-21"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G29",
  :open,
  "native code gives nil back from `to_s` unchanged, where every other column renders it as the empty string",
  opened("2026-11-25"),
  owner("docs/ROADMAP.md, placement parity")
)

gap(
  "G30",
  :open,
  "tatara-lisp-eval 0.4.26 lifts a value back to code twice at each level of a one-argument macro call, so nested expansion doubles its work per level",
  opened("2026-11-25"),
  owner("docs/COHESION.md, U11")
)

gap(
  "G31",
  :open,
  "on tatara-lisp-eval 0.4.26 a quote inside a quote evaluates to an opaque value, not a walkable list",
  opened("2026-11-25"),
  owner("docs/COHESION.md, U11")
)

gap(
  "G32",
  :open,
  "one authority vocabulary: a service's access effects and the runtime's capabilities are two enums spelled two ways",
  opened("2026-11-07"),
  owner("docs/HORIZON.md H11"),
  was("G24")
)

gap(
  "G33",
  :open,
  "pure by default: a run, a hosted load and an embedder with no declaration reach the host",
  opened("2026-11-07"),
  owner("docs/HORIZON.md H12"),
  was("G25")
)

gap(
  "G34",
  :open,
  "authority per bidama at run time: one hold covers the whole interpreter",
  opened("2026-11-07"),
  owner("docs/HORIZON.md H13"),
  was("G26")
)

gap(
  "G35",
  :open,
  "authority as a value: no grant, attenuation or revocation per call",
  opened("2026-11-07"),
  owner("docs/HORIZON.md H15"),
  was("G27")
)

gap(
  "G36",
  :open,
  "every placement derived from `access`: most placements run with a boundary written by hand, or none",
  opened("2026-11-07"),
  owner("docs/HORIZON.md H16"),
  was("G28")
)

gap(
  "G37",
  :open,
  "parity of authority: each placement keeps its own effect table, and nothing proves they agree",
  opened("2026-11-07"),
  owner("docs/HORIZON.md H17"),
  was("G29")
)
