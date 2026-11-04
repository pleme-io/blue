use("hon", [:generated_files])
use("mokuroku", [:tsv_lines])
use("retsu", %i[first last])
use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
picked: The commit a line of a rebase's `done` file picks, or nil for a line
that picks none.

    picked("pick 8bd5119 land") #=> "8bd5119"
    picked("exec cargo test") #=> nil
    picked("pick") #=> nil
"""
def picked(line)
  words = split(line, " ")
  if count(words) > 1 and
      member?(first(words), %w[pick p reword r edit e fixup f squash s])
    words[1]
  end
end

@doc """
merge_head: The commit a `git merge` names in its GITHEAD_ variable, from the
lines of the environment; nil unless exactly one names one.

    merge_head(["GITHEAD_abc=topic", "PATH=/bin"]) #=> "abc"
    merge_head(["PATH=/bin"]) #=> nil
"""
def merge_head(environment)
  heads = filter((l) -> starts_with?(l, "GITHEAD_"), environment)
  if count(heads) == 1
    first(split(replace(first(heads), "GITHEAD_", ""), "="))
  end
end

@doc """
picked_label: The commit a cherry-pick's conflict label names (git passes it as
%Y): the short name before its parenthesized subject, or nil for a label that
names none.

    picked_label("8bd5119 (land it)") #=> "8bd5119"
    picked_label("topic") #=> nil
    picked_label("") #=> nil
"""
def picked_label(label)
  if contains?(label, " (")
    first(split(label, " ("))
  end
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

def pick_of(label)
  short = picked_label(label)
  on = getenv("BLUE_MERGE_PICK", "on") != "off"
  if on and not short.nil?
    found = exec_capture(
      "git",
      "rev-parse",
      "--verify",
      "-q",
      "#{short}^{commit}"
    )
    if status_of(found) == 0
      sha = trim(stdout_of(found))
      [sha, "#{sha}^"]
    end
  end
end

def their_commit(label)
  done = "#{trim(git(%w[rev-parse --path-format=absolute --git-dir]))}/rebase-merge/done"
  if path_exists(done)
    sha = picked(last(tsv_lines(read_file(done))))
    if not sha.nil?
      [sha, "#{sha}^"]
    end
  else
    sha = merge_head(tsv_lines(stdout_of(exec_capture("env"))))
    if sha.nil?
      pick_of(label)
    else
      [sha, nil]
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
    [%w[BLUE_MERGE_NESTED 1]],
    "git",
    *append(%w[merge-tree --write-tree], base, ["HEAD", first(pick)])
  )
  if status_of(r) > 1
    nil
  else
    first(tsv_lines(stdout_of(r)))
  end
end

def in_tree(tree, args)
  exec_with_env(
    [["PATH", "#{path_dirname(self_exe)}:#{getenv("PATH")}"]],
    "env",
    "-u",
    "GEN_ROOT",
    "-C",
    tree,
    self_exe,
    *args
  )
end

def regenerate(tree, path)
  is_lock = path_basename(path) == "Bluefile.lock"
  dir = if is_lock and path_dirname(path) != ""
    path_dirname(path)
  else
    "."
  end
  locked = in_tree(tree, ["lock", dir])
  if is_lock or status_of(locked) != 0
    locked
  elsif member?(
    path,
    generated_files(
      {manifest: json_read(read_file("#{tree}/Bluefile.lock"))["manifest"]}
    )
  )
    in_tree(tree, ["run", "--quiet", "gen/regen.b", "--", path])
  end
end

@doc """
main: A merge driver for a generated file, as git calls it with %O %A %B %P %Y.
Text merging a generated file is the wrong question: its sources merged, so
this regenerates it from the merged tree and leaves that in %A. A rebase names
its commit in `rebase-merge/done`, a merge in GITHEAD_, a cherry-pick in the
%Y label; BLUE_MERGE_PICK=off ignores the label. A commit it cannot name, a
merge of the sources that does not produce a tree, or a generator that fails
each falls back to the text merge git would have run, and says so. `nix
develop` and `git land` set the driver; a clone without it merges as text.
"""
def main()
  ancestor = argv_get(0)
  ours = argv_get(1)
  theirs = argv_get(2)
  path = argv_get(3)
  if getenv("BLUE_MERGE_NESTED") == "1"
    as_text(ancestor, ours, theirs)
  end
  pick = their_commit(
    if count(argv) > 4
      argv_get(4)
    else
      ""
    end
  )
  tree = if pick.nil?
    nil
  else
    merged_tree(pick)
  end
  if tree.nil?
    write_stderr(
      unlines(
        [
          "merge: #{path} is generated, and this merge names no commit to regenerate it from; merged as text"
        ]
      )
    )
    as_text(ancestor, ours, theirs)
  end
  scratch = trim(stdout_of(exec_capture("mktemp", "-d")))
  index = [["GIT_INDEX_FILE", "#{scratch}/index"]]
  exec_with_env(index, "git", "read-tree", tree)
  exec_with_env(
    index,
    "git",
    "checkout-index",
    "-a",
    "--prefix=#{scratch}/tree/"
  )
  run = regenerate("#{scratch}/tree", path)
  if run.nil? or status_of(run) != 0
    why = if run.nil?
      "no generator names it"
    else
      stderr_of(run)
    end
    rm_rf(scratch)
    write_stderr(
      unlines(["merge: #{path} was not regenerated: #{why}; merged as text"])
    )
    as_text(ancestor, ours, theirs)
  end
  write_file(ours, read_file("#{scratch}/tree/#{path}"))
  rm_rf(scratch)
  write_stderr(unlines(["merge: #{path} regenerated from the merged tree"]))
end

def program(name)
  root = getenv("GEN_ROOT", cwd)
  if starts_with?(root, "/")
    path_join(root, name)
  else
    path_join(path_join(cwd, root), name)
  end
end

def in_repo(dir, args)
  exec_capture(
    "git",
    "-C",
    dir,
    "-c",
    "user.name=t",
    "-c",
    "user.email=t@t",
    *args
  )
end

def must(dir, args)
  cap = in_repo(dir, args)
  if status_of(cap) != 0
    raise(:git, "git #{join(args, " ")}: #{stderr_of(cap)}")
  end
  cap
end

def fixture(attributed)
  dir = path_join(getenv("TMPDIR", "/tmp"), "merge-#{to_s(now_ns)}")
  mkdir_p(path_join(dir, "gen"))
  mkdir_p(path_join(dir, "notes"))
  write_program(
    path_join(dir, "gen/regen.b"),
    read_file(program("gen/regen.b"))
  )
  write_file(
    path_join(dir, "Bluefile"),
    unlines(
      [
        "package(\"fixture\", \"0.1.0\")",
        "generate(\"made\", \"made.txt\", \"made.b\", [\"notes\"])"
      ]
    )
  )
  write_program(
    path_join(dir, "made.b"),
    unlines(
      [
        "root = getenv(\"GEN_ROOT\", \".\")",
        "there = (n) -> path_exists(path_join(path_join(root, \"notes\"), n))",
        "write_file(getenv(\"GEN_OUT\"), unlines(filter(there, %w[ant base bee])))"
      ]
    )
  )
  write_file(path_join(dir, "notes/base"), "base")
  write_file(path_join(dir, "made.txt"), unlines(["base"]))
  if attributed
    write_file(
      path_join(dir, ".gitattributes"),
      unlines(["made.txt merge=blue-generated"])
    )
  end
  if status_of(exec_capture(self_exe, "lock", dir)) != 0
    raise(:fixture, "blue lock failed in #{dir}")
  end
  must(dir, %w[init -q -b main])
  must(
    dir,
    [
      "config",
      "merge.blue-generated.driver",
      "#{self_exe} run --quiet #{program("gen/merge.b")} -- %O %A %B %P %Y"
    ]
  )
  must(dir, %w[add -A])
  must(dir, %w[commit -q -m base])
  dir
end

def note(dir, branch, start, name)
  must(dir, ["checkout", "-q", "-b", branch, start])
  write_file(path_join(dir, "notes/#{name}"), name)
  write_file(path_join(dir, "made.txt"), unlines(["base", name]))
  must(dir, %w[add -A])
  must(dir, ["commit", "-q", "-m", name])
end

def two_branches(attributed)
  dir = fixture(attributed)
  note(dir, "one", "main", "ant")
  note(dir, "two", "main", "bee")
  dir
end

test "the same two branches conflict on the generated file without the driver"
  if self_exe != nil
    dir = two_branches(false)
    must(dir, %w[checkout -q one])
    assert status_of(in_repo(dir, %w[merge -q --no-edit two])) != 0
    assert contains?(read_file(path_join(dir, "made.txt")), "<<<<<<<")
    rm_rf(dir)
  end
end

test "a merge regenerates the generated file from the merged tree"
  if self_exe != nil
    dir = two_branches(true)
    must(dir, %w[checkout -q one])
    merged = in_repo(dir, %w[merge -q --no-edit two])
    assert status_of(merged) == 0
    assert read_file(path_join(dir, "made.txt")) == unlines(%w[ant base bee])
    rm_rf(dir)
  end
end

test "a rebase regenerates the generated file at the commit it replays"
  if self_exe != nil
    dir = two_branches(true)
    must(dir, %w[checkout -q two])
    rebased = in_repo(dir, %w[rebase -q one])
    assert status_of(rebased) == 0
    assert read_file(path_join(dir, "made.txt")) == unlines(%w[ant base bee])
    rm_rf(dir)
  end
end

test "a cherry-pick regenerates the generated file from its label's commit"
  if self_exe != nil
    dir = two_branches(true)
    must(dir, %w[checkout -q one])
    picked_up = in_repo(dir, %w[cherry-pick two])
    assert status_of(picked_up) == 0
    assert read_file(path_join(dir, "made.txt")) == unlines(%w[ant base bee])
    rm_rf(dir)
  end
end

test "BLUE_MERGE_PICK=off and a driver with no label both merge a cherry-pick as text and say so"
  if self_exe != nil
    dir = two_branches(true)
    must(
      dir,
      [
        "config",
        "merge.blue-generated.driver",
        "env BLUE_MERGE_PICK=off #{self_exe} run --quiet #{program("gen/merge.b")} -- %O %A %B %P %Y"
      ]
    )
    must(dir, %w[checkout -q one])
    picked_up = in_repo(dir, %w[cherry-pick two])
    assert status_of(picked_up) != 0
    assert contains?(stderr_of(picked_up), "merged as text")
    must(dir, %w[cherry-pick --abort])
    must(
      dir,
      [
        "config",
        "merge.blue-generated.driver",
        "#{self_exe} run --quiet #{program("gen/merge.b")} -- %O %A %B %P"
      ]
    )
    picked_up = in_repo(dir, %w[cherry-pick two])
    assert status_of(picked_up) != 0
    assert contains?(stderr_of(picked_up), "merged as text")
    assert contains?(read_file(path_join(dir, "made.txt")), "<<<<<<<")
    rm_rf(dir)
  end
end
