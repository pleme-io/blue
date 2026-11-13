@moduledoc """
coverage: blue native's coverage policy, which `checks.test-beside` judges its bidamas by (the Bluefile's `coverage("coverage.b")`): every package at enforce, and the debt measured on 2026-11-13, which may shrink or hold and never grow.

    policy[:recorded] == recorded #=> true
"""

use("retsu", [:size])
use("tesuto", [:level])

@doc """
recorded: The untested definitions and untaken arms per package, measured by `blue test --coverage` on 2026-11-13.

    starts_with?(recorded, "untested: chuuzou") #=> true
"""
def recorded()
  unlines(
    ["untested: chuuzou 6", "unbranched: chuuzou 138", "unbranched: kiban 2"]
  )
end

@doc """
policy: The entries and the recorded debt, as `blue run coverage.b -- policy` prints them.

    size(policy[:entries]) #=> 1
"""
def policy()
  {
    entries: [
      level(
        "*",
        :enforce,
        "a definition is reached by a test beside it, and each arm of its decisions is taken"
      )
    ],
    recorded:
  }
end

def main()
  if argv == ["policy"]
    write_stdout(json_stringify(policy))
  else
    raise(:usage, "blue run coverage.b -- policy")
  end
end

test "the policy prints its entries and the recorded debt as JSON"
  p = json_read(json_stringify(policy))
  assert size(p["entries"]) == 1
  assert p["recorded"] == recorded
end
