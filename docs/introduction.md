---
kind: explanation
role: introduction
runs: true
summary: blue is a general-purpose language with a Ruby/Elixir surface that parses to a tatara-lisp tree and runs on a Rust runtime. It has one formatting, rigor where you write it, safety first, and most of its vocabulary in packages called bidamas.
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
that function is checked. Safety is not a choice: a program reaches the host
only through the capabilities it is given. The standard library is a set of
packages called bidamas, and one `Bluefile` says how a project is built,
tested, documented and shipped.

The philosophy is two axes
([`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md) §0).
**Form has no choices:** there is one short, distinct way to write each
thing, every larger form is built from smaller ones, and every tool and gate
enforces it. **Rigor has every choice:** a program is as strict as you write
it, where you write it, and pays for nothing else. Every blue word (bidama,
waku, mondou, the blueshift) maps to the concept you already know in
[the glossary](GLOSSARY.md).

A file is a program, a library and its tests at once:

```blue file=words.b
@doc """
shout: The text in capitals, with an exclamation mark.

    shout("olá") #=> "OLÁ!"
"""
def shout(text: String) -> String
  "#{upcase(text)}!"
end

def main()
  write_stdout(unlines([join(map(shout, argv), " ")]))
end

test "shout raises its voice and keeps the text"
  assert shout("oi") == "OI!"
  assert shout("") == "!"
end
```

```console
$ blue words.b olá mundo
OLÁ! MUNDO!
$ blue test words.b
2 test(s): 2 passed, 0 failed
```

The example in the `@doc` is the second test: `blue test` runs it beside the
`test` block, so a documented example cannot drift from the code.

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

The language server closes the gap for you: on a loose definition it offers a
code action that writes the types its calls showed.

## Safety first

Every effect outside the program is a capability: `process`, `filesystem`,
`environment`, `clock`, `network` or `entropy`. `--allow` holds a run to the
ones you name, and the check stage refuses the program before it runs when it
writes a host name outside them:

```blue file=peek.b
def main()
  write_stdout(read_file("words.b"))
end
```

```console fails
$ blue --allow none peek.b
refused: `read_file` reaches the host (filesystem), which this run does not allow; pass --allow filesystem to grant it
```

A script states its capabilities in its shebang,
`#!/usr/bin/env -S blue --allow filesystem`. A project states them once in its
`Bluefile`: `allow` is the ceiling of the whole program, `reach` is the floor
each package needs, and `blue lock` refuses a package whose floor does not fit
under the ceiling. `virtualize` binds a capability to a pure provider, such as
a stepped clock, a seeded random source or an in-memory file tree, for the
whole program or only for the packages you name. An evaluation session
(`eval`, `repl`, `serve`) is pure unless you start it with `--allow`. Every
Rust guarantee, the blue gate that matches it and its off switch are in
[Safety first](SAFETY.md).

## What ships

| Battery | What you get | Read |
|---|---|---|
| The language | macros as term rewriting, with bounded expansion; errors raised and rescued by kind, or returned as refusals; OTP-style processes with private environments, copy-on-send and supervised restarts | [the reference](REFERENCE.md), [the agent guide](../AGENTS.md) |
| Tests | `test` blocks beside the code, a doctest in every `@doc`, coverage, mutation testing, and a conformance suite every evaluator must pass | [Testing](TESTING.md), [the spec](../spec/README.md) |
| Tools | one formatter; a check stage whose rules carry their own fixes; a language server with hover, completion, definitions, references, rename, signature help, semantic tokens, inlay hints and code actions; a REPL; `watch`, `profile`, `trace` and code queries | [Diagnostics](DIAGNOSTICS.md) |
| Packages | bidamas, each a namespace; a `Bluefile` that is itself a blue program, pinned by its lock; registries rendered as publish workflows | [Authoring](../bidamas/AUTHORING.md), [Registry](REGISTRY.md) |
| Shipping | a Bluefile `app`, `image` (built by nix, distroless by default), `workload` and `service` (Kubernetes objects and a Helm chart, committed and gated fresh for GitOps), and `blue diff`, read-only | [the build stack](BUILD-STACK.md) |
| Services | configuration (`settei`), entries each off or refused alone (`kousei`), postures (`shisei`), request defence (`bougyo`), retries (`saishikou`); HTTP, NATS, PostgreSQL, Valkey and JetStream; HTTP/2 framing and HPACK in pure blue | [Service architecture](SERVICE-ARCHITECTURE.md), [HTTP/2](HTTP2.md) |
| Documentation | this README, `AGENTS.md`, `llms.txt` and the book, rendered from one source per fact, every example run | [Documentation](DOCUMENTATION.md), [Markdown](MARKDOWN.md) |
| Editors | a tree-sitter grammar generated from blue's own grammar spec | [tree-sitter](NATURALIZE-TREESITTER.md) |
| WebAssembly | the whole pipeline compiled to `wasm32-unknown-unknown` with no host imports at all | [`blue-lang-wasm`](../crates/blue-lang-wasm) |

## Commands

Every command `blue` takes, read from its own argument parser when this file
was rendered. `blue help COMMAND` shows each one's flags.

```hon
commands
```

## The language in numbers

Counted from the tables the implementation runs on, when this file was
rendered:

```hon
language
```

## The standard library

<details>
<summary>Every bidama, with the purpose its <code>@moduledoc</code> states</summary>

```hon
packages
```

</details>

## What is not built

blue states its gaps plainly, because a language's honest gaps matter more
than its claims. This list is the one in
[Implementing blue](implementing.md#what-is-not-built), rendered here:

```hon
include implementing.md#what-is-not-built
```

## Theming

Colours come from [irodori](https://github.com/pleme-io/irodori), the fleet's
Nord palette. blue carries no hex of its own. `nord10` (`#5E81AC`, deep frost
blue) is its identity, and `nord8` frost cyan stays the fleet's shared
interaction colour: identity and interaction are different roles. The mark is
a blueshift too: four solid cells walk Nord's Frost band toward blue. It names
each colour by ANSI slot, never by hex, so it renders in your Nord and follows
you when you retheme.

## Building blue

```console host
$ nix build .#blue
$ nix flake check
$ cargo test --workspace
```

`nix build` is hermetic. `nix flake check` runs every gate the root
`Bluefile` declares. This README is rendered by `hon` from
[`docs/introduction.md`](introduction.md), the first tutorial, the
implementation's own tables and the catalogue; edit those, then run
`nix run .#regen`. Changing blue itself starts at [AGENTS.md](../AGENTS.md).

MIT.
