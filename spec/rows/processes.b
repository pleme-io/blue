# blue processes: spawn, mailboxes, links, monitors, supervision and code
# migration (BLUE-GAPS G11). The program is process 0; the processes it starts
# run while it waits. Crash traces and their replay are pinned in
# crates/blue-lang-proc/tests/crash_replay.rs, where a trace can be read back.

row(
  "processes.spawn.runs_a_function",
  join_lines(["me = self", "spawn(fn() send(me, 42) end)", "receive()"]),
  value("42"),
  covers("builtin:spawn", "builtin:self", "builtin:send", "builtin:receive")
)

row(
  "processes.spawn.brings_helpers_and_copies_captures",
  join_lines(
    [
      "def double(x)",
      "  x * 2",
      "end",
      "me = self",
      "k = 20",
      "spawn(fn() send(me, [:r, double(k + 1)]) end)",
      "receive()"
    ]
  ),
  value("[:r, 42]")
)

row(
  "processes.send.refuses_a_function",
  "send(self, fn(x) x end)",
  fails(:eval, "not data")
)

row(
  "processes.receive.selective",
  join_lines(
    [
      "me = self",
      "send(me, :noise)",
      "send(me, [:reply, 1])",
      "[receive([:reply, :_]), receive()]"
    ]
  ),
  value("[[:reply, 1], :noise]")
)

row("processes.receive.timeout", "receive(:_, 10, :late)", value(":late"))

row(
  "processes.receive.deadlock",
  "receive()",
  fails(:eval, "would wait forever")
)

row(
  "processes.alive_and_exit",
  join_lines(
    [
      "p = spawn(fn() receive() end)",
      "a = alive?(p)",
      "exit(p, :kill)",
      "[a, alive?(p)]"
    ]
  ),
  value("[true, false]"),
  covers("builtin:alive?", "builtin:exit")
)

row(
  "processes.spawn_link.crash_reaches_the_program",
  join_lines(["spawn_link(fn() raise(:x, \"boom\") end)", "receive()"]),
  fails(:eval, "linked process 1 exited"),
  covers("builtin:spawn_link")
)

row(
  "processes.link_and_unlink",
  join_lines(
    ["p = spawn(fn() receive() end)", "[link(p), unlink(p), link(999)]"]
  ),
  value("[true, true, false]"),
  covers("builtin:link", "builtin:unlink")
)

row(
  "processes.trap_exit",
  join_lines(
    [
      "trap_exit(true)",
      "spawn_link(fn() raise(:x, \"boom\") end)",
      "m = receive()",
      "[nth(0, m), nth(1, m)]"
    ]
  ),
  value("[:exit, 1]"),
  covers("builtin:trap_exit")
)

row(
  "processes.monitor",
  join_lines(["p = spawn(fn() 1 end)", "m = monitor(p)", "receive()"]),
  value("[:down, 1, 1, :normal]"),
  covers("builtin:monitor")
)

row(
  "processes.demonitor",
  join_lines(
    [
      "p = spawn(fn() receive() end)",
      "m = monitor(p)",
      "demonitor(m)",
      "exit(p, :kill)",
      "receive(:_, 10, :quiet)"
    ]
  ),
  value(":quiet"),
  covers("builtin:demonitor")
)

row(
  "processes.supervisor.restarts_a_crashed_child",
  join_lines(
    [
      "def child(parent)",
      "  send(parent, :up)",
      "  if receive() == :crash",
      "    raise(:asked, \"crash\")",
      "  end",
      "end",
      "me = self",
      "sup = supervisor(:one_for_one, [[child, [me]]], 3)",
      "c = nth(0, children(sup))",
      "receive(:up)",
      "send(c, :crash)",
      "receive(:up)"
    ]
  ),
  value(":up"),
  covers("builtin:supervisor", "builtin:children")
)

row(
  "processes.spawn_server",
  join_lines(
    [
      "def h(msg, n)",
      "  if list?(msg)",
      "    send(nth(1, msg), n)",
      "    n",
      "  else",
      "    n + msg",
      "  end",
      "end",
      "s = spawn_server(h, 1)",
      "send(s, 2)",
      "send(s, [:get, self])",
      "receive()"
    ]
  ),
  value("3"),
  covers("builtin:spawn_server")
)

row(
  "processes.defmigrate.keeps_the_mailbox_and_migrates_state",
  join_lines(
    [
      "def h(msg, n)",
      "  if list?(msg)",
      "    send(nth(1, msg), n)",
      "    n",
      "  else",
      "    n + msg",
      "  end",
      "end",
      "def h2(msg, n)",
      "  if list?(msg)",
      "    send(nth(1, msg), [:v2, n])",
      "    n",
      "  else",
      "    n + 2 * msg",
      "  end",
      "end",
      "s = spawn_server(h, 1)",
      "send(s, 2)",
      "r = defmigrate(h, h2, fn(n) n * 10 end)",
      "send(s, [:get, self])",
      "[r, receive()]"
    ]
  ),
  value("[[[1, :ok]], [:v2, 14]]"),
  covers("builtin:defmigrate")
)

row(
  "processes.exit_with.not_a_status",
  "exit_with(4294967296)",
  fails(:eval, "is not a process exit status"),
  covers("builtin:exit_with"),
  host()
)

row(
  "processes.spawn_server.idle_answers_as_normal_does",
  join_lines(
    [
      "def h(msg, n)",
      "  if list?(msg)",
      "    send(nth(1, msg), n)",
      "    n",
      "  else",
      "    n + msg",
      "  end",
      "end",
      "s = spawn_server(h, 1, {scheduling: :idle})",
      "send(s, 2)",
      "send(s, [:get, self])",
      "receive()"
    ]
  ),
  value("3"),
  host()
)

row(
  "processes.spawn_server.realtime_is_refused_by_name",
  join_lines(
    [
      "def h(msg, n)",
      "  n",
      "end",
      "",
      "begin",
      "  spawn_server(h, 0, {scheduling: :realtime})",
      "rescue :permission_denied as e",
      "  [e.kind, contains?(e.message, \"privileged\")]",
      "end"
    ]
  ),
  value("[:permission_denied, true]")
)

row(
  "processes.spawn_server.dispatch_steps_refuses_a_long_message_and_keeps_the_state",
  join_lines(
    [
      "def spin(k)",
      "  if k == 0",
      "    0",
      "  else",
      "    spin(k - 1)",
      "  end",
      "end",
      "",
      "def h(msg, n)",
      "  if list?(msg)",
      "    send(nth(0, msg), n)",
      "    n",
      "  elsif msg == 0",
      "    spin(5000)",
      "    n + 1000",
      "  else",
      "    n + msg",
      "  end",
      "end",
      "",
      "sup = supervisor(:one_for_one, [[:server, h, 0, {dispatch_steps: 2000}]])",
      "s = nth(0, children(sup))",
      "send(s, 1)",
      "send(s, 2)",
      "monitor(s)",
      "send(s, 0)",
      "receive(%i[down _ _ _])",
      "send(s, 5)",
      "send(s, [self])",
      "receive()"
    ]
  ),
  value("8")
)

row(
  "processes.spawn_server.dispatch_steps_is_a_positive_integer",
  join_lines(
    [
      "def h(msg, n)",
      "  n",
      "end",
      "",
      "begin",
      "  spawn_server(h, 0, {dispatch_steps: 0})",
      "rescue :bad_option as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":bad_option")
)

row(
  "processes.spawn.a_class_blue_does_not_know_is_refused",
  join_lines(
    [
      "def w()",
      "  1",
      "end",
      "",
      "begin",
      "  spawn(w, [], {scheduling: :fast})",
      "rescue :bad_option as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":bad_option")
)
