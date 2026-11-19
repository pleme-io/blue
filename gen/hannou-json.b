use("deeta", [:parse])
use("hannou")
use("moji", [:before_last])

def main()
  out = getenv("GEN_OUT", "bidamas/hannou/gen/hooks.json")
  mkdir_p(before_last(out, "/"))
  write_file(out, hannou::render_json(hannou::long_turn_sound))
end

test "the rendered JSON reads back as guardrail's hook table", {
  kind: :rendering
}
  t = parse(hannou::render_json(hannou::long_turn_sound), :json)
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
