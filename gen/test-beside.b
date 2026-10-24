use("hadome", [:judge, :parse, :render, :shrunk])
use("mokuroku", [:blue_path_roots, :package_dirs])
use("retsu", [:concat_lists, :find_first, :flat_map, :last, :size])
use("tesuto", [:beside, :level, :settle, :stale, :uncovered, :waive])

# Tests live beside what they test (docs/TESTING.md). Every bidama's
# definitions are reached by a test in the same package, or the gap is a
# waiver here with a why and an until date, or it is debt recorded below. The
# entries are the configuration: each is judged alone, a bad one is refused
# and named, its siblings stand. `level("*", :off, why)` turns the gate off.

def entries()
  [
    level(
      "*",
      :enforce,
      "a definition is reached by a test beside it; recorded debt may shrink, never grow"
    )
  ]
end

# Untested definitions per bidama, measured by `blue test --coverage` on
# 2026-10-24. A row may shrink or hold, never grow; a package with no row
# holds at zero.
def recorded()
  "untested: bougyo 1\nuntested: danpen 1\nuntested: deeta 3\nuntested: empresa 2\nuntested: gitto 1\nuntested: gyouretsu 1\nuntested: haibi 1\nuntested: heni 2\nuntested: hyouka 9\nuntested: jitaku 11\nuntested: kakou 2\nuntested: keisoku 6\nuntested: keiyu 1\nuntested: kijun 9\nuntested: kikagaku 1\nuntested: kinji 2\nuntested: kinko 5\nuntested: kirikae 16\nuntested: kiwari 14\nuntested: kousei 1\nuntested: kueri 7\nuntested: kyuuji 2\nuntested: mokuroku 8\nuntested: nikkusu 1\nuntested: okite 1\nuntested: outou 11\nuntested: raifusaikuru 25\nuntested: retsu 2\nuntested: rittai 6\nuntested: rogu 5\nuntested: ryouiki 1\nuntested: sabi 2\nuntested: settei 5\nuntested: shinchoku 14\nuntested: shinsuu 1\nuntested: souji 5\nuntested: teeburu 3\nuntested: tehai 1\nuntested: touroku 3\nuntested: tsuushin 1\nuntested: ukai 16\nuntested: zumen 1\n"
end

def today()
  join(take(10, chars(now_rfc3339)), "")
end

def bidamas_root()
  here = find_first(
    (r) -> path_exists(path_join(r, "tesuto/Bluefile")),
    blue_path_roots(getenv("BLUE_PATH", ""))
  )
  if here.nil?
    "bidamas"
  else
    here
  end
end

def records_of(text)
  map(
    json_read,
    filter((l) -> starts_with?(l, "{\"covered\""), split(text, "\n"))
  )
end

# One package measured: the names its tests do not reach, or blind when its
# tests did not run green (no evidence is not a pass).
def measure(exe, dir)
  package = last(split(dir, "/"))
  cap = exec_capture(exe, "test", dir, "--coverage", "--json")
  if json_get(cap, :status) != 0
    {package:, blind: true}
  else
    {
      package:,
      blind: false,
      names: flat_map(records_of(json_get(cap, :stdout)), uncovered)
    }
  end
end

def measure_all(exe, root)
  map((d) -> measure(exe, d), sort_keyed((d) -> d, package_dirs(root)))
end

# Each package's verdict: off, green, red or blind, with the reason.
def verdict(settled, rows, m)
  pkg = get(m, :package)
  if get(m, :blind)
    b = beside(settled, pkg, [])
    if get(b, :level) == :off
      assoc(b, :verdict, :off)
    elsif get(b, :level) == :enforce
      assoc(assoc(b, :verdict, :red), :why, "its tests did not run green")
    else
      assoc(assoc(b, :verdict, :blind), :why, "its tests did not run green")
    end
  else
    b = beside(settled, pkg, get(m, :names))
    n = size(get(b, :untested))
    j = get(judge(rows, "untested", pkg, n), :verdict)
    grew = j == :grew or j == :unrecorded and n > 0
    if get(b, :level) == :off
      assoc(b, :verdict, :off)
    elsif grew and get(b, :level) == :enforce
      assoc(
        assoc(b, :verdict, :red),
        :why,
        "#{to_s(n)} untested beyond the recorded debt: #{join(get(b, :untested), ", ")}"
      )
    else
      assoc(b, :verdict, :green)
    end
  end
end

# The whole judgement: every package's verdict, every refused entry and
# every stale waiver. Red is any enforced red, any refused entry, any stale
# waiver.
def judge_all(entries, baseline, measured, day)
  settled = settle(entries, day)
  rows = parse(baseline)
  verdicts = map((m) -> verdict(settled, rows, m), measured)
  every_name = flat_map(measured, (m) -> get(m, :names) or [])
  {
    verdicts:,
    refused: get(settled, :refused),
    stale: stale(settled, every_name),
    red: filter((v) -> get(v, :verdict) == :red, verdicts),
    measurements: map(
      (v) -> {key: get(v, :package), size: size(get(v, :untested))},
      filter((v) -> get(v, :verdict) != :off, verdicts)
    )
  }
end

def red?(r)
  get(r, :red) != [] or get(r, :refused) != [] or get(r, :stale) != []
end

def report(r, baseline)
  lines = concat_lists(
    concat_lists(
      map((v) -> "❌ #{get(v, :package)}: #{get(v, :why)}", get(r, :red)),
      map(
        (x) -> "❌ entry #{to_s(get(x, :entry))} #{get(x, :why)}",
        get(r, :refused)
      )
    ),
    map(
      (w) -> "❌ waiver #{get(w, :name)} covers nothing; remove it",
      get(r, :stale)
    )
  )
  down = shrunk(parse(baseline), "untested", get(r, :measurements))
  hint = if down == []
    ""
  else
    "debt shrank; record it in gen/test-beside.b:\n#{render("untested", filter((m) -> get(m, :size) > 0, get(r, :measurements)))}"
  end
  "#{join(lines, "\n")}\n#{hint}"
end

def zed_root(source)
  root = path_join(
    getenv("TMPDIR", "/tmp"),
    "test-beside-zed-#{blake3_hex(source)}"
  )
  rm_rf(root)
  mkdir_p(path_join(root, "zed"))
  write_file(path_join(root, "zed/Bluefile"), "package(\"zed\", \"0.1.0\")\n")
  write_program(path_join(root, "zed/zed.b"), source)
  root
end

def zed(tests)
  "def lower(s)\n  s\nend\n\ndef upper(s)\n  s\nend\n\n#{tests}"
end

def zed_judged(entries, baseline, tests)
  root = zed_root(zed(tests))
  r = judge_all(entries, baseline, measure_all(self_exe, root), "2026-10-24")
  rm_rf(root)
  r
end

def lower_only()
  "test \"lower\"\n  assert lower(\"A\") == \"A\"\nend\n"
end

def both()
  "test \"both\"\n  assert lower(\"A\") == \"A\"\n  assert upper(\"a\") == \"a\"\nend\n"
end

test "an untested definition with no recorded debt is red, and its test beside it turns it green"
  red = zed_judged(entries, "", lower_only)
  assert red?(red)
  assert map((v) -> get(v, :why), get(red, :red)) ==
    ["1 untested beyond the recorded debt: zed::upper"]
  assert not red?(zed_judged(entries, "", both))
end

test "recorded debt holds, and growth past it is red"
  assert not red?(zed_judged(entries, "untested: zed 1\n", lower_only))
  grew = zed_judged(
    entries,
    "untested: zed 1\n",
    "test \"none\"\n  assert 1 == 1\nend\n"
  )
  assert map((v) -> get(v, :why), get(grew, :red)) ==
    ["2 untested beyond the recorded debt: zed::lower, zed::upper"]
end

test "a waiver with a why and a date covers its definition; without a why it is refused and the gap stays red"
  w = [waive("zed::upper", "the fixture's second word", "2026-12-31")]
  assert not red?(zed_judged(concat_lists(entries, w), "", lower_only))
  bad = zed_judged(
    concat_lists(entries, [waive("zed::upper", "", "2026-12-31")]),
    "",
    lower_only
  )
  assert size(get(bad, :refused)) == 1
  assert size(get(bad, :red)) == 1
end

test "a waiver that covers nothing is stale and red"
  w = [waive("zed::gone", "removed long ago", "2026-12-31")]
  r = zed_judged(concat_lists(entries, w), "", both)
  assert map((x) -> get(x, :name), get(r, :stale)) == ["zed::gone"]
  assert red?(r)
end

test "audit lists the gap without red, and off measures nothing"
  audit = zed_judged([level("*", :audit, "a trial")], "", lower_only)
  assert not red?(audit)
  assert map((v) -> get(v, :untested), get(audit, :verdicts)) ==
    [["zed::upper"]]
  off = zed_judged([level("zed", :off, "the fixture is off")], "", "")
  assert not red?(off)
  assert get(off, :measurements) == []
end

test "a package whose tests fail is blind, never green"
  r = zed_judged(
    entries,
    "",
    "test \"no\"\n  assert lower(\"A\") == \"B\"\nend\n"
  )
  assert map((v) -> get(v, :why), get(r, :red)) ==
    ["its tests did not run green"]
end

test "every bidama is tested beside its definitions, beyond the debt recorded"
  r = judge_all(entries, recorded, measure_all(self_exe, bidamas_root), today)
  if red?(r)
    write_stderr(report(r, recorded))
  end
  assert size(get(r, :verdicts)) > 50
  assert not red?(r)
end
