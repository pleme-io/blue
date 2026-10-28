use("moji", [:take_chars])
use("retsu", [:first, :reject])
use("shisutemu", [:stdout_of])

@doc """
land_ref: The branch a landing pushes to. CI runs the whole suite on it and
fast-forwards main to it when green; a dry landing runs the suite and only
rehearses the fast-forward.

    land_ref("blue/toolchain-friction", false) #=> "land/blue/toolchain-friction"
    land_ref("blue/toolchain-friction", true) #=> "land/dry-blue/toolchain-friction"
"""
def land_ref(slug, dry)
  if dry
    "land/dry-#{slug}"
  else
    "land/#{slug}"
  end
end

@doc """
slug_for: The slug a landing takes: the one given, else the branch, else the
short commit when HEAD is main or no branch.

    slug_for(nil, "blue/toolchain-friction", "8bd5119") #=> "blue/toolchain-friction"
    slug_for(nil, "main", "8bd5119") #=> "8bd5119"
    slug_for("hard-blocks", "main", "8bd5119") #=> "hard-blocks"
"""
def slug_for(given, branch, short)
  if not given.nil?
    given
  elsif branch == "" or branch == "main" or branch == "HEAD"
    short
  else
    branch
  end
end

@doc """
land_args: The words after the program: an optional slug and the flags
--dry and --watch, in any order.

    land_args(["--watch", "x"]) #=> {slug: "x", dry: false, watch: true}
    land_args([]) #=> {slug: nil, dry: false, watch: false}
"""
def land_args(words)
  plain = reject((w) -> starts_with?(w, "--"), words)
  {
    slug: if plain == []
      nil
    else
      first(plain)
    end,
    dry: member?("--dry", words),
    watch: member?("--watch", words)
  }
end

def git(args)
  trim(stdout_of(exec_capture("git", *args)))
end

def main()
  a = land_args(argv)
  if git(["status", "--porcelain", "--untracked-files=no"]) != ""
    write_stderr(
      unlines(
        ["land: tracked files differ from HEAD; commit them, since CI checks the commit"]
      )
    )
    exit_with(1)
  end
  if exec_check("git", "fetch", "-q", "origin", "main") != 0
    exit_with(1)
  end
  if not exec_ok?("git", "merge-base", "--is-ancestor", "origin/main", "HEAD")
    write_stderr(
      unlines(
        ["land: HEAD does not contain origin/main, so main cannot fast-forward to it. Run: git rebase origin/main"]
      )
    )
    exit_with(1)
  end
  sha = git(["rev-parse", "HEAD"])
  ref = land_ref(
    slug_for(
      a[:slug],
      git(["rev-parse", "--abbrev-ref", "HEAD"]),
      git(["rev-parse", "--short", "HEAD"])
    ),
    a[:dry]
  )
  if exec_check("git", "push", "--force", "origin", "HEAD:refs/heads/#{ref}") !=
      0
    exit_with(1)
  end
  write_stderr(
    unlines(
      [
        "land: #{take_chars(sha, 10)} is on #{ref}. CI runs the whole suite and, when green, fast-forwards main to it; when main moved first, it fails and you rebase and land again"
      ]
    )
  )
  if a[:watch]
    found = reduce(
      fn(id, _)
        if id != ""
          id
        else
          sleep(3)
          trim(
            stdout_of(
              exec_capture(
                "gh",
                "run",
                "list",
                "--branch",
                ref,
                "--workflow",
                "land.yml",
                "--commit",
                sha,
                "--json",
                "databaseId",
                "--jq",
                ".[0].databaseId"
              )
            )
          )
        end
      end,
      "",
      range(20)
    )
    if found == ""
      write_stderr(
        unlines(
          ["land: no run appeared in a minute; gh run list --branch #{ref}"]
        )
      )
      exit_with(1)
    end
    exit_with(exec_check("gh", "run", "watch", found, "--exit-status"))
  else
    write_stderr(unlines(["land: follow it with gh run list --branch #{ref}"]))
  end
end

test "a landing pushes to land/<slug>, and a dry one to land/dry-<slug>"
  assert land_ref(slug_for(nil, "a/b", "1234567"), false) == "land/a/b"
  assert land_ref(slug_for(nil, "main", "1234567"), true) == "land/dry-1234567"
end
