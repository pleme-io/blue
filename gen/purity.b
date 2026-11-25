use("hadome", %i[blind failures measurement parse row])
use("hikisuu", [:flag])
use("hon", [:generated_outputs])
use("junjo", [:sort_by])
use("kyohi", %i[kinds ok ok? refusal refusal_of refused value why])
use("moji", [:includes])
use("retsu", %i[is_empty size])
use("shisutemu", [:read_or])

KIND = "purity-bytes"

BASELINE = "gen/purity.baseline"

LOCK = "Bluefile.lock"

@doc """
root: the tree the ledger reads: $GEN_ROOT, where a nix check places its inputs, or the working directory.

    string?(root) #=> true
"""
def root()
  getenv("GEN_ROOT", ".")
end

RECORD = "blue gen/purity.b record [--receipt \"<kind>: <why>\"]"

@doc """
crate_of: the crate a Rust source path belongs to, or nil for a path outside crates/*/src.

    crate_of("crates/blue-lang-fmt/src/lib.rs") #=> "blue-lang-fmt"
    crate_of("crates/blue-lang-fmt/tests/laws.rs") #=> nil
    crate_of("bidamas/kazu/kazu.b") #=> nil
"""
def crate_of(path)
  if starts_with?(path, "crates/") and
      includes(path, "/src/") and
      ends_with?(path, ".rs")
    moji::before_first(replace(path, "crates/", ""), "/src/")
  end
end

@doc """
generated: the crate sources a `generate` row of the tree's Bluefile.lock writes, as a kyohi result. Each is a rendering of blue that its checks.generated-<name>-fresh holds to its program, so the ledger leaves it out. A tree with no readable lock is refused as blind: the ledger cannot then tell generated Rust from hand-written.

    kinds([refusal_of(generated("no/such/root"))]) #=> [:blind]
"""
def generated(root)
  text = read_or(path_join(root, LOCK), "")
  lock = if text == ""
    nil
  else
    json_read(text) rescue nil
  end
  if lock.nil?
    refused(
      refusal(
        :blind,
        "#{LOCK} is absent or unreadable, so generated Rust cannot be told from hand-written"
      )
    )
  else
    ok(
      filter(
        (p) -> crate_of(p) != nil,
        generated_outputs({manifest: lock["manifest"] or {}})
      )
    )
  end
end

@doc """
rust_files: every hand-written Rust source path under crates, sorted: a path in `made`, the generated ones, is left out.

    is_empty(rust_files("no/such/root", [])) #=> true
"""
def rust_files(root, made)
  if path_exists(path_join(root, "crates"))
    sort_by(
      (p) -> p,
      filter(
        (p) -> crate_of(p) != nil and not member?(p, made),
        map(
          (p) -> replace(p, "#{root}/crates/", "crates/"),
          walk_dir(path_join(root, "crates"))
        )
      )
    )
  else
    []
  end
end

@doc """
totals: the Rust source bytes of each crate, as measurements keyed crates/NAME.

    totals([], []) #=> []
"""
def totals(paths, sizes)
  names = distinct(sort_by((n) -> n, map(crate_of, paths)))
  map(
    fn(n)
      measurement(
        "crates/#{n}",
        reduce(
          fn(acc, i)
            if crate_of(paths[i]) == n
              acc + sizes[i]
            else
              acc
            end
          end,
          0,
          range(0, size(paths))
        )
      )
    end,
    names
  )
end

@doc """
measured: the ledger's rows for a tree: each crate's hand-written Rust bytes, or one blind row when the tree's lock cannot say which Rust is generated.

    measured("no/such/root")[0][:key] #=> "Bluefile.lock"
"""
def measured(root)
  made = generated(root)
  if ok?(made)
    paths = rust_files(root, value(made))
    map(
      (m) -> row(KIND, m[:key], m[:size]),
      totals(paths, map((p) -> file_size(path_join(root, p)), paths))
    )
  else
    [blind(KIND, LOCK, why(refusal_of(made)))]
  end
end

@doc """
advice: what the gate says under its failures: a blind ledger names the lock it
could not read, since a record refuses a blind measure; a crate that grew or is
new names the record.

    advice([]) #=> []
    count(advice([refusal(:grew, "crates/a grew"), refusal(:blind, "no lock")])) #=> 2
"""
def advice(found)
  ks = kinds(found)
  blind = if member?(:blind, ks)
    [
      "the ledger is blind: write #{LOCK} with blue lock ., and name it in the purity-ledger check's inputs; a record refuses a blind measure"
    ]
  else
    []
  end
  grew = if any?((k) -> k != :blind, ks)
    ["a crate that grew or is new is recorded with its reason: #{RECORD}"]
  else
    []
  end
  append(blind, grew)
end

def record(receipt)
  got = hadome::record(path_join(root, BASELINE), measured(root), {receipt:})
  if ok?(got)
    write_stdout(
      unlines(["recorded #{to_s(value(got))} crate(s) in #{BASELINE}"])
    )
  else
    write_stderr(unlines([why(refusal_of(got)), "usage: #{RECORD}"]))
    exit_with(1)
  end
end

def main()
  if argv_get(0) == "record"
    record(flag(argv, "--receipt"))
  else
    write_stderr(unlines(["usage: #{RECORD}"]))
    exit_with(64)
  end
end

test "no crate grows past its recorded hand-written Rust bytes, and a new crate must be recorded"
  rows = parse(read_or(path_join(root, BASELINE), ""))
  ms = measured(root)
  found = failures(rows, KIND, ms)
  bad = map((f) -> f[1], found)
  if not is_empty(bad)
    write_stderr(unlines(append(bad, advice(found))))
  end
  assert is_empty(bad)
  assert size(ms) >= 20
end

test "a crate whose source grew is refused, one that shrank or held is not"
  rows = parse(unlines(["purity-bytes: crates/a 100"]))
  assert is_empty(failures(rows, KIND, [measurement("crates/a", 100)]))
  assert is_empty(failures(rows, KIND, [measurement("crates/a", 40)]))
  assert size(failures(rows, KIND, [measurement("crates/a", 101)])) == 1
  assert size(failures(rows, KIND, [measurement("crates/b", 1)])) == 1
end

test "totals sums each crate's files under its own key"
  ps = %w[crates/a/src/x.rs crates/a/src/y.rs crates/b/src/z.rs]
  assert totals(ps, [10, 5, 7]) ==
    [measurement("crates/a", 15), measurement("crates/b", 7)]
end

test "only a crate's src files count"
  assert crate_of("crates/k/src/m/n.rs") == "k"
  assert crate_of("crates/k/build.rs").nil?
  assert crate_of("crates/k/src/data.json").nil?
end

test "a growth is reported as its message"
  rows = parse(unlines(["purity-bytes: crates/a 100"]))
  bad = map((f) -> f[1], failures(rows, KIND, [measurement("crates/a", 101)]))
  assert bad ==
    ["purity-bytes: crates/a measures 101, past its recorded 100 by 1"]
end

def lock_text(outputs)
  json_stringify(
    {
      manifest: {
        generated: reduce(
          (acc, o) -> assoc(acc, o, {output: o, program: "gen/t.b"}),
          {},
          outputs
        )
      }
    }
  )
end

def tree_at(name, files, outputs)
  away = path_join(temp_dir("purity"), name)
  map(
    fn(f)
      mkdir_p(path_join(away, path_dirname(f[0])))
      write_file(path_join(away, f[0]), f[1])
    end,
    files
  )
  if outputs != nil
    write_file(path_join(away, LOCK), lock_text(outputs))
  end
  away
end

test "the ledger measures a tree it is not standing in"
  away = tree_at(
    "away",
    [["crates/tiny/src/lib.rs", unlines(["fn a() {}"])]],
    []
  )
  ms = measured(away)
  assert ms == [row(KIND, "crates/tiny", 10)]
  rm_rf(away)
end

test "a Rust file a generate row writes is not counted, and growing it moves nothing"
  files = [
    ["crates/k/src/lib.rs", "fn a() {}"],
    ["crates/k/src/t.rs", "pub const T: u8 = 1;"]
  ]
  away = tree_at("made", files, ["crates/k/src/t.rs"])
  assert measured(away) == [row(KIND, "crates/k", 9)]
  write_file(
    path_join(away, "crates/k/src/t.rs"),
    "pub const T: [u8; 2] = [1, 2];"
  )
  rows = [row(KIND, "crates/k", 9)]
  assert failures(rows, KIND, measured(away)) == []
  write_file(path_join(away, "crates/k/src/lib.rs"), "fn a() { 1; }")
  assert kinds(failures(rows, KIND, measured(away))) == [:grew]
  rm_rf(away)
end

test "a tree with no lock is blind, and a blind ledger is red"
  away = tree_at("unlocked", [["crates/k/src/lib.rs", "fn a() {}"]], nil)
  got = failures([row(KIND, "crates/k", 9)], KIND, measured(away))
  assert kinds(got) == [:blind]
  assert includes(got[0][1], "#{LOCK} is absent or unreadable")
  rm_rf(away)
end

test "a blind ledger is told to write its lock, never to record what a record refuses"
  away = tree_at("unlocked", [["crates/k/src/lib.rs", "fn a() {}"]], nil)
  said = advice(failures([row(KIND, "crates/k", 9)], KIND, measured(away)))
  assert count(said) == 1
  assert includes(said[0], "blue lock .")
  assert not includes(said[0], "gen/purity.b record")
  grew = failures(
    [row(KIND, "crates/k", 1)],
    KIND,
    [measurement("crates/k", 2)]
  )
  assert advice(grew) ==
    ["a crate that grew or is new is recorded with its reason: #{RECORD}"]
  rm_rf(away)
end

test "record banks a shrink with no receipt and refuses a growth without one"
  away = tree_at("record", [["crates/k/src/lib.rs", "fn a() {}"]], [])
  path = path_join(away, BASELINE)
  mkdir_p(path_dirname(path))
  write_file(
    path,
    unlines(
      ["# receipt: measurement: receipts begin", "purity-bytes: crates/k 20"]
    )
  )
  assert value(hadome::record(path, measured(away), {})) == 1
  assert read_file(path) ==
    unlines(
      ["# receipt: measurement: receipts begin", "purity-bytes: crates/k 9"]
    )
  write_file(path_join(away, "crates/k/src/lib.rs"), "fn a() { 1; }")
  assert kinds([refusal_of(hadome::record(path, measured(away), {}))]) ==
    [:unreceipted]
  assert read_file(path) ==
    unlines(
      ["# receipt: measurement: receipts begin", "purity-bytes: crates/k 9"]
    )
  rm_rf(away)
end
