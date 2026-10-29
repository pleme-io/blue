use("deeta", [:pretty])
use("kyohi", %i[kinds refusal standing])
use("moji", [:made_of])
use("retsu", %i[contains first flat_map is_empty size])
use("ronri", [:every])
use("shuugou", [:ordered])

def sdk()
  "onepassword-sdk-go v0.4.1"
end

def permission(name, bit, requires, settable)
  {name:, bit:, requires:, settable:}
end

def permissions()
  [
    permission("read_items", 32, [], true),
    permission("create_items", 128, ["read_items"], true),
    permission("reveal_item_password", 16, ["read_items"], true),
    permission("update_items", 64, %w[read_items reveal_item_password], true),
    permission(
      "archive_items",
      256,
      %w[read_items reveal_item_password update_items],
      true
    ),
    permission(
      "delete_items",
      512,
      %w[read_items reveal_item_password update_items],
      true
    ),
    permission(
      "update_item_history",
      1024,
      %w[read_items reveal_item_password],
      true
    ),
    permission("import_items", 2_097_152, %w[read_items create_items], true),
    permission(
      "export_items",
      4_194_304,
      %w[read_items reveal_item_password update_item_history],
      true
    ),
    permission(
      "send_items",
      1_048_576,
      %w[read_items reveal_item_password update_item_history],
      true
    ),
    permission(
      "print_items",
      8_388_608,
      %w[read_items reveal_item_password update_item_history],
      true
    ),
    permission("manage_vault", 2, [], true),
    permission("recover_vault", 1, [], false)
  ]
end

def bundles()
  [
    ["view", %w[read_items reveal_item_password update_item_history]],
    [
      "edit",
      %w[
        create_items
        update_items
        archive_items
        delete_items
        import_items
        export_items
        send_items
        print_items
      ]
    ],
    ["manage", ["manage_vault"]]
  ]
end

def bundle(name)
  first(filter((b) -> first(b) == name, bundles))[1]
end

def lookup(name)
  first(filter((p) -> p.name == name, permissions))
end

def names()
  map((p) -> p.name, permissions)
end

def settable_names()
  map((p) -> p.name, filter((p) -> p.settable, permissions))
end

def sorted(xs)
  ordered(xs)
end

def encode(ns)
  reduce((acc, n) -> acc + lookup(n).bit, 0, distinct(ns))
end

def decode(bits)
  sorted(map((p) -> p.name, filter((p) -> has_bit?(bits, p.bit), permissions)))
end

def has_bit?(bits, bit)
  floor(bits / bit) % 2 == 1
end

def missing(have, wanted)
  filter((w) -> not contains(have, w), wanted)
end

def closure_whys(ns)
  have = sorted(ns)
  flat_map(have, (n) -> name_whys(have, n))
end

def name_whys(have, n)
  if not contains(names, n)
    ["\"#{n}\" is not a permission; legal: #{join(settable_names, ", ")}"]
  elsif not lookup(n).settable
    ["\"#{n}\" belongs to the built-in recovery group and cannot be declared"]
  elsif not is_empty(missing(have, lookup(n).requires))
    ["\"#{n}\" requires #{join(missing(have, lookup(n).requires), ", ")}"]
  else
    []
  end
end

def bundle_whys(have, b)
  inside = filter((m) -> contains(have, m), b[1])
  outside = missing(have, b[1])
  if is_empty(inside) or is_empty(outside)
    []
  else
    [
      "a Teams account grants the \"#{first(b)}\" bundle whole: add #{join(outside, ", ")} or remove #{join(inside, ", ")}"
    ]
  end
end

def teams_whys(ns)
  have = sorted(ns)
  covered = flat_map(bundles, (b) -> b[1])
  partial = flat_map(bundles, (b) -> bundle_whys(have, b))
  stray = map(
    (n) -> "\"#{n}\" is not part of any Teams bundle",
    filter((n) -> not contains(covered, n), have)
  )
  edit_alone = if contains(have, "create_items") and
      not contains(have, "read_items")
    ["the \"edit\" bundle requires the \"view\" bundle"]
  else
    []
  end
  append(partial, stray, edit_alone)
end

def tiers()
  [
    ["individual", 1000, false],
    ["families", 1000, false],
    ["teams", 5000, true],
    ["business", 50000, true]
  ]
end

def tier_row(t)
  first(filter((r) -> first(r) == t, tiers))
end

def tier_names()
  map(first, tiers)
end

def daily_limit(t)
  tier_row(t)[1]
end

def grants_allowed?(t)
  tier_row(t)[2]
end

def interval_s(t, reads)
  -floor(-(86400 * reads) / (daily_limit(t) * 0.5))
end

def key_chars()
  "abcdefghijklmnopqrstuvwxyz0123456789_"
end

def key?(v)
  string?(v) and length(v) > 0 and made_of(v, key_chars)
end

def group_id?(v)
  string?(v) and
    length(v) > 0 and
    made_of(v, "abcdefghijklmnopqrstuvwxyz0123456789")
end

def vault(key, title)
  {
    key:,
    title:,
    description: "",
    allow_admins_access: true,
    force_destroy: false
  }
end

def described(v, description)
  assoc(v, :description, description)
end

def admins_barred(v)
  assoc(v, :allow_admins_access, false)
end

def destroyable(v)
  assoc(v, :force_destroy, true)
end

def grant(vault_key, group_id, ns)
  {vault: vault_key, group: group_id, permissions: ns}
end

def account(tier, vaults, grants)
  {tier:, vaults:, grants:}
end

def fault(cond, r)
  if cond
    r
  else
    []
  end
end

def listed(ns)
  if list?(ns)
    ns
  else
    []
  end
end

def teams_refusals(tier, at, ns)
  if tier == "teams"
    map((w) -> refusal(:teams_bundle, "#{at}: #{w}"), teams_whys(listed(ns)))
  else
    []
  end
end

def vault_whys(v)
  append(
    fault(not key?(v[:key]), ["#{v[:key]} is not a key of [a-z0-9_]"]),
    fault(
      not (string?(v[:title]) and length(v[:title]) > 0),
      ["a vault needs a title"]
    ),
    fault(not string?(v[:description]), ["a description is text"]),
    fault(
      not boolean?(v[:allow_admins_access]),
      ["allow_admins_access is true or false"]
    ),
    fault(not boolean?(v[:force_destroy]), ["force_destroy is true or false"])
  )
end

def vault_refusals(vs)
  map(
    fn(i)
      v = vs[i]
      earlier = map((w) -> w[:key], take(i, vs))
      own = map(
        (w) -> refusal(:bad_vault, "vault #{v[:key]}: #{w}"),
        vault_whys(v)
      )
      dup = if contains(earlier, v[:key])
        [refusal(:duplicate_vault, "vault #{v[:key]} is declared twice")]
      else
        []
      end
      append(own, dup)
    end,
    range(0, size(vs))
  )
end

def grant_name(g)
  "#{g[:vault]}__#{g[:group]}"
end

def grant_refusals(tier, keys, gs)
  map(
    fn(i)
      g = gs[i]
      at = "grant #{grant_name(g)}"
      earlier = map(grant_name, take(i, gs))
      ns = g[:permissions]
      append(
        fault(
          not grants_allowed?(tier),
          [
            refusal(
              :tier_forbids_grants,
              "#{at}: a #{tier} account has no group vault access"
            )
          ]
        ),
        fault(
          not contains(keys, g[:vault]),
          [refusal(:unknown_vault, "#{at}: no accepted vault #{g[:vault]}")]
        ),
        fault(
          not group_id?(g[:group]),
          [refusal(:bad_grant, "#{at}: #{g[:group]} is not a group id")]
        ),
        fault(
          not list?(ns),
          [refusal(:bad_grant, "#{at}: permissions is a list")]
        ),
        map(
          (w) -> refusal(:bad_permissions, "#{at}: #{w}"),
          closure_whys(listed(ns))
        ),
        teams_refusals(tier, at, ns),
        fault(
          contains(earlier, grant_name(g)),
          [refusal(:duplicate_grant, "#{at} is declared twice")]
        )
      )
    end,
    range(0, size(gs))
  )
end

def judge(a)
  tier = a[:tier]
  if not contains(tier_names, tier)
    {
      tier: nil,
      vaults: [],
      grants: [],
      refusals: [
        refusal(
          :unknown_tier,
          "#{tier} is not one of #{join(tier_names, ", ")}"
        )
      ]
    }
  else
    vs = a[:vaults] or []
    vmarks = vault_refusals(vs)
    kept = standing(vs, vmarks)
    gs = a[:grants] or []
    gmarks = grant_refusals(tier, map((v) -> v[:key], kept), gs)
    {
      tier:,
      vaults: kept,
      grants: standing(gs, gmarks),
      refusals: append(flat_map(vmarks, (r) -> r), flat_map(gmarks, (r) -> r))
    }
  end
end

def accepted(a)
  j = judge(a)
  {tier: j[:tier], vaults: j[:vaults], grants: j[:grants]}
end

def reads(a)
  j = judge(a)
  size(j[:vaults]) + size(j[:grants]) + 1
end

def reconcile_interval_s(a)
  j = judge(a)
  if j[:tier].nil?
    nil
  else
    interval_s(j[:tier], reads(a))
  end
end

def vault_block(v)
  {
    title: v[:title],
    description: v[:description],
    allow_admins_access: v[:allow_admins_access],
    force_destroy: v[:force_destroy]
  }
end

def grant_block(g)
  {
    vault_id: "${opadmin_vault.#{g[:vault]}.id}",
    group_id: g[:group],
    permissions: sorted(g[:permissions])
  }
end

def keyed(rows, name_of, block_of)
  reduce((m, r) -> assoc(m, name_of(r), block_of(r)), {}, rows)
end

def resources(j)
  r = {}
  r2 = if is_empty(j[:vaults])
    r
  else
    assoc(r, :opadmin_vault, keyed(j[:vaults], (v) -> v[:key], vault_block))
  end
  if is_empty(j[:grants])
    r2
  else
    assoc(
      r2,
      :opadmin_group_vault_access,
      keyed(j[:grants], grant_name, grant_block)
    )
  end
end

def terraform(a)
  j = judge(a)
  base = {
    terraform: {
      required_providers: {
        opadmin: {source: "registry.opentofu.org/pleme-io/opadmin"},
        onepassword: {source: "1Password/onepassword"}
      }
    },
    provider: {opadmin: {}, onepassword: {}}
  }
  res = resources(j)
  if res == {}
    base
  else
    assoc(base, :resource, res)
  end
end

def to_json(a)
  json_stringify(terraform(a))
end

def permissions_doc()
  {
    source: "kinko",
    sdk:,
    permissions: map(
      fn(p)
        {name: p.name, bit: p.bit, requires: p.requires, settable: p.settable}
      end,
      permissions
    ),
    teams_bundles: {
      view: bundle("view"),
      edit: bundle("edit"),
      manage: bundle("manage")
    }
  }
end

def permissions_json()
  pretty(permissions_doc)
end

def unreachable()
  [
    [
      "users",
      "no API a reconciler can hold: the SDK has none, SCIM is Business-only with a deprecated bridge, op needs a human session",
      "a user API on the SDK or Connect"
    ],
    [
      "groups",
      "the SDK reads groups only; create, rename and delete need op or SCIM",
      "group CRUD on the SDK"
    ],
    [
      "group membership",
      "membership changes need op or SCIM",
      "membership on the SDK"
    ],
    [
      "built-in vaults",
      "a service account never reaches Personal, Private, Employee or the default Shared vault",
      "none: a vendor rule"
    ],
    [
      "vaults the service account did not create",
      "a service account updates, deletes and grants only on vaults it created; its access is immutable",
      "adoption of an existing vault by a service account"
    ],
    [
      "account policy",
      "sign-in, firewall, 2FA, recovery, roles and billing have no API on any surface",
      "an account settings API"
    ],
    [
      "allow_admins_access read-back",
      "the SDK's Vault carries no such field, so the provider keeps the value it wrote",
      "the field on Vault"
    ]
  ]
end

def unreachable_md()
  rows = map((r) -> "| #{r[0]} | #{r[1]} | #{r[2]} |", unreachable)
  head = [
    "# What opadmin cannot reach",
    "",
    "Generated by the kinko bidama (blue). Do not edit by hand.",
    "",
    "| Concern | Why | What would have to exist |",
    "|---|---|---|"
  ]
  unlines([join(append(head, rows), line_break)])
end

def write_outputs(root)
  write_file("#{root}/internal/permissions/permissions.json", permissions_json)
  write_file("#{root}/UNREACHABLE.md", unreachable_md)
  nil
end

def main()
  root = first(argv)
  if root.nil?
    raise(:usage, "kinko <onepassword-admin checkout>")
  end
  write_outputs(root)
end

def example()
  account(
    "business",
    [vault("infra", "Infra"), described(vault("ci", "CI"), "CI secrets")],
    [
      grant(
        "infra",
        "ops",
        %w[read_items reveal_item_password update_item_history]
      )
    ]
  )
end

test "an empty account on a known tier stands, empty, with only the providers"
  a = account("families", [], [])
  assert judge(a).refusals == []
  assert accepted(a)[:vaults] == []
  assert terraform(a)[:resource].nil?
  assert to_json(a) ==
    "{\"provider\":{\"onepassword\":{},\"opadmin\":{}},\"terraform\":{\"required_providers\":{\"onepassword\":{\"source\":\"1Password/onepassword\"},\"opadmin\":{\"source\":\"registry.opentofu.org/pleme-io/opadmin\"}}}}"
  assert kinds(judge(account("enterprise", [], [])).refusals) == [:unknown_tier]
end

test "the table covers every SDK bit once and round-trips"
  bits = map((p) -> p.bit, permissions)
  assert size(distinct(bits)) == 13
  assert reduce((a, b) -> a + b, 0, bits) == 15_730_675
  assert decode(encode(names)) == sorted(names)
  assert decode(0) == []
  assert encode(
    %w[read_items reveal_item_password update_items delete_items]
  ) == 624
  assert decode(624) ==
    %w[delete_items read_items reveal_item_password update_items]
  assert every((p) -> every((r) -> contains(names, r), p.requires), permissions)
end

test "closure refuses a permission without what it requires, and names what is missing"
  assert closure_whys([]) == []
  assert closure_whys(["read_items"]) == []
  assert closure_whys(["manage_vault"]) == []
  assert closure_whys(["delete_items"]) ==
    ["\"delete_items\" requires read_items, reveal_item_password, update_items"]
  assert closure_whys(
    %w[read_items reveal_item_password update_items delete_items]
  ) == []
  assert size(closure_whys(["recover_vault"])) == 1
  assert size(closure_whys(["bogus"])) == 1
  assert every(
    (p) -> closure_whys(append([p.name], p.requires)) == [],
    filter((p) -> p.settable, permissions)
  )
end

test "Teams grants whole bundles, edit only with view"
  view = bundle("view")
  edit = append(view, bundle("edit"))
  assert teams_whys(view) == []
  assert teams_whys(edit) == []
  assert teams_whys(append(edit, bundle("manage"))) == []
  assert closure_whys(append(edit, bundle("manage"))) == []
  assert size(teams_whys(["read_items"])) == 1
  assert teams_whys(bundle("edit")) != []
  assert teams_whys(["recover_vault"]) != []
end

test "a bad entry is refused alone and its valid siblings stand"
  a = account(
    "business",
    [
      vault("infra", "Infra"),
      vault("infra", "Again"),
      vault("Bad Key", "X"),
      vault("ci", "")
    ],
    [
      grant("infra", "ops", ["read_items"]),
      grant("ghost", "ops", ["read_items"]),
      grant("infra", "devs", ["delete_items"]),
      grant("infra", "ops", ["read_items"])
    ]
  )
  assert kinds(judge(a).refusals) ==
    %i[
      duplicate_vault
      bad_vault
      bad_vault
      unknown_vault
      bad_permissions
      duplicate_grant
    ]
  assert map((v) -> v[:key], accepted(a)[:vaults]) == ["infra"]
  assert map(grant_name, accepted(a)[:grants]) == ["infra__ops"]
end

test "a tier without group access refuses every grant and keeps every vault"
  a = account(
    "families",
    [vault("home", "Home")],
    [grant("home", "family", ["read_items"])]
  )
  assert kinds(judge(a).refusals) == [:tier_forbids_grants]
  assert size(accepted(a)[:vaults]) == 1
  t = account(
    "teams",
    [vault("home", "Home")],
    [grant("home", "family", ["read_items"])]
  )
  assert kinds(judge(t).refusals) == [:teams_bundle]
end

test "the projection carries what stands, field for field"
  t = terraform(example)
  assert t[:resource][:opadmin_vault]["ci"] ==
    {
      title: "CI",
      description: "CI secrets",
      allow_admins_access: true,
      force_destroy: false
    }
  assert t[:resource][:opadmin_group_vault_access]["infra__ops"] ==
    {
      vault_id: "${opadmin_vault.infra.id}",
      group_id: "ops",
      permissions: %w[read_items reveal_item_password update_item_history]
    }
  assert accepted(accepted(example)) == accepted(example)
end

test "the reconcile interval follows the tier's daily quota with half in reserve"
  assert interval_s("families", 16) == 2765
  assert interval_s("business", 16) == 56
  assert interval_s("teams", 1) == 35
  assert reconcile_interval_s(account("nope", [], [])).nil?
  assert reconcile_interval_s(example) == 14
end

test "the generated documents carry every row"
  assert size(permissions_doc[:permissions]) == 13
  assert size(split(unreachable_md, line_break)) == size(unreachable) + 7
end
