# The dual-pulse wire: the Flash channel (comm_flash, framing byte 0x02) and
# the Tide channel (comm_scavenger, framing byte 0x01) over one UDP socket.
# Each row is host() and runs on loopback with no peer, so it states what blue
# promises without one: a frame past 1280 bytes is refused before it is sent,
# a Flash burst past the wire's rate is refused as :rate_limited, a handle of
# the wrong kind is refused, and a channel not opened on a wire is refused by
# name. The pacing, the loopback provider and the gossip run in
# crates/blue-lang-cli/tests/wire.rs.

row(
  "wire.flash_open.bad_address",
  "flash_open(\"no-port-here\")",
  fails(:eval, "flash_open"),
  covers("builtin:flash_open"),
  host()
)

row(
  "wire.flash_put.past_the_mtu_sends_nothing",
  join_lines(
    [
      "w = flash_open(\"127.0.0.1:0\")",
      "[flash_put(w, \"127.0.0.1:9\", join(map((_i) -> \"x\", range(1279)), \"\")), (flash_put(w, \"127.0.0.1:9\", join(map((_i) -> \"x\", range(1280)), \"\")) rescue :refused), flash_stats(w).sent]"
    ]
  ),
  value("[1280, :refused, 1]"),
  covers("builtin:flash_put"),
  covers("builtin:flash_stats"),
  host()
)

row(
  "wire.flash_put.past_the_rate_refuses_and_counts",
  join_lines(
    [
      "w = flash_open(\"127.0.0.1:0\")",
      "big = join(map((_i) -> \"x\", range(1279)), \"\")",
      "sent = map((_i) -> (flash_put(w, \"127.0.0.1:9\", big) rescue :refused), range(20))",
      "[member?(:refused, sent), flash_stats(w).sent + flash_stats(w).refused, flash_stats(w).rate]"
    ]
  ),
  value("[true, 20, 16384]"),
  host()
)

row(
  "wire.flash_put.past_the_rate_names_it",
  join_lines(
    [
      "w = flash_open(\"127.0.0.1:0\")",
      "big = join(map((_i) -> \"x\", range(1279)), \"\")",
      "",
      "begin",
      "  map((_i) -> flash_put(w, \"127.0.0.1:9\", big), range(20))",
      "rescue :rate_limited as e",
      "  [e.kind, contains?(e.message, \"past the wire's rate\")]",
      "end"
    ]
  ),
  value("[:rate_limited, true]"),
  host()
)

row(
  "wire.flash_next.nothing_came",
  join_lines(["w = flash_open(\"127.0.0.1:0\")", "flash_next(w, 0)"]),
  value("nil"),
  covers("builtin:flash_next"),
  host()
)

row(
  "wire.flash_close.then_refused",
  join_lines(
    ["w = flash_open(\"127.0.0.1:0\")", "flash_close(w)", "flash_next(w, 0)"]
  ),
  fails(:eval, "not open"),
  covers("builtin:flash_close"),
  host()
)

row(
  "wire.tide_open.not_a_wire",
  "tide_open(:x)",
  fails(:eval, "expected an address to bind or a wire to join"),
  covers("builtin:tide_open"),
  host()
)

row(
  "wire.tide_open.ring_below_one_frame",
  "tide_open(\"127.0.0.1:0\", {ring_bytes: 100})",
  fails(:eval, "ring_bytes holds at least one 1280-byte frame"),
  host()
)

row(
  "wire.tide_put.the_ring_evicts_its_oldest",
  join_lines(
    [
      "w = tide_open(\"127.0.0.1:0\", {ring_frames: 2})",
      "[tide_put(w, \"127.0.0.1:9\", \"a\"), tide_put(w, \"127.0.0.1:9\", \"b\"), tide_put(w, \"127.0.0.1:9\", \"c\"), tide_stats(w).queued, tide_stats(w).evicted]"
    ]
  ),
  value("[0, 0, 1, 2, 1]"),
  covers("builtin:tide_put"),
  covers("builtin:tide_stats"),
  host()
)

row(
  "wire.tide_release.only_what_the_window_allows",
  join_lines(
    [
      "w = tide_open(\"127.0.0.1:0\")",
      "tide_put(w, \"127.0.0.1:9\", \"abc\")",
      "tide_put(w, \"127.0.0.1:9\", \"def\")",
      "[tide_release(w, 13, 0), tide_release(w, 11, 0), tide_release(w, 12, 0), tide_stats(w).queued]"
    ]
  ),
  value("[12, 0, 12, 0]"),
  covers("builtin:tide_release"),
  host()
)

row(
  "wire.tide_send.past_the_mtu",
  join_lines(
    [
      "w = tide_open(\"127.0.0.1:0\")",
      "tide_send(w, \"127.0.0.1:9\", join(map((_i) -> \"x\", range(1272)), \"\"), 0)"
    ]
  ),
  fails(:eval, "at most 1280 bytes"),
  covers("builtin:tide_send"),
  host()
)

row(
  "wire.tide_next.nothing_came",
  join_lines(["w = tide_open(\"127.0.0.1:0\")", "tide_next(w, 0)"]),
  value("nil"),
  covers("builtin:tide_next"),
  host()
)

row(
  "wire.tide_close.a_shared_wire_keeps_its_other_channel",
  join_lines(
    [
      "w = flash_open(\"127.0.0.1:0\")",
      "tide_open(w)",
      "tide_close(w)",
      "[flash_next(w, 0), (tide_next(w, 0) rescue :closed)]"
    ]
  ),
  value("[nil, :closed]"),
  covers("builtin:tide_close"),
  host()
)

row(
  "wire.evict.a_server_moves_with_its_waiting_messages",
  join_lines(
    [
      "def h(msg, seen)",
      "  if msg[0] == :inc",
      "    append(seen, [msg[1]])",
      "  else",
      "    send(msg[1], seen)",
      "    seen",
      "  end",
      "end",
      "a = tide_open(\"127.0.0.1:0\")",
      "b = tide_open(\"127.0.0.1:0\")",
      "s = spawn_server(h, [])",
      "send(s, [:inc, 1])",
      "send(s, [:get, self])",
      "before = receive()",
      "send(s, [:inc, 2])",
      "moved = evict(s, a, tide_stats(b).address)",
      "tide_release(a, 1_000_000, 0)",
      "p = accept(b, 5000)",
      "send(p, [:inc, 3])",
      "send(p, [:get, self])",
      "[before, receive(), alive?(s), moved.frames > 0]"
    ]
  ),
  value("[[1], [1, 2, 3], false, true]"),
  covers("builtin:evict"),
  covers("builtin:accept"),
  host()
)

row(
  "wire.evict.a_plain_process_is_refused",
  join_lines(
    [
      "def w(x)",
      "  receive()",
      "end",
      "a = tide_open(\"127.0.0.1:0\")",
      "evict(spawn(w, [1]), a, \"127.0.0.1:9\")"
    ]
  ),
  fails(:eval, "not a server"),
  host()
)

row(
  "wire.accept.nothing_came",
  join_lines(["b = tide_open(\"127.0.0.1:0\")", "accept(b, 0)"]),
  value("nil"),
  host()
)

row(
  "wire.evict.a_supervised_server_is_handed_over",
  join_lines(
    [
      "def h(msg, seen)",
      "  if msg == :boom",
      "    raise(:boom, \"asked to crash\")",
      "  end",
      "  if msg[0] == :inc",
      "    append(seen, [msg[1]])",
      "  else",
      "    send(msg[1], seen)",
      "    seen",
      "  end",
      "end",
      "a = tide_open(\"127.0.0.1:0\")",
      "b = tide_open(\"127.0.0.1:0\")",
      "sup = supervisor(:one_for_one, [[:server, h, [0]]])",
      "s = children(sup)[0]",
      "send(s, [:inc, 1])",
      "evict(s, a, tide_stats(b).address)",
      "tide_release(a, 1_000_000, 0)",
      "p = accept(b, 5000)",
      "send(p, [:get, self])",
      "moved = receive()",
      "send(p, :boom)",
      "receive(:never, 50, :waited)",
      "send(p, [:get, self])",
      "[moved, receive(), children(sup), alive?(s)]"
    ]
  ),
  value("[[0, 1], [0], [], false]"),
  host()
)

row(
  "wire.evict.a_partner_that_traps_exits_hears_the_link_break",
  join_lines(
    [
      "def h(msg, n)",
      "  n",
      "end",
      "a = tide_open(\"127.0.0.1:0\")",
      "s = spawn_server(h, 0)",
      "trap_exit(true)",
      "link(s)",
      "evict(s, a, \"127.0.0.1:9\")",
      "[receive() == [:exit, s, :evicted], alive?(s)]"
    ]
  ),
  value("[true, false]"),
  host()
)

row(
  "wire.evict.a_partner_that_does_not_trap_exits_is_refused",
  join_lines(
    [
      "def h(msg, n)",
      "  n",
      "end",
      "a = tide_open(\"127.0.0.1:0\")",
      "s = spawn_server(h, 0)",
      "link(s)",
      "evict(s, a, \"127.0.0.1:9\")"
    ]
  ),
  fails(:eval, "does not trap exits"),
  host()
)
