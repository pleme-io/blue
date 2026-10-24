use("moji", [:checked])

@doc """
raises?: whether f raises that kind of error.
"""
def raises?(kind, f)
  f()
  false
rescue e
  e.kind == kind
end

def literal(value)
  if string?(value)
    json_stringify(value)
  else
    to_s(value)
  end
end

def snapshot_path(opts)
  name = get(opts, :name)
  if not string?(name) or name == "" or contains?(name, "/")
    raise(:bad_option, "a snapshot takes name: text with no slash")
  end
  path_join(get(opts, :dir) or "snapshots", "#{name}.b")
end

@doc """
snapshot: compare a value with its stored copy; update on request.
"""
def snapshot(value, opts)
  checked(opts, [:name, :dir, :update])
  path = snapshot_path(opts)
  actual = "#{literal(value)}\n"
  if get(opts, :update) == true
    mkdir_p(path_dirname(path))
    write_file(path, actual)
    nil
  elsif not path_exists(path)
    raise(
      :snapshot_missing,
      "no snapshot at #{path}; run with update: true to record it",
      {data: {path:, actual:}}
    )
  else
    expected = read_file(path)
    if expected != actual
      raise(
        :snapshot_mismatch,
        "snapshot #{path} differs\nexpected: #{expected}actual:   #{actual}",
        {data: {path:, expected:, actual:}}
      )
    end
    nil
  end
end

def scratch()
  path_join(getenv("TMPDIR") or "/tmp", "tesuto-#{to_s(now_ns)}")
end

def caught(f)
  f()
  nil
rescue e
  e
end

test "raises? is true for the kind raised and false for no error"
  assert raises?(:oops, () -> raise(:oops, "no")) == true
  assert raises?(:oops, () -> 1 + 1) == false
  assert raises?(:oops, () -> nil) == false
end

test "raises? is false for another kind and never raises for the kind it tests"
  assert raises?(:oops, () -> raise(:other, "no")) == false
  assert raises?(:other, () -> raise(:oops, "no")) == false
  assert raises?(:oops, () -> raise(:oops, "x", {data: {a: 1}})) == true
end

test "raises? sees an error raised deep inside the function"
  deep = () -> map((x) -> raise(:oops, "at #{to_s(x)}"), [1, 2])
  assert raises?(:oops, deep) == true
  assert raises?(:oops, () -> map((x) -> x, [])) == false
end

test "snapshot records with update and then accepts the same value"
  dir = scratch
  assert snapshot({a: [1, 2]}, {name: "first", dir:, update: true}).nil?
  assert read_file(path_join(dir, "first.b")) == "{a: [1, 2]}\n"
  assert snapshot({a: [1, 2]}, {name: "first", dir:}).nil?
  rm_rf(dir)
end

test "snapshot refuses a changed value and names both copies"
  dir = scratch
  snapshot([1, 2, 3], {name: "list", dir:, update: true})
  e = caught(() -> snapshot([1, 2, 4], {name: "list", dir:}))
  assert e.kind == :snapshot_mismatch
  assert e.data.expected == "[1, 2, 3]\n"
  assert e.data.actual == "[1, 2, 4]\n"
  assert contains?(e.message, "differs") == true
  rm_rf(dir)
end

test "snapshot update replaces the stored copy"
  dir = scratch
  snapshot([1], {name: "n", dir:, update: true})
  snapshot([2], {name: "n", dir:, update: true})
  assert read_file(path_join(dir, "n.b")) == "[2]\n"
  assert snapshot([2], {name: "n", dir:}).nil?
  rm_rf(dir)
end

test "snapshot of nothing recorded is a missing snapshot, not a pass"
  dir = scratch
  e = caught(() -> snapshot(1, {name: "absent", dir:}))
  assert e.kind == :snapshot_missing
  assert path_exists(dir) == false
end

test "snapshot tells text from a keyword and from a number"
  dir = scratch
  snapshot("a", {name: "t", dir:, update: true})
  assert read_file(path_join(dir, "t.b")) == "\"a\"\n"
  assert raises?(:snapshot_mismatch, () -> snapshot(:a, {name: "t", dir:}))
  assert raises?(:snapshot_mismatch, () -> snapshot(1, {name: "t", dir:}))
  snapshot(nil, {name: "z", dir:, update: true})
  assert read_file(path_join(dir, "z.b")) == "\n"
  assert snapshot(nil, {name: "z", dir:}).nil?
  rm_rf(dir)
end

test "snapshot refuses a missing or unsafe name and an unknown option"
  assert raises?(:bad_option, () -> snapshot(1, {dir: "x"}))
  assert raises?(:bad_option, () -> snapshot(1, {name: "", dir: "x"}))
  assert raises?(:bad_option, () -> snapshot(1, {name: "../up", dir: "x"}))
  assert raises?(:bad_option, () -> snapshot(1, {name: 5, dir: "x"}))
  assert raises?(
    :bad_option,
    () -> snapshot(1, {name: "n", dir: "x", fresh: true})
  )
end

test "snapshot defaults its directory to snapshots"
  assert snapshot_path({name: "n"}) == "snapshots/n.b"
  assert snapshot_path({name: "n", dir: "d/e"}) == "d/e/n.b"
end
