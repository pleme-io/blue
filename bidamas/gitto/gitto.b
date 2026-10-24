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
    :take_chars,
    :trim
  ]
)

use("retsu", [:first, :is_empty, :last])
use("shisutemu")
use("tesuto", [:scratch])

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

@doc """
exists?: whether the subject is there; in_space("gitto", repo) asks about a ref.
"""
def exists?(repo, ref)
  resolves(repo, ref)
end

@doc """
get: one commit, nil when the ref is absent.
"""
def get(repo, ref, opts?)
  checked(opts, [])
  if resolves(repo, ref)
    commit_of(out(repo, ["log", "-1", commit_format, ref, "--"]))
  end
end

def head_of(repo)
  get(repo, "HEAD")
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

def require_repo(repo)
  if succeeds(repo, ["rev-parse", "--git-dir"]) == false
    raise(:not_found, "#{repo} is not a git repository")
  end
end

@doc """
info: the current state of the subject as a record: in_space("gitto", repo) is the repository's state.
"""
def info(repo)
  require_repo(repo)
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

def limit_args(opts)
  n = get_or(opts, :limit, nil)
  if n.nil?
    []
  else
    ["-n", to_s(n)]
  end
end

@doc """
list: branches, tags, commits, remotes or worktrees, chosen by of:
"""
def list(repo, opts?)
  o = checked(opts, [:of, :limit, :ref])
  require_repo(repo)
  what = get_or(o, :of, :commits)
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
    ref = get_or(o, :ref, "HEAD")
    if resolves(repo, ref)
      map(
        commit_of,
        lines(
          raw(
            repo,
            append(append(["log", commit_format], limit_args(o)), [ref, "--"])
          )
        )
      )
    elsif ref == "HEAD"
      []
    else
      raise(:not_found, "#{ref} in #{repo}")
    end
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
      "list takes of: :branches, :tags, :commits, :remotes or :worktrees, not #{what}"
    )
  end
end

@doc """
read: the whole content of a source, by the source's space: in_space("gitto", repo) reads a file at a ref. Raises :usage when no space owns the subject or the space has no handler.
"""
def read(repo, path, opts?)
  o = checked(opts, [:at])
  at = get_or(o, :at, "HEAD")
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

@doc """
diff: the differences between two values as change records, by the space of a: diff(in_space("gitto", repo), from, to) compares two refs.
"""
def diff(repo, a, b, opts?)
  o = checked(opts, [:paths])
  map(
    change_line,
    lines(
      raw(
        repo,
        append(
          ["diff", "--name-status", "--no-renames", a, b, "--"],
          get_or(o, :paths, [])
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

@doc """
create: add a new entry, refusing to overwrite; in_space("gitto", repo) makes a branch or tag.
"""
def create(repo, key, value, opts?)
  o = checked(opts, [:kind])
  ref = ref_of(key, get_or(o, :kind, :branch))
  if succeeds(repo, ["show-ref", "--verify", "--quiet", ref])
    raise(:exists, "#{ref} in #{repo}")
  end
  if resolves(repo, value) == false
    raise(:not_found, "#{value} in #{repo}")
  end
  out(repo, ["update-ref", ref, "#{value}^{commit}", ""])
  value
end

@doc """
delete: make an entry absent; absent counts as done. A plain map goes to jisho; in_space("gitto", repo) deletes a branch or tag.
"""
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

def commit(repo, message, opts?)
  o = checked(opts, [:paths, :all, :author])
  paths = get_or(o, :paths, [])
  if is_empty(paths) == false
    out(repo, append(["add", "--"], paths))
  end
  if get_or(o, :all, false)
    out(repo, ["add", "-A"])
  end
  if succeeds(repo, ["diff", "--cached", "--quiet"])
    raise(:empty, "nothing staged to commit in #{repo}")
  end
  author = get_or(o, :author, nil)
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

def fetch(repo, opts?)
  o = checked(opts, [:remote, :prune])
  out(
    repo,
    append(
      ["fetch"],
      if get_or(o, :prune, false)
        ["--prune"]
      else
        []
      end,
      [get_or(o, :remote, "origin")]
    )
  )
  nil
end

def clone(url, dir, opts?)
  o = checked(opts, [:branch, :depth])
  branch = get_or(o, :branch, nil)
  depth = get_or(o, :depth, nil)
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

def merge(repo, ref, opts?)
  o = checked(opts, [:fast_forward_only])
  ff = get_or(o, :fast_forward_only, true)
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

def push(repo, opts?)
  o = checked(opts, [:remote, :branch, :rebase])
  remote = get_or(o, :remote, "origin")
  branch = get_or(o, :branch, current_branch(repo))
  cap = run(repo, ["push", remote, branch])
  if shisutemu::status_of(cap) != 0
    if contains?(shisutemu::stderr_of(cap), "rejected") == false
      fail(repo, ["push", remote, branch], cap)
    end
    if get_or(o, :rebase, true) == false
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
  path = "#{scratch}-gitto-#{name}"
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

verb_for("gitto", "exists?", exists?)
verb_for("gitto", "info", info)
verb_for("gitto", "read", read)
verb_for("gitto", "diff", diff)
verb_for("gitto", "create", create)
verb_for("gitto", "delete", delete)

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
  assert get(r, "nope", {}).nil?
  assert get(r, "HEAD~1", {}).oid == first_commit.oid
  assert ancestor?(r, first_commit.oid, second.oid) == true
  assert ancestor?(r, second.oid, first_commit.oid) == false
  assert read(r, "a.txt", {}) == "two\n"
  assert read(r, "a.txt", {at: first_commit.oid}) == "one\n"
  assert raised(() -> read(r, "gone.txt", {})) != nil
  assert gitto::list(r, {of: :commits, limit: 1}) == [second]
  assert map((c) -> c.subject, gitto::list(r, {of: :commits})) ==
    ["second", "first"]
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
  assert map((b) -> b.name, gitto::list(r, {of: :branches})) ==
    ["main", "topic"]
  assert map((t) -> t.name, gitto::list(r, {of: :tags})) == ["v1"]
  assert first(gitto::list(r, {of: :branches})).current == true
  assert raised(() -> create(r, "topic", c.oid, {})) == :exists
  assert raised(() -> create(r, "other", "no-such-ref", {})) == :not_found
  assert delete(r, "topic").nil?
  assert delete(r, "topic").nil?
  assert delete(r, "refs/tags/v1").nil?
  assert gitto::list(r, {of: :tags}) == []
  assert map((b) -> b.name, gitto::list(r, {of: :branches})) == ["main"]
end

test "an unknown option or list kind is refused by name"
  r = fixture("options")
  save(r, "a.txt", "one\n", "first")
  assert raised(() -> gitto::list(r, {of: :commits, limt: 2})) == :bad_option
  assert raised(() -> gitto::list(r, {of: :stashes})) == :bad_option
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
  work = "#{scratch}-gitto-work"
  rm_rf(work)
  assert clone(origin, work, {}) == work
  out(work, ["config", "user.name", "Tester"])
  out(work, ["config", "user.email", "tester@example.invalid"])
  assert map((x) -> x.name, gitto::list(work, {of: :remotes})) == ["origin"]
  assert info(work).head == base.oid
  ahead = save(origin, "a.txt", "two\n", "second")
  assert fetch(work, {}).nil?
  assert info(work).behind == 1
  assert merge(work, "origin/main", {}).oid == ahead.oid
  local = save(work, "b.txt", "local\n", "third")
  assert info(work).ahead == 1
  assert push(work, {}).nil?
  assert get(origin, "main", {}).oid == local.oid
  assert first(gitto::list(work, {of: :worktrees})).path == "/private#{work}" or
    first(gitto::list(work, {of: :worktrees})).path == work
end

test "a diverged push rebases once and a diverged merge is refused"
  origin = fixture("diverge-origin")
  save(origin, "a.txt", "one\n", "first")
  out(origin, ["config", "receive.denyCurrentBranch", "ignore"])
  work = "#{scratch}-gitto-diverge-work"
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
  assert map((c) -> c.subject, gitto::list(origin, {of: :commits})) ==
    ["local", "remote", "first"]
end

test "get returns one commit by ref or oid and nil when absent"
  r = fixture("get")
  assert get(r, "HEAD", {}).nil?
  first_commit = save(r, "a.txt", "one\n", "first")
  second = save(r, "a.txt", "two\n", "second")
  assert get(r, "HEAD", {}) == second
  assert get(r, "main", {}) == second
  assert get(r, first_commit.oid, {}) == first_commit
  assert get(r, "HEAD~1", {}) == first_commit
  assert get(r, "HEAD~5", {}).nil?
  assert get(r, "nope", {}).nil?
  assert get("/tmp/blue-gitto-not-a-repo-at-all", "HEAD", {}).nil?
end

test "get refuses an option it does not take"
  r = fixture("get-option")
  save(r, "a.txt", "one\n", "first")
  assert raised(() -> get(r, "HEAD", {at: "main"})) == :bad_option
end

test "list defaults to every commit, newest first, and takes of, limit and ref"
  r = fixture("list-commits")
  first_commit = save(r, "a.txt", "one\n", "first")
  save(r, "a.txt", "two\n", "second")
  third = save(r, "a.txt", "three\n", "third")
  assert map((c) -> c.subject, gitto::list(r, {})) ==
    ["third", "second", "first"]
  assert gitto::list(r, {}) == gitto::list(r, {of: :commits})
  assert gitto::list(r, {limit: 1}) == [third]
  assert map((c) -> c.subject, gitto::list(r, {limit: 2})) ==
    ["third", "second"]
  assert map((c) -> c.subject, gitto::list(r, {ref: first_commit.oid})) ==
    ["first"]
  assert gitto::list(r, {limit: 0}) == []
end

test "list reads every commit past the old default page of fifty"
  r = fixture("list-many")
  map((i) -> save(r, "a.txt", "#{i}\n", "c#{i}"), range(0, 55))
  assert length(gitto::list(r, {})) == 55
  assert length(gitto::list(r, {limit: 7})) == 7
end

test "list reads branches, tags, remotes and worktrees by of"
  r = fixture("list-refs")
  head = save(r, "a.txt", "one\n", "first")
  out(r, ["branch", "topic"])
  out(r, ["tag", "v1"])
  assert map((b) -> b.name, gitto::list(r, {of: :branches})) ==
    ["main", "topic"]
  assert map((t) -> t.name, gitto::list(r, {of: :tags})) == ["v1"]
  assert first(gitto::list(r, {of: :tags})).oid == head.oid
  assert gitto::list(r, {of: :remotes}) == []
  assert length(gitto::list(r, {of: :worktrees})) == 1
end

test "list of an empty repository is empty, and of a missing one is not_found"
  r = fixture("list-empty")
  assert gitto::list(r, {}) == []
  assert gitto::list(r, {of: :branches}) == []
  assert gitto::list(r, {of: :tags}) == []
  assert raised(() -> gitto::list("/tmp/blue-gitto-not-a-repo-at-all", {})) ==
    :not_found
  assert raised(() -> gitto::list(r, {ref: "nope"})) == :not_found
end

test "list refuses an unknown of and an unknown option"
  r = fixture("list-bad")
  save(r, "a.txt", "one\n", "first")
  assert raised(() -> gitto::list(r, {of: :stashes})) == :bad_option
  assert raised(() -> gitto::list(r, {limt: 2})) == :bad_option
end

test "each verb runs with its options left out as it runs with an empty record"
  r = fixture("optional")
  first_commit = save(r, "a.txt", "one\n", "first")
  second = save(r, "a.txt", "two\n", "second")
  assert get(r, "HEAD") == second
  assert get(r, "HEAD") == get(r, "HEAD", {})
  assert get(r, "HEAD", nil) == second
  assert get(r, "nope").nil?
  assert gitto::list(r) == gitto::list(r, {})
  assert gitto::list(r, nil) == gitto::list(r, {})
  assert map((c) -> c.subject, gitto::list(r)) == ["second", "first"]
  assert read(r, "a.txt") == "two\n"
  assert read(r, "a.txt", nil) == "two\n"
  assert diff(r, first_commit.oid, second.oid) ==
    [{path: "a.txt", state: :modified}]
  assert diff(r, first_commit.oid, second.oid, nil) ==
    diff(r, first_commit.oid, second.oid, {})
  assert create(r, "topic", second.oid) == second.oid
  assert raised(() -> create(r, "topic", second.oid)) == :exists
  assert create(r, "other", second.oid, nil) == second.oid
  assert raised(() -> commit(r, "nothing")) == :empty
  assert raised(() -> commit(r, "nothing", nil)) == :empty
end

test "an option given to a verb with options left out is still checked"
  r = fixture("optional-bad")
  save(r, "a.txt", "one\n", "first")
  assert raised(() -> get(r, "HEAD", {at: "main"})) == :bad_option
  assert raised(() -> read(r, "a.txt", {when: 1})) == :bad_option
  assert raised(() -> fetch(r, {force: true})) == :bad_option
  assert raised(() -> get(r, "HEAD", 1)) != nil
end

test "clone, fetch, merge and push run with their options left out"
  origin = fixture("optional-origin")
  base = save(origin, "a.txt", "one\n", "first")
  out(origin, ["config", "receive.denyCurrentBranch", "ignore"])
  work = "#{scratch}-gitto-optional-work"
  rm_rf(work)
  assert clone(origin, work) == work
  out(work, ["config", "user.name", "Tester"])
  out(work, ["config", "user.email", "tester@example.invalid"])
  assert info(work).head == base.oid
  ahead = save(origin, "a.txt", "two\n", "second")
  assert fetch(work).nil?
  assert merge(work, "origin/main").oid == ahead.oid
  local = save(work, "b.txt", "local\n", "third")
  assert push(work).nil?
  assert get(origin, "main").oid == local.oid
end

test "the master verbs reach gitto for a subject tagged with its space"
  r = fixture("dispatch")
  c = save(r, "a.txt", "one\n", "first")
  d = save(r, "a.txt", "two\n", "second")
  s = in_space("gitto", r)
  assert blue::info(s) == info(r)
  assert blue::exists?(s, c.oid) == true
  assert blue::exists?(s, "no-such-ref") == false
  assert blue::read(s, "a.txt", {}) == read(r, "a.txt", {})
  assert blue::diff(s, c.oid, d.oid, {}) == [{path: "a.txt", state: :modified}]
  assert blue::diff(s, c.oid, c.oid) == []
  assert blue::create(s, "topic", c.oid, {}) == c.oid
  assert blue::delete(s, "topic").nil?
  assert blue::delete(s, "topic").nil?
  assert space_of(s) == "gitto"
end

test "a master verb on a gitto subject raises what gitto raises"
  r = fixture("dispatch-raise")
  c = save(r, "a.txt", "one\n", "first")
  s = in_space("gitto", r)
  assert raised(() -> blue::create(s, "other", "no-such-ref", {})) == :not_found
  assert blue::create(s, "topic", c.oid, {}) == c.oid
  assert raised(() -> blue::create(s, "topic", c.oid, {})) == :exists
  assert raised(
    () -> blue::info(in_space("gitto", "/tmp/blue-gitto-not-a-repo"))
  ) != nil
  assert raised(() -> has?(s, "topic")) == :usage
  assert raised(() -> need(s, "topic")) == :usage
end
