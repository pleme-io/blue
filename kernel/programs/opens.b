use("kaaneru/bpf", %i[declare_map emit helper])

EVENTS = declare_map(:opens_events, :ringbuf, 0, 0, 65536)

def on_open(ctx)
  emit(EVENTS, [helper(:get_current_pid_tgid), 7])
  0
end
