@moduledoc """
kernel-compile: Every file of the kernel suites checked, and every program compiled to bytecode, on any host, with no kernel. A suite only runs on a machine that can load programs, so a call a rebase left with the wrong arguments stays quiet until a real kernel reaches it.

A program file with no row here is red, so the table cannot fall behind the directory.

    blue test gen/kernel-compile.b
"""

use("bpf", [:compile])

use("retsu", [:first])

use("shisutemu", %i[blue_exe status_of stderr_of stdout_of])

def root()
  getenv("GEN_ROOT", ".")
end

@doc """
programs: Each program the suites load, as [file, entry, kind, on_fault]. A file's definitions may compile to several kinds; one row per entry shows the source compiles.

    first(first(programs)) #=> "kernel/programs/args.b"
"""
def programs()
  [
    ["kernel/programs/args.b", :sum_args, :raw_tracepoint, 0],
    ["kernel/programs/args.b", :sum_words, :syscall, 0],
    ["kernel/programs/arith.b", :entry, :xdp, 0],
    ["kernel/programs/cc.b", :init, :struct_ops, 0],
    ["kernel/programs/cgroup_device.b", :no_dev_zero, :cgroup_device, 0],
    ["kernel/programs/cgroup_sock.b", :no_ping_socket, :cgroup_sock, 1],
    ["kernel/programs/count.b", :on_event, :raw_tracepoint, 0],
    ["kernel/programs/fentry.b", :on_open, :tracing, 0],
    ["kernel/programs/fexit_args.b", :on_return, :tracing, 0],
    ["kernel/programs/filter.b", :filter, :xdp, 0],
    ["kernel/programs/fmod_ret.b", :replaced, :tracing, 0],
    ["kernel/programs/l3_filter.b", :l3_filter, :lwt_in, 1],
    ["kernel/programs/lsm_count.b", :on_file_open, :lsm, 0],
    ["kernel/programs/lsm_deny.b", :on_file_open, :lsm, 0],
    ["kernel/programs/nf_filter.b", :nf_filter, :netfilter, 1],
    ["kernel/programs/object.b", :on_packet, :xdp, 0],
    ["kernel/programs/opens.b", :on_open, :kprobe, 0],
    ["kernel/programs/refused.b", :read_far, :xdp, 0],
    ["kernel/programs/sk_lookup.b", :sk_lookup, :sk_lookup, 1],
    ["kernel/programs/socket_len.b", :socket_len, :socket_filter, 1],
    ["kernel/programs/spin.b", :on_packet, :xdp, 0],
    ["kernel/programs/tc_filter.b", :tc_filter, :sched_cls, 1]
  ]
end

@doc """
without_row: The program files no row of `rows` names.

    without_row(["a.b", "b.b"], [["a.b", :f, :xdp, 0]]) #=> ["b.b"]
    without_row([], []) #=> []
"""
def without_row(files, rows)
  named = map(first, rows)
  retsu::reject((f) -> member?(f, named), files)
end

@doc """
sources: The `.b` files of a directory and every directory under it, each as a path relative to the root.

    sources("/no/such/kernel/compile") #=> []
"""
def sources(dir)
  full = "#{root}/#{dir}"
  if is_dir?(full)
    map(
      (p) -> replace(p, "#{root}/", ""),
      filter((p) -> ends_with?(p, ".b"), walk_dir(full))
    )
  else
    []
  end
end

@doc """
check_fault: What `blue check` says is wrong with a file, or nil.

    check_fault({status: 0}, "x") #=> nil
"""
def check_fault(r, file)
  if status_of(r) != 0
    "#{file}: #{stdout_of(r)}#{stderr_of(r)}"
  end
end

def checked(file)
  check_fault(exec_capture(blue_exe, "check", "#{root}/#{file}"), file)
end

def compile_fault(row)
  file = first(row)
  begin
    compile("#{root}/#{file}", {entry: row[1], kind: row[2], on_fault: row[3]})
    nil
  rescue e
    "#{file} #{to_s(row[1])}: #{to_s(e.message)}"
  end
end

test "a program file with no row is named, so a new program cannot be missed"
  assert without_row(["a.b"], []) == ["a.b"]
  assert without_row(["a.b"], [["a.b", :f, :xdp, 0]]) == []
end

test "every program under kernel/programs has its row"
  assert sources("kernel/programs") != []
  assert without_row(sources("kernel/programs"), programs) == []
end

test "every kernel file passes the check stage"
  files = sources("kernel")
  assert count(files) > count(sources("kernel/programs"))
  assert filter((f) -> f != nil, map(checked, files)) == []
end

test "every program compiles to bytecode"
  assert filter((f) -> f != nil, map(compile_fault, programs)) == []
end

test "the check this gate runs goes red on a call a rebase left short"
  dir = "#{getenv("TMPDIR") or "/tmp"}/kernel-compile-#{to_s(now_ms)}"
  mkdir_p(dir)
  file = "#{dir}/planted.b"
  write_program(
    file,
    join_lines(["def two(a, b)", "  [a, b]", "end", "", "two(1)", ""])
  )
  fault = check_fault(exec_capture(blue_exe, "check", file), "planted.b")
  rm_rf(dir)
  assert contains?(fault, "B0072")
end
