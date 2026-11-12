---
kind: explanation
summary: "the GPU rung: a restricted rung of blue lowered to a WGSL compute kernel for data-parallel definitions, validated by naga at build time, gated by equality with blue's own run (design, 2026-11-12)"
---

# GPU — data-parallel blue as a compute kernel

Status: DESIGN, 2026-11-12. No code. HORIZON H8 names this placement; this
file owns its design. The [Ledger](#7-ledger) is the only place a state is
claimed.

## 1. Destination

A blue definition that is a pure map over a list or a grid runs as one GPU
compute pass, and nothing in the program says "GPU". The author writes
`map(scale, xs)` over a typed, pure `def scale(x: Int) -> Int`; blue lowers
`scale` to a WGSL kernel, the host runs it over `xs` on the device, and the
answer is the list blue's own evaluator answers, byte for byte. A definition
outside the rung is never miscompiled: the lowering refuses it with the
construct and the rule, and the map runs on the CPU, as today.

This is the data-parallel lever of PERFORMANCE.md §3.0 ("a pure map runs over
a grid or a list: one GPU compute pass instead of a CPU loop"). Its bench row
is a ratio to a Rust twin, as the memo, bake and incremental rows are.

## 2. What exists, and what each part reuses

| Need | Exists | Move |
|---|---|---|
| the program, checked and resolved | `blue ast --resolved`, read by chuuzou's `cz_read` (`native/bidamas/chuuzou`) | reuse: the GPU rung is a second emitter beside chuuzou's Rust emitter, over the same resolved tree |
| which definitions are pure | capabilities name every effect (SAFETY.md); a definition that reaches none is pure | reuse: only a pure definition enters the rung |
| the types of the rung | typed signatures (H2), checked at the boundary | reuse: `Int`, `Float`, `Bool` and records of them; nothing else |
| WGSL to a checked module, pure Rust | `naga`: `front::wgsl::parse_str`, `Validator::new(ValidationFlags::all(), …)` (garasu, engawa and kasane use it through wgpu 25) | reuse as a build- or dev-dependency, so no shipped binary parses a shader and no C is linked (CONTAIN THE C) |
| running a kernel | `engawa` (render graph) and `engawa-metal` (Metal executor); wgpu on Linux | reuse at the host seam: Rust keeps only the device call |
| the equality gate | `checks.conformance` compares output across placements; the placement test compares receipts | reuse: the GPU is one more column |

## 3. The rung

The restricted rung is the subset whose meaning a compute kernel can hold
exactly. One table, in the order it lands:

| Blue | WGSL | Why it is exact |
|---|---|---|
| `def f(x: Int, …) -> Int` with no capability | `fn bl_f(p_x: i32, …) -> i32` | Int on the rung is 32-bit, as chuuzou's board word is on a 32-bit board; a result outside i32 is refused at the boundary (G3), never wrapped |
| `+ - *`, `floor(a / b)`, `mod` | checked i32 ops through a helper that sets a fault flag | WGSL integer overflow wraps; blue raises. The kernel writes a fault word, and the host raises :overflow naming the index, as the walker would |
| `== != < <= > >=`, `not and or`, `if` | the same | — |
| a call to another rung definition | a WGSL function call | recursion is refused: WGSL has none |
| `record p(x: Int, y: Int)` | `struct R_p { x: i32, y: i32 }` | the record's own struct, as chuuzou lowers it |
| `Float` | `f32` only where the definition declares `Float32` | blue's Float is f64; WGSL's f64 is an optional feature. Until a device reports it, a Float definition stays on the CPU (refused with that reason) |
| `map(f, xs)` where `f` is on the rung | one dispatch, `@workgroup_size(64)`, one invocation per element, `arrayLength` bound | the map is the only entry point: a kernel has no other caller |

Everything else (strings, maps, lists inside the kernel, closures, effects,
recursion, `raise` other than overflow) is refused by the lowering with its
name. The refusal is the rung's edge, not a bug.

## 4. Where it runs

| Phase | What happens | Where |
|---|---|---|
| lower | resolved tree → WGSL text (a blue emitter, a level of chuuzou) | build time |
| validate | naga parses and validates every emitted module with `ValidationFlags::all()`; a WGSL error is a build failure | build time, CI, any machine |
| dispatch | the host hands the input buffer to the device and reads the output and the fault word | run time, a device with an adapter |
| fall back | no adapter, or a refused definition: the map runs on the CPU and the receipt says which | run time |

The seam stays in Rust and stays small: one call that takes the module, the
entry point and two buffers. blue decides what runs where; Rust only talks
to the device.

## 5. Gates

| Gate | Proves | Red run |
|---|---|---|
| G1 lowering rows | each rung row lowers to WGSL that naga validates | break the emitter (drop a `;`): naga refuses, the row is red |
| G2 refusals | each construct off the rung is refused by name | lower a recursive definition: the refusal names it |
| G3 equality | `map(f, xs)` on the device equals blue's walker over a seeded input, fault word included | flip an operator in the emitter: the device answers differently |
| G4 lever row | the bench row records the ratio to a Rust twin | — |

G1 and G2 prove the build, not the run (a green build gate does not prove a
kernel's answer). G3 is the gate that makes a kernel trustworthy, and it is
the only one that needs a device.

## 6. First step, and why it waits

The first runnable step is G1 and G3 together for one definition:
`def scale(x: Int) -> Int` (`x * 3 + 1`) lowered to WGSL, validated by naga,
dispatched over 1,024 seeded inputs, and compared with the walker. G1 alone
would be a build gate that says nothing about the answer.

It waits on a device in CI. Every runner blue lands through is
`ubuntu-latest` or the runner `land.yml` resolves (measured 2026-11-12,
`.github/workflows/land.yml`, `ci.yml`); none declares a GPU adapter, so G3
would run only on a workstation and stay green on CI by skipping. The fleet
has GPU nodes (`gpu-desktop` in nix `lib/ecosystem.nix`); the step starts
when one of them carries a runner label blue's land can ask for. Until then
G1 and G2 can land behind it, named as build-only.

## 7. Ledger

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| This design | ✅ built | This page. |
| G1: lowering to WGSL, validated by naga | ❌ not built | No emitter; naga is not in `Cargo.lock`. |
| G2: refusals off the rung | ❌ not built | No emitter. |
| G3: equality with the walker on a device | ❌ not built | Waits on a CI runner with a GPU adapter (section 6). |
| G4: the data-parallel bench row | ❌ not built | Waits on G3. |
