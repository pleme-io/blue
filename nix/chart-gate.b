@moduledoc """
chart-gate: Judge the objects `helm template` renders for a service against what its access declares. A service that reaches the kernel holds exactly CAP_BPF, CAP_PERFMON and CAP_NET_ADMIN, mounts bpffs and a read-only tracefs from the host and no other host path, and joins the host network only when declared; any other service holds none of it. The expected shape is written here, not read from the renderer, since a gate derived from what it checks passes whatever it renders.

    blue run chart-gate.b -- RENDERED.yaml (kernel|plain) (host_network|own_network) (per_node|one_set)
"""

use("deeta", [:parse])

use("retsu", %i[first flat_map])

use("shuugou", [:as_set])

@doc """
workloads: The objects that run pods.

    workloads([{"kind" => "Service"}, {"kind" => "DaemonSet"}]) #=> [{"kind" => "DaemonSet"}]
    workloads([nil]) #=> []
"""
def workloads(docs)
  filter(
    fn(d)
      d != nil and member?(d["kind"], %w[Deployment DaemonSet StatefulSet])
    end,
    docs
  )
end

def named(rows, name)
  first(filter((r) -> r["name"] == name, as_set(rows)))
end

def check_mount(pod, container, name, path, read_only)
  mount = named(container["volumeMounts"], name)
  volume = named(pod["volumes"], name)
  if mount.nil? or volume.nil?
    ["#{name}_missing"]
  elsif mount["mountPath"] != path or
      volume["hostPath"].nil? or
      volume["hostPath"]["path"] != path
    ["#{name}_elsewhere"]
  elsif mount["readOnly"] == true != read_only
    ["#{name}_access"]
  else
    []
  end
end

def host_paths(pod)
  map(
    (v) -> v["hostPath"]["path"],
    filter((v) -> v["hostPath"] != nil, as_set(pod["volumes"]))
  )
end

def propagation(container)
  map((m) -> m["mountPropagation"], as_set(container["volumeMounts"]))
end

def added(container)
  sc = container["securityContext"]
  if sc.nil? or sc["capabilities"].nil?
    []
  else
    as_set(sc["capabilities"]["add"])
  end
end

def posture_faults(pod, container)
  sc = container["securityContext"]
  flags = [
    [sc.nil? or sc["privileged"] == true, :privileged],
    [sc.nil? or sc["allowPrivilegeEscalation"] != false, :escalation],
    [sc.nil? or sc["readOnlyRootFilesystem"] != true, :writable_root],
    [
      sc.nil? or
        sc["capabilities"].nil? or
        sc["capabilities"]["drop"] != ["ALL"],
      :capabilities_kept
    ],
    [pod["hostPID"] == true, :host_pid],
    [pod["hostIPC"] == true, :host_ipc]
  ]
  map((f) -> second(f), filter((f) -> first(f), flags))
end

def network_faults(pod, host_network)
  if host_network and pod["hostNetwork"] != true
    [:host_network_missing]
  elsif not host_network and pod["hostNetwork"] == true
    [:host_network_undeclared]
  else
    []
  end
end

def kernel_faults(pod, container)
  caps = added(container)
  widened = if retsu::reject(
      (c) -> member?(c, %w[BPF PERFMON NET_ADMIN]),
      caps
    ) != []
    [:capability_widened]
  else
    []
  end
  narrowed = if retsu::reject(
      (c) -> member?(c, caps),
      %w[BPF PERFMON NET_ADMIN]
    ) != []
    [:capability_missing]
  else
    []
  end
  root = if pod["securityContext"].nil? or
      pod["securityContext"]["runAsUser"] != 0
    [:not_root]
  else
    []
  end
  stray = if retsu::reject(
      (p) -> member?(p, %w[/sys/fs/bpf /sys/kernel/tracing]),
      host_paths(pod)
    ) != []
    [:host_path_undeclared]
  else
    []
  end
  bidirectional = if member?("Bidirectional", propagation(container))
    [:bidirectional]
  else
    []
  end
  flat_map(
    [
      widened,
      narrowed,
      root,
      stray,
      bidirectional,
      check_mount(pod, container, "bpffs", "/sys/fs/bpf", false),
      check_mount(pod, container, "tracefs", "/sys/kernel/tracing", true)
    ],
    (x) -> x
  )
end

def plain_faults(pod, container)
  caps = if added(container) != []
    [:capability_widened]
  else
    []
  end
  paths = if host_paths(pod) != []
    [:host_path_undeclared]
  else
    []
  end
  append(caps, paths)
end

@doc """
faults: Every way the rendered objects leave what the service declares, as names.

    faults([], {kernel: false, host_network: false, per_node: false}) #=> [:no_workload]
"""
def faults(docs, declared)
  sets = workloads(docs)
  if count(sets) != 1
    [:no_workload]
  else
    set = first(sets)
    pod = set["spec"]["template"]["spec"]
    container = first(pod["containers"])
    kind = if declared[:per_node]
      "DaemonSet"
    else
      "Deployment"
    end
    wrong = if set["kind"] != kind
      [:wrong_kind]
    else
      []
    end
    shape = if declared[:kernel]
      kernel_faults(pod, container)
    else
      plain_faults(pod, container)
    end
    flat_map(
      [
        wrong,
        posture_faults(pod, container),
        network_faults(pod, declared[:host_network]),
        shape
      ],
      (x) -> x
    )
  end
end

def main()
  docs = parse(read_file(argv[0]), :yaml, {documents: :all})
  found = faults(
    docs,
    {
      kernel: argv[1] == "kernel",
      host_network: argv[2] == "host_network",
      per_node: argv[3] == "per_node"
    }
  )
  if found != []
    raise(:gate, "the chart leaves what its access declares: #{to_s(found)}")
  end
  write_stdout(
    unlines(["chart: #{to_s(count(workloads(docs)))} workload, no finding"])
  )
end

def agent()
  {
    "kind" => "DaemonSet",
    "spec" => {
      "template" => {
        "spec" => {
          "hostNetwork" => true,
          "securityContext" => {"runAsUser" => 0},
          "volumes" => [
            {"name" => "bpffs", "hostPath" => {"path" => "/sys/fs/bpf"}},
            {
              "name" => "tracefs",
              "hostPath" => {"path" => "/sys/kernel/tracing"}
            }
          ],
          "containers" => [
            {
              "name" => "agent",
              "securityContext" => {
                "allowPrivilegeEscalation" => false,
                "readOnlyRootFilesystem" => true,
                "capabilities" => {
                  "drop" => ["ALL"],
                  "add" => %w[BPF PERFMON NET_ADMIN]
                }
              },
              "volumeMounts" => [
                {
                  "name" => "bpffs",
                  "mountPath" => "/sys/fs/bpf",
                  "mountPropagation" => "HostToContainer"
                },
                {
                  "name" => "tracefs",
                  "mountPath" => "/sys/kernel/tracing",
                  "readOnly" => true
                }
              ]
            }
          ]
        }
      }
    }
  }
end

def declared()
  {kernel: true, host_network: true, per_node: true}
end

def with_pod(k, v)
  a = agent
  pod = assoc(a["spec"]["template"]["spec"], k, v)
  assoc(a, "spec", {"template" => {"spec" => pod}})
end

def with_container(k, v)
  c = assoc(first(agent["spec"]["template"]["spec"]["containers"]), k, v)
  with_pod("containers", [c])
end

def with_security(k, v)
  sc = first(agent["spec"]["template"]["spec"]["containers"])["securityContext"]
  with_container("securityContext", assoc(sc, k, v))
end

def with_caps(add)
  with_security("capabilities", {"drop" => ["ALL"], "add" => add})
end

test "the chart that holds what a node agent declares has no finding"
  assert faults([agent], declared) == []
  assert faults([nil, {"kind" => "Service"}, agent], declared) == []
end

test "a capability widened is named, and so is one missing"
  assert faults([with_caps(%w[BPF PERFMON NET_ADMIN SYS_ADMIN])], declared) ==
    [:capability_widened]
  assert faults([with_caps(%w[BPF PERFMON])], declared) == [:capability_missing]
end

test "a mount missing is named, whichever half of it is gone"
  containers = get(
    first(agent["spec"]["template"]["spec"]["containers"]),
    "volumeMounts"
  )
  volumes = agent["spec"]["template"]["spec"]["volumes"]
  assert faults([with_container("volumeMounts", [containers[1]])], declared) ==
    ["bpffs_missing"]
  assert faults([with_container("volumeMounts", [containers[0]])], declared) ==
    ["tracefs_missing"]
  assert faults([with_pod("volumes", [volumes[1]])], declared) ==
    ["bpffs_missing"]
  assert faults([with_pod("volumes", [volumes[0]])], declared) ==
    ["tracefs_missing"]
end

test "a mount at another path, a writable tracefs or a read-only bpffs is named"
  ms = first(agent["spec"]["template"]["spec"]["containers"])["volumeMounts"]
  moved = assoc(ms[0], "mountPath", "/var/bpf")
  assert faults([with_container("volumeMounts", [moved, ms[1]])], declared) ==
    ["bpffs_elsewhere"]
  writable = assoc(ms[1], "readOnly", false)
  assert faults(
    [with_container("volumeMounts", [ms[0], writable])],
    declared
  ) == ["tracefs_access"]
  frozen = assoc(ms[0], "readOnly", true)
  assert faults([with_container("volumeMounts", [frozen, ms[1]])], declared) ==
    ["bpffs_access"]
end

test "a host path nobody declared and Bidirectional propagation are named"
  vs = agent["spec"]["template"]["spec"]["volumes"]
  stray = {"name" => "root", "hostPath" => {"path" => "/"}}
  assert faults([with_pod("volumes", append(vs, [stray]))], declared) ==
    [:host_path_undeclared]
  ms = first(agent["spec"]["template"]["spec"]["containers"])["volumeMounts"]
  both = assoc(ms[0], "mountPropagation", "Bidirectional")
  assert faults([with_container("volumeMounts", [both, ms[1]])], declared) ==
    [:bidirectional]
end

test "privilege, escalation, a writable root and kept capabilities are named"
  assert faults([with_security("privileged", true)], declared) == [:privileged]
  assert faults([with_security("allowPrivilegeEscalation", true)], declared) ==
    [:escalation]
  assert faults([with_security("readOnlyRootFilesystem", false)], declared) ==
    [:writable_root]
  kept = with_security("capabilities", {"add" => %w[BPF PERFMON NET_ADMIN]})
  assert faults([kept], declared) == [:capabilities_kept]
end

test "the host's other namespaces and a pod that is not root are named"
  assert faults([with_pod("hostPID", true)], declared) == [:host_pid]
  assert faults([with_pod("hostIPC", true)], declared) == [:host_ipc]
  assert faults(
    [with_pod("securityContext", {"runAsUser" => 65532})],
    declared
  ) == [:not_root]
end

test "host network follows the declaration in both directions"
  assert faults([agent], assoc(declared, :host_network, false)) ==
    [:host_network_undeclared]
  assert faults([with_pod("hostNetwork", false)], declared) ==
    [:host_network_missing]
end

test "the wrong workload kind, or no workload, is named"
  assert faults([assoc(agent, "kind", "Deployment")], declared) == [:wrong_kind]
  assert faults([], declared) == [:no_workload]
  assert faults([agent, agent], declared) == [:no_workload]
end

test "a service that does not reach the kernel holds no capability and no host path"
  plain = assoc(declared, :kernel, false)
  plain_decl = assoc(assoc(plain, :host_network, true), :per_node, true)
  assert faults([agent], plain_decl) ==
    %i[capability_widened host_path_undeclared]
end

test "helm's rendered text reads through the one YAML reader"
  docs = parse(
    join_lines(
      [
        "---",
        "# Source: agent/templates/daemonset.yaml",
        "apiVersion: apps/v1",
        "kind: DaemonSet",
        "---",
        "kind: Service"
      ]
    ),
    :yaml,
    {documents: :all}
  )
  assert count(workloads(docs)) == 1
end
