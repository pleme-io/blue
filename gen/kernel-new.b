@moduledoc """
kernel-new: holds `blue new --kernel` to the kernel words as they change. It makes a project in a fresh directory and runs its tests with the blue under test, so a word the template names that moves or breaks turns this check red.
"""

use("shisutemu", %i[status_of stderr_of stdout_of])

def fresh(tag)
  dir = path_join(getenv("TMPDIR", "/tmp"), "kernel-new-#{tag}-#{to_s(now_ms)}")
  mkdir_p(dir)
  dir
end

def project(dir)
  path = path_join(dir, "probe")
  made = exec_capture(self_exe, "new", "--kernel", path)
  if status_of(made) != 0
    raise(:kernel_new, stderr_of(made))
  end
  path
end

def blue_in(root, args)
  exec_with_env([["GEN_ROOT", root], %w[BLUE_TEST_CACHE off]], self_exe, *args)
end

test "a generated project passes its tests with what this host has"
  dir = fresh("test")
  got = begin
    root = project(dir)
    blue_in(root, ["test", path_join(root, "probe.b")])
  ensure
    rm_rf(dir)
  end
  assert status_of(got) == 0
  said = stdout_of(got)
  assert contains?(said, "3 passed, 0 failed, 1 skipped") or
    contains?(said, "4 passed, 0 failed")
end

test "a skip names the test and the reason, and refused it is a failure"
  dir = fresh("skip")
  root = project(dir)
  file = path_join(root, "probe.b")
  plain = blue_in(root, ["test", file])
  refused = exec_with_env(
    [["GEN_ROOT", root], %w[BLUE_TEST_SKIP refuse]],
    self_exe,
    "test",
    file
  )
  rm_rf(dir)
  if contains?(stdout_of(plain), "skipped")
    assert contains?(stderr_of(plain), "SKIP on a real kernel")
    assert status_of(refused) != 0
    assert contains?(stderr_of(refused), "BLUE_TEST_SKIP=refuse")
  else
    assert status_of(refused) == 0
  end
end

test "a generated project is canonical, and its lock is its Bluefile's evaluation"
  dir = fresh("gates")
  root = project(dir)
  formatted = exec_capture(
    self_exe,
    "fmt",
    "--check",
    path_join(root, "probe.b"),
    path_join(root, "Bluefile")
  )
  confirmed = exec_capture(
    self_exe,
    "bluefile",
    "--confirm",
    path_join(root, "Bluefile")
  )
  said = read_file(path_join(root, "Bluefile"))
  rm_rf(dir)
  assert status_of(formatted) == 0
  assert status_of(confirmed) == 0
  assert contains?(said, "kernel_bpf")
end

test "a name the distribution holds is refused by name"
  dir = fresh("name")
  got = exec_capture(self_exe, "new", "--kernel", path_join(dir, "kaaneru"))
  rm_rf(dir)
  assert status_of(got) != 0
  assert contains?(stderr_of(got), "standard bidama")
end
