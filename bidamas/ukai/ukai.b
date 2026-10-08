use("deeta", [:as_json, :get_str])
use("retsu", [:first, :is_empty, :last, :rest, :size])
use("shisutemu", [:read_or, :status_of, :stderr_of, :stdout_of])
use("shuugou", [:as_set, :difference, :unique])

# ukai (迂回) — a detour: keep an overlay VPN reaching its control plane and relays while a full-tunnel corporate VPN owns the default route.
def axes()
  [
    [:corp, [:absent, :split, :full, :unread]],
    [
      :enforcement,
      [:permissive, :routes_rewritten, :egress_blocked, :unknown, :unread]
    ],
    [:overlay, [:down, :direct, :relay, :none, :unread]],
    [:gateway, [:present, :absent, :unread]],
    [:targets, [:resolved, :unread]],
    [:platform, [:darwin, :nixos]]
  ]
end

def axis_names()
  map(fn(a) first(a) end, axes())
end

def variants(axis)
  last(first(filter(fn(a) first(a) == axis end, axes())))
end

def variant_named(axis, text)
  first(filter(fn(v) to_s(v) == text end, variants(axis)))
end

def every_state()
  reduce(fn(acc, a) flat_map_states(acc, first(a), last(a)) end, [{}], axes())
end

def flat_map_states(acc, axis, vs)
  reduce(
    fn(out, s) append(out, map(fn(v) assoc(s, axis, v) end, vs)) end,
    [],
    acc
  )
end

def state(axes_map, payload)
  bad = filter(fn(a) !member?(get(axes_map, a), variants(a)) end, axis_names())
  if is_empty(bad)
    reduce(
      fn(s, k) assoc(s, k, get(payload, k)) end,
      axes_map,
      [:gateway_addr, :gateway_iface, :hosts, :routed, :table, :priority]
    )
  else
    throw(
      error(
        :not_a_variant,
        "no such variant on #{join(map(fn(a) to_s(a) end, bad), ", ")}"
      )
    )
  end
end

def unread_axes(s)
  filter(fn(a) get(s, a) == :unread end, axis_names())
end

def noop(reason)
  {kind: :noop, reason: reason}
end

def refused(reason)
  {kind: :refused, reason: reason}
end

def blind(what)
  {kind: :blind, unread: what}
end

def decide(s)
  if !is_empty(unread_axes(s))
    blind(unread_axes(s))
  elsif get(s, :corp) == :absent
    noop(:no_corp_tunnel)
  elsif get(s, :corp) == :split
    noop(:split_tunnel_leaves_default)
  elsif get(s, :overlay) == :down
    noop(:overlay_down)
  elsif get(s, :gateway) == :absent
    refused(:no_physical_gateway)
  elsif get(s, :enforcement) == :routes_rewritten
    refused(:enforcement_rewrites_routes)
  elsif get(s, :enforcement) == :egress_blocked
    refused(:enforcement_blocks_egress)
  else
    {kind: :bypass, routes: route_set(s)}
  end
end

def route_set(s)
  hosts = sorted(unique(as_set(get(s, :hosts))))
  {
    backend: get(s, :platform),
    gateway: get(s, :gateway_addr),
    iface: get(s, :gateway_iface),
    table: get(s, :table),
    priority: get(s, :priority),
    hosts: hosts,
    add: sorted(difference(hosts, as_set(get(s, :routed))))
  }
end

def sorted(xs)
  sort_keyed(fn(x) x end, xs)
end

def outcome_label(o)
  k = get(o, :kind)
  if k == :blind
    "blind:#{join(map(fn(a) to_s(a) end, get(o, :unread)), ",")}"
  elsif k == :bypass
    "bypass"
  else
    "#{to_s(k)}:#{to_s(get(o, :reason))}"
  end
end

def row_key(s)
  join(map(fn(a) to_s(get(s, a)) end, axis_names()), "\t")
end

def matrix_rows(text)
  filter(
    fn(l) !is_empty(trim(l)) && !starts_with?(l, "corp\t") end,
    split(text, "\n")
  )
end

def matrix_row(line)
  fs = split(line, "\t")
  [join(take(size(axis_names()), fs), "\t"), last(fs)]
end

def matrix_text(states)
  header = "#{join(map(fn(a) to_s(a) end, axis_names()), "\t")}\toutcome\n"
  concat(
    header,
    join(
      map(fn(s) "#{row_key(s)}\t#{outcome_label(decide(s))}\n" end, states),
      ""
    )
  )
end

def matrix_findings(text, states)
  rows = map(fn(l) matrix_row(l) end, matrix_rows(text))
  want = reduce(
    fn(m, s) assoc(m, row_key(s), outcome_label(decide(fill(s)))) end,
    {},
    states
  )
  seen = reduce(fn(m, r) assoc(m, first(r), last(r)) end, {}, rows)
  missing = map(
    fn(s) [:missing_row, row_key(s)] end,
    filter(fn(s) get(seen, row_key(s)) == nil end, states)
  )
  extra = map(
    fn(r) [:row_without_variant, first(r)] end,
    filter(fn(r) get(want, first(r)) == nil end, rows)
  )
  dup = duplicates(rows)
  wrong = map(
    fn(r) [:decision_disagrees, "#{first(r)}\twant #{last(r)}"] end,
    filter(
      fn(r) get(want, first(r)) != nil && get(want, first(r)) != last(r) end,
      rows
    )
  )
  append(append(append(missing, extra), dup), wrong)
end

def duplicates(rows)
  r = reduce(
    fn(acc, row)
      if get(first(acc), first(row)) == nil
        [assoc(first(acc), first(row), true), last(acc)]
      else
        [first(acc), append(last(acc), [[:duplicate_row, first(row)]])]
      end
    end,
    [{}, []],
    rows
  )
  last(r)
end

def fill(s)
  assoc(
    assoc(
      assoc(assoc(s, :gateway_addr, "192.0.2.1"), :gateway_iface, "en0"),
      :hosts,
      ["198.51.100.1"]
    ),
    :routed,
    []
  )
end

def capture(argv)
  cap = try(apply(exec_capture, argv), catch(_e(), nil))
  if cap == nil
    {
      argv: argv,
      started: false,
      status: -1,
      stdout: "",
      stderr: "could not start #{first(argv)}"
    }
  else
    {
      argv: argv,
      started: true,
      status: status_of(cap),
      stdout: stdout_of(cap),
      stderr: stderr_of(cap)
    }
  end
end

def ok(v)
  {ok: true, value: v}
end

def bad(why)
  {ok: false, why: why}
end

def from_capture(c, parser)
  if get(c, :status) != 0
    bad(
      "#{first(get(c, :argv))} exited #{to_s(get(c, :status))}: #{trim(get(c, :stderr))}"
    )
  else
    parser(get(c, :stdout))
  end
end

def netstat_argv()
  ["/usr/sbin/netstat", "-rn", "-f", "inet"]
end

def ifconfig_argv()
  ["/sbin/ifconfig", "-l"]
end

def route_add_argv(host, gateway)
  ["/sbin/route", "-n", "add", "-host", host, gateway]
end

def dscacheutil_argv(name)
  ["/usr/bin/dscacheutil", "-q", "host", "-a", "name", name]
end

def derp_map_argv(tailscale)
  [tailscale, "debug", "derp-map"]
end

def netcheck_argv(tailscale)
  [tailscale, "netcheck", "--format=json"]
end

def status_argv(tailscale)
  [tailscale, "status", "--json"]
end

def ip_route_argv(ip)
  [ip, "-4", "route", "show", "table", "main"]
end

def ip_rule_argv(ip)
  [ip, "-4", "rule", "show"]
end

def ip_route_add_argv(ip, host, gateway, iface, table)
  [
    ip,
    "-4",
    "route",
    "replace",
    "#{host}/32",
    "via",
    gateway,
    "dev",
    iface,
    "table",
    to_s(table)
  ]
end

def ip_rule_add_argv(ip, host, table, priority)
  [
    ip,
    "-4",
    "rule",
    "add",
    "to",
    "#{host}/32",
    "lookup",
    to_s(table),
    "priority",
    to_s(priority)
  ]
end

def getent_argv(getent, name)
  [getent, "ahostsv4", name]
end

def fields(line)
  filter(fn(f) !is_empty(f) end, split(replace(trim(line), "\t", " "), " "))
end

def ipv4?(s)
  ps = split(s, ".")
  size(ps) == 4 && every_octet(ps)
end

def every_octet(ps)
  is_empty(filter(fn(p) !octet?(p) end, ps))
end

def octet?(p)
  !is_empty(p) &&
    is_empty(filter(fn(c) !contains?("0123456789", c) end, chars(p))) &&
    to_int(p) <= 255
end

def parse_netstat(text)
  ls = split(text, "\n")
  hdr = filter(fn(l) starts_with?(l, "Destination") end, ls)
  if is_empty(hdr)
    bad("netstat: no Destination header")
  else
    rows = filter(
      fn(f) size(f) >= 4 end,
      map(fn(l) fields(l) end, after_header(ls))
    )
    ok(
      map(
        fn(f)
          {
            dest: nth(0, f),
            gateway: nth(1, f),
            flags: nth(2, f),
            iface: nth(3, f)
          }
        end,
        rows
      )
    )
  end
end

def after_header(ls)
  if is_empty(ls)
    []
  elsif starts_with?(first(ls), "Destination")
    rest(ls)
  else
    after_header(rest(ls))
  end
end

def parse_ip_route(text)
  rows = map(
    fn(l) ip_route_row(fields(l)) end,
    filter(fn(l) !is_empty(trim(l)) end, split(text, "\n"))
  )
  if !is_empty(filter(fn(r) r == nil end, rows))
    bad("ip route: a line with no dev")
  else
    ok(rows)
  end
end

def ip_route_row(fs)
  d = after_word(fs, "dev")
  if d == nil
    nil
  else
    dest = if first(fs) == "0.0.0.0/1"
      "0/1"
    elsif first(fs) == "128.0.0.0/1"
      "128.0/1"
    else
      first(fs)
    end
    via = after_word(fs, "via")
    {
      dest: dest,
      gateway: if via == nil
        d
      else
        via
      end,
      flags: if via == nil
        "U"
      else
        "UG"
      end,
      iface: d
    }
  end
end

def after_word(fs, w)
  if size(fs) < 2
    nil
  elsif first(fs) == w
    nth(1, fs)
  else
    after_word(rest(fs), w)
  end
end

def parse_ip_rules(text)
  ok(
    unique(
      filter(
        fn(h) h != nil end,
        map(fn(l) rule_host(fields(l)) end, split(text, "\n"))
      )
    )
  )
end

def rule_host(fs)
  t = after_word(fs, "to")
  if t != nil && ends_with?(t, "/32")
    replace(t, "/32", "")
  else
    nil
  end
end

def corp_iface?(iface, pattern, overlay_iface)
  starts_with?(iface, pattern) && iface != overlay_iface
end

def overlay_iface(routes)
  r = first(
    filter(
      fn(r) r_dest(r) == "100.64/10" || r_dest(r) == "100.64.0.0/10" end,
      routes
    )
  )
  if r == nil
    ""
  else
    get(r, :iface)
  end
end

def r_dest(r)
  get(r, :dest)
end

def half?(d)
  member?(d, ["0/1", "128/1", "128.0/1"])
end

def corp_of(routes, pattern)
  ov = overlay_iface(routes)
  mine = filter(fn(r) corp_iface?(get(r, :iface), pattern, ov) end, routes)
  halves = filter(fn(r) half?(r_dest(r)) || r_dest(r) == "default" end, mine)
  if is_empty(mine)
    :absent
  elsif size(
    unique(map(fn(r) r_dest(r) end, filter(fn(r) half?(r_dest(r)) end, halves)))
  ) >=
    2 ||
    !is_empty(filter(fn(r) r_dest(r) == "default" end, halves))
    :full
  else
    :split
  end
end

def gateway_of(routes, pattern)
  ov = overlay_iface(routes)
  first(
    filter(
      fn(r)
        r_dest(r) == "default" &&
          ipv4?(get(r, :gateway)) &&
          !corp_iface?(get(r, :iface), pattern, ov) &&
          get(r, :iface) != ov
      end,
      routes
    )
  )
end

def routed_via(routes, gateway)
  unique(
    map(
      fn(r) r_dest(r) end,
      filter(
        fn(r)
          get(r, :gateway) == gateway &&
            ipv4?(r_dest(r)) &&
            contains?(get(r, :flags), "H")
        end,
        routes
      )
    )
  )
end

def parse_derp_map(text)
  doc = try(json_parse(text), catch(_e(), nil))
  regions = as_json(doc, "Regions")
  if regions == nil || !list?(regions)
    bad("derp-map: no Regions object")
  else
    ips = unique(
      filter(
        fn(ip) ipv4?(ip) end,
        reduce(
          fn(acc, reg) append(acc, region_ips(nth(1, reg))) end,
          [],
          regions
        )
      )
    )
    if is_empty(ips)
      bad("derp-map: Regions parsed but no node has an IPv4")
    else
      ok(ips)
    end
  end
end

def region_ips(reg)
  nodes = as_json(reg, "Nodes")
  if nodes == nil || !list?(nodes)
    []
  else
    map(fn(n) get_str(n, "IPv4", "") end, nodes)
  end
end

def parse_netcheck(text)
  doc = try(json_parse(text), catch(_e(), nil))
  if doc == nil || !list?(doc)
    bad("netcheck: not a JSON object")
  else
    udp = as_json(doc, "UDP")
    lat = as_json(doc, "RegionLatency")
    reached = list?(lat) && !null?(lat)
    if !boolean?(udp)
      bad("netcheck: no UDP field")
    elsif !reached
      ok(:none)
    elsif udp
      ok(:direct)
    else
      ok(:relay)
    end
  end
end

def parse_backend_state(text)
  doc = try(json_parse(text), catch(_e(), nil))
  st = get_str(doc, "BackendState", "")
  if is_empty(st)
    bad("status: no BackendState")
  else
    ok(st)
  end
end

def parse_dscacheutil(text)
  ips = unique(
    filter(
      fn(ip) ipv4?(ip) end,
      map(
        fn(l) trim(replace(l, "ip_address:", "")) end,
        filter(fn(l) starts_with?(l, "ip_address:") end, split(text, "\n"))
      )
    )
  )
  if is_empty(ips)
    bad("dscacheutil: no ip_address line")
  else
    ok(ips)
  end
end

def parse_getent(text)
  ips = unique(
    filter(
      fn(ip) ipv4?(ip) end,
      map(
        fn(l) first(fields(l)) end,
        filter(fn(l) !is_empty(trim(l)) end, split(text, "\n"))
      )
    )
  )
  if is_empty(ips)
    bad("getent: no IPv4 address")
  else
    ok(ips)
  end
end

def infer_enforcement(targets, routed, applied, overlay)
  present = filter(fn(h) member?(h, routed) end, targets)
  lost = filter(fn(h) !member?(h, routed) end, applied)
  if !is_empty(lost)
    :routes_rewritten
  elsif is_empty(present)
    :unknown
  elsif overlay == :none
    :egress_blocked
  else
    :permissive
  end
end

def overlay_of(status_r, netcheck_r)
  if !get(status_r, :ok)
    :unread
  elsif get(status_r, :value) != "Running"
    :down
  elsif !get(netcheck_r, :ok)
    :unread
  else
    get(netcheck_r, :value)
  end
end

def assemble(cfg, obs)
  routes_r = get(obs, :routes)
  pattern = get(cfg, :corp_pattern)
  routes = if get(routes_r, :ok)
    get(routes_r, :value)
  else
    []
  end
  overlay = overlay_of(get(obs, :status), get(obs, :netcheck))
  gw_row = gateway_of(routes, pattern)
  gw_addr = if !is_empty(get(cfg, :gateway))
    get(cfg, :gateway)
  elsif gw_row != nil
    get(gw_row, :gateway)
  else
    ""
  end
  gw_iface = if !is_empty(get(cfg, :gateway_iface))
    get(cfg, :gateway_iface)
  elsif gw_row != nil
    get(gw_row, :iface)
  else
    ""
  end
  derp_r = get(obs, :derp)
  ctl_r = get(obs, :control)
  targets_ok = get(derp_r, :ok) && get(ctl_r, :ok)
  hosts = if targets_ok
    sorted(
      unique(
        append(
          append(get(derp_r, :value), get(ctl_r, :value)),
          get(cfg, :extra_hosts)
        )
      )
    )
  else
    []
  end
  routed = if get(cfg, :platform) == :nixos
    as_set(get(get(obs, :rules), :value))
  else
    routed_via(routes, gw_addr)
  end
  routes_ok = get(routes_r, :ok) &&
    (get(cfg, :platform) == :darwin || get(get(obs, :rules), :ok))
  corp = if get(routes_r, :ok)
    corp_of(routes, pattern)
  else
    :unread
  end
  gateway = if !get(routes_r, :ok) && is_empty(get(cfg, :gateway))
    :unread
  elsif is_empty(gw_addr) || is_empty(gw_iface)
    :absent
  else
    :present
  end
  enforcement = if !routes_ok || overlay == :unread || !targets_ok
    :unread
  else
    infer_enforcement(hosts, routed, get(cfg, :applied), overlay)
  end
  state(
    {
      corp: corp,
      enforcement: enforcement,
      overlay: overlay,
      gateway: gateway,
      targets: if targets_ok
        :resolved
      else
        :unread
      end,
      platform: get(cfg, :platform)
    },
    {
      gateway_addr: gw_addr,
      gateway_iface: gw_iface,
      hosts: hosts,
      routed: routed,
      table: get(cfg, :table),
      priority: get(cfg, :priority)
    }
  )
end

def observe(cfg)
  ts = get(cfg, :tailscale)
  host = get(cfg, :control_host)
  if get(cfg, :platform) == :nixos
    ip = get(cfg, :ip)
    {
      routes: from_capture(capture(ip_route_argv(ip)), parse_ip_route),
      rules: from_capture(capture(ip_rule_argv(ip)), parse_ip_rules),
      status: from_capture(capture(status_argv(ts)), parse_backend_state),
      netcheck: from_capture(capture(netcheck_argv(ts)), parse_netcheck),
      derp: from_capture(capture(derp_map_argv(ts)), parse_derp_map),
      control: from_capture(
        capture(getent_argv(get(cfg, :getent), host)),
        parse_getent
      )
    }
  else
    {
      routes: from_capture(capture(netstat_argv()), parse_netstat),
      rules: ok([]),
      status: from_capture(capture(status_argv(ts)), parse_backend_state),
      netcheck: from_capture(capture(netcheck_argv(ts)), parse_netcheck),
      derp: from_capture(capture(derp_map_argv(ts)), parse_derp_map),
      control: from_capture(capture(dscacheutil_argv(host)), parse_dscacheutil)
    }
  end
end

def plan(o, cfg)
  if get(o, :kind) != :bypass
    []
  else
    rs = get(o, :routes)
    if get(rs, :backend) == :nixos
      reduce(
        fn(acc, h)
          append(
            acc,
            [
              ip_route_add_argv(
                get(cfg, :ip),
                h,
                get(rs, :gateway),
                get(rs, :iface),
                get(rs, :table)
              ),
              ip_rule_add_argv(
                get(cfg, :ip),
                h,
                get(rs, :table),
                get(rs, :priority)
              )
            ]
          )
        end,
        [],
        get(rs, :add)
      )
    else
      map(fn(h) route_add_argv(h, get(rs, :gateway)) end, get(rs, :add))
    end
  end
end

def act(argvs, dry_run)
  if dry_run
    map(
      fn(a)
        {argv: a, started: false, status: nil, stdout: "", stderr: "dry-run"}
      end,
      argvs
    )
  else
    map(fn(a) capture(a) end, argvs)
  end
end

def read_applied(path)
  doc = try(json_parse(read_or(path, "")), catch(_e(), nil))
  xs = as_json(doc, "applied")
  if xs == nil || !list?(xs)
    []
  else
    filter(fn(x) string?(x) end, xs)
  end
end

def config()
  {
    platform: if getenv("UKAI_PLATFORM", "darwin") == "nixos"
      :nixos
    else
      :darwin
    end,
    corp_pattern: getenv("UKAI_CORP_PATTERN", "utun"),
    control_host: getenv("UKAI_CONTROL_HOST", "controlplane.tailscale.com"),
    gateway: getenv("UKAI_GATEWAY", ""),
    gateway_iface: getenv("UKAI_GATEWAY_IFACE", ""),
    extra_hosts: filter(
      fn(h) ipv4?(h) end,
      split(getenv("UKAI_EXTRA_HOSTS", ""), ",")
    ),
    tailscale: getenv("UKAI_TAILSCALE", "tailscale"),
    ip: getenv("UKAI_IP", "ip"),
    getent: getenv("UKAI_GETENT", "getent"),
    table: to_int(getenv("UKAI_TABLE", "5280")),
    priority: to_int(getenv("UKAI_PRIORITY", "5200")),
    dry_run: getenv("UKAI_DRY_RUN", "1") != "0",
    state_path: getenv("UKAI_STATE", "/var/run/ukai/state.json")
  }
end

def run(cfg)
  now = now_ms()
  cfg2 = assoc(cfg, :applied, read_applied(get(cfg, :state_path)))
  s = assemble(cfg2, observe(cfg2))
  o = decide(s)
  argvs = plan(o, cfg2)
  results = act(argvs, get(cfg2, :dry_run))
  failed = filter(
    fn(r) get(r, :status) != 0 && get(r, :status) != nil end,
    results
  )
  applied = if get(cfg2, :dry_run) ||
    get(o, :kind) != :bypass ||
    !is_empty(failed)
    get(cfg2, :applied)
  else
    sorted(unique(append(get(cfg2, :applied), get(get(o, :routes), :hosts))))
  end
  record = {
    checked_ms: now,
    outcome: outcome_label(o),
    state: row_key(s),
    dry_run: get(cfg2, :dry_run),
    planned: map(fn(a) join(a, " ") end, argvs),
    failed: map(
      fn(r) "#{join(get(r, :argv), " ")}: #{trim(get(r, :stderr))}" end,
      failed
    ),
    applied: applied
  }
  mkdir_p(path_dirname(get(cfg2, :state_path)))
  tmp = "#{get(cfg2, :state_path)}.tmp"
  write_file(tmp, json_stringify(record))
  rename_file(tmp, get(cfg2, :state_path))
  write_stdout(
    "#{outcome_label(o)} #{row_key(s)} planned=#{to_s(size(argvs))} failed=#{to_s(size(failed))}\n"
  )
  record
end

def main()
  run(config())
end

def fixture(name)
  roots = append(
    split(getenv("BLUE_PATH", ""), ":"),
    [path_join(cwd(), "bidamas"), path_join(cwd(), "../../bidamas")]
  )
  hits = filter(
    fn(p) is_file?(p) end,
    map(fn(r) path_join(r, "ukai/fixtures/#{name}") end, roots)
  )
  if is_empty(hits)
    throw(error(:no_fixture, name))
  else
    read_file(first(hits))
  end
end

def measured(routes_text, netcheck_text)
  {
    routes: parse_netstat(routes_text),
    rules: ok([]),
    status: parse_backend_state(fixture("status-running.json")),
    netcheck: parse_netcheck(netcheck_text),
    derp: parse_derp_map(fixture("derp-map.json")),
    control: parse_dscacheutil(fixture("dscacheutil.txt"))
  }
end

def cfg_for(platform, applied)
  {
    platform: platform,
    corp_pattern: "utun",
    control_host: "controlplane.tailscale.com",
    gateway: "",
    gateway_iface: "",
    extra_hosts: [],
    tailscale: "tailscale",
    ip: "ip",
    getent: "getent",
    table: 5280,
    priority: 5200,
    applied: applied
  }
end

test "the matrix: every variant of every axis has exactly one row, and decide agrees with each"
  states = every_state()
  assert size(states) == 4 * 5 * 5 * 3 * 2 * 2
  assert size(states) == 1200
  findings = matrix_findings(fixture("matrix.tsv"), states)
  assert findings == []
end

test "the matrix gate goes red on a missing row, a stray row and a wrong decision"
  states = every_state()
  text = fixture("matrix.tsv")
  ls = matrix_rows(text)
  short = join(rest(ls), "\n")
  assert first(first(matrix_findings(short, states))) == :missing_row
  stray = concat(
    text,
    "full\tpermissive\trelay\tpresent\tresolved\tsolaris\tbypass\n"
  )
  assert first(first(matrix_findings(stray, states))) == :row_without_variant
  flipped = replace(
    text,
    "full\tpermissive\trelay\tpresent\tresolved\tdarwin\tbypass",
    "full\tpermissive\trelay\tpresent\tresolved\tdarwin\tnoop:no_corp_tunnel"
  )
  assert first(first(matrix_findings(flipped, states))) == :decision_disagrees
  assert size(
    matrix_findings(
      text,
      append(states, [assoc(first(states), :platform, :plan9)])
    )
  ) ==
    1
end

test "the measured live row: full tunnel, permissive, relay, gateway present, darwin is a bypass"
  rows = map(fn(l) matrix_row(l) end, matrix_rows(fixture("matrix.tsv")))
  r = first(
    filter(
      fn(r)
        first(r) == "full\tpermissive\trelay\tpresent\tresolved\tdarwin"
      end,
      rows
    )
  )
  assert last(r) == "bypass"
end

test "blind is never noop: an unread axis wins over every other answer"
  s = fill(first(every_state()))
  assert get(decide(assoc(s, :corp, :unread)), :kind) == :blind
  assert get(
    decide(assoc(assoc(s, :corp, :absent), :targets, :unread)),
    :unread
  ) ==
    [:targets]
  assert get(decide(assoc(s, :corp, :absent)), :kind) == :noop
  assert size(
    filter(fn(x) get(decide(fill(x)), :kind) == :blind end, every_state())
  ) ==
    1200 - 3 * 4 * 4 * 2 * 1 * 2
end

test "a state with a value outside its axis is refused, not decided"
  r = try(
    state(
      {
        corp: :sideways,
        enforcement: :unknown,
        overlay: :relay,
        gateway: :present,
        targets: :resolved,
        platform: :darwin
      },
      {}
    ),
    catch(_e(), :refused)
  )
  assert r == :refused
end

test "netstat: the measured full tunnel with no bypass yet"
  rs = get(parse_netstat(fixture("netstat-full-no-bypass.txt")), :value)
  assert corp_of(rs, "utun") == :full
  assert overlay_iface(rs) == "utun4"
  gw = gateway_of(rs, "utun")
  assert get(gw, :gateway) == "192.168.60.1"
  assert get(gw, :iface) == "en0"
  assert routed_via(rs, "192.168.60.1") == []
  assert get(parse_netstat("garbage"), :ok) == false
end

test "netstat: the measured bypass has the 8 control-plane and 88 DERP host routes"
  rs = get(parse_netstat(fixture("netstat-full-bypassed.txt")), :value)
  assert corp_of(rs, "utun") == :full
  assert size(routed_via(rs, "192.168.60.1")) == 96
  assert corp_of(rs, "utun7") == :full
  assert corp_of(rs, "ppp") == :absent
end

test "derp-map: the real map yields 88 IPv4 nodes, never 0"
  r = parse_derp_map(fixture("derp-map.json"))
  assert get(r, :ok) == true
  assert size(get(r, :value)) == 88
  assert member?("199.38.181.93", get(r, :value)) == true
  assert get(
    parse_derp_map("{\"Regions\": {\"1\": {\"Nodes\": [{\"IPv4\": \"\"}]}}}"),
    :ok
  ) ==
    false
  assert get(parse_derp_map("not json"), :ok) == false
  assert get(parse_derp_map(""), :ok) == false
end

test "netcheck: blocked reads none, bypassed reads direct, a DERP-only reply reads relay"
  assert get(parse_netcheck(fixture("netcheck-blocked.json")), :value) == :none
  assert get(parse_netcheck(fixture("netcheck-bypassed.json")), :value) ==
    :direct
  assert get(
    parse_netcheck("{\"UDP\": false, \"RegionLatency\": {\"1\": 5}}"),
    :value
  ) ==
    :relay
  assert get(parse_netcheck("{}"), :ok) == false
  assert get(parse_netcheck("nope"), :ok) == false
end

test "control plane resolution and status"
  r = parse_dscacheutil(fixture("dscacheutil.txt"))
  assert size(get(r, :value)) == 8
  assert member?("192.200.0.110", get(r, :value)) == true
  assert get(parse_dscacheutil("name: x\n"), :ok) == false
  assert get(parse_backend_state(fixture("status-stopped.json")), :value) ==
    "Stopped"
  assert get(parse_backend_state("{}"), :ok) == false
  assert get(
    parse_getent(
      "192.200.0.102   STREAM controlplane.tailscale.com\n192.200.0.102   DGRAM\n"
    ),
    :value
  ) ==
    ["192.200.0.102"]
end

test "end to end over the measured state before the bypass: enforcement unknown, so bypass every target"
  obs = measured(
    fixture("netstat-full-no-bypass.txt"),
    fixture("netcheck-blocked.json")
  )
  s = assemble(cfg_for(:darwin, []), obs)
  assert row_key(s) == "full\tunknown\tnone\tpresent\tresolved\tdarwin"
  o = decide(s)
  assert get(o, :kind) == :bypass
  assert size(get(get(o, :routes), :add)) == 96
  argvs = plan(o, cfg_for(:darwin, []))
  assert first(argvs) ==
    [
      "/sbin/route",
      "-n",
      "add",
      "-host",
      first(get(get(o, :routes), :add)),
      "192.168.60.1"
    ]
end

test "end to end over the measured state after the bypass: permissive, and only the rotated control-plane addresses left to add"
  obs = measured(
    fixture("netstat-full-bypassed.txt"),
    fixture("netcheck-bypassed.json")
  )
  s = assemble(cfg_for(:darwin, []), obs)
  assert row_key(s) == "full\tpermissive\tdirect\tpresent\tresolved\tdarwin"
  o = decide(s)
  assert get(o, :kind) == :bypass
  assert get(get(o, :routes), :add) ==
    [
      "192.200.0.103",
      "192.200.0.105",
      "192.200.0.106",
      "192.200.0.108",
      "192.200.0.115"
    ]
  assert size(plan(o, cfg_for(:darwin, []))) == 5
end

test "enforcement: removed routes and blocked egress are told apart, and each refuses"
  assert infer_enforcement(["a", "b"], ["a"], ["a", "b"], :relay) ==
    :routes_rewritten
  assert infer_enforcement(["a", "b"], ["a", "b"], [], :none) == :egress_blocked
  assert infer_enforcement(["a", "b"], ["a", "b"], [], :relay) == :permissive
  assert infer_enforcement(["a", "b"], ["a"], [], :relay) == :permissive
  assert infer_enforcement(["a", "b"], [], [], :relay) == :unknown
  assert infer_enforcement([], [], [], :relay) == :unknown
  obs = measured(
    fixture("netstat-full-no-bypass.txt"),
    fixture("netcheck-blocked.json")
  )
  s = assemble(cfg_for(:darwin, ["199.38.181.93"]), obs)
  assert get(s, :enforcement) == :routes_rewritten
  assert decide(s) == {kind: :refused, reason: :enforcement_rewrites_routes}
end

test "an unreadable observation is blind, naming what could not be read"
  obs = assoc(
    measured(
      fixture("netstat-full-no-bypass.txt"),
      fixture("netcheck-blocked.json")
    ),
    :derp,
    bad("tailscale exited 1")
  )
  o = decide(assemble(cfg_for(:darwin, []), obs))
  assert get(o, :kind) == :blind
  assert get(o, :unread) == [:enforcement, :targets]
  obs2 = assoc(obs, :routes, bad("netstat exited 1"))
  assert get(decide(assemble(cfg_for(:darwin, []), obs2)), :unread) ==
    [:corp, :enforcement, :gateway, :targets]
end

test "nixos is policy routing: a table route and a rule per host"
  text = "0.0.0.0/1 dev ppp0 scope link\n128.0.0.0/1 dev ppp0 scope link\ndefault via 192.168.1.1 dev eth0 proto dhcp\n100.64.0.0/10 dev tailscale0\n"
  rs = get(parse_ip_route(text), :value)
  assert corp_of(rs, "ppp") == :full
  assert get(gateway_of(rs, "ppp"), :iface) == "eth0"
  assert get(
    parse_ip_rules(
      "5200:\tfrom all to 192.200.0.102/32 lookup 5280\n5210:\tfrom all fwmark 0x80000/0xff0000 lookup main\n"
    ),
    :value
  ) ==
    ["192.200.0.102"]
  obs = {
    routes: parse_ip_route(text),
    rules: parse_ip_rules("5200:\tfrom all to 192.200.0.102/32 lookup 5280\n"),
    status: ok("Running"),
    netcheck: ok(:relay),
    derp: ok(["199.38.181.93"]),
    control: ok(["192.200.0.102"])
  }
  cfg = assoc(assoc(cfg_for(:nixos, []), :corp_pattern, "ppp"), :ip, "/bin/ip")
  o = decide(assemble(cfg, obs))
  assert get(o, :kind) == :bypass
  assert plan(o, cfg) ==
    [
      [
        "/bin/ip",
        "-4",
        "route",
        "replace",
        "199.38.181.93/32",
        "via",
        "192.168.1.1",
        "dev",
        "eth0",
        "table",
        "5280"
      ],
      [
        "/bin/ip",
        "-4",
        "rule",
        "add",
        "to",
        "199.38.181.93/32",
        "lookup",
        "5280",
        "priority",
        "5200"
      ]
    ]
end

test "dry-run plans and runs nothing; a real capture keeps status and stdout apart"
  rs = act([[self_exe(), "--version"]], true)
  assert get(first(rs), :stderr) == "dry-run"
  c = capture([self_exe(), "--version"])
  assert get(c, :status) == 0
  assert starts_with?(get(c, :stdout), "blue ") == true
  assert get(capture(["/nonexistent/ukai-tool"]), :started) == false
  assert get(
    from_capture(capture([self_exe(), "no-such-subcommand"]), parse_netstat),
    :ok
  ) ==
    false
end
