# A security hook that denies, tested with no kernel
#
# An LSM program answers for one operation: 0 allows it and a negative errno
# denies it. The machine takes the identity a test gives it. On Linux,
# `kaaneru::attached(program, {lsm: "file_open"}, body)` holds the hook while
# `body` runs, and takes it away whatever `body` does.
use("kaaneru/bpf", %i[compile helper])

EPERM = 1

THREAD = 4242

def deny_one_thread(_ctx)
  if bit_and(helper(:get_current_pid_tgid), 4_294_967_295) == THREAD
    -EPERM
  else
    0
  end
end

def program()
  compile(
    "15_kernel_deny.b",
    {entry: :deny_one_thread, kind: :lsm, on_fault: 0}
  )
end

def answer_for(thread)
  kaaneru::bpf::run(
    program,
    {ctx: [0, 0, 0, 0, 0, 0, 0, 0], pid_tgid: thread}
  ).ret
end

test "the target thread is denied"
  assert answer_for(THREAD) == -EPERM
end

test "any other thread is allowed"
  assert answer_for(THREAD + 1) == 0
end
