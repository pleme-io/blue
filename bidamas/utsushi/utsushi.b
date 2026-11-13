@moduledoc """
utsushi (写し, a transcription) — a part of a repository's history, shown as a history of its own: a lens picks the part, and each commit is written again over the part's tree, with its author, committer and message unchanged, so the same lens over the same commit gives the same commit id on every machine (docs/UTSUSHI.md).

    sub("a/b") #=> {lens: :sub, path: "a/b"}
"""

use("gitto")
use("kyohi")
use("moji", %i[drop_chars starts_with take_chars trim])
use("retsu", %i[first is_empty last])
use("shisutemu")

@doc """
sub: The lens that keeps only the tree at `path`, which becomes the root.

    sub("/a/b/") #=> {lens: :sub, path: "a/b"}
"""
def sub(path)
  {lens: :sub, path: clean(path)}
end

@doc """
prefix: The lens that moves the whole tree under `path`.

    prefix("lib/x") #=> {lens: :prefix, path: "lib/x"}
"""
def prefix(path)
  {lens: :prefix, path: clean(path)}
end

@doc """
chain: The lenses applied in order, each to what the one before it kept.

    chain([sub("a"), prefix("b")])[:lens] #=> :chain
"""
def chain(lenses)
  {lens: :chain, parts: lenses}
end

@doc """
compose: The trees of several lenses side by side. Their output roots must not overlap, so each file of the result has one source and the result can be written back; an overlap is refused, naming both roots.

    compose([prefix("x"), prefix("y")])[:lens] #=> :compose
"""
def compose(lenses)
  roots = map(out_root, lenses)
  clashes = filter(
    (pair) -> overlap?(pair[0], pair[1]),
    retsu::flat_map(
      range(retsu::size(roots)),
      (i) -> map((j) -> [roots[i], roots[j]], range(i + 1, retsu::size(roots)))
    )
  )
  if not is_empty(clashes)
    c = first(clashes)
    raise(
      :lens_refused,
      "compose: the output roots `#{shown_root(c[0])}` and `#{shown_root(c[1])}` overlap, so a file would have two sources"
    )
  end
  {lens: :compose, parts: lenses}
end

@doc """
shown_root is an output root as a refusal shows it: the whole tree is `/`.

    shown_root("") #=> "/"
"""
def shown_root(r)
  if r == ""
    "/"
  else
    r
  end
end

@doc """
clean is a lens path without empty segments, refusing one that names no directory or leaves the tree.

    clean("/a//b/") #=> "a/b"
"""
def clean(path)
  segs = filter((s) -> s != "", split(path, "/"))
  if is_empty(segs)
    raise(:lens_refused, "a lens path names no directory: `#{path}`")
  end
  if any?((s) -> s == "." or s == "..", segs)
    raise(:lens_refused, "a lens path stays inside the tree: `#{path}`")
  end
  join(segs, "/")
end

@doc """
out_root is where a lens puts what it keeps: a prefix's path, or the whole tree.

    out_root(prefix("x")) #=> "x"
"""
def out_root(lens)
  if lens[:lens] == :prefix
    lens[:path]
  elsif lens[:lens] == :chain and not is_empty(lens[:parts])
    out_root(last(lens[:parts]))
  else
    ""
  end
end

@doc """
under? tells whether path a is b or inside it.

    under?("a/b", "a") #=> true
"""
def under?(a, b)
  a == b or starts_with(a, "#{b}/")
end

@doc """
overlap? tells whether two output roots can hold the same file.

    overlap?("a", "b") #=> false
"""
def overlap?(a, b)
  a == "" or b == "" or under?(a, b) or under?(b, a)
end

@doc """
parse: A lens from Josh's filter text: `:/a/b` is `sub("a/b")`, `:prefix=x` is `prefix("x")`, and filters written one after another are a chain. Any other filter is refused by name.

    parse(":/a/b:prefix=x") #=> chain([sub("a/b"), prefix("x")])
"""
def parse(spec)
  parts = filter((p) -> p != "", split(spec, ":"))
  lenses = map(parse_one, parts)
  if retsu::size(lenses) == 1
    first(lenses)
  else
    chain(lenses)
  end
end

@doc """
parse_one is the lens one Josh filter names, without its leading `:`.

    parse_one("prefix=x") #=> prefix("x")
"""
def parse_one(part)
  if starts_with(part, "/")
    sub(drop_chars(part, 1))
  elsif starts_with(part, "prefix=")
    prefix(drop_chars(part, 7))
  else
    raise(
      :lens_refused,
      "the filter `:#{part}` is not built (built: :/path, :prefix=path)"
    )
  end
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
git_stdin runs git in `repo` with `input` on its standard input and gives its trimmed output.

    git_stdin(josh_fixture("doc-stdin"), "", ["mktree"]) #=> "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
"""
def git_stdin(repo, input, args)
  cap = exec_with_stdin(input, "git", "-C", repo, *args)
  if shisutemu::status_of(cap) != 0
    gitto::fail(repo, args, cap)
  end
  trim(shisutemu::stdout_of(cap))
end

@doc """
entry_of is one `git ls-tree` line as its mode, type, id and name.

    entry_of("100644 blob abc\tf")[:name] #=> "f"
"""
def entry_of(line)
  tab = text_index(line, "\t", 0)
  meta = split(take_chars(line, tab), " ")
  {mode: meta[0], type: meta[1], id: meta[2], name: drop_chars(line, tab + 1)}
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
entries is every entry of one tree, read with `git ls-tree`.

    map((e) -> e[:name], entries(josh_fixture("doc-entries"), "main")) #=> ["a", "top.txt"]
"""
def entries(repo, tree)
  map(
    entry_of,
    filter(
      (l) -> l != "",
      split(gitto::raw(repo, ["ls-tree", tree]), line_break)
    )
  )
end

@doc """
entry_line is an entry as the `git mktree` line that writes it.

    entry_line({mode: "100644", type: "blob", id: "abc", name: "f"}) #=> "100644 blob abc\tf"
"""
def entry_line(e)
  "#{e[:mode]} #{e[:type]} #{e[:id]}\t#{e[:name]}"
end

@doc """
mktree writes a tree of these entries and gives its id.

    mktree(josh_fixture("doc-mktree"), []) #=> "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
"""
def mktree(repo, es)
  git_stdin(repo, unlines(map(entry_line, es)), ["mktree"])
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
subtree is the id of the directory at `path` in a tree, or nil when there is none there.

    subtree(josh_fixture("doc-subtree"), "main", "nowhere") #=> nil
"""
def subtree(repo, tree, path)
  found = filter(
    (l) -> l != "",
    split(gitto::raw(repo, ["ls-tree", tree, path]), line_break)
  )
  if is_empty(found)
    nil
  else
    e = entry_of(first(found))
    if e[:type] == "tree" and e[:name] == path
      e[:id]
    end
  end
end

@doc """
wrap is a new tree that holds `tree` at `path`.

    length(wrap(josh_fixture("doc-wrap"), "4b825dc642cb6eb9a060e54bf8d69288fbee4904", "a/b")) #=> 40
"""
def wrap(repo, tree, path)
  reduce(
    fn(t, seg)
      mktree(repo, [{mode: "040000", type: "tree", id: t, name: seg}])
    end,
    tree,
    reverse(split(path, "/"))
  )
end

@doc """
merge_trees is one tree holding the entries of both, refusing a name that both hold as a file.

    merge_trees(josh_fixture("doc-merge"), "4b825dc642cb6eb9a060e54bf8d69288fbee4904", "4b825dc642cb6eb9a060e54bf8d69288fbee4904") #=> "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
"""
def merge_trees(repo, a, b)
  ea = entries(repo, a)
  eb = entries(repo, b)
  names = map((e) -> e[:name], ea)
  merged = map(
    fn(e)
      other = filter((x) -> x[:name] == e[:name], eb)
      if is_empty(other)
        e
      elsif e[:type] == "tree" and first(other)[:type] == "tree"
        assoc(e, :id, merge_trees(repo, e[:id], first(other)[:id]))
      else
        raise(:lens_refused, "compose: `#{e[:name]}` comes from two lenses")
      end
    end,
    ea
  )
  mktree(repo, append(merged, filter((e) -> not member?(e[:name], names), eb)))
end

@doc """
keep: The tree a lens keeps of `tree`, or nil when it keeps nothing.

    keep(josh_fixture("doc-keep"), sub("nowhere"), "main") #=> nil
"""
def keep(repo, lens, tree)
  if tree.nil?
    nil
  elsif lens[:lens] == :sub
    subtree(repo, tree, lens[:path])
  elsif lens[:lens] == :prefix
    wrap(repo, tree, lens[:path])
  elsif lens[:lens] == :chain
    reduce((t, l) -> keep(repo, l, t), tree, lens[:parts])
  else
    kept = filter(
      (t) -> t != nil,
      map((l) -> keep(repo, l, tree), lens[:parts])
    )
    if is_empty(kept)
      nil
    else
      reduce((x, y) -> merge_trees(repo, x, y), first(kept), drop(1, kept))
    end
  end
end

@doc """
person is an author or committer header's name, email and date.

    person("t <t@x> 1700000000 +0000")[:email] #=> "t@x"
"""
def person(rest)
  lt = text_index(rest, " <", 0)
  gt = text_index(rest, "> ", 0)
  {
    name: take_chars(rest, lt),
    email: take_chars(drop_chars(rest, lt + 2), gt - lt - 2),
    date: drop_chars(rest, gt + 2)
  }
end

@doc """
header_value is the value of a commit header line, or nil when the commit has none.

    header_value(["tree abc", "author x"], "tree") #=> "abc"
"""
def header_value(lines, key)
  found = filter((l) -> starts_with(l, "#{key} "), lines)
  if is_empty(found)
    nil
  else
    drop_chars(first(found), length(key) + 1)
  end
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
commit_parts is a commit's tree, author, committer, signature flag and exact message.

    commit_parts(josh_fixture("doc-parts"), "main")[:message] #=> "two files\n"
"""
def commit_parts(repo, c)
  text = gitto::raw(repo, ["cat-file", "commit", c])
  cut = text_index(text, unlines(["", ""]), 0)
  head = split(take_chars(text, cut), line_break)
  if header_value(head, "encoding") != nil
    raise(:lens_refused, "commit #{c} declares an encoding, which is not built")
  end
  {
    tree: header_value(head, "tree"),
    author: person(header_value(head, "author")),
    committer: person(header_value(head, "committer")),
    signed: header_value(head, "gpgsig") != nil,
    message: drop_chars(text, cut + 2)
  }
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
commit_tree writes a commit of `tree` on `parents` with the author, committer and message of `parts`, and gives its id.

    length(commit_tree(josh_fixture("doc-commit"), path_join(getenv("TMPDIR") or "/tmp", "utsushi-doc-msg"), "4b825dc642cb6eb9a060e54bf8d69288fbee4904", [], commit_parts(josh_fixture("doc-commit-parts"), "main"))) #=> 40
"""
def commit_tree(repo, msg_file, tree, parents, parts)
  write_file(msg_file, parts[:message])
  a = parts[:author]
  c = parts[:committer]
  args = append(
    append(["commit-tree", tree], retsu::flat_map(parents, (p) -> ["-p", p])),
    ["-F", msg_file]
  )
  cap = exec_with_env(
    [
      %w[GIT_TERMINAL_PROMPT 0],
      %w[LC_ALL C],
      ["GIT_AUTHOR_NAME", a[:name]],
      ["GIT_AUTHOR_EMAIL", a[:email]],
      ["GIT_AUTHOR_DATE", a[:date]],
      ["GIT_COMMITTER_NAME", c[:name]],
      ["GIT_COMMITTER_EMAIL", c[:email]],
      ["GIT_COMMITTER_DATE", c[:date]]
    ],
    "git",
    "-C",
    repo,
    *args
  )
  if shisutemu::status_of(cap) != 0
    gitto::fail(repo, args, cap)
  end
  trim(shisutemu::stdout_of(cap))
end

@doc """
check_policy refuses a projection that names no signature policy, or one that is not built.

    lens_refused?(() -> check_policy({})) #=> true
"""
def check_policy(opts)
  policy = opts[:signatures]
  if policy.nil?
    raise(
      :lens_refused,
      "a split names its signature policy: {signatures: :drop}"
    )
  end
  if policy != :drop
    raise(
      :lens_refused,
      "the signature policy #{to_s(policy)} is not built (built: :drop)"
    )
  end
end

@doc """
step projects one commit, given as its `rev-list --parents` row: written again, mapped to a parent when its tree did not change, or dropped when the lens keeps nothing of it.

    step(josh_fixture("doc-step"), sub("nowhere"), "unused", {map: {}, trees: {}, written: 0, signed: 0}, ["917c1f56804c077576931b6c8f59e2ae38fd4539"])[:written] #=> 0
"""
def step(repo, lens, msg_file, state, row)
  c = first(row)
  parts = commit_parts(repo, c)
  t = keep(repo, lens, parts[:tree])
  mapped = distinct(
    filter((p) -> p != nil, map((p) -> get(state[:map], p), drop(1, row)))
  )
  made = if t.nil?
    first(mapped)
  elsif retsu::size(mapped) == 1 and get(state[:trees], first(mapped)) == t
    first(mapped)
  else
    commit_tree(repo, msg_file, t, mapped, parts)
  end
  {
    map: assoc(state[:map], c, made),
    trees: if made.nil?
      state[:trees]
    else
      assoc(
        state[:trees],
        made,
        if t.nil?
          get(state[:trees], made)
        else
          t
        end
      )
    end,
    written: if made != nil and not member?(made, mapped)
      state[:written] + 1
    else
      state[:written]
    end,
    signed: if parts[:signed]
      state[:signed] + 1
    else
      state[:signed]
    end
  }
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
project: The history of `source` seen through `lens`, written to the ref `target`. Returns the new head (nil when the lens kept nothing), how many commits were read, how many were written, and how many signatures were dropped. `opts` names the signature policy, and only `{signatures: :drop}` is built: a rewritten commit's old signature cannot verify.

    project(josh_fixture("doc-project"), sub("a/b"), "main", "refs/doc", DROP)[:written] #=> 2
"""
def project(repo, lens, source, target, opts)
  check_policy(opts)
  rows = map(
    (l) -> split(l, " "),
    filter(
      (l) -> l != "",
      split(
        gitto::raw(
          repo,
          ["rev-list", "--topo-order", "--reverse", "--parents", source]
        ),
        line_break
      )
    )
  )
  msg_file = path_join(
    gitto::out(repo, %w[rev-parse --absolute-git-dir]),
    "UTSUSHI_MSG"
  )
  start = {map: {}, trees: {}, written: 0, signed: 0}
  final = reduce((s, row) -> step(repo, lens, msg_file, s, row), start, rows)
  tip = gitto::out(repo, ["rev-parse", source])
  head = get(final[:map], tip)
  if head != nil
    gitto::out(repo, ["update-ref", target, head])
  end
  {
    head:,
    read: retsu::size(rows),
    written: final[:written],
    signatures_dropped: final[:signed]
  }
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
at_fixed_time runs git in `repo` as the fixture's author and committer at 1700000000 +0000, so the commits it writes have the same ids on every machine.

    at_fixed_time(josh_fixture("doc-time"), ["status", "--short"]) #=> nil
"""
def at_fixed_time(repo, args)
  cap = exec_with_env(
    [
      %w[GIT_AUTHOR_DATE 1700000000+0000],
      %w[GIT_COMMITTER_DATE 1700000000+0000],
      %w[GIT_AUTHOR_NAME t],
      %w[GIT_AUTHOR_EMAIL t@example.invalid],
      %w[GIT_COMMITTER_NAME t],
      %w[GIT_COMMITTER_EMAIL t@example.invalid]
    ],
    "git",
    "-C",
    repo,
    *args
  )
  if shisutemu::status_of(cap) != 0
    gitto::fail(repo, args, cap)
  end
end

@doc """
fixed_commit writes `files` as [path, text] pairs and commits them at the fixed time.

    fixed_commit(josh_fixture("doc-fixed"), [["n.txt", "n"]], "n") #=> nil
"""
def fixed_commit(repo, files, message)
  map((f) -> write_file(path_join(repo, f[0]), f[1]), files)
  at_fixed_time(repo, %w[add -A])
  at_fixed_time(repo, ["commit", "-q", "-m", message])
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
josh_fixture is a fresh repository holding the four fixed-time commits the Josh ids were recorded on.

    first(log_of(josh_fixture("doc-josh"), "main")) #=> "917c1f56804c077576931b6c8f59e2ae38fd4539"
"""
def josh_fixture(name)
  r = gitto::fixture(name)
  mkdir_p(path_join(r, "a/b"))
  fixed_commit(r, [["top.txt", unlines(["r"])]], "root, no sub yet")
  fixed_commit(r, [["a/b/one", unlines(["1"])]], "add a/b/one")
  fixed_commit(r, [["top.txt", unlines(["t2"])]], "touch only top")
  fixed_commit(
    r,
    [["a/b/two", unlines(["2"])], ["a/x", unlines(["x"])]],
    "two files"
  )
  r
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
log_of is the commit ids reachable from `ref`, newest first.

    length(log_of(josh_fixture("doc-log"), "main")) #=> 4
"""
def log_of(repo, ref)
  filter(
    (l) -> l != "",
    split(gitto::raw(repo, ["log", "--format=%H", ref]), line_break)
  )
end

@doc """
DROP is the signature policy that drops a rewritten commit's signature.

    DROP #=> {signatures: :drop}
"""
DROP = {signatures: :drop}

@doc """
lens_refused? tells whether calling f raises `:lens_refused`.

    lens_refused?(() -> sub("/")) #=> true
"""
def lens_refused?(f)
  kyohi::raised(f) == :lens_refused
end

test "the fixture is the one the Josh ids were recorded on"
  r = josh_fixture("utsushi-base")
  assert first(log_of(r, "main")) == "917c1f5" or
    starts_with(first(log_of(r, "main")), "917c1f5")
end

test "sub gives Josh's commit ids: unchanged and empty commits drop out"
  r = josh_fixture("utsushi-sub")
  out = project(r, parse(":/a/b"), "main", "refs/utsushi/sub", DROP)
  assert log_of(r, "refs/utsushi/sub") ==
    %w[
      6f11a1fc9e3ca6fea56184bef03c41a4196a3267
      66c01049f2a39d336b7c44acd1988893b8bb1512
    ]
  assert out[:read] == 4
  assert out[:written] == 2
end

test "prefix gives Josh's commit ids: every commit is kept"
  r = josh_fixture("utsushi-prefix")
  project(r, parse(":prefix=lib/x"), "main", "refs/utsushi/prefix", DROP)
  assert log_of(r, "refs/utsushi/prefix") ==
    %w[
      c34c7e046b5a1b72b8629f58c263829effdf3ea8
      eedc8ecba26ce5f7e4a193ea63891e5e142d501d
      95565941c32bc92bfa4fce5104fc3ece26da6a08
      db0e63d6dfa90165be51f09459de069e9a7c9058
    ]
end

test "the same lens twice gives the same head"
  r = josh_fixture("utsushi-again")
  one = project(r, sub("a/b"), "main", "refs/utsushi/one", DROP)
  two = project(r, sub("a/b"), "main", "refs/utsushi/two", DROP)
  assert one[:head] == two[:head]
end

test "a chain moves a subtree under a new root"
  r = josh_fixture("utsushi-chain")
  out = project(
    r,
    parse(":/a/b:prefix=lib"),
    "main",
    "refs/utsushi/chain",
    DROP
  )
  files = split(
    trim(gitto::raw(r, ["ls-tree", "-r", "--name-only", out[:head]])),
    line_break
  )
  assert files == %w[lib/one lib/two]
end

test "compose puts disjoint lenses side by side and refuses an overlap"
  r = josh_fixture("utsushi-compose")
  lens = compose([chain([sub("a/b"), prefix("lib/b")]), prefix("lib/all")])
  out = project(r, lens, "main", "refs/utsushi/compose", DROP)
  files = split(
    trim(gitto::raw(r, ["ls-tree", "-r", "--name-only", out[:head]])),
    line_break
  )
  assert member?("lib/b/one", files)
  assert member?("lib/all/a/x", files)
  assert lens_refused?(() -> compose([sub("a"), prefix("x")]))
  assert lens_refused?(() -> compose([prefix("lib"), prefix("lib/b")]))
end

test "a lens path names a directory inside the tree"
  assert lens_refused?(() -> sub("/"))
  assert lens_refused?(() -> sub("a/../b"))
  assert lens_refused?(() -> parse(":exclude[a]"))
end

test "a projection names its signature policy, and only drop is built"
  r = josh_fixture("utsushi-policy")
  assert lens_refused?(() -> project(r, sub("a/b"), "main", "refs/x", {}))
  assert lens_refused?(
    () -> project(r, sub("a/b"), "main", "refs/x", {signatures: :re_sign})
  )
end

test "a lens that keeps nothing writes no ref"
  r = josh_fixture("utsushi-none")
  out = project(r, sub("nowhere"), "main", "refs/utsushi/none", DROP)
  assert out[:head].nil?
  assert not gitto::resolves(r, "refs/utsushi/none")
end
