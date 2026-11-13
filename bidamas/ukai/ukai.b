@moduledoc """
ukai (迂回) — a detour: keep an overlay VPN reaching its control plane and relays while a full-tunnel corporate VPN owns the default route.

    infer_enforcement([], [], [], [], :relay) #=> :unknown
"""

use("deeta", %i[as_json get_str])
use("fairu")
use("kyohi", %i[ok ok?])
use("retsu", %i[first is_empty last rest size])
use("shisutemu", %i[read_or status_of stderr_of stdout_of])
use("shuugou", %i[as_set difference unique])
use("tesuto")

def axes()
  [
    [:corp, %i[absent split full unread]],
    [
      :enforcement,
      %i[permissive routes_rewritten egress_blocked unknown unread]
    ],
    [:overlay, %i[down direct relay none unread]],
    [:gateway, %i[present absent unread]],
    [:targets, %i[resolved unread]],
    [:platform, %i[darwin nixos]],
    [:stale, %i[none present unread]]
  ]
end

def axis_names()
  map((a) -> first(a), axes)
end

def variant_named(axis, text)
  first(filter((v) -> to_s(v) == text, tesuto::variants(axes, axis)))
end

def state(axes_map, payload)
  bad = filter(
    (a) -> not member?(get(axes_map, a), tesuto::variants(axes, a)),
    axis_names
  )
  if is_empty(bad)
    reduce(
      (s, k) -> assoc(s, k, get(payload, k)),
      axes_map,
      %i[gateway_addr gateway_iface hosts routed stale_hosts table priority]
    )
  else
    raise(
      :not_a_variant,
      "no such variant on #{join(map((a) -> to_s(a), bad), ", ")}"
    )
  end
end

@doc """
unread_among: the names in `names` whose value in `m` is `:unread`, in order: the axes a reading could not fill.

    unread_among({site: :unread, gateway: :up}, %i[site gateway]) #=> [:site]
"""
def unread_among(m, names)
  filter((a) -> get(m, a) == :unread, names)
end

def unread_axes(s)
  unread_among(s, axis_names)
end

def noop(reason)
  {kind: :noop, reason:}
end

def refused(reason)
  {kind: :refused, reason:}
end

def blind(what)
  {kind: :blind, unread: what}
end

@doc """
decide: noop, bypass, refused or blind, over a total state. A route this host applied through a gateway that is no longer its own is retracted beside any answer but blind, so a move between networks never strands it.
"""
def decide(s)
  o = decide_kind(s)
  if o[:kind] != :blind and s[:stale] == :present
    assoc(o, :retract, retract_set(s))
  else
    o
  end
end

@doc """
decide_kind: the answer of `decide` before any retract. It is blind when an axis is unread; otherwise the first axis that settles the case gives noop or refused, and a state that passes every check is a bypass with its route set.

    decide_kind({corp: :split}) #=> {kind: :noop, reason: :split_tunnel_leaves_default}
"""
def decide_kind(s)
  if not is_empty(unread_axes(s))
    blind(unread_axes(s))
  elsif s[:corp] == :absent
    noop(:no_corp_tunnel)
  elsif s[:corp] == :split
    noop(:split_tunnel_leaves_default)
  elsif s[:overlay] == :down
    noop(:overlay_down)
  elsif s[:gateway] == :absent
    refused(:no_physical_gateway)
  elsif s[:enforcement] == :routes_rewritten
    refused(:enforcement_rewrites_routes)
  elsif s[:enforcement] == :egress_blocked
    refused(:enforcement_blocks_egress)
  else
    {kind: :bypass, routes: route_set(s)}
  end
end

def route_set(s)
  hosts = sorted(unique(as_set(s[:hosts])))
  held = difference(as_set(s[:routed]), as_set(s[:stale_hosts]))
  {
    backend: s[:platform],
    gateway: s[:gateway_addr],
    iface: s[:gateway_iface],
    table: s[:table],
    priority: s[:priority],
    hosts:,
    add: sorted(difference(hosts, held))
  }
end

@doc """
retract_set: the routes to take back for `s`. It carries the backend, table and priority of `s` and its stale hosts, unique and sorted.

    retract_set({platform: :darwin, table: 52, priority: 5200, stale_hosts: ["b", "a", "b"]}) #=> {backend: :darwin, table: 52, priority: 5200, hosts: ["a", "b"]}
"""
def retract_set(s)
  {
    backend: s[:platform],
    table: s[:table],
    priority: s[:priority],
    hosts: sorted(unique(as_set(s[:stale_hosts])))
  }
end

def sorted(xs)
  sort_keyed((x) -> x, xs)
end

def outcome_label(o)
  k = o[:kind]
  base = if k == :blind
    "blind:#{join(map((a) -> to_s(a), o[:unread]), ",")}"
  elsif k == :bypass
    "bypass"
  else
    "#{to_s(k)}:#{to_s(o[:reason])}"
  end
  if o[:retract].nil?
    base
  else
    "#{base}+retract"
  end
end

def row_key(s)
  tesuto::row_key(axes, s)
end

@doc """
verdict: the outcome label of `decide` over `s` after `fill` adds a payload. It is the cell a matrix row holds for that state.

    verdict({corp: :absent}) #=> "noop:no_corp_tunnel"
"""
def verdict(s)
  outcome_label(decide(fill(s)))
end

def matrix_rows(text)
  tesuto::matrix_rows(axes, text)
end

@doc """
variants: the variants of `axis` in ukai's axis table, in table order.

    variants(:gateway) #=> [:present, :absent, :unread]
"""
def variants(axis)
  tesuto::variants(axes, axis)
end

@doc """
every_state: every total state over ukai's axes, one for each row of the decision matrix.

    size(every_state) #=> 3600
"""
def every_state()
  tesuto::axis_states(axes)
end

@doc """
flat_map_states: each state in `acc` once for each variant in `vs`, with `axis` set to that variant.

    flat_map_states([{}], :a, [:x, :y]) #=> [{a: :x}, {a: :y}]
"""
def flat_map_states(acc, axis, vs)
  reduce((out, s) -> append(out, map((v) -> assoc(s, axis, v), vs)), [], acc)
end

@doc """
matrix_text: the decision matrix for `states` as text. A header row names the axes and the outcome; each state then gives one row with the label of its decision.

    starts_with?(matrix_text(every_state), "corp") #=> true
"""
def matrix_text(states)
  tesuto::matrix_text(axes, (s) -> outcome_label(decide(s)), states)
end

@doc """
matrix_findings: the findings where the matrix `text` disagrees with `verdict` over `states`. An empty list means the matrix holds.

    matrix_findings(fixture("matrix.tsv"), every_state) #=> []
"""
def matrix_findings(text, states)
  tesuto::matrix_findings(axes, verdict, text, states)
end

@doc """
duplicates: a finding for each row key that `rows` holds more than once.

    duplicates([["x", "a"], ["x", "b"]]) #=> [[:duplicate_row, "x"]]
"""
def duplicates(rows)
  tesuto::duplicate_rows(rows)
end

@doc """
ip_rule_add_argv: the `ip rule` argv that adds the rule sending `host` to `table` at `priority`.

    ip_rule_add_argv("ip", "192.0.2.9", 52, 5200) #=> ["ip", "-4", "rule", "add", "to", "192.0.2.9/32", "lookup", "52", "priority", "5200"]
"""
def ip_rule_add_argv(ip, host, table, priority)
  ip_rule_to_argv(ip, "add", host, table, priority)
end

@doc """
fixture: the text of ukai's fixture file `name`.

    starts_with?(fixture("matrix.tsv"), "corp") #=> true
"""
def fixture(name)
  fairu::fixture("ukai", name)
end

def matrix_row(line)
  tesuto::matrix_row(axes, line)
end

def fill(s)
  assoc(
    assoc(
      assoc(
        assoc(assoc(s, :gateway_addr, "192.0.2.1"), :gateway_iface, "en0"),
        :hosts,
        ["198.51.100.1"]
      ),
      :routed,
      []
    ),
    :stale_hosts,
    ["198.51.100.9"]
  )
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
def capture(argv)
  cap = exec_capture(*argv) rescue nil
  if cap.nil?
    {
      argv:,
      started: false,
      status: -1,
      stdout: "",
      stderr: "could not start #{first(argv)}"
    }
  else
    {
      argv:,
      started: true,
      status: status_of(cap),
      stdout: stdout_of(cap),
      stderr: stderr_of(cap)
    }
  end
end

def bad(why)
  {ok: false, why:}
end

def from_capture(c, parser)
  if c[:status] != 0
    bad(
      "#{first(c[:argv])} exited #{to_s(c[:status])}: #{blue::trim(c[:stderr])}"
    )
  else
    parser(c[:stdout])
  end
end

def netstat_argv()
  %w[/usr/sbin/netstat -rn -f inet]
end

def ifconfig_argv()
  %w[/sbin/ifconfig -l]
end

def route_add_argv(host, gateway)
  ["/sbin/route", "-n", "add", "-host", host, gateway]
end

@doc """
route_delete_argv: the darwin `route` argv that deletes the host route to `host`.

    route_delete_argv("192.0.2.9") #=> ["/sbin/route", "-n", "delete", "-host", "192.0.2.9"]
"""
def route_delete_argv(host)
  ["/sbin/route", "-n", "delete", "-host", host]
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

@doc """
ip_table_argv: the `ip route` argv that shows the IPv4 routes in `table`.

    ip_table_argv("ip", 52) #=> ["ip", "-4", "route", "show", "table", "52"]
"""
def ip_table_argv(ip, table)
  [ip, "-4", "route", "show", "table", to_s(table)]
end

@doc """
ip_route_del_argv: the `ip route` argv that deletes the host route to `host` from `table`.

    ip_route_del_argv("ip", "192.0.2.9", 52) #=> ["ip", "-4", "route", "del", "192.0.2.9/32", "table", "52"]
"""
def ip_route_del_argv(ip, host, table)
  [ip, "-4", "route", "del", "#{host}/32", "table", to_s(table)]
end

@doc """
ip_rule_to_argv: the `ip rule` argv that adds or deletes (`verb`) the rule sending `host` to `table` at `priority`.

    ip_rule_to_argv("ip", "del", "192.0.2.9", 52, 5200) #=> ["ip", "-4", "rule", "del", "to", "192.0.2.9/32", "lookup", "52", "priority", "5200"]
"""
def ip_rule_to_argv(ip, verb, host, table, priority)
  [
    ip,
    "-4",
    "rule",
    verb,
    "to",
    "#{host}/32",
    "lookup",
    to_s(table),
    "priority",
    to_s(priority)
  ]
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

def getent_argv(getent, name)
  [getent, "ahostsv4", name]
end

def fields(line)
  filter(
    (f) -> not is_empty(f),
    split(replace(blue::trim(line), "\t", " "), " ")
  )
end

def ipv4?(s)
  ps = split(s, ".")
  size(ps) == 4 and every_octet(ps)
end

def every_octet(ps)
  is_empty(filter((p) -> not octet?(p), ps))
end

def octet?(p)
  not is_empty(p) and
    is_empty(filter((c) -> not contains?("0123456789", c), chars(p))) and
    to_int(p) <= 255
end

def parse_netstat(text)
  ls = split(text, line_break)
  hdr = filter((l) -> starts_with?(l, "Destination"), ls)
  if is_empty(hdr)
    bad("netstat: no Destination header")
  else
    rows = filter((f) -> size(f) >= 4, map(fields, after_header(ls)))
    ok(map((f) -> {dest: f[0], gateway: f[1], flags: f[2], iface: f[3]}, rows))
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
    (l) -> ip_route_row(fields(l)),
    filter((l) -> not is_empty(blue::trim(l)), split(text, line_break))
  )
  if not is_empty(filter((r) -> r.nil?, rows))
    bad("ip route: a line with no dev")
  else
    ok(rows)
  end
end

def ip_route_row(fs)
  d = after_word(fs, "dev")
  if d.nil?
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
      dest:,
      gateway: if via.nil?
        d
      else
        via
      end,
      flags: if via.nil?
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
    fs[1]
  else
    after_word(rest(fs), w)
  end
end

def parse_ip_rules(text)
  ok(
    unique(
      filter(
        (h) -> h != nil,
        map((l) -> rule_host(fields(l)), split(text, line_break))
      )
    )
  )
end

def rule_host(fs)
  t = after_word(fs, "to")
  if t != nil and ends_with?(t, "/32")
    replace(t, "/32", "")
  end
end

def corp_iface?(iface, pattern, overlay_iface)
  starts_with?(iface, pattern) and iface != overlay_iface
end

def overlay_iface(routes)
  r = first(
    filter(
      (r) -> r_dest(r) == "100.64/10" or r_dest(r) == "100.64.0.0/10",
      routes
    )
  )
  if r.nil?
    ""
  else
    r[:iface]
  end
end

def r_dest(r)
  r[:dest]
end

def half?(d)
  member?(d, %w[0/1 128/1 128.0/1])
end

def corp_of(routes, pattern)
  ov = overlay_iface(routes)
  mine = filter((r) -> corp_iface?(r[:iface], pattern, ov), routes)
  halves = filter((r) -> half?(r_dest(r)) or r_dest(r) == "default", mine)
  if is_empty(mine)
    :absent
  elsif size(unique(map(r_dest, filter((r) -> half?(r_dest(r)), halves)))) >=
      2 or not is_empty(filter((r) -> r_dest(r) == "default", halves))
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
        r_dest(r) == "default" and
          ipv4?(r[:gateway]) and
          not corp_iface?(r[:iface], pattern, ov) and
          r[:iface] != ov
      end,
      routes
    )
  )
end

def routed_via(routes, gateway)
  unique(
    map(
      r_dest,
      filter(
        fn(r)
          r[:gateway] == gateway and
            ipv4?(r_dest(r)) and
            contains?(r[:flags], "H")
        end,
        routes
      )
    )
  )
end

def parse_derp_map(text)
  doc = json_parse(text) rescue nil
  regions = as_json(doc, "Regions")
  if regions.nil? or not list?(regions)
    bad("derp-map: no Regions object")
  else
    ips = unique(
      filter(
        ipv4?,
        reduce((acc, reg) -> append(acc, region_ips(reg[1])), [], regions)
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
  if nodes.nil? or not list?(nodes)
    []
  else
    map((n) -> get_str(n, "IPv4", ""), nodes)
  end
end

def parse_netcheck(text)
  doc = json_parse(text) rescue nil
  if doc.nil? or not list?(doc)
    bad("netcheck: not a JSON object")
  else
    udp = as_json(doc, "UDP")
    lat = as_json(doc, "RegionLatency")
    reached = list?(lat) and not null?(lat)
    if not boolean?(udp)
      bad("netcheck: no UDP field")
    elsif not reached
      ok(:none)
    elsif udp
      ok(:direct)
    else
      ok(:relay)
    end
  end
end

def parse_backend_state(text)
  doc = json_parse(text) rescue nil
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
      ipv4?,
      map(
        (l) -> blue::trim(replace(l, "ip_address:", "")),
        filter((l) -> starts_with?(l, "ip_address:"), split(text, line_break))
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
      ipv4?,
      map(
        (l) -> first(fields(l)),
        filter((l) -> not is_empty(blue::trim(l)), split(text, line_break))
      )
    )
  )
  if is_empty(ips)
    bad("getent: no IPv4 address")
  else
    ok(ips)
  end
end

@doc """
stale_via: the hosts in `applied` that a host route still sends through a gateway other than `gateway`, the routes a move between networks leaves behind.

    stale_via([{dest: "192.0.2.9", gateway: "192.168.50.1", flags: "UGHS", iface: "en0"}], "192.168.60.1", ["192.0.2.9"]) #=> ["192.0.2.9"]
"""
def stale_via(routes, gateway, applied)
  unique(
    map(
      r_dest,
      filter(
        fn(r)
          member?(r_dest(r), applied) and
            ipv4?(r[:gateway]) and
            r[:gateway] != gateway and
            contains?(r[:flags], "H")
        end,
        routes
      )
    )
  )
end

@doc """
stale_in_table: every host route in ukai's own table whose gateway is not `gateway`.

    stale_in_table([{dest: "192.0.2.9", gateway: "192.168.50.1", flags: "UG", iface: "eth0"}], "192.168.1.1") #=> ["192.0.2.9"]
"""
def stale_in_table(rows, gateway)
  unique(
    map(
      (r) -> replace(r_dest(r), "/32", ""),
      filter((r) -> ipv4?(r[:gateway]) and r[:gateway] != gateway, rows)
    )
  )
end

@doc """
stale_of: the stale axis. It is unread when the routes or the table could not be read, none when there is no gateway or no stale host, and present otherwise.

    stale_of(true, {ok: true}, "192.168.1.1", ["192.0.2.9"]) #=> :present
    stale_of(false, {ok: true}, "", []) #=> :unread
"""
def stale_of(routes_ok, table_r, gw_addr, hosts)
  if not routes_ok or not ok?(table_r)
    :unread
  elsif is_empty(gw_addr) or is_empty(hosts)
    :none
  else
    :present
  end
end

@doc """
infer_enforcement: a host this side applied and no route now carries was removed by the corporate tunnel; one still routed through an old gateway is stale, not removed.

    infer_enforcement(["a"], [], ["a"], ["a"], :relay) #=> :unknown
"""
def infer_enforcement(targets, routed, applied, stale, overlay)
  present = filter((h) -> member?(h, routed), targets)
  lost = filter(
    (h) -> not member?(h, routed) and not member?(h, stale),
    applied
  )
  if not is_empty(lost)
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
  if not ok?(status_r)
    :unread
  elsif status_r[:value] != "Running"
    :down
  elsif not ok?(netcheck_r)
    :unread
  else
    netcheck_r[:value]
  end
end

def assemble(cfg, obs)
  routes_r = obs[:routes]
  pattern = cfg[:corp_pattern]
  routes = if ok?(routes_r)
    routes_r[:value]
  else
    []
  end
  overlay = overlay_of(obs[:status], obs[:netcheck])
  gw_row = gateway_of(routes, pattern)
  gw_addr = if not is_empty(cfg[:gateway])
    cfg[:gateway]
  elsif gw_row != nil
    gw_row[:gateway]
  else
    ""
  end
  gw_iface = if not is_empty(cfg[:gateway_iface])
    cfg[:gateway_iface]
  elsif gw_row != nil
    gw_row[:iface]
  else
    ""
  end
  derp_r = obs[:derp]
  ctl_r = obs[:control]
  targets_ok = ok?(derp_r) and ok?(ctl_r)
  hosts = if targets_ok
    sorted(
      unique(append(append(derp_r[:value], ctl_r[:value]), cfg[:extra_hosts]))
    )
  else
    []
  end
  routed = if cfg[:platform] == :nixos
    as_set(obs[:rules][:value])
  else
    routed_via(routes, gw_addr)
  end
  routes_ok = ok?(routes_r) and (cfg[:platform] == :darwin or ok?(obs[:rules]))
  table_r = obs[:table]
  stale_hosts = if not routes_ok or not ok?(table_r) or is_empty(gw_addr)
    []
  elsif cfg[:platform] == :nixos
    stale_in_table(table_r[:value], gw_addr)
  else
    stale_via(routes, gw_addr, cfg[:applied])
  end
  corp = if ok?(routes_r)
    corp_of(routes, pattern)
  else
    :unread
  end
  gateway = if not ok?(routes_r) and is_empty(cfg[:gateway])
    :unread
  elsif is_empty(gw_addr) or is_empty(gw_iface)
    :absent
  else
    :present
  end
  enforcement = if not routes_ok or overlay == :unread or not targets_ok
    :unread
  else
    infer_enforcement(hosts, routed, cfg[:applied], stale_hosts, overlay)
  end
  state(
    {
      corp:,
      enforcement:,
      overlay:,
      gateway:,
      targets: if targets_ok
        :resolved
      else
        :unread
      end,
      platform: cfg[:platform],
      stale: stale_of(routes_ok, table_r, gw_addr, stale_hosts)
    },
    {
      gateway_addr: gw_addr,
      gateway_iface: gw_iface,
      hosts:,
      routed:,
      stale_hosts:,
      table: cfg[:table],
      priority: cfg[:priority]
    }
  )
end

@doc """
observe: read routes and overlay status into one typed state.
"""
def observe(cfg)
  ts = cfg[:tailscale]
  host = cfg[:control_host]
  if cfg[:platform] == :nixos
    ip = cfg[:ip]
    {
      routes: from_capture(capture(ip_route_argv(ip)), parse_ip_route),
      rules: from_capture(capture(ip_rule_argv(ip)), parse_ip_rules),
      status: from_capture(capture(status_argv(ts)), parse_backend_state),
      netcheck: from_capture(capture(netcheck_argv(ts)), parse_netcheck),
      derp: from_capture(capture(derp_map_argv(ts)), parse_derp_map),
      control: from_capture(
        capture(getent_argv(cfg[:getent], host)),
        parse_getent
      ),
      table: from_capture(
        capture(ip_table_argv(ip, cfg[:table])),
        parse_ip_route
      )
    }
  else
    {
      routes: from_capture(capture(netstat_argv), parse_netstat),
      rules: ok([]),
      table: ok([]),
      status: from_capture(capture(status_argv(ts)), parse_backend_state),
      netcheck: from_capture(capture(netcheck_argv(ts)), parse_netcheck),
      derp: from_capture(capture(derp_map_argv(ts)), parse_derp_map),
      control: from_capture(capture(dscacheutil_argv(host)), parse_dscacheutil)
    }
  end
end

@doc """
plan: host routes or policy rules an outcome needs: the stale ones retracted first, then the missing ones added.
"""
def plan(o, cfg)
  append(retract_plan(o, cfg), add_plan(o, cfg))
end

@doc """
retract_plan: the commands that take back the routes in the retract of `o`. On nixos each host gets a route delete and a rule delete; on darwin each host gets a route delete. With no retract the plan is empty.

    retract_plan({kind: :noop, retract: {backend: :darwin, hosts: ["192.0.2.9"]}}, {}) #=> [["/sbin/route", "-n", "delete", "-host", "192.0.2.9"]]
    retract_plan({kind: :noop}, {}) #=> []
"""
def retract_plan(o, cfg)
  rt = o[:retract]
  if rt.nil?
    []
  elsif rt[:backend] == :nixos
    reduce(
      fn(acc, h)
        append(
          acc,
          [
            ip_route_del_argv(cfg[:ip], h, rt[:table]),
            ip_rule_to_argv(cfg[:ip], "del", h, rt[:table], rt[:priority])
          ]
        )
      end,
      [],
      rt[:hosts]
    )
  else
    map(route_delete_argv, rt[:hosts])
  end
end

@doc """
next_applied: the hosts this side holds after a run. A dry run or any failed command keeps the record as it was, so the next run retries.

    next_applied(["a"], {kind: :noop, retract: {hosts: ["a"]}}, [], false) #=> []
"""
def next_applied(applied, o, failed, dry_run)
  if dry_run or not is_empty(failed)
    applied
  else
    kept = if o[:retract].nil?
      applied
    else
      difference(as_set(applied), as_set(o[:retract][:hosts]))
    end
    if o[:kind] == :bypass
      sorted(unique(append(kept, o[:routes][:hosts])))
    else
      sorted(unique(kept))
    end
  end
end

@doc """
add_plan: the commands that add the routes a bypass `o` still lacks. On nixos each host gets a route replace and a rule add; on darwin each host gets a route add through the gateway. Any answer but bypass gives an empty plan.

    add_plan({kind: :bypass, routes: {backend: :darwin, gateway: "192.168.1.1", add: ["192.0.2.9"]}}, {}) #=> [["/sbin/route", "-n", "add", "-host", "192.0.2.9", "192.168.1.1"]]
    add_plan({kind: :noop}, {}) #=> []
"""
def add_plan(o, cfg)
  if o[:kind] != :bypass
    []
  else
    rs = o[:routes]
    if rs[:backend] == :nixos
      reduce(
        fn(acc, h)
          append(
            acc,
            [
              ip_route_add_argv(
                cfg[:ip],
                h,
                rs[:gateway],
                rs[:iface],
                rs[:table]
              ),
              ip_rule_to_argv(cfg[:ip], "add", h, rs[:table], rs[:priority])
            ]
          )
        end,
        [],
        rs[:add]
      )
    else
      map((h) -> route_add_argv(h, rs[:gateway]), rs[:add])
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
    map(capture, argvs)
  end
end

def read_applied(path)
  doc = json_parse(read_or(path, "")) rescue nil
  xs = as_json(doc, "applied")
  if xs.nil? or not list?(xs)
    []
  else
    filter((x) -> string?(x), xs)
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
    extra_hosts: filter(ipv4?, split(getenv("UKAI_EXTRA_HOSTS", ""), ",")),
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
  now = now_ms
  cfg2 = assoc(cfg, :applied, read_applied(cfg[:state_path]))
  s = assemble(cfg2, observe(cfg2))
  o = decide(s)
  argvs = plan(o, cfg2)
  results = act(argvs, cfg2[:dry_run])
  failed = filter((r) -> r[:status] != 0 and r[:status] != nil, results)
  applied = next_applied(cfg2[:applied], o, failed, cfg2[:dry_run])
  record = {
    checked_ms: now,
    outcome: outcome_label(o),
    state: row_key(s),
    dry_run: cfg2[:dry_run],
    planned: map((a) -> join(a, " "), argvs),
    failed: map(
      (r) -> "#{join(r[:argv], " ")}: #{blue::trim(r[:stderr])}",
      failed
    ),
    applied:
  }
  mkdir_p(path_dirname(cfg2[:state_path]))
  tmp = "#{cfg2[:state_path]}.tmp"
  write_file(tmp, json_stringify(record))
  rename_file(tmp, cfg2[:state_path])
  write_stdout(
    unlines(
      [
        "#{outcome_label(o)} #{row_key(s)} planned=#{to_s(size(argvs))} failed=#{to_s(size(failed))}"
      ]
    )
  )
  record
end

def main()
  run(config)
end

def measured(routes_text, netcheck_text)
  {
    routes: parse_netstat(routes_text),
    rules: ok([]),
    status: parse_backend_state(fairu::fixture("ukai", "status-running.json")),
    netcheck: parse_netcheck(netcheck_text),
    derp: parse_derp_map(fairu::fixture("ukai", "derp-map.json")),
    control: parse_dscacheutil(fairu::fixture("ukai", "dscacheutil.txt")),
    table: ok([])
  }
end

def cfg_for(platform, applied)
  {
    platform:,
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
    applied:
  }
end

test "the matrix: every variant of every axis has exactly one row, and decide agrees with each"
  states = tesuto::axis_states(axes)
  assert size(states) == 4 * 5 * 5 * 3 * 2 * 2 * 3
  assert size(states) == 3600
  findings = tesuto::matrix_findings(
    axes,
    verdict,
    fairu::fixture("ukai", "matrix.tsv"),
    states
  )
  assert findings == []
end

test "the matrix gate goes red on a missing row, a stray row and a wrong decision"
  states = tesuto::axis_states(axes)
  text = fairu::fixture("ukai", "matrix.tsv")
  ls = matrix_rows(text)
  short = join(rest(ls), line_break)
  assert first(first(tesuto::matrix_findings(axes, verdict, short, states))) ==
    :missing_row
  stray = concat(
    text,
    unlines(
      ["full\tpermissive\trelay\tpresent\tresolved\tsolaris\tnone\tbypass"]
    )
  )
  assert first(first(tesuto::matrix_findings(axes, verdict, stray, states))) ==
    :row_without_variant
  flipped = replace(
    text,
    "full\tpermissive\trelay\tpresent\tresolved\tdarwin\tnone\tbypass",
    "full\tpermissive\trelay\tpresent\tresolved\tdarwin\tnone\tnoop:no_corp_tunnel"
  )
  assert first(
    first(tesuto::matrix_findings(axes, verdict, flipped, states))
  ) == :decision_disagrees
  assert size(
    tesuto::matrix_findings(
      axes,
      verdict,
      text,
      append(states, [assoc(first(states), :platform, :plan9)])
    )
  ) == 1
end

test "the measured live row: full tunnel, permissive, relay, gateway present, darwin is a bypass"
  rows = map(matrix_row, matrix_rows(fairu::fixture("ukai", "matrix.tsv")))
  r = first(
    filter(
      fn(r)
        first(r) == "full\tpermissive\trelay\tpresent\tresolved\tdarwin\tnone"
      end,
      rows
    )
  )
  assert last(r) == "bypass"
  moved = first(
    filter(
      fn(r)
        first(r) == "absent\tunknown\tnone\tpresent\tresolved\tdarwin\tpresent"
      end,
      rows
    )
  )
  assert last(moved) == "noop:no_corp_tunnel+retract"
end

test "blind is never noop: an unread axis wins over every other answer"
  s = fill(first(tesuto::axis_states(axes)))
  assert decide(assoc(s, :corp, :unread))[:kind] == :blind
  assert decide(assoc(assoc(s, :corp, :absent), :targets, :unread))[:unread] ==
    [:targets]
  assert decide(assoc(s, :corp, :absent))[:kind] == :noop
  assert size(
    filter((x) -> decide(fill(x))[:kind] == :blind, tesuto::axis_states(axes))
  ) == 3600 - 3 * 4 * 4 * 2 * 1 * 2 * 2
  assert decide(assoc(assoc(s, :corp, :absent), :stale, :unread))[:unread] ==
    [:stale]
  assert get(
    decide(assoc(assoc(s, :corp, :unread), :stale, :present)),
    :retract
  ).nil?
end

test "a state with a value outside its axis is refused, not decided"
  r = state(
    {
      corp: :sideways,
      enforcement: :unknown,
      overlay: :relay,
      gateway: :present,
      targets: :resolved,
      platform: :darwin
    },
    {}
  ) rescue
    :refused
  assert r == :refused
end

test "netstat: the measured full tunnel with no bypass yet"
  rs = get(
    parse_netstat(fairu::fixture("ukai", "netstat-full-no-bypass.txt")),
    :value
  )
  assert corp_of(rs, "utun") == :full
  assert overlay_iface(rs) == "utun4"
  gw = gateway_of(rs, "utun")
  assert gw[:gateway] == "192.168.60.1"
  assert gw[:iface] == "en0"
  assert routed_via(rs, "192.168.60.1") == []
  assert ok?(parse_netstat("garbage")) == false
end

test "netstat: the measured bypass has the 8 control-plane and 88 DERP host routes"
  rs = get(
    parse_netstat(fairu::fixture("ukai", "netstat-full-bypassed.txt")),
    :value
  )
  assert corp_of(rs, "utun") == :full
  assert size(routed_via(rs, "192.168.60.1")) == 96
  assert corp_of(rs, "utun7") == :full
  assert corp_of(rs, "ppp") == :absent
end

test "derp-map: the real map yields 88 IPv4 nodes, never 0"
  r = parse_derp_map(fairu::fixture("ukai", "derp-map.json"))
  assert ok?(r) == true
  assert size(r[:value]) == 88
  assert member?("199.38.181.93", r[:value]) == true
  assert get(
    parse_derp_map("{\"Regions\": {\"1\": {\"Nodes\": [{\"IPv4\": \"\"}]}}}"),
    :ok
  ) == false
  assert ok?(parse_derp_map("not json")) == false
  assert ok?(parse_derp_map("")) == false
end

test "netcheck: blocked reads none, bypassed reads direct, a DERP-only reply reads relay"
  assert get(
    parse_netcheck(fairu::fixture("ukai", "netcheck-blocked.json")),
    :value
  ) == :none
  assert get(
    parse_netcheck(fairu::fixture("ukai", "netcheck-bypassed.json")),
    :value
  ) == :direct
  assert get(
    parse_netcheck("{\"UDP\": false, \"RegionLatency\": {\"1\": 5}}"),
    :value
  ) == :relay
  assert ok?(parse_netcheck("{}")) == false
  assert ok?(parse_netcheck("nope")) == false
end

test "control plane resolution and status"
  r = parse_dscacheutil(fairu::fixture("ukai", "dscacheutil.txt"))
  assert size(r[:value]) == 8
  assert member?("192.200.0.110", r[:value]) == true
  assert ok?(parse_dscacheutil(unlines(["name: x"]))) == false
  assert get(
    parse_backend_state(fairu::fixture("ukai", "status-stopped.json")),
    :value
  ) == "Stopped"
  assert ok?(parse_backend_state("{}")) == false
  assert get(
    parse_getent(
      unlines(
        [
          "192.200.0.102   STREAM controlplane.tailscale.com",
          "192.200.0.102   DGRAM"
        ]
      )
    ),
    :value
  ) == ["192.200.0.102"]
end

test "end to end over the measured state before the bypass: enforcement unknown, so bypass every target"
  obs = measured(
    fairu::fixture("ukai", "netstat-full-no-bypass.txt"),
    fairu::fixture("ukai", "netcheck-blocked.json")
  )
  s = assemble(cfg_for(:darwin, []), obs)
  assert row_key(s) == "full\tunknown\tnone\tpresent\tresolved\tdarwin\tnone"
  o = decide(s)
  assert o[:kind] == :bypass
  assert size(o[:routes][:add]) == 96
  argvs = plan(o, cfg_for(:darwin, []))
  assert first(argvs) ==
    [
      "/sbin/route",
      "-n",
      "add",
      "-host",
      first(o[:routes][:add]),
      "192.168.60.1"
    ]
end

test "end to end over the measured state after the bypass: permissive, and only the rotated control-plane addresses left to add"
  obs = measured(
    fairu::fixture("ukai", "netstat-full-bypassed.txt"),
    fairu::fixture("ukai", "netcheck-bypassed.json")
  )
  s = assemble(cfg_for(:darwin, []), obs)
  assert row_key(s) ==
    "full\tpermissive\tdirect\tpresent\tresolved\tdarwin\tnone"
  o = decide(s)
  assert o[:kind] == :bypass
  assert o[:routes][:add] ==
    %w[192.200.0.103 192.200.0.105 192.200.0.106 192.200.0.108 192.200.0.115]
  assert size(plan(o, cfg_for(:darwin, []))) == 5
end

test "enforcement: removed routes and blocked egress are told apart, and each refuses"
  assert infer_enforcement(%w[a b], ["a"], %w[a b], [], :relay) ==
    :routes_rewritten
  assert infer_enforcement(%w[a b], ["a"], %w[a b], ["b"], :relay) ==
    :permissive
  assert infer_enforcement(%w[a b], [], %w[a b], %w[a b], :relay) == :unknown
  assert infer_enforcement(%w[a b], %w[a b], [], [], :none) == :egress_blocked
  assert infer_enforcement(%w[a b], %w[a b], [], [], :relay) == :permissive
  assert infer_enforcement(%w[a b], ["a"], [], [], :relay) == :permissive
  assert infer_enforcement(%w[a b], [], [], [], :relay) == :unknown
  assert infer_enforcement([], [], [], [], :relay) == :unknown
  obs = measured(
    fairu::fixture("ukai", "netstat-full-no-bypass.txt"),
    fairu::fixture("ukai", "netcheck-blocked.json")
  )
  s = assemble(cfg_for(:darwin, ["199.38.181.93"]), obs)
  assert s[:enforcement] == :routes_rewritten
  assert decide(s) == {kind: :refused, reason: :enforcement_rewrites_routes}
end

test "an unreadable observation is blind, naming what could not be read"
  obs = assoc(
    measured(
      fairu::fixture("ukai", "netstat-full-no-bypass.txt"),
      fairu::fixture("ukai", "netcheck-blocked.json")
    ),
    :derp,
    bad("tailscale exited 1")
  )
  o = decide(assemble(cfg_for(:darwin, []), obs))
  assert o[:kind] == :blind
  assert o[:unread] == %i[enforcement targets]
  obs2 = assoc(obs, :routes, bad("netstat exited 1"))
  assert decide(assemble(cfg_for(:darwin, []), obs2))[:unread] ==
    %i[corp enforcement gateway targets stale]
end

test "nixos is policy routing: a table route and a rule per host"
  text = unlines(
    [
      "0.0.0.0/1 dev ppp0 scope link",
      "128.0.0.0/1 dev ppp0 scope link",
      "default via 192.168.1.1 dev eth0 proto dhcp",
      "100.64.0.0/10 dev tailscale0"
    ]
  )
  rs = parse_ip_route(text)[:value]
  assert corp_of(rs, "ppp") == :full
  assert gateway_of(rs, "ppp")[:iface] == "eth0"
  assert get(
    parse_ip_rules(
      unlines(
        [
          "5200:\tfrom all to 192.200.0.102/32 lookup 5280",
          "5210:\tfrom all fwmark 0x80000/0xff0000 lookup main"
        ]
      )
    ),
    :value
  ) == ["192.200.0.102"]
  obs = {
    routes: parse_ip_route(text),
    rules: parse_ip_rules(
      unlines(["5200:\tfrom all to 192.200.0.102/32 lookup 5280"])
    ),
    status: ok("Running"),
    netcheck: ok(:relay),
    derp: ok(["199.38.181.93"]),
    control: ok(["192.200.0.102"]),
    table: ok([])
  }
  cfg = assoc(assoc(cfg_for(:nixos, []), :corp_pattern, "ppp"), :ip, "/bin/ip")
  o = decide(assemble(cfg, obs))
  assert o[:kind] == :bypass
  assert plan(o, cfg) ==
    [
      %w[
        /bin/ip
        -4
        route
        replace
        199.38.181.93/32
        via
        192.168.1.1
        dev
        eth0
        table
        5280
      ],
      %w[/bin/ip -4 rule add to 199.38.181.93/32 lookup 5280 priority 5200]
    ]
end

test "dry-run plans and runs nothing; a real capture keeps status and stdout apart"
  rs = act([%w[/sbin/route -n add -host 192.0.2.9 192.0.2.1]], true)
  assert first(rs)[:stderr] == "dry-run"
  assert first(rs)[:status].nil?
  ok_cap = {
    argv: ["/sbin/x"],
    started: true,
    status: 0,
    stdout: unlines(["Destination"]),
    stderr: "warn"
  }
  assert ok?(from_capture(ok_cap, parse_netstat)) == true
  bad_cap = assoc(ok_cap, :status, 3)
  assert from_capture(bad_cap, parse_netstat)[:why] == "/sbin/x exited 3: warn"
  missing = capture(["/nonexistent/ukai-tool"])
  assert missing[:started] == false
  assert ok?(from_capture(missing, parse_netstat)) == false
end

@doc """
moved_applied: the hosts this side applied before the move in the site-move fixtures.

    moved_applied #=> ["192.200.0.102", "199.38.181.93", "5.161.218.233"]
"""
def moved_applied()
  %w[192.200.0.102 199.38.181.93 5.161.218.233]
end

test "a move between networks with no corporate tunnel retracts every route this side applied through the old gateway, and only those"
  obs = measured(
    fairu::fixture("ukai", "netstat-site-moved.txt"),
    fairu::fixture("ukai", "netcheck-blocked.json")
  )
  cfg = cfg_for(:darwin, moved_applied)
  s = assemble(cfg, obs)
  assert row_key(s) ==
    "absent\tunknown\tnone\tpresent\tresolved\tdarwin\tpresent"
  o = decide(s)
  assert outcome_label(o) == "noop:no_corp_tunnel+retract"
  assert plan(o, cfg) ==
    [
      %w[/sbin/route -n delete -host 192.200.0.102],
      %w[/sbin/route -n delete -host 199.38.181.93],
      %w[/sbin/route -n delete -host 5.161.218.233]
    ]
  assert member?("203.0.113.7", o[:retract][:hosts]) == false
end

test "a move between networks under a full tunnel retracts the old routes, then adds them through the new gateway, and is not read as rewritten routes"
  text = concat(
    fairu::fixture("ukai", "netstat-site-moved.txt"),
    unlines(
      [
        "0/1                utun7              UScg                utun7       ",
        "128.0/1            utun7              UScg                utun7       "
      ]
    )
  )
  obs = measured(text, fairu::fixture("ukai", "netcheck-blocked.json"))
  cfg = cfg_for(:darwin, moved_applied)
  s = assemble(cfg, obs)
  assert s[:enforcement] == :unknown
  o = decide(s)
  assert outcome_label(o) == "bypass+retract"
  argvs = plan(o, cfg)
  assert take(3, argvs) ==
    [
      %w[/sbin/route -n delete -host 192.200.0.102],
      %w[/sbin/route -n delete -host 199.38.181.93],
      %w[/sbin/route -n delete -host 5.161.218.233]
    ]
  assert member?(
    %w[/sbin/route -n add -host 199.38.181.93 192.168.60.1],
    argvs
  ) == true
  assert size(argvs) == 3 + size(o[:routes][:add])
end

test "routes through the current gateway are never stale, and a host this side never applied is never retracted"
  rs = parse_netstat(fairu::fixture("ukai", "netstat-site-moved.txt"))[:value]
  assert stale_via(rs, "192.168.50.1", moved_applied) == []
  assert stale_via(rs, "192.168.60.1", []) == []
  assert sorted(stale_via(rs, "192.168.60.1", moved_applied)) ==
    %w[192.200.0.102 199.38.181.93 5.161.218.233]
  assert stale_via(rs, "192.168.60.1", ["203.0.113.8"]) == []
end

test "nixos: a table route through an old gateway is retracted with its rule, then replaced through the new one"
  text = unlines(
    [
      "0.0.0.0/1 dev ppp0 scope link",
      "128.0.0.0/1 dev ppp0 scope link",
      "default via 192.168.1.1 dev eth0 proto dhcp",
      "100.64.0.0/10 dev tailscale0"
    ]
  )
  obs = {
    routes: parse_ip_route(text),
    rules: parse_ip_rules(
      unlines(["5200:\tfrom all to 199.38.181.93/32 lookup 5280"])
    ),
    status: ok("Running"),
    netcheck: ok(:relay),
    derp: ok(["199.38.181.93"]),
    control: ok(["192.200.0.102"]),
    table: parse_ip_route(unlines(["199.38.181.93 via 192.168.50.1 dev eth0"]))
  }
  cfg = assoc(assoc(cfg_for(:nixos, []), :corp_pattern, "ppp"), :ip, "/bin/ip")
  s = assemble(cfg, obs)
  assert s[:stale] == :present
  o = decide(s)
  assert outcome_label(o) == "bypass+retract"
  assert take(2, plan(o, cfg)) ==
    [
      %w[/bin/ip -4 route del 199.38.181.93/32 table 5280],
      %w[/bin/ip -4 rule del to 199.38.181.93/32 lookup 5280 priority 5200]
    ]
  assert member?("199.38.181.93", o[:routes][:add]) == true
  unread = assemble(cfg, assoc(obs, :table, bad("ip exited 2")))
  assert decide(unread)[:unread] == [:stale]
end

test "the applied record: a dry run or a failure keeps it, a retract removes its hosts, a bypass adds its own"
  o = {kind: :noop, reason: :no_corp_tunnel, retract: {hosts: ["a"]}}
  assert next_applied(%w[a b], o, [], true) == %w[a b]
  assert next_applied(%w[a b], o, [{status: 1}], false) == %w[a b]
  assert next_applied(%w[a b], o, [], false) == ["b"]
  by = {kind: :bypass, routes: {hosts: %w[a c]}, retract: {hosts: ["a"]}}
  assert next_applied(%w[a b], by, [], false) == %w[a b c]
  assert next_applied(
    %w[a b],
    {kind: :noop, reason: :overlay_down},
    [],
    false
  ) == %w[a b]
end

test "the released words keep their behaviour through their new homes"
  assert variants(:host) == tesuto::variants(axes, :host)
  assert length(every_state) == length(tesuto::axis_states(axes))
  assert flat_map_states([{}], :a, %i[x y]) == [{a: :x}, {a: :y}]
  assert duplicates([%w[x a], %w[x b]]) == [[:duplicate_row, "x"]]
  assert ip_rule_add_argv("ip", "192.0.2.9", 52, 5200) ==
    ip_rule_to_argv("ip", "add", "192.0.2.9", 52, 5200)
  assert fixture("matrix.tsv") == fairu::fixture("ukai", "matrix.tsv")
  assert matrix_findings(fixture("matrix.tsv"), every_state) == []
  assert starts_with?(
    matrix_text(every_state),
    "#{join(map(to_s, axis_names), "\t")}\toutcome"
  )
end
