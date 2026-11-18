# Pure blue — tracks L (language) and M (memory), mapped to the code

**Tier: DESIGN (2026-11-17).** Plan: [`../PURE-BLUE.md`](../PURE-BLUE.md). Paths are relative to
the blue repo unless prefixed `tatara-lisp/`; read on 2026-11-17.

**Base for tatara changes:** blue pins tatara-lisp-eval **0.4.23** (`Cargo.toml:44-45`); the
local checkout is 0.4.21 and differs in `eval.rs`, `ffi.rs`, `words.rs`, `vm/{op,run}.rs`.
Work from 0.4.23. tatara-lisp-eval has eight other dependents (izumi, arnes, vigy, mado,
escriba, …), and its auto-release waits for blue's conformance, so a `Value` API change is a
fleet change.

## How mutation works today (the facts L and M rest on)

- `set!` is `sf_set` (`tatara-lisp-eval/src/eval.rs:2542`) → `Env::set` (`env.rs:628`), a write
  through `Arc<Frame>` behind an `RwLock`. A closure keeps the whole frame chain
  (`Closure.captured_env`, `value.rs:148`), so a rebind is seen by every closure on that frame.
- The VM emits `StoreLocal`/`StoreCaptured` (`vm/compile.rs:1128`, `:512`) and promotes a
  captured local to `Arc<Mutex<Value>>` (`vm/run.rs:358-747`).
- **`set!` is not the only rebind:**
  - `x = e` is `(define x e)` (`blue-lang-syntax/src/parse.rs:1206`); a second `x = …` after a
    closure captured `x` mutates.
  - `while` is a stdlib macro over `letrec` + lambda (`lisp_stdlib.tlisp:967`), so every
    `while(c, set!(acc, …))` rebinds a captured name (5 in `bpf.b`, 1 in `kaaneru.b:783`).
  - The VM lowers `letrec` to `let`-nil + `set!` (`vm/compile.rs:815-860`).
  - `Value::Promise` mutates through a `Mutex` (`value.rs:40`).
- Measured: 43 `set!(` in 18 files, 69 `while(` in 22 files; 4 of the files are `spec/rows`.
- **Reuse in place today** works only through the "owned" convention: `register_owned_fn`
  (`eval.rs:225`) for `cons`, `append`, `assoc`, `dissoc`, `hash-map-set` and blue's `append`
  (`stdlib.rs:557`), deciding by `Arc::make_mut` (`map.rs:259`). An argument is unique only in
  a tail call, where the walker releases the caller's frame first (`TailOutcome::Apply`,
  `eval.rs:1545`). Elsewhere the binding is a second reference and the update copies.

## L — the language

### L0 — measure every rebind

- **Change.** A rule `B0101 captured-rebind` with a `ratchet:` (`blue-lang-check/src/rules.rs:83-107`),
  counted by `blue census`. It flags `set!` on an enclosing binding, a repeated `define` after
  capture, `set!` in a `while` body, and rebinding inside `delay`. The `Scopes` walker
  (`blue-lang-syntax/src/scope.rs:448`, `place` :873) already reports `set!` targets.
- **Where it lives.** The census covers the fleet, and project rules (`rules/*.b`) run only on
  this repo; so either `blue census` learns to load a rule file, or the rule ships built in.
  Blue first: teach `census` to load `rules/mutation.b`.
- **First commit.** `rules/mutation.b` with `captured_rebind`, its tests (gamen's
  `sink = (t) -> set!(seen, …)` found; a plain local `set!` not).
- **Exit.** The census count equals the ratchet; a rise fails `checks.namespace-census`.

### L1 — typed cells

- **Collision.** `get` (`docs.rs:358`) and `put` (dispatch verb, `docs.rs:368`) exist, and six
  bidamas define their own `put`. The words are `cell`, `cell_get`, `cell_put`.
- **Change.** The cell is `Value::Foreign(Arc<Cell>)` registered from `blue-lang-runtime`, so no
  tatara publish is needed yet (precedent: blue overrides `append`, `stdlib.rs:557`). `B0101`
  becomes an error at ratchet 0 (`Rule::active`, `rules.rs:109`), and its fix names `cell`. A
  `blue migrate` rule (`crates/blue-lang-cli/blue/migrate.b`) rewrites
  `while(c, set!(acc, f(acc)))` to recursion or `reduce`, and the sink pattern to a cell. The
  runtime's own `while`/`letrec` lowering stops using `set!`.
- **First commit.** `cell`/`cell_get`/`cell_put` with rows in `spec/rows/cells.b` on walker and VM.
- **Exit.** Census 0, the rule active, `spec/rows/control.b:142` rewritten.

### L2 — fixed-width integers

- **Today.** `Ty` (`blue-lang-check/src/lib.rs:73`) has no widths; `Ty::from_sexp` (:92) parses
  `u8` as an opaque `Named`; `op_sig` (:866) hard-codes `Int`; runtime is `Value::Int(i64)`;
  bit words are 64-bit (`bits.rs:65-90`); kaaneru checks widths by hand (`imm32_of`, `bpf.b:407`).
- **Change.** `Ty::UInt(u8)` and `Ty::SInt(u8)`, compatible with `Int` and range-checked;
  width-aware `op_sig`; width words (`u8_add`, `as_u32`, …) in a blue bidama over the existing
  bit words. No new runtime variant until B5 unboxes.
- **First commit.** `from_sexp` learns `u8…i64`; `diagnoses(["B0004"])` when a `u8` parameter
  gets 300.
- **Exit.** The rows pass; kaaneru's `imm32_of` guards become typed signatures.

### L3 — deterministic expansion

- **Today.** `gensym` is a process-global `AtomicU64` (`primitive.rs:768`). The check stage runs
  on unexpanded forms (`pipeline.rs:1095`), but `program_names` expands builtin macros on a
  separate interpreter (`pipeline.rs:1812-1841`), advancing that counter, so later names depend
  on what was checked first. The expander has no hygiene (`macro_expand.rs:23`).
- **Change.** Blue re-registers `gensym` with a counter per interpreter seeded from the form's
  def-hash and an ordinal (no tatara publish: `register_fn` overwrites). Then the pipeline
  becomes lower → expand fully → check.
- **First commit.** The override and a test expanding one file twice in one process, byte-equal.
- **Exit.** Two expansions of the corpus byte-identical (`blue ast --expanded`, a nix check).

## M — memory

### M1 — ownership facts

- **Conflict to resolve.** The checker is built to skip unannotated code ("zero analysis at rung
  0", `lib.rs:1-30`). Ownership needs every expression, so it is its own pass, outside the
  typing ladder, with its own `check_cache::Pass` entry.
- **Change.** `Fact { span, kind: LastUse | Borrow | Unique | Escape | Reuse, name }`, computed
  per definition with a borrowed-parameter summary per callee, **on the expanded, resolved tree
  the runtimes execute** (so after L3). Written in tatara-lisp or Rust until blue code can see
  spans (F1); the Lisp-layer plan puts it in a tatara-lisp pass (`lisp-layer.md`).
- **First commit.** `last_use` for parameters and `let` bindings in straight-line code, one row.
- **Exit.** `Expect::Facts` in `crates/blue-lang-test/tests/conformance/rows.rs:116`; rows per
  kind in `spec/rows/memory.b`.

### M2 — reporting

- **Today.** `Cmd::Explain` (`blue-lang-cli/src/main.rs:438`) takes a code or `--list`; the LSP
  serves inlay hints only with live evaluation on (`blue-lang-lsp/src/server.rs:306`, `:1005`).
- **Change.** `blue explain --memory FILE` (a blue renderer over JSON facts); static memory hints
  merged into the LSP's inlay hints, served without live evaluation.
- **Exit.** Golden output per M1 row; an LSP test.

### M3 — the fallback runtime on the model

- **Change** (tatara-lisp-eval; publish then bump the pin):
  - `Env::take` and a VM `MoveLocal` op that move a value out at its last use;
  - last uses marked by a `%move` form that blue's lowering emits from M1's facts;
  - flat closures (L1 makes captures immutable), which removes the frame ring and
    `release_scope_frames` (`env.rs:696-787`);
  - cells, including `letrec`'s, as the only roots the cycle collector scans.
- **Arc stays atomic until M4.** Blockers: `Value::Foreign` is `Send + Sync` (`value.rs:52`);
  `blue-lang-proc` needs `Interpreter: Send + Sync` (`lib.rs:449`); idle lanes send a whole
  `Proc` across threads (`node.rs:1720-1790`); forks share sealed frames via `ArcSwapOption`
  (`env.rs:499-502`); `copy_data` shares `Str` across processes (`mailbox.rs:177-185`).
  After M4, follow Lean 4: counts are non-atomic by default, and a value reachable from another
  thread is marked shared and counted atomically.
- **First commit.** `Env::take` and in-place reuse for a binding at its last use outside tail
  position; a row where `assoc` in a fold updates in place, measured with
  `blue-lang-runtime/src/alloc.rs`.
- **Exit.** I2 and I3 on walker and VM (extend `tests/interpreter_leak.rs`); a gain on
  `bench/bench.b` against `bench/cost.baseline`.

### M4 — per-process heaps

- **Today.** A `Vm` and `Interpreter` per process (`blue-lang-proc/src/lib.rs:219`), but not a
  heap per process (`lib.rs:38-41`). `send` deep-copies and the sender keeps a reference
  (`node.rs:3613-3630`). Mailboxes: `NodeState.boxes` (`node.rs:559`). Live bytes per process
  are counted (`alloc::Account`, `node.rs:1630-1650`).
- **Change.** `send` takes the owned convention and moves a uniquely held message; forks copy
  shared frames or mark them shared and immortal; strings are copied across processes.
- **First commit.** A row showing a dead process's `Account` falls to 0.
- **Exit.** Move-vs-copy rows in `spec/rows/processes.b`; live count zero after exit.

## Corrections to the plan

1. **The census counts every rebind**, not only `set!`: `define` after capture, `while`,
   `letrec`, `delay`.
2. **M1 needs L3**: facts on the expanded tree.
3. **M4 comes before the `Arc` → `Rc` half of M3.**
4. **I4 (cycles only through cells) is broken by `letrec` and local `def`** until closures are flat
   or `letrec` cells are collector roots.
5. **M3 is a tatara-lisp-eval release**, a fleet change for its nine dependents.
