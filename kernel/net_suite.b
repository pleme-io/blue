@moduledoc """
The kernel tests that need a network: run inside a private network namespace, so no interface appears where a host's own network daemons watch.

    ip netns add blue_suite
    ip netns exec blue_suite blue test --allow host kernel/net_suite.b
    ip netns del blue_suite
"""

use("baito", %i[bytes_int int_bytes])
use("bpf", [:compile])
use("kaaneru", %i[attach detach install map_get map_named])
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
