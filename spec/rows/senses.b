# The senses: audio_out, audio_in and display. Each row is host() and states
# what blue promises before a word reaches a device, so no row plays, records
# or opens a window: a clip, a format, a count and a canvas size are checked
# first, a canvas word refuses what is not a canvas, and a format query is a
# format or nil. The holds, the recording sink, the monitor, the seeded
# source, the framebuffer, the absent host and the lock run in
# crates/blue-lang-cli/tests/senses.rs.

row(
  "senses.play_audio.refuses_what_is_not_whole_frames_within_one",
  join_lines(
    [
      "def kind(clip)",
      "  play_audio(clip)",
      "  :played",
      "rescue :bad_option as e",
      "  e.kind",
      "end",
      "",
      "[",
      "  kind({rate: 8000, channels: 2, samples: [0.5]}),",
      "  kind({rate: 8000, channels: 1, samples: [1.5]}),",
      "  kind({rate: 0, channels: 1, samples: []}),",
      "  kind({rate: 8000, channels: 1}),",
      "  kind(7)",
      "]"
    ]
  ),
  value("[:bad_option, :bad_option, :bad_option, :bad_option, :bad_option]"),
  covers("builtin:play_audio"),
  host()
)

row(
  "senses.audio_out_format.is_a_format_or_nil",
  join_lines(
    ["f = audio_out_format", "f.nil? or (f.rate > 0 and f.channels > 0)"]
  ),
  value("true"),
  covers("builtin:audio_out_format"),
  host()
)

row(
  "senses.capture_audio.refuses_a_bad_count_or_format",
  join_lines(
    [
      "def kind(n, format)",
      "  capture_audio(n, format)",
      "  :captured",
      "rescue :bad_option as e",
      "  e.kind",
      "end",
      "",
      "[",
      "  kind(-1, {rate: 8000, channels: 1}),",
      "  kind(1.5, {rate: 8000, channels: 1}),",
      "  kind(1, {rate: 8000, channels: 0}),",
      "  kind(1, \"8000\")",
      "]"
    ]
  ),
  value("[:bad_option, :bad_option, :bad_option, :bad_option]"),
  covers("builtin:capture_audio"),
  host()
)

row(
  "senses.audio_in_format.is_a_format_or_nil",
  join_lines(
    ["f = audio_in_format", "f.nil? or (f.rate > 0 and f.channels > 0)"]
  ),
  value("true"),
  covers("builtin:audio_in_format"),
  host()
)

row(
  "senses.canvas_open.refuses_a_side_outside_one_to_4096",
  join_lines(
    [
      "def kind(opts)",
      "  canvas_open(opts)",
      "  :opened",
      "rescue :bad_option as e",
      "  e.kind",
      "end",
      "",
      "[",
      "  kind({width: 0, height: 8}),",
      "  kind({width: 8, height: 4097}),",
      "  kind({width: 8}),",
      "  kind({width: 8, height: 8, title: 3})",
      "]"
    ]
  ),
  value("[:bad_option, :bad_option, :bad_option, :bad_option]"),
  covers("builtin:canvas_open"),
  host()
)

row(
  "senses.canvas_words.refuse_what_is_not_a_canvas",
  join_lines(
    [
      "def kind(f)",
      "  f()",
      "  :drew",
      "rescue :bad_option as e",
      "  e.kind",
      "end",
      "",
      "[",
      "  kind(() -> canvas_clear(nil, \"#000000\")),",
      "  kind(() -> canvas_fill_rect(nil, 0, 0, 1, 1, \"#000000\")),",
      "  kind(() -> canvas_text(nil, 0, 0, \"a\", \"#000000\")),",
      "  kind(() -> canvas_present(nil)),",
      "  kind(() -> canvas_pixel(nil, 0, 0)),",
      "  kind(() -> canvas_close(nil))",
      "]"
    ]
  ),
  value("[:bad_option, :bad_option, :bad_option, :bad_option, :bad_option, :bad_option]"),
  covers(
    "builtin:canvas_clear",
    "builtin:canvas_fill_rect",
    "builtin:canvas_text",
    "builtin:canvas_present",
    "builtin:canvas_pixel",
    "builtin:canvas_close"
  ),
  host()
)
