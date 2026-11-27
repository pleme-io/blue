# Stacked backends, the canonical flat seam, and capability-enforced codegen — the plan

Status: DESIGN, ratified by the operator 2026-11-27. Not yet started.

Interlocks, read before Phase 1:
- The cohesion wave owns erasure, blueshift and the pipeline surface this
  plan builds on. blue-ir lowers VERIFIED Sexp + check metadata — it must
  be sequenced with the wave's remaining units, not under them.
- The DuckDB door plan (docs/DUCKDB-DOOR.md) shares the seam discipline:
  capability vtables across one auditable boundary.
- Every phase lands through `git land` with the full gate battery; the
  conformance suite runs against every backend a phase adds.

## Objective

Extend blue from a frontend-only, type-erased interpreter into a zoned,
multi-backend language without breaking canonical syntax, the tatara-lisp
AST substrate, OTP supervision, or lock-first Nix packaging:

1. blue-ir — a type-preserving mid-level IR lowered from verified
   `tatara_lisp::Sexp` + blueshift metadata for high-blueshift zones
   (bypassing type erasure where a compiled posture is requested).
2. blue-seam — a canonical flat ABI: position-independent, pointer-free
   byte layouts with compact relative offsets; zero-copy or one-memcpy
   exchange between any two zones/backends; a linear-time verifier for
   untrusted buffers.
3. heapless/flat posture — compiler-managed data stacks, inline
   variable-sized data, static rooting, pointer-reset deallocation, no
   heap, no Arc.
4. Tiered native backends: Cranelift for dev/JIT, LLVM for release AOT,
   beside the existing Rust runtime, zero-import WASM, and --kernel eBPF.
5. Capability-enforced codegen: backends refuse to emit or link host-call
   stubs beyond the granted capability set; permitted calls route through
   a capability vtable across the seam so virtualize and blue replay work
   on native zones unmodified.
6. Showcase: examples/zero-trust-edge-gateway — eBPF drop/rate-limit →
   heapless native parser → capability-sealed bidama plugin → OTP outer
   supervisor → virtualize + blue replay deterministic crash reproduction.

## Non-negotiable constraints

- The default parse → check → erase → execute path stays intact and fast.
- No private AST: blue-lang-syntax lowers to Sexp; type/posture/capability
  metadata attaches as a side-table or the IR, never a parser fork.
- Shared-nothing across seams: no shared GC, Arc or raw pointers cross a
  seam; ownership transfers explicitly through blue-seam.
- Conformance-first: every backend passes the shared suite for the
  features its posture permits.

## Phases (strictly in order; cargo test + conformance after each)

1. blue-ir: the typed SSA-friendly IR (types, tagged unions, postures,
   per-module capabilities, explicit SeamCall) + `blue ir <file>` inspection.
2. blue-seam: the flat layout, the verifier, Sexp<->flat marshalers,
   seam-cost reporting in check and the LSP.
3. The heapless posture: static enforcement (no heap, no Arc, no escaping
   closures), data stacks with scope rooting, seam-only boundary types,
   negative-test battery.
4. Native backends: 4a Cranelift (dev), 4b LLVM (release AOT), 4c dispatch
   + artifact caching keyed by IR hash + posture + capability set.
5. Capability-enforced codegen and virtualize across seams (refuse-to-emit,
   ceiling errors, capability vtable).
6. The showcase, end to end.

## Execution rules

- Inspect the workspace first and document the plug points before code.
- One phase per milestone; no todo!() stubs across a phase boundary.
- Simple, deterministic, property-tested (round-trip fuzz Sexp <-> flat).
- Operator check-in after Phase 1 and after Phase 2 — the IR and the seam
  are the two decisions everything else inherits.
