use("bpf", %i[declare_map helper map_get])

TARGET = declare_map(:lsm_target, :array, 4, 8, 1)

EPERM = 1

def on_file_open(_ctx)
  target = map_get(TARGET, 0) or 0
  tid = bit_and(helper(:get_current_pid_tgid), 4_294_967_295)
  if target != 0 and tid == target
    -EPERM
  else
    0
  end
end
