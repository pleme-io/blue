use("retsu")
use("mokuroku")
# regen: rewrite every file blue generates for this repository, in place.
#
#   nix run .#regen        (from the repository root)
#
# What to generate is not listed here. It is read from Bluefile.lock, blue's
# evaluation of ./Bluefile: the catalogue path from `catalog`, and every
# generated file from `generate`. The flake reads the same lock to build and
# gate each file, so regen and the checks cannot disagree about what exists.
# Bluefile.lock itself has its own command: `blue lock .`.

def manifest()
  json_get(json_parse(read_file("Bluefile.lock")), "manifest")
end

# [name, output, program] for every `generate` in the Bluefile.
def generated()
  g = json_get(manifest(), "generated")
  if g == nil
    []
  else
    map(fn(entry) [first(entry), json_get(last(entry), "output"), json_get(last(entry), "program")] end, g)
  end
end

# Run one generator with $GEN_OUT set to the output the lock names, so the
# declaration, not the program's own default, decides where the file goes.
def regenerate(g)
  status = exec_check("env", "GEN_OUT=#{nth(1, g)}", "blue", "run", nth(2, g))
  if status != 0
    throw(error(:regen, "#{nth(2, g)} exited #{to_s(status)}; #{nth(1, g)} was not rewritten", []))
  end
  nth(1, g)
end

# The catalogue covers the project's own `packages` roots, not every root on
# BLUE_PATH: a project composed over the public distribution catalogues only
# its own packages (the flake renders the same roots; nix/project.nix).
catalog = json_get(manifest(), "catalog")
written = if catalog == nil
  []
else
  write_file(catalog, render_markdown(catalog_of(json_get(manifest(), "packages"))))
  [catalog]
end
written = concat_lists(written, map(fn(g) regenerate(g) end, generated()))
write_file("/dev/stderr", "regen: rewrote #{join(written, ", ")}\n")
