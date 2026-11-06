use(
  "kaaneru/bpf",
  %i[declare_map map_get map_put packet_int packet_put xdp_pass]
)

LAST = declare_map(:arith_last, :hash, 8, 8, 16)

def count_up(i, acc)
  if i >= 8
    acc
  else
    count_up(i + 1, acc + i)
  end
end

def remembered(key, value)
  seen = map_get(LAST, key)
  map_put(LAST, key, value)
  if seen.nil?
    0
  else
    seen
  end
end

def entry(ctx)
  a = packet_int(ctx, 0, 8)
  b = packet_int(ctx, 8, 8)
  packet_put(ctx, 16, 8, a + b)
  packet_put(ctx, 24, 8, count_up(0, 0))
  packet_put(ctx, 32, 8, remembered(1, a))
  xdp_pass
end
