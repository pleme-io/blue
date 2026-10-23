use(
  "mokuroku",
  [
    :blue_path_roots,
    :edges_tsv,
    :graph_baseline,
    :graph_findings,
    :graph_findings_live,
    :graph_from_tsv,
    :graph_load,
    :graph_shrunk,
    :graph_verdict,
    :graph_writes,
    :import_refusals,
    :untested_probe,
    :verbs_tsv,
    :vocab_tsv
  ]
)

use("retsu", [:concat_lists, :first, :is_empty, :size])
use("shisutemu", [:status_of, :stderr_of, :stdout_of])

def graph_dir_default()
  "bidamas/mokuroku/graph"
end

def baseline_name()
  "graph.baseline"
end

def flag_value(args, flag)
  at = filter((i) -> nth(i, args) == flag, range(length(args)))
  if is_empty(at) or first(at) + 1 >= length(args)
    nil
  else
    nth(first(at) + 1, args)
  end
end

def or_else(v, d)
  if v.nil?
    d
  else
    v
  end
end

def has_flag(args, flag)
  member?(flag, args)
end

def positional(args)
  value_flags = ["--dir", "--out", "--tsv", "--baseline"]
  keep = filter(
    fn(i)
      a = nth(i, args)
      not starts_with?(a, "--") and
        (i == 0 or not member?(nth(i - 1, args), value_flags))
    end,
    range(length(args))
  )
  map((i) -> nth(i, args), keep)
end

def show_refusals(refusals)
  map(
    (r) -> write_stderr("blue verbs: #{to_s(first(r))}: #{nth(1, r)}\n"),
    refusals
  )
  nil
end

def table_kind(text)
  head = first(split(text, "\n"))
  cols = split(head, "\t")
  if first(cols) == "region"
    :verbs
  elsif first(cols) == "from"
    :edges
  elsif first(cols) == "verb" and nth(1, cols) == "subject"
    :vocab
  end
end

def merged_tables(texts)
  head = first(split(first(texts), "\n"))
  if every?((t) -> first(split(t, "\n")) == head, texts)
    join(
      concat_lists(
        [first(texts)],
        map((t) -> join(drop(1, split(t, "\n")), "\n"), drop(1, texts))
      ),
      "\n"
    )
  end
end

def of_kind(tables, kind)
  map((t) -> nth(1, t), filter((t) -> first(t) == kind, tables))
end

def single(texts)
  if is_empty(texts)
    ""
  else
    merged_tables(texts)
  end
end

def format_files(paths)
  r = exec_capture(self_exe, "fmt", "--write", *paths)
  if status_of(r) != 0
    raise(:format, "blue fmt --write: #{stderr_of(r)}#{stdout_of(r)}")
  end
  nil
end

def do_import(args)
  dir = or_else(flag_value(args, "--dir"), graph_dir_default)
  files = positional(args)
  if is_empty(files)
    raise(:usage, "usage: blue verbs import [--dir DIR] TSV...")
  end
  tables = map((p) -> [table_kind(read_file(p)), read_file(p)], files)
  unknown = filter((i) -> first(nth(i, tables)).nil?, range(length(tables)))
  if not is_empty(unknown)
    show_refusals(
      map(
        fn(i)
          [
            :tsv_header,
            "#{nth(i, files)} is no verbs, edges or contracts table"
          ]
        end,
        unknown
      )
    )
    false
  else
    verbs = of_kind(tables, :verbs)
    edges = of_kind(tables, :edges)
    vocab = of_kind(tables, :vocab)
    vocab_text = if is_empty(vocab)
      vocab_tsv(graph_load(dir))
    else
      merged_tables(vocab)
    end
    g = graph_from_tsv(single(verbs), single(edges), vocab_text)
    refusals = import_refusals(g)
    if not is_empty(refusals)
      show_refusals(refusals)
      write_stderr(
        "blue verbs: nothing written: #{to_s(size(refusals))} refusals\n"
      )
      false
    else
      mkdir_p(dir)
      written = map(
        fn(w)
          path = path_join(dir, first(w))
          write_file(path, nth(1, w))
          path
        end,
        graph_writes(g)
      )
      format_files(written)
      write_stdout(
        "imported #{to_s(size(get(g, :verbs)))} verbs, #{to_s(size(get(g, :edges)))} edges and #{to_s(size(get(g, :vocab)))} vocab rows into #{to_s(size(written))} files in #{dir}\n"
      )
      true
    end
  end
end

def do_export(args)
  dir = or_else(flag_value(args, "--dir"), graph_dir_default)
  out = flag_value(args, "--out")
  if out.nil?
    raise(:usage, "usage: blue verbs export [--dir DIR] --out DIR")
  end
  g = graph_load(dir)
  if not is_empty(get(g, :refusals))
    show_refusals(get(g, :refusals))
    false
  else
    mkdir_p(out)
    write_file(path_join(out, "verbs.tsv"), verbs_tsv(g))
    write_file(path_join(out, "edges.tsv"), edges_tsv(g))
    write_file(path_join(out, "contracts.tsv"), vocab_tsv(g))
    write_stdout(
      "exported #{to_s(size(get(g, :verbs)))} verbs, #{to_s(size(get(g, :edges)))} edges and #{to_s(size(get(g, :vocab)))} vocab rows to #{out}\n"
    )
    true
  end
end

def finding_line(f)
  "#{get(f, :kind)}\t#{get(f, :subject)}\n"
end

def do_findings(args)
  tsv = flag_value(args, "--tsv")
  if tsv.nil?
    raise(:usage, "usage: blue verbs findings --tsv DIR")
  end
  g = graph_from_tsv(
    read_file(path_join(tsv, "verbs.tsv")),
    read_file(path_join(tsv, "edges.tsv")),
    read_file(path_join(tsv, "contracts.tsv"))
  )
  if not is_empty(get(g, :refusals))
    show_refusals(get(g, :refusals))
    false
  else
    write_stdout(join(map(finding_line, graph_findings(g)), ""))
    true
  end
end

def do_untested(args)
  dir = or_else(flag_value(args, "--dir"), graph_dir_default)
  g = graph_load(dir)
  if not is_empty(get(g, :refusals))
    show_refusals(get(g, :refusals))
    false
  else
    write_stdout(
      join(
        map(
          finding_line,
          untested_probe(g, blue_path_roots(getenv("BLUE_PATH", "")))
        ),
        ""
      )
    )
    true
  end
end

def do_check(args)
  dir = or_else(flag_value(args, "--dir"), graph_dir_default)
  baseline = or_else(
    flag_value(args, "--baseline"),
    path_join(dir, baseline_name)
  )
  g = graph_load(dir)
  if not is_empty(get(g, :refusals))
    show_refusals(get(g, :refusals))
    false
  else
    findings = graph_findings_live(g, self_exe)
    if has_flag(args, "--record")
      write_file(baseline, graph_baseline(findings))
      write_stdout("recorded #{to_s(size(findings))} findings in #{baseline}\n")
      true
    else
      text = if path_exists(baseline)
        read_file(baseline)
      else
        ""
      end
      failures = graph_verdict(findings, text)
      shrunk = graph_shrunk(findings, text)
      write_stdout(
        "#{to_s(size(get(g, :verbs)))} verbs, #{to_s(size(get(g, :edges)))} edges, #{to_s(size(get(g, :vocab)))} vocab rows; #{to_s(size(findings))} findings against the baseline\n"
      )
      if not is_empty(shrunk)
        write_stdout(
          "the baseline can shrink (blue verbs check --record): #{join(shrunk, ", ")}\n"
        )
      end
      if is_empty(failures)
        true
      else
        show_refusals(failures)
        false
      end
    end
  end
end

def main(args)
  cmd = if is_empty(args)
    ""
  else
    first(args)
  end
  rest_args = drop(1, args)
  if cmd == "import"
    do_import(rest_args)
  elsif cmd == "export"
    do_export(rest_args)
  elsif cmd == "check"
    do_check(rest_args)
  elsif cmd == "findings"
    do_findings(rest_args)
  elsif cmd == "untested"
    do_untested(rest_args)
  else
    raise(:usage, "usage: blue verbs import|export|check|findings|untested ...")
  end
end

main(argv)
