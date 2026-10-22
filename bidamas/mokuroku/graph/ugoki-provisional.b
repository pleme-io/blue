space("ugoki?", {status: :provisional})

verb(
  "ugoki?",
  "advance",
  {
    kind: :pure,
    shape: "advance(motion, state, dt) -> state",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "move a motion state forward by dt",
    wave: 0,
    origin: "G",
    contract: "advance(motion, state, opts) -> state"
  }
)

verb(
  "ugoki?",
  "bake",
  {
    kind: :pure,
    shape: "bake(motion, fps) -> samples",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "sample a motion at a fixed frame rate",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "check",
  {
    kind: :pure,
    shape: "check(motion, limits) -> findings",
    laterals: ["validate"],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "find a motion that breaks its time or distance budget",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "clock",
  {
    kind: :decl,
    shape: "clock(kind, opts) -> clock",
    laterals: ["time"],
    fleet: "madori",
    today: "absent",
    meaning: "declare a frame clock: fixed step or display sync",
    wave: 2,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "curve",
  {
    kind: :decl,
    shape: "curve(kind, params) -> curve",
    laterals: ["validate"],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "declare an easing curve: bezier, steps or named",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "duration",
  {
    kind: :pure,
    shape: "duration(motion) -> duration",
    laterals: ["time"],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "how long a motion runs; nil for a spring",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "ease",
  {
    kind: :pure,
    shape: "ease(curve, t) -> number",
    laterals: [],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "progress from 0 to 1 along a curve at t",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "mix",
  {
    kind: :pure,
    shape: "mix(a, b, t) -> value",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "blend two numbers, vectors, colors or rotations at t",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "parallel",
  {
    kind: :pure,
    shape: "parallel(motions) -> motion",
    laterals: [],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "motions that run together",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "pause",
  {
    kind: :effect,
    shape: "pause(handle) -> nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "hold a playing motion where it is",
    wave: 2,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "play",
  {
    kind: :stream,
    shape: "play(motion, f, opts) -> handle",
    laterals: ["cancel", "time"],
    fleet: "madori",
    today: "absent",
    meaning: "call f with the motion value on every frame",
    wave: 2,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "repeat",
  {
    kind: :pure,
    shape: "repeat(motion, n) -> motion",
    laterals: [],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "a motion run n times, or forever",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "retime",
  {
    kind: :pure,
    shape: "retime(motion, factor) -> motion",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "a motion made faster or slower",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "sample",
  {
    kind: :pure,
    shape: "sample(motion, t) -> value",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the value of a motion at time t",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "seek",
  {
    kind: :effect,
    shape: "seek(handle, t) -> nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "jump a playing motion to time t",
    wave: 2,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "sequence",
  {
    kind: :pure,
    shape: "sequence(motions) -> motion",
    laterals: [],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "motions that run one after another",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "settled?",
  {
    kind: :pure,
    shape: "settled?(motion, state) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a motion has come to rest",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "soften",
  {
    kind: :pure,
    shape: "soften(motion, preference) -> motion",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "a motion reduced for people who prefer less motion",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "spring",
  {
    kind: :decl,
    shape: "spring(stiffness, damping, mass) -> motion",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare a damped spring motion",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "stagger",
  {
    kind: :pure,
    shape: "stagger(motions, delay) -> motion",
    laterals: ["time"],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "motions that start one delay apart",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "timeline",
  {
    kind: :decl,
    shape: "timeline(tracks) -> motion",
    laterals: ["validate"],
    fleet: "ishou-batente",
    today: "absent",
    meaning: "declare keyframe tracks on one clock",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ugoki?",
  "tween",
  {
    kind: :decl,
    shape: "tween(from, to, opts) -> motion",
    laterals: ["validate"],
    fleet: "caixa-bevy_tweening",
    today: "absent",
    meaning: "declare a change of value over a duration",
    wave: 0,
    origin: "G"
  }
)

edge("ugoki?::play", :composes, "ugoki?::advance", "steps per frame")
edge("ugoki?::tween", :composes, "ugoki?::ease", "value follows the curve")
edge("ugoki?::tween", :composes, "ugoki?::mix", "blend from to")
edge("ugoki?::stagger", :composes, "ugoki?::parallel", "parallel with offsets")
edge("ugoki?::play", :composes, "ugoki?::sample", "value per frame")
edge("ugoki?::repeat", :composes, "ugoki?::sequence", "n copies in sequence")
edge("ugoki?::parallel", :composes, "ugoki?::timeline", "together")
edge("ugoki?::sequence", :composes, "ugoki?::timeline", "one after another")
edge("ugoki?::timeline", :composes, "ugoki?::tween", "tracks hold tweens")
edge("ugoki?::curve", :generalizes, "ugoki?::ease", "an ease samples a curve")
edge("ugoki?::check", :guards, "ugoki?::play", "budget before playing")
edge("ugoki?::soften", :guards, "ugoki?::play", "reduced motion before playing")
edge("ugoki?::bake", :lifts, "ugoki?::sample", "samples at a fixed rate")
edge("ugoki?::clock", :pairs, "byouga?::draw", "frames follow the clock")
edge("ugoki?::pause", :pairs, "ugoki?::seek", "hold then jump")
edge("ugoki?::advance", :pairs, "ugoki?::settled?", "step until rest")
edge("ugoki?::retime", :pairs, "ugoki?::stagger", "scale offsets too")
edge("ugoki?::sample", :refines, "ugoki?::advance", "random access at t")

edge(
  "ugoki?::spring",
  :refines,
  "ugoki?::tween",
  "a tween with physics, no end"
)

edge(
  "ugoki?::play",
  :requires,
  "gamen?::apply",
  "each frame changes the surface"
)

edge(
  "ugoki?::soften",
  :requires,
  "gamen?::describe",
  "reduced-motion preference"
)

edge(
  "ugoki?::settled?",
  :requires,
  "ugoki?::advance",
  "tests the stepped state"
)

edge("ugoki?::ease", :requires, "ugoki?::curve", "needs a curve")
edge("ugoki?::bake", :requires, "ugoki?::duration", "frame count")
edge("ugoki?::check", :requires, "ugoki?::duration", "time budget")
edge("ugoki?::repeat", :requires, "ugoki?::duration", "loop length")
edge("ugoki?::retime", :requires, "ugoki?::duration", "scales time")
edge("ugoki?::stagger", :requires, "ugoki?::duration", "offsets within length")
edge("ugoki?::mix", :requires, "ugoki?::ease", "blend at eased t")
edge("ugoki?::clock", :requires, "ugoki?::play", "play follows a clock")
edge("ugoki?::pause", :requires, "ugoki?::play", "needs a handle")
edge("ugoki?::seek", :requires, "ugoki?::play", "needs a handle")
edge("ugoki?::duration", :requires, "ugoki?::sample", "a motion has an end")
edge("ugoki?::seek", :requires, "ugoki?::sample", "jump needs a sample")
edge("ugoki?::advance", :requires, "ugoki?::spring", "steps a spring")
