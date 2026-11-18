# Pure blue — track D: the build surface

**Tier: DESIGN (2026-11-17).** Plan: [`../PURE-BLUE.md`](../PURE-BLUE.md).

**The rule (operator, 2026-11-17):** every way blue can be built is a selectable configuration
with a full module-trio surface. Choosing how a project, a node or a run builds blue (Rust
fallback, pure native, which seed, which memory model) is one field, and every reusable builder
lives in `pleme-io/substrate`.

## Today (measured 2026-11-17)

- The builders live in the blue repo: `mkBlueApp`, `mkBluePath`, `mkBlueWithBidamas`
  (`bidamas/mk-bidama.nix:492`), and the Bluefile → flake renderer (`nix/project.nix`: `app`,
  `generate`, appliances, images). `bidamasOverlay` (`flake.nix:567`) builds wrapped programs
  from `blueFor system`, not from `final.blue`.
- substrate holds two small blue helpers: `lib/build/scripting/blue-program-package.nix`,
  `lib/blue-service-helpers.nix`.
- A consuming fleet takes one binary through one overlay line
  (`blue = inputs.blue.packages.${system}.blue`).
- Per run, `BLUE_DOOR` picks the walker, the VM or `auto` (`crates/blue-lang-cli/src/door.rs`).
- Nothing selects a toolchain per project or per node.

## The destination

1. **One builder family in substrate**, `substrate/lib/build/blue/`, beside `rust/`, `go/`,
   `ruby/`. It takes the toolchain as an argument, the way the Rust builders take a Rust
   toolchain, so substrate never depends on the blue repo. The blue repo and every blue project
   consume it.
2. **One registry concept, `blue.toolchain`** (`mkModuleTrio`, `kind = "registry"`). Its
   entries are the named permutations; its selector picks one; everything else derives.
3. **Three places select, one surface:** a project in its Bluefile, a node in its config, a run
   with `BLUE_DOOR`. The narrower one wins: run over project over node.
4. **Every permutation is proven.** A matrix check builds and runs conformance for every
   buildable entry; a new entry without its row fails the build.

## The axes

| Axis | Values | Today |
|---|---|---|
| `runtime` | `rust` (tatara walker/VM), `native` (blue-compiled machine code) | `rust` |
| `door` (rust runtime only) | `auto`, `walker`, `vm` | `auto` |
| `front` | `rust` (blue-lang-syntax/check/fmt), `blue` (F1-F4) | `rust` |
| `backend` (native only) | `rustc` (chuuzou → Rust → rustc), `x64` (B1-B4) | `rustc` for chuuzou's subset |
| `seed` (native only) | `stage0` (built by the Rust blue), `binary` (S2), `full-source` (S4) | `stage0` |
| `memory` | `counted` (today's `Arc` counts, tail-position reuse), `inferred` (M3: last-use frees, cells), `inferred-local` (M5: non-atomic counts) | `counted` |

## The registry

```nix
toolchain = trio.mkModuleTrio {
  kind = "registry";
  namespace = "pleme";
  name = "blueToolchain";
  description = "how blue is built and run: runtime, front end, backend, seed, memory";
  entries = {
    rust        = { runtime = "rust";   door = "auto"; front = "rust"; memory = "counted"; };
    rust-owned  = { runtime = "rust";   door = "auto"; front = "rust"; memory = "inferred"; };   # M3
    native-rustc= { runtime = "native"; front = "rust"; backend = "rustc"; seed = "stage0"; memory = "inferred"; };
    pure        = { runtime = "native"; front = "blue"; backend = "x64";   seed = "binary"; memory = "inferred-local"; }; # S2
    pure-source = { runtime = "native"; front = "blue"; backend = "x64";   seed = "full-source"; memory = "inferred-local"; }; # S4
  };
  selector.default = "rust";
  projections = {
    package = …;        # the blue derivation for the selected entry (readOnly)
    door = …;           # BLUE_DOOR default for the rust runtime
    builders = …;       # substrate's builder family bound to this toolchain
  };
  render.nixos = ./render/nixos.nix;          # overlay: pkgs.blue = projections.package
  render.darwin = ./render/darwin.nix;        # same; native entries refuse until S5
  render.homeManager = ./render/hm.nix;       # the user's blue on PATH, BLUE_DOOR
};
```

- **Refusal is per entry, never per document.** An entry that cannot be built yet is refused
  by name with the rung that unblocks it (`unimplemented: needs M3`), and its siblings
  proceed. On darwin the native entries refuse `unimplemented: needs S5` until the Mach-O
  path exists. A combination that can never work (`backend` with `runtime = rust`,
  `seed = full-source` off Linux) is unrepresentable in the entry type.
- **Nothing is deleted.** A retired permutation stays as an entry, configured off.
- **Constraint table** (typed, checked at eval): `door` only with `rust`; `backend` and `seed`
  only with `native`; `seed = binary|full-source` only with `backend = x64`;
  `memory = inferred-local` only after M5 on the rust runtime.

## The three selection points

| Where | How | Example |
|---|---|---|
| Node | `pleme.blueToolchain.selected` in the node's layer | the x86-64 builder runs `pure`, every other node `rust` |
| Project | `toolchain("pure")` in the Bluefile; `nix/project.nix` passes it to substrate's builders | a service built and shipped pure |
| Run | `BLUE_DOOR` (`walker`, `vm`, `auto`, `native`, `rust`) | an A/B run on one machine |

A project that names a toolchain builds with it whatever the node runs; a node's selection is
the default for projects that name none.

## Rungs

Dependencies are in the plan's §7.

| # | Rung | Exit check |
|---|---|---|
| D0 | **Lift the builders into substrate**: `mkBluePath`, `mkBlueWithBidamas`, `mkBlueApp`, the Bluefile renderer and `generate` into `substrate/lib/build/blue/`, taking the toolchain as an argument; the blue repo re-exports them | every blue project's and every fleet node's drvPaths identical before and after |
| D1 | **`bidamasOverlay` reads `final.blue`**, so an overridden toolchain reaches every wrapped program | a check: `blueApp` over an overridden `blue` points at the override |
| D2 | **The registry** `blue.toolchain` in substrate (kind `registry`), with entry `rust` rendering and the rest refused by rung | kijun `trio/every-concept`; substrate's kinds test gains the concept |
| D3 | **Bluefile `toolchain(...)`**: a project selects its entry | a project built with each buildable entry; the Bluefile rejects an unknown name |
| D4 | **Fleet selection**: the fleet imports the concept's `.module`; nodes select; the fleet's one-line blue overlay becomes the `rust` projection | identical drvPaths for every node with `rust` selected |
| D5 | **The matrix**: every buildable entry builds `blue` and runs conformance; an entry without a matrix row fails | `checks.toolchain-matrix` (I11) |
| D6 | **Entries come alive as their rungs land**: `rust-owned` at M3, `native-rustc` widened at B1, `pure` at S2, `pure-source` at S4, darwin native at S5; each is a refusal turned into a render | the matrix grows a row per entry |

D0-D2 can start now: they need nothing from the compiler work, and they make every later rung
a one-field switch.
