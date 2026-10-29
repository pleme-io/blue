@moduledoc """
tehai (手配) — which nix remote builders can take work right now: every declared machine checked, and only the live ones written where nix reads them.

nix reads its remote builders from a machines file (`builders = @<path>`).
Written by hand or by a system config, that file names machines whether
they are up or not, so a dead builder costs a TCP timeout on every
dispatch, and a builder switched off by hand ("offline") stays off after it
comes back. tehai separates the two facts: the DECLARED set (a machines
file, for example the one nix-darwin or NixOS renders to /etc/nix/machines)
is config; which of them are LIVE is measured, each time tehai runs.

One run: parse the declared file; for each machine, ssh to it with a short
timeout and ask its nix for a version; write the live machines, unchanged,
to the output with an atomic rename, so nix never reads a half-written list;
write a state file saying which are up, since when, and why not. A timer
(launchd's StartInterval, a systemd timer) runs it every few seconds.

A malformed line is refused alone, named in the state, and never takes its
valid siblings down with it.

Substituters get the same split when TEHAI_SUBSTITUTERS_DECLARED names a
file of URLs: each one's `nix-cache-info` is read with a short timeout, and
the live ones are written as an `extra-substituters` line to a fragment
nix.conf includes, so a peer cache that is down costs no lookup.

    probe(probe_target, 2, "") #=> [false, "ssh could not be started: "]
"""

use("deeta", %i[as_json get_int get_str])
use("moji", %i[after_first before_first includes trim])

use(
  "retsu",
  %i[concat_lists contains find_first first is_empty last size take_n]
)

use("shisutemu", %i[last_nonempty_line read_or status_of stderr_of stdout_of])

use("tesuto", [:fresh_dir])

legacy_names("0.1.1", "th")

# ── the machines format ──────────────────────────────────────────────
# One machine per line, fields separated by spaces: URI, systems, SSH key,
# max jobs, speed factor, supported features, mandatory features, host key;
# "-" for an empty field. Blank lines and # comments are skipped.

def fields(line)
  filter(
    (f) -> is_empty(f) == false,
    split(replace(trim(line), "\t", " "), " ")
  )
end

def meaningful?(line)
  t = trim(line)
  is_empty(t) == false and starts_with?(t, "#") == false
end

@doc """
machine: A declared machine: its line as written, its URI, host and user, its
key, the store protocol nix speaks to it and the far side's program when the
URI names one (`?remote-program=`), or a refusal naming the line.

    machine("ssh-ng://u@cid?remote-program=/x aarch64-darwin - 1 1 - - -")[:host] #=> "cid"
"""
def machine(line)
  fs = fields(line)
  uri = first(fs)
  if (starts_with?(uri, "ssh://") or starts_with?(uri, "ssh-ng://")) == false
    {line:, ok: false, why: "not an ssh:// or ssh-ng:// URI: #{uri}"}
  else
    target = before_first_or_all(after_first(uri, "://"), "?")
    user = if includes(target, "@")
      before_first(target, "@")
    end
    host = if includes(target, "@")
      after_first(target, "@")
    else
      target
    end
    key = if size(fs) > 2 and fs[2] != "-"
      fs[2]
    end
    {
      line: trim(line),
      ok: true,
      uri:,
      host:,
      user:,
      key:,
      protocol: protocol(uri),
      remote_program: query_param(uri, "remote-program")
    }
  end
end

@doc """
before_first_or_all: The text before the first `sep`, or all of it when there is none.

    before_first_or_all("cid?x=1", "?") #=> "cid"
"""
def before_first_or_all(s, sep)
  if includes(s, sep)
    before_first(s, sep)
  else
    s
  end
end

@doc """
protocol: The store protocol nix speaks to a builder, from its URI's scheme:
`:worker` for ssh-ng:// (the far side runs `nix-daemon --stdio`), `:serve`
for ssh:// (`nix-store --serve --write`).

    protocol("ssh-ng://u@h") #=> :worker
"""
def protocol(uri)
  if starts_with?(uri, "ssh-ng://")
    :worker
  else
    :serve
  end
end

@doc """
query_param: The value of `name` in a URI's query, or nil.

    query_param("ssh-ng://h?a=1&remote-program=/p", "remote-program") #=> "/p"
"""
def query_param(uri, name)
  if includes(uri, "?") == false
    nil
  else
    hit = find_first(
      (kv) -> starts_with?(kv, "#{name}="),
      split(after_first(uri, "?"), "&")
    )
    if hit.nil?
      nil
    else
      after_first(hit, "=")
    end
  end
end

@doc """
entries: Each meaningful line of a declared file, read by `read_line`.

    entries(unlines(["# c", "", "x"]), trim) #=> ["x"]
"""
def entries(text, read_line)
  map(read_line, filter(meaningful?, split(text, line_break)))
end

@doc """
parse: declared remote builders from the machines file.
"""
def parse(text)
  entries(text, machine)
end

# ── the check ────────────────────────────────────────────────────────

@doc """
remote_command: What nix runs on the far side for this builder: cppnix's
ssh-store (`nix-daemon --stdio`) or legacy-ssh-store (`nix-store --serve
--write`), with the URI's remote program in place of the default.

    remote_command(machine("ssh-ng://h x - 1 1 - - -")) #=> ["nix-daemon", "--stdio"]
"""
def remote_command(m)
  if m[:protocol] == :worker
    [m[:remote_program] or "nix-daemon", "--stdio"]
  else
    [m[:remote_program] or "nix-store", "--serve", "--write"]
  end
end

@doc """
probe_argv: The ssh command that checks one machine: non-interactive, a short
connect timeout, a short keep-alive, and on the far side the very program nix
will run for a build, so "up" means the builder's store answers the protocol
nix speaks, not merely that ssh or `nix --version` does. `ssh` is the binary
to run, by absolute path when the caller has one (services.tehai passes
/usr/bin/ssh on macOS, openssh on NixOS), so the state can name which ssh ran.
"""
def probe_argv(m, timeout_s, ssh)
  key = if m[:key].nil?
    []
  else
    ["-i", m[:key]]
  end
  dest = if m[:user].nil?
    m[:host]
  else
    "#{m[:user]}@#{m[:host]}"
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
    concat_lists(key, concat_lists([dest], remote_command(m)))
  )
end

@doc """
le_bytes: `n` as `k` little-endian bytes, the nix wire format of a u64.

    le_bytes(258, 3) #=> [2, 1, 0]
"""
def le_bytes(n, k)
  if k == 0
    []
  else
    concat_lists([n % 256], le_bytes(floor(n / 256), k - 1))
  end
end

@doc """
handshake: The client's opening magic and the reply's magic for a protocol,
as wire bytes, and the protocol's name (cppnix worker-protocol.hh,
serve-protocol.hh).

    handshake(:worker)[:name] #=> "worker"
"""
def handshake(proto)
  if proto == :worker
    {
      name: "worker",
      hello: le_bytes(1_852_405_859, 8),
      reply: le_bytes(1_685_612_911, 8)
    }
  else
    {
      name: "serve",
      hello: le_bytes(957_128_171, 8),
      reply: le_bytes(1_414_721_227, 8)
    }
  end
end

@doc """
probe: [up?, detail] for one machine. The opening magic of its store protocol
is sent, and it is up only when the far side replies with the protocol's own
magic; the detail is then the protocol version it offers. A failure to start
ssh at all is a down machine with the reason, never an uncaught error for the
whole run.

    probe(probe_target, 2, "") #=> [false, "ssh could not be started: "]
"""
def probe(m, timeout_s, ssh)
  hs = handshake(m[:protocol])
  cap = exec_exchange(
    hs[:hello],
    16,
    timeout_s * 3000,
    *probe_argv(m, timeout_s, ssh)
  ) rescue
    nil
  if cap.nil?
    [false, "ssh could not be started: #{ssh}"]
  else
    out = json_get(cap, :stdout) or []
    if size(out) >= 10 and take_n(out, 8) == hs[:reply]
      [true, "#{hs[:name]} protocol #{to_s(out[9])}.#{to_s(out[8])}"]
    else
      why = last_nonempty_line(stderr_of(cap))
      if is_empty(why)
        [false, "no #{hs[:name]} protocol handshake"]
      else
        [false, why]
      end
    end
  end
end

# ── what gets written ────────────────────────────────────────────────

@doc """
live_text: The live machines file: each live machine's declared line, unchanged.
"""
def live_text(checked)
  join(
    map((c) -> concat(c[:line], line_break), filter((c) -> c[:up], checked)),
    ""
  )
end

@doc """
states: Each machine's state, carrying `since` forward while up/down is unchanged.
"""
def states(checked, previous, now)
  map((c) -> state(c, previous_of(previous, c[:line]), now), checked)
end

def previous_of(previous, line)
  find_first((p) -> p[:line] == line, previous)
end

def state(c, prev, now)
  since = if prev != nil and prev[:up] == c[:up]
    prev[:since_ms]
  else
    now
  end
  {
    line: c[:line],
    host: c[:host],
    up: c[:up],
    since_ms: since,
    checked_ms: now,
    detail: c[:detail]
  }
end

@doc """
read_previous: A previous state file's machines, or [] when there is none or it is not
JSON: a missing history only resets `since`.
"""
def read_previous(path)
  text = read_or(path, "")
  if is_empty(text)
    []
  else
    parsed = json_parse(text) rescue nil
    if parsed.nil?
      []
    else
      or_empty(as_json(parsed, "machines"))
    end
  end
end

@doc """
or_empty: A parsed JSON object is a key/value list, not a map, so its fields are read
through deeta (as_json, get_str, get_int), never `get`.

    or_empty(nil) #=> []
"""
def or_empty(xs)
  if xs.nil?
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

@doc """
write_atomic: Write through a temporary beside the target, then rename: atomic on one
filesystem, so a reader sees the old file or the new one.
"""
def write_atomic(path, text)
  tmp = "#{path}.tehai-tmp"
  write_file(tmp, text)
  rename_file(tmp, path)
end

# ── one run ──────────────────────────────────────────────────────────

@doc """
run: Check every declared machine once; write the live file and the state.
Returns the state record.
"""
def run(declared_path, live_path, state_path, timeout_s, ssh)
  now = now_ms
  machines = parse(read_or(declared_path, ""))
  good = filter((m) -> m[:ok], machines)
  refused = map(
    (m) -> {line: m[:line], why: m[:why]},
    filter((m) -> m[:ok] == false, machines)
  )
  checked = map((m) -> tehai::checked(m, probe(m, timeout_s, ssh)), good)
  states = tehai::states(checked, read_previous(state_path), now)
  mkdir_p(path_dirname(live_path))
  write_atomic(live_path, live_text(checked))
  record = {
    checked_ms: now,
    declared: declared_path,
    live: live_path,
    ssh:,
    machines: states,
    refused:
  }
  mkdir_p(path_dirname(state_path))
  write_atomic(state_path, json_stringify(record))
  record
end

def checked(m, result)
  {line: m[:line], host: m[:host], up: result[0], detail: result[1]}
end

# ── substituters ─────────────────────────────────────────────────────
# A peer binary cache that is down costs every narinfo lookup a connect
# timeout plus retries, the same way a dead builder costs every dispatch.
# The declared list is one URL per line; the live ones are written as an
# `extra-substituters` line in a file nix.conf includes with `!include`.

@doc """
substituter: A declared substituter: its URL as written (a `?priority=` query
kept, since nix reads it), its host, and the base its `nix-cache-info` is read
under, or a refusal naming the line.

    get(substituter("http://cid:5001?priority=29"), :base) #=> "http://cid:5001"
"""
def substituter(line)
  url = trim(line)
  if (starts_with?(url, "http://") or starts_with?(url, "https://")) == false
    {line: url, ok: false, why: "not an http:// or https:// URL: #{url}"}
  else
    base = before_first(url, "?")
    host = before_first(after_first(base, "://"), "/")
    {line: url, ok: true, host:, base:}
  end
end

@doc """
parse_substituters: declared substituters, one URL per line.

    length(parse_substituters(unlines(["# peers", "http://rio:5000"]))) #=> 1
"""
def parse_substituters(text)
  entries(text, substituter)
end

@doc """
cache_info_argv: The curl command that reads one substituter's
`nix-cache-info`: silent, failing on an HTTP error, with a short connect
timeout and a whole-request bound, so "up" means the cache answers as a nix
cache, not merely that the port is open.

    last(cache_info_argv(substituter("http://rio:5000"), 2, "curl")) #=> "http://rio:5000/nix-cache-info"
"""
def cache_info_argv(s, timeout_s, curl)
  [
    curl,
    "-fsS",
    "--connect-timeout",
    to_s(timeout_s),
    "--max-time",
    to_s(timeout_s * 2),
    "#{s[:base]}/nix-cache-info"
  ]
end

@doc """
probe_substituter: [up?, detail] for one substituter. A curl that cannot start
is a down substituter with the reason, never an uncaught error for the run.

    probe_substituter(cache_target, 1, "") #=> [false, "curl could not be started: "]
"""
def probe_substituter(s, timeout_s, curl)
  cap = exec_capture(*cache_info_argv(s, timeout_s, curl)) rescue nil
  if cap.nil?
    [false, "curl could not be started: #{curl}"]
  elsif status_of(cap) == 0 and includes(stdout_of(cap), "StoreDir:")
    [true, trim(first(split(stdout_of(cap), line_break)))]
  else
    [false, last_nonempty_line(stderr_of(cap))]
  end
end

@doc """
substituters_text: The nix.conf fragment for the live substituters: one
`extra-substituters` line, or nothing when none answers.

    substituters_text([]) #=> ""
"""
def substituters_text(checked)
  live = map((c) -> c[:line], filter((c) -> c[:up], checked))
  if is_empty(live)
    ""
  else
    "extra-substituters = #{join(live, " ")}#{line_break}"
  end
end

@doc """
run_substituters: Check every declared substituter once; write the live
fragment and the state. Returns the state record.
"""
def run_substituters(declared_path, live_path, state_path, timeout_s, curl)
  now = now_ms
  declared = parse_substituters(read_or(declared_path, ""))
  good = filter((s) -> s[:ok], declared)
  refused = map(
    (s) -> {line: s[:line], why: s[:why]},
    filter((s) -> s[:ok] == false, declared)
  )
  checked = map(
    (s) -> tehai::checked(s, probe_substituter(s, timeout_s, curl)),
    good
  )
  states = tehai::states(checked, read_previous(state_path), now)
  mkdir_p(path_dirname(live_path))
  write_atomic(live_path, substituters_text(checked))
  record = {
    checked_ms: now,
    declared: declared_path,
    live: live_path,
    curl:,
    machines: states,
    refused:
  }
  mkdir_p(path_dirname(state_path))
  write_atomic(state_path, json_stringify(record))
  record
end

@doc """
main: The daemon's entry point: paths, timeout and the ssh binary from the
environment. A bare "ssh" (PATH lookup) is the fallback, and the state says so.
Substituters are checked only when TEHAI_SUBSTITUTERS_DECLARED names a file.
"""
def main()
  r = run(
    getenv("TEHAI_DECLARED", "/etc/nix/machines"),
    getenv("TEHAI_LIVE", "/var/run/tehai/machines"),
    getenv("TEHAI_STATE", "/var/run/tehai/state.json"),
    to_int(getenv("TEHAI_TIMEOUT_S", "2")),
    getenv("TEHAI_SSH", "ssh")
  )
  declared = getenv("TEHAI_SUBSTITUTERS_DECLARED", "")
  if is_empty(declared) == false
    run_substituters(
      declared,
      getenv("TEHAI_SUBSTITUTERS_LIVE", "/var/run/tehai/substituters.conf"),
      getenv("TEHAI_SUBSTITUTERS_STATE", "/var/run/tehai/substituters.json"),
      to_int(getenv("TEHAI_TIMEOUT_S", "2")),
      getenv("TEHAI_CURL", "curl")
    )
  end
  r
end

# ── tests ────────────────────────────────────────────────────────────

def sample()
  unlines(
    [
      "# declared by nix-darwin",
      "ssh-ng://builder@quero-builder-ssm aarch64-linux /Users/x/.ssh/key 8 1 kvm,big-parallel - -",
      "",
      "ssh://root@plo x86_64-linux - 8 8 - - -",
      "not-a-uri x86_64-linux"
    ]
  )
end

test "the machines format: comments and blanks skipped, fields read, a bad line refused alone"
  ms = parse(sample)
  assert size(ms) == 3
  q = ms[0]
  assert q[:host] == "quero-builder-ssm"
  assert q[:user] == "builder"
  assert q[:key] == "/Users/x/.ssh/key"
  # "-" is an empty field: no key.
  assert ms[1][:key].nil?
  assert ms[1][:host] == "plo"
  # The control: one malformed line is refused, and its siblings are not.
  assert ms[2][:ok] == false
  assert size(filter((m) -> m[:ok], ms)) == 2
  # The empty case.
  assert is_empty(parse("")) == true
end

test "the check is non-interactive, short, and opens the store protocol nix will use"
  ms = parse(sample)
  argv = probe_argv(ms[0], 2, "/usr/bin/ssh")
  assert first(argv) == "/usr/bin/ssh"
  assert contains(argv, "BatchMode=yes") == true
  assert contains(argv, "ConnectTimeout=2") == true
  assert take_n(reverse(argv), 3) ==
    %w[--stdio nix-daemon builder@quero-builder-ssm]
  assert contains(argv, "/Users/x/.ssh/key") == true
  assert take_n(reverse(probe_argv(ms[1], 2, "ssh")), 4) ==
    %w[--write --serve nix-store root@plo]
end

test "a remote-program query names the far side's program, and the host drops the query"
  m = machine("ssh-ng://u@cid?remote-program=/opt/sui/bin/nix-daemon aarch64-darwin - 8 1 - - -")
  assert m[:host] == "cid"
  assert m[:protocol] == :worker
  assert take_n(reverse(probe_argv(m, 2, "ssh")), 3) ==
    %w[--stdio /opt/sui/bin/nix-daemon u@cid]
  assert machine("ssh://h?compress=true x - 1 1 - - -")[:protocol] == :serve
  assert machine("ssh://h?compress=true x - 1 1 - - -")[:host] == "h"
end

test "only live machines are written, each line exactly as declared"
  ms = filter((m) -> m[:ok], parse(sample))
  checked = [
    tehai::checked(ms[0], [false, "Connection timed out"]),
    tehai::checked(ms[1], [true, "nix-store (Nix) 2.31.5"])
  ]
  assert live_text(checked) ==
    unlines(["ssh://root@plo x86_64-linux - 8 8 - - -"])
  # None live: an empty file, so nix builds locally rather than timing out.
  assert live_text([tehai::checked(ms[0], [false, "down"])]) == ""
end

test "since carries forward while a machine's state holds, and resets when it flips"
  ms = filter((m) -> m[:ok], parse(sample))
  c = checked(ms[1], [true, "ok"])
  first_run = states([c], [], 1000)
  assert first(first_run)[:since_ms] == 1000
  again = states([c], first_run, 2000)
  assert first(again)[:since_ms] == 1000
  assert first(again)[:checked_ms] == 2000
  flipped = states([checked(ms[1], [false, "gone"])], again, 3000)
  assert first(flipped)[:since_ms] == 3000
end

test "a run end to end, with a machine that cannot answer"
  dir = path_join(getenv("TMPDIR", "/tmp"), "tehai-test-#{to_s(now_ms)}")
  mkdir_p(dir)
  declared = path_join(dir, "machines")
  # A port nothing listens on, on this host: a fast, certain "down".
  write_file(
    declared,
    unlines(["ssh://root@127.0.0.1 x86_64-linux - 1 1 - - -", "broken"])
  )
  r = run(
    declared,
    path_join(dir, "live"),
    path_join(dir, "state.json"),
    1,
    "ssh"
  )
  assert read_file(path_join(dir, "live")) == ""
  assert size(r[:machines]) == 1
  assert first(r[:machines])[:up] == false
  assert size(r[:refused]) == 1
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
  assert first(r2[:machines])[:since_ms] == first(r[:machines])[:since_ms]
  rm_rf(dir)
end

test "a missing ssh binary is named, and the state records which ssh ran"
  dir = path_join(getenv("TMPDIR", "/tmp"), "tehai-ssh-test-#{to_s(now_ms)}")
  mkdir_p(dir)
  declared = path_join(dir, "machines")
  write_file(
    declared,
    unlines(["ssh://root@127.0.0.1 x86_64-linux - 1 1 - - -"])
  )
  r = run(
    declared,
    path_join(dir, "live"),
    path_join(dir, "state.json"),
    1,
    "/nonexistent/ssh"
  )
  m = first(r[:machines])
  assert m[:up] == false
  assert m[:detail] == "ssh could not be started: /nonexistent/ssh"
  assert r[:ssh] == "/nonexistent/ssh"
  assert contains?(
    read_file(path_join(dir, "state.json")),
    "\"ssh\":\"/nonexistent/ssh\""
  ) == true
  # Control: a real ssh reaches the machine, so its failure is a different one.
  r2 = run(
    declared,
    path_join(dir, "live"),
    path_join(dir, "state.json"),
    1,
    "ssh"
  )
  assert first(r2[:machines])[:detail] != "ssh could not be started: ssh"
  rm_rf(dir)
end

def fake_ssh(dir, name, body)
  path = path_join(dir, name)
  write_file(path, unlines(["#!/bin/sh", body]))
  exec_check("chmod", "+x", path)
  path
end

def probe_dir(label)
  fresh_dir("tehai-probe-#{label}")
end

def probe_target()
  {host: "h", user: "u", key: nil}
end

@doc """
cache_target: The substituter the probe tests read: cid's sui origin, with
the priority query nix reads.

    get(cache_target, :host) #=> "cid:5001"
"""
def cache_target()
  substituter("http://cid:5001?priority=29")
end

@doc """
fake_curl: A stand-in curl the probe tests run: a script in `dir` named
`name` whose body is `body`, made executable; its path.

    ends_with?(fake_curl(probe_dir("doc"), "curl", "exit 0"), "/curl") #=> true
"""
def fake_curl(dir, name, body)
  fake_ssh(dir, name, body)
end

test "substituters: the URL is kept as written, the probe drops the query, a bad line is refused alone"
  ss = parse_substituters(
    unlines(
      [
        "# peers",
        "http://cid:5001",
        "",
        "http://cid.buzios.pleme.internal:5001?priority=29",
        "ssh://cid"
      ]
    )
  )
  assert size(ss) == 3
  assert ss[0][:host] == "cid:5001"
  assert ss[1][:line] == "http://cid.buzios.pleme.internal:5001?priority=29"
  assert ss[1][:base] == "http://cid.buzios.pleme.internal:5001"
  assert ss[2][:ok] == false
  assert last(cache_info_argv(ss[1], 2, "/usr/bin/curl")) ==
    "http://cid.buzios.pleme.internal:5001/nix-cache-info"
  assert contains(cache_info_argv(ss[1], 2, "c"), "--connect-timeout") == true
end

test "substituters: only the live ones are written, as one extra-substituters line"
  ss = parse_substituters(unlines(%w[http://a:1 http://b:2?priority=29]))
  checked = [
    tehai::checked(ss[0], [false, "Connection timed out"]),
    tehai::checked(ss[1], [true, "StoreDir: /nix/store"])
  ]
  assert substituters_text(checked) ==
    unlines(["extra-substituters = http://b:2?priority=29"])
  # None live: an empty fragment, so nix lists no peer at all.
  assert substituters_text([tehai::checked(ss[0], [false, "down"])]) == ""
end

test "probe_substituter is up only when the far side answers as a nix cache"
  dir = probe_dir("cache")
  up = fake_curl(dir, "up", "printf 'StoreDir: /nix/store\\nPriority: 30\\n'")
  assert probe_substituter(cache_target, 1, up) ==
    [true, "StoreDir: /nix/store"]
  page = fake_curl(dir, "page", "echo '<html>'")
  assert first(probe_substituter(cache_target, 1, page)) == false
  down = fake_curl(
    dir,
    "down",
    "echo 'curl: (28) Connection timed out after 1001 milliseconds' >&2; exit 28"
  )
  assert probe_substituter(cache_target, 1, down) ==
    [false, "curl: (28) Connection timed out after 1001 milliseconds"]
  assert probe_substituter(cache_target, 1, "/nonexistent/curl") ==
    [false, "curl could not be started: /nonexistent/curl"]
  rm_rf(dir)
end

test "a substituter run end to end: a dead peer is left out and named in the state"
  dir = probe_dir("subs-run")
  declared = path_join(dir, "substituters")
  write_file(declared, unlines(%w[http://127.0.0.1:1 broken]))
  r = run_substituters(
    declared,
    path_join(dir, "substituters.conf"),
    path_join(dir, "substituters.json"),
    1,
    "curl"
  )
  assert read_file(path_join(dir, "substituters.conf")) == ""
  assert first(r[:machines])[:up] == false
  assert size(r[:refused]) == 1
  assert size(read_previous(path_join(dir, "substituters.json"))) == 1
  rm_rf(dir)
end

def worker_target()
  machine("ssh-ng://u@h aarch64-darwin - 1 1 - - -")
end

def serve_target()
  machine("ssh://u@h aarch64-darwin - 1 1 - - -")
end

def worker_reply()
  "printf 'oixd\\000\\000\\000\\000\\046\\001\\000\\000\\000\\000\\000\\000'"
end

def serve_reply()
  "printf '\\313\\356\\122\\124\\000\\000\\000\\000\\007\\002\\000\\000\\000\\000\\000\\000'"
end

test "probe is up only when the far side answers the worker handshake, and names its version"
  dir = probe_dir("worker")
  seen = path_join(dir, "stdin")
  ssh = fake_ssh(dir, "ssh", "head -c 8 > #{seen}; #{worker_reply}")
  assert probe(worker_target, 2, ssh) == [true, "worker protocol 1.38"]
  assert read_file(seen) == "cxin\u{0}\u{0}\u{0}\u{0}"
  rm_rf(dir)
end

test "probe is up only when the far side answers the serve handshake, and names its version"
  dir = probe_dir("serve")
  ssh = fake_ssh(dir, "ssh", "head -c 8 > /dev/null; #{serve_reply}")
  assert probe(serve_target, 2, ssh) == [true, "serve protocol 2.7"]
  rm_rf(dir)
end

test "a far side whose nix answers --version but not the store protocol is down"
  dir = probe_dir("version-only")
  version = fake_ssh(dir, "version", "echo 'nix-store (Nix) 2.31.5'")
  assert probe(worker_target, 2, version) ==
    [false, "no worker protocol handshake"]
  refused = fake_ssh(
    dir,
    "refused",
    "echo \"error: unexpected argument '--stdio' found\" >&2; exit 2"
  )
  assert probe(worker_target, 2, refused) ==
    [false, "error: unexpected argument '--stdio' found"]
  assert first(probe(serve_target, 2, fake_ssh(dir, "wrong", worker_reply))) ==
    false
  rm_rf(dir)
end

test "probe is down with the last non-empty line of stderr when ssh fails"
  dir = probe_dir("denied")
  ssh = fake_ssh(
    dir,
    "ssh",
    "echo 'first' >&2; echo 'Permission denied' >&2; echo >&2; exit 255"
  )
  assert probe(worker_target, 2, ssh) == [false, "Permission denied"]
  quiet = fake_ssh(dir, "quiet", "exit 0")
  assert probe(worker_target, 2, quiet) ==
    [false, "no worker protocol handshake"]
  rm_rf(dir)
end

test "probe names an ssh it could not start and never raises"
  assert probe(probe_target, 2, "/nonexistent/ssh") ==
    [false, "ssh could not be started: /nonexistent/ssh"]
  assert probe(probe_target, 2, "") == [false, "ssh could not be started: "]
end

test "probe hands ssh the argv that probe_argv builds"
  dir = probe_dir("argv")
  seen = path_join(dir, "argv")
  ssh = fake_ssh(dir, "ssh", "echo \"$*\" > #{seen}; #{worker_reply}")
  m = machine("ssh-ng://u@h aarch64-darwin /k 1 1 - - -")
  assert first(probe(m, 3, ssh)) == true
  assert contains?(read_file(seen), "ConnectTimeout=3")
  assert contains?(read_file(seen), "-i /k u@h nix-daemon --stdio")
  rm_rf(dir)
end

test "the handshake magics are cppnix's: cxin/oixd for the worker protocol, 0x390c9deb/0x5452eecb for serve"
  assert handshake(:worker)[:hello] == [99, 120, 105, 110, 0, 0, 0, 0]
  assert handshake(:worker)[:reply] == [111, 105, 120, 100, 0, 0, 0, 0]
  assert handshake(:serve)[:hello] == [235, 157, 12, 57, 0, 0, 0, 0]
  assert handshake(:serve)[:reply] == [203, 238, 82, 84, 0, 0, 0, 0]
end
