# A web site rendered on the server
#
# BLUE_SITE=127.0.0.1:8080 blue run examples/13_web_site.b serves it.
use("bougyo", [:defended])
use("gamen", [:page, :theme, :view])

use(
  "kyuuji",
  [:answer, :dispatch, :param, :redirect, :request, :route, :router, :serve]
)

use("shisei", [:silent])

def shell(title, body)
  page(
    {
      title:,
      body: [
        view(
          :main,
          {},
          [
            view(
              :nav,
              {},
              [
                view(:a, {href: "/"}, ["home"]),
                view(:a, {href: "/about"}, ["about"])
              ]
            ),
            body
          ]
        )
      ]
    }
  )
end

def site()
  router(
    [
      route(
        "GET",
        "/",
        fn(_req)
          shell(
            "blue",
            [view(:h1, {}, ["blue"]), view(:p, {}, ["one file, served"])]
          )
        end
      ),
      route(
        "GET",
        "/about",
        (_req) -> shell("about", [view(:h1, {}, ["about"])])
      ),
      route(
        "GET",
        "/u/:name",
        fn(req)
          shell(
            param(req, "name"),
            [view(:h1, {}, ["hello #{param(req, "name")}"])]
          )
        end
      ),
      route("GET", "/home", (_req) -> redirect(301, "/"))
    ],
    {theme: theme({text: "#2e3440", surface: "#eceff4"}, :light)}
  )
end

def handler()
  app = site
  defended([], silent, (req) -> dispatch(app, req))[:handler]
end

def visit(method, path)
  answer(request(method, path, ""), "/healthz", handler)
end

addr = getenv("BLUE_SITE")

if addr != nil
  serve(addr, "/healthz", handler)
end

test "each route answers a page of its own"
  home = visit("GET", "/")
  assert home[:status] == 200
  assert contains?(home[:body], "<h1>blue</h1>")
  assert contains?(visit("GET", "/about")[:body], "<h1>about</h1>")
  assert contains?(visit("GET", "/u/ana")[:body], "<h1>hello ana</h1>")
  assert contains?(
    visit("GET", "/u/%3Cb%3E")[:body],
    "<h1>hello &lt;b&gt;</h1>"
  )
end

test "a page carries the security headers and a policy with no inline script"
  csp = visit("GET", "/")[:headers]["Content-Security-Policy"]
  assert contains?(csp, "default-src 'none'")
  assert contains?(csp, "style-src-elem 'sha256-")
  assert not contains?(csp, "script-src")
  assert visit("GET", "/")[:headers]["X-Frame-Options"] == "DENY"
end

test "a moved path redirects, a missing one is 404, a wrong method 405"
  moved = visit("GET", "/home")
  assert moved[:status] == 301
  assert moved[:headers]["Location"] == "/"
  assert visit("GET", "/nope")[:status] == 404
  assert visit("POST", "/about")[:status] == 405
end
