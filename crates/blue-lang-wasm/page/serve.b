@moduledoc """
serve: the blue service that serves a page running the blue engine. The page is rendered here; its one script is burauza's engine row; the engine and the program's sources are files this service names by environment, built beside it.

    BLUE_PAGE_SITE=127.0.0.1:8080 BLUE_PAGE_WASM=blue_lang_wasm.wasm BLUE_PAGE_BUNDLE=app.json blue run crates/blue-lang-wasm/page/serve.b
"""

use("burauza", %i[engine_policy loader])

use("eigyou/bougyo", %i[defended page_policy_default])

use(
  "eigyou/kyuuji",
  %i[answer dispatch file request response route router serve]
)

use("eigyou/shisei", [:silent])

use("gamen", %i[page view])

use("kousei", [:tune])

@doc """
mount: the element the engine renders into, naming where it reads the engine and the sources.

    mount[:props][:data_seam] #=> "engine"
"""
def mount()
  view(
    :main,
    {
      data_seam: "engine",
      data_value: json_stringify({wasm: "/blue.wasm", bundle: "/app.json"})
    },
    []
  )
end

def named_file(var, content_type)
  path = getenv(var)
  if path.nil?
    response(
      404,
      "text/plain; charset=utf-8",
      unlines(["#{var} names no file"])
    )
  else
    file(path, {content_type:})
  end
end

def site()
  router(
    [
      route(
        "GET",
        "/",
        fn(_req)
          page(
            {
              title: "blue in the page",
              body: [mount, view(:pre, {data_seam: "receipt"}, [])]
            }
          )
        end
      ),
      route(
        "GET",
        "/engine.js",
        fn(_req)
          response(200, "text/javascript; charset=utf-8", loader([:engine]))
        end
      ),
      route(
        "GET",
        "/blue.wasm",
        (_req) -> named_file("BLUE_PAGE_WASM", "application/wasm")
      ),
      route(
        "GET",
        "/app.json",
        (_req) -> named_file("BLUE_PAGE_BUNDLE", "application/json")
      )
    ],
    {shell: {script: "/engine.js"}}
  )
end

def handler()
  app = site
  get(
    defended(
      [
        tune(
          :headers,
          "default",
          {page_security_policy: engine_policy(page_policy_default)}
        )
      ],
      silent,
      (req) -> dispatch(app, req)
    ),
    :handler
  )
end

def visit(path)
  answer(request("GET", path, ""), "/healthz", handler)
end

addr = getenv("BLUE_PAGE_SITE")

if addr != nil
  serve(addr, "/healthz", handler)
end

test "the page holds the mount, the receipt and the one script, and no inline script"
  home = visit("/")
  assert home[:status] == 200
  assert contains?(home[:body], "data-seam=\"engine\"")
  assert contains?(home[:body], "data-seam=\"receipt\"")
  assert contains?(home[:body], "<script src=\"/engine.js\" defer></script>")
  csp = home[:headers]["Content-Security-Policy"]
  assert contains?(csp, "script-src 'self' 'wasm-unsafe-eval'")
  assert contains?(csp, "connect-src 'self'")
  assert not contains?(csp, "'unsafe-eval'")
end

test "the script is burauza's engine row, and a file the environment does not name is 404"
  js = visit("/engine.js")
  assert js[:status] == 200
  assert contains?(js[:body], "blue_run_bundle")
  assert starts_with?(js[:headers]["Content-Type"], "text/javascript")
  if getenv("BLUE_PAGE_WASM").nil?
    assert visit("/blue.wasm")[:status] == 404
  end
end
