# Pure blue — the implementation plan

**Tier: DESIGN (2026-11-17).**

**Pure blue:** every byte of blue's toolchain that runs (reader, checker, formatter, compiler,
runtime, standard library) is either blue source or machine code that blue emitted from blue
source. Four facts of the world stay outside, each a typed seam and not code in another
language: the instruction set, the kernel's system call ABI, executable formats (ELF,
Mach-O), and on macOS the `libSystem` dynamic imports, since Apple gives no stable raw
syscall ABI.

The destination: `blue` on every node is a native executable that blue compiled from blue
source, rebuilt from a committed blue seed, with the Rust implementation kept only as an
independent witness. Self-hosting through emitted Rust and rustc keeps a foreign compiler in
the seed; this plan emits machine code directly, as the BPF backend already does.

## Ground truth (2026-11-17)

- Rust today: 25 crates, 144,354 source lines, plus tatara-lisp (~95k) and tatara-lisp-eval
  (~25k) from crates.io.
- Blue today: 599 `.b` files, 246,021 lines. Toolchain-relevant: `chuuzou` (blue → Rust AST,
  3,231), `kaaneru/bpf` (encoder, assembler, compiler subset, 7,610), `kaaneru/erufu` (ELF
  writer, 2,302), `kaaneru/btf`, `gen/kigou.b` (lexer tables), `spec/rows` (the conformance
  yardstick), CLI subcommands in blue.
- Pure today: the BPF path, held byte-identical to `llvm-mc` on 166 of 166 instructions.

## Milestones

Each rung builds only on shipped rungs and ends at a check that fails without it.

| # | Rung | Reuses | Exit check |
|---|---|---|---|
| P0 | **Purity ledger.** Count the non-blue bytes in the toolchain closure by layer (reader, checker, evaluator, runtime, backend) | nix closure walk; `hadome` baseline | `checks.purity-ledger`, a ratchet that only falls |
| P1 | **Reader in blue.** Lexer and parser as a bidama, emitting the same tree as `blue-lang-syntax` | `gen/kigou.b` tables, `parse.rs` as the oracle | differential over every `.b` in the fleet: identical trees, identical spans |
| P2 | **Blue IR.** A-normal form, explicit closures, explicit allocation; the lowering moves out of `chuuzou`'s Rust-AST target | `chuuzou` passes | an IR interpreter in blue passes every `spec/rows` row |
| P3 | **Encoders per ISA** (x86-64 first, then aarch64, riscv64), assembler style | `kaaneru/bpf` encoder method | byte-identical to `llvm-mc` on a generated instruction corpus per ISA |
| P4 | **Code generation.** Instruction selection and a linear-scan register allocator from the IR | P2, P3 | `spec/rows` pass as native code on rio (x86-64) and cid (aarch64) |
| P5 | **Object writers.** `erufu` grows from relocatable BPF objects to static ELF executables; a new Mach-O writer with libSystem dynamic imports | `kaaneru/erufu` | a hello program runs on Linux and macOS from a blue-written file; `readelf`/`otool` agree with the writer's own reader |
| P6 | **Runtime in blue.** Allocator and precise reference counting first, cycle collection later; closures, strings, maps, errors; the raw-memory seam of a few words, reachable only from the runtime bidama | `kiban` heap seams | runtime tests under the native build; a check-stage rule refuses a raw word outside the runtime |
| P7 | **Host words over syscalls.** Files, processes, time, sockets; then blue processes and their scheduler (`blue-lang-proc` ported); JSON, crypto, protocols move from Rust crates to blue | existing blue HPACK/HTTP2, pure BLAKE3 | the host rows of `spec/rows` pass native; `docs/REFERENCE.md` marks each word's home |
| P8 | **Checker and formatter in blue.** Names, types, rules (partly blue already), canonical layout | `rules/conventions.b`, `okite` | differential against `blue-lang-check` and `blue-lang-fmt` over the fleet corpus |
| P9 | **The fixpoint.** `bluec` compiles itself: stage 1 → stage 2 → stage 3, `bluec₂ == bluec₃` | P1–P8 | `checks.pure-fixpoint`; `nix build --rebuild` bit-identical |
| P10 | **Seed and witness.** Commit `seed/<host>/bluec`; `nix run .#update-seed`; DDC against the Rust walker | the `generate` + `-fresh` pattern | `checks.pure-seed-ddc`; the fleet's `blue` comes from the seed build |
| P11 | **Cutover.** The Rust crates leave the build path, configured off; they stay as the DDC witness and, until it is ported, the LSP's engine | — | purity ledger at the four world facts only |

## Order and parallelism

- P0 first: it measures everything after it.
- P1 (reader) and P3 (encoders) are independent and can run beside each other; both have
  exact oracles, so they land fast.
- P2 → P4 → P5 is the spine to the first pure native program. P6 and P7 make it a real
  host program. P8 is last of the parts, because the Rust checker and formatter are shipped
  and shared with the LSP.
- P9–P11 close the tower.

## Gaps blue must grow first

`case` and walkable maps now exist. Still open:

- fixed-width integers and a type language for the IR and encoders (the checker's `Ty` has
  `Int` only);
- deterministic `gensym` and expansion before check (reproducible output, P9);
- a primitive handing blue the checked tree (until P1 and P8 replace the Rust reader and checker);
- raw-memory words for the runtime seam (P6), contained to one bidama.

## Decisions for the operator

1. **Hosts first:** x86-64 Linux (rio, plo) then aarch64 macOS (cid, ryn), or both at once?
2. **Memory:** precise reference counting with a cycle collector, or a tracing collector?
3. **Seed policy:** a committed binary seed per host plus DDC (Go, Zig), or also the
   full-source rung down to a hex seed (Guix)?
4. **The Rust implementation after cutover:** DDC witness and LSP only (proposed), or also a
   supported fallback runtime?
