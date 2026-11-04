use("bpf", %i[declare_locked locked_add packet_put xdp_pass])

TOTALS = declare_locked(:spin_totals, :array, 4, 1)

@doc """
on_packet: add 5 to a total under its lock, and write the new total into the packet.

    (on_packet(nil) rescue :compiled) #=> :compiled
"""
def on_packet(ctx)
  packet_put(ctx, 0, 8, locked_add(TOTALS, 0, 5))
  xdp_pass
end
