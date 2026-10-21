use("deeta", [:pretty])
use("kyohi", [:kinds, :refusal, :standing])
use("moji", [:made_of])
use("retsu", [:contains, :first, :flat_map, :is_empty, :last, :size])
use("ronri", [:every])

def slug_chars()
  "abcdefghijklmnopqrstuvwxyz0123456789-"
end

def repo_chars()
  "abcdefghijklmnopqrstuvwxyz0123456789-_."
end

def path_chars()
  "abcdefghijklmnopqrstuvwxyz0123456789-_./"
end

def roles()
  [:primary, :secondary]
end

def kinds_of_site()
  [:static, :service]
end

def gates()
  [:proxy, :app]
end

def visibilities()
  [:public, :private]
end

def dns_hosts()
  [:route53]
end

def permissions()
  [
    [:read, "pull"],
    [:triage, "triage"],
    [:write, "push"],
    [:maintain, "maintain"],
    [:admin, "admin"]
  ]
end

def presets()
  {
    google: {
      mx: [[1, "smtp.google.com."]],
      spf: "v=spf1 include:_spf.google.com ~all",
      dkim: [["google._domainkey", "TXT", "PENDING-google-dkim"]],
      verify: "PENDING-google-verification"
    },
    proton: {
      mx: [[10, "mail.protonmail.ch."], [20, "mailsec.protonmail.ch."]],
      spf: "v=spf1 include:_spf.protonmail.ch ~all",
      dkim: [
        ["protonmail._domainkey", "CNAME", "PENDING-proton-dkim1"],
        ["protonmail2._domainkey", "CNAME", "PENDING-proton-dkim2"],
        ["protonmail3._domainkey", "CNAME", "PENDING-proton-dkim3"]
      ],
      verify: "PENDING-proton-verification"
    },
    fastmail: {
      mx: [
        [10, "in1-smtp.messagingengine.com."],
        [20, "in2-smtp.messagingengine.com."]
      ],
      spf: "v=spf1 include:spf.messagingengine.com ~all",
      dkim: [
        ["fm1._domainkey", "CNAME", "fm1.{domain}.dkim.fmhosted.com."],
        ["fm2._domainkey", "CNAME", "fm2.{domain}.dkim.fmhosted.com."],
        ["fm3._domainkey", "CNAME", "fm3.{domain}.dkim.fmhosted.com."]
      ],
      verify: ""
    }
  }
end

def preset_names()
  [:google, :proton, :fastmail]
end

def text?(v)
  string?(v) and length(v) > 0
end

def slug?(v)
  text?(v) and
    made_of(v, slug_chars) and
    not starts_with?(v, "-") and
    not ends_with?(v, "-")
end

def domain?(v)
  text?(v) and size(split(v, ".")) >= 2 and every(slug?, split(v, "."))
end

def repo_name?(v)
  text?(v) and made_of(v, repo_chars) and v != "." and v != ".."
end

def path_prefix?(v)
  text?(v) and
    starts_with?(v, "/") and
    made_of(v, path_chars) and
    (v == "/" or not ends_with?(v, "/"))
end

def fault(cond, r)
  if cond
    r
  else
    []
  end
end

def listed(v)
  if list?(v)
    v
  else
    []
  end
end

def if_ok(ok, v, otherwise)
  if ok
    v
  else
    otherwise
  end
end

def flag(b)
  if b
    "true"
  else
    "false"
  end
end

def zone_key(domain)
  replace(domain, ".", "_")
end

def repo_slug(name)
  replace(replace(name, "-", "_"), ".", "_")
end

def team_slug(name)
  replace(name, "-", "_")
end

def domain_whys(d)
  append(
    fault(
      not domain?(get(d, :name)),
      ["#{get(d, :name)} is not a domain name"]
    ),
    fault(
      not contains(roles, get(d, :role)),
      ["role is one of #{join(map(to_s, roles), ", ")}"]
    ),
    fault(
      not contains(dns_hosts, get(d, :dns_host)),
      ["dns_host is one of #{join(map(to_s, dns_hosts), ", ")}"]
    )
  )
end

def domain_refusals(ds)
  map(
    fn(i)
      d = nth(i, ds)
      at = "domain #{get(d, :name)}"
      earlier = map((e) -> get(e, :name), take(i, ds))
      append(
        map((w) -> refusal(:bad_domain, "#{at}: #{w}"), domain_whys(d)),
        fault(
          contains(earlier, get(d, :name)),
          [refusal(:duplicate_domain, "#{at} is declared twice")]
        )
      )
    end,
    range(0, size(ds))
  )
end

def domain_names(ds)
  map((d) -> get(d, :name), ds)
end

def zone_for(ds, host)
  ms = filter((d) -> host == d or ends_with?(host, ".#{d}"), domain_names(ds))
  first(sort_keyed((d) -> -length(d), ms))
end

def site_whys(s)
  prefix = get(s, :path_prefix) or ""
  append(
    fault(not slug?(get(s, :name)), ["name is not a slug"]),
    fault(not list?(get(s, :hosts)), ["hosts is a list"]),
    fault(not domain?(get(s, :origin_host)), ["origin_host is not a hostname"]),
    fault(
      not (prefix == "" or path_prefix?(prefix)),
      ["path_prefix is empty or a path starting with / and not ending with /"]
    ),
    fault(
      not contains(gates, get(s, :gate)),
      ["gate is one of #{join(map(to_s, gates), ", ")}"]
    ),
    fault(
      not contains(kinds_of_site, get(s, :kind)),
      ["kind is one of #{join(map(to_s, kinds_of_site), ", ")}"]
    ),
    kind_whys(s)
  )
end

def flake?(v)
  text?(v) and
    starts_with?(v, "github:") and
    contains(split(v, ""), "#") and
    not ends_with?(v, "#")
end

def port?(v)
  integer?(v) and v >= 1 and v <= 65535
end

def kind_whys(s)
  if get(s, :kind) == :service
    append(
      fault(
        get(s, :flake) == nil,
        ["a service needs a flake (github:owner/repo#package)"]
      ),
      fault(
        get(s, :flake) != nil and not flake?(get(s, :flake)),
        ["flake is github:owner/repo#package"]
      ),
      fault(get(s, :port) == nil, ["a service needs a port"]),
      fault(
        get(s, :port) != nil and not port?(get(s, :port)),
        ["port is a number from 1 to 65535"]
      ),
      fault(
        get(s, :health_path) != nil and not path_prefix?(get(s, :health_path)),
        ["health_path is a path starting with /"]
      )
    )
  elsif get(s, :kind) == :static
    fault(get(s, :flake) != nil, ["a static site carries no flake"])
  else
    []
  end
end

def site_refusals(ss)
  map(
    fn(i)
      s = nth(i, ss)
      at = "site #{get(s, :name)}"
      earlier = map((e) -> get(e, :name), take(i, ss))
      append(
        map((w) -> refusal(:bad_site, "#{at}: #{w}"), site_whys(s)),
        fault(
          contains(earlier, get(s, :name)),
          [refusal(:duplicate_site, "#{at} is declared twice")]
        )
      )
    end,
    range(0, size(ss))
  )
end

def host_refusals(ds, claimed, at, h)
  if not domain?(h)
    [refusal(:bad_site, "#{at}: #{h} is not a hostname")]
  elsif zone_for(ds, h) == nil
    [
      refusal(
        :host_outside_domains,
        "#{at}: host #{h} is under no declared domain"
      )
    ]
  elsif contains(claimed, h)
    [refusal(:duplicate_host, "#{at}: host #{h} belongs to an earlier site")]
  else
    []
  end
end

def host_step(ds, at, st, h)
  rs = host_refusals(ds, append(st.claimed, st.good), at, h)
  if is_empty(rs)
    assoc(st, :good, append(st.good, [h]))
  else
    assoc(st, :refusals, append(st.refusals, rs))
  end
end

def site_fold(ds, st, s)
  at = "site #{get(s, :name)}"
  hs = reduce(
    (h_st, h) -> host_step(ds, at, h_st, h),
    {claimed: st.claimed, good: [], refusals: []},
    get(s, :hosts)
  )
  if is_empty(hs.good)
    {
      claimed: st.claimed,
      sites: st.sites,
      refusals: append(
        st.refusals,
        hs.refusals,
        [
          refusal(
            :site_without_domain,
            "#{at}: no host is under a declared domain"
          )
        ]
      )
    }
  else
    {
      claimed: append(st.claimed, hs.good),
      sites: append(st.sites, [assoc(s, :hosts, hs.good)]),
      refusals: append(st.refusals, hs.refusals)
    }
  end
end

def mail_judge(ds, m)
  if m == nil
    {kept: nil, refusals: []}
  elsif get(m, :provider) == :undecided
    {kept: m, refusals: []}
  elsif not contains(preset_names, get(m, :provider))
    {
      kept: nil,
      refusals: [
        refusal(
          :unknown_mail_preset,
          "mail: #{get(m, :provider)} is not one of #{join(map(to_s, preset_names), ", ")} or undecided"
        )
      ]
    }
  elsif not contains(domain_names(ds), get(m, :domain))
    {
      kept: nil,
      refusals: [
        refusal(
          :mail_domain_undeclared,
          "mail: #{get(m, :domain)} is not an accepted domain"
        )
      ]
    }
  else
    {kept: m, refusals: []}
  end
end

def repo_whys(r)
  append(
    fault(not repo_name?(get(r, :name)), ["name is not a repository name"]),
    fault(
      not contains(visibilities, get(r, :visibility)),
      ["visibility is one of #{join(map(to_s, visibilities), ", ")}"]
    ),
    fault(not string?(get(r, :description) or ""), ["description is text"])
  )
end

def repo_refusals(rs)
  map(
    fn(i)
      r = nth(i, rs)
      at = "repo #{get(r, :name)}"
      earlier = map((e) -> repo_slug(to_s(get(e, :name))), take(i, rs))
      append(
        map((w) -> refusal(:bad_repo, "#{at}: #{w}"), repo_whys(r)),
        fault(
          contains(earlier, repo_slug(to_s(get(r, :name)))),
          [refusal(:duplicate_repo, "#{at} is declared twice")]
        )
      )
    end,
    range(0, size(rs))
  )
end

def team_whys(t)
  repos = get(t, :repos) or []
  append(
    fault(not slug?(get(t, :name)), ["name is not a slug"]),
    fault(
      not contains(map(first, permissions), get(t, :permission)),
      [
        "permission is one of #{join(map((p) -> to_s(first(p)), permissions), ", ")}"
      ]
    ),
    fault(
      not (repos == :all or list?(repos)),
      ["repos is a list of repository names or all"]
    )
  )
end

def team_refusals(ts)
  map(
    fn(i)
      t = nth(i, ts)
      at = "team #{get(t, :name)}"
      earlier = map((e) -> get(e, :name), take(i, ts))
      append(
        map((w) -> refusal(:bad_team, "#{at}: #{w}"), team_whys(t)),
        fault(
          contains(earlier, get(t, :name)),
          [refusal(:duplicate_team, "#{at} is declared twice")]
        )
      )
    end,
    range(0, size(ts))
  )
end

def team_repos(t)
  get(t, :repos) or []
end

def grant_refusals(names, t)
  if team_repos(t) == :all
    []
  else
    map(
      fn(n)
        refusal(:unknown_repo, "team #{get(t, :name)}: no accepted repo #{n}")
      end,
      filter((n) -> not contains(names, n), team_repos(t))
    )
  end
end

def trim_team(names, t)
  if team_repos(t) == :all
    t
  else
    assoc(t, :repos, filter((n) -> contains(names, n), team_repos(t)))
  end
end

def flat(marks)
  flat_map((r) -> r, marks)
end

def org_refusals(org, repos, teams)
  if org == nil
    fault(
      not (is_empty(repos) and is_empty(teams)),
      [refusal(:no_github_org, "repos and teams need a github_org")]
    )
  else
    fault(
      not slug?(org),
      [refusal(:bad_slug, "github_org #{org} is not a slug")]
    )
  end
end

def judge(a)
  company = get(a, :company)
  org = get(a, :github_org)
  doms = get(a, :domains) or []
  dmarks = domain_refusals(doms)
  ds = standing(doms, dmarks)
  sites = get(a, :sites) or []
  smarks = site_refusals(sites)
  folded = reduce(
    (st, s) -> site_fold(ds, st, s),
    {claimed: [], sites: [], refusals: []},
    standing(sites, smarks)
  )
  mj = mail_judge(ds, get(a, :mail))
  repos = get(a, :repos) or []
  teams = get(a, :teams) or []
  org_marks = org_refusals(org, repos, teams)
  org_ok = is_empty(org_marks) and org != nil
  held_repos = if_ok(org_ok, repos, [])
  rmarks = repo_refusals(held_repos)
  rs = standing(held_repos, rmarks)
  names = map((r) -> get(r, :name), rs)
  held_teams = if_ok(org_ok, teams, [])
  tmarks = team_refusals(held_teams)
  ts = standing(held_teams, tmarks)
  company_marks = fault(
    not slug?(company),
    [refusal(:bad_slug, "company #{company} is not a slug")]
  )
  {
    accepted: {
      company: if_ok(is_empty(company_marks), company, nil),
      github_org: if_ok(org_ok, org, nil),
      domains: ds,
      mail: mj.kept,
      sites: folded.sites,
      repos: rs,
      teams: map((t) -> trim_team(names, t), ts)
    },
    refused: append(
      company_marks,
      org_marks,
      flat(dmarks),
      flat(smarks),
      folded.refusals,
      mj.refusals,
      flat(rmarks),
      flat(tmarks),
      flat_map((t) -> grant_refusals(names, t), ts)
    )
  }
end

def pending?(value)
  starts_with?(value, "PENDING-")
end

def dns_row(zone, purpose, name, type, value)
  {
    slug: "#{zone}__#{purpose}",
    zone: zone,
    name: name,
    type: type,
    ttl: "3600",
    value: value,
    pending: flag(pending?(value))
  }
end

def mx_rows(z, d, p)
  map(
    fn(i)
      e = nth(i, get(p, :mx))
      dns_row(z, "mx#{i + 1}", d, "MX", "#{first(e)} #{nth(1, e)}")
    end,
    range(0, size(get(p, :mx)))
  )
end

def dkim_rows(z, d, p)
  map(
    fn(i)
      e = nth(i, get(p, :dkim))
      dns_row(
        z,
        "dkim#{i + 1}",
        "#{first(e)}.#{d}",
        nth(1, e),
        replace(nth(2, e), "{domain}", d)
      )
    end,
    range(0, size(get(p, :dkim)))
  )
end

def verify_rows(z, d, p)
  if get(p, :verify) == ""
    []
  else
    [dns_row(z, "verify", d, "TXT", get(p, :verify))]
  end
end

def mail_rows(m)
  if m == nil or get(m, :provider) == :undecided
    []
  else
    d = get(m, :domain)
    z = zone_key(d)
    p = get(presets, get(m, :provider))
    append(
      mx_rows(z, d, p),
      [dns_row(z, "spf", d, "TXT", get(p, :spf))],
      dkim_rows(z, d, p),
      verify_rows(z, d, p),
      [
        dns_row(
          z,
          "dmarc",
          "_dmarc.#{d}",
          "TXT",
          "v=DMARC1; p=none; rua=mailto:dmarc@#{d}"
        )
      ]
    )
  end
end

def zone_rows(ds)
  map(
    fn(d)
      {
        key: zone_key(get(d, :name)),
        name: get(d, :name),
        role: to_s(get(d, :role)),
        dns_host: to_s(get(d, :dns_host))
      }
    end,
    ds
  )
end

def alias_rows(ds, ss)
  flat_map(
    fn(s)
      map(
        fn(h)
          {
            slug: replace(h, ".", "-"),
            site: get(s, :name),
            host: h,
            zone: zone_for(ds, h)
          }
        end,
        get(s, :hosts)
      )
    end,
    ss
  )
end

def service?(s)
  get(s, :kind) == :service
end

def edge_site_rows(ss)
  map(
    fn(s)
      {
        site: get(s, :name),
        origin_host: get(s, :origin_host),
        origin_path: get(s, :path_prefix) or "",
        hosts: join(get(s, :hosts), ","),
        gate: to_s(get(s, :gate)),
        kind: to_s(get(s, :kind)),
        cache: if_ok(service?(s), "disabled", "optimized"),
        all_methods: flag(service?(s)),
        origin_request: if_ok(service?(s), "all_viewer_except_host", "none"),
        flake: get(s, :flake) or "",
        port: to_s(get(s, :port) or ""),
        health_path: get(s, :health_path) or ""
      }
    end,
    ss
  )
end

def repo_row(r)
  public = get(r, :visibility) == :public
  {
    name: get(r, :name),
    slug: repo_slug(get(r, :name)),
    description: get(r, :description) or "",
    visibility: to_s(get(r, :visibility)),
    archived: "false",
    default_branch: "main",
    has_issues: "true",
    delete_branch_on_merge: "true",
    actions_enabled: "true",
    actions_disabled: "false",
    standard_labels: "false",
    has_branch_protection: flag(public),
    bp_strict: flag(public),
    bp_enforce_admins: flag(public),
    has_ci_shim: "false",
    ci_shim_slug: "",
    ci_shim_path: "",
    ci_shim_content: "",
    exists_on_github: "false"
  }
end

def team_rows(ts)
  map(
    fn(t)
      {slug: team_slug(get(t, :name)), name: get(t, :name), privacy: "closed"}
    end,
    ts
  )
end

def permission_name(p)
  nth(1, first(filter((e) -> first(e) == p, permissions)))
end

def grant_rows(rs, ts)
  names = map((r) -> get(r, :name), rs)
  flat_map(
    fn(t)
      targets = if team_repos(t) == :all
        names
      else
        team_repos(t)
      end
      map(
        fn(n)
          {
            key: "#{team_slug(get(t, :name))}__#{repo_slug(n)}",
            team_slug: team_slug(get(t, :name)),
            repo_slug: repo_slug(n),
            repo_name: n,
            permission: permission_name(get(t, :permission))
          }
        end,
        targets
      )
    end,
    ts
  )
end

def variables(a)
  x = judge(a).accepted
  {
    company: get(x, :company) or "",
    owner: get(x, :github_org) or "",
    repo_count: to_s(size(get(x, :repos))),
    zones: zone_rows(get(x, :domains)),
    dns_records: mail_rows(get(x, :mail)),
    edge_aliases: alias_rows(get(x, :domains), get(x, :sites)),
    edge_sites: edge_site_rows(get(x, :sites)),
    repos: map(repo_row, get(x, :repos)),
    teams: team_rows(get(x, :teams)),
    team_repo_grants: grant_rows(get(x, :repos), get(x, :teams))
  }
end

def variables_json(a)
  pretty(variables(a))
end

def registrar(name)
  if ends_with?(name, ".br")
    "Registro.br"
  else
    "the domain's registrar"
  end
end

def step(id, where, what)
  {step: id, where: where, what: what}
end

def mail_steps(m, rows)
  if m == nil
    []
  elsif get(m, :provider) == :undecided
    [
      step(
        "3",
        "operator",
        "Choose a mail provider (#{join(map(to_s, preset_names), ", ")}) and set it in the declaration; no mail rows exist until then"
      )
    ]
  else
    append(
      map(
        fn(r)
          step(
            "3",
            "#{get(m, :provider)} console",
            "Replace #{get(r, :value)} in the #{get(r, :type)} row #{get(r, :name)} with the value the provider shows for #{get(m, :domain)}"
          )
        end,
        filter((r) -> get(r, :pending) == "true", rows)
      ),
      [
        step(
          "3a",
          "#{get(m, :provider)} console",
          "Create the mailboxes of #{get(m, :domain)}"
        )
      ]
    )
  end
end

def github_steps(org)
  if org == nil
    []
  else
    [
      step(
        "4",
        "github.com",
        "Create a GitHub user on the domain email, then the organisation #{org}; no API creates an organisation"
      )
    ]
  end
end

def manual_steps(a)
  x = judge(a).accepted
  names = domain_names(get(x, :domains))
  append(
    map((n) -> step("1", registrar(n), "Register #{n}"), names),
    map(
      fn(n)
        step(
          "2a",
          "#{registrar(n)} panel",
          "Point the nameservers of #{n} at the Route 53 zone's NS records"
        )
      end,
      names
    ),
    mail_steps(get(x, :mail), mail_rows(get(x, :mail))),
    github_steps(get(x, :github_org))
  )
end

def manual_md(a)
  x = judge(a).accepted
  rows = map(
    (s) -> "| #{get(s, :step)} | #{get(s, :where)} | #{get(s, :what)} |",
    manual_steps(a)
  )
  head = [
    "# Manual steps: #{get(x, :company) or "company"}",
    "",
    "Generated by the empresa bidama from the declaration. Do not edit by hand.",
    "",
    "| Step | Where | What |",
    "|---|---|---|"
  ]
  "#{join(append(head, rows), "\n")}\n"
end

def refused_md(a)
  rows = map((r) -> "| #{first(r)} | #{nth(1, r)} |", judge(a).refused)
  head = ["| Refused | Why |", "|---|---|"]
  "#{join(append(head, rows), "\n")}\n"
end

def write_outputs(a, dir)
  write_file("#{dir}/variables.json", variables_json(a))
  write_file("#{dir}/manual-steps.md", manual_md(a))
  write_file("#{dir}/refused.md", refused_md(a))
  nil
end

def example()
  {
    company: "acme",
    domains: [
      {name: "acme.example", role: :primary, dns_host: :route53},
      {name: "acme-labs.example", role: :secondary, dns_host: :route53}
    ],
    mail: {provider: :google, domain: "acme.example"},
    sites: [
      {
        name: "acme-site",
        hosts: ["acme.example", "www.acme.example", "acme-labs.example"],
        origin_host: "origin.tailnet.example",
        path_prefix: "/acme",
        gate: :proxy,
        kind: :static
      }
    ],
    github_org: "acme-org",
    repos: [
      {name: "audit-action", visibility: :public, description: "an action"},
      {name: "deploy-helm", visibility: :private}
    ],
    teams: [
      {name: "core", permission: :admin, repos: :all},
      {name: "field", permission: :write, repos: ["audit-action"]}
    ]
  }
end

def with(a, k, v)
  assoc(a, k, v)
end

def one_domain()
  [{name: "acme.example", role: :primary, dns_host: :route53}]
end

def site(name, hosts)
  {
    name: name,
    hosts: hosts,
    origin_host: "o.example",
    gate: :proxy,
    kind: :static
  }
end

def service_site(name, hosts)
  assoc(
    assoc(
      assoc(site(name, hosts), :kind, :service),
      :flake,
      "github:acme-org/api#default"
    ),
    :port,
    8081
  )
end

test "a static site projects an optimized cache and a service a disabled one"
  api = assoc(
    service_site("api", ["api.acme.example"]),
    :health_path,
    "/healthz"
  )
  a = {
    company: "acme",
    domains: one_domain,
    sites: [site("web", ["acme.example"]), api]
  }
  assert judge(a).refused == []
  rows = variables(a).edge_sites
  assert size(rows) == 2
  web = first(rows)
  assert web.kind == "static"
  assert web.cache == "optimized"
  assert web.all_methods == "false"
  assert web.origin_request == "none"
  assert web.flake == ""
  assert web.port == ""
  svc = nth(1, rows)
  assert svc.kind == "service"
  assert svc.cache == "disabled"
  assert svc.all_methods == "true"
  assert svc.origin_request == "all_viewer_except_host"
  assert svc.flake == "github:acme-org/api#default"
  assert svc.port == "8081"
  assert svc.health_path == "/healthz"
end

test "a service without a flake or a port, or a static site with a flake, is refused alone"
  ok = site("web", ["acme.example"])
  no_flake = dissoc(service_site("a", ["a.acme.example"]), :flake)
  no_port = dissoc(service_site("b", ["b.acme.example"]), :port)
  bad_flake = assoc(service_site("c", ["c.acme.example"]), :flake, "owner/repo")
  bad_port = assoc(service_site("d", ["d.acme.example"]), :port, 70000)
  bad_health = assoc(
    service_site("e", ["e.acme.example"]),
    :health_path,
    "healthz"
  )
  static_flake = assoc(
    site("f", ["f.acme.example"]),
    :flake,
    "github:acme-org/api#default"
  )
  no_kind = dissoc(site("g", ["g.acme.example"]), :kind)
  j = judge(
    {
      company: "acme",
      domains: one_domain,
      sites: [
        ok,
        no_flake,
        no_port,
        bad_flake,
        bad_port,
        bad_health,
        static_flake,
        no_kind
      ]
    }
  )
  assert kinds(j.refused) ==
    [
      :bad_site,
      :bad_site,
      :bad_site,
      :bad_site,
      :bad_site,
      :bad_site,
      :bad_site
    ]
  assert map((x) -> x.name, j.accepted.sites) == ["web"]
  assert size(j.refused) == 7
  assert size(
    judge(
      {
        company: "acme",
        domains: one_domain,
        sites: [service_site("a", ["a.acme.example"])]
      }
    ).refused
  ) ==
    0
end

test "edge rows carry the comma-joined hosts, a host slug and the zone name"
  v = variables(example)
  s = first(v.edge_sites)
  assert s.hosts == "acme.example,www.acme.example,acme-labs.example"
  assert s.site == "acme-site"
  assert s.origin_host == "origin.tailnet.example"
  assert map((a) -> a.slug, v.edge_aliases) ==
    ["acme-example", "www-acme-example", "acme-labs-example"]
  assert map((a) -> a.zone, v.edge_aliases) ==
    ["acme.example", "acme.example", "acme-labs.example"]
  assert map((a) -> a.site, v.edge_aliases) ==
    ["acme-site", "acme-site", "acme-site"]
end

def all_strings?(rows)
  every((r) -> every((e) -> string?(nth(1, e)), map_entries(r)), rows)
end

test "every projected field is a string, numeric-looking ones included"
  v = variables(example)
  lists = [
    v.zones,
    v.dns_records,
    v.edge_aliases,
    v.edge_sites,
    v.repos,
    v.teams,
    v.team_repo_grants
  ]
  assert every(all_strings?, lists)
  assert size(v.dns_records) > 0
  api = assoc(
    service_site("api", ["api.acme.example"]),
    :health_path,
    "/healthz"
  )
  w = variables({company: "acme", domains: one_domain, sites: [api]})
  assert nth(0, w.edge_sites).port == "8081"
  assert first(v.dns_records).ttl == "3600"
  j = json_read(variables_json(example))
  assert string?(first(j.dns_records).ttl)
  assert string?(first(j.zones).key)
  assert string?(first(j.edge_sites).all_methods)
  numeric = with(example, :mail, {provider: :fastmail, domain: "acme.example"})
  assert every(string?, map((r) -> r.value, variables(numeric).dns_records))
end

test "an empty declaration stands empty and every list is empty"
  a = {company: "acme"}
  assert judge(a).refused == []
  assert kinds(judge({}).refused) == [:bad_slug]
  v = variables(a)
  assert v.zones == []
  assert v.dns_records == []
  assert v.edge_aliases == []
  assert v.repos == []
  assert v.teams == []
  assert v.team_repo_grants == []
  assert v.repo_count == "0"
  assert size(manual_steps(a)) == 0
end

test "what stands is itself accepted again"
  j = judge(example)
  assert j.refused == []
  assert judge(j.accepted).accepted == j.accepted
  assert judge(j.accepted).refused == []
  bad = with(
    example,
    :domains,
    [{name: "x", role: :primary, dns_host: :route53}]
  )
  assert judge(judge(bad).accepted).accepted == judge(bad).accepted
end

test "two domains, one site and a google preset give counted rows"
  v = variables(example)
  assert size(v.zones) == 2
  assert size(v.dns_records) == 5
  assert size(v.edge_aliases) == 3
  assert size(v.edge_sites) == 1
  assert size(v.repos) == 2
  assert size(v.teams) == 2
  assert size(v.team_repo_grants) == 3
  assert v.repo_count == "2"
  assert v.owner == "acme-org"
  assert size(manual_steps(example)) == 8
  assert size(distinct(map((r) -> r.slug, v.dns_records))) == 5
  assert first(v.edge_sites).origin_path == "/acme"
  assert nth(1, v.zones).key == "acme-labs_example"
end

test "email rows are expanded from the preset with documented values only"
  rows = variables(example).dns_records
  mx = first(rows)
  assert mx.type == "MX"
  assert mx.value == "1 smtp.google.com."
  assert mx.name == "acme.example"
  dmarc = last(rows)
  assert dmarc.name == "_dmarc.acme.example"
  assert dmarc.value == "v=DMARC1; p=none; rua=mailto:dmarc@acme.example"
  assert map((r) -> r.pending, rows) ==
    ["false", "false", "true", "true", "false"]
  assert nth(1, rows).value == "v=spf1 include:_spf.google.com ~all"
  assert nth(2, rows).name == "google._domainkey.acme.example"
  assert nth(2, rows).value == "PENDING-google-dkim"
  assert nth(3, rows).value == "PENDING-google-verification"
end

test "a control: another preset changes the rows, undecided removes them"
  proton = variables(
    with(example, :mail, {provider: :proton, domain: "acme.example"})
  ).dns_records
  assert size(proton) == 8
  assert map((r) -> r.value, take(2, proton)) ==
    ["10 mail.protonmail.ch.", "20 mailsec.protonmail.ch."]
  fast = variables(
    with(example, :mail, {provider: :fastmail, domain: "acme.example"})
  ).dns_records
  assert size(fast) == 7
  assert nth(3, fast).value == "fm1.acme.example.dkim.fmhosted.com."
  assert filter((r) -> r.pending == "true", fast) == []
  none = with(example, :mail, {provider: :undecided})
  assert variables(none).dns_records == []
  assert judge(none).refused == []
  assert size(filter((s) -> s.step == "3", manual_steps(none))) == 1
  assert filter((s) -> s.step == "3a", manual_steps(none)) == []
end

test "manual steps follow the order table and name each pending value"
  s = manual_steps(example)
  assert map((x) -> x.step, s) == ["1", "1", "2a", "2a", "3", "3", "3a", "4"]
  assert first(s).what == "Register acme.example"
  assert nth(4, s).what ==
    "Replace PENDING-google-dkim in the TXT row google._domainkey.acme.example with the value the provider shows for acme.example"
  assert size(split(manual_md(example), "\n")) == 6 + 8 + 1
  assert registrar("x.com.br") == "Registro.br"
end

test "a bad company slug is refused and the rest stands"
  j = judge(with(example, :company, "Acme Corp"))
  assert kinds(j.refused) == [:bad_slug]
  assert j.accepted.company == nil
  assert size(j.accepted.domains) == 2
  assert kinds(judge(with(example, :github_org, "Bad Org")).refused) ==
    [:bad_slug]
end

test "a bad domain falls alone"
  ds = [
    {name: "acme.example", role: :primary, dns_host: :route53},
    {name: "nodot", role: :primary, dns_host: :route53},
    {name: "b.example", role: :tertiary, dns_host: :route53},
    {name: "c.example", role: :primary, dns_host: :cloudflare}
  ]
  j = judge({company: "acme", domains: ds})
  assert kinds(j.refused) == [:bad_domain, :bad_domain, :bad_domain]
  assert domain_names(j.accepted.domains) == ["acme.example"]
end

test "a host belongs to the longest domain that holds it"
  ds = [
    {name: "acme.example", role: :primary, dns_host: :route53},
    {name: "eu.acme.example", role: :secondary, dns_host: :route53}
  ]
  a = {
    company: "acme",
    domains: ds,
    sites: [
      site("s", ["x.eu.acme.example", "y.acme.example", "eu.acme.example"])
    ]
  }
  assert map((r) -> r.zone, variables(a).edge_aliases) ==
    ["eu.acme.example", "acme.example", "eu.acme.example"]
end

test "a duplicate domain is refused and the first stands"
  d = first(one_domain)
  e = {name: "acme.example", role: :secondary, dns_host: :route53}
  z = {name: "z.example", role: :secondary, dns_host: :route53}
  j = judge({company: "acme", domains: [d, e, z]})
  assert kinds(j.refused) == [:duplicate_domain]
  assert j.accepted.domains == [d, z]
end

test "a host under no declared domain is refused and its siblings stand"
  s = site("s", ["acme.example", "evil.other", "a.acme.example"])
  a = {company: "acme", domains: one_domain, sites: [s]}
  j = judge(a)
  assert kinds(j.refused) == [:host_outside_domains]
  assert first(j.accepted.sites).hosts == ["acme.example", "a.acme.example"]
  assert size(variables(a).edge_aliases) == 2
end

test "a site with no host under a domain is refused whole"
  s = site("s", ["evil.other"])
  t = site("t", [])
  j = judge({company: "acme", domains: one_domain, sites: [s, t]})
  assert kinds(j.refused) ==
    [:host_outside_domains, :site_without_domain, :site_without_domain]
  assert j.accepted.sites == []
end

test "a host claimed twice is refused the second time"
  a = site("a", ["acme.example"])
  b = site("b", ["acme.example", "x.acme.example"])
  j = judge({company: "acme", domains: one_domain, sites: [a, b]})
  assert kinds(j.refused) == [:duplicate_host]
  assert map((s) -> s.hosts, j.accepted.sites) ==
    [["acme.example"], ["x.acme.example"]]
end

test "a bad or duplicate site is refused alone"
  ok = site("ok", ["acme.example"])
  bad_gate = assoc(site("g", ["acme.example"]), :gate, :open)
  bad_path = assoc(site("p", ["acme.example"]), :path_prefix, "kensa/")
  j = judge(
    {company: "acme", domains: one_domain, sites: [ok, bad_gate, bad_path, ok]}
  )
  assert kinds(j.refused) == [:bad_site, :bad_site, :duplicate_site]
  assert size(j.accepted.sites) == 1
end

test "an unknown mail preset is refused and nothing else falls"
  a = with(example, :mail, {provider: :hotmail, domain: "acme.example"})
  j = judge(a)
  assert kinds(j.refused) == [:unknown_mail_preset]
  assert j.accepted.mail == nil
  assert size(j.accepted.sites) == 1
  assert variables(a).dns_records == []
end

test "mail on a domain nobody declared is refused"
  j = judge(with(example, :mail, {provider: :google, domain: "other.example"}))
  assert kinds(j.refused) == [:mail_domain_undeclared]
end

test "a bad or duplicate repo is refused alone"
  rs = [
    {name: "good", visibility: :public},
    {name: "bad name", visibility: :public},
    {name: "v", visibility: :secret},
    {name: "good", visibility: :private},
    {name: "a-b", visibility: :public},
    {name: "a_b", visibility: :public}
  ]
  j = judge({company: "acme", github_org: "acme-org", repos: rs})
  assert kinds(j.refused) ==
    [:bad_repo, :bad_repo, :duplicate_repo, :duplicate_repo]
  assert map((r) -> r.name, j.accepted.repos) == ["good", "a-b"]
end

test "repo rows carry the full github-org-repos field set as strings"
  rs = variables(example).repos
  r = first(rs)
  assert size(map_entries(r)) == 19
  assert r.slug == "audit_action"
  assert r.has_branch_protection == "true"
  assert nth(1, rs).has_branch_protection == "false"
  assert r.exists_on_github == "false"
end

test "a bad or duplicate team is refused alone and an unknown repo falls only its grant"
  ts = [
    {name: "core", permission: :admin, repos: :all},
    {name: "BAD", permission: :admin, repos: :all},
    {name: "x", permission: :owner, repos: :all},
    {name: "core", permission: :read, repos: :all},
    {name: "field", permission: :write, repos: ["audit-action", "ghost"]}
  ]
  a = with(
    with(example, :teams, ts),
    :repos,
    [{name: "audit-action", visibility: :public}]
  )
  j = judge(a)
  assert kinds(j.refused) ==
    [:bad_team, :bad_team, :duplicate_team, :unknown_repo]
  assert map((t) -> t.name, j.accepted.teams) == ["core", "field"]
  assert nth(1, j.accepted.teams).repos == ["audit-action"]
end

test "grants map permissions to the provider's names"
  g = variables(example).team_repo_grants
  assert map((x) -> x.permission, g) == ["admin", "admin", "push"]
  assert map((x) -> x.repo_slug, g) ==
    ["audit_action", "deploy_helm", "audit_action"]
end

test "repos and teams without an org are refused, the rest stands"
  j = judge(with(example, :github_org, nil))
  assert kinds(j.refused) == [:no_github_org]
  assert j.accepted.repos == []
  assert size(j.accepted.domains) == 2
end

test "the json carries one object per list"
  v = json_read(variables_json(example))
  assert size(v.zones) == 2
  assert size(v.dns_records) == 5
  assert first(v.zones).key == "acme_example"
end
