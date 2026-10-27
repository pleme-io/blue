---
kind: explanation
summary: Rust's static guarantees and Lua's runtime, brought into blue
---

# Compile time: Rust's static guarantees and Lua's runtime, in blue

Operator, 2026-10-24: *"lets ensure that all the compiletime benefits rust has
bluelang has as well"* and *"lets take everything good from lua for sure"*.

This document is the destination for both requests. `docs/SAFETY.md` owns the
safety rows (null, must-use, unsafe, races, secrets). This document owns the
rest of what Rust's compiler gives at compile time, and what Lua's runtime
gives at run time. It does not restate a SAFETY row; it points at it.

Tier: DESIGN. Measurements: `origin/main` at `2026394`, 2026-10-24.

## 1. Destination

A blue program is resolved once, before it runs. Every name is a slot, every
call has a known arity, every value whose kind is known is checked where it
flows, and every closed set (a `case`, a record's fields, an option map) is
checked for totality. The checked program is the program that runs: the
runtime reads slots, not names, and it never resolves a name twice.

The two requests meet at one pass. Rust gets its static guarantees from a
resolver and a type checker that run before code generation. Lua gets its
speed from a compiler that turns each local into a register and each capture
into an upvalue. Both are the same work: **resolve every name to a place
before the program runs.** blue does that work once and gets both results.

World-facts that limit this destination:

- blue is dynamic. A higher-order call cannot be proven pure or total without
  an effect system (SAFETY §1).
- `eval`, `macroexpand` and a REPL create names at run time. A name a program
  creates at run time cannot be a compile-time slot; it stays a by-name lookup
  in a global table, as in Lua.

Every other limit below is phrased in blue's own abstractions, so it is ours
to dissolve.

## 2. Ground: what exists

- **Names resolve at check time and again at run time.** B0001 refuses an
  unbound name before a program runs. The runtime then hashes each name with
  SipHash and walks frames on every read (`docs/PERFORMANCE.md` §2.1: 24%
  hashing, 7% `Env::lookup`, 24% frame allocation, 12% frame locks).
- **One program is resolved four times per run** (`PERFORMANCE.md` §2.6).
- **Types are gradual.** `def f(n: Int) -> Int` is checked inside typed
  definitions (B0003–B0005). B0062 checks a value of known kind at a builtin.
  An untyped definition is not checked.
- **Arity is checked at run time.** A call with too many arguments raises,
  naming the range (`REFERENCE.md`, optional parameters). No B-code checks
  arity before a run.
- **No declared records or enums.** A map is the record. `case` compares with
  `==`, does not destructure, and falls through to `nil` (SAFETY row 3).
- **Macros** are `defmacro` + `quote`, with `gensym` for private names. They
  are not hygienic by construction.
- **Lints** exist for unused bindings (B0002, warning), unused imports
  (B0016), duplicate definitions (B0017) and discarded values (B0053).
- **Docs are typed and tested** (B0056–B0060). This row is already ahead of
  Rust's: an example is required, not optional.
- **Concurrency** is share-nothing processes (SAFETY row 10), plus tatara
  channels and fibers (`chan`, `go`) whose run and put/take words have no blue
  spelling.
- **A bytecode VM exists** but is off for `blue run`. It lifts every callback
  back to a tree-walker closure, looks globals up by name, and keeps captures
  in `Arc<Mutex<Value>>` cells (`PERFORMANCE.md` §2.2).

## 3. Rust's compile-time benefits

Tiers as in SAFETY §4: open, runtime-refused, checked-at-expansion,
parse-rejected, unrepresentable. ✅ sealed at target, ⚠️ partial, ❌ open.

| # | Rust benefit | blue today | Gate | Tier today → target |
|---|---|---|---|---|
| R1 | Every name resolved before run | ✅ B0001 at check; ❌ the runtime resolves again by name | resolver output is the program the runtime runs (§5) | checked-at-expansion → unrepresentable |
| R2 | Arity checked at every call | ❌ raises at run time | B-code: a call to a known definition passes an arity in its range | runtime-refused → checked-at-expansion |
| R3 | Types inferred, not only declared | ⚠️ typed definitions only; B0062 for known kinds at builtins | local inference: a literal, a constructor, a typed return and a builtin's result give a kind; the kind flows through bindings and calls | checked-at-expansion (typed) → checked-at-expansion (every known kind) |
| R4 | Declared structs: a field set is closed | ❌ a map is the record; `cap.status` raises at run time on a missing field | `record Name(a, b)`: construction must give every field; a read of an absent field of a known record is refused | open → checked-at-expansion |
| R5 | Declared enums | ❌ keywords are open | `enum Name(:a, :b)` (SAFETY Q5): a keyword outside the set, where an enum is expected, is refused | open → checked-at-expansion |
| R6 | Exhaustive `match` with destructuring | ❌ `case` is `==` and falls to `nil` | SAFETY row 3 owns totality; this row adds destructuring of records and lists in `case` | open → checked-at-expansion |
| R7 | Traits: a capability a type must provide | ❌ none | `protocol` over records: a call through a protocol to a record that lacks it is refused | open → checked-at-expansion |
| R8 | Generics with bounds | ⚠️ builtins are polymorphic at run time | type variables in signatures, `def first(xs: List(T)) -> T`, checked by R3's inference | open → checked-at-expansion |
| R9 | Hygienic macros | ⚠️ `gensym` by hand | a macro's own bindings are renamed by the expander; a capture is written on purpose | open → unrepresentable |
| R10 | `const` evaluation | ❌ | a top-level binding of a pure expression is folded at check time; its value is in the checked program | open → checked-at-expansion |
| R11 | Dead code and unreachable code | ⚠️ B0002 (warning), B0016, B0053 | unused private definition; code after `raise`; an `if` on a known constant | checked-at-expansion |
| R12 | `#[deprecated]` | ✅ `legacy_names` + B0021/B0022 | none | checked-at-expansion |
| R13 | Privacy | ✅ SAFETY row 17 + `docs/NAMESPACES.md` | none | unrepresentable |
| R14 | Refactor safety: a rename breaks every stale call | ⚠️ B0001/B0011 for names; ❌ fields and option keys at run time (B0061 covers option keys) | R4 + R2 | checked-at-expansion |
| R15 | Compile once, run the artifact | ❌ four resolutions per run | the checked, resolved program is cached by content hash and run directly | → unrepresentable (one resolution) |
| R16 | Doc tests | ✅ B0056–B0060, `blue test` runs `#=>` lines | none | checked-at-expansion |

R1, R2, R3, R14 and R15 all need the same pass (§5). R4–R8 need a declared
shape; they share one surface (§6).

## 4. Lua's good parts

| # | Lua mechanism | What it gives | blue today | blue's form |
|---|---|---|---|---|
| L1 | Locals are registers, chosen at compile time | a variable read is one array index | name hashed per read | §5: resolver assigns slots; frames are `Vec<Value>` |
| L2 | Upvalues: open on the stack, closed on frame exit | a capture costs nothing until its frame ends | `Arc<Mutex<Value>>` per capture | §5: open/closed upvalues; values are immutable, so a closed upvalue needs no lock |
| L3 | One `lua_State` per thread, no locks inside | no allocation and no lock per call | `Mutex<HashMap>` behind `Arc` per frame | one interpreter per blue process (already share-nothing); frames become a stack window |
| L4 | Interned strings | a name or key compare is a pointer compare | SipHash + `memcmp` per read | intern symbols and keyword keys at parse; map keys of keyword type compare by id |
| L5 | Native calls VM closures without leaving the VM | `map(f, xs)` costs one VM call per element | callback lifted to a tree-walker closure per call | the VM is the only evaluator; builtins take a VM call handle |
| L6 | Asymmetric coroutines (`resume`/`yield`) | generators, lazy pipelines, cooperative tasks | `chan`/`go` with no blue spelling for run, put or take | `coroutine(f)`, `resume(co, x)`, `yield(x)`: stackful, inside one process |
| L7 | Small, stable embedding API; sol2's one-line `new_usertype` | a host type becomes a script type with no glue | bidamas written by hand per library | a derive in `blue-lang-host-macros` that exposes a Rust type and its methods as a bidama |
| L8 | Tiny core, small binary, fast start | embed anywhere | 6.4 ms `hello`, faster than Python already | keep: a start-up budget row in `PERFORMANCE.md` |
| L9 | Incremental, generational GC | short pauses | `Arc` reference counting | keep RC: values are immutable, so no cycles form except through closures; measure before changing |
| L10 | LuaJIT trace JIT + FFI | near-C loops | none | after §5 only; WASM AOT (`blue-lang-wasm`) is the nearer path |

Lua features that conflict with a Rust row are not refused. They take a
position on the blueshift (§7). Only these are refused, because each is a bad
state at every rung, not a good state in some places:

- **One `table` type for list and map.** No rung gains from it; a kind check
  can no longer tell a list from a map.
- **1-based indexing and `nil`-terminated arrays.** A length that stops at the
  first `nil` is wrong for any list that holds `nil`. `nil` belongs to
  `docs/ABSENCE.md`.
- **`_ENV` sandboxing.** Capabilities and session frames (SAFETY row 8) already
  do this job; a second mechanism would be two answers to one question.

## 5. The pass: resolve once, run the resolved program

One pass between check and run. Input: the expanded, checked program. Output:
a resolved program in which

- each local is `Slot(depth, index)`; each capture is `Upvalue(index)`; each
  global is `Global(id)` with an interned id (L1, L2, L4, R1);
- each call to a known definition carries its arity range, refused at this
  pass when the call is outside it (R2);
- each expression whose kind is known carries the kind (R3, feeding B0062);
- the whole result is keyed by the content hash of its inputs and cached, so a
  second run skips parse, expand, check and resolve (R15).

The VM consumes the resolved program, and the tree-walker becomes a test
oracle: both run the conformance corpus, and every result must agree. A name
created at run time (`eval`, REPL) resolves to a global by id, the Lua
fallback.

This is where the Rust request and the Lua request are the same work.

## 6. The declared-shape surface

One surface for records, enums and protocols, so a shape is declared once and
every check reads the same declaration:

```
record Repo(name: String, url: String, private: Bool)
enum Visibility(:public, :private, :internal)
protocol Render(render)
```

Construction, field reads, `case` destructuring, enum membership and protocol
dispatch all read this one declaration. A record is still a map at run time,
so every map word keeps working on it (behaviour is added, never removed).

## 7. Conflicts resolve on the blueshift

Operator, 2026-10-24: *"make sure conflicting features use blueshift so we get
the best of everything whenever we want with a set of the best defaults as
defaults"*.

The rule is `BLUE-GAPS.md`'s: when two ideals are both right in different
places, the behaviour becomes a function of the program's declared position on
the blueshift (`theory/BLUE.md` §V.20: `dynamic → annotated → checked →
restricted`, per axis, plus quantized lines). It is never a global semantic
change and never an off switch. A per-site fallback slides continuously; an
indivisible resident (an evaluator, a collector) is a line, chosen per
artifact.

**First, separate a conflict from a free gain.** A check that only moves a raise
that would certainly happen at run time to an earlier door removes no good
behaviour. It is not a conflict, so it is on at every rung: R1 (an unbound
name), R2 (an arity outside a known definition's range), R9's default
hygiene, R11's code after `raise`. Every row below is a real conflict.

| Conflict | Ideal A (where it is right) | Ideal B (where it is right) | Position | Kind | Default |
|---|---|---|---|---|---|
| Open map vs closed record (R4) | a map takes any key: exploration, JSON, scripts | a record's fields are closed: refactors, APIs | per value: a map literal is open; a value built by `record` is closed | continuous | map literal open; `record` closed |
| Metatable dispatch vs declared protocol (Lua `__index`, R7) | an implementation added at run time: plugins, REPL, live patching | every implementation known at check: totality, inlining | per protocol: `dynamic` accepts a run-time `impl`; from `checked` an `impl` must be visible at check | continuous | a protocol is closed once its file is `checked`; open below |
| Global by name vs slot (Lua globals, L1) | a name made at run time: `eval`, REPL, `defmigrate` | a name known at check: speed, refactor safety | per site: a name the resolver can see is a slot; one it cannot is a global by interned id | continuous | slot wherever the resolver sees the name |
| Inferred kind vs dynamic value (R3, R8) | a value of any kind: glue code, data walks | a known kind: refused mismatch, typed opcodes | per definition: the rung the definition's declarations justify | continuous | infer everywhere; refuse only where the kind is known |
| Exhaustive `case` vs fall-through (R6) | a fall-through: a partial handler for open data | totality: a missed variant is a bug | per `case`: over a declared `enum` or `record` set, totality is checked; over an open value, an `else` is required (SAFETY row 3) | continuous | checked over declared sets |
| Hygienic macro vs intentional capture (R9) | capture: anaphoric macros, DSLs | hygiene: no accidental capture | per binding: captured only when the macro writes it as `capture(name)` | continuous | hygienic |
| Tree-walker vs VM (L5) | the walker: a reference oracle, simplest semantics | the VM: speed | the evaluator in the artifact | line (Q_link) | VM for `run`; walker kept as the conformance oracle |
| Reference counting vs tracing collector (L9) | RC: no pauses, no tracer linked | a tracer: cycles through closures | collector residency, per artifact | line | RC; a tracer only when an artifact declares it |
| Stackful coroutine vs share-nothing process (L6) | a coroutine: cheap, one process, shared stack | a process: isolation, supervision | per call site: `coroutine` inside a process, `spawn` across | both exist | both on; neither replaces the other |
| JIT vs AOT vs interpreted (L10) | interpreted: start-up, REPL | AOT (WASM): no evaluator shipped; JIT: hot loops | Q_link, per artifact | line | interpreted for scripts; AOT when a Bluefile declares a WASM target |

Each default is the best answer for a program that declares nothing. A
program moves off a default by declaring a position, in the file or the
Bluefile, never by an environment variable, and `blue shift` reports the
position and what holds it there (§V.20).

Where a row needs a position the blueshift cannot yet express (the
per-protocol open/closed bit, the per-binding capture), the model gains that
axis; the language does not fork.

## 8. Phases, ranked by classes closed per effort

| Phase | Work | Closes |
|---|---|---|
| 1 | Static arity B-code from the resolver's arity table (R2) | wrong-arity calls before run |
| 2 | Slot resolver + interned symbols; VM reads slots; tree-walker kept as oracle (R1, L1, L4) | the 24% + 7% name cost; second resolution |
| 3 | Lock-free frames and upvalues (L2, L3) | the 24% allocation + 12% lock cost |
| 4 | VM-native callbacks; VM on for `blue run` (L5) | the lift cost in `map`/`filter`/`reduce` |
| 5 | Resolved-program cache by content hash (R15) | four resolutions per run |
| 6 | Coroutines: `coroutine`, `resume`, `yield` (L6) | missing generators; unspelled fiber words |
| 7 | `record` / `enum` / `protocol` surface (R4, R5, R7) + `case` destructuring (R6) | missing-field, bad-variant, missing-method bugs at run time |
| 8 | Local inference and type variables (R3, R8) | kind errors in untyped code |
| 9 | Hygienic `defmacro` (R9), const folding (R10), dead-code rules (R11) | capture bugs, run-time constants, dead code |
| 10 | Host derive for bidamas (L7) | hand-written glue per Rust library |

Each phase ships with a red-run test (the gate fails with the change removed)
and a row in `docs/PERFORMANCE.md` or `docs/DIAGNOSTICS.md`.

## 9. Tier ledger

| Item | Tier | Evidence |
|---|---|---|
| this matrix | DESIGN | this file |
| R12, R13, R16 | EXISTS | B0021/B0022, SAFETY row 17, B0056–B0060 |
| R1 at check time | EXISTS | B0001 |
| every other row | DESIGN | phases 1–10 |
