use("kaaneru/bpf", %i[declare_map emit helper kernel_read])

EVENTS = declare_map(:fentry_events, :ringbuf, 0, 0, 65536)

def on_open(_ctx)
  task = helper(:get_current_task)
  emit(
    EVENTS,
    [
      helper(:get_current_pid_tgid),
      kernel_read(task, "task_struct", ["pid"], 4)
    ]
  )
  0
end
