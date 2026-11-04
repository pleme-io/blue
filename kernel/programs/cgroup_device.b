use("bpf", %i[ctx_int declare_map map_add])

ASKED = declare_map(:device_asked, :array, 4, 8, 1)

MEM_MAJOR = 1

ZERO_MINOR = 5

def no_dev_zero(ctx)
  map_add(ASKED, 0, 1)
  if ctx_int(ctx, 4, 4) == MEM_MAJOR and ctx_int(ctx, 8, 4) == ZERO_MINOR
    0
  else
    1
  end
end
