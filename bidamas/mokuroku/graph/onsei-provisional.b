space("onsei?", {status: :provisional})

verb(
  "onsei?",
  "concat",
  {
    kind: :pure,
    shape: "concat(clips) -> clip",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "clips joined end to end",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "cut",
  {
    kind: :pure,
    shape: "cut(clip, from, to) -> clip",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the part of a clip between two times",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "decode",
  {
    kind: :pure,
    shape: "decode(bytes, codec) -> clip",
    laterals: [],
    fleet: "oto",
    today: "absent",
    meaning: "encoded bytes to samples",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "encode",
  {
    kind: :pure,
    shape: "encode(clip, codec) -> bytes",
    laterals: [],
    fleet: "eizou",
    today: "absent",
    meaning: "samples to encoded bytes",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "gain",
  {
    kind: :pure,
    shape: "gain(clip, decibels) -> clip",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a clip made louder or quieter",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "info",
  {
    kind: :effect,
    shape: "info(src) -> {codec, rate, channels, duration}",
    laterals: [],
    fleet: "oto",
    today: "absent",
    meaning: "facts about an audio source",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "level",
  {
    kind: :pure,
    shape: "level(clip, target) -> clip",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a clip set to a target loudness",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "list",
  {
    kind: :effect,
    shape: "list(devices) -> devices",
    laterals: [],
    fleet: "oto",
    today: "absent",
    meaning: "the audio devices that exist now",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "listen",
  {
    kind: :effect,
    shape: "listen(device, opts) -> handle",
    laterals: %w[cancel resource],
    fleet: "oto",
    today: "absent",
    meaning: "capture audio from an input device",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "measure",
  {
    kind: :pure,
    shape: "measure(clip, metric) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "peak, RMS, loudness or pitch of a clip",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "overlay",
  {
    kind: :pure,
    shape: "overlay(base, top, at) -> clip",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "one clip layered over another at a time",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "play",
  {
    kind: :effect,
    shape: "play(clip, opts) -> handle",
    laterals: %w[cancel resource],
    fleet: "oto",
    today: "absent",
    meaning: "play a clip on an output device",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "read",
  {
    kind: :effect,
    shape: "read(src, opts) -> clip",
    laterals: ["resource"],
    fleet: "oto",
    today: "absent",
    meaning: "decode a whole audio file to a clip",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "resample",
  {
    kind: :pure,
    shape: "resample(clip, rate) -> clip",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a clip at another sample rate",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "segment",
  {
    kind: :pure,
    shape: "segment(clip, opts) -> spans",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "speech and silence spans of a clip",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "speak",
  {
    kind: :effect,
    shape: "speak(text, voice, opts) -> clip",
    laterals: %w[cache deadline retry],
    fleet: nil,
    today: "absent",
    meaning: "text spoken as a clip",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "spectrum",
  {
    kind: :pure,
    shape: "spectrum(clip, opts) -> frames",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "frequency content of a clip over time",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "stream",
  {
    kind: :stream,
    shape: "stream(src, f, opts) -> nil",
    laterals: ["cancel"],
    fleet: "oto",
    today: "absent",
    meaning: "call f with each chunk of samples",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "tone",
  {
    kind: :pure,
    shape: "tone(hz, duration, shape) -> clip",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a pure tone, square, saw or noise clip",
    wave: 2,
    origin: "G"
  }
)

verb(
  "onsei?",
  "transcribe",
  {
    kind: :effect,
    shape: "transcribe(clip, opts) -> {text, spans}",
    laterals: %w[cache deadline retry],
    fleet: nil,
    today: "absent",
    meaning: "speech in a clip as timed text",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "treat",
  {
    kind: :pure,
    shape: "treat(clip, effect) -> clip",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "apply an effect: low-pass, equalizer, compressor",
    wave: 3,
    origin: "G"
  }
)

verb(
  "onsei?",
  "write",
  {
    kind: :effect,
    shape: "write(clip, target, opts) -> nil",
    laterals: ["resource"],
    fleet: "oto",
    today: "absent",
    meaning: "encode a clip to a file by its extension",
    wave: 2,
    origin: "G"
  }
)

edge("onsei?::read", :composes, "onsei?::decode", "bytes then samples")
edge("onsei?::write", :composes, "onsei?::encode", "samples then bytes")
edge("onsei?::level", :composes, "onsei?::gain", "set loudness")
edge("onsei?::level", :composes, "onsei?::measure", "measure then gain")
edge("onsei?::segment", :composes, "onsei?::measure", "speech by energy")
edge("onsei?::overlay", :generalizes, "onsei?::concat", "layers in time")
edge("onsei?::cut", :inverse, "onsei?::concat", "join what trim cut")
edge("onsei?::concat", :inverse, "onsei?::cut", "join what trim cut")
edge("onsei?::encode", :inverse, "onsei?::decode", "bytes and samples")
edge("onsei?::decode", :inverse, "onsei?::encode", "bytes and samples")
edge("onsei?::transcribe", :inverse, "onsei?::speak", "text to speech and back")
edge("onsei?::speak", :inverse, "onsei?::transcribe", "text to speech and back")
edge("onsei?::stream", :lifts, "onsei?::read", "chunks of read")
edge("onsei?::overlay", :pairs, "gazou?::overlay", "layering on any media")
edge("onsei?::tone", :pairs, "onsei?::overlay", "tones mixed into a clip")
edge("onsei?::listen", :pairs, "onsei?::play", "input and output")
edge("onsei?::resample", :pairs, "onsei?::spectrum", "fixed rate for analysis")

edge(
  "onsei?::segment",
  :pairs,
  "onsei?::transcribe",
  "spans feed transcription"
)

edge("onsei?::list", :refines, "onsei?::info", "devices, not files")
edge("onsei?::list", :requires, "debaisu?::list", "devices and buses are lists")
edge("onsei?::decode", :requires, "gazou?::demux", "audio from a container")
edge("onsei?::treat", :requires, "gazou?::treat", "same verb on images")
edge("onsei?::speak", :requires, "mokei?::ask", "a speech model")
edge("onsei?::transcribe", :requires, "mokei?::ask", "a speech model")
edge("onsei?::tone", :requires, "ongaku::hz", "pitch from a note")
edge("onsei?::cut", :requires, "onsei?::info", "bounds from duration")
edge("onsei?::resample", :requires, "onsei?::info", "rate comes from info")
edge("onsei?::stream", :requires, "onsei?::info", "chunk size from the rate")
edge("onsei?::write", :requires, "onsei?::level", "level before write")
edge("onsei?::listen", :requires, "onsei?::list", "pick an input device")
edge("onsei?::play", :requires, "onsei?::list", "pick an output device")
edge("onsei?::gain", :requires, "onsei?::measure", "set gain from a level")
edge("onsei?::info", :requires, "onsei?::read", "facts before decode")
edge("onsei?::spectrum", :requires, "onsei?::resample", "fixed rate input")
edge("onsei?::treat", :requires, "onsei?::resample", "effects need one rate")
edge("onsei?::cut", :requires, "onsei?::segment", "cut at spans")

edge(
  "onsei?::transcribe",
  :requires,
  "onsei?::segment",
  "split long audio first"
)

edge("onsei?::measure", :requires, "onsei?::spectrum", "pitch needs a spectrum")
