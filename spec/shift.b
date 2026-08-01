# The blueshift, observable from inside the language.
#
# This file is at the `annotated` rung: `shifted` carries types, `loose` does
# not. `blue shift spec/shift.b` reports exactly that, and names `loose` as what
# is holding it back.
#
# Blue is the only language that can report this, because blueshift is its own
# model of itself — the continuum is the design, not a lint.

def shifted(n: Int) -> Int
  n * 2
end
def loose(n)
  n * 3
end
test "both rungs run the same way"
  assert shifted(2) == 4
  assert loose(2) == 6
end
test "annotating does not change the answer"
  assert shifted(5) == loose(5) - 5
end
