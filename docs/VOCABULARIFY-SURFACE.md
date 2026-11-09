---
kind: explanation
summary: "kigou and yakugo: a program's spelling separated from its meaning"
---

# vocabularify — the surface/structure vocabulary

The typed vocabulary for *"a program's spelling is separable from its
meaning."* Two primitives — **`kigou`** (記号, which characters mean what) and
**`yakugo`** (訳語, which words mean what) — over one invariant: the
tatara-lisp form tree.

This page names the illegal states first (Gate 0). The [Ledger](#ledger) then
gives the state of each one, and of each phase. Most states are caught by a
test, not made impossible by a type.

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

## Ledger

✅ built and tested · ⏳ in progress · ❌ not built

A test over the packs catches most of these states. A type does not forbid
them. A pack added to `BUILTIN_PACKS` (11 today, in
`crates/blue-lang-syntax/src/yakugo.rs`) gets every test below at once. A pack
not added there gets none.

| Item | State | What makes it true |
|---|---|---|
| [1] a surface changes meaning | ✅ built | `every_language_produces_the_identical_ast` (`yakugo.rs`): each pack gives a byte-identical `Sexp` to English. This is a test over the packs that exist. No type forbids a divergent pack. |
| [2] a surface is half-applied | ⏳ in progress | `every_builtin_pack_loads` holds each pack to at least 15 terms. A count is not coverage: a pack can translate 15 wrong terms. A coverage proof against the keyword list does not exist. |
| [3] the static and build phases disagree | ✅ built | `the_ast_rewrite_agrees_with_the_token_rewrite` (`yakugo.rs`), per pack. It is not per construct. |
| [4] a symbol is both operator and name | ⏳ in progress | `the_two_tables_do_not_overlap` (`kigou.rs`) checks two hand tables. One table with a variant field, where overlap has no representation, is not built. |
| [5] an alias means something else | ✅ built | `an_alias_lexes_to_the_same_program_as_its_ascii_spelling` (`kigou.rs`). The lexer resolves the alias to the same token, so the parse refuses a different meaning. |
| [6] an invisible character enters source | ⏳ in progress | `kigou::classify` returns `Class::Reject` for a control character, a whitespace character (NBSP too) and U+FEFF; the lexer reports the codepoint. A zero-width space (U+200B) is not whitespace in Unicode, so it lexes as part of a word. |
| [7] a mistyped surface tag | ✅ built | `resolve_surface` (`crates/blue-lang-cli/src/main.rs`) refuses an unknown `BLUE_LANG` and lists the surfaces. An unknown host locale falls back to English by design. |
| [8] a pack rewrites strings | ✅ built | `a_pack_does_not_rewrite_string_literals` (`yakugo.rs`). `apply` matches only `TokenKind::Ident` and `rewrite_symbols` only `Atom::Symbol`: no code path rewrites a `Str`. |
| [9] a pack rewrites a colliding variable | ❌ not built | Accepted, not solved. A surface localises what counts as reserved: a variable `fin` under the French pack breaks as `end` does in English. |
| the static phase: `yakugo::apply` on tokens | ✅ built | `BLUE_LANG` selects a pack for `blue` (`resolve_surface`). |
| the build phase: `yakugo::rewrite_symbols` after macro expansion | ⏳ in progress | The pass exists and agrees with the token path ([3]). No macro calls it. |
| the runtime phase: `rewrite_symbols` before evaluation | ⏳ in progress | The same function. No evaluator entry point takes a pack. |
| `yakugo` and `kigou` as a fleet library | ❌ not built | They live in `blue-lang-syntax`. They have one consumer, so extraction waits for a second. |
| `(defyakugo …)` as a typed domain | ❌ not built | A small hand parser reads packs. A typed border would put an evaluator dependency in the lexer's crate. |
