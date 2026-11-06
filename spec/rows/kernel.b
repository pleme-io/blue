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
  "kernel.fd_open.bad_path",
  "fd_open(3)",
  fails(:eval, "fd_open"),
  covers("builtin:fd_open"),
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

row(
  "kernel.erufu.round_trip",
  join_lines(
    [
      "use(\"kaaneru/bpf\")",
      "use(\"kaaneru/erufu\")",
      "p = kaaneru::bpf::assemble([kaaneru::bpf::alu(:mov, 0, 7), kaaneru::bpf::exit_program])",
      "kaaneru::bpf::run(kaaneru::erufu::program_of(kaaneru::erufu::decode(kaaneru::erufu::object(p, {section: \"xdp\"})))).ret"
    ]
  ),
  value("7"),
  pending("G16", "wasm")
)

row(
  "kernel.erufu.not_an_object",
  join_lines(["use(\"kaaneru/erufu\")", "kaaneru::erufu::decode([1, 2, 3])"]),
  fails(:eval, "not ELF"),
  pending("G16", "wasm")
)

row(
  "kernel.btf.written_reads_back",
  join_lines(
    [
      "use(\"kaaneru/btf\")",
      "kaaneru::btf::find(kaaneru::btf::read(kaaneru::btf::encode([kaaneru::btf::int_type(\"int\", 4)])), \"int\", :int)"
    ]
  ),
  value("1"),
  pending("G16", "wasm")
)

row(
  "kernel.bpf.global_subprogram",
  join_lines(
    [
      "use(\"kaaneru/bpf\")",
      "p = kaaneru::bpf::compile_forms(read_forms(\"(define (%root/g a) (+ a 1)) (define (%root/e c) (%root/g 41))\"), {entry: :e, kind: :xdp, on_fault: 9, global: [:g]})",
      "[length(p[:funcs]), kaaneru::bpf::run(p).ret]"
    ]
  ),
  value("[2, 42]"),
  pending("G16", "wasm")
)
