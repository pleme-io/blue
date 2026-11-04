---
kind: howto
order: 13
summary: declare a service that reaches the kernel, see the DaemonSet and exact capabilities blue renders, and test it with no cluster
---

# Ship a node agent

A node agent is a service that loads kernel programs on each node. You declare
the `:kernel_bpf` effect in its `Bluefile`, and blue renders the rest: a DaemonSet,
`CAP_BPF`, `CAP_PERFMON` and `CAP_NET_ADMIN`, and the `bpffs` and `tracefs` mounts.
The rendered chart is checked here. No cluster has run it yet, so test it on yours
first.

```console
$ mkdir agent
$ cd agent
```

```blue file=Bluefile
package("agent", "0.1.0")

service(
  "agent",
  {
    program: "agent.b",
    repository: "ghcr.io/example/agent",
    port: 8080,
    access: {
      effects: %i[network clock entropy environment kernel_bpf],
      host_network: true
    },
    runtime: :native,
    because: :device
  }
)

check("agent", "agent.b")
```

`runtime: :native` with `because: :device` is required: WASI reaches no kernel
ABI. The program answers health checks like any service. Load your kernel program
beside `serve_settings` with the words in
[the first kernel program](../tutorial/first-kernel-program.md).

```blue file=agent.b
use("kyuuji")
use("settei")

def handle(req)
  if req[:path] == "/"
    kyuuji::text(200, unlines(["agent"]))
  else
    kyuuji::not_found(req)
  end
end

if settei::serving?
  kyuuji::serve_settings(settei::current, handle)
end

test "the root answers, and anything else is not found"
  assert handle(kyuuji::request("GET", "/", ""))[:status] == 200
  assert handle(kyuuji::request("GET", "/x", ""))[:status] == 404
end
```

```console
$ blue lock .
./Bluefile.lock: 0 source(s) pinned
$ blue test agent.b
1 test(s): 1 passed, 0 failed
```

This program shows what the declaration renders:

```blue file=../show.b
use("haibi", %i[container_security files workload_kind])
use("retsu", [:first])

m = get(json_read(read_file("agent/Bluefile.lock")), "manifest")
spec = get(get(m, "services"), "agent")
paths = map(first, files("agent", get(m, "version"), spec))
write_stdout(unlines(filter((p) -> contains?(p, "daemonset"), paths)))
write_stdout(unlines([workload_kind(spec)]))
write_stdout(unlines(container_security(spec)["capabilities"]["add"]))
```

```console
$ cd ..
$ blue show.b
chart/templates/daemonset.yaml
DaemonSet
BPF
PERFMON
NET_ADMIN
```

`host_network` and `per_node` mean nothing without the effect, so a service that
writes one without `:kernel_bpf` is refused by name when it locks:

```blue file=refused/Bluefile
package("refused", "0.1.0")

service(
  "refused",
  {
    program: "refused.b",
    repository: "ghcr.io/example/refused",
    port: 8080,
    access: {host_network: true}
  }
)
```

```blue file=refused/refused.b
def noop()
  nil
end

test "it passes"
  assert noop.nil?
end
```

```console fails
$ blue lock refused
lacks the :kernel_bpf effect
```

A real agent adds the one-line `flake.nix` that `blue new --kernel` writes. Then
nix builds the image and checks the chart against this shape:

```console host
$ nix flake check
```

`per_node: false` keeps the service a Deployment. The fields are in
[SERVICE-ACCESS.md](../SERVICE-ACCESS.md), and which capability each kind of hook
needs is in [KERNEL.md](../KERNEL.md) §3.
