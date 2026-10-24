use("gamen", [:css, :element?, :render, :url_ok?])

use(
  "kousei",
  [:field, :flag, :int_in, :list_of, :one_of, :overlay, :record_whys, :required]
)

use("kyohi", [:refusal])
use("retsu", [:first, :is_empty, :last, :rest])
use("shinsuu", [:bytes_base64, :hex_bytes])
use("tesuto", [:raises?])

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
      dispatch(handler, req)
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
    resp = wire(answer(req, health, handler))
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
      blue::zip(latency_bounds, get(m, "buckets"))
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
    blue::zip(latency_bounds, get(m, "buckets"))
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
    resp = wire(first(out))
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

def header(req, name)
  n = downcase(name)
  hs = get(req, :headers)
  pairs = if map?(hs)
    map_entries(hs)
  else
    hs or []
  end
  hit = find(pairs, (p) -> downcase(first(p)) == n)
  if hit.nil?
    nil
  else
    second(hit)
  end
end

def decoded(text)
  parts = split(text, "%")
  bytes = reduce(
    fn(acc, part)
      b = hex_bytes(join(take(2, chars(part)), ""))
      if count(chars(part)) >= 2 and b != nil
        append(acc, b, text_bytes(join(drop(2, chars(part)), "")))
      else
        append(acc, text_bytes("%#{part}"))
      end
    end,
    text_bytes(first(parts)),
    rest(parts)
  )
  bytes_text(bytes) or text
end

def form_decoded(text)
  decoded(replace(text, "+", " "))
end

def route_methods()
  ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
end

def segments(path)
  if path == "/" or path == ""
    []
  else
    rest(split(path, "/"))
  end
end

def segment(part)
  tail = join(drop(1, chars(part)), "")
  if starts_with?(part, ":")
    {param: tail}
  elsif starts_with?(part, "*")
    {rest: tail}
  else
    {literal: part}
  end
end

def bound_name(s)
  get(s, :param) or get(s, :rest)
end

def route_fault(r)
  pattern = get(r, :pattern)
  if not member?(get(r, :method), route_methods)
    "method #{to_s(get(r, :method))} is not one of #{join(route_methods, ", ")}"
  elsif not string?(pattern) or not starts_with?(pattern, "/")
    "pattern #{to_s(pattern)} does not start with /"
  elsif get(r, :handler).nil?
    "#{pattern} has no handler"
  else
    segs = get(r, :segments)
    names = filter((n) -> n != nil, map(bound_name, segs))
    if any?((s) -> get(s, :literal) == "", segs)
      "#{pattern} has an empty segment"
    elsif member?("", names)
      "#{pattern} has a parameter with no name"
    elsif any?((s) -> get(s, :rest) != nil, drop_last(segs))
      "#{pattern} has a * segment before its last"
    elsif count(names) != count(distinct(names))
      "#{pattern} names a parameter twice"
    end
  end
end

def drop_last(xs)
  take(blue::max(0, count(xs) - 1), xs)
end

def route(method, pattern, handler)
  segs = if string?(pattern)
    map(segment, segments(pattern))
  else
    []
  end
  {method:, pattern:, segments: segs, handler:}
end

def splat?(xs)
  not is_empty(xs) and get(first(xs), :rest) != nil
end

def overlapping?(xs, ys)
  if is_empty(xs) and is_empty(ys)
    true
  elsif splat?(xs) and not is_empty(ys) or splat?(ys) and not is_empty(xs)
    true
  elsif is_empty(xs) or is_empty(ys)
    false
  else
    a = get(first(xs), :literal)
    b = get(first(ys), :literal)
    if a != nil and b != nil and a != b
      false
    else
      overlapping?(rest(xs), rest(ys))
    end
  end
end

def clash(kept, r)
  find(
    kept,
    fn(k)
      get(k, :method) == get(r, :method) and
        overlapping?(get(k, :segments), get(r, :segments))
    end
  )
end

def router(routes, opts?)
  o = opts or {}
  stray = filter(
    (e) -> not member?(first(e), [:theme, :hydrate]),
    map_entries(o)
  )
  if not is_empty(stray)
    raise(
      :bad_option,
      "router takes theme: and hydrate:, not #{to_s(first(first(stray)))}"
    )
  end
  judged = reduce(
    fn(acc, r)
      why = route_fault(r)
      other = if why.nil?
        clash(get(acc, :routes), r)
      end
      if why != nil
        assoc(
          acc,
          :refusals,
          append(get(acc, :refusals), [refusal(:route, why)])
        )
      elsif other != nil
        assoc(
          acc,
          :refusals,
          append(
            get(acc, :refusals),
            [
              refusal(
                :overlap,
                "#{get(r, :method)} #{get(r, :pattern)} overlaps #{get(other, :pattern)}"
              )
            ]
          )
        )
      else
        assoc(acc, :routes, append(get(acc, :routes), [r]))
      end
    end,
    {routes: [], refusals: []},
    routes
  )
  assoc(judged, :opts, o)
end

def app?(x)
  map?(x) and get(x, :routes) != nil
end

def bind(segs, parts, params)
  if is_empty(segs)
    if is_empty(parts)
      params
    end
  elsif is_empty(parts)
    nil
  else
    s = first(segs)
    if get(s, :rest) != nil
      assoc(params, get(s, :rest), join(map(decoded, parts), "/"))
    elsif get(s, :param) != nil
      if first(parts) != ""
        bind(
          rest(segs),
          rest(parts),
          assoc(params, get(s, :param), decoded(first(parts)))
        )
      end
    elsif get(s, :literal) == first(parts)
      bind(rest(segs), rest(parts), params)
    end
  end
end

def bound(routes, method, parts)
  find(
    map(
      fn(r)
        params = if get(r, :method) == method
          bind(get(r, :segments), parts, {})
        end
        if params != nil
          {route: r, params:}
        end
      end,
      routes
    ),
    (x) -> x != nil
  )
end

def resolve(app, req)
  parts = segments(get(req, :path))
  hit = bound(get(app, :routes), get(req, :method), parts)
  if hit.nil? and get(req, :method) == "HEAD"
    bound(get(app, :routes), "GET", parts)
  else
    hit
  end
end

def allowed(app, path)
  parts = segments(path)
  distinct(
    map(
      (r) -> get(r, :method),
      filter(
        (r) -> bind(get(r, :segments), parts, {}) != nil,
        get(app, :routes)
      )
    )
  )
end

def param(req, name)
  get(get(req, :params) or {}, name) or query_param(req, name)
end

def page_response(app, tree)
  o = get(app, :opts)
  theme = get(o, :theme)
  hydrate = get(o, :hydrate)
  {
    status: 200,
    headers: {"Content-Type" => "text/html; charset=utf-8"},
    body: render(tree, :html, {theme:}),
    inline: {
      styles: if theme.nil?
        []
      else
        [css(theme)]
      end,
      scripts: if hydrate.nil?
        []
      else
        [hydrate]
      end
    }
  }
end

def routed(app, req)
  hit = resolve(app, req)
  if hit.nil?
    allow = allowed(app, get(req, :path))
    if is_empty(allow)
      not_found(req)
    else
      r = text(
        405,
        "#{get(req, :method)} is not allowed on #{get(req, :path)}\n"
      )
      assoc(r, :headers, assoc(get(r, :headers), "Allow", join(allow, ", ")))
    end
  else
    out = get(
      get(hit, :route),
      :handler
    )(assoc(req, :params, get(hit, :params)))
    resp = if element?(out)
      page_response(app, out)
    else
      out
    end
    if get(req, :method) == "HEAD" and well_formed?(resp)
      assoc(resp, :body, "")
    else
      resp
    end
  end
end

def dispatch(handler, req)
  if app?(handler)
    routed(handler, req)
  else
    handler(req)
  end
end

def mount(app, prefix, sub)
  why = route_fault(route("GET", prefix, () -> nil))
  if why != nil or prefix == "/"
    assoc(
      app,
      :refusals,
      append(
        get(app, :refusals),
        [refusal(:mount, "prefix #{to_s(prefix)}: #{why or "is the root"}")]
      )
    )
  else
    moved = map(
      fn(r)
        p = if get(r, :pattern) == "/"
          prefix
        else
          "#{prefix}#{get(r, :pattern)}"
        end
        route(get(r, :method), p, get(r, :handler))
      end,
      get(sub, :routes)
    )
    joined = router(append(get(app, :routes), moved), get(app, :opts))
    assoc(
      joined,
      :refusals,
      append(get(app, :refusals), get(sub, :refusals), get(joined, :refusals))
    )
  end
end

def redirect(status, location)
  if not member?(status, [301, 302, 303, 307, 308])
    raise(
      :bad_option,
      "a redirect is 301, 302, 303, 307 or 308, not #{to_s(status)}"
    )
  end
  if not url_ok?(location)
    raise(
      :bad_option,
      "the location #{to_s(location)} is not https, mailto or a relative path"
    )
  end
  {status:, headers: {"Location" => location}, body: ""}
end

def guard(handler, check)
  fn(req)
    verdict = check(req)
    if verdict.nil? or verdict == true
      dispatch(handler, req)
    elsif verdict == false
      text(403, "forbidden\n")
    elsif well_formed?(verdict)
      verdict
    else
      raise(
        :bad_option,
        "a guard's check answers nil, true, false or a response, not #{to_s(verdict)}"
      )
    end
  end
end

def body(req, format)
  raw = get(req, :body) or ""
  kind = if format == :auto
    t = downcase(header(req, "content-type") or "")
    if starts_with?(t, "application/json")
      :json
    elsif starts_with?(t, "application/x-www-form-urlencoded")
      :form
    elsif starts_with?(t, "text/")
      :text
    else
      raise(:unsupported, "a body of type #{to_s(t)} is not read")
    end
  else
    format
  end
  if kind == :text
    raw
  elsif kind == :json
    begin
      json_parse(raw)
    rescue _e
      raise(:bad_request, "the body is not JSON")
    end
  elsif kind == :form
    reduce(
      fn(acc, part)
        kv = split(part, "=")
        if first(kv) == ""
          acc
        else
          assoc(acc, form_decoded(first(kv)), form_decoded(join(rest(kv), "=")))
        end
      end,
      {},
      split(raw, "&")
    )
  else
    raise(
      :bad_option,
      "body reads :text, :json, :form or :auto, not #{to_s(format)}"
    )
  end
end

def recover_statuses()
  {
    bad_request: 400,
    unauthorized: 401,
    forbidden: 403,
    not_found: 404,
    conflict: 409,
    too_large: 413,
    unsupported: 415,
    timeout: 503
  }
end

def recover(handler)
  fn(req)
    begin
      dispatch(handler, req)
    rescue e
      recovered(e.kind, e.message)
    end
  end
end

def recovered(kind, message)
  code = get(recover_statuses, kind)
  if code.nil?
    text(500, "internal error\n")
  else
    text(code, "#{message}\n")
  end
end

def timeout(handler, ms)
  if not integer?(ms) or ms <= 0
    raise(
      :bad_option,
      "a timeout is a positive whole number of ms, not #{to_s(ms)}"
    )
  end
  fn(req)
    started = now_ms
    resp = dispatch(handler, req)
    if now_ms - started > ms
      text(503, "the handler ran past its #{to_s(ms)} ms deadline\n")
    else
      resp
    end
  end
end

def stream(_req, f, opts?)
  o = opts or {}
  chunks = [[]]
  f((chunk) -> set!(chunks, [append(first(chunks), [to_s(chunk)])]))
  cs = first(chunks)
  {
    status: get(o, :status) or 200,
    headers: {
      "Content-Type" => get(o, :content_type) or "text/plain; charset=utf-8"
    },
    body: join(cs, ""),
    chunks: cs
  }
end

def content_types()
  {
    "css" => "text/css; charset=utf-8",
    "html" => "text/html; charset=utf-8",
    "js" => "text/javascript; charset=utf-8",
    "json" => "application/json",
    "md" => "text/markdown; charset=utf-8",
    "mjs" => "text/javascript; charset=utf-8",
    "svg" => "image/svg+xml",
    "txt" => "text/plain; charset=utf-8",
    "webmanifest" => "application/manifest+json",
    "xml" => "application/xml"
  }
end

def content_type_of(path)
  name = last(split(path, "/"))
  if contains?(name, ".")
    get(content_types, downcase(last(split(name, ".")))) or
      "application/octet-stream"
  else
    "application/octet-stream"
  end
end

def byte_range(spec, total)
  if not starts_with?(spec, "bytes=")
    nil
  else
    r = join(drop(6, chars(spec)), "")
    ends = split(r, "-")
    if contains?(r, ",") or count(ends) != 2
      nil
    elsif first(ends) == ""
      n = to_int(second(ends))
      if n.nil?
        nil
      elsif n <= 0 or total == 0
        :unsatisfiable
      else
        [blue::max(0, total - n), total - 1]
      end
    else
      a = to_int(first(ends))
      b = if second(ends) == ""
        total - 1
      else
        to_int(second(ends))
      end
      if a.nil? or b.nil?
        nil
      elsif a >= total or b < a
        :unsatisfiable
      else
        [a, blue::min(b, total - 1)]
      end
    end
  end
end

def ranged(content, spec, base)
  bytes = text_bytes(content)
  total = count(bytes)
  r = byte_range(spec, total)
  whole = {status: 200, headers: base, body: content}
  if r.nil?
    whole
  elsif r == :unsatisfiable
    {
      status: 416,
      headers: assoc(base, "Content-Range", "bytes */#{to_s(total)}"),
      body: ""
    }
  else
    a = first(r)
    b = second(r)
    part = bytes_text(take(b - a + 1, drop(a, bytes)))
    if part.nil?
      whole
    else
      {
        status: 206,
        headers: assoc(
          base,
          "Content-Range",
          "bytes #{to_s(a)}-#{to_s(b)}/#{to_s(total)}"
        ),
        body: part
      }
    end
  end
end

def file(path, opts?)
  o = opts or {}
  if member?("..", split(path, "/"))
    text(403, "a path with .. is refused\n")
  else
    content = read_file(path) rescue nil
    if content.nil?
      text(404, "no such file\n")
    else
      file_response(path, content, o)
    end
  end
end

def file_response(path, content, o)
  req = get(o, :request) or {headers: []}
  tag = "\"#{join(take(32, chars(digest_hex(:sha256, content))), "")}\""
  base = {
    "Content-Type" => get(o, :content_type) or content_type_of(path),
    "ETag" => tag,
    "Accept-Ranges" => "bytes"
  }
  asked = header(req, "if-none-match")
  spec = header(req, "range")
  if asked != nil and
      (
        asked == "*" or
        member?(tag, map((t) -> blue::trim(t), split(asked, ",")))
      )
    {status: 304, headers: base, body: ""}
  elsif spec.nil?
    {status: 200, headers: base, body: content}
  else
    ranged(content, spec, base)
  end
end

def cors_table()
  [
    required(field(:origins, list_of(kousei::text))),
    field(:methods, list_of(one_of(route_methods))),
    field(:headers, list_of(kousei::text)),
    field(:max_age, int_in(0, 86400)),
    field(:credentials, flag)
  ]
end

def cors_defaults()
  {
    methods: ["GET", "HEAD", "POST"],
    headers: [],
    max_age: 600,
    credentials: false
  }
end

def cors_policy(policy)
  whys = record_whys(cors_table, policy)
  p = if map?(policy)
    overlay(cors_defaults, policy)
  else
    cors_defaults
  end
  all = if is_empty(whys) and
      get(p, :credentials) and
      member?("*", get(p, :origins))
    ["a wildcard origin cannot carry credentials"]
  else
    whys
  end
  if not is_empty(all)
    raise(:bad_option, "cors policy: #{join(all, "; ")}")
  end
  p
end

def cors_headers(p, origin)
  wild = member?("*", get(p, :origins)) and not get(p, :credentials)
  base = {
    "Access-Control-Allow-Origin" => if wild
      "*"
    else
      origin
    end,
    "Vary" => "Origin"
  }
  if get(p, :credentials)
    assoc(base, "Access-Control-Allow-Credentials", "true")
  else
    base
  end
end

def cors(handler, policy)
  p = cors_policy(policy)
  fn(req)
    origin = header(req, "origin")
    allowed = origin != nil and
      (member?("*", get(p, :origins)) or member?(origin, get(p, :origins)))
    asked = header(req, "access-control-request-method")
    if get(req, :method) == "OPTIONS" and asked != nil and origin != nil
      if allowed and member?(asked, get(p, :methods))
        {
          status: 204,
          headers: overlay(
            cors_headers(p, origin),
            {
              "Access-Control-Allow-Methods" => join(get(p, :methods), ", "),
              "Access-Control-Allow-Headers" => join(get(p, :headers), ", "),
              "Access-Control-Max-Age" => to_s(get(p, :max_age))
            }
          ),
          body: ""
        }
      else
        text(403, "cross-origin request refused\n")
      end
    else
      resp = dispatch(handler, req)
      if allowed and well_formed?(resp)
        assoc(
          resp,
          :headers,
          overlay(get(resp, :headers) or {}, cors_headers(p, origin))
        )
      else
        resp
      end
    end
  end
end

def websocket_guid()
  "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
end

def accept_key(key)
  bytes_base64(hex_bytes(digest_hex(:sha1, "#{key}#{websocket_guid}")))
end

def upgrade(req, f)
  key = header(req, "sec-websocket-key")
  up = downcase(header(req, "upgrade") or "")
  conn = downcase(header(req, "connection") or "")
  if get(req, :method) != "GET" or
      up != "websocket" or
      not contains?(conn, "upgrade") or
      key.nil? or
      count(chars(key)) != 24 or
      not ends_with?(key, "==")
    text(400, "not a websocket handshake\n")
  elsif header(req, "sec-websocket-version") != "13"
    r = text(426, "websocket version 13 is the one spoken\n")
    assoc(r, :headers, assoc(get(r, :headers), "Sec-WebSocket-Version", "13"))
  else
    {
      status: 101,
      headers: {
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Accept" => accept_key(key)
      },
      body: "",
      socket: f
    }
  end
end

def wire(resp)
  if get(resp, :socket) != nil
    text(501, "the websocket hand-off needs a host socket seam, not built\n")
  else
    resp
  end
end

def with_headers(req, pairs)
  assoc(req, :headers, pairs)
end

def site()
  router(
    [
      route("GET", "/", (_req) -> text(200, "home")),
      route("GET", "/u/:id", (req) -> text(200, "user #{param(req, "id")}")),
      route(
        "GET",
        "/files/*path",
        (req) -> text(200, "file #{param(req, "path")}")
      ),
      route("POST", "/u/:id", (req) -> text(201, "made #{param(req, "id")}")),
      route("GET", "/page", (_req) -> gamen::view(:p, {}, ["<hi>"]))
    ]
  )
end

test "a request header is found whatever the case of its name"
  r = with_headers(
    request("GET", "/", ""),
    [["content-type", "text/plain"], ["x-a", "1"]]
  )
  assert header(r, "Content-Type") == "text/plain"
  assert header(r, "X-A") == "1"
  assert header(r, "accept").nil?
  assert header(request("GET", "/", ""), "x").nil?
  assert header({method: "GET"}, "x").nil?
  assert header(text(200, ""), "content-type") == "text/plain; charset=utf-8"
end

test "a router keeps sound routes and refuses each bad or overlapping one alone"
  app = router(
    [
      route("GET", "/a/:id", (_req) -> text(200, "a")),
      route("GET", "/a/new", (_req) -> text(200, "new")),
      route("BREW", "/b", (_req) -> text(200, "b")),
      route("GET", "c", (_req) -> text(200, "c")),
      route("GET", "/d//e", (_req) -> text(200, "d")),
      route("GET", "/f/*x/g", (_req) -> text(200, "f")),
      route("GET", "/h/:x/:x", (_req) -> text(200, "h")),
      route("POST", "/a/new", (_req) -> text(200, "post")),
      route("GET", "/z", (_req) -> text(200, "z"))
    ]
  )
  assert map((r) -> get(r, :pattern), get(app, :routes)) ==
    ["/a/:id", "/a/new", "/z"]
  assert map(first, get(app, :refusals)) ==
    [:overlap, :route, :route, :route, :route, :route]
  assert second(first(get(app, :refusals))) == "GET /a/new overlaps /a/:id"
  assert get(router([]), :routes) == []
  assert get(router([]), :refusals) == []
  assert raises?(:bad_option, () -> router([], {colour: 1}))
end

test "resolve binds path parameters, decodes them, and takes a tail with *"
  app = site
  hit = resolve(app, request("GET", "/u/a%20b", ""))
  assert get(get(hit, :route), :pattern) == "/u/:id"
  assert get(hit, :params) == {"id" => "a b"}
  assert get(resolve(app, request("GET", "/files/a/b.css", "")), :params) ==
    {"path" => "a/b.css"}
  assert resolve(app, request("GET", "/files", "")).nil?
  assert resolve(app, request("GET", "/u/", "")).nil?
  assert resolve(app, request("GET", "/u/1/x", "")).nil?
  assert get(get(resolve(app, request("POST", "/u/1", "")), :route), :method) ==
    "POST"
  assert get(get(resolve(app, request("HEAD", "/u/1", "")), :route), :method) ==
    "GET"
  assert get(resolve(app, request("GET", "/", "")), :params) == {}
  assert resolve(router([]), request("GET", "/", "")).nil?
end

test "an app answers its routes, 404 for no path, 405 with Allow for a wrong method"
  app = site
  assert get(answer(request("GET", "/u/7", ""), "/healthz", app), :body) ==
    "user 7"
  assert get(answer(request("POST", "/u/7", ""), "/healthz", app), :status) ==
    201
  missing = answer(request("GET", "/nope", ""), "/healthz", app)
  assert get(missing, :status) == 404
  wrong = answer(request("DELETE", "/u/7", ""), "/healthz", app)
  assert get(wrong, :status) == 405
  assert get(get(wrong, :headers), "Allow") == "GET, POST"
  head = answer(request("HEAD", "/u/7", ""), "/healthz", app)
  assert get(head, :status) == 200
  assert get(head, :body) == ""
  assert param(request("GET", "/u/7", "id=9"), "id") == "9"
end

test "a view route answers html rendered by gamen, its text escaped"
  r = answer(request("GET", "/page", ""), "/healthz", site)
  assert get(r, :status) == 200
  assert get(get(r, :headers), "Content-Type") == "text/html; charset=utf-8"
  assert get(r, :body) == "<p>&lt;hi&gt;</p>"
  assert get(r, :inline) == {styles: [], scripts: []}
  t = gamen::theme({text: "#2e3440"}, :light)
  themed = router(
    [route("GET", "/", (_req) -> gamen::page({title: "x", body: []}))],
    {theme: t, hydrate: "import('/app.js')"}
  )
  page = answer(request("GET", "/", ""), "/healthz", themed)
  assert contains?(get(page, :body), "<style>#{css(t)}</style>")
  assert get(page, :inline) ==
    {styles: [css(t)], scripts: ["import('/app.js')"]}
end

test "mount places a sub-app under a prefix and refuses a bad prefix alone"
  api = router(
    [
      route("GET", "/", (_req) -> text(200, "api root")),
      route("GET", "/v/:n", (req) -> text(200, "v#{param(req, "n")}"))
    ]
  )
  app = mount(site, "/api", api)
  assert get(answer(request("GET", "/api", ""), "/healthz", app), :body) ==
    "api root"
  assert get(answer(request("GET", "/api/v/2", ""), "/healthz", app), :body) ==
    "v2"
  assert get(answer(request("GET", "/u/1", ""), "/healthz", app), :body) ==
    "user 1"
  bad = mount(site, "api/", api)
  assert map(first, get(bad, :refusals)) == [:mount]
  assert get(answer(request("GET", "/u/1", ""), "/healthz", bad), :status) ==
    200
  assert map(first, get(mount(site, "/", api), :refusals)) == [:mount]
  clash = mount(
    site,
    "/u",
    router([route("GET", "/:x", (_req) -> text(200, "x"))])
  )
  assert map(first, get(clash, :refusals)) == [:overlap]
end

test "redirect answers a 3xx with a safe location and refuses anything else"
  r = redirect(303, "/done?x=1")
  assert get(r, :status) == 303
  assert get(get(r, :headers), "Location") == "/done?x=1"
  assert get(r, :body) == ""
  assert get(redirect(301, "https://blue.example/"), :status) == 301
  assert raises?(:bad_option, () -> redirect(200, "/"))
  assert raises?(:bad_option, () -> redirect(302, "//evil.example/"))
  assert raises?(:bad_option, () -> redirect(302, "javascript:alert(1)"))
  assert raises?(:bad_option, () -> redirect(302, "/a\r\nSet-Cookie: x"))
end

test "guard lets nil and true through, answers 403 for false, and passes a refusal response on"
  ok = (_req) -> text(200, "in")
  req = request("GET", "/", "")
  assert get(guard(ok, (_r) -> nil)(req), :body) == "in"
  assert get(guard(ok, (_r) -> true)(req), :body) == "in"
  assert get(guard(ok, (_r) -> false)(req), :status) == 403
  assert get(guard(ok, (_r) -> text(401, "who"))(req), :status) == 401
  assert raises?(:bad_option, () -> guard(ok, (_r) -> 7)(req))
  assert get(guard(site, (_r) -> nil)(request("GET", "/u/3", "")), :body) ==
    "user 3"
end

test "body reads text, json and a form, by name or by Content-Type"
  json = with_headers(
    assoc(request("POST", "/", ""), :body, "{\"a\":[1,2]}"),
    [["content-type", "application/json; charset=utf-8"]]
  )
  assert body(json, :auto) == [["a", [1, 2]]]
  assert body(json, :text) == "{\"a\":[1,2]}"
  form = with_headers(
    assoc(request("POST", "/", ""), :body, "who=a+b&x=%3D%26&&n"),
    [["content-type", "application/x-www-form-urlencoded"]]
  )
  assert body(form, :auto) == {"who" => "a b", "x" => "=&", "n" => ""}
  assert body(request("POST", "/", ""), :text) == ""
  assert body(request("POST", "/", ""), :form) == {}
  bad = assoc(request("POST", "/", ""), :body, "{nope")
  assert raises?(:bad_request, () -> body(bad, :json))
  assert raises?(:unsupported, () -> body(bad, :auto))
  assert raises?(:bad_option, () -> body(bad, :xml))
end

test "recover turns a raised kind into its status and hides an unknown fault"
  boom = (kind) -> recover((_req) -> raise(kind, "said #{to_s(kind)}"))
  req = request("GET", "/", "")
  assert get(boom(:bad_request)(req), :status) == 400
  assert get(boom(:bad_request)(req), :body) == "said bad_request\n"
  assert get(boom(:forbidden)(req), :status) == 403
  assert get(boom(:not_found)(req), :status) == 404
  assert get(boom(:unsupported)(req), :status) == 415
  assert get(boom(:timeout)(req), :status) == 503
  hidden = boom(:secret_detail)(req)
  assert get(hidden, :status) == 500
  assert get(hidden, :body) == "internal error\n"
  assert get(recover((_r) -> text(200, "fine"))(req), :body) == "fine"
  assert get(recover(site)(request("GET", "/u/4", "")), :body) == "user 4"
end

test "timeout answers 503 past its deadline and passes a fast answer through"
  req = request("GET", "/", "")
  slow = fn(_r)
    sleep_ms(60)
    text(200, "late")
  end
  late = timeout(slow, 20)(req)
  assert get(late, :status) == 503
  assert get(late, :body) == "the handler ran past its 20 ms deadline\n"
  assert get(timeout((_r) -> text(200, "quick"), 1000)(req), :body) == "quick"
  assert raises?(:bad_option, () -> timeout(slow, 0))
  assert raises?(:bad_option, () -> timeout(slow, 1.5))
end

test "stream keeps each chunk in order and the body is their join"
  r = stream(
    request("GET", "/", ""),
    fn(emit)
      emit("a")
      emit("b")
      emit(3)
    end,
    {content_type: "text/event-stream"}
  )
  assert get(r, :chunks) == ["a", "b", "3"]
  assert get(r, :body) == "ab3"
  assert get(get(r, :headers), "Content-Type") == "text/event-stream"
  empty = stream(request("GET", "/", ""), (_emit) -> nil)
  assert get(empty, :chunks) == []
  assert get(empty, :body) == ""
  assert get(empty, :status) == 200
end

test "file serves a file with its type and validator, 304 on a match, ranges by byte"
  dir = getenv("TMPDIR", "/tmp")
  path = "#{dir}/kyuuji-file-test.css"
  write_file(path, "body{color:red}")
  r = file(path)
  assert get(r, :status) == 200
  assert get(r, :body) == "body{color:red}"
  assert get(get(r, :headers), "Content-Type") == "text/css; charset=utf-8"
  tag = get(get(r, :headers), "ETag")
  assert tag ==
    "\"#{join(take(32, chars(digest_hex(:sha256, "body{color:red}"))), "")}\""
  again = with_headers(request("GET", "/", ""), [["if-none-match", tag]])
  assert get(file(path, {request: again}), :status) == 304
  part = with_headers(request("GET", "/", ""), [["range", "bytes=5-9"]])
  p = file(path, {request: part})
  assert get(p, :status) == 206
  assert get(p, :body) == "color"
  assert get(get(p, :headers), "Content-Range") == "bytes 5-9/15"
  tail = with_headers(request("GET", "/", ""), [["range", "bytes=-4"]])
  assert get(file(path, {request: tail}), :body) == "red}"
  past = with_headers(request("GET", "/", ""), [["range", "bytes=99-"]])
  assert get(file(path, {request: past}), :status) == 416
  assert get(file("#{dir}/kyuuji-no-such-file"), :status) == 404
  assert get(file("#{dir}/../etc/passwd"), :status) == 403
  assert content_type_of("a/b") == "application/octet-stream"
  assert content_type_of("a/INDEX.HTML") == "text/html; charset=utf-8"
end

test "cors answers an allowed preflight, marks allowed answers, and refuses a bad policy"
  policy = {origins: ["https://app.example"], methods: ["GET", "POST"]}
  h = cors((_r) -> text(200, "data"), policy)
  pre = h(
    with_headers(
      request("OPTIONS", "/", ""),
      [
        ["origin", "https://app.example"],
        ["access-control-request-method", "POST"]
      ]
    )
  )
  assert get(pre, :status) == 204
  assert get(get(pre, :headers), "Access-Control-Allow-Origin") ==
    "https://app.example"
  assert get(get(pre, :headers), "Access-Control-Allow-Methods") == "GET, POST"
  assert get(get(pre, :headers), "Vary") == "Origin"
  stranger = h(
    with_headers(
      request("OPTIONS", "/", ""),
      [
        ["origin", "https://evil.example"],
        ["access-control-request-method", "GET"]
      ]
    )
  )
  assert get(stranger, :status) == 403
  verb = h(
    with_headers(
      request("OPTIONS", "/", ""),
      [
        ["origin", "https://app.example"],
        ["access-control-request-method", "DELETE"]
      ]
    )
  )
  assert get(verb, :status) == 403
  simple = h(
    with_headers(request("GET", "/", ""), [["origin", "https://app.example"]])
  )
  assert get(get(simple, :headers), "Access-Control-Allow-Origin") ==
    "https://app.example"
  other = h(
    with_headers(request("GET", "/", ""), [["origin", "https://evil.example"]])
  )
  assert get(get(other, :headers), "Access-Control-Allow-Origin").nil?
  bare = h(request("GET", "/", ""))
  assert get(bare, :headers) == {"Content-Type" => "text/plain; charset=utf-8"}
  any = cors((_r) -> text(200, "x"), {origins: ["*"]})
  assert get(
    get(
      any(with_headers(request("GET", "/", ""), [["origin", "https://a.b"]])),
      :headers
    ),
    "Access-Control-Allow-Origin"
  ) == "*"
  assert raises?(
    :bad_option,
    () -> cors(h, {origins: ["*"], credentials: true})
  )
  assert raises?(:bad_option, () -> cors(h, {origin: ["x"]}))
  assert raises?(
    :bad_option,
    () -> cors(h, {origins: ["x"], methods: ["BREW"]})
  )
end

test "upgrade answers the RFC 6455 handshake and the wire refuses a hand-off it cannot make"
  req = with_headers(
    request("GET", "/ws", ""),
    [
      ["upgrade", "websocket"],
      ["connection", "keep-alive, Upgrade"],
      ["sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ=="],
      ["sec-websocket-version", "13"]
    ]
  )
  r = upgrade(req, (_socket) -> nil)
  assert get(r, :status) == 101
  assert get(get(r, :headers), "Sec-WebSocket-Accept") ==
    "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
  assert get(get(r, :headers), "Upgrade") == "websocket"
  assert get(wire(r), :status) == 501
  old = with_headers(
    req,
    [
      ["upgrade", "websocket"],
      ["connection", "upgrade"],
      ["sec-websocket-key", "dGhlIHNhbXBsZSBub25jZQ=="],
      ["sec-websocket-version", "8"]
    ]
  )
  assert get(upgrade(old, (_s) -> nil), :status) == 426
  assert get(upgrade(request("GET", "/ws", ""), (_s) -> nil), :status) == 400
  assert get(wire(text(200, "x")), :status) == 200
end

test "serve_once answers a router app over a socket, view routes included"
  assert served("/u/7", "/healthz", site) == 200
  assert served("/page", "/healthz", site) == 200
  assert served("/nope", "/healthz", site) == 404
end
