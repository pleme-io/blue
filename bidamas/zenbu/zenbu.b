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
# Twenty-three literal `needs` lines are exactly the shape that invites
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

use("anaritikusu", [:la_lit_type])
use("angou", [:is_prime])
use("deeta", [:get_str])
use("gyouretsu", [:dot])
# waive B0016: zenbu is the facade, and depending on it means depending on heni
use("heni")
use("hizuke", [:is_leap])
use("junjo", [:is_sorted, :sort])
use("kakou", [:kk_outside_setback])
use("kansuu", [:identity])
use("kazu", [:clamp, :near])
use("kikagaku", [:manhattan])
use("kinji")
use("kueri")
use("kumiawase", [:combinations])
use("moji", [:empty])
use("mokuroku", [:md_cell])
use("nisshi")
# waive B0016: zenbu is the facade, and depending on it means depending on okite
use("okite")
use("ongaku", [:major_triad])
use("raifusaikuru")
use("ran", [:take_ints])
use("retsu", [:contains, :size])
use("rittai")
use("ronri", [:every])
use("ryouiki", [:box_around])
use("sabi")
use("seimei", [:life_step])
use("shinsuu", [:to_hex])
use("shisutemu", [:age_s])
use("shomei", [:hash_message])
# waive B0016: zenbu is the facade, and depending on it means depending on shuugou
use("shuugou")
use("souji")
use("tehai")
use("tokumei", [:suppress_small])
use("toukei", [:mean, :median])
use("zumen", [:zu_num])

test "every bidama in the distribution answers through this one import"
  # One probe per package, in the manifest's order. These are not behaviour
  # tests — each package proves its own behaviour in its own file. Each line
  # here asserts REACHABILITY: that a name defined in exactly one bidama, and
  # nowhere in blue's builtins, resolves after importing only `zenbu`.
  #
  # The distinguishing case for a facade is a MISSING ARM, so the value of this
  # block is that it has as many lines as the Bluefile has `needs`.
  assert la_lit_type(1) == :bigint
  assert is_prime(97) == true
  assert get_str(json_parse("{\"a\":\"x\"}"), "a", "d") == "x"
  assert dot([1, 2, 3], [4, 5, 6]) == 32
  assert is_leap(2000) == true
  assert sort([3, 1, 2]) == [1, 2, 3]
  assert identity(7) == 7
  assert clamp(99, 1, 10) == 10
  assert near(kk_outside_setback(90, 1, 1), 2) == true
  assert manhattan([0, 0], [3, 4]) == 7
  assert near(kinji::trapz([0, 1, 3], [0, 2, 6]), 9) == true
  assert kueri::ident("order") == "\"order\""
  assert combinations(52, 5) == 2598960
  assert empty("") == true
  assert md_cell("a|b") == "a\\|b"
  assert nisshi::format() == "nisshi/1"
  assert major_triad(0) == [0, 4, 7]
  assert raifusaikuru::hours(2) == 7200
  assert take_ints(42, 100, 5) == take_ints(42, 100, 5)
  assert rittai::z([1, 2, 3]) == 3
  assert size([1, 2, 3]) == 3
  assert every(fn(v) v > 0 end, [1, 2, 3]) == true
  assert box_around([[1, 2], [3, 0]]) == [[1, 3], [0, 2]]
  assert sabi::valid_ident?("OPERATOR_ALIASES") == true
  assert life_step([[0, 0], [0, 0]]) == [[0, 0], [0, 0]]
  assert to_hex(255) == "ff"
  assert age_s(3600000) == "1h0m"
  assert hash_message("") ==
    "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
  assert contains([1, 2, 3], 2) == true
  assert suppress_small(3, 5) == nil
  assert near(mean([2, 4, 6]), 4) == true
  assert zu_num(1.5) == "1.5"
  assert get(
    tehai::machine("ssh://root@plo x86_64-linux - 8 8 - - -"),
    :host
  ) ==
    "plo"
  assert get(souji::parse(["nix"]), :days) == 14
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
