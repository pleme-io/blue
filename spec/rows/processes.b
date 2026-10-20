# blue processes: spawn, mailboxes, links, monitors, supervision and code
# migration (BLUE-GAPS G11). The program is process 0; the processes it starts
# run while it waits. Crash traces and their replay are pinned in
# crates/blue-lang-proc/tests/crash_replay.rs, where a trace can be read back.

row(
  "processes.spawn.runs_a_function",
  "me = self\nspawn(fn() send(me, 42) end)\nreceive()",
  value("42"),
  covers("builtin:spawn", "builtin:self", "builtin:send", "builtin:receive")
)

row(
  "processes.spawn.brings_helpers_and_copies_captures",
  "def double(x)\n  x * 2\nend\nme = self\nk = 20\nspawn(fn() send(me, [:r, double(k + 1)]) end)\nreceive()",
  value("[:r, 42]")
)

row(
  "processes.send.refuses_a_function",
  "send(self, fn(x) x end)",
  fails(:eval, "not data")
)

row(
  "processes.receive.selective",
  "me = self\nsend(me, :noise)\nsend(me, [:reply, 1])\n[receive([:reply, :_]), receive()]",
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
  "p = spawn(fn() receive() end)\na = alive?(p)\nexit(p, :kill)\n[a, alive?(p)]",
  value("[true, false]"),
  covers("builtin:alive?", "builtin:exit")
)

row(
  "processes.spawn_link.crash_reaches_the_program",
  "spawn_link(fn() raise(:x, \"boom\") end)\nreceive()",
  fails(:eval, "linked process 1 exited"),
  covers("builtin:spawn_link")
)

row(
  "processes.link_and_unlink",
  "p = spawn(fn() receive() end)\n[link(p), unlink(p), link(999)]",
  value("[true, true, false]"),
  covers("builtin:link", "builtin:unlink")
)

row(
  "processes.trap_exit",
  "trap_exit(true)\nspawn_link(fn() raise(:x, \"boom\") end)\nm = receive()\n[nth(0, m), nth(1, m)]",
  value("[:exit, 1]"),
  covers("builtin:trap_exit")
)

row(
  "processes.monitor",
  "p = spawn(fn() 1 end)\nm = monitor(p)\nreceive()",
  value("[:down, 1, 1, :normal]"),
  covers("builtin:monitor")
)

row(
  "processes.demonitor",
  "p = spawn(fn() receive() end)\nm = monitor(p)\ndemonitor(m)\nexit(p, :kill)\nreceive(:_, 10, :quiet)",
  value(":quiet"),
  covers("builtin:demonitor")
)

row(
  "processes.supervisor.restarts_a_crashed_child",
  "def child(parent)\n  send(parent, :up)\n  if receive() == :crash\n    raise(:asked, \"crash\")\n  end\nend\nme = self\nsup = supervisor(:one_for_one, [[child, [me]]], 3)\nc = nth(0, children(sup))\nreceive(:up)\nsend(c, :crash)\nreceive(:up)",
  value(":up"),
  covers("builtin:supervisor", "builtin:children")
)

row(
  "processes.spawn_server",
  "def h(msg, n)\n  if list?(msg)\n    send(nth(1, msg), n)\n    n\n  else\n    n + msg\n  end\nend\ns = spawn_server(h, 1)\nsend(s, 2)\nsend(s, [:get, self])\nreceive()",
  value("3"),
  covers("builtin:spawn_server")
)

row(
  "processes.defmigrate.keeps_the_mailbox_and_migrates_state",
  "def h(msg, n)\n  if list?(msg)\n    send(nth(1, msg), n)\n    n\n  else\n    n + msg\n  end\nend\ndef h2(msg, n)\n  if list?(msg)\n    send(nth(1, msg), [:v2, n])\n    n\n  else\n    n + 2 * msg\n  end\nend\ns = spawn_server(h, 1)\nsend(s, 2)\nr = defmigrate(h, h2, fn(n) n * 10 end)\nsend(s, [:get, self])\n[r, receive()]",
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
