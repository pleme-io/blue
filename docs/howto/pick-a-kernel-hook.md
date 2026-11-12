---
kind: howto
order: 10
summary: choose the kernel hook for a task, compile for its program kind, and attach with one word
---

# Pick a kernel hook

A hook is where the kernel runs your program. Pick it from what the program must
see, and compile for the kind that hook takes:

| You want to | Hook spec | Program kind | Target |
|---|---|---|---|
| decide about a packet first, at the driver | `{xdp: index}` | `:xdp` | an interface index |
| decide about a packet at traffic control | `{tcx_ingress: index}`, `{tcx_egress: index}` | `:sched_cls` | an interface index |
| hold one group of processes to a network rule | `{cgroup_inet_ingress: path}`, `{cgroup_inet_egress: path}` | `:cgroup_skb` | a cgroup directory |
| refuse a socket or a device to a group of processes | `{cgroup_inet_sock_create: path}`, `{cgroup_device: path}` | `:cgroup_sock`, `:cgroup_device` | a cgroup directory |
| refuse a sysctl write to a group of processes | `{cgroup_sysctl: path}` | `:cgroup_sysctl` | a cgroup directory |
| decide at a netfilter hook | `{netfilter: {family: :ipv4, hook: :local_in, priority: -100}}` | `:netfilter` | the hook's place |
| count an event the kernel names | `{tracepoint: ["sched", "sched_process_exec"]}`, `{raw_tracepoint: "sched_process_exec"}` | `:tracepoint`, `:raw_tracepoint` | the event |
| watch a kernel function | `{kprobe: name}`, `{fentry: name}`, `{fexit: name}` | `:kprobe`, `:tracing` | the function |
| replace a test function's answer | `{fmod_ret: name}` | `:tracing` | the function |
| deny an operation, such as opening a file | `{lsm: "file_open"}` | `:lsm` | the LSM hook |
| walk kernel objects | `{iter: "task"}` | `:tracing` | the iterator |

`kaaneru::hooks` holds this table as data. Each row's kind is checked here against
it:

```blue file=hooks.b
use("kaaneru", %i[hook_row hooks])
use("retsu", [:size])

def kind_of(spec, kind)
  hook_row({kind:}, spec).kind == kind
end

test "each spec in the table takes the kind the table names"
  assert kind_of({xdp: 1}, :xdp)
  assert kind_of({tcx_ingress: 1}, :sched_cls)
  assert kind_of({tcx_egress: 1}, :sched_cls)
  assert kind_of({cgroup_inet_ingress: "/c"}, :cgroup_skb)
  assert kind_of({cgroup_inet_egress: "/c"}, :cgroup_skb)
  assert kind_of({cgroup_inet_sock_create: "/c"}, :cgroup_sock)
  assert kind_of({cgroup_device: "/c"}, :cgroup_device)
  assert kind_of({cgroup_sysctl: "/c"}, :cgroup_sysctl)
  assert kind_of({netfilter: {}}, :netfilter)
  assert kind_of({tracepoint: ["a", "b"]}, :tracepoint)
  assert kind_of({raw_tracepoint: "a"}, :raw_tracepoint)
  assert kind_of({kprobe: "f"}, :kprobe)
  assert kind_of({fentry: "f"}, :tracing)
  assert kind_of({fexit: "f"}, :tracing)
  assert kind_of({fmod_ret: "f"}, :tracing)
  assert kind_of({lsm: "file_open"}, :lsm)
  assert kind_of({iter: "task"}, :tracing)
end

test "the table is every hook"
  assert size(hooks) == 17
end
```

```console
$ blue test hooks.b
2 test(s): 2 passed, 0 failed
```

Attach with `kaaneru::attached(compiled, spec, body)`. A spec and a kind that do
not fit stop before any call to the kernel, on any host:

```blue file=wrong.b
use("kaaneru", [:attached])

attached({kind: :xdp}, {lsm: "file_open"}, (live) -> live)
```

```console fails
$ blue wrong.b
the lsm hook takes a lsm program, and this one is xdp
```

A spec names one hook, and the refusal lists every hook when it names none or two.

The machine runs a program of any kind that reads its packet or its own memory.
It cannot run a kernel pointer, so a `:netfilter` program that reads the live
`sk_buff` is tested on a real kernel. `BPF_PROG_RUN` refuses `:lsm` with
`ENOTSUPP`, and `kaaneru::run` runs `:tracing` only at the kernel's test functions:
a test of those kinds attaches. Which word and which hook each has run on, with
the test that shows it, is the ledger in [KERNEL.md](../KERNEL.md).

Other attachments have their own words, each with a `blue doc` page:
`attach_uprobes`, `attach_kprobes`, `attach_sampling` and `install_struct_ops`.
