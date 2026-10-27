---
kind: tutorial
order: 5
summary: declare a service in a Bluefile, write its handler and tests, and see what blue renders from it
---

# A first service

A service is one declaration and one program. The declaration names what the
service needs; blue renders the chart, the settings schema, the image and
the checks from it. This tutorial builds a small copy of
[ola-mundo](https://github.com/pleme-io/ola-mundo), the reference blue service.

Make a directory for the service, and declare it in a `Bluefile`:

```console
$ mkdir hello
$ cd hello
```

```blue file=Bluefile
package("hello", "0.1.0")

service(
  "hello",
  {
    program: "hello.b",
    repository: "ghcr.io/example/hello",
    port: 8080,
    config: {greeting: "Olá", subject: "mundo"}
  }
)

check("hello", "hello.b")
```

The program answers `GET /`. `settei` reads the settings the declaration
gives it, and `kyuuji` serves HTTP:

```blue file=hello.b
use("kyuuji")
use("settei")

def greeting(s, who)
  subject = if who == nil or who == ""
    settei::setting(s, "subject")
  else
    who
  end
  "#{settei::setting(s, "greeting")}, #{subject}!"
end

def handle(s, req)
  if get(req, :method) == "GET" and get(req, :path) == "/"
    kyuuji::text(200, unlines([greeting(s, kyuuji::query_param(req, "who"))]))
  else
    kyuuji::not_found(req)
  end
end

if settei::serving?
  s = settei::current
  kyuuji::serve_settings(s, (req) -> handle(s, req))
end

def settings()
  {"greeting" => "Olá", "subject" => "mundo"}
end

test "the root greets the configured subject"
  r = handle(settings, kyuuji::request("GET", "/", ""))
  assert get(r, :status) == 200
  assert get(r, :body) == unlines(["Olá, mundo!"])
end

test "any other path is not found"
  assert get(handle(settings, kyuuji::request("GET", "/x", "")), :status) ==
    404
end
```

The handler is a function from a request to a response, so the tests call
it directly. Lock the declaration and run the tests:

```console
$ blue lock .
./Bluefile.lock: 0 source(s) pinned
$ blue test hello.b
2 test(s): 2 passed, 0 failed
```

The `haibi` bidama renders the declaration into everything that ships the
service. This program lists the files it would write:

```blue file=../show.b
use("haibi", [:files])
use("retsu", [:first])

m = get(json_read(read_file("hello/Bluefile.lock")), "manifest")
spec = get(get(m, "services"), "hello")
paths = map(first, files("hello", get(m, "version"), spec))
write_stdout(unlines(sort_keyed((p) -> p, paths)))
```

```console
$ cd ..
$ blue show.b
chart/Chart.yaml
chart/files/dashboard.json
chart/templates/NOTES.txt
chart/templates/dashboard.yaml
chart/templates/deployment.yaml
chart/templates/service.yaml
chart/templates/serviceaccount.yaml
chart/templates/slo-rules.yaml
chart/values.schema.json
chart/values.yaml
config/hello.schema.json
config/hello.yaml
```

A real service adds a one-line `flake.nix` (`blue.lib.project { src = ./.; }`,
as ola-mundo has). Then nix builds the image and runs every check:

```console host
$ nix flake check
```

The [how-to guides](../howto/test-and-doctest.md) each do one task from
here.
