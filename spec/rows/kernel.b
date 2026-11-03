# The Linux kernel surface, the kernel_bpf capability. A field that cannot be
# marshalled is refused before any call, on every host; what the kernel itself
# answers runs on Linux only, in bidamas/kaaneru's kernel suite.

row(
  "kernel.bpf_syscall.bad_field",
  "bpf_syscall(0, 8, [[0, :nope, 1]], false)",
  fails(:eval, "no field kind"),
  covers("builtin:bpf_syscall"),
  host()
)

row(
  "kernel.perf_event_open.bad_group",
  "perf_event_open(8, [], 0, 0, 3, 0)",
  fails(:eval, "kernel file descriptor"),
  covers("builtin:perf_event_open"),
  host()
)

row(
  "kernel.fd_ioctl.bad_fd",
  "fd_ioctl(3, 0, 0)",
  fails(:eval, "kernel file descriptor"),
  covers("builtin:fd_ioctl"),
  host()
)

row(
  "kernel.fd_close.bad_fd",
  "fd_close(3)",
  fails(:eval, "kernel file descriptor"),
  covers("builtin:fd_close"),
  host()
)

row(
  "kernel.fd_number.bad_fd",
  "fd_number(3)",
  fails(:eval, "kernel file descriptor"),
  covers("builtin:fd_number"),
  host()
)

row(
  "kernel.ringbuf_open.bad_map",
  "ringbuf_open(3, 4096)",
  fails(:eval, "kernel file descriptor"),
  covers("builtin:ringbuf_open"),
  host()
)

row(
  "kernel.ringbuf_next.bad_ring",
  "ringbuf_next(3, 0)",
  fails(:eval, "ringbuf_open"),
  covers("builtin:ringbuf_next"),
  host()
)
