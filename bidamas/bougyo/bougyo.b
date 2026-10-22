use("kousei", [:field, :int_in, :list_of, :off, :one_of, :text, :tune])
use("retsu", [:contains, :first, :size])
use("shisei", [:gated, :posture, :serving])

# bougyo (防御) — the request-side defence of a service: security headers, a request id, and limits on what a request may be.
#
# Three postures for `shisei`, one `kousei` kind each. `headers` and `request_id`
# only add to the response, so they run by default. `limits` can refuse a
# request, so it carries a `mode` and defaults to "audit": a violation is
# recorded and the request goes on until the operator sets "enforce".
#
# Request headers arrive as a list of [name, value] pairs with lowercase names;
# response headers are a map. The posture builders take no arguments, so a
# service lists them as `[headers_posture, request_id_posture, limits_posture]`.

def lowered(s)
  downcase(s)
end

# The value of a request header, or nil.
def request_header(req, name)
  hit = filter((p) -> nth(0, p) == name, get(req, :headers))
  if size(hit) == 0
    nil
  else
    nth(1, nth(0, hit))
  end
end

# Whether the response already sets a header, whatever the case of its name.
def has_header?(headers, name)
  any?((p) -> lowered(nth(0, p)) == lowered(name), map_entries(headers))
end

def with_missing(headers, additions)
  reduce(
    fn(acc, p)
      if has_header?(acc, nth(0, p))
        acc
      else
        assoc(acc, nth(0, p), nth(1, p))
      end
    end,
    headers,
    additions
  )
end

# --- headers --------------------------------------------------------------

def header_defaults()
  {
    content_type_options: "nosniff",
    frame_options: "DENY",
    referrer_policy: "no-referrer",
    content_security_policy: "default-src 'none'; frame-ancestors 'none'",
    strict_transport_security: "max-age=31536000; includeSubDomains",
    cache_control: "no-store",
    cross_origin_resource_policy: "same-origin"
  }
end

def header_table()
  map(
    (k) -> field(k, text),
    [
      :content_security_policy,
      :cache_control,
      :content_type_options,
      :cross_origin_resource_policy,
      :frame_options,
      :referrer_policy,
      :strict_transport_security
    ]
  )
end

def header_pairs(s)
  [
    ["X-Content-Type-Options", get(s, :content_type_options)],
    ["X-Frame-Options", get(s, :frame_options)],
    ["Referrer-Policy", get(s, :referrer_policy)],
    ["Content-Security-Policy", get(s, :content_security_policy)],
    ["Strict-Transport-Security", get(s, :strict_transport_security)],
    ["Cache-Control", get(s, :cache_control)],
    ["Cross-Origin-Resource-Policy", get(s, :cross_origin_resource_policy)]
  ]
end

def headers_posture()
  posture(
    :headers,
    header_table,
    header_defaults,
    fn(settings, _sink)
      fn(handler)
        fn(req)
          r = handler(req)
          assoc(
            r,
            :headers,
            with_missing(get(r, :headers), header_pairs(settings))
          )
        end
      end
    end
  )
end

# --- request id -----------------------------------------------------------

def id_chars()
  chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
end

# An inbound id is echoed only when it is short and made of safe characters, so
# it cannot forge a log line or split a header.
def safe_id?(s, max)
  if not string?(s)
    false
  elsif length(s) == 0 or length(s) > max
    false
  else
    size(filter((c) -> not contains(id_chars, c), chars(s))) == 0
  end
end

def request_id_posture()
  posture(
    :request_id,
    [field(:header, text), field(:max_length, int_in(8, 128))],
    {header: "X-Request-Id", max_length: 64},
    fn(settings, _sink)
      counter = [0]
      fn(handler)
        fn(req)
          inbound = request_header(req, lowered(get(settings, :header)))
          id = if safe_id?(inbound, get(settings, :max_length))
            inbound
          else
            set!(counter, [first(counter) + 1])
            "req-#{now_ms}-#{first(counter)}"
          end
          r = handler(assoc(req, :request_id, id))
          assoc(
            r,
            :headers,
            assoc(get(r, :headers), get(settings, :header), id)
          )
        end
      end
    end
  )
end

# --- limits ---------------------------------------------------------------

def limit_methods()
  ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
end

def refusal_response(status, why)
  {status: status, headers: {}, body: "#{why}\n"}
end

# The first limit a request breaks, as [status, why], or nil.
def broken_limit(settings, req)
  body = get(req, :body)
  if not contains(get(settings, :methods), get(req, :method))
    [405, "#{get(req, :method)} is not an allowed method"]
  elsif length(get(req, :path)) > get(settings, :max_path)
    [414, "the path is longer than #{get(settings, :max_path)}"]
  elsif size(get(req, :headers)) > get(settings, :max_headers)
    [431, "more than #{get(settings, :max_headers)} request headers"]
  elsif string?(body) and length(body) > get(settings, :max_body)
    [413, "the body is longer than #{get(settings, :max_body)}"]
  end
end

def limits_posture()
  posture(
    :limits,
    [
      field(:max_body, int_in(0, 1_073_741_824)),
      field(:max_headers, int_in(1, 1000)),
      field(:max_path, int_in(1, 65536)),
      field(:methods, list_of(one_of(limit_methods))),
      field(:mode, one_of(["audit", "enforce"]))
    ],
    {
      max_body: 1_048_576,
      max_headers: 100,
      max_path: 2048,
      methods: limit_methods,
      mode: "audit"
    },
    fn(settings, sink)
      fn(handler)
        fn(req)
          hit = broken_limit(settings, req)
          if hit == nil
            handler(req)
          else
            gated(
              get(settings, :mode),
              sink,
              :limits,
              nth(1, hit),
              refusal_response(nth(0, hit), nth(1, hit)),
              () -> handler(req)
            )
          end
        end
      end
    end
  )
end

def ok(_req)
  {status: 200, headers: {"Content-Type" => "text/plain"}, body: "ok"}
end

def get_req(path, headers, body)
  {method: "GET", path: path, query: "", headers: headers, body: body}
end

def defended(declaration, sink, handler)
  serving(
    [headers_posture, request_id_posture, limits_posture],
    declaration,
    sink,
    handler
  )
end

def quiet(_name, _why)
  nil
end

def hdr(resp, name)
  get(get(resp, :headers), name)
end

test "a bare service gets the seven security headers and keeps its own"
  d = defended([], quiet, ok)
  assert get(d, :refusals) == []
  r = get(d, :handler)(get_req("/", [], ""))
  assert hdr(r, "X-Content-Type-Options") == "nosniff"
  assert hdr(r, "X-Frame-Options") == "DENY"
  assert hdr(r, "Referrer-Policy") == "no-referrer"
  assert hdr(r, "Cache-Control") == "no-store"
  assert hdr(r, "Cross-Origin-Resource-Policy") == "same-origin"
  assert contains(
    map((p) -> nth(0, p), map_entries(get(r, :headers))),
    "Strict-Transport-Security"
  )
  assert hdr(r, "Content-Type") == "text/plain"
  own = defended(
    [],
    quiet,
    fn(_req)
      {status: 200, headers: {"cache-control" => "max-age=60"}, body: ""}
    end
  )
  r2 = get(own, :handler)(get_req("/", [], ""))
  assert hdr(r2, "cache-control") == "max-age=60"
  assert hdr(r2, "Cache-Control") == nil
end

test "the headers posture can be configured off or tuned, and a bad tune is refused alone"
  off_d = defended([off(:headers, "default")], quiet, ok)
  assert size(get(off_d, :off)) == 1
  r = get(off_d, :handler)(get_req("/", [], ""))
  assert hdr(r, "X-Frame-Options") == nil
  assert hdr(r, "X-Request-Id") != nil
  tuned = defended(
    [tune(:headers, "default", {frame_options: "SAMEORIGIN"})],
    quiet,
    ok
  )
  assert hdr(get(tuned, :handler)(get_req("/", [], "")), "X-Frame-Options") ==
    "SAMEORIGIN"
  bad = defended([tune(:headers, "default", {frame_options: 7})], quiet, ok)
  assert size(get(bad, :refusals)) == 1
  assert hdr(get(bad, :handler)(get_req("/", [], "")), "X-Frame-Options") ==
    "DENY"
end

test "a safe inbound request id is echoed and an unsafe one is replaced"
  h = get(defended([], quiet, ok), :handler)
  echoed = h(get_req("/", [["x-request-id", "abc-123_X.9"]], ""))
  assert hdr(echoed, "X-Request-Id") == "abc-123_X.9"
  forged = h(get_req("/", [["x-request-id", "a\r\nSet-Cookie: x=1"]], ""))
  assert hdr(forged, "X-Request-Id") != "a\r\nSet-Cookie: x=1"
  assert starts_with?(hdr(forged, "X-Request-Id"), "req-")
  long = h(
    get_req(
      "/",
      [["x-request-id", join(map((_) -> "a", range(0, 65)), "")]],
      ""
    )
  )
  assert starts_with?(hdr(long, "X-Request-Id"), "req-")
  fresh = h(get_req("/", [], ""))
  assert starts_with?(hdr(fresh, "X-Request-Id"), "req-")
  blank = h(get_req("/", [["x-request-id", ""]], ""))
  assert starts_with?(hdr(blank, "X-Request-Id"), "req-")
end

test "the request id reaches the handler"
  seen = defended(
    [],
    quiet,
    (req) -> {status: 200, headers: {}, body: get(req, :request_id)}
  )
  r = get(seen, :handler)(get_req("/", [["x-request-id", "trace-7"]], ""))
  assert get(r, :body) == "trace-7"
end

test "limits in audit record the violation and let the request through"
  hits = [[]]
  note = (name, why) -> set!(hits, [append(first(hits), [[name, why]])])
  d = defended([tune(:limits, "default", {max_body: 5})], note, ok)
  r = get(d, :handler)(get_req("/", [], "0123456789"))
  assert get(r, :status) == 200
  assert size(first(hits)) == 1
  assert nth(0, nth(0, first(hits))) == :limits
  fine = get(d, :handler)(get_req("/", [], "0123"))
  assert get(fine, :status) == 200
  assert size(first(hits)) == 1
end

test "limits in enforce refuse with the status that names the limit"
  enforce = fn(fields)
    tune(:limits, "default", assoc(fields, :mode, "enforce"))
  end
  body = get(defended([enforce({max_body: 5})], quiet, ok), :handler)
  assert get(body(get_req("/", [], "0123456789")), :status) == 413
  assert get(body(get_req("/", [], "0123")), :status) == 200
  path = get(defended([enforce({max_path: 4})], quiet, ok), :handler)
  assert get(path(get_req("/toolong", [], "")), :status) == 414
  heads = get(defended([enforce({max_headers: 1})], quiet, ok), :handler)
  assert get(heads(get_req("/", [["a", "1"], ["b", "2"]], "")), :status) == 431
  verbs = get(defended([enforce({methods: ["GET"]})], quiet, ok), :handler)
  post = {method: "POST", path: "/", query: "", headers: [], body: ""}
  assert get(verbs(post), :status) == 405
  assert get(verbs(get_req("/", [], "")), :status) == 200
end

test "a refused request still carries no stale state and the defaults stand when a limit is malformed"
  bad = defended([tune(:limits, "default", {max_body: -1})], quiet, ok)
  assert size(get(bad, :refusals)) == 1
  r = get(bad, :handler)(get_req("/", [], "x"))
  assert get(r, :status) == 200
  worse = defended(
    [tune(:limits, "default", {methods: ["GET", "TRACE"]})],
    quiet,
    ok
  )
  assert size(get(worse, :refusals)) == 1
end

test "with every posture off the handler is untouched"
  d = defended(
    [
      off(:headers, "default"),
      off(:request_id, "default"),
      off(:limits, "default")
    ],
    quiet,
    ok
  )
  assert get(d, :refusals) == []
  assert size(get(d, :off)) == 3
  assert get(d, :handler)(get_req("/", [], "")) == ok(nil)
end
