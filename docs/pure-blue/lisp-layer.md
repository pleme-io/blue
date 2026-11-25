---
kind: explanation
r_ids: PURE-BLUE.md
summary: pure blue, the Lisp layer
---
# Pure blue — the Lisp layer

**Tier: DESIGN (2026-11-17).** Plan: [`../PURE-BLUE.md`](../PURE-BLUE.md).

**The thesis (operator, 2026-11-17): Lisp is special for what blue wants.** Blue's syntax
tree already *is* tatara-lisp data (`Spanned`/`SpannedForm`, Tenet 1): blue reads to Lisp
forms, and both runtimes execute Lisp forms. So every optimisation, every compiler pass and
the memory model are written as programs over that data, in the language that data belongs
to. This doc says how each track uses the layer.

## Why Lisp, with its record

| Property | What it gives pure blue | Prior art |
|---|---|---|
| Code is data | Every pass is a function from forms to forms; the IR is forms; nothing needs a separate AST library | Lisp 1.5's compiler was written in Lisp (1962), the first self-hosting compiler |
| Macros run at compile time | Tables, encoders, pass boilerplate and specialisations are generated, not written | Racket, Chez Scheme |
| Small passes over declared languages | A compiler made of many tiny, checkable rewrites, each between two declared IR languages | Chez Scheme's nanopass framework (Keep, Dybvig, 2013) |
| A restricted subset compiles without a runtime | The runtime (allocator, counts, scheduler) is written in blue itself, in a subset that needs no allocation | PreScheme, which implements Scheme48's VM |
| Ownership inference in a Lisp | The memory model without a collector | Carp (inferred borrow checking, no GC); Baker's Linear Lisp (1992) |
| A tiny Lisp at the bottom of a bootstrap | The full-source tower ends in a minimal reader and evaluator | GNU Mes, the Scheme at the heart of Guix's full-source bootstrap |

## How each track uses the layer

### 1. The IR is forms (B1)

The IR's atoms, bindings and terms are tatara forms, not records: `(let v (prim add a b))`,
`(dup v)`, `(drop v)`, `(reuse v (alloc Cons x xs))`. Every existing tool works on them
unchanged: `read_forms`, the printer, `blue ast`, the formatter, span tracking, the
differential runners. A pass's input and output can be printed, diffed and pasted back.

### 2. Passes are declared languages and small rewrites (B1, B3, B5)

Following nanopass: each IR level is **declared** as a `(defir name …)` form (its terminals
and productions), and each pass is a `(defpass from to …)` whose body handles only the forms it
changes; the macro generates the identity cases for the rest. The declared languages are
checked: a pass that emits a form its target language does not allow fails at expansion. So
the compiler is ~30-50 passes of a few dozen lines each, every one readable, every one tested
by a differential between its input and output under `ir_eval`.

Planned passes, in order: expand → resolve → ANF → closure conversion → **Perceus**
(`dup`/`drop` insertion) → drop specialisation → reuse pairing → borrow inference →
unboxing → inlining → instruction selection → register allocation → encoding.

### 3. Perceus is a rewrite (M1, B1)

Ownership inference is a pass over ANF forms: walk each body backwards with the live set,
insert `(drop x)` after a binding's last use, `(dup x)` where a live value is passed owned,
and pair a `drop` with a following same-shape `alloc` into `reuse`. In Lisp this is one
tree walk with a set, the shape of Koka's implementation. The facts M1 reports are the same
pass run in "explain" mode: it returns the annotations as data instead of rewriting.

### 4. Macros generate tables and specialisations (B2, R3, B5)

- **Encoders.** The x86-64 instruction table is data, and a macro expands it into the
  encoder, decoder and printer, so the three never disagree (as `bpf.b`'s tables do by hand).
- **Specialisation.** A `(specialise f arg)` macro partially evaluates `f` at compile time when
  an argument is known: the board, the width, the size class. Compile-time evaluation is just
  running blue, which Lisp makes ordinary.
- **Reports.** Generators already emit Rust tables, docs and grammars (`gen/*.b`); the same
  macros emit IR declarations and conformance rows.

### 5. The runtime is written in a restricted subset (R1, R2, R5)

The allocator, counts and scheduler cannot use the allocator they implement. PreScheme's
answer: a **declared subset** of the language (static types, fixed-width integers, no
allocation, no closures that escape) that compiles without a runtime. Blue's subset is a
`(defir runtime …)` language plus a checker rule: the runtime bidama is written in blue, the
rule proves it stays in the subset, and only it may use the raw words (I5).

### 6. Optimisation is driven by facts as data (B5, M2)

Every pass can attach facts to forms (last use, unique, borrowed, range, type). Facts are
forms too, so the engine, the LSP and `blue explain` read them without a second format, and an
optimisation is a rewrite whose guard reads a fact. Range-proven check removal (`cz_nonneg`)
is the existing example.

### 7. The bottom turtle is a tiny Lisp (S4)

The full-source chain follows Guix's: hex seed → a minimal reader and evaluator of a small
Lisp (Mes's role) → that Lisp runs the blue reader and compiler. Blue's forms are Lisp, so the
tiny evaluator does not translate anything: it reads blue's own tree.

## What this changes in the plan

1. **B1 starts with `defir`/`defpass`** (a nanopass macro library in blue), before the first
   real pass; every later pass is written with it.
2. **M1 is the Perceus pass in explain mode**, not a separate analysis in the Rust checker; it
   runs on the expanded forms (after L3) and lands as tatara-lisp/blue, not Rust.
3. **R1-R2 add the runtime subset** as a declared language with its rule.
4. **S4's evaluator is a minimal Lisp** that reads blue forms directly.
5. **Prior art adds** Chez Scheme's nanopass, PreScheme/Scheme48, Carp, Linear Lisp and GNU Mes.
