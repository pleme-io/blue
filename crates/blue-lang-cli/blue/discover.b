use(
  "gaisou",
  %i[
    candidates
    changes
    consumer_owed
    contradicted
    counts
    decide
    groups
    history_edges
    history_rows
    pair_edges
    registry_edges
    render
  ]
)

use("moji", %i[after_first lines starts_with trim])
use("retsu", %i[first index_of is_empty last size])
use("settei")
use("shisutemu", %i[read_or status_of stderr_of stdout_of])

def json_lines(path)
  map(json_read, filter((l) -> trim(l) != "", lines(read_file(path))))
end

def debts_line(debts)
  join(
    map(
      (e) -> "#{first(e)}=#{to_s(e[1])}",
      sort_keyed((e) -> first(e), map_entries(debts))
    ),
    " "
  )
end

def debts_of(rules)
  reduce((acc, r) -> assoc(acc, r["code"], r["debt"]), {}, rules)
end

def discover(args)
  root = args[1]
  facts = json_lines(args[2])
  registry = json_read(read_file(args[3]))
  s = settei::settled("gaisou", gaisou::settings)
  rules = filter((f) -> f["fact"] == "rule", facts)
  codes = map((r) -> r["code"], rules)
  forms = first(filter((f) -> f["fact"] == "forms", facts))
  sites = filter(
    (f) -> f["fact"] == "site" and member?(f["code"], codes),
    facts
  )
  owed = groups(
    map((f) -> ["#{f["file"]}:#{to_s(f["line"])}", f["code"]], sites)
  )
  consumers_text = read_or(path_join(root, "gen/consumers.b"), nil)
  consumer_files = if consumers_text.nil?
    []
  else
    consumer_owed(consumers_text, codes)
  end
  history_text = read_or(path_join(root, "gen/obligation-debt.tsv"), nil)
  moved = if history_text.nil?
    []
  else
    changes(history_rows(history_text))
  end
  edges = append(
    pair_edges("census", counts(owed, forms["forms"]), s),
    pair_edges("consumers", counts(consumer_files, size(consumer_files)), s),
    history_edges(moved, s),
    registry_edges(rules)
  )
  seen = {
    "census" => distinct(map((f) -> f["code"], sites)),
    "consumers" => distinct(flatten(consumer_files)),
    "history" => distinct(
      flatten(map((c) -> map(first, map_entries(c)), moved))
    ),
    "registry" => codes
  }
  rows = decide(edges, registry["kinds"], registry["relations"], seen, s)
  gone = contradicted(rows, registry["relations"])
  waived = map(
    (f) -> [f["code"], f["reason"]],
    filter((f) -> f["state"] == "waived", sites)
  )
  report = {
    sources: [
      {
        source: "census",
        sites: size(owed),
        denominator: "#{to_s(forms["forms"])} top-level forms in #{to_s(forms["files"])} files"
      },
      {
        source: "consumers",
        sites: size(consumer_files),
        denominator: if consumers_text.nil?
          "blind: gen/consumers.b absent"
        else
          "consumer files with a refused row of a node code (names withheld)"
        end
      },
      {
        source: "history",
        sites: size(moved),
        denominator: if history_text.nil?
          "blind: gen/obligation-debt.tsv absent"
        else
          "changes that moved a debt, of #{to_s(size(history_rows(history_text)))} rows"
        end
      },
      {
        source: "registry",
        sites: size(rules),
        denominator: "rules that are obligations or ratcheted"
      }
    ],
    rows:,
    candidates: candidates(rules, rows, waived, registry["candidates"], s),
    contradicted: gone,
    settings: s
  }
  text = if member?("--json", args)
    json_stringify(report)
  else
    render(report)
  end
  at = index_of(args, "--check")
  against = if at < 0
    nil
  else
    args[at + 1]
  end
  if against.nil?
    write_stdout(text)
    is_empty(gone)
  else
    same = read_or(against, nil) == text
    if not same
      write_stderr(
        unlines(
          [
            "blue obligations discover: #{against} is stale against the corpus; regenerate it"
          ]
        )
      )
    end
    if not is_empty(gone)
      write_stderr(
        unlines(
          [
            "blue obligations discover: live rows the corpus no longer shows: #{join(gone, ", ")}"
          ]
        )
      )
    end
    same and is_empty(gone)
  end
end

def scan_rules(text)
  get(
    reduce(
      fn(acc, l)
        t = trim(l)
        if starts_with(l, "    B") and
            size(t) == 7 and
            after_first(t, " ") == "{"
          assoc(acc, :cur, first(split(t, " ")))
        elsif starts_with(t, "ratchet: ") and acc[:cur] != nil
          assoc(
            acc,
            :debt,
            assoc(
              acc[:debt],
              acc[:cur],
              to_int(trim(replace(after_first(t, ": "), ",", "")))
            )
          )
        else
          acc
        end
      end,
      {cur: nil, debt: {}},
      lines(text)
    ),
    :debt
  )
end

def scan_held(text)
  get(
    reduce(
      fn(acc, l)
        t = trim(l)
        if starts_with(t, "refusal: Code(Code::")
          assoc(acc, :cur, first(split(after_first(t, "Code::"), ")")))
        elsif starts_with(t, "\"")
          assoc(acc, :cur, nil)
        elsif starts_with(t, "held: ") and acc[:cur] != nil
          assoc(
            acc,
            :held,
            assoc(
              acc[:held],
              acc[:cur],
              to_int(trim(replace(after_first(t, ": "), ",", "")))
            )
          )
        elsif starts_with(t, "owner: ") and acc[:cur] != nil
          assoc(
            acc,
            :held,
            assoc(acc[:held], acc[:cur], get(acc[:held], acc[:cur]) or 0)
          )
        else
          acc
        end
      end,
      {cur: nil, held: {}},
      lines(text)
    ),
    :held
  )
end

def debts_at(rules_text, obligations_text)
  held = scan_held(obligations_text)
  reduce(
    (acc, e) -> assoc(acc, first(e), (get(acc, first(e)) or 0) + e[1]),
    scan_rules(rules_text),
    map_entries(held)
  )
end

def git_text(rev, path)
  r = exec_capture("git", "show", "#{rev}:#{path}")
  if status_of(r) == 0
    stdout_of(r)
  else
    ""
  end
end

def backfill()
  log = exec_capture(
    "git",
    "log",
    "--first-parent",
    "--reverse",
    "--format=%h",
    "-Gratchet: [0-9]|held: [0-9]",
    "HEAD",
    "--",
    "crates/blue-lang-check/src/rules.rs",
    "crates/blue-lang-check/src/obligations.rs"
  )
  if status_of(log) != 0
    raise(:history, "git log failed: #{stderr_of(log)}")
  end
  revs = filter((l) -> trim(l) != "", lines(stdout_of(log)))
  map(
    fn(rev)
      debts = debts_at(
        git_text(rev, "crates/blue-lang-check/src/rules.rs"),
        git_text(rev, "crates/blue-lang-check/src/obligations.rs")
      )
      ["git:#{rev}", debts]
    end,
    revs
  )
end

HEADER = "# seq\torigin\tdebt per code (ratchet + held), one row per change that moved one; gen/obligation-debt.b appends, blue obligations history --backfill rebuilds from git"

def history(args)
  now = debts_of(json_lines(args[2]))
  kept = if member?("--backfill", args)
    backfill
  else
    text = read_or(args[1], nil)
    if text.nil?
      []
    else
      map(
        (l) -> [split(l, "\t")[1], last(split(l, "\t"))],
        filter((l) -> trim(l) != "" and not starts_with(l, "#"), lines(text))
      )
    end
  end
  rendered = map(
    fn(row)
      if string?(row[1])
        row
      else
        [row[0], debts_line(row[1])]
      end
    end,
    kept
  )
  current = debts_line(now)
  rows = if not is_empty(rendered) and last(last(rendered)) == current
    rendered
  else
    append(rendered, [["regen", current]])
  end
  write_stdout(
    unlines(
      append(
        [HEADER],
        map(
          (i) -> "#{to_s(i + 1)}\t#{rows[i][0]}\t#{rows[i][1]}",
          range(size(rows))
        )
      )
    )
  )
  true
end

def main(args)
  if first(args) == "history"
    history(args)
  else
    discover(args)
  end
end

main(argv)
