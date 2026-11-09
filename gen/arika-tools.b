use("shisutemu", %i[blue_exe status_of stderr_of stdout_of])

def main()
  out = getenv("GEN_OUT", "docs/arika-tools.json")
  r = exec_capture(blue_exe, "arika", "tools")
  if status_of(r) != 0
    raise(:arika, stderr_of(r))
  end
  write_file(out, stdout_of(r))
  true
end
