use("hadome", %i[measurement orphans parse recorded render])

use("heni", %i[fell? mutations report_text run score sound? survivors])

use("moji", %i[includes trim])
use("mokuroku", [:blue_path_roots])
use("retsu", %i[find_first flat_map is_empty last reject size])
use("shisutemu", [:read_or])
use("shuugou", [:unique])

CAUGHT = "heni-caught"

TOTAL = "heni-total"

RECORD = "blue gen/heni-gate.b record"

def off?()
  v = getenv("BLUE_HENI_OFF")
  if v.nil?
    false
  elsif v == "1"
    true
  else
    raise(:heni_gate, "BLUE_HENI_OFF is \"#{v}\"; the one value it takes is 1")
  end
end

def bidamas_root()
  here = find_first(
    (r) -> path_exists(path_join(r, "heni/mutations")),
    blue_path_roots(getenv("BLUE_PATH", ""))
  )
  if here.nil?
    "bidamas"
  else
    here
  end
end

def specs()
  reject(
    (p) -> not ends_with?(p, ".json"),
    sort_keyed((p) -> p, walk_dir(path_join(bidamas_root, "heni/mutations")))
  )
end

def name_of(spec_path)
  last(split(spec_path, "heni/mutations/"))
end

def key_of(spec_path)
  replace(name_of(spec_path), ".json", "")
end

def chosen(all, want)
  if want.nil?
    all
  else
    hit = filter((s) -> name_of(s) == want, all)
    if is_empty(hit)
      raise(
        :heni_gate,
        "HENI_SPEC is \"#{want}\"; no file heni/mutations/#{want} exists"
      )
    else
      hit
    end
  end
end

def package_of(spec_path)
  path_join(bidamas_root, key_of(spec_path))
end

def baseline_path()
  path_join(bidamas_root, "heni/ratio.baseline")
end

def report(spec_path)
  run(
    {
      package: package_of(spec_path),
      mutations: mutations(json_parse(read_file(spec_path))),
      blue: self_exe,
      test: nil,
      tmp: getenv("TMPDIR", "/tmp")
    }
  )
end

def ratio_text(q)
  "#{to_s(q[:caught])}/#{to_s(q[:total])}"
end

def recorded_ratio(rows, key)
  c = recorded(rows, CAUGHT, key)
  t = recorded(rows, TOTAL, key)
  if c.nil? or t.nil?
    nil
  else
    {caught: c, total: t}
  end
end

def survived_text(r)
  names = survivors(r)
  if is_empty(names)
    "no survivor, so a caught mutation was removed"
  else
    "survived: #{join(names, ", ")}"
  end
end

def problems(rows, key, r)
  if not sound?(r)
    ["#{key}: #{trim(report_text(r))}"]
  else
    was = recorded_ratio(rows, key)
    now = score(r)
    if was.nil?
      [
        "#{key}: caught #{ratio_text(now)} and the baseline has no row for it; record it: #{RECORD}"
      ]
    elsif fell?(was, now)
      [
        "#{key}: caught #{ratio_text(now)}, below its recorded #{ratio_text(was)}; #{survived_text(r)}"
      ]
    else
      []
    end
  end
end

def rose?(rows, key, r)
  was = recorded_ratio(rows, key)
  was != nil and sound?(r) and fell?(score(r), was)
end

def measure(paths)
  map((s) -> {key: key_of(s), r: report(s)}, paths)
end

def judge(rows, measured)
  flat_map(measured, (m) -> problems(rows, m[:key], m[:r]))
end

def advisories(rows, measured, keys)
  append(
    map(
      (m) -> "#{m[:key]}: caught ratio rose; bank it: #{RECORD}",
      filter((m) -> rose?(rows, m[:key], m[:r]), measured)
    ),
    map(
      fn(k)
        "#{k}: recorded, and no mutation file names it; drop it: #{RECORD}"
      end,
      orphans(rows, CAUGHT, keys)
    )
  )
end

def rendered(measured)
  entries(measured, [])
end

@doc """
kept: the rows of a baseline whose key no measured package names, as entries, so a run that measured one spec rewrites that spec's rows and keeps every other.

    kept(parse("heni-caught: a 1\nheni-total: a 2\n"), []) #=> [{key: "a", caught: 1, total: 2}]
"""
def kept(rows, measured)
  names = map((m) -> m[:key], measured)
  map(
    fn(k)
      {
        key: k,
        caught: recorded(rows, CAUGHT, k),
        total: recorded(rows, TOTAL, k)
      }
    end,
    reject((k) -> member?(k, names), unique(map((r) -> r[:key], rows)))
  )
end

def entries(measured, others)
  join(
    map(
      fn(e)
        concat(
          render(CAUGHT, [measurement(e[:key], e[:caught])]),
          render(TOTAL, [measurement(e[:key], e[:total])])
        )
      end,
      sort_keyed(
        (e) -> e[:key],
        append(
          others,
          map(
            fn(m)
              q = score(m[:r])
              {key: m[:key], caught: q[:caught], total: q[:total]}
            end,
            measured
          )
        )
      )
    ),
    ""
  )
end

def baseline_text(old, receipt, measured, partial)
  notes = append(
    filter((l) -> starts_with?(l, "#"), split(old, line_break)),
    if receipt.nil?
      []
    else
      ["# receipt: #{receipt}"]
    end
  )
  body = if partial
    entries(measured, kept(parse(old), measured))
  else
    rendered(measured)
  end
  if is_empty(notes)
    body
  else
    concat(unlines(notes), body)
  end
end

def receipt_of(args)
  at = position("--receipt", args)
  if at < 0
    nil
  else
    args[at + 1] rescue nil
  end
end

def record(receipt)
  path = baseline_path
  old = read_or(path, "")
  rows = parse(old)
  want = getenv("HENI_SPEC")
  measured = measure(chosen(specs, want))
  unsound = filter((m) -> not sound?(m[:r]), measured)
  fell = filter(
    fn(m)
      was = recorded_ratio(rows, m[:key])
      was != nil and fell?(was, score(m[:r]))
    end,
    measured
  )
  if not is_empty(unsound)
    write_stderr(unlines(judge([], unsound)))
    write_stderr(unlines(["refused: a run that is not sound records nothing"]))
    exit_with(1)
  elsif not is_empty(fell) and receipt.nil?
    write_stderr(unlines(judge(rows, fell)))
    write_stderr(
      unlines(["refused: a fall needs a reason: #{RECORD} --receipt \"<why>\""])
    )
    exit_with(1)
  else
    write_file(path, baseline_text(old, receipt, measured, not want.nil?))
    write_stdout(
      unlines(["recorded #{to_s(size(measured))} package(s) to #{path}"])
    )
  end
end

def main()
  if argv_get(0) == "record"
    record(receipt_of(drop(1, argv)))
  else
    write_stderr(unlines(["usage: #{RECORD} [--receipt WHY]"]))
    exit_with(64)
  end
end

test "every package holds its recorded caught ratio"
  if not off?
    assert size(specs) >= 2
    rows = parse(read_or(baseline_path, ""))
    measured = measure(chosen(specs, getenv("HENI_SPEC")))
    map(
      (a) -> write_stderr(unlines([a])),
      advisories(rows, measured, map(key_of, specs))
    )
    bad = judge(rows, measured)
    if not is_empty(bad)
      write_stderr(unlines(bad))
    end
    assert is_empty(bad)
  end
end

test "a mutation file names the package it mutates"
  assert package_of("heni/mutations/shuusei.json") ==
    path_join(bidamas_root, "shuusei")
  assert package_of("bidamas/heni/mutations/mitoshi/keisoku.json") ==
    path_join(bidamas_root, "mitoshi/keisoku")
  assert key_of("bidamas/heni/mutations/mitoshi/keisoku.json") ==
    "mitoshi/keisoku"
end

def fixture_run(verdicts)
  {
    control: 0,
    refused: 0,
    blind: 0,
    results: map((v) -> {name: "m-#{to_s(v[0])}", verdict: v[1]}, verdicts)
  }
end

test "a survivor below the recorded ratio names its package and itself"
  rows = parse(unlines(["heni-caught: kazu 2", "heni-total: kazu 2"]))
  held = fixture_run([[0, :caught], [1, :caught]])
  assert judge(rows, [{key: "kazu", r: held}]) == []
  fell = fixture_run([[0, :caught], [1, :survived]])
  assert judge(rows, [{key: "kazu", r: fell}]) ==
    ["kazu: caught 1/2, below its recorded 2/2; survived: m-1"]
  grown = fixture_run([[0, :caught], [1, :caught], [2, :survived]])
  assert judge(rows, [{key: "kazu", r: grown}]) ==
    ["kazu: caught 2/3, below its recorded 2/2; survived: m-2"]
  assert judge([], [{key: "kazu", r: held}]) ==
    ["kazu: caught 2/2 and the baseline has no row for it; record it: blue gen/heni-gate.b record"]
  refused = assoc(held, :refused, 1)
  assert size(judge(rows, [{key: "kazu", r: refused}])) == 1
end

test "a record of one spec rewrites that spec's rows and keeps every other"
  old = unlines(
    [
      "# receipt: before",
      "heni-caught: alpha 3",
      "heni-total: alpha 4",
      "heni-caught: kazu 1",
      "heni-total: kazu 1"
    ]
  )
  held = fixture_run([[0, :caught], [1, :caught]])
  text = baseline_text(old, nil, [{key: "kazu", r: held}], true)
  assert text ==
    unlines(
      [
        "# receipt: before",
        "heni-caught: alpha 3",
        "heni-total: alpha 4",
        "heni-caught: kazu 2",
        "heni-total: kazu 2"
      ]
    )
  whole = baseline_text(old, nil, [{key: "kazu", r: held}], false)
  assert not includes(whole, "alpha")
  assert kept(parse(old), [{key: "alpha", r: held}]) ==
    [{key: "kazu", caught: 1, total: 1}]
end

test "a recorded survivor holds, and the baseline round-trips"
  rows = parse(unlines(["heni-caught: kazu 1", "heni-total: kazu 2"]))
  debt = fixture_run([[0, :caught], [1, :survived]])
  assert judge(rows, [{key: "kazu", r: debt}]) == []
  text = baseline_text(
    "# receipt: first",
    "second",
    [{key: "kazu", r: debt}],
    false
  )
  assert text ==
    unlines(
      [
        "# receipt: first",
        "# receipt: second",
        "heni-caught: kazu 1",
        "heni-total: kazu 2"
      ]
    )
  assert recorded_ratio(parse(text), "kazu") == {caught: 1, total: 2}
  better = fixture_run([[0, :caught], [1, :caught]])
  assert advisories(rows, [{key: "kazu", r: better}], ["kazu"]) ==
    ["kazu: caught ratio rose; bank it: blue gen/heni-gate.b record"]
  assert advisories(rows, [], []) ==
    ["kazu: recorded, and no mutation file names it; drop it: blue gen/heni-gate.b record"]
end

test "HENI_SPEC measures the one spec it names, refuses a name with no spec, and unset measures all"
  all = %w[b/heni/mutations/kazu.json b/heni/mutations/mitoshi/keisoku.json]
  assert chosen(all, nil) == all
  assert chosen(all, "mitoshi/keisoku.json") ==
    ["b/heni/mutations/mitoshi/keisoku.json"]
  assert chosen(all, "kazu.json") == ["b/heni/mutations/kazu.json"]
  refused = begin
    chosen(all, "mitoshi/keisoku")
  rescue e
    e.message
  end
  assert refused ==
    "HENI_SPEC is \"mitoshi/keisoku\"; no file heni/mutations/mitoshi/keisoku exists"
end
