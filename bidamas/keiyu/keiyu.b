use("retsu", [:first, :is_empty, :rest])
use("shisutemu", [:status_of, :stdout_of])

# keiyu (経由) — by way of: run one command with a proxy set for it alone.
def proxy_names()
  [
    "ALL_PROXY",
    "all_proxy",
    "HTTPS_PROXY",
    "https_proxy",
    "HTTP_PROXY",
    "http_proxy"
  ]
end

def relay_env(url)
  map(fn(n) [n, url] end, proxy_names())
end

def run_via(url, command)
  if is_empty(command)
    error(
      :keiyu_no_command,
      "keiyu runs a command through the relay: keiyu <command> [args...]"
    )
  end
  apply(exec_into, relay_env(url), first(command), rest(command))
end

def main()
  run_via(env_required("KEIYU_RELAY"), argv())
end

test "every proxy variable a client reads names the relay"
  assert relay_env("socks5h://r:1") ==
    [
      ["ALL_PROXY", "socks5h://r:1"],
      ["all_proxy", "socks5h://r:1"],
      ["HTTPS_PROXY", "socks5h://r:1"],
      ["https_proxy", "socks5h://r:1"],
      ["HTTP_PROXY", "socks5h://r:1"],
      ["http_proxy", "socks5h://r:1"]
    ]
end

test "an empty command is refused"
  assert try(run_via("socks5h://r:1", []), catch(_e(), :refused)) == :refused
end

test "the proxy reaches the child and never this process"
  before = getenv("ALL_PROXY")
  if self_exe() != nil
    dir = path_join(getenv("TMPDIR", "/tmp"), "keiyu-#{to_s(now_ns())}")
    mkdir_p(dir)
    prog = path_join(dir, "child.b")
    write_file(prog, "use(\"keiyu\", [:main])\nmain()\n")
    cap = exec_with_env(
      [["KEIYU_RELAY", "socks5h://relay.test:11080"]],
      self_exe(),
      "run",
      "--quiet",
      prog,
      "--",
      "printenv",
      "ALL_PROXY"
    )
    rm_rf(dir)
    assert status_of(cap) == 0
    assert stdout_of(cap) == "socks5h://relay.test:11080\n"
  end
  assert getenv("ALL_PROXY") == before
end
