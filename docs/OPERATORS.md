---
kind: explanation
summary: short notation for what blue says most, keyed to the blueshift (design)
---

# OPERATORS — short notation for what blue says most, keyed to the blueshift

Status: DESIGN, 2026-10-27. Corpus measured at `71b4f65`: 336 files, 152,314
lines (blue's tracked `.b` files, kensa's bidama, the blue actions). Nothing here
is built unless §9 says so.

## 1. Destination

Blue writes the patterns it uses most in the shortest form that reads at a
glance, keeps exactly one stored spelling for each meaning, and grows a notation
for mathematics and science whose meaning the checker proves at the rung that
can prove it. The defaults permit the most: every operator whose meaning holds
at the file's rung is on. Two choices are mutually exclusive only where the
architectures behind them cannot coexist (the numeric model, a proof rung), and
then a project selects one, once.

## 2. The rules (amending `CANONICAL-FORMS.md` §1-2)

1. A new operator lowers to the same tree as the form it replaces, or it is a
   new meaning and both stay (rule 4 of the canon: `x or d` is not `x ?? d`,
   because `or` treats `false` as absent).
2. The long form still parses; `blue fmt` rewrites it to the operator; check,
   run and test refuse it in a stored file, with a B-code and an autofix.
3. **Amended:** words beat symbols, **except universal notation**: indexing,
   ranges, membership, and mathematical operators whose symbol is the
   discipline's own spelling. A symbol wins only when it is in the corpus's top
   tier (§3) or is the notation of a science the language serves.
4. **The rewrite is rung-scoped.** A rewrite whose safety needs a type (that
   `x` is never `false`, that `+` is defined on these operands) fires only at a
   rung where the checker knows that type. Below that rung both spellings stay
   legal and the long one is canonical. Raising a file's rung can change its
   canonical text; the formatter applies it, and the change is reviewed like
   any other.
5. One stored spelling per operator. Mathematical operators store their
   Unicode symbol; each has one ASCII input that `blue fmt` rewrites, as `!x`
   becomes `not x` today.

## 3. What the corpus says to shorten

Ranked by occurrences × files.

| Rank | Pattern | Uses / files | Notation | Rung |
|---|---|---|---|---|
| 1, 3 | `get(m, :k)` | 4,141 / 62 | `m.k` when `blue-field` on a map is exactly `get` (same tree, same nil behaviour); otherwise `m[:k]` | dynamic |
| 2, 6, 12, 17 | calls nested 3+ deep; `map(f, filter(g, xs))` | 2,349 / 113 | `xs \|> filter(g) \|> map(f)`: the pipe threads into the **collection slot**, read from each verb's signature (`docs::NAMES`, the table B0062 already uses), not into the first argument, so `map`'s order needs no migration | dynamic for builtins; annotated for user functions (inferred parameter kinds) |
| 4, 5, 15 | `nth(i, xs)`, `first(xs)`, `nth(0, xs)` | 1,802 / 81 | `xs[i]`; `first` stays a word (it answers `nil` on `[]`, `xs[0]` the same: one tree, so `nth(0, xs)` rewrites to `xs[0]`) | dynamic |
| 7, 20, 26 | `x or d` as a default; `if x.nil? d else x end` | 325 / 115 | `x ?? d`, a new meaning (nil only). `x or d` rewrites to `x ?? d` only where the checker proves `x` is not a Bool | `??` dynamic; the rewrite annotated |
| 19, 24 | `get(get(m, :a), :b)`; `if x.nil? nil else f(x) end` | 202 / 47 | `m?.a?.b`, `x?.f`: a new meaning (nil propagates; `get` raises) | dynamic |
| 11, 22 | `append(xs, [y])` | 60 / 27 | `[*xs, y]` (the splat already exists for arguments) | dynamic |
| 9, 14 | `(x) -> f(x)` | 259 / 57 | `f`, only when `f` is a function of arity ≥ 1 (never a zero-arity name, B0063) | annotated |
| 28 | `x >= a and x <= b` | 28 / 15 | `x in a..b`; `a..b` and `a..<b` lower to `range`; `x in xs` lowers to `member?` | dynamic |

Not shortened, by rule 1: `xs == []` against `empty?` and `count(x) == 0`
(they differ on `nil`), `concat` against interpolation (both stay), `&name`
(rejected; the lambda is the one function value).

## 4. The mathematics and science tier

Default on at every rung where its meaning holds.

| Operator | Stored | ASCII input | Lowers to | Rung where it is checked |
|---|---|---|---|---|
| power | `x ** n` | — | `pow` | dynamic |
| integer division | `a ÷ b` | `a // b` | `quot` | dynamic |
| composition | `f ∘ g` | `f >> g` reads as `g ∘ f` | `compose` | annotated (arities agree) |
| membership, not | `x ∈ s`, `x ∉ s` | `x in s`, `x not in s` | `member?` | dynamic |
| set algebra | `∪ ∩ ∖ ⊆ ⊂` | `union`, `intersect`… | `kumi` (sets) | annotated |
| comparison | `≤ ≥ ≠` | `<= >= !=` | as today | dynamic; ASCII stays stored for these (rule 3: the corpus spells them in ASCII, 0 churn) |
| summation, product | `∑(i ∈ a..b) e`, `∏(…) e` | `sum(i in a..b) e` | `fold` over the range | annotated |
| square root, abs | `√x`, `\|x\|` | `sqrt(x)`, `abs(x)` | `sqrt`, `abs` | dynamic |
| dot, cross, matrix product | `u · v`, `u × v`, `A ⊗ B` | `dot`, `cross`, `kron` | `gyouretsu` | checked (shapes agree) |
| units | `9.81 m/s²` | `9.81 <m/s^2>` | a quantity with a dimension | checked (dimensions agree; a mismatch is a type error) |
| logic | `∀ x ∈ s, p`, `∃ x ∈ s, p`, `p → q`, `p ↔ q` | `all x in s: p`… | `every?`, `any?`, implication | stated / proven (§5) |

Arithmetic operators on new types (rationals, intervals, vectors, quantities)
dispatch by type, so `+` on two quantities adds them and checks their
dimension. That needs the type, so it is `checked`; at `dynamic`, `+` keeps its
numeric meaning and a vector is added with `vadd`.

## 5. Proof rungs on the blueshift

Theory already names two optional proof rungs above `restricted`
(`theory/BLUE.md`). This design fixes what they mean for notation:

| Rung | A file here | Operators gain |
|---|---|---|
| dynamic | declares no types | type-agnostic operators (§3 at dynamic, §4 at dynamic) |
| annotated | some typed declarations | the pipe for user functions, `??` rewrites, eta, composition, set algebra |
| checked | every declaration typed | operator dispatch by type, shapes, units and dimensions |
| restricted | macros read only declared, content-addressed inputs | notation macros (a project's own operators), evaluated at compile time and cached |
| **stated** | every operator's laws are written (`okite` style: associativity, identity, distribution) and checked by generated property tests | `∀`, `∃`, `→` in law statements; a law a test refutes fails the build |
| **proven** | every stated law is discharged by a proof the checker verifies | the laws become theorems; a proof term or tactic script is required, Lean-style, and an unproven law fails the build |

## 6. Mutually exclusive architectures

Defaults permit the most. These pairs cannot coexist in one program, so a
project chooses one (a Bluefile `posture` entry, refused when both are chosen;
`blue_lang_bidama::quality` already computes exclusive groups):

| Group | Choices | Default | Why exclusive |
|---|---|---|---|
| numeric model | IEEE floats · exact (big integers, rationals, decimals, intervals) | IEEE | `1/3` cannot be both `0.333…` and `1/3` |
| proof | `proven` · unrestricted floats | — | a proof over IEEE arithmetic needs a model of rounding the kernel does not have; `proven` requires the exact model |
| effects in notation | `restricted` macros · macros that read the host | restricted | a notation whose expansion reads the world cannot be cached or proven |

## 7. Batteries for math and science

| Domain | Today | Needs |
|---|---|---|
| numbers | `kazu` (abs, pow, clamp), `shinsuu` (bases) | big integers, rationals, decimals, intervals (the exact model) |
| numerical methods | `kinji` (ODEs, roots, fitting, quadrature) | operator notation over it |
| linear algebra | `gyouretsu` | `·`, `×`, `⊗` dispatch at checked |
| statistics | `toukei` | distributions as values, `~` sampling notation (later) |
| number theory | `angou` | — |
| laws | `okite` | the `stated` rung's generator |
| units and dimensions | none | a units bidama and the quantity type |
| sets | none named here | `kumi`, through `/naming` |
| symbolic algebra | none | expressions as values, simplification (after the exact model) |
| proofs | none | the `proven` rung's kernel (a design of its own) |

## 8. Decisions

| Question | Chosen | Rejected, and why |
|---|---|---|
| Pipe direction | into the collection slot by signature | **first argument**: `xs \|> map(f)` is an error with `map(f, xs)`; **migrate `map` to data-first**: 1,569 call sites for a rule the signature table already encodes |
| `??` vs `or` | both, two meanings; rewrite only where types prove them equal | **one operator**: `false or d` and `false ?? d` differ |
| Unicode | stored for the math tier, one ASCII input each | **ASCII stored, Unicode rendered**: two spellings of one source; **Unicode everywhere**: churns 0-cost ASCII operators like `<=` |
| Proofs | rungs on the blueshift | **a separate proof language**: a second toolchain, and the program would not be the theorem's subject |
| Numeric model | a project-wide exclusive choice | **per-expression**: mixing them makes `/` ambiguous within one file |

## 9. Build order

| Step | Work | Gate |
|---|---|---|
| O1 | `m.k` vs `get` equivalence measured; then `m.k` or `m[:k]`, `xs[i]`, `[*xs, y]`, `a..b`, `in` | parse tests, a B-code and autofix each, the corpus rewritten and byte-checked |
| O2 | `?.`, `??` | runtime tests for the new meanings |
| O3 | the collection-slot pipe | the nested-call corpus rewritten; output identical |
| O4 | rung-scoped rewrites (eta, `or` → `??`) driven by `blue shift` | a file's canonical text changes only when its rung does |
| O5 | the math tier at dynamic | parse and lowering tests |
| O6 | exact numeric model and its exclusive group | `1/3` exact under the exact posture; refused if both postures are declared |
| O7 | units and quantities at checked | a dimension mismatch is a type error |
| O8 | the `stated` rung | a refuted law fails the build |
| O9 | the `proven` rung kernel | its own design first |

| Item | Tier |
|---|---|
| everything above | design |
