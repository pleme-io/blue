# retsu (列) — lists.
#
# Depends on `kazu` — the first bidama-to-bidama dependency, which is how the
# distribution proves `needs(...)` resolves rather than merely parsing.

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
