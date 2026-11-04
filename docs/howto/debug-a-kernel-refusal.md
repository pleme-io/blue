---
kind: howto
order: 12
summary: find which layer refused a kernel program, the compiler, the machine or the verifier, and read why
---

# Debug a kernel refusal

Three layers can say no, and each names its error kind. Find the layer first:

| Error kind | Who says it | When |
|---|---|---|
| `:bpf_compile` | blue's compiler | at `compile`, on any host |
| `:bpf_fault` | the pure machine | at `bpf::run`, on any host |
| `:kernel_refused` | the kernel's verifier | at load, on Linux |
| `:kernel_mismatch` | the loader | a field has another size on this kernel |
| `:unsupported` | the host | off Linux, at any word that reaches the kernel |

## The compiler

`:bpf_compile` names the construct. Most refusals come from a value the verifier
would have to bound. Here `*` has operands of unknown range, and the compiler asks
you to bound them or to say that wrapping is what you want:

```blue file=product.b
use("bpf", %i[compile packet_int])

def product(ctx)
  packet_int(ctx, 0, 8) * packet_int(ctx, 8, 8)
end

compile("product.b", {entry: :product, kind: :xdp, on_fault: 0})
```

```console fails
$ blue product.b
bpf_compile
cannot be checked in a kernel program
```

## The machine

`:bpf_fault` means an assembled program did something the machine does not allow.
The machine does not check as much as the verifier does, so this layer finds
faults and does not promise a load:

```blue file=fault.b
use("bpf", %i[assemble exit_program load])

def outside()
  assemble([load(:b, 0, 1, 99999), exit_program])
end

test "a read outside every region is a fault, and the message says where"
  got = begin
    bpf::run(outside)
  rescue :bpf_fault as e
    e.message
  end
  assert contains?(got, "outside every region")
end
```

```console
$ blue test fault.b
1 test(s): 1 passed, 0 failed
```

## The verifier

`:kernel_refused` carries the errno's name and the verifier's whole log as data:
`e.data.name` and `e.data.log`. This program reads a register nothing wrote. It
needs Linux and root:

```blue file=refused.b
use("bpf", %i[alu assemble exit_program r])
use("kaaneru")

def main()
  kaaneru::load(
    assemble([alu(:mov, 0, r(5)), exit_program]),
    {kind: :xdp, name: "refused"}
  )
rescue :kernel_refused as e
  write_stdout(unlines([e.data.name, e.data.log]))
end
```

```console host
$ sudo blue run --allow host --quiet refused.b
EACCES
0: R1=ctx() R10=fp0
0: (bf) r0 = r5
R5 !read_ok
processed 1 insns (limit 1000000) max_states_per_insn 0 total_states 0 peak_states 0 mark_read 0
```

Read the log from the end. The last instruction it names is the one that failed,
and the line after it is the reason. `R5 !read_ok` says that nothing wrote `r5`.
The lines above show what the verifier knew about each register at each step.

To see the instructions by number, print the program:

```blue file=text.b
use("bpf", %i[alu assemble disassemble encode exit_program r])

test "the listing numbers each instruction as the log does"
  listed = disassemble(encode(assemble([alu(:mov, 0, r(5)), exit_program])))
  assert listed == ["r0 = r5", "exit"]
end
```

```console
$ blue test text.b
1 test(s): 1 passed, 0 failed
```

`kernel_absence` says why a host cannot load at all. A test passes it to
`tesuto::skip_for`, so the test is skipped by name and not passed. `BLUE_TEST_SKIP=refuse` turns each skip into a
failure, for a host where every test must run.
