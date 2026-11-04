---
kind: explanation
summary: blue as the whole kernel toolchain, from source to a program the verifier admits, and where each part runs
---

# KERNEL — write only blue for the Linux kernel

Status: BUILDING, 2026-11-03. §6 states what is built and what is design. Every
"built" row names the test that shows it.

## 1. Destination

A person writes one blue file. Blue compiles it to BPF, loads it, attaches it and
reads its results. No clang, libbpf, aya, rustc or LLVM is in that path, and no C
library binding. The same source runs in three places and they must agree: the
blue interpreter, a pure machine on any host, and a real kernel.

## 2. The layers, each one bidama

| Layer | Bidama or crate | Owns | Host needs |
|---|---|---|---|
| bytes | `baito` | integers at a width and order; record layouts placed as a C struct | nothing |
| instructions | `bpf` | RFC 9669 instructions as values, assembler, encoder, decoder, text, pure machine | nothing |
| compiler | `bpf` (`compile`, `compile_forms`) | a restricted blue subset to bytecode, with a report of checks proven and emitted | process, to run `blue ast --resolved` |
| types | `btf` | the kernel's own types: hook ids, field offsets; a program's own types written, and `.BTF.ext` | filesystem, to read a kernel's |
| objects | `erufu` | an ELF object written and read, in the shape clang gives the same program | nothing |
| kernel client | `kaaneru` | maps, programs, links, pins, ring buffers, every attach kind in §6 | `kernel_bpf` |
| the seam | `blue-lang-kernel` | `bpf(2)`, `perf_event_open(2)`, ioctl, `open(2)` of a descriptor a link names, mmap of the ring | Linux; one `unsafe` module |

The seam knows no BPF. It takes a struct size and a list of fields: integers,
raw bytes, buffers whose address goes in the struct, and descriptors. Every
kernel struct is a `baito` layout in blue. So a new kernel feature is a blue
change, not a Rust change.

## 3. Hosting: which part runs where

The judge is `blue_lang_pkg::deploy::runtime`, and the rule is `BUILD-STACK.md`
§2. WASI has no kernel ABI, so anything that loads a program is native, and the
reason is the named gap `:device`.

| Part | Host | Why |
|---|---|---|
| kernel-side program | BPF bytecode in the kernel; no evaluator, no collector | the verifier admits nothing else |
| compile, assemble, machine, tests | any host, any rung, including wasm | pure |
| loader tool, one-shot | `blue run --allow kernel_bpf`, or a shebang with it | the capability is the whole grant, and it is visible at the top of the file |
| node daemon | `service(...)` with `runtime: :native, because: :device`: a nix closure on an engenho node, `mkHardenedImageSet` on a foreign cluster | WASI preview 2 reaches no kernel ABI |
| sealed daemon | `blue bundle --runner blue-appliance` | held to the capabilities its lock verified, and takes no flags |
| inside a Rust program | `blue-lang-host` with a `#[host]` block | where Rust already owns the descriptors, as kanshi and engenho do |
| wasm component | refused by the judge | the refusal names the gap |
| a `.ko` kernel module | not built | §5 |

Capabilities a daemon needs, least first: `CAP_BPF` with `CAP_NET_ADMIN` for
XDP, tc, cgroup and netfilter; `CAP_BPF` with `CAP_PERFMON` for kprobe,
tracepoint, tracing, LSM and struct_ops. Never `privileged`, and never
`CAP_SYS_ADMIN` unless a named map type needs it. `CAP_BPF` without
`CAP_PERFMON` verifies differently: pointer leaks and Spectre bypass stay off.

## 4. Facts this design stands on

Each was read from the kernel source at the named tag, 2026-11-03.

| Fact | Consequence |
|---|---|
| Newest stable 7.3; LTS 6.18, 6.12, 6.6; 7.x has no LTS | the floor is 6.6, and plo's 6.12.93 is the first real target |
| cpu v4 (`sdiv`, `smod`, `movsx`, `bswap`, signed loads, `gotol`) landed in 6.6 | the compiler may use them at the floor |
| only the 512-byte stack and 8 frames hold across the range | the compiler inlines every call by default and holds 64 slots; a chain of global subprograms is refused past 512 bytes |
| a back-edge needs `CAP_BPF` | tail recursion lowers to a loop only for a privileged loader |
| XDP, tcx, cgroup, fentry, fexit, lsm, iter, netfilter, kprobe_multi, uprobe_multi and struct_ops attach through `BPF_LINK_CREATE` alone at 6.6 | no netlink in the attach path |
| perf_event, tracepoint and a single kprobe still need a `perf_event_open` descriptor | the seam has that one extra call |
| one program attaches once to one tracepoint, whichever CPU its event names | a second event for it answers `EEXIST`, as measured on plo |
| `BPF_PROG_RUN` serves XDP, tc, socket filter, cgroup skb, lwt, flow dissector, sk_lookup, netfilter, raw tracepoint and syscall; it refuses LSM; tracing runs only at fixed test functions | those kinds test attach-free; LSM and tracing test attached |
| `BPF_PROG_RUN` at 6.12 computes `data_end` for tc and lwt, and not for cgroup skb | a cgroup skb program's direct packet read is measured attached; its `len` runs attach-free, as measured on plo |
| a netfilter and an sk_lookup program must name their one attach type at load, and a syscall program must load sleepable | `kaaneru::load` sets each; plo answers `EINVAL` without them |
| a struct_ops program needs no program BTF: its types come from the member it names in the kernel's own; its map must name a BTF object, and any will do | `install_struct_ops` loads `btf::smallest`, one `int`, with the compiler free of BTF generation |
| `BPF_PROG_RUN` of a netfilter program with no context runs at `local_out`, with the network header unset | a frame read at its network header runs with a `local_in` context |
| global subprograms, callbacks and spin locks need program BTF; plain programs, ring buffers and maps do not | a plain program loads with none; `bpf::needs_btf?` says which do |
| a global subprogram returns one integer, and is verified with its arguments unknown | a fault crosses by a pointer to the caller's slot, null-checked as the verifier asks at 6.6; a range does not cross a call, so `*` on a parameter is refused where the inlined call compiles |
| a callback must be a static function; `bpf_spin_lock` allows no call but its unlock, and no return with it held | the machine models the same rules, and the kernel's refusals are in the suite |
| libbpf 1.x reads maps only from BTF in `.maps`, and fills a data section's size and places from the symbols | `erufu` writes them filled, and fills clang's when it reads one |
| signed programs arrived in 6.18; CO-RE relocations are refused for them at 7.4-rc1 | a signing mode resolves offsets before it signs |
| Aya's eBPF side still needs nightly and LLVM | no reason to take that path; its userspace is pure Rust, which this seam matches |

## 5. Not taken, and why

- **Emit Rust and use aya.** It works, and it brings nightly, `bpf-linker` and
  LLVM into every build. BPF's instruction set is small, and the direct backend
  is the `backend: :direct` that `theory/BLUE-NATIVE.md` §1.5 left configured
  off. Here it is the only backend, because it is the one that removes the
  toolchain.
- **Kernel modules.** The supported path is the kernel's own build tree with its
  exact compiler, and no producer without rustc and kbuild is known. Hooks,
  struct_ops and kfuncs cover what the fleet needs, so a module stays a design
  row until something needs one.
- **A Rust BPF machine as the capability's provider.** The pure machine is blue,
  so it is one implementation, and `kernel_bpf` has no pure provider.

## 6. Ledger

Every "measured on plo" row ran on 6.12.93, 2026-11-03 or 2026-11-04.

| Item | Tier | Shown by |
|---|---|---|
| `baito` layouts | built | `bidamas/baito/baito.b`; 7 of 7 mutants caught |
| encoder, every instruction form | built, checked against LLVM | `kernel/isa_llvm.b`: 166 of 166 byte-identical to `llvm-mc --mcpu=v4` |
| machine against the kernel: ALU, jumps, swaps, memory, atomics | built, measured on plo | `kernel/suite.b`: 7,168 ALU programs over edge values |
| maps, ring buffer, pins, program id, verifier log | built, measured on plo | `kernel/suite.b` |
| compiler: integers, booleans, locals, `if`, inlined calls, tail loops, maps, packets, events, helpers | built | `bidamas/bpf/bpf.b`; 21 of 21 mutants caught |
| one source agrees in interpreter, machine and kernel | built, measured on plo | `kernel/suite.b`, "one source": 456 inputs |
| tracepoint attach and detach | built, measured on plo | `kernel/suite.b` |
| kprobe through a perf event | built, measured on plo | `kernel/suite.b`; a NixOS 25.11 kernel leaves `CONFIG_FPROBE` off |
| kprobe_multi | built, and a named refusal on plo | `kernel/suite.b`: answers `EOPNOTSUPP`; the path that succeeds has not run |
| XDP and tcx on a real interface | built, measured on plo | `kernel/net_suite.b`: ping drops, is counted, returns on detach |
| `btf`: read a kernel's types, find a hook, a field's offset through anonymous unions | built, measured on plo's 115,470 types | `bidamas/btf/btf.b`; `kernel/suite.b` |
| fentry found through BTF, a field read at the kernel's own offset | built, measured on plo | `kernel/suite.b`: the field equals the thread id |
| LSM program that counts, and one that denies only its target | built, measured on plo | `kernel/suite.b` |
| a field of another size on this kernel refuses at load | built | `bpf::bind_fields` |
| `:kernel_bpf` forces the native rung | built | `deploy::service` tests |
| chart: exact capabilities for a service that reaches the kernel | built, not deployed | `bidamas/haibi/haibi.b`; `nix/chart-gate.b`; the values schema holds them as `const`; no release uses it |
| chart: DaemonSet, host network, bpffs and tracefs mounts | built, not deployed | `examples/kernel-agent`: `helm lint --strict`, render and `nix/chart-gate.b`, each widened capability and missing mount red; no cluster has run it |
| cgroup v2 descriptor, a named absence off a v2 directory | built, measured on plo | `kaaneru::open_cgroup`; `kernel/net_suite.b`: `:cgroup_absent` |
| cgroup skb, egress and ingress, through a link | built, measured on plo | `kernel/net_suite.b`: a fresh test cgroup's ping drops and is counted, ping outside it passes, detach restores it |
| cgroup sock_create through a link | built, measured on plo | `kernel/net_suite.b`: an ICMP socket is refused in the test cgroup alone |
| cgroup device through a link | built, measured on plo | `kernel/net_suite.b`: `/dev/zero` is denied in the test cgroup, `/dev/urandom` is not |
| netfilter in a network namespace | built, measured on plo | `kernel/net_suite.b`: `local_in` drops ICMP of one TTL read from the live `sk_buff`, passes another, detach restores it |
| fexit, fmod_ret at the kernel's test functions | built, measured on plo | `kernel/suite.b`: fexit reads argument 1 and return 2 of `bpf_fentry_test1`; fmod_ret's 5 replaces `bpf_modify_return_test` and skips its side effect |
| task iterator, read back through a pin | built, measured on plo | `kernel/suite.b`: the output holds this thread's id and pid 1 |
| uprobe_multi on an executable's entry | built, measured on plo | `kernel/suite.b`: a private copy of `head` counts once per exec, the original not at all, nothing after detach |
| raw tracepoint attach | built, measured on plo | `kernel/suite.b`: counts exec, nothing after detach |
| perf_event on the CPU clock | built, measured on plo | `kernel/suite.b`: counts on CPU 0, nothing after detach |
| struct_ops: a TCP congestion control in blue | built, measured on plo | `kernel/net_suite.b`: its name is listed while the link lives, `init` runs for a real connection on a namespace route, and detach removes it. It registers system-wide; only a route in the suite's namespace selects it |
| `BPF_PROG_RUN`: machine and kernel agree | built, measured on plo | `kernel/suite.b`: sched_cls, sched_act, flow dissector, lwt_in, lwt_out, lwt_xmit, socket filter, and cgroup skb on `len`, over 23 frames; sk_lookup, raw tracepoint and syscall over their contexts |
| `BPF_PROG_RUN`: netfilter | built, measured on plo; the machine does not apply | `kernel/suite.b`: it decides from a real `sk_buff`, a kernel pointer the machine has no model of |
| `BPF_PROG_RUN`: tracing, LSM | built, measured on plo | tracing through the fexit row; LSM answers `ENOTSUPP`, a named refusal |
| `BPF_PROG_RUN`: a cgroup skb's direct packet read | a named refusal on 6.12 | `kernel/suite.b`: the kernel leaves `data_end` unset in this run; the attached row measures the read |
| ELF object, written and read (`erufu`) | built, checked against clang and LLVM, measured on plo | `kernel/object_llvm.b`: sections, symbols, relocations, disassembly, BTF and func_info equal to clang's for one program, `readelf -a` silent, a changed instruction seen; `kernel/object_suite.b`: `bpftool` dumps, loads and runs it, `veristat` verifies it, a clang object loads through blue |
| not in an object: line info, CO-RE relocations, a map value reference | not built | `erufu::object` refuses unbound fields and a map value reference by name; no line info is written |
| reading an object: the whole of `.text` is linked | built, with a limit | a function in `.text` nothing reaches makes the verifier refuse the program; libbpf drops it, `erufu::program_of` does not |
| program BTF: functions, maps, `license`, `.BTF.ext` | built, measured on plo | `btf::encode`, `bpf::program_btf`; `kernel/object_suite.b`: the kernel reports 2 in `nr_func_info` and a `btf_id` |
| global subprograms in the compiler, by `{global: [...]}`; inlining stays the default | built, measured on plo | `kernel/suite.b`, "one source with a global subprogram": 456 inputs agree in interpreter, machine and kernel, faults included; a static reader loads where a global one is refused |
| spin lock: `declare_locked`, `locked_add` | built, measured on plo, one CPU at a time | `kernel/object_suite.b`: 1,001 adds counted, machine agrees on the first, the kernel's two refusals seen; contention across CPUs has not run |
| callback: `func_ref`, `bpf_loop` | built for assembled programs, measured on plo | `kernel/object_suite.b`: kernel and machine both count 3; the compiler has no word for a callback |
| a kernel matrix in a VM as a nix check | design | until it runs, the kernel words' real behaviour is proven only by running `kernel/suite.b` by hand; their tests beside them reach the refusals |
| kanshi's LSM enforcer in blue | design | the first real consumer |

## 7. Running the kernel suites

The suites load programs, so they need root and Linux. Run them from the
repository root at low priority. Two kinds of run can disturb a host, and the
split below keeps both away from it:

- `kernel/suite.b` attaches read-only tracepoints and kprobes, and an LSM program
  that denies only its own process. It removes the one pin it makes.
- `kernel/net_suite.b` makes interfaces, so it runs inside a private network
  namespace, where no daemon on the host sees them. Its cgroup tests attach only
  to a fresh cgroup named `blue_suite_*`, moved into by a child alone and removed
  after. `ip netns exec` hides the cgroup mount, so the suite mounts cgroup2 in
  the private mount namespace that command makes.
- `kernel/object_suite.b` loads global subprograms, a spin lock and a callback,
  and hands blue's objects to `bpftool` and `veristat`. Its one pin is removed
  whatever the run answers.

```text
blue kernel/run.b
```

`kernel/run.b` does all of it. It refuses a host whose load is over its core
count or that has more than four tasks stalled in D state, because a loaded host
reads as a broken BPF. It builds the checkout's blue at idle priority, runs both
suites, and fails when a link, a namespace, a pin or a test cgroup is left behind.
Its settings are `kernel-run`'s, through `settei`:
`KERNEL_RUN_ADMISSION__ENABLED=false` turns the refusal off,
`KERNEL_RUN_BUILD__ENABLED=false` the build, `KERNEL_RUN_TOOLS__FROM_NIX=false`
the nix lookup of `ip`, `ping` and the object oracles (`bpftool`, `clang`, LLVM's
tools, `readelf`, and `veristat`, which it builds because nixpkgs does not carry
it; nothing in blue's build needs these), and `KERNEL_RUN_SUITE__FILTER=fexit`
keeps the tests whose name holds it.

Run it detached with a log on a remote host, since a dropped SSH session loses a
foreground run. The encoder's check needs only an `llvm-mc`:

```text
BLUE_PATH=bidamas blue kernel/isa_llvm.b "$(nix build --no-link --print-out-paths nixpkgs#llvmPackages.llvm)/bin/llvm-mc"
```
