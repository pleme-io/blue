@moduledoc """
fuuin (封印) — k-of-n threshold signing: a group whose key no one share holds, signed by any k of its n shares in two rounds, RFC 9591 FROST over Ed25519.

The words stand on the runtime's `threshold_*` host words, which the mpc_threshold capability holds; `virtualize(:mpc_threshold, {using: :seeded, seed: "s"})` draws every key and nonce from a stream keyed by the seed, so a run signs the same way twice. A share prints its participant, its group's key and its threshold, and its secret as `foreign`. The signature `combine` answers is ordinary Ed25519, so `shomei::verify?(data, signature, group.key)` checks it with no capability at all.

`generate` deals a group from one trusted dealer, which holds the whole key while it runs. A group no process ever holds whole comes from `threshold_dkg_start`, `threshold_dkg_exchange` and `threshold_dkg_finish`, one call each per participant.

    size(generate(:threshold, {min: 2, max: 3}).shares) #=> 3
"""

use("kyohi", [:raised])
use("moji", [:checked])
use("retsu", %i[first last size])
use("shomei", [:verify?])

@doc """
generate: a new threshold group from secure entropy, `max` shares of which any `min` sign together: {group:, key:, min:, max:, shares:}. :threshold is the one kind; another kind, or a threshold outside 2 <= min <= max, raises :bad_option.

    generate(:threshold, {min: 2, max: 3}).min #=> 2
"""
def generate(kind, opts)
  checked(opts, %i[max min])
  if kind != :threshold
    raise(:bad_option, "generate makes :threshold groups, got #{to_s(kind)}")
  end
  threshold_deal(opts[:min], opts[:max])
end

@doc """
offer: one share's first round toward signing data, {nonces:, commitment:}. The commitment goes to whoever combines the signature; the nonces stay with the share and sign once.

    offer(first(generate(:threshold, {min: 2, max: 3}).shares), "m").commitment.participant #=> 1
"""
def offer(share, data)
  threshold_commit(share, data)
end

@doc """
sign: one share's signature share over data, {participant:, hex:}, from the nonces its offer kept and the commitments of the signers, at least the group's k with its own among them. The nonces are spent, so a second sign with them raises :refused.

    raised(() -> sign("m", first(generate(:threshold, {min: 2, max: 3}).shares), {nonces: :none, commitments: []})) #=> :bad_option
"""
def sign(data, share, opts)
  checked(opts, %i[commitments nonces])
  threshold_sign(share, opts[:nonces], data, opts[:commitments])
end

@doc """
combine: the group's Ed25519 signature over data, in hex, from at least k signature shares and the commitments they signed for, checked under the group's key before it is answered. Fewer than k raises :refused, and a share that does not verify raises :tampered naming its participant.

    raised(() -> combine([], {group: generate(:threshold, {min: 2, max: 3}).group, data: "m", commitments: []})) #=> :refused
"""
def combine(parts, opts)
  checked(opts, %i[commitments data group])
  threshold_aggregate(opts[:group], opts[:data], opts[:commitments], parts)
end

test "any two shares of a 2-of-3 group sign, and the signature verifies as Ed25519 under the group key"
  g = generate(:threshold, {min: 2, max: 3})
  signed_by = fn(picks, data)
    offers = map((p) -> offer(g.shares[p - 1], data), picks)
    commitments = map((o) -> o.commitment, offers)
    parts = map(
      fn(i)
        sign(
          data,
          g.shares[picks[i] - 1],
          {nonces: offers[i].nonces, commitments:}
        )
      end,
      range(size(picks))
    )
    combine(parts, {group: g.group, data:, commitments:})
  end
  assert size(g.shares) == 3
  assert map((s) -> s.participant, g.shares) == [1, 2, 3]
  assert every?(
    fn(picks)
      sig = signed_by(picks, "release v1")
      verify?("release v1", sig, g.key) and
        not verify?("release v2", sig, g.key)
    end,
    [[1, 2], [1, 3], [2, 3], [3, 1, 2]]
  )
end

test "one share alone cannot sign: its commitment is below the threshold and its part alone does not combine"
  g = generate(:threshold, {min: 2, max: 3})
  s = first(g.shares)
  o = offer(s, "m")
  assert raised(
    () -> sign("m", s, {nonces: o.nonces, commitments: [o.commitment]})
  ) == :refused
  a = offer(s, "m")
  b = offer(last(g.shares), "m")
  both = [a.commitment, b.commitment]
  part = sign("m", s, {nonces: a.nonces, commitments: both})
  assert raised(
    () -> combine([part], {group: g.group, data: "m", commitments: both})
  ) == :refused
  assert raised(
    () -> combine([], {group: g.group, data: "m", commitments: []})
  ) == :refused
end

test "nonces sign once, and only for the data and the share that made them"
  g = generate(:threshold, {min: 2, max: 3})
  s = first(g.shares)
  t = last(g.shares)
  a = offer(s, "m")
  b = offer(t, "m")
  both = [a.commitment, b.commitment]
  sign("m", s, {nonces: a.nonces, commitments: both})
  assert raised(() -> sign("m", s, {nonces: a.nonces, commitments: both})) ==
    :refused
  c = offer(s, "m")
  assert raised(
    () -> sign("other", s, {nonces: c.nonces, commitments: both})
  ) == :refused
  d = offer(s, "m")
  assert raised(() -> sign("m", t, {nonces: d.nonces, commitments: both})) ==
    :refused
end

test "a signature share from another session is named as the one that does not verify"
  g = generate(:threshold, {min: 2, max: 3})
  s = first(g.shares)
  t = last(g.shares)
  a = offer(s, "m")
  b = offer(t, "m")
  both = [a.commitment, b.commitment]
  good = sign("m", s, {nonces: a.nonces, commitments: both})
  c = offer(s, "m")
  d = offer(t, "m")
  stray = sign(
    "m",
    t,
    {nonces: d.nonces, commitments: [c.commitment, d.commitment]}
  )
  e = begin
    combine([good, stray], {group: g.group, data: "m", commitments: both})
  rescue :tampered as caught
    caught
  end
  assert e.kind == :tampered
  assert e.data.culprits == [3]
end

test "generate refuses a kind it does not make and a threshold that is no threshold"
  assert raised(() -> generate(:ed25519, {min: 2, max: 3})) == :bad_option
  assert raised(() -> generate(:threshold, {min: 1, max: 3})) == :bad_option
  assert raised(() -> generate(:threshold, {min: 4, max: 3})) == :bad_option
  assert raised(() -> generate(:threshold, {min: 2, max: 3, k: 2})) ==
    :bad_option
end

test "a share prints its participant and key and never its secret"
  g = generate(:threshold, {min: 2, max: 3})
  s = first(g.shares)
  whole = threshold_share_export(s)
  assert contains?(to_s(s), "secret: foreign")
  assert not contains?(to_s(s), whole)
  assert s.key == g.key
  assert threshold_share_import(whole).participant == 1
end
