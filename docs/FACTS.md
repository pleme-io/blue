---
kind: explanation
summary: how facts decide and defaults follow; the one mechanism behind every automatic choice blue makes, the contract each default meets, and the waves that spread it through the whole language
---

# Facts decide

blue makes the choices a Rust author makes by hand. A Rust program is fast,
safe and well configured when its author adds a cache, picks a set over a list,
narrows a capability, runs a profile-guided build or writes an unchecked fast
path. blue holds facts about each piece of code that let it make the same choice
itself, exactly, and only where the fact holds. This page names that mechanism,
the contract every default meets, the facts blue holds and lacks, and the plan
to apply it to every part of the language.

The objective it serves is the one in blue's design: correctness is invariant,
and blue moves along the trade between automatic and performant. A program that
declares nothing gets every default its facts allow. A declaration moves the
program to a position where more facts hold, and more defaults fire.

## 1. The shape every default has

| Part | What it is | Example |
|---|---|---|
| **Fact** | a property blue proves about one atom (a definition, then a region in it), keyed by something that only grows: a content hash, a frame version, a store path | `fib` is pure; `allowed` is never assigned; this program has an artifact for `slow` |
| **Rule** | facts imply a lever, written as a Horn clause, per atom; a fact a definition gains turns on the rule for it and for each caller it completes | pure ∧ calls itself twice → memo |
| **Guard and exact fallback** | the lever acts only where the fact holds; anywhere else, and on any failure, the plain path runs, so the result never changes | a folded call that raises stays as written; an index confirms each candidate with `blue_equal` |
| **Receipt, switch, ratchet** | the default names itself where the run reports (`--timings`, the door receipt); one switch turns it off; a measurement decides whether it ships | the `folded` row, `BLUE_FOLD=off`, the cost baseline |

blue's speed rules R1 to R12 ([`PERFORMANCE.md`](PERFORMANCE.md) §1.4.0) are
the first full set built this way. The shape is not about speed. Capabilities
held per placement, configuration as typed defaults with a switch per entry,
and rules in the check stage have the same four parts.

## 2. The contract a new default meets

A default lands only when every line holds. Each line is a lesson from a rule
that broke it.

| # | Requirement | Why (receipt, 2026-11-16 to 2026-11-17) |
|---|---|---|
| C1 | The fallback is exactly the old path, and a test compares the two outputs on every door | R3 fusion, R4 folding, R10 indexing each compare on and off |
| C2 | The test reaches the default: it runs where the default fires, and a red run fails it | conformance ran every column under a step bound, where R4 and R10 stand down, so their rows held only the plain path; the `default` column (W0) now runs every row as a user does |
| C3 | A default that moves work stands down where a bound can count that work | R4 under `dispatch_steps`: a server bound to refuse long work stopped refusing it |
| C4 | A default that assumes blue's own primitives stands down where an embedder may replace them | R4 in a hosted interpreter |
| C5 | Commands that observe the code as written hold the default off | fusion and folding under `blue test --coverage`, `trace`, `profile` |
| C6 | A cache never holds a reference that changes how the interpreter treats a value | R10: any reference to a list makes it non-unique and stops in-place updates, so its index lives for one call |
| C7 | A default ships only on a measured gain, recorded beside the rule | R5 on the walker and R11 measured no gain and did not ship |
| C8 | An explicit declaration wins over an inferred default | `reclaim(:arena, …)`, `BLUE_MEMO=on`, a project's bounds |
| C9 | A default never widens trust, capability or resource use without the author | the native tier runs only artifacts named by content under roots the operator gives |

## 3. The facts

| Fact | Source today | Key | State |
|---|---|---|---|
| purity, effects, reached capabilities | `reach.rs`, waku, mondou | `def_hash` | ✅ held |
| content identity | `def_hash` | itself | ✅ held |
| types and value ranges | the checker; chuuzou's range facts | position on the blueshift | ⏳ local inference and chuuzou only |
| how a value is used (indexed, appended, tested, popped, escaped) | the AST at each use | the binding | ⏳ membership in loops only (R10) |
| uniqueness | refcounts at run time | the value | ⏳ run time only; no static fact |
| profile (cost, calls, argument shapes) | the profile tier (R7) | `def_hash` | ⏳ outermost-call time, only for definitions with an artifact |
| stored results and their cost | the memo store (R8) | `def_hash` and arguments | ✅ held |
| artifacts | the native tier | `def_hash` | ✅ held when built |
| placement | the build target | the target | ⏳ a lock test only (R12) |
| bounds in force | `ExecutionBounds`, the hold | the run | ✅ held |
| termination, determinism, idempotence | — | — | ❌ none |
| algebraic laws (commutative, associative, monotone) | okite laws on bidama words | the word | ⏳ declared for library words, not inferred |
| data volume | — | — | ❌ none |

## 4. The engine it becomes

Today each rule is its own Rust module: the memo planner, `fuse.rs`,
`fold.rs`, `member_index.rs`, `native::planned`, `memo::costly`. Each module
finds its facts again and decides alone. The destination is one engine:

1. **One fact store.** mondou computes each atom's facts once and caches them by
   `def_hash`, so an unchanged definition costs a lookup.
2. **One rule registry, in blue.** Each rule is a row of the `kitei` bidama: its
   facts, its lever, its guard, its switch, its receipt text, its bench row. Adding a default is adding
   a row and the lever it names. Rust carries the levers that blue cannot reach;
   the decision is blue.
3. **One least model per atom.** The rules are Horn clauses, so each atom has one
   least model, computed in time linear in its facts and rules, and cached with
   them.
4. **One explanation.** `blue shift --defaults FILE` prints, per atom, its facts, the defaults
   that fired, and the one fact missing for the next default ("annotate `n: Int`
   and `fib` compiles natively"). This turns the blueshift into a guide: the
   author sees what each declaration buys.
5. **One gate.** Each rule has a red run, a bench row and a conformance column
   that runs its rewritten path (C2).

## 5. Waves

Each wave lists defaults in the order their gain is known. Each default meets
§2 before it ships.

### W0: the engine (§4)

- ✅ The rule registry as a bidama: `kitei` (既定), one `rule` record per rule
  R1 to R12 (facts, lever, receipt, switch, state, locks). `tests/kitei_gate.rs`
  holds the table in docs/PERFORMANCE.md, the switches the crates read and the
  rules `blue shift --defaults` names to its rows; each turns red on a wrong row.
- The fact store in mondou.
- ✅ `blue shift --defaults FILE` (`--json` too): per definition of the file,
  its facts (pure or why not, calls itself twice, typed), each default that
  fires (R2 memo, R3 fusion, R4 fold, R10 index, R7 native, R8 stored results)
  and, for one that does not, the fact it is missing (R2: the effect that makes
  it volatile; R7: a mean below 20 ms). It runs the passes a run runs, under the
  same switches, and `tests/shift_defaults.rs` holds it to what `blue run
  --timings` reports. The missing fact "annotate `n: Int` and native code
  answers it" waits on a test of chuuzou's subset per definition (W1).
- ✅ A conformance column that runs rows without the step bound (`default`,
  through `blue run --literal`), so R4, R10 and every later rewrite are held to
  the plain path on every row (C2).
- ✅ The decisions move onto the registry. Each `kitei` rule names its body
  (`needs`: the facts that must all hold), and `gen/kitei.b` renders the shipped
  rows to `crates/blue-lang-runtime/src/kitei/tables.rs`, the table the runtime
  decides by (`kitei::fires`, `missing`, `switched_off`). The memo planner (R2),
  the native tier (R7) and the stored results (R8) fire through it; fusion (R3),
  the fold (R4) and the index (R10) read their switches from it, so their
  variables are named once, in blue. Red run: R2 needing `typed` as well turns
  `tests/door.rs` and `tests/shift_defaults.rs` red; R7 and R8 needing it turn
  `tests/native_tier.rs` and `tests/fleet_memo.rs` red.

### W1: compiled code by default

- ✅ Artifacts in process: each `def_hash` is linked a second time as a
  library (`def.so`, `native/seam/def64/lib.rs`), loaded once through libc's
  `dlopen` in one audited unsafe seam (`crates/blue-lang-cli/src/dl.rs`). A
  hot call is a function call, not a process: 2,000 calls of a native `fib`,
  4.01 s as processes, 0.06 s in process, 0.19 s in the interpreter (debug
  build, the same answer). A library that faults, prints or refuses leaves the
  call to the interpreter. Lock: `tests/native_tier.rs`, red when the tier
  ignores the library; `checks.native-defs` answers through it.
- ✅ The hot mean follows the fact "its library loaded": a definition is hot
  from 0.2 ms when it did (ten times the about 20 µs one call through it
  costs) and from 20 ms when it did not (sized for a process start). Blue on
  Linux is a static musl binary, which cannot load a library, so there every
  call starts the executable; the fact is the load, not the file
  (`a_library_that_does_not_load_keeps_the_process_threshold`). `fib(16 + i % 3)` called 300
  times, the default with no flag: 2.09 s on every run before; now 2.18 s on
  the first run (it profiles) and 0.02 s from the second, the same answer.
  Lock: `tests/native_tier.rs`, a 5 ms definition is native with a library
  and not without, a 0.1 ms one never; red with the library threshold ignored.
- ✅ Artifacts built in the background. A run whose evaluation took 20 ms or
  more, on a node with a native tier, asks once per program text
  (`<cache>/blue/native/wanted/<content hash>`, `store::want_native`) and
  starts the builder `BLUE_NATIVE_BUILDER` names (`nix run .#native-build`,
  `native/build/wanted.b`). The builder builds each function chuuzou compiles
  into this node's tier, which every run now reads before the shared roots;
  the profile then decides which go native. Timing every definition instead
  would put an observer on every run, so the fact read is the run's own
  evaluation time (`timings::evaluated`, counted always). End to end with no
  flag: 0.52 s (asks; 3 definitions built), 2.36 s (profiles them), 0.39 s,
  then 0.02 s, the same answer. Lock: `tests/native_build.rs` (asks once per
  text, again after an edit, never when done, never with no tier, a run under
  20 ms or `BLUE_NATIVE=off`; starts the builder), red with the 20 ms ignored;
  `checks.native-native-builder`.
- chuuzou's subset widened one type at a time (strings, maps, records in lists,
  closures), each step moving code from the interpreter to native code.
  - ✅ Bool: a definition that takes or answers Bools compiles for the tier;
    a Bool crosses the seam as 1 or 0 (`cz_seam_arg`, `cz_seam_result`), and
    the tier reads each definition's signature from its own `define-typed`
    form to convert (`native::Shape`), for the library and the executable
    alike, so a static blue answers a Bool through the executable. Lock: `tests/native_tier.rs`
    `a_bool_crosses_the_seam_as_one_or_zero_both_ways` (red with the result
    left an Int) and `checks.native-defs` "a Bool crosses the seam both ways"
    (`small`, `big`, `pick` in `native/defs/base.b`; `big` answered by
    `small`'s library proves the library answered).
  - Next: Float, then strings.
- Doctests as profiles: each `@doc` example is a typed sample input, run at
  build to seed the profile before the first real run.
- Proven types drop the guard in compiled code (R6, at T3).

### W2: data that fits its use

- A list only appended then read in order compiles to a growable vector; a list
  only tested for membership to a set; a list only popped at the front to a
  queue; in native code, not only in the interpreter.
- A string built by appends in a loop becomes a builder.
- A record in native code is a struct with fixed slots (R9 at T3).
- A value nothing else holds is updated in place, decided statically where
  uniqueness can be proven, not only at run time.

### W3: work done once

- Pure top-level values computed at build and baked into the bundle (R4 at
  build time).
- Pure results shared through the fleet store by default for costly calls
  (R8), with the cost from the profile instead of from a first run.
- Tests selected by `def_hash`: a change reruns only the tests that reach it.
- Expensive optimization (a search over equivalent forms) run once per
  `def_hash` and shared.

### W4: concurrency from facts

- `map` over a pure callback on a large list runs in parallel, the size from the
  profile.
- Independent effects batched: calls the effect graph shows to be independent
  share one round trip.
- An idempotent effect retried on a transient failure, with the retry named in
  the receipt.

### W5: safety and resources from facts

- A program's capability hold narrowed to what it reaches, by default.
- A step and memory bound proposed from the profile ("this runs in 120 ms; hold
  it to 10 s"), applied only when the author accepts it (C9).
- Run-time guards at the seams the checker could not close (R5's "guard kept"),
  emitted where a declared type meets undeclared code.

### W6: configuration from context

- Timeouts, cache sizes and pool sizes from measured latency and load, each a
  typed default with its switch.
- Behaviour per placement (a phone, a wasm component, a node) chosen from the
  placement fact, never from a flag the author must know.

### W7: the author sees it

- The editor shows each atom's defaults and the one declaration that unlocks the
  next.
- Docs list the defaults a word gets, generated from the facts.

## 6. How a wave is measured

Each default adds a bench row (`bench/cost.baseline` or `bench/lever.baseline`)
and a row in `PERFORMANCE.md` §1.4.0. The permutation analysis of the speed
plan applies to every wave: across rigor, effects, shape and placement, no
permutation may fall below today's floor, because the fallback is the old path
(C1) and a default fires only where its gain is known (C7).
