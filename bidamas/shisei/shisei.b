use(
  "kousei",
  [
    :entry,
    :field,
    :judge,
    :kind_of,
    :name_of,
    :off,
    :one_of,
    :text,
    :tune,
    :value_of
  ]
)

use("retsu", [:first, :flat_map, :size])

# shisei (姿勢) — a service's posture: postures declared as kousei entries, each on by default, each configured off or tuned, each refused alone.
#
# A posture is a record: name (the kousei kind), table (its field table),
# defaults (the settings it runs with when declared bare) and layer, a function
# of (settings, sink) that returns a middleware, a function from a handler to a
# handler. Every posture runs unless the declaration turns it off, and a bad
# entry is refused without touching its siblings.
#
# A posture that can refuse a request carries a `mode` setting, "audit" or
# "enforce". In audit the violation goes to the sink and the request proceeds;
# in enforce the request is refused. A blocking posture defaults to audit, so a
# new posture never turns a working service away until the operator says so.

def posture(name, table, defaults, layer)
  {name: name, table: table, defaults: defaults, layer: layer}
end

def table_of(p)
  get(p, :table)
end

# The kousei schema of a set of postures: each kind maps to its field table.
def schema(postures)
  reduce((acc, p) -> assoc(acc, name_of(p), table_of(p)), {}, postures)
end

# One entry per posture, running its defaults: the stance of a bare service.
def defaults(postures)
  map((p) -> entry(name_of(p), "default", get(p, :defaults)), postures)
end

# The declaration laid over the defaults and judged: accepted, off and refusals.
def stance(postures, declaration)
  judge(schema(postures), append(defaults(postures), declaration))
end

# The middlewares of every accepted entry, in the order the postures are given.
def layers(postures, accepted, sink)
  flat_map(
    fn(p)
      map(
        (e) -> get(p, :layer)(value_of(e), sink),
        filter((e) -> kind_of(e) == name_of(p), accepted)
      )
    end,
    postures
  )
end

# The first layer is outermost: it sees the request first and the response last.
def stack(ls, handler)
  reduce((h, l) -> l(h), handler, reverse(ls))
end

# The whole composition: the stance, its refusals and the handler it makes.
def serving(postures, declaration, sink, handler)
  s = stance(postures, declaration)
  {
    handler: stack(layers(postures, get(s, :accepted), sink), handler),
    off: get(s, :off),
    refusals: get(s, :refusals)
  }
end

# The ladder. `deny` is the refusal to send; `allow` is a function that goes on.
def gated(mode, sink, posture_name, why, deny, allow)
  if mode == "audit"
    sink(posture_name, why)
    allow()
  else
    deny
  end
end

# A sink that forgets. A sink that remembers is written where the cell is, since
# `set!` rebinds the variable it names and a cell handed through a parameter is
# a different binding.
def silent()
  (_name, _why) -> nil
end

def tag(key, value)
  posture(
    :tag,
    [field(:value, text)],
    {value: value},
    fn(settings, _sink)
      fn(handler)
        fn(req)
          r = handler(req)
          assoc(
            r,
            :headers,
            assoc(get(r, :headers), key, get(settings, :value))
          )
        end
      end
    end
  )
end

def veto(mode_default)
  posture(
    :veto,
    [field(:mode, one_of(["audit", "enforce"])), field(:path, text)],
    {mode: mode_default, path: "/no"},
    fn(settings, sink)
      fn(handler)
        fn(req)
          if get(req, :path) == get(settings, :path)
            gated(
              get(settings, :mode),
              sink,
              :veto,
              "#{get(req, :path)} is vetoed",
              {status: 403, headers: {}, body: "vetoed\n"},
              () -> handler(req)
            )
          else
            handler(req)
          end
        end
      end
    end
  )
end

def echo(req)
  {status: 200, headers: {}, body: "echo #{get(req, :path)}"}
end

def req_at(path)
  {method: "GET", path: path, query: "", headers: [], body: ""}
end

test "a bare service runs every posture it is given"
  s = stance([tag("X-A", "1"), veto("audit")], [])
  assert size(get(s, :accepted)) == 2
  assert get(s, :refusals) == []
  assert get(s, :off) == []
end

test "a layer wraps the handler and the first layer is outermost"
  order = [[]]
  mark = fn(label)
    fn(handler)
      fn(req)
        set!(order, [append(first(order), [label])])
        handler(req)
      end
    end
  end
  h = stack([mark("outer"), mark("inner")], echo)
  assert get(h(req_at("/")), :status) == 200
  assert first(order) == ["outer", "inner"]
  assert stack([], echo)(req_at("/a")) == echo(req_at("/a"))
end

test "a posture runs by default and the declaration can configure it off"
  postures = [tag("X-A", "1")]
  running = serving(postures, [], silent, echo)
  assert get(get(get(running, :handler)(req_at("/")), :headers), "X-A") == "1"
  disabled = serving(postures, [off(:tag, "default")], silent, echo)
  assert get(disabled, :refusals) == []
  assert size(get(disabled, :off)) == 1
  assert get(get(get(disabled, :handler)(req_at("/")), :headers), "X-A") == nil
end

test "a tune lays fields over the default, and a bad tune is refused alone"
  postures = [tag("X-A", "1")]
  tuned = serving(postures, [tune(:tag, "default", {value: "2"})], silent, echo)
  assert get(get(get(tuned, :handler)(req_at("/")), :headers), "X-A") == "2"
  bad = serving(postures, [tune(:tag, "default", {value: 7})], silent, echo)
  assert size(get(bad, :refusals)) == 1
  assert get(get(get(bad, :handler)(req_at("/")), :headers), "X-A") == "1"
end

test "audit records the violation and goes on, enforce refuses it"
  seen = [[]]
  note = (name, why) -> set!(seen, [append(first(seen), [[name, why]])])
  audit = serving([veto("audit")], [], note, echo)
  r = get(audit, :handler)(req_at("/no"))
  assert get(r, :status) == 200
  assert first(seen) == [[:veto, "/no is vetoed"]]
  seen2 = [[]]
  note2 = (name, why) -> set!(seen2, [append(first(seen2), [[name, why]])])
  enforce = serving(
    [veto("audit")],
    [tune(:veto, "default", {mode: "enforce"})],
    note2,
    echo
  )
  r2 = get(enforce, :handler)(req_at("/no"))
  assert get(r2, :status) == 403
  assert first(seen2) == []
  assert get(get(enforce, :handler)(req_at("/fine")), :status) == 200
end

test "a bad entry is refused alone and the other postures still stand"
  s = serving(
    [tag("X-A", "1"), veto("audit")],
    [entry(:veto, "extra", {mode: "loud", path: "/x"})],
    silent,
    echo
  )
  assert size(get(s, :refusals)) == 1
  assert get(get(get(s, :handler)(req_at("/")), :headers), "X-A") == "1"
end
