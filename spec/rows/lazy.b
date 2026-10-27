# Delayed values and channels. Channels are bound but have no blue spelling
# for put, take or run (G11); those rows state the destination.

row(
  "lazy.delay_force",
  join_lines(["p = delay(1 + 1)", "force(p)"]),
  value("2"),
  covers("builtin:force")
)

row(
  "lazy.once",
  join_lines(
    [
      "n = 0",
      "p = delay(begin(set!(n, n + 1), n))",
      "force(p)",
      "force(p)",
      "n"
    ]
  ),
  value("1")
)

row(
  "lazy.cycle",
  "first(cycle([1, 2]))",
  value("1"),
  covers("builtin:cycle"),
  isolate()
)

row("chan.make", "chan?(chan(2))", value("true"))

row(
  "chan.close",
  join_lines(["ch = chan(1)", "close!(ch)"]),
  value("nil"),
  covers("builtin:close!")
)

row(
  "chan.drain",
  "drain!(chan(1))",
  value("[]"),
  covers("builtin:drain!"),
  isolate()
)

row("chan.go", "go?(go(fn() 1 end))", value("true"), covers("builtin:go"))

row(
  "chan.put_take",
  join_lines(["ch = chan(1)", "put(ch, 1)", "take_from(ch)"]),
  value("1"),
  pending("G11")
)

row(
  "lazy.realize",
  "realize(cycle([]))",
  value("nil"),
  covers("builtin:realize")
)

row(
  "lazy.take_realize",
  "realize(take(2, cycle([1, 2])))",
  value("[1, 2]"),
  pending("G17"),
  isolate()
)

row("lazy.take", "take(2, cycle([1, 2]))", value("[1, 2]"), pending("G17"))
