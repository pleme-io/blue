# vocabularify — the surface/structure vocabulary

The typed vocabulary for *"a program's spelling is separable from its
meaning."* Two primitives — **`kigou`** (記号, which characters mean what) and
**`yakugo`** (訳語, which words mean what) — over one invariant: the
tatara-lisp form tree.

This is the `/vocabularify` pass on that domain: Gate 0 first (name the illegal
states), then the ledger grading how each is actually cornered. **The ledger is
the deliverable, and it is graded honestly — most of these are CI-caught, not
unrepresentable.**

---

## Gate 0 — the illegal states, named before anything is graded

You cannot pick a technique before naming the bad value. Written as a literal
list, in the order they were discovered rather than the order that flatters:

1. **A surface changes a program's meaning.** French `clamp` computes something
   other than English `clamp`. This is the one that would make the whole idea
   worthless — a surface that alters semantics is a dialect, and dialects
   fragment a language.
2. **A surface is half-applied.** A pack translates 15 of 20 keywords, so the
   other five stay English and the surface is a pidgin nobody can write in.
3. **A pack means one thing at parse time and another at macro-expansion.** The
   static and build phases disagree, so code that arrives from a macro behaves
   differently from identical code written by hand.
4. **A symbol is both an operator and a name.** `≠` lexes as `!=` in one place
   and as an identifier in another.
5. **An alias means something subtly different from what it looks like.** `≤`
   is *almost* `<=`. This is worse than not having it.
6. **An invisible character enters source.** A zero-width space or NBSP that
   makes correct-looking source fail, or worse, parse differently.
7. **A typo'd surface tag silently runs the program in another surface.**
   `BLUE_LANG=fr` misspelled falls back to English and fails much later as an
   unbound symbol pointing at innocent code.
8. **A pack rewrites string literals.** A translated program's data is silently
   altered.
9. **A pack rewrites a user's variable that collides with a keyword.** Under
   the French pack a variable named `fin` becomes `end`.

---

## The ledger

Tier vocabulary is closed (`selo`'s `SealTier`): `truly-unrep` ·
`parse-time-rejected` · `only-mitigated (C1..C6)`. **A row grading
`only-mitigated` names its ceiling** — an unnamed ceiling is the round-up this
section exists to forbid.

<!-- tier-ledger -->

| bad state | how it is cornered | tier |
|---|---|---|
| **[1] a surface changes meaning** | `every_language_produces_the_identical_ast` — the same program in every one of the 11 packs must produce a byte-identical `Sexp` to the English one. Asserted per pack, not sampled. | only-mitigated (C2) — a test over the packs that EXIST; a pack added without one is ungraded. Ceiling: no type forbids authoring a divergent pack |
| **[2] a surface is half-applied** | `every_builtin_pack_loads` asserts a floor of ≥15 translated terms per pack, and a pack translating nothing fails to parse at all | only-mitigated (C1) — the floor is a count, not a coverage proof against the keyword list. Ceiling: a pack could translate 15 *wrong* terms |
| **[3] static and build phases disagree** | `the_ast_rewrite_agrees_with_the_token_rewrite` — for every pack, the token path and the AST path must produce identical trees | only-mitigated (C2) — same ceiling as [1]: per-pack, not per-construct |
| **[4] a symbol is both operator and name** | `the_two_tables_do_not_overlap` — the tables are hand-maintained, so this is the check that keeps a later addition from creating one | only-mitigated (C1). Ceiling: two hand-tables rather than one source. **The real fix is one table with a variant field**, so overlap has no representation — named, not built |
| **[5] an alias means something else** | `an_alias_lexes_to_the_same_program_as_its_ascii_spelling` — each alias must produce the *identical* tree as its ASCII form | **parse-time-rejected** — the alias resolves to the same token in the lexer, so a divergent meaning has no path to exist |
| **[6] an invisible character** | `kigou::classify` returns `Class::Reject` for control and whitespace characters; the lexer turns that into a lex error naming the codepoint | **parse-time-rejected** |
| **[7] a typo'd surface tag** | `resolve_surface` ERRORS on an unknown `BLUE_LANG`, listing the available surfaces. An unrecognised host *locale* falls back to English deliberately — nobody asked for it | **parse-time-rejected** for the explicit case; the locale case is a designed default, not a gap |
| **[8] a pack rewrites strings** | `a_pack_does_not_rewrite_string_literals` — `apply` matches only `TokenKind::Ident`, and `rewrite_symbols` only `Atom::Symbol` | **truly-unrep** — a `Str` token has no branch that rewrites it; the code path does not exist |
| **[9] a pack rewrites a colliding variable** | Nothing. Documented in the module as inherent | only-mitigated (C6) — **accepted, not solved**. Ceiling: localising the surface localises what counts as reserved. Naming a variable `fin` under the French pack is exactly as broken as naming one `end` in English |

**Read the shape, not the count.** Two rows are `truly-unrep` or close to it;
six are `only-mitigated`, and four of those share one ceiling — *the guarantees
are per-pack tests, not types*. A pack authored tomorrow gets no protection
until someone adds it to `BUILTIN_PACKS`, at which point every test above
covers it automatically. That automatic-on-registration property is the honest
strength here; the weakness is that registration is a human step.

---

## The three phases

| phase | mechanism | status |
|---|---|---|
| **static** — source text | `yakugo::apply` on the token stream | **SHIPPED**. Keywords are structural, so nothing else can work: `définir` will not parse until it is `def` |
| **build** — macro expansion | `yakugo::rewrite_symbols` on the emitted tree | **SHIPPED as a primitive, UNWIRED**. The pass exists and is tested against the token path; no macro currently calls it |
| **runtime** — eval / REPL | the same `rewrite_symbols`, applied to a form before evaluation | **SHIPPED as a primitive, UNWIRED**. Same function; no evaluator entry point takes a pack |

The honest statement: **one mechanism covers all three phases and one of the
three is wired.** The other two need a call site, not a design — which is a
much smaller remaining job than it was, and is why the AST pass was worth
building before the wiring.

---

## Not done, and named rather than implied

- **Fleet extraction.** `yakugo` and `kigou` live in `blue-lang-syntax`. The
  mechanism — a symbol-substitution layer over a tatara-lisp tree — is not
  blue-specific and belongs in a fleet library, since any Four-Lisps surface
  could use it. That is `/extract-and-dominate` work and its trigger has not
  fired: **one consumer**. Extracting on one consumer is how a premature
  abstraction gets born, so this waits for the second.
- **The `(defyakugo …)` form is data, not a `TataraDomain`.** Packs are parsed
  by a small hand parser rather than registered as a typed Lisp domain, because
  `blue-lang-syntax` is the bottom of the stack and everything above it pays
  for any dependency added here. A typed border is the destination; the cost of
  reaching it today is an evaluator dependency in the lexer's crate.
- **One table instead of two** for `kigou`, per ledger row [4].
