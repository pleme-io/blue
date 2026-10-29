space("debaisu?", {status: :provisional})

verb(
  "debaisu?",
  "calibrate",
  {
    kind: :pure,
    shape: "calibrate(sensor, points) -> model",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "fit raw readings to known true values",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "check",
  {
    kind: :pure,
    shape: "check(board, program) -> findings",
    laterals: ["validate"],
    fleet: "kiban",
    today: "absent",
    meaning: "find a pin clash, a missing clock or a bad register use",
    wave: 2,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "close",
  {
    kind: :effect,
    shape: "close(handle) -> nil",
    laterals: %w[idempotent resource],
    fleet: nil,
    today: "absent",
    meaning: "release a bus or device; closed counts as done",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "decode",
  {
    kind: :pure,
    shape: "decode(protocol, bytes) -> record",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "bytes of a frame as a record; bad checksum refused",
    wave: 2,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "encode",
  {
    kind: :pure,
    shape: "encode(protocol, record) -> bytes",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a record as bytes of a bus or radio frame",
    wave: 2,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "flash",
  {
    kind: :effect,
    shape: "flash(image, target, opts) -> nil",
    laterals: %w[capability deadline resource],
    fleet: nil,
    today: "absent",
    meaning: "write an image to a device",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "fuse",
  {
    kind: :pure,
    shape: "fuse(estimates, opts) -> estimate",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "combine several sensor estimates into one",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "list",
  {
    kind: :effect,
    shape: "list(bus) -> addresses",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "devices that answer on a bus",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "monitor",
  {
    kind: :stream,
    shape: "monitor(port, f, opts) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "call f for each line from a device console",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "on",
  {
    kind: :decl,
    shape: "on(source, interrupt, handler) -> nil",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "bind a handler to an interrupt",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "open",
  {
    kind: :effect,
    shape: "open(bus, opts) -> handle",
    laterals: %w[capability resource],
    fleet: nil,
    today: "absent",
    meaning: "take a bus: I2C, SPI, UART, CAN",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "read",
  {
    kind: :effect,
    shape: "read(target, opts) -> value",
    laterals: %w[deadline resource],
    fleet: "kiban",
    today: "rust:kiban",
    meaning: "a pin level or a register value",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "reset",
  {
    kind: :effect,
    shape: "reset(target, opts) -> nil",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "restart a device",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "run",
  {
    kind: :effect,
    shape: "run(image, board, opts) -> trace",
    laterals: %w[deadline process],
    fleet: "kiban",
    today: "rust:kiban",
    meaning: "run an image on an emulated board",
    wave: 2,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "sample",
  {
    kind: :stream,
    shape: "sample(sensor, opts) -> readings",
    laterals: %w[deadline time],
    fleet: nil,
    today: "absent",
    meaning: "readings from a sensor at a rate",
    wave: 3,
    origin: "G",
    contract: "sample(sensor) -> readings"
  }
)

verb(
  "debaisu?",
  "schedule",
  {
    kind: :pure,
    shape: "schedule(tasks) -> table",
    laterals: %w[time validate],
    fleet: nil,
    today: "absent",
    meaning: "prove every task meets its deadline, or name the one that fails",
    wave: 2,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "smooth",
  {
    kind: :pure,
    shape: "smooth(readings, kind, opts) -> readings",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "reduce noise: moving average, median, Kalman",
    wave: 2,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "task",
  {
    kind: :decl,
    shape: "task(period, budget, f) -> task",
    laterals: %w[time validate],
    fleet: nil,
    today: "absent",
    meaning: "declare a periodic task with a time budget",
    wave: 2,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "terminal",
  {
    kind: :decl,
    shape: "terminal(board, name) -> pin",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a pin: name, function, pull, drive",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "transfer",
  {
    kind: :effect,
    shape: "transfer(handle, address, bytes, opts) -> bytes",
    laterals: %w[deadline retry],
    fleet: nil,
    today: "absent",
    meaning: "one bus transaction: write, then read",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "watch",
  {
    kind: :stream,
    shape: "watch(pin, f, opts) -> nil",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "call f on every edge of a pin",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "waveform",
  {
    kind: :decl,
    shape: "waveform(kind, params) -> signal",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a level, pulse train or PWM wave",
    wave: 3,
    origin: "G"
  }
)

verb(
  "debaisu?",
  "write",
  {
    kind: :effect,
    shape: "write(target, value, opts) -> nil",
    laterals: %w[capability resource],
    fleet: "kiban",
    today: "rust:kiban",
    meaning: "drive a pin or set a register",
    wave: 3,
    origin: "G"
  }
)

edge("debaisu?::transfer", :composes, "debaisu?::decode", "parse the reply")
edge("debaisu?::transfer", :composes, "debaisu?::encode", "frame the request")

edge(
  "debaisu?::check",
  :guards,
  "chuuzou::build",
  "catch faults before the image"
)

edge("debaisu?::run", :guards, "debaisu?::flash", "try before real hardware")

edge(
  "debaisu?::schedule",
  :guards,
  "debaisu?::flash",
  "no image with a missed deadline"
)

edge("debaisu?::open", :inverse, "debaisu?::close", "release what open took")
edge("debaisu?::encode", :inverse, "debaisu?::decode", "bytes to record")
edge("debaisu?::decode", :inverse, "debaisu?::encode", "bytes to record")
edge("debaisu?::close", :inverse, "debaisu?::open", "release what open took")
edge("debaisu?::monitor", :lifts, "debaisu?::read", "console lines as a stream")
edge("debaisu?::sample", :lifts, "debaisu?::read", "reads at a rate")
edge("debaisu?::watch", :lifts, "debaisu?::read", "a read per edge")
edge("debaisu?::open", :pairs, "debaisu?::close", "take and release")
edge("debaisu?::reset", :pairs, "debaisu?::flash", "restart after write")
edge("debaisu?::write", :pairs, "debaisu?::read", "register and pin access")
edge("debaisu?::list", :pairs, "debaisu?::transfer", "scan then talk")
edge("debaisu?::terminal", :pairs, "debaisu?::waveform", "pins carry signals")
edge("debaisu?::read", :pairs, "debaisu?::write", "pin and register access")
edge("debaisu?::calibrate", :pairs, "saiten?::calibrate", "fit raw to true")
edge("debaisu?::task", :pairs, "ugoki?::clock", "periods follow a clock")
edge("debaisu?::waveform", :pairs, "ugoki?::sample", "waves are sampled values")
edge("debaisu?::on", :refines, "debaisu?::watch", "interrupt, not polling")
edge("debaisu?::fuse", :refines, "kensaku?::fuse", "merge estimates, not lists")
edge("debaisu?::flash", :requires, "chuuzou::build", "needs an image")
edge("debaisu?::run", :requires, "chuuzou::build", "emulate the image")
edge("debaisu?::list", :requires, "debaisu?::open", "scan a bus")
edge("debaisu?::monitor", :requires, "debaisu?::open", "console is a port")
edge("debaisu?::reset", :requires, "debaisu?::open", "needs a link")
edge("debaisu?::transfer", :requires, "debaisu?::open", "needs a handle")
edge("debaisu?::calibrate", :requires, "debaisu?::sample", "needs readings")
edge("debaisu?::smooth", :requires, "debaisu?::sample", "filters readings")
edge("debaisu?::task", :requires, "debaisu?::schedule", "tasks are scheduled")
edge("debaisu?::fuse", :requires, "debaisu?::smooth", "fuse clean estimates")

edge(
  "debaisu?::on",
  :requires,
  "debaisu?::terminal",
  "interrupts come from pins"
)

edge("debaisu?::waveform", :requires, "debaisu?::write", "a signal is written")

edge(
  "debaisu?::check",
  :requires,
  "kiban::board",
  "pins and clocks come from the board"
)

edge("debaisu?::terminal", :requires, "kiban::board", "pins belong to a board")
edge("debaisu?::write", :requires, "kiban::device", "address from the board")
