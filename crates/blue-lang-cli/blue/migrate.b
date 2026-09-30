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
    # A rewrite that does not even resolve is refused like one that changes
    # the tree: restored, and named.
    after = try(resolved(file), catch(_e(), nil))
    same = after != nil &&
      forms_under(after, "ns") == forms_under(before, "flat")
    left = if after == nil
      []
    else
      wanted(after)
    end
    if same && empty?(left)
      "migrated #{file}: #{length(want)} name(s) made explicit"
    else
      write_file(file, text)
      if bidama
        write_file(bluefile, old_bluefile)
        relock(path_dirname(file))
      end
      why = if after == nil
        "the rewritten file does not resolve"
      elsif same
        "#{length(left)} reference(s) still implicit"
      else
        "its resolved tree changed"
      end
      throw(error(:migrate, "refused #{file}: #{why}; restored"))
    end
  end
end

# ── the prefix strip: blue migrate --strip PREFIX BIDAMA CALLER... ──────────
#
# A bidama whose definitions are hand-prefixed (`lc_hours`) loses the prefix:
# each `lc_x` becomes `x`, and `legacy_names("0.1.1", "lc")` keeps the old
# spelling as a bridge. A definition whose stripped name is a reserved word or
# a builtin keeps its prefix, waived, and gains the stripped name as a second
# name; the bidama's own bare uses of that builtin become `blue::x`, since the
# second name now wins inside it. Each caller's references to a renamed
# definition are written `pkg::x`, and its import list drops the old names.
# The version goes to 0.1.1, the window's start.
#
# The proof, per file: its forms resolved under namespaces after equal its
# forms before with every renamed key rewritten (`lc/lc_x` to `lc/x`), and
# `blue check` passes. Otherwise every file is restored.

def ident_char?(c)
  contains?(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_?!",
    c
  )
end

# `s` with every whole-identifier `old` replaced by `new`.
def replace_word(s, old, new)
  pieces = split(s, old)
  numbered = zip(range(0, length(pieces)), pieces)
  foldl(
    fn(acc, np)
      i = first(np)
      piece = nth(1, np)
      if i == 0
        piece
      else
        before = if acc == ""
          nil
        else
          last(chars(acc))
        end
        after = if piece == ""
          nil
        else
          first(chars(piece))
        end
        whole = (before == nil || !ident_char?(before)) &&
          (after == nil || !ident_char?(after))
        if whole
          "#{acc}#{new}#{piece}"
        else
          "#{acc}#{old}#{piece}"
        end
      end
    end,
    "",
    numbered
  )
end

# A string literal's source with `old` replaced by `new` inside its
# interpolations only: the parser gives every name in them the string's
# span, and the literal text around them is text. Interpolations nest (a
# string inside `#{…}` has its own), so the scan counts braces: depth 0 is
# text, anything deeper is code.
def replace_ident(s, old, new)
  # [segments, current, depth, previous char]; a segment is [code?, text].
  step = fn(st, c)
    segs = first(st)
    cur = nth(1, st)
    depth = nth(2, st)
    prev = nth(3, st)
    if depth == 0 && prev == "#" && c == "{"
      [append(segs, [[false, cur]]), c, 1, c]
    elsif depth > 0 && c == "{"
      [segs, "#{cur}#{c}", depth + 1, c]
    elsif depth == 1 && c == "}"
      [append(segs, [[true, cur]]), c, 0, c]
    elsif depth > 1 && c == "}"
      [segs, "#{cur}#{c}", depth - 1, c]
    else
      [segs, "#{cur}#{c}", depth, c]
    end
  end
  st = foldl(step, [[], "", 0, ""], chars(s))
  segs = append(first(st), [[nth(2, st) > 0, nth(1, st)]])
  join(
    map(
      fn(seg)
        if first(seg)
          replace_word(nth(1, seg), old, new)
        else
          nth(1, seg)
        end
      end,
      segs
    ),
    ""
  )
end

# Rewrite the span [col, end_col) of `line` by `renames` ([[old, new], …]):
# the span is exactly one old name, or a string literal whose
# interpolations the parser gave every name inside it the string's span.
def edit_at(line, col, end_col, renames)
  cs = chars(line)
  written = join(take(end_col - col, drop(col - 1, cs)), "")
  exact = filter(fn(r) first(r) == written end, renames)
  replacement = if !empty?(exact)
    nth(1, first(exact))
  elsif contains?(written, "#\u{7b}")
    foldl(fn(w, r) replace_ident(w, first(r), nth(1, r)) end, written, renames)
  else
    throw(
      error(
        :migrate,
        "expected `#{first(first(renames))}` at column #{col}, found `#{written}`"
      )
    )
  end
  join(append(take(col - 1, cs), [replacement], drop(end_col - 1, cs)), "")
end

# Apply [[line, col, end_col, old, new], …] to `text`: one rewrite per span,
# right to left within a line, so earlier columns stay valid.
def apply_edits(text, edits)
  lines = split(text, "\n")
  numbered = zip(range(1, length(lines) + 1), lines)
  out = map(
    fn(nl)
      here = filter(fn(e) first(e) == first(nl) end, edits)
      spans = sort_keyed(
        fn(sp) -first(sp) end,
        distinct(map(fn(e) [nth(1, e), nth(2, e)] end, here))
      )
      foldl(
        fn(l, sp)
          renames = distinct(
            map(
              fn(e) [nth(3, e), nth(4, e)] end,
              filter(
                fn(e) nth(1, e) == first(sp) && nth(2, e) == nth(1, sp) end,
                here
              )
            )
          )
          edit_at(l, first(sp), nth(1, sp), renames)
        end,
        nth(1, nl),
        spans
      )
    end,
    numbered
  )
  join(out, "\n")
end

# Insert `new_lines` before line `at` (1-based).
def insert_lines(text, at, new_lines)
  lines = split(text, "\n")
  join(append(take(at - 1, lines), new_lines, drop(at - 1, lines)), "\n")
end

# The rename map over a resolved tree: every key `pkg/old` becomes
# `pkg/new`. Quoted data (the source an assertion quotes) is elided before
# the comparison, and strings are text the rename leaves alone.
def key_rewrite(tree, pkg, renames)
  foldl(
    fn(t, r)
      foldl(
        fn(acc, end_char)
          replace(
            acc,
            "#{pkg}/#{first(r)}#{end_char}",
            "#{pkg}/#{nth(1, r)}#{end_char}"
          )
        end,
        t,
        [" ", ")"]
      )
    end,
    tree,
    renames
  )
end

# A resolved form with every quoted datum elided: `assert e` lowers to
# `(blue-assert 'e e)`, and the datum is the source an assertion quotes in
# its failure message. The rename rewrites that source with the code, and
# may qualify it (`blue::get`), so the proof compares what RUNS: the datum
# is text, the evaluated copy beside it is checked like all code.
def unquoted(t)
  # [out chars (reversed), depth inside a datum, in string?, escaped?, prev]
  step = fn(st, c)
    out = first(st)
    depth = nth(1, st)
    str = nth(2, st)
    esc = nth(3, st)
    prev = nth(4, st)
    if depth == 0
      if prev == "'" && c == "("
        [cons("…", out), 1, false, false, c]
      else
        [cons(c, out), 0, false, false, c]
      end
    elsif str
      if esc
        [out, depth, true, false, c]
      elsif c == "\\"
        [out, depth, true, true, c]
      elsif c == "\""
        [out, depth, false, false, c]
      else
        [out, depth, true, false, c]
      end
    elsif c == "\""
      [out, depth, true, false, c]
    elsif c == "("
      [out, depth + 1, false, false, c]
    elsif c == ")"
      if depth == 1
        [cons(")", out), 0, false, false, c]
      else
        [out, depth - 1, false, false, c]
      end
    else
      [out, depth, false, false, c]
    end
  end
  join(reverse(first(foldl(step, [[], 0, false, false, ""], chars(t)))), "")
end

def settled_forms(doc, rule)
  filter(fn(f) !starts_with?(f, "(legacy_names ") end, forms_under(doc, rule))
end

# The source spelling of a reference: `pkg::x` for a qualified one.
def surface(written)
  if contains?(written, "/")
    parts = split(written, "/")
    "#{first(parts)}::#{nth(1, parts)}"
  else
    written
  end
end

def ref_edit(r, new)
  [
    json_get(r, "line"),
    json_get(r, "column"),
    json_get(r, "end_column"),
    surface(json_get(r, "written")),
    new
  ]
end

def check_ok?(file)
  status_of(run_blue(["check", file])) == 0
end

def strip_bidama(prefix, file)
  doc = resolved(file)
  pkg = json_get(doc, "namespace")
  builtins = json_get(doc, "builtins")
  reserved = json_get(doc, "reserved")
  p = "#{prefix}_"
  defs = filter(
    fn(d) starts_with?(json_get(d, "name"), p) end,
    json_get(doc, "definitions")
  )
  stripped = fn(n) join(drop(length(chars(p)), chars(n)), "") end
  keep? = fn(n)
    member?(stripped(n), builtins) || member?(stripped(n), reserved)
  end
  renames = map(
    fn(d) [json_get(d, "name"), stripped(json_get(d, "name"))] end,
    filter(fn(d) !keep?(json_get(d, "name")) end, defs)
  )
  kept = map(
    fn(d) stripped(json_get(d, "name")) end,
    filter(fn(d) keep?(json_get(d, "name")) end, defs)
  )
  old_names = map(fn(r) first(r) end, renames)
  new_of = fn(n) nth(1, first(filter(fn(r) first(r) == n end, renames))) end
  def_edits = map(
    fn(d)
      [
        json_get(d, "line"),
        json_get(d, "column"),
        json_get(d, "end_column"),
        json_get(d, "name"),
        new_of(json_get(d, "name"))
      ]
    end,
    filter(fn(d) member?(json_get(d, "name"), old_names) end, defs)
  )
  refs = json_get(doc, "references")
  # A new name a local of the same name would capture is written qualified.
  ref_edits = map(
    fn(r)
      new = new_of(json_get(r, "written"))
      if member?(new, json_get(r, "locals"))
        ref_edit(r, "#{pkg}::#{new}")
      else
        ref_edit(r, new)
      end
    end,
    filter(
      fn(r)
        ns = json_get(r, "ns")
        member?(json_get(r, "written"), old_names) &&
          json_get(ns, "kind") == "def" &&
          json_get(ns, "namespace") == pkg
      end,
      refs
    )
  )
  # A name another bidama lends it that a kept name's second name now
  # shadows (tier 2 over 3): written qualified, and dropped from the list.
  lent = filter(
    fn(r)
      ns = json_get(r, "ns")
      json_get(ns, "kind") == "def" &&
        json_get(ns, "namespace") != pkg &&
        json_get(ns, "namespace") != nil &&
        member?(json_get(r, "written"), kept)
    end,
    refs
  )
  lent_edits = map(
    fn(r)
      ref_edit(
        r,
        "#{json_get(json_get(r, "ns"), "namespace")}::#{json_get(r, "written")}"
      )
    end,
    lent
  )
  builtin_edits = map(
    fn(r) ref_edit(r, "blue::#{json_get(r, "written")}") end,
    filter(
      fn(r)
        json_get(json_get(r, "ns"), "kind") == "builtin" &&
          member?(json_get(r, "written"), kept)
      end,
      refs
    )
  )
  text = read_file(file)
  renamed = apply_edits(
    text,
    append(def_edits, ref_edits, builtin_edits, lent_edits)
  )
  # Waivers above each kept definition, bottom up so line numbers hold.
  kept_defs = sort_keyed(
    fn(d) -json_get(d, "line") end,
    filter(fn(d) keep?(json_get(d, "name")) end, defs)
  )
  waived = foldl(
    fn(t, d)
      n = stripped(json_get(d, "name"))
      why = if member?(n, reserved)
        "a reserved word"
      else
        "a builtin #{pkg} also uses"
      end
      insert_lines(
        t,
        json_get(d, "line"),
        [
          "# waive B0013: `#{n}` is #{why}, so the prefix stays; #{pkg}::#{n} names it too"
        ]
      )
    end,
    renamed,
    kept_defs
  )
  imports = json_get(doc, "imports")
  at = if empty?(imports)
    json_get_or(doc, "first_line", 1)
  else
    json_get(last(imports), "end_line") + 1
  end
  ledger = if empty?(imports)
    ["legacy_names(\"0.1.1\", \"#{prefix}\")", ""]
  else
    ["", "legacy_names(\"0.1.1\", \"#{prefix}\")"]
  end
  ledgered = insert_lines(waived, at, ledger)
  lenders = distinct(
    map(fn(r) json_get(json_get(r, "ns"), "namespace") end, lent)
  )
  relisted = foldl(
    fn(t, lender) relist(t, doc, lender, kept) end,
    ledgered,
    lenders
  )
  [pkg, renames, text, relisted, length(kept)]
end

# A caller's references to renamed definitions, qualified; the old names off
# its import list.
def strip_caller(pkg, renames, file)
  doc = resolved(file)
  old_names = map(fn(r) first(r) end, renames)
  bridged = filter(
    fn(r)
      ns = json_get(r, "ns")
      json_get(ns, "kind") == "def" &&
        json_get(ns, "namespace") == pkg &&
        json_get(ns, "name") != last(split(json_get(r, "written"), "/"))
    end,
    json_get(doc, "references")
  )
  edits = map(
    fn(r) ref_edit(r, "#{pkg}::#{json_get(json_get(r, "ns"), "name")}") end,
    bridged
  )
  relist(apply_edits(read_file(file), edits), doc, pkg, old_names)
end

# `text` with the `use` of `package` (as `doc` found it) listing no name in
# `dropped`: the names a rewrite made qualified. Its lines must still be
# where `doc` saw them.
def relist(text, doc, package, dropped)
  mine = filter(
    fn(u) json_get(u, "package") == package end,
    json_get(doc, "imports")
  )
  if empty?(mine)
    text
  else
    u = first(mine)
    left = filter(fn(n) !member?(n, dropped) end, json_get(u, "names"))
    line = json_get(u, "line")
    lines = split(text, "\n")
    numbered = zip(range(1, length(lines) + 1), lines)
    kept = filter(
      fn(nl) first(nl) < line || first(nl) > json_get(u, "end_line") end,
      numbered
    )
    before = filter(fn(nl) first(nl) < line end, kept)
    after = filter(fn(nl) first(nl) > line end, kept)
    join(
      append(
        map(fn(nl) nth(1, nl) end, before),
        [render_use([package, left])],
        map(fn(nl) nth(1, nl) end, after)
      ),
      "\n"
    )
  end
end

def bump_version(bluefile)
  write_file(bluefile, replace(read_file(bluefile), "\"0.1.0\")", "\"0.1.1\")"))
end

def strip(prefix, file, callers)
  before = resolved(file)
  pkg = json_get(before, "namespace")
  befores = map(fn(c) [c, read_file(c), resolved(c)] end, callers)
  plan = strip_bidama(prefix, file)
  renames = nth(1, plan)
  dir = path_dirname(file)
  bluefile = path_join(dir, "Bluefile")
  old_bluefile = read_file(bluefile)
  restore = fn()
    write_file(file, nth(2, plan))
    write_file(bluefile, old_bluefile)
    relock(dir)
    map(fn(b) write_file(first(b), nth(1, b)) end, befores)
  end
  write_file(file, nth(3, plan))
  bump_version(bluefile)
  relock(dir)
  run_blue(["fmt", "--write", file])
  map(
    fn(b)
      write_file(first(b), strip_caller(pkg, renames, first(b)))
      run_blue(["fmt", "--write", first(b)])
    end,
    befores
  )
  # nil when `f` proves out; otherwise why, with the first difference.
  proof = fn(f, old_doc)
    now = try(resolved(f), catch(_e(), nil))
    if now == nil
      "#{f}: does not resolve"
    else
      want = map(
        fn(t) unquoted(key_rewrite(t, pkg, renames)) end,
        settled_forms(old_doc, "ns")
      )
      got = map(fn(t) unquoted(t) end, settled_forms(now, "ns"))
      if got != want
        pairs = filter(fn(p) first(p) != nth(1, p) end, zip(want, got))
        if empty?(pairs)
          "#{f}: #{length(want)} forms expected, #{length(got)} found"
        else
          "#{f}: expected #{first(first(pairs))}, found #{nth(1, first(pairs))}"
        end
      else
        c = run_blue(["check", f])
        if status_of(c) != 0
          "#{f}: does not check: #{stderr_of(c)}"
        else
          nil
        end
      end
    end
  end
  bad = filter(
    fn(why) why != nil end,
    map(
      fn(fd) proof(first(fd), nth(1, fd)) end,
      cons([file, before], map(fn(b) [first(b), nth(2, b)] end, befores))
    )
  )
  if empty?(bad)
    "stripped #{pkg}: #{length(renames)} renamed, #{nth(4, plan)} kept with a second name, #{length(callers)} caller(s) rewritten"
  else
    restore()
    throw(
      error(
        :migrate,
        "refused the strip of #{pkg}, restored: #{join(bad, "\n")}"
      )
    )
  end
end

# `write_stdout`, not `println`: the report is text for a person, unquoted.
args = argv()

if !empty?(args) && first(args) == "--strip"
  write_stdout("#{strip(nth(1, args), nth(2, args), drop(3, args))}\n")
else
  map(fn(f) write_stdout("#{migrate(f)}\n") end, args)
end
