```
░▒▓█  blue
────────────────────
a Ruby/Elixir surface on tatara-lisp and Rust
```

**blue** is the pleme-io language. A Ruby/Elixir surface parses to a
[tatara-lisp](https://github.com/pleme-io/tatara-lisp) AST, macros are term
rewriting on that AST, and the runtime is Rust — not the BEAM.

## The mark is a blueshift

`░▒▓█` is not decoration. **Blueshift** is blue's central metaphor: the wave that
shifts with you across tatara-lisp and Rust as you write. A spectral shift toward
blue is a compression of light toward one end of a band, and the ramp is exactly
that — four cells of increasing density resolving to solid. Read left to right it
is the language's thesis: **loose, then denser, then locked.**

Declare nothing and blue is dynamic and fast. Annotate one function and *that
function* gets analysis. Nothing else changes — same tree, same answer, same
speed.

```blue
def add(a, b)                      # no annotation, no analysis
  a + b
end

def fact(n: Int) -> Int            # annotated — this one is checked
  if n < 2
    1
  else
    n * fact(n - 1)
  end
end
```

`blue check` prints what that cost, so the claim is a measurement rather than a
promise:

```
$ blue check example.b
typed declarations: 1
nodes analysed:     11
seams:              0
```

## Try it

```
nix run github:pleme-io/blue -- run example.b
```

| Command | |
|---|---|
| `blue run FILE` | parse, type-check, erase, execute |
| `blue test FILE` | run the file's `test` blocks |
| `blue fmt FILE [--check\|--write]` | the one formatting |
| `blue check FILE` | what the type checker did |
| `blue ast FILE` / `blue erase FILE` | the tree with and without annotations — the sliding scale, visible |
| `blue deps FILE` / `blue posture FILE` | read a `Bluefile` |
| `blue lsp` | language server over stdio |
| `blue banner` | the wordmark |

## What is here

Macros with **bounded expansion** — a runaway macro is a typed error naming the
macro, not a dead compiler. OTP-style **supervision** with private per-process
environments and copy-on-send. A **test framework** whose failures print the
expression as blue source. A **package manager** whose manifest is itself a blue
program. A **WASM** target that runs the whole language in an engine with *zero
host imports*.

```
$ blue test spec/macros.b
FAIL a macro expands
  assert double(21) == 43
3 test(s): 2 passed, 1 failed
```

The failure message is the formatter's output, so it reads exactly as written.

## What is not

Stated plainly, because a language's honest gaps matter more than its claims:

- **No per-process GC heap.** Processes have private environments and messages
  are deep-copied, but reclamation is `Arc` refcounting — there is no
  independent per-process collection pause.
- **Not self-hosted.** The toolchain is Rust. `spec/*.b` is blue specifying blue,
  which is the specification axis only.
- **Nothing fetches.** Dependency *resolution* is real; there is no registry
  client.
- **The formatter refuses a comment it cannot place.** Comments before or after a
  top-level form are preserved; one buried inside an expression is refused rather
  than dropped, because those lines get re-laid out.

The full tier ledger — every row marked SHIPPED or ABSENT — is
[`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md) §V.26.

## Theming

Colours come from [irodori](https://github.com/pleme-io/irodori), the fleet's
Nord palette. blue carries no hex of its own: `nord10` (`#5E81AC`, deep frost
blue) is its identity, and `nord8` frost-cyan stays the *fleet's* shared
interaction colour — identity and interaction are different roles.

## Building

```
nix build .#blue          # hermetic
cargo test --workspace    # 306 tests
```

MIT.
