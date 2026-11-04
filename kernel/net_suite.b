@moduledoc """
The kernel tests that need a network: run inside a private network namespace, so no interface appears where a host's own network daemons watch.

    ip netns add blue_suite
    ip netns exec blue_suite blue test --allow host kernel/net_suite.b
    ip netns del blue_suite
"""

use("baito", %i[bytes_int int_bytes])

use("bpf", [:compile])

use("btf")

use(
  "kaaneru",
  %i[
    attach
    attach_cgroup
    attach_netfilter
    detach
    install
    install_struct_ops
    map_get
    map_named
  ]
)

use("retsu", [:first])

def sh(cmd, args)
  got = exec_capture(*append([cmd], args))
  if got.status != 0
    raise(:suite, "#{cmd} #{join(args, " ")}: #{got.stderr}")
  end
  got.stdout
end

def veth_up(tag)
  ns = "blue_ns_#{tag}"
  host = "blue_h#{tag}"
  peer = "blue_p#{tag}"
  sh("ip", %w[link set lo up])
  sh("ip", ["netns", "add", ns])
  sh(
    "ip",
    ["link", "add", host, "type", "veth", "peer", "name", peer, "netns", ns]
  )
  sh("ip", ["addr", "add", "10.199.77.1/30", "dev", host])
  sh("ip", ["link", "set", host, "up"])
  sh(
    "ip",
    ["netns", "exec", ns, "ip", "addr", "add", "10.199.77.2/30", "dev", peer]
  )
  sh("ip", ["netns", "exec", ns, "ip", "link", "set", peer, "up"])
  {
    ns:,
    host:,
    ifindex: to_int(trim(read_file("/sys/class/net/#{host}/ifindex")))
  }
end

def veth_down(v)
  exec_capture("ip", "link", "del", v[:host])
  exec_capture("ip", "netns", "del", v[:ns])
end

def ping_works?(v)
  got = exec_capture(
    "ip",
    "netns",
    "exec",
    v[:ns],
    "ping",
    "-c",
    "1",
    "-W",
    "1",
    "10.199.77.1"
  )
  got.status == 0
end

test "a blue XDP filter attached to a real interface drops ping, counts it, and detaching restores it"
  v = veth_up("x")
  live = install(
    compile(
      "kernel/programs/filter.b",
      {entry: :filter, kind: :xdp, on_fault: 0}
    )
  )
  counts = map_named(live, :filter_counts)
  result = begin
    before = ping_works?(v)
    link = attach(live[:prog], :xdp, v[:ifindex])
    during = ping_works?(v)
    seen = bytes_int(map_get(counts, int_bytes(1, 4)), 0, 8)
    detach(link)
    after = ping_works?(v)
    [before, during, seen, after]
  ensure
    veth_down(v)
  end
  assert first(result) == true
  assert result[1] == false
  assert result[2] >= 1
  assert result[3] == true
end

test "a blue tcx program on ingress drops ping the same way, through a link and no netlink"
  v = veth_up("t")
  live = install(
    compile(
      "kernel/programs/tc_filter.b",
      {entry: :tc_filter, kind: :sched_cls, on_fault: 0}
    )
  )
  seen = map_named(live, :tc_seen)
  result = begin
    link = attach(live[:prog], :tcx_ingress, v[:ifindex])
    during = ping_works?(v)
    count = bytes_int(map_get(seen, int_bytes(1, 4)), 0, 8)
    detach(link)
    [during, count, ping_works?(v)]
  ensure
    veth_down(v)
  end
  assert first(result) == false
  assert result[1] >= 1
  assert result[2] == true
end

def cgroup_up(tag)
  if not path_exists("/sys/fs/cgroup/cgroup.controllers")
    sh("mount", %w[-t cgroup2 cgroup2 /sys/fs/cgroup])
  end
  path = "/sys/fs/cgroup/blue_suite_#{tag}_#{to_s(now_ms)}"
  mkdir(path)
  path
end

def cgroup_down(path)
  sh("rmdir", [path])
end

def in_cgroup(path, argv)
  script = "echo $$ > #{path}/cgroup.procs && exec \"$@\""
  exec_capture("sh", "-c", script, "sh", *argv).status
end

def ping_argv(address)
  ["ping", "-c", "1", "-W", "1", address]
end

def ping_status(address)
  exec_capture(*ping_argv(address)).status
end

def l3_decision(attach_kind, tag)
  live = install(
    compile(
      "kernel/programs/l3_filter.b",
      {entry: :l3_filter, kind: :cgroup_skb, on_fault: 1}
    ),
    {attach: attach_kind}
  )
  v = veth_up(tag)
  path = cgroup_up(tag)
  seen = map_named(live, :l3_seen)
  begin
    before = in_cgroup(path, ping_argv("10.199.77.2"))
    link = attach_cgroup(live[:prog], attach_kind, path)
    held = in_cgroup(path, ping_argv("10.199.77.2"))
    outside = ping_status("10.199.77.2")
    count = bytes_int(map_get(seen, int_bytes(1, 4)), 0, 8)
    detach(link)
    after = in_cgroup(path, ping_argv("10.199.77.2"))
    {before:, held:, outside:, count:, after:}
  ensure
    veth_down(v)
    cgroup_down(path)
  end
end

test "a cgroup skb program on egress drops ICMP for its own cgroup alone, through a link, and detach restores it"
  got = l3_decision(:cgroup_inet_egress, "e")
  assert got[:before] == 0
  assert got[:held] != 0
  assert got[:outside] == 0
  assert got[:count] >= 1
  assert got[:after] == 0
end

test "a cgroup skb program on ingress drops the reply for its own cgroup alone, and detach restores it"
  got = l3_decision(:cgroup_inet_ingress, "i")
  assert got[:before] == 0
  assert got[:held] != 0
  assert got[:outside] == 0
  assert got[:count] >= 1
  assert got[:after] == 0
end

test "a cgroup sock program refuses an ICMP socket inside its cgroup, and nowhere else"
  live = install(
    compile(
      "kernel/programs/cgroup_sock.b",
      {entry: :no_ping_socket, kind: :cgroup_sock, on_fault: 1}
    ),
    {attach: :cgroup_inet_sock_create}
  )
  path = cgroup_up("s")
  sh("ip", %w[link set lo up])
  got = begin
    link = attach_cgroup(live[:prog], :cgroup_inet_sock_create, path)
    held = in_cgroup(path, ping_argv("127.0.0.1"))
    outside = ping_status("127.0.0.1")
    detach(link)
    [held, outside, in_cgroup(path, ping_argv("127.0.0.1"))]
  ensure
    cgroup_down(path)
  end
  assert first(got) != 0
  assert got[1] == 0
  assert got[2] == 0
end

test "a cgroup device program denies one device inside its cgroup, allows another, and detach restores it"
  live = install(
    compile(
      "kernel/programs/cgroup_device.b",
      {entry: :no_dev_zero, kind: :cgroup_device, on_fault: 1}
    ),
    {attach: :cgroup_device}
  )
  path = cgroup_up("d")
  zero = %w[head -c 1 /dev/zero]
  urandom = %w[head -c 1 /dev/urandom]
  got = begin
    link = attach_cgroup(live[:prog], :cgroup_device, path)
    denied = in_cgroup(path, zero)
    allowed = in_cgroup(path, urandom)
    outside = exec_capture(*zero).status
    asked = bytes_int(
      map_get(map_named(live, :device_asked), int_bytes(0, 4)),
      0,
      8
    )
    detach(link)
    {denied:, allowed:, outside:, asked:, after: in_cgroup(path, zero)}
  ensure
    cgroup_down(path)
  end
  assert got[:denied] != 0
  assert got[:allowed] == 0
  assert got[:outside] == 0
  assert got[:asked] >= 2
  assert got[:after] == 0
end

test "a cgroup that does not exist is a named absence, not an attach"
  live = install(
    compile(
      "kernel/programs/cgroup_device.b",
      {entry: :no_dev_zero, kind: :cgroup_device, on_fault: 1}
    ),
    {attach: :cgroup_device}
  )
  got = attach_cgroup(
    live[:prog],
    :cgroup_device,
    "/sys/fs/cgroup/blue_suite_none"
  ) rescue
    :absent
  assert got == :absent
end

test "a netfilter program in this namespace drops only marked ICMP, decided from the live packet, and detach restores it"
  table = btf::open(btf::vmlinux_path)
  live = install(
    compile(
      "kernel/programs/nf_filter.b",
      {entry: :nf_filter, kind: :netfilter, on_fault: 1}
    ),
    {btf: table}
  )
  v = veth_up("n")
  ping_ttl = fn(ttl)
    exec_capture(
      "ip",
      "netns",
      "exec",
      v[:ns],
      "ping",
      "-c",
      "1",
      "-W",
      "1",
      "-t",
      ttl,
      "10.199.77.1"
    ).status
  end
  got = begin
    link = attach_netfilter(
      live[:prog],
      {family: :ipv4, hook: :local_in, priority: -100}
    )
    marked = ping_ttl("33")
    plain = ping_ttl("64")
    count = bytes_int(map_get(map_named(live, :nf_seen), int_bytes(1, 4)), 0, 8)
    detach(link)
    {marked:, plain:, count:, after: ping_ttl("33")}
  ensure
    veth_down(v)
  end
  assert got[:marked] != 0
  assert got[:plain] == 0
  assert got[:count] >= 2
  assert got[:after] == 0
end

def congestion_names()
  read_file("/proc/sys/net/ipv4/tcp_available_congestion_control")
end

def cc_programs()
  map(
    fn(row)
      [
        first(row),
        compile(
          "kernel/programs/cc.b",
          {entry: row[1], kind: :struct_ops, on_fault: 0}
        )
      ]
    end,
    [
      ["init", :init],
      ["ssthresh", :ssthresh],
      ["undo_cwnd", :undo],
      ["cong_avoid", :avoid]
    ]
  )
end

test "a TCP congestion control written in blue registers through a struct_ops link, runs for a real connection, and detach removes it"
  table = btf::open(btf::vmlinux_path)
  name = "blue_cc_#{to_s(now_ms % 100_000)}"
  sh("ip", %w[link set lo up])
  live = install_struct_ops(
    table,
    {
      ops: "tcp_congestion_ops",
      name: "blue_suite_cc",
      programs: cc_programs,
      values: [["name", name]]
    }
  )
  inits = map_named(live, :cc_inits)
  key = int_bytes(0, 4)
  got = begin
    listed = contains?(congestion_names, name)
    sh(
      "ip",
      [
        "route",
        "replace",
        "local",
        "127.0.0.1",
        "dev",
        "lo",
        "table",
        "local",
        "congctl",
        name
      ]
    )
    server = http_listen("127.0.0.1:0")
    port = http_listener_port(server)
    answer = tcp_connect_ms("127.0.0.1", port, 2000)
    sleep_ms(100)
    ran = bytes_int(map_get(inits, key), 0, 8)
    sh("ip", %w[route replace local 127.0.0.1 dev lo table local])
    {listed:, answer:, ran:}
  ensure
    detach(live[:link])
  end
  assert got[:listed]
  assert integer?(got[:answer]) or float?(got[:answer])
  assert got[:ran] >= 1
  assert not contains?(congestion_names, name)
end
