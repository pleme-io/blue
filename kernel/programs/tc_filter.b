use("kaaneru/bpf", %i[declare_map map_add packet_int packet_len])

SEEN = declare_map(:tc_seen, :array, 4, 8, 256)

TC_OK = 0

TC_SHOT = 2

def tc_filter(ctx)
  if packet_len(ctx) < 34 or packet_int(ctx, 12, 2) != 2048
    TC_OK
  else
    proto = packet_int(ctx, 23, 1)
    map_add(SEEN, proto, 1)
    if proto == 1
      TC_SHOT
    else
      TC_OK
    end
  end
end
