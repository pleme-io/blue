@moduledoc """
jitaku (自宅) — a home, declared entry by entry, each refused alone, projected to pleme.lareira.

A home is a list of entries: its site, delivery and exposure, components with
their settings, Home Assistant integrations, speakers, lights by role, tones,
moods, and mood sets (lists of moods). `lareira` gives the attribute set the
nix module takes, from the entries that stand; `refusals` names the rest.

    accepted([]) #=> []
"""

use(
  "kousei",
  %i[entry flag int_in kind_of name_of required text value_of verdict where]
)

use("kyohi", %i[kinds refusal])
use("moji", %i[is_hex made_of strip_prefix])
use("retsu", %i[contains first flat_map index_of is_empty last size])

legacy_names("0.1.1", [%w[unrefused kyohi::standing]])

# ── checks: a check is fn(value) answering nil, or why the value is wrong ──

def number_in(lo, hi)
  fn(v)
    verdict(
      number?(v) and v >= lo and v <= hi,
      "#{v} is not a number in #{lo}..#{hi}"
    )
  end
end

def float_in(lo, hi)
  fn(v)
    verdict(
      float?(v) and v >= lo and v <= hi,
      "#{v} is not a float in #{lo}..#{hi}"
    )
  end
end

def one_of(choices)
  fn(v)
    verdict(contains(choices, v), "#{v} is not one of #{join(choices, ", ")}")
  end
end

def lower_digits()
  "abcdefghijklmnopqrstuvwxyz0123456789"
end

def slug_chars()
  "#{lower_digits}_"
end

def name_chars()
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
end

@doc """
name_text: A name a home gives a thing (a tone, a mood, a speaker, a role).
"""
def name_text()
  (v) -> verdict(string?(v) and made_of(v, name_chars), "#{v} is not a name")
end

@doc """
entity: A Home Assistant entity id in `domain`: `light.hallway`.
"""
def entity(domain)
  fn(v)
    verdict(
      string?(v) and
        made_of(strip_prefix(v, "#{domain}."), slug_chars) and
        strip_prefix(v, "#{domain}.") != v,
      "#{v} is not a #{domain} entity"
    )
  end
end

def icon()
  fn(v)
    verdict(
      string?(v) and made_of(v, "#{lower_digits}-"),
      "#{v} is not a Material Design Icons name"
    )
  end
end

def hex_color()
  fn(v)
    verdict(
      string?(v) and
        length(v) == 7 and
        strip_prefix(v, "#") != v and
        is_hex(strip_prefix(v, "#")),
      "#{v} is not a #RRGGBB colour"
    )
  end
end

def host_of(v)
  strip_prefix(strip_prefix(v, "http://"), "https://")
end

def base_url()
  fn(v)
    verdict(
      v == :host or
        string?(v) and
          host_of(v) != v and
          length(host_of(v)) > 0 and
          not contains(chars(host_of(v)), "/"),
      "#{v} is not http(s)://host[:port]"
    )
  end
end

def applied(f, v)
  f(v)
end

def passes?(check, v)
  applied(check, v).nil?
end

def first_why(check, xs)
  whys = filter((w) -> w != nil, map((x) -> check(x), xs))
  if is_empty(whys)
    nil
  else
    first(whys)
  end
end

def list_of(check)
  fn(v)
    if v != nil and list?(v) and not map?(v)
      first_why(check, v)
    else
      "#{v} is not a list"
    end
  end
end

def three_of(check)
  fn(v)
    if v != nil and list?(v) and size(v) == 3
      first_why(check, v)
    else
      "#{v} is not three values"
    end
  end
end

# ── records: a table of fields, read once to check and once to project ─────

@doc """
field: A field: its key in blue, its key in pleme.lareira (nil: blue's alone), the
check its value passes, and how its value is rendered.
"""
def field(key, json, check)
  {key:, json:, check:, render: (v) -> v, required: false}
end

def record_field(key, json, table)
  {
    key:,
    json:,
    check: record_check(table),
    render: (v) -> project(table, v),
    required: false
  }
end

def records_field(key, json, table)
  {
    key:,
    json:,
    check: list_of(record_check(table)),
    render: (v) -> map((r) -> project(table, r), v),
    required: false
  }
end

def key_text(f)
  to_s(f[:key])
end

@doc """
key_names: The keys a map was written with, as text. Blue has no word that lists a
map's keys; JSON text does, so the map is read back through it.
"""
def key_names(m)
  map((p) -> first(p), json_parse(json_stringify(m)))
end

def field_why(f, m)
  v = get(m, f[:key])
  if v.nil?
    verdict(not f[:required], "#{key_text(f)} is required")
  else
    why = applied(f[:check], v)
    if why.nil?
      nil
    else
      "#{key_text(f)}: #{why}"
    end
  end
end

def record_whys(table, m)
  if m.nil? or not map?(m)
    ["#{m} is not a record"]
  else
    known = map(key_text, table)
    unknown = map(
      (k) -> "#{k} is not a field here",
      filter((k) -> not contains(known, k), key_names(m))
    )
    append(unknown, filter((w) -> w != nil, map((f) -> field_why(f, m), table)))
  end
end

def record_check(table)
  fn(m)
    whys = record_whys(table, m)
    if is_empty(whys)
      nil
    else
      join(whys, "; ")
    end
  end
end

@doc """
project: The record in pleme.lareira's spelling: its declared fields only, so every
default stays the module's.
"""
def project(table, m)
  reduce((acc, f) -> projected(acc, f, m), {}, table)
end

def projected(acc, f, m)
  v = get(m, f[:key])
  if v.nil? or f[:json].nil?
    acc
  else
    assoc(acc, f[:json], applied(f[:render], v))
  end
end

# ── the tables ──────────────────────────────────────────────────────────────

def tone_table()
  [
    field(:frequency, "frequency", int_in(20, 20000)),
    field(:frequencies, "frequencies", list_of(int_in(20, 20000))),
    field(:noise, "noise", one_of(%w[white pink brown])),
    field(:tremolo, "tremolo", number_in(0.1, 20.0)),
    field(:depth, "depth", number_in(0.1, 1.0)),
    field(:minutes, "minutes", int_in(1, 60)),
    field(:seconds, "seconds", int_in(2, 600)),
    field(:level, "level", number_in(0.05, 1.0))
  ]
end

def lights_table()
  [
    required(field(:brightness_pct, "brightnessPct", int_in(0, 100))),
    field(:kelvin, "kelvin", int_in(2000, 6500)),
    field(:transition, "transition", int_in(0, 600)),
    field(:only, "only", list_of(entity("light"))),
    field(:role, nil, name_text),
    field(:rgb, "rgb", three_of(int_in(0, 255)))
  ]
end

def breathing_table()
  [
    required(field(:low_pct, "lowPct", int_in(1, 100))),
    required(field(:high_pct, "highPct", int_in(1, 100))),
    required(field(:inhale, "inhale", int_in(1, 30))),
    required(field(:exhale, "exhale", int_in(1, 30))),
    field(:minutes, "minutes", int_in(1, 120))
  ]
end

def hand_over_table()
  [
    required(field(:after_minutes, "afterMinutes", int_in(0, 240))),
    required(field(:mood, "mood", name_text))
  ]
end

def sound_table()
  [
    required(field(:tone, "tone", name_text)),
    field(:volume, "volume", number_in(0.0, 1.0)),
    field(:speakers, "speakers", list_of(name_text))
  ]
end

def mood_table()
  [
    field(:label, "label", text),
    field(:group, "group", text),
    field(:icon, "icon", icon),
    field(:color, "color", hex_color),
    field(:enable, "enable", flag),
    field(:phone_button, "phoneButton", flag),
    record_field(:lights, "lights", lights_table),
    record_field(:breathing, "breathing", breathing_table),
    records_field(:then, "then", hand_over_table),
    record_field(:sound, "sound", sound_table)
  ]
end

def coordinates_table()
  [
    required(field(:latitude, "latitude", float_in(-90.0, 90.0))),
    required(field(:longitude, "longitude", float_in(-180.0, 180.0))),
    field(:elevation, "elevation", int_in(-500, 9000))
  ]
end

def site_table()
  [
    required(field(:name, "name", name_text)),
    record_field(:coordinates, "coordinates", coordinates_table)
  ]
end

def enable_field()
  field(:enable, "enable", flag)
end

@doc """
device_row: [name, host] or [name, host, port], one per ESPHome device.
"""
def device_row()
  fn(r)
    verdict(
      list?(r) and
        (size(r) == 2 or size(r) == 3) and
        passes?(name_text, first(r)) and
        passes?(text, r[1]) and
        (size(r) == 2 or passes?(int_in(1, 65535), last(r))),
      "#{r} is not [name, host] or [name, host, port]"
    )
  end
end

def device_render(rows)
  reduce((acc, r) -> assoc(acc, first(r), device_of(r)), {}, rows)
end

def device_of(r)
  if size(r) == 3
    {"host" => r[1], "port" => last(r)}
  else
    {"host" => r[1]}
  end
end

@doc """
camera_row: [name, stream], one per Frigate camera; the stream is rtsp(s)://.
"""
def camera_row()
  fn(r)
    verdict(
      list?(r) and
        size(r) == 2 and
        passes?(name_text, first(r)) and
        string?(last(r)) and
        (
          strip_prefix(last(r), "rtsp://") != last(r) or
          strip_prefix(last(r), "rtsps://") != last(r)
        ),
      "#{r} is not [name, rtsp(s)://stream]"
    )
  end
end

def camera_render(rows)
  reduce((acc, r) -> assoc(acc, first(r), {"stream" => last(r)}), {}, rows)
end

def rows_field(key, json, row_check, render)
  assoc(field(key, json, list_of(row_check)), :render, render)
end

@doc """
components: Every component the stack knows: its name here, its name in pleme.lareira,
its settings, and the radio it bridges (nil for none).
"""
def components()
  [
    [:mosquitto, "mosquitto", [enable_field], nil],
    [
      :zigbee2mqtt,
      "zigbee2mqtt",
      [enable_field, field(:permit_join, "permitJoin", flag)],
      "zigbee"
    ],
    [:zwave_js, "zwaveJs", [enable_field], "zwave"],
    [:matter, "matter", [enable_field], nil],
    [
      :otbr,
      "otbr",
      [enable_field, field(:backbone_interface, "backboneInterface", text)],
      "thread"
    ],
    [
      :esphome,
      "esphome",
      [
        enable_field,
        rows_field(:devices, "devices", device_row, device_render)
      ],
      nil
    ],
    [
      :whisper,
      "whisper",
      [
        enable_field,
        field(:model, "model", text),
        field(:language, "language", text)
      ],
      nil
    ],
    [:piper, "piper", [enable_field, field(:voice, "voice", text)], nil],
    [:wakeword, "wakeword", [enable_field], nil],
    [
      :frigate,
      "frigate",
      [
        enable_field,
        rows_field(:cameras, "cameras", camera_row, camera_render)
      ],
      nil
    ],
    [:go2rtc, "go2rtc", [enable_field], nil],
    [
      :music_assistant,
      "musicAssistant",
      [enable_field, field(:providers, "providers", list_of(text))],
      nil
    ],
    [:node_red, "nodeRed", [enable_field], nil],
    [
      :nats,
      "nats",
      [enable_field, field(:bridge_mqtt, "bridgeMqtt", flag)],
      nil
    ]
  ]
end

def component_row(name)
  rows = filter((c) -> first(c) == name, components)
  if is_empty(rows)
    nil
  else
    first(rows)
  end
end

def component_names()
  map((c) -> first(c), components)
end

# ── entries: a home is a list of them; a mood set is a list inside it ─────

@doc """
site: Which home this is, by its site name.
"""
def site(name)
  entry(:site, "site", {name:})
end

@doc """
site_at: A site with its true coordinates rather than the site's city-level point.
"""
def site_at(name, latitude, longitude, elevation)
  entry(
    :site,
    "site",
    {name:, coordinates: {latitude:, longitude:, elevation:}}
  )
end

@doc """
delivery: How the stack runs: "systemd" or "engenho".
"""
def delivery(how)
  entry(:delivery, "delivery", how)
end

@doc """
exposure: Where human-facing UIs are reachable: "tailnet" or "lan".
"""
def exposure(where)
  entry(:exposure, "exposure", where)
end

@doc """
secrets_source: Where /run/secrets/lareira comes from: "sops" or "external".
"""
def secrets_source(source)
  entry(:secrets_source, "secrets_source", source)
end

@doc """
recorder: Home Assistant's history database: "sqlite" or "postgres".
"""
def recorder(kind)
  entry(:recorder, "recorder", kind)
end

@doc """
media_base_url: The address the speakers fetch tones from.
"""
def media_base_url(url)
  entry(:media_base_url, "media_base_url", url)
end

@doc """
media_base_url_from_host: The address is the host's to supply (nix renders it from its own topology):
moods may play, and the projection leaves the field for the module to fill.
"""
def media_base_url_from_host()
  entry(:media_base_url, "media_base_url", :host)
end

@doc """
component: A component with its settings: component(:whisper, {enable: true, language: "pt"}).
"""
def component(name, settings)
  entry(:component, to_s(name), settings)
end

def on(name)
  component(name, {enable: true})
end

@doc """
off: Declared, and configured off.
"""
def off(name)
  component(name, {enable: false})
end

@doc """
integration: A Home Assistant integration to load, by domain.
"""
def integration(domain)
  entry(:integration, domain, domain)
end

def integrations(domains)
  map(integration, domains)
end

@doc """
speaker: A speaker by short name, as the media_player entity Home Assistant gives it.
"""
def speaker(name, entity_id)
  entry(:speaker, name, entity_id)
end

@doc """
light_role: A named group of lights a mood can address without knowing the house.
"""
def light_role(role, lights)
  entry(:light_role, role, lights)
end

@doc """
tone: A sound the house can play: tone("hz174", {frequency: 174}).
"""
def tone(name, spec)
  entry(:tone, name, spec)
end

@doc """
mood: A whole-house state (lights and sound), one script and one phone button.
"""
def mood(name, fields)
  entry(:mood, name, fields)
end

@doc """
mood_of: The one-line mood: label, icon, colour, lights, then the tone it plays and
at what volume.
"""
def mood_of(name, label, icon_name, color, lights, tone_name, volume)
  mood(
    name,
    {label:, icon: icon_name, color:, lights:, sound: sound(tone_name, volume)}
  )
end

@doc """
with: The entry with one more field: with(mood_of(…), :breathing, breathing(…)).
"""
def with(e, key, v)
  entry(kind_of(e), name_of(e), assoc(value_of(e), key, v))
end

def white(brightness_pct, kelvin)
  {brightness_pct:, kelvin:}
end

def tint(brightness_pct, rgb)
  {brightness_pct:, rgb:}
end

def slow(seconds, lights)
  assoc(lights, :transition, seconds)
end

def lights_off(seconds)
  {brightness_pct: 0, transition: seconds}
end

@doc """
on_role: Only the lights a role names; the home says which lights those are.
"""
def on_role(role, lights)
  assoc(lights, :role, role)
end

def breathing(low_pct, high_pct, inhale, exhale, minutes)
  {low_pct:, high_pct:, inhale:, exhale:, minutes:}
end

def hand_over(after_minutes, mood_name)
  {after_minutes:, mood: mood_name}
end

def sound(tone_name, volume)
  {tone: tone_name, volume:}
end

@doc """
mood_set: Moods under one dashboard heading; a mood that names its own group keeps it.
"""
def mood_set(group, moods)
  map(
    fn(m)
      if value_of(m)[:group].nil?
        with(m, :group, group)
      else
        m
      end
    end,
    moods
  )
end

@doc """
tune: Fields laid over an entry declared earlier, so a home retunes or configures
off what a mood set gave it: tune(:mood, "relax", {enable: false}).
"""
def tune(kind, name, fields)
  {entry: :tune, name: "#{kind}/#{name}", target: kind, of: name, value: fields}
end

# ── judging: each entry on its own, then against the entries that stand ──

def flat(entries)
  flat_map(
    entries,
    fn(x)
      if map?(x)
        [x]
      else
        flat(x)
      end
    end
  )
end

def singleton_checks()
  [
    [:delivery, one_of(%w[systemd engenho])],
    [:exposure, one_of(%w[tailnet lan])],
    [:secrets_source, one_of(%w[sops external])],
    [:recorder, one_of(%w[sqlite postgres])],
    [:media_base_url, base_url]
  ]
end

def refuse_entry(kind, e, why)
  refusal(kind, "#{where(e)}: #{why}")
end

def whys_to_refusals(e, whys)
  if is_empty(whys)
    []
  else
    [refuse_entry(:invalid, e, join(whys, "; "))]
  end
end

def check_why(check, v)
  w = check(v)
  if w.nil?
    []
  else
    [w]
  end
end

def local_refusals(e)
  k = kind_of(e)
  v = value_of(e)
  singles = filter((s) -> first(s) == k, singleton_checks)
  if not is_empty(singles)
    whys_to_refusals(e, check_why(last(first(singles)), v))
  elsif k == :site
    whys_to_refusals(e, record_whys(site_table, v))
  elsif k == :integration
    whys_to_refusals(
      e,
      check_why(
        fn(d)
          verdict(string?(d) and made_of(d, slug_chars), "#{d} is not a domain")
        end,
        v
      )
    )
  elsif k == :speaker
    append(
      whys_to_refusals(e, check_why(name_text, name_of(e))),
      whys_to_refusals(e, check_why(entity("media_player"), v))
    )
  elsif k == :light_role
    append(
      whys_to_refusals(e, check_why(name_text, name_of(e))),
      whys_to_refusals(e, check_why(list_of(entity("light")), v))
    )
  elsif k == :tone
    tone_refusals(e)
  elsif k == :mood
    mood_refusals(e)
  elsif k == :component
    component_refusals(e)
  else
    [refuse_entry(:unknown_entry, e, "no such kind of entry")]
  end
end

def tone_refusals(e)
  v = value_of(e)
  whys = append(check_why(name_text, name_of(e)), record_whys(tone_table, v))
  if not is_empty(whys)
    whys_to_refusals(e, whys)
  else
    refused_if(
      v[:frequency].nil? and is_empty(v[:frequencies]) and v[:noise].nil?,
      :silent,
      e,
      "a tone needs a frequency, frequencies or a noise"
    )
  end
end

def both?(l, a, b)
  l != nil and get(l, a) != nil and get(l, b) != nil
end

def lights_conflicts(e, l)
  append(
    refused_if(
      both?(l, :rgb, :kelvin),
      :conflict,
      e,
      "lights set rgb or kelvin, not both"
    ),
    refused_if(
      both?(l, :only, :role),
      :conflict,
      e,
      "lights name entities or a role, not both"
    )
  )
end

def mood_refusals(e)
  v = value_of(e)
  whys = append(check_why(name_text, name_of(e)), record_whys(mood_table, v))
  b = v[:breathing]
  if not is_empty(whys)
    whys_to_refusals(e, whys)
  elsif b != nil and b[:low_pct] >= b[:high_pct]
    [refuse_entry(:breath, e, "breathing needs low_pct below high_pct")]
  else
    lights_conflicts(e, v[:lights])
  end
end

def component_refusals(e)
  row = component_row(component_key(e))
  v = value_of(e)
  if row.nil?
    [
      refuse_entry(
        :unknown_component,
        e,
        "not one of #{join(map((n) -> to_s(n), component_names), ", ")}"
      )
    ]
  else
    whys = record_whys(row[2], v)
    enabled = v[:enable] == true
    if not is_empty(whys)
      whys_to_refusals(e, whys)
    elsif enabled and last(row) != nil
      [
        refuse_entry(
          :needs_radio,
          e,
          "it bridges a #{last(row)} radio, and jitaku declares no radios yet"
        )
      ]
    elsif enabled and first(row) == :frigate and is_empty(v[:cameras])
      [refuse_entry(:no_cameras, e, "Frigate with no cameras records nothing")]
    else
      []
    end
  end
end

def component_key(e)
  n = name_of(e)
  hits = filter((c) -> to_s(c) == n, component_names)
  if is_empty(hits)
    nil
  else
    first(hits)
  end
end

def entry_id(e)
  "#{kind_of(e)}/#{name_of(e)}"
end

@doc """
duplicate_refusals: A name is declared once: every later declaration of it is refused.
"""
def duplicate_refusals(es)
  ids = map(entry_id, es)
  map(
    fn(i)
      refused_if(
        index_of(ids, ids[i]) < i,
        :duplicate,
        es[i],
        "declared twice; the first stands"
      )
    end,
    range(0, size(es))
  )
end

def fields_of(kind)
  if kind == :mood
    mood_table
  elsif kind == :tone
    tone_table
  end
end

def overlay(table, base, fields)
  reduce(
    fn(acc, f)
      if get(fields, f[:key]).nil?
        acc
      else
        assoc(acc, f[:key], get(fields, f[:key]))
      end
    end,
    base,
    table
  )
end

def tune_refusals(t, es)
  table = fields_of(t[:target])
  hits = filter((e) -> kind_of(e) == t[:target] and name_of(e) == t[:of], es)
  if table.nil?
    [refuse_entry(:invalid, t, "only a mood or a tone is tuned")]
  elsif is_empty(hits)
    [refuse_entry(:unknown_entry, t, "nothing declared to tune")]
  else
    whys_to_refusals(t, record_whys(table, value_of(t)))
  end
end

@doc """
apply_tunes: Every tune laid onto its entry, in order; each tune is checked first.
"""
def apply_tunes(es)
  tunes = filter((e) -> kind_of(e) == :tune, es)
  base = filter((e) -> kind_of(e) != :tune, es)
  bad = map((t) -> tune_refusals(t, base), tunes)
  good = kyohi::standing(tunes, bad)
  {entries: map((e) -> tuned(e, good), base), refusals: flat_map(bad, (r) -> r)}
end

def tuned(e, tunes)
  reduce(
    fn(acc, t)
      if kind_of(acc) == t[:target] and name_of(acc) == t[:of]
        entry(
          kind_of(acc),
          name_of(acc),
          overlay(fields_of(kind_of(acc)), value_of(acc), value_of(t))
        )
      else
        acc
      end
    end,
    e,
    tunes
  )
end

def names_of_kind(es, kind)
  map(name_of, filter((e) -> kind_of(e) == kind, es))
end

def has_kind?(es, kind)
  not is_empty(names_of_kind(es, kind))
end

def active?(m)
  kind_of(m) == :mood and value_of(m)[:enable] != false
end

def phone?(m)
  active?(m) and value_of(m)[:phone_button] != false
end

def label_of(m)
  l = value_of(m)[:label]
  if l.nil?
    name_of(m)
  else
    l
  end
end

def missing(names, known)
  filter((n) -> not contains(known, n), names)
end

def role_lights(es, role)
  hits = filter((e) -> kind_of(e) == :light_role and name_of(e) == role, es)
  if is_empty(hits)
    []
  else
    value_of(first(hits))
  end
end

@doc """
mood_needs: What one standing mood still lacks among the entries that stand with it.
"""
def mood_needs(m, es)
  v = value_of(m)
  s = v[:sound]
  l = v[:lights]
  active = filter((e) -> kind_of(e) == :mood and active?(e), es)
  targets = map((h) -> h[:mood], v[:then] or [])
  lost = missing(targets, names_of_kind(active, :mood))
  phones = filter(phone?, es)
  role = (l or {})[:role]
  tone_name = (s or {})[:tone]
  deaf = missing((s or {})[:speakers] or [], names_of_kind(es, :speaker))
  flat_map(
    [
      refused_if(
        s != nil and not contains(names_of_kind(es, :tone), tone_name),
        :unknown_tone,
        m,
        "no tone #{tone_name} stands"
      ),
      refused_if(
        not is_empty(deaf),
        :unknown_speaker,
        m,
        "no speaker #{join(deaf, ", ")} stands"
      ),
      refused_if(
        s != nil and not has_kind?(es, :media_base_url),
        :no_media_base_url,
        m,
        "it plays a tone, and no media_base_url stands"
      ),
      refused_if(
        s != nil and not has_kind?(es, :speaker),
        :no_speakers,
        m,
        "it plays a tone, and no speaker stands"
      ),
      refused_if(
        not is_empty(lost),
        :unknown_mood,
        m,
        "it hands over to #{join(lost, ", ")}, not a standing mood"
      ),
      refused_if(
        role != nil and is_empty(role_lights(es, role)),
        :unknown_role,
        m,
        "no light role #{role} with lights stands"
      ),
      refused_if(
        phone?(m) and
          index_of(map(label_of, phones), label_of(m)) <
            index_of(map(name_of, phones), name_of(m)),
        :duplicate_label,
        m,
        "an earlier phone button already says #{label_of(m)}"
      )
    ],
    (g) -> g
  )
end

@doc """
refused_if: [the refusal] when `fault` holds, else nothing.
"""
def refused_if(fault, kind, e, why)
  if fault
    [refuse_entry(kind, e, why)]
  else
    []
  end
end

def needs(e, es)
  if kind_of(e) == :mood
    mood_needs(e, es)
  else
    []
  end
end

@doc """
settle: Refuse whatever lacks what it names, and again over what is left, until
nothing more falls: a mood handing over to a refused mood falls with it.
"""
def settle(standing, refused)
  fresh = map((e) -> needs(e, standing), standing)
  falls = flat_map(fresh, (r) -> r)
  if is_empty(falls)
    {accepted: standing, refusals: refused}
  else
    settle(kyohi::standing(standing, fresh), append(refused, falls))
  end
end

@doc """
judge: The home judged: `accepted`, the entries that stand (tunes applied), and
`refusals`, one or more per entry that does not, each naming it. A bad
entry is refused alone; its siblings stand.
"""
def judge(entries)
  t = apply_tunes(flat(entries))
  es = t[:entries]
  own = map(local_refusals, es)
  dups = duplicate_refusals(es)
  marks = map((i) -> append(own[i], dups[i]), range(0, size(es)))
  first_pass = kyohi::standing(es, marks)
  settled = settle(first_pass, append(t[:refusals], flat_map(marks, (r) -> r)))
  site_missing = if has_kind?(settled[:accepted], :site)
    []
  else
    [refusal(:no_site, "a home needs a site")]
  end
  {
    accepted: settled[:accepted],
    refusals: append(settled[:refusals], site_missing)
  }
end

def accepted(entries)
  judge(entries)[:accepted]
end

def refusals(entries)
  judge(entries)[:refusals]
end

# ── the projection: pleme.lareira's attribute set ──────────────────────────

def of_kind(es, kind)
  filter((e) -> kind_of(e) == kind, es)
end

@doc """
resolved: A role-addressed mood's lights become the role's lights.
"""
def resolved(m, es)
  l = value_of(m)[:lights]
  if l.nil? or l[:role].nil?
    value_of(m)
  else
    assoc(value_of(m), :lights, assoc(l, :only, role_lights(es, l[:role])))
  end
end

def component_json(es)
  reduce(
    fn(acc, e)
      component_into(acc, component_row(component_key(e)), value_of(e))
    end,
    {},
    of_kind(es, :component)
  )
end

def component_into(acc, row, settings)
  assoc(acc, row[1], project(row[2], settings))
end

@doc """
slot: A key of the projection: where it goes, the kind of entry it gathers, and
how those entries render. A kind with no standing entry leaves the key out,
so the module's default holds.
"""
def slot(json, kind, render)
  [json, kind, render]
end

def filled(acc, es, slots)
  reduce((m, s) -> slot_into(m, s, of_kind(es, s[1])), acc, slots)
end

def slot_into(acc, s, hits)
  if is_empty(hits)
    acc
  else
    rendered = applied(last(s), hits)
    if rendered.nil?
      acc
    else
      assoc(acc, first(s), rendered)
    end
  end
end

def unless_host(v)
  if v == :host
    nil
  else
    v
  end
end

def single(render)
  (hits) -> render(first(hits))
end

def by_name(render)
  (hits) -> reduce((m, e) -> assoc(m, name_of(e), render(e)), {}, hits)
end

def home_assistant(es)
  filled(
    {},
    es,
    [
      slot("recorder", :recorder, single(value_of)),
      slot(
        "mediaBaseUrl",
        :media_base_url,
        single((e) -> unless_host(value_of(e)))
      ),
      slot("integrations", :integration, (hits) -> map(name_of, hits)),
      slot("speakers", :speaker, by_name(value_of)),
      slot("lightRoles", :light_role, by_name(value_of)),
      slot("tones", :tone, by_name((e) -> project(tone_table, value_of(e)))),
      slot("moods", :mood, by_name((e) -> project(mood_table, resolved(e, es))))
    ]
  )
end

@doc """
lareira: The attribute set pleme.lareira takes, from the entries that stand:
`pleme.lareira = lib.importJSON ./home.json`.
"""
def lareira(entries)
  es = accepted(entries)
  out = filled(
    {"enable" => true},
    es,
    [
      slot("delivery", :delivery, single(value_of)),
      slot("exposure", :exposure, single(value_of)),
      slot("secretsSource", :secrets_source, single(value_of)),
      slot("site", :site, single((e) -> project(site_table, value_of(e)))),
      slot("components", :component, component_json)
    ]
  )
  ha = home_assistant(es)
  if ha == {}
    out
  else
    assoc(out, "homeAssistant", ha)
  end
end

def to_json(entries)
  json_stringify(lareira(entries))
end

def example_home()
  [
    site("natal"),
    delivery("engenho"),
    on(:mosquitto),
    component(:whisper, {enable: true, language: "pt"}),
    off(:node_red),
    integrations(%w[default_config met]),
    media_base_url("http://192.0.2.10:8123"),
    speaker("kitchen", "media_player.kitchen_speaker"),
    light_role("nightPath", ["light.hallway"]),
    tone("hz432", {frequency: 432}),
    tone("confirm-chime", {frequencies: [659, 880], seconds: 3}),
    mood_set(
      "Essentials",
      [
        mood_of(
          "relax",
          "Relax",
          "weather-night",
          "#8B1A00",
          tint(10, [255, 45, 0]),
          "hz432",
          0.3
        ),
        mood_of(
          "lightsNormal",
          "Lights Normal",
          "lightbulb",
          "#BDC3C7",
          white(80, 2700),
          "confirm-chime",
          0.25
        )
      ]
    ),
    with(
      mood_of(
        "glow",
        "Glow",
        "weather-night-partly-cloudy",
        "#4A235A",
        on_role("nightPath", tint(3, [255, 40, 0])),
        "hz432",
        0.08
      ),
      :then,
      [hand_over(5, "lightsNormal")]
    )
  ]
end

def home_doc(entries)
  json_parse(to_json(entries))
end

def mood_doc(entries, name)
  json_get(json_get(json_get(home_doc(entries), :homeAssistant), :moods), name)
end

test "an empty home is on, and refused only for the site it lacks"
  assert kinds(refusals([])) == [:no_site]
  assert accepted([]) == []
  assert to_json([]) == "{\"enable\":true}"
  assert kinds(refusals([site("natal")])) == []
end

test "a tone and a mood project field for field as pleme.lareira takes them"
  assert to_json(
    [
      site("natal"),
      tone(
        "alpha-10hz",
        {frequency: 200, tremolo: 10.0, depth: 1.0, minutes: 30}
      )
    ]
  ) ==
    "{\"enable\":true,\"homeAssistant\":{\"tones\":{\"alpha-10hz\":{\"depth\":1.0,\"frequency\":200,\"minutes\":30,\"tremolo\":10.0}}},\"site\":{\"name\":\"natal\"}}"
  assert json_stringify(lareira(example_home)) == to_json(example_home)
  relax = json_stringify(
    project(
      mood_table,
      value_of(
        nth(
          0,
          mood_set(
            "Essentials",
            [
              mood_of(
                "relax",
                "Relax",
                "weather-night",
                "#8B1A00",
                tint(10, [255, 45, 0]),
                "hz432",
                0.3
              )
            ]
          )
        )
      )
    )
  )
  assert relax ==
    "{\"color\":\"#8B1A00\",\"group\":\"Essentials\",\"icon\":\"weather-night\",\"label\":\"Relax\",\"lights\":{\"brightnessPct\":10,\"rgb\":[255,45,0]},\"sound\":{\"tone\":\"hz432\",\"volume\":0.3}}"
end

test "judging is idempotent: what stands, judged again, all stands"
  h = example_home
  assert refusals(h) == []
  assert accepted(accepted(h)) == accepted(h)
  assert to_json(accepted(h)) == to_json(h)
  assert size(accepted(h)) == 15
end

test "a role-addressed mood takes the role's lights, and hands over by name"
  glow = mood_doc(example_home, "glow")
  assert json_get(json_get(glow, :lights), :only) == ["light.hallway"]
  assert json_get(first(json_get(glow, :then)), :afterMinutes) == 5
  assert json_get(json_get(glow, :lights), :role).nil?
end

test "a bad entry is refused alone, and what names it falls with it"
  h = append(
    example_home,
    [
      mood_of("hot", "Hot", "fire", "#FF0000", white(50, 9000), "hz432", 0.3),
      mood_of("warm", "Warm", "fire", "#FF0000", white(50, 3000), "hz432", 0.3),
      tone("too-low", {frequency: 5}),
      mood_of(
        "rumble",
        "Rumble",
        "speaker",
        "#000000",
        white(10, 3000),
        "too-low",
        0.2
      ),
      with(
        mood_of(
          "after",
          "After",
          "speaker",
          "#000000",
          white(10, 3000),
          "hz432",
          0.2
        ),
        :then,
        [hand_over(1, "rumble")]
      ),
      tone("hz432", {frequency: 440}),
      on(:zigbee2mqtt),
      mood("typo", {label: "Typo", lights: {brightnes: 10}})
    ]
  )
  assert kinds(refusals(h)) ==
    %i[invalid invalid duplicate needs_radio invalid unknown_tone unknown_mood]
  moods = json_get(json_get(home_doc(h), :homeAssistant), :moods)
  assert json_get(moods, :warm) != nil
  assert json_get(moods, :hot).nil?
  assert json_get(moods, :rumble).nil?
  assert json_get(moods, :after).nil?
  assert json_get(moods, :relax) != nil
  assert json_get(
    json_get(json_get(json_get(home_doc(h), :homeAssistant), :tones), :hz432),
    :frequency
  ) == 432
  assert json_get(json_get(home_doc(h), :components), :zigbee2mqtt).nil?
  assert json_get(
    json_get(json_get(home_doc(h), :components), :mosquitto),
    :enable
  ) == true
end

test "a tune configures a set's mood off without forking the set"
  h = append(
    example_home,
    [
      tune(:mood, "relax", {enable: false}),
      tune(:mood, "absent", {enable: false})
    ]
  )
  assert kinds(refusals(h)) == [:unknown_entry]
  assert json_get(mood_doc(h, "relax"), :enable) == false
  assert json_get(mood_doc(h, "relax"), :label) == "Relax"
  assert kinds(
    refusals(
      append(
        example_home,
        [
          tune(:mood, "relax", {enable: false}),
          mood("x", {label: "X", then: [hand_over(1, "relax")]})
        ]
      )
    )
  ) == [:unknown_mood]
end

test "a mood plays only where a base url and speakers stand"
  bare = [
    site("natal"),
    tone("hz432", {frequency: 432}),
    mood("m", {sound: sound("hz432", 0.3)})
  ]
  assert kinds(refusals(bare)) == %i[no_media_base_url no_speakers]
  assert kinds(
    refusals(append(bare, [media_base_url("ftp://x"), speaker("k", "light.k")]))
  ) == %i[invalid invalid no_media_base_url no_speakers]
  assert kinds(
    refusals(
      append(
        bare,
        [media_base_url("http://x:8123"), speaker("k", "media_player.k")]
      )
    )
  ) == []
  hosted = append(
    bare,
    [media_base_url_from_host, speaker("k", "media_player.k")]
  )
  assert kinds(refusals(hosted)) == []
  assert lareira(hosted)["homeAssistant"]["mediaBaseUrl"].nil?
  assert lareira(hosted)["homeAssistant"]["moods"]["m"] != nil
end

test "a field the table does not know is refused, never dropped"
  ok = [site("natal"), mood("m", {label: "M", lights: {brightness_pct: 10}})]
  typo = [
    site("natal"),
    mood("m", {label: "M", lights: {brightness_pct: 10, kelvn: 3000}})
  ]
  assert refusals(ok) == []
  assert kinds(refusals(typo)) == [:invalid]
  assert kinds(
    refusals([site("natal"), tone("t", {frequency: 432, volume: 1})])
  ) == [:invalid]
end
