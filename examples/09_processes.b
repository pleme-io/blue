# Running other programs
#
# exec_capture runs a command with no shell and answers its status, stdout and
# stderr as pairs; shisutemu reads them. exec_check answers only the status.
# To run blue itself, spawn self_exe: a nix sandbox has no blue on PATH.
use("moji", %i[is_blank trim])
use("shisutemu", %i[status_of stderr_of stdout_of])

def blue_version()
  cap = exec_capture(self_exe, "--version")
  if status_of(cap) == 0
    trim(stdout_of(cap))
  end
end

test "a command's output, read through shisutemu"
  assert starts_with?(blue_version, "blue ")
end

test "a failing command is a status, not a raise"
  cap = exec_capture(self_exe, "no-such-subcommand")
  assert status_of(cap) != 0
  assert not is_blank(stderr_of(cap))
end
