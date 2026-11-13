@moduledoc """
keiyu (経由) — by way of: run one command with a proxy set for it alone.

`run_via(url, command)` execs `command` with every proxy variable a client
reads set to `url` in the child's environment alone; `main` reads the relay
from `KEIYU_RELAY`. An empty command is refused as `:keiyu_no_command`.

    relay_env("socks5h://r:1")[0] #=> %w[ALL_PROXY socks5h://r:1]
    relay_env("socks5h://r:1")[5] #=> %w[http_proxy socks5h://r:1]
"""

use("retsu", %i[first is_empty rest])
use("shisutemu", %i[status_of stdout_of])

def proxy_names()
  %w[ALL_PROXY all_proxy HTTPS_PROXY https_proxy HTTP_PROXY http_proxy]
end

def relay_env(url)
  map((n) -> [n, url], proxy_names)
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
def run_via(url, command)
  if is_empty(command)
    error(
      :keiyu_no_command,
      "keiyu runs a command through the relay: keiyu <command> [args...]"
    )
  end
  exec_into(relay_env(url), first(command), *rest(command))
end

def main()
  run_via(env_required("KEIYU_RELAY"), argv)
end

test "every proxy variable a client reads names the relay"
  assert relay_env("socks5h://r:1") ==
    [
      %w[ALL_PROXY socks5h://r:1],
      %w[all_proxy socks5h://r:1],
      %w[HTTPS_PROXY socks5h://r:1],
      %w[https_proxy socks5h://r:1],
      %w[HTTP_PROXY socks5h://r:1],
      %w[http_proxy socks5h://r:1]
    ]
end

test "an empty command is refused"
  assert (run_via("socks5h://r:1", []) rescue :refused) == :refused
end

test "the proxy reaches the child and never this process"
  before = getenv("ALL_PROXY")
  if self_exe != nil
    dir = path_join(temp_dir("keiyu"), "keiyu")
    mkdir_p(dir)
    prog = path_join(dir, "child.b")
    write_program(prog, unlines(["use(\"keiyu\", [:main])", "main()"]))
    cap = exec_with_env(
      [%w[KEIYU_RELAY socks5h://relay.test:11080]],
      self_exe,
      "run",
      "--quiet",
      prog,
      "--",
      "printenv",
      "ALL_PROXY"
    )
    rm_rf(dir)
    assert status_of(cap) == 0
    assert stdout_of(cap) == unlines(["socks5h://relay.test:11080"])
  end
  assert getenv("ALL_PROXY") == before
end
