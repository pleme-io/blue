use("deeta", [:get_or])

use(
  "moji",
  [
    :char_index,
    :checked,
    :drop_chars,
    :ends_with,
    :lines,
    :starts_with,
    :take_chars
  ]
)

use("retsu", [:first, :is_empty, :last])
use("shisutemu")

def run(repo, args)
  exec_with_env(
    [["GIT_TERMINAL_PROMPT", "0"], ["LC_ALL", "C"]],
    "git",
    "-C",
    repo,
    *args
  )
end

def fail(repo, args, cap)
  raise(
    :git_failed,
    "git #{join(args, " ")} in #{repo}: #{trim(shisutemu::stderr_of(cap))}"
  )
end

def raw(repo, args)
  cap = run(repo, args)
  if shisutemu::status_of(cap) != 0
    fail(repo, args, cap)
  end
  shisutemu::stdout_of(cap)
end

def out(repo, args)
  trim(raw(repo, args))
end

def succeeds(repo, args)
  shisutemu::status_of(run(repo, args)) == 0
end

def commit_of(line)
  f = split(line, "\u{1f}")
  {
    oid: nth(0, f),
    parents: filter((p) -> p != "", split(nth(1, f), " ")),
    author: nth(2, f),
    date: nth(3, f),
    subject: nth(4, f)
  }
end

def commit_format()
  "--format=%H%x1f%P%x1f%an%x1f%aI%x1f%s"
end

def resolves(repo, ref)
  succeeds(repo, ["rev-parse", "--verify", "--quiet", "#{ref}^{commit}"])
end

def exists?(repo, ref)
  resolves(repo, ref)
end

def commit_at(repo, ref)
  if resolves(repo, ref)
    commit_of(out(repo, ["log", "-1", commit_format, ref, "--"]))
  end
end

def head_of(repo)
  commit_at(repo, "HEAD")
end

def ancestor?(repo, a, b)
  cap = run(repo, ["merge-base", "--is-ancestor", a, b])
  s = shisutemu::status_of(cap)
  if s == 0
    true
  elsif s == 1
    false
  else
    fail(repo, ["merge-base", "--is-ancestor", a, b], cap)
  end
end

def change_of(line)
  {path: drop_chars(line, 3), state: take_chars(line, 2)}
end

def counts(repo)
  cap = run(repo, ["rev-list", "--left-right", "--count", "@{u}...HEAD"])
  if shisutemu::status_of(cap) == 0
    p = split(trim(shisutemu::stdout_of(cap)), "\t")
    {behind: to_int(nth(0, p)), ahead: to_int(nth(1, p))}
  else
    {behind: 0, ahead: 0}
  end
end

def info(repo)
  if succeeds(repo, ["rev-parse", "--git-dir"]) == false
    raise(:not_found, "#{repo} is not a git repository")
  end
  head = head_of(repo)
  c = counts(repo)
  changes = map(change_of, lines(raw(repo, ["status", "--porcelain"])))
  {
    branch: if succeeds(repo, ["symbolic-ref", "-q", "HEAD"])
      out(repo, ["symbolic-ref", "--short", "HEAD"])
    end,
    head: if head != nil
      head.oid
    end,
    ahead: c.ahead,
    behind: c.behind,
    clean?: is_empty(changes),
    changes:
  }
end

def branch_of(line)
  f = split(line, "\t")
  {name: nth(0, f), oid: nth(1, f), current: nth(2, f) == "*"}
end

def tag_of(line)
  f = split(line, "\t")
  {name: nth(0, f), oid: nth(1, f)}
end

def remote_of(line)
  f = split(line, "\t")
  {name: nth(0, f), url: first(split(nth(1, f), " "))}
end

def worktree_of(block)
  fields = map(
    fn(l)
      i = char_index(l, " ")
      [take_chars(l, i), drop_chars(l, i + 1)]
    end,
    filter((l) -> contains?(l, " "), lines(block))
  )
  row = zipmap(map(first, fields), map(last, fields))
  {
    path: get_or(row, "worktree", nil),
    head: get_or(row, "HEAD", nil),
    branch: get_or(row, "branch", nil)
  }
end

def entries(repo, what, opts)
  checked(opts, [:limit, :ref])
  if what == :branches
    map(
      branch_of,
      lines(
        raw(
          repo,
          [
            "for-each-ref",
            "--format=%(refname:short)%09%(objectname)%09%(HEAD)",
            "refs/heads"
          ]
        )
      )
    )
  elsif what == :tags
    map(
      tag_of,
      lines(
        raw(
          repo,
          [
            "for-each-ref",
            "--format=%(refname:short)%09%(objectname)",
            "refs/tags"
          ]
        )
      )
    )
  elsif what == :commits
    map(
      commit_of,
      lines(
        raw(
          repo,
          [
            "log",
            commit_format,
            "-n",
            to_s(get_or(opts, :limit, 50)),
            get_or(opts, :ref, "HEAD"),
            "--"
          ]
        )
      )
    )
  elsif what == :remotes
    map(
      remote_of,
      filter((l) -> ends_with(l, "(fetch)"), lines(raw(repo, ["remote", "-v"])))
    )
  elsif what == :worktrees
    map(
      worktree_of,
      filter(
        (b) -> b != "",
        split(raw(repo, ["worktree", "list", "--porcelain"]), "\n\n")
      )
    )
  else
    raise(
      :bad_option,
      "list takes :branches, :tags, :commits, :remotes or :worktrees, not #{what}"
    )
  end
end

def read(repo, path, opts)
  checked(opts, [:at])
  at = get_or(opts, :at, "HEAD")
  cap = run(repo, ["show", "#{at}:#{path}"])
  if shisutemu::status_of(cap) != 0
    raise(:not_found, "#{path} at #{at} in #{repo}")
  end
  shisutemu::stdout_of(cap)
end

def state_of(code)
  if code == "A"
    :added
  elsif code == "D"
    :deleted
  elsif code == "T"
    :type_changed
  else
    :modified
  end
end

def change_line(line)
  f = split(line, "\t")
  {path: nth(1, f), state: state_of(nth(0, f))}
end

def diff(repo, a, b, opts)
  checked(opts, [:paths])
  map(
    change_line,
    lines(
      raw(
        repo,
        append(
          ["diff", "--name-status", "--no-renames", a, b, "--"],
          get_or(opts, :paths, [])
        )
      )
    )
  )
end

def ref_of(key, kind)
  if starts_with(key, "refs/")
    key
  elsif kind == :tag
    "refs/tags/#{key}"
  else
    "refs/heads/#{key}"
  end
end

def create(repo, key, value, opts)
  checked(opts, [:kind])
  ref = ref_of(key, get_or(opts, :kind, :branch))
  if succeeds(repo, ["show-ref", "--verify", "--quiet", ref])
    raise(:exists, "#{ref} in #{repo}")
  end
  if resolves(repo, value) == false
    raise(:not_found, "#{value} in #{repo}")
  end
  out(repo, ["update-ref", ref, "#{value}^{commit}", ""])
  value
end

def delete(repo, key)
  ref = ref_of(key, :branch)
  if succeeds(repo, ["show-ref", "--verify", "--quiet", ref])
    if starts_with(ref, "refs/heads/")
      out(repo, ["branch", "-D", drop_chars(ref, 11)])
    elsif starts_with(ref, "refs/tags/")
      out(repo, ["tag", "-d", drop_chars(ref, 10)])
    else
      out(repo, ["update-ref", "-d", ref])
    end
  end
  nil
end

def commit(repo, message, opts)
  checked(opts, [:paths, :all, :author])
  paths = get_or(opts, :paths, [])
  if is_empty(paths) == false
    out(repo, append(["add", "--"], paths))
  end
  if get_or(opts, :all, false)
    out(repo, ["add", "-A"])
  end
  if succeeds(repo, ["diff", "--cached", "--quiet"])
    raise(:empty, "nothing staged to commit in #{repo}")
  end
  author = get_or(opts, :author, nil)
  out(
    repo,
    append(
      ["commit", "-m", message],
      if author != nil
        ["--author", author]
      else
        []
      end
    )
  )
  head_of(repo)
end

def fetch(repo, opts)
  checked(opts, [:remote, :prune])
  out(
    repo,
    append(
      ["fetch"],
      if get_or(opts, :prune, false)
        ["--prune"]
      else
        []
      end,
      [get_or(opts, :remote, "origin")]
    )
  )
  nil
end

def clone(url, dir, opts)
  checked(opts, [:branch, :depth])
  branch = get_or(opts, :branch, nil)
  depth = get_or(opts, :depth, nil)
  out(
    ".",
    append(
      ["clone"],
      if branch != nil
        ["--branch", branch]
      else
        []
      end,
      if depth != nil
        ["--depth", to_s(depth)]
      else
        []
      end,
      ["--", url, dir]
    )
  )
  dir
end

def merge(repo, ref, opts)
  checked(opts, [:fast_forward_only])
  ff = get_or(opts, :fast_forward_only, true)
  args = if ff
    ["merge", "--ff-only", ref]
  else
    ["merge", "--no-edit", ref]
  end
  cap = run(repo, args)
  if shisutemu::status_of(cap) != 0
    if ff == false
      run(repo, ["merge", "--abort"])
    end
    if contains?(shisutemu::stdout_of(cap), "CONFLICT") or
      contains?(shisutemu::stderr_of(cap), "fast-forward")
      raise(
        :conflict,
        "#{ref} into #{repo}: #{trim(shisutemu::stderr_of(cap))}"
      )
    end
    fail(repo, args, cap)
  end
  head_of(repo)
end

def current_branch(repo)
  out(repo, ["symbolic-ref", "--short", "HEAD"])
end

def push(repo, opts)
  checked(opts, [:remote, :branch, :rebase])
  remote = get_or(opts, :remote, "origin")
  branch = get_or(opts, :branch, current_branch(repo))
  cap = run(repo, ["push", remote, branch])
  if shisutemu::status_of(cap) != 0
    if contains?(shisutemu::stderr_of(cap), "rejected") == false
      fail(repo, ["push", remote, branch], cap)
    end
    if get_or(opts, :rebase, true) == false
      raise(:diverged, "#{branch} on #{remote} has commits #{repo} lacks")
    end
    out(repo, ["fetch", remote])
    rebase = run(repo, ["rebase", "#{remote}/#{branch}"])
    if shisutemu::status_of(rebase) != 0
      run(repo, ["rebase", "--abort"])
      raise(:conflict, "rebasing #{branch} onto #{remote}/#{branch} in #{repo}")
    end
    out(repo, ["push", remote, branch])
  end
  nil
end

def fixture(name)
  path = "/tmp/blue-gitto-#{name}"
  rm_rf(path)
  out(".", ["init", "-q", "-b", "main", path])
  out(path, ["config", "user.name", "Tester"])
  out(path, ["config", "user.email", "tester@example.invalid"])
  path
end

def raised(f)
  f()
  nil
rescue e
  e.kind
end

def save(repo, name, text, message)
  write_file("#{repo}/#{name}", text)
  commit(repo, message, {paths: [name]})
end

test "a repository is read as commits, refs and files"
  r = fixture("read")
  first_commit = save(r, "a.txt", "one\n", "first")
  second = save(r, "a.txt", "two\n", "second")
  assert first_commit.subject == "first"
  assert first_commit.parents == []
  assert second.parents == [first_commit.oid]
  assert second.author == "Tester"
  assert exists?(r, "HEAD") == true
  assert exists?(r, "nope") == false
  assert commit_at(r, "nope").nil?
  assert commit_at(r, "HEAD~1").oid == first_commit.oid
  assert ancestor?(r, first_commit.oid, second.oid) == true
  assert ancestor?(r, second.oid, first_commit.oid) == false
  assert read(r, "a.txt", {}) == "two\n"
  assert read(r, "a.txt", {at: first_commit.oid}) == "one\n"
  assert raised(() -> read(r, "gone.txt", {})) != nil
  assert entries(r, :commits, {limit: 1}) == [second]
  assert map((c) -> c.subject, entries(r, :commits, {})) == ["second", "first"]
  assert diff(r, first_commit.oid, second.oid, {}) ==
    [{path: "a.txt", state: :modified}]
  assert diff(r, first_commit.oid, first_commit.oid, {}) == []
end

test "info reports the branch, the head and the working tree"
  r = fixture("info")
  c = save(r, "a.txt", "one\n", "first")
  i = info(r)
  assert i.branch == "main"
  assert i.head == c.oid
  assert i.ahead == 0
  assert i.behind == 0
  assert i.clean? == true
  write_file("#{r}/b.txt", "new\n")
  j = info(r)
  assert j.clean? == false
  assert j.changes == [{path: "b.txt", state: "??"}]
  assert raised(() -> info("/tmp/blue-gitto-not-a-repo")) != nil
end

test "branches and tags are created once and deleted idempotently"
  r = fixture("refs")
  c = save(r, "a.txt", "one\n", "first")
  assert create(r, "topic", c.oid, {}) == c.oid
  assert create(r, "v1", c.oid, {kind: :tag}) == c.oid
  assert map((b) -> b.name, entries(r, :branches, {})) == ["main", "topic"]
  assert map((t) -> t.name, entries(r, :tags, {})) == ["v1"]
  assert first(entries(r, :branches, {})).current == true
  assert raised(() -> create(r, "topic", c.oid, {})) == :exists
  assert raised(() -> create(r, "other", "no-such-ref", {})) == :not_found
  assert delete(r, "topic").nil?
  assert delete(r, "topic").nil?
  assert delete(r, "refs/tags/v1").nil?
  assert entries(r, :tags, {}) == []
  assert map((b) -> b.name, entries(r, :branches, {})) == ["main"]
end

test "an unknown option or list kind is refused by name"
  r = fixture("options")
  save(r, "a.txt", "one\n", "first")
  assert raised(() -> entries(r, :commits, {limt: 2})) == :bad_option
  assert raised(() -> entries(r, :stashes, {})) == :bad_option
  assert raised(() -> fetch(r, {force: true})) == :bad_option
end

test "commit refuses an empty index and takes an author"
  r = fixture("commit")
  save(r, "a.txt", "one\n", "first")
  assert raised(() -> commit(r, "nothing", {})) == :empty
  write_file("#{r}/b.txt", "two\n")
  c = commit(
    r,
    "all of it",
    {all: true, author: "Other <other@example.invalid>"}
  )
  assert c.author == "Other"
  assert info(r).clean? == true
end

test "clone, fetch, merge and push follow the house rule"
  origin = fixture("origin")
  base = save(origin, "a.txt", "one\n", "first")
  out(origin, ["config", "receive.denyCurrentBranch", "ignore"])
  work = "/tmp/blue-gitto-work"
  rm_rf(work)
  assert clone(origin, work, {}) == work
  out(work, ["config", "user.name", "Tester"])
  out(work, ["config", "user.email", "tester@example.invalid"])
  assert map((x) -> x.name, entries(work, :remotes, {})) == ["origin"]
  assert info(work).head == base.oid
  ahead = save(origin, "a.txt", "two\n", "second")
  assert fetch(work, {}).nil?
  assert info(work).behind == 1
  assert merge(work, "origin/main", {}).oid == ahead.oid
  local = save(work, "b.txt", "local\n", "third")
  assert info(work).ahead == 1
  assert push(work, {}).nil?
  assert commit_at(origin, "main").oid == local.oid
  assert first(entries(work, :worktrees, {})).path == "/private#{work}" or
    first(entries(work, :worktrees, {})).path == work
end

test "a diverged push rebases once and a diverged merge is refused"
  origin = fixture("diverge-origin")
  save(origin, "a.txt", "one\n", "first")
  out(origin, ["config", "receive.denyCurrentBranch", "ignore"])
  work = "/tmp/blue-gitto-diverge-work"
  rm_rf(work)
  clone(origin, work, {})
  out(work, ["config", "user.name", "Tester"])
  out(work, ["config", "user.email", "tester@example.invalid"])
  save(origin, "a.txt", "two\n", "remote")
  save(work, "b.txt", "mine\n", "local")
  fetch(work, {})
  assert raised(() -> merge(work, "origin/main", {})) == :conflict
  assert raised(() -> push(work, {rebase: false})) == :diverged
  assert push(work, {}).nil?
  assert map((c) -> c.subject, entries(origin, :commits, {})) ==
    ["local", "remote", "first"]
end
