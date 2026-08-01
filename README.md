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
