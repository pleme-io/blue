use("kaaneru/bpf", %i[declare_map map_add packet_int packet_len])

SEEN = declare_map(:l3_seen, :array, 4, 8, 256)

DROP = 0

ALLOW = 1

def l3_filter(ctx)
  if packet_len(ctx) < 20
    ALLOW
  else
    proto = packet_int(ctx, 9, 1)
    map_add(SEEN, proto, 1)
    if proto == 1
      DROP
    else
      ALLOW
    end
  end
end
