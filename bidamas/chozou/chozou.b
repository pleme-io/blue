@moduledoc """
chozou (貯蔵, storage) — what a service keeps and reads back.

Three levels: `chozou/teeburu` reads and writes a service's rows in Postgres,
`chozou/kiibariu` caches in Valkey and Redis, and `chozou/sutoriimu` carries
NATS JetStream streams and the outbox. The root defines nothing; a
`use("chozou")` brings all three.
"""

test "the root reaches each of its levels by the path below it"
  assert teeburu::quoted("t") == "\"t\""
  assert kiibariu::versioned_key("o", "h", :order, 1) == "o:vh:order:1"
  assert sutoriimu::api("s", "INFO") == "$JS.API.STREAM.INFO.s"
end
