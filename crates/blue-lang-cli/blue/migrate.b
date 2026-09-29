# blue migrate: make every reference a file makes to another bidama's
# definition explicit, and keep the change only when the file's meaning is
# provably the same.
#
#   blue migrate FILE...
#
# Per file, every bare name that reaches another bidama's definition only
# because one global environment holds every loaded definition (B0012) is
# listed in that bidama's `use` (`use("retsu", [:first])`). A `use` is added
# where the file had none, and inside a bidama the matching `needs` goes into
# its Bluefile and the lock is refreshed. The file's imports are written in
# their canonical order (B0015).
#
# The proof: `blue ast --resolved --json` resolves the file before and after.
# The file is kept only when its forms resolved under per-bidama namespaces
# AFTER are byte-identical to its forms resolved under today's flat rule
# BEFORE, and nothing is left for B0012. Otherwise every file the run touched
# for it is restored, and the run fails naming why.
#
# The tool is blue, over builtins only, so it runs against any distribution:
# it spawns the blue running it (`self_exe`) for everything it asks of the
# name table.

def run_blue(args)
  apply(exec_capture, cons(self_exe(), args))
end

def status_of(r)
  nth(1, nth(0, r))
end

def stdout_of(r)
  nth(1, nth(1, r))
end

def stderr_of(r)
  nth(1, nth(2, r))
end

def resolved(file)
  r = run_blue(["ast", "--resolved", "--json", file])
  if status_of(r) != 0
    throw(error(:migrate, "blue ast --resolved #{file}: #{stderr_of(r)}"))
  end
  json_parse(stdout_of(r))
end

# The file's forms resolved under `rule` ("flat" or "ns"), without its `use`
# declarations, which are what the migration changes.
def forms_under(doc, rule)
  filter(fn(f) !starts_with?(f, "(use ") end, json_get(doc, rule))
end

def sorted(xs)
  distinct(sort_keyed(fn(x) x end, xs))
end

# Is `r` a bare reference to another bidama's definition that per-bidama
# namespaces would not bind to it?
def implicit?(r, own)
  flat = json_get(r, "flat")
  kind = json_get(json_get(r, "ns"), "kind")
  owner = json_get(flat, "namespace")
  json_get(flat, "kind") == "def" &&
    owner != nil &&
    owner != own &&
    (kind == "builtin" || kind == "unbound") &&
    !contains?(json_get(r, "written"), "/")
end

# [[package, name], ...] the file must list.
def wanted(doc)
  own = json_get(doc, "namespace")
  hits = filter(fn(r) implicit?(r, own) end, json_get(doc, "references"))
  distinct(
    map(
      fn(r)
        flat = json_get(r, "flat")
        [json_get(flat, "namespace"), json_get(flat, "name")]
      end,
      hits
    )
  )
end

# [package, [names]] for every `use` the file will have, sorted.
def uses_after(doc, want)
  existing = json_get(doc, "imports")
  packages = sorted(
    append(
      map(fn(u) json_get(u, "package") end, existing),
      map(fn(w) first(w) end, want)
    )
  )
  map(
    fn(p)
      listed = append(
        apply(
          append,
          map(
            fn(u) json_get(u, "names") end,
            filter(fn(u) json_get(u, "package") == p end, existing)
          )
        ),
        map(fn(w) nth(1, w) end, filter(fn(w) first(w) == p end, want))
      )
      [p, sorted(listed)]
    end,
    packages
  )
end

def render_use(u)
  names = nth(1, u)
  if empty?(names)
    "use(\"#{first(u)}\")"
  else
    "use(\"#{first(u)}\", [#{join(map(fn(n) ":#{n}" end, names), ", ")}])"
  end
end

# The file's text with its `use` lines replaced by `block`, written where the
# first `use` was (or above the first form, with a blank line after).
def rewrite(text, doc, block)
  lines = split(text, "\n")
  existing = json_get(doc, "imports")
  dropped = apply(
    append,
    map(
      fn(u) range(json_get(u, "line"), json_get(u, "end_line") + 1) end,
      existing
    )
  )
  at = if empty?(existing)
    json_get_or(doc, "first_line", 1)
  else
    json_get(first(existing), "line")
  end
  inserted = if empty?(existing)
    append(block, [""])
  else
    block
  end
  numbered = zip(range(1, length(lines) + 1), lines)
  before = filter(
    fn(nl) first(nl) < at && !member?(first(nl), dropped) end,
    numbered
  )
  after = filter(
    fn(nl) first(nl) >= at && !member?(first(nl), dropped) end,
    numbered
  )
  join(
    append(
      map(fn(nl) nth(1, nl) end, before),
      inserted,
      map(fn(nl) nth(1, nl) end, after)
    ),
    "\n"
  )
end

# The bidamas a Bluefile `needs`.
def needs_of(bluefile)
  r = run_blue(["bluefile", "--json", bluefile])
  if status_of(r) != 0
    throw(error(:migrate, "blue bluefile #{bluefile}: #{stderr_of(r)}"))
  end
  needs = json_get(json_parse(stdout_of(r)), "needs")
  if needs == nil
    []
  else
    map(fn(kv) first(kv) end, needs)
  end
end

# Add `needs(p, "^0.1")` after the Bluefile's last `needs` or `package` line.
def add_needs(text, packages)
  lines = split(text, "\n")
  numbered = zip(range(0, length(lines)), lines)
  anchors = filter(
    fn(nl)
      starts_with?(nth(1, nl), "needs(") || starts_with?(nth(1, nl), "package(")
    end,
    numbered
  )
  at = first(last(anchors)) + 1
  added = map(fn(p) "needs(\"#{p}\", \"^0.1\")" end, packages)
  join(append(take(at, lines), added, drop(at, lines)), "\n")
end

def relock(dir)
  r = run_blue(["lock", dir])
  if status_of(r) != 0
    throw(error(:migrate, "blue lock #{dir}: #{stderr_of(r)}"))
  end
end

# Migrate one file. Returns a line for the report; raises when the proof
# fails, after restoring what it touched.
def migrate(file)
  before = resolved(file)
  want = wanted(before)
  if empty?(want)
    "unchanged #{file}"
  else
    text = read_file(file)
    uses = uses_after(before, want)
    write_file(file, rewrite(text, before, map(fn(u) render_use(u) end, uses)))
    own = json_get(before, "namespace")
    bluefile = path_join(path_dirname(file), "Bluefile")
    bidama = own != nil && path_exists(bluefile)
    old_bluefile = if bidama
      read_file(bluefile)
    else
      nil
    end
    if bidama
      needed = needs_of(bluefile)
      missing = filter(
        fn(p) p != own && !member?(p, needed) end,
        map(fn(u) first(u) end, uses)
      )
      if !empty?(missing)
        write_file(bluefile, add_needs(old_bluefile, missing))
        relock(path_dirname(file))
      end
    end
    after = resolved(file)
    same = forms_under(after, "ns") == forms_under(before, "flat")
    left = wanted(after)
    if same && empty?(left)
      "migrated #{file}: #{length(want)} name(s) made explicit"
    else
      write_file(file, text)
      if bidama
        write_file(bluefile, old_bluefile)
        relock(path_dirname(file))
      end
      why = if same
        "#{length(left)} reference(s) still implicit"
      else
        "its resolved tree changed"
      end
      throw(error(:migrate, "refused #{file}: #{why}; restored"))
    end
  end
end

# `write_stdout`, not `println`: the report is text for a person, unquoted.
map(fn(f) write_stdout("#{migrate(f)}\n") end, argv())
