@moduledoc """
toride (砦) — a fort at the border: split-horizon DNS for a machine that roams between sites. It finds the site it stands on from the default route, the interface address and the gateway's MAC, and serves each name its LAN address at home, its tailnet address elsewhere, or withholds it with a reason.

    relation("natal", "natal") #=> :here
"""

use("deeta", %i[as_json get_if])
use("fairu")
use("kyohi", %i[ok refusal])
use("retsu", %i[first is_empty last rest size])
use("shisutemu", [:read_or])
use("tesuto")

use(
  "ukai",
  %i[
    after_word
    bad
    capture
    fields
    from_capture
    ip_route_argv
    ipv4?
    parse_ip_route
    parse_netstat
    unread_among
  ]
)

@doc """
axes: The closed set of axes one entry's answer depends on. `site` is the entry's site against the site the machine stands on.

    length(axes) #=> 5
"""
def axes()
  [
    [:site, %i[here elsewhere unknown ambiguous unread]],
    [:gateway, %i[up down unread]],
    [:entry, %i[node routed_service local_service]],
    [:lan, %i[inside outside]],
    [:platform, %i[darwin nixos]]
  ]
end

def axis_names()
  map(first, axes)
end

@doc """
state: An entry state over the axes; a value outside its axis is refused by name.

    (state({site: :sideways}) rescue :refused) #=> :refused
"""
def state(m)
  wrong = filter(
    (a) -> not member?(get(m, a), tesuto::variants(axes, a)),
    axis_names
  )
  if is_empty(wrong)
    m
  else
    raise(:not_a_variant, "no such variant on #{join(map(to_s, wrong), ", ")}")
  end
end

@doc """
decide: What one entry resolves to: its LAN address, its tailnet address, withheld with a reason, or blind when an axis could not be read.

    decide({site: :here, gateway: :up, entry: :node, lan: :inside, platform: :darwin}) #=> {kind: :serve, via: :lan}
"""
def decide(s)
  unread = unread_among(s, axis_names)
  if not is_empty(unread)
    {kind: :blind, unread:}
  elsif s[:site] == :here and s[:gateway] == :up
    {kind: :serve, via: :lan}
  elsif s[:entry] == :node
    {kind: :serve, via: :tailnet}
  elsif s[:entry] == :local_service
    {kind: :withheld, reason: :lan_only}
  elsif s[:lan] == :inside
    {kind: :withheld, reason: :shadowed_by_local_lan}
  else
    {kind: :serve, via: :lan}
  end
end

@doc """
outcome_label: An answer as one word, the matrix's outcome column.

    outcome_label({kind: :withheld, reason: :lan_only}) #=> "withheld:lan_only"
"""
def outcome_label(o)
  if o[:kind] == :blind
    "blind:#{join(map(to_s, o[:unread]), ",")}"
  elsif o[:kind] == :serve
    to_s(o[:via])
  else
    "withheld:#{to_s(o[:reason])}"
  end
end

def verdict(s)
  outcome_label(decide(s))
end

@doc """
ip_int: A dotted IPv4 address as one integer.

    ip_int("192.168.50.1") #=> 3232248321
"""
def ip_int(ip)
  reduce((acc, o) -> acc * 256 + to_int(o), 0, split(ip, "."))
end

@doc """
int_ip: An integer as a dotted IPv4 address.

    int_ip(3232248321) #=> "192.168.50.1"
"""
def int_ip(n)
  join(map((d) -> to_s(floor(n / d) % 256), [16_777_216, 65536, 256, 1]), ".")
end

@doc """
span: How many addresses a prefix length covers.

    span(24) #=> 256
"""
def span(prefix)
  reduce((acc, _i) -> acc * 2, 1, range(0, 32 - prefix))
end

@doc """
parse_cidr: `a.b.c.d/n` as its network and prefix, or nil when it is not one.

    parse_cidr("192.168.50.7/24") #=> {network: 3232248320, prefix: 24}
"""
def parse_cidr(text)
  ps = split(text, "/")
  p = if size(ps) == 2
    to_int(last(ps))
  end
  if size(ps) != 2 or not ipv4?(first(ps)) or p.nil? or p < 0 or p > 32
    nil
  else
    {network: floor(ip_int(first(ps)) / span(p)) * span(p), prefix: p}
  end
end

@doc """
inside?: Whether an address lies in a network.

    inside?("192.168.60.9", parse_cidr("192.168.60.0/24")) #=> true
"""
def inside?(ip, net)
  floor(ip_int(ip) / span(net[:prefix])) ==
    floor(net[:network] / span(net[:prefix]))
end

@doc """
mask_prefix: The prefix length of a netmask written in hex, as ifconfig prints it.

    mask_prefix("0xffffff00") #=> 24
"""
def mask_prefix(hex)
  digits = chars(downcase(replace(hex, "0x", "")))
  n = reduce((acc, c) -> acc * 16 + position(c, hex_digits), 0, digits)
  size(filter((i) -> bit_and(n, span(32 - i)) != 0, range(0, 32)))
end

def hex_digits()
  chars("0123456789abcdef")
end

@doc """
normal_mac: A MAC address in lower case with two digits an octet, or nil when it is not one. darwin's arp drops leading zeros.

    normal_mac("2:0:5E:60:0:1") #=> "02:00:5e:60:00:01"
"""
def normal_mac(text)
  os = split(downcase(text), ":")
  good = fn(o)
    size(chars(o)) >= 1 and
      size(chars(o)) <= 2 and
      is_empty(filter((c) -> not member?(c, hex_digits), chars(o)))
  end
  if size(os) == 6 and is_empty(filter((o) -> not good(o), os))
    join(
      map(
        fn(o)
          if size(chars(o)) == 1
            "0#{o}"
          else
            o
          end
        end,
        os
      ),
      ":"
    )
  end
end

@doc """
redacted?: macOS shows an unprivileged reader every MAC as 02:00:00:00:00:00; that is no reading at all.

    redacted?("02:00:00:00:00:00") #=> true
"""
def redacted?(mac)
  mac == "02:00:00:00:00:00"
end

@doc """
defaults: Every setting's typed default; the Rust daemon's literals live here and nowhere else.

    get(defaults, :dnsmasq_conf) #=> "/etc/dnsmasq.d/toride.conf"
"""
def defaults()
  {
    platform: :darwin,
    dry_run: true,
    state_path: "/var/run/toride/state.json",
    dnsmasq_conf: "/etc/dnsmasq.d/toride.conf",
    reload: %w[killall -HUP dnsmasq],
    probe_ports: [53, 80, 443],
    probe_timeout_ms: 1000,
    probe_interval_s: 10,
    fail_threshold: 3,
    heartbeat_interval: 30,
    netstat: "/usr/sbin/netstat",
    arp: "/usr/sbin/arp",
    ifconfig: "/sbin/ifconfig",
    ip: "ip"
  }
end

@doc """
settings: Each setting's reader: its key and the kind of value it takes.

    length(settings) #=> 14
"""
def settings()
  [
    %i[platform platform],
    %i[dry_run flag],
    %i[state_path path],
    %i[dnsmasq_conf path],
    %i[reload argv],
    %i[probe_ports ports],
    %i[probe_timeout_ms count],
    %i[probe_interval_s count],
    %i[fail_threshold count],
    %i[heartbeat_interval count],
    %i[netstat program],
    %i[arp program],
    %i[ifconfig program],
    %i[ip program]
  ]
end

@doc """
read_setting: A setting's JSON value read as its kind: `[:ok, value]`, or `[:bad, why]`.

    read_setting(:count, 0) #=> [:bad, "not a whole number of at least 1"]
"""
def read_setting(kind, v)
  if kind == :platform and v == "nixos"
    %i[ok nixos]
  elsif kind == :platform and v == "darwin"
    %i[ok darwin]
  elsif kind == :platform
    [:bad, "not darwin or nixos"]
  elsif kind == :flag and boolean?(v)
    [:ok, v]
  elsif kind == :flag
    [:bad, "not true or false"]
  elsif kind == :path and string?(v) and starts_with?(v, "/")
    [:ok, v]
  elsif kind == :path
    [:bad, "not an absolute path"]
  elsif kind == :program and string?(v) and v != "" and not contains?(v, " ")
    [:ok, v]
  elsif kind == :program
    [:bad, "not a program name or path"]
  elsif kind == :argv and words?(v)
    [:ok, v]
  elsif kind == :argv
    [:bad, "not a non-empty list of words"]
  elsif kind == :ports and ports?(v)
    [:ok, v]
  elsif kind == :ports
    [:bad, "not a non-empty list of ports"]
  elsif integer?(v) and v >= 1
    [:ok, v]
  else
    [:bad, "not a whole number of at least 1"]
  end
end

def words?(v)
  v != nil and
    list?(v) and
    not is_empty(v) and
    is_empty(filter((w) -> not string?(w) or w == "", v))
end

def ports?(v)
  v != nil and
    list?(v) and
    not is_empty(v) and
    is_empty(filter((p) -> not integer?(p) or p < 1 or p > 65535, v))
end

@doc """
domain?: Whether text can stand in a dnsmasq `address=/name/ip` line.

    domain?("plo.pleme.internal") #=> true
"""
def domain?(d)
  string?(d) and
    d != "" and
    is_empty(filter((c) -> member?(c, ["/", " ", "#", "\t"]), chars(d)))
end

def domains?(v)
  v != nil and
    list?(v) and
    not is_empty(v) and
    is_empty(filter((d) -> not domain?(d), v))
end

@doc """
read_site: One site entry: `[:ok, site]` or `[:bad, refusal]`. The gateway defaults to the network's first address; the MAC is optional and, when given, must be one.

    first(read_site({}, [])) #=> :bad
"""
def read_site(doc, taken)
  name = get_if(doc, "name", string?, "")
  net = parse_cidr(get_if(doc, "cidr", string?, ""))
  gw_text = as_json(doc, "gateway")
  mac_text = as_json(doc, "gateway_mac")
  gateway = if gw_text.nil? and net != nil
    int_ip(net[:network] + 1)
  else
    gw_text
  end
  mac = if string?(mac_text)
    normal_mac(mac_text)
  end
  why = if name == ""
    "has no name"
  elsif member?(name, taken)
    "is named twice"
  elsif net.nil?
    "has no cidr a.b.c.d/n"
  elsif not string?(gateway) or not ipv4?(gateway)
    "has a gateway that is not an IPv4 address"
  elsif not inside?(gateway, net)
    "has a gateway outside its cidr"
  elsif mac_text != nil and mac.nil?
    "has a gateway_mac that is not a MAC address"
  end
  if why.nil?
    [:ok, {name:, net:, gateway:, gateway_mac: mac}]
  else
    [:bad, refusal(:bad_site, "site #{label_of(name)} #{why}")]
  end
end

def label_of(name)
  if name == ""
    "(unnamed)"
  else
    name
  end
end

def site_named(sites, name)
  first(filter((s) -> s[:name] == name, sites))
end

@doc """
read_node: One node: name, site, lan and tailnet addresses, domains. Its LAN address must lie in its site's network.

    first(read_node(json_parse("{}"), [])) #=> :bad
"""
def read_node(doc, sites)
  name = get_if(doc, "name", string?, "")
  site = site_named(sites, get_if(doc, "site", string?, ""))
  lan = get_if(doc, "lan", string?, "")
  tailnet = get_if(doc, "tailnet", string?, "")
  domains = as_json(doc, "domains")
  why = if name == ""
    "has no name"
  elsif site.nil?
    "names no configured site"
  elsif not ipv4?(lan)
    "has a lan address that is not IPv4"
  elsif not inside?(lan, site[:net])
    "has a lan address outside its site"
  elsif not ipv4?(tailnet)
    "has a tailnet address that is not IPv4"
  elsif not domains?(domains)
    "has no domains, or one that is not a name"
  end
  if why.nil?
    [:ok, {kind: :node, name:, site: site[:name], lan:, tailnet:, domains:}]
  else
    [:bad, refusal(:bad_node, "node #{label_of(name)} #{why}")]
  end
end

@doc """
read_service: One service: domains, site, its LAN address, and whether a subnet route reaches it off site (`subnet_routed`, default false).

    first(read_service(json_parse("{}"), [])) #=> :bad
"""
def read_service(doc, sites)
  domains = as_json(doc, "domains")
  name = if domains?(domains)
    first(domains)
  else
    ""
  end
  site = site_named(sites, get_if(doc, "site", string?, ""))
  ip = get_if(doc, "ip", string?, "")
  routed = as_json(doc, "subnet_routed")
  why = if name == ""
    "has no domains, or one that is not a name"
  elsif site.nil?
    "names no configured site"
  elsif not ipv4?(ip)
    "has an address that is not IPv4"
  elsif not inside?(ip, site[:net])
    "has an address outside its site"
  elsif routed != nil and not boolean?(routed)
    "has a subnet_routed that is not true or false"
  end
  kind = if routed == true
    :routed_service
  else
    :local_service
  end
  if why.nil?
    [:ok, {kind:, name:, site: site[:name], lan: ip, tailnet: nil, domains:}]
  else
    [:bad, refusal(:bad_service, "service #{label_of(name)} #{why}")]
  end
end

@doc """
tagged: the values of the `[tag, value]` pairs in `rs` whose tag is `tag`, in order.

    tagged(:ok, [[:ok, 1], [:bad, 2], [:ok, 3]]) #=> [1, 3]
"""
def tagged(tag, rs)
  map(last, filter((r) -> first(r) == tag, rs))
end

def doc_list(doc, key)
  v = as_json(doc, key)
  if v != nil and list?(v)
    v
  else
    []
  end
end

def read_sites(docs)
  reduce(
    fn(acc, d)
      r = read_site(d, map((s) -> s[:name], tagged(:ok, acc)))
      append(acc, [r])
    end,
    [],
    docs
  )
end

@doc """
load: A config from its JSON text. Each setting, site, node and service is read alone: a malformed one is refused by name and its siblings stand. Text that is not a JSON object is unreadable, never an empty config.

    get(load("not json"), :readable) #=> false
"""
def load(text)
  doc = if string?(text)
    json_parse(text) rescue nil
  end
  if not object?(doc)
    assoc(defaults, :readable, false)
  else
    keys = if doc == {}
      []
    else
      map(first, doc)
    end
    known = append(
      map((s) -> to_s(first(s)), settings),
      %w[sites nodes services]
    )
    unknown = map(
      (k) -> refusal(:unknown_setting, "setting #{k} is not one toride reads"),
      filter((k) -> not member?(k, known), keys)
    )
    read = reduce(
      fn(acc, s)
        v = as_json(doc, to_s(first(s)))
        r = if v.nil?
          [:ok, get(defaults, first(s))]
        else
          read_setting(last(s), v)
        end
        if first(r) == :ok
          assoc(acc, first(s), last(r))
        else
          assoc(
            acc,
            :refusals,
            append(
              acc[:refusals],
              [refusal(:bad_setting, "#{to_s(first(s))} #{last(r)}")]
            )
          )
        end
      end,
      assoc(defaults, :refusals, unknown),
      settings
    )
    site_rs = read_sites(doc_list(doc, "sites"))
    sites = tagged(:ok, site_rs)
    entry_rs = append(
      map((d) -> read_node(d, sites), doc_list(doc, "nodes")),
      map((d) -> read_service(d, sites), doc_list(doc, "services"))
    )
    assoc(
      assoc(
        assoc(
          assoc(read, :readable, true),
          :refusals,
          append(
            append(read[:refusals], tagged(:bad, site_rs)),
            tagged(:bad, entry_rs)
          )
        ),
        :sites,
        sites
      ),
      :entries,
      tagged(:ok, entry_rs)
    )
  end
end

def object?(doc)
  doc == {} or
    doc != nil and
      list?(doc) and
      not null?(doc) and
      list?(first(doc)) and
      size(first(doc)) == 2 and
      string?(first(first(doc)))
end

@doc """
default_gateway: The first default route through an IPv4 gateway, as `{gateway:, iface:}`, or nil.

    default_gateway([]) #=> nil
"""
def default_gateway(routes)
  r = first(filter((r) -> r[:dest] == "default" and ipv4?(r[:gateway]), routes))
  if r != nil
    {gateway: r[:gateway], iface: r[:iface]}
  end
end

@doc """
parse_ifconfig: The interface's first IPv4 address and prefix from darwin's `ifconfig IFACE`.

    get(parse_ifconfig(""), :ok) #=> false
"""
def parse_ifconfig(text)
  fs = first(
    filter((f) -> first(f) == "inet", map(fields, split(text, line_break)))
  )
  mask = if fs != nil
    after_word(fs, "netmask")
  end
  if fs.nil? or mask.nil? or not ipv4?(fs[1])
    bad("ifconfig: no inet line with a netmask")
  else
    ok({addr: fs[1], prefix: mask_prefix(mask)})
  end
end

@doc """
parse_ip_addr: The interface's IPv4 address and prefix from `ip -4 -o addr`.

    get(parse_ip_addr("", "eth0"), :ok) #=> false
"""
def parse_ip_addr(text, iface)
  fs = first(
    filter(
      (f) -> size(f) > 3 and f[1] == iface,
      map(fields, split(text, line_break))
    )
  )
  a = if fs != nil
    after_word(fs, "inet")
  end
  ps = if a != nil
    split(a, "/")
  end
  if a.nil? or size(ps) != 2 or not ipv4?(first(ps))
    bad("ip addr: no inet address on #{iface}")
  else
    ok({addr: first(ps), prefix: to_int(last(ps))})
  end
end

@doc """
parse_arp: darwin's `arp -an` as `{ip:, mac:, iface:}` rows; an incomplete entry is no row. An unprivileged reader is shown no rows at all.

    parse_arp("") #=> {ok: true, value: []}
"""
def parse_arp(text)
  ok(
    filter(
      (r) -> r != nil,
      map((l) -> arp_row(fields(l)), split(text, line_break))
    )
  )
end

def arp_row(fs)
  ip = if size(fs) > 1
    replace(replace(fs[1], "(", ""), ")", "")
  end
  mac = after_word(fs, "at")
  if ip != nil and ipv4?(ip) and mac != nil and normal_mac(mac) != nil
    {ip:, mac: normal_mac(mac), iface: after_word(fs, "on")}
  end
end

@doc """
parse_ip_neigh: `ip -4 neigh` as `{ip:, mac:, iface:}` rows; a FAILED or INCOMPLETE entry carries no lladdr and is no row.

    parse_ip_neigh("10.0.0.1 dev eth0 FAILED") #=> {ok: true, value: []}
"""
def parse_ip_neigh(text)
  ok(
    filter(
      (r) -> r != nil,
      map((l) -> neigh_row(fields(l)), split(text, line_break))
    )
  )
end

def neigh_row(fs)
  mac = after_word(fs, "lladdr")
  if not is_empty(fs) and
      ipv4?(first(fs)) and
      mac != nil and
      normal_mac(mac) != nil
    {ip: first(fs), mac: normal_mac(mac), iface: after_word(fs, "dev")}
  end
end

@doc """
mac_of: The gateway's MAC from the neighbour rows on its interface, or :unread when there is no usable row.

    mac_of([], "10.0.0.1", "en0") #=> :unread
"""
def mac_of(rows, ip, iface)
  r = first(
    filter(
      (r) -> r[:ip] == ip and r[:iface] == iface and not redacted?(r[:mac]),
      rows
    )
  )
  if r.nil?
    :unread
  else
    r[:mac]
  end
end

@doc """
match_site: The configured site the machine stands on, from the sites whose network holds the interface address and whose gateway is the default gateway. A MAC, where a site names one, decides between them; when it is needed and unread the answer is :unread, and two sites left standing are :ambiguous. Neither ever picks one.

    match_site([], :unread) #=> :unknown
"""
def match_site(candidates, mac)
  needs = filter((c) -> c[:gateway_mac] != nil, candidates)
  loose = filter((c) -> c[:gateway_mac].nil?, candidates)
  matched = filter((c) -> c[:gateway_mac] == mac, needs)
  pool = if mac == :unread and not is_empty(needs)
    nil
  elsif mac == :unread or is_empty(matched)
    loose
  else
    matched
  end
  if pool.nil?
    :unread
  elsif is_empty(pool)
    :unknown
  elsif size(pool) > 1
    :ambiguous
  else
    first(pool)[:name]
  end
end

@doc """
debounce: The gateway axis from one probe and the failures before it: a down probe holds `up` until `threshold` fail in a row. Answers `[axis, streak]`.

    debounce(false, 0, 3) #=> [:up, 1]
"""
def debounce(reachable, streak, threshold)
  if reachable
    [:up, 0]
  elsif streak + 1 >= threshold
    [:down, streak + 1]
  else
    [:up, streak + 1]
  end
end

@doc """
assemble: The machine's run state from its observations: which site it stands on, whether the gateway answers, and the local network.

    get(assemble(load("{}"), {routes: {ok: false, why: "x"}}, {}), :site) #=> :unread
"""
def assemble(cfg, obs, prior)
  streak = prior[:streak] or 0
  routes_r = obs[:routes]
  gw = if routes_r[:ok]
    default_gateway(routes_r[:value])
  end
  local_r = obs[:local]
  neigh_r = obs[:neighbours]
  probe_r = obs[:probe]
  local = if gw != nil and local_r[:ok]
    {
      network: floor(
        ip_int(local_r[:value][:addr]) / span(local_r[:value][:prefix])
      ) * span(local_r[:value][:prefix]),
      prefix: local_r[:value][:prefix]
    }
  end
  mac = if gw != nil and neigh_r[:ok]
    mac_of(neigh_r[:value], gw[:gateway], gw[:iface])
  else
    :unread
  end
  site = if not routes_r[:ok]
    :unread
  elsif gw.nil?
    :unknown
  elsif not local_r[:ok]
    :unread
  else
    match_site(
      filter(
        fn(s)
          inside?(local_r[:value][:addr], s[:net]) and
            s[:gateway] == gw[:gateway]
        end,
        cfg[:sites]
      ),
      mac
    )
  end
  g = if not routes_r[:ok]
    [:unread, streak]
  elsif gw.nil?
    [:down, cfg[:fail_threshold]]
  elsif not probe_r[:ok]
    [:unread, streak]
  else
    debounce(probe_r[:value], streak, cfg[:fail_threshold])
  end
  {
    site:,
    gateway: first(g),
    streak: last(g),
    platform: cfg[:platform],
    local:,
    gateway_addr: if gw != nil
      gw[:gateway]
    end,
    mac:
  }
end

@doc """
relation: An entry's site against the site the machine stands on.

    relation("buzios", :ambiguous) #=> :ambiguous
"""
def relation(entry_site, site)
  if not string?(site)
    site
  elsif entry_site == site
    :here
  else
    :elsewhere
  end
end

def entry_state(e, run)
  state(
    {
      site: relation(e[:site], run[:site]),
      gateway: run[:gateway],
      entry: e[:kind],
      lan: if run[:local] != nil and inside?(e[:lan], run[:local])
        :inside
      else
        :outside
      end,
      platform: run[:platform]
    }
  )
end

@doc """
answer: One entry's decision with the address it is served at, nil when it is withheld or blind.

    get(answer({kind: :node, site: "a", lan: "10.0.0.2", tailnet: "100.64.0.2", domains: ["a"]}, {site: "a", gateway: :up, platform: :darwin}), :address) #=> "10.0.0.2"
"""
def answer(e, run)
  o = decide(entry_state(e, run))
  address = if o[:kind] == :serve and o[:via] == :lan
    e[:lan]
  elsif o[:kind] == :serve
    e[:tailnet]
  end
  {entry: e, outcome: o, address:}
end

@doc """
render: The dnsmasq conf text for a run: one `address=` line per served domain, and a comment naming each withheld one with its reason.

    starts_with?(render({site: :unknown, gateway: :down}, []), "# Generated by toride") #=> true
"""
def render(run, answers)
  head = [
    "# Generated by toride; do not edit",
    "# site: #{to_s(run[:site])} gateway: #{to_s(run[:gateway])}"
  ]
  body = reduce(
    fn(acc, a)
      append(
        acc,
        map(
          fn(d)
            if a[:address] != nil
              "address=/#{d}/#{a[:address]}"
            else
              "# withheld #{d}: #{to_s(a[:outcome][:reason])}"
            end
          end,
          a[:entry][:domains]
        )
      )
    end,
    [],
    answers
  )
  unlines(append(head, body))
end

@doc """
converge: Render the answers for a run and, when the text differs from the file, write it atomically and reload dnsmasq; a dry run only says so. Blind writes nothing.

    get(converge(load("{}"), {site: :unread, gateway: :unread}, live), :result) #=> "blind:site,gateway"
"""
def converge(cfg, run, io)
  if not is_empty(unread_among(run, %i[site gateway]))
    {
      result: "blind:#{join(map(to_s, unread_among(run, %i[site gateway])), ",")}",
      answers: [],
      text: nil
    }
  else
    answers = map((e) -> answer(e, run), cfg[:entries])
    text = render(run, answers)
    path = cfg[:dnsmasq_conf]
    result = if read_or(path, "") == text
      "unchanged"
    elsif cfg[:dry_run]
      "would-write"
    elsif write_atomic(path, text) != true
      "write-failed"
    elsif reloaded(io, cfg[:reload]) != 0
      "reload-failed"
    else
      "written"
    end
    {result:, answers:, text:}
  end
end

def reloaded(io, argv)
  exec = io[:exec]
  exec(argv)[:status]
end

def write_atomic(path, text)
  mkdir_p(path_dirname(path))
  write_file("#{path}.tmp", text)
  rename_file("#{path}.tmp", path)
  true
rescue _e
  false
end

@doc """
routes_argv: The command that reads the main route table on a platform.

    routes_argv(load("{}")) #=> ["/usr/sbin/netstat", "-rn", "-f", "inet"]
"""
def routes_argv(cfg)
  if cfg[:platform] == :nixos
    ip_route_argv(cfg[:ip])
  else
    [cfg[:netstat], "-rn", "-f", "inet"]
  end
end

@doc """
local_argv: The command that reads an interface's address on a platform.

    local_argv(load("{}"), "en0") #=> ["/sbin/ifconfig", "en0"]
"""
def local_argv(cfg, iface)
  if cfg[:platform] == :nixos
    [cfg[:ip], "-4", "-o", "addr", "show", "dev", iface]
  else
    [cfg[:ifconfig], iface]
  end
end

@doc """
neigh_argv: The command that reads the neighbour table on a platform.

    neigh_argv(load("{}"), "en0") #=> ["/usr/sbin/arp", "-an"]
"""
def neigh_argv(cfg, iface)
  if cfg[:platform] == :nixos
    [cfg[:ip], "-4", "neigh", "show", "dev", iface]
  else
    [cfg[:arp], "-an"]
  end
end

@doc """
probe: Whether the gateway accepts a TCP connection on any of the ports, the timeout shared between them; a probe that cannot be made is bad, never down.

    get(probe("127.0.0.1", [], 100), :ok) #=> false
"""
def probe(addr, ports, timeout_ms)
  if is_empty(ports)
    bad("probe: no ports")
  else
    share = floor(timeout_ms / size(ports))
    per = if share < 1
      1
    else
      share
    end
    r = reach(addr, ports, per) rescue nil
    if r.nil?
      bad("probe: #{addr} could not be probed")
    else
      ok(r)
    end
  end
end

def reach(addr, ports, per)
  if is_empty(ports)
    false
  elsif number?(tcp_connect_ms(addr, first(ports), per))
    true
  else
    reach(addr, rest(ports), per)
  end
end

@doc """
live: The machine's own effects: commands run by `capture`, the gateway reached by `probe`. A test hands `observe` and `run` its own.

    live[:exec] != nil #=> true
"""
def live()
  {exec: capture, probe:}
end

@doc """
observe: Read the route table, the default interface's address, the neighbour table and the gateway probe through `io`. What cannot be read is bad, so the run is blind, never empty.

    get(get(observe(assoc(load("{}"), :netstat, "/nonexistent/netstat"), live), :routes), :ok) #=> false
"""
def observe(cfg, io)
  exec = io[:exec]
  prober = io[:probe]
  nixos = cfg[:platform] == :nixos
  routes = from_capture(
    exec(routes_argv(cfg)),
    if nixos
      parse_ip_route
    else
      parse_netstat
    end
  )
  gw = if routes[:ok]
    default_gateway(routes[:value])
  end
  if gw.nil?
    {
      routes:,
      local: bad("no default route"),
      neighbours: bad("no default route"),
      probe: bad("no default route")
    }
  else
    {
      routes:,
      local: from_capture(
        exec(local_argv(cfg, gw[:iface])),
        if nixos
          (t) -> parse_ip_addr(t, gw[:iface])
        else
          parse_ifconfig
        end
      ),
      neighbours: from_capture(
        exec(neigh_argv(cfg, gw[:iface])),
        if nixos
          parse_ip_neigh
        else
          parse_arp
        end
      ),
      probe: prober(gw[:gateway], cfg[:probe_ports], cfg[:probe_timeout_ms])
    }
  end
end

def read_prior(path)
  doc = json_parse(read_or(path, "")) rescue nil
  {
    streak: get_if(doc, "streak", integer?, 0),
    runs: get_if(doc, "runs", integer?, 0),
    line: get_if(doc, "line", string?, "")
  }
end

@doc """
outcome_line: The run's one line: result, site, gateway, and how many names were served, withheld and refused.

    outcome_line({result: "unchanged", answers: []}, {site: "natal", gateway: :up}, []) #=> "unchanged site=natal gateway=up served=0 withheld=0 refused=0"
"""
def outcome_line(c, run, refusals)
  served = filter((a) -> a[:address] != nil, c[:answers])
  "#{c[:result]} site=#{to_s(run[:site])} gateway=#{to_s(run[:gateway])} served=#{to_s(size(served))} withheld=#{to_s(size(c[:answers]) - size(served))} refused=#{to_s(size(refusals))}"
end

@doc """
loud?: Whether a run prints its line: when the line changed, and on every heartbeat.

    loud?("a", "a", 4, 30) #=> false
"""
def loud?(line, prior_line, runs, heartbeat)
  line != prior_line or runs % heartbeat == 0
end

@doc """
run: One pass through `io`: observe, decide every entry, converge the dnsmasq conf, record the state file, and print the outcome line when it changed or on a heartbeat. An unreadable config is refused and writes nothing.

    get(run(assoc(load(nil), :state_path, "#{tesuto::fresh_dir("toride-doc")}/s.json"), live), :result) #=> "refused:config_unreadable"
"""
def run(cfg, io)
  prior = read_prior(cfg[:state_path])
  r = if cfg[:readable]
    s = assemble(cfg, observe(cfg, io), prior)
    {run: s, c: converge(cfg, s, io)}
  else
    {
      run: {site: :unread, gateway: :unread, streak: prior[:streak]},
      c: {result: "refused:config_unreadable", answers: [], text: nil}
    }
  end
  refusals = cfg[:refusals] or []
  line = outcome_line(r[:c], r[:run], refusals)
  runs = prior[:runs] + 1
  record = {
    checked_ms: now_ms,
    line:,
    result: r[:c][:result],
    site: to_s(r[:run][:site]),
    gateway: to_s(r[:run][:gateway]),
    streak: r[:run][:streak],
    runs:,
    dry_run: cfg[:dry_run],
    refused: map(last, refusals)
  }
  write_atomic(cfg[:state_path], json_stringify(record))
  if loud?(line, prior[:line], runs, cfg[:heartbeat_interval])
    write_stdout(unlines([line]))
  end
  record
end

def main()
  run(
    load(read_or(getenv("TORIDE_CONFIG", "/etc/toride/config.json"), nil)),
    live
  )
end

def config()
  load(fairu::fixture("toride", "config.json"))
end

def natal_commands()
  [
    [
      "ip -4 route show table main",
      fairu::fixture("toride", "ip-route-natal.txt")
    ],
    [
      "ip -4 -o addr show dev wlo1",
      fairu::fixture("toride", "ip-addr-natal.txt")
    ],
    [
      "ip -4 neigh show dev wlo1",
      fairu::fixture("toride", "ip-neigh-natal.txt")
    ],
    ["/usr/bin/true", ""]
  ]
end

def buzios_commands(arp)
  [
    [
      "/usr/sbin/netstat -rn -f inet",
      fairu::fixture("toride", "netstat-buzios.txt")
    ],
    ["/sbin/ifconfig en0", fairu::fixture("toride", "ifconfig-buzios.txt")],
    ["/usr/sbin/arp -an", fairu::fixture("toride", arp)],
    ["/usr/bin/true", ""]
  ]
end

def fake(commands, probed)
  {
    exec: fn(argv)
      hit = first(filter((c) -> first(c) == join(argv, " "), commands))
      if hit.nil?
        {
          argv:,
          started: false,
          status: -1,
          stdout: "",
          stderr: "could not start #{first(argv)}"
        }
      else
        {argv:, started: true, status: 0, stdout: last(hit), stderr: ""}
      end
    end,
    probe: (_addr, _ports, _ms) -> probed
  }
end

def at(cfg, commands, probed, streak)
  assemble(cfg, observe(cfg, fake(commands, probed)), {streak:})
end

def served(cfg, run)
  reduce(
    fn(m, a)
      v = if a[:address].nil?
        outcome_label(a[:outcome])
      else
        a[:address]
      end
      assoc(m, a[:entry][:name], v)
    end,
    {},
    map((e) -> answer(e, run), cfg[:entries])
  )
end

def darwin(cfg)
  assoc(cfg, :platform, :darwin)
end

def without_site(cfg, name)
  assoc(
    assoc(cfg, :sites, filter((s) -> s[:name] != name, cfg[:sites])),
    :entries,
    filter((e) -> e[:site] != name, cfg[:entries])
  )
end

def site_mac(cfg, name, mac)
  assoc(
    cfg,
    :sites,
    map(
      fn(s)
        if s[:name] == name
          assoc(s, :gateway_mac, mac)
        else
          s
        end
      end,
      cfg[:sites]
    )
  )
end

def in_dir(cfg)
  dir = tesuto::fresh_dir("toride")
  assoc(
    assoc(
      assoc(cfg, :dnsmasq_conf, "#{dir}/dnsmasq.d/toride.conf"),
      :state_path,
      "#{dir}/state/state.json"
    ),
    :reload,
    ["/usr/bin/true"]
  )
end

test "the matrix: every variant of every axis has exactly one row, and decide agrees with each"
  states = tesuto::axis_states(axes)
  assert size(states) == 5 * 3 * 3 * 2 * 2
  assert size(states) == 180
  assert tesuto::matrix_findings(
    axes,
    verdict,
    fairu::fixture("toride", "matrix.tsv"),
    states
  ) == []
end

test "the matrix gate goes red on a missing row, a stray row and a wrong decision"
  states = tesuto::axis_states(axes)
  text = fairu::fixture("toride", "matrix.tsv")
  short = replace(text, unlines(["here\tup\tnode\tinside\tdarwin\tlan"]), "")
  assert tesuto::matrix_findings(axes, verdict, short, states) ==
    [[:missing_row, "here\tup\tnode\tinside\tdarwin"]]
  stray = concat(text, unlines(["here\tup\tnode\tinside\tsolaris\tlan"]))
  assert tesuto::matrix_findings(axes, verdict, stray, states) ==
    [[:row_without_variant, "here\tup\tnode\tinside\tsolaris"]]
  flipped = replace(
    text,
    "elsewhere\tup\tnode\toutside\tdarwin\ttailnet",
    "elsewhere\tup\tnode\toutside\tdarwin\tlan"
  )
  assert first(
    first(tesuto::matrix_findings(axes, verdict, flipped, states))
  ) == :decision_disagrees
  assert tesuto::matrix_text(axes, verdict, states) == text
end

test "decide: home serves the LAN, away serves the tailnet, and a service off site keeps its LAN address only through a subnet route it does not shadow"
  s = {site: :here, gateway: :up, entry: :node, lan: :inside, platform: :darwin}
  assert verdict(s) == "lan"
  assert verdict(assoc(s, :gateway, :down)) == "tailnet"
  assert verdict(assoc(s, :site, :elsewhere)) == "tailnet"
  assert verdict(assoc(s, :site, :ambiguous)) == "tailnet"
  assert verdict(assoc(s, :site, :unknown)) == "tailnet"
  r = assoc(assoc(s, :entry, :routed_service), :site, :elsewhere)
  assert verdict(r) == "withheld:shadowed_by_local_lan"
  assert verdict(assoc(r, :lan, :outside)) == "lan"
  assert verdict(assoc(r, :entry, :local_service)) == "withheld:lan_only"
  assert verdict(assoc(s, :entry, :local_service)) == "lan"
  assert verdict(assoc(s, :site, :unread)) == "blind:site"
  assert verdict(assoc(assoc(s, :site, :unread), :gateway, :unread)) ==
    "blind:site,gateway"
  assert size(
    filter((x) -> decide(x)[:kind] == :blind, tesuto::axis_states(axes))
  ) == 180 - 4 * 2 * 3 * 2 * 2
  assert (state(assoc(s, :entry, :printer)) rescue :refused) == :refused
  assert state(s) == s
end

test "addresses and networks: dotted quads, prefixes, netmasks and MACs"
  assert int_ip(ip_int("10.20.30.40")) == "10.20.30.40"
  assert span(32) == 1
  assert span(0) == 4_294_967_296
  net = parse_cidr("192.168.50.0/24")
  assert inside?("192.168.50.255", net) == true
  assert inside?("192.168.51.0", net) == false
  assert parse_cidr("192.168.50.0").nil?
  assert parse_cidr("192.168.50.0/33").nil?
  assert parse_cidr("192.168.50.0/-1").nil?
  assert parse_cidr("192.168.500.0/24").nil?
  assert parse_cidr("10.0.0.0/x").nil?
  assert parse_cidr("0.0.0.0/0") == {network: 0, prefix: 0}
  assert mask_prefix("0xffff0000") == 16
  assert mask_prefix("0xFFFFFFFC") == 30
  assert normal_mac("02:00:5E:50:00:01") == "02:00:5e:50:00:01"
  assert normal_mac("2:0:5e:50:0").nil?
  assert normal_mac("2:0:5e:50:0:1:7").nil?
  assert normal_mac("02:00:5e:50:00:0g").nil?
  assert normal_mac("02:00:5e:50:00:001").nil?
  assert normal_mac("02:00:5e:50::01").nil?
  assert redacted?("02:00:5e:50:00:01") == false
end

test "settings: each takes its typed default, and a malformed one is refused by name while its siblings stand"
  d = load("{}")
  assert d[:readable] == true
  assert d[:refusals] == []
  assert d[:platform] == :darwin
  assert d[:dry_run] == true
  assert d[:state_path] == "/var/run/toride/state.json"
  assert d[:reload] == %w[killall -HUP dnsmasq]
  assert d[:probe_ports] == [53, 80, 443]
  assert d[:probe_timeout_ms] == 1000
  assert d[:probe_interval_s] == 10
  assert d[:fail_threshold] == 3
  assert d[:heartbeat_interval] == 30
  assert d[:netstat] == "/usr/sbin/netstat"
  assert d[:ip] == "ip"
  assert d[:sites] == []
  assert d[:entries] == []
  c = load(
    json_stringify(
      {
        platform: "solaris",
        dry_run: "no",
        dnsmasq_conf: "relative/toride.conf",
        reload: [],
        probe_ports: [53, 70000],
        fail_threshold: 0,
        arp: "arp -an",
        gateway: "192.168.50.1",
        probe_timeout_ms: 250,
        ifconfig: "/usr/local/sbin/ifconfig"
      }
    )
  )
  assert map(last, c[:refusals]) ==
    [
      "setting gateway is not one toride reads",
      "platform not darwin or nixos",
      "dry_run not true or false",
      "dnsmasq_conf not an absolute path",
      "reload not a non-empty list of words",
      "probe_ports not a non-empty list of ports",
      "fail_threshold not a whole number of at least 1",
      "arp not a program name or path"
    ]
  assert c[:platform] == :darwin
  assert c[:fail_threshold] == 3
  assert c[:probe_timeout_ms] == 250
  assert c[:ifconfig] == "/usr/local/sbin/ifconfig"
  assert load(json_stringify({platform: "nixos"}))[:platform] == :nixos
  assert load(json_stringify({platform: "darwin"}))[:refusals] == []
  assert load(json_stringify({dry_run: false}))[:dry_run] == false
  assert load(json_stringify({reload: ["/bin/kill", ""]}))[:reload] ==
    %w[killall -HUP dnsmasq]
  assert load(json_stringify({probe_ports: "53"}))[:probe_ports] ==
    [53, 80, 443]
  assert load(json_stringify({ip: ""}))[:ip] == "ip"
  assert load(nil)[:readable] == false
  assert load("[[1, 2]]")[:readable] == false
  assert load("[[\"a\", 1, 2]]")[:readable] == false
  assert load(json_stringify({sites: "natal"}))[:sites] == []
  assert load("[1, 2]")[:readable] == false
  assert load("not json")[:readable] == false
end

test "sites, nodes and services: a malformed entry is refused alone, by name, and valid siblings proceed"
  cfg = config
  assert cfg[:refusals] == []
  assert map((s) -> s[:name], cfg[:sites]) ==
    %w[natal bristol buzios parnamirim]
  natal = first(cfg[:sites])
  assert natal[:gateway] == "192.168.50.1"
  assert last(cfg[:sites])[:gateway] == "192.168.70.1"
  assert last(cfg[:sites])[:gateway_mac].nil?
  assert cfg[:sites][2][:gateway_mac] == "02:00:5e:60:00:01"
  assert map((e) -> e[:kind], cfg[:entries]) ==
    %i[node node routed_service routed_service local_service]
  bad_text = json_stringify(
    {
      sites: [
        {name: "a", cidr: "10.1.0.0/16"},
        {name: "a", cidr: "10.2.0.0/16"},
        {cidr: "10.3.0.0/16"},
        {name: "c", cidr: "10.4.0.0"},
        {name: "d", cidr: "10.5.0.0/16", gateway: "10.6.0.1"},
        {name: "e", cidr: "10.7.0.0/16", gateway: "ten"},
        {name: "f", cidr: "10.8.0.0/16", gateway_mac: "nope"}
      ],
      nodes: [
        {
          name: "ok",
          site: "a",
          lan: "10.1.0.2",
          tailnet: "100.64.0.2",
          domains: ["ok"]
        },
        {site: "a", lan: "10.1.0.3", tailnet: "100.64.0.3", domains: ["x"]},
        {
          name: "n1",
          site: "zz",
          lan: "10.1.0.3",
          tailnet: "100.64.0.3",
          domains: ["x"]
        },
        {
          name: "n2",
          site: "a",
          lan: "10.1.0",
          tailnet: "100.64.0.3",
          domains: ["x"]
        },
        {
          name: "n3",
          site: "a",
          lan: "10.9.0.3",
          tailnet: "100.64.0.3",
          domains: ["x"]
        },
        {name: "n4", site: "a", lan: "10.1.0.3", tailnet: "", domains: ["x"]},
        {
          name: "n5",
          site: "a",
          lan: "10.1.0.3",
          tailnet: "100.64.0.3",
          domains: []
        },
        {
          name: "n6",
          site: "a",
          lan: "10.1.0.3",
          tailnet: "100.64.0.3",
          domains: ["a/b"]
        }
      ],
      services: [
        {domains: ["s.ok"], site: "a", ip: "10.1.0.9"},
        {domains: [], site: "a", ip: "10.1.0.9"},
        {domains: ["s1"], site: "zz", ip: "10.1.0.9"},
        {domains: ["s2"], site: "a", ip: "x"},
        {domains: ["s3"], site: "a", ip: "10.9.0.9"},
        {domains: ["s4"], site: "a", ip: "10.1.0.9", subnet_routed: "yes"}
      ]
    }
  )
  c = load(bad_text)
  assert map((s) -> s[:name], c[:sites]) == ["a"]
  assert map((e) -> e[:name], c[:entries]) == %w[ok s.ok]
  assert map(last, c[:refusals]) ==
    [
      "site a is named twice",
      "site (unnamed) has no name",
      "site c has no cidr a.b.c.d/n",
      "site d has a gateway outside its cidr",
      "site e has a gateway that is not an IPv4 address",
      "site f has a gateway_mac that is not a MAC address",
      "node (unnamed) has no name",
      "node n1 names no configured site",
      "node n2 has a lan address that is not IPv4",
      "node n3 has a lan address outside its site",
      "node n4 has a tailnet address that is not IPv4",
      "node n5 has no domains, or one that is not a name",
      "node n6 has no domains, or one that is not a name",
      "service (unnamed) has no domains, or one that is not a name",
      "service s1 names no configured site",
      "service s2 has an address that is not IPv4",
      "service s3 has an address outside its site",
      "service s4 has a subnet_routed that is not true or false"
    ]
  assert first(first(c[:refusals])) == :bad_site
  assert first(last(c[:refusals])) == :bad_service
  assert domain?(7) == false
  assert domain?("") == false
end

test "darwin parsers over the measured Búzios captures: netstat, ifconfig and a root arp table"
  rs = parse_netstat(fairu::fixture("toride", "netstat-buzios.txt"))[:value]
  assert default_gateway(rs) == {gateway: "192.168.60.1", iface: "en0"}
  assert default_gateway(
    [{dest: "default", gateway: "link#14", flags: "UCS", iface: "en0"}]
  ).nil?
  assert get(
    parse_ifconfig(fairu::fixture("toride", "ifconfig-buzios.txt")),
    :value
  ) == {addr: "192.168.60.138", prefix: 24}
  assert parse_ifconfig(unlines(["\tinet 10.0.0.2"]))[:ok] == false
  assert parse_ifconfig(unlines(["\tinet nope netmask 0xffffff00"]))[:ok] ==
    false
  arp = parse_arp(fairu::fixture("toride", "arp-buzios.txt"))[:value]
  assert size(arp) == 14
  assert mac_of(arp, "192.168.60.1", "en0") == "02:00:5e:60:00:01"
  assert mac_of(arp, "192.168.60.1", "en1") == :unread
  assert mac_of(arp, "192.168.60.3", "en0") == :unread
  assert parse_arp(fairu::fixture("toride", "arp-unprivileged.txt"))[:value] ==
    []
  assert get(
    parse_arp("? (10.0.0.1) at 2:0:5e:0:0:1 on en7 ifscope [ethernet]"),
    :value
  ) == [{ip: "10.0.0.1", mac: "02:00:5e:00:00:01", iface: "en7"}]
  assert get(
    parse_arp("? (not.an.ip) at 02:00:5e:60:00:01 on en0 ifscope"),
    :value
  ) == []
  assert get(
    parse_arp("? (10.0.0.1) at 02:00:00:00:00:00 on en0 ifscope [ethernet]"),
    :value
  ) == [{ip: "10.0.0.1", mac: "02:00:00:00:00:00", iface: "en0"}]
  assert mac_of(
    [{ip: "10.0.0.1", mac: "02:00:00:00:00:00", iface: "en0"}],
    "10.0.0.1",
    "en0"
  ) == :unread
end

test "nixos parsers over the measured Natal captures: ip route, ip addr and ip neigh"
  rs = parse_ip_route(fairu::fixture("toride", "ip-route-natal.txt"))[:value]
  assert default_gateway(rs) == {gateway: "192.168.50.1", iface: "wlo1"}
  assert get(
    parse_ip_addr(fairu::fixture("toride", "ip-addr-natal.txt"), "wlo1"),
    :value
  ) == {addr: "192.168.50.3", prefix: 24}
  assert get(
    parse_ip_addr(fairu::fixture("toride", "ip-addr-natal.txt"), "eth9"),
    :ok
  ) == false
  assert parse_ip_addr("3: wlo1    inet nope/24 brd x", "wlo1")[:ok] == false
  n = parse_ip_neigh(fairu::fixture("toride", "ip-neigh-natal.txt"))[:value]
  assert size(n) == 8
  assert mac_of(n, "192.168.50.1", "wlo1") == "02:00:5e:50:00:01"
  assert mac_of(n, "192.168.50.2", "wlo1") == :unread
  assert mac_of(n, "192.168.50.1", "eth0") == :unread
  assert get(
    parse_ip_neigh("10.0.0.1 dev eth0 lladdr 02:00:5E:00:00:01 REACHABLE"),
    :value
  ) == [{ip: "10.0.0.1", mac: "02:00:5e:00:00:01", iface: "eth0"}]
  assert parse_ip_neigh("10.0.0.1 dev eth0 lladdr nope REACHABLE")[:value] == []
  assert get(
    parse_ip_neigh("fe80::1 dev wlo1 lladdr 02:00:5e:50:00:01 router"),
    :value
  ) == []
end

test "site matching: subnet and gateway filter, a MAC decides, and neither an unread MAC nor a tie ever picks one"
  cfg = config
  natal = first(cfg[:sites])
  bristol = cfg[:sites][1]
  loose_n = assoc(natal, :gateway_mac, nil)
  loose_b = assoc(bristol, :gateway_mac, nil)
  assert match_site([natal, bristol], "02:00:5e:50:00:01") == "natal"
  assert match_site([natal, bristol], "02:00:5e:b0:00:01") == "bristol"
  assert match_site([natal, bristol], "02:00:5e:99:00:01") == :unknown
  assert match_site([natal, bristol], :unread) == :unread
  assert match_site([loose_n, loose_b], "02:00:5e:50:00:01") == :ambiguous
  assert match_site([loose_n, loose_b], :unread) == :ambiguous
  assert match_site([loose_n], :unread) == "natal"
  assert match_site([natal, loose_b], "02:00:5e:50:00:01") == "natal"
  assert match_site([natal, loose_b], "02:00:5e:99:00:01") == "bristol"
  assert match_site([natal, loose_b], :unread) == :unread
  assert match_site(
    [natal, assoc(bristol, :gateway_mac, natal[:gateway_mac])],
    natal[:gateway_mac]
  ) == :ambiguous
  assert match_site([], "02:00:5e:50:00:01") == :unknown
  assert relation("natal", "natal") == :here
  assert relation("natal", "buzios") == :elsewhere
  assert relation("natal", :unknown) == :unknown
end

test "the gateway is down only after fail_threshold probes fail in a row"
  assert debounce(true, 5, 3) == [:up, 0]
  assert debounce(false, 1, 3) == [:up, 2]
  assert debounce(false, 2, 3) == [:down, 3]
  assert debounce(false, 0, 1) == [:down, 1]
end

test "on Natal (nixos, measured): home names on the LAN, Búzios through its subnet route, the lan-only printer withheld"
  cfg = config
  run = at(cfg, natal_commands, ok(true), 0)
  assert run[:site] == "natal"
  assert run[:gateway] == :up
  assert run[:mac] == "02:00:5e:50:00:01"
  assert run[:local] == {network: ip_int("192.168.50.0"), prefix: 24}
  assert served(cfg, run) ==
    {
      "plo" => "192.168.50.3",
      "zek" => "192.168.50.20",
      "hue.natal.pleme.internal" => "192.168.50.183",
      "cid.buzios.pleme.internal" => "192.168.60.138",
      "printer.parnamirim.pleme.internal" => "withheld:lan_only"
    }
  text = render(run, map((e) -> answer(e, run), cfg[:entries]))
  assert text ==
    unlines(
      [
        "# Generated by toride; do not edit",
        "# site: natal gateway: up",
        "address=/plo.pleme.internal/192.168.50.3",
        "address=/plo/192.168.50.3",
        "address=/zek.pleme.internal/192.168.50.20",
        "address=/hue.natal.pleme.internal/192.168.50.183",
        "address=/cid.buzios.pleme.internal/192.168.60.138",
        "# withheld printer.parnamirim.pleme.internal: lan_only"
      ]
    )
end

test "on Búzios (darwin, measured): Natal's nodes on the tailnet, Búzios's own entry on the LAN, Natal's routed service kept"
  cfg = darwin(config)
  run = at(cfg, buzios_commands("arp-buzios.txt"), ok(true), 0)
  assert run[:site] == "buzios"
  assert served(cfg, run) ==
    {
      "plo" => "100.64.0.110",
      "zek" => "100.64.0.20",
      "hue.natal.pleme.internal" => "192.168.50.183",
      "cid.buzios.pleme.internal" => "192.168.60.138",
      "printer.parnamirim.pleme.internal" => "withheld:lan_only"
    }
end

test "on an unknown LAN: no site claims it, so every node is on the tailnet"
  cfg = without_site(darwin(config), "buzios")
  run = at(cfg, buzios_commands("arp-buzios.txt"), ok(true), 0)
  assert run[:site] == :unknown
  assert served(cfg, run) ==
    {
      "plo" => "100.64.0.110",
      "zek" => "100.64.0.20",
      "hue.natal.pleme.internal" => "192.168.50.183",
      "printer.parnamirim.pleme.internal" => "withheld:lan_only"
    }
  gone = [
    [
      "/usr/sbin/netstat -rn -f inet",
      unlines(["Destination  Gateway  Flags  Netif"])
    ]
  ]
  offline = at(cfg, gone, ok(true), 0)
  assert offline[:site] == :unknown
  assert offline[:gateway] == :down
  moved = map(
    fn(s)
      if s[:name] == "buzios"
        assoc(s, :gateway, "192.168.60.254")
      else
        s
      end
    end,
    config[:sites]
  )
  other_router = at(
    darwin(assoc(config, :sites, moved)),
    buzios_commands("arp-buzios.txt"),
    ok(true),
    0
  )
  assert other_router[:site] == :unknown
  narrow = map(
    fn(s)
      if s[:name] == "buzios"
        assoc(s, :net, parse_cidr("192.168.60.0/30"))
      else
        s
      end
    end,
    config[:sites]
  )
  other_net = at(
    darwin(assoc(config, :sites, narrow)),
    buzios_commands("arp-buzios.txt"),
    ok(true),
    0
  )
  assert other_net[:site] == :unknown
end

test "on an ambiguous LAN: Natal and Bristol share a subnet and a gateway; the MAC decides, and with no MAC neither is picked"
  cfg = config
  bristol = at(
    site_mac(
      site_mac(cfg, "natal", "02:00:5e:aa:00:01"),
      "bristol",
      "02:00:5e:50:00:01"
    ),
    natal_commands,
    ok(true),
    0
  )
  assert bristol[:site] == "bristol"
  assert served(cfg, bristol)["plo"] == "100.64.0.110"
  assert served(cfg, bristol)["hue.natal.pleme.internal"] ==
    "withheld:shadowed_by_local_lan"
  loose = site_mac(site_mac(cfg, "natal", nil), "bristol", nil)
  run = at(loose, natal_commands, ok(true), 0)
  assert run[:site] == :ambiguous
  assert served(loose, run) ==
    {
      "plo" => "100.64.0.110",
      "zek" => "100.64.0.20",
      "hue.natal.pleme.internal" => "withheld:shadowed_by_local_lan",
      "cid.buzios.pleme.internal" => "192.168.60.138",
      "printer.parnamirim.pleme.internal" => "withheld:lan_only"
    }
end

test "gateway unreachable: held on the LAN until the threshold, then home names move to the tailnet"
  cfg = config
  held = at(cfg, natal_commands, ok(false), 1)
  assert held[:gateway] == :up
  assert held[:streak] == 2
  down = at(cfg, natal_commands, ok(false), 2)
  assert down[:gateway] == :down
  assert down[:streak] == 3
  assert served(cfg, down)["plo"] == "100.64.0.110"
  assert served(cfg, down)["hue.natal.pleme.internal"] ==
    "withheld:shadowed_by_local_lan"
  assert served(cfg, down)["cid.buzios.pleme.internal"] == "192.168.60.138"
end

test "an unreadable observation is blind, never empty, and blind writes nothing"
  cfg = in_dir(config)
  nothing = at(cfg, [], ok(true), 0)
  assert nothing[:site] == :unread
  assert nothing[:gateway] == :unread
  c = converge(cfg, nothing, fake([], ok(true)))
  assert c[:result] == "blind:site,gateway"
  assert path_exists(cfg[:dnsmasq_conf]) == false
  no_mac = at(darwin(cfg), buzios_commands("arp-unprivileged.txt"), ok(true), 0)
  assert no_mac[:site] == :unread
  assert no_mac[:mac] == :unread
  assert converge(cfg, no_mac, fake([], ok(true)))[:result] == "blind:site"
  no_probe = at(cfg, natal_commands, bad("probe: could not"), 0)
  assert no_probe[:site] == "natal"
  assert no_probe[:gateway] == :unread
  assert converge(cfg, no_probe, fake([], ok(true)))[:result] == "blind:gateway"
  no_addr = at(cfg, [first(natal_commands)], ok(true), 0)
  assert no_addr[:site] == :unread
  no_neigh = at(cfg, take(2, natal_commands), ok(true), 0)
  assert no_neigh[:site] == :unread
  assert no_neigh[:mac] == :unread
end

test "converge writes and reloads only when the text changes, a dry run only says so, and a failed write or reload is named"
  cfg = in_dir(config)
  io = fake(natal_commands, ok(true))
  run = at(cfg, natal_commands, ok(true), 0)
  assert converge(assoc(cfg, :dry_run, true), run, io)[:result] == "would-write"
  assert path_exists(cfg[:dnsmasq_conf]) == false
  c = converge(cfg, run, io)
  assert c[:result] == "written"
  assert read_file(cfg[:dnsmasq_conf]) == c[:text]
  assert converge(cfg, run, io)[:result] == "unchanged"
  away = at(cfg, natal_commands, ok(false), 5)
  assert get(
    converge(assoc(cfg, :reload, ["/no/such/reload"]), away, io),
    :result
  ) == "reload-failed"
  assert contains?(
    read_file(cfg[:dnsmasq_conf]),
    "address=/plo/100.64.0.110"
  ) == true
  assert get(
    converge(assoc(cfg, :dnsmasq_conf, "/dev/null/toride.conf"), run, io),
    :result
  ) == "write-failed"
end

test "run: observe, converge and record; the streak survives between runs, and the line prints on change or heartbeat"
  cfg = in_dir(config)
  io = fake(natal_commands, ok(false))
  first_run = run(cfg, io)
  assert first_run[:result] == "written"
  assert first_run[:streak] == 1
  assert first_run[:runs] == 1
  assert first_run[:line] ==
    "written site=natal gateway=up served=4 withheld=1 refused=0"
  second = run(cfg, io)
  assert second[:result] == "unchanged"
  assert second[:streak] == 2
  third = run(cfg, io)
  assert third[:gateway] == "down"
  assert third[:result] == "written"
  assert contains?(
    read_file(cfg[:dnsmasq_conf]),
    "address=/plo/100.64.0.110"
  ) == true
  assert read_prior(cfg[:state_path])[:runs] == 3
  assert loud?("a", "b", 1, 30) == true
  assert loud?("a", "a", 30, 30) == true
  refused = run(assoc(in_dir(load(nil)), :refusals, [refusal(:x, "y")]), io)
  assert refused[:result] == "refused:config_unreadable"
  assert refused[:refused] == ["y"]
end

test "the commands toride runs, by platform, and a probe that reaches nothing"
  cfg = load(
    json_stringify({platform: "nixos", ip: "/run/current-system/sw/bin/ip"})
  )
  assert routes_argv(cfg) ==
    %w[/run/current-system/sw/bin/ip -4 route show table main]
  assert local_argv(cfg, "wlo1") ==
    %w[/run/current-system/sw/bin/ip -4 -o addr show dev wlo1]
  assert neigh_argv(cfg, "wlo1") ==
    %w[/run/current-system/sw/bin/ip -4 neigh show dev wlo1]
  assert probe("127.0.0.1", [1, 2], 1)[:value] == false
  assert probe("127.0.0.1", [1], 0)[:ok] == true
  assert probe("127.0.0.1", [0], 100)[:ok] == false
  assert reach("127.0.0.1", [], 10) == false
  listener = http_listen("127.0.0.1:0")
  assert probe("127.0.0.1", [1, http_listener_port(listener)], 1000)[:value] ==
    true
  assert get(
    get(
      observe(
        darwin(cfg),
        fake(
          [
            [
              "/usr/sbin/netstat -rn -f inet",
              fairu::fixture("toride", "netstat-buzios.txt")
            ]
          ],
          ok(true)
        )
      ),
      :local
    ),
    :ok
  ) == false
end
