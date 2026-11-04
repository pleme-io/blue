use(
  "bpf",
  %i[
    declare_locked
    declare_map
    locked_add
    map_add
    packet_int
    packet_put
    xdp_pass
  ]
)

COUNTS = declare_map(:object_counts, :array, 4, 8, 4)

TOTALS = declare_locked(:object_totals, :array, 4, 1)

@doc """
sum_into: write a sum into the packet and answer it, the subprogram a compile makes global.

    (sum_into(nil, 1, 2) rescue :compiled) #=> :compiled
"""
def sum_into(ctx, a, b)
  packet_put(ctx, 16, 8, a + b)
  a + b
end

@doc """
on_packet: count the packet, sum its two integers through `sum_into`, and add the sum to a total under its lock.

    (on_packet(nil) rescue :compiled) #=> :compiled
"""
def on_packet(ctx)
  map_add(COUNTS, 1, 1)
  total = sum_into(ctx, packet_int(ctx, 0, 8), packet_int(ctx, 8, 8))
  packet_put(ctx, 24, 8, locked_add(TOTALS, 0, total))
  xdp_pass
end
