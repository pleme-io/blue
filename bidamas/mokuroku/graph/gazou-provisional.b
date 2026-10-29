space("gazou?", {status: :provisional})

verb(
  "gazou?",
  "convert",
  {
    kind: :pure,
    shape: "convert(image, space) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "an image in another pixel format or color space",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "crop",
  {
    kind: :pure,
    shape: "crop(image, rect) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the part of an image inside a rectangle",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "cut",
  {
    kind: :pure,
    shape: "cut(video, from, to) -> video",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the part of a video between two times",
    wave: 3,
    origin: "G"
  }
)

verb(
  "gazou?",
  "decode",
  {
    kind: :pure,
    shape: "decode(bytes, format) -> image",
    laterals: [],
    fleet: "caixa-png",
    today: "absent",
    meaning: "PNG, JPEG or WebP bytes to pixels",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "demux",
  {
    kind: :effect,
    shape: "demux(src) -> streams",
    laterals: ["resource"],
    fleet: "eizou",
    today: "absent",
    meaning: "split a container into video, audio and text streams",
    wave: 3,
    origin: "G"
  }
)

verb(
  "gazou?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> {score, mask}",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "how two images differ, and where",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "encode",
  {
    kind: :pure,
    shape: "encode(image, format) -> bytes",
    laterals: [],
    fleet: "caixa-png",
    today: "absent",
    meaning: "pixels to PNG, JPEG or WebP bytes",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "frames",
  {
    kind: :stream,
    shape: "frames(video, f, opts) -> nil",
    laterals: %w[cancel resource],
    fleet: "eizou",
    today: "absent",
    meaning: "call f with each decoded frame",
    wave: 3,
    origin: "G",
    contract: "frames(video) -> nil"
  }
)

verb(
  "gazou?",
  "hash",
  {
    kind: :pure,
    shape: "hash(image, kind) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a perceptual hash that survives resizing",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "info",
  {
    kind: :effect,
    shape: "info(src) -> {format, size, frames, fps}",
    laterals: [],
    fleet: "caixa-image",
    today: "absent",
    meaning: "facts about an image or video source",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "measure",
  {
    kind: :pure,
    shape: "measure(image, metric) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "mean color, sharpness or entropy of an image",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "mux",
  {
    kind: :effect,
    shape: "mux(streams, target, opts) -> nil",
    laterals: ["resource"],
    fleet: "eizou",
    today: "absent",
    meaning: "join streams into one container file",
    wave: 3,
    origin: "G"
  }
)

verb(
  "gazou?",
  "ocr",
  {
    kind: :effect,
    shape: "ocr(image, opts) -> {text, boxes}",
    laterals: %w[cache deadline retry],
    fleet: nil,
    today: "absent",
    meaning: "text found in an image, with boxes",
    wave: 3,
    origin: "G"
  }
)

verb(
  "gazou?",
  "overlay",
  {
    kind: :pure,
    shape: "overlay(base, top, at) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "one image layered over another at a place",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "palette",
  {
    kind: :pure,
    shape: "palette(image, n) -> colors",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the n dominant colors of an image",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "read",
  {
    kind: :effect,
    shape: "read(src, opts) -> image",
    laterals: ["resource"],
    fleet: "caixa-image",
    today: "absent",
    meaning: "decode a still image file",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "resize",
  {
    kind: :pure,
    shape: "resize(image, size, opts) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "an image scaled to a size",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "segment",
  {
    kind: :pure,
    shape: "segment(video, opts) -> spans",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "shots or scenes of a video as spans",
    wave: 4,
    origin: "G"
  }
)

verb(
  "gazou?",
  "strip",
  {
    kind: :pure,
    shape: "strip(image) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "an image without its metadata, such as GPS",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "thumbnail",
  {
    kind: :pure,
    shape: "thumbnail(media, size, opts) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a small preview of an image or video",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "transcode",
  {
    kind: :effect,
    shape: "transcode(src, target, opts) -> nil",
    laterals: %w[deadline process],
    fleet: nil,
    today: "absent",
    meaning: "re-encode a video to another codec or size",
    wave: 4,
    origin: "G"
  }
)

verb(
  "gazou?",
  "treat",
  {
    kind: :pure,
    shape: "treat(image, effect) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "apply an effect: blur, sharpen, curves",
    wave: 3,
    origin: "G"
  }
)

verb(
  "gazou?",
  "turn",
  {
    kind: :pure,
    shape: "turn(image, turns) -> image",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "an image turned by quarter turns or an angle",
    wave: 2,
    origin: "G"
  }
)

verb(
  "gazou?",
  "write",
  {
    kind: :effect,
    shape: "write(image, target, opts) -> nil",
    laterals: ["resource"],
    fleet: "caixa-image",
    today: "absent",
    meaning: "encode an image to a file by its extension",
    wave: 2,
    origin: "G"
  }
)

edge("gazou?::read", :composes, "gazou?::decode", "bytes then pixels")
edge("gazou?::transcode", :composes, "gazou?::demux", "split first")
edge("gazou?::write", :composes, "gazou?::encode", "pixels then bytes")
edge("gazou?::transcode", :composes, "gazou?::frames", "re-encode frames")
edge("gazou?::diff", :composes, "gazou?::measure", "score from pixel error")
edge("gazou?::transcode", :composes, "gazou?::mux", "join last")

edge(
  "gazou?::thumbnail",
  :composes,
  "gazou?::resize",
  "resize with a preview rule"
)

edge(
  "gazou?::convert",
  :guards,
  "gazou?::overlay",
  "same space before layering"
)

edge("gazou?::strip", :guards, "gazou?::write", "no metadata leaves")
edge("gazou?::encode", :inverse, "gazou?::decode", "bytes and pixels")
edge("gazou?::mux", :inverse, "gazou?::demux", "streams into a container")
edge("gazou?::decode", :inverse, "gazou?::encode", "bytes and pixels")
edge("gazou?::demux", :inverse, "gazou?::mux", "streams into a container")
edge("gazou?::frames", :lifts, "gazou?::decode", "decode per frame")
edge("gazou?::hash", :pairs, "gazou?::diff", "hash for fast, diff for detail")
edge("gazou?::cut", :pairs, "gazou?::frames", "cut at frame times")
edge("gazou?::treat", :pairs, "onsei?::treat", "effects on any media")

edge(
  "gazou?::overlay",
  :refines,
  "byouga?::composite",
  "image form of layering"
)

edge("gazou?::cut", :refines, "onsei?::cut", "time cut on video")
edge("gazou?::segment", :refines, "onsei?::segment", "shots, not speech")
edge("gazou?::palette", :requires, "gamen?::theme", "colors feed a theme")
edge("gazou?::resize", :requires, "gazou?::convert", "resize in linear space")
edge("gazou?::treat", :requires, "gazou?::convert", "effects in a known space")
edge("gazou?::turn", :requires, "gazou?::crop", "crop after turning")
edge("gazou?::measure", :requires, "gazou?::decode", "reads pixels")
edge("gazou?::segment", :requires, "gazou?::frames", "shot changes from frames")
edge("gazou?::thumbnail", :requires, "gazou?::frames", "a frame of a video")
edge("gazou?::crop", :requires, "gazou?::info", "rect inside size")
edge("gazou?::strip", :requires, "gazou?::info", "metadata to remove")
edge("gazou?::turn", :requires, "gazou?::info", "orientation metadata")
edge("gazou?::palette", :requires, "gazou?::measure", "color stats")
edge("gazou?::info", :requires, "gazou?::read", "facts before decode")
edge("gazou?::diff", :requires, "gazou?::resize", "same size before compare")
edge("gazou?::hash", :requires, "gazou?::resize", "hash a normalized size")
edge("gazou?::write", :requires, "gazou?::strip", "strip then write")
edge("gazou?::ocr", :requires, "gazou?::treat", "clean before reading")
edge("gazou?::ocr", :requires, "mokei?::ask", "a vision model")
