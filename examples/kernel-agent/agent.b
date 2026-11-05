@moduledoc """
agent: A node agent's shape, and no more: its Bluefile declares `:kernel_bpf` and `host_network`, and everything else about how it runs on a node (a DaemonSet, CAP_BPF, CAP_PERFMON and CAP_NET_ADMIN, bpffs and a read-only tracefs) is rendered into `deploy/`. It loads no program, so `checks.example-kernel-agent` runs in any sandbox. docs/KERNEL.md §7 runs real kernel programs.
"""

use("eigyou/kyuuji")
use("settei")

def handle(req)
  if req[:path] == "/"
    eigyou::kyuuji::text(200, unlines(["kernel agent"]))
  else
    eigyou::kyuuji::not_found(req)
  end
end

if settei::serving?
  eigyou::kyuuji::serve_settings(settei::current, handle)
end

test "the root answers, and anything else is not found"
  assert handle(eigyou::kyuuji::request("GET", "/", ""))[:status] == 200
  assert handle(eigyou::kyuuji::request("GET", "/x", ""))[:status] == 404
end
