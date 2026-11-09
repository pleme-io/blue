use("shisutemu", %i[read_or status_of stderr_of])

def regen_program()
  root = getenv("GEN_ROOT", cwd)
  if starts_with?(root, "/")
    path_join(root, "gen/regen.b")
  else
    path_join(path_join(cwd, root), "gen/regen.b")
  end
end

def git(dir, args)
  cap = exec_capture("git", "-C", dir, *args)
  if status_of(cap) != 0
    raise(:git, stderr_of(cap))
  end
  cap
end

def fixture()
  dir = path_join(getenv("TMPDIR", "/tmp"), "regen-untracked-#{to_s(now_ns)}")
  mkdir_p(path_join(dir, "bidamas/zed"))
  write_file(
    path_join(dir, "Bluefile"),
    unlines(
      [
        "package(\"fixture\", \"0.1.0\")",
        "packages(\"bidamas\")",
        "catalog(\"bidamas/CATALOG.md\")",
        "check(\"unit\", \"t.b\", [\"notes\"])"
      ]
    )
  )
  write_file(
    path_join(dir, "bidamas/zed/Bluefile"),
    unlines(["package(\"zed\", \"0.1.0\")"])
  )
  write_program(
    path_join(dir, "bidamas/zed/zed.b"),
    unlines(
      [
        "@moduledoc \"\"\"",
        "zed: a fixture package.",
        "",
        "    one #=> 1",
        "\"\"\"",
        "",
        "@doc \"\"\"",
        "one: The number one.",
        "",
        "    one #=> 1",
        "\"\"\"",
        "def one()",
        "  1",
        "end"
      ]
    )
  )
  write_program(
    path_join(dir, "t.b"),
    unlines(["test \"one\"", "  assert true", "end"])
  )
  mkdir_p(path_join(dir, "notes"))
  write_file(path_join(dir, "notes/n.txt"), unlines(["a note"]))
  if status_of(exec_capture(self_exe, "lock", dir)) != 0
    raise(:fixture, "blue lock failed in #{dir}")
  end
  git(".", ["init", "-q", "-b", "main", dir])
  git(dir, %w[add Bluefile Bluefile.lock t.b])
  dir
end

def regen_in(dir, env)
  exec_with_env(
    env,
    "env",
    "-C",
    dir,
    self_exe,
    "run",
    "--quiet",
    regen_program
  )
end

def generating_fixture()
  dir = path_join(getenv("TMPDIR", "/tmp"), "regen-self-#{to_s(now_ns)}")
  mkdir_p(path_join(dir, "fake"))
  write_file(
    path_join(dir, "Bluefile"),
    unlines(
      [
        "package(\"fixture\", \"0.1.0\")",
        "generate(\"made\", \"made.txt\", \"gen.b\")"
      ]
    )
  )
  write_program(
    path_join(dir, "gen.b"),
    unlines(
      [
        "@moduledoc \"\"\"",
        "gen: the fixture's generator, which writes made.",
        "",
        "    join(%w[ma de], \"\") #=> \"made\"",
        "\"\"\"",
        "",
        "write_file(getenv(\"GEN_OUT\"), \"made\")"
      ]
    )
  )
  fake = path_join(dir, "fake/blue")
  write_file(
    fake,
    unlines(["#!/bin/sh", "touch '#{path_join(dir, "fake-ran")}'", "exit 7"])
  )
  exec_check("chmod", "+x", fake)
  if status_of(exec_capture(self_exe, "lock", dir)) != 0
    raise(:fixture, "blue lock failed in #{dir}")
  end
  dir
end

def fake_first(dir)
  ["PATH", "#{path_join(dir, "fake")}:#{getenv("PATH")}"]
end

test "regen spawns the blue running it, not a blue first on PATH"
  if self_exe != nil
    dir = generating_fixture
    cap = regen_in(dir, [fake_first(dir)])
    assert not path_exists(path_join(dir, "fake-ran"))
    assert status_of(cap) == 0
    assert read_or(path_join(dir, "made.txt"), nil) == "made"
    rm_rf(dir)
  end
end

test "BLUE_SPAWN_FROM_PATH=1 spawns the blue on PATH"
  if self_exe != nil
    dir = generating_fixture
    cap = regen_in(dir, [fake_first(dir), %w[BLUE_SPAWN_FROM_PATH 1]])
    assert status_of(cap) != 0
    assert path_exists(path_join(dir, "fake-ran"))
    assert not path_exists(path_join(dir, "made.txt"))
    rm_rf(dir)
  end
end

test "regen refuses a package git does not track, and names its files"
  if self_exe != nil
    dir = fixture
    cap = regen_in(dir, [])
    assert status_of(cap) != 0
    assert contains?(stderr_of(cap), "bidamas/zed/zed.b")
    assert contains?(stderr_of(cap), "notes/n.txt")
    assert not path_exists(path_join(dir, "bidamas/CATALOG.md"))
    rm_rf(dir)
  end
end

test "regen renders once the package is tracked"
  if self_exe != nil
    dir = fixture
    git(dir, %w[add bidamas notes])
    cap = regen_in(dir, [])
    assert status_of(cap) == 0
    assert contains?(read_file(path_join(dir, "bidamas/CATALOG.md")), "zed")
    rm_rf(dir)
  end
end

test "allow renders without the refusal, and an unknown setting is refused"
  if self_exe != nil
    dir = fixture
    assert status_of(regen_in(dir, [%w[BLUE_REGEN_UNTRACKED allow]])) == 0
    bad = regen_in(dir, [%w[BLUE_REGEN_UNTRACKED maybe]])
    assert status_of(bad) != 0
    assert contains?(stderr_of(bad), "BLUE_REGEN_UNTRACKED")
    rm_rf(dir)
  end
end
