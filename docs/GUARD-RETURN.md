---
kind: explanation
summary: Guard-clause return, DESIGN: `return x` where the parser can rewrite it into if/else, refused where it cannot, so blue stays one expression per body at no run-time cost
---

# Guard-clause `return`: the design of record

**Tier: DESIGN (2026-11-06), operator-approved.** Blue has no `return`
today. A body is one expression, because blue lowers to tatara-lisp, whose
only non-local exit is `throw`/`try`, which `raise`/`rescue` already use. A
general `return` would be an exception per call: slow, and caught by the wrong
`rescue`. Without it, a reader with several early exits nests: khipu's
`read_statement` (2026-11-06) is four lambdas inside `then(...)`, where guard
clauses would be five flat lines.

## The rule

`return x` is a statement allowed where the parser can rewrite it into
`if`/`else`, and nowhere else.

```text
def read(cs)                       def read(cs)
  s = node(cs)                       s = node(cs)
  if s.why                           if s.why
    return s                           s
  end                    lowers to   else
  p = node(cs, s.i)                    p = node(cs, s.i)
  ok(s, p)                             ok(s, p)
end                                  end
                                   end
```

- **Allowed:** a `return` as the last statement of a branch of an `if`,
  `elsif`, `else` or `case` arm, where every enclosing form up to the
  function body is a statement sequence or one of those branches. The rest of
  the sequence after the `if` becomes the `else`.
- **Refused, with a named rule:** a `return` inside a lambda (whose function
  would it leave?), inside a loop form, inside an argument, or at the top
  level of a file. The refusal names the form that blocks it.
- **Free of cost:** the rewrite happens before lowering, so the evaluator,
  the VM, `def_hash` and the shape hashes see only `if`/`else`. Two programs
  that differ only by a guard `return` versus the nested `if` have the same
  `def_hash`.
- **Additive:** nested `if`/`else` stays valid; `blue fmt` keeps the form a
  file used.

## Gates

| Gate | Proves | Red run |
|---|---|---|
| R-lower | a guard `return` and its nested `if` lower to the same tree and the same `def_hash` | lower the `return` to `throw` |
| R-refuse | each refused position gives its rule code and names the blocking form | allow `return` in a lambda |
| R-total | a function whose branches all `return` still has a value on every path | drop the implicit `else` |

## Phases

| # | Deliverable | Exit |
|---|---|---|
| G1 | parser rewrite and the refusal rule, with the three gates | `read_statement` in khipu is written flat |
| G2 | `blue fmt` and the language server show the guard form; the tree-sitter grammar knows `return` | editors highlight it |
