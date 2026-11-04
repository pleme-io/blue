use("bpf", %i[declare_map map_add])

INITS = declare_map(:cc_inits, :array, 4, 8, 1)

SSTHRESH = 2

def init(_ctx)
  map_add(INITS, 0, 1)
  0
end

def ssthresh(_ctx)
  SSTHRESH
end

def undo(_ctx)
  SSTHRESH
end

def avoid(_ctx)
  0
end
