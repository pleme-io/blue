use("shisutemu", %i[blue_exe status_of stderr_of])

def main()
  root = path_join(getenv("GEN_ROOT", "."), "bidamas")
  out = getenv("RUN_OUT", "result-arika")
  r = exec_capture(
    blue_exe,
    "arika",
    "emit",
    root,
    "--out",
    path_join(out, "SNAPSHOT.json"),
    "--facts",
    path_join(out, "facts.jsonl")
  )
  if status_of(r) != 0
    raise(:arika, stderr_of(r))
  end
  true
end
