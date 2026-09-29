# Delayed values and channels. Channels are bound but have no blue spelling
# for put, take or run (G11); those rows state the destination.

row(
  "lazy.delay_force",
  "p = delay(1 + 1)\nforce(p)",
  value("2"),
  covers("builtin:force")
)

row(
  "lazy.once",
  "n = 0\np = delay(begin(set!(n, n + 1), n))\nforce(p)\nforce(p)\nn",
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
  "ch = chan(1)\nclose!(ch)",
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
  "ch = chan(1)\nput(ch, 1)\ntake_from(ch)",
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
