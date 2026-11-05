use("eigyou/kyuuji")
use("settei")

def greeting(s, req)
  who = eigyou::kyuuji::query_param(req, "who")
  subject = if who.nil?
    settei::setting(s, "subject")
  else
    who
  end
  text = "#{settei::setting(s, "greeting")}, #{subject}"
  if settei::flag(s, "shout")
    upcase(text)
  else
    text
  end
end

def handle(s, req)
  if req[:path] == "/"
    eigyou::kyuuji::text(200, unlines([greeting(s, req)]))
  else
    eigyou::kyuuji::not_found(req)
  end
end

if settei::serving?
  s = settei::current
  eigyou::kyuuji::serve_settings(s, (req) -> handle(s, req))
end

def settings(shout)
  {"greeting" => "hello", "subject" => "world", "flags" => {"shout" => shout}}
end

test "the root greets the configured subject, or the one asked for"
  assert greeting(settings(false), eigyou::kyuuji::request("GET", "/", "")) ==
    "hello, world"
  assert greeting(
    settings(false),
    eigyou::kyuuji::request("GET", "/", "who=blue")
  ) == "hello, blue"
end

test "the shout flag turns the greeting up"
  assert greeting(settings(true), eigyou::kyuuji::request("GET", "/", "")) ==
    "HELLO, WORLD"
end

test "anything but the root is not found"
  assert get(
    handle(settings(false), eigyou::kyuuji::request("GET", "/x", "")),
    :status
  ) == 404
end
