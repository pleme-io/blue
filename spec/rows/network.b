# The network: NATS and HTTP over TCP. Each row is host(). A row runs with no
# peer, so it states what blue promises without one: a refused connection
# raises naming the primitive, a handle of the wrong kind is refused, and https
# is refused rather than sent in the clear. The exchanges themselves run
# against a real nats-server and a TCP listener in
# crates/blue-lang-runtime/tests/net.rs.

row(
  "network.nats_connect.refused",
  "nats_connect(\"nats://127.0.0.1:1\", 500)",
  fails(:eval, "nats_connect"),
  covers("builtin:nats_connect"),
  host()
)

row(
  "network.nats_publish.not_a_connection",
  "nats_publish(\"bus\", \"home.light\", \"on\")",
  fails(:eval, "expected a NATS connection"),
  covers("builtin:nats_publish"),
  host()
)

row(
  "network.nats_request.not_a_connection",
  "nats_request(nil, \"svc.echo\", \"hi\", 100)",
  fails(:eval, "expected a NATS connection"),
  covers("builtin:nats_request"),
  host()
)

row(
  "network.nats_subscribe.not_a_connection",
  "nats_subscribe(1, \"home.>\")",
  fails(:eval, "expected a NATS connection"),
  covers("builtin:nats_subscribe"),
  host()
)

row(
  "network.nats_next_message.not_a_subscription",
  "nats_next_message(\"sub\", 0)",
  fails(:eval, "expected a subscription"),
  covers("builtin:nats_next_message"),
  host()
)

row(
  "network.nats_unsubscribe.not_a_subscription",
  "nats_unsubscribe([])",
  fails(:eval, "expected a subscription"),
  covers("builtin:nats_unsubscribe"),
  host()
)

row(
  "network.nats_close.not_a_connection",
  "nats_close(:bus)",
  fails(:eval, "expected a NATS connection"),
  covers("builtin:nats_close"),
  host()
)

row(
  "network.http_request.https_refused",
  "http_request(\"GET\", \"https://127.0.0.1/\", nil, nil, 500)",
  fails(:eval, "https is not supported"),
  covers("builtin:http_request"),
  host()
)
