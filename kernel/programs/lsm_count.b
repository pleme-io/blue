use("kaaneru/bpf", %i[declare_map map_add])

OPENS = declare_map(:lsm_opens, :array, 4, 8, 1)

def on_file_open(_ctx)
  map_add(OPENS, 0, 1)
  0
end
