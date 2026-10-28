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
  r = http_request(req[0], req[1], req[2], req[3], 5000)
  r[:status] < 300
end

# "home.light.kitchen" with payload "on" is light.turn_on for light.kitchen.
def command_of(m)
  parts = split(m[:subject], ".")
  service = if m[:payload] == "on"
    "turn_on"
  else
    "turn_off"
  end
  [parts[1], service, "#{parts[1]}.#{parts[2]}"]
end

# One turn of the daemon's loop: the next message applied, or nil when quiet.
def serve_once(sub, base, token)
  m = nats_next_message(sub, 1000)
  if m.nil?
    nil
  else
    cmd = command_of(m)
    send(service_call(base, token, cmd[0], cmd[1], cmd[2]))
  end
end

def serve(url, base, token)
  sub = nats_subscribe(nats_connect(url), "home.>")
  reduce((_acc, _i) -> serve_once(sub, base, token), nil, range(0, 3600))
end

test "a service call is a POST with a bearer token and a JSON body"
  req = service_call(
    "http://127.0.0.1:8123",
    "t0k",
    "light",
    "turn_on",
    "light.kitchen"
  )
  assert req[0] == "POST"
  assert req[1] == "http://127.0.0.1:8123/api/services/light/turn_on"
  assert json_get(req[2], :Authorization) == "Bearer t0k"
  assert json_get(json_parse(req[3]), :entity_id) == "light.kitchen"
end

test "a bus message names its command"
  m = {subject: "home.light.kitchen", payload: "on", reply: nil}
  assert command_of(m) == ["light", "turn_on", "light.kitchen"]
  assert command_of(assoc(m, :payload, "off"))[1] == "turn_off"
end

test "nothing listening is a raise, not a silent false"
  assert error?(
    begin
      nats_connect("nats://127.0.0.1:1", 500)
    rescue e
      e
    end
  )
  assert error?(
    begin
      http_request("GET", "http://127.0.0.1:1/", nil, nil, 500)
    rescue e
      e
    end
  )
end
