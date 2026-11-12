use("retsu", %i[first rest size])

use("shisutemu", %i[blue_exe status_of stderr_of stdout_of])

use(
  "shomei",
  %i[
    content_root_of
    hash_message
    is_hash_hex
    keypair_public
    keypair_secret
    release_note
    release_refusal
    release_tag
    signing_keypair
  ]
)

def keys_default()
  "keys/bidama-release.pub"
end

def hidden?(rel)
  any?((s) -> starts_with?(s, "."), split(rel, "/"))
end

def relative(dir, path)
  join(drop(size(chars(dir)) + 1, chars(path)), "")
end

def content_rows(dir)
  map(
    (p) -> [relative(dir, p), hash_message(read_bytes(p))],
    filter((p) -> not hidden?(relative(dir, p)), walk_dir(dir))
  )
end

def content_root(dir)
  content_root_of(content_rows(dir))
end

def identity(dir)
  manifest = json_read(read_file(path_join(dir, "Bluefile.lock")))["manifest"]
  [manifest["name"], manifest["version"]]
end

def seed_of(path)
  seed = trim(read_file(path))
  if not is_hash_hex(seed)
    raise(:release, "#{path} does not hold a 64-hex seed")
  end
  seed
end

def sign(dir, seed)
  kp = signing_keypair(seed)
  id = identity(dir)
  release_note(
    first(id),
    id[1],
    content_root(dir),
    keypair_secret(kp),
    keypair_public(kp)
  )
end

def trusted_in(text)
  filter(is_hash_hex, map(trim, split(text, line_break)))
end

def trusted_at(path)
  if is_file?(path)
    trusted_in(read_file(path))
  else
    []
  end
end

def verify(dir, note, trusted)
  release_refusal(note, first(identity(dir)), content_root(dir), trusted)
end

def git(repo, args)
  cap = exec_capture("git", "-C", repo, *args)
  if status_of(cap) != 0
    raise(:git, "git #{join(args, " ")}: #{stderr_of(cap)}")
  end
  stdout_of(cap)
end

def tag_note(repo, tag)
  text = git(repo, ["cat-file", "tag", tag])
  join(rest(split(text, unlines(["", ""]))), unlines(["", ""]))
end

def tag(repo, rel, seed, rev)
  dir = path_join(repo, rel)
  id = identity(dir)
  name = release_tag(first(id), id[1])
  note_file = path_join(temp_dir("release-note"), "note")
  write_file(note_file, sign(dir, seed))
  git(repo, ["tag", "-a", name, "-F", note_file, rev])
  name
end

def verify_tag(repo, rel, tag, trusted)
  at = path_join(temp_dir("release-verify"), "tree")
  git(repo, ["worktree", "add", "--detach", at, tag])
  verdict = verify(path_join(at, rel), tag_note(repo, tag), trusted)
  git(repo, ["worktree", "remove", "--force", at])
  verdict
end

def say(verdict)
  if verdict.nil?
    print("verified")
  else
    write_stderr(unlines(["refused #{to_s(first(verdict))}: #{verdict[1]}"]))
    exit_with(1)
  end
end

def main()
  dispatch(argv)
end

def dispatch(args)
  verb = first(args)
  if verb == "content"
    print(content_root(args[1]))
  elsif verb == "sign"
    print(sign(args[1], seed_of(args[2])))
  elsif verb == "verify"
    say(
      verify(args[1], read_file(args[2]), trusted_at(args[3] or keys_default))
    )
  elsif verb == "tag"
    print(tag(args[1], args[2], seed_of(args[3]), args[4] or "HEAD"))
  elsif verb == "verify-tag"
    say(
      verify_tag(args[1], args[2], args[3], trusted_at(args[4] or keys_default))
    )
  else
    write_stderr(
      unlines(
        ["usage: release.b content DIR | sign DIR SEED_FILE | verify DIR NOTE [KEYS] | tag REPO BIDAMA_DIR SEED_FILE [REV] | verify-tag REPO BIDAMA_DIR TAG [KEYS]"]
      )
    )
    exit_with(2)
  end
end

def fixture_bidama(label)
  root = path_join(temp_dir(label), "dist")
  dir = path_join(root, "zed")
  mkdir_p(dir)
  write_file(
    path_join(dir, "Bluefile"),
    unlines(["package(\"zed\", \"0.1.0\")"])
  )
  write_program(
    path_join(dir, "zed.b"),
    unlines(
      [
        "@moduledoc \"\"\"",
        "zed: a fixture.",
        "",
        "    one #=> 1",
        "\"\"\"",
        "",
        "@doc \"\"\"",
        "one: One.",
        "",
        "    one #=> 1",
        "\"\"\"",
        "def one()",
        "  1",
        "end"
      ]
    )
  )
  lock = exec_capture(blue_exe, "lock", dir)
  if status_of(lock) != 0
    raise(:fixture, stderr_of(lock))
  end
  [root, dir]
end

def test_seed(label)
  hash_message("gen/release.b test key: #{label}")
end

test "a signed bidama verifies, an altered file is refused, and restoring it verifies again"
  dir = fixture_bidama("release-alter")[1]
  seed = test_seed("alter")
  trusted = [keypair_public(signing_keypair(seed))]
  note = sign(dir, seed)
  assert verify(dir, note, trusted).nil?
  original = read_file(path_join(dir, "zed.b"))
  write_program(
    path_join(dir, "zed.b"),
    replace(original, join_lines(["  1", "end"]), join_lines(["  2", "end"]))
  )
  refused = verify(dir, note, trusted)
  assert first(refused) == :altered
  write_file(path_join(dir, "extra.json"), "{}")
  write_program(path_join(dir, "zed.b"), original)
  assert first(verify(dir, note, trusted)) == :altered
  rm_rf(path_join(dir, "extra.json"))
  assert verify(dir, note, trusted).nil?
  write_file(path_join(dir, ".scratch"), "ignored")
  assert verify(dir, note, trusted).nil?
end

test "an unprovisioned key file trusts nothing, and a note signed by another key is untrusted"
  dir = fixture_bidama("release-keys")[1]
  note = sign(dir, test_seed("keys"))
  assert first(verify(dir, note, trusted_at("/no/such/keys"))) == :untrusted
  other = [keypair_public(signing_keypair(test_seed("other")))]
  assert first(verify(dir, note, other)) == :untrusted
  assert trusted_in(unlines(["# a comment", other[0], "not-a-key"])) == other
end

test "blue lock records the content root this program computes, for the same tree"
  pair = fixture_bidama("release-agree")
  app = path_join(path_dirname(first(pair)), "app")
  mkdir_p(app)
  write_file(
    path_join(app, "Bluefile"),
    unlines(
      [
        "package(\"the-app\", \"0.1.0\")",
        "needs(\"zed\", \"^0.1\")",
        "verify(%i[contents])"
      ]
    )
  )
  write_program(
    path_join(app, "main.b"),
    unlines(["use(\"zed\", [:one])", "", "one"])
  )
  cap = exec_with_env([["BLUE_PATH", first(pair)]], blue_exe, "lock", app)
  assert status_of(cap) == 0
  locked = json_read(read_file(path_join(app, "Bluefile.lock")))["contents"]
  assert locked["zed"] == content_root(pair[1])
end

test "a release tag carries its note, and the tag verifies against the tree it names"
  pair = fixture_bidama("release-tag")
  repo = first(pair)
  git(repo, %w[init -q])
  git(repo, %w[config user.name t])
  git(repo, %w[config user.email t@t])
  git(repo, %w[config commit.gpgsign false])
  git(repo, %w[config tag.gpgsign false])
  git(repo, %w[add .])
  git(repo, %w[commit -q -m zed])
  seed = test_seed("tag")
  trusted = [keypair_public(signing_keypair(seed))]
  made = tag(repo, "zed", seed, "HEAD")
  assert made == "bidama/zed/v0.1.0"
  assert verify_tag(repo, "zed", made, trusted).nil?
  write_program(
    path_join(repo, "zed/zed.b"),
    unlines(["def one()", "  2", "end"])
  )
  assert first(verify(pair[1], tag_note(repo, made), trusted)) == :altered
  assert verify_tag(repo, "zed", made, trusted).nil?
end
