use("haibi", [:files, :write_tree])
use("mokuroku", [:catalog_of, :registered_only, :render_markdown])
use("retsu", [:concat_lists, :first, :flat_map, :is_empty, :last])
use("shisutemu", [:status_of, :stdout_of])

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
  g = json_get(manifest, "generated")
  if g.nil?
    []
  else
    map(
      fn(entry)
        [
          first(entry),
          json_get(last(entry), "output"),
          json_get(last(entry), "program")
        ]
      end,
      g
    )
  end
end

# Run one generator with $GEN_OUT set to the output the lock names, so the
# declaration, not the program's own default, decides where the file goes.
def regenerate(g)
  status = exec_check(
    "env",
    "GEN_ROOT=#{cwd}",
    "GEN_OUT=#{nth(1, g)}",
    "blue",
    "run",
    nth(2, g)
  )
  if status != 0
    raise(
      :regen,
      "#{nth(2, g)} exited #{to_s(status)}; #{nth(1, g)} was not rewritten"
    )
  end
  nth(1, g)
end

def inputs_of(entry)
  i = json_get(entry, "inputs")
  if i.nil?
    []
  else
    i
  end
end

def entries_of(obj)
  if list?(obj)
    obj
  else
    map_entries(obj)
  end
end

def inputs_of_packages()
  p = json_get(manifest, "packages")
  if p.nil?
    []
  else
    p
  end
end

def read_paths()
  g = json_get(manifest, "generated")
  c = json_get(manifest, "checks")
  inputs = concat_lists(
    if g.nil?
      []
    else
      flat_map(entries_of(g), (e) -> inputs_of(last(e)))
    end,
    if c.nil?
      []
    else
      flat_map(entries_of(c), (e) -> inputs_of(last(e)))
    end
  )
  distinct(concat_lists(inputs_of_packages, inputs))
end

def untracked_files(paths)
  if is_empty(paths) or not path_exists(".git")
    []
  else
    cap = exec_capture(
      "git",
      "ls-files",
      "--others",
      "--exclude-standard",
      "--",
      *paths
    )
    if status_of(cap) != 0
      []
    else
      filter((l) -> l != "", split(stdout_of(cap), line_break))
    end
  end
end

def untracked_setting()
  v = getenv("BLUE_REGEN_UNTRACKED", "refuse")
  if v != "refuse" and v != "allow"
    raise(
      :regen_setting,
      "BLUE_REGEN_UNTRACKED is \"#{v}\"; it takes refuse (the default) or allow"
    )
  end
  v
end

untracked = untracked_files(read_paths)

if untracked != [] and untracked_setting == "refuse"
  raise(
    :untracked,
    "regen reads files the flake cannot see, because git does not track them: #{join(untracked, ", ")}. Run `git add` on them, then regen again; BLUE_REGEN_UNTRACKED=allow renders without them"
  )
end

# The catalogue covers the project's own `packages` roots, not every root on
# BLUE_PATH: a project composed over the public distribution catalogues only
# its own packages (the flake renders the same roots; nix/project.nix).
catalog = json_get(manifest, "catalog")

def registered_catalog(catalog)
  records = catalog_of(json_get(manifest, "packages"))
  ledger = path_join(path_dirname(catalog), "NAMES.md")
  if path_exists(ledger)
    registered_only(read_file(ledger), records)
  else
    records
  end
end

written = if catalog.nil?
  []
else
  write_file(catalog, render_markdown(registered_catalog(catalog)))
  [catalog]
end

written = concat_lists(written, map(regenerate, generated))

# Every `workload` file, rendered from the same lock by blue itself.
workloads = json_get(manifest, "workloads")

written = if workloads.nil?
  written
else
  if exec_check("blue", "workload", "render", "--write") != 0
    raise(:regen, "blue workload render --write failed")
  end
  concat_lists(written, map((w) -> json_get(last(w), "output"), workloads))
end

written = if json_get(manifest, "registries").nil?
  written
else
  if exec_check("blue", "registry", "render", "--write") != 0
    raise(:regen, "blue registry render --write failed")
  end
  concat_lists(
    written,
    map((r) -> json_get(last(r), "output"), json_get(manifest, "registries"))
  )
end

lock_manifest = get(json_read(read_file("Bluefile.lock")), "manifest")

written = if get(lock_manifest, "services").nil?
  written
else
  concat_lists(
    written,
    map(
      fn(e)
        out = get(second(e), "output")
        rm_rf(out)
        write_tree(
          out,
          files(first(e), get(lock_manifest, "version"), second(e))
        )
        out
      end,
      map_entries(get(lock_manifest, "services"))
    )
  )
end

write_file("/dev/stderr", unlines(["regen: rewrote #{join(written, ", ")}"]))
