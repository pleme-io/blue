@moduledoc """
kurashi (暮らし) — how a person lives on a desktop seat: their keys, named commands, bar modules, look, idle, lock and notes as entries, each refused alone.

A world is a list of entries. A bar module is a `.b` file with `render()` returning
text or `nil`. Every constructor here is pure and returns a plain record, so the
host reads the same value a test does. The host holds the schema of a config group
and checks each of its fields alone.

    declare([look({bar_height: 26}), bind("super+a", :close)]).refusals #=> []
"""

use(
  "kousei",
  %i[config entry field flag int_in judge list_of off one_of required text tune]
)

use("retsu", %i[is_empty size])

@doc """
look: the seat's look fields: its accent, its bar height, its focus ring.

    look({accent: :frost2}).name #=> "look"
"""
def look(fields)
  config(:look, fields)
end

@doc """
idle: how long the seat waits with no input: `blank_s` to darken the panel, `lock_s` to lock.

    idle({blank_s: 300}).name #=> "idle"
"""
def idle(fields)
  config(:idle, fields)
end

@doc """
sleep: what the seat does around a system sleep: `lock_before` locks it first.

    sleep({lock_before: true}).name #=> "sleep"
"""
def sleep(fields)
  config(:sleep, fields)
end

@doc """
notes: how the seat shows notifications: `ms` on screen, `max` at once, `enabled`.

    notes({ms: 6000}).name #=> "notes"
"""
def notes(fields)
  config(:notes, fields)
end

@doc """
keyboard: the layouts a seat cycles through, first one first, each `layout` or `layout+variant`.

    keyboard(%w[us us+intl]).value #=> {layouts: %w[us us+intl]}
"""
def keyboard(layouts)
  config(:ukeire, {layouts:})
end

@doc """
lock_with: the program the seat starts to hold its lock, as an argv.

    lock_with(%w[swaylock]).value #=> {client: %w[swaylock]}
"""
def lock_with(argv)
  config(:lock, {client: argv})
end

@doc """
nord: a band of the Nord palette as bare hex, the spelling a lock client's flags take.

    nord(:night0) #=> "2E3440"
    nord(:frost1) #=> "88C0D0"
    nord(:frost3) #=> "5E81AC"
"""
def nord(band)
  get(
    {
      night0: "2E3440",
      night1: "3B4252",
      night2: "434C5E",
      night3: "4C566A",
      snow0: "D8DEE9",
      snow1: "E5E9F0",
      snow2: "ECEFF4",
      frost0: "8FBCBB",
      frost1: "88C0D0",
      frost2: "81A1C1",
      frost3: "5E81AC",
      aurora_red: "BF616A"
    },
    band
  )
end

@doc """
swaylock: the argv that runs swaylock in a cold field: Nord night, a small ring, nothing else moving.

    swaylock(:night0)[0] #=> "swaylock"
    contains?(join(swaylock(:night0), " "), "--color 2E3440") #=> true
"""
def swaylock(field_band)
  field = nord(field_band)
  ring = nord(:night2)
  key = nord(:frost1)
  [
    "swaylock",
    "--color",
    field,
    "--indicator-radius",
    "28",
    "--indicator-thickness",
    "2",
    "--inside-color",
    "#{field}00",
    "--inside-clear-color",
    "#{field}00",
    "--inside-ver-color",
    "#{field}00",
    "--inside-wrong-color",
    "#{field}00",
    "--ring-color",
    "#{ring}ff",
    "--ring-clear-color",
    "#{ring}ff",
    "--ring-ver-color",
    "#{key}ff",
    "--ring-wrong-color",
    "#{nord(:aurora_red)}ff",
    "--key-hl-color",
    "#{key}ff",
    "--bs-hl-color",
    "#{ring}ff",
    "--line-color",
    "00000000",
    "--separator-color",
    "00000000",
    "--text-color",
    "00000000",
    "--text-clear-color",
    "00000000",
    "--text-ver-color",
    "00000000",
    "--text-wrong-color",
    "00000000",
    "--ignore-empty-password"
  ]
end

@doc """
command: a named thing the seat can do; a binding runs it by its name. A list is a program's argv, and no shell reads it.

    command(:louder, volume(5)).name #=> "louder"
    command(:term, %w[mado]).value #=> {kind: "run", argv: ["mado"]}
"""
def command(name, action)
  entry(:command, to_s(name), action_of(action))
end

@doc """
action_of: what a command runs: a list becomes the action that starts that program, and anything else stands as written.

    action_of(%w[mado]).kind #=> "run"
    action_of(mute).kind #=> "mute"
"""
def action_of(action)
  if action != nil and list?(action)
    {kind: "run", argv: action}
  else
    action
  end
end

@doc """
deed: the action that runs one of the seat's own verbs.

    deed(:close).verb #=> "close"
"""
def deed(verb)
  {kind: "deed", verb: to_s(verb)}
end

@doc """
volume: the action that moves the default output's volume by a step in percent.

    volume(-5).step_pct #=> -5
"""
def volume(step_pct)
  {kind: "volume", step_pct:}
end

@doc """
mute: the action that toggles the default output's mute.

    mute.kind #=> "mute"
"""
def mute()
  {kind: "mute"}
end

@doc """
backlight: the action that moves the panel's brightness by a step in percent.

    backlight(5).step_pct #=> 5
"""
def backlight(step_pct)
  {kind: "backlight", step_pct:}
end

@doc """
screenshot: the action that writes the screen to a PNG in a folder.

    screenshot("/tmp").dir #=> "/tmp"
"""
def screenshot(dir)
  {kind: "screenshot", dir:}
end

@doc """
bind: a chord and the verb or named command it runs; `{locked: true}` lets it run behind a lock.

    bind("super+a", :close).value #=> {action: "close"}
    bind("volume_up", :louder, {locked: true}).value.locked #=> true
"""
def bind(chord, action, opts?)
  word = if keyword?(action)
    to_s(action)
  else
    action
  end
  entry(:bind, chord, {**opts, action: word})
end

@doc """
bar_module: a `.b` file under `bar/`, by its file name without `.b`, shown in the bar's right zone.

    bar_module("uptime", {every_s: 60}).name #=> "uptime"
"""
def bar_module(name, fields)
  entry(:bar_module, name, fields)
end

@doc """
capabilities: the host capabilities a bar module may ask for.

    member?(:filesystem, capabilities) #=> true
"""
def capabilities()
  %i[process filesystem environment clock network]
end

@doc """
command_fields: the fields each kind of command takes.

    size(command_fields[:run]) #=> 2
"""
def command_fields()
  kinds = %w[run deed volume mute backlight screenshot]
  {
    run: [
      required(field(:kind, one_of(kinds))),
      required(field(:argv, list_of(text)))
    ],
    deed: [required(field(:kind, one_of(kinds))), required(field(:verb, text))],
    volume: [
      required(field(:kind, one_of(kinds))),
      required(field(:step_pct, int_in(-100, 100)))
    ],
    mute: [required(field(:kind, one_of(kinds)))],
    backlight: [
      required(field(:kind, one_of(kinds))),
      required(field(:step_pct, int_in(-100, 100)))
    ],
    screenshot: [
      required(field(:kind, one_of(kinds))),
      required(field(:dir, text))
    ]
  }
end

@doc """
schema: the kinds a world may declare and the fields each takes. A config group's own fields, and a command's, are checked on the way in.

    size(schema[:bind]) #=> 2
"""
def schema()
  {
    config: [],
    command: [],
    bind: [required(field(:action, text)), field(:locked, flag)],
    bar_module: [
      field(:every_s, int_in(1, 86400)),
      field(:allow, list_of(one_of(capabilities))),
      field(:deadline_ms, int_in(1, 60000)),
      field(:fuel, int_in(1, 1_000_000_000))
    ]
  }
end

@doc """
command_why: why a command's action is malformed, or nil.

    command_why(action_of(%w[a])) #=> nil
    command_why({kind: "nope"}) #=> "nope is no command kind"
"""
def command_why(action)
  if not map?(action)
    "#{action} is no command action"
  else
    rows = filter(
      (p) -> to_s(p[0]) == action[:kind],
      map_entries(command_fields)
    )
    if is_empty(rows)
      "#{action[:kind]} is no command kind"
    else
      why = kousei::record_whys(rows[0][1], action)
      if is_empty(why)
        nil
      else
        why[0]
      end
    end
  end
end

@doc """
open_fields: entries with a config group's fields and a command's action set aside, so the judge never reads them.

    open_fields([look({bar_height: 1})])[0].fields #=> {bar_height: 1}
"""
def open_fields(entries)
  map(
    fn(e)
      if map?(e) and (e[:entry] == :config or e[:entry] == :command)
        {entry: e[:entry], name: e[:name], value: {}, fields: e[:value]}
      else
        e
      end
    end,
    entries
  )
end

@doc """
restored: a judged entry with its set-aside fields back in its value.

    restored({entry: :config, name: "a", value: {}, fields: {b: 1}}).value #=> {b: 1}
"""
def restored(e)
  if e[:entry] == :config or e[:entry] == :command
    {entry: e[:entry], name: e[:name], value: e[:fields]}
  else
    e
  end
end

@doc """
standing_commands: the commands whose action is well formed, each bad one refused alone, in the order they came.

    standing_commands([command(:a, %w[x])]).refusals #=> []
    size(standing_commands([command(:a, {kind: "nope"})]).refusals) #=> 1
"""
def standing_commands(accepted)
  checked = map(
    fn(e)
      why = if e[:entry] == :command
        command_why(e[:value])
      end
      {entry: e, why:}
    end,
    accepted
  )
  {
    accepted: map((c) -> c[:entry], filter((c) -> c[:why].nil?, checked)),
    refusals: map(
      (c) -> [:invalid, "command #{c[:entry][:name]}: #{c[:why]}"],
      filter((c) -> not c[:why].nil?, checked)
    )
  }
end

@doc """
declare: a world's entries judged: `accepted`, `off` and `refusals`, each refusal scoped to its entry.

    declare([]).accepted #=> []
    declare([bind("x", 7)]).accepted #=> []
"""
def declare(entries)
  judged = judge(schema, open_fields(entries))
  standing = standing_commands(map(restored, judged[:accepted]))
  {
    accepted: standing[:accepted],
    off: judged[:off],
    refusals: append(judged[:refusals], standing[:refusals])
  }
end

test "an empty world declares nothing and refuses nothing"
  d = declare([])
  assert d[:accepted] == []
  assert d[:off] == []
  assert d[:refusals] == []
end

test "a bad entry is refused alone and its siblings stand"
  d = declare(
    [
      look({bar_height: 26}),
      bind("super+a", 7),
      bind("super+b", :close),
      bar_module("a", {allow: [:root]}),
      bar_module("b", {allow: [:filesystem]}),
      command(:bad, {kind: "nope"}),
      command(:good, ["mado"])
    ]
  )
  assert map((e) -> e[:name], d[:accepted]) == %w[look super+b b good]
  assert size(d[:refusals]) == 3
  assert map((r) -> r[0], d[:refusals]) == %i[invalid invalid invalid]
end

test "a config group's fields reach the host untouched, whatever they are"
  d = declare([look({bar_height: "tall", brand_new_field: 1})])
  assert is_empty(d[:refusals])
  assert d[:accepted][0][:value] == {bar_height: "tall", brand_new_field: 1}
end

test "every sugar word lowers to the group the host's schema names"
  groups = map(
    (e) -> e[:name],
    [
      look({}),
      idle({}),
      sleep({}),
      notes({}),
      keyboard(["us"]),
      lock_with(["x"])
    ]
  )
  assert groups == %w[look idle sleep notes ukeire lock]
end

test "a list is a program, and a list of the wrong things is refused alone"
  d = declare([command(:a, %w[mado --flag]), command(:b, [1])])
  assert map((e) -> e[:name], d[:accepted]) == ["a"]
  assert d[:accepted][0][:value] == {kind: "run", argv: %w[mado --flag]}
  assert map((r) -> r[0], d[:refusals]) == [:invalid]
end

test "off takes a declared module out and names only what was declared"
  d = declare(
    [bar_module("a", {}), off(:bar_module, "a"), off(:bar_module, "nope")]
  )
  assert d[:accepted] == []
  assert map((e) -> e[:name], d[:off]) == ["a"]
  assert map((r) -> r[0], d[:refusals]) == [:unknown_entry]
end

test "tune lays fields over an earlier entry"
  d = declare(
    [bar_module("a", {every_s: 60}), tune(:bar_module, "a", {every_s: 5})]
  )
  assert d[:accepted][0][:value] == {every_s: 5}
end

test "the same chord twice stands once and the second is refused"
  d = declare([bind("x", :close), bind("x", :minimize)])
  assert size(d[:accepted]) == 1
  assert d[:accepted][0][:value] == {action: "close"}
  assert map((r) -> r[0], d[:refusals]) == [:duplicate]
end

test "a thing that is no entry is refused and the rest stand"
  d = declare([42, look({})])
  assert size(d[:accepted]) == 1
  assert map((r) -> r[0], d[:refusals]) == [:invalid]
end

test "every command kind is well formed and a malformed one names its field"
  good = [
    action_of(["a"]),
    deed(:close),
    volume(5),
    mute,
    backlight(-5),
    screenshot("/tmp")
  ]
  assert filter((a) -> not command_why(a).nil?, good) == []
  assert command_why({kind: "run"}) == "argv is required"
  assert command_why({kind: "run", argv: [1]}) == "argv: 1 is not text"
  assert command_why(7) == "7 is no command action"
  assert command_why(volume(101)) ==
    "step_pct: 101 is not a whole number in -100..100"
end

test "a binding carries its locked flag only when asked"
  assert bind("a", :x).value == {action: "x"}
  assert bind("a", :x, {locked: true}).value == {action: "x", locked: true}
end

test "swaylock is rendered from the palette and says nothing in words"
  argv = swaylock(:night0)
  text_of = join(argv, " ")
  assert argv[0] == "swaylock"
  assert contains?(text_of, "--color 2E3440")
  assert contains?(text_of, "--text-color 00000000")
  assert not contains?(text_of, "nil")
end

test "the palette reads Nord and an unknown band reads nothing"
  assert nord(:night0) == "2E3440"
  assert nord(:snow2) == "ECEFF4"
  assert nord(:nope).nil?
end
