@moduledoc """
hannou (反応) — a turn's reactions, declared once and rendered as the `hooks` table of guardrail's config: a `mark` reaction on UserPromptSubmit records the turn start, a `sound` reaction on Stop plays a file when the turn ran long enough. A bad declaration is refused as data, and every refusal is named.

    render_data([]) #=> {hooks: {}}
"""

use("deeta", %i[parse pretty yaml])
use("kyohi", %i[enforce kinds refusal])
use("retsu", %i[count_where flat_map is_empty size])

@doc """
events: the hook events a reaction may sit on, mark first.

    events #=> ["UserPromptSubmit", "Stop"]
"""
def events()
  %w[UserPromptSubmit Stop]
end

@doc """
reaction: one declared reaction; a sound or a threshold that does not apply is nil, and it is off unless `enabled`.

    reaction("m", "UserPromptSubmit", :mark, nil, nil, false)[:enabled] #=> false
"""
def reaction(name, event, kind, sound, min_turn_secs, enabled)
  {name:, event:, kind:, sound:, min_turn_secs:, enabled:}
end

@doc """
long_turn_sound: the default declaration, a mark on UserPromptSubmit and a sound on Stop for turns of at least 90 seconds, both off.

    size(long_turn_sound) #=> 2
"""
def long_turn_sound()
  [
    reaction("long-turn-sound", "UserPromptSubmit", :mark, nil, nil, false),
    reaction("long-turn-sound", "Stop", :sound, nil, 90, false)
  ]
end

@doc """
home_event: the one event a reaction kind sits on.

    home_event(:sound) #=> "Stop"
"""
def home_event(kind)
  if kind == :mark
    "UserPromptSubmit"
  else
    "Stop"
  end
end

@doc """
faults: every refusal of one reaction on its own, in a fixed order.

    faults(reaction("m", "Stop", :mark, nil, nil, false)) #=> [[:wrong_event, "m: a mark reaction sits on UserPromptSubmit, not Stop"]]
"""
def faults(r)
  n = r[:name]
  k = r[:kind]
  t = r[:min_turn_secs]
  known_kind = k == :mark or k == :sound
  known_event = member?(r[:event], events)
  rows = [
    [not string?(n) or n == "", :bad_name, "a reaction needs a non-empty name"],
    [
      not known_kind,
      :unknown_reaction,
      "#{n}: reaction kind #{to_s(k)} is neither mark nor sound"
    ],
    [
      not known_event,
      :unknown_event,
      "#{n}: event #{to_s(r[:event])} is not UserPromptSubmit or Stop"
    ],
    [
      known_kind and known_event and r[:event] != home_event(k),
      :wrong_event,
      "#{n}: a #{to_s(k)} reaction sits on #{home_event(k)}, not #{r[:event]}"
    ],
    [
      k == :mark and not r[:sound].nil?,
      :mark_takes_no_sound,
      "#{n}: a mark reaction takes no sound"
    ],
    [
      k == :mark and not t.nil?,
      :mark_takes_no_min_turn_secs,
      "#{n}: a mark reaction takes no minTurnSecs"
    ],
    [
      not t.nil? and not (integer?(t) and t > 0),
      :bad_min_turn_secs,
      "#{n}: minTurnSecs must be a positive integer, got #{to_s(t)}"
    ],
    [
      r[:enabled] != true and r[:enabled] != false,
      :bad_enabled,
      "#{n}: enabled must be true or false"
    ]
  ]
  map(
    (row) -> refusal(row[1], row[2]),
    filter((row) -> retsu::first(row), rows)
  )
end

@doc """
duplicates: a refusal for each name declared twice on one event.

    duplicates([reaction("x", "Stop", :sound, nil, nil, false), reaction("x", "Stop", :sound, nil, nil, false)]) #=> [[:duplicate_name, "x/Stop: a name is declared once per event"]]
"""
def duplicates(rs)
  keys = map((r) -> "#{r[:name]}/#{r[:event]}", rs)
  twice = filter((k) -> count_where((x) -> x == k, keys) > 1, keys)
  map(
    (k) -> refusal(:duplicate_name, "#{k}: a name is declared once per event"),
    distinct(sort_keyed((k) -> k, twice))
  )
end

@doc """
validate: every refusal across the reactions, each a kyohi refusal; empty when all are sound.

    validate(long_turn_sound) #=> []
"""
def validate(rs)
  append(flat_map(rs, faults), duplicates(rs))
end

@doc """
entry: one reaction as the hook action guardrail reads, with sound and minTurnSecs only when set.

    entry(reaction("m", "UserPromptSubmit", :mark, nil, nil, true)) #=> {action: "react", reaction: "mark", enabled: true}
"""
def entry(r)
  base = {action: "react", reaction: to_s(r[:kind]), enabled: r[:enabled]}
  with_sound = if r[:sound].nil?
    base
  else
    assoc(base, :sound, r[:sound])
  end
  if r[:min_turn_secs].nil?
    with_sound
  else
    assoc(with_sound, :minTurnSecs, r[:min_turn_secs])
  end
end

@doc """
render_data: the `hooks` table as data, an event with no reactions absent and each event's entries ordered by name; raises one :refused error naming every fault.

    render_data(long_turn_sound)[:hooks]["UserPromptSubmit"] #=> [{action: "react", reaction: "mark", enabled: false}]
"""
def render_data(rs)
  enforce(rs, [validate])
  on = fn(e)
    map(entry, sort_keyed((r) -> r[:name], filter((r) -> r[:event] == e, rs)))
  end
  present = filter((e) -> not is_empty(on(e)), events)
  {hooks: reduce((acc, e) -> assoc(acc, e, on(e)), {}, present)}
end

@doc """
render: the `hooks:` YAML of guardrail.yaml for the reactions.

    render([]) #=> "hooks: {}\n"
"""
def render(rs)
  yaml(render_data(rs))
end

@doc """
render_json: the same `hooks` table as JSON, for a reader that has no YAML parser, such as Nix's `builtins.fromJSON`.

    render_json([]) #=> "{\n  \"hooks\": {}\n}\n"
"""
def render_json(rs)
  pretty(render_data(rs))
end

test "nothing declared renders an empty table and validates clean"
  assert render([]) == unlines(["hooks: {}"])
  assert validate([]) == []
  assert duplicates([]) == []
  assert render_data([]) == {hooks: {}}
end

test "the order of declaration does not change the output"
  a = reaction("a", "Stop", :sound, nil, 5, true)
  b = reaction("b", "Stop", :sound, "/x.aiff", nil, false)
  m = reaction("m", "UserPromptSubmit", :mark, nil, nil, true)
  assert render([a, b, m]) == render([m, b, a])
  assert render([a, b, m]) == render([b, m, a])
end

test "the default declaration renders exactly the YAML guardrail reads, off"
  assert events == %w[UserPromptSubmit Stop]
  assert validate(long_turn_sound) == []
  assert render(long_turn_sound) ==
    unlines(
      [
        "hooks:",
        "  Stop:",
        "    - action: \"react\"",
        "      enabled: false",
        "      minTurnSecs: 90",
        "      reaction: \"sound\"",
        "  UserPromptSubmit:",
        "    - action: \"react\"",
        "      enabled: false",
        "      reaction: \"mark\""
      ]
    )
end

test "an entry carries the flag as set, on and off"
  on = {
    name: "s",
    event: "Stop",
    kind: :sound,
    sound: "/x.aiff",
    min_turn_secs: nil,
    enabled: true
  }
  off = {
    name: "s",
    event: "Stop",
    kind: :sound,
    sound: nil,
    min_turn_secs: 7,
    enabled: false
  }
  assert entry(on) ==
    {action: "react", reaction: "sound", enabled: true, sound: "/x.aiff"}
  assert entry(off) ==
    {action: "react", reaction: "sound", enabled: false, minTurnSecs: 7}
  assert faults(on) == []
  assert faults(off) == []
  assert kinds(faults(assoc(on, :enabled, 1))) == [:bad_enabled]
end

test "a mark reaction takes no sound"
  r = reaction("m", "UserPromptSubmit", :mark, "/x.aiff", nil, false)
  assert kinds(faults(r)) == [:mark_takes_no_sound]
end

test "a mark reaction takes no minTurnSecs"
  r = reaction("m", "UserPromptSubmit", :mark, nil, 5, false)
  assert kinds(validate([r])) == [:mark_takes_no_min_turn_secs]
end

test "minTurnSecs must be a positive integer"
  bad = [0, -3, 1.5, "9"]
  assert map(
    (n) -> kinds(validate([reaction("s", "Stop", :sound, nil, n, false)])),
    bad
  ) ==
    [
      [:bad_min_turn_secs],
      [:bad_min_turn_secs],
      [:bad_min_turn_secs],
      [:bad_min_turn_secs]
    ]
  assert validate([reaction("s", "Stop", :sound, nil, 1, false)]) == []
end

test "a sound reaction sits only on Stop"
  assert home_event(:mark) == "UserPromptSubmit"
  r = reaction("s", "UserPromptSubmit", :sound, nil, nil, false)
  assert kinds(validate([r])) == [:wrong_event]
end

test "a mark reaction sits only on UserPromptSubmit"
  r = reaction("m", "Stop", :mark, nil, nil, false)
  assert kinds(validate([r])) == [:wrong_event]
end

test "a name is declared once per event"
  a = reaction("x", "Stop", :sound, nil, nil, false)
  assert kinds(validate([a, a])) == [:duplicate_name]
  m = reaction("x", "UserPromptSubmit", :mark, nil, nil, false)
  assert kinds(duplicates([a, m])) == []
end

test "an unknown event, kind or name is refused"
  assert kinds(
    validate([reaction("e", "PreToolUse", :mark, nil, nil, false)])
  ) == [:unknown_event]
  assert kinds(validate([reaction("k", "Stop", :buzz, nil, nil, false)])) ==
    [:unknown_reaction]
  assert kinds(validate([reaction("", "Stop", :sound, nil, nil, false)])) ==
    [:bad_name]
end

test "rendering an invalid declaration raises one refusal naming the fault"
  r = reaction("m", "Stop", :mark, nil, nil, false)
  assert kyohi::raised(() -> render([r])) == :refused
end

test "the JSON reads back as the YAML does, and the default is exact"
  assert parse(render_json(long_turn_sound), :json) ==
    parse(render(long_turn_sound), :yaml)
  assert render_json(long_turn_sound) ==
    unlines(
      [
        "{",
        "  \"hooks\": {",
        "    \"Stop\": [",
        "      {",
        "        \"action\": \"react\",",
        "        \"enabled\": false,",
        "        \"minTurnSecs\": 90,",
        "        \"reaction\": \"sound\"",
        "      }",
        "    ],",
        "    \"UserPromptSubmit\": [",
        "      {",
        "        \"action\": \"react\",",
        "        \"enabled\": false,",
        "        \"reaction\": \"mark\"",
        "      }",
        "    ]",
        "  }",
        "}"
      ]
    )
end
