# blue's own configuration — written in blue.
#
# This file is not decoration and not a sample. shikumi ships a `.b` config
# front-end (`shikumi::blue_provider`) whose own header calls itself
# "wired-but-unproven": until this file, no real `.b` config had ever
# round-tripped through it. It has now, which makes blue the first fleet tool
# configured in its own language.
#
# ── THE SHAPE, AND WHY IT IS THIS ONE ────────────────────────────────────────
#
# shikumi maps a config by taking the FIRST top-level form, dropping a leading
# head symbol, and requiring what remains to be a kwargs list — alternating
# `Atom::Keyword` and value. Exactly one blue surface form lowers to that:
#
#   {k: v, …}          ->  (hash-map :k v …)      ACCEPTED
#
# Three plausible-looking alternatives do NOT, measured 2026-08-01 against the
# shipped provider rather than guessed:
#
#   config(k: v)       ->  parse error: blue rejects a label in argument
#                          position ("expected an expression, found Label").
#   k = v              ->  (define k v) — a define, not kwargs. Maps to an
#                          Array, so shikumi sees a list and not a dict.
#   {"k" => v}         ->  (hash-map "k" v …) — a string key is `Atom::Str`,
#                          not `Atom::Keyword`, so the kwargs test fails.
#
# The rocket case is the instructive one: §V.13's rendering law says `a: 1` and
# `:a => 1` are the SAME tree, but `"a" => 1` is a different tree because a
# string key is a different thing. Config keys are symbols, so the shorthand is
# not merely the tidy spelling here — it is the only one that is a dict.
#
# ── THE VALUES ARE THE SHIPPED DEFAULTS ──────────────────────────────────────
#
# Both are BOUNDS: raising either changes no program's meaning, only whether a
# pathological input is refused. That is the entire argument for why these two
# knobs are configurable and blue's formatter width and posture ceiling are not
# — see `crates/blue-lang-cli/src/config.rs`.
{
  solver_max_steps: 100000,
  max_expr_depth: 256
}
