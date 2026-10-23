def response(status, content_type, body)
  {status:, headers: {"Content-Type" => content_type}, body:}
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
  if q.nil? or q == ""
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
  if req.nil?
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
  serve_metered(addr, health, handler, getenv("BLUE_SERVICE", "blue"))
end

def metrics_path()
  "/metrics"
end

def latency_bounds()
  [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
end

def status_classes()
  ["2xx", "3xx", "4xx", "5xx"]
end

def status_class(status)
  "#{to_s(floor(status / 100))}xx"
end

def metrics_empty()
  {
    "codes" => reduce((acc, c) -> assoc(acc, c, 0), {}, status_classes),
    "errors" => 0,
    "buckets" => map((_) -> 0, latency_bounds),
    "sum" => 0,
    "count" => 0
  }
end

def observe(m, status, seconds)
  codes = get(m, "codes")
  c = status_class(status)
  seen = get(codes, c)
  {
    "codes" => assoc(
      codes,
      c,
      if seen.nil?
        1
      else
        seen + 1
      end
    ),
    "errors" => get(m, "errors") +
      if status >= 500
        1
      else
        0
      end,
    "buckets" => map(
      fn(pair)
        if seconds <= first(pair)
          second(pair) + 1
        else
          second(pair)
        end
      end,
      zip(latency_bounds, get(m, "buckets"))
    ),
    "sum" => get(m, "sum") + seconds,
    "count" => get(m, "count") + 1
  }
end

def exposition(m, service)
  l = "service=\"#{service}\""
  codes = get(m, "codes")
  requests = map(
    (c) -> "http_requests_total{#{l},code=\"#{c}\"} #{to_s(get(codes, c))}",
    status_classes
  )
  buckets = map(
    fn(pair)
      "http_request_duration_seconds_bucket{#{l},le=\"#{to_s(first(pair))}\"} #{to_s(second(pair))}"
    end,
    zip(latency_bounds, get(m, "buckets"))
  )
  "#{join(append(["# HELP http_requests_total Requests answered, by status class.", "# TYPE http_requests_total counter"], requests, ["# HELP http_request_errors_total Requests answered with a 5xx status.", "# TYPE http_request_errors_total counter", "http_request_errors_total{#{l}} #{to_s(get(m, "errors"))}", "# HELP http_request_duration_seconds Time from a request to its answer.", "# TYPE http_request_duration_seconds histogram"], buckets, ["http_request_duration_seconds_bucket{#{l},le=\"+Inf\"} #{to_s(get(m, "count"))}", "http_request_duration_seconds_sum{#{l}} #{to_s(get(m, "sum"))}", "http_request_duration_seconds_count{#{l}} #{to_s(get(m, "count"))}"]), "\n")}\n"
end

def metrics_response(m, service)
  response(
    200,
    "text/plain; version=0.0.4; charset=utf-8",
    exposition(m, service)
  )
end

def metered(req, health, handler, m, service)
  path = get(req, :path)
  if path == metrics_path
    [metrics_response(m, service), m]
  else
    started = now_ms
    resp = answer(req, health, handler)
    if path == health
      [resp, m]
    else
      [resp, observe(m, get(resp, :status), (now_ms - started) / 1000)]
    end
  end
end

def serve_metered_once(l, health, handler, wait_ms, m, service)
  req = http_next_request(l, wait_ms)
  if req.nil?
    m
  else
    out = metered(req, health, handler, m, service)
    resp = first(out)
    http_respond(req, get(resp, :status), get(resp, :headers), get(resp, :body))
    write_stderr(
      "kyuuji: #{get(req, :method)} #{get(req, :path)} #{to_s(get(resp, :status))}\n"
    )
    second(out)
  end
end

def serve_metered(addr, health, handler, service)
  l = http_listen(addr)
  write_stderr(
    "kyuuji: listening on #{addr}, health #{health}, metrics #{metrics_path}\n"
  )
  m = metrics_empty
  while(true, set!(m, serve_metered_once(l, health, handler, 1000, m, service)))
end

def address(settings)
  listen = get(settings, "listen")
  "#{get(listen, "host")}:#{to_s(get(listen, "port"))}"
end

def serve_settings(settings, handler)
  serve(address(settings), get(settings, "health"), handler)
end

def request(method, path, query)
  {method:, path:, query:, headers: [], body: ""}
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
    (_) -> raise(:x, "unreached")
  )
  assert get(r, :status) == 200
  assert get(r, :body) == "ok\n"
end

test "a route answers, an unknown path is 404, a raise is 500"
  assert get(
    answer(request("GET", "/", "who=blue"), "/healthz", hello),
    :body
  ) == "hi blue"
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
  assert query_param(request("GET", "/", "a=1"), "z").nil?
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

test "an empty registry exposes every series at zero"
  text = exposition(metrics_empty, "svc")
  assert contains?(
    text,
    "http_requests_total{service=\"svc\",code=\"5xx\"} 0\n"
  ) == true
  assert contains?(text, "http_request_errors_total{service=\"svc\"} 0\n") ==
    true
  assert contains?(
    text,
    "http_request_duration_seconds_bucket{service=\"svc\",le=\"+Inf\"} 0\n"
  ) == true
  assert contains?(text, "# TYPE http_request_duration_seconds histogram\n") ==
    true
end

test "an observation lands in its class, its buckets and the sum"
  m = observe(observe(metrics_empty, 200, 0.02), 503, 2)
  assert get(get(m, "codes"), "2xx") == 1
  assert get(get(m, "codes"), "5xx") == 1
  assert get(m, "errors") == 1
  assert get(m, "count") == 2
  assert get(m, "sum") == 2.02
  assert get(m, "buckets") == [0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2]
  assert status_class(404) == "4xx"
end

test "the metrics path answers the exposition and is not itself counted"
  m = observe(metrics_empty, 200, 0.001)
  out = metered(request("GET", "/metrics", ""), "/healthz", hello, m, "svc")
  assert get(first(out), :status) == 200
  assert contains?(get(first(out), :body), "code=\"2xx\"} 1\n") == true
  assert second(out) == m
  h = metered(request("GET", "/healthz", ""), "/healthz", hello, m, "svc")
  assert second(h) == m
  b = metered(request("GET", "/boom", ""), "/healthz", hello, m, "svc")
  assert get(first(b), :status) == 500
  assert get(second(b), "errors") == 1
end

def served(path, health, handler)
  l = http_listen("127.0.0.1:0")
  me = self
  port = http_listener_port(l)
  spawn(
    fn()
      r = begin
        http_request(
          "GET",
          "http://127.0.0.1:#{to_s(port)}#{path}",
          nil,
          nil,
          100
        )
      rescue _e
        "gave up"
      end
      send(me, r)
    end
  )
  receive(:_, 2000, :none)
  serve_once(l, health, handler, 2000)
end

test "response is a status, a Content-Type header and a body"
  assert response(201, "text/x", "b") ==
    {status: 201, headers: {"Content-Type" => "text/x"}, body: "b"}
  assert response(204, "", "") ==
    {status: 204, headers: {"Content-Type" => ""}, body: ""}
end

test "not_found is a 404 plain text naming the method and the path"
  r = not_found(request("POST", "/a/b", ""))
  assert get(r, :status) == 404
  assert get(r, :body) == "no route for POST /a/b\n"
  assert get(get(r, :headers), "Content-Type") == "text/plain; charset=utf-8"
  assert get(not_found(request("GET", "", "")), :body) == "no route for GET \n"
end

test "serve_once returns nil when no request arrives in the time given"
  l = http_listen("127.0.0.1:0")
  assert serve_once(l, "/healthz", hello, 20).nil?
  assert serve_once(l, "/healthz", hello, 0).nil?
end

test "serve refuses an address it cannot listen on"
  r = serve("no-port-here", "/healthz", hello) rescue "caught"
  assert r == "caught"
  s = serve("", "/healthz", hello) rescue "caught"
  assert s == "caught"
end

test "serve_once answers a queued request with the handler's status and returns it"
  assert served("/?who=z", "/healthz", hello) == 200
  assert served("/other", "/healthz", hello) == 404
end

test "serve_once answers the health path before the handler, and turns a raise or a non-response into a 500"
  assert served("/healthz", "/healthz", (_) -> raise(:x, "unreached")) == 200
  assert served("/boom", "/healthz", hello) == 500
  assert served("/nil", "/healthz", hello) == 500
end
