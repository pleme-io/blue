# Talking to the network
#
# http_request makes one plain-http request and answers {status:, headers:,
# body:}; any status is an answer, and only a failed exchange raises. A NATS bus
# is nats_connect, nats_subscribe and nats_next_message, which waits at most its
# timeout and answers nil when nothing came, so a daemon is a loop over it.
# Build each request and read each message as data, and the tests need no
# server: here a bus message becomes a Home Assistant service call.
def service_call(base, token, domain, service, entity)
  [
    "POST",
    "#{base}/api/services/#{domain}/#{service}",
    [
      ["Authorization", "Bearer #{token}"],
      ["Content-Type", "application/json"]
    ],
    json_stringify({entity_id: entity})
  ]
end

def send(req)
  r = http_request(nth(0, req), nth(1, req), nth(2, req), nth(3, req), 5000)
  get(r, :status) < 300
end

# "home.light.kitchen" with payload "on" is light.turn_on for light.kitchen.
def command_of(m)
  parts = split(get(m, :subject), ".")
  service = if get(m, :payload) == "on"
    "turn_on"
  else
    "turn_off"
  end
  [nth(1, parts), service, "#{nth(1, parts)}.#{nth(2, parts)}"]
end

# One turn of the daemon's loop: the next message applied, or nil when quiet.
def serve_once(sub, base, token)
  m = nats_next_message(sub, 1000)
  if m == nil
    nil
  else
    cmd = command_of(m)
    send(service_call(base, token, nth(0, cmd), nth(1, cmd), nth(2, cmd)))
  end
end

def serve(url, base, token)
  sub = nats_subscribe(nats_connect(url), "home.>")
  reduce(fn(_acc, _i) serve_once(sub, base, token) end, nil, range(0, 3600))
end

test "a service call is a POST with a bearer token and a JSON body"
  req = service_call(
    "http://127.0.0.1:8123",
    "t0k",
    "light",
    "turn_on",
    "light.kitchen"
  )
  assert nth(0, req) == "POST"
  assert nth(1, req) == "http://127.0.0.1:8123/api/services/light/turn_on"
  assert json_get(nth(2, req), "Authorization") == "Bearer t0k"
  assert json_get(json_parse(nth(3, req)), "entity_id") == "light.kitchen"
end

test "a bus message names its command"
  m = {subject: "home.light.kitchen", payload: "on", reply: nil}
  assert command_of(m) == ["light", "turn_on", "light.kitchen"]
  assert nth(1, command_of(assoc(m, :payload, "off"))) == "turn_off"
end

test "nothing listening is a raise, not a silent false"
  assert error?(try(nats_connect("nats://127.0.0.1:1", 500), catch(e(), e)))
  assert error?(
    try(
      http_request("GET", "http://127.0.0.1:1/", nil, nil, 500),
      catch(e(), e)
    )
  )
end
