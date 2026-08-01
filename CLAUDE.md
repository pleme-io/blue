# blue — Claude Orientation

pending-shikumi: M1 — no configuration surface exists to type yet. The knobs
that will be configurable (posture ceiling, default execution budget,
formatter width) are each blocked on an unsettled design (`theory/BLUE.md`
§V.19, §V.13). Emitting an options schema now would freeze guesses as a
public interface. `flake.nix` carries no `module` for the same reason.

pending-tela: not a frontend. No `pending-urdume:` — blue is a language
workspace, not a Rust service.

> **★★★ CSE / Knowable Construction.** This repo operates under
> **Constructive Substrate Engineering** — canonical spec at
> [`pleme-io/theory/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md`](https://github.com/pleme-io/theory/blob/main/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md).
> **The design is canonical in [`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md)
> — read it before non-trivial changes, and do not restate it here.**

A general-purpose language: a Ruby/Elixir surface, a tatara-lisp AST, macros
as term rewriting on that AST, and a Rust runtime. Crates are `blue-lang-*`
(bare `blue` is squatted on crates.io); source extension is `.b`.

## The pipeline is the architecture

**parse → check → erase → run.** The order is load-bearing and lives in
`blue-lang-runtime::pipeline`, not in each caller, because two of the four
orderings are silently wrong: *erase before check* turns the type checker off,
and *run before check* reports a type error after the side effects. Neither
fails loudly; both produce a green run on a program that should be rejected.

**Ask the pipeline for a result, never assemble the stages yourself.** A
caller that re-implements the order is one reordering away from disabling the
checker.

## Where to look

| Intent | Crate |
|---|---|
| lexer + Pratt parser → `Sexp`; the `INFIX` table | `blue-lang-syntax` |
| the one formatting (Wadler/Oppen) | `blue-lang-fmt` |
| sliding-scale typing; `Seam`; `Stats` | `blue-lang-check` |
| REACH/WHEN/WHERE frame lattice | `blue-lang-waku` |
| package posture floors + resolution | `blue-lang-bidama` |
| processes, supervision, mailboxes | `blue-lang-proc` |
| interpreter construction, erasure, pipeline | `blue-lang-runtime` |
| `blue run/fmt/ast/erase/check` | `blue-lang-cli` |

## Rules this repo has learned the hard way

Each of these is a defect that shipped, not a style preference.

- **`INFIX` is one table, and both directions read it.** Precedence and
  lowering used to live apart, so `==`, `!=`, `&&`, `||` and `%` had a
  precedence and no callee: `a == b` lowered to `(== a b)`, a symbol nothing
  binds, and died at runtime. The formatter kept a third copy labelled "must
  agree with the parser's table", and it did not. **Adding an operator means
  adding one row.**
- **The runtime has two layers and both are required.** `install_primitives`
  is not enough — the Lisp stdlib holds `mod`, `first`, `inc`, and more.
  Three crates each hand-rolled `Interpreter::new()` and all three omitted
  it. **Use `blue_lang_runtime::interpreter`.**
- **A parking primitive must not consume.** `receive` is registered through
  `register_awaitable_fn`, whose readiness phase holds `&System` — so
  take-then-park does not typecheck. Do not move it back to a one-phase
  primitive to "simplify" it; the compile error is the feature.
- **A restart empties the mailbox.** In-flight messages were addressed to the
  incarnation that died. Replaying them is how a poison message kills a
  process forever.
- **Restart intensity is checked on the child that exited**, not on siblings a
  strategy sweeps up. A sibling restarted as collateral has not misbehaved.
- **A formatter law passing is not the formatter being right.** All three laws
  held while every call rendered as a method send — `fact(n - 1)` printed as
  `(n - 1).fact`. A round-trip law measures the tree, never the readability.
  **When you change rendering, read the output.**
- **A corpus is only as strong as what is in it.** The annotated-`def`
  rendering bug survived because the formatter corpus contained no annotated
  defs. Add the case with the rule.

## Testing discipline

Every gate here has a **red run**: the test was shown to fail on a
deliberately broken input before being trusted. Two specific traps this repo
hit:

- **A gate derived from the thing it checks is a tautology.** Compare against
  independent evidence — emitted bytecode, a real interpreter resolving a
  symbol, a counted call — not against the predicate under test.
- **A break attempt that is semantically equivalent proves nothing.** One
  "proof" here stayed green because the mutation could not actually violate
  the property. If the red run does not go red, the mutation is wrong or the
  gate is vacuous; find out which.

## Dependencies

`tatara-lisp` and `tatara-lisp-eval` are **git deps pinned by rev**, not path
deps. A path dep outside the repo cannot resolve in a Nix sandbox, where the
source is just this repository. Co-developing the two means pushing
tatara-lisp first and bumping the rev — which is the trunk-based order anyway.

## What is not built

Stated so nobody cites it as existing: no LSP, no test framework, no package
manager or `Bluefile`, no `blue posture` subcommand (it needs a
package-declaration surface that does not exist), no WASM target, no
per-process heaps, and no self-hosting. `theory/BLUE.md` holds the tier
ledger; **do not build against a DESIGN-tier row without saying so.**
