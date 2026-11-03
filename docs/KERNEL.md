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
| types | `btf` | the kernel's own types: hook ids, field offsets | filesystem |
| kernel client | `kaaneru` | maps, programs, links, pins, ring buffers, tracepoints, kprobes, fentry, LSM | `kernel_bpf` |
| the seam | `blue-lang-kernel` | `bpf(2)`, `perf_event_open(2)`, ioctl, mmap of the ring | Linux; one `unsafe` module |

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
| only the 512-byte stack and 8 frames hold across the range | the compiler inlines every call and holds 64 slots |
| a back-edge needs `CAP_BPF` | tail recursion lowers to a loop only for a privileged loader |
| XDP, tcx, cgroup, fentry, fexit, lsm, iter, netfilter, kprobe_multi, uprobe_multi and struct_ops attach through `BPF_LINK_CREATE` alone at 6.6 | no netlink in the attach path |
| perf_event, tracepoint and a single kprobe still need a `perf_event_open` descriptor | the seam has that one extra call |
| one program attaches once to one tracepoint, whichever CPU its event names | a second event for it answers `EEXIST`, as measured on plo |
| `BPF_PROG_RUN` serves XDP, tc, socket filter, cgroup skb, lwt, flow dissector, sk_lookup, netfilter, raw tracepoint and syscall; it refuses LSM; tracing runs only at fixed test functions | those kinds test attach-free; LSM and tracing test attached |
| global subprograms, callbacks and spin locks need program BTF; plain programs, ring buffers and maps do not | inlining keeps the first compiler free of BTF generation |
| `veristat` reads ELF through libbpf | a raw stream needs `erufu` before that tool applies |
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

Every "measured on plo" row ran on 6.12.93, 2026-11-03.

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
| chart: exact capabilities for a service that reaches the kernel | built, not deployed | `bidamas/haibi/haibi.b`; no release uses it |
| chart: DaemonSet, host network, bpffs and tracefs mounts | design | a node agent needs them |
| cgroup and netfilter attach | written, not run | `kaaneru::attach` takes them; a cgroup descriptor has no word yet |
| ELF object, so `bpftool` and `veristat` apply (`erufu`) | design | |
| program BTF generation (global subprograms, spin locks) | design | inlining avoids the need today |
| a kernel matrix in a VM as a nix check | design | until it runs, the kernel words' real behaviour is proven only by running `kernel/suite.b` by hand; their tests beside them reach the refusals |
| kanshi's LSM enforcer in blue | design | the first real consumer |

## 7. Running the kernel suites

The suites load programs, so they need root and Linux. Run them from the
repository root at low priority. Two kinds of run can disturb a host, and the
split below keeps both away from it:

- `kernel/suite.b` attaches read-only tracepoints and kprobes, and an LSM program
  that denies only its own process. It removes the one pin it makes.
- `kernel/net_suite.b` makes interfaces, so it runs inside a private network
  namespace, where no daemon on the host sees them.

```text
sudo env BLUE_TEST_WRITES=anywhere BLUE_PATH=$PWD/bidamas target/debug/blue test --allow host kernel/suite.b

sudo ip netns add blue_suite
sudo ip netns exec blue_suite env BLUE_PATH=$PWD/bidamas target/debug/blue test --allow host kernel/net_suite.b
sudo ip netns del blue_suite
```

`BLUE_TEST_WRITES` is on the command line because a pin's path lies outside the
test sandbox. The encoder's check needs only an `llvm-mc`:

```text
BLUE_PATH=bidamas blue kernel/isa_llvm.b "$(nix build --no-link --print-out-paths nixpkgs#llvmPackages.llvm)/bin/llvm-mc"
```
