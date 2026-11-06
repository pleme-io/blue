use("kaaneru/bpf", %i[declare_map map_add])

HITS = declare_map(:hits, :array, 4, 8, 1)

def on_event(_ctx)
  map_add(HITS, 0, 1)
  0
end
