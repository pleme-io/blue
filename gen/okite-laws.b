use("okite")
use("retsu", [:size])

# The second enforcer of blue's decisions, independent of okite's own test
# block: a flake check (the root Bluefile's check()), so weakening either one
# alone leaves the other failing. heni found the gap on 2026-09-27: turning
# okite's enforcement assertion into `assert true` survived.

test "every blue decision has a law, and every law holds"
  assert okite::failures() == []
  assert size(okite::decisions()) >= 12
end
