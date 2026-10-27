use("retsu", [:concat_lists, :flat_map])

# The distroless gate for an image a Bluefile declares (nix/project.nix).
#
#   blue run image-gate.b -- STORE_PATHS TIER
#
# STORE_PATHS is the image's closure, one store path per line (closureInfo's
# store-paths). TIER is what the entry declared: distroless-static (no
# deviation), distroless-glibc (tools, no shell) or shell. A shell anywhere in
# the closure of an image that declared none is refused, and so is glibc on
# the static tier. The closure must hold blue itself, so a scan of the wrong
# list fails rather than passing over nothing.

def shells()
  ["bin/sh", "bin/bash", "bin/dash", "bin/ash", "bin/zsh", "bin/busybox"]
end

def closure(file)
  filter((p) -> p != "", split(read_file(file), line_break))
end

def shells_in(path)
  map(
    (s) -> path_join(path, s),
    filter((s) -> path_exists(path_join(path, s)), shells)
  )
end

def glibc?(path)
  count(split(path_basename(path), "-glibc-")) > 1
end

def blue?(path)
  is_file?(path_join(path, "bin/blue"))
end

def findings(paths, tier)
  shell = if tier == "shell"
    []
  else
    map(
      (s) -> "#{s}: a shell, and the image declares none",
      flat_map(paths, shells_in)
    )
  end
  libc = if tier == "distroless-static"
    map((p) -> "#{p}: glibc, on the static tier", filter(glibc?, paths))
  else
    []
  end
  concat_lists(shell, libc)
end

def gate(file, tier)
  paths = closure(file)
  if not any?(blue?, paths)
    raise(:gate, "#{file} holds no bin/blue: this is not an image's closure")
  end
  found = findings(paths, tier)
  if found != []
    raise(
      :gate,
      join_lines(["the image is not #{tier}:", join(found, line_break)])
    )
  end
  write_stdout(
    unlines(["tier #{tier}: #{to_s(count(paths))} store paths, no finding"])
  )
end

gate(argv[0], argv[1])
