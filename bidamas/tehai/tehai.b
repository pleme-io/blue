use("deeta", [:as_json, :get_int, :get_str])
use("moji", [:after_first, :before_first, :includes])

use(
  "retsu",
  [:concat_lists, :contains, :find_first, :first, :is_empty, :size, :take_n]
)

use(
  "shisutemu",
  [:last_nonempty_line, :read_or, :status_of, :stderr_of, :stdout_of]
)

legacy_names("0.1.1", "th")

# tehai (手配) — which nix remote builders can take work right now: every declared machine checked, and only the live ones written where nix reads them.
#
# nix reads its remote builders from a machines file (`builders = @<path>`).
# Written by hand or by a system config, that file names machines whether
# they are up or not, so a dead builder costs a TCP timeout on every
# dispatch, and a builder switched off by hand ("offline") stays off after it
# comes back. tehai separates the two facts: the DECLARED set (a machines
# file, for example the one nix-darwin or NixOS renders to /etc/nix/machines)
# is config; which of them are LIVE is measured, each time tehai runs.
#
# One run: parse the declared file; for each machine, ssh to it with a short
# timeout and ask its nix for a version; write the live machines, unchanged,
# to the output with an atomic rename, so nix never reads a half-written list;
# write a state file saying which are up, since when, and why not. A timer
# (launchd's StartInterval, a systemd timer) runs it every few seconds.
#
# A malformed line is refused alone, named in the state, and never takes its
# valid siblings down with it.

# ── the machines format ──────────────────────────────────────────────
# One machine per line, fields separated by spaces: URI, systems, SSH key,
# max jobs, speed factor, supported features, mandatory features, host key;
# "-" for an empty field. Blank lines and # comments are skipped.

def fields(line)
  filter(
    fn(f) is_empty(f) == false end,
    split(replace(trim(line), "\t", " "), " ")
  )
end

def meaningful?(line)
  t = trim(line)
  is_empty(t) == false && starts_with?(t, "#") == false
end

# A declared machine: its line as written, its URI, host and user, and its
# key, or a refusal naming the line.
def machine(line)
  fs = fields(line)
  uri = first(fs)
  if (starts_with?(uri, "ssh://") || starts_with?(uri, "ssh-ng://")) == false
    {line: line, ok: false, why: "not an ssh:// or ssh-ng:// URI: #{uri}"}
  else
    target = after_first(uri, "://")
    user = if includes(target, "@")
      before_first(target, "@")
    else
      nil
    end
    host = if includes(target, "@")
      after_first(target, "@")
    else
      target
    end
    key = if size(fs) > 2 && nth(2, fs) != "-"
      nth(2, fs)
    else
      nil
    end
    {line: trim(line), ok: true, uri: uri, host: host, user: user, key: key}
  end
end

def parse(text)
  map(fn(l) machine(l) end, filter(fn(l) meaningful?(l) end, split(text, "\n")))
end

# ── the check ────────────────────────────────────────────────────────

# The ssh command that checks one machine: non-interactive, a short connect
# timeout, a short keep-alive, and a trivial nix command on the far side, so
# "up" means nix answers, not merely that port 22 is open. `ssh` is the binary
# to run, by absolute path when the caller has one (services.tehai passes
# /usr/bin/ssh on macOS, openssh on NixOS), so the state can name which ssh ran.
def probe_argv(m, timeout_s, ssh)
  key = if get(m, :key) == nil
    []
  else
    ["-i", get(m, :key)]
  end
  dest = if get(m, :user) == nil
    get(m, :host)
  else
    "#{get(m, :user)}@#{get(m, :host)}"
  end
  concat_lists(
    [
      ssh,
      "-o",
      "BatchMode=yes",
      "-o",
      "ConnectTimeout=#{to_s(timeout_s)}",
      "-o",
      "ServerAliveInterval=#{to_s(timeout_s)}",
      "-o",
      "ServerAliveCountMax=1"
    ],
    concat_lists(key, [dest, "nix-store", "--version"])
  )
end

# [up?, detail] for one machine. A failure to start ssh at all is a down
# machine with the reason, never an uncaught error for the whole run.
def probe(m, timeout_s, ssh)
  cap = try(
    apply(exec_capture, probe_argv(m, timeout_s, ssh)),
    catch(_e(), nil)
  )
  if cap == nil
    [false, "ssh could not be started: #{ssh}"]
  elsif status_of(cap) == 0 && starts_with?(trim(stdout_of(cap)), "nix-store")
    [true, trim(stdout_of(cap))]
  else
    [false, last_nonempty_line(stderr_of(cap))]
  end
end

# ── what gets written ────────────────────────────────────────────────

# The live machines file: each live machine's declared line, unchanged.
def live_text(checked)
  join(
    map(
      fn(c) concat(get(c, :line), "\n") end,
      filter(fn(c) get(c, :up) end, checked)
    ),
    ""
  )
end

# Each machine's state, carrying `since` forward while up/down is unchanged.
def states(checked, previous, now)
  map(fn(c) state(c, previous_of(previous, get(c, :line)), now) end, checked)
end

def previous_of(previous, line)
  find_first(fn(p) get(p, :line) == line end, previous)
end

def state(c, prev, now)
  since = if prev != nil && get(prev, :up) == get(c, :up)
    get(prev, :since_ms)
  else
    now
  end
  {
    line: get(c, :line),
    host: get(c, :host),
    up: get(c, :up),
    since_ms: since,
    checked_ms: now,
    detail: get(c, :detail)
  }
end

# A previous state file's machines, or [] when there is none or it is not
# JSON: a missing history only resets `since`.
def read_previous(path)
  text = read_or(path, "")
  if is_empty(text)
    []
  else
    parsed = try(json_parse(text), catch(_e(), nil))
    if parsed == nil
      []
    else
      or_empty(as_json(parsed, "machines"))
    end
  end
end

# A parsed JSON object is a key/value list, not a map, so its fields are read
# through deeta (as_json, get_str, get_int), never `get`.
def or_empty(xs)
  if xs == nil
    []
  else
    map(
      fn(p)
        {
          line: get_str(p, "line", ""),
          up: as_json(p, "up") == true,
          since_ms: get_int(p, "since_ms", 0)
        }
      end,
      xs
    )
  end
end

# Write through a temporary beside the target, then rename: atomic on one
# filesystem, so a reader sees the old file or the new one.
def write_atomic(path, text)
  tmp = "#{path}.tehai-tmp"
  write_file(tmp, text)
  rename_file(tmp, path)
end

# ── one run ──────────────────────────────────────────────────────────

# Check every declared machine once; write the live file and the state.
# Returns the state record.
def run(declared_path, live_path, state_path, timeout_s, ssh)
  now = now_ms()
  machines = parse(read_or(declared_path, ""))
  good = filter(fn(m) get(m, :ok) end, machines)
  refused = map(
    fn(m) {line: get(m, :line), why: get(m, :why)} end,
    filter(fn(m) get(m, :ok) == false end, machines)
  )
  checked = map(fn(m) tehai::checked(m, probe(m, timeout_s, ssh)) end, good)
  states = tehai::states(checked, read_previous(state_path), now)
  mkdir_p(path_dirname(live_path))
  write_atomic(live_path, live_text(checked))
  record = {
    checked_ms: now,
    declared: declared_path,
    live: live_path,
    ssh: ssh,
    machines: states,
    refused: refused
  }
  mkdir_p(path_dirname(state_path))
  write_atomic(state_path, json_stringify(record))
  record
end

def checked(m, result)
  {
    line: get(m, :line),
    host: get(m, :host),
    up: nth(0, result),
    detail: nth(1, result)
  }
end

# The daemon's entry point: paths, timeout and the ssh binary from the
# environment. A bare "ssh" (PATH lookup) is the fallback, and the state says so.
def main()
  run(
    getenv("TEHAI_DECLARED", "/etc/nix/machines"),
    getenv("TEHAI_LIVE", "/var/run/tehai/machines"),
    getenv("TEHAI_STATE", "/var/run/tehai/state.json"),
    to_int(getenv("TEHAI_TIMEOUT_S", "2")),
    getenv("TEHAI_SSH", "ssh")
  )
end

# ── tests ────────────────────────────────────────────────────────────

def sample()
  "# declared by nix-darwin\nssh-ng://builder@quero-builder-ssm aarch64-linux /Users/x/.ssh/key 8 1 kvm,big-parallel - -\n\nssh://root@plo x86_64-linux - 8 8 - - -\nnot-a-uri x86_64-linux\n"
end

test "the machines format: comments and blanks skipped, fields read, a bad line refused alone"
  ms = parse(sample())
  assert size(ms) == 3
  q = nth(0, ms)
  assert get(q, :host) == "quero-builder-ssm"
  assert get(q, :user) == "builder"
  assert get(q, :key) == "/Users/x/.ssh/key"
  # "-" is an empty field: no key.
  assert get(nth(1, ms), :key) == nil
  assert get(nth(1, ms), :host) == "plo"
  # The control: one malformed line is refused, and its siblings are not.
  assert get(nth(2, ms), :ok) == false
  assert size(filter(fn(m) get(m, :ok) end, ms)) == 2
  # The empty case.
  assert is_empty(parse("")) == true
end

test "the check is non-interactive, short, and asks nix, not just the port"
  argv = probe_argv(first(parse(sample())), 2, "/usr/bin/ssh")
  assert first(argv) == "/usr/bin/ssh"
  assert contains(argv, "BatchMode=yes") == true
  assert contains(argv, "ConnectTimeout=2") == true
  assert take_n(reverse(argv), 3) ==
    ["--version", "nix-store", "builder@quero-builder-ssm"]
  assert contains(argv, "/Users/x/.ssh/key") == true
end

test "only live machines are written, each line exactly as declared"
  ms = filter(fn(m) get(m, :ok) end, parse(sample()))
  checked = [
    tehai::checked(nth(0, ms), [false, "Connection timed out"]),
    tehai::checked(nth(1, ms), [true, "nix-store (Nix) 2.31.5"])
  ]
  assert live_text(checked) == "ssh://root@plo x86_64-linux - 8 8 - - -\n"
  # None live: an empty file, so nix builds locally rather than timing out.
  assert live_text([tehai::checked(nth(0, ms), [false, "down"])]) == ""
end

test "since carries forward while a machine's state holds, and resets when it flips"
  ms = filter(fn(m) get(m, :ok) end, parse(sample()))
  c = checked(nth(1, ms), [true, "ok"])
  first_run = states([c], [], 1000)
  assert get(first(first_run), :since_ms) == 1000
  again = states([c], first_run, 2000)
  assert get(first(again), :since_ms) == 1000
  assert get(first(again), :checked_ms) == 2000
  flipped = states([checked(nth(1, ms), [false, "gone"])], again, 3000)
  assert get(first(flipped), :since_ms) == 3000
end

test "a run end to end, with a machine that cannot answer"
  dir = path_join(getenv("TMPDIR", "/tmp"), "tehai-test-#{to_s(now_ms())}")
  mkdir_p(dir)
  declared = path_join(dir, "machines")
  # A port nothing listens on, on this host: a fast, certain "down".
  write_file(
    declared,
    "ssh://root@127.0.0.1 x86_64-linux - 1 1 - - -\nbroken\n"
  )
  r = run(
    declared,
    path_join(dir, "live"),
    path_join(dir, "state.json"),
    1,
    "ssh"
  )
  assert read_file(path_join(dir, "live")) == ""
  assert size(get(r, :machines)) == 1
  assert get(first(get(r, :machines)), :up) == false
  assert size(get(r, :refused)) == 1
  # The state file is JSON that reads back, and the next run keeps `since`:
  # still down, so the second run's since is the first run's.
  assert size(read_previous(path_join(dir, "state.json"))) == 1
  r2 = run(
    declared,
    path_join(dir, "live"),
    path_join(dir, "state.json"),
    1,
    "ssh"
  )
  assert get(first(get(r2, :machines)), :since_ms) ==
    get(first(get(r, :machines)), :since_ms)
  rm_rf(dir)
end

test "a missing ssh binary is named, and the state records which ssh ran"
  dir = path_join(getenv("TMPDIR", "/tmp"), "tehai-ssh-test-#{to_s(now_ms())}")
  mkdir_p(dir)
  declared = path_join(dir, "machines")
  write_file(declared, "ssh://root@127.0.0.1 x86_64-linux - 1 1 - - -\n")
  r = run(
    declared,
    path_join(dir, "live"),
    path_join(dir, "state.json"),
    1,
    "/nonexistent/ssh"
  )
  m = first(get(r, :machines))
  assert get(m, :up) == false
  assert get(m, :detail) == "ssh could not be started: /nonexistent/ssh"
  assert get(r, :ssh) == "/nonexistent/ssh"
  assert contains?(
    read_file(path_join(dir, "state.json")),
    "\"ssh\":\"/nonexistent/ssh\""
  ) ==
    true
  # Control: a real ssh reaches the machine, so its failure is a different one.
  r2 = run(
    declared,
    path_join(dir, "live"),
    path_join(dir, "state.json"),
    1,
    "ssh"
  )
  assert get(first(get(r2, :machines)), :detail) !=
    "ssh could not be started: ssh"
  rm_rf(dir)
end
