# Pure blue — tracks B (backend) and R (runtime), mapped to the code

**Tier: DESIGN (2026-11-17).** Plan: [`../PURE-BLUE.md`](../PURE-BLUE.md). Paths are relative to
the repo root and were read on 2026-11-17.

## Facts every rung stands on

- **Bytes are lists of Ints 0..255** (`read_bytes`/`write_bytes`, `bidamas/baito/baito.b`
  `layout`/`pack`/`unpack`). No packed byte value exists yet.
- **Int is checked i64.** No fixed-width types; `bpf.b` fakes them with `mask32`/`low32`/`sign32`
  (`bpf.b:1380-1407`). An unsigned 64-bit immediate above 2^63 is a negative Int until L2.
- **`Value` lives in tatara-lisp-eval**, a crates.io dependency. Builtins are installed by
  `install_full_stdlib_with` (`crates/blue-lang-runtime/src/lib.rs:142`).
- **The walker runs ~790× slower than Rust** (fib 788×, loop 1637×; `docs/PERFORMANCE.md`
  §1.4.1). Every blue compiler pass runs at that speed until S1, so stage 1 is measured early.

## B — the backend

### B0 — the nanopass library

- **Today.** Nothing; `chuuzou.b` is one hand-written pass.
- **Change.** A bidama with two macros: `defir` declares an IR language (terminals, productions
  as form shapes); `defpass` declares a rewrite from one language to another, writing only the
  cases it changes and generating the identity cases. Expansion checks every emitted form
  against the target language. Method: `lisp-layer.md` §2.
- **First commit.** `defir` for a two-production toy language and a `defpass` that renames one
  form, with a row where a pass emitting a forbidden form fails at expansion.
- **Exit.** That row; B1's first pass written with it.

### B1 — the IR

- **Today.** `native/bidamas/chuuzou/chuuzou.b` (3,386 lines) is one pass from the resolved
  tree to Rust-AST JSON: its reader `cz_read` :177, names :226-265, types `cz_sig_ty` :388 /
  `cz_ty` :545 / `cz_unify` :476, records :461-2217, list strategies `cz_list_op` :1143 /
  `cz_strategy` :1082, a borrow seed `cz_borrowed` :1101 and use count `cz_uses` :1365, tail
  loops `cz_tail` :1587, call graph `cz_recursive` :1644-1698, range facts `cz_nonneg` :2133,
  driver `cz_lower` :2263. It handles `if`, `begin`, arithmetic, records and Int lists: no
  lambdas, closures, strings, maps, floats or `rescue`.
- **Change.** A new bidama `native/bidamas/ir/ir.b`:
  - `atom`: `{var:}`, `{int:}`, `{float:}`, `{sym:}`
  - `bind`: `{let:, prim:, args:}`, `{let:, call:, args:}`, `{let:, alloc:, fields:}`,
    `{let:, closure:, env:}`, `{dup:}`, `{drop:}`, `{reuse:, as:}`
  - `term`: `{ret:}`, `{if:, then:, else:}`, `{jump:, args:}`, `{tail:, args:}`
  - functions: `{name:, params:, free:, body:}`

  chuuzou's reader, name, record, type, recursion and range passes move into the IR front;
  chuuzou stays as one backend (IR → Rust AST), so its corpus keeps passing. New passes: ANF,
  closure conversion, Perceus `dup`/`drop` from IR liveness (generalising `cz_uses`).
- **First commit.** `ir.b` lowering chuuzou's current subset, plus `ir_eval`, an interpreter.
  Test: every `native/corpus/*.b` gives the same output under `ir_eval` as `blue run`
  (reuse `native/checks/corpus.b`'s `difference`).
- **Exit.** `checks.ir-conformance`: `ir_eval` equals the walker on every accepted row, the
  accepted count is a ratchet, and the live count is zero at exit.
- **The core the IR must accept (measured 2026-11-18).** `blue ast --resolved` lowers all of
  blue to a small core. Over the four compiler sources (chuuzou, bpf, erufu, baito) the heads
  are `equal?` 2819, `list` 2766, `get` 2347, `define` 2079, `hash-map` 1263, `if` 745,
  `begin` 731, `concat` 686, `lambda` 432, `assoc` 328, `nth` 298, `try`/`catch` 239,
  `cond` and `let` (a `case` lowers to `let` over `cond` with `equal?` tests), `quote`, and
  calls to globals and builtins. So: a `rescue` is `(try body (catch (e) handler))`; a map
  literal is `hash-map`; indexing a map is `get`; `case` is `(let ((case-subject k)) (cond ...))`.
  B1's source language is exactly these forms, and `henkan` (B0) declares it.

### B2 — the x86-64 encoder

- **Today.** `bidamas/kaaneru/bpf/bpf.b` is the template: tables as `[name, bits]` rows
  (`sizes` :38, `alu_ops` :47, `jump_ops` :93, `op_table` :25), `insn` :419, operands
  :371-407, labels and `assemble` :754-896, `encode_insn` :965, `decode` :1007, `text` :1324,
  `disassemble` :1369. The oracle `kernel/isa_llvm.b` runs `llvm-mc --show-encoding` over a
  generated corpus, but by hand (`docs/KERNEL.md:255-258`), not as a flake check.
- **Change.** `bidamas/kaaneru/x86/x86.b` in the same shape: `x86_ops` rows `[name, opcode,
  form]` (forms `:mr :rm :mi :oi :m :d32`), operands `r64`, `mem(base, index, scale, disp)`,
  `imm(n, width)`, encoders `rex`/`modrm`/`sib`/`disp`, `encode_insn`, `text` (AT&T for
  llvm-mc), `decode`. Oracle `kernel/x86_llvm.b`: operations × operand forms × registers,
  including r12/r13 and rsp/rbp (the SIB and displacement edge cases).
- **First commit.** `mov`/`add`/`sub`/`cmp` (r64↔r64, r64←imm32), `ret`, `syscall`, the oracle,
  wired as `checks.x86-isa-llvm` with nixpkgs' llvm-mc. Make `isa_llvm.b` a flake check too.
- **Exit.** `checks.x86-isa-llvm`: N of N byte-identical.
- **New work the BPF path lacks:** branch relaxation (rel8/rel32 to a fixpoint; BPF slots are
  fixed, `slots_of` :775), SSE2 for floats (`cvtsi2sd`, `movsd`, `ucomisd`), `movabs` imm64.

### B3 — code generation

- **Today.** The nearest is `bpf.b`'s compiler (:2915-5411): value in r0, stack slots, no
  register allocator. Linear scan: not found.
- **Change.** `native/bidamas/x64/`: `isel.b` (IR → instructions on virtual registers),
  `regalloc.b` (live intervals, linear scan over 14 registers, spill slots), `abi.b` (a
  SysV-like internal convention, frame layout, `jo` → a fault stub for checked arithmetic).
- **First commit.** isel and an all-spilled allocator for `native/corpus/arith.b`, returning a
  value through `exit`. Needs B4's first commit.
- **Exit.** `checks.native-x64-corpus`, then an `Ev::Native` column in
  `crates/blue-lang-test/tests/conformance/rows.rs:28` (and `ALL` :59) with a ratchet on rows
  passing.
- **Also:** a stack-depth guard (host64 allows 100,000 frames today, `kiban.b:91`) and yield
  checks at calls and loop back edges for R5's preemption.

### B4 — ELF executables

- **Today.** `bidamas/kaaneru/erufu/erufu.b`: layouts :24-90; `encode` :296 hardcodes a
  relocatable (`type: 1`), `machine: 247` (BPF) and no program headers; `.rel` only;
  `decode` :407 reads sections, not program headers; `program_of` :1753 refuses machine ≠ 247.
- **Change.** `phdr_layout`; `executable(segments, entry)` writing ET_EXEC, EM_X86_64 (62),
  PT_LOAD for RX text and RW data, page-aligned; `decode` reads program headers. No
  relocations: codegen resolves every address, as `assemble` resolves labels.
- **First commit.** `erufu::executable` over hand-assembled `mov eax,60; xor edi,edi; syscall`;
  a doctest round-trips through `decode`; a Linux check runs it and gets exit 0.
- **Exit.** `checks.native-hello-elf` on an x86-64 Linux builder: a blue-compiled hello prints; `readelf -lh` agrees
  with `erufu::decode` (the `kernel/object_llvm.b` pattern).

### B5 — optimisation

- **Today.** Range-proven check removal (`cz_nonneg`), tail loops, in-place push (sums 8.8× →
  1.5×). Bench: `bench/bench.b native`, Rust twins in `bench/native/*.rs`, baseline
  `bench/native.baseline`.
- **Change.** `native/bidamas/ir/opt.b`: inlining, unboxed Ints where typed, drop fusion,
  reuse pairing; `cz_nonneg` ported onto the IR.
- **Exit.** `checks.native-bench` against `bench/native.baseline`, a ratchet (I7).

## R — the runtime

### R1 — the raw seam

- **Today.** kiban models raw words in blue (`mmio_write` :210, `put_byte` :230, `reclaim`
  :259) and lowers them to the `kiban_io::Io` trait; the emitted crate is `forbid(unsafe_code)`
  and only the seam crate is unsafe.
- **Change.** kiban gains `load_word`, `store_word`, `syscall6`; the IR has them as prims and
  isel lowers them to `mov [r]` and `syscall`. A checker rule refuses them outside the runtime
  bidama (I5), built like the existing B-rules.
- **First commit.** The three words with walker models (memory as a simulated map; `syscall6`
  refusing), the rule, a refusal row in `spec/rows/refusals.b`.
- **Exit.** The I5 row; `write(1, …)` through `syscall6` prints natively.

### R2 — the allocator

- **Today.** Rust only: `native/seam/kiban_heap.rs` (171 lines, `Rc<Vec<i64>>` plus arenas),
  `crates/blue-lang-runtime/src/alloc.rs` (per-thread allocation counts), `memory.rs` (a
  live-byte limit). No blue allocator.
- **Change.** A new bidama (name to mint): mmap'd chunks, size classes, free lists, a header
  word `{count, tag, size}`, `dup`/`drop`/`reuse`, a live-object counter for I3.
- **First commit.** A bump allocator with counts over R1, running `native/corpus/lists.b`
  natively with live count zero at exit.
- **Exit.** `checks.no-leak` native; `sums.b` within its current 1.32× of Rust.

### R3 — values

- **Today.** All in tatara-lisp-eval and `stdlib.rs`. Semantics to match: `length` counts
  characters; full Unicode case mapping; maps ordered by key across kinds (REFERENCE.md:245);
  `to_s` from `display.rs`.
- **Change.** A values bidama: UTF-8 strings, a persistent vector, a sorted map, closures as
  `{code, env}`, errors, `render` byte-identical to Rust's.
- **First commit.** Strings and `render` of Int, Str and List: the value rows of
  `spec/rows/lists.b` and `strings.b` natively.
- **Exit.** `lists`, `maps`, `strings`, `records`, `numbers` rows in the `Ev::Native` column.
- **Missed by the plan:** shortest round-trip float printing and parsing (a Ryu-class algorithm),
  Unicode case tables, cross-kind key ordering (NaN last), a packed byte value.

### R4 — host words over syscalls

- **Today.** 621 reference rows (files 28, processes 10, time 7, network 45, hashing 24, blue
  processes 26), implemented in `crates/blue-lang-runtime/src/sys.rs` (1,978 lines), `net.rs`
  and `net/` (1,134 + TLS), `crates/blue-lang-host/src/world.rs`.
- **Change.** A syscall bidama (name to mint): `open`/`read`/`write`/`close`, `clock_gettime`,
  `execve`/`fork`/`pipe`/`wait4`, `socket`/`connect`/`bind`/`epoll`, termios.
- **First commit.** `write_stdout`, `read_file`, `write_bytes`, `exit` natively with their rows.
- **Exit.** The 40 `spec/rows/host.b` rows natively; REFERENCE.md gains a "home" column.
- **On the critical path:** the compiler itself calls `exec_capture`, `exec_with_stdin` and
  `self_exe` (chuuzou :2403, :2417, :2442).

### R5 — processes

- **Today.** `crates/blue-lang-proc` (10,959 lines): `node.rs`, `mailbox.rs` (deep copy on
  send), `scheduling.rs`; a `Vm` and `Interpreter` per process; preemption by the VM's
  reduction counter.
- **Change.** A blue scheduler: green stacks, run queues, mailboxes that move or copy, links,
  monitors, supervisors, over R2's per-process heaps and B3's yield points.
- **First commit.** `spawn`/`send`/`receive`, cooperative, natively.
- **Exit.** The 28 `spec/rows/processes.b` rows natively; a dead process's heap reads zero.

### R6 — libraries in blue

- **Already blue:** HPACK (`bidamas/eigyou/heddaa/heddaa.b`), HTTP/2 frames
  (`bidamas/eigyou/tajuu/tajuu.b`), bit words (`shinsuu`).
- **Still Rust:** JSON (`json.rs`, serde_json), all crypto (`crypto.rs`, 1,602 lines: BLAKE3,
  Ed25519, X25519, ChaCha20-Poly1305, SHA-1/2, HMAC, Bao), Nix parsing (rnix), XML, YAML,
  FROST threshold signatures, the HTTP/1.1 listener.
- **First commit.** A blue JSON reader and writer, differential against `json_read`/`json_write`
  on the 15 `spec/rows/json.b` rows. Then BLAKE3 against `blake3_hex`.
- **Exit.** json and crypto rows natively; `checks.purity-ledger` falls.
- **Needs L2 first:** constant-time arithmetic and Ed25519 field math need unsigned 64-bit and a
  64×64→128 multiply.

### R7 — TLS

- **Today.** `net/tls.rs` over rustls and ring, webpki-roots for trust.
- **Change.** TLS 1.3 in blue over R6: X25519, ChaCha20-Poly1305, SHA-256, signature verify
  (Ed25519, ECDSA P-256, RSA for real certificates), X.509.
- **First commit.** The HKDF key schedule, checked against the RFC 8448 vectors.
- **Exit.** The purity ledger at the four world facts.

## What must run natively before the compiler compiles itself

chuuzou, bpf, erufu and baito use keyword maps and `**` spread, string interpolation (61 and
133 sites), lambdas (~120 each), `rescue`, `raise`, `case`/`when`, optional parameters, `use`
across bidamas, the list words, and `while` + `set!` (4 sites in bpf at :1016, :2299, :2323,
:2741; 4 in btf), which L1 rewrites. Their builtins include `json_read`, `json_stringify`,
`read_file`, `write_file`, `mkdir_p`, `temp_dir`, `exec_capture`, `exec_with_stdin`, `self_exe`.

So the minimum native rows are `functions`, `control`, `lists`, `maps`, `strings`, `records`,
`errors`, `patterns`, `numbers`, `keywords`, `modules`, `json`, and the host file and exec
rows, plus a native reader (F1) before S1.

## Stage 0 and speed

At ~790× Rust, a blue compiler run on the walker would take hours per build. Once B1 makes
chuuzou the IR → Rust backend, chuuzou's subset is the IR's subset, so stage 0 is `bluec.b`
compiled through IR → chuuzou → rustc and runs at native speed. The walker builds the compiler
once per seed, as the DDC witness (S2). B1's exit times its passes over `chuuzou.b` on the
walker, so the cost is measured, not guessed.

Every finding of this mapping (B1 without M1, flake-checked oracles, a byte-identical
`render`, floats, branch relaxation, stack guards, yield points, the Rust-backed words split
into R6a-c, a packed byte value) is folded into the plan's §6-§7.
