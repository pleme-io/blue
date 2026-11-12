@moduledoc """
sysctl_guard: A cgroup sysctl program: inside its cgroup a sysctl reads and does not write. kernel/net_suite.b attaches it to a test cgroup.

    blue test --allow host kernel/net_suite.b
"""

use("kaaneru/bpf", [:ctx_int])

def no_sysctl_write(ctx)
  if ctx_int(ctx, 0, 4) == 1
    0
  else
    1
  end
end
