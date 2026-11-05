@moduledoc """
eigyou (営業, open for business) — what a running service answers, guards and reports.

Eight levels: `eigyou/kyuuji` (the HTTP service loop), `eigyou/bougyo` (the
request-side defence), `eigyou/shisei` (a service's postures), `eigyou/tsuushin`
(URLs and requests), `eigyou/heddaa` (HPACK header fields), `eigyou/tajuu`
(HTTP/2 frames and streams), `eigyou/shihyou` (SLOs as data) and `eigyou/haibi`
(a service rendered into what ships). The root defines nothing; a
`use("eigyou")` brings all eight.

    eigyou::tajuu::error_code(:cancel) #=> 8
"""

test "the root reaches each of its levels by the path below it"
  assert eigyou::kyuuji::address({"listen" => {"host" => "h", "port" => 1}}) ==
    "h:1"
  assert eigyou::bougyo::safe_id?("abc-1", 64)
  assert eigyou::shisei::stack([], (r) -> r)(1) == 1
  assert eigyou::tsuushin::join("http://a.com/b/c", "../d") == "http://a.com/d"
  assert eigyou::heddaa::encode_int(1337, 5, 0) == [31, 154, 10]
  assert eigyou::tajuu::error_code(:cancel) == 8
  assert eigyou::shihyou::defaults["availability"] == 99.5
  assert eigyou::haibi::column_sql("text")[1] == false
end
