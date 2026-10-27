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

# The distribution's waivers: each names one definition no test can reach,
# with why and until when.
def waivers()
  [
    waive(
      "koutei::fail",
      "it ends the process with exit_with(1); the blue actions in pleme-io/actions run it on every failing step",
      "2027-01-31"
    )
  ]
end

# Untested definitions per bidama, measured by `blue test --coverage` on
# 2026-10-24. A row may shrink or hold, never grow; a package with no row
# holds at zero.
def recorded()
  unlines(
    [
      "untested: bougyo 1",
      "untested: danpen 1",
      "untested: deeta 3",
      "untested: empresa 2",
      "untested: gitto 1",
      "untested: gyouretsu 1",
      "untested: haibi 1",
      "untested: heni 2",
      "untested: hyouka 9",
      "untested: jitaku 11",
      "untested: kakou 2",
      "untested: keisoku 6",
      "untested: keiyu 1",
      "untested: kijun 9",
      "untested: kikagaku 1",
      "untested: kinji 2",
      "untested: kinko 5",
      "untested: kirikae 16",
      "untested: kiwari 14",
      "untested: kousei 1",
      "untested: kueri 7",
      "untested: kyuuji 2",
      "untested: mokuroku 8",
      "untested: nikkusu 1",
      "untested: okite 1",
      "untested: outou 11",
      "untested: raifusaikuru 25",
      "untested: retsu 2",
      "untested: rittai 6",
      "untested: rogu 5",
      "untested: ryouiki 1",
      "untested: sabi 2",
      "untested: settei 5",
      "untested: shinchoku 14",
      "untested: shinsuu 1",
      "untested: souji 5",
      "untested: teeburu 3",
      "untested: tehai 1",
      "untested: touroku 3",
      "untested: tsuushin 1",
      "untested: ukai 16",
      "untested: zumen 1"
    ]
  )
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
    filter((l) -> starts_with?(l, "{\"covered\""), split(text, line_break))
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
  pkg = m[:package]
  if m[:blind]
    b = beside(settled, pkg, [])
    if b[:level] == :off
      assoc(b, :verdict, :off)
    elsif b[:level] == :enforce
      assoc(assoc(b, :verdict, :red), :why, "its tests did not run green")
    else
      assoc(assoc(b, :verdict, :blind), :why, "its tests did not run green")
    end
  else
    b = beside(settled, pkg, m[:names])
    n = size(b[:untested])
    j = judge(rows, "untested", pkg, n)[:verdict]
    grew = j == :grew or j == :unrecorded and n > 0
    if b[:level] == :off
      assoc(b, :verdict, :off)
    elsif grew and b[:level] == :enforce
      assoc(
        assoc(b, :verdict, :red),
        :why,
        "#{to_s(n)} untested beyond the recorded debt: #{join(b[:untested], ", ")}"
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
  every_name = flat_map(measured, (m) -> m[:names] or [])
  {
    verdicts:,
    refused: settled[:refused],
    stale: stale(settled, every_name),
    red: filter((v) -> v[:verdict] == :red, verdicts),
    measurements: map(
      (v) -> {key: v[:package], size: size(v[:untested])},
      filter((v) -> v[:verdict] != :off, verdicts)
    )
  }
end

def red?(r)
  r[:red] != [] or r[:refused] != [] or r[:stale] != []
end

def report(r, baseline)
  lines = concat_lists(
    concat_lists(
      map((v) -> "❌ #{v[:package]}: #{v[:why]}", r[:red]),
      map((x) -> "❌ entry #{to_s(x[:entry])} #{x[:why]}", r[:refused])
    ),
    map((w) -> "❌ waiver #{w[:name]} covers nothing; remove it", r[:stale])
  )
  down = shrunk(parse(baseline), "untested", r[:measurements])
  hint = if down == []
    ""
  else
    join_lines(
      [
        "debt shrank; record it in gen/test-beside.b:",
        render("untested", filter((m) -> m[:size] > 0, r[:measurements]))
      ]
    )
  end
  join_lines([join(lines, line_break), hint])
end

def zed_root(source)
  root = path_join(
    getenv("TMPDIR", "/tmp"),
    "test-beside-zed-#{blake3_hex(source)}"
  )
  rm_rf(root)
  mkdir_p(path_join(root, "zed"))
  write_file(
    path_join(root, "zed/Bluefile"),
    unlines(["package(\"zed\", \"0.1.0\")"])
  )
  write_program(path_join(root, "zed/zed.b"), source)
  root
end

def zed(tests)
  join_lines(
    ["def lower(s)", "  s", "end", "", "def upper(s)", "  s", "end", "", tests]
  )
end

def zed_judged(entries, baseline, tests)
  root = zed_root(zed(tests))
  r = judge_all(entries, baseline, measure_all(self_exe, root), "2026-10-24")
  rm_rf(root)
  r
end

def lower_only()
  unlines(["test \"lower\"", "  assert lower(\"A\") == \"A\"", "end"])
end

def both()
  unlines(
    [
      "test \"both\"",
      "  assert lower(\"A\") == \"A\"",
      "  assert upper(\"a\") == \"a\"",
      "end"
    ]
  )
end

test "an untested definition with no recorded debt is red, and its test beside it turns it green"
  red = zed_judged(entries, "", lower_only)
  assert red?(red)
  assert map((v) -> v[:why], red[:red]) ==
    ["1 untested beyond the recorded debt: zed::upper"]
  assert not red?(zed_judged(entries, "", both))
end

test "recorded debt holds, and growth past it is red"
  assert not red?(zed_judged(entries, unlines(["untested: zed 1"]), lower_only))
  grew = zed_judged(
    entries,
    unlines(["untested: zed 1"]),
    unlines(["test \"none\"", "  assert 1 == 1", "end"])
  )
  assert map((v) -> v[:why], grew[:red]) ==
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
  assert size(bad[:refused]) == 1
  assert size(bad[:red]) == 1
end

test "a waiver that covers nothing is stale and red"
  w = [waive("zed::gone", "removed long ago", "2026-12-31")]
  r = zed_judged(concat_lists(entries, w), "", both)
  assert map((x) -> x[:name], r[:stale]) == ["zed::gone"]
  assert red?(r)
end

test "audit lists the gap without red, and off measures nothing"
  audit = zed_judged([level("*", :audit, "a trial")], "", lower_only)
  assert not red?(audit)
  assert map((v) -> v[:untested], audit[:verdicts]) == [["zed::upper"]]
  off = zed_judged([level("zed", :off, "the fixture is off")], "", "")
  assert not red?(off)
  assert off[:measurements] == []
end

test "a package whose tests fail is blind, never green"
  r = zed_judged(
    entries,
    "",
    unlines(["test \"no\"", "  assert lower(\"A\") == \"B\"", "end"])
  )
  assert map((v) -> v[:why], r[:red]) == ["its tests did not run green"]
end

test "every bidama is tested beside its definitions, beyond the debt recorded"
  r = judge_all(
    concat_lists(entries, waivers),
    recorded,
    measure_all(self_exe, bidamas_root),
    today
  )
  if red?(r)
    write_stderr(report(r, recorded))
  end
  assert size(r[:verdicts]) > 50
  assert not red?(r)
end
