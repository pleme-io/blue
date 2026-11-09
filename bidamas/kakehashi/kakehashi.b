@moduledoc """
kakehashi (架け橋, a bridge) — blue speaks Nix, Nix runs blue, and a rebuild does
only the work that changed.

Six levels: `kakehashi/nikkusu` (Nix as verbs), `kakehashi/hyouka` (evaluation),
`kakehashi/kirikae` (switching a system), `kakehashi/kijun` (the fleet repo
standard), `kakehashi/tehai` (live builders and substituters) and
`kakehashi/souji` (cleaning stores and targets). The root defines nothing; a
`use("kakehashi")` brings all six.

    kakehashi::hyouka::installable(".", "x") #=> ".#x"
"""

test "the root reaches each of its levels by the path below it"
  assert kakehashi::kijun::fleet_repo(1)[:standard] == "fleet-repo"
  assert kakehashi::hyouka::installable(".", "x") == ".#x"
  assert kakehashi::tehai::le_bytes(258, 3) == [2, 1, 0]
  assert procedure?(kakehashi::souji::perform)
end
