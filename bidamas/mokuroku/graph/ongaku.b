space("ongaku", {status: :ratified})

verb(
  "ongaku",
  "analyze",
  {
    kind: :pure,
    shape: "analyze(notes) -> {key, chords}",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the key and chords that fit notes",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ongaku",
  "chord",
  {
    kind: :pure,
    shape: "chord(root, kind) -> notes",
    laterals: [],
    fleet: nil,
    today: "partial:ongaku",
    meaning: "the notes of a chord from a root",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ongaku",
  "hz",
  {
    kind: :pure,
    shape: "hz(note) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:ongaku",
    meaning: "the frequency of a MIDI note",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ongaku",
  "notes",
  {
    kind: :pure,
    shape: "notes(root, kind) -> notes",
    laterals: [],
    fleet: nil,
    today: "partial:ongaku",
    meaning: "the notes of a scale from a root",
    wave: 0,
    origin: "G"
  }
)

verb(
  "ongaku",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> score",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "ABC or MIDI text to a score",
    wave: 1,
    origin: "G"
  }
)

verb(
  "ongaku",
  "render",
  {
    kind: :pure,
    shape: "render(score, format) -> clip or bytes",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a score as MIDI bytes or an audio clip",
    wave: 2,
    origin: "G"
  }
)

verb(
  "ongaku",
  "transpose",
  {
    kind: :pure,
    shape: "transpose(notes, semitones) -> notes",
    laterals: [],
    fleet: nil,
    today: "exists:ongaku",
    meaning: "notes moved by semitones",
    wave: 0,
    origin: "G"
  }
)

edge("ongaku::render", :composes, "onsei?::encode", "an audio clip is encoded")
edge("ongaku::render", :inverse, "ongaku::parse", "score to bytes")
edge("ongaku::parse", :inverse, "ongaku::render", "score to bytes")
edge("ongaku::transpose", :pairs, "ongaku::notes", "moves any notes")
edge("ongaku::analyze", :pairs, "ongaku::parse", "parse then analyze")
edge("ongaku::analyze", :requires, "ongaku::chord", "match known chords")
edge("ongaku::hz", :requires, "ongaku::notes", "frequency of a note")
edge("ongaku::chord", :requires, "ongaku::transpose", "chord from a root")
edge("ongaku::notes", :requires, "ongaku::transpose", "scale from a root")
