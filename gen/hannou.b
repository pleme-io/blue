use("deeta", [:parse])
use("hannou")
use("moji", [:before_last])

def main()
  out = getenv("GEN_OUT", "bidamas/hannou/gen/hooks.yaml")
  mkdir_p(before_last(out, "/"))
  write_file(out, hannou::render(hannou::long_turn_sound))
end

test "the rendered hooks read back as the entries guardrail's hook action reads", {
  kind: :rendering
}
  t = parse(hannou::render(hannou::long_turn_sound), :yaml)
  assert t["hooks"]["UserPromptSubmit"] ==
    [{"action" => "react", "reaction" => "mark", "enabled" => false}]
  assert t["hooks"]["Stop"] ==
    [
      {
        "action" => "react",
        "reaction" => "sound",
        "minTurnSecs" => 90,
        "enabled" => false
      }
    ]
end
