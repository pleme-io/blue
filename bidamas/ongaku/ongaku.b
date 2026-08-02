use("kazu")
use("retsu")
# ongaku (音楽) — twelve-tone music theory, as arithmetic on semitones.
#
# Western harmony is modular arithmetic mod 12 with names attached, which
# makes it a genuinely good fit for a small library and a genuinely exotic
# thing to find in one. A pitch class is 0..11 with 0 = C.

def note_names()
  ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
end

def note_name(pc)
  nth(((pc % 12) + 12) % 12, note_names())
end

def transpose_note(pc, semitones)
  ((pc + semitones) % 12 + 12) % 12
end

# Build a scale by walking a list of intervals from a root.
def scale_from(root, steps)
  reduce(fn(acc, s) push(acc, transpose_note(last(acc), s)) end, [root], steps)
end

def major_scale(root)
  scale_from(root, [2, 2, 1, 2, 2, 2, 1])
end

def minor_scale(root)
  scale_from(root, [2, 1, 2, 2, 1, 2, 2])
end

def major_triad(root)
  [root, transpose_note(root, 4), transpose_note(root, 7)]
end

def minor_triad(root)
  [root, transpose_note(root, 3), transpose_note(root, 7)]
end

def dominant_seventh(root)
  push(major_triad(root), transpose_note(root, 10))
end

def interval_name(semitones)
  nth(((semitones % 12) + 12) % 12,
      ["unison", "minor second", "major second", "minor third",
       "major third", "perfect fourth", "tritone", "perfect fifth",
       "minor sixth", "major sixth", "minor seventh", "major seventh"])
end

# MIDI note number to frequency in Hz. 69 is A4 = 440.
def midi_to_hz(n)
  440 * expt(2, (n - 69) / 12)
end

test "note naming wraps in both directions"
  assert note_name(0) == "C"
  assert note_name(12) == "C"
  assert note_name(0 - 1) == "B"
  assert note_name(7) == "G"
end

test "a major scale returns to its octave"
  # Eight notes, first and last the same pitch class: the check that the
  # interval pattern sums to 12.
  s = major_scale(0)
  assert size(s) == 8
  assert first(s) == 0
  assert last(s) == 0
  assert s == [0, 2, 4, 5, 7, 9, 11, 0]
end

test "C major has no sharps, which is the thing everyone knows"
  named = map(fn(pc) note_name(pc) end, take(7, major_scale(0)))
  assert named == ["C", "D", "E", "F", "G", "A", "B"]
end

test "minor differs from major exactly at the third"
  assert nth(2, minor_scale(0)) == 3
  assert nth(2, major_scale(0)) == 4
end

test "triads and sevenths"
  assert major_triad(0) == [0, 4, 7]
  assert minor_triad(9) == [9, 0, 4]
  assert dominant_seventh(7) == [7, 11, 2, 5]
end

test "interval names"
  assert interval_name(7) == "perfect fifth"
  assert interval_name(0) == "unison"
  assert interval_name(6) == "tritone"
end

test "concert pitch"
  assert near(midi_to_hz(69), 440) == true
  # An octave up is exactly double.
  assert near(midi_to_hz(81), 880) == true
end
