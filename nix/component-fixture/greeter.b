# waive B0086: debt recorded 2026-11-13: the component fixture is served by checks.service-greeter-component-serves, which no test of this file declares yet
# waive B0087: debt recorded 2026-11-13: the component fixture has no test of its binding's shape yet
use("aisatsu", [:salute])
use("eigyou/kyuuji")
use("settei")

def answer(s, req)
  if req[:path] == "/"
    line = salute(settei::setting(s, "greeting"), settei::setting(s, "subject"))
    eigyou::kyuuji::text(200, unlines([line]))
  else
    eigyou::kyuuji::not_found(req)
  end
end

if settei::serving?
  s = settei::current
  eigyou::kyuuji::serve_settings(s, (req) -> answer(s, req))
end

test "the root answers through the project's own salute, and the rest is not found"
  s = {"greeting" => "hi", "subject" => "there", "flags" => {"shout" => false}}
  assert answer(s, eigyou::kyuuji::request("GET", "/", ""))[:status] == 200
  assert answer(s, eigyou::kyuuji::request("GET", "/x", ""))[:status] == 404
end
