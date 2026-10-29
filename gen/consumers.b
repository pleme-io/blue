use("hadome", %i[failures orphans parse shrunk])
use("kyohi")
use("moji", %i[after_first after_last before_first trim])
use("retsu", %i[concat_lists flat_map is_empty reject size])
use("shisutemu", %i[status_of stderr_of stdout_of])
use("tesuto", %i[level level_of settle])

def entries()
  [
    level(
      "*",
      :enforce,
      "a repository that runs blue stays green at this blue: a canonical or format rule lands on main only after every consumer is written in it"
    ),
    level(
      "nupastel",
      :audit,
      "its bidamas need blue migrate (B0012, B0013, B0015) before blue fmt can write them, and the operator runs that by hand; it is measured and never red"
    )
  ]
end

def recorded()
  unlines(
    [
      "refused: hanshi:crates/hanshi-core/rules/heartbeat.b:B0001 3",
      "refused: makoto:games/blackout.b:fmt 1",
      "refused: makoto:games/careful-curator.b:fmt 1",
      "refused: makoto:games/certainty-vs-severity-sensitivity.b:fmt 1",
      "refused: makoto:games/certainty-vs-severity.b:fmt 1",
      "refused: makoto:games/contrast-dose.b:fmt 1",
      "refused: makoto:games/denunciation-cascade.b:fmt 1",
      "refused: makoto:games/fader-regions.b:fmt 1",
      "refused: makoto:games/fading-exploiters.b:fmt 1",
      "refused: makoto:games/heterogeneous-types.b:fmt 1",
      "refused: makoto:games/inherited-records-sensitivity.b:fmt 1",
      "refused: makoto:games/inherited-records.b:fmt 1",
      "refused: makoto:games/judgment-economy.b:fmt 1",
      "refused: makoto:games/ledger-scoring-rule.b:fmt 1",
      "refused: makoto:games/lock-in.b:fmt 1",
      "refused: makoto:games/lying-profiles.b:fmt 1",
      "refused: makoto:games/malice-or-noise.b:fmt 1",
      "refused: makoto:games/messiah.b:fmt 1",
      "refused: makoto:games/mimetic-doubles.b:fmt 1",
      "refused: makoto:games/mimetic-levers.b:fmt 1",
      "refused: makoto:games/mimetic-rivalry.b:fmt 1",
      "refused: makoto:games/molog-breaking.b:fmt 1",
      "refused: makoto:games/mutual-reveal.b:fmt 1",
      "refused: makoto:games/noise-forgiveness.b:fmt 1",
      "refused: makoto:games/paid-enforcer.b:fmt 1",
      "refused: makoto:games/promise-as-cheap-talk.b:fmt 1",
      "refused: makoto:games/scapegoat.b:fmt 1",
      "refused: makoto:games/strategic-reporting.b:fmt 1",
      "refused: makoto:games/treadmill.b:fmt 1",
      "refused: makoto:games/tribes-sorting.b:fmt 1",
      "refused: makoto:games/trust-first-mover.b:fmt 1",
      "refused: makoto:games/uplift-floor.b:fmt 1",
      "refused: makoto:games/voice-vs-exit.b:fmt 1",
      "refused: makoto:games/wirehead-ess.b:fmt 1",
      "refused: makoto:tools/catalog.b:B0012 2",
      "refused: makoto:tools/claims-evidence.b:fmt 1",
      "refused: makoto:tools/claims-evidence.b:B0012 13",
      "refused: makoto:tools/claims-evidence.b:B0015 1",
      "refused: makoto:tools/claims-evidence.b:B0066 1",
      "refused: makoto:tools/collisions.b:B0012 17",
      "refused: makoto:tools/collisions.b:B0015 1",
      "refused: makoto:tools/regions.b:fmt 1",
      "refused: makoto:tools/regions.b:B0012 41",
      "refused: makoto:tools/regions.b:B0015 1",
      "refused: makoto:tools/regions.b:B0066 9",
      "refused: makoto:tools/tune-duckdb.b:B0012 10",
      "refused: makoto:tools/tune-duckdb.b:B0015 1",
      "refused: zukai:crates/zukai-confluence/tests/pages.b:B0001 31",
      "refused: zukai:crates/zukai-kata/tests/patterns.b:B0001 20"
    ]
  )
end

def producer()
  "blue"
end

def registry_path()
  path_join(getenv("GEN_ROOT", "."), "gen/consumers.json")
end

def lines_of(text)
  reject((l) -> trim(l) == "", split(text or "", line_break))
end

def blue_pin?(locked)
  map?(locked) and
    locked["type"] == "github" and
    locked["owner"] == "pleme-io" and
    locked["repo"] == "blue"
end

def direct_inputs(doc)
  root = get(doc["nodes"] or {}, doc["root"]) or {}
  inputs = root["inputs"] or {}
  filter(string?, map(retsu::last, map_entries(inputs)))
end

def flake_pins(text)
  if text.nil?
    []
  else
    doc = json_read(text)
    roots = direct_inputs(doc)
    flat_map(
      sort_keyed(retsu::first, map_entries(doc["nodes"] or {})),
      fn(entry)
        locked = entry[1]["locked"]
        if blue_pin?(locked)
          [
            {
              kind: :flake,
              node: entry[0],
              rev: locked["rev"],
              direct: member?(entry[0], roots)
            }
          ]
        else
          []
        end
      end
    )
  end
end

def flake_inputs(text)
  if text.nil?
    []
  else
    distinct(
      flat_map(
        map_entries(json_read(text)["nodes"] or {}),
        fn(entry)
          locked = entry[1]["locked"]
          if map?(locked) and locked["owner"] == "pleme-io"
            [locked["repo"]]
          else
            []
          end
        end
      )
    )
  end
end

def blue_source(line)
  prefix = "source = \"git+https://github.com/pleme-io/blue"
  l = trim(line)
  if starts_with?(l, prefix)
    rest = after_first(l, prefix)
    if starts_with?(rest, "?") or
        starts_with?(rest, "#") or
        starts_with?(rest, ".git")
      before_first(after_last(rest, "#"), "\"")
    end
  end
end

def field(block, key)
  hit = filter((l) -> starts_with?(trim(l), "#{key} = \""), lines_of(block))
  if hit != []
    before_first(after_first(retsu::first(hit), "\""), "\"")
  end
end

def crate_pin(block)
  name = field(block, "name") or ""
  source = field(block, "source") or ""
  if starts_with?(name, "blue-lang-") and starts_with?(source, "registry+")
    {kind: :crate, rev: field(block, "version")}
  end
end

def cargo_pins(text)
  revs = distinct(reject((r) -> r.nil?, map(blue_source, lines_of(text))))
  crates = distinct(
    reject((p) -> p.nil?, map(crate_pin, split(text or "", "[[package]]")))
  )
  append(map((r) -> {kind: :cargo, rev: r}, revs), crates)
end

def setup_pins(texts)
  if any?((t) -> contains?(t, "pleme-io/actions/blue-setup@"), texts)
    [{kind: :setup, rev: "main"}]
  else
    []
  end
end

def consumer(name, files, pins, inputs)
  {name:, files:, pins:, inputs:}
end

def pin_refusal(p)
  if not map?(p)
    "has a pin that is not an entry"
  elsif not member?(p[:kind], %i[flake cargo crate setup])
    "has a pin of kind #{to_s(p[:kind])}, not flake, cargo, crate or setup"
  elsif not string?(p[:rev]) or p[:rev] == ""
    "has a #{to_s(p[:kind])} pin with no rev"
  end
end

def consumer_refusal(c)
  if not map?(c)
    "is not an entry"
  elsif not string?(c[:name]) or c[:name] == ""
    "names no repository"
  elsif c[:name] == producer
    "is blue itself, which its own gates hold"
  elsif not list?(c[:files]) or is_empty(c[:files])
    "lists no .b file"
  elsif not every?((f) -> string?(f) and ends_with?(f, ".b"), c[:files])
    "lists a file that is not a .b file"
  elsif not list?(c[:pins])
    "has no pin list"
  else
    find_first_refusal(map(pin_refusal, c[:pins]))
  end
end

def find_first_refusal(rs)
  hit = reject((r) -> r.nil?, rs)
  if hit != []
    retsu::first(hit)
  end
end

def settle_consumers(cs)
  judged = map((c) -> [c, consumer_refusal(c)], cs)
  names = map((j) -> j[0][:name], filter((j) -> j[1].nil?, judged))
  twice = filter(
    (n) -> count(filter((m) -> m == n, names)) > 1,
    distinct(names)
  )
  {
    consumers: map(
      retsu::first,
      filter((j) -> j[1].nil? and not member?(j[0][:name], twice), judged)
    ),
    refused: concat_lists(
      map((j) -> {entry: j[0], why: j[1]}, filter((j) -> j[1] != nil, judged)),
      map((n) -> {entry: {name: n}, why: "is listed twice"}, twice)
    )
  }
end

def carriers(c, cs)
  map(
    (o) -> o[:name],
    filter((o) -> member?(c[:name], o[:inputs] or []) and o[:pins] != [], cs)
  )
end

def pin_text(p)
  if p[:kind] == :flake
    "flake #{p[:node]}@#{take_text(p[:rev], 7)}"
  elsif p[:kind] == :cargo
    "cargo @#{take_text(p[:rev], 7)}"
  elsif p[:kind] == :crate
    "crates.io blue-lang @#{p[:rev]}"
  else
    "blue-setup @#{p[:rev]}"
  end
end

def take_text(s, n)
  join(take(n, chars(s)), "")
end

def pins_text(c, cs)
  if c[:pins] != []
    join(map(pin_text, c[:pins]), ", ")
  elsif carriers(c, cs) != []
    "carried by #{join(carriers(c, cs), ", ")}"
  else
    "no pin: whatever blue is on PATH"
  end
end

def to_row(c)
  {
    "name" => c[:name],
    "files" => c[:files],
    "inputs" => c[:inputs],
    "pins" => map(
      fn(p)
        {
          "kind" => to_s(p[:kind]),
          "node" => p[:node],
          "rev" => p[:rev],
          "direct" => p[:direct]
        }
      end,
      c[:pins]
    )
  }
end

def kind_of(text)
  if text == "flake"
    :flake
  elsif text == "cargo"
    :cargo
  elsif text == "setup"
    :setup
  elsif text == "crate"
    :crate
  else
    text
  end
end

def from_row(r)
  consumer(
    r["name"],
    r["files"],
    map(
      fn(p)
        {
          kind: kind_of(p["kind"]),
          node: p["node"],
          rev: p["rev"],
          direct: p["direct"]
        }
      end,
      r["pins"] or []
    ),
    r["inputs"] or []
  )
end

def read_registry(text)
  doc = json_read(text)
  {consumers: map(from_row, doc["consumers"] or []), swept: doc["swept"] or {}}
end

def render_registry(cs, swept)
  json_stringify(
    {
      "consumers" => map(to_row, sort_keyed((c) -> c[:name], cs)),
      "swept" => swept
    }
  )
end

def codes_of(listing)
  distinct(
    filter(
      (w) -> starts_with?(w, "B") and count(chars(w)) == 5,
      map((l) -> retsu::first(split(trim(l), " ")), lines_of(listing))
    )
  )
end

def unswept(codes, swept)
  reject((c) -> member?(c, swept["codes"] or []), codes)
end

def error_codes(check_out)
  diags = map(
    json_read,
    filter((l) -> starts_with?(l, "{"), lines_of(check_out))
  )
  map(
    (d) -> d["code"],
    filter((d) -> d["severity"] == "error" and d["waiver"].nil?, diags)
  )
end

def measure(name, file, fmt_status, check_out)
  codes = error_codes(check_out)
  fmt = if fmt_status != 0
    [{key: "#{name}:#{file}:fmt", size: 1}]
  else
    []
  end
  concat_lists(
    fmt,
    map(
      fn(c)
        {key: "#{name}:#{file}:#{c}", size: count(filter((x) -> x == c, codes))}
      end,
      sort_keyed((c) -> c, distinct(codes))
    )
  )
end

def verdict(level, rows, measurements, reached)
  if level == :off
    {state: :off, failures: []}
  elsif not reached
    {state: :blind, failures: []}
  else
    fs = failures(rows, "refused", measurements)
    if fs == []
      {state: :green, failures: []}
    elsif level == :audit
      {state: :audit, failures: fs}
    else
      {state: :red, failures: fs}
    end
  end
end

def judge_all(settled, rows, measured)
  verdicts = map(
    fn(m)
      {
        name: m[:name],
        **verdict(
          level_of(settled, m[:name]),
          rows,
          m[:measurements],
          m[:reached]
        )
      }
    end,
    measured
  )
  live = flat_map(measured, (m) -> map((x) -> x[:key], m[:measurements]))
  {
    verdicts:,
    red: filter((v) -> v[:state] == :red, verdicts),
    shrunk: shrunk(
      rows,
      "refused",
      flat_map(measured, (m) -> m[:measurements])
    ),
    orphans: if every?((m) -> m[:reached], measured)
      orphans(rows, "refused", live)
    else
      []
    end
  }
end

def symbol(state)
  get({green: "✅", red: "❌", audit: "⚠️", off: "➖", blind: "➖"}, state)
end

def report_lines(judged, cs, refused)
  append(
    map(
      fn(v)
        c = find_first_named(v[:name], cs)
        pins = if c.nil?
          ""
        else
          " (#{pins_text(c, cs)})"
        end
        head = "#{symbol(v[:state])} #{v[:name]}#{pins}: #{to_s(v[:state])}"
        join_lines(
          concat_lists([head], map((f) -> "    #{kyohi::why(f)}", v[:failures]))
        )
      end,
      judged[:verdicts]
    ),
    map(
      (r) -> "⚠️ registry entry #{to_s(r[:entry][:name])} #{r[:why]}",
      refused
    ),
    map(
      fn(m)
        "⚠️ #{m[:key]} measures #{to_s(m[:size])}, below its record: tighten recorded"
      end,
      judged[:shrunk]
    ),
    map(
      (k) -> "⚠️ #{k} is recorded and no longer measured: drop its row",
      judged[:orphans]
    )
  )
end

def find_first_named(n, cs)
  hit = filter((c) -> c[:name] == n, cs)
  if hit != []
    retsu::first(hit)
  end
end

def git_in(dir, args)
  exec_capture("git", "-C", dir, *args)
end

def ref_of(dir)
  if status_of(git_in(dir, %w[rev-parse -q --verify origin/HEAD])) == 0
    "origin/HEAD"
  elsif status_of(git_in(dir, %w[rev-parse -q --verify origin/main])) == 0
    "origin/main"
  else
    "HEAD"
  end
end

def show(dir, ref, path)
  cap = git_in(dir, ["show", "#{ref}:#{path}"])
  if status_of(cap) == 0
    stdout_of(cap)
  end
end

def tracked(dir, ref)
  lines_of(stdout_of(git_in(dir, ["ls-tree", "-r", "--name-only", ref])))
end

def probe(dir)
  ref = ref_of(dir)
  all = tracked(dir, ref)
  files = filter((f) -> ends_with?(f, ".b"), all)
  if files == []
    nil
  else
    workflows = filter(
      (f) -> ends_with?(f, ".yml") or ends_with?(f, ".yaml"),
      all
    )
    lock = show(dir, ref, "flake.lock")
    consumer(
      path_basename(dir),
      files,
      append(
        flake_pins(lock),
        cargo_pins(show(dir, ref, "Cargo.lock")),
        setup_pins(map((f) -> show(dir, ref, f) or "", workflows))
      ),
      flake_inputs(lock)
    )
  end
end

def derive(root)
  dirs = filter(
    (d) -> is_dir?(path_join(d, ".git")) and path_basename(d) != producer,
    ls(root)
  )
  reject((c) -> c.nil?, map(probe, dirs))
end

def workspace()
  getenv(
    "BLUE_CONSUMERS_ROOT",
    path_join(getenv("HOME", "/"), "code/github/pleme-io")
  )
end

def scratch(name)
  path_join(getenv("TMPDIR", "/tmp"), "blue-consumers", name)
end

def reach(root, name, clone)
  dir = path_join(root, name)
  if clone and not path_exists(dir)
    mkdir_p(root)
    exec_ok?(
      "git",
      "clone",
      "-q",
      "--depth",
      "1",
      "https://github.com/pleme-io/#{name}.git",
      dir
    )
  elsif path_exists(path_join(dir, ".git"))
    status_of(git_in(dir, %w[fetch -q origin])) == 0
  else
    false
  end
end

def extract(root, name)
  dir = path_join(root, name)
  ref = ref_of(dir)
  all = tracked(dir, ref)
  wanted = filter(
    fn(f)
      ends_with?(f, ".b") or
        path_basename(f) == "Bluefile" or
        path_basename(f) == "Bluefile.lock"
    end,
    all
  )
  out = scratch(name)
  rm_rf(out)
  mkdir_p(out)
  tar = "#{out}.tar"
  archived = exec_capture(
    "git",
    "-C",
    dir,
    "archive",
    "-o",
    tar,
    ref,
    "--",
    *wanted
  )
  if status_of(archived) == 0 and exec_ok?("tar", "-xf", tar, "-C", out)
    rm(tar)
    {dir: out, files: filter((f) -> ends_with?(f, ".b"), wanted)}
  end
end

def measure_one(blue, root, name, level, clone)
  if level == :off
    {name:, reached: true, measurements: []}
  elsif not reach(root, name, clone)
    {name:, reached: false, measurements: []}
  else
    got = extract(root, name)
    if got.nil?
      {name:, reached: false, measurements: []}
    else
      ms = flat_map(
        got[:files],
        fn(f)
          path = path_join(got[:dir], f)
          measure(
            name,
            f,
            status_of(exec_capture(blue, "fmt", "--check", path)),
            stdout_of(exec_capture(blue, "check", "--format", "json", path))
          )
        end
      )
      rm_rf(got[:dir])
      {name:, reached: true, measurements: ms}
    end
  end
end

def sweep(blue, root, clone, record)
  reg = read_registry(read_file(registry_path))
  regs = settle_consumers(reg[:consumers])
  pol = settle(entries, nil)
  measured = map(
    (c) -> measure_one(blue, root, c[:name], level_of(pol, c[:name]), clone),
    regs[:consumers]
  )
  judged = judge_all(pol, parse(recorded), measured)
  drift = if clone
    []
  else
    registry_drift(reg[:consumers], derive(root))
  end
  write_stderr(
    unlines(
      concat_lists(
        report_lines(
          judged,
          regs[:consumers],
          concat_lists(regs[:refused], pol[:refused])
        ),
        map((d) -> "❌ #{d}", drift)
      )
    )
  )
  green = judged[:red] == [] and drift == [] and pol[:refused] == []
  if green and record
    codes = codes_of(stdout_of(exec_capture(blue, "explain", "--list")))
    write_file(
      registry_path,
      render_registry(
        reg[:consumers],
        {"blue" => blue_rev, "codes" => sort_keyed((c) -> c, codes)}
      )
    )
    write_stderr(unlines(["🟢 consumers: green; swept codes recorded"]))
  elsif green
    write_stderr(unlines(["🟢 consumers: green at this blue"]))
  else
    write_stderr(
      unlines(
        [
          "🔴 consumers: #{to_s(size(judged[:red]) + size(drift))} red at this blue. Write them with blue gen/consumers.b fix REPO, or hold one with level(REPO, :audit, why) in entries"
        ]
      )
    )
    exit_with(1)
  end
end

def blue_rev()
  trim(stdout_of(exec_capture("git", "rev-parse", "HEAD")))
end

def registry_drift(registered, derived)
  have = map((c) -> c[:name], registered)
  live = map((c) -> c[:name], derived)
  concat_lists(
    map(
      fn(n)
        "#{n} has .b files and is not in gen/consumers.json: run blue gen/consumers.b derive"
      end,
      reject((n) -> member?(n, have), live)
    ),
    map(
      fn(n)
        "#{n} is in gen/consumers.json and has no .b file: run blue gen/consumers.b derive"
      end,
      reject((n) -> member?(n, live), have)
    )
  )
end

def write_registry(root)
  old = if is_file?(registry_path)
    read_registry(read_file(registry_path))[:swept]
  else
    {}
  end
  cs = derive(root)
  write_file(registry_path, render_registry(cs, old))
  write_stderr(
    unlines(
      map(
        (c) -> "#{c[:name]}: #{to_s(size(c[:files]))} .b, #{pins_text(c, cs)}",
        cs
      )
    )
  )
end

def erased(blue, path)
  stdout_of(exec_capture(blue, "erase", path))
end

def rewrite(blue, path)
  before = erased(blue, path)
  written = exec_capture(blue, "fmt", "--write", path)
  after = erased(blue, path)
  {
    path:,
    written: status_of(written) == 0,
    same: before == after and before != ""
  }
end

def fix(blue, root, name)
  pol = settle(entries, nil)
  lv = level_of(pol, name)
  if lv != :enforce
    write_stderr(
      unlines(["fix: #{name} is held at #{to_s(lv)}; its entry says why"])
    )
    exit_with(2)
  end
  dir = path_join(root, name)
  git_in(dir, %w[fetch -q origin])
  ref = ref_of(dir)
  wt = scratch("fix-#{name}")
  rm_rf(wt)
  git_in(dir, %w[worktree prune])
  added = git_in(dir, ["worktree", "add", "-q", "--detach", wt, ref])
  if status_of(added) != 0
    write_stderr(stderr_of(added))
    exit_with(1)
  end
  red = filter(
    fn(f)
      status_of(exec_capture(blue, "fmt", "--check", path_join(wt, f))) != 0
    end,
    filter((f) -> ends_with?(f, ".b"), tracked(wt, "HEAD"))
  )
  done = map((f) -> rewrite(blue, path_join(wt, f)), red)
  bad = filter((r) -> not (r[:written] and r[:same]), done)
  if bad != []
    write_stderr(
      unlines(
        concat_lists(
          [
            "❌ fix: blue erase differs or fmt refused; nothing committed in #{wt}:"
          ],
          map((r) -> "    #{r[:path]}", bad)
        )
      )
    )
    exit_with(1)
  elsif done == []
    write_stderr(unlines(["✅ fix: #{name} is already written at this blue"]))
  else
    git_in(wt, %w[add -A])
    msg = "blue fmt --write at blue #{take_text(blue_rev, 7)}: #{to_s(size(done))} files rewritten; blue erase byte-identical before and after each"
    committed = git_in(wt, ["commit", "-q", "-m", msg])
    if status_of(committed) != 0
      write_stderr(stderr_of(committed))
      exit_with(1)
    end
    write_stderr(
      unlines(
        [
          "✅ fix: #{to_s(size(done))} files in #{wt}, erase byte-identical; move the pin to this blue, run the repository's tests, then push HEAD:main as a fast-forward"
        ]
      )
    )
  end
end

def usage()
  write_stderr(
    unlines(
      [
        "blue gen/consumers.b derive | sweep [--clone DIR] [--record] | fix REPO",
        "  derive  rewrite gen/consumers.json from the workspace (BLUE_CONSUMERS_ROOT)",
        "  sweep   every consumer's .b files through this blue's fmt --check and check",
        "  fix     blue fmt --write one consumer in a worktree, proved by blue erase"
      ]
    )
  )
  exit_with(64)
end

def main()
  verb = argv_get(0, "")
  args = drop(1, argv)
  blue = self_exe
  if verb == "derive"
    write_registry(argv_get(1, workspace))
  elsif verb == "sweep"
    clone = member?("--clone", args)
    root = if clone
      args[position("--clone", args) + 1]
    else
      workspace
    end
    sweep(blue, root, clone, member?("--record", args))
  elsif verb == "fix" and size(args) == 1
    fix(blue, workspace, args[0])
  else
    usage
  end
end

def lock_fixture()
  json_stringify(
    {
      "root" => "root",
      "nodes" => {
        "root" => {"inputs" => {"blue" => "blue", "substrate" => "substrate"}},
        "blue" => {
          "locked" => {
            "type" => "github",
            "owner" => "pleme-io",
            "repo" => "blue",
            "rev" => "ea7b0251"
          }
        },
        "blue_2" => {
          "locked" => {
            "type" => "github",
            "owner" => "pleme-io",
            "repo" => "blue",
            "rev" => "60e090b1"
          }
        },
        "substrate" => {
          "locked" => {
            "type" => "github",
            "owner" => "pleme-io",
            "repo" => "substrate",
            "rev" => "038b0e5"
          }
        },
        "bluez" => {
          "locked" => {
            "type" => "github",
            "owner" => "pleme-io",
            "repo" => "blue-lsp",
            "rev" => "x"
          }
        }
      }
    }
  )
end

test "a flake.lock's blue nodes are its pins, and the root's own input is the direct one"
  pins = flake_pins(lock_fixture)
  assert map((p) -> p[:node], pins) == %w[blue blue_2]
  assert map((p) -> p[:direct], pins) == [true, false]
  assert flake_pins(nil) == []
  assert flake_inputs(lock_fixture) == %w[blue substrate blue-lsp] or
    sort_keyed((x) -> x, flake_inputs(lock_fixture)) ==
      %w[blue blue-lsp substrate]
end

test "a Cargo.lock pins blue by its git source, and a sibling repository named blue-something is not blue"
  text = unlines(
    [
      "[[package]]",
      "name = \"blue-lang-runtime\"",
      "source = \"git+https://github.com/pleme-io/blue?rev=04c7012#04c70120\"",
      "[[package]]",
      "name = \"blue-lang-pkg\"",
      "source = \"git+https://github.com/pleme-io/blue?rev=04c7012#04c70120\"",
      "[[package]]",
      "name = \"other\"",
      "source = \"git+https://github.com/pleme-io/blue-lsp#ffff\"",
      "[[package]]",
      "name = \"blue-lang-host\"",
      "version = \"0.0.120\"",
      "source = \"registry+https://github.com/rust-lang/crates.io-index\"",
      "[[package]]",
      "name = \"serde\"",
      "version = \"1.0.0\"",
      "source = \"registry+https://github.com/rust-lang/crates.io-index\""
    ]
  )
  assert cargo_pins(text) ==
    [{kind: :cargo, rev: "04c70120"}, {kind: :crate, rev: "0.0.120"}]
  assert cargo_pins(nil) == []
end

test "a workflow that installs blue with blue-setup tracks blue main"
  assert setup_pins(["uses: pleme-io/actions/blue-setup@main"]) ==
    [{kind: :setup, rev: "main"}]
  assert setup_pins(["uses: actions/checkout@v4"]) == []
end

test "each registry entry is judged alone: a bad one is refused and named, its siblings stand"
  good = consumer(
    "arnes",
    ["gen/a.b"],
    [{kind: :flake, node: "blue", rev: "626946a"}],
    []
  )
  s = settle_consumers(
    [
      good,
      consumer("flows", [], [], []),
      consumer("tend", ["x.b"], [{kind: :nix, rev: "a"}], []),
      consumer("blue", ["x.b"], [], []),
      consumer("zukai", ["x.b"], [], []),
      consumer("zukai", ["y.b"], [], [])
    ]
  )
  assert map((c) -> c[:name], s[:consumers]) == ["arnes"]
  assert map((r) -> r[:why], s[:refused]) ==
    [
      "lists no .b file",
      "has a pin of kind nix, not flake, cargo, crate or setup",
      "is blue itself, which its own gates hold",
      "is listed twice"
    ]
end

test "a repository with no pin of its own is carried by the consumer whose flake locks it"
  nix = consumer(
    "nix",
    ["a.b"],
    [{kind: :flake, node: "blue", rev: "ea7b025", direct: true}],
    ["blackmatter-kubernetes"]
  )
  bk = consumer("blackmatter-kubernetes", ["nerai.b"], [], [])
  assert pins_text(bk, [nix, bk]) == "carried by nix"
  assert pins_text(consumer("flows", ["c.b"], [], []), [nix]) ==
    "no pin: whatever blue is on PATH"
end

test "the registry round-trips through its JSON rendering"
  cs = [
    consumer("tend", ["blue/align.b"], [{kind: :cargo, rev: "abc"}], []),
    consumer("actions", ["run.b"], [{kind: :setup, rev: "main"}], [])
  ]
  back = read_registry(render_registry(cs, {"codes" => ["B0001"]}))
  assert map((c) -> c[:name], back[:consumers]) == %w[actions tend]
  assert back[:consumers][1][:pins][0][:kind] == :cargo
  assert back[:swept]["codes"] == ["B0001"]
end

test "a file's measurement is its fmt drift and each error code by count; warnings and waived errors do not count"
  out = unlines(
    [
      "{\"code\":\"B0066\",\"severity\":\"error\"}",
      "{\"code\":\"B0066\",\"severity\":\"error\"}",
      "{\"code\":\"B0002\",\"severity\":\"warning\"}",
      "{\"code\":\"B0013\",\"severity\":\"error\",\"waiver\":{\"reason\":\"kept\"}}",
      "typed declarations: 0"
    ]
  )
  assert measure("actions", "run.b", 1, out) ==
    [{key: "actions:run.b:fmt", size: 1}, {key: "actions:run.b:B0066", size: 2}]
  assert measure("actions", "run.b", 0, "") == []
end

test "a new refusal in an enforced consumer is red, recorded debt holds, audit lists it without red, off measures nothing"
  rows = parse(unlines(["refused: hanshi:h.b:B0001 3"]))
  pol = settle(
    [
      level("*", :enforce, "all"),
      level("nupastel", :audit, "migrate first"),
      level("gone", :off, "archived")
    ],
    nil
  )
  r = judge_all(
    pol,
    rows,
    [
      {
        name: "actions",
        reached: true,
        measurements: [{key: "actions:run.b:B0066", size: 6}]
      },
      {
        name: "hanshi",
        reached: true,
        measurements: [{key: "hanshi:h.b:B0001", size: 3}]
      },
      {
        name: "nupastel",
        reached: true,
        measurements: [{key: "nupastel:a.b:B0012", size: 1}]
      },
      {name: "gone", reached: true, measurements: []},
      {name: "kensa", reached: false, measurements: []}
    ]
  )
  assert map((v) -> v[:state], r[:verdicts]) == %i[red green audit off blind]
  assert map((v) -> v[:name], r[:red]) == ["actions"]
  assert r[:orphans] == []
end

test "the report gives each consumer one symbol line and each failure its reason beneath"
  cs = [consumer("actions", ["run.b"], [{kind: :setup, rev: "main"}], [])]
  r = judge_all(
    settle([level("*", :enforce, "all")], nil),
    [],
    [
      {
        name: "actions",
        reached: true,
        measurements: [{key: "actions:run.b:B0066", size: 6}]
      }
    ]
  )
  lines = split(join(report_lines(r, cs, []), line_break), line_break)
  assert lines[0] == "❌ actions (blue-setup @main): red"
  assert lines[1] ==
    "    refused: actions:run.b:B0066 measures 6 and the baseline has no row for it"
end

test "debt that shrank is named for tightening, and a recorded row nothing measures is an orphan"
  rows = parse(
    unlines(["refused: hanshi:h.b:B0001 3", "refused: tend:t.b:fmt 1"])
  )
  r = judge_all(
    settle([level("*", :enforce, "all")], nil),
    rows,
    [
      {
        name: "hanshi",
        reached: true,
        measurements: [{key: "hanshi:h.b:B0001", size: 1}]
      }
    ]
  )
  assert r[:red] == []
  assert map((m) -> m[:key], r[:shrunk]) == ["hanshi:h.b:B0001"]
  assert r[:orphans] == ["tend:t.b:fmt"]
end

def old_spelling(path)
  write_file(path, unlines(["m = {k: 1}", "get(m, :k)"]))
end

test "a consumer whose files are written at this blue and one that is not differ only by a fmt write"
  dir = scratch("probe-#{to_s(now_ns)}")
  mkdir_p(dir)
  path = path_join(dir, "old.b")
  old_spelling(path)
  assert status_of(exec_capture(self_exe, "fmt", "--check", path)) != 0
  r = rewrite(self_exe, path)
  assert r[:written] and r[:same]
  assert status_of(exec_capture(self_exe, "fmt", "--check", path)) == 0
  rm_rf(dir)
end

test "every check code this blue knows was swept clean across the registry"
  reg = read_registry(read_file(registry_path))
  codes = codes_of(stdout_of(exec_capture(self_exe, "explain", "--list")))
  assert size(codes) > 60
  missing = unswept(codes, reg[:swept])
  if missing != []
    write_stderr(
      unlines(
        [
          "unswept: #{join(missing, ", ")}. Run blue gen/consumers.b sweep --record once every consumer is green at this blue"
        ]
      )
    )
  end
  assert missing == []
end

test "the committed registry settles with no refused entry"
  reg = read_registry(read_file(registry_path))
  s = settle_consumers(reg[:consumers])
  assert s[:refused] == []
  assert size(s[:consumers]) >= 10
end

def every?(f, xs)
  not any?((x) -> not f(x), xs)
end
