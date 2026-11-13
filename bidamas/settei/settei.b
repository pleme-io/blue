@moduledoc """
settei (設定) — configuration, blue's shikumi: a record of defaults grouped by concern, resolved by read(app, defaults) from the defaults, then ~/.config/<app>/<app>.yaml (or <APP>_CONFIG), then <APP>_<GROUP>__<KEY> in the environment, each value typed by its default and a wrong type refused. The resolved record is read by dotted path; a misspelt path raises and names the fields that exist.

A program's core model is a record of knobs (`knob(default, annotations)`): type, default, bounds, doc, unit, secret, since, deprecated and the layers that may set it. From that one model settei renders the layering (`settle`: defaults, then file, then environment, then flags, each bad value refused for its key alone), the command line (`cli_spec`, `line`, `command`: flags, help, completion, `--explain KEY`), the settings table (`table`) and the check that code reads no knob the model lacks (`unmodelled`). Design: docs/CORE-MODEL.md.

    resolve("app", {"guard" => {"branch" => "main"}}, nil, env_of({"APP_GUARD__BRANCH" => "next"})).guard.branch #=> "next"
    settle("app", {port: knob(80, {min: 1})}, nil, env_of({"APP_PORT" => "8080"}))[:config] #=> {port: 8080}
"""

use("deeta")
use("hikisuu")
use("jisho")
use("kousei")
use("kyohi", %i[enforce exit_status refusal])
use("moji", %i[env_key pad_right])
use("retsu", %i[first index_of rest size take_while])

def env_prefix(app)
  env_key([app, ""])
end

def env_name(app, path)
  "#{env_prefix(app)}#{upcase(join(path, "__"))}"
end

def kind_of(v)
  if v == true or v == false
    :bool
  elsif integer?(v)
    :int
  elsif float?(v)
    :float
  elsif string?(v)
    :text
  elsif v != nil and map?(v)
    :map
  else
    :other
  end
end

def same_kind?(default, v)
  kind_of(default) == kind_of(v) or
    kind_of(default) == :float and kind_of(v) == :int
end

def dotted(path)
  join(path, ".")
end

def coerce(default, text)
  coerce_as(kind_of(default), text)
end

@doc """
coerce_as: environment text read as a knob type, nil when it does not read.

    coerce_as(:int, "42") #=> 42
    coerce_as(:bool, "maybe") #=> nil
"""
def coerce_as(k, text)
  if k == :text
    text
  elsif k == :int
    to_int(text)
  elsif k == :float
    if to_int(text) != nil
      to_float(text)
    elsif contains?(text, ".")
      to_float(text)
    end
  elsif k == :bool
    if member?(downcase(text), %w[true 1 yes on])
      true
    elsif member?(downcase(text), %w[false 0 no off])
      false
    end
  end
end

def file_tier(defaults, doc, path)
  reduce(
    fn(acc, e)
      key = first(e)
      v = second(e)
      at = append(path, [key])
      d = get(defaults, key)
      if d.nil?
        [
          first(acc),
          append(
            second(acc),
            [
              refusal(
                :unknown_key,
                "#{dotted(at)} is not a setting; the settings are #{join(map((x) -> first(x), map_entries(defaults)), ", ")}"
              )
            ]
          )
        ]
      elsif kind_of(d) == :map and kind_of(v) == :map
        inner = file_tier(d, v, at)
        [
          assoc(first(acc), key, first(inner)),
          append(second(acc), second(inner))
        ]
      elsif same_kind?(d, v)
        [assoc(first(acc), key, v), second(acc)]
      else
        [
          first(acc),
          append(
            second(acc),
            [
              refusal(
                :wrong_type,
                "#{dotted(at)} must be #{to_s(kind_of(d))}, got #{to_s(kind_of(v))}"
              )
            ]
          )
        ]
      end
    end,
    [defaults, []],
    map_entries(doc)
  )
end

def env_tier(app, defaults, lookup, path)
  reduce(
    fn(acc, e)
      key = first(e)
      d = second(e)
      at = append(path, [key])
      if kind_of(d) == :map
        inner = env_tier(app, d, lookup, at)
        [
          assoc(first(acc), key, first(inner)),
          append(second(acc), second(inner))
        ]
      else
        name = env_name(app, at)
        text = lookup(name)
        if text.nil?
          acc
        else
          v = coerce(d, text)
          if v.nil?
            [
              first(acc),
              append(
                second(acc),
                [
                  refusal(
                    :wrong_type,
                    "#{name}=#{text} is not a #{to_s(kind_of(d))} (#{dotted(at)})"
                  )
                ]
              )
            ]
          else
            [assoc(first(acc), key, v), second(acc)]
          end
        end
      end
    end,
    [defaults, []],
    map_entries(defaults)
  )
end

def resolve(app, defaults, doc, lookup)
  from_file = if doc.nil?
    [defaults, []]
  elsif kind_of(doc) == :map
    file_tier(defaults, doc, [])
  else
    [defaults, [refusal(:not_a_map, "the config file must hold one object")]]
  end
  from_env = env_tier(app, first(from_file), lookup, [])
  enforce(
    [from_file, from_env],
    [(tiers) -> append(second(first(tiers)), second(second(tiers)))],
    {kind: :first}
  )
  first(from_env)
end

@doc """
file: where the config file of an app tier lives.
"""
def file(app, tier)
  if tier == :explicit
    getenv("#{env_prefix(app)}CONFIG")
  elsif tier == :xdg
    xdg = getenv("XDG_CONFIG_HOME")
    if xdg.nil?
      nil
    else
      "#{xdg}/#{app}/#{app}.yaml"
    end
  elsif tier == :home
    home = getenv("HOME")
    if home.nil?
      nil
    else
      "#{home}/.config/#{app}/#{app}.yaml"
    end
  else
    raise(:unknown_tier, "#{to_s(tier)} is not a tier")
  end
end

def discovered_path(app)
  find(
    map((t) -> file(app, t), %i[explicit xdg home]),
    (p) -> p != nil and is_file?(p)
  )
end

def prescribed(app, path)
  if path.nil?
    raise(
      :no_defaults,
      "#{env_prefix(app)}DEFAULTS names no file of prescribed settings"
    )
  end
  json_read(read_file(path))
end

@doc """
defaults: the built-in default record of an app.
"""
def defaults(app)
  prescribed(app, getenv("#{env_prefix(app)}DEFAULTS"))
end

def formats()
  {"yaml" => :yaml, "json" => :json}
end

def file_format(app, opts)
  chosen = if opts.nil? or opts[:format].nil?
    getenv("#{env_prefix(app)}CONFIG_FORMAT")
  else
    opts[:format]
  end
  format = if chosen.nil?
    :yaml
  else
    get(formats, to_s(chosen))
  end
  if format.nil?
    raise(
      :bad_option,
      "#{to_s(chosen)} is not a config file format; the formats are yaml and json"
    )
  end
  format
end

def file_doc(path, format)
  deeta::parse(read_file(path), format)
end

@doc """
read: resolve defaults, then file, then environment into one record. opts[:aliases] maps a setting's environment name to the older name that still sets it.
"""
def read(app, defaults, opts?)
  path = discovered_path(app)
  doc = if path.nil?
    nil
  else
    file_doc(path, file_format(app, opts))
  end
  aliases = if opts.nil? or opts[:aliases].nil?
    {}
  else
    opts[:aliases]
  end
  resolve(app, defaults, doc, aliased((name) -> getenv(name), aliases))
end

@doc """
aliased: a lookup that reads a setting's environment name, then the older name aliases gives it, so a renamed setting keeps its old name working.

    aliased(env_of({"APP_WAIT_S" => "5"}), {"APP_WAIT__SECONDS" => "APP_WAIT_S"})("APP_WAIT__SECONDS") #=> "5"
"""
def aliased(lookup, aliases)
  fn(name)
    v = lookup(name)
    old = get(aliases, name)
    if v.nil? and old != nil
      lookup(old)
    else
      v
    end
  end
end

def load(app, opts?)
  read(app, defaults(app), opts)
end

@doc """
merge: combine two records, b winning, deep for maps.

    merge({}, {}) #=> {}
"""
def merge(a, b)
  reduce(
    fn(acc, e)
      key = first(e)
      v = second(e)
      cur = get(acc, key)
      if kind_of(cur) == :map and kind_of(v) == :map
        assoc(acc, key, merge(cur, v))
      else
        assoc(acc, key, v)
      end
    end,
    a,
    map_entries(b)
  )
end

def lookup_path(config, parts)
  reduce(
    fn(acc, k)
      if acc.nil? or kind_of(acc) != :map
        nil
      else
        get(acc, k)
      end
    end,
    config,
    parts
  )
end

@doc """
has?: whether a setting is defined.
"""
def has?(config, path)
  lookup_path(config, split(path, ".")) != nil
end

@doc """
need: one setting by dotted path, raising not_found.
"""
def need(config, path)
  v = lookup_path(config, split(path, "."))
  if v.nil?
    raise(:not_found, "no setting #{path}")
  end
  v
end

def serving?()
  getenv("BLUE_SERVICE") != nil
end

def current()
  load(env_required("BLUE_SERVICE"))
end

def flag(settings, name)
  flags = settings["flags"]
  v = if flags.nil?
    nil
  else
    get(flags, name)
  end
  if v.nil?
    raise(:unknown_flag, "#{name} is not a declared flag")
  end
  v == true
end

def setting(settings, name)
  v = get(settings, name)
  if v.nil?
    raise(:unknown_setting, "#{name} is not a declared setting")
  end
  v
end

def no_env(_name)
  nil
end

def env_of(pairs)
  (name) -> get(pairs, name)
end

@doc """
knob_types: the types a knob may hold.

    knob_types #=> %i[bool int float text]
"""
def knob_types()
  %i[bool int float text]
end

@doc """
layers: the layers above the defaults, lowest first.

    layers #=> %i[file env flag]
"""
def layers()
  %i[file env flag]
end

@doc """
number_check: the kousei check that a bound is a number.

    kousei::field(:min, number_check)[:check]("x") #=> "x is not a number"
"""
def number_check()
  (v) -> kousei::verdict(integer?(v) or float?(v), "#{v} is not a number")
end

@doc """
annotation_table: the kousei field table every knob's annotations are judged by.

    kousei::record_whys(annotation_table, {colour: 1}) #=> ["colour is not a field"]
"""
def annotation_table()
  [
    kousei::field(:type, kousei::one_of(knob_types)),
    kousei::field(:doc, kousei::text),
    kousei::field(:min, number_check),
    kousei::field(:max, number_check),
    kousei::field(
      :choices,
      (v) -> kousei::verdict(list?(v), "#{v} is not a list")
    ),
    kousei::field(:unit, kousei::text),
    kousei::field(:secret, kousei::flag),
    kousei::field(:since, kousei::text),
    kousei::field(:deprecated, kousei::text),
    kousei::field(:set_by, kousei::list_of(kousei::one_of(layers))),
    kousei::field(:renamed, kousei::list_of(kousei::text)),
    kousei::field(:value_name, kousei::text),
    kousei::field(:required, kousei::flag),
    kousei::field(:immutable, kousei::flag),
    kousei::field(
      :computed,
      (v) -> kousei::verdict(procedure?(v), "#{v} is not a function")
    )
  ]
end

@doc """
fits?: whether a value is of a knob type; a whole number fits a float.

    fits?(:float, 2) #=> true
    fits?(:int, "2") #=> false
"""
def fits?(t, v)
  k = kind_of(v)
  k == t or t == :float and k == :int
end

@doc """
range_text: the legal values of a knob as a reader says them.

    range_text(knob(6, {min: 0})) #=> "0 or more"
    range_text(knob("a", {choices: %w[a b]})) #=> "one of a, b"
"""
def range_text(k)
  lo = k[:min]
  hi = k[:max]
  if k[:choices] != nil
    "one of #{join(map(to_s, k[:choices]), ", ")}"
  elsif lo != nil and hi != nil
    "#{lo}..#{hi}"
  elsif lo != nil
    "#{lo} or more"
  elsif hi != nil
    "#{hi} or less"
  else
    "any #{to_s(k[:type])}"
  end
end

@doc """
why_not: why a value is not legal for a knob, or nil when it is.

    why_not(knob(6, {min: 0}), -1) #=> "must be 0 or more, got -1"
    why_not(knob(6, {min: 0}), 2) #=> nil
"""
def why_not(k, v)
  bounded = member?(k[:type], %i[int float]) and
    (k[:min] != nil or k[:max] != nil)
  if not fits?(k[:type], v)
    "must be #{to_s(k[:type])}, got #{to_s(v)}"
  elsif bounded and
      (k[:min] != nil and v < k[:min] or k[:max] != nil and v > k[:max])
    if k[:min] != nil and k[:max] != nil
      "must be in #{range_text(k)}, got #{to_s(v)}"
    else
      "must be #{range_text(k)}, got #{to_s(v)}"
    end
  elsif k[:choices] != nil and not member?(v, k[:choices])
    "must be #{range_text(k)}, got #{to_s(v)}"
  end
end

@doc """
knob_whys: why a knob's annotations do not agree with each other or with its default.

    knob_whys({type: :text, min: 0, max: nil, choices: nil, default: "a"}) #=> ["min and max bound a number, not text"]
"""
def knob_whys(k)
  numeric = member?(k[:type], %i[int float])
  bad_choice = find(k[:choices] or [], (c) -> not fits?(k[:type], c))
  filter(
    (w) -> w != nil,
    [
      kousei::verdict(
        numeric or k[:min].nil? and k[:max].nil?,
        "min and max bound a number, not #{to_s(k[:type])}"
      ),
      kousei::verdict(
        k[:min].nil? or k[:max].nil? or k[:min] <= k[:max],
        "min #{k[:min]} is above max #{k[:max]}"
      ),
      kousei::verdict(
        bad_choice.nil?,
        "choice #{to_s(bad_choice)} is not #{to_s(k[:type])}"
      ),
      if k[:default] != nil and why_not(k, k[:default]) != nil
        "the default #{why_not(k, k[:default])}"
      end
    ]
  )
end

@doc """
knob: one setting of a core model: its default and its annotations (type, doc, min, max, choices, unit, secret, since, deprecated, set_by). The type is the default's unless type: names it; set_by lists the layers that may set it, every layer when absent. A bad annotation raises :bad_option, naming it.

    knob(6, {min: 0, unit: "hours"})[:type] #=> :int
"""
def knob(default, ann?)
  a = ann or {}
  table_whys = kousei::record_whys(annotation_table, a)
  t = a[:type] or kind_of(default)
  shape_why = if a[:required] == true and default != nil
    "a required knob has no default"
  elsif default.nil? and a[:type].nil?
    "a knob with no default names its type"
  elsif not member?(t, knob_types)
    "a knob holds bool, int, float or text, got #{to_s(default)}"
  end
  if table_whys != [] or shape_why != nil
    raise(
      :bad_option,
      "knob: #{join(filter((w) -> w != nil, append(table_whys, [shape_why])), "; ")}"
    )
  end
  k = {
    knob: true,
    default:,
    type: t,
    doc: a[:doc] or "",
    min: a[:min],
    max: a[:max],
    choices: a[:choices],
    unit: a[:unit],
    secret: a[:secret] == true,
    since: a[:since],
    deprecated: a[:deprecated],
    set_by: if a[:computed] != nil
      []
    else
      a[:set_by] or layers
    end,
    renamed: a[:renamed] or [],
    required: a[:required] == true,
    immutable: a[:immutable] == true,
    computed: a[:computed],
    value_name: a[:value_name]
  }
  whys = knob_whys(k)
  if whys != []
    raise(:bad_option, "knob: #{join(whys, "; ")}")
  end
  k
end

@doc """
knob?: whether a value of a core model is a knob rather than a group.

    knob?(knob(1)) #=> true
"""
def knob?(v)
  map?(v) and v[:knob] == true and member?(v[:type], knob_types)
end

@doc """
dotted_key: a knob path as the dotted key people write.

    dotted_key([:net, :port]) #=> "net.port"
"""
def dotted_key(path)
  join(map(to_s, path), ".")
end

@doc """
knobs: every knob of a core model with its path, groups walked in key order.

    knobs({a: knob(1)}) #=> [{path: [:a], knob: knob(1)}]
"""
def knobs(model, path?)
  at = path or []
  reduce(
    fn(acc, e)
      p = append(at, [first(e)])
      v = second(e)
      if knob?(v)
        append(acc, [{path: p, knob: v}])
      elsif map?(v)
        append(acc, knobs(v, p))
      else
        raise(
          :bad_option,
          "#{dotted_key(p)} is neither a knob nor a group of knobs"
        )
      end
    end,
    [],
    map_entries(model)
  )
end

@doc """
put_in: a record with the value at a path set, groups made as needed.

    put_in({}, [:net, :port], 1) #=> {net: {port: 1}}
"""
def put_in(rec, path, v)
  k = first(path)
  if rest(path) == []
    assoc(rec, k, v)
  else
    assoc(rec, k, put_in(get(rec, k) or {}, rest(path), v))
  end
end

@doc """
defaults_of: the plain record of a core model's defaults, the shape read and resolve take.

    defaults_of({a: knob(1), g: {b: knob("x")}}) #=> {a: 1, g: {b: "x"}}
"""
def defaults_of(model)
  reduce(
    (acc, r) -> put_in(acc, r[:path], r[:knob][:default]),
    {},
    knobs(model)
  )
end

@doc """
text_get: the value of a map under a key compared as text, so a file's "port" finds a model's :port.

    text_get({port: 1}, "port") #=> 1
"""
def text_get(m, key)
  hit = find(map_entries(m), (e) -> to_s(first(e)) == to_s(key))
  if hit.nil?
    nil
  else
    second(hit)
  end
end

@doc """
doc_at: the value at a knob path in a record, nil when any step is absent.

    doc_at({"net" => {"port" => 9}}, [:net, :port]) #=> 9
"""
def doc_at(doc, path)
  reduce(
    fn(acc, k)
      if acc.nil? or not map?(acc)
        nil
      else
        text_get(acc, k)
      end
    end,
    doc,
    path
  )
end

@doc """
fault: one refusal of settle, a kyohi refusal scoped to the key and the layer that gave the bad value.

    fault("port", :env, refusal(:wrong_type, "x"))[:kind] #=> :wrong_type
"""
def fault(key, layer, refused)
  {key:, layer:, kind: kyohi::kind(refused), why: kyohi::why(refused)}
end

@doc """
strays: a fault for each key of a config file the model lacks, and for a group given as a plain value.

    strays({port: knob(1)}, {"prot" => 2}, [])[0][:kind] #=> :unknown_key
"""
def strays(model, doc, path)
  reduce(
    fn(acc, e)
      key = first(e)
      at = append(path, [key])
      m = text_get(model, key)
      if m.nil?
        append(
          acc,
          [
            fault(
              dotted_key(at),
              :file,
              refusal(
                :unknown_key,
                "#{dotted_key(at)} is not a setting; the settings here are #{join(map((x) -> to_s(first(x)), map_entries(model)), ", ")}"
              )
            )
          ]
        )
      elsif knob?(m) or second(e).nil?
        acc
      elsif map?(second(e))
        append(acc, strays(m, second(e), at))
      else
        append(
          acc,
          [
            fault(
              dotted_key(at),
              :file,
              refusal(
                :wrong_type,
                "#{dotted_key(at)} is a group of settings and takes an object"
              )
            )
          ]
        )
      end
    end,
    [],
    map_entries(doc)
  )
end

@doc """
offer_of: what one layer offers for one knob, the value and where it came from, or nil when the layer says nothing.

    offer_of("app", :env, [:port], knob(1), nil, env_of({"APP_PORT" => "2"}), {}) #=> {value: 2, from: "APP_PORT"}
"""
def offer_of(app, layer, p, k, doc, lookup, given)
  if layer == :file
    v = doc_at(doc, p)
    if v != nil
      {value: v, from: "the file"}
    end
  elsif layer == :env
    names = append(
      [env_name(app, map(to_s, p))],
      map((old) -> env_name(app, split(old, ".")), k[:renamed])
    )
    name = find(names, (n) -> lookup(n) != nil)
    text = if name != nil
      lookup(name)
    end
    if text != nil
      v = coerce_as(k[:type], text)
      if v.nil?
        {value: text, from: name}
      else
        {value: v, from: name}
      end
    end
  else
    v = get(given, dotted_key(p))
    if v != nil
      {value: v, from: flag_word(p)}
    end
  end
end

@doc """
settle_knob: one knob taken through every layer: each legal offer sets it, each bad one is refused for this key alone.

    settle_knob("a", {config: {p: 1}, sources: {}, refusals: [], notices: []}, {path: [:p], knob: knob(1)}, nil, no_env, {})[:sources] #=> {"p" => :default}
"""
def settle_knob(app, acc, row, doc, lookup, given)
  p = row[:path]
  k = row[:knob]
  key = dotted_key(p)
  start = assoc(acc, :sources, assoc(acc[:sources], key, :default))
  reduce(
    fn(s, layer)
      o = offer_of(app, layer, p, k, doc, lookup, given)
      if o.nil?
        s
      elsif not member?(layer, k[:set_by])
        jisho::update(
          s,
          :refusals,
          fn(rs)
            append(
              rs,
              [
                fault(
                  key,
                  layer,
                  refusal(
                    :not_settable,
                    if k[:computed] != nil
                      "#{key} is computed from the other settings; no layer sets it"
                    else
                      "#{key} may not be set by #{to_s(layer)}; it is set by #{join(map(to_s, k[:set_by]), ", ")}"
                    end
                  )
                )
              ]
            )
          end
        )
      else
        why = why_not(k, o[:value])
        if why != nil
          kept = doc_at(s[:config], p)
          shown = if k[:secret]
            "<secret>"
          else
            to_s(o[:value])
          end
          why_text = replace(why, "got #{to_s(o[:value])}", "got #{shown}")
          kind = if fits?(k[:type], o[:value])
            :out_of_range
          else
            :wrong_type
          end
          jisho::update(
            s,
            :refusals,
            fn(rs)
              append(
                rs,
                [
                  fault(
                    key,
                    layer,
                    refusal(
                      kind,
                      "#{key} #{why_text} from #{o[:from]}; kept #{shown_value(k, kept)}"
                    )
                  )
                ]
              )
            end
          )
        else
          settled = assoc(
            assoc(s, :config, put_in(s[:config], p, o[:value])),
            :sources,
            assoc(s[:sources], key, layer)
          )
          if k[:deprecated] != nil and
              not member?(
                "#{key} is deprecated: #{k[:deprecated]}",
                s[:notices]
              )
            jisho::update(
              settled,
              :notices,
              (ns) -> append(ns, ["#{key} is deprecated: #{k[:deprecated]}"])
            )
          else
            settled
          end
        end
      end
    end,
    start,
    layers
  )
end

@doc """
shown_value: a knob's value as explain, docs and refusals print it: <secret> for a secret, unset for nil.

    shown_value(knob("", {secret: true}), "t0k3n") #=> "<secret>"
"""
def shown_value(k, v)
  if k[:secret]
    "<secret>"
  elsif v.nil?
    "unset"
  else
    to_s(v)
  end
end

@doc """
settle: a core model resolved through its layers, defaults, then the file, then the environment, then flags, merged per key. A bad value is refused for its key alone (the key, the layer, the range, the value kept) and every other key still loads. Returns config, sources (dotted key to layer), refusals and notices.

    settle("app", {port: knob(80, {min: 1})}, nil, no_env, {"port" => 0})[:config] #=> {port: 80}
"""
def settle(app, model, doc, lookup, given?)
  flags = given or {}
  base = {config: defaults_of(model), sources: {}, refusals: [], notices: []}
  read_doc = if doc != nil and map?(doc)
    doc
  end
  moved = renames(model, read_doc)
  start = if doc.nil?
    base
  elsif read_doc.nil?
    assoc(
      base,
      :refusals,
      [
        fault(
          "",
          :file,
          refusal(:not_a_map, "the config file must hold one object")
        )
      ]
    )
  else
    assoc(base, :refusals, strays(model, moved[:doc], []))
  end
  layered = reduce(
    (acc, row) -> settle_knob(app, acc, row, moved[:doc], lookup, flags),
    assoc(start, :notices, moved[:notices]),
    knobs(model)
  )
  derived(app, model, layered)
end

@doc """
renames: a config file with each key a knob was renamed from moved to the knob's key, and a notice for each move; the new key wins when both are written.

    renames({w: knob(0, {renamed: ["w_s"]})}, {"w_s" => 5})[:doc] #=> {w: 5}
"""
def renames(model, doc)
  if doc.nil?
    {doc: nil, notices: []}
  else
    reduce(
      fn(acc, r)
        reduce(
          fn(a, old)
            parts = split(old, ".")
            v = doc_at(a[:doc], parts)
            if v.nil?
              a
            else
              stripped = drop_at(a[:doc], parts)
              placed = if doc_at(stripped, r[:path]).nil?
                put_in(stripped, r[:path], v)
              else
                stripped
              end
              {
                doc: placed,
                notices: append(
                  a[:notices],
                  ["#{old} is now #{dotted_key(r[:path])}"]
                )
              }
            end
          end,
          acc,
          r[:knob][:renamed]
        )
      end,
      {doc:, notices: []},
      knobs(model)
    )
  end
end

@doc """
drop_at: a record without the value at a path whose steps match keys as text.

    drop_at({"a" => {"b" => 1, "c" => 2}}, ["a", "b"]) #=> {"a" => {"c" => 2}}
"""
def drop_at(rec, path)
  hit = find(map_entries(rec), (e) -> to_s(first(e)) == to_s(first(path)))
  if hit.nil?
    rec
  elsif rest(path) == []
    dissoc(rec, first(hit))
  elsif map?(second(hit))
    assoc(rec, first(hit), drop_at(second(hit), rest(path)))
  else
    rec
  end
end

@doc """
derived: a settled record with each required knob no layer set refused alone, and each computed knob derived from the rest.

    derived("a", {}, {config: {}, sources: {}, refusals: [], notices: []})[:refusals] #=> []
"""
def derived(app, model, s)
  reduce(
    fn(acc, r)
      k = r[:knob]
      key = dotted_key(r[:path])
      if k[:computed] != nil
        assoc(
          assoc(
            acc,
            :config,
            put_in(acc[:config], r[:path], k[:computed](acc[:config]))
          ),
          :sources,
          assoc(acc[:sources], key, :computed)
        )
      elsif k[:required] and doc_at(acc[:config], r[:path]).nil?
        where = filter(
          (w) -> w != nil,
          [
            if member?(:env, k[:set_by])
              env_name(app, map(to_s, r[:path]))
            end,
            if by_flag?(k)
              flag_word(r[:path])
            end
          ]
        )
        named = if member?(:file, k[:set_by])
          "#{join(where, ", ")} or the file"
        else
          join(where, " or ")
        end
        jisho::update(
          acc,
          :refusals,
          fn(rs)
            append(
              rs,
              [
                fault(
                  key,
                  :default,
                  refusal(
                    :missing,
                    "#{key} is required and no layer sets it (#{named})"
                  )
                )
              ]
            )
          end
        )
      else
        acc
      end
    end,
    s,
    knobs(model)
  )
end

@doc """
flag_word: the command-line spelling of a knob path, groups joined by a dash.

    flag_word([:net, :max_conns]) #=> "--net-max-conns"
"""
def flag_word(path)
  "--#{replace(join(map(to_s, path), "-"), "_", "-")}"
end

@doc """
flag_key: the key a knob's flag has in a hikisuu spec: the knob's own key at the top, its path joined by underscores inside a group.

    flag_key([:net, :port]) #=> "net_port"
    flag_key([:dry_run]) #=> :dry_run
"""
def flag_key(path)
  if rest(path) == []
    first(path)
  else
    join(map(to_s, path), "_")
  end
end

@doc """
flag_kind: the hikisuu kind of a knob's flag: a switch for bool, int for int, text otherwise.

    flag_kind(knob(false)) #=> :switch
"""
def flag_kind(k)
  if k[:type] == :bool
    :switch
  elsif k[:type] == :int
    :int
  else
    :text
  end
end

@doc """
by_flag?: whether a flag may set a knob.

    by_flag?(knob("", {set_by: [:file]})) #=> false
"""
def by_flag?(k)
  member?(:flag, k[:set_by])
end

@doc """
explain_flag: the --explain KEY flag every program with a core model has.

    explain_flag[:value] #=> "KEY"
"""
def explain_flag()
  {
    default: nil,
    kind: :text,
    value: "KEY",
    about: "show one setting: its value, the layer it came from, its default and its range"
  }
end

@doc """
knob_flags: the hikisuu flags of a model's knobs, each defaulting to its value in below, or to nil when below is :unset.

    knob_flags({port: knob(80, {min: 1})}, {port: 9})[:port][:default] #=> 9
"""
def knob_flags(model, below)
  reduce(
    fn(acc, r)
      k = r[:knob]
      shown = if below == :unset or k[:secret]
        nil
      else
        doc_at(below, r[:path])
      end
      flag = {default: shown, kind: flag_kind(k), about: k[:doc]}
      named = if k[:value_name] != nil
        assoc(flag, :value, k[:value_name])
      else
        flag
      end
      floored = if k[:type] == :int and k[:min] != nil
        assoc(named, :min, k[:min])
      else
        named
      end
      assoc(acc, flag_key(r[:path]), floored)
    end,
    {},
    filter((r) -> by_flag?(r[:knob]), knobs(model))
  )
end

@doc """
spec_with: a frame with its knob flags and --explain added, refusing a frame flag the model already renders.

    spec_with({port: knob(80)}, {name: "x"}, :unset)[:flags][:port][:default] #=> nil
"""
def spec_with(model, frame, below)
  own = frame[:flags] or {}
  rendered = knob_flags(model, below)
  clash = find(
    map(first, map_entries(rendered)),
    (k) -> get(own, k) != nil or to_s(k) == "explain"
  )
  if clash != nil or own[:explain] != nil
    raise(
      :bad_option,
      "flag #{flag_word([clash or :explain])} is the core model's; the frame does not declare it"
    )
  end
  assoc(frame, :flags, assoc(merge(own, rendered), :explain, explain_flag))
end

@doc """
cli_spec: the hikisuu spec of a program: its frame (name, about, commands, positionals) with a flag for each knob a flag may set, typed, floored and documented from the model, defaulting to the value below the flag layer, and --explain KEY.

    hikisuu::parse(["--port", "9"], cli_spec({port: knob(80)}, {name: "x"}))[:port] #=> 9
"""
def cli_spec(model, frame, below?)
  spec_with(model, frame, below or defaults_of(model))
end

@doc """
given_flags: the knob values a parsed line set, by dotted key; a flag left out is absent.

    given_flags({port: knob(80)}, {port: 9}) #=> {"port" => 9}
"""
def given_flags(model, parsed)
  reduce(
    fn(acc, r)
      v = get(parsed, flag_key(r[:path]))
      if v.nil?
        acc
      elsif r[:knob][:type] == :float
        assoc(acc, dotted_key(r[:path]), coerce_as(:float, v) or v)
      else
        assoc(acc, dotted_key(r[:path]), v)
      end
    end,
    {},
    filter((r) -> by_flag?(r[:knob]), knobs(model))
  )
end

@doc """
explain_of: the key a line asks to explain and the line without it, or nil when it asks none.

    explain_of(["--explain", "port", "go"]) #=> {key: "port", rest: ["go"]}
"""
def explain_of(args)
  before = take_while((a) -> a != "--", args)
  at = find(before, (a) -> a == "--explain" or starts_with?(a, "--explain="))
  if at.nil?
    nil
  elsif at == "--explain"
    i = index_of(before, at)
    if i + 1 < size(before)
      {key: before[i + 1], rest: append(take(i, before), drop(i + 2, args))}
    else
      {key: nil, rest: args}
    end
  else
    {key: second(hikisuu::split_flag(at)), rest: filter((a) -> a != at, args)}
  end
end

@doc """
source_text: the layer a value came from as explain says it: the env name or the flag when one set it.

    source_text("app", {path: [:port]}, :env) #=> "env APP_PORT"
"""
def source_text(app, r, layer)
  if layer == :env
    "env #{env_name(app, map(to_s, r[:path]))}"
  elsif layer == :flag
    "flag #{flag_word(r[:path])}"
  else
    to_s(layer)
  end
end

@doc """
explain: one setting as a person reads it: its value, the layer it came from, its default, range, type, unit, doc, the layers that may set it, its environment name and flag, since and deprecated. A secret's value and default read <secret>; an unknown key raises :usage naming the settings.

    contains?(explain("app", {port: knob(80)}, settle("app", {port: knob(80)}, nil, no_env), "port"), "port = 80") #=> true
"""
def explain(app, model, settled, key)
  rows = knobs(model)
  r = find(rows, (x) -> dotted_key(x[:path]) == key)
  if r.nil?
    raise(
      :usage,
      "no setting #{key}; the settings are #{join(map((x) -> dotted_key(x[:path]), rows), ", ")}"
    )
  end
  k = r[:knob]
  facts = filter(
    (row) -> second(row) != nil,
    [
      ["source", source_text(app, r, get(settled[:sources], key))],
      ["default", shown_value(k, k[:default])],
      ["range", range_text(k)],
      ["type", to_s(k[:type])],
      ["unit", k[:unit]],
      ["doc", k[:doc]],
      ["set by", join(map(to_s, k[:set_by]), ", ")],
      ["env", env_name(app, map(to_s, r[:path]))],
      [
        "flag",
        if by_flag?(k)
          flag_word(r[:path])
        end
      ],
      ["since", k[:since]],
      ["deprecated", k[:deprecated]]
    ]
  )
  w = reduce((m, row) -> blue::max(m, size(chars(first(row)))), 0, facts)
  unlines(
    append(
      ["#{key} = #{shown_value(k, doc_at(settled[:config], r[:path]))}"],
      map((row) -> "  #{pad_right(first(row), w, " ")}  #{second(row)}", facts)
    )
  )
end

@doc """
usage: a usage refusal of a line: exit 64, the fault, the usage line and where help is.

    usage({name: "x"}, {name: "x"}, "bad")[:status] #=> 64
"""
def usage(frame, spec, text)
  {
    kind: :usage,
    status: exit_status(:usage),
    text: unlines(
      [
        "#{frame[:name]}: #{text}",
        hikisuu::usage_line(spec, nil),
        "try #{frame[:name]} --help"
      ]
    )
  }
end

@doc """
quietly_given: the knob flags a line sets, or none when the line does not parse, so explain still answers.

    quietly_given({port: knob(80)}, {name: "x"}, ["--nope"]) #=> {}
"""
def quietly_given(model, frame, args)
  given_flags(model, hikisuu::parse(args, spec_with(model, frame, :unset)))
rescue :usage
  {}
end

@doc """
run_opts: the record a program runs with: the parsed line without its knob flags and --explain, with the settled config laid over it.

    run_opts({port: knob(80)}, {name: "x"}, {port: 9, help: false, explain: nil}, {port: 9}) #=> {help: false, port: 9}
"""
def run_opts(model, _frame, parsed, config)
  bare = reduce(
    (acc, r) -> dissoc(acc, flag_key(r[:path])),
    dissoc(parsed, :explain),
    knobs(model)
  )
  reduce((acc, e) -> assoc(acc, first(e), second(e)), bare, map_entries(config))
end

@doc """
line: what one command line asks of a program with a core model, resolved through every layer: help, completion, explain, a usage refusal with exit 64 (a bad flag names its key and range), or the record to run with and the warnings of every file or environment value refused alone.

    line("x", {port: knob(80)}, {name: "x"}, ["--port", "9"], nil, no_env)[:opts][:port] #=> 9
"""
def line(app, model, frame, args, doc, lookup)
  below = settle(app, model, doc, lookup, {})
  spec = cli_spec(model, frame, below[:config])
  ex = explain_of(args)
  completing = args != [] and first(args) == "__complete"
  if completing and size(args) >= 3 and args[size(args) - 2] == "--explain"
    {
      kind: :complete,
      text: unlines(
        hikisuu::matching(
          args[size(args) - 1],
          map((r) -> dotted_key(r[:path]), knobs(model))
        )
      )
    }
  elsif completing
    hikisuu::outcome(args, spec)
  elsif ex != nil
    if ex[:key].nil?
      usage(frame, spec, "--explain needs a KEY")
    else
      s = settle(
        app,
        model,
        doc,
        lookup,
        quietly_given(model, frame, ex[:rest])
      )
      begin
        {kind: :explain, text: explain(app, model, s, ex[:key])}
      rescue :usage as e
        usage(frame, spec, e.message)
      end
    end
  else
    o = hikisuu::outcome(args, spec)
    if o[:kind] != :run
      o
    else
      parsed = hikisuu::parse(args, spec_with(model, frame, :unset))
      s = settle(app, model, doc, lookup, given_flags(model, parsed))
      bad = filter((f) -> f[:layer] == :flag, s[:refusals])
      if bad != []
        usage(frame, spec, join(map((f) -> f[:why], bad), "; "))
      else
        {
          kind: :run,
          opts: run_opts(model, frame, o[:opts], s[:config]),
          warnings: append(
            map(
              (f) -> f[:why],
              filter((f) -> f[:layer] != :flag, s[:refusals])
            ),
            s[:notices]
          )
        }
      end
    end
  end
end

# waive B0083: it ends the process with exit_with(64) on a bad line; line and explain are its body, tested with values, until the Terminal capability (docs/CLI-TUI.md section 7) lets a test hand it a line
@doc """
settled: the settings of a program with a core model and no command line of its own (a service, a library tool): the discovered config file and the environment settled per key, each refusal and notice warned on stderr, the config returned.

    procedure?(settled) #=> true
"""
def settled(app, model)
  path = discovered_path(app)
  doc = if path.nil?
    nil
  else
    file_doc(path, file_format(app, nil))
  end
  s = settle(app, model, doc, (name) -> getenv(name), {})
  said = append(map((f) -> f[:why], s[:refusals]), s[:notices])
  if said != []
    write_stderr(unlines(map((w) -> "#{app}: #{w}", said)))
  end
  s[:config]
end

@doc """
env_pairs: the named knobs of a settled record as [environment name, value] pairs, in the order named, to hand the same settings to another process or host. A key the model lacks raises :bad_option naming it.

    env_pairs("app", {port: knob(80)}, {port: 9}, ["port"]) #=> [["APP_PORT", 9]]
"""
def env_pairs(app, model, config, keys)
  rows = knobs(model)
  map(
    fn(key)
      r = find(rows, (x) -> dotted_key(x[:path]) == key)
      if r.nil?
        raise(:bad_option, "#{key} is not a setting of #{app}")
      end
      [env_name(app, map(to_s, r[:path])), doc_at(config, r[:path])]
    end,
    keys
  )
end

@doc """
aliases_of: each renamed knob's environment name and the name it had before, the alias map read takes.

    aliases_of("app", {wait: {seconds: knob(0, {renamed: ["wait_s"]})}}) #=> {"APP_WAIT__SECONDS" => "APP_WAIT_S"}
"""
def aliases_of(app, model)
  jisho::from_entries(
    map(
      fn(r)
        [
          env_name(app, map(to_s, r[:path])),
          env_name(app, split(first(r[:knob][:renamed]), "."))
        ]
      end,
      filter((r) -> r[:knob][:renamed] != [], knobs(model))
    )
  )
end

@doc """
command: the door of a program with a core model: argv, the discovered config file and the environment resolved by `line`; help, completion and explain printed, a bad line refused with exit 64, each refused file or environment value warned on stderr, and f called with the record.

    procedure?(command) #=> true
"""
def command(app, model, frame, f)
  path = discovered_path(app)
  doc = if path.nil?
    nil
  else
    file_doc(path, file_format(app, nil))
  end
  o = line(app, model, frame, argv, doc, (name) -> getenv(name))
  k = o[:kind]
  if k == :run
    if o[:warnings] != []
      write_stderr(unlines(map((w) -> "#{frame[:name]}: #{w}", o[:warnings])))
    end
    f(o[:opts])
  elsif k == :usage
    write_stderr(o[:text])
    exit_with(o[:status])
    nil
  else
    if o[:text] != ""
      write_stdout(o[:text])
    end
    nil
  end
end

test "nothing configured resolves to the defaults"
  d = {"greeting" => "hello", "port" => 8080, "flags" => {"shout" => false}}
  assert resolve("ola-mundo", d, nil, no_env) == d
  assert resolve("ola-mundo", {}, nil, no_env) == {}
end

test "a file overrides the defaults and the environment overrides the file"
  d = {"greeting" => "hello", "port" => 8080, "flags" => {"shout" => false}}
  doc = json_read("{\"greeting\":\"oi\",\"flags\":{\"shout\":true}}")
  r = resolve(
    "ola-mundo",
    d,
    doc,
    env_of({"OLA_MUNDO_PORT" => "9090", "OLA_MUNDO_FLAGS__SHOUT" => "false"})
  )
  assert r ==
    {"greeting" => "oi", "port" => 9090, "flags" => {"shout" => false}}
  assert flag(r, "shout") == false
  assert setting(r, "greeting") == "oi"
end

test "env names are the app upcased, nested keys joined by two underscores"
  assert env_prefix("ola-mundo") == "OLA_MUNDO_"
  assert env_name("ola-mundo", %w[flags shout]) == "OLA_MUNDO_FLAGS__SHOUT"
  assert coerce(1, "42") == 42
  assert coerce(1.5, "2") == 2.0
  assert coerce(true, "OFF") == false
  assert coerce(true, "maybe").nil?
  assert coerce(false, "1") == true
  assert coerce(true, "0") == false
end

test "an unknown key and a wrong type are each refused, all at once"
  d = {"port" => 8080, "flags" => {"shout" => false}}
  doc = json_read("{\"prot\":1,\"flags\":{\"shout\":\"yes\"}}")
  caught = begin
    resolve("x", d, doc, env_of({"X_PORT" => "eighty"}))
  rescue e
    e.message
  end
  thrown = begin
    resolve("x", d, doc, env_of({"X_PORT" => "eighty"}))
  rescue e
    e
  end
  assert thrown.kind == :wrong_type
  assert contains?(caught, "prot is not a setting") == true
  assert contains?(caught, "flags.shout must be bool, got text") == true
  assert contains?(caught, "X_PORT=eighty is not a int") == true
end

test "an undeclared flag or setting is refused, not read as off"
  r = {"flags" => {"shout" => true}}
  assert flag(r, "shout") == true
  assert error?(
    begin
      flag(r, "whisper")
    rescue e
      e
    end
  ) == true
  assert error?(
    begin
      setting(r, "nope")
    rescue e
      e
    end
  ) == true
end

test "merge lets b win and is deep for maps"
  assert merge(
    {"a" => 1, "n" => {"x" => 1, "y" => 2}},
    {"n" => {"y" => 3}, "b" => 4}
  ) == {"a" => 1, "n" => {"x" => 1, "y" => 3}, "b" => 4}
  assert merge({"n" => {"x" => 1}}, {"n" => 5}) == {"n" => 5}
  assert merge({}, {}) == {}
end

test "has? and need read a dotted path and need raises not_found"
  c = {"port" => 80, "flags" => {"shout" => false}}
  assert has?(c, "port") == true
  assert has?(c, "flags.shout") == true
  assert has?(c, "flags.whisper") == false
  assert has?(c, "port.x") == false
  assert need(c, "flags.shout") == false
  assert contains?(
    begin
      need(c, "flags.whisper")
    rescue e
      e.message
    end,
    "no setting flags.whisper"
  ) == true
end

test "file refuses an unknown tier and the explicit tier is nil when unset"
  assert file("zz-no-such-app", :explicit).nil?
  assert contains?(
    begin
      file("x", :nope)
    rescue e
      e.message
    end,
    "nope is not a tier"
  ) == true
end

def defaults_dir()
  dir = path_join(temp_dir("settei-defs"), "settei-defs")
  mkdir_p(dir)
  dir
end

test "prescribed reads the file as JSON settings"
  dir = defaults_dir
  p = path_join(dir, "defaults.json")
  write_file(p, "{\"port\":8080,\"name\":\"x\",\"nested\":{\"on\":true}}")
  s = prescribed("zz-app", p)
  assert s["port"] == 8080
  assert s["name"] == "x"
  assert s["nested"]["on"] == true
  write_file(p, "{}")
  assert prescribed("zz-app", p) == {}
  rm_rf(dir)
end

test "prescribed raises no_defaults, naming the app's variable, when there is no path"
  r = begin
    prescribed("zz-app", nil)
  rescue e
    e.message
  end
  assert contains?(r, "ZZ_APP_DEFAULTS names no file of prescribed settings")
end

test "prescribed raises when the file is missing or is not JSON"
  gone = prescribed("zz-app", "/nonexistent/defaults.json") rescue "caught"
  assert gone == "caught"
  dir = defaults_dir
  p = path_join(dir, "defaults.json")
  write_file(p, "not json")
  bad = prescribed("zz-app", p) rescue "caught"
  assert bad == "caught"
  rm_rf(dir)
end

test "defaults raises no_defaults, naming the variable, when none is set"
  r = begin
    defaults("zz-unset-app")
  rescue e
    e.message
  end
  assert contains?(
    r,
    "ZZ_UNSET_APP_DEFAULTS names no file of prescribed settings"
  )
end

test "defaults reads the variable of the app it is given: a hyphen is an underscore, case is upper"
  assert env_prefix("zz-unset-app") == "ZZ_UNSET_APP_"
  r = defaults("zz-unset-app") rescue "caught"
  assert r == "caught"
end

test "the file tier reads YAML unless the format is chosen"
  assert file_format("zz-no-such-app", nil) == :yaml
  assert file_format("zz-no-such-app", {format: :json}) == :json
  assert file_format("zz-no-such-app", {format: "yaml"}) == :yaml
  r = begin
    file_format("zz-no-such-app", {format: :toml})
  rescue e
    e.kind
  end
  assert r == :bad_option
end

test "a YAML file and a JSON file resolve to the same settings"
  dir = defaults_dir
  y = path_join(dir, "app.yaml")
  j = path_join(dir, "app.json")
  write_file(y, unlines(["greeting: oi", "flags:", "  shout: true"]))
  write_file(j, "{\"greeting\": \"oi\", \"flags\": {\"shout\": true}}")
  d = {"greeting" => "hello", "port" => 8080, "flags" => {"shout" => false}}
  want = {"greeting" => "oi", "port" => 8080, "flags" => {"shout" => true}}
  assert resolve("x", d, file_doc(y, :yaml), no_env) == want
  assert resolve("x", d, file_doc(j, :json), no_env) == want
  assert resolve("x", d, file_doc(j, :yaml), no_env) == want
  assert (file_doc(y, :json) rescue :refused) == :refused
  rm_rf(dir)
end

test "an alias keeps a renamed setting's old environment name working, and the new name wins"
  d = {"wait" => {"seconds" => 0}}
  old = env_of({"X_WAIT_S" => "5"})
  both = env_of({"X_WAIT_S" => "5", "X_WAIT__SECONDS" => "9"})
  names = {"X_WAIT__SECONDS" => "X_WAIT_S"}
  assert resolve("x", d, nil, aliased(old, names)).wait.seconds == 5
  assert resolve("x", d, nil, aliased(both, names)).wait.seconds == 9
  assert resolve("x", d, nil, aliased(old, {})).wait.seconds == 0
end

@doc """
json_type: the JSON Schema type of a knob type.

    json_type(:int) #=> "integer"
"""
def json_type(t)
  get({bool: "boolean", int: "integer", float: "number", text: "string"}, t)
end

@doc """
knob_schema: one knob as a JSON Schema: type, default (never a secret's), bounds, enum, description, deprecated, writeOnly for a secret, and x-unit, x-since and x-set-by where they say more than the default.

    knob_schema(knob(6, {min: 0}))["minimum"] #=> 0
"""
def knob_schema(k)
  jisho::from_entries(
    filter(
      (e) -> second(e) != nil,
      [
        ["type", json_type(k[:type])],
        [
          "default",
          if not k[:secret]
            k[:default]
          end
        ],
        ["minimum", k[:min]],
        ["maximum", k[:max]],
        ["enum", k[:choices]],
        [
          "description",
          if k[:doc] != ""
            k[:doc]
          end
        ],
        [
          "deprecated",
          if k[:deprecated] != nil
            true
          end
        ],
        [
          "writeOnly",
          if k[:secret]
            true
          end
        ],
        [
          "readOnly",
          if k[:computed] != nil
            true
          end
        ],
        ["x-unit", k[:unit]],
        ["x-since", k[:since]],
        [
          "x-set-by",
          if k[:set_by] != layers
            map(to_s, k[:set_by])
          end
        ]
      ]
    )
  )
end

@doc """
group_schema: a group of a core model as a closed JSON Schema object.

    group_schema({})["additionalProperties"] #=> false
"""
def group_schema(model)
  {
    "type" => "object",
    "additionalProperties" => false,
    "properties" => jisho::from_entries(
      map(
        fn(e)
          v = second(e)
          [
            to_s(first(e)),
            if knob?(v)
              knob_schema(v)
            else
              group_schema(v)
            end
          ]
        end,
        map_entries(model)
      )
    )
  }
end

@doc """
json_schema: the JSON Schema (2020-12) of a core model: the config file's schema, the chart values' schema and an MCP tool's input, one rendering for all three.

    json_schema("app", {port: knob(80)})["properties"]["port"]["type"] #=> "integer"
"""
def json_schema(app, model)
  merge(
    {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "title" => "#{app} settings"
    },
    group_schema(model)
  )
end

@doc """
trio_field: one knob as the module trio's typed field: intRange for a number bounded both ways, enum for choices, the nullOr form for no default, and its default and description.

    trio_field(knob(true, {doc: "x"})) #=> {"type" => "bool", "default" => true, "description" => "x"}
"""
def trio_field(k)
  t = k[:type]
  base = if t == :int and k[:min] != nil and k[:max] != nil
    {"type" => "intRange", "min" => k[:min], "max" => k[:max]}
  elsif k[:choices] != nil
    {"type" => "enum", "values" => k[:choices]}
  else
    named = get({bool: "bool", int: "int", float: "float", text: "str"}, t)
    if k[:default].nil?
      {"type" => "nullOr#{moji::capitalize(named)}"}
    else
      {"type" => named}
    end
  end
  jisho::from_entries(
    filter(
      (e) -> second(e) != nil,
      append(
        map_entries(base),
        [
          [
            "default",
            if not k[:secret]
              k[:default]
            end
          ],
          [
            "description",
            if k[:doc] != ""
              k[:doc]
            end
          ]
        ]
      )
    )
  )
end

@doc """
typed_groups: a core model as the module trio's shikumiTypedGroups (group to field to typed spec), so the NixOS, darwin and home-manager options of a program are rendered from its model; a knob outside a group, or deeper than one group, is refused alone.

    typed_groups({g: {on: knob(true)}})[:groups]["g"]["on"]["type"] #=> "bool"
"""
def typed_groups(model)
  reduce(
    fn(acc, r)
      p = r[:path]
      key = dotted_key(p)
      if size(p) == 2
        group = to_s(first(p))
        fields = get(acc[:groups], group) or {}
        assoc(
          acc,
          :groups,
          assoc(
            acc[:groups],
            group,
            assoc(fields, to_s(second(p)), trio_field(r[:knob]))
          )
        )
      else
        why = if size(p) == 1
          "a module option needs a group"
        else
          "a module option holds one group level"
        end
        assoc(acc, :refused, append(acc[:refused], ["#{key}: #{why}"]))
      end
    end,
    {groups: {}, refused: []},
    knobs(model)
  )
end

@doc """
mcp_tool: an MCP tool that reads or proposes a program's settings, its input the model's JSON Schema.

    mcp_tool("my-app", {})["name"] #=> "my_app_settings"
"""
def mcp_tool(app, model)
  {
    "name" => "#{replace(app, "-", "_")}_settings",
    "description" => "the settings of #{app}: each one's value, the layer it came from, its range and its doc",
    "inputSchema" => json_schema(app, model)
  }
end

@doc """
redacted: a settings record with every secret replaced by <secret>, for a log line, a crash report or an MCP answer.

    redacted({t: knob("", {secret: true})}, {t: "x"}) #=> {t: "<secret>"}
"""
def redacted(model, record)
  reduce(
    fn(acc, r)
      if r[:knob][:secret] and doc_at(acc, r[:path]) != nil
        put_in(acc, r[:path], "<secret>")
      else
        acc
      end
    end,
    record,
    knobs(model)
  )
end

@doc """
diff: each key whose value differs between two settings records, with both values as a person reads them, a secret hidden.

    diff({p: knob(1)}, {p: 1}, {p: 2}) #=> [{key: "p", from: "1", to: "2"}]
"""
def diff(model, a, b)
  map(
    fn(r)
      {
        key: dotted_key(r[:path]),
        from: shown_value(r[:knob], doc_at(a, r[:path])),
        to: shown_value(r[:knob], doc_at(b, r[:path]))
      }
    end,
    filter((r) -> doc_at(a, r[:path]) != doc_at(b, r[:path]), knobs(model))
  )
end

@doc """
reload: a running program's settings settled again: an immutable knob keeps its value and its change is refused alone, and changes lists each key that moved with the layer that moved it, the audit line of the reload.

    reload("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env), nil, env_of({"A_P" => "2"}))[:changes] #=> [{key: "p", from: "1", to: "2", source: :env}]
"""
def reload(app, model, before, doc, lookup, given?)
  after = settle(app, model, doc, lookup, given or {})
  held = reduce(
    fn(acc, r)
      k = r[:knob]
      was = doc_at(before[:config], r[:path])
      now = doc_at(acc[:config], r[:path])
      if k[:immutable] and was != now
        key = dotted_key(r[:path])
        jisho::update(
          assoc(
            assoc(acc, :config, put_in(acc[:config], r[:path], was)),
            :sources,
            assoc(acc[:sources], key, get(before[:sources], key))
          ),
          :refusals,
          fn(rs)
            append(
              rs,
              [
                fault(
                  key,
                  get(acc[:sources], key),
                  refusal(
                    :immutable,
                    "#{key} is set at start only; it stays #{shown_value(k, was)} until a restart"
                  )
                )
              ]
            )
          end
        )
      else
        acc
      end
    end,
    after,
    knobs(model)
  )
  assoc(
    held,
    :changes,
    map(
      (c) -> assoc(c, :source, get(held[:sources], c[:key])),
      diff(model, before[:config], held[:config])
    )
  )
end

@doc """
samples: values for a knob's bounds law: inside holds each value its bounds accept (each end, the default, each choice), outside each one they refuse (one past each end, a choice it lacks, a value of another type).

    samples(knob(5, {min: 0, max: 9}))[:outside] #=> [-1, 10, "x"]
"""
def samples(k)
  t = k[:type]
  if t == :bool
    {inside: [true, false], outside: ["x"]}
  elsif t == :text
    if k[:choices] != nil
      {
        inside: k[:choices],
        outside: [
          if member?("z", k[:choices])
            "zz"
          else
            "z"
          end,
          1
        ]
      }
    else
      {
        inside: distinct(filter((v) -> v != nil, [k[:default], "", "x"])),
        outside: [1]
      }
    end
  else
    step = if t == :int
      1
    else
      0.5
    end
    ends = filter((v) -> v != nil, [k[:min], k[:max]])
    {
      inside: distinct(
        filter(
          (v) -> v != nil and why_not(k, v).nil?,
          append(ends, [k[:default]])
        )
      ),
      outside: append(
        filter(
          (v) -> v != nil,
          [
            if k[:min] != nil
              k[:min] - step
            end,
            if k[:max] != nil
              k[:max] + step
            end
          ]
        ),
        ["x"]
      )
    }
  end
end

@doc """
law_case: one value offered for one knob by one layer, settled: the value the knob ends with and whether its key was refused.

    law_case("a", {p: knob(1, {min: 0})}, {path: [:p], knob: knob(1, {min: 0})}, :file, -1) #=> {value: 1, refused: true}
"""
def law_case(app, model, r, layer, v)
  p = r[:path]
  key = dotted_key(p)
  doc = if layer == :file
    put_in({}, p, v)
  end
  env = if layer == :env
    env_of({env_name(app, map(to_s, p)) => to_s(v)})
  else
    no_env
  end
  flags = if layer == :flag
    {key => v}
  else
    {}
  end
  s = settle(app, model, doc, env, flags)
  {
    value: doc_at(s[:config], p),
    refused: any?((f) -> f[:key] == key, s[:refusals])
  }
end

@doc """
bounds_law: the property every knob's bounds promise, checked on every layer that may set it: each inside sample loads as given, each outside sample is refused for its key and the default stands. Returns each broken case; a test asserts none.

    bounds_law("app", {p: knob(1, {min: 0})}) #=> []
"""
def bounds_law(app, model)
  reduce(
    fn(acc, r)
      k = r[:knob]
      s = samples(k)
      cases = reduce(
        fn(c, layer)
          append(
            c,
            map((v) -> [layer, v, true], s[:inside]),
            map(
              (v) -> [layer, v, false],
              filter((v) -> layer != :env or fits?(k[:type], v), s[:outside])
            )
          )
        end,
        [],
        filter((l) -> member?(l, k[:set_by]), layers)
      )
      append(
        acc,
        reduce(
          fn(bad, c)
            got = law_case(app, model, r, c[0], c[1])
            ok = if c[2]
              not got[:refused] and got[:value] == c[1]
            else
              got[:refused] and got[:value] == k[:default]
            end
            if ok
              bad
            else
              append(
                bad,
                [
                  "#{dotted_key(r[:path])} from #{to_s(c[0])}: #{to_s(c[1])} should be #{if c[2]
  "loaded"
else
  "refused"
end}"
                ]
              )
            end
          end,
          [],
          cases
        )
      )
    end,
    [],
    filter((r) -> r[:knob][:computed].nil?, knobs(model))
  )
end

@doc """
form: the settings form of a program: one row per knob with its value, source, range and doc, ready for edits checked live.

    size(form("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env))[:rows]) #=> 1
"""
def form(app, model, settled)
  {
    app:,
    model:,
    config: settled[:config],
    rows: map(
      fn(r)
        k = r[:knob]
        key = dotted_key(r[:path])
        {
          key:,
          path: r[:path],
          value: shown_value(k, doc_at(settled[:config], r[:path])),
          source: get(settled[:sources], key),
          range: range_text(k),
          doc: k[:doc],
          edit: nil,
          error: nil
        }
      end,
      knobs(model)
    )
  }
end

@doc """
form_row: the row of one key in a form.

    form_row(form("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env)), "p")[:value] #=> "1"
"""
def form_row(f, key)
  find(f[:rows], (r) -> r[:key] == key)
end

@doc """
form_edit: a form with one row edited from the text typed: read as the knob's type and checked against its bounds now, the reason shown on the row when it is refused.

    form_row(form_edit(form("a", {p: knob(1, {min: 0})}, settle("a", {p: knob(1, {min: 0})}, nil, no_env)), "p", "-1"), "p")[:error] #=> "must be 0 or more, got -1"
"""
def form_edit(f, key, text)
  r = form_row(f, key)
  k = r and find(knobs(f[:model]), (x) -> dotted_key(x[:path]) == key)[:knob]
  v = if k != nil
    coerce_as(k[:type], text)
  end
  error = if r.nil?
    "no setting #{key}"
  elsif k[:secret]
    "a secret is not edited here"
  elsif k[:computed] != nil
    "a computed setting is not edited"
  elsif v.nil?
    "must be #{to_s(k[:type])}, got #{text}"
  else
    why_not(k, v)
  end
  edited = if error.nil?
    v
  end
  assoc(
    f,
    :rows,
    map(
      fn(row)
        if row[:key] == key
          assoc(assoc(row, :edit, edited), :error, error)
        else
          row
        end
      end,
      f[:rows]
    )
  )
end

@doc """
form_pending: the changes a form would apply, each key with its old and new value: the diff shown before apply.

    form_pending(form("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env))) #=> []
"""
def form_pending(f)
  map(
    fn(row)
      k = find(knobs(f[:model]), (x) -> x[:path] == row[:path])[:knob]
      {key: row[:key], from: row[:value], to: shown_value(k, row[:edit])}
    end,
    filter((row) -> row[:edit] != nil and row[:error].nil?, f[:rows])
  )
end

@doc """
form_text: a form as the lines a terminal shows: each key, its value or the pending change, its range and source, and a refused edit's reason under it.

    contains?(form_text(form("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env))), "p") #=> true
"""
def form_text(f)
  pending = form_pending(f)
  w = reduce((m, r) -> blue::max(m, size(chars(r[:key]))), 0, f[:rows])
  unlines(
    append(
      ["#{f[:app]} settings"],
      reduce(
        fn(acc, r)
          change = find(pending, (c) -> c[:key] == r[:key])
          shown = if change != nil
            "#{change[:from]} -> #{change[:to]}"
          else
            r[:value]
          end
          line = "  #{pad_right(r[:key], w, " ")}  #{shown}  (#{r[:range]}, #{to_s(r[:source])})"
          if r[:error] != nil
            append(acc, [line, "    ! #{r[:error]}"])
          else
            append(acc, [line])
          end
        end,
        [],
        f[:rows]
      ),
      [
        if pending == []
          "no changes"
        else
          "#{to_s(size(pending))} change(s) to apply"
        end
      ]
    )
  )
end

@doc """
form_apply: the settings record a form's pending changes make.

    form_apply(form_edit(form("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env)), "p", "2")) #=> {p: 2}
"""
def form_apply(f)
  reduce(
    (acc, row) -> put_in(acc, row[:path], row[:edit]),
    f[:config],
    filter((row) -> row[:edit] != nil and row[:error].nil?, f[:rows])
  )
end

@doc """
form_step: one line typed into a settings form: `key=value` edits a row, checked live; `apply` ends with the pending changes applied; `quit` or the end of input ends with nothing applied; anything else is told how to answer.

    form_step(form("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env)), "apply")[:applied] #=> {p: 1}
"""
def form_step(f, line)
  if line.nil? or line == "quit"
    {form: f, done: true, applied: nil, says: "nothing applied"}
  elsif line == "apply"
    changes = form_pending(f)
    {
      form: f,
      done: true,
      applied: form_apply(f),
      says: if changes == []
        "no changes"
      else
        join(
          map((c) -> "#{c[:key]}: #{c[:from]} -> #{c[:to]}", changes),
          line_break
        )
      end
    }
  else
    parts = split(line, "=")
    if size(parts) < 2
      {
        form: f,
        done: false,
        applied: nil,
        says: "type key=value, apply or quit"
      }
    else
      key = first(parts)
      edited = form_edit(f, key, join(rest(parts), "="))
      row = form_row(edited, key)
      {
        form: edited,
        done: false,
        applied: nil,
        says: if row.nil?
          "no setting #{key}"
        elsif row[:error] != nil
          "#{key}: #{row[:error]}"
        else
          "#{key} -> #{to_s(row[:edit])}"
        end
      }
    end
  end
end

@doc """
form_session: a settings form driven by a list of typed lines, as a terminal session would drive it: the last step, and every line said along the way.

    form_session(form("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env)), ["p=2", "apply"])[:applied] #=> {p: 2}
"""
def form_session(f, lines)
  start = {form: f, done: false, applied: nil, says: nil, said: []}
  reduce(
    fn(acc, line)
      if acc[:done]
        acc
      else
        step = form_step(acc[:form], line)
        assoc(step, :said, append(acc[:said], [step[:says]]))
      end
    end,
    start,
    append(lines, [nil])
  )
end

@doc """
form_run: the settings form as a terminal loop: it writes the form, reads the next line with `next_line(i)`, says what the line did and the form again, until `apply`, `quit` or the end of input (nil), and answers the settings applied or nil. A program on a terminal passes `(i) -> read_line()` and `(t) -> write_stdout(t)`.

    form_run(form("a", {p: knob(1)}, settle("a", {p: knob(1)}, nil, no_env)), (i) -> ["p=2", "apply"][i], (_t) -> nil) #=> {p: 2}
"""
def form_run(f, next_line, say, at?)
  i = if at.nil?
    0
  else
    at
  end
  say(unlines([form_text(f)]))
  say("> ")
  step = form_step(f, next_line(i))
  say(unlines([step[:says]]))
  if step[:done]
    step[:applied]
  else
    form_run(step[:form], next_line, say, i + 1)
  end
end

@doc """
table_head: the two heading lines of a settings table.

    size(split(table_head, line_break)) #=> 3
"""
def table_head()
  unlines(
    [
      "| Setting | Type | Default | Range | Unit | Environment | Flag | Set by | Since | About |",
      "|---|---|---|---|---|---|---|---|---|---|"
    ]
  )
end

@doc """
code_cell: a table cell in code type, empty for nothing.

    code_cell("x") #=> "`x`"
"""
def code_cell(text)
  if text.nil? or text == ""
    ""
  else
    "`#{text}`"
  end
end

@doc """
about_cell: a knob's doc as the table's last cell, with its deprecation said.

    about_cell(knob(1, {doc: "n", deprecated: "use m"})) #=> "n. Deprecated: use m."
"""
def about_cell(k)
  if k[:deprecated].nil?
    k[:doc]
  else
    "#{k[:doc]}. Deprecated: #{k[:deprecated]}."
  end
end

@doc """
table: the settings table of a core model as Markdown, one row per knob: key, type, default (hidden for a secret), range, unit, environment name, flag, the layers that may set it, since and the doc. A program's generated docs page is this table, gated fresh.

    contains?(table("app", {port: knob(80, {min: 1})}), "| `port` | int | `80` | 1 or more |") #=> true

A program with no command line of its own passes {flags: false}: no flag is shown and flag leaves the layers that may set a knob.
"""
def table(app, model, opts?)
  lined = opts.nil? or opts[:flags] != false
  rows = map(
    fn(r)
      k = r[:knob]
      by = if lined
        k[:set_by]
      else
        filter((l) -> l != :flag, k[:set_by])
      end
      cells = [
        code_cell(dotted_key(r[:path])),
        to_s(k[:type]),
        code_cell(shown_value(k, k[:default])),
        range_text(k),
        k[:unit] or "",
        code_cell(env_name(app, map(to_s, r[:path]))),
        if lined and by_flag?(k)
          code_cell(flag_word(r[:path]))
        else
          ""
        end,
        join(map(to_s, by), ", "),
        k[:since] or "",
        about_cell(k)
      ]
      "| #{join(cells, " | ")} |"
    end,
    knobs(model)
  )
  concat(table_head, unlines(rows))
end

@doc """
root?: whether a form is the settings record: a name in names, or a call of such a word with no arguments, by its last name segment.

    root?(first(read_forms("(pkg/config)")), ["config"]) #=> true
"""
def root?(f, names)
  named = (s) -> symbol?(s) and member?(retsu::last(split(to_s(s), "/")), names)
  named(f) or list?(f) and size(f) == 1 and named(first(f))
end

@doc """
bindings: the local names one definition binds to the settings record (`c = config`), so reads through them count.

    bindings(first(read_forms("(define (f) (begin (define c (pkg/config)) c))")), "config") #=> ["c"]
"""
def bindings(f, param)
  if not list?(f) or f == []
    []
  elsif size(f) == 3 and
      to_s(first(f)) == "define" and
      symbol?(f[1]) and
      root?(f[2], [param])
    [to_s(f[1])]
  else
    reduce((acc, x) -> append(acc, bindings(x, param)), [], f)
  end
end

@doc """
read_path: the keys a chain of reads takes from the settings record, outermost last, or nil when the form is not such a chain.

    read_path(first(read_forms("(get (get opts :net) :port)")), ["opts"]) #=> %w[net port]
"""
def read_path(f, param)
  if list?(f) and
      size(f) == 3 and
      member?(to_s(first(f)), %w[get blue-field]) and
      (keyword?(f[2]) or string?(f[2]))
    inner = if root?(f[1], param)
      []
    else
      read_path(f[1], param)
    end
    if inner != nil and ends_with?(to_s(f[2]), "?")
      inner
    elsif inner != nil
      append(inner, [to_s(f[2])])
    end
  end
end

@doc """
form_reads: the dotted paths one form and everything inside it read off the settings record.

    form_reads(first(read_forms("(get opts :port)")), ["opts"]) #=> ["port"]
"""
def form_reads(f, param)
  path = read_path(f, param)
  if path == []
    []
  elsif path != nil
    [join(path, ".")]
  elsif not list?(f) or f == []
    []
  else
    reduce((acc, x) -> append(acc, form_reads(x, param)), [], f)
  end
end

@doc """
reads: every dotted path a program's forms read off the settings record named param (a parameter, or a word called with no arguments), as `get(param, :k)`, `param[:k]` or `param.k.j`, sorted, each once.

    reads(read_forms("(get opts :port)"), "opts") #=> ["port"]
"""
def reads(forms, param)
  sort_keyed(
    (x) -> x,
    distinct(
      reduce(
        fn(acc, f)
          append(acc, form_reads(f, append([param], bindings(f, param))))
        end,
        [],
        forms
      )
    )
  )
end

@doc """
frame_keys: the keys a parsed line holds besides the knobs: command, help, every positional and every frame flag.

    frame_keys({name: "x", positional: [{name: :roots}]}) #=> %w[command help roots]
"""
def frame_keys(frame)
  slots = append(
    frame[:positional] or [],
    reduce(
      (acc, c) -> append(acc, map?(c) and c[:positional] or []),
      [],
      frame[:commands] or []
    )
  )
  own = append(
    map((e) -> to_s(first(e)), map_entries(frame[:flags] or {})),
    reduce(
      fn(acc, c)
        if map?(c)
          append(acc, map((e) -> to_s(first(e)), map_entries(c[:flags] or {})))
        else
          acc
        end
      end,
      [],
      frame[:commands] or []
    )
  )
  append(%w[command help], map((s) -> to_s(s[:name]), slots), own)
end

@doc """
unmodelled: each key the code reads off its record that neither the core model nor the command-line frame declares; a test asserts it is empty, so a knob read in code and missing from the model fails the build.

    unmodelled({port: knob(80)}, {name: "x"}, read_forms("(get opts :prot)"), "opts") #=> ["prot"]
"""
def unmodelled(model, frame, forms, param)
  keys = map((r) -> dotted_key(r[:path]), knobs(model))
  framed = frame_keys(frame)
  filter(
    fn(k)
      not (
        member?(first(split(k, ".")), framed) or
        any?((m) -> m == k or starts_with?(m, "#{k}."), keys)
      )
    end,
    reads(forms, param)
  )
end

@doc """
unread: each knob of a core model the code never reads off its record, neither itself nor a group holding it: a knob nothing uses.

    unread({port: knob(80)}, [], "opts") #=> ["port"]
"""
def unread(model, forms, param)
  seen = reads(forms, param)
  filter(
    (k) -> not any?((s) -> s == k or starts_with?(k, "#{s}."), seen),
    map((r) -> dotted_key(r[:path]), knobs(model))
  )
end

@doc """
model_fixture: the core model the tests read: switches, floors, a group with a range, choices and a secret, and a deprecated knob.

    size(knobs(model_fixture)) #=> 6
"""
def model_fixture()
  {
    dry_run: knob(false, {doc: "say what would go; delete nothing"}),
    min_age_hours: knob(
      6,
      {min: 0, unit: "hours", doc: "keep what changed within this many hours"}
    ),
    net: {
      port: knob(8080, {min: 1, max: 65535, doc: "the port to listen on"}),
      mode: knob("fast", {choices: %w[fast safe], doc: "how to send"}),
      token: knob(
        "",
        {secret: true, set_by: %i[file env], doc: "the bearer token"}
      )
    },
    retries: knob(
      3,
      {deprecated: "use net.mode", since: "0.1.0", doc: "how often to retry"}
    )
  }
end

@doc """
kinds_of: the kind of each fault, in order.

    kinds_of([fault("a", :env, refusal(:wrong_type, "x"))]) #=> [:wrong_type]
"""
def kinds_of(found)
  map((r) -> r[:kind], found)
end

test "a knob takes its type from its default and keeps every annotation"
  k = knob(6, {min: 0, unit: "hours", doc: "idle hours", since: "0.2.0"})
  assert k[:type] == :int
  assert k[:default] == 6
  assert k[:min] == 0
  assert k[:unit] == "hours"
  assert k[:since] == "0.2.0"
  assert k[:secret] == false
  assert k[:set_by] == %i[file env flag]
  assert knob("x")[:type] == :text
  assert knob(nil, {type: :float})[:type] == :float
  assert knob?(k) == true
  assert knob?({min: 0}) == false
end

test "a bad annotation is refused as bad_option, naming it"
  why = fn(f)
    begin
      f()
      nil
    rescue :bad_option as e
      e.message
    end
  end
  assert contains?(why(() -> knob(1, {colour: "red"})), "colour is not a field")
  assert contains?(why(() -> knob(-1, {min: 0})), "must be 0 or more, got -1")
  assert contains?(why(() -> knob("a", {min: 0})), "min and max bound a number")
  assert contains?(
    why(() -> knob("z", {choices: %w[a b]})),
    "must be one of a, b, got z"
  )
  assert contains?(
    why(() -> knob(nil)),
    "a knob with no default names its type"
  )
  assert contains?(
    why(() -> knob([1])),
    "a knob holds bool, int, float or text"
  )
  assert contains?(why(() -> knob(1, {set_by: [:cli]})), "set_by")
  assert why(() -> knob(1, {min: 0, max: 3})).nil?
end

test "knobs lists every knob by path, and defaults_of is the plain record settei reads"
  m = model_fixture
  assert map((r) -> dotted_key(r[:path]), knobs(m)) ==
    %w[dry_run min_age_hours net.mode net.port net.token retries]
  assert defaults_of(m) ==
    {
      dry_run: false,
      min_age_hours: 6,
      net: {port: 8080, mode: "fast", token: ""},
      retries: 3
    }
  assert knobs({}) == []
  assert defaults_of({}) == {}
end

test "settle with nothing given is the defaults, each from the default layer"
  s = settle("app", model_fixture, nil, no_env, {})
  assert s[:config] == defaults_of(model_fixture)
  assert s[:refusals] == []
  assert s[:notices] == []
  assert s[:sources]["net.port"] == :default
  assert settle("app", {}, nil, no_env, {})[:config] == {}
end

test "the file overrides the defaults, the environment the file, and a flag the environment"
  doc = json_read("{\"net\":{\"port\":9000,\"mode\":\"safe\"},\"min_age_hours\":2}")
  env = env_of(
    {"APP_NET__PORT" => "9100", "APP_DRY_RUN" => "yes", "APP_RETRIES" => "4"}
  )
  s = settle("app", model_fixture, doc, env, {"net.port" => 9200})
  assert s[:config][:net][:port] == 9200
  assert s[:config][:net][:mode] == "safe"
  assert s[:config][:min_age_hours] == 2
  assert s[:config][:retries] == 4
  assert s[:sources]["min_age_hours"] == :file
  assert get(
    get(
      settle(
        "app",
        model_fixture,
        doc,
        env_of({"APP_MIN_AGE_HOURS" => "4"}),
        {}
      ),
      :config
    ),
    :min_age_hours
  ) == 4
  assert s[:config][:dry_run] == true
  assert s[:sources]["net.port"] == :flag
  assert s[:sources]["net.mode"] == :file
  assert s[:sources]["dry_run"] == :env
  assert s[:sources]["retries"] == :env
  assert s[:sources]["net.token"] == :default
  assert s[:refusals] == []
end

test "a bad value is refused for its key alone, naming the key and its range, and its siblings still load"
  doc = json_read("{\"net\":{\"port\":70000,\"mode\":\"safe\"},\"colour\":1,\"min_age_hours\":\"x\"}")
  env = env_of({"APP_RETRIES" => "eighty", "APP_DRY_RUN" => "true"})
  s = settle("app", model_fixture, doc, env, {"net.token" => "t"})
  assert s[:config][:net][:port] == 8080
  assert s[:config][:net][:mode] == "safe"
  assert s[:config][:min_age_hours] == 6
  assert s[:config][:retries] == 3
  assert s[:config][:dry_run] == true
  assert s[:config][:net][:token] == ""
  assert kinds_of(s[:refusals]) ==
    %i[unknown_key wrong_type out_of_range not_settable wrong_type]
  whys = join(map((r) -> r[:why], s[:refusals]), line_break)
  assert contains?(
    whys,
    "net.port must be in 1..65535, got 70000 from the file; kept 8080"
  )
  assert contains?(whys, "colour is not a setting")
  assert contains?(
    whys,
    "retries must be int, got eighty from APP_RETRIES; kept 3"
  )
  assert contains?(
    whys,
    "net.token may not be set by flag; it is set by file, env"
  )
  assert map((r) -> r[:key], s[:refusals]) ==
    %w[colour min_age_hours net.port net.token retries]
end

test "a deprecated knob that is set is a notice, not a refusal"
  s = settle("app", model_fixture, nil, env_of({"APP_RETRIES" => "5"}), {})
  assert s[:config][:retries] == 5
  assert s[:refusals] == []
  assert s[:notices] == ["retries is deprecated: use net.mode"]
end

@doc """
frame_fixture: the command-line frame the tests read: one command and the roots.

    frame_fixture[:name] #=> "app"
"""
def frame_fixture()
  {
    name: "app",
    about: "a fixture program",
    commands: [{name: :go, about: "go somewhere"}],
    positional: [{name: :roots, many: true, about: "where to look"}]
  }
end

test "the command line is rendered from the model: flags, kinds, floors, help and explain"
  spec = cli_spec(model_fixture, frame_fixture)
  help = hikisuu::render(spec, nil)
  assert contains?(help, "--min-age-hours N")
  assert contains?(help, "keep what changed within this many hours (default 6)")
  assert contains?(help, "--net-port N")
  assert contains?(help, "--net-mode TEXT")
  assert contains?(help, "--explain KEY")
  assert contains?(help, "--net-token") == false
  assert spec[:flags][:min_age_hours][:min] == 0
  shown = hikisuu::render(
    cli_spec(model_fixture, frame_fixture, {min_age_hours: 2}),
    nil
  )
  assert contains?(shown, "within this many hours (default 2)")
end

test "a line runs with every layer merged per key, a flag winning"
  doc = json_read("{\"net\":{\"mode\":\"safe\"}}")
  o = line(
    "app",
    model_fixture,
    frame_fixture,
    %w[go --net-port 9000 /a],
    doc,
    env_of({"APP_MIN_AGE_HOURS" => "2"})
  )
  assert o[:kind] == :run
  assert o[:opts][:command] == :go
  assert o[:opts][:roots] == ["/a"]
  assert o[:opts][:net] == {port: 9000, mode: "safe", token: ""}
  assert o[:opts][:min_age_hours] == 2
  assert o[:opts][:dry_run] == false
  assert o[:warnings] == []
end

test "a bad flag is a usage refusal naming the key and range; a bad file value warns and the run goes on"
  o = line(
    "app",
    model_fixture,
    frame_fixture,
    %w[go --net-port 70000],
    nil,
    no_env
  )
  assert o[:kind] == :usage
  assert o[:status] == 64
  assert contains?(
    o[:text],
    "net.port must be in 1..65535, got 70000 from --net-port"
  )
  w = line(
    "app",
    model_fixture,
    frame_fixture,
    ["go"],
    json_read("{\"net\":{\"port\":0}}"),
    no_env
  )
  assert w[:kind] == :run
  assert w[:opts][:net][:port] == 8080
  assert w[:warnings] ==
    ["net.port must be in 1..65535, got 0 from the file; kept 8080"]
end

test "explain KEY names the value, its layer, the default and the range, and hides a secret"
  o = line(
    "app",
    model_fixture,
    frame_fixture,
    %w[--explain net.port],
    nil,
    env_of({"APP_NET__PORT" => "9000", "APP_NET__TOKEN" => "t0k3n"})
  )
  assert o[:kind] == :explain
  assert contains?(o[:text], "net.port = 9000")
  assert contains?(o[:text], "source   env APP_NET__PORT")
  assert contains?(o[:text], "default  8080")
  assert contains?(o[:text], "range    1..65535")
  assert contains?(o[:text], "flag     --net-port")
  t = line(
    "app",
    model_fixture,
    frame_fixture,
    ["--explain=net.token"],
    nil,
    env_of({"APP_NET__TOKEN" => "t0k3n"})
  )
  assert contains?(t[:text], "net.token = <secret>")
  assert contains?(t[:text], "t0k3n") == false
  assert contains?(t[:text], "set by   file, env")
  f = line(
    "app",
    model_fixture,
    frame_fixture,
    %w[go --dry-run --explain dry_run],
    nil,
    no_env
  )
  assert contains?(f[:text], "source   flag --dry-run")
  u = line(
    "app",
    model_fixture,
    frame_fixture,
    %w[--explain net.prt],
    nil,
    no_env
  )
  assert u[:kind] == :usage
  assert contains?(
    u[:text],
    "no setting net.prt; the settings are dry_run, min_age_hours, net.mode, net.port, net.token, retries"
  )
end

test "completion after --explain offers the settings"
  o = line(
    "app",
    model_fixture,
    frame_fixture,
    %w[__complete --explain net.p],
    nil,
    no_env
  )
  assert o[:kind] == :complete
  assert o[:text] == unlines(["net.port"])
  h = line(
    "app",
    model_fixture,
    frame_fixture,
    %w[__complete go --net],
    nil,
    no_env
  )
  assert contains?(h[:text], "--net-port")
end

test "the settings table renders one row per knob, a secret's default hidden and a deprecation said"
  t = table("app", model_fixture)
  rows = split(t, line_break)
  assert rows[0] ==
    "| Setting | Type | Default | Range | Unit | Environment | Flag | Set by | Since | About |"
  assert contains?(
    t,
    "| `min_age_hours` | int | `6` | 0 or more | hours | `APP_MIN_AGE_HOURS` | `--min-age-hours` | file, env, flag |  | keep what changed within this many hours |"
  )
  assert contains?(
    t,
    "| `net.token` | text | `<secret>` | any text |  | `APP_NET__TOKEN` |  | file, env |  | the bearer token |"
  )
  assert contains?(t, "how often to retry. Deprecated: use net.mode. |")
  assert size(filter((r) -> r != "", rows)) == 8
  assert table("app", {}) == table_head
end

@doc """
forms_fixture: resolved forms the tests read, with reads of modelled, framed and unmodelled keys.

    size(forms_fixture) #=> 1
"""
def forms_fixture()
  read_forms("(define (%root/perform opts) (begin (get opts :dry_run) (blue-field opts :roots) (get (get opts :net) :port) (other (get opts :colour)) (get cfg :ignored)))")
end

test "unmodelled names each key code reads off its record that neither the model nor the frame declares"
  assert reads(forms_fixture, "opts") == %w[colour dry_run net.port roots]
  assert unmodelled(model_fixture, frame_fixture, forms_fixture, "opts") ==
    ["colour"]
  assert unread(model_fixture, forms_fixture, "opts") ==
    %w[min_age_hours net.mode net.token retries]
  nested = read_forms("(get (blue-field (pkg/config) :net) :prot)")
  assert unmodelled(model_fixture, frame_fixture, nested, "config") ==
    ["net.prot"]
  assert unmodelled(
    model_fixture,
    frame_fixture,
    read_forms("(blue-field (pkg/config) :net)"),
    "config"
  ) == []
  assert reads([], "opts") == []
  assert unmodelled(
    model_fixture,
    frame_fixture,
    read_forms("(get opts :command)"),
    "opts"
  ) == []
end

test "a document with one bad key and two valid ones loads the two valid ones"
  doc = json_read("{\"min_age_hours\":-5,\"dry_run\":true,\"net\":{\"mode\":\"safe\"}}")
  s = settle("app", model_fixture, doc, no_env, {})
  assert s[:config][:dry_run] == true
  assert s[:config][:net][:mode] == "safe"
  assert s[:config][:min_age_hours] == 6
  assert map((r) -> r[:key], s[:refusals]) == ["min_age_hours"]
  assert s[:refusals][0][:why] ==
    "min_age_hours must be 0 or more, got -5 from the file; kept 6"
end

test "the JSON Schema of a model types, bounds, documents and closes every group, and hides a secret's default"
  s = json_schema("app", model_fixture)
  assert s["$schema"] == "https://json-schema.org/draft/2020-12/schema"
  assert s["type"] == "object"
  assert s["additionalProperties"] == false
  port = s["properties"]["net"]["properties"]["port"]
  assert port ==
    {
      "type" => "integer",
      "default" => 8080,
      "minimum" => 1,
      "maximum" => 65535,
      "description" => "the port to listen on"
    }
  token = s["properties"]["net"]["properties"]["token"]
  assert token["writeOnly"] == true
  assert token["default"].nil?
  assert s["properties"]["net"]["properties"]["mode"]["enum"] == %w[fast safe]
  assert s["properties"]["retries"]["deprecated"] == true
  assert s["properties"]["min_age_hours"]["x-unit"] == "hours"
  assert json_schema("app", {})["properties"] == {}
end

test "the MCP tool of a model takes the model's JSON Schema as its input"
  t = mcp_tool("app", model_fixture)
  assert t["name"] == "app_settings"
  assert t["inputSchema"] == json_schema("app", model_fixture)
end

test "redacted hides every secret of a record and keeps the rest"
  c = get(
    settle(
      "app",
      model_fixture,
      nil,
      env_of({"APP_NET__TOKEN" => "t0k3n"}),
      {}
    ),
    :config
  )
  r = redacted(model_fixture, c)
  assert r[:net][:token] == "<secret>"
  assert r[:net][:port] == 8080
  assert contains?(to_s(r), "t0k3n") == false
  assert redacted({}, {}) == {}
end

test "diff names each key that differs, with both values, a secret hidden"
  a = defaults_of(model_fixture)
  b = put_in(put_in(a, %i[net port], 9000), %i[net token], "t0k3n")
  assert diff(model_fixture, a, b) ==
    [
      {key: "net.port", from: "8080", to: "9000"},
      {key: "net.token", from: "<secret>", to: "<secret>"}
    ]
  assert diff(model_fixture, a, a) == []
end

test "reload keeps an immutable knob, refuses its change alone, and logs who set what"
  m = {
    port: knob(80, {immutable: true, doc: "the port"}),
    level: knob("info", {choices: %w[info debug], doc: "the log level"})
  }
  before = settle("app", m, nil, no_env, {})
  after = reload(
    "app",
    m,
    before,
    nil,
    env_of({"APP_PORT" => "81", "APP_LEVEL" => "debug"})
  )
  assert after[:config] == {port: 80, level: "debug"}
  assert kinds_of(after[:refusals]) == [:immutable]
  assert after[:refusals][0][:why] ==
    "port is set at start only; it stays 80 until a restart"
  assert after[:changes] ==
    [{key: "level", from: "info", to: "debug", source: :env}]
end

test "a renamed knob reads its old key from a file and its old environment name, with a notice"
  m = {wait: {seconds: knob(0, {renamed: ["wait_s"], doc: "how long to wait"})}}
  s = settle("app", m, json_read("{\"wait_s\":5}"), no_env, {})
  assert s[:config][:wait][:seconds] == 5
  assert s[:refusals] == []
  assert s[:notices] == ["wait_s is now wait.seconds"]
  e = settle("app", m, nil, env_of({"APP_WAIT_S" => "7"}), {})
  assert e[:config][:wait][:seconds] == 7
  gone = settle("app", m, json_read("{\"wait_ms\":5}"), no_env, {})
  assert kinds_of(gone[:refusals]) == [:unknown_key]
end

test "a required knob no layer sets is refused alone, naming it"
  m = {
    url: knob(nil, {type: :text, required: true, doc: "the database URL"}),
    pool: knob(4, {min: 1, doc: "connections"})
  }
  s = settle("app", m, nil, no_env, {})
  assert kinds_of(s[:refusals]) == [:missing]
  assert s[:refusals][0][:why] ==
    "url is required and no layer sets it (APP_URL, --url or the file)"
  assert s[:config][:pool] == 4
  assert get(
    settle("app", m, nil, env_of({"APP_URL" => "pg://x"}), {}),
    :refusals
  ) == []
end

test "a computed knob is derived from the others and refused from every layer"
  m = {
    hours: knob(2, {min: 0, doc: "hours"}),
    seconds: knob(
      0,
      {computed: (c) -> c[:hours] * 3600, doc: "the same span in seconds"}
    )
  }
  s = settle(
    "app",
    m,
    nil,
    env_of({"APP_HOURS" => "3", "APP_SECONDS" => "9"}),
    {}
  )
  assert s[:config][:seconds] == 10800
  assert kinds_of(s[:refusals]) == [:not_settable]
  assert contains?(s[:refusals][0][:why], "seconds is computed")
  assert by_flag?(m[:seconds]) == false
end

test "the bounds law: every knob accepts each value inside its bounds and refuses each outside, for every layer"
  assert bounds_law("app", model_fixture) == []
  assert size(samples(knob(6, {min: 0, max: 9}))[:inside]) >= 3
  assert member?(-1, samples(knob(6, {min: 0}))[:outside])
  assert member?("z", samples(knob("a", {choices: %w[a b]}))[:outside])
end

test "the settings form: rows from the model, an edit checked live, and the diff shown before apply"
  f = form("app", model_fixture, settle("app", model_fixture, nil, no_env, {}))
  assert size(f[:rows]) == 6
  bad = form_edit(f, "net.port", "70000")
  assert form_row(bad, "net.port")[:error] == "must be in 1..65535, got 70000"
  assert form_pending(bad) == []
  good = form_edit(bad, "net.port", "9000")
  assert form_row(good, "net.port")[:error].nil?
  assert form_pending(good) == [{key: "net.port", from: "8080", to: "9000"}]
  assert contains?(form_text(good), "net.port")
  assert contains?(form_text(good), "8080 -> 9000")
  assert form_apply(good)[:net][:port] == 9000
  locked = form_edit(f, "net.token", "x")
  assert form_row(locked, "net.token")[:error] == "a secret is not edited here"
end

test "a predicate called on a setting reads the setting, not a key"
  assert reads(read_forms("(blue-field (get a :test) :nil?)"), "a") == ["test"]
end

test "a table for a program with no command line shows no flag"
  t = table("app", {port: knob(80, {min: 1, doc: "p"})}, {flags: false})
  assert contains?(
    t,
    "| `port` | int | `80` | 1 or more |  | `APP_PORT` |  | file, env |  | p |"
  )
end

test "the module trio's typed groups render each grouped knob, and a top-level knob is refused alone"
  t = typed_groups(model_fixture)
  assert t[:groups]["net"]["port"] ==
    {
      "type" => "intRange",
      "min" => 1,
      "max" => 65535,
      "default" => 8080,
      "description" => "the port to listen on"
    }
  assert t[:groups]["net"]["mode"]["type"] == "enum"
  assert t[:groups]["net"]["mode"]["values"] == %w[fast safe]
  assert t[:groups]["net"]["token"]["type"] == "str"
  assert t[:refused] ==
    [
      "dry_run: a module option needs a group",
      "min_age_hours: a module option needs a group",
      "retries: a module option needs a group"
    ]
  assert typed_groups({})[:groups] == {}
end

test "a settings form driven line by line: a refused edit says why, a good one is pending, apply shows the diff and applies it"
  f = form("app", model_fixture, settle("app", model_fixture, nil, no_env, {}))
  s = form_session(
    f,
    %w[net.port=70000 net.port=9000 colour=red hello apply net.port=1]
  )
  assert s[:done]
  assert s[:applied][:net][:port] == 9000
  assert s[:said] ==
    [
      "net.port: must be in 1..65535, got 70000",
      "net.port -> 9000",
      "no setting colour",
      "type key=value, apply or quit",
      "net.port: 8080 -> 9000"
    ]
end

test "a settings form ended by quit or the end of input applies nothing"
  f = form("app", model_fixture, settle("app", model_fixture, nil, no_env, {}))
  assert form_session(f, %w[net.port=9000 quit])[:applied].nil?
  ended = form_session(f, ["net.port=9000"])
  assert ended[:done]
  assert ended[:applied].nil?
  assert ended[:said] == ["net.port -> 9000", "nothing applied"]
  assert form_step(f, "apply")[:says] == "no changes"
end

test "form_run reads line by line, writes the form and what each line did, and answers what form_session applies"
  f = form("app", model_fixture, settle("app", model_fixture, nil, no_env, {}))
  lines = %w[net.port=9000 apply]
  applied = form_run(f, (i) -> lines[i], (_t) -> nil)
  assert applied == form_session(f, lines)[:applied]
  assert applied[:net][:port] == 9000
  assert form_run(f, (_i) -> nil, (_t) -> nil).nil?
end

test "the helpers under the renderings answer for the fixture model: schema pieces, trio fields, renames, aliases and the bounds law's single case"
  assert json_type(:int) == "integer"
  assert json_type(:text) == "string"
  assert knob_schema(knob(6, {min: 0, max: 9}))["maximum"] == 9
  assert group_schema({p: knob(1)})["properties"]["p"]["default"] == 1
  assert trio_field(knob(3, {min: 1, max: 9, doc: "n"}))["type"] == "intRange"
  assert trio_field(knob(3, {min: 1, doc: "n"}))["type"] == "int"
  assert renames({w: knob(0, {renamed: ["w_s"]})}, {"w_s" => 5})[:doc] == {w: 5}
  assert aliases_of("app", {w: knob(0, {renamed: ["w_s"]})}) ==
    {"APP_W" => "APP_W_S"}
  assert drop_at({"a" => {"b" => 1, "c" => 2}}, %w[a c]) == {"a" => {"b" => 1}}
  assert env_pairs(
    "app",
    model_fixture,
    settle("app", model_fixture, nil, no_env, {})[:config],
    ["net.port"]
  ) == [["APP_NET__PORT", 8080]]
  bad = law_case(
    "a",
    {p: knob(1, {min: 0})},
    {path: [:p], knob: knob(1, {min: 0})},
    :env,
    -1
  )
  assert bad == {value: 1, refused: true}
  ok = law_case(
    "a",
    {p: knob(1, {min: 0})},
    {path: [:p], knob: knob(1, {min: 0})},
    :file,
    4
  )
  assert ok == {value: 4, refused: false}
end

test "a computed knob is derived from the settled record, and the reads helpers follow bindings and nested paths"
  s = settle("a", {}, nil, no_env, {})
  assert derived("a", {}, s)[:config] == {}
  assert bindings(
    first(read_forms("(define (f) (begin (define c (pkg/config)) c))")),
    "config"
  ) == ["c"]
  assert form_reads(first(read_forms("(get opts :port)")), ["opts"]) == ["port"]
  assert read_path(
    first(read_forms("(get (get opts :net) :port)")),
    ["opts"]
  ) == %w[net port]
  assert root?(first(read_forms("(pkg/config)")), ["config"])
  assert not root?(first(read_forms("(pkg/other)")), ["config"])
end

test "settled answers the defaults of a model when no file or environment sets it"
  assert settled("settei-test-none", {p: knob(7)}) == {p: 7}
end
