<!-- Rendered by hon from docs/introduction.md, docs/tutorial/install.md. Edit the sources, then run `nix run .#regen`. -->

# blue

```text
████  blue          nord7 → nord8 → nord9 → nord10
────────────────────    teal   cyan   light  deep blue
a Ruby/Elixir surface on tatara-lisp and Rust
```

**blue** is the pleme-io language. You write it like Ruby or Elixir. It
parses to a [tatara-lisp](https://github.com/pleme-io/tatara-lisp) tree,
macros rewrite that tree, and a Rust runtime runs it, not the BEAM. Each
thing has one spelling, and the formatter writes it. Rigor is your choice:
declare nothing and a program is dynamic and fast; annotate one function and
that function is checked. The standard library is a set of packages called
bidamas, and one `Bluefile` says how a project is built, tested, rendered and
shipped.

The philosophy is two axes
([`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md) §0).
**Form has no choices:** there is one short, distinct way to write each
thing, every larger form is built from smaller ones, and every tool and gate
enforces it. **Rigor has every choice:** a program is as strict as you write
it, where you write it, and pays for nothing else.

## Quickstart

You need [Nix](https://nixos.org) with flakes turned on. Install blue into
your profile:

```console host
$ nix profile install github:pleme-io/blue
```

To try blue without installing it, put `nix run github:pleme-io/blue --` in
front of each command below.

Ask blue for a value:

```console
$ blue eval '1 + 2'
3
```

Write a file called `hello.b`:

```blue file=hello.b
write_stdout(unlines(["Olá, mundo!"]))
```

Run it:

```console
$ blue hello.b
Olá, mundo!
```

That is a whole blue program. The next tutorial, [a first script](docs/tutorial/first-script.md),
gives it arguments.

## The blueshift

The blueshift is how far a program has moved from dynamic toward checked.
You move it one definition at a time. Here `add` has no annotation, so
nothing analyses it. `fact` is annotated, so the checker proves it:

```blue file=shift.b
def add(a, b)
  a + b
end

def fact(n: Int) -> Int
  if n < 2
    1
  else
    n * fact(n - 1)
  end
end
```

`blue check` prints what the check cost, so the claim is a measurement:

```console
$ blue check shift.b
typed declarations: 1
nodes analysed:     11
seams:              0
names resolved:     11
waived:             0
```

`blue shift` names the rung the file stands on and what holds it back:

```console
$ blue shift shift.b
██░░ annotated  (1/2 typed, 11 nodes analysed)
some declarations are typed; untyped ones are unchecked

  · untyped declaration      `add` has no annotation — annotate it to shift further
  → type annotation          `fact` is annotated, so it is checked
```

The mark is a blueshift too: four solid cells walk Nord's Frost band toward
blue. A blueshift is a shift in colour, so the mark shifts colour. It names
each colour by ANSI slot, never by hex, so it renders in your Nord and
follows you when you retheme.

## Commands

| Command | |
|---|---|
| `blue FILE ARGS` | run a program as a script: quiet, every argument after the file reaches `argv` |
| `blue run FILE` | parse, check, erase and run, then print the final value |
| `blue test FILE` | check the file, then run its `test` blocks and its doctests |
| `blue fmt FILE [--check\|--write]` | the one formatting |
| `blue check FILE` | every rule, and what the type checker did |
| `blue shift FILE` | the blueshift: how far the file is checked, and what holds it back |
| `blue doc NAME` | what a name is: signature, doc line, tier and an example |
| `blue new NAME` | a project; `--bidama NAME` a package; `--script NAME.b` a script |
| `blue ast FILE` / `blue erase FILE` | the tree with and without annotations |
| `blue lock DIR` | evaluate a `Bluefile` into `Bluefile.lock` |
| `blue reference` | the language reference, as JSON |
| `blue lsp` | the language server over stdio |
| `blue repl` / `blue eval EXPR` | an evaluation session at the terminal, or one expression |
| `blue banner` | the wordmark |

## What is here

Macros with **bounded expansion**: a runaway macro is a typed error that
names the macro, not a dead compiler. OTP-style **supervision** with private
per-process environments and copy-on-send. A **test framework** whose
failures print the expression as blue source, and **doctests** in every
`@doc`. A **package manager** whose manifest is itself a blue program. A
**WASM** target that runs the whole language with zero host imports.

## What is not

blue states its gaps plainly, because a language's honest gaps matter more
than its claims:

- **No per-process GC heap.** Processes have private environments and
  messages are deep-copied, but reclamation is `Arc` refcounting. There is no
  independent per-process collection pause.
- **Not self-hosted.** The toolchain is Rust. `spec/*.b` is blue specifying
  blue, which is the specification axis only.
- **Nothing fetches.** Dependency resolution is real; there is no registry
  client.
- **The formatter refuses a comment it cannot place.** It keeps comments
  before and after a top-level form. It refuses a comment inside an
  expression rather than drop it.

The full tier ledger, every row marked SHIPPED or ABSENT, is
[`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md) §V.26.

## Theming

Colours come from [irodori](https://github.com/pleme-io/irodori), the fleet's
Nord palette. blue carries no hex of its own. `nord10` (`#5E81AC`, deep frost
blue) is its identity, and `nord8` frost cyan stays the fleet's shared
interaction colour: identity and interaction are different roles.

## Building blue

```console host
$ nix build .#blue
$ nix flake check
$ cargo test --workspace
```

`nix build` is hermetic. `nix flake check` runs every gate the root
`Bluefile` declares. Changing blue itself starts at [AGENTS.md](AGENTS.md).

MIT.

## The book

Read it in order as [The blue Book](docs/BOOK.md), or open one page:

### Tutorials

- [Install blue](docs/tutorial/install.md): install blue, evaluate one expression and run a first file, in about a minute
- [A first script](docs/tutorial/first-script.md): write a script that reads its arguments, and let blue start one for you
- [A first program](docs/tutorial/first-program.md): start a program with blue new, change its code, and test it
- [A first bidama](docs/tutorial/first-bidama.md): write a documented bidama with doctests, read its docs with blue doc, and use it from a program
- [A first service](docs/tutorial/first-service.md): declare a service in a Bluefile, write its handler and tests, and see what blue renders from it

### How-to guides

- [Write a test and a doctest](docs/howto/test-and-doctest.md): write a test block and a doctest, read a failure, and run one test by name
- [Climb the blueshift](docs/howto/climb-the-blueshift.md): move a file from dynamic to checked one annotation at a time, reading blue shift at each step
- [Declare what a program may touch](docs/howto/declare-access.md): hold a program to the host capabilities it needs with --allow, in a run or in a script's shebang
- [Write an action](docs/howto/write-an-action.md): write a GitHub Actions step in blue with koutei, and run it locally before CI does
- [Publish a bidama](docs/howto/publish-a-bidama.md): make a bidama reachable from other projects, and declare the registries that publish it

### Reference

- [Canonical forms](docs/CANONICAL-FORMS.md): every place the surface accepts two spellings, the one blue writes, and the rule that names it
- [Diagnostics](docs/DIAGNOSTICS.md): what the check stage reports, every rule code, and the machine-readable shape of a diagnostic
- [blue examples](docs/EXAMPLES.md): one tested program per common task, ready to paste as examples
- [blue language reference](docs/REFERENCE.md): syntax, operators, reserved words, every built-in name and the Bluefile words
- [Safety first: blue's posture, row by row](docs/SAFETY.md): the safety-first posture, one row per Rust guarantee: blue today, the gate, its tier and its off switch
- [blue — the agent guide](AGENTS.md): rules for people and agents who write blue programs or change blue itself, with the build commands from the Bluefile

### Explanation

- [ABSENCE — no undeclared nil](docs/ABSENCE.md): no undeclared nil: how blue makes absence a declared, checked state
- [API-EVOLUTION — the API is a versioned rendering of the one model](docs/API-EVOLUTION.md): the API as a versioned rendering of one model (design)
- [BIDAMA-COHESION — one word per job, foundations below, a complete vocabulary](docs/BIDAMA-COHESION.md): one word per job, foundations below, a complete vocabulary across the bidamas (plan)
- [BUILD-ASSURANCE — what a blue build proves, how fast, and from which cache](docs/BUILD-ASSURANCE.md): what a blue build proves, how fast, and from which cache (design)
- [BUILD-STACK — the default platform for a blue service, from Bluefile to a running node](docs/BUILD-STACK.md): the default platform for a blue service, from Bluefile to a running node (design)
- [`Cargo.gen.lock` is committed, and that is a trade](docs/CARGO-GEN-LOCK.md): why Cargo.gen.lock is committed, and what that trade costs
- [CLI-TUI — one way to build a command line and a terminal interface in blue](docs/CLI-TUI.md): one way to build a command line and a terminal interface in blue (design, layer 1 built)
- [Competing languages — what blue takes, and what it refuses](docs/COMPETING-LANGUAGES.md): what blue takes from competing languages on packaging and the standard library, and what it refuses
- [Compile time: Rust's static guarantees and Lua's runtime, in blue](docs/COMPILE-TIME.md): Rust's static guarantees and Lua's runtime, brought into blue
- [Compounding: every evolution break fixes itself](docs/COMPOUNDING.md): every break blue's evolution causes ships its own fixer
- [CST plan: a lossless tree, resilient parsing, surface blame](docs/CST-PLAN.md): the design for a lossless CST with resilient parsing and surface blame; nothing is built yet
- [DOCUMENTATION — every blue project documents itself, and the language has a book](docs/DOCUMENTATION.md): documentation as a battery: one source per fact, a Diátaxis book, rendered README, AGENTS.md and llms.txt (design)
- [FRONTEND-PLAN — building the blue frontend framework](docs/FRONTEND-PLAN.md): the build plan for blue's frontend framework
- [HTTP2 — blue speaks HTTP/2 and gRPC itself](docs/HTTP2.md): blue speaks HTTP/2 and gRPC itself (design, phase 1 built)
- [Lessons behind the agent guide's rules](docs/LESSONS.md): the full story behind each rule the agent page states in short
- [Namespaces: a bidama definition stays in its bidama](docs/NAMESPACES.md): a bidama definition stays in its bidama: the rule as built and its gates
- [naturalize(tree-sitter) — the destination, before the build](docs/NATURALIZE-TREESITTER.md): tree-sitter naturalized: the grammar spec and what is emitted from it
- [OPERATORS — short notation for what blue says most, keyed to the blueshift](docs/OPERATORS.md): short notation for what blue says most, keyed to the blueshift (design)
- [Performance: blue as a scripting language and as a tool](docs/PERFORMANCE.md): what blue costs today, where the time goes, and the order to remove it
- [Registry](docs/REGISTRY.md): how a blue project is published and resolved: registries as renderings of the Bluefile
- [SERVICE-ACCESS — one access declaration, enforced by every layer that builds a service](docs/SERVICE-ACCESS.md): one access declaration, enforced by every layer that builds a service (design)
- [SERVICE-ARCHITECTURE — the default blue service](docs/SERVICE-ARCHITECTURE.md): the default blue service and the batteries it composes (design)
- [SERVICE-DATA — Postgres, Valkey and the nervous system as defaults](docs/SERVICE-DATA.md): Postgres, Valkey and the nervous system as the configurable defaults of a blue service (design)
- [STDLIB: blue's batteries, as one verb vocabulary](docs/STDLIB.md): the standard library's design as one verb vocabulary (design)
- [Testing and the SDLC: one blue pipeline](docs/TESTING.md): every kind of test and its one place beside what it tests, and the Bluefile as the one pipeline
- [Blue verb roadmap: full software verbalization](docs/VERB-ROADMAP.md): the roadmap to full software verbalization
- [vocabularify — the surface/structure vocabulary](docs/VOCABULARIFY-SURFACE.md): kigou and yakugo: a program's spelling separated from its meaning
- [WORKSPACES — one root, many bidamas and many crates](docs/WORKSPACES.md): one root holding many bidamas and many crates (design)
- [Region A: data and knowledge (578 verbs, 30 spaces, 875 edges)](docs/verbs/A/REGION.md): verb graph region A: data and knowledge
- [Region B: storage and state (2026-10-22)](docs/verbs/B/REGION.md): verb graph region B: storage and state
- [Blue verb graph: shared brief (read fully first)](docs/verbs/BRIEF.md): the shared brief behind the verb graph
- [Region C: communication and distributed systems](docs/verbs/C/REGION.md): verb graph region C: communication and distributed systems
- [Region D: security and trust (2026-10-22)](docs/verbs/D/REGION.md): verb graph region D: security and trust
- [Region E: build, ship and run (346 verbs, 567 edges, 29 spaces)](docs/verbs/E/REGION.md): verb graph region E: build, ship and run
- [Region F: OBSERVE, TEST, QUALITY AND THE ENGINEERING PROCESS](docs/verbs/F/REGION.md): verb graph region F: observe, test, quality and process
- [Region G: interfaces, intelligence and the physical world](docs/verbs/G/REGION.md): verb graph region G: interfaces, intelligence and the physical world
- [H: the verb GRAPH as data blue owns (META region)](docs/verbs/H/DESIGN.md): the verb graph as data blue owns
- [Merged graph: repairs and decisions (H0a)](docs/verbs/merged/CHANGES.md): the merged verb graph: repairs and decisions
- [Naming sweep: what is applied and what the operator decided](docs/verbs/names/RULINGS.md): the naming sweep of the verb graph's spaces, and the rulings
