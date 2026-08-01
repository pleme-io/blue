# blue

The pleme-io language: Ruby/Elixir surface syntax on a tatara-lisp AST,
with a Rust runtime.

**Status: v0.0.1 — the surface parses and runs. Nothing else is built.**

Canonical design: [`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md).

```blue
def fact(n)
  if n < 2
    1
  else
    n * fact(n - 1)
  end
end

5 |> fact
```

parses to

```lisp
(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))
(fact 5)
```

and evaluates to `120` on the shipped tatara-lisp interpreter.

## What exists

| Crate | Status |
|---|---|
| `blue-lang-syntax` | lexer, precedence-climbing parser, lowering to `tatara_lisp::Sexp` |
| `blue-lang-fmt` | Wadler/Oppen pretty-printer + the canonical formatter. **No configuration type exists.** |
| `blue-lang-waku` | the frame — REACH/WHEN/WHERE — with the lattice laws property-tested and `narrow` proven never to widen |
| `blue-lang-check` | the typing ladder: **zero analysis at rung 0, measured**; checked where declared; seams recorded |

## The ladder, measured

```blue
def add(a, b)          # rung 0 — 0 nodes visited
  a + b
end

def add(a: Int, b: Int) -> Int   # rung 1 — checked
  a + b
end
```

`Stats::visited` is `0` for an unannotated program, and **stays 0 when you
wrap it in fifty more unannotated functions.** Cost is a function of
annotation density, not of the call graph — that is what makes the ladder
slide exactly rather than approximately.

## The formatter's two laws

Property-tested over a 50-entry corpus, not asserted:

1. **Idempotence** — `fmt(fmt(s)) == fmt(s)`
2. **Semantic round-trip** — `parse(fmt(s)) == parse(s)`, compared as trees

Plus canonicality: two spellings that parse to one tree format to one text.
That is the text↔tree bijection content-addressed identity depends on.

Everything else in the design — the typing ladder, the memory model, the
`waku` frame, `bīdama` packages, the formatter, the LSP — is **design only**.
Read `theory/BLUE.md` for what is settled, what is open, and what has been
retracted.

## The one structural commitment

The parser's output **is** a `tatara_lisp::Sexp`. There is no private blue
AST. Blue source parses *to tatara-lisp*, which is what makes homoiconicity
an identity rather than a conversion step.

## Tests

```
cargo test
```
