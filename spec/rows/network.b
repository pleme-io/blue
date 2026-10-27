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

row(
  "network.tcp_connect_ms.refused_is_an_answer",
  "take(2, tcp_connect_ms(\"127.0.0.1\", 1, 500))",
  value("[:error, :refused]"),
  covers("builtin:tcp_connect_ms"),
  host()
)

row(
  "network.tcp_connect_ms.bad_port",
  "tcp_connect_ms(\"127.0.0.1\", 0, 500)",
  fails(:eval, "port must be 1..=65535"),
  host()
)

row(
  "network.http_listen.bad_address",
  "http_listen(\"no-port-here\")",
  fails(:eval, "cannot listen"),
  covers("builtin:http_listen"),
  host()
)

row(
  "network.http_listener_port.not_a_listener",
  "http_listener_port(:x)",
  fails(:eval, "expected a listener"),
  covers("builtin:http_listener_port"),
  host()
)

row(
  "network.http_next_request.not_a_listener",
  "http_next_request(:x, 0)",
  fails(:eval, "expected a listener"),
  covers("builtin:http_next_request"),
  host()
)

row(
  "network.http_respond.not_a_request",
  "http_respond(:x, 200, nil, nil)",
  fails(:eval, "expected a request"),
  covers("builtin:http_respond"),
  host()
)

row(
  "network.pg_connect.not_postgres",
  "pg_connect(\"mysql://u@h/d\")",
  fails(:eval, "the scheme is postgres://"),
  covers("builtin:pg_connect"),
  host()
)

row(
  "network.pg_query.not_a_connection",
  "pg_query(:db, \"SELECT 1\", [])",
  fails(:eval, "expected a Postgres connection"),
  covers("builtin:pg_query"),
  host()
)

row(
  "network.pg_execute.not_a_connection",
  "pg_execute(:db, \"SELECT 1\")",
  fails(:eval, "expected a Postgres connection"),
  covers("builtin:pg_execute"),
  host()
)

row(
  "network.pg_close.not_a_connection",
  "pg_close(:db)",
  fails(:eval, "expected a Postgres connection"),
  covers("builtin:pg_close"),
  host()
)
