---
kind: howto
order: 11
summary: read a field of a kernel struct at the offset the running kernel states, and test the read on the pure machine
---

# Read a kernel field

`kernel_read(pointer, struct, path, size)` reads one field of a kernel struct.
You name the field. The offset comes from the running kernel's BTF when the program
loads, so the program does not hold an offset that another kernel moved.

```blue file=whoami.b
use("bpf", %i[bind_fields compile helper kernel_read])

def task_pid(_ctx)
  kernel_read(helper(:get_current_task), "task_struct", ["pid"], 4)
end

def program()
  compile("whoami.b", {entry: :task_pid, kind: :tracing, on_fault: 0})
end

def task_at(offset)
  (_struct, _path) -> {offset:, size: 4}
end

test "the program names the field it reads"
  field = program[:fields][0]
  assert field[:struct] == "task_struct"
  assert field[:path] == ["pid"]
end

test "bound to an offset, the program reads the field there"
  memory = {at: 805_306_368, bytes: [0, 0, 0, 0, 42, 0, 0, 0]}
  assert bpf::run(bind_fields(program, task_at(4)), {kernel: memory}).ret == 42
end

test "a read past the struct is the fault answer, never a wrong value"
  memory = {at: 805_306_368, bytes: [1]}
  assert bpf::run(bind_fields(program, task_at(4)), {kernel: memory}).ret == 0
end

test "a field of another size on this kernel refuses to bind"
  other = (_struct, _path) -> {offset: 4, size: 8}
  assert (bind_fields(program, other) rescue :refused) == :refused
end
```

```console
$ blue test whoami.b
4 test(s): 4 passed, 0 failed
```

The tests give the machine a piece of kernel memory and an offset. `bind_fields`
does what a load does: it writes each offset into the program, and it refuses a
field whose size differs from what the program reads.

On a real kernel, `attached` finds the field in this kernel's BTF for you. This
program counts nothing and only reports. It needs Linux and root:

```blue file=watch.b
use("baito", [:bytes_int])
use("bpf", %i[compile declare_map emit helper kernel_read])
use("kaaneru", %i[attached map_named next_event open_events])

EVENTS = declare_map(:events, :ringbuf, 0, 0, 65536)

def on_open(_ctx)
  emit(EVENTS, [kernel_read(helper(:get_current_task), "task_struct", ["pid"], 4)])
  0
end

def main()
  compiled = compile("watch.b", {entry: :on_open, kind: :tracing, on_fault: 0})
  attached(
    compiled,
    {fentry: "do_sys_openat2"},
    fn(live)
      ring = open_events(map_named(live, :events))
      read_file("/proc/version")
      got = next_event(ring, 2000)
      write_stdout(unlines(["a thread opened a file: #{to_s(bytes_int(got, 0, 8) > 0)}"]))
    end
  )
end
```

```console host
$ sudo blue run --allow host --quiet watch.b
a thread opened a file: true
```

A struct or a member this kernel does not have raises `:not_found` at load, and
names it. `blue doc btf::field` shows how to read a field's place by hand.
