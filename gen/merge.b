use("retsu", [:first, :last, :reject])
use("shisutemu", [:status_of, :stderr_of, :stdout_of])

ancestor = argv_get(0)
ours = argv_get(1)
theirs = argv_get(2)
path = argv_get(3)

def lines_of(text)
  reject((l) -> l == "", split(text, "\n"))
end

def git(args)
  stdout_of(exec_capture("git", *args))
end

def as_text(ancestor, ours, theirs)
  exit_with(
    exec_check(
      "git",
      "merge-file",
      "-L",
      "ours",
      "-L",
      "base",
      "-L",
      "theirs",
      ours,
      ancestor,
      theirs
    )
  )
end

def picked(line)
  words = split(line, " ")
  if count(words) > 1 and
      member?(
        first(words),
        ["pick", "p", "reword", "r", "edit", "e", "fixup", "f", "squash", "s"]
      )
    nth(1, words)
  end
end

def their_commit()
  done = "#{blue::trim(git(["rev-parse", "--path-format=absolute", "--git-dir"]))}/rebase-merge/done"
  if path_exists(done)
    sha = picked(last(lines_of(read_file(done))))
    if sha.nil?
      nil
    else
      [sha, "#{sha}^"]
    end
  else
    heads = filter(
      (l) -> starts_with?(l, "GITHEAD_"),
      lines_of(stdout_of(exec_capture("env")))
    )
    if count(heads) == 1
      [first(split(replace(first(heads), "GITHEAD_", ""), "=")), nil]
    end
  end
end

def merged_tree(pick)
  base = if last(pick).nil?
    []
  else
    ["--merge-base=#{last(pick)}"]
  end
  r = exec_with_env(
    [["BLUE_MERGE_NESTED", "1"]],
    "git",
    *append(["merge-tree", "--write-tree"], base, ["HEAD", first(pick)])
  )
  if status_of(r) > 1
    nil
  else
    first(lines_of(stdout_of(r)))
  end
end

def generated_outputs(tree)
  m = get(json_read(read_file("#{tree}/Bluefile.lock")), "manifest")
  outputs = map(
    (e) -> get(last(e), "output"),
    map_entries(get(m, "generated") or {})
  )
  if get(m, "catalog").nil?
    outputs
  else
    append([get(m, "catalog")], outputs)
  end
end

def regenerate(tree, path)
  bin = path_dirname(self_exe)
  if path_basename(path) == "Bluefile.lock"
    exec_capture("env", "-C", tree, self_exe, "lock", path_dirname(path))
  elsif member?(path, generated_outputs(tree))
    exec_capture(
      "env",
      "-C",
      tree,
      "PATH=#{bin}:#{getenv("PATH")}",
      self_exe,
      "run",
      "--quiet",
      "gen/regen.b",
      "--",
      path
    )
  end
end

if getenv("BLUE_MERGE_NESTED") == "1"
  as_text(ancestor, ours, theirs)
end

pick = their_commit

tree = if pick.nil?
  nil
else
  merged_tree(pick)
end

if tree.nil?
  write_stderr(
    "merge: #{path} is generated, and this merge names no commit to regenerate it from; merged as text\n"
  )
  as_text(ancestor, ours, theirs)
end

scratch = blue::trim(stdout_of(exec_capture("mktemp", "-d")))
index = [["GIT_INDEX_FILE", "#{scratch}/index"]]
exec_with_env(index, "git", "read-tree", tree)
exec_with_env(index, "git", "checkout-index", "-a", "--prefix=#{scratch}/tree/")
run = regenerate("#{scratch}/tree", path)

if run.nil? or status_of(run) != 0
  why = if run.nil?
    "no generator names it"
  else
    stderr_of(run)
  end
  rm_rf(scratch)
  write_stderr("merge: #{path} was not regenerated: #{why}; merged as text\n")
  as_text(ancestor, ours, theirs)
end

write_file(ours, read_file("#{scratch}/tree/#{path}"))
rm_rf(scratch)
write_stderr("merge: #{path} regenerated from the merged tree\n")
