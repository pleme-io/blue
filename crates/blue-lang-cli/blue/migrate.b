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
  exec_capture(*cons(self_exe, args))
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
    raise(:migrate, "blue ast --resolved #{file}: #{stderr_of(r)}")
  end
  json_parse(stdout_of(r))
end

# The file's forms resolved under `rule` ("flat" or "ns"), without its `use`
# declarations, which are what the migration changes.
def forms_under(doc, rule)
  filter((f) -> not starts_with?(f, "(use "), json_get(doc, rule))
end

def sorted(xs)
  distinct(sort_keyed((x) -> x, xs))
end

# Is `r` a bare reference to another bidama's definition that per-bidama
# namespaces would not bind to it?
def implicit?(r, own)
  flat = json_get(r, "flat")
  kind = json_get(json_get(r, "ns"), "kind")
  owner = json_get(flat, "namespace")
  json_get(flat, "kind") == "def" and
    owner != nil and
    owner != own and
    (kind == "builtin" or kind == "unbound") and
    not contains?(json_get(r, "written"), "/")
end

# [[package, name], ...] the file must list.
def wanted(doc)
  own = json_get(doc, "namespace")
  hits = filter((r) -> implicit?(r, own), json_get(doc, "references"))
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
      map((u) -> json_get(u, "package"), existing),
      map((w) -> first(w), want)
    )
  )
  map(
    fn(p)
      listed = append(
        append(
          *map(
            (u) -> json_get(u, "names"),
            filter((u) -> json_get(u, "package") == p, existing)
          )
        ),
        map((w) -> nth(1, w), filter((w) -> first(w) == p, want))
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
    "use(\"#{first(u)}\", [#{join(map((n) -> ":#{n}", names), ", ")}])"
  end
end

# The file's text with its `use` lines replaced by `block`, written where the
# first `use` was (or above the first form, with a blank line after).
def rewrite(text, doc, block)
  lines = split(text, "\n")
  existing = json_get(doc, "imports")
  dropped = append(
    *map(
      (u) -> range(json_get(u, "line"), json_get(u, "end_line") + 1),
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
    (nl) -> first(nl) < at and not member?(first(nl), dropped),
    numbered
  )
  after = filter(
    (nl) -> first(nl) >= at and not member?(first(nl), dropped),
    numbered
  )
  join(
    append(
      map((nl) -> nth(1, nl), before),
      inserted,
      map((nl) -> nth(1, nl), after)
    ),
    "\n"
  )
end

# The bidamas a Bluefile `needs`.
def needs_of(bluefile)
  r = run_blue(["bluefile", "--json", bluefile])
  if status_of(r) != 0
    raise(:migrate, "blue bluefile #{bluefile}: #{stderr_of(r)}")
  end
  needs = json_get(json_parse(stdout_of(r)), "needs")
  if needs.nil?
    []
  else
    map((kv) -> first(kv), needs)
  end
end

# Add `needs(p, "^0.1")` after the Bluefile's last `needs` or `package` line.
def add_needs(text, packages)
  lines = split(text, "\n")
  numbered = zip(range(0, length(lines)), lines)
  anchors = filter(
    fn(nl)
      starts_with?(nth(1, nl), "needs(") or starts_with?(nth(1, nl), "package(")
    end,
    numbered
  )
  at = first(last(anchors)) + 1
  added = map((p) -> "needs(\"#{p}\", \"^0.1\")", packages)
  join(append(take(at, lines), added, drop(at, lines)), "\n")
end

def relock(dir)
  r = run_blue(["lock", dir])
  if status_of(r) != 0
    raise(:migrate, "blue lock #{dir}: #{stderr_of(r)}")
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
    write_file(file, rewrite(text, before, map(render_use, uses)))
    own = json_get(before, "namespace")
    bluefile = path_join(path_dirname(file), "Bluefile")
    bidama = own != nil and path_exists(bluefile)
    old_bluefile = if bidama
      read_file(bluefile)
    end
    if bidama
      needed = needs_of(bluefile)
      missing = filter(
        (p) -> p != own and not member?(p, needed),
        map((u) -> first(u), uses)
      )
      if not empty?(missing)
        write_file(bluefile, add_needs(old_bluefile, missing))
        relock(path_dirname(file))
      end
    end
    # A rewrite that does not even resolve is refused like one that changes
    # the tree: restored, and named.
    after = resolved(file) rescue nil
    same = after != nil and
      forms_under(after, "ns") == forms_under(before, "flat")
    left = if after.nil?
      []
    else
      wanted(after)
    end
    if same and empty?(left)
      "migrated #{file}: #{length(want)} name(s) made explicit"
    else
      write_file(file, text)
      if bidama
        write_file(bluefile, old_bluefile)
        relock(path_dirname(file))
      end
      why = if after.nil?
        "the rewritten file does not resolve"
      elsif same
        "#{length(left)} reference(s) still implicit"
      else
        "its resolved tree changed"
      end
      raise(:migrate, "refused #{file}: #{why}; restored")
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
  reduce(
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
        whole = (before.nil? or not ident_char?(before)) and
          (after.nil? or not ident_char?(after))
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
    if depth == 0 and prev == "#" and c == "{"
      [append(segs, [[false, cur]]), c, 1, c]
    elsif depth > 0 and c == "{"
      [segs, "#{cur}#{c}", depth + 1, c]
    elsif depth == 1 and c == "}"
      [append(segs, [[true, cur]]), c, 0, c]
    elsif depth > 1 and c == "}"
      [segs, "#{cur}#{c}", depth - 1, c]
    else
      [segs, "#{cur}#{c}", depth, c]
    end
  end
  st = reduce(step, [[], "", 0, ""], chars(s))
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
  exact = filter((r) -> first(r) == written, renames)
  replacement = if not empty?(exact)
    nth(1, first(exact))
  elsif contains?(written, "#\u{7b}")
    reduce((w, r) -> replace_ident(w, first(r), nth(1, r)), written, renames)
  else
    raise(
      :migrate,
      "expected `#{first(first(renames))}` at column #{col}, found `#{written}`"
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
      here = filter((e) -> first(e) == first(nl), edits)
      spans = sort_keyed(
        (sp) -> -first(sp),
        distinct(map((e) -> [nth(1, e), nth(2, e)], here))
      )
      reduce(
        fn(l, sp)
          renames = distinct(
            map(
              (e) -> [nth(3, e), nth(4, e)],
              filter(
                (e) -> nth(1, e) == first(sp) and nth(2, e) == nth(1, sp),
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
  reduce(
    fn(t, r)
      reduce(
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
      if prev == "'" and c == "("
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
  join(reverse(first(reduce(step, [[], 0, false, false, ""], chars(t)))), "")
end

def settled_forms(doc, rule)
  filter((f) -> not starts_with?(f, "(legacy_names "), forms_under(doc, rule))
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
    (d) -> starts_with?(json_get(d, "name"), p),
    json_get(doc, "definitions")
  )
  stripped = (n) -> join(drop(length(chars(p)), chars(n)), "")
  keep? = fn(n)
    member?(stripped(n), builtins) or member?(stripped(n), reserved)
  end
  renames = map(
    (d) -> [json_get(d, "name"), stripped(json_get(d, "name"))],
    filter((d) -> not keep?(json_get(d, "name")), defs)
  )
  kept = map(
    (d) -> stripped(json_get(d, "name")),
    filter((d) -> keep?(json_get(d, "name")), defs)
  )
  old_names = map((r) -> first(r), renames)
  new_of = (n) -> nth(1, first(filter((r) -> first(r) == n, renames)))
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
    filter((d) -> member?(json_get(d, "name"), old_names), defs)
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
        member?(json_get(r, "written"), old_names) and
          json_get(ns, "kind") == "def" and
          json_get(ns, "namespace") == pkg
      end,
      refs
    )
  )
  # A name another bidama lends it that a new name or a kept name's second
  # name now shadows (tier 2 over 3; zumen's zu_region becoming region over
  # kikagaku's): written qualified, and dropped from the list.
  shadowing = append(kept, map((r) -> nth(1, r), renames))
  lent = filter(
    fn(r)
      ns = json_get(r, "ns")
      json_get(ns, "kind") == "def" and
        json_get(ns, "namespace") != pkg and
        json_get(ns, "namespace") != nil and
        member?(json_get(r, "written"), shadowing)
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
    (r) -> ref_edit(r, "blue::#{json_get(r, "written")}"),
    filter(
      fn(r)
        json_get(json_get(r, "ns"), "kind") == "builtin" and
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
    (d) -> -json_get(d, "line"),
    filter((d) -> keep?(json_get(d, "name")), defs)
  )
  waived = reduce(
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
  lenders = distinct(map((r) -> json_get(json_get(r, "ns"), "namespace"), lent))
  relisted = reduce(
    (t, lender) -> relist(t, doc, lender, shadowing),
    ledgered,
    lenders
  )
  [pkg, renames, text, relisted, length(kept)]
end

# A caller's references to renamed definitions, qualified; the old names off
# its import list.
def strip_caller(pkg, renames, file)
  doc = resolved(file)
  old_names = map((r) -> first(r), renames)
  bridged = filter(
    fn(r)
      ns = json_get(r, "ns")
      json_get(ns, "kind") == "def" and
        json_get(ns, "namespace") == pkg and
        json_get(ns, "name") != last(split(json_get(r, "written"), "/"))
    end,
    json_get(doc, "references")
  )
  edits = map(
    (r) -> ref_edit(r, "#{pkg}::#{json_get(json_get(r, "ns"), "name")}"),
    bridged
  )
  relist(apply_edits(read_file(file), edits), doc, pkg, old_names)
end

# `text` with the `use` of `package` (as `doc` found it) listing no name in
# `dropped`: the names a rewrite made qualified. Its lines must still be
# where `doc` saw them.
def relist(text, doc, package, dropped)
  mine = filter(
    (u) -> json_get(u, "package") == package,
    json_get(doc, "imports")
  )
  if empty?(mine)
    text
  else
    u = first(mine)
    left = filter((n) -> not member?(n, dropped), json_get(u, "names"))
    line = json_get(u, "line")
    lines = split(text, "\n")
    numbered = zip(range(1, length(lines) + 1), lines)
    kept = filter(
      (nl) -> first(nl) < line or first(nl) > json_get(u, "end_line"),
      numbered
    )
    before = filter((nl) -> first(nl) < line, kept)
    after = filter((nl) -> first(nl) > line, kept)
    join(
      append(
        map((nl) -> nth(1, nl), before),
        [render_use([package, left])],
        map((nl) -> nth(1, nl), after)
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
  befores = map((c) -> [c, read_file(c), resolved(c)], callers)
  plan = strip_bidama(prefix, file)
  renames = nth(1, plan)
  dir = path_dirname(file)
  bluefile = path_join(dir, "Bluefile")
  old_bluefile = read_file(bluefile)
  restore = fn()
    write_file(file, nth(2, plan))
    write_file(bluefile, old_bluefile)
    relock(dir)
    map((b) -> write_file(first(b), nth(1, b)), befores)
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
    now = resolved(f) rescue nil
    if now.nil?
      "#{f}: does not resolve"
    else
      want = map(
        (t) -> unquoted(key_rewrite(t, pkg, renames)),
        settled_forms(old_doc, "ns")
      )
      got = map(unquoted, settled_forms(now, "ns"))
      if got != want
        pairs = filter((p) -> first(p) != nth(1, p), zip(want, got))
        if empty?(pairs)
          "#{f}: #{length(want)} forms expected, #{length(got)} found"
        else
          "#{f}: expected #{first(first(pairs))}, found #{nth(1, first(pairs))}"
        end
      else
        c = run_blue(["check", f])
        if status_of(c) != 0
          "#{f}: does not check: #{stderr_of(c)}"
        end
      end
    end
  end
  bad = filter(
    (why) -> why != nil,
    map(
      (fd) -> proof(first(fd), nth(1, fd)),
      cons([file, before], map((b) -> [first(b), nth(2, b)], befores))
    )
  )
  if empty?(bad)
    "stripped #{pkg}: #{length(renames)} renamed, #{nth(4, plan)} kept with a second name, #{length(callers)} caller(s) rewritten"
  else
    restore()
    raise(:migrate, "refused the strip of #{pkg}, restored: #{join(bad, "\n")}")
  end
end

def blank_char?(c)
  member?(c, [" ", "\n", "\t", "\r"])
end

def leading_blanks(cs)
  first(
    reduce(
      fn(st, c)
        if nth(1, st) or not blank_char?(c)
          [first(st), true]
        else
          [first(st) + 1, false]
        end
      end,
      [0, false],
      cs
    )
  )
end

def padded(seg)
  lead = leading_blanks(seg)
  trail = leading_blanks(reverse(drop(lead, seg)))
  core = length(seg) - lead - trail
  [take(lead, seg), take(core, drop(lead, seg)), drop(lead + core, seg)]
end

def swap_args_at(cs, plan)
  open = first(plan)
  a = open + 1
  b = open + nth(1, plan)
  c = open + nth(2, plan)
  one = padded(take(b - a, drop(a, cs)))
  two = padded(take(c - b - 1, drop(b + 1, cs)))
  append(
    take(a, cs),
    first(one),
    nth(1, two),
    nth(2, one),
    [","],
    first(two),
    nth(1, one),
    nth(2, two),
    drop(c, cs)
  )
end

def scan_step(st, c)
  stack = first(st)
  comma = nth(1, st)
  commas = nth(2, st)
  close = nth(3, st)
  comment = nth(4, st)
  esc = nth(5, st)
  i = nth(6, st)
  prev = nth(7, st)
  top = first(stack)
  if close != nil
    st
  elsif top == "str"
    if esc
      [stack, comma, commas, close, comment, false, i + 1, ""]
    elsif c == "\\"
      [stack, comma, commas, close, comment, true, i + 1, c]
    elsif c == "\""
      [rest(stack), comma, commas, close, comment, false, i + 1, c]
    elsif c == "{" and prev == "#"
      [cons("code", stack), comma, commas, close, comment, false, i + 1, c]
    else
      [stack, comma, commas, close, comment, false, i + 1, c]
    end
  elsif c == "\""
    [cons("str", stack), comma, commas, close, comment, false, i + 1, c]
  elsif c == "#"
    [stack, comma, commas, close, true, false, i + 1, c]
  elsif member?(c, ["(", "[", "{"])
    [cons(c, stack), comma, commas, close, comment, false, i + 1, c]
  elsif member?(c, [")", "]", "}"])
    left = rest(stack)
    if first(left) == "root"
      [left, comma, commas, i, comment, false, i + 1, c]
    else
      [left, comma, commas, close, comment, false, i + 1, c]
    end
  elsif c == "," and length(stack) == 2
    at = if comma.nil?
      i
    else
      comma
    end
    [stack, at, commas + 1, close, comment, false, i + 1, c]
  else
    [stack, comma, commas, close, comment, false, i + 1, c]
  end
end

def scan_call(window)
  st = reduce(scan_step, [["root"], nil, 0, nil, false, false, 0, ""], window)
  [nth(1, st), nth(2, st), nth(3, st), nth(4, st)]
end

def scan_at(cs, open)
  reduce(
    fn(found, width)
      if found != nil
        found
      else
        s = scan_call(take(width, drop(open, cs)))
        if nth(2, s).nil?
          nil
        else
          s
        end
      end
    end,
    nil,
    [4000, 16000, 64000, 1_000_000]
  )
end

def starts_of(lines)
  reverse(
    first(
      reduce(
        (st, l) -> [cons(nth(1, st), first(st)), nth(1, st) + length(l) + 1],
        [[], 0],
        lines
      )
    )
  )
end

def offset_of(starts, line, column)
  nth(line - 1, starts) + column - 1
end

def flag(why)
  ["flag", why]
end

def site_plan(cs, starts, r)
  line = json_get(r, "line")
  name = surface(json_get(r, "written"))
  at = "line #{line}, `#{name}`"
  ns_key = json_get_or(json_get(r, "ns"), "key", "")
  flat_key = json_get_or(json_get(r, "flat"), "key", "")
  begin_at = offset_of(starts, line, json_get(r, "column"))
  end_at = offset_of(starts, json_get(r, "end_line"), json_get(r, "end_column"))
  if json_get(r, "position") != "call"
    flag("#{at}: not called here (#{json_get(r, "position")})")
  elsif ns_key != flat_key
    flag("#{at}: reached only because every definition is global (B0012)")
  elsif json_get(r, "argc") != 2
    flag("#{at}: called with #{json_get(r, "argc")} arguments")
  elsif join(take(end_at - begin_at, drop(begin_at, cs)), "") != name
    flag("#{at}: the source at its span does not read `#{name}`")
  elsif nth(end_at, cs) != "("
    flag("#{at}: no `(` follows the name")
  else
    s = scan_at(cs, end_at)
    if s.nil?
      flag("#{at}: the call does not close")
    elsif nth(3, s)
      flag("#{at}: a comment inside the call")
    elsif nth(1, s) != 1
      flag(
        "#{at}: #{nth(1, s) + 1} arguments written (a pipe, method or splat form)"
      )
    else
      ["plan", [end_at, first(s), nth(2, s)]]
    end
  end
end

def occurrences(t, needle, from)
  at = text_index(t, needle, from)
  if at < 0
    []
  else
    cons(at, occurrences(t, needle, at + 1))
  end
end

def begun(began, depth, i)
  if began.nil? and depth == 1
    i
  else
    began
  end
end

def sexp_step(st, c)
  i = first(st)
  depth = nth(1, st)
  str = nth(2, st)
  esc = nth(3, st)
  began = nth(4, st)
  items = nth(5, st)
  done = nth(6, st)
  if done
    st
  elsif str
    if esc
      [i + 1, depth, true, false, began, items, false]
    elsif c == "\\"
      [i + 1, depth, true, true, began, items, false]
    elsif c == "\"" and depth == 1
      [i + 1, depth, false, false, nil, cons([began, i + 1], items), false]
    else
      [i + 1, depth, c != "\"", false, began, items, false]
    end
  elsif c == "\""
    [i + 1, depth, true, false, begun(began, depth, i), items, false]
  elsif c == "("
    [i + 1, depth + 1, false, false, begun(began, depth, i), items, false]
  elsif c == ")"
    if depth == 2
      [i + 1, 1, false, false, nil, cons([began, i + 1], items), false]
    elsif depth == 1
      more = if began.nil?
        items
      else
        cons([began, i], items)
      end
      [i + 1, 0, false, false, nil, more, true]
    else
      [i + 1, depth - 1, false, false, began, items, false]
    end
  elsif blank_char?(c)
    if depth == 1 and began != nil
      [i + 1, 1, false, false, nil, cons([began, i], items), false]
    else
      [i + 1, depth, false, false, began, items, false]
    end
  elsif began.nil? and depth == 1
    [i + 1, depth, false, false, i, items, false]
  else
    [i + 1, depth, false, false, began, items, false]
  end
end

def sexp_items(cs, at)
  st = reduce(sexp_step, [at, 0, false, false, nil, [], false], drop(at, cs))
  reverse(nth(5, st))
end

def swap_sexp_at(cs, at)
  items = sexp_items(cs, at)
  if length(items) != 3
    nil
  else
    one = nth(1, items)
    two = nth(2, items)
    append(
      take(first(one), cs),
      take(nth(1, two) - first(two), drop(first(two), cs)),
      take(first(two) - nth(1, one), drop(nth(1, one), cs)),
      take(nth(1, one) - first(one), drop(first(one), cs)),
      drop(nth(1, two), cs)
    )
  end
end

def swap_heads(form, key)
  needle = "(#{key} "
  cs = chars(form)
  heads = reverse(
    filter(
      (p) -> p < 8 or join(take(8, drop(p - 8, cs)), "") != "(define ",
      occurrences(form, needle, 0)
    )
  )
  reduce(
    fn(st, p)
      moved = swap_sexp_at(first(st), p)
      if moved.nil?
        [first(st), nth(1, st) + 1_000_000]
      else
        [moved, nth(1, st) + 1]
      end
    end,
    [cs, 0],
    heads
  )
end

def swap_form(form, keys)
  st = reduce(
    fn(acc, key)
      r = swap_heads(join(first(acc), ""), key)
      [first(r), nth(1, acc) + nth(1, r)]
    end,
    [chars(form), 0],
    keys
  )
  [join(first(st), ""), nth(1, st)]
end

def swap_proof(before, after, keys, planned)
  moved = map((f) -> swap_form(unquoted(f), keys), settled_forms(before, "ns"))
  want = map((m) -> first(m), moved)
  count = reduce((n, m) -> n + nth(1, m), 0, moved)
  got = map(unquoted, settled_forms(after, "ns"))
  if count != planned
    "#{planned} call(s) rewritten but #{count} head(s) found in the resolved tree"
  elsif got != want
    pairs = filter((p) -> first(p) != nth(1, p), zip(want, got))
    if empty?(pairs)
      "#{length(want)} forms expected, #{length(got)} found"
    else
      "expected #{first(first(pairs))}, found #{nth(1, first(pairs))}"
    end
  end
end

def swap_file(file, keys)
  before = resolved(file)
  sites = filter(
    fn(r)
      member?(json_get_or(json_get(r, "ns"), "key", ""), keys) or
        member?(json_get_or(json_get(r, "flat"), "key", ""), keys)
    end,
    json_get(before, "references")
  )
  if empty?(sites)
    [true, "unchanged #{file}"]
  else
    text = read_file(file)
    cs = chars(text)
    starts = starts_of(split(text, "\n"))
    plans = map((r) -> site_plan(cs, starts, r), sites)
    flags = map((p) -> nth(1, p), filter((p) -> first(p) == "flag", plans))
    if not empty?(flags)
      [false, "flagged #{file}: #{join(flags, "; ")}"]
    else
      spots = distinct(map((p) -> nth(1, p), plans))
      ordered = sort_keyed((p) -> -first(p), spots)
      write_file(file, join(reduce(swap_args_at, cs, ordered), ""))
      run_blue(["fmt", "--write", file])
      after = resolved(file) rescue nil
      why = if after.nil?
        "the rewritten file does not resolve"
      else
        swap_proof(before, after, keys, length(spots))
      end
      if why.nil?
        [true, "swapped #{file}: #{length(spots)} call(s)"]
      else
        write_file(file, text)
        [false, "refused #{file}: #{why}; restored"]
      end
    end
  end
end

args = argv

if not empty?(args) and first(args) == "--swap"
  results = map((f) -> swap_file(f, split(nth(1, args), ",")), drop(2, args))
  map((r) -> write_stdout("#{nth(1, r)}\n"), results)
  if any?((r) -> not first(r), results)
    exit_with(1)
  end
elsif not empty?(args) and first(args) == "--strip"
  write_stdout("#{strip(nth(1, args), nth(2, args), drop(3, args))}\n")
else
  map((f) -> write_stdout("#{migrate(f)}\n"), args)
end
