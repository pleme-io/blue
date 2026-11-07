use("shisutemu", %i[blue_exe status_of stderr_of])

def main()
  root = path_join(getenv("GEN_ROOT", "."), "bidamas")
  out = getenv("GEN_OUT", "bidamas/SNAPSHOT.json")
  r = exec_capture(blue_exe, "arika", "emit", root, "--out", out)
  if status_of(r) != 0
    raise(:arika, stderr_of(r))
  end
  true
end
