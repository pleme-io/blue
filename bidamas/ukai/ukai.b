@moduledoc """
ukai (迂回) — a detour: keep an overlay VPN reaching its control plane and relays while a full-tunnel corporate VPN owns the default route.

    infer_enforcement([], [], [], [], :relay) #=> :unknown
"""

use("deeta", %i[as_json get_str])
use("fairu")
use("kyohi", %i[ok ok?])
use("retsu", %i[first is_empty last rest size])
use("settei")
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
    [:stale, %i[none present unread]],
    [:held, %i[none present unread]]
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
      %i[
        gateway_addr
        gateway_iface
        hosts
        routed
        stale_hosts
        held_hosts
        lost_hosts
        orphan_hosts
        peer_hosts
        fingerprint
        iface_addr
        table
        priority
      ]
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
decide: noop, bypass, refused or blind, over a total state. A route this host applied through a gateway that is no longer its own is retracted beside any answer but blind, so a move between networks never strands it. A route it applied through its own gateway is a detour, so a noop, which needs no detour, retracts it too. A bypass retracts a peer endpoint that no peer still names.
"""
def decide(s)
  o = decide_kind(s)
  stale = o[:kind] != :blind and s[:stale] == :present
  held = o[:kind] == :noop and s[:held] == :present
  orphans = if o[:kind] == :bypass and list?(s[:orphan_hosts])
    s[:orphan_hosts]
  else
    []
  end
  if stale or held or not is_empty(orphans)
    assoc(
      o,
      :retract,
      retract_set(
        s,
        append(
          append(
            if stale
              as_set(s[:stale_hosts])
            else
              []
            end,
            if held
              as_set(s[:held_hosts])
            else
              []
            end
          ),
          orphans
        )
      )
    )
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
retract_set: the routes to take back for `s`. It carries the backend, table and priority of `s` and `hosts`, unique and sorted.

    retract_set({platform: :darwin, table: 52, priority: 5200}, ["b", "a", "b"]) #=> {backend: :darwin, table: 52, priority: 5200, hosts: ["a", "b"]}
"""
def retract_set(s, hosts)
  {
    backend: s[:platform],
    table: s[:table],
    priority: s[:priority],
    hosts: sorted(unique(as_set(hosts)))
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

    size(every_state) #=> 10800
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
    ),
    :held_hosts,
    ["198.51.100.8"]
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
  ["/sbin/ifconfig"]
end

@doc """
parse_ifconfig: the IPv4 address of each interface in darwin `ifconfig` output, one {iface:, addr:} per `inet` line, in order.

    parse_ifconfig("en0: flags=8863<UP> mtu 1500\n\tinet 192.0.2.7 netmask 0xffffff00\n")[:value] #=> [{iface: "en0", addr: "192.0.2.7"}]
"""
def parse_ifconfig(text)
  ok(reduce(ifconfig_line, {cur: "", rows: []}, split(text, line_break))[:rows])
end

@doc """
ifconfig_line: one line of `ifconfig` folded into `acc`: an interface header names the current interface, and an `inet` line adds its address to the rows.

    ifconfig_line({cur: "en0", rows: []}, "\tinet 192.0.2.7 netmask 0xffffff00")[:rows] #=> [{iface: "en0", addr: "192.0.2.7"}]
"""
def ifconfig_line(acc, l)
  fs = fields(l)
  if is_empty(fs)
    acc
  elsif not starts_with?(l, " ") and
      not starts_with?(l, "\t") and
      ends_with?(first(fs), ":")
    assoc(acc, :cur, replace(first(fs), ":", ""))
  elsif first(fs) == "inet" and size(fs) >= 2 and ipv4?(fs[1])
    assoc(acc, :rows, append(acc[:rows], [{iface: acc[:cur], addr: fs[1]}]))
  else
    acc
  end
end

@doc """
addrs_of: the IPv4 addresses `rows` give `iface`.

    addrs_of([{iface: "en0", addr: "192.0.2.7"}, {iface: "lo0", addr: "127.0.0.1"}], "en0") #=> ["192.0.2.7"]
"""
def addrs_of(rows, iface)
  map((r) -> r[:addr], filter((r) -> r[:iface] == iface, rows))
end

@doc """
iface_addr_of: the address the host now holds on the gateway interface, read from `addrs_r`; nil when it could not be read, "" when the interface holds none.

    iface_addr_of({ok: true, value: [{iface: "en0", addr: "192.0.2.7"}]}, "en0") #=> "192.0.2.7"
    iface_addr_of(nil, "en0") #=> nil
"""
def iface_addr_of(addrs_r, iface)
  if addrs_r.nil? or not ok?(addrs_r)
    nil
  else
    xs = addrs_of(addrs_r[:value], iface)
    if is_empty(xs)
      ""
    else
      first(xs)
    end
  end
end

@doc """
addr_moved?: darwin pins a host route to the interface address it was added through, so a route this side added from `applied_addr` is dead once the interface holds another. It is true only when both addresses were read and differ.

    addr_moved?(:darwin, "192.0.2.177", "192.0.2.122") #=> true
    addr_moved?(:darwin, "", "192.0.2.122") #=> false
    addr_moved?(:darwin, "192.0.2.177", nil) #=> false
"""
def addr_moved?(platform, applied_addr, iface_addr)
  platform == :darwin and
    string?(applied_addr) and
    not is_empty(applied_addr) and
    not is_empty(iface_addr) and
    applied_addr != iface_addr
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

@doc """
netmap_argv: the argv that prints the overlay's network map, whose peers name the endpoints they answer on.

    netmap_argv("tailscale") #=> ["tailscale", "debug", "netmap"]
"""
def netmap_argv(tailscale)
  [tailscale, "debug", "netmap"]
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
public_ipv4?: true for an IPv4 address a peer can be reached on across the internet; false for a private, shared, loopback, link-local, protocol-assignment (192.0.0/24), benchmarking (198.18/15), multicast or reserved one, and for anything not IPv4.

    public_ipv4?("203.0.113.7") #=> true
    public_ipv4?("192.168.50.3") #=> false
"""
def public_ipv4?(s)
  if not ipv4?(s)
    false
  else
    os = map(to_int, split(s, "."))
    a = os[0]
    b = os[1]
    not (
      a == 0 or
      a == 10 or
      a == 127 or
      a >= 224 or
      a == 169 and b == 254 or
      a == 172 and b >= 16 and b <= 31 or
      a == 192 and b == 168 or
      a == 192 and b == 0 and os[2] == 0 or
      a == 198 and (b == 18 or b == 19) or
      a == 100 and b >= 64 and b <= 127
    )
  end
end

@doc """
endpoint_host: the IPv4 address of an `address:port` endpoint, or "" for an IPv6 or malformed one.

    endpoint_host("203.0.113.7:41641") #=> "203.0.113.7"
    endpoint_host("[2001:db8::1]:41641") #=> ""
"""
def endpoint_host(ep)
  ps = split(ep, ":")
  if size(ps) == 2 and ipv4?(ps[0])
    ps[0]
  else
    ""
  end
end

@doc """
parse_peer_endpoints: the public IPv4 addresses every peer in a network map names as an endpoint, unique and sorted. A map with no peers is an empty list, not a failure.

    parse_peer_endpoints("{\"Peers\": [{\"Endpoints\": [\"203.0.113.7:41641\", \"192.168.1.9:41641\"]}]}")[:value] #=> ["203.0.113.7"]
"""
def parse_peer_endpoints(text)
  doc = json_parse(text) rescue nil
  peers = as_json(doc, "Peers")
  if doc.nil?
    bad("netmap: not JSON")
  elsif peers.nil?
    ok([])
  else
    ok(
      sorted(
        unique(
          filter(
            public_ipv4?,
            map(
              endpoint_host,
              reduce(
                fn(acc, p)
                  eps = as_json(p, "Endpoints")
                  if list?(eps)
                    append(acc, filter(string?, eps))
                  else
                    acc
                  end
                end,
                [],
                peers
              )
            )
          )
        )
      )
    )
  end
end

@doc """
lost_of: the hosts this side applied that no route carries and that are not stale: routes something else took away.

    lost_of(["a", "b", "c"], ["a"], ["c"]) #=> ["b"]
"""
def lost_of(applied, routed, stale)
  filter(
    (h) -> not member?(h, routed) and not member?(h, stale),
    unique(applied)
  )
end

@doc """
recent_rewrites: the times in `times` no older than `window_ms` before `now`; anything not a number is dropped.

    recent_rewrites([100, 900, "x"], 1000, 500) #=> [900]
"""
def recent_rewrites(times, now, window_ms)
  if not list?(times)
    []
  else
    filter((t) -> integer?(t) and t <= now and now - t <= window_ms, times)
  end
end

@doc """
next_rewrites: the loss times the next run sees: the recent ones, plus `now` when this run found routes taken away under a full tunnel.

    next_rewrites([100, 900], 1000, 500, true) #=> [900, 1000]
"""
def next_rewrites(times, now, window_ms, lost_now)
  kept = recent_rewrites(times, now, window_ms)
  if lost_now
    append(kept, [now])
  else
    kept
  end
end

@doc """
parse_public_ip: the public IPv4 address netcheck saw this node's traffic leave from (its GlobalV4, without the port), or "" when it saw none.

    parse_public_ip("{\"UDP\": true, \"GlobalV4\": \"203.0.113.7:41641\"}")[:value] #=> "203.0.113.7"
"""
def parse_public_ip(text)
  doc = json_parse(text) rescue nil
  if doc.nil?
    bad("netcheck: not JSON")
  else
    ok(endpoint_host(get_str(doc, "GlobalV4", "")))
  end
end

@doc """
fingerprint: the network this node sits on, as one string: the tunnel, the physical gateway, its address there and the public address its traffic leaves from. nil when a part could not be read, so an unread run never reads as a change.

    fingerprint(:full, "192.0.2.1", "192.0.2.122", {ok: true, value: "203.0.113.7"}) #=> "full|192.0.2.1|192.0.2.122|203.0.113.7"
    fingerprint(:unread, "192.0.2.1", "192.0.2.122", {ok: true, value: ""}) #=> nil
"""
def fingerprint(corp, gw_addr, iface_addr, public_r)
  if corp == :unread or iface_addr.nil? or public_r.nil? or not ok?(public_r)
    nil
  else
    join([to_s(corp), gw_addr, iface_addr, public_r[:value]], "|")
  end
end

@doc """
next_epoch: whether a network change has settled and the overlay should restart, and what the next run remembers. A new fingerprint must hold for `settle` runs in a row; the restart then waits out `cooldown_ms` after the last one. An unread fingerprint, the first one seen, or a change that reverts before it settles restarts nothing.

    next_epoch({epoch: "a"}, "b", 1000, 2, 600, 0)[:pending] #=> "b"
    next_epoch({epoch: "a", pending: "b", runs: 1}, "b", 1000, 2, 600, 0)[:restart] #=> true
"""
def next_epoch(prev, fp, now, settle, cooldown_ms, last_restart_ms)
  last = if integer?(last_restart_ms)
    last_restart_ms
  else
    0
  end
  if fp.nil?
    assoc(prev, :restart, false)
  elsif not string?(prev[:epoch]) or is_empty(prev[:epoch])
    {epoch: fp, pending: "", runs: 0, restart: false}
  elsif fp == prev[:epoch]
    {epoch: fp, pending: "", runs: 0, restart: false}
  else
    runs = if fp == prev[:pending] and integer?(prev[:runs])
      prev[:runs] + 1
    else
      1
    end
    if runs >= settle and now - last >= cooldown_ms
      {epoch: fp, pending: "", runs: 0, restart: true}
    else
      {epoch: prev[:epoch], pending: fp, runs:, restart: false}
    end
  end
end

@doc """
restart_argv: the command that restarts the overlay daemon, so its control session starts over on the network it now sits on.

    restart_argv(:darwin, "") #=> ["/bin/launchctl", "kickstart", "-k", "system/com.tailscale.tailscaled"]
    restart_argv(:nixos, "/bin/systemctl") #=> ["/bin/systemctl", "restart", "tailscaled.service"]
"""
def restart_argv(platform, systemctl)
  if platform == :nixos
    [systemctl, "restart", "tailscaled.service"]
  else
    %w[/bin/launchctl kickstart -k system/com.tailscale.tailscaled]
  end
end

@doc """
epoch_of: the network memory a state document holds: the settled fingerprint, a pending one and how many runs it has held.

    epoch_of(nil) #=> {epoch: "", pending: "", runs: 0}
"""
def epoch_of(doc)
  runs = as_json(doc, "epoch_runs")
  {
    epoch: get_str(doc, "epoch", ""),
    pending: get_str(doc, "epoch_pending", ""),
    runs: if integer?(runs)
      runs
    else
      0
    end
  }
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
held_of: the hosts this side applied that a route still carries and that are not stale: the detour it holds through its own gateway.

    held_of(["a", "b", "c"], ["b", "c", "d"], ["c"]) #=> ["b"]
"""
def held_of(routed, applied, stale)
  filter((h) -> member?(h, routed) and not member?(h, stale), unique(applied))
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
  lost = lost_of(applied, routed, stale)
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
  peers_ok = obs[:peers] != nil and ok?(obs[:peers])
  peer_hosts = if peers_ok
    obs[:peers][:value]
  else
    []
  end
  hosts = if targets_ok
    sorted(
      unique(
        append(
          append(append(derp_r[:value], ctl_r[:value]), cfg[:extra_hosts]),
          peer_hosts
        )
      )
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
  iface_addr = iface_addr_of(obs[:addrs], gw_iface)
  stale_hosts = if not routes_ok or not ok?(table_r) or is_empty(gw_addr)
    []
  elsif cfg[:platform] == :nixos
    stale_in_table(table_r[:value], gw_addr)
  elsif addr_moved?(cfg[:platform], cfg[:applied_addr], iface_addr)
    unique(
      append(
        stale_via(routes, gw_addr, cfg[:applied]),
        filter((h) -> member?(h, routed), cfg[:applied])
      )
    )
  else
    stale_via(routes, gw_addr, cfg[:applied])
  end
  held_hosts = held_of(routed, cfg[:applied], stale_hosts)
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
  lost_hosts = if routes_ok
    lost_of(cfg[:applied], routed, stale_hosts)
  else
    []
  end
  orphan_hosts = if routes_ok and targets_ok and peers_ok
    filter(
      (h) -> member?(h, routed) and not member?(h, hosts),
      as_set(cfg[:peer_applied])
    )
  else
    []
  end
  strikes = size(
    recent_rewrites(cfg[:rewrites_ms], cfg[:now], cfg[:rewrite_window_ms])
  ) +
    if corp == :full and not is_empty(lost_hosts)
      1
    else
      0
    end
  enforcement = if not routes_ok or overlay == :unread or not targets_ok
    :unread
  elsif integer?(cfg[:rewrite_limit]) and strikes >= cfg[:rewrite_limit]
    :routes_rewritten
  else
    infer_enforcement(
      hosts,
      routed,
      difference(as_set(cfg[:applied]), as_set(lost_hosts)),
      stale_hosts,
      overlay
    )
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
      stale: stale_of(routes_ok, table_r, gw_addr, stale_hosts),
      held: if not routes_ok
        :unread
      elsif is_empty(held_hosts)
        :none
      else
        :present
      end
    },
    {
      gateway_addr: gw_addr,
      gateway_iface: gw_iface,
      hosts:,
      routed:,
      stale_hosts:,
      held_hosts:,
      lost_hosts:,
      orphan_hosts:,
      peer_hosts:,
      fingerprint: fingerprint(
        corp,
        gw_addr,
        if cfg[:platform] == :nixos
          ""
        else
          iface_addr
        end,
        obs[:public_ip]
      ),
      iface_addr: if iface_addr.nil?
        ""
      else
        iface_addr
      end,
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
  nc = capture(netcheck_argv(ts))
  host = cfg[:control_host]
  if cfg[:platform] == :nixos
    ip = cfg[:ip]
    {
      routes: from_capture(capture(ip_route_argv(ip)), parse_ip_route),
      rules: from_capture(capture(ip_rule_argv(ip)), parse_ip_rules),
      status: from_capture(capture(status_argv(ts)), parse_backend_state),
      netcheck: from_capture(nc, parse_netcheck),
      public_ip: from_capture(nc, parse_public_ip),
      derp: from_capture(capture(derp_map_argv(ts)), parse_derp_map),
      control: from_capture(
        capture(getent_argv(cfg[:getent], host)),
        parse_getent
      ),
      peers: peers_observed(cfg),
      table: from_capture(
        capture(ip_table_argv(ip, cfg[:table])),
        parse_ip_route
      )
    }
  else
    {
      routes: from_capture(capture(netstat_argv), parse_netstat),
      addrs: from_capture(capture(ifconfig_argv), parse_ifconfig),
      rules: ok([]),
      table: ok([]),
      status: from_capture(capture(status_argv(ts)), parse_backend_state),
      netcheck: from_capture(nc, parse_netcheck),
      public_ip: from_capture(nc, parse_public_ip),
      derp: from_capture(capture(derp_map_argv(ts)), parse_derp_map),
      control: from_capture(capture(dscacheutil_argv(host)), parse_dscacheutil),
      peers: peers_observed(cfg)
    }
  end
end

@doc """
peers_observed: the peer endpoints read from the network map, or an empty list without a read when peer endpoints are configured off.

    peers_observed({peers: false})[:value] #=> []
"""
def peers_observed(cfg)
  if cfg[:peers]
    from_capture(capture(netmap_argv(cfg[:tailscale])), parse_peer_endpoints)
  else
    ok([])
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

@doc """
read_state: the state document the last run wrote at `path`, or nil when there is none or it does not parse.

    read_state("/nonexistent/ukai/state.json") #=> nil
"""
def read_state(path)
  json_parse(read_or(path, "")) rescue nil
end

@doc """
applied_of: the hosts a state document says this side applied; [] for no document, and only the strings of its list.

    applied_of(nil) #=> []
"""
def applied_of(doc)
  xs = as_json(doc, "applied")
  if xs.nil? or not list?(xs)
    []
  else
    filter((x) -> string?(x), xs)
  end
end

@doc """
applied_addr_of: the interface address a state document says this side added its routes through; "" when it names none.

    applied_addr_of(nil) #=> ""
"""
def applied_addr_of(doc)
  a = as_json(doc, "applied_addr")
  if string?(a)
    a
  else
    ""
  end
end

@doc """
next_applied_addr: the interface address the routes this side holds after a run were added through. A dry run or a failure keeps the record; no held host clears it; a bypass records the address it added through.

    next_applied_addr("192.0.2.177", {kind: :bypass}, [], false, "192.0.2.122", ["a"]) #=> "192.0.2.122"
    next_applied_addr("192.0.2.177", {kind: :noop}, [], false, "192.0.2.122", []) #=> ""
"""
def next_applied_addr(prev, o, failed, dry_run, iface_addr, applied)
  if dry_run or not is_empty(failed)
    prev
  elsif is_empty(applied)
    ""
  elsif o[:kind] == :bypass
    iface_addr
  else
    prev
  end
end

@doc """
strings_of: the strings of the list a state document holds at `key`; [] for no document or no list.

    strings_of(nil, "peers") #=> []
"""
def strings_of(doc, key)
  xs = as_json(doc, key)
  if xs.nil? or not list?(xs)
    []
  else
    filter((x) -> string?(x), xs)
  end
end

@doc """
rewrites_of: the times a state document says routes were taken away under a full tunnel; [] when it names none.

    rewrites_of(nil) #=> []
"""
def rewrites_of(doc)
  xs = as_json(doc, "rewrites_ms")
  if xs.nil? or not list?(xs)
    []
  else
    filter((x) -> integer?(x), xs)
  end
end

@doc """
next_peers: the applied hosts that are peer endpoints after a run: those the last record or this run named as peer endpoints, among what this side still holds.

    next_peers(["a"], ["b"], ["a", "b", "c"]) #=> ["a", "b"]
"""
def next_peers(prev, now_peers, applied)
  sorted(filter((h) -> member?(h, applied), unique(append(prev, now_peers))))
end

@doc """
read_applied: the hosts the state document at `path` says this side applied.

    read_applied("/nonexistent/ukai/state.json") #=> []
"""
def read_applied(path)
  applied_of(read_state(path))
end

@doc """
tunables: the settings ukai reads through settei: whether peer endpoints join the bypass; how many losses of its routes inside the window refuse the bypass until the window passes; whether a settled network change restarts the overlay, after how many runs and how long after the last restart, and the systemctl that does it on nixos (UKAI_PEER_ENDPOINTS, UKAI_REWRITE_LIMIT, UKAI_REWRITE_WINDOW_S, UKAI_RESTART_ON_CHANGE, UKAI_SETTLE_RUNS, UKAI_RESTART_COOLDOWN_S, UKAI_SYSTEMCTL).

    tunables["rewrite_limit"] #=> 3
"""
def tunables()
  {
    "peer_endpoints" => true,
    "rewrite_limit" => 3,
    "rewrite_window_s" => 900,
    "restart_on_change" => true,
    "settle_runs" => 2,
    "restart_cooldown_s" => 600,
    "systemctl" => "systemctl"
  }
end

def config()
  tuned = settei::read("ukai", tunables)
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
    peers: tuned["peer_endpoints"],
    rewrite_limit: tuned["rewrite_limit"],
    rewrite_window_ms: tuned["rewrite_window_s"] * 1000,
    restart_on_change: tuned["restart_on_change"],
    settle_runs: tuned["settle_runs"],
    restart_cooldown_ms: tuned["restart_cooldown_s"] * 1000,
    systemctl: tuned["systemctl"],
    dry_run: getenv("UKAI_DRY_RUN", "1") != "0",
    state_path: getenv("UKAI_STATE", "/var/run/ukai/state.json")
  }
end

@doc """
poll_of: the seconds between two runs, from the last run's `checked_ms`, for the heartbeat; 30 when there is no last run, and never under 30.

    poll_of(nil, 90000) #=> 30
    poll_of(0, 90000) #=> 90
"""
def poll_of(last_ms, now)
  secs = if last_ms.nil? or not integer?(last_ms) or last_ms > now
    0
  else
    floor((now - last_ms + 999) / 1000)
  end
  if secs < 30
    30
  else
    secs
  end
end

@doc """
beat: the overlay's verdict in the heartbeat form plantao's inbox reads. It is failed when a route command failed or the overlay is down (stopped or logged out) or reaches nothing, degraded when an axis is unread, and ok otherwise; the detail names the outcome and the state.

    beat({overlay: :relay}, {kind: :bypass}, [], 1000, 30) #=> {verdict: "ok", detail: "bypass", at_unix_ms: 1000, poll_seconds: 30}
    beat({overlay: :down, corp: :absent}, {kind: :noop, reason: :overlay_down}, [], 1000, 30)[:verdict] #=> "failed"
"""
def beat(s, o, failed, now, poll)
  label = outcome_label(o)
  vd = if not is_empty(failed)
    [
      "failed",
      "#{to_s(size(failed))} route command(s) failed: #{first(failed)}"
    ]
  elsif o[:kind] == :blind
    ["degraded", "unread: #{label}"]
  elsif member?(s[:overlay], %i[down none])
    [
      "failed",
      "overlay #{to_s(s[:overlay])}: #{label} (corp #{to_s(s[:corp])}, enforcement #{to_s(s[:enforcement])})"
    ]
  else
    ["ok", label]
  end
  {verdict: vd[0], detail: vd[1], at_unix_ms: now, poll_seconds: poll}
end

@doc """
persist: write each [path, text] of `writes` whole (fairu::write_atomic), and raise `:unwritable` naming the first path that could not be written.

    persist([]) #=> []
"""
def persist(writes)
  map(
    fn(w)
      if not fairu::write_atomic(w[0], w[1])
        raise(:unwritable, "ukai could not write #{w[0]}")
      end
    end,
    writes
  )
end

def run(cfg)
  now = now_ms
  last = read_state(cfg[:state_path])
  cfg2 = reduce(
    (c, kv) -> assoc(c, kv[0], kv[1]),
    cfg,
    [
      [:applied, applied_of(last)],
      [:applied_addr, applied_addr_of(last)],
      [:peer_applied, strings_of(last, "peers")],
      [:rewrites_ms, rewrites_of(last)],
      [:now, now]
    ]
  )
  s = assemble(cfg2, observe(cfg2))
  o = decide(s)
  argvs = plan(o, cfg2)
  results = act(argvs, cfg2[:dry_run])
  ep = next_epoch(
    epoch_of(last),
    s[:fingerprint],
    now,
    cfg2[:settle_runs],
    cfg2[:restart_cooldown_ms],
    as_json(last, "restarted_ms")
  )
  restart = ep[:restart] and cfg2[:restart_on_change] and not cfg2[:dry_run]
  restarted = if restart
    act([restart_argv(cfg2[:platform], cfg2[:systemctl])], false)
  else
    []
  end
  failed = filter(
    (r) -> r[:status] != 0 and r[:status] != nil,
    append(results, restarted)
  )
  held_now = if cfg2[:dry_run]
    cfg2[:applied]
  else
    difference(as_set(cfg2[:applied]), as_set(s[:lost_hosts]))
  end
  applied = next_applied(held_now, o, failed, cfg2[:dry_run])
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
    applied:,
    peers: next_peers(cfg2[:peer_applied], s[:peer_hosts], applied),
    rewrites_ms: next_rewrites(
      cfg2[:rewrites_ms],
      now,
      cfg2[:rewrite_window_ms],
      not cfg2[:dry_run] and s[:corp] == :full and not is_empty(s[:lost_hosts])
    ),
    epoch: ep[:epoch],
    epoch_pending: ep[:pending],
    epoch_runs: ep[:runs],
    restarted_ms: if restart
      now
    else
      as_json(last, "restarted_ms")
    end,
    applied_addr: next_applied_addr(
      cfg2[:applied_addr],
      o,
      failed,
      cfg2[:dry_run],
      s[:iface_addr],
      applied
    )
  }
  persist(
    [
      [cfg2[:state_path], json_stringify(record)],
      [
        path_join(path_dirname(cfg2[:state_path]), "beat.json"),
        json_stringify(
          beat(
            s,
            o,
            record[:failed],
            now,
            poll_of(as_json(last, "checked_ms"), now)
          )
        )
      ]
    ]
  )
  write_stdout(
    unlines(
      [
        "#{outcome_label(o)} #{row_key(s)} planned=#{to_s(size(argvs))} failed=#{to_s(size(failed))}#{if restart
  " restarted=overlay"
else
  ""
end}"
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
    addrs: parse_ifconfig(fairu::fixture("ukai", "ifconfig.txt")),
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
  assert size(states) == 4 * 5 * 5 * 3 * 2 * 2 * 3 * 3
  assert size(states) == 10800
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
      ["full\tpermissive\trelay\tpresent\tresolved\tsolaris\tnone\tnone\tbypass"]
    )
  )
  assert first(first(tesuto::matrix_findings(axes, verdict, stray, states))) ==
    :row_without_variant
  flipped = replace(
    text,
    "full\tpermissive\trelay\tpresent\tresolved\tdarwin\tnone\tnone\tbypass",
    "full\tpermissive\trelay\tpresent\tresolved\tdarwin\tnone\tnone\tnoop:no_corp_tunnel"
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
        first(r) ==
          "full\tpermissive\trelay\tpresent\tresolved\tdarwin\tnone\tnone"
      end,
      rows
    )
  )
  assert last(r) == "bypass"
  moved = first(
    filter(
      fn(r)
        first(r) ==
          "absent\tunknown\tnone\tpresent\tresolved\tdarwin\tpresent\tnone"
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
  ) == 10800 - 3 * 4 * 4 * 2 * 1 * 2 * 2 * 2
  assert decide(assoc(assoc(s, :corp, :absent), :held, :unread))[:unread] ==
    [:held]
  assert decide(assoc(assoc(s, :corp, :unread), :held, :present))[:retract].nil?
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
  assert row_key(s) ==
    "full\tunknown\tnone\tpresent\tresolved\tdarwin\tnone\tnone"
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
    "full\tpermissive\tdirect\tpresent\tresolved\tdarwin\tnone\tnone"
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
  base = assoc(
    assoc(
      assoc(cfg_for(:darwin, ["199.38.181.93"]), :rewrite_limit, 3),
      :rewrite_window_ms,
      900_000
    ),
    :now,
    1_000_000
  )
  first_loss = assemble(base, obs)
  assert first_loss[:lost_hosts] == ["199.38.181.93"]
  assert first_loss[:enforcement] == :unknown
  o = decide(first_loss)
  assert o[:kind] == :bypass
  assert member?("199.38.181.93", o[:routes][:add]) == true
  third = assemble(assoc(base, :rewrites_ms, [500_000, 900_000]), obs)
  assert third[:enforcement] == :routes_rewritten
  assert decide(third) == {kind: :refused, reason: :enforcement_rewrites_routes}
  aged = assemble(assoc(base, :rewrites_ms, [1, 2]), obs)
  assert decide(aged)[:kind] == :bypass
  calm = assemble(
    assoc(assoc(base, :applied, []), :rewrites_ms, [900_000, 950_000, 990_000]),
    measured(
      fairu::fixture("ukai", "netstat-full-bypassed.txt"),
      fairu::fixture("ukai", "netcheck-bypassed.json")
    )
  )
  assert calm[:lost_hosts] == []
  assert decide(calm) == {kind: :refused, reason: :enforcement_rewrites_routes}
  split = assemble(
    assoc(
      assoc(base, :applied, ["203.0.113.8"]),
      :rewrites_ms,
      [900_000, 950_000]
    ),
    measured(
      fairu::fixture("ukai", "netstat-site-moved.txt"),
      fairu::fixture("ukai", "netcheck-blocked.json")
    )
  )
  assert split[:lost_hosts] == ["203.0.113.8"]
  assert split[:enforcement] != :routes_rewritten
end

test "lost routes: the hosts taken away, the loss times kept inside the window, and a loss under no full tunnel never counts"
  assert lost_of(%w[a b c b], ["a"], ["c"]) == ["b"]
  assert lost_of(["a"], ["a"], []) == []
  assert recent_rewrites([100, 900, "x", 2000], 1000, 500) == [900]
  assert recent_rewrites(nil, 1000, 500) == []
  assert next_rewrites([100, 900], 1000, 500, true) == [900, 1000]
  assert next_rewrites([100, 900], 1000, 500, false) == [900]
  assert rewrites_of(nil) == []
  assert tunables["rewrite_window_s"] == 900
  assert tunables["peer_endpoints"] == true
  assert rewrites_of(json_parse(json_stringify({rewrites_ms: [5, "x"]}))) == [5]
end

test "peer endpoints: each peer's public IPv4 endpoint joins the bypass, a private, shared, link-local or IPv6 one never does, and one no peer names any more is retracted while control and relay routes stay"
  r = parse_peer_endpoints(fixture("netmap.json"))
  assert r[:value] == %w[198.51.100.30 203.0.113.107 203.0.113.61]
  assert ok?(parse_peer_endpoints("nope")) == false
  assert parse_peer_endpoints("{}")[:value] == []
  assert public_ipv4?("172.32.0.1") == true
  assert public_ipv4?("172.31.0.1") == false
  assert public_ipv4?("100.128.0.1") == true
  assert public_ipv4?("224.0.0.1") == false
  assert public_ipv4?("not-an-ip") == false
  assert endpoint_host("203.0.113.7") == ""
  assert public_ipv4?("192.0.0.6") == false
  assert public_ipv4?("192.0.1.6") == true
  assert public_ipv4?("198.18.0.1") == false
  assert public_ipv4?("198.20.0.1") == true
  assert netmap_argv("/bin/ts") == %w[/bin/ts debug netmap]
  assert peers_observed({peers: false})[:value] == []
  bypassed = measured(
    fairu::fixture("ukai", "netstat-full-bypassed.txt"),
    fairu::fixture("ukai", "netcheck-bypassed.json")
  )
  s = assemble(cfg_for(:darwin, []), assoc(bypassed, :peers, r))
  assert member?("192.168.50.3", s[:hosts]) == false
  o = decide(s)
  assert o[:kind] == :bypass
  assert member?("203.0.113.107", o[:routes][:add]) == true
  text = concat(
    fairu::fixture("ukai", "netstat-full-bypassed.txt"),
    unlines(
      [
        "203.0.113.9        192.168.60.1       UGHS                  en0       ",
        "203.0.113.10       192.168.60.1       UGHS                  en0       "
      ]
    )
  )
  routed = measured(text, fairu::fixture("ukai", "netcheck-bypassed.json"))
  cfg = assoc(
    cfg_for(:darwin, %w[203.0.113.9 203.0.113.10 199.38.181.93]),
    :peer_applied,
    %w[203.0.113.9 199.38.181.93]
  )
  so = assemble(cfg, assoc(routed, :peers, r))
  assert so[:orphan_hosts] == ["203.0.113.9"]
  oo = decide(so)
  assert outcome_label(oo) == "bypass+retract"
  assert oo[:retract][:hosts] == ["203.0.113.9"]
  quiet = assoc(fill(first(tesuto::axis_states(axes))), :orphan_hosts, ["x"])
  assert decide(quiet)[:kind] != :bypass
  assert decide(quiet)[:retract].nil?
  su = assemble(cfg, assoc(routed, :peers, bad("tailscale exited 1")))
  assert su[:orphan_hosts] == []
  assert outcome_label(decide(su)) == "bypass"
  assert next_peers(["203.0.113.9"], ["203.0.113.107"], ["203.0.113.107"]) ==
    ["203.0.113.107"]
  assert strings_of(json_parse(json_stringify({peers: ["a", 3]})), "peers") ==
    ["a"]
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
    %i[corp enforcement gateway targets stale held]
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
  assert get(
    assemble(cfg, assoc(obs, :public_ip, ok("203.0.113.7"))),
    :fingerprint
  ) == "full|192.168.1.1||203.0.113.7"
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
    "absent\tunknown\tnone\tpresent\tresolved\tdarwin\tpresent\tnone"
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

test "a detour outlives no detour: with no corporate tunnel every route this side applied through its own gateway is retracted, and under a full tunnel that refuses it is kept"
  text = replace(
    fairu::fixture("ukai", "netstat-site-moved.txt"),
    "192.168.50.1",
    "192.168.60.1"
  )
  cfg = cfg_for(:darwin, moved_applied)
  s = assemble(
    cfg,
    measured(text, fairu::fixture("ukai", "netcheck-blocked.json"))
  )
  assert row_key(s) ==
    "absent\tegress_blocked\tnone\tpresent\tresolved\tdarwin\tnone\tpresent"
  o = decide(s)
  assert outcome_label(o) == "noop:no_corp_tunnel+retract"
  assert plan(o, cfg) ==
    [
      %w[/sbin/route -n delete -host 192.200.0.102],
      %w[/sbin/route -n delete -host 199.38.181.93],
      %w[/sbin/route -n delete -host 5.161.218.233]
    ]
  assert next_applied(moved_applied, o, [], false) == []
  full = concat(
    text,
    unlines(
      [
        "0/1                utun7              UScg                utun7       ",
        "128.0/1            utun7              UScg                utun7       "
      ]
    )
  )
  held = assemble(
    cfg,
    measured(full, fairu::fixture("ukai", "netcheck-blocked.json"))
  )
  assert held[:held] == :present
  assert decide(held) == {kind: :refused, reason: :enforcement_blocks_egress}
  assert held_of(%w[a b], %w[b a c b], ["a"]) == ["b"]
  assert held_of([], ["a"], []) == []
end

test "ifconfig: each interface's IPv4 address, and none from an interface with only inet6"
  rows = parse_ifconfig(fairu::fixture("ukai", "ifconfig.txt"))[:value]
  assert addrs_of(rows, "en0") == ["192.0.2.122"]
  assert addrs_of(rows, "lo0") == ["127.0.0.1"]
  assert addrs_of(rows, "utun1") == []
  assert iface_addr_of({ok: true, value: rows}, "en7") == ""
  assert iface_addr_of(bad("ifconfig exited 1"), "en0").nil?
  assert ifconfig_line({cur: "", rows: []}, "en9: flags=0 mtu 1500")[:cur] ==
    "en9"
end

test "an address change on the same gateway retracts every route this side added through the old address and adds it back through the current one; an unchanged or unread address retracts nothing"
  full = concat(
    replace(
      fairu::fixture("ukai", "netstat-site-moved.txt"),
      "192.168.50.1",
      "192.168.60.1"
    ),
    unlines(
      [
        "0/1                utun7              UScg                utun7       ",
        "128.0/1            utun7              UScg                utun7       "
      ]
    )
  )
  cfg = assoc(cfg_for(:darwin, moved_applied), :applied_addr, "192.0.2.177")
  obs = measured(full, fairu::fixture("ukai", "netcheck-bypassed.json"))
  s = assemble(cfg, obs)
  assert s[:stale] == :present
  assert s[:iface_addr] == "192.0.2.122"
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
  applied = next_applied(moved_applied, o, [], false)
  assert member?("199.38.181.93", applied) == true
  assert next_applied_addr(
    "192.0.2.177",
    o,
    [],
    false,
    s[:iface_addr],
    applied
  ) == "192.0.2.122"
  blocked = assemble(
    cfg,
    measured(full, fairu::fixture("ukai", "netcheck-blocked.json"))
  )
  assert outcome_label(decide(blocked)) ==
    "refused:enforcement_blocks_egress+retract"
  same = assoc(cfg, :applied_addr, "192.0.2.122")
  assert assemble(same, obs)[:stale] == :none
  assert outcome_label(decide(assemble(same, obs))) == "bypass"
  unread = assemble(cfg, assoc(obs, :addrs, bad("ifconfig exited 1")))
  assert unread[:stale] == :none
  assert assemble(cfg_for(:darwin, moved_applied), obs)[:stale] == :none
end

test "the applied address: a bypass records the address it added through, no held host clears it, a dry run or a failure keeps it"
  assert next_applied_addr("a", {kind: :bypass}, [], false, "b", ["h"]) == "b"
  assert next_applied_addr("a", {kind: :noop}, [], false, "b", []) == ""
  assert next_applied_addr("a", {kind: :refused}, [], false, "b", ["h"]) == "a"
  assert next_applied_addr("a", {kind: :bypass}, ["x"], false, "b", ["h"]) ==
    "a"
  assert next_applied_addr("a", {kind: :bypass}, [], true, "b", ["h"]) == "a"
  assert applied_addr_of(nil) == ""
  assert applied_addr_of(
    json_parse(json_stringify({applied_addr: "192.0.2.1"}))
  ) == "192.0.2.1"
  assert addr_moved?(:nixos, "192.0.2.1", "192.0.2.2") == false
end

test "the beat fails when the overlay reaches nothing or is down, names why, and is ok only through a working overlay"
  split = {overlay: :none, corp: :split, enforcement: :routes_rewritten}
  b = beat(split, decide_kind(split), [], 5, 30)
  assert b[:verdict] == "failed"
  assert b[:detail] ==
    "overlay none: noop:split_tunnel_leaves_default (corp split, enforcement routes_rewritten)"
  corp = {overlay: :none, corp: :full, enforcement: :egress_blocked}
  assert contains?(
    beat(corp, refused(:enforcement_blocks_egress), [], 5, 30)[:detail],
    "refused:enforcement_blocks_egress (corp full"
  )
  assert beat({overlay: :down}, noop(:overlay_down), [], 5, 30)[:verdict] ==
    "failed"
  assert beat({overlay: :relay}, blind([:corp]), [], 5, 30)[:verdict] ==
    "degraded"
  assert get(
    beat({overlay: :direct}, {kind: :bypass}, ["route: x"], 5, 30),
    :detail
  ) == "1 route command(s) failed: route: x"
  ok = beat({overlay: :direct}, {kind: :bypass}, [], 7, 30)
  assert ok ==
    {verdict: "ok", detail: "bypass", at_unix_ms: 7, poll_seconds: 30}
  assert json_get(json_parse(json_stringify(ok)), :verdict) == "ok"
  assert poll_of(nil, 5000) == 30
  assert poll_of(1000, 121_000) == 120
  assert poll_of(1000, 121_001) == 121
  assert poll_of(9000, 1000) == 30
end

test "the state and the beat are written whole, and a path that cannot be written raises unwritable"
  dir = temp_dir("ukai-persist")
  persist(
    [
      [path_join(dir, "state.json"), "{}"],
      [path_join(dir, "beat.json"), "{\"verdict\":\"ok\"}"]
    ]
  )
  assert read_file(path_join(dir, "beat.json")) == "{\"verdict\":\"ok\"}"
  assert tesuto::raises?(
    :unwritable,
    () -> persist([[path_join(path_join(dir, "state.json"), "x"), "{}"]])
  ) == true
end

test "a run reads its last state once: the hosts it applied and when it last checked, and nothing from a missing or broken state"
  path = path_join(temp_dir("ukai-state"), "state.json")
  assert read_state(path).nil?
  assert read_applied(path) == []
  write_file(
    path,
    json_stringify({checked_ms: 1000, applied: ["192.0.2.1", 7]})
  )
  prior = read_state(path)
  assert applied_of(prior) == ["192.0.2.1"]
  assert read_applied(path) == ["192.0.2.1"]
  assert poll_of(as_json(prior, "checked_ms"), 121_000) == 120
  write_file(path, json_stringify({applied: "192.0.2.1"}))
  assert read_applied(path) == []
  write_file(path, "not json")
  assert read_state(path).nil?
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

test "a network change restarts the overlay once it settles: a new fingerprint held for the settle runs and past the cooldown restarts, a flap or an unread run does not"
  assert fingerprint(
    :split,
    "192.0.2.1",
    "192.0.2.122",
    {ok: true, value: ""}
  ) == "split|192.0.2.1|192.0.2.122|"
  assert fingerprint(:full, "192.0.2.1", nil, {ok: true, value: "x"}).nil?
  assert fingerprint(:full, "g", "a", bad("netcheck exited 1")).nil?
  first_seen = next_epoch(epoch_of(nil), "a", 1000, 2, 600, 0)
  assert first_seen == {epoch: "a", pending: "", runs: 0, restart: false}
  one = next_epoch(first_seen, "b", 1000, 2, 600, 0)
  assert one == {epoch: "a", pending: "b", runs: 1, restart: false}
  two = next_epoch(one, "b", 1030, 2, 600, 0)
  assert two == {epoch: "b", pending: "", runs: 0, restart: true}
  flap = next_epoch(one, "a", 1030, 2, 600, 0)
  assert flap == {epoch: "a", pending: "", runs: 0, restart: false}
  other = next_epoch(one, "c", 1030, 2, 600, 0)
  assert other[:runs] == 1
  assert other[:pending] == "c"
  unread = next_epoch(one, nil, 1030, 2, 600, 0)
  assert unread[:restart] == false
  assert unread[:pending] == "b"
  cooling = next_epoch(one, "b", 1030, 2, 600, 900)
  assert cooling == {epoch: "a", pending: "b", runs: 2, restart: false}
  assert next_epoch(cooling, "b", 1600, 2, 600, 900)[:restart] == true
  assert ok?(parse_public_ip(fixture("netcheck-bypassed.json"))) == true
  assert parse_public_ip("{}")[:value] == ""
  assert ok?(parse_public_ip("nope")) == false
  assert restart_argv(:nixos, "/bin/systemctl") ==
    %w[/bin/systemctl restart tailscaled.service]
  assert first(restart_argv(:darwin, "")) == "/bin/launchctl"
  doc = json_parse(
    json_stringify({epoch: "a", epoch_pending: "b", epoch_runs: 1})
  )
  assert epoch_of(doc) == {epoch: "a", pending: "b", runs: 1}
  assert tunables["settle_runs"] == 2
  obs = measured(
    fairu::fixture("ukai", "netstat-full-bypassed.txt"),
    fairu::fixture("ukai", "netcheck-bypassed.json")
  )
  s = assemble(cfg_for(:darwin, []), assoc(obs, :public_ip, ok("203.0.113.7")))
  assert s[:fingerprint] == "full|192.168.60.1|192.0.2.122|203.0.113.7"
end
