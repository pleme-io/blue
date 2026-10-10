use("kyohi", [:kinds, :refusal])
use("moji", [:is_hex, :made_of, :strip_prefix])
use("retsu", [:contains, :first, :flat_map, :index_of, :is_empty, :last, :size])

# jitaku (自宅) — a home, declared entry by entry, each refused alone, projected to pleme.lareira.
#
# A home is a list of entries: its site, delivery and exposure, components with
# their settings, Home Assistant integrations, speakers, lights by role, tones,
# moods, and mood sets (lists of moods). `lareira` gives the attribute set the
# nix module takes, from the entries that stand; `refusals` names the rest.

# ── checks: a check is fn(value) answering nil, or why the value is wrong ──

def verdict(ok, why)
  if ok
    nil
  else
    why
  end
end

def int_in(lo, hi)
  fn(v)
    verdict(
      integer?(v) && v >= lo && v <= hi,
      "#{v} is not a whole number in #{lo}..#{hi}"
    )
  end
end

def number_in(lo, hi)
  fn(v)
    verdict(
      number?(v) && v >= lo && v <= hi,
      "#{v} is not a number in #{lo}..#{hi}"
    )
  end
end

def float_in(lo, hi)
  fn(v)
    verdict(
      float?(v) && v >= lo && v <= hi,
      "#{v} is not a float in #{lo}..#{hi}"
    )
  end
end

def flag()
  fn(v) verdict(bool?(v), "#{v} is not true or false") end
end

def text()
  fn(v) verdict(string?(v) && length(v) > 0, "#{v} is not text") end
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
  "#{lower_digits()}_"
end

def name_chars()
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
end

# A name a home gives a thing (a tone, a mood, a speaker, a role).
def name_text()
  fn(v)
    verdict(string?(v) && made_of(v, name_chars()), "#{v} is not a name")
  end
end

# A Home Assistant entity id in `domain`: `light.hallway`.
def entity(domain)
  fn(v)
    verdict(
      string?(v) &&
        made_of(strip_prefix(v, "#{domain}."), slug_chars()) &&
        strip_prefix(v, "#{domain}.") != v,
      "#{v} is not a #{domain} entity"
    )
  end
end

def icon()
  fn(v)
    verdict(
      string?(v) && made_of(v, "#{lower_digits()}-"),
      "#{v} is not a Material Design Icons name"
    )
  end
end

def hex_color()
  fn(v)
    verdict(
      string?(v) &&
        length(v) == 7 &&
        strip_prefix(v, "#") != v &&
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
      string?(v) &&
        host_of(v) != v &&
        length(host_of(v)) > 0 &&
        !contains(chars(host_of(v)), "/"),
      "#{v} is not http(s)://host[:port]"
    )
  end
end

def applied(f, v)
  f(v)
end

def passes?(check, v)
  applied(check, v) == nil
end

def first_why(check, xs)
  whys = filter(fn(w) w != nil end, map(fn(x) check(x) end, xs))
  if is_empty(whys)
    nil
  else
    first(whys)
  end
end

def list_of(check)
  fn(v)
    if v != nil && list?(v) && !map?(v)
      first_why(check, v)
    else
      "#{v} is not a list"
    end
  end
end

def three_of(check)
  fn(v)
    if v != nil && list?(v) && size(v) == 3
      first_why(check, v)
    else
      "#{v} is not three values"
    end
  end
end

# ── records: a table of fields, read once to check and once to project ─────

# A field: its key in blue, its key in pleme.lareira (nil: blue's alone), the
# check its value passes, and how its value is rendered.
def field(key, json, check)
  {key: key, json: json, check: check, render: fn(v) v end, required: false}
end

def required(f)
  assoc(f, :required, true)
end

def record_field(key, json, table)
  {
    key: key,
    json: json,
    check: record_check(table),
    render: fn(v) project(table, v) end,
    required: false
  }
end

def records_field(key, json, table)
  {
    key: key,
    json: json,
    check: list_of(record_check(table)),
    render: fn(v) map(fn(r) project(table, r) end, v) end,
    required: false
  }
end

def key_text(f)
  to_s(get(f, :key))
end

# The keys a map was written with, as text. Blue has no word that lists a
# map's keys; JSON text does, so the map is read back through it.
def key_names(m)
  map(fn(p) first(p) end, json_parse(json_stringify(m)))
end

def field_why(f, m)
  v = get(m, get(f, :key))
  if v == nil
    verdict(!get(f, :required), "#{key_text(f)} is required")
  else
    why = applied(get(f, :check), v)
    if why == nil
      nil
    else
      "#{key_text(f)}: #{why}"
    end
  end
end

def record_whys(table, m)
  if m == nil || !map?(m)
    ["#{m} is not a record"]
  else
    known = map(fn(f) key_text(f) end, table)
    unknown = map(
      fn(k) "#{k} is not a field here" end,
      filter(fn(k) !contains(known, k) end, key_names(m))
    )
    append(
      unknown,
      filter(fn(w) w != nil end, map(fn(f) field_why(f, m) end, table))
    )
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

# The record in pleme.lareira's spelling: its declared fields only, so every
# default stays the module's.
def project(table, m)
  reduce(fn(acc, f) projected(acc, f, m) end, {}, table)
end

def projected(acc, f, m)
  v = get(m, get(f, :key))
  if v == nil || get(f, :json) == nil
    acc
  else
    assoc(acc, get(f, :json), applied(get(f, :render), v))
  end
end

# ── the tables ──────────────────────────────────────────────────────────────

def tone_table()
  [
    field(:frequency, "frequency", int_in(20, 20000)),
    field(:frequencies, "frequencies", list_of(int_in(20, 20000))),
    field(:noise, "noise", one_of(["white", "pink", "brown"])),
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
    field(:role, nil, name_text()),
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
    required(field(:mood, "mood", name_text()))
  ]
end

def sound_table()
  [
    required(field(:tone, "tone", name_text())),
    field(:volume, "volume", number_in(0.0, 1.0)),
    field(:speakers, "speakers", list_of(name_text()))
  ]
end

def mood_table()
  [
    field(:label, "label", text()),
    field(:group, "group", text()),
    field(:icon, "icon", icon()),
    field(:color, "color", hex_color()),
    field(:enable, "enable", flag()),
    field(:phone_button, "phoneButton", flag()),
    record_field(:lights, "lights", lights_table()),
    record_field(:breathing, "breathing", breathing_table()),
    records_field(:then, "then", hand_over_table()),
    record_field(:sound, "sound", sound_table())
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
    required(field(:name, "name", name_text())),
    record_field(:coordinates, "coordinates", coordinates_table())
  ]
end

def enable_field()
  field(:enable, "enable", flag())
end

# [name, host] or [name, host, port], one per ESPHome device.
def device_row()
  fn(r)
    verdict(
      list?(r) &&
        (size(r) == 2 || size(r) == 3) &&
        passes?(name_text(), first(r)) &&
        passes?(text(), nth(1, r)) &&
        (size(r) == 2 || passes?(int_in(1, 65535), last(r))),
      "#{r} is not [name, host] or [name, host, port]"
    )
  end
end

def device_render(rows)
  reduce(fn(acc, r) assoc(acc, first(r), device_of(r)) end, {}, rows)
end

def device_of(r)
  if size(r) == 3
    {"host" => nth(1, r), "port" => last(r)}
  else
    {"host" => nth(1, r)}
  end
end

# [name, stream], one per Frigate camera; the stream is rtsp(s)://.
def camera_row()
  fn(r)
    verdict(
      list?(r) &&
        size(r) == 2 &&
        passes?(name_text(), first(r)) &&
        string?(last(r)) &&
        (strip_prefix(last(r), "rtsp://") != last(r) ||
          strip_prefix(last(r), "rtsps://") != last(r)),
      "#{r} is not [name, rtsp(s)://stream]"
    )
  end
end

def camera_render(rows)
  reduce(fn(acc, r) assoc(acc, first(r), {"stream" => last(r)}) end, {}, rows)
end

def rows_field(key, json, row_check, render)
  assoc(field(key, json, list_of(row_check)), :render, render)
end

# Every component the stack knows: its name here, its name in pleme.lareira,
# its settings, and the radio it bridges (nil for none).
def components()
  [
    [:mosquitto, "mosquitto", [enable_field()], nil],
    [
      :zigbee2mqtt,
      "zigbee2mqtt",
      [enable_field(), field(:permit_join, "permitJoin", flag())],
      "zigbee"
    ],
    [:zwave_js, "zwaveJs", [enable_field()], "zwave"],
    [:matter, "matter", [enable_field()], nil],
    [
      :otbr,
      "otbr",
      [enable_field(), field(:backbone_interface, "backboneInterface", text())],
      "thread"
    ],
    [
      :esphome,
      "esphome",
      [
        enable_field(),
        rows_field(
          :devices,
          "devices",
          device_row(),
          fn(v) device_render(v) end
        )
      ],
      nil
    ],
    [
      :whisper,
      "whisper",
      [
        enable_field(),
        field(:model, "model", text()),
        field(:language, "language", text())
      ],
      nil
    ],
    [:piper, "piper", [enable_field(), field(:voice, "voice", text())], nil],
    [:wakeword, "wakeword", [enable_field()], nil],
    [
      :frigate,
      "frigate",
      [
        enable_field(),
        rows_field(
          :cameras,
          "cameras",
          camera_row(),
          fn(v) camera_render(v) end
        )
      ],
      nil
    ],
    [:go2rtc, "go2rtc", [enable_field()], nil],
    [
      :music_assistant,
      "musicAssistant",
      [enable_field(), field(:providers, "providers", list_of(text()))],
      nil
    ],
    [:node_red, "nodeRed", [enable_field()], nil],
    [
      :nats,
      "nats",
      [enable_field(), field(:bridge_mqtt, "bridgeMqtt", flag())],
      nil
    ]
  ]
end

def component_row(name)
  rows = filter(fn(c) first(c) == name end, components())
  if is_empty(rows)
    nil
  else
    first(rows)
  end
end

def component_names()
  map(fn(c) first(c) end, components())
end

# ── entries: a home is a list of them; a mood set is a list inside it ─────

def entry(kind, name, value)
  {entry: kind, name: name, value: value}
end

def kind_of(e)
  get(e, :entry)
end

def name_of(e)
  get(e, :name)
end

def value_of(e)
  get(e, :value)
end

# Which home this is, by its site name.
def site(name)
  entry(:site, "site", {name: name})
end

# A site with its true coordinates rather than the site's city-level point.
def site_at(name, latitude, longitude, elevation)
  entry(
    :site,
    "site",
    {
      name: name,
      coordinates: {
        latitude: latitude,
        longitude: longitude,
        elevation: elevation
      }
    }
  )
end

# How the stack runs: "systemd" or "engenho".
def delivery(how)
  entry(:delivery, "delivery", how)
end

# Where human-facing UIs are reachable: "tailnet" or "lan".
def exposure(where)
  entry(:exposure, "exposure", where)
end

# Where /run/secrets/lareira comes from: "sops" or "external".
def secrets_source(source)
  entry(:secrets_source, "secrets_source", source)
end

# Home Assistant's history database: "sqlite" or "postgres".
def recorder(kind)
  entry(:recorder, "recorder", kind)
end

# The address the speakers fetch tones from.
def media_base_url(url)
  entry(:media_base_url, "media_base_url", url)
end

# A component with its settings: component(:whisper, {enable: true, language: "pt"}).
def component(name, settings)
  entry(:component, to_s(name), settings)
end

def on(name)
  component(name, {enable: true})
end

# Declared, and configured off.
def off(name)
  component(name, {enable: false})
end

# A Home Assistant integration to load, by domain.
def integration(domain)
  entry(:integration, domain, domain)
end

def integrations(domains)
  map(fn(d) integration(d) end, domains)
end

# A speaker by short name, as the media_player entity Home Assistant gives it.
def speaker(name, entity_id)
  entry(:speaker, name, entity_id)
end

# A named group of lights a mood can address without knowing the house.
def light_role(role, lights)
  entry(:light_role, role, lights)
end

# A sound the house can play: tone("hz174", {frequency: 174}).
def tone(name, spec)
  entry(:tone, name, spec)
end

# A whole-house state (lights and sound), one script and one phone button.
def mood(name, fields)
  entry(:mood, name, fields)
end

# The one-line mood: label, icon, colour, lights, then the tone it plays and
# at what volume.
def mood_of(name, label, icon_name, color, lights, tone_name, volume)
  mood(
    name,
    {
      label: label,
      icon: icon_name,
      color: color,
      lights: lights,
      sound: sound(tone_name, volume)
    }
  )
end

# The entry with one more field: with(mood_of(…), :breathing, breathing(…)).
def with(e, key, v)
  entry(kind_of(e), name_of(e), assoc(value_of(e), key, v))
end

def white(brightness_pct, kelvin)
  {brightness_pct: brightness_pct, kelvin: kelvin}
end

def tint(brightness_pct, rgb)
  {brightness_pct: brightness_pct, rgb: rgb}
end

def slow(seconds, lights)
  assoc(lights, :transition, seconds)
end

def lights_off(seconds)
  {brightness_pct: 0, transition: seconds}
end

# Only the lights a role names; the home says which lights those are.
def on_role(role, lights)
  assoc(lights, :role, role)
end

def breathing(low_pct, high_pct, inhale, exhale, minutes)
  {
    low_pct: low_pct,
    high_pct: high_pct,
    inhale: inhale,
    exhale: exhale,
    minutes: minutes
  }
end

def hand_over(after_minutes, mood_name)
  {after_minutes: after_minutes, mood: mood_name}
end

def sound(tone_name, volume)
  {tone: tone_name, volume: volume}
end

# Moods under one dashboard heading; a mood that names its own group keeps it.
def mood_set(group, moods)
  map(
    fn(m)
      if get(value_of(m), :group) == nil
        with(m, :group, group)
      else
        m
      end
    end,
    moods
  )
end

# Fields laid over an entry declared earlier, so a home retunes or configures
# off what a mood set gave it: tune(:mood, "relax", {enable: false}).
def tune(kind, name, fields)
  {entry: :tune, name: "#{kind}/#{name}", target: kind, of: name, value: fields}
end

# ── judging: each entry on its own, then against the entries that stand ──

def flat(entries)
  flat_map(
    fn(x)
      if map?(x)
        [x]
      else
        flat(x)
      end
    end,
    entries
  )
end

def singleton_checks()
  [
    [:delivery, one_of(["systemd", "engenho"])],
    [:exposure, one_of(["tailnet", "lan"])],
    [:secrets_source, one_of(["sops", "external"])],
    [:recorder, one_of(["sqlite", "postgres"])],
    [:media_base_url, base_url()]
  ]
end

def where(e)
  "#{kind_of(e)} #{name_of(e)}"
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
  if w == nil
    []
  else
    [w]
  end
end

def local_refusals(e)
  k = kind_of(e)
  v = value_of(e)
  singles = filter(fn(s) first(s) == k end, singleton_checks())
  if !is_empty(singles)
    whys_to_refusals(e, check_why(last(first(singles)), v))
  elsif k == :site
    whys_to_refusals(e, record_whys(site_table(), v))
  elsif k == :integration
    whys_to_refusals(
      e,
      check_why(
        fn(d)
          verdict(
            string?(d) && made_of(d, slug_chars()),
            "#{d} is not a domain"
          )
        end,
        v
      )
    )
  elsif k == :speaker
    append(
      whys_to_refusals(e, check_why(name_text(), name_of(e))),
      whys_to_refusals(e, check_why(entity("media_player"), v))
    )
  elsif k == :light_role
    append(
      whys_to_refusals(e, check_why(name_text(), name_of(e))),
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
  whys = append(
    check_why(name_text(), name_of(e)),
    record_whys(tone_table(), v)
  )
  if !is_empty(whys)
    whys_to_refusals(e, whys)
  else
    refused_if(
      get(v, :frequency) == nil &&
        is_empty(get(v, :frequencies)) &&
        get(v, :noise) == nil,
      :silent,
      e,
      "a tone needs a frequency, frequencies or a noise"
    )
  end
end

def both?(l, a, b)
  l != nil && get(l, a) != nil && get(l, b) != nil
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
  whys = append(
    check_why(name_text(), name_of(e)),
    record_whys(mood_table(), v)
  )
  b = get(v, :breathing)
  if !is_empty(whys)
    whys_to_refusals(e, whys)
  elsif b != nil && get(b, :low_pct) >= get(b, :high_pct)
    [refuse_entry(:breath, e, "breathing needs low_pct below high_pct")]
  else
    lights_conflicts(e, get(v, :lights))
  end
end

def component_refusals(e)
  row = component_row(component_key(e))
  v = value_of(e)
  if row == nil
    [
      refuse_entry(
        :unknown_component,
        e,
        "not one of #{join(map(fn(n) to_s(n) end, component_names()), ", ")}"
      )
    ]
  else
    whys = record_whys(nth(2, row), v)
    enabled = get(v, :enable) == true
    if !is_empty(whys)
      whys_to_refusals(e, whys)
    elsif enabled && last(row) != nil
      [
        refuse_entry(
          :needs_radio,
          e,
          "it bridges a #{last(row)} radio, and jitaku declares no radios yet"
        )
      ]
    elsif enabled && first(row) == :frigate && is_empty(get(v, :cameras))
      [refuse_entry(:no_cameras, e, "Frigate with no cameras records nothing")]
    else
      []
    end
  end
end

def component_key(e)
  n = name_of(e)
  hits = filter(fn(c) to_s(c) == n end, component_names())
  if is_empty(hits)
    nil
  else
    first(hits)
  end
end

def entry_id(e)
  "#{kind_of(e)}/#{name_of(e)}"
end

# The entries whose refusal list (same position in `marks`) is empty.
def unrefused(es, marks)
  map(
    fn(i) nth(i, es) end,
    filter(fn(i) is_empty(nth(i, marks)) end, range(0, size(es)))
  )
end

# A name is declared once: every later declaration of it is refused.
def duplicate_refusals(es)
  ids = map(fn(e) entry_id(e) end, es)
  map(
    fn(i)
      refused_if(
        index_of(ids, nth(i, ids)) < i,
        :duplicate,
        nth(i, es),
        "declared twice; the first stands"
      )
    end,
    range(0, size(es))
  )
end

def fields_of(kind)
  if kind == :mood
    mood_table()
  elsif kind == :tone
    tone_table()
  else
    nil
  end
end

def overlay(table, base, fields)
  reduce(
    fn(acc, f)
      if get(fields, get(f, :key)) == nil
        acc
      else
        assoc(acc, get(f, :key), get(fields, get(f, :key)))
      end
    end,
    base,
    table
  )
end

def tune_refusals(t, es)
  table = fields_of(get(t, :target))
  hits = filter(
    fn(e) kind_of(e) == get(t, :target) && name_of(e) == get(t, :of) end,
    es
  )
  if table == nil
    [refuse_entry(:invalid, t, "only a mood or a tone is tuned")]
  elsif is_empty(hits)
    [refuse_entry(:unknown_entry, t, "nothing declared to tune")]
  else
    whys_to_refusals(t, record_whys(table, value_of(t)))
  end
end

# Every tune laid onto its entry, in order; each tune is checked first.
def apply_tunes(es)
  tunes = filter(fn(e) kind_of(e) == :tune end, es)
  base = filter(fn(e) kind_of(e) != :tune end, es)
  bad = map(fn(t) tune_refusals(t, base) end, tunes)
  good = unrefused(tunes, bad)
  {
    entries: map(fn(e) tuned(e, good) end, base),
    refusals: flat_map(fn(r) r end, bad)
  }
end

def tuned(e, tunes)
  reduce(
    fn(acc, t)
      if kind_of(acc) == get(t, :target) && name_of(acc) == get(t, :of)
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
  map(fn(e) name_of(e) end, filter(fn(e) kind_of(e) == kind end, es))
end

def has_kind?(es, kind)
  !is_empty(names_of_kind(es, kind))
end

def active?(m)
  kind_of(m) == :mood && get(value_of(m), :enable) != false
end

def phone?(m)
  active?(m) && get(value_of(m), :phone_button) != false
end

def label_of(m)
  l = get(value_of(m), :label)
  if l == nil
    name_of(m)
  else
    l
  end
end

def missing(names, known)
  filter(fn(n) !contains(known, n) end, names)
end

def role_lights(es, role)
  hits = filter(fn(e) kind_of(e) == :light_role && name_of(e) == role end, es)
  if is_empty(hits)
    []
  else
    value_of(first(hits))
  end
end

# What one standing mood still lacks among the entries that stand with it.
def mood_needs(m, es)
  v = value_of(m)
  s = get(v, :sound)
  l = get(v, :lights)
  active = filter(fn(e) kind_of(e) == :mood && active?(e) end, es)
  targets = map(fn(h) get(h, :mood) end, get(v, :then) || [])
  lost = missing(targets, names_of_kind(active, :mood))
  phones = filter(fn(p) phone?(p) end, es)
  role = get(l || {}, :role)
  tone_name = get(s || {}, :tone)
  deaf = missing(get(s || {}, :speakers) || [], names_of_kind(es, :speaker))
  flat_map(
    fn(g) g end,
    [
      refused_if(
        s != nil && !contains(names_of_kind(es, :tone), tone_name),
        :unknown_tone,
        m,
        "no tone #{tone_name} stands"
      ),
      refused_if(
        !is_empty(deaf),
        :unknown_speaker,
        m,
        "no speaker #{join(deaf, ", ")} stands"
      ),
      refused_if(
        s != nil && !has_kind?(es, :media_base_url),
        :no_media_base_url,
        m,
        "it plays a tone, and no media_base_url stands"
      ),
      refused_if(
        s != nil && !has_kind?(es, :speaker),
        :no_speakers,
        m,
        "it plays a tone, and no speaker stands"
      ),
      refused_if(
        !is_empty(lost),
        :unknown_mood,
        m,
        "it hands over to #{join(lost, ", ")}, not a standing mood"
      ),
      refused_if(
        role != nil && is_empty(role_lights(es, role)),
        :unknown_role,
        m,
        "no light role #{role} with lights stands"
      ),
      refused_if(
        phone?(m) &&
          index_of(map(fn(p) label_of(p) end, phones), label_of(m)) <
            index_of(map(fn(p) name_of(p) end, phones), name_of(m)),
        :duplicate_label,
        m,
        "an earlier phone button already says #{label_of(m)}"
      )
    ]
  )
end

# [the refusal] when `fault` holds, else nothing.
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

# Refuse whatever lacks what it names, and again over what is left, until
# nothing more falls: a mood handing over to a refused mood falls with it.
def settle(standing, refused)
  fresh = map(fn(e) needs(e, standing) end, standing)
  falls = flat_map(fn(r) r end, fresh)
  if is_empty(falls)
    {accepted: standing, refusals: refused}
  else
    settle(unrefused(standing, fresh), append(refused, falls))
  end
end

# The home judged: `accepted`, the entries that stand (tunes applied), and
# `refusals`, one or more per entry that does not, each naming it. A bad
# entry is refused alone; its siblings stand.
def judge(entries)
  t = apply_tunes(flat(entries))
  es = get(t, :entries)
  own = map(fn(e) local_refusals(e) end, es)
  dups = duplicate_refusals(es)
  marks = map(fn(i) append(nth(i, own), nth(i, dups)) end, range(0, size(es)))
  first_pass = unrefused(es, marks)
  settled = settle(
    first_pass,
    append(get(t, :refusals), flat_map(fn(r) r end, marks))
  )
  site_missing = if has_kind?(get(settled, :accepted), :site)
    []
  else
    [refusal(:no_site, "a home needs a site")]
  end
  {
    accepted: get(settled, :accepted),
    refusals: append(get(settled, :refusals), site_missing)
  }
end

def accepted(entries)
  get(judge(entries), :accepted)
end

def refusals(entries)
  get(judge(entries), :refusals)
end

# ── the projection: pleme.lareira's attribute set ──────────────────────────

def of_kind(es, kind)
  filter(fn(e) kind_of(e) == kind end, es)
end

# A role-addressed mood's lights become the role's lights.
def resolved(m, es)
  l = get(value_of(m), :lights)
  if l == nil || get(l, :role) == nil
    value_of(m)
  else
    assoc(value_of(m), :lights, assoc(l, :only, role_lights(es, get(l, :role))))
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
  assoc(acc, nth(1, row), project(nth(2, row), settings))
end

# A key of the projection: where it goes, the kind of entry it gathers, and
# how those entries render. A kind with no standing entry leaves the key out,
# so the module's default holds.
def slot(json, kind, render)
  [json, kind, render]
end

def filled(acc, es, slots)
  reduce(fn(m, s) slot_into(m, s, of_kind(es, nth(1, s))) end, acc, slots)
end

def slot_into(acc, s, hits)
  if is_empty(hits)
    acc
  else
    assoc(acc, first(s), applied(last(s), hits))
  end
end

def single(render)
  fn(hits) render(first(hits)) end
end

def by_name(render)
  fn(hits) reduce(fn(m, e) assoc(m, name_of(e), render(e)) end, {}, hits) end
end

def home_assistant(es)
  filled(
    {},
    es,
    [
      slot("recorder", :recorder, single(fn(e) value_of(e) end)),
      slot("mediaBaseUrl", :media_base_url, single(fn(e) value_of(e) end)),
      slot(
        "integrations",
        :integration,
        fn(hits) map(fn(e) name_of(e) end, hits) end
      ),
      slot("speakers", :speaker, by_name(fn(e) value_of(e) end)),
      slot("lightRoles", :light_role, by_name(fn(e) value_of(e) end)),
      slot(
        "tones",
        :tone,
        by_name(fn(e) project(tone_table(), value_of(e)) end)
      ),
      slot(
        "moods",
        :mood,
        by_name(fn(e) project(mood_table(), resolved(e, es)) end)
      )
    ]
  )
end

# The attribute set pleme.lareira takes, from the entries that stand:
# `pleme.lareira = lib.importJSON ./home.json`.
def lareira(entries)
  es = accepted(entries)
  out = filled(
    {"enable" => true},
    es,
    [
      slot("delivery", :delivery, single(fn(e) value_of(e) end)),
      slot("exposure", :exposure, single(fn(e) value_of(e) end)),
      slot("secretsSource", :secrets_source, single(fn(e) value_of(e) end)),
      slot("site", :site, single(fn(e) project(site_table(), value_of(e)) end)),
      slot("components", :component, fn(hits) component_json(hits) end)
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
    integrations(["default_config", "met"]),
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
  json_get(
    json_get(json_get(home_doc(entries), "homeAssistant"), "moods"),
    name
  )
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
  assert json_stringify(lareira(example_home())) == to_json(example_home())
  relax = json_stringify(
    project(
      mood_table(),
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
  h = example_home()
  assert refusals(h) == []
  assert accepted(accepted(h)) == accepted(h)
  assert to_json(accepted(h)) == to_json(h)
  assert size(accepted(h)) == 15
end

test "a role-addressed mood takes the role's lights, and hands over by name"
  glow = mood_doc(example_home(), "glow")
  assert json_get(json_get(glow, "lights"), "only") == ["light.hallway"]
  assert json_get(first(json_get(glow, "then")), "afterMinutes") == 5
  assert json_get(json_get(glow, "lights"), "role") == nil
end

test "a bad entry is refused alone, and what names it falls with it"
  h = append(
    example_home(),
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
    [
      :invalid,
      :invalid,
      :duplicate,
      :needs_radio,
      :invalid,
      :unknown_tone,
      :unknown_mood
    ]
  moods = json_get(json_get(home_doc(h), "homeAssistant"), "moods")
  assert json_get(moods, "warm") != nil
  assert json_get(moods, "hot") == nil
  assert json_get(moods, "rumble") == nil
  assert json_get(moods, "after") == nil
  assert json_get(moods, "relax") != nil
  assert json_get(
    json_get(
      json_get(json_get(home_doc(h), "homeAssistant"), "tones"),
      "hz432"
    ),
    "frequency"
  ) ==
    432
  assert json_get(json_get(home_doc(h), "components"), "zigbee2mqtt") == nil
  assert json_get(
    json_get(json_get(home_doc(h), "components"), "mosquitto"),
    "enable"
  ) ==
    true
end

test "a tune configures a set's mood off without forking the set"
  h = append(
    example_home(),
    [
      tune(:mood, "relax", {enable: false}),
      tune(:mood, "absent", {enable: false})
    ]
  )
  assert kinds(refusals(h)) == [:unknown_entry]
  assert json_get(mood_doc(h, "relax"), "enable") == false
  assert json_get(mood_doc(h, "relax"), "label") == "Relax"
  assert kinds(
    refusals(
      append(
        example_home(),
        [
          tune(:mood, "relax", {enable: false}),
          mood("x", {label: "X", then: [hand_over(1, "relax")]})
        ]
      )
    )
  ) ==
    [:unknown_mood]
end

test "a mood plays only where a base url and speakers stand"
  bare = [
    site("natal"),
    tone("hz432", {frequency: 432}),
    mood("m", {sound: sound("hz432", 0.3)})
  ]
  assert kinds(refusals(bare)) == [:no_media_base_url, :no_speakers]
  assert kinds(
    refusals(append(bare, [media_base_url("ftp://x"), speaker("k", "light.k")]))
  ) ==
    [:invalid, :invalid, :no_media_base_url, :no_speakers]
  assert kinds(
    refusals(
      append(
        bare,
        [media_base_url("http://x:8123"), speaker("k", "media_player.k")]
      )
    )
  ) ==
    []
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
  ) ==
    [:invalid]
end
