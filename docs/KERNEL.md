---
kind: explanation
summary: blue as the whole kernel toolchain, from source to a program the verifier admits, and where each part runs
---

# KERNEL — write only blue for the Linux kernel

Status: BUILDING, 2026-11-03. §6 states what is built and what is design. Every
"built" row names the test that shows it.

This page is the reference. To learn by doing, start with
[the first kernel program](tutorial/first-kernel-program.md), then
[pick a hook](howto/pick-a-kernel-hook.md),
[read a kernel field](howto/read-a-kernel-field.md),
[debug a refusal](howto/debug-a-kernel-refusal.md) and
[ship a node agent](howto/ship-a-node-agent.md). `blue new --kernel NAME` starts a
project, and [the examples](EXAMPLES.md) run on the machine anywhere.

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
| compiler | `bpf` (`compile`, `compile_forms`) | a restricted blue subset to bytecode, with a report of checks proven and emitted, and each instruction's source line | process, to run `blue ast --resolved --lines` |
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
| loader tool, one-shot | `blue run --allow kernel_bpf`, or a shebang with it; `--allow host` or more `--allow` flags when it also compiles, since `compile` needs `process` and `filesystem` | the capability is the whole grant for the kernel, and it is visible at the top of the file |
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
| at 6.6.142 `sdiv` and `smod` of the lowest value by -1 reach the CPU's divide: a divide error and a kernel panic, measured in a machine, 2026-11-04; the fix, 7dd34d7b, is in 6.12, and 6.12.92, 6.12.93 and 7.0.11 answer as RFC 9669 states | `kaaneru::load` refuses a register divisor or an immediate -1 below 6.12, naming the release and the fix (`signed_division: :trust` is the off switch); the compiler divides signed only by a divisor it proves positive, so `install` trusts it; `kernel/suite.b` skips the one pair by name |
| only the 512-byte stack and 8 frames hold across the range | the compiler inlines every call by default and holds 64 slots; a chain of global subprograms is refused past 512 bytes |
| a back-edge needs `CAP_BPF` | tail recursion lowers to a loop only for a privileged loader |
| XDP, tcx, cgroup, fentry, fexit, lsm, iter, netfilter, kprobe_multi, uprobe_multi and struct_ops attach through `BPF_LINK_CREATE` alone at 6.6 | no netlink in the attach path |
| perf_event, tracepoint and a single kprobe still need a `perf_event_open` descriptor | the seam has that one extra call |
| one program attaches once to one tracepoint, whichever CPU its event names | a second event for it answers `EEXIST`, as measured on plo |
| `BPF_PROG_RUN` serves XDP, tc, socket filter, cgroup skb, lwt, flow dissector, sk_lookup, netfilter, raw tracepoint and syscall; it refuses LSM; tracing runs only at fixed test functions | those kinds test attach-free; LSM and tracing test attached |
| `BPF_PROG_RUN` at 6.6 and 6.12 computes `data_end` for tc and lwt, and not for cgroup skb; at 7.0.11 it does for cgroup skb too | a cgroup skb program's direct packet read is measured attached; its `len` runs attach-free; `kernel/suite.b` holds each measured line to its answer |
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

Every "measured on plo" row ran on 6.12.93, 2026-11-03 or 2026-11-04, and every row in `kernel/suite.b`, `kernel/object_suite.b` and `kernel/net_suite.b` also answers on 6.6.142, 6.12.92 and 7.0.11 through the matrix.

| Item | Tier | Shown by |
|---|---|---|
| `baito` layouts | built | `bidamas/baito/baito.b`; 7 of 7 mutants caught |
| encoder, every instruction form | built, checked against LLVM | `kernel/isa_llvm.b`: 166 of 166 byte-identical to `llvm-mc --mcpu=v4` |
| machine against the kernel: ALU, jumps, swaps, memory, atomics | built, measured on plo | `kernel/suite.b`: 7,168 ALU programs over edge values |
| maps, ring buffer, pins, program id, verifier log | built, measured on plo | `kernel/suite.b` |
| compiler: integers, booleans, locals, `if`, inlined calls, tail loops, maps, packets, events, helpers | built | `bidamas/kaaneru/bpf/bpf.b`; 21 of 21 mutants caught |
| one source agrees in interpreter, machine and kernel | built, measured on plo | `kernel/suite.b`, "one source": 456 inputs |
| tracepoint attach and detach | built, measured on plo | `kernel/suite.b` |
| kprobe through a perf event | built, measured on plo | `kernel/suite.b`; a NixOS 25.11 kernel leaves `CONFIG_FPROBE` off |
| kprobe_multi | built, run where the kernel has `CONFIG_FPROBE`, and a named refusal elsewhere | `kernel/suite.b` on `vm-kernel-6-12-fprobe`, a 6.12.92 built from source with it on: the link attaches and an event arrives. On plo, 6.6.142, 6.12.92 and 7.0.11 it answers `EOPNOTSUPP`, held there by `vm_check`; a stock kernel told to expect `attached` went red |
| XDP and tcx on a real interface | built, measured on plo | `kernel/net_suite.b`: ping drops, is counted, returns on detach |
| `btf`: read a kernel's types, find a hook, a field's offset through anonymous unions | built, measured on plo's 115,470 types | `bidamas/kaaneru/btf/btf.b`; `kernel/suite.b` |
| fentry found through BTF, a field read at the kernel's own offset | built, measured on plo | `kernel/suite.b`: the field equals the thread id |
| LSM program that counts, and one that denies only its target | built, measured on plo | `kernel/suite.b` |
| a field of another size on this kernel refuses at load | built | `bpf::bind_fields` |
| `:kernel_bpf` forces the native rung | built | `deploy::service` tests |
| chart: exact capabilities for a service that reaches the kernel | built, not deployed | `bidamas/eigyou/haibi/haibi.b`; `nix/chart-gate.b`; the values schema holds them as `const`; no release uses it |
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
| `BPF_PROG_RUN`: a cgroup skb's direct packet read | a named refusal on 6.6 and 6.12, runs on 7.0.11 | `kernel/suite.b`: the older kernels leave `data_end` unset in this run, and the attached row measures the read there |
| ELF object, written and read (`erufu`) | built, checked against clang and LLVM, measured on plo | `kernel/object_llvm.b`: sections, symbols, relocations, disassembly, BTF and func_info equal to clang's for one program, `readelf -a` silent, a changed instruction seen; `kernel/object_suite.b`: `bpftool` dumps, loads and runs it, `veristat` verifies it, a clang object loads through blue |
| line info in an object and at load | built, measured on plo | `bpf::compile` marks each statement through `blue ast --resolved --lines`; `kernel/object_suite.b`: `bpftool prog dump xlated linum` prints blue's lines with `[file:kernel/programs/object.b line_num:…]`; `kernel/object_llvm.b` holds the `.BTF.ext` sections equal to clang's. `{lines: false}` and `erufu::object(p, {line_info: false})` leave them out |
| a refusal names the blue line and the reason | built, measured on plo | `kernel/object_suite.b`, `kernel/programs/refused.b`: `load read_far: EACCES at kernel/programs/refused.b:11:3: invalid bpf_context access off=1000 size=4`, and the verifier's own log holds `; far = ctx_int(c, 1000, 4) @ refused.b:11`. A plain program that loads carries no BTF; only a refused one loads again with its lines |
| CO-RE relocations in an object: a byte offset, for a field read through `kernel_read` | built, checked against clang, measured on plo with one kernel | `kernel/object_suite.b`: libbpf moves `r3 += 0` to this kernel's offset of `task_struct.pid`, and to 12 from a second BTF named by `kernel_btf`; clang's record for the same field is equal; blue reads and binds its own and clang's. `{core: false}` refuses, as before. A second real kernel has not run. A field of another size is not refused here, as `bpf::bind_fields` refuses it: libbpf's relocation moves the offset alone. Other kinds (size, existence, type) are not built |
| a map value reference in an object: a one-entry array as `.data.NAME` | built, checked against clang and LLVM, measured on plo | `kernel/object_llvm.b` "value": sections, symbols, relocations, disassembly and BTF equal to clang's; `kernel/object_suite.b`: `bpftool` loads and runs it for 42, blue reads it back, kernel and machine agree. A map also named as a map, or of another shape, is refused by name; a section holding other bytes is not read, its contents having no form at load |
| reading an object: functions nothing reaches are dropped, as libbpf drops them | built, measured on plo | `kernel/object_suite.b`: a clang object with an unreached function loads through blue and answers 2. `{keep_unreached: true}` links all of `.text`, which the verifier refuses: `number of funcs in func_info doesn't match number of subprogs`. A CO-RE relocation at an instruction with no immediate is refused by name, where it was silently read at its local offset |
| program BTF: functions, maps, `license`, `.BTF.ext` | built, measured on plo | `btf::encode`, `bpf::program_btf`; `kernel/object_suite.b`: the kernel reports 2 in `nr_func_info` and a `btf_id` |
| global subprograms in the compiler, by `{global: [...]}`; inlining stays the default | built, measured on plo | `kernel/suite.b`, "one source with a global subprogram": 456 inputs agree in interpreter, machine and kernel, faults included; a static reader loads where a global one is refused |
| spin lock: `declare_locked`, `locked_add` | built, measured on plo, one CPU at a time | `kernel/object_suite.b`: 1,001 adds counted, machine agrees on the first, the kernel's two refusals seen; contention across CPUs has not run |
| callback: `func_ref`, `bpf_loop` | built for assembled programs, measured on plo | `kernel/object_suite.b`: kernel and machine both count 3 |
| callback in the compiler: `loop_fold(n, init, step)` | built, measured on plo | `kernel/suite.b`, "one source with a callback": 456 inputs agree in interpreter, machine and kernel, a checked add's overflow inside the step included. `step` is a top-level definition, compiled as a static function that reads and writes the value and a fault flag through a pointer to its caller's slots |
| a kernel matrix in machines, through `vm_check` | built, run on a hosted runner with KVM, 2026-11-04 | `.github/workflows/kernel-matrix.yml`, generated from the Bluefile, on a schedule, by hand, on a `kernel-matrix/**` branch and after a push to main that touches the kernel; never on a land. 6.6.142, 6.12.92, 7.0.11 and a 6.12.92 built with `CONFIG_FPROBE` each boot and answer 38 of 38 in `kernel/suite.b`, 11 of 11 in `kernel/object_suite.b`, 9 of 9 in `kernel/net_suite.b`, with `kernel/control.b` red in each. A stock kernel takes 12 to 16 minutes and the built one about 2 hours. Seen red three times: a stock kernel told to expect kprobe_multi attached, 7.0.11 gave cgroup skb a packet the suite said it would not, and with the division guard off 6.6.142 panicked with a divide error. Off KVM, `checks.vm-kernel-absent` says none of it ran. plo stays the one host for `blue kernel/run.b on HOST` |
| a check of every kernel file and program, with no kernel | built | `checks.kernel-compile`: 27 files and 21 programs on any host at land time; rule B0072 holds a call to its definition's argument count, which `blue check` did not before |
| `kaaneru::attached`: load onto one of `hooks`, run a body, close everything, a spec and a kind that do not fit refused before the kernel | built, measured on plo | `kernel/suite.b`, `kernel/net_suite.b`: 12 call sites attach through it, over xdp, tcx, cgroup skb, sock and device, netfilter, fentry, fexit, fmod_ret, lsm and raw tracepoint, and a raise from the body closes the link; tracepoint, kprobe and iter have their own words measured and have not run through it; the refusals are in `bidamas/kaaneru/kaaneru.b` |
| `blue new --kernel`: a project that passes with no kernel, its real-kernel test skipped by name | built, measured on plo | `gen/kernel-new.b` holds the template to the words; `kernel/suite.b`: `BLUE_TEST_SKIP=refuse` passes on 6.12.93. The tutorial followed as written on plo: 4 of 4 tests as root, 3 ICMP dropped on `lo` in a namespace, ping back after; `EPERM` named as the skip when not root |
| kanshi's LSM enforcer in blue | built, measured on plo 2026-11-04 scoped to spawned processes, off by default, never run host-wide | kanshi `enforcer/differential.b`: 144 of 144 questions agree with the C's logic, 192 denials all in targets, 5 of 5 mutants caught; kanshi's `CLAUDE.md` says why it stays off |

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

Every nix call in a run reads a cache of its own under `target/kernel-run`, since a
damaged `~/.cache/nix/tarball-cache` stops every `nix develop` that reads it;
`KERNEL_RUN_BUILD__PRIVATE_CACHE=false` hands it back the host's.

From another machine, one command does the rest:

```text
blue kernel/run.b on HOST [REF]
```

It reads admission from the host, brings REF (`HEAD` by default) to the host, by a shallow
fetch there when origin holds it and as a tree when it does not, so REF needs no
push, and makes a directory only this run owns under
`/tmp/blue-kernel-runs`. It starts the run detached under
`flock /tmp/blue-kernel.lock`, so a dropped session loses nothing, and prints each
tally as its suite ends. The run builds the tree's blue at idle priority. Once this
side has read the log's last line, the runner on the host removes its directory;
with this side gone, it does so after `on.linger_seconds`. A build that fails has
no runner, and the next run on that host sweeps what it left, as it does for a
host that rebooted. `KERNEL_RUN_ON__CLEANUP=false` keeps the directory, and the
`KERNEL_RUN_*` settings on this side reach the host's run, the filter included.

`gen/kernel-compile.b` (`checks.kernel-compile`) holds every file here to the check
stage and every program to the compiler, with no kernel, on any host, at land time.

The encoder's check needs only an `llvm-mc`:

```text
BLUE_PATH=bidamas blue kernel/isa_llvm.b "$(nix build --no-link --print-out-paths nixpkgs#llvmPackages.llvm)/bin/llvm-mc"
```
