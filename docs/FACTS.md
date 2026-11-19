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
  - ✅ Float, on the host board: an f64 natively, a literal as its exact
    IEEE-754 bits (chuuzou computes them by halving and doubling, both exact),
    an Int that meets a Float widened as the interpreter widens it, `/`
    faulting on a zero divisor where the interpreter raises; `mod` and
    `floor` of a Float stay refused. A Float crosses the seam as its bits.
    The checker had typed `+ - * /` and the orders as Int only, so no typed
    Float definition with arithmetic passed the check stage; they now take
    numbers and answer a Float when an operand is one. The profile now counts
    a loop of tail calls as one outermost call (`Exit::TailCalled`), where it
    counted each step and so never found a tail loop hot. `drift(3_000_000,
    1.0)`, a Float tail loop, with no flag: 0.62 s interpreted, 0.01 s native
    from the second run, the same answer. Locks: `tests/native_tier.rs`
    `a_float_crosses_the_seam_as_its_bits_both_ways` (red with the answer
    left an Int) and `a_loop_of_tail_calls_is_one_outermost_call_in_the_profile`
    (red without the tail rule: 10,007 calls); chuuzou's Float tests (exact
    bits, what compiles, what is refused); the checker's
    `arithmetic_on_a_float_answers_a_float_and_an_order_takes_one` (red with
    Int answered); `checks.native-defs` "a Float crosses the seam both ways"
    (`area`, `half`, `wide`; a swapped library proves the library answered);
    `spec/rows/check.b` `check.float_arithmetic`, `check.float_into_int`.
  - ✅ Str, on the host board: a refcounted string (`kiban_heap::Str`), a
    literal rendered through tatara-rust-ast's typed `Str` node (no source
    text), `concat` and interpolation of a Str, an Int or a Bool written as
    the interpreter writes them (`kiban_heap::Piece`), `length` in
    characters, `==` by content; a Float in `concat` and an order on strings
    stay refused. No word holds a string, so a definition that takes or
    answers one crosses a second seam: value tokens (`i42`, `b1`, `f<bits>`,
    `s<hex>`), through the library's `blue_def_call` or the executable's
    arguments. An all-Int definition keeps the word seam and bare decimals,
    so an artifact built before tokens still answers it; one of another
    shape refuses tokens it cannot read, and the interpreter runs the call.
    `score("key", 1_000_000, 0)`, a loop of small string steps, with no
    flag: 0.93 s interpreted, 0.19 s native from the third run, the same
    answer. Locks: `tests/native_tier.rs`
    `a_str_crosses_the_library_seam_as_a_token_both_ways` (red with the
    token's bytes dropped); native.rs `a_str_crosses_the_seam_as_a_token_both_ways`;
    chuuzou's Str tests (what compiles, what is refused, the board without a
    heap); `checks.native-defs` "a Str crosses the seam both ways" on Linux
    (`shout`, `width`, `twice`; `bang`'s artifact swapped in proves the
    artifact answered).
  - ✅ A list of Ints across the seam: a definition that takes or answers
    `List` or `List(Int)` crosses the valued seam, its list a token (`l1,2,3`,
    `l` the empty one) read into a refcounted `kiban_heap::List`; a list
    holding anything but Ints is not sent, and the interpreter runs the
    call. A definition that holds its lists in a region (`reclaim(:arena,
    …)`) is refused, since a region's list does not outlive its call. One
    table (`cz_seam_kind`) names how each type crosses. `total(range(300_000),
    0, 0)`, a loop over a list, with no flag: 0.22 s interpreted, 0.03 s
    native from the third run, the same answer. Locks: native.rs
    `a_list_of_ints_crosses_the_seam_as_a_token_both_ways`; chuuzou "a list
    of Ints crosses the valued seam, refcounted only" (an arena definition
    refused for its region); `checks.native-defs` "a list of Ints crosses
    the seam both ways" on Linux (`grown`, `tally`; `doubled`'s artifact
    swapped in proves the artifact answered).
  - ✅ A record of Ints across the seam: a definition that takes or answers
    a record whose fields are Int or untyped crosses the valued seam, the
    record a token of its fields in declared order (`r6,2`). Natively it is
    the record's own struct; the tier sends a record only when its name and
    every field match, and answers one with `blue_lang_runtime::record::value_of`,
    which builds the value the record's constructor builds (the same `$record`
    tag, its field names sorted, as JSON shows it). chuuzou reads typed fields
    (`(:x Int)`) and refuses a record field of another type. `walk(pt(1, 2),
    1_000_000)`, a loop of record updates, with no flag: 2.51 s interpreted,
    0.01 s native from the third run, the same answer. Locks: the runtime's
    `a_record_built_outside_the_interpreter_equals_the_one_its_constructor_builds`
    (red with the tag's fields unsorted); native.rs
    `a_record_of_ints_crosses_the_seam_as_its_fields_in_declared_order` (a
    record of another name, a short token and a Str field refused); chuuzou "a
    record of Ints crosses the valued seam as its fields"; `checks.native-defs`
    "a record of Ints crosses the seam both ways" (`shifted`, `spread`;
    `lifted`'s artifact swapped in proves the artifact answered).
  - Next: maps, and records holding other types.
- ✅ Doctests as profiles. The builder runs a program's tests once it has
  built its definitions, and the test run seeds the profile through the
  native tier (`native::Tier::seeding`): it answers no call, times each
  definition with an artifact, and records one only when it ran hot, so a
  definition its tests call cheaply stays unprofiled and the first real run
  times it as before. A documented `fib` (`fib(24) #=> 46368`): the first
  real run after the build is 0.02 s, where it was the 2.36 s profiling run.
  Lock: `tests/native_tier.rs` `a_test_run_seeds_the_profile_only_for_what_it_ran_hot`
  (red when every time is recorded, and red when a seeding run answers from
  the artifact).
- ✅ A proven fact drops a guard in compiled code (R6, at T3). The type
  guard on a call is a few comparisons, so dropping it gains nothing to
  measure; the guard that costs is the thread that holds the board's depth
  bound, about 20 µs a call. chuuzou proves a slice shallow when no function
  of it recurses but in its tail (`cz_recursive`), and says so in the
  artifact (`pub fn shallow()`, `cz_shallow_fn`); the library runs a shallow
  definition on its caller's stack under `catch_unwind`. 20,000 calls of the
  native `square`: 0.40 s through a thread each, 0.03 s on the caller's
  stack, the same answer. Lock: chuuzou "a slice with no recursion is
  shallow, and one that recurses is not" (red with the fact inverted);
  `checks.native-defs` answers `square` (shallow) and `fib` (deep) as the
  interpreter does.

### W2: data that fits its use

- A list only appended then read in order compiles to a growable vector; a list
  only tested for membership to a set; a list only popped at the front to a
  queue; in native code, not only in the interpreter.
  - ✅ Vector: a native list is a refcounted vector (`kiban_heap::List`),
    and `append(xs, [a])` pushes in place when nothing else holds `xs`.
  - ✅ Set: `member?` compiles natively (a scan of the list), and a list
    parameter of a tail-looping definition that is read only by `member?`
    and passed unchanged to its own tail call (`cz_sets`, decided from the
    tree) is held as a set built once before the loop, so each test is a
    lookup. It is a choice inside the artifact, under R7's switch, as the
    shallow fact is. 200,000 tests against 4,000 Ints (`hits`), with no
    flag: 1.97 s interpreted, 0.05 s native scanning the list, 0.01 s native
    with the set, the same answer. Locks: chuuzou "a list only tested in a
    tail loop is a set built once before the loop" (red with the fact off; a
    list read any other way stays a scan); `checks.native-defs` "a list only
    tested is a set, and answers as the list does" (the artifact holds the
    set and answers as the interpreter does).
  - ✅ Queue: a list parameter of a tail-looping definition that is read only
    by `first` and `count` and passed to its own tail call as its `rest`
    (`cz_queues`, decided from the tree) is held as a queue
    (`kiban_heap::Queue`, the list and where its front is), so each `rest`
    moves the front where it would copy the list. Outside that fact `rest`
    is refused natively: copying at every step took 4.8 s where the
    interpreter takes 0.46 s, so it would have made a hot definition slower
    by default; refused, the definition keeps the interpreter's speed.
    300,000 pops (`drain`), with no flag: 0.46 s interpreted, 0.03 s native
    from the third run, the same answer. Locks: chuuzou "a list only popped
    in a tail loop is a queue whose rest moves its front" (red with the fact
    off; a list read any other way is refused, naming the cost);
    `checks.native-defs` "a list only popped is a queue, and answers as the
    list does".
- ✅ A string built by appends in a loop is built once (R13, `builder.rs`):
  `reduce((s, x) -> "#{s}…", init, xs)`, with `s` read nowhere else, becomes
  `init` as the first step converts it, then the `join` of each step's parts,
  each part evaluated in its order; an empty list or a non-list runs the
  loop as written. 200,000 appends: 2.87 s to 0.08 s, the same string. Locks:
  `tests/builder.rs` (six cases on both doors against `BLUE_BUILDER=off`: a
  start that is no string, an empty list, nil, effects in the parts, a part
  that raises, a non-list; and linear time), red when the start is dropped;
  `spec/rows/builder.b` on every column, the `default` column holding the
  rewritten path.
- ✅ A record in native code is a struct with fixed slots (R9 at T3).
  chuuzou lowers each record to its own struct (`R_<name>`, fields read in
  place, an updated copy built from the fields it keeps), and a record of
  Ints now crosses the seam as its fields (W1, above), so a definition over
  records runs native by default: 1,000,000 record updates, 2.51 s
  interpreted, 0.01 s native. Locks: as W1's record row.
- A value nothing else holds is updated in place, decided statically where
  uniqueness can be proven, not only at run time. Owned by PURE-BLUE M3 and
  B5 ([ROADMAP.md](ROADMAP.md), "One deliverable, one owner"); this row is
  an alias and keeps no state. Native code already updates a list in place
  when its count shows nothing else holds it.

### W3: work done once

- ✅ Pure top-level values computed at build and baked into the bundle (R4 at
  build time). `blue bundle` compiles through the same prepare stage as a
  run, so a pure call on literals in a definition is folded before the
  payload is sealed and the bundle carries its value (`fib(12)` in `score`
  is the Int 144 in the payload). A call past the fold's step bound stays as
  written and runs at its own time. Lock: `tests/bundle.rs`
  `a_bundle_carries_a_pure_call_on_literals_as_its_value_folded_at_build_time`
  (the call, not the value, under `BLUE_FOLD=off`).
- Pure results shared through the fleet store by default for costly calls
  (R8), with the cost from the profile instead of from a first run.
  - ✅ R8 fires on a stored result that cost 20 ms or more, and nothing
    stored a result for a definition no memo ran, so a costly pure definition
    never got its first one. The profile tier cannot supply the fact (it
    times only definitions with a native artifact, which R7 answers), so the
    cost is the run's own: a run whose evaluation took 20 ms or more
    (`timings::evaluated`, counted always since W1.3) marks its program text
    slow, and the next run records its pure definitions' results with their
    cost (rule R14, `kitei`), after which R8 answers the costly ones.
    `slow(3_000_000)`, with no flag: 0.55 s on every run before; now 0.55 s,
    0.93 s (it records), then 0.01 s, the same answer. Lock:
    `tests/fleet_memo.rs`
    `a_slow_program_records_its_pure_results_on_the_next_run_and_answers_from_them_after`
    (a quick program never marked, `BLUE_MEMO=off` marks nothing; red when
    nothing is marked).
- ✅ Tests selected by `def_hash`: a change reruns only the tests that reach it.
  A test's identity is its own tree and the hashes of what it reaches
  (`mondou::def_hash::test_identities`), and `blue test` answers a passed
  identity from the test tier (`test_cache.rs`, `N cached` in its tally;
  `BLUE_TEST_CACHE=off`, `--no-cache`). Locks: `def_hash`'s
  `a_test_is_identified_by_its_tree_and_what_it_reaches_never_by_its_name`;
  `tests/test_cache.rs`.
- Expensive optimization (a search over equivalent forms) run once per
  `def_hash` and shared.
  - ✅ The fold (R4) decides each site once: what it decided, a literal or
    that it gave up, is kept in the check cache as its own pass
    (`check_cache::Pass::Fold`), in the callee's `def_hash` bucket under the
    call's text, and every later run recalls it. A give-up is kept only when
    it had the whole per-call step bound, since a site that ran short of the
    pass's budget may finish another time. The cache is keyed by this
    build's identity, so a new blue decides again. A program whose fold
    gives up on `fib(22)`: erase 2.95 ms on the first run, 0.17 ms after;
    one that folds `fib(12)`: 0.53 ms to 0.33 ms, the same answers. Lock:
    `tests/fold_memory.rs` `a_fold_is_decided_once_per_definition_and_recalled_after`
    (a poisoned kept literal is what the second fold writes; red when the
    fold runs the call again). `BLUE_FOLD=off` and `BLUE_CHECK_CACHE=off` turn
    it off.
  - ✅ A search over equivalent forms (rule R19): blue's rewrites are rules
    over one e-graph per stage call (`blue-lang-saturate`, over `egg`),
    saturated within a budget and extracted by a measured cost model (S1,
    `blue cost`), the decision kept by the call and recalled; fusion is
    its first rule, and saturation gives the tree fusion gives on every
    chain the parity gate holds. Erasure: 0.67 ms to decide, 0.16 ms
    recalled. [ENGINES.md](ENGINES.md) §2 has each phase and its lock.

### W4: concurrency from facts

- ✅ `map` over a pure callback on a large list runs in parallel, the size
  from what the run measures (rule R17). In a project that declares
  `schedulers(n)` with n above 1 (ASYNC A6), erasure renames each `map`
  whose callback only computes, by the test fusion applies, to `par_map`.
  `par_map` times its first call on the caller's thread; the rest runs on
  n workers when the time they save is more than twice what a worker costs
  to start (one interpreter, built once and timed). The callback and the
  elements travel as a spawned process's do (`proc::code::function_code`,
  `copy_data`), each worker maps one slice on an interpreter of its own, and
  the slices are joined in order, so the answer is map's. A callback or
  element that cannot travel, or a worker that raises, maps on the caller's
  thread, which raises map's own error. `--timings` counts each parallel map
  (`parallel`); `BLUE_PARMAP=off` turns it off; `par_map` is also a word a
  program can call. Eight 400,000-step calls: 0.67 s on one scheduler,
  0.30 s on four, the same answer. Locks: `tests/schedulers.rs`
  `par_map_runs_apart_on_a_project_s_schedulers_and_answers_as_map_does`
  and `rule_r17_runs_a_map_whose_callback_only_computes_apart_and_its_switch_keeps_it_home`
  (a callback that writes keeps its order); `parallel::tests` for the
  decision.
- ✅ Independent effects batched (rule R18): reads the effect graph shows to
  be independent and to commute are sent at once. The graph (E1) records
  each host call with its resource and the calls it depends on; the
  commutation table (E2) names each host word a read, a write or ordered;
  R18 (E3) turns a run of independent GET-family requests into one
  `http_batch`, the answers bound in order. Two GETs to a server that holds
  each 300 ms are held open at once, and in turn under `BLUE_BATCH=off`, with
  the same answers. Reads behind a request helper are batched too (E4).
  [ENGINES.md](ENGINES.md) §1 has each phase and its lock.
- ✅ An idempotent effect retried on a transient failure, with the retry named in
  the receipt (rule R15). An `http_request` whose method is GET, HEAD or
  OPTIONS, idempotent by RFC 9110, that fails before an answer because the
  connection was refused or reset is sent again, up to twice, 50 then 100
  ms apart; every try shares the call's one deadline, so its timeout still
  bounds it. A timeout, a refused request, a malformed answer and every
  other method are sent once (PUT and DELETE are idempotent, but a retry of
  one that reached the server repeats its effect). `--timings` counts each
  retry (`retried`), from one table of counted rows the fold, the index and
  the builder share; `BLUE_RETRY=off` turns it off. A GET to a server that
  comes up 30 ms late raised before and answers now. Locks: `tests/net.rs`
  `an_idempotent_request_refused_once_is_sent_again_and_answered` (red when
  nothing is retried) and `a_request_that_is_not_idempotent_is_sent_once`
  (red when a POST is retried, against the same late server).

### W5: safety and resources from facts

- A program's capability hold narrowed to what it reaches, by default.
  Waits on the operator: [SAFETY.md](SAFETY.md) D3 keeps an undeclared
  script ambient, and flips it to declared through a ratchet when `blue
  check` counts no undeclared script that reaches the host. Narrowing to a
  computed reach would refuse a script whose reach the analysis cannot see
  (a name computed at run time), a refusal bigger than the fault. A
  project's lock already holds its run to the join of what its reached
  definitions name (`unit` floors, SAFETY.md §4). Operator ruling,
  2026-11-19: D3 stands; W5.1 waits on D3's ratchet reaching zero.
- ✅ A step and memory bound proposed from the profile ("this runs in 120 ms; hold
  it to 10 s"), applied only when the author accepts it (C9). `blue bounds
  FILE` runs the program once on the tree-walker, which counts every step,
  reads the steps and the bytes it allocated from `--timings`, and proposes
  `bounds({steps:, alloc_bytes:})` at ten times each, rounded up to a power
  of ten (allocated bytes are a total, never less than the live bytes the
  bound holds). `--accept` writes the line into the nearest Bluefile and
  locks it; a Bluefile that already declares bounds is its author's, since a
  proposal never widens one, and nothing is written without `--accept`. The
  verb is blue (`crates/blue-lang-cli/blue/bounds.b`), run through one
  `embedded` door the `doc`, `verbs` and `reuse` verbs now share where each
  had its own copy. On `slow(3_000_000)`: 21,000,022 steps and 1,740,411,944
  bytes, proposed `bounds({steps: 1_000_000_000, alloc_bytes: 100_000_000_000})`.
  Lock: `tests/bounds.rs`
  `a_measured_run_proposes_bounds_and_writes_them_only_when_accepted` (the
  bounded program still runs; a second accept refused; red when a proposal
  writes without `--accept`).
- Run-time guards at the seams the checker could not close (R5's "guard kept"),
  emitted where a declared type meets undeclared code. Waits on the
  operator: today `half(4)`, `half(x: Float)` reached through an untyped
  caller, answers 2.0; a guard makes it raise. That changes what a working
  program does, which no default may (§2: an exact fallback), so it is a
  semantic decision, not a lever. Operator ruling, 2026-11-19: refused.
  Types are checked statically only, so the gradual guarantee holds: an
  annotation never changes what a program that runs answers.

### W6: configuration from context

- Timeouts, cache sizes and pool sizes from measured latency and load, each a
  typed default with its switch.
  - ✅ Timeouts (rule R16): an `http_request` whose `timeout_ms` is nil takes
    ten times the slowest answer its host has given this process, at least
    1 s, or 30 s for a host not yet heard from; a given timeout is kept as
    given, and a nil timeout raised before, so no working program changes.
    `BLUE_TIMEOUT=fixed` keeps every nil timeout at 30 s. A host that
    answered at once and then hangs: the next nil-timeout request times out
    within 1 s where a fixed 30 s would wait. Lock: `tests/net.rs`
    `a_nil_timeout_is_measured_from_how_fast_the_host_answered_before` (red
    when nothing is measured).
  - ✅ Pool sizes (rule R20): a `par_map` that runs apart (R17's decision,
    unchanged) takes a worker only while it pays. The first call prices the
    load `w`, one worker's start is measured, and the `k`-th worker saves
    `w / (k(k-1))`, so the pool is the largest `k`, at least 2 and at most
    the schedulers, whose last worker saves more than twice a start.
    `--timings` counts the workers started (`workers`); `BLUE_POOL=fixed`
    takes a scheduler for each element left. Sixteen 20,000-step calls on
    sixteen schedulers: 5 workers, not 15, the same 0.07 s wall time on half
    the CPU (0.10 s, not 0.20 s), the same answer. Locks: `tests/schedulers.rs`
    `rule_r20_sizes_the_pool_from_the_measured_load_and_its_switch_takes_every_scheduler`
    (red when the pool is fixed); `parallel::tests` for the rule, and that a
    sized pool runs apart exactly when the fixed one does and is never larger.
  - Next: cache sizes from measured load.
- ✅ Behaviour per placement (a phone, a wasm component, a node) chosen from the
  placement fact, never from a flag the author must know. Every placement
  difference blue makes is read from the build target, and each is locked:
  a phone or a wasm component runs ahead-of-time code only, since its crates
  link no native tier and map no executable memory (R12,
  `tests/placement_tiers.rs`); the native tier's hot mean follows whether
  this platform could load a library (a static Linux blue cannot), never a
  flag (R7, `tests/native_tier.rs`
  `a_library_that_does_not_load_keeps_the_process_threshold`); and a wasm32
  build counts no evaluation time, which it cannot read
  (`timings::counted`). A new per-placement default reads the same fact.

### W7: the author sees it

- ✅ The editor shows each atom's defaults and the one declaration that unlocks
  the next. Hover on a definition in the language server now lists, under
  what blue derives about it, each rule the defaults engine decides
  (`blue_lang_runtime::defaults::explain`, computed once per analysis,
  `Analysis::defaults`): `default R2: …` where one fires, `R2 waits on: …`
  with the fact it lacks, which names the declaration that would unlock it.
  Hover works in every editor, so the defaults are always in view. `blue
  doc` answers the same question on the command line (W7.2). Lock:
  `blue-lang-lsp` `hover_names_the_defaults_a_definition_gets_and_what_the_next_waits_on`
  (a self-recursive pure `fib` shows R2 firing, one that reads the clock
  shows what R2 waits on; red when hover leaves them out).
- ✅ Docs list the defaults a word gets, generated from the facts. `blue doc`
  on a bidama definition adds each rule `blue shift --defaults` decides for
  it from its facts: a rule that fires as `default R2: …`, one that waits as
  `R2 waits on: …` with the fact it lacks, which is the declaration that
  would unlock it; `--json` carries them as `defaults`. `blue doc
  kazu::int_sqrt_fix` says `default R2: its repeated calls are answered from
  a table`; `blue doc junjo::sort_by` says `R2 waits on: it is not pure: it
  reaches retsu::is_empty`. Lock: `tests/doc.rs`
  `a_bidama_definition_lists_the_defaults_it_gets_and_what_the_next_waits_on`
  (red when no defaults are read).

## 6. How a wave is measured

Each default adds a bench row (`bench/cost.baseline` or `bench/lever.baseline`)
and a row in `PERFORMANCE.md` §1.4.0. The permutation analysis of the speed
plan applies to every wave: across rigor, effects, shape and placement, no
permutation may fall below today's floor, because the fallback is the old path
(C1) and a default fires only where its gain is known (C7).
