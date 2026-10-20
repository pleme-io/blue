def response(status, content_type, body)
  {status: status, headers: {"Content-Type" => content_type}, body: body}
end

def text(status, body)
  response(status, "text/plain; charset=utf-8", body)
end

def json(status, value)
  response(status, "application/json", json_stringify(value))
end

def not_found(req)
  text(404, "no route for #{get(req, :method)} #{get(req, :path)}\n")
end

def query_params(req)
  q = get(req, :query)
  if q == nil or q == ""
    {}
  else
    reduce(
      fn(acc, part)
        kv = split(part, "=")
        if first(kv) == ""
          acc
        else
          assoc(acc, first(kv), join(rest(kv), "="))
        end
      end,
      {},
      split(q, "&")
    )
  end
end

def query_param(req, name)
  get(query_params(req), name)
end

def well_formed?(resp)
  resp != nil and map?(resp) and integer?(get(resp, :status))
end

def answer(req, health, handler)
  if get(req, :path) == health
    text(200, "ok\n")
  else
    resp = begin
      handler(req)
    rescue e
      text(500, "#{e.message}\n")
    end
    if well_formed?(resp)
      resp
    else
      text(500, "the handler answered #{to_s(resp)}, not a response\n")
    end
  end
end

def serve_once(l, health, handler, wait_ms)
  req = http_next_request(l, wait_ms)
  if req == nil
    nil
  else
    resp = answer(req, health, handler)
    http_respond(req, get(resp, :status), get(resp, :headers), get(resp, :body))
    write_stderr(
      "kyuuji: #{get(req, :method)} #{get(req, :path)} #{to_s(get(resp, :status))}\n"
    )
    get(resp, :status)
  end
end

def serve(addr, health, handler)
  l = http_listen(addr)
  write_stderr("kyuuji: listening on #{addr}, health #{health}\n")
  while(true, serve_once(l, health, handler, 1000))
end

def address(settings)
  listen = get(settings, "listen")
  "#{get(listen, "host")}:#{to_s(get(listen, "port"))}"
end

def serve_settings(settings, handler)
  serve(address(settings), get(settings, "health"), handler)
end

def request(method, path, query)
  {method: method, path: path, query: query, headers: [], body: ""}
end

def hello(req)
  if get(req, :path) == "/"
    text(200, "hi #{query_param(req, "who")}")
  elsif get(req, :path) == "/boom"
    raise(:boom, "it broke")
  elsif get(req, :path) == "/nil"
    nil
  else
    not_found(req)
  end
end

test "the health path is answered before the handler"
  r = answer(
    request("GET", "/healthz", ""),
    "/healthz",
    fn(_) raise(:x, "unreached") end
  )
  assert get(r, :status) == 200
  assert get(r, :body) == "ok\n"
end

test "a route answers, an unknown path is 404, a raise is 500"
  assert get(
    answer(request("GET", "/", "who=blue"), "/healthz", hello),
    :body
  ) ==
    "hi blue"
  assert get(answer(request("GET", "/x", ""), "/healthz", hello), :status) ==
    404
  r = answer(request("GET", "/boom", ""), "/healthz", hello)
  assert get(r, :status) == 500
  assert get(r, :body) == "it broke\n"
  assert get(answer(request("GET", "/nil", ""), "/healthz", hello), :status) ==
    500
end

test "query parameters are split once on = and empty ones dropped"
  assert query_params(request("GET", "/", "")) == {}
  assert query_params(request("GET", "/", "a=1&b=x=y&&c")) ==
    {"a" => "1", "b" => "x=y", "c" => ""}
  assert query_param(request("GET", "/", "a=1"), "z") == nil
end

test "a json response carries its content type"
  r = json(201, {"ok" => true})
  assert get(r, :status) == 201
  assert get(r, :body) == "{\"ok\":true}"
  assert get(get(r, :headers), "Content-Type") == "application/json"
end

test "settings name the address and the health path"
  s = {"listen" => {"host" => "127.0.0.1", "port" => 8080}, "health" => "/up"}
  assert address(s) == "127.0.0.1:8080"
end
