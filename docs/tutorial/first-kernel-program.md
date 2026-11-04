---
kind: tutorial
order: 6
summary: start a kernel program with blue new --kernel, test it with no kernel, make it drop ICMP, and load it on Linux
---

# A first kernel program

A kernel program is a function in blue. Blue compiles it to BPF. The same source
then runs in two places: a pure machine that needs no kernel, and a real Linux
kernel. This tutorial writes a program that counts packets by protocol and drops
ICMP. You need no root and no Linux until the last section.

`blue new --kernel` starts a project that passes its tests as written:

```console
$ blue new --kernel pkts
created pkts/: Bluefile, Bluefile.lock, flake.nix, pkts.b
test it  cd pkts && blue test pkts.b
run it   cd pkts && sudo blue run --allow host --quiet pkts.b -- eth0
$ cd pkts
$ blue test --filter "on the machine" pkts.b
2 test(s): 2 passed, 0 failed
```

The `--filter` keeps the two tests that run on the machine. The file holds one
more test, and that test needs a kernel. Without `--filter`, a host with no kernel
says which test it skipped and why, and the tally counts it apart from a pass:

```console host
$ blue test pkts.b
SKIP on a real kernel, the program counts what the machine counts: no kernel here: this host is not Linux
3 test(s): 2 passed, 0 failed, 1 skipped
```

Now make the program drop ICMP. Replace `pkts.b` with this:

```blue file=pkts.b
use(
  "bpf",
  %i[compile declare_map map_add packet_int packet_len xdp_drop xdp_pass]
)

use("kaaneru", %i[attached install kernel_absence])
use("retsu", %i[first repeat])
use("tesuto", [:skip_for])

COUNTS = declare_map(:counts, :array, 4, 8, 256)

ICMP = 1

def filter_packets(ctx)
  if packet_len(ctx) < 34
    xdp_pass
  else
    protocol = packet_int(ctx, 23, 1)
    map_add(COUNTS, protocol, 1)
    if protocol == ICMP
      xdp_drop
    else
      xdp_pass
    end
  end
end

def program()
  compile("pkts.b", {entry: :filter_packets, kind: :xdp, on_fault: xdp_pass})
end

def frame(protocol)
  append(*[repeat(0, 23), [protocol], repeat(0, 10)])
end

def main()
  index = to_int(trim(read_file("/sys/class/net/#{first(argv)}/ifindex")))
  attached(
    program,
    {xdp: index},
    fn(live)
      sleep_ms(5000)
      dropped = kaaneru::map_int(live, :counts, ICMP)
      write_stdout(unlines(["ICMP packets dropped: #{to_s(dropped)}"]))
    end
  )
end

test "on the machine, ICMP is counted and dropped"
  p = program
  st = bpf::run(p, {packet: frame(ICMP), maps: p[:maps]})
  assert st.ret == xdp_drop
  assert bpf::map_int(st, :counts, ICMP) == 1
end

test "on the machine, TCP is counted and passed"
  p = program
  st = bpf::run(p, {packet: frame(6), maps: p[:maps]})
  assert st.ret == xdp_pass
  assert bpf::map_int(st, :counts, 6) == 1
  assert bpf::map_int(st, :counts, ICMP) == 0
end

test "on the machine, a frame too short for the field is passed and not counted"
  p = program
  st = bpf::run(p, {packet: repeat(0, 20), maps: p[:maps]})
  assert st.ret == xdp_pass
  assert bpf::map_int(st, :counts, 0) == 0
end

test "on a real kernel, the program decides as the machine decides"
  skip_for(kernel_absence)
  live = install(program)
  assert kaaneru::run(live[:prog], {packet: frame(ICMP)})[:ret] == xdp_drop
  assert kaaneru::run(live[:prog], {packet: frame(6)})[:ret] == xdp_pass
  assert kaaneru::map_int(live, :counts, ICMP) == 1
end
```

Each part has one job:

- `declare_map` states a map's shape: the machine and the kernel read the same
  shape.
- `filter_packets` is the kernel program. It runs only when compiled, and the
  compiler writes the bounds check each packet read needs.
- `compile` turns it into BPF and checks it first. `on_fault` is what the program
  answers when a read falls outside the packet.
- `bpf::run` runs the program on the pure machine. `bpf::map_int` reads a map on
  it.
- `attached` loads the program onto one hook, runs a function, and takes the
  program away whatever the function does.
- `kaaneru::map_int` reads a map in the kernel, with the same arguments.

Run the tests:

```console
$ blue test --filter "on the machine" pkts.b
3 test(s): 3 passed, 0 failed
```

A program the kernel cannot take stops before it reaches the kernel. Blue
fractions have no BPF form, so this program never compiles:

```blue file=../fraction.b
use("bpf", [:compile])

def half(_ctx)
  7 / 2
end

compile("fraction.b", {entry: :half, kind: :xdp, on_fault: 0})
```

```console
$ cd ..
```

```console fails
$ blue fraction.b
bpf_compile
fraction
```

## On a real kernel

This section needs Linux and root. The test that needs a kernel runs the program
through `BPF_PROG_RUN`, which attaches nothing:

```console host
$ cd pkts
$ sudo blue test pkts.b
4 test(s): 4 passed, 0 failed
```

To see real packets, make a network namespace, so nothing on your host sees the
hook. Run the loader in one terminal:

```console host
$ sudo ip netns add demo
$ sudo ip netns exec demo ip link set lo up
$ sudo ip netns exec demo blue run --allow host --quiet pkts.b -- lo
ICMP packets dropped: 3
```

While the loader waits five seconds, ping from a second terminal. The pings get
no answer, and when the loader ends the program is gone:

```console host
$ sudo ip netns exec demo ping -c 3 -W 1 127.0.0.1
$ sudo ip netns del demo
```

Next: [pick a hook](../howto/pick-a-kernel-hook.md),
[read a kernel field](../howto/read-a-kernel-field.md),
[debug a refusal](../howto/debug-a-kernel-refusal.md) and
[ship a node agent](../howto/ship-a-node-agent.md). The words and what each has
been measured on are in [KERNEL.md](../KERNEL.md).
