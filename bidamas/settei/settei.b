use("kyohi", [:refusal, :refuse])
use("retsu", [:first])

def env_prefix(app)
  "#{upcase(replace(app, "-", "_"))}_"
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
  k = kind_of(default)
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
    if member?(downcase(text), ["true", "1", "yes", "on"])
      true
    elsif member?(downcase(text), ["false", "0", "no", "off"])
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
      if d == nil
        [
          first(acc),
          append(
            second(acc),
            [
              refusal(
                :unknown_key,
                "#{dotted(at)} is not a setting; the settings are #{join(map(fn(x) first(x) end, map_entries(defaults)), ", ")}"
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
        if text == nil
          acc
        else
          v = coerce(d, text)
          if v == nil
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
  from_file = if doc == nil
    [defaults, []]
  elsif kind_of(doc) == :map
    file_tier(defaults, doc, [])
  else
    [defaults, [refusal(:not_a_map, "the config file must hold one object")]]
  end
  from_env = env_tier(app, first(from_file), lookup, [])
  refuse(append(second(from_file), second(from_env)))
  first(from_env)
end

def discovered_path(app, lookup)
  explicit = lookup("#{env_prefix(app)}CONFIG")
  xdg = lookup("XDG_CONFIG_HOME")
  home = lookup("HOME")
  candidates = filter(
    fn(p) p != nil end,
    [
      explicit,
      if xdg == nil
        nil
      else
        "#{xdg}/#{app}/#{app}.yaml"
      end,
      if home == nil
        nil
      else
        "#{home}/.config/#{app}/#{app}.yaml"
      end
    ]
  )
  find(fn(p) is_file?(p) end, candidates)
end

def defaults_of(app, lookup)
  path = lookup("#{env_prefix(app)}DEFAULTS")
  if path == nil
    raise(
      :no_defaults,
      "#{env_prefix(app)}DEFAULTS names no file of prescribed settings"
    )
  end
  json_read(read_file(path))
end

def load(app)
  lookup = fn(name) getenv(name) end
  path = discovered_path(app, lookup)
  doc = if path == nil
    nil
  else
    json_read(read_file(path))
  end
  resolve(app, defaults_of(app, lookup), doc, lookup)
end

def serving?()
  getenv("BLUE_SERVICE") != nil
end

def current()
  load(env_required("BLUE_SERVICE"))
end

def flag(settings, name)
  flags = get(settings, "flags")
  v = if flags == nil
    nil
  else
    get(flags, name)
  end
  if v == nil
    raise(:unknown_flag, "#{name} is not a declared flag")
  end
  v == true
end

def setting(settings, name)
  v = get(settings, name)
  if v == nil
    raise(:unknown_setting, "#{name} is not a declared setting")
  end
  v
end

def no_env(_name)
  nil
end

def env_of(pairs)
  fn(name) get(pairs, name) end
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
  assert env_name("ola-mundo", ["flags", "shout"]) == "OLA_MUNDO_FLAGS__SHOUT"
  assert coerce(1, "42") == 42
  assert coerce(1.5, "2") == 2.0
  assert coerce(true, "OFF") == false
  assert coerce(true, "maybe") == nil
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
  ) ==
    true
  assert error?(
    begin
      setting(r, "nope")
    rescue e
      e
    end
  ) ==
    true
end
