# Threshold signing, the mpc_threshold capability: RFC 9591 FROST over
# Ed25519. Each row is host() and states what blue promises with host
# randomness, so no row reads a key or a signature byte for byte: a group
# deals its shares, any k of them sign a message ed25519_verify accepts, fewer
# than k are refused, nonces sign once, DKG makes one group for every
# participant, and a share survives its export. The breach, the seeded
# provider and the tameshi round trips run in crates/blue-lang-cli/tests/synod.rs.

row(
  "threshold.deal.shapes",
  join_lines(
    [
      "g = threshold_deal(2, 3)",
      "[length(g.shares), g.min, g.max, length(g.key), map((s) -> s.participant, g.shares), every?((s) -> s.key == g.key, g.shares)]"
    ]
  ),
  value("[3, 2, 3, 64, [1, 2, 3], true]"),
  covers("builtin:threshold_deal"),
  host()
)

row(
  "threshold.deal.below_two_refuses",
  "threshold_deal(1, 3)",
  fails(:eval, "2 <= k <= n"),
  host()
)

row(
  "threshold.sign.two_of_three_verifies",
  join_lines(
    [
      "g = threshold_deal(2, 3)",
      "a = threshold_commit(g.shares[0], \"m\")",
      "c = threshold_commit(g.shares[2], \"m\")",
      "cs = [a.commitment, c.commitment]",
      "parts = [threshold_sign(g.shares[0], a.nonces, \"m\", cs), threshold_sign(g.shares[2], c.nonces, \"m\", cs)]",
      "sig = threshold_aggregate(g.group, \"m\", cs, parts)",
      "[map((p) -> p.participant, parts), length(sig), ed25519_verify(g.key, \"m\", sig), ed25519_verify(g.key, \"n\", sig)]"
    ]
  ),
  value("[[1, 3], 128, true, false]"),
  covers("builtin:threshold_commit"),
  covers("builtin:threshold_sign"),
  covers("builtin:threshold_aggregate"),
  host()
)

row(
  "threshold.aggregate.one_share_is_refused",
  join_lines(
    [
      "g = threshold_deal(2, 3)",
      "a = threshold_commit(g.shares[0], \"m\")",
      "b = threshold_commit(g.shares[1], \"m\")",
      "cs = [a.commitment, b.commitment]",
      "part = threshold_sign(g.shares[0], a.nonces, \"m\", cs)",
      "",
      "begin",
      "  threshold_aggregate(g.group, \"m\", cs, [part])",
      "rescue :refused as e",
      "  [e.kind, e.data.have, e.data.need]",
      "end"
    ]
  ),
  value("[:refused, 1, 2]"),
  host()
)

row(
  "threshold.sign.nonces_sign_once",
  join_lines(
    [
      "g = threshold_deal(2, 2)",
      "a = threshold_commit(g.shares[0], \"m\")",
      "b = threshold_commit(g.shares[1], \"m\")",
      "cs = [a.commitment, b.commitment]",
      "threshold_sign(g.shares[0], a.nonces, \"m\", cs)",
      "",
      "begin",
      "  threshold_sign(g.shares[0], a.nonces, \"m\", cs)",
      "rescue :refused as e",
      "  [e.kind, contains?(e.message, \"already signed once\")]",
      "end"
    ]
  ),
  value("[:refused, true]"),
  host()
)

row(
  "threshold.dkg.three_rounds_one_group",
  join_lines(
    [
      "starts = map((p) -> threshold_dkg_start(p, 2, 3), [1, 2, 3])",
      "bs = map((s) -> s.broadcast, starts)",
      "xs = map((s) -> threshold_dkg_exchange(s.secret, bs), starts)",
      "sends = flat_map(xs, (x) -> x.sends)",
      "done = map((x) -> threshold_dkg_finish(x.secret, bs, sends), xs)",
      "b = threshold_commit(done[1].share, \"m\")",
      "c = threshold_commit(done[2].share, \"m\")",
      "cs = [b.commitment, c.commitment]",
      "parts = [threshold_sign(done[1].share, b.nonces, \"m\", cs), threshold_sign(done[2].share, c.nonces, \"m\", cs)]",
      "sig = threshold_aggregate(done[0].group, \"m\", cs, parts)",
      "[length(sends), every?((d) -> d.key == done[0].key, done), map((d) -> d.share.participant, done), ed25519_verify(done[0].key, \"m\", sig)]"
    ]
  ),
  value("[6, true, [1, 2, 3], true]"),
  covers("builtin:threshold_dkg_start"),
  covers("builtin:threshold_dkg_exchange"),
  covers("builtin:threshold_dkg_finish"),
  host()
)

row(
  "threshold.share.export_import_round_trip",
  join_lines(
    [
      "g = threshold_deal(2, 3)",
      "h = threshold_share_export(g.shares[1])",
      "t = threshold_share_import(h)",
      "[t.participant, t.min, t.key == g.key, threshold_share_export(t) == h, contains?(to_s(g.shares[1]), h)]"
    ]
  ),
  value("[2, 2, true, true, false]"),
  covers("builtin:threshold_share_export"),
  covers("builtin:threshold_share_import"),
  host()
)

row(
  "threshold.share_import.not_a_share",
  "threshold_share_import(\"00ff\")",
  fails(:eval, "the share does not decode"),
  host()
)
