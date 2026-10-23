use("deeta", [:as_json, :get_str])
use("kyohi", [:ok, :ok?, :refusal, :refusal_of, :refused, :value])
use("moji", [:drop_chars, :includes, :lines, :take_chars])
use("retsu", [:concat_lists, :first, :is_empty, :size])

use(
  "shisutemu",
  [:last_nonempty_line, :status_of, :stderr_of, :stdout_of, :strip_ansi]
)

def nix_bin()
  getenv("HYOUKA_NIX", "nix")
end

def installable(flake, attr)
  "#{flake}##{attr}"
end

def store_dir()
  "/nix/store/"
end

def store_path?(p)
  string?(p) and
    starts_with?(p, store_dir) and
    length(p) > 44 and
    take_chars(drop_chars(p, 43), 1) == "-"
end

def store_hash(p)
  if store_path?(p)
    take_chars(drop_chars(p, 11), 32)
  end
end

def store_name(p)
  if store_path?(p)
    first(split(drop_chars(p, 44), "/"))
  end
end

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

def failure_of(text)
  refusal(failure_class(text), trim(strip_ansi(last_nonempty_line(text))))
end

def capture(argv)
  exec_capture(*argv) rescue nil
end

def run_nix(args)
  argv = concat_lists([nix_bin], args)
  cap = capture(argv)
  if cap.nil?
    {status: -1, stdout: "", stderr: "could not start #{nix_bin}"}
  else
    {status: status_of(cap), stdout: stdout_of(cap), stderr: stderr_of(cap)}
  end
end

def answer(out, read)
  if get(out, :status) == 0
    parsed = begin
      read(get(out, :stdout))
    rescue e
      e
    end
    if error?(parsed)
      refused(
        refusal(
          :unreadable,
          "nix answered text that does not parse: #{take_chars(get(out, :stdout), 200)}"
        )
      )
    else
      ok(parsed)
    end
  elsif get(out, :status) == -1
    refused(refusal(:unstartable, get(out, :stderr)))
  else
    refused(failure_of(get(out, :stderr)))
  end
end

def eval_json(inst, extra)
  answer(
    run_nix(concat_lists(["eval", "--json", inst], extra)),
    (t) -> json_parse(t)
  )
end

def eval_raw(inst, extra)
  answer(run_nix(concat_lists(["eval", "--raw", inst], extra)), (t) -> t)
end

def target_of(o)
  outs = as_json(o, "outputs")
  {drv: get_str(o, "drvPath", ""), out: get_str(outs, "out", "")}
end

def targets(text)
  parsed = json_parse(text)
  if list?(parsed)
    map(target_of, parsed)
  else
    []
  end
end

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

def work_step(acc, line)
  s = section_of(line)
  if s == :build or s == :fetch
    assoc(acc, :in, s)
  elsif s == :member and get(acc, :in) != nil
    k = get(acc, :in)
    assoc(acc, k, concat_lists(get(acc, k), [trim(line)]))
  else
    assoc(acc, :in, nil)
  end
end

def work(text)
  r = reduce(work_step, {in: nil, build: [], fetch: []}, lines(text))
  {build: get(r, :build), fetch: get(r, :fetch)}
end

def plan_build(inst, extra)
  out = run_nix(
    concat_lists(["build", "--dry-run", "--json", "--no-link", inst], extra)
  )
  r = answer(out, targets)
  if ok?(r)
    w = work(get(out, :stderr))
    ok({targets: value(r), build: get(w, :build), fetch: get(w, :fetch)})
  else
    r
  end
end

def first_out(plan)
  ts = get(plan, :targets)
  if is_empty(ts)
    nil
  else
    get(first(ts), :out)
  end
end

def info_pairs(parsed)
  if list?(parsed)
    filter((p) -> list?(p) and size(p) == 2 and nth(1, p) != nil, parsed)
  else
    []
  end
end

def path_info(paths, store)
  where = if store.nil?
    []
  else
    ["--store", store]
  end
  out = run_nix(
    concat_lists(concat_lists(["path-info", "--json"], where), paths)
  )
  parsed = json_parse(get(out, :stdout)) rescue nil
  present = map((p) -> first(p), info_pairs(parsed))
  {present:, missing: filter((p) -> member?(p, present) == false, paths)}
end

def resolve(link)
  cap = capture(["readlink", "-f", link])
  if cap.nil? or status_of(cap) != 0
    nil
  else
    trim(stdout_of(cap))
  end
end

def sample_dry_run()
  "this derivation will be built:\n  /nix/store/79318l15inqy72wqdqp9hixn762vlfza-kirikae-probe.drv\nthese 2 paths will be fetched (0.01 MiB download, 0.08 MiB unpacked):\n  /nix/store/002bc1h837ifc9vsv6vcf1ah5psckn1h-capnp-grammar-0.0.0+rev=7b0883c\n  /nix/store/f97whj20l07gbd9ir1m3kd6lizx2mc1h-darwin-system-25.11.ebec37a\n"
end

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
  assert get(first(ts), :drv) ==
    "/nix/store/79318l15inqy72wqdqp9hixn762vlfza-kirikae-probe.drv"
  assert get(first(ts), :out) ==
    "/nix/store/jrbqf1qkyiiq0v3b66ngc9fbj2cj1737-kirikae-probe"
  w = work(sample_dry_run)
  assert size(get(w, :build)) == 1
  assert size(get(w, :fetch)) == 2
  assert store_name(first(get(w, :build))) == "kirikae-probe.drv"
  assert first_out({targets: ts}) ==
    "/nix/store/jrbqf1qkyiiq0v3b66ngc9fbj2cj1737-kirikae-probe"
end

test "nothing to do is empty work, not an error"
  w = work("")
  assert get(w, :build) == []
  assert get(w, :fetch) == []
  assert targets("[]") == []
  assert first_out({targets: []}).nil?
  assert work("warning: Git tree is dirty\n") == {build: [], fetch: []}
end

test "a failure is classified by what nix said, with the last line as its why"
  f = failure_of("error:\n       … while evaluating the attribute 'optionalValue.value'\n\n       error: iroha gate (kata-fleet-pleme): FAILED — 48/49 passed\n")
  assert first(f) == :eval
  assert nth(1, f) ==
    "error: iroha gate (kata-fleet-pleme): FAILED — 48/49 passed"
  assert failure_class("error: unable to download 'https://github.com/x': HTTP error 404") ==
    :credential
  assert failure_class("error: unable to download 'https://x': Couldn't resolve host name") ==
    :fetch
  assert failure_class("error: builder for '/nix/store/x.drv' failed with exit code 1") ==
    :builder
  assert failure_class("run timed out after 5400s") == :timeout
  assert failure_class("Failed assertions:\n- nope") == :assertion
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
