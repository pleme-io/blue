@moduledoc """
motenashi (もてなし) — how a launcher receives a person: a world's look, sections, ranking and bindings as entries, and a provider's answer as rows.

A world is a list of entries, each refused alone. A provider is a `.b` file with
`search(query, limit)` returning rows. Every constructor here is pure and returns
a plain record, so the host reads the same value a test does.

    declare([look({width: 680}), bind("ctrl+j", :next)]).refusals #=> []
"""

use("kousei", %i[entry field judge list_of one_of required text])

use("retsu", %i[is_empty size])
use("shinsuu", [:parse_int])

@doc """
config: an entry that sets fields of one config group of the host; the host checks each field alone.

    config(:layout, {padding: 12}).value #=> {padding: 12}
"""
def config(group, fields)
  entry(:config, to_s(group), fields)
end

@doc """
look: the panel's appearance fields: width, opacity, colours, corner radius, sizes.

    look({width: 680}).name #=> "appearance"
"""
def look(fields)
  config(:appearance, fields)
end

@doc """
spacing: the panel's geometry fields: padding and the gaps.

    spacing({padding: 12}).name #=> "layout"
"""
def spacing(fields)
  config(:layout, fields)
end

@doc """
font: the face and size the launcher draws its text in.

    font("Inter", 17).value #=> {font_family: "Inter", font_size: 17}
"""
def font(family, size)
  entry(:font, "font", {font_family: family, font_size: size})
end

@doc """
empty_text: what the panel says when a query matches nothing.

    empty_text("Nada").value #=> {no_matches_text: "Nada"}
"""
def empty_text(words)
  entry(:search_text, "no_matches_text", {no_matches_text: words})
end

@doc """
more_text: what the panel says when more rows exist than it shows.

    more_text("Mais").value #=> {more_matches_text: "Mais"}
"""
def more_text(words)
  entry(:search_text, "more_matches_text", {more_matches_text: words})
end

@doc """
placeholder: the text an empty input shows.

    placeholder("Busca").value #=> {placeholder_text: "Busca"}
"""
def placeholder(words)
  entry(:search_text, "placeholder_text", {placeholder_text: words})
end

@doc """
section: a heading over one provider's rows, and how much those rows weigh.

    section(:apps, {title: "Apps"}).name #=> "apps"
"""
def section(provider_name, fields)
  entry(:section, to_s(provider_name), fields)
end

@doc """
rank: the ranking weights: `frecency` over text relevance.

    rank({frecency: 0.5}).value #=> {frecency: 0.5}
"""
def rank(weights)
  entry(:rank, "rank", weights)
end

@doc """
bind: a key chord and the action it runs.

    bind("ctrl+j", :next).value #=> {action: :next}
"""
def bind(chord, action)
  entry(:bind, chord, {action:})
end

@doc """
provider: a provider file under `providers/`, by its file name without `.b`.

    provider("notas", {prefix: "n "}).name #=> "notas"
"""
def provider(name, fields)
  entry(:provider, name, fields)
end

@doc """
off: a declared entry, or a built-in provider, configured off.

    off(:provider, "music").entry #=> :off
"""
def off(kind, name)
  kousei::off(kind, name)
end

@doc """
without: a provider built into the host, configured off.

    without(:music).name #=> "music"
"""
def without(builtin)
  entry(:without, to_s(builtin), {})
end

@doc """
tune: fields laid over an entry declared earlier.

    tune(:provider, "notas", {prefix: "x "}).entry #=> :tune
"""
def tune(kind, name, fields)
  kousei::tune(kind, name, fields)
end

@doc """
actions: the words a binding may run.

    member?(:next, actions) #=> true
"""
def actions()
  %i[hide next previous execute delete_back delete_word clear]
end

@doc """
capabilities: the host capabilities a provider may ask for.

    member?(:filesystem, capabilities) #=> true
"""
def capabilities()
  %i[process filesystem environment clock network entropy]
end

@doc """
number_field: the check of a field that must be a number.

    map(number_field, [3]) #=> [nil]
"""
def number_field()
  (v) -> kousei::verdict(number?(v), "#{v} is not a number")
end

@doc """
schema: the kinds a world may declare and the fields each takes. A config group's own fields are the host's to check.

    size(schema[:bind]) #=> 1
"""
def schema()
  {
    config: [],
    without: [],
    font: [field(:font_family, text), field(:font_size, number_field)],
    search_text: [
      field(:no_matches_text, text),
      field(:more_matches_text, text),
      field(:placeholder_text, text)
    ],
    section: [
      field(:title, text),
      field(:order, number_field),
      field(:weight, number_field)
    ],
    rank: [field(:frecency, number_field), field(:text, number_field)],
    bind: [required(field(:action, one_of(actions)))],
    provider: [
      field(:prefix, text),
      field(:allow, list_of(one_of(capabilities))),
      field(:deadline_ms, number_field),
      field(:fuel, number_field)
    ]
  }
end

@doc """
open_fields: entries with a config group's fields set aside, so the judge never reads them.

    open_fields([look({width: 1})])[0].fields #=> {width: 1}
"""
def open_fields(entries)
  map(
    fn(e)
      if map?(e) and e[:entry] == :config
        {entry: :config, name: e[:name], value: {}, fields: e[:value]}
      else
        e
      end
    end,
    entries
  )
end

@doc """
restored: a judged entry with its config group's fields back in its value.

    restored({entry: :config, name: "a", value: {}, fields: {b: 1}}).value #=> {b: 1}
"""
def restored(e)
  if e[:entry] == :config
    {entry: :config, name: e[:name], value: e[:fields]}
  else
    e
  end
end

@doc """
declare: a world's entries judged: `accepted`, `off` and `refusals`, each refusal scoped to its entry.

    declare([]).accepted #=> []
    declare([bind("x", :nope)]).accepted #=> []
"""
def declare(entries)
  judged = judge(schema, open_fields(entries))
  {
    accepted: map(restored, judged[:accepted]),
    off: judged[:off],
    refusals: judged[:refusals]
  }
end

@doc """
row: one answer of a provider: its title and any of `subtitle`, `icon`, `score`, `action`.

    row("a", {score: 2}).score #=> 2
    row("a", {}).title #=> "a"
"""
def row(title, fields)
  {**fields, title:}
end

@doc """
open_url: the action that opens a URL.

    open_url("https://a").kind #=> "open_url"
"""
def open_url(url)
  {kind: "open_url", url:}
end

@doc """
copy: the action that puts text on the clipboard.

    copy("a").kind #=> "copy"
"""
def copy(words)
  {kind: "copy", text: words}
end

@doc """
launch: the action that opens a path: a desktop entry, a file.

    launch("/a.desktop").kind #=> "launch"
"""
def launch(path)
  {kind: "launch", path:}
end

@doc """
run: the action that runs a command, its argv as a list.

    run(%w[true]).kind #=> "run"
"""
def run(argv)
  {kind: "run", argv:}
end

@doc """
channel: the two hex digits at a position of a colour's characters, as a number.

    channel(chars("#ff0000"), 1) #=> 255
"""
def channel(cs, at)
  parse_int(join(take(2, drop(at, cs)), ""), 16)
end

@doc """
color: a `#rrggbb` colour as the unit channels a host's config takes. Anything else passes through for the host to refuse alone.

    color("#ff0000") #=> [1.0, 0.0, 0.0]
    color("nope") #=> "nope"
"""
def color(hex_text)
  cs = if string?(hex_text)
    chars(hex_text)
  else
    []
  end
  values = if size(cs) == 7 and cs[0] == "#"
    map((at) -> channel(cs, at), [1, 3, 5])
  else
    []
  end
  if size(filter(number?, values)) == 3
    map((v) -> v / 255.0, values)
  else
    hex_text
  end
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
      look({width: 680}),
      bind("ctrl+j", :explode),
      bind("ctrl+k", :next),
      provider("a", {allow: [:root]}),
      provider("b", {allow: [:filesystem]})
    ]
  )
  assert map((e) -> e[:name], d[:accepted]) == %w[appearance ctrl+k b]
  assert size(d[:refusals]) == 2
  assert map((r) -> r[0], d[:refusals]) == %i[invalid invalid]
end

test "a config group's fields reach the host untouched, whatever they are"
  d = declare([look({width: "not a number", brand_new_field: 1})])
  assert is_empty(d[:refusals])
  assert d[:accepted][0][:value] == {width: "not a number", brand_new_field: 1}
end

test "off takes a declared provider out and names only what was declared"
  d = declare([provider("a", {}), off(:provider, "a"), off(:provider, "nope")])
  assert d[:accepted] == []
  assert map((e) -> e[:name], d[:off]) == ["a"]
  assert map((r) -> r[0], d[:refusals]) == [:unknown_entry]
end

test "a built in provider is configured off by its own word"
  d = declare([without(:music), without(:ai)])
  assert map((e) -> e[:name], d[:accepted]) == %w[music ai]
  assert is_empty(d[:refusals])
end

test "tune lays fields over an earlier entry"
  d = declare(
    [provider("a", {prefix: "a "}), tune(:provider, "a", {prefix: "b "})]
  )
  assert d[:accepted][0][:value] == {prefix: "b "}
end

test "the same entry twice stands once and the second is refused"
  d = declare([bind("x", :next), bind("x", :hide)])
  assert size(d[:accepted]) == 1
  assert d[:accepted][0][:value] == {action: :next}
  assert map((r) -> r[0], d[:refusals]) == [:duplicate]
end

test "a thing that is no entry is refused and the rest stand"
  d = declare([42, look({})])
  assert size(d[:accepted]) == 1
  assert map((r) -> r[0], d[:refusals]) == [:invalid]
end

test "color reads hex to unit channels and passes anything else through"
  assert color("#ffffff") == [1.0, 1.0, 1.0]
  assert color("#000000") == [0.0, 0.0, 0.0]
  c = color("#336699")
  assert c == [0.2, 0.4, 0.6]
  assert color("no") == "no"
  assert color("#xyz123") == "#xyz123"
  assert color("#12345") == "#12345"
  assert color(7) == 7
end

test "a row keeps its fields and its title wins"
  r = row("t", {title: "x", score: 3, action: copy("c")})
  assert r[:title] == "t"
  assert r[:score] == 3
  assert r[:action] == {kind: "copy", text: "c"}
end

test "every action word is one a binding accepts"
  good = map((a) -> bind("x#{a}", a), actions)
  assert is_empty(declare(good)[:refusals])
  assert size(declare(good)[:accepted]) == size(actions)
end
