# Pure blue — the implementation plan

**Tier: DESIGN (2026-11-17).** Nothing here is built unless a row says so.

## 1. The destination

1. **Pure.** Every byte of blue's toolchain that runs (reader, checker, formatter, compiler,
   runtime, standard library) is blue source, or machine code that blue emitted from blue
   source. Four facts of the world stay outside, each a typed seam of data, never code in
   another language:
   - the instruction set;
   - the kernel's system call ABI;
   - executable formats (ELF, Mach-O);
   - on macOS, the `libSystem` dynamic imports, because Apple gives no stable raw syscall ABI.
2. **Rust's discipline is the floor, and the compiler proves it.** One owner per value, a
   value freed at its owner's last use, sharing only through a counted handle. Rust makes the
   author prove ownership to the compiler; blue makes the compiler prove it for the author
   (§4).
3. **Blue all the way down.** `blue` compiles itself to the same bytes twice, and the tower
   ends at a full-source chain from a seed small enough to audit as hex (Guix style).
4. **Two runtimes, one language.** The pure native build is the default. The Rust
   implementation stays a fully supported fallback runtime. Both are held to the same
   conformance suite, permanently.
5. **Linux first.** x86-64 Linux (rio, plo); aarch64 macOS follows.

## 2. Ground truth (measured 2026-11-17)

| Fact | Value |
|---|---|
| Rust in blue | 25 crates, 144,354 source lines |
| Rust from crates.io | tatara-lisp (~95k lines; reader, macro expander), tatara-lisp-eval (~25k; walker, VM) |
| Blue | 600 `.b` files, ~246k lines |
| Already pure | the BPF path: `kaaneru/bpf` encodes BPF (7,610 lines), `kaaneru/erufu` writes ELF (2,302); byte-identical to `llvm-mc` on 166 of 166 instructions |
| Native today | `chuuzou` (3,231 lines) lowers the resolved tree to a Rust AST; rustc emits the code |
| Value model (fallback runtime) | `Value` holds `Arc<str>`, `Arc<List>`, `Arc<Map>`, `Arc<Closure>`: atomic reference counts, copy-on-write |
| Reuse in place | already: `cons`, `append`, `assoc` update in place when the value is held nowhere else |
| Mutation | one form, `set!` (rebind a name): 43 calls in 18 of 600 files in this repo, 4 files elsewhere; `while` (needs `set!`): 69 calls in 22 files |
| Types in the checker | `Dyn, Int, Float, Str, Bool, Sym, Nil, List, Map, Record, Union, Named, Fragment`; no fixed-width integers |

So the fallback runtime is already a reference-counted runtime with reuse in place. The
model in §4 makes those counts *inferred, non-atomic and mostly removed*, and gives the
native build the same semantics.

## 3. Invariants

Each is a check that fails the build. They hold from the rung that introduces them onward.

| # | Invariant | Check |
|---|---|---|
| I1 | Every conformance row gives the same answer on the walker, the VM and native | `checks.conformance-three-way`, one run per row per runtime |
| I2 | Both runtimes free and close at the same points for every row that observes it | resource-timing rows in `spec/rows` |
| I3 | No row leaks | `checks.no-leak`: live-object count is zero at exit, per runtime |
| I4 | A cycle can form only through a typed cell | a checker rule; a fuzz row that builds every value shape |
| I5 | Raw-memory words are reachable only from the runtime bidama | a check-stage rule |
| I6 | The non-blue bytes in the pure toolchain only fall | `checks.purity-ledger`, a ratchet |
| I7 | Native speed never regresses | `checks.native-bench`, a ratchet per benchmark against its Rust equivalent |
| I8 | The compiler is a fixpoint of its own source, and the seed chain rebuilds it | `checks.pure-fixpoint`, `checks.pure-full-source` |

## 4. Memory: inferred ownership

1. **Values are immutable.** A new value points only at older values, so ordinary data
   cannot form a cycle.
2. **Ownership is inferred.** The compiler computes each value's last use and frees it there
   (Perceus, as shipped in Lean 4 and Koka). No lifetimes, no `&`/`&mut`, no borrow checker
   for the author.
3. **Borrowing is inferred.** A value only read inside a call is passed with no count change.
4. **Counts are the compiler's fallback** where sharing is real (where Rust makes the author
   write `Rc`/`Arc`). They are non-atomic inside a process.
5. **Reuse in place.** An update to a value whose count is one mutates it in place (blue
   already does this for `cons`, `append`, `assoc`; the model makes it universal).
6. **A heap per blue process** (the Erlang model). A message moves when uniquely held and is
   copied otherwise; a dead process frees its heap at once; counts never cross a process.
7. **Cells are the only mutation and the only cycle source.** A `cell` is a typed value; a
   small collector scans cells only, never the whole heap.
8. **Resources are values.** A file, socket or lock closes at its last use, without `defer`,
   `finally` or a finaliser.
9. **The cost model is visible.** The engine and the LSP report each fact: freed here, shared
   here, updated in place here, copied into a message here.

## 5. Tracks and rungs

Seven tracks. Each rung ends at a check that fails without it. A rung depends only on the
rungs named in its "after" column. Each track is mapped to the code, file by file, with its
first commit and its blockers:

| Track doc | Tracks |
|---|---|
| [`pure-blue/language-memory.md`](pure-blue/language-memory.md) | L, M |
| [`pure-blue/backend-runtime.md`](pure-blue/backend-runtime.md) | B, R |
| [`pure-blue/front-tower-conformance.md`](pure-blue/front-tower-conformance.md) | F, S, C |
| [`pure-blue/lisp-layer.md`](pure-blue/lisp-layer.md) | how every track is written over tatara-lisp forms |

**Lisp is the method.** Blue's tree is tatara-lisp data, so the IR is forms, every pass is a
small rewrite between declared languages (nanopass), Perceus is one of those rewrites, macros
generate tables and specialisations, the runtime is a declared subset (PreScheme), and the
bottom of the tower is a tiny Lisp (Mes). See `lisp-layer.md`.

### L — the language moves onto the model

| # | Rung | After | Exit check |
|---|---|---|---|
| L0 | **Measure** mutation: every `set!`, `while` and captured rebound name across the fleet, with the closures that share one | — | a committed census; the count is a ratchet |
| L1 | **Typed cells.** A `cell` word (`cell`, `get`, `put`); `set!` on a name a closure captures becomes a checker error pointing at `cell`; `while` loops rewritten as recursion or `reduce` | L0 | the census reaches 0 untyped captured rebinds; `legacy_names` and a `blue migrate` rule rewrite the 22 files |
| L2 | **Fixed-width integers** (`u8`…`u64`, `i8`…`i64`) and a type language the IR and encoders need | — | checker rows; the encoders in B2 use them |
| L3 | **Deterministic expansion**: expansion before check, deterministic `gensym` | — | two expansions of the corpus are byte-identical |

### M — the memory model

| # | Rung | After | Exit check |
|---|---|---|---|
| M1 | **Ownership facts**: the Perceus pass (B1) in explain mode, on the expanded tree, returning last use, borrow, uniqueness, escape, reuse as data | L1, L3, B1 | facts over the corpus; a row per fact kind |
| M2 | **Facts reported**: `blue explain --memory`, LSP hints without live evaluation | M1 | golden output per row |
| M3 | **The fallback runtime follows the model** (a tatara-lisp-eval release): `Env::take`, a VM `MoveLocal`, `%move` marks from M1, flat closures, cells as the only collector roots | M1 | I2, I3 on the walker and the VM; a gain on `bench/cost.baseline` |
| M4 | **Per-process heaps** in `blue-lang-proc`: `send` moves a uniquely held message and copies otherwise; forks stop sharing frames; strings copied across processes | M3 | process rows; a dead process's account falls to zero |
| M5 | **Non-atomic counts**: Lean 4's scheme, non-atomic by default, atomic only for a value marked shared across threads | M4 | the `Send + Sync` blockers gone; a benchmark gain |

### F — the front end in blue

| # | Rung | After | Exit check |
|---|---|---|---|
| F1 | **Reader**: lexer and parser as a bidama, emitting the same tree as `blue-lang-syntax` | — | differential over every `.b` in the fleet: identical trees and spans |
| F2 | **Macro expander** in blue (replaces tatara-lisp's expander for blue) | F1, L3 | differential over the corpus |
| F3 | **Checker** in blue: names, types, rules, and M1's facts | F2, M1 | differential against `blue-lang-check` |
| F4 | **Formatter** in blue | F1 | `blue fmt` differential over the corpus |

### B — the backend in blue

| # | Rung | After | Exit check |
|---|---|---|---|
| B0 | **Nanopass library**: `defir` (a declared IR language) and `defpass` (a rewrite between two), in blue | — | a pass emitting a form its target language forbids fails at expansion |
| B1 | **IR as forms**: ANF, closure conversion, Perceus `dup`/`drop`/`reuse` from IR liveness, `ir_eval`; chuuzou's front passes move in, chuuzou stays as the IR → Rust backend | B0 | `ir_eval` equals the walker on every accepted row (a ratchet), live count zero at exit |
| B2 | **x86-64 encoder**, assembler style (the `kaaneru/bpf` method); aarch64 and riscv64 later | L2 | byte-identical to `llvm-mc` on a generated instruction corpus |
| B3 | **Code generation**: instruction selection, linear-scan register allocation, the calling convention | B1, B2 | conformance rows run native on rio |
| B4 | **ELF executables**: `erufu` grows from relocatable BPF objects to static executables | B3 | a blue-written hello runs on Linux; `readelf` agrees with erufu's own reader |
| B5 | **Optimisation**: inlining, specialisation, unboxed integers, drop fusion | B3 | I7 benchmarks improve; none regresses |

### R — the runtime in blue

| # | Rung | After | Exit check |
|---|---|---|---|
| R1 | **Raw seam**: a handful of words (load and store a machine word, a system call), reachable only from the runtime bidama | B3 | I5 |
| R2 | **Allocator and counts**: size-classed per-process heaps, non-atomic counts, `dup`/`drop`/`reuse`, the cell collector | R1, M1 | I2, I3 native |
| R3 | **Values**: strings, persistent lists and maps, closures, errors, in blue | R2 | the value rows pass native |
| R4 | **Host words over syscalls**: files, processes, time, sockets, terminal | R1 | host rows pass native; `docs/REFERENCE.md` marks each word's home |
| R5 | **Blue processes**: scheduler, mailboxes, links, supervisors, per-process heaps | R2, R4 | process rows pass native |
| R6 | **Libraries moved from Rust crates to blue**: JSON, crypto (BLAKE3, Ed25519, ChaCha20), protocols over TCP | R4 | their rows pass native; the purity ledger drops |
| R7 | **TLS**: the last contained seam, ported last | R6 | the ledger at the four world facts |

### S — the stages (the tower; "T3" already names a native tier)

| # | Rung | After | Exit check |
|---|---|---|---|
| S0 | **Purity ledger**: non-blue bytes in the toolchain closure, by layer (`gen/purity.b`, hadome) | — | I6 |
| S1 | **The fixpoint**: stage 0 (the Rust blue) runs `bluec.b` → `bluec₁`; `bluec₁` → `bluec₂`; `bluec₂` → `bluec₃`; `bluec₂ == bluec₃` | F1, B4, R5 | I8; `nix build --rebuild` bit-identical |
| S2 | **Binary seed and witness**: `seed/x86_64-linux/bluec` as a `generate` row (`nix run .#regen` updates it); DDC: the Rust runtime and the seed rebuild the same bytes | S1 | `checks.pure-seed-ddc`; the fleet's `blue` comes from the seed build |
| S3 | **Two runtimes**: `blue-native` default, `blue-rust` selectable per node (`pleme.blue.runtime`) or per run (`BLUE_DOOR`); needs `bidamasOverlay` to read `final.blue` | S2, M5 | I1–I3 on both, permanently |
| S4 | **Full-source bootstrap**: a hex seed (the nixpkgs `stage0-posix` model), a tiny Lisp reader and evaluator over blue forms, then the compiler; the binary seed is retired | S2 | `checks.pure-full-source`: the chain rebuilds `bluec` byte-identical to S2's seed |
| S5 | **aarch64 macOS**: encoder, Mach-O writer with libSystem imports and an ad-hoc code signature, the darwin host words | B5, R7 | conformance native on cid and ryn |

### C — conformance, the spine every track stands on

| # | Rung | After | Exit check |
|---|---|---|---|
| C1 | **Three-way conformance** (walker, VM, native) per row, as the native build gains rows | — | I1, with a ratchet on the count of rows native passes |
| C2 | **Memory rows**: resource close timing, leak, cycle-through-cell, message move vs copy | M1 | I2, I3, I4 |
| C3 | **Benchmarks** against Rust equivalents, native and fallback | B3 | I7 |

## 6. Phases and the critical path

| Phase | Rungs | What exists at the end |
|---|---|---|
| 1. Ground | S0, L0, L1, L2, L3, C1, B0 | the ledger, typed cells, fixed-width integers, deterministic expansion, the nanopass library |
| 2. The model | B1, M1, M2, M3, M4, M5, C2 | the IR and Perceus as forms; both existing runtimes on inferred ownership; the facts visible to authors |
| 3. First native program | B2, B3, B4, R1, R2, R3, C3 | blue programs compiled by blue to x86-64 ELF, no rustc |
| 4. A real host program | R4, R5, R6, R7, B5 | the compiler itself can run natively |
| 5. The front end | F1, F2, F3, F4 | reader, expander, checker and formatter in blue |
| 6. The tower | S1, S2, S3, S4 | the fixpoint, the seed, two runtimes, full-source bootstrap |
| 7. The second host | S5 | aarch64 macOS |

The critical path is **L1 → B0 → B1 → B3 → R2 → R4 (exec) → R5 → S1**. B1 computes
`dup`/`drop` from IR liveness on its own; M1 is the same pass in explain mode, a cross-check.
F1 (the kiwari-emitted reader) and B2 have exact oracles and no dependencies, so they run
beside phases 1 and 2. Phase 2 pays off before any native code exists: the fallback runtime
gains last-use frees, in-place updates outside tail position, and non-atomic counts.

### Work the first draft missed (found by mapping the code)

- **Rebinds beyond `set!`**: `define` after capture, `while`, `letrec`, `delay` (L0, L1).
- **`letrec` and local `def` build cycles without a cell** until closures are flat (M3).
- **F2 needs an evaluator in blue**: macros run their bodies (`ir_eval`, B1).
- **F1 is kiwari's M3** (`docs/NATURALIZE-TREESITTER.md:254`), not a third parser.
- **L3 and M3 are tatara-lisp-eval releases** (pinned 0.4.23; nine dependents).
- **The compiler spawns processes** (`exec_capture`, `exec_with_stdin`, `self_exe`): R4's exec
  words are on the critical path.
- **Floats**: SSE2 encodings, shortest round-trip printing, correctly rounded parsing.
- **x86**: branch relaxation, stack-depth guards, yield points for preemption.
- **Values**: Unicode case tables, cross-kind key ordering, a packed byte value.
- **More Rust-backed words** to move: Nix parsing, XML, YAML, FROST, Bao, SHA/HMAC, ECDSA/RSA.
- **Stage 1 speed**: the walker runs ~790× slower than Rust; measure the first self-build early.
- **S3** needs `bidamasOverlay` to read `final.blue`; **S5** needs Mach-O code signing.

## 7. Decisions (2026-11-17)

1. Linux first.
2. Memory: inferred ownership (§4).
3. Seed: the most pure; S2's binary seed is a stepping stone to S4's full-source chain.
4. The Rust implementation is a fully supported fallback runtime (S3).
5. Lisp is the method: every pass, optimisation and the memory model are written over
   tatara-lisp forms (`pure-blue/lisp-layer.md`).

## 8. Prior art, used as oracles

- **Perceus** (Reinking, Xie, de Moura, Leijen; PLDI 2021) and its successor **frame-limited
  reuse** (Lorenzen, Leijen; ICFP 2022): the inference in §4.2–4.5. Koka's test programs are
  oracles for M1 and B1.
- **Lean 4** ("Counting Immutable Beans", Ullrich, de Moura; IFL 2019): borrow inference and
  reuse in a shipped compiler; its benchmarks are oracles for C3.
- **Project Verona** (Microsoft Research): ownership by regions with concurrency; the
  reference for M4 and R5.
- **Erlang/BEAM**: per-process heaps, message copying, supervisors; the reference for §4.6
  and R5.
- **Guix full-source bootstrap** (`hex0`, stage0, GNU Mes): the reference for S4.
- **Go 1.5 and Zig** (`zig1.wasm`): self-hosting from a committed previous build; the
  reference for S2.
- **Diverse double-compiling** (Wheeler, 2009): the reference for S2's witness check.
- **Lisp prior art** (`pure-blue/lisp-layer.md`): Chez Scheme's nanopass framework (B0, B1),
  PreScheme and Scheme48 (the runtime subset, R1-R2), Carp and Baker's Linear Lisp (ownership in
  a Lisp without a collector), GNU Mes (the tiny Lisp at the bottom of S4).
