use("mokuroku", %i[blue_path_roots package_dirs])
use("retsu", %i[concat_lists find_first last size])

use(
  "tesuto",
  %i[
    coverage_arms
    coverage_names
    coverage_red?
    coverage_report
    judge_coverage
    level
    skip_for
    waive
  ]
)

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
    ),
    waive(
      "hikisuu::command",
      "it reads the process's argv and may end it with exit_with(64); hikisuu::run_with is its body, tested with sinks, until the Terminal capability (docs/CLI-TUI.md section 7) lets a test hand it a line",
      "2027-04-30"
    ),
    waive(
      "settei::command",
      "it reads the process's argv, the config file and the environment, and may end it with exit_with(64); settei::line is its body, tested with a given line, file and environment, until the Terminal capability (docs/CLI-TUI.md section 7) lets a test hand it a line",
      "2027-04-30"
    ),
    waive(
      "heni::main",
      "it reads the process's argv and may end it with exit_with(64); hikisuu::run_with is its body, tested with sinks, until the Terminal capability (docs/CLI-TUI.md section 7) lets a test hand it a line",
      "2027-04-30"
    ),
    waive(
      "toride::main",
      "it reads TORIDE_CONFIG and acts on the machine's own dnsmasq conf and state file; toride::run is its body, tested through a fake io",
      "2027-04-30"
    ),
    waive(
      "kakehashi::souji::main",
      "it reads the process's argv and may end it with exit_with(64); hikisuu::run_with is its body, tested with sinks, until the Terminal capability (docs/CLI-TUI.md section 7) lets a test hand it a line",
      "2027-04-30"
    )
  ]
end

# Untested definitions and untaken arms per bidama, measured by `blue test
# --coverage` on 2026-11-13. A row may shrink or hold, never grow; a package with no row
# holds at zero.
def recorded()
  unlines(
    [
      "untested: deeta 3",
      "untested: eigyou 3",
      "untested: heni 2",
      "untested: kakehashi 24",
      "untested: keiyu 1",
      "untested: kiwari 5",
      "untested: koubou 10",
      "untested: kousei 1",
      "untested: kueri 6",
      "untested: mitoshi 11",
      "untested: mokuroku 6",
      "untested: okite 1",
      "untested: retsu 2",
      "untested: sabi 2",
      "untested: settei 5",
      "untested: shinchoku 10",
      "untested: suugaku 4",
      "untested: todokede 16",
      "untested: touroku 3",
      "untested: ukai 15",
      "unbranched: angou 5",
      "unbranched: baito 7",
      "unbranched: bunsho 67",
      "unbranched: chozou 63",
      "unbranched: deeta 95",
      "unbranched: eigyou 48",
      "unbranched: fairu 1",
      "unbranched: gamen 17",
      "unbranched: gitto 15",
      "unbranched: happa 8",
      "unbranched: heni 8",
      "unbranched: hikisuu 5",
      "unbranched: hizuke 1",
      "unbranched: hon 31",
      "unbranched: ibuki 1",
      "unbranched: isshou 85",
      "unbranched: junjo 1",
      "unbranched: junni 2",
      "unbranched: kaaneru 245",
      "unbranched: kakehashi 194",
      "unbranched: kazu 3",
      "unbranched: keiyu 1",
      "unbranched: khipu 22",
      "unbranched: kiwari 14",
      "unbranched: kodou 11",
      "unbranched: koubou 39",
      "unbranched: kousei 1",
      "unbranched: koutei 1",
      "unbranched: kueri 39",
      "unbranched: kyohi 1",
      "unbranched: mitoshi 3",
      "unbranched: mokuroku 73",
      "unbranched: okite 5",
      "unbranched: ongaku 3",
      "unbranched: retsu 5",
      "unbranched: sabi 10",
      "unbranched: saishikou 1",
      "unbranched: seikika 46",
      "unbranched: settei 16",
      "unbranched: shinchoku 38",
      "unbranched: shinsatsu 1",
      "unbranched: shinsuu 2",
      "unbranched: shisutemu 5",
      "unbranched: shomei 1",
      "unbranched: shuugou 1",
      "unbranched: shuusei 5",
      "unbranched: suugaku 16",
      "unbranched: tesuto 8",
      "unbranched: todokede 20",
      "unbranched: toride 4",
      "unbranched: toriyose 189",
      "unbranched: touroku 8",
      "unbranched: ukai 23",
      "unbranched: utsushi 9"
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
      names: coverage_names(json_get(cap, :stdout)),
      arms: coverage_arms(json_get(cap, :stdout))
    }
  end
end

def measure_all(exe, root)
  map((d) -> measure(exe, d), sort_keyed((d) -> d, package_dirs(root)))
end

@doc """
policy: The policy `checks.test-beside` judges every bidama by (the Bluefile's `coverage("gen/test-beside.b")`), which `blue run gen/test-beside.b -- policy` prints: the entries, the waivers and the recorded debt.

    policy[:recorded] == recorded #=> true
"""
def policy()
  {entries: concat_lists(entries, waivers), recorded:}
end

def main()
  if argv == ["policy"]
    write_stdout(json_stringify(policy))
  else
    raise(:usage, "blue run gen/test-beside.b -- policy")
  end
end

def judge_all(entries, baseline, measured, day)
  judge_coverage(entries, baseline, measured, day)
end

def red?(r)
  coverage_red?(r)
end

def report(r, baseline)
  coverage_report(r, baseline, "gen/test-beside.b")
end

def zed_root(source)
  root = path_join(temp_dir("test-beside-zed"), "test-beside-zed")
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
    [
      "@moduledoc \"\"\"",
      "zed: two words, each giving back the string it is given.",
      "",
      "    join(%w[z ed], \"\") #=> \"zed\"",
      "\"\"\"",
      "",
      "def lower(s)",
      "  s",
      "end",
      "",
      "def upper(s)",
      "  s",
      "end",
      "",
      tests
    ]
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
    unlines(
      [
        "test \"none\"",
        "  assert join([\"z\", \"ed\"], \"\") == \"zed\"",
        "end"
      ]
    )
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

test "the policy printed for checks.test-beside is the entries, waivers and recorded debt"
  p = json_read(json_stringify(policy))
  assert size(p["entries"]) == size(entries) + size(waivers)
  assert p["recorded"] == recorded
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
  skip_for(
    if getenv("BLUE_TEST_BESIDE_CORPUS", "") == "on"
      nil
    else
      "checks.test-beside judges the corpus from the bidama-test outputs; the pre-push gate sets BLUE_TEST_BESIDE_CORPUS=on to measure it here"
    end
  )
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
