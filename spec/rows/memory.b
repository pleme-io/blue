row(
  "memory.last_use.straight_line",
  join_lines(["def f(x)", "  y = x + 1", "  y * x", "end"]),
  facts(["f: last_use y (* y x)", "f: last_use x (* y x)"])
)

row(
  "memory.last_use.read_twice_in_one_call",
  join_lines(["def sq(x)", "  x * x", "end"]),
  facts(["sq: last_use x (* x x)"])
)

row(
  "memory.last_use.per_branch",
  join_lines(
    ["def g(c, s)", "  if c", "    size(s)", "  else", "    0", "  end", "end"]
  ),
  facts(["g: last_use c (if c (size s) 0)", "g: last_use s (size s)"])
)

row(
  "memory.last_use.never_read",
  join_lines(["def k(x)", "  1", "end"]),
  facts([])
)

# Memory rows (docs/PURE-BLUE.md C2, invariant I3): a run leaves nothing live.
# leaks(N) runs the program once to warm the evaluator, then three more times,
# and reads the counting allocator's bytes retained per run.

row(
  "memory.a_built_list_is_freed",
  join_lines(["xs = map((i) -> [i, i * 2], range(0, 200))", "length(xs)"]),
  leaks(0)
)

row(
  "memory.a_closure_and_its_captures_are_freed",
  join_lines(["k = 3", "add = (x) -> x + k", "length(map(add, range(0, 50)))"]),
  leaks(0)
)

row(
  "memory.a_cell_is_freed",
  join_lines(
    ["c = cell([1, 2, 3])", "cell_put(c, [4])", "length(cell_get(c))"]
  ),
  leaks(0)
)

row(
  "memory.a_dispatch_handler_closure_is_freed",
  join_lines(
    [
      "space_for(:map, \"m\")",
      "verb_for(\"m\", \"has?\", (m, k) -> get(m, k) != nil)",
      "has?({a: 1}, :a)"
    ]
  ),
  leaks(0)
)

row(
  "memory.a_memoized_function_is_freed",
  join_lines(["f = memoize(fn(x) x * x end)", "[f(3), f(3)]"]),
  leaks(0)
)

row(
  "memory.a_closure_kept_by_a_closure_is_freed",
  join_lines(
    ["mk = fn(h) fn(x) h(x) end end", "f = mk(fn(y) y + 1 end)", "f(2)"]
  ),
  leaks(0)
)

row(
  "memory.closes_at.a_listener_left_open_closes_when_the_run_ends",
  join_lines(["l = tcp_listen(\"127.0.0.1:0\")", "tcp_port(l) > 0"]),
  closes_at(:end),
  host()
)

row(
  "memory.closes_at.a_connection_closed_by_hand_closes_at_once",
  join_lines(
    [
      "l = tcp_listen(\"127.0.0.1:0\")",
      "c = tcp_connect(concat(\"127.0.0.1:\", tcp_port(l)), 1000)",
      "tcp_close(c)",
      "tcp_close(l)",
      "true"
    ]
  ),
  closes_at(:end),
  host()
)

row(
  "memory.closes_at.an_accepted_connection_left_open_closes_when_the_run_ends",
  join_lines(
    [
      "l = tcp_listen(\"127.0.0.1:0\")",
      "c = tcp_connect(concat(\"127.0.0.1:\", tcp_port(l)), 1000)",
      "net_wait([[l, :read]], 1000)",
      "s = tcp_accept(l)",
      "s != nil"
    ]
  ),
  closes_at(:end),
  host()
)

row(
  "memory.closes_at.an_http_listener_left_open_closes_when_the_run_ends",
  join_lines(["l = http_listen(\"127.0.0.1:0\")", "http_listener_port(l) > 0"]),
  closes_at(:end),
  host()
)

row(
  "memory.closes_at.a_wire_left_open_closes_when_the_run_ends",
  join_lines(["w = flash_open(\"127.0.0.1:0\")", "w != nil"]),
  closes_at(:end),
  host()
)

row(
  "memory.closes_at.a_wire_closed_by_hand_closes_at_once",
  join_lines(["w = flash_open(\"127.0.0.1:0\")", "flash_close(w)", "true"]),
  closes_at(:end),
  host()
)
