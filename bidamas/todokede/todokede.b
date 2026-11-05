@moduledoc """
todokede (届出, filings) — what a person or a company declares as entries.

Five levels: `todokede/jitaku` (a home: site, delivery, exposure, components),
`todokede/kurashi` (a desktop seat's world), `todokede/motenashi` (a launcher's
world), `todokede/empresa` (a company: domains, mail, sites, a GitHub org) and
`todokede/kinko` (a 1Password account: tier, vaults, grants). The root defines
nothing; a `use("todokede")` brings all five.
"""

test "the root reaches each of its levels by the path below it"
  assert jitaku::to_json([]) == "{\"enable\":true}"
  assert kinko::interval_s("families", 16) == 2765
  assert empresa::slug?("acme-org")
  assert member?(:filesystem, kurashi::capabilities)
  assert member?(:next, motenashi::actions)
end
