use("bpf", %i[ctx_int declare_map map_put])

SEEN = declare_map(:fexit_seen, :array, 4, 8, 2)

def on_return(ctx)
  map_put(SEEN, 0, ctx_int(ctx, 0, 8))
  map_put(SEEN, 1, ctx_int(ctx, 8, 8))
  0
end
