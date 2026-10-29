@moduledoc """
bougyo (防御) — the request-side defence of a service: security headers, a request id, and limits on what a request may be.

Three postures for `shisei`, one `kousei` kind each. `headers` and `request_id`
only add to the response, so they run by default. `limits` can refuse a
request, so it carries a `mode` and defaults to "audit": a violation is
recorded and the request goes on until the operator sets "enforce".

Request headers arrive as a list of [name, value] pairs with lowercase names;
response headers are a map. The posture builders take no arguments, so a
service lists them as `[headers_posture, request_id_posture, limits_posture]`.
"""

use("gamen")
use("kousei", %i[field int_in list_of off one_of text tune])
use("kyuuji", %i[header route_methods])
use("moji", [:lower])
use("retsu", %i[contains first is_empty size])
use("shinsuu", %i[bytes_base64 hex_bytes])
use("shisei", %i[gated posture serving])

legacy_names("0.1.1", [%w[request_header kyuuji::header]])

@doc """
has_header?: Whether the response already sets a header, whatever the case of its name.
"""
def has_header?(headers, name)
  any?((p) -> lower(p[0]) == lower(name), map_entries(headers))
end

def with_missing(headers, additions)
  reduce(
    fn(acc, p)
      if has_header?(acc, p[0])
        acc
      else
        assoc(acc, p[0], p[1])
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
    page_security_policy: page_policy_default,
    strict_transport_security: "max-age=31536000; includeSubDomains",
    cache_control: "no-store",
    cross_origin_resource_policy: "same-origin"
  }
end

def page_policy_default()
  "default-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'; img-src 'self'; style-src-attr 'unsafe-inline'"
end

def header_table()
  map(
    (k) -> field(k, text),
    %i[
      content_security_policy
      cache_control
      content_type_options
      cross_origin_resource_policy
      frame_options
      page_security_policy
      referrer_policy
      strict_transport_security
    ]
  )
end

def hash_source(content)
  "'sha256-#{bytes_base64(hex_bytes(digest_hex(:sha256, content)))}'"
end

def hashed(directive, contents)
  if is_empty(contents)
    []
  else
    ["#{directive} #{join(map(hash_source, contents), " ")}"]
  end
end

def page_policy(base, inline)
  join(
    append(
      [base],
      hashed("style-src-elem", inline[:styles] or []),
      hashed("script-src", inline[:scripts] or [])
    ),
    "; "
  )
end

def page?(r)
  starts_with?(downcase(header(r, "content-type") or ""), "text/html")
end

def policy_for(s, r)
  if page?(r)
    page_policy(s[:page_security_policy], r[:inline] or {})
  else
    s[:content_security_policy]
  end
end

def header_pairs(s, r)
  [
    ["X-Content-Type-Options", s[:content_type_options]],
    ["X-Frame-Options", s[:frame_options]],
    ["Referrer-Policy", s[:referrer_policy]],
    ["Content-Security-Policy", policy_for(s, r)],
    ["Strict-Transport-Security", s[:strict_transport_security]],
    ["Cache-Control", s[:cache_control]],
    ["Cross-Origin-Resource-Policy", s[:cross_origin_resource_policy]]
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
            with_missing(r[:headers], header_pairs(settings, r))
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

@doc """
safe_id?: An inbound id is echoed only when it is short and made of safe characters, so
it cannot forge a log line or split a header.
"""
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
          inbound = header(req, settings[:header])
          id = if safe_id?(inbound, settings[:max_length])
            inbound
          else
            set!(counter, [first(counter) + 1])
            "req-#{now_ms}-#{first(counter)}"
          end
          r = handler(assoc(req, :request_id, id))
          assoc(r, :headers, assoc(r[:headers], settings[:header], id))
        end
      end
    end
  )
end

# --- limits ---------------------------------------------------------------

def refusal_response(status, why)
  {status:, headers: {}, body: unlines([why])}
end

@doc """
broken_limit: The first limit a request breaks, as [status, why], or nil.
"""
def broken_limit(settings, req)
  body = req[:body]
  if not contains(settings[:methods], req[:method])
    [405, "#{req[:method]} is not an allowed method"]
  elsif length(req[:path]) > settings[:max_path]
    [414, "the path is longer than #{settings[:max_path]}"]
  elsif size(req[:headers]) > settings[:max_headers]
    [431, "more than #{settings[:max_headers]} request headers"]
  elsif string?(body) and length(body) > settings[:max_body]
    [413, "the body is longer than #{settings[:max_body]}"]
  end
end

def limits_posture()
  posture(
    :limits,
    [
      field(:max_body, int_in(0, 1_073_741_824)),
      field(:max_headers, int_in(1, 1000)),
      field(:max_path, int_in(1, 65536)),
      field(:methods, list_of(one_of(route_methods))),
      field(:mode, one_of(%w[audit enforce]))
    ],
    {
      max_body: 1_048_576,
      max_headers: 100,
      max_path: 2048,
      methods: route_methods,
      mode: "audit"
    },
    fn(settings, sink)
      fn(handler)
        fn(req)
          hit = broken_limit(settings, req)
          if hit.nil?
            handler(req)
          else
            gated(
              settings[:mode],
              sink,
              :limits,
              hit[1],
              refusal_response(hit[0], hit[1]),
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
  {method: "GET", path:, query: "", headers:, body:}
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
  get(resp[:headers], name)
end

test "a bare service gets the seven security headers and keeps its own"
  d = defended([], quiet, ok)
  assert d[:refusals] == []
  r = d[:handler](get_req("/", [], ""))
  assert hdr(r, "X-Content-Type-Options") == "nosniff"
  assert hdr(r, "X-Frame-Options") == "DENY"
  assert hdr(r, "Referrer-Policy") == "no-referrer"
  assert hdr(r, "Cache-Control") == "no-store"
  assert hdr(r, "Cross-Origin-Resource-Policy") == "same-origin"
  assert contains(
    map((p) -> p[0], map_entries(r[:headers])),
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
  r2 = own[:handler](get_req("/", [], ""))
  assert hdr(r2, "cache-control") == "max-age=60"
  assert hdr(r2, "Cache-Control").nil?
end

test "an html page gets the page policy: its inline style and module allowed by hash, inline script never"
  page = fn(_req)
    {
      status: 200,
      headers: {"Content-Type" => "text/html; charset=utf-8"},
      body: "<p>x</p>",
      inline: {styles: ["a"], scripts: ["abc"]}
    }
  end
  r = defended([], quiet, page)[:handler](get_req("/", [], ""))
  assert hdr(r, "Content-Security-Policy") ==
    "#{page_policy_default}; style-src-elem 'sha256-ypeBEsobvcr6wjGzmiPcTaeG7/gUfE5yuYB3ha/uSLs='; script-src 'sha256-ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0='"
  bare = fn(_req)
    {status: 200, headers: {"content-type" => "TEXT/HTML"}, body: ""}
  end
  b = defended([], quiet, bare)[:handler](get_req("/", [], ""))
  assert hdr(b, "Content-Security-Policy") == page_policy_default
  assert not contains?(page_policy_default, "script-src")
  assert hdr(
    defended([], quiet, ok)[:handler](get_req("/", [], "")),
    "Content-Security-Policy"
  ) == "default-src 'none'; frame-ancestors 'none'"
  tuned = defended(
    [tune(:headers, "default", {page_security_policy: "default-src 'self'"})],
    quiet,
    bare
  )
  assert hdr(
    tuned[:handler](get_req("/", [], "")),
    "Content-Security-Policy"
  ) == "default-src 'self'"
end

test "a kyuuji view route served through bougyo carries the hash of its theme's style"
  t = gamen::theme({text: "#2e3440"}, :light)
  app = kyuuji::router(
    [
      kyuuji::route(
        "GET",
        "/",
        (_req) -> gamen::page({title: "x", body: [gamen::view(:p, {}, ["hi"])]})
      )
    ],
    {theme: t}
  )
  h = defended([], quiet, (req) -> kyuuji::dispatch(app, req))[:handler]
  r = h(get_req("/", [], ""))
  assert r[:status] == 200
  assert contains?(r[:body], "<p>hi</p>")
  assert hdr(r, "Content-Security-Policy") ==
    "#{page_policy_default}; style-src-elem #{hash_source(gamen::css(t))}"
end

test "the headers posture can be configured off or tuned, and a bad tune is refused alone"
  off_d = defended([off(:headers, "default")], quiet, ok)
  assert size(off_d[:off]) == 1
  r = off_d[:handler](get_req("/", [], ""))
  assert hdr(r, "X-Frame-Options").nil?
  assert hdr(r, "X-Request-Id") != nil
  tuned = defended(
    [tune(:headers, "default", {frame_options: "SAMEORIGIN"})],
    quiet,
    ok
  )
  assert hdr(tuned[:handler](get_req("/", [], "")), "X-Frame-Options") ==
    "SAMEORIGIN"
  bad = defended([tune(:headers, "default", {frame_options: 7})], quiet, ok)
  assert size(bad[:refusals]) == 1
  assert hdr(bad[:handler](get_req("/", [], "")), "X-Frame-Options") == "DENY"
end

test "a safe inbound request id is echoed and an unsafe one is replaced"
  h = defended([], quiet, ok)[:handler]
  echoed = h(get_req("/", [%w[x-request-id abc-123_X.9]], ""))
  assert hdr(echoed, "X-Request-Id") == "abc-123_X.9"
  forged = h(
    get_req("/", [["x-request-id", join_lines(["a\r", "Set-Cookie: x=1"])]], "")
  )
  assert hdr(forged, "X-Request-Id") != join_lines(["a\r", "Set-Cookie: x=1"])
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
    (req) -> {status: 200, headers: {}, body: req[:request_id]}
  )
  r = seen[:handler](get_req("/", [%w[x-request-id trace-7]], ""))
  assert r[:body] == "trace-7"
end

test "limits in audit record the violation and let the request through"
  hits = [[]]
  note = (name, why) -> set!(hits, [append(first(hits), [[name, why]])])
  d = defended([tune(:limits, "default", {max_body: 5})], note, ok)
  r = d[:handler](get_req("/", [], "0123456789"))
  assert r[:status] == 200
  assert size(first(hits)) == 1
  assert first(hits)[0][0] == :limits
  fine = d[:handler](get_req("/", [], "0123"))
  assert fine[:status] == 200
  assert size(first(hits)) == 1
end

test "limits in enforce refuse with the status that names the limit"
  enforce = fn(fields)
    tune(:limits, "default", assoc(fields, :mode, "enforce"))
  end
  body = defended([enforce({max_body: 5})], quiet, ok)[:handler]
  assert body(get_req("/", [], "0123456789"))[:status] == 413
  assert body(get_req("/", [], "0123"))[:status] == 200
  path = defended([enforce({max_path: 4})], quiet, ok)[:handler]
  assert path(get_req("/toolong", [], ""))[:status] == 414
  heads = defended([enforce({max_headers: 1})], quiet, ok)[:handler]
  assert heads(get_req("/", [%w[a 1], %w[b 2]], ""))[:status] == 431
  verbs = defended([enforce({methods: ["GET"]})], quiet, ok)[:handler]
  post = {method: "POST", path: "/", query: "", headers: [], body: ""}
  assert verbs(post)[:status] == 405
  assert verbs(get_req("/", [], ""))[:status] == 200
end

test "a refused request still carries no stale state and the defaults stand when a limit is malformed"
  bad = defended([tune(:limits, "default", {max_body: -1})], quiet, ok)
  assert size(bad[:refusals]) == 1
  r = bad[:handler](get_req("/", [], "x"))
  assert r[:status] == 200
  worse = defended(
    [tune(:limits, "default", {methods: %w[GET TRACE]})],
    quiet,
    ok
  )
  assert size(worse[:refusals]) == 1
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
  assert d[:refusals] == []
  assert size(d[:off]) == 3
  assert d[:handler](get_req("/", [], "")) == ok(nil)
end
