# A kernel program, tested with no kernel
#
# `compile` turns one definition into BPF. `kaaneru::bpf::run` runs it on a pure machine
# on any host, with its maps; `blue new --kernel` starts a project in this shape.
# On Linux, `kaaneru::attached(program, {xdp: index}, body)` loads the same source
# onto an interface and `kaaneru::map_int` reads the same map.
use(
  "kaaneru/bpf",
  %i[compile declare_map map_add packet_int packet_len xdp_pass]
)

use("retsu", [:repeat])

COUNTS = declare_map(:counts, :array, 4, 8, 256)

def count_packets(ctx)
  if packet_len(ctx) >= 34
    map_add(COUNTS, packet_int(ctx, 23, 1), 1)
  end
  xdp_pass
end

def program()
  compile(
    "14_kernel_counter.b",
    {entry: :count_packets, kind: :xdp, on_fault: xdp_pass}
  )
end

def frame(protocol)
  append(*[repeat(0, 23), [protocol], repeat(0, 10)])
end

test "a packet is counted under its protocol and passed"
  p = program
  st = kaaneru::bpf::run(p, {packet: frame(17), maps: p[:maps]})
  assert st.ret == xdp_pass
  assert kaaneru::bpf::map_int(st, :counts, 17) == 1
  assert kaaneru::bpf::map_int(st, :counts, 6) == 0
end

test "a frame too short for the field is not counted"
  p = program
  st = kaaneru::bpf::run(p, {packet: repeat(0, 20), maps: p[:maps]})
  assert st.ret == xdp_pass
  assert kaaneru::bpf::map_int(st, :counts, 0) == 0
end

test "a map no program declared is refused by name"
  p = program
  st = kaaneru::bpf::run(p, {packet: frame(6), maps: p[:maps]})
  assert (kaaneru::bpf::map_int(st, :nope, 0) rescue :refused) == :refused
end
