# zenbu (全部) — the whole distribution, as ONE dependency.
#
# ## What this is for
#
# Distribution granularity is the CONSUMER's choice, not something the language
# imposes. Depend on `kazu` and you get numbers; depend on `zenbu` and you get
# everything. Both are ordinary bidamas resolved by the same solver — the only
# difference is how many `needs(...)` the manifest declares.
#
# Rust's `futures` is the precedent: `futures-core` and `futures-util` are
# usable on their own, and `futures` re-exports them so a consumer who does not
# want to think about the split does not have to. Neither granularity is the
# "real" one.
#
# ## Why it defines nothing of its own
#
# A facade that added a function would stop being a facade — it would be an
# eighteenth package with a bundle attached, and the next author would have to
# ask which of its two jobs a change belongs to. Everything here is `use`, and
# the only code is the test that proves every arm of the bundle is live.
#
# ## The one thing that would make this a lie
#
# A `needs(...)` without its `use(...)` — the manifest claiming a dependency the
# import does not deliver. Two gates hold it, and they hold it from opposite
# sides: `distribution.rs::every_declared_dependency_is_actually_imported`
# checks manifest→source, and the reachability test below checks that the
# import actually BINDS something from each package. A dropped line fails one
# or the other.
#
# ## Do not compute this list, however much you want to
#
# Seventeen literal `needs` lines are exactly the shape that invites
# `map(fn(d) needs(d, "^0.1") end, siblings())` — and a Bluefile is blue code,
# so that would *work*. It would also silently halve the package: `mk-bidama.nix`
# reads the dependency graph by splitting the manifest text on `needs("`, so a
# computed argument is invisible to nix while blue resolves it fine.
#
# Measured 2026-08-02, one entry rewritten as `computed = "moji"` /
# `needs(computed, "^0.1")`: blue's resolver still reported 17 dependencies,
# nix's saw 16, and the built closure came back with 17 bidamas instead of 18 —
# `moji` recorded and not delivered, with nothing red anywhere.
# `granularity.rs::the_regex_and_evaluated_dependency_views_agree` now fails on
# that divergence, which makes it loud; it does not make it impossible. The real
# fix is the `blue bluefile --deps --json` subcommand `mk-bidama.nix` names, so
# nix consumes blue's own evaluation instead of re-deriving it.

use("angou")
use("gyouretsu")
use("hizuke")
use("junjo")
use("kansuu")
use("kazu")
use("kikagaku")
use("kumiawase")
use("moji")
use("ongaku")
use("ran")
use("retsu")
use("ronri")
use("seimei")
use("shinsuu")
use("shuugou")
use("toukei")

test "every bidama in the distribution answers through this one import"
  # One probe per package, in the manifest's order. These are not behaviour
  # tests — each package proves its own behaviour in its own file. Each line
  # here asserts REACHABILITY: that a name defined in exactly one bidama, and
  # nowhere in blue's builtins, resolves after importing only `zenbu`.
  #
  # The distinguishing case for a facade is a MISSING ARM, so the value of this
  # block is that it has as many lines as the Bluefile has `needs`.
  assert is_prime(97) == true
  assert dot([1, 2, 3], [4, 5, 6]) == 32
  assert is_leap(2000) == true
  assert sort([3, 1, 2]) == [1, 2, 3]
  assert identity(7) == 7
  assert clamp(99, 1, 10) == 10
  assert manhattan([0, 0], [3, 4]) == 7
  assert combinations(52, 5) == 2598960
  assert empty("") == true
  assert major_triad(0) == [0, 4, 7]
  assert take_ints(42, 100, 5) == take_ints(42, 100, 5)
  assert size([1, 2, 3]) == 3
  assert every(fn(v) v > 0 end, [1, 2, 3]) == true
  assert life_step([[0, 0], [0, 0]]) == [[0, 0], [0, 0]]
  assert to_hex(255) == "ff"
  assert contains([1, 2, 3], 2) == true
  assert near(mean([2, 4, 6]), 4) == true
end

test "four packages compose without the consumer naming any of them"
  # ran -> junjo -> toukei -> kazu, off ONE declared dependency. This is what
  # the facade is actually worth: a consumer mixing four areas of the library
  # writes one `needs`, and never learns that `toukei` reaches `kazu` through
  # `junjo` and `ronri`.
  vs = take_ints(9, 100, 21)
  ordered = sort(vs)
  assert size(ordered) == 21
  assert is_sorted(ordered) == true
  # An odd count, so the median is an element rather than a float average.
  assert contains(ordered, median(ordered)) == true
end
