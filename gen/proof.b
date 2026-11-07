use("retsu", [:first])
use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
notes_ref: The git notes ref a suite proof lives under, one note per commit.

    notes_ref #=> "refs/notes/blue-suite"
"""
def notes_ref()
  "refs/notes/blue-suite"
end

@doc """
suite_words: The command a proof stands for: the whole workspace suite but the
wasm crate, the run the operator makes before every land.

    first(suite_words) #=> "env"
"""
def suite_words()
  %w[
    env
    CARGO_BUILD_JOBS=8
    nix
    develop
    -c
    cargo
    test
    --workspace
    --exclude
    blue-lang-wasm
  ]
end

@doc """
suite_command: The command a proof stands for, as one line of text.

    suite_command #=> "CARGO_BUILD_JOBS=8 nix develop -c cargo test --workspace --exclude blue-lang-wasm"
"""
def suite_command()
  join(drop(1, suite_words), " ")
end

@doc """
binaries_in: The test binaries in `cargo test --no-run` output: cargo names
each with one `Executable` line.

    binaries_in(unlines(["  Executable unittests src/lib.rs (a)", "  Executable tests/x.rs (b)"])) #=> 2
    binaries_in(unlines(["   Compiling blue v0.1.0"])) #=> 0
"""
def binaries_in(text)
  count(
    filter((l) -> starts_with?(trim(l), "Executable "), split(text, line_break))
  )
end

@doc """
note_for: The proof a green run leaves: the tree it ran on, the git blob of each
lock, the command, the passing test binaries, the toolchain and the time.

    note_for("t", "f", "c", 3, "rustc 1.0", "now")[:tree] #=> "t"
"""
def note_for(tree, flake, cargo, binaries, rustc, at)
  {
    schema: "blue-suite/1",
    tree:,
    flake_lock: flake,
    cargo_lock: cargo,
    command: suite_command,
    binaries:,
    rustc:,
    at:
  }
end

@doc """
proof_gap: Why a note proves nothing for a commit, or nil when it proves the
suite ran green on that commit's tree with its locks. A missing note, one that
is not JSON, another schema and each differing hash are each a gap.

    proof_gap(nil, "t", "f", "c") #=> "the commit carries no refs/notes/blue-suite note"
    proof_gap("{", "t", "f", "c") #=> "the note is not JSON"
"""
def proof_gap(text, tree, flake, cargo)
  note = if text.nil? or trim(text) == ""
    nil
  else
    json_parse(text) rescue :unreadable
  end
  schema = if not note.nil? and note != :unreadable
    json_get(note, :schema) rescue nil
  end
  if note.nil?
    "the commit carries no #{notes_ref} note"
  elsif note == :unreadable
    "the note is not JSON"
  elsif schema != "blue-suite/1"
    "the note is no blue-suite/1 proof"
  elsif json_get(note, :tree) != tree
    "the note proves tree #{to_s(json_get(note, :tree))}, the commit's is #{tree}"
  elsif json_get(note, :flake_lock) != flake
    "the note's flake.lock is #{to_s(json_get(note, :flake_lock))}, the commit's is #{flake}"
  elsif json_get(note, :cargo_lock) != cargo
    "the note's Cargo.lock is #{to_s(json_get(note, :cargo_lock))}, the commit's is #{cargo}"
  end
end

def say(line)
  write_stderr(unlines(["proof: #{line}"]))
end

def git(args)
  trim(stdout_of(exec_capture("git", *args)))
end

def fetch_notes()
  exec_capture("git", "fetch", "-q", "origin", "+#{notes_ref}:#{notes_ref}")
end

def note_of(rev)
  cap = exec_capture("git", "notes", "--ref=blue-suite", "show", rev)
  if status_of(cap) == 0
    stdout_of(cap)
  end
end

def gap_at(rev)
  proof_gap(
    note_of(rev),
    git(["rev-parse", "#{rev}^{tree}"]),
    git(["rev-parse", "#{rev}:flake.lock"]),
    git(["rev-parse", "#{rev}:Cargo.lock"])
  )
end

@doc """
verify: Print `true` when the commit carries a proof of its own tree and locks,
else `false`, and the gap on stderr. It fetches the notes first; it exits 0
either way, so CI reads the answer rather than a status.
"""
def verify(rev)
  fetch_notes
  gap = gap_at(rev)
  if gap.nil?
    write_stdout("true")
  else
    say(gap)
    write_stdout("false")
  end
end

def clean?()
  git(%w[status --porcelain --untracked-files=no]) == ""
end

def run_suite()
  if exec_check(*suite_words) != 0
    say("the suite is red; no proof is written")
    exit_with(1)
  end
  built = exec_capture(*append(suite_words, ["--no-run"]))
  rustc = trim(
    stdout_of(exec_capture("nix", "develop", "-c", "rustc", "--version"))
  )
  {binaries: binaries_in(stderr_of(built)), rustc:}
end

def push_notes(left)
  if exec_check("git", "push", "-q", "origin", notes_ref) == 0
    0
  elsif left == 0
    1
  else
    say("the notes ref moved on origin; fetching it and adding the note again")
    note = note_of("HEAD")
    fetch_notes
    exec_check(
      "git",
      "notes",
      "--ref=blue-suite",
      "add",
      "-f",
      "-m",
      note,
      "HEAD"
    )
    push_notes(left - 1)
  end
end

@doc """
prove: Run the suite on HEAD and, when green, note the proof on HEAD under
refs/notes/blue-suite and push it. A HEAD that already carries a proof of its
tree is not run again. Tracked changes stop it: the proof names the tree it ran.
"""
def prove()
  if not clean?
    say("tracked files differ from HEAD; commit them, since the proof names HEAD's tree")
    exit_with(1)
  end
  fetch_notes
  tree = git(%w[rev-parse HEAD^{tree}])
  if gap_at("HEAD").nil?
    say("HEAD already carries a proof of tree #{tree}")
  else
    ran = run_suite
    if not clean? or git(%w[rev-parse HEAD^{tree}]) != tree
      say("HEAD moved while the suite ran; prove the new HEAD")
      exit_with(1)
    end
    note = json_stringify(
      note_for(
        tree,
        git(%w[rev-parse HEAD:flake.lock]),
        git(%w[rev-parse HEAD:Cargo.lock]),
        ran[:binaries],
        ran[:rustc],
        now_rfc3339
      )
    )
    exec_check(
      "git",
      "notes",
      "--ref=blue-suite",
      "add",
      "-f",
      "-m",
      note,
      "HEAD"
    )
    say("noted #{note}")
  end
  if push_notes(2) != 0
    say("the note could not be pushed; CI will run the suite")
    exit_with(1)
  end
end

def main()
  if count(argv) == 2 and first(argv) == "--verify"
    verify(argv_get(1))
  elsif argv == ["--prove"]
    prove
  else
    say("gen/proof.b --prove | --verify <rev>")
    exit_with(2)
  end
end

test "a proof holds only for the tree and the locks it names"
  note = json_stringify(note_for("t", "f", "c", 165, "rustc 1.0", "now"))
  assert proof_gap(note, "t", "f", "c").nil?
  assert contains?(proof_gap(note, "u", "f", "c"), "tree t")
  assert contains?(proof_gap(note, "t", "g", "c"), "flake.lock")
  assert contains?(proof_gap(note, "t", "f", "d"), "Cargo.lock")
  assert contains?(proof_gap("", "t", "f", "c"), "no refs/notes/blue-suite")
  assert proof_gap("{", "t", "f", "c") == "the note is not JSON"
  assert proof_gap("[1]", "t", "f", "c") == "the note is no blue-suite/1 proof"
  assert proof_gap("{\"schema\":\"x\"}", "t", "f", "c") ==
    "the note is no blue-suite/1 proof"
end

test "the note names the command it proves and counts its binaries"
  note = json_parse(json_stringify(note_for("t", "f", "c", 2, "r", "a")))
  assert json_get(note, :command) == suite_command
  assert json_get(note, :binaries) == 2
  assert binaries_in(
    unlines(["  Executable a (x)", "Doc-tests b", "Executable c (y)"])
  ) == 2
end

def repo(dir, args)
  r = exec_capture(
    "git",
    "-C",
    dir,
    "-c",
    "user.name=t",
    "-c",
    "user.email=t@t",
    *args
  )
  if status_of(r) != 0
    raise(:git, "git #{join(args, " ")}: #{stderr_of(r)}")
  end
  trim(stdout_of(r))
end

def verify_in(work)
  exec_capture(
    "env",
    "-C",
    work,
    self_exe,
    "run",
    "--quiet",
    path_join(getenv("GEN_ROOT", cwd), "gen/proof.b"),
    "--",
    "--verify",
    "HEAD"
  )
end

test "--verify reads the note origin holds for the commit, and a commit with none is not proven"
  if self_exe != nil
    root = path_join(getenv("TMPDIR", "/tmp"), "proof-#{to_s(now_ns)}")
    work = path_join(root, "work")
    mkdir_p(work)
    write_file(path_join(work, "flake.lock"), "{}")
    write_file(path_join(work, "Cargo.lock"), "")
    repo(root, %w[init -q --bare -b main origin.git])
    repo(work, %w[init -q -b main])
    repo(work, %w[add -A])
    repo(work, %w[commit -q -m base])
    repo(work, ["remote", "add", "origin", path_join(root, "origin.git")])
    repo(work, %w[push -q origin main])
    unproven = verify_in(work)
    assert stdout_of(unproven) == "false"
    assert contains?(stderr_of(unproven), "no refs/notes/blue-suite")
    note = json_stringify(
      note_for(
        repo(work, %w[rev-parse HEAD^{tree}]),
        repo(work, %w[rev-parse HEAD:flake.lock]),
        repo(work, %w[rev-parse HEAD:Cargo.lock]),
        1,
        "r",
        "a"
      )
    )
    repo(work, ["notes", "--ref=blue-suite", "add", "-m", note, "HEAD"])
    repo(work, %w[push -q origin refs/notes/blue-suite])
    repo(work, %w[update-ref -d refs/notes/blue-suite])
    assert stdout_of(verify_in(work)) == "true"
    write_file(path_join(work, "Cargo.lock"), "changed")
    repo(work, %w[commit -q -am moved])
    assert stdout_of(verify_in(work)) == "false"
    rm_rf(root)
  end
end
