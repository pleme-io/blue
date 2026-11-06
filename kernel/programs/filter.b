use(
  "kaaneru/bpf",
  %i[declare_map map_add packet_int packet_len xdp_drop xdp_pass]
)

COUNTS = declare_map(:filter_counts, :array, 4, 8, 256)

def ipv4?(ctx)
  packet_int(ctx, 12, 2) == 2048
end

def proto_of(ctx)
  packet_int(ctx, 23, 1)
end

def filter(ctx)
  if packet_len(ctx) < 34 or not ipv4?(ctx)
    xdp_pass
  else
    proto = proto_of(ctx)
    map_add(COUNTS, proto, 1)
    if proto == 1
      xdp_drop
    else
      xdp_pass
    end
  end
end
