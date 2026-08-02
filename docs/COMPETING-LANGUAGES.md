# Competing languages — what blue takes, and what it refuses

**Scope and honesty note.** This reviews the languages blue is actually
competing with *on packaging and standard library*, because that is the axis
this document was commissioned on. It is written from published, checkable
behaviour of each ecosystem — not from benchmarks run here — so treat every row
as "documented design", and verify before betting on a number.

Blue's position is unusual and worth stating before the table: it is a
**Ruby/Elixir surface on a tatara-lisp AST with a Rust runtime**, inside a fleet
where every artifact is already content-addressed and git-hosted. That last
clause changes which trade-offs are available, and it is why the answers below
diverge from what a general-purpose language would choose.

---

## 1. Packaging — the axis blue is deciding now

| Language | Source of truth | Resolution | What blue takes / refuses |
|---|---|---|---|
| **Rust / Cargo** | crates.io index + `Cargo.toml` | SemVer, MVS-adjacent, lockfile | **Take:** the lockfile discipline and *floors-not-ceilings* (Cargo names leaf-side ceilings an anti-pattern by name — blue's §V.24 already adopted this). **Refuse:** a central registry as the only path. |
| **Go modules** | **VCS directly** — no registry service | MVS (minimal version selection), `go.sum` | **Take: the whole shape.** Go proved a language can resolve straight from git with no package server. blue's `GitRegistry` is this. **Take also:** MVS's determinism-without-a-solver argument is worth reading before blue's solver grows. |
| **Nix / flakes** | git revisions, content-addressed | exact pins, `flake.lock` | **Take:** revision pinning + a lock that is a *hash*, not a version range. This is the honest ceiling blue's git registry has not reached yet. |
| **Elixir / Hex** | hex.pm + `mix.exs` | SemVer solver | **Take:** the manifest-is-code idea (`mix.exs` is Elixir). blue already goes further — a `Bluefile` is blue, evaluated. |
| **Unison** | content-addressed codebase, names as metadata | by hash, no version conflicts | **Study, do not copy.** Unison *publicly retracted* its first codebase model as lacking "practical ergonomics". The idea is right; a decade of tooling rebuild (diff, review, search, IDE) is the price. |
| **Deno** | URL imports | none — the URL is the version | **Refuse.** Deno itself walked this back (`deno.json`, JSR) after unpinned URLs proved unauditable. |
| **npm** | registry + `package.json` | SemVer, nested resolution | **Refuse the shape.** Nested duplicate resolution is why `node_modules` is a punchline. Instructive as a counterexample. |

**The decision this review supports:** blue's default is **git-based**, because
the fleet is already git-and-content-addressed and a registry service would be a
second source of truth to keep in sync with the repository. **Nix is the
delivery mechanism, not a second package manager** — a bidama distribution is a
directory in a repo; a flake pins the *revision* of that repo. Those compose:
git answers "what does this package need", nix answers "exactly which bytes".

**Stated ceiling:** blue's `GitRegistry` today resolves from a *working tree*.
It does not fetch and does not pin revisions, so the Nix-flake half of the
answer is what supplies pinning until a worktree-per-tag or git-object reader
lands. Do not describe blue as "fully git-based" while that is true.

---

## 2. Standard library — scope, and the one thing that decides it

| Language | Stdlib posture | Consequence |
|---|---|---|
| **Go** | large, batteries included, frozen by compat promise | you rarely need a dependency; you also cannot fix the stdlib |
| **Rust** | deliberately small; `std` is a floor, crates.io the rest | fast core evolution, dependency sprawl downstream |
| **Python** | very large, aging in visible layers | `urllib` vs `requests` — the stdlib becomes the *deprecated* option |
| **Elixir** | small core + OTP, which is enormous and coherent | the best argument for "one big coherent subsystem beats fifty small ones" |
| **Ruby** | mid-size, extremely ergonomic, blocks everywhere | the surface blue copied — and the reason §3 below matters |
| **Clojure** | tiny core, sequence abstraction does the work | one abstraction (`seq`) replaces dozens of container APIs |

**What blue should take:** Rust's *small floor* plus Clojure's *one abstraction
carries the library*. A bidama distribution then grows the rest without
freezing anything into the language — which is exactly what the `bidamas/`
directory is for, and why the stdlib grows **in blue** rather than in Rust.

**What blue should refuse:** Python's shape. A stdlib large enough to age is a
stdlib that becomes the deprecated option while the ecosystem routes around it.

---

## 3. The blocker this review named — and the correction

**The original claim here was wrong, and it is left visible rather than
quietly rewritten, because the mistake is instructive.**

This section first argued that blue could not have a real standard library
because it lacked a closure form, citing one measurement:

```
[1, 2, 3].map { |x| x * 2 }
  -> Parse error: expected an expression, found Op("|")
```

That measurement is real. The conclusion drawn from it was not. Blue has
lambdas — `fn(x) … end` — and the higher-order functions were already there:

```
map(fn(x) x * 2 end, [1,2,3])            => [2, 4, 6]
filter(fn(x) x > 2 end, [1,2,3,4])       => [3, 4]
reduce(fn(a, b) a + b end, 0, [1,2,3,4]) => 10
```

What failed was Ruby's **brace-block** sugar and a method-position call. One
syntax was tested, and a missing capability was inferred from it. The cost of
that error was a deferred standard library and a recommendation not to build
one — an expensive conclusion from a single unchecked assumption.

**The real gap, found by writing the library**, was that blue had no *import*
form at all: a package could not see another package. That is now `use("name")`,
resolving through `BLUE_PATH`, which a nix store path satisfies directly.

Brace blocks and `xs.map { … }` remain genuinely absent, and are worth adding
for ergonomics. They were never what stood between blue and a standard library.

## 4. Exotic domains — where blue could be genuinely different

Deferred until §3 lands, but worth recording now so the direction is chosen
rather than defaulted. Blue's actual differentiators are not "a faster map":

- **Manifest-is-blue.** A `Bluefile` is evaluated blue, so a dependency set can
  be *computed*. Nothing in the table above can do this without a second
  language (Nix comes closest, and pays for it with a second language).
- **The tatara-lisp AST.** Any consumer that speaks the AST speaks blue for one
  parser call — which is how blue became a shikumi config format in ~20 lines.
  A bidama that emits typed config for *other* pleme-io tools is a domain no
  general-purpose language is positioned to serve.
- **Content-addressed everything.** The fleet already hashes artifacts. A
  distribution where a package *is* its hash makes Unison's idea available
  without Unison's tooling debt, because the surrounding infrastructure exists.

---

## What this review changed

1. **Git-based is the right default** — Go proves the shape works; the fleet's
   content-addressing makes it natural rather than contrarian.
2. **Nix is the pinning layer, not a competing package manager.** They compose.
3. **The distribution was NOT blocked on block syntax** — that was this
   review's own error, corrected in §3. It was blocked on the absence of an
   import form, which no amount of syntax would have fixed.
