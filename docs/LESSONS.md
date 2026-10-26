# Lessons behind the CLAUDE.md rules

Full text of rules that CLAUDE.md states in short. Each shipped as a defect.

- **A formatter law passing is not the formatter being right.** All three laws
  held while every call rendered as a method send — `fact(n - 1)` printed as
  `(n - 1).fact`. A round-trip law measures the tree, never the readability.
  **When you change rendering, read the output.**
- **A corpus is only as strong as what is in it.** The annotated-`def`
  rendering bug survived because the formatter corpus contained no annotated
  defs. Add the case with the rule. `SURFACE_KEYWORDS` now makes the *omission*
  the failure — adding a keyword forces the corpus entry.

- **A round-trip law measures the tree, never the readability** — now with a
  third citation. `x = 5` rendered as `define(x, 5)` and interpolation as
  `concat(concat("a", x), "")`; both re-parse to the same tree, so all three
  laws passed while `fmt --write` silently rewrote real files. **Ship the
  formatter arm WITH the surface form, and read the output.**
- **A span is a property of the tree that `to_sexp` throws away, so tree tests
  cannot see it either** — the same lesson, fourth citation, now off the
  formatter. Making the parser build `Spanned` landed two mis-anchored
  productions (`body`'s synthesized `begin`, `case`'s `else`) that every one of
  the 82 parser tests passed over, because both TREES were correct and the
  spans were not compared to anything. The gate that found them walks each node
  asserting it sits inside its parent's span. **A derived artifact needs a test
  that reads the artifact, not the thing it was derived from.**
- **A diagnostic without a span is a diagnostic the editor puts in the wrong
  place.** `Diagnostic` carried only a message, so the LSP attached every type
  error to `Range::default()` — line 0, column 0 — and drew the squiggle on the
  first character of the file. It was not the LSP's bug: the parser had already
  discarded the position, and a span discarded at the parser is unrecoverable.
  **When a layer reports a location it does not have, look upstream for where
  the location was dropped, not downstream for somewhere to invent one.**

- **Isolation is the SEAL, not the rebuild.** The test runner and the process
  supervisor both threw an interpreter away per child to get isolation, at
  ~945µs each — essentially the entire cost of running a test, spent
  re-evaluating the stdlib to reach an identical state. `Interpreter::fork`
  shares the evaluated globals and seals them: a child's `define`s land in a
  private frame, and a `set!` reaching an inherited binding raises `SetSealed`.
  Same guarantee, 29µs. **Use `blue_lang_proc::forking` for `spawn`**, never a
  factory that rebuilds. A plain `Clone` is NOT a fork — `Env::set` writes
  through the `Arc`.

- **Two doors to the formatter is one door too many.** `fmt --write` learned to
  re-interleave comments; the LSP kept calling `format_forms`, so
  `textDocument/formatting` returned 707 bytes for 1010 and **deleted all six
  comments in the buffer**. Everything that shows a user their own file goes
  through `format_source_lossless`; `format_source` is for comparing trees.
- **A document built to be measured must give its comments back.** The
  formatter claims a comment when a document takes it, and a lambda is built
  as its inline and its block spelling while only one is printed; the rescue
  modifier measures its operands before it picks `begin`. Each dropped its
  comments with `Ok` and a green law, because the claim flag says a document
  took the comment, not that it was printed. Measure through `Renderer::probe`,
  decide on comments before building, and rely on the door's output check
  (`format_tree_lossless` compares the comment texts it prints with the ones it
  was given). A comment inside `#{}` code is invisible to the lexer's comment
  list; `comment_count` counts it and the door refuses it by line.
- **Printing code inside `#{}` can end the interpolation early.** The lexer
  closed `#{` on the first unbalanced brace, strings included, so a printed
  `"}"` cut the code short. It now reads a nested string whole; keep it that
  way when touching `skip_interpolation`.

- **`interpreter_hostless` is not hostless when the `sys` feature is on.** It
  forks a base built by `interpreter(&mut ())`, and `interpreter` installs the
  host layer under `#[cfg(feature = "sys")]` — so in `blue-lang-cli`, and in
  every `cargo test --workspace` run through cargo's feature unification, the
  "hostless" interpreter binds all 37 host primitives including `rm_rf`.
  `bluefile`'s module doc credited the opposite for months: it said a manifest
  was *"safe by absence of a binding"*. It is safe by the `check_reach` frame,
  and by nothing else — which makes the frame load-bearing rather than
  belt-and-braces. **A name that reads like a guarantee is not one; ask an
  interpreter.** Pinned by `blue-lang-cli/tests/capability_surface.rs`.
- **A capability is a bundle of NAMES, not a host effect.** `Reach` governs
  *what may be named*, and blue's real frames grant `+`, `define` and `package`
  — so a closed universe of host effects alone could not express a single frame
  blue mints. `Capability` closes the whole nameable vocabulary; the host-effect
  subset is what `imports_of` lowers. **Adding a variant is `E0004` at four
  sites**, which is what makes the import table derived rather than maintained.

- **The mark is a COLOUR shift, and its direction is meaning.** Four solid `█`
  across Nord's Frost band (`BrightCyan → Cyan → BrightBlue → Blue`), named by
  ANSI slot so it tracks the reader's theme. The first version was `░▒▓█` — a
  *density* ramp in one flat colour — which shipped and read as a blue box. It
  was wrong twice: a shift with nothing shifting, and dither glyphs katsuji's own
  docs warn "read as fuzz at cell size". **Quoting a warning and arguing past it
  is not clearing it.** Theme colours are `irodori` lookups; blue carries no hex,
  and a test enforces it.

