# retsu (列) — lists.
#
# Depends on `kazu`, and now SAYS so in code. The manifest declared
# needs("kazu", "^0.1") from the day this package was seeded, but the language
# had no import form, so nothing consumed it: the edge was described by the
# Bluefile, the resolver, the git registry and a nix derivation, and traversed
# by none of them.
#
# `use("kazu")` is that edge made real. `clamped_sum` below calls kazu's
# `clamp`, so if the import stops working this package stops evaluating — which
# is the only way a dependency proves it is one.
use("kazu")

def sum_to(n)
  if n < 1
    0
  else
    n + sum_to(n - 1)
  end
end

def count_down(n)
  if n < 1
    0
  else
    count_down(n - 1)
  end
end

# Sum 1..n, held inside a range — the distribution's one cross-package call.
#
# It exists to be a USE of kazu rather than a re-implementation of it: writing
# a local `clamp` here would leave the dependency decorative again, which is
# the exact state this package just left.
def clamped_sum(n, lo, hi)
  clamp(sum_to(n), lo, hi)
end
