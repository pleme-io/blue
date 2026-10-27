---
kind: explanation
role: introduction
runs: true
summary: blue is a general-purpose language with a Ruby/Elixir surface that parses to a tatara-lisp tree and runs on a Rust runtime. It has one formatting, rigor where you write it, and most of its vocabulary in packages called bidamas.
---

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
`Bluefile` declares. Changing blue itself starts at [AGENTS.md](../AGENTS.md).

MIT.
