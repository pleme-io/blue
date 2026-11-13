@moduledoc """
hyouka (評価) — evaluation: Nix's command line as data.

`eval_json`, `eval_raw` and `plan_build` run nix and answer a kyohi result:
the value, or one refusal classified from what nix said. `plan_build` reads
a dry build's drv and out paths, and what nix will build and fetch, from
nix's own output. `path_info` asks any store which paths it holds, and a
store path is read by its fixed layout.

    failure_class("run timed out after 5400s") #=> :timeout
"""

use("deeta", %i[as_json get_str])
use("kyohi", %i[ok ok? refusal refusal_of refused value])
use("moji", %i[drop_chars includes lines take_chars trim])
use("retsu", %i[concat_lists first is_empty size])

use(
  "shisutemu",
  %i[last_nonempty_line status_of stderr_of stdout_of strip_ansi]
)

@doc """
nix_bin: the nix hyouka runs, HYOUKA_NIX when set, so a test or a pinned nix can stand in for the one on PATH.

    eval_args("--raw", installable(".", "a"), []) #=> ["eval", "--raw", ".#a"]
"""
def nix_bin()
  getenv("HYOUKA_NIX", "nix")
end

@doc """
installable: the flake reference nix builds or evaluates for one attribute of a flake.

    installable(".", "darwinConfigurations.ryn.system") #=> ".#darwinConfigurations.ryn.system"
"""
def installable(flake, attr)
  "#{flake}##{attr}"
end

@doc """
store_dir: the prefix every Nix store path starts with.

    store_dir #=> "/nix/store/"
"""
def store_dir()
  "/nix/store/"
end

@doc """
store_path?: the text is a Nix store path by its fixed layout: the store prefix, a 32-character hash, a dash and a name.

    store_path?("/nix/store/f97whj20l07gbd9ir1m3kd6lizx2mc1h-darwin-system-25.11.ebec37a") #=> true
    store_path?("/run/current-system") #=> false
"""
def store_path?(p)
  string?(p) and
    starts_with?(p, store_dir) and
    length(p) > 44 and
    take_chars(drop_chars(p, 43), 1) == "-"
end

@doc """
store_hash: the hash part of a store path, nil for text that is not one.

    store_hash("/nix/store/f97whj20l07gbd9ir1m3kd6lizx2mc1h-darwin-system-25.11.ebec37a") #=> "f97whj20l07gbd9ir1m3kd6lizx2mc1h"
    store_hash("") #=> nil
"""
def store_hash(p)
  if store_path?(p)
    take_chars(drop_chars(p, 11), 32)
  end
end

@doc """
store_name: the name part of a store path, without the hash or any path inside it; nil for text that is not one.

    store_name("/nix/store/f97whj20l07gbd9ir1m3kd6lizx2mc1h-darwin-system-25.11.ebec37a/sw/bin/nix") #=> "darwin-system-25.11.ebec37a"
"""
def store_name(p)
  if store_path?(p)
    first(split(drop_chars(p, 44), "/"))
  end
end

@doc """
failure_class: the kind of failure nix's message names (credential, fetch, builder, timeout, memory, assertion, eval, disk), else unknown.

    failure_class("run timed out after 5400s") #=> :timeout
    failure_class("") #=> :unknown
"""
def failure_class(text)
  if includes(text, "HTTP error 401") or
      includes(text, "HTTP error 403") or
      includes(text, "HTTP error 404") or
      includes(text, "Bad credentials")
    :credential
  elsif includes(text, "unable to download") or
      includes(text, "Could not resolve host") or
      includes(text, "Couldn't resolve host") or
      includes(text, "HTTP error")
    :fetch
  elsif includes(text, "error: builder for") or
      includes(text, "Cannot build '") or
      includes(text, "failed with exit code")
    :builder
  elsif includes(text, "timed out")
    :timeout
  elsif includes(text, "out of memory") or
      includes(text, "GC Warning: Out of Memory") or
      includes(text, "std::bad_alloc")
    :memory
  elsif includes(text, "Failed assertions:")
    :assertion
  elsif includes(text, "while evaluating") or
      includes(text, "while calling") or
      includes(text, "error: attribute") or
      includes(text, "undefined variable")
    :eval
  elsif includes(text, "No space left on device")
    :disk
  else
    :unknown
  end
end

@doc """
failure_of: the refusal for a failed nix run: its class, with the last line nix printed as the reason.

    failure_of("error: builder for '/nix/store/x.drv' failed with exit code 1") #=> [:builder, "error: builder for '/nix/store/x.drv' failed with exit code 1"]
"""
def failure_of(text)
  refusal(failure_class(text), trim(strip_ansi(last_nonempty_line(text))))
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
capture: run a command and keep what it printed and its status, nil when it cannot start, so a missing tool is an answer and not a crash.

    answer({status: -1, stdout: "", stderr: "could not start nix"}, (t) -> t) |> ok? #=> false
"""
def capture(argv)
  exec_capture(*argv) rescue nil
end

@doc """
run_nix: run nix with the arguments and answer its status, stdout and stderr; status -1 when nix cannot start.

    a = answer({status: -1, stdout: "", stderr: "could not start nix"}, (t) -> t)
    first(refusal_of(a)) #=> :unstartable
"""
def run_nix(args)
  argv = concat_lists([nix_bin], args)
  cap = capture(argv)
  if cap.nil?
    {status: -1, stdout: "", stderr: "could not start #{nix_bin}"}
  else
    {status: status_of(cap), stdout: stdout_of(cap), stderr: stderr_of(cap)}
  end
end

@doc """
answer: the kyohi result of one nix run: what `read` makes of stdout on success, else a refusal classified from what nix said.

    a = answer({status: 0, stdout: "{\"a\":1}", stderr: ""}, (t) -> json_parse(t))
    ok?(a) #=> true
    as_json(value(a), "a") #=> 1
"""
def answer(out, read)
  if out[:status] == 0
    parsed = begin
      read(out[:stdout])
    rescue e
      e
    end
    if error?(parsed)
      refused(
        refusal(
          :unreadable,
          "nix answered text that does not parse: #{take_chars(out[:stdout], 200)}"
        )
      )
    else
      ok(parsed)
    end
  elsif out[:status] == -1
    refused(refusal(:unstartable, out[:stderr]))
  else
    refused(failure_of(out[:stderr]))
  end
end

@doc """
eval_json: evaluate an installable with `nix eval --json` and answer the parsed value, or the refusal.

    eval_args("--json", "f#a", []) #=> ["eval", "--json", "f#a"]
"""
def eval_json(inst, extra)
  eval_with("--json", inst, extra, (t) -> json_parse(t))
end

@doc """
eval_raw: evaluate an installable with `nix eval --raw` and answer its text, or the refusal.

    eval_args("--raw", "f#a", %w[--impure]) #=> ["eval", "--raw", "f#a", "--impure"]
"""
def eval_raw(inst, extra)
  eval_with("--raw", inst, extra, (t) -> t)
end

@doc """
eval_args: the arguments of `nix eval` printing `inst` in the format `flag`, then `extra`.

    eval_args("--raw", "f#a", ["--impure"]) #=> ["eval", "--raw", "f#a", "--impure"]
"""
def eval_args(flag, inst, extra)
  concat_lists(["eval", flag, inst], extra)
end

@doc """
eval_with: run `nix eval` with `eval_args` and answer what `read` makes of its output.

    ok?(eval_with("--raw", "/nonexistent/hyouka#a", [], (t) -> t)) #=> false
"""
def eval_with(flag, inst, extra, read)
  answer(run_nix(eval_args(flag, inst, extra)), read)
end

@doc """
target_of: one target of a dry build's JSON: its drv path and its out path.

    target_of(json_parse("{\"drvPath\":\"/nix/store/a.drv\",\"outputs\":{\"out\":\"/nix/store/a\"}}")) #=> {drv: "/nix/store/a.drv", out: "/nix/store/a"}
"""
def target_of(o)
  outs = as_json(o, "outputs")
  {drv: get_str(o, "drvPath", ""), out: get_str(outs, "out", "")}
end

@doc """
targets: every target a dry build's JSON names; none when the text is not a list.

    size(targets(sample_targets)) #=> 1
    targets("[]") #=> []
"""
def targets(text)
  parsed = json_parse(text)
  if list?(parsed)
    map(target_of, parsed)
  else
    []
  end
end

@doc """
section_of: which part of a dry run's report a line opens or belongs to: the build list, the fetch list, a store path inside one, or other.

    section_of("these 2 paths will be fetched (0.01 MiB download):") #=> :fetch
    section_of("warning: Git tree is dirty") #=> :other
"""
def section_of(line)
  t = trim(line)
  if starts_with?(t, "this derivation will be built") or
      starts_with?(t, "these ") and includes(t, "derivations will be built")
    :build
  elsif starts_with?(t, "this path will be fetched") or
      starts_with?(t, "these ") and includes(t, "paths will be fetched")
    :fetch
  elsif store_path?(t)
    :member
  else
    :other
  end
end

@doc """
work_step: read one line of a dry run's report into the build and fetch lists gathered so far.

    work_step({in: nil, build: [], fetch: []}, "this derivation will be built:")[:in] #=> :build
"""
def work_step(acc, line)
  s = section_of(line)
  if s == :build or s == :fetch
    assoc(acc, :in, s)
  elsif s == :member and acc[:in] != nil
    k = acc[:in]
    assoc(acc, k, concat_lists(get(acc, k), [trim(line)]))
  else
    assoc(acc, :in, nil)
  end
end

@doc """
work: what a dry run will build and fetch, read from nix's report.

    size(work(sample_dry_run)[:fetch]) #=> 2
    work("") #=> {build: [], fetch: []}
"""
def work(text)
  r = reduce(work_step, {in: nil, build: [], fetch: []}, lines(text))
  {build: r[:build], fetch: r[:fetch]}
end

@doc """
plan_build: dry-run a build of an installable and answer its targets and what nix will build and fetch, or the refusal.

    w = work(sample_dry_run)
    store_name(first(w[:build])) #=> "kirikae-probe.drv"
"""
def plan_build(inst, extra)
  out = run_nix(
    concat_lists(["build", "--dry-run", "--json", "--no-link", inst], extra)
  )
  r = answer(out, targets)
  if ok?(r)
    w = work(out[:stderr])
    ok({targets: value(r), build: w[:build], fetch: w[:fetch]})
  else
    r
  end
end

@doc """
first_out: the out path of a plan's first target, nil when the plan has none.

    first_out({targets: targets(sample_targets)}) #=> "/nix/store/jrbqf1qkyiiq0v3b66ngc9fbj2cj1737-kirikae-probe"
    first_out({targets: []}) #=> nil
"""
def first_out(plan)
  ts = plan[:targets]
  if is_empty(ts)
    nil
  else
    first(ts)[:out]
  end
end

@doc """
info_pairs: the [path, info] pairs of `nix path-info --json` whose path the store holds.

    info_pairs([["/nix/store/a", {}], ["/nix/store/b", nil]]) #=> [["/nix/store/a", {}]]
    info_pairs(nil) #=> []
"""
def info_pairs(parsed)
  if list?(parsed)
    filter((p) -> list?(p) and size(p) == 2 and p[1] != nil, parsed)
  else
    []
  end
end

@doc """
path_info: which of the paths a store holds and which it lacks; the local store when `store` is nil.

    map((p) -> first(p), info_pairs([["/nix/store/a", {}], ["/nix/store/b", nil]])) #=> ["/nix/store/a"]
"""
def path_info(paths, store)
  where = if store.nil?
    []
  else
    ["--store", store]
  end
  out = run_nix(concat_lists(concat_lists(%w[path-info --json], where), paths))
  parsed = json_parse(out[:stdout]) rescue nil
  present = map((p) -> first(p), info_pairs(parsed))
  {present:, missing: filter((p) -> member?(p, present) == false, paths)}
end

@doc """
resolve: the store path a link such as /run/current-system points at, nil when it cannot be read.

    store_name("/nix/store/f97whj20l07gbd9ir1m3kd6lizx2mc1h-darwin-system-25.11.ebec37a") #=> "darwin-system-25.11.ebec37a"
"""
def resolve(link)
  cap = capture(["readlink", "-f", link])
  if cap.nil? or status_of(cap) != 0
    nil
  else
    trim(stdout_of(cap))
  end
end

@doc """
sample_dry_run: a real dry run's report, one drv to build and two paths to fetch, for tests and examples.

    size(work(sample_dry_run)[:build]) #=> 1
"""
def sample_dry_run()
  unlines(
    [
      "this derivation will be built:",
      "  /nix/store/79318l15inqy72wqdqp9hixn762vlfza-kirikae-probe.drv",
      "these 2 paths will be fetched (0.01 MiB download, 0.08 MiB unpacked):",
      "  /nix/store/002bc1h837ifc9vsv6vcf1ah5psckn1h-capnp-grammar-0.0.0+rev=7b0883c",
      "  /nix/store/f97whj20l07gbd9ir1m3kd6lizx2mc1h-darwin-system-25.11.ebec37a"
    ]
  )
end

@doc """
sample_targets: a real dry build's JSON with one target, for tests and examples.

    first(targets(sample_targets))[:drv] #=> "/nix/store/79318l15inqy72wqdqp9hixn762vlfza-kirikae-probe.drv"
"""
def sample_targets()
  "[{\"drvPath\":\"/nix/store/79318l15inqy72wqdqp9hixn762vlfza-kirikae-probe.drv\",\"outputs\":{\"out\":\"/nix/store/jrbqf1qkyiiq0v3b66ngc9fbj2cj1737-kirikae-probe\"}}]"
end

test "store paths are read by their fixed layout and nothing else is one"
  p = "/nix/store/f97whj20l07gbd9ir1m3kd6lizx2mc1h-darwin-system-25.11.ebec37a"
  assert store_path?(p) == true
  assert store_hash(p) == "f97whj20l07gbd9ir1m3kd6lizx2mc1h"
  assert store_name(p) == "darwin-system-25.11.ebec37a"
  assert store_name("#{p}/sw/bin/nix") == "darwin-system-25.11.ebec37a"
  assert store_path?("/nix/store/short-x") == false
  assert store_path?("/run/current-system") == false
  assert store_path?(nil) == false
  assert store_hash("").nil?
end

test "a dry run's targets and its work are read from nix's own output"
  ts = targets(sample_targets)
  assert size(ts) == 1
  assert first(ts)[:drv] ==
    "/nix/store/79318l15inqy72wqdqp9hixn762vlfza-kirikae-probe.drv"
  assert first(ts)[:out] ==
    "/nix/store/jrbqf1qkyiiq0v3b66ngc9fbj2cj1737-kirikae-probe"
  w = work(sample_dry_run)
  assert size(w[:build]) == 1
  assert size(w[:fetch]) == 2
  assert store_name(first(w[:build])) == "kirikae-probe.drv"
  assert first_out({targets: ts}) ==
    "/nix/store/jrbqf1qkyiiq0v3b66ngc9fbj2cj1737-kirikae-probe"
end

test "nothing to do is empty work, not an error"
  w = work("")
  assert w[:build] == []
  assert w[:fetch] == []
  assert targets("[]") == []
  assert first_out({targets: []}).nil?
  assert work(unlines(["warning: Git tree is dirty"])) == {build: [], fetch: []}
end

test "a failure is classified by what nix said, with the last line as its why"
  f = failure_of(
    unlines(
      [
        "error:",
        "       … while evaluating the attribute 'optionalValue.value'",
        "",
        "       error: iroha gate (kata-fleet-pleme): FAILED — 48/49 passed"
      ]
    )
  )
  assert first(f) == :eval
  assert f[1] == "error: iroha gate (kata-fleet-pleme): FAILED — 48/49 passed"
  assert failure_class("error: unable to download 'https://github.com/x': HTTP error 404") ==
    :credential
  assert failure_class("error: unable to download 'https://x': Couldn't resolve host name") ==
    :fetch
  assert failure_class("error: builder for '/nix/store/x.drv' failed with exit code 1") ==
    :builder
  assert failure_class("run timed out after 5400s") == :timeout
  assert failure_class(join_lines(["Failed assertions:", "- nope"])) ==
    :assertion
  assert failure_class("") == :unknown
end

test "results carry a value or a refusal, never both"
  a = answer({status: 0, stdout: "{\"a\":1}", stderr: ""}, (t) -> json_parse(t))
  assert ok?(a) == true
  assert as_json(value(a), "a") == 1
  b = answer(
    {
      status: 1,
      stdout: "",
      stderr: "error: builder for '/nix/store/y.drv' failed"
    },
    (t) -> t
  )
  assert ok?(b) == false
  assert first(refusal_of(b)) == :builder
  c = answer({status: 0, stdout: "not json", stderr: ""}, (t) -> json_parse(t))
  assert first(refusal_of(c)) == :unreadable
  d = answer({status: -1, stdout: "", stderr: "could not start nix"}, (t) -> t)
  assert first(refusal_of(d)) == :unstartable
  assert installable(".", "darwinConfigurations.ryn.system") ==
    ".#darwinConfigurations.ryn.system"
end

test "eval_args puts the format flag before the installable and the extras after"
  assert eval_args("--json", "f#a", []) == ["eval", "--json", "f#a"]
  assert eval_args("--raw", "", []) == ["eval", "--raw", ""]
  assert eval_args("--raw", "f#a", %w[--impure --offline]) ==
    ["eval", "--raw", "f#a", "--impure", "--offline"]
end

test "eval_with refuses an installable nix cannot read"
  assert not ok?(
    eval_with("--json", "/nonexistent/hyouka#a", [], (t) -> json_parse(t))
  )
  assert not ok?(eval_raw("/nonexistent/hyouka#a", []))
end
