# BUILD-ASSURANCE — what a blue build proves, how fast, and from which cache

Status: DESIGN, 2026-10-27. Nothing here is built unless the tier ledger (§9)
says so. Ground measured 2026-10-27; paths are under `~/code/github/pleme-io/`.

## 1. Destination

Every blue project builds blue-only and fast, and every build proves a known
set of things. A project compiles no Rust: the `blue` toolchain arrives from a
cache, never from a local `cargo` run. Every project gets a **default set of
assurances** with no configuration. Above that floor, the **blueshift** is the
sliding scale: a project declares the rung its files must reach, and the build
fails below it. Each rung adds a build-time guarantee, and the same typing that
gives the guarantee also makes rebuilds smaller, because a typed interface lets
the build stop early when a change does not reach it. Every blue build reads
the local store and the fleet's caches first, then public caches, and pushes
what it built, with no per-repo opt-in. Build time is itself measured and gated,
like any other assurance.

## 2. Ground

| Fact | Where | State |
|---|---|---|
| Blueshift rungs: `dynamic`, `annotated`, `checked`, `restricted`; a file's rung is its lowest declaration's | `theory/BLUE.md:391`, `:3457`; `enum Rung` `blue/crates/blue-lang-lsp/src/shift.rs:45`; `blue shift FILE` | typed and reported; **not a Bluefile word, not a build gate** |
| `mkBidama` runs `blue check` (meaning only) per `.b`; a failing file does not build | `blue/bidamas/mk-bidama.nix:150-158` | exists |
| Checks: `bidama-form-*`, `bidama-test-*` (no tests is a refusal), `bidama-collisions`, `bidama-locks-fresh`, `bidama-deps-resolve`, `repository-lock-fresh`, `generated-*-fresh`, `bidama-catalog-fresh`, `project-rules-hold`, `service-*-{fresh,chart,serves,migrations}`, `-trio`, `image-*-distroless` | `blue/nix/project.nix:39-57`, `:450-530`; `blue/nix/service.nix:203` | exist; all run by `checks.project` |
| No default assurance set; `posture(when:)` lowers to nothing | `blue/nix/project.nix:57` | gap |
| One derivation per bidama; each program file is its own store path | `mk-bidama.nix:188`; `project.nix:66-70`, `:186` | exists; the check is per bidama, not per file, and has no early cutoff |
| A project compiles no Rust of its own; `blue` is `base.packages.default` (270 crates) and builds from source when not substituted | `blue/flake.nix:376`; `blue/Cargo.lock` | exists; a cold machine builds 270 crates |
| No blue, substrate or kensa flake has `nixConfig` | `rg nixConfig` | gap |
| Fleet cache `sui`: `rio` (x86_64-linux, `:5000`), `cid` (aarch64-darwin, `:5001`) | `nix/lib/sui-cache.nix:132` | exists; each node's pull is `enable = false` by default (`nix/modules/pleme/darwin/binary-caches.nix:38`); the builder node reads cache.nixos.org only (`nix/nodes/builder/default.nix:81`) |
| Push: a post-build hook on darwin; CI `cache-push` defaults to `false` | `nix/modules/pleme/darwin/post-build-hook.nix:96`; `substrate/.github/workflows/nix-fleet.yml:68` | exists, off by default |
| Build times | `rg -i 'build time\|s CPU\|wall.clock'` over `blue/docs`, `theory/BLUE*` | never measured |
| kensa: 5 Rust workspace members, 624 crates in `Cargo.lock`, 208 `.rs` against 2 `.b` | `kensa/flake.nix:13,23` | not blue-only; a `host` service (FUEKI H1) |
| Measured plan, `kensa#packages.aarch64-darwin.default` on ryn, 2026-10-27 (`pleme-io/actions` `blue-build-plan`) | 545 derivations to build, 56 paths fetched, 445 of the builds Rust | the cache served 9% of the plan |
| A dead substituter costs seconds per lookup: ryn's nix lists the `cid` sui origin, offline 9 h (tailscale status, ICMP, TCP: three probes); each narinfo lookup waits a 5 s connect timeout and retries | `nix build --dry-run` on ryn, 2026-10-27 | a fast negative is not configured: no `connect-timeout`, no health-gated substituter list |

## 2a. Why typing is build speed

A file at `dynamic` has no interface: any change to it can change what its
importers mean, so every importer is checked again. From `annotated` up, a
typed declaration has a signature. The build can hash the **interface** of a
file (its exported names and their types) apart from its **body**. Importers
depend on the interface hash only. A body edit that leaves the interface alone
re-checks one file and stops: early cutoff, the way OCaml's `.cmi` and GHC's
interface hashes work. At `checked`, every export has an interface, so cutoff
holds for the whole file. At `restricted`, a macro reads only declared,
content-addressed inputs, so macro expansion becomes its own derivation, keyed
by those inputs, and is cached across projects and machines. So each rung up
the blueshift is both a stronger proof and a smaller rebuild. The scale is not
assurance traded against speed; both rise together.

## 3. The default assurance set (every blue project, no configuration)

| Assurance | Gate | When it fails |
|---|---|---|
| parses and is canonical | `blue fmt --check` | build |
| means one thing | check stage, every B-code at its level | build |
| is tested | `blue test`; a file with no test is refused | `nix flake check` |
| docs are typed and run | `@doc`/`@moduledoc` doctests | `nix flake check` |
| renderings are fresh | every `-fresh` check | `nix flake check` |
| access is declared and judged (services) | `SERVICE-ACCESS.md` A1 | eval |
| reaches its kind's default rung (§4) | `blue shift` per file | build |
| blue-only | no Rust derivation in the build plan beyond the pinned toolchain (§5) | `nix flake check` |
| inside its build-time budget (§6) | measured, ratcheted | `nix flake check` |

## 4. The blueshift as a declared floor

A new Bluefile word, `shift(rung)`, sets the lowest rung every `.b` in the
project must reach; `shift(rung, {files: [...]})` raises it for named files.
The default floor depends on what the project builds:

| Project builds | Default floor | Why |
|---|---|---|
| a `service` | `checked` | it runs for other people; every export typed, cutoff everywhere |
| a bidama others import | `annotated`, exports `checked` | importers depend on its interface |
| a program or script | `dynamic` | one file, nothing imports it |
| macros reading inputs | `restricted` for those files | expansion is cached only when its inputs are declared |

A project may declare a lower floor than its kind's default only as a recorded
waiver, `shift(:annotated, {waive: "<typed reason>"})`, which the build prints
and the catalog lists: behaviour configured off, never deleted. `mkBidama`
runs `blue shift` on each file and fails with the file, its rung and its lowest
declaration when the file sits below the floor.

## 5. Blue-only and the toolchain

A blue project's derivations may depend on the pinned `blue` toolchain, its
bidamas and nixpkgs, and nothing else that compiles Rust. `checks.blue-only`
reads the project's build plan (`nix path-info --derivation` over
`checks.project`) and fails when a derivation runs `cargo` or `rustc` outside
the toolchain pin. A `host` service (kensa today) is the one typed exception:
its Bluefile says `host:`, the check names the host build and its crate count,
and FUEKI H1's destination (the host form configured off) is the way out.

The toolchain is never built on a developer machine or a CI runner: it is
pushed once per blue revision by blue's own CI and substituted everywhere else.
A cold machine that would build `blue` from source fails `checks.blue-only`
with "the toolchain for <rev> is not in any configured cache", which is a cache
fault to fix, not a reason to compile 270 crates.

## 6. Build time as an assurance

| Measure | Budget (start) | Recorded by |
|---|---|---|
| no-op `nix flake check` on a clean tree | eval only, < 5 s | `checks.build-time` (wall clock from `nix build --dry-run` and a timed eval) |
| one-file body edit, interface unchanged | re-checks one file | the derivation count in the build plan, which is exact |
| cold build of a service with every cache warm | no local compile; substitution only | the same plan: zero derivations to build |

Derivation counts are the gate, because they are exact; wall clock is
recorded beside them and ratcheted like the namespace census, never as the
pass/fail line, because it varies by machine.

## 7. Caches by default

| Side | Default | Configured off by |
|---|---|---|
| Pull, local | the machine's own store, then the fleet `sui` origins on the tailnet for the build's system | `pleme.binaryCaches.<name>.enable = false` |
| Pull, foreign | cache.nixos.org, then the published public pleme cache when one exists | the same registry |
| Pull, in the flake | `blue.lib.project` renders `nixConfig.extra-substituters` and `extra-trusted-public-keys` into every blue project's generated `flake.nix` (a blue project writes no nix, so the renderer carries it) | a Bluefile `cache(...)` entry turned off |
| Push, developer | the post-build hook pushes blue toolchain and bidama outputs to the node's own `sui` | the hook's `enable` |
| Push, CI | `nix-fleet.yml` pushes every built output for a repo whose root has a Bluefile | `cache-push: false` in that repo's workflow call |

A substituter that does not answer must cost milliseconds, not seconds. The
global `connect-timeout` stays at 15 s: flake tarball fetches have no
fallback, and a 2 s value once failed whole rebuilds
(`nix/modules/shared/nix-performance.nix:307`). So the fix is the list, not the
timeout: only an always-on node is a fleet origin. cid, a laptop that is
online only sometimes, was configured off as an origin on 2026-10-27 (§2);
rio (x86_64-linux) is the build node and origin, plo the dev host.

Two changes in the nix repo turn the fleet on: the `sui` pull entries default
to enabled for the node's own system, and the builder node gains the fleet
caches beside cache.nixos.org. Both are `enable` flips on entries that exist.

## 8. Decisions

| Question | Chosen | Rejected, and why |
|---|---|---|
| Unit of rebuild | the file, cut off on its interface hash | **the bidama** (today): one edit re-checks every file in it and every importer |
| Where the floor lives | the Bluefile (`shift`) | **CI config**: a second place to drift from the source |
| Default floor for services | `checked` | **`dynamic` everywhere, opt in**: the bad state is the default and nobody opts in |
| Gate on wall clock | no; gate on derivation counts, record wall clock | **wall-clock budgets**: flaky by machine, so they get waived |
| Toolchain on a cold machine | substitute or fail with a cache fault | **build from source silently**: 270 crates hide behind a green build |
| Cache config per repo | rendered by `blue.lib.project` | **hand-written `nixConfig` per repo**: one copy per repo, drifting |

## 9. Build order and tier

| Step | Work | Gate | Tier |
|---|---|---|---|
| B0 | measure: derivation counts and wall clock for blue's examples, ola-mundo and kensa, cold and warm | numbers recorded here | kensa measured (§2); the rest design |
| A | the actions: `blue-setup`, `blue-check`, `blue-test`, `blue-shift`, `blue-build-plan` (`pleme-io/actions`, logic in `run.b` on the `koutei` bidama) and the reusable `substrate/.github/workflows/blue-project.yml` | each run locally against kensa and a broken fixture | built 2026-10-27 |
| B1 | caches: `sui` pull on by default per system; builder node gains fleet caches; CI push on for Bluefile repos | a fresh runner builds ola-mundo with zero local Rust | design |
| B2 | `nixConfig` rendered by `blue.lib.project` | a new blue project's flake carries the substituters | design |
| B3 | `shift(rung)` word and the per-file gate in `mkBidama`; kind defaults | a service file at `annotated` fails the build | design |
| B4 | `checks.blue-only` | kensa reports its host build; ola-mundo passes | design |
| B5 | per-file check derivations with interface hashes | a body edit re-checks one derivation (counted) | design |
| B6 | `restricted` macro expansion as content-addressed derivations | a second project reusing a macro input substitutes its expansion | design |
| B7 | `checks.build-time` with ratchets | a regression in derivation count fails | design |
