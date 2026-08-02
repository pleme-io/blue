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

# --- pitch classes and spelling ---------------------------------------------

# The normaliser every function below shares. `%` is Euclidean on this runtime
# — (0 - 5) % 12 is 7, not -5 — so the second fold is belt-and-braces rather
# than load-bearing; it is kept because the three functions written before this
# one already spell it out and disagreeing with them would be worse.
def pitch_class(n)
  ((n % 12) + 12) % 12
end

# The same fold for a list of length n rather than for the twelve pitches:
# degree 7 of a seven-note scale is degree 0 again, and degree 0 - 1 is the
# seventh. Chord-building walks off both ends of a scale constantly.
def wrap_index(i, n)
  if n < 1
    0
  else
    ((i % n) + n) % n
  end
end

# The same twelve pitches, spelled with flats.
#
# This is not a stylistic alternative: which spelling is CORRECT is a property
# of the key, not of the pitch. Db major contains Db, and writing C# there
# gives a scale with two D's and no C, which is wrong on paper even though it
# sounds identical. Both tables exist so `note_name_for_key` can choose.
def note_names_flat()
  ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
end

def note_name_flat(pc)
  nth(pitch_class(pc), note_names_flat())
end

def note_name_in(pc, use_flats)
  if use_flats
    note_name_flat(pc)
  else
    note_name(pc)
  end
end

# Name -> pitch class. Returns 0 - 1 for a name it cannot place, matching
# retsu's index_of convention: a negative sentinel a caller can compare,
# where nil would not survive a `<`.
def pitch_class_of(name)
  i = index_of(note_names(), name)
  if i >= 0
    i
  else
    j = index_of(note_names_flat(), name)
    if j >= 0
      j
    else
      pitch_class_of_crossing(name)
    end
  end
end

# The four spellings that cross a letter boundary. E#, Fb, B# and Cb are in
# neither twelve-name table — each table holds exactly one name per pitch —
# yet they occur in real key signatures (F# major genuinely has an E#). There
# are only four, so they are listed rather than parsed.
#
# Written as two parallel lists and not as an if/elsif chain because `elsif`
# is accepted by this parser and then dies at evaluation with
# "unbound symbol: elsif". Nothing in this file may use it.
def crossing_names()
  ["E#", "Fb", "B#", "Cb"]
end

def pitch_class_of_crossing(name)
  i = index_of(crossing_names(), name)
  if i >= 0
    nth(i, [5, 4, 0, 11])
  else
    0 - 1
  end
end

# The other spelling of the same pitch. A natural has only one spelling in
# these tables, so it maps to itself — which is what makes this an involution
# on every input rather than only on the accidentals.
def enharmonic_of(name)
  pc = pitch_class_of(name)
  if pc < 0
    name
  else
    sharp = note_name(pc)
    if name == sharp
      note_name_flat(pc)
    else
      sharp
    end
  end
end

def is_enharmonic(a, b)
  pa = pitch_class_of(a)
  pa >= 0 && pa == pitch_class_of(b)
end

# --- chords -------------------------------------------------------------------

# The two triads the existing pair leaves out. Together the four exhaust the
# ways to stack two thirds: major+minor, minor+major, minor+minor, major+major.
def diminished_triad(root)
  [root, transpose_note(root, 3), transpose_note(root, 6)]
end

def augmented_triad(root)
  [root, transpose_note(root, 4), transpose_note(root, 8)]
end

# Suspensions are not a third quality — they have no third at all, which is the
# point of them, and why they are here rather than in the quality list above.
def sus2_triad(root)
  [root, transpose_note(root, 2), transpose_note(root, 7)]
end

def sus4_triad(root)
  [root, transpose_note(root, 5), transpose_note(root, 7)]
end

def major_seventh(root)
  push(major_triad(root), transpose_note(root, 11))
end

def minor_seventh(root)
  push(minor_triad(root), transpose_note(root, 10))
end

# Minor triad, minor seventh, flat fifth — the ii of a minor key. Called
# half-diminished because only the fifth is diminished; the seventh is not.
def half_diminished_seventh(root)
  push(diminished_triad(root), transpose_note(root, 10))
end

# Four minor thirds stacked, so it divides the octave evenly: every inversion
# of it is another diminished seventh, and there are only three distinct ones.
def diminished_seventh(root)
  push(diminished_triad(root), transpose_note(root, 9))
end

# The tonic seventh of harmonic minor — minor triad under a MAJOR seventh,
# which is the raised leading tone showing up as a chord tone.
def minor_major_seventh(root)
  push(minor_triad(root), transpose_note(root, 11))
end

def augmented_major_seventh(root)
  push(augmented_triad(root), transpose_note(root, 11))
end

def augmented_seventh(root)
  push(augmented_triad(root), transpose_note(root, 10))
end

# A chord reduced to its shape: the intervals of every note above the lowest.
# Quality is a property of that shape and not of the pitches, so classifying
# has to go through here first.
def chord_intervals(notes)
  if is_empty(notes)
    []
  else
    map(fn(pc) interval_between(first(notes), pc) end, notes)
  end
end

def chord_from_root(root, intervals)
  map(fn(s) transpose_note(root, s) end, intervals)
end

# Shape -> name, with "unknown" for anything unlisted. An unlisted shape is a
# real answer here: most of the 4096 note sets have no traditional name, and
# inventing one would be worse than admitting it.
def quality_of_shape(shape, shapes, names)
  i = index_of(shapes, shape)
  if i < 0
    "unknown"
  else
    nth(i, names)
  end
end

def triad_shapes()
  [[0, 4, 7], [0, 3, 7], [0, 3, 6], [0, 4, 8], [0, 2, 7], [0, 5, 7]]
end

def triad_quality_names()
  ["major", "minor", "diminished", "augmented", "sus2", "sus4"]
end

def triad_quality(notes)
  quality_of_shape(chord_intervals(notes), triad_shapes(), triad_quality_names())
end

def seventh_shapes()
  [[0, 4, 7, 11], [0, 4, 7, 10], [0, 3, 7, 10], [0, 3, 6, 10],
   [0, 3, 6, 9], [0, 3, 7, 11], [0, 4, 8, 11], [0, 4, 8, 10]]
end

def seventh_quality_names()
  ["major seventh", "dominant seventh", "minor seventh",
   "half-diminished seventh", "diminished seventh", "minor-major seventh",
   "augmented major seventh", "augmented seventh"]
end

def seventh_quality(notes)
  quality_of_shape(chord_intervals(notes), seventh_shapes(), seventh_quality_names())
end

# Dispatches on how many notes there are, since a three-note shape and a
# four-note shape are never the same chord and sharing one table would let
# [0,4,7] match a seventh by accident.
def chord_quality(notes)
  n = size(notes)
  if n == 3
    triad_quality(notes)
  else
    if n == 4
      seventh_quality(notes)
    else
      "unknown"
    end
  end
end

def chord_name(notes)
  if is_empty(notes)
    "unknown"
  else
    join([note_name(first(notes)), chord_quality(notes)], " ")
  end
end

# Inversion in pitch-class space is rotation: the notes are the same, the
# bottom one changes. Voicing (which octave each note sits in) is not modelled
# here, so this is the harmonic half of inversion, not the pianistic half.
def invert_chord(notes, n)
  if is_empty(notes)
    []
  else
    rotate(notes, wrap_index(n, size(notes)))
  end
end

# --- modes and scales --------------------------------------------------------

# The seven modes are ROTATIONS of one interval pattern, not seven patterns.
# Spelling them that way is the whole content of the idea: dorian is what you
# get by starting the major steps one place along, which is also why every mode
# of C major uses only the white notes. Hard-coding seven lists would compile
# and would lose the reason.
def major_steps()
  [2, 2, 1, 2, 2, 2, 1]
end

def mode_names()
  ["ionian", "dorian", "phrygian", "lydian", "mixolydian", "aeolian", "locrian"]
end

def mode_steps(name)
  i = index_of(mode_names(), name)
  if i < 0
    []
  else
    rotate(major_steps(), i)
  end
end

# An unrecognised mode name gives [] rather than a one-note scale, because
# scale_from with no steps returns just the root and a caller cannot tell that
# apart from a real answer.
def mode_scale(root, name)
  if index_of(mode_names(), name) < 0
    []
  else
    scale_from(root, mode_steps(name))
  end
end

# The other, equivalent definition: the mode you land on by starting a major
# scale from its nth degree. mode_scale says WHICH steps; this says WHERE from.
# The test pins them against each other, which is the only way either one is
# checked by something other than itself.
def mode_of_major(root, degree)
  d = ((degree % 7) + 7) % 7
  mode_scale(nth(d, major_scale(root)), nth(d, mode_names()))
end

# Harmonic minor raises the seventh so the chord on V is major and can pull
# home; the augmented second it leaves between the sixth and seventh (the 3 in
# this list) is the sound the raise costs you.
def harmonic_minor_scale(root)
  scale_from(root, [2, 1, 2, 2, 1, 3, 1])
end

# Melodic minor, ascending form — sixth AND seventh raised, which is what
# removes that augmented second. Classical practice descends in natural minor;
# this returns the ascending form, since jazz treats it as a scale in its own
# right and the descending form is already minor_scale.
def melodic_minor_scale(root)
  scale_from(root, [2, 1, 2, 2, 2, 2, 1])
end

def major_pentatonic_scale(root)
  scale_from(root, [2, 2, 3, 2, 3])
end

def minor_pentatonic_scale(root)
  scale_from(root, [3, 2, 2, 3, 2])
end

# The minor pentatonic with the flat fifth wedged in — one passing note, and
# the reason this is six notes where the pentatonics are five.
def blues_scale(root)
  scale_from(root, [3, 2, 1, 1, 3, 2])
end

def chromatic_scale(root)
  scale_from(root, repeat(1, 12))
end

# Six equal whole steps. It divides the octave evenly, so it is one of the two
# scales that transpose onto themselves — a fact the test uses.
def whole_tone_scale(root)
  scale_from(root, repeat(2, 6))
end

# Every scale here ends on the octave restatement of its root, so `size` counts
# one more than the number of distinct pitches. This drops it.
def scale_tones(scale)
  all_but_last(scale)
end

def is_in_scale(pc, scale)
  contains(scale, pitch_class(pc))
end

# Zero-based degree — 0 is the tonic, so degree 4 is the dominant. 0 - 1 when
# the note is not in the scale.
def scale_degree_of(pc, scale)
  index_of(scale_tones(scale), pitch_class(pc))
end

# Transposes any note list — a scale, a chord, a melody. Kept separate from
# transpose_note so callers do not map by hand at every site.
def transpose_all(notes, semitones)
  map(fn(pc) transpose_note(pc, semitones) end, notes)
end

def note_names_of(notes)
  map(fn(pc) note_name(pc) end, notes)
end

# --- chords built out of a scale ----------------------------------------------

# The degree-th note of a scale, wrapping. Degrees are zero-based here to match
# every other index in this distribution; musicians count the tonic as 1, so a
# caller writing roman numerals subtracts one.
def scale_note(scale, degree)
  tones = scale_tones(scale)
  if is_empty(tones)
    nil
  else
    nth(wrap_index(degree, size(tones)), tones)
  end
end

# A chord on a scale degree is thirds stacked WITHIN the scale — skip a note,
# skip a note — so the quality falls out of where you are rather than being
# chosen. That is why the seven triads of a major scale are three major, three
# minor and one diminished without anyone deciding so.
def scale_triad(scale, degree)
  if is_empty(scale_tones(scale))
    []
  else
    [scale_note(scale, degree),
     scale_note(scale, degree + 2),
     scale_note(scale, degree + 4)]
  end
end

def scale_seventh(scale, degree)
  t = scale_triad(scale, degree)
  if is_empty(t)
    []
  else
    push(t, scale_note(scale, degree + 6))
  end
end

# The quality of every degree's triad, in order — the "I ii iii IV V vi vii°"
# of a key, derived rather than recited.
def scale_triad_qualities(scale)
  map(fn(d) triad_quality(scale_triad(scale, d)) end,
      range(0, size(scale_tones(scale))))
end

def scale_seventh_qualities(scale)
  map(fn(d) seventh_quality(scale_seventh(scale, d)) end,
      range(0, size(scale_tones(scale))))
end

# --- keys, and the circle of fifths -------------------------------------------

def fifth_up(pc)
  transpose_note(pc, 7)
end

def fifth_down(pc)
  transpose_note(pc, 0 - 7)
end

# Stepping by fifths visits all twelve pitches before repeating, because 7 and
# 12 are coprime. That single fact is why the circle is a circle and why the
# key signatures come out one accidental apart all the way round.
def circle_of_fifths(start)
  map(fn(i) transpose_note(start, 7 * i) end, range(0, 12))
end

# Accidentals in a MAJOR key: positive counts sharps, negative counts flats.
#
# Position on the circle of fifths from C is exactly the sharp count, so the
# whole thing is pc * 7 mod 12, folded into -5..6 so the far side of the circle
# reads as flats rather than as seven-plus sharps. The fold has to break the
# tie somewhere: 6 goes to F# with six sharps rather than Gb with six flats,
# which is arbitrary in the same way the two names are.
def key_signature(pc)
  n = pitch_class(pc * 7)
  if n > 6
    n - 12
  else
    n
  end
end

def sharp_count(pc)
  max(key_signature(pc), 0)
end

def flat_count(pc)
  max(0 - key_signature(pc), 0)
end

def key_uses_flats(pc)
  key_signature(pc) < 0
end

# Spelling driven by the key rather than by preference — the reason both name
# tables exist. Eb in Bb major, D# in E major, same pitch.
def note_name_for_key(pc, key)
  note_name_in(pc, key_uses_flats(key))
end

# The scale of a major key, spelled the way that key is written.
#
# Honest limit: a pitch class carries no letter name, so this cannot enforce
# the real rule that a key uses each of the seven letters once. It is correct
# for every key with five or fewer accidentals, and wrong in exactly one place
# — F# major, whose seventh degree must be written E# and comes back as F.
# Fixing that needs a letter+accidental type, not a bigger table; the test
# pins the failure so it is a known edge and not a lurking one.
def key_note_names(key)
  map(fn(pc) note_name_for_key(pc, key) end, scale_tones(major_scale(key)))
end

# Sharps are added F C G D A E B and flats in the exact reverse. It is the same
# order run backwards because each is a chain of fifths, one up and one down —
# so writing the second list as reverse of the first is the statement, not a
# shortcut.
def sharps_in_order()
  ["F", "C", "G", "D", "A", "E", "B"]
end

def flats_in_order()
  reverse(sharps_in_order())
end

# Which letters carry an accidental in this key, in the order a copyist writes
# them on the staff.
def key_accidentals(pc)
  if key_uses_flats(pc)
    take(flat_count(pc), flats_in_order())
  else
    take(sharp_count(pc), sharps_in_order())
  end
end

# A major key and its relative minor share every note and every accidental;
# they differ only in which note is home. Three semitones down, or nine up.
def relative_minor(pc)
  transpose_note(pc, 9)
end

def relative_major(pc)
  transpose_note(pc, 3)
end

# A minor key's signature is its relative major's, by definition rather than by
# a second table — which is what keeps the two from ever disagreeing.
def minor_key_signature(pc)
  key_signature(relative_major(pc))
end

# --- intervals ---------------------------------------------------------------

# Semitones from a UP to b. Directed, so it is deliberately not symmetric:
# C up to G is 7, G up to C is 5, and those two are different intervals.
def interval_between(a, b)
  pitch_class(b - a)
end

def interval_name_between(a, b)
  interval_name(interval_between(a, b))
end

# The undirected distance, 0..6. A fifth up and a fourth down separate the same
# two pitches, so both fold to 5. The tritone is 6 and is its own inversion,
# which is exactly why it has no direction to lose.
def interval_class(a, b)
  d = interval_between(a, b)
  min(d, 12 - d)
end

def invert_interval(semitones)
  pitch_class(0 - semitones)
end

# Consonance in the common-practice sense: unison, both thirds, both sixths,
# the fifth and the fourth. The fourth is the contested one — it is a perfect
# consonance in isolation and a dissonance against the bass — and it is counted
# consonant here, which is the interval-in-isolation reading this function's
# signature can actually support. A caller judging a fourth over a bass note
# needs voicing information this does not have.
def is_consonant(semitones)
  contains([0, 3, 4, 5, 7, 8, 9], pitch_class(semitones))
end

def is_dissonant(semitones)
  !is_consonant(semitones)
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

test "the two spelling tables name the same twelve pitches"
  # The check that matters: every flat name round-trips to the pitch class it
  # was taken from. A table with a typo, or one note out of order, fails here
  # and nowhere else — naming C# and Db both "correct" hides a shifted table.
  assert map(fn(pc) pitch_class_of(note_name_flat(pc)) end, range(0, 12)) == range(0, 12)
  assert map(fn(pc) pitch_class_of(note_name(pc)) end, range(0, 12)) == range(0, 12)
  assert note_name_flat(1) == "Db"
  assert note_name(1) == "C#"
  assert note_name_in(6, true) == "Gb"
  assert note_name_in(6, false) == "F#"
end

test "enharmonic_of is an involution, and the identity on naturals"
  assert enharmonic_of("C#") == "Db"
  assert enharmonic_of("Db") == "C#"
  assert enharmonic_of(enharmonic_of("C#")) == "C#"
  assert enharmonic_of(enharmonic_of("Bb")) == "Bb"
  # A natural has one spelling here, so it is its own partner. Any
  # implementation that blindly swaps tables would return something else.
  assert enharmonic_of("E") == "E"
  assert enharmonic_of("unplayable") == "unplayable"
end

test "letter-crossing spellings resolve, unknown names do not"
  assert pitch_class_of("E#") == 5
  assert pitch_class_of("Cb") == 11
  assert pitch_class_of("B#") == 0
  assert pitch_class_of("H") == 0 - 1
  assert is_enharmonic("E#", "F") == true
  assert is_enharmonic("E", "F") == false
  # Two unknown names are not "both nothing, therefore equal".
  assert is_enharmonic("H", "H") == false
end

test "interval_between is directed; interval_class is not"
  assert interval_between(0, 7) == 7
  assert interval_between(7, 0) == 5
  # The pair sums to an octave — the property a symmetric implementation,
  # which is the tempting wrong one, cannot satisfy.
  assert interval_between(0, 7) + interval_between(7, 0) == 12
  assert interval_class(0, 7) == 5
  assert interval_class(7, 0) == 5
  assert interval_class(0, 6) == 6
  assert interval_name_between(9, 0) == "minor third"
end

test "interval inversion is an involution with the tritone fixed"
  assert invert_interval(7) == 5
  assert invert_interval(5) == 7
  assert invert_interval(0) == 0
  assert invert_interval(6) == 6
  assert map(fn(s) invert_interval(invert_interval(s)) end, range(0, 12)) == range(0, 12)
end

test "consonance splits the octave seven to five"
  assert is_consonant(0) == true
  assert is_consonant(4) == true
  assert is_consonant(7) == true
  assert is_consonant(6) == false
  assert is_consonant(1) == false
  assert is_consonant(11) == false
  # An inversion of a consonance is a consonance — true of this set and false
  # of most hand-typed near-misses.
  assert count_where(fn(s) is_consonant(s) end, range(0, 12)) == 7
  assert count_where(fn(s) is_consonant(invert_interval(s)) end, range(0, 12)) == 7
  assert is_dissonant(6) == true
end

test "every mode is a rotation of one pattern and closes the octave"
  # Each mode's steps must still sum to 12, or the scale does not come home.
  assert map(fn(m) sum(mode_steps(m)) end, mode_names()) == repeat(12, 7)
  assert map(fn(m) size(mode_scale(0, m)) end, mode_names()) == repeat(8, 7)
  assert map(fn(m) last(mode_scale(5, m)) end, mode_names()) == repeat(5, 7)
end

test "ionian is major and aeolian is minor, by construction not by table"
  assert mode_scale(0, "ionian") == major_scale(0)
  assert mode_scale(9, "aeolian") == minor_scale(9)
  # Lydian sharpens the fourth, mixolydian flattens the seventh: one note each
  # away from major, and the note has to be the right one.
  assert nth(3, mode_scale(0, "lydian")) == 6
  assert nth(6, mode_scale(0, "mixolydian")) == 10
  assert nth(1, mode_scale(0, "phrygian")) == 1
  assert nth(4, mode_scale(0, "locrian")) == 6
  assert mode_scale(0, "not a mode") == []
end

test "the two definitions of a mode agree"
  # D dorian derived from its own steps, against D dorian derived as the second
  # mode of C major. Either alone proves nothing; together they pin both.
  assert mode_of_major(0, 1) == mode_scale(2, "dorian")
  assert mode_of_major(0, 5) == mode_scale(9, "aeolian")
  # All seven modes of C major use only the white notes.
  assert map(fn(d) contains(major_scale(0), first(mode_of_major(0, d))) end, range(0, 7)) == repeat(true, 7)
end

test "harmonic and melodic minor differ from natural minor at named degrees"
  # Natural, harmonic and melodic minor share degrees 0..4; the sixth and
  # seventh are the whole argument between them.
  assert take(5, harmonic_minor_scale(9)) == take(5, minor_scale(9))
  assert take(5, melodic_minor_scale(9)) == take(5, minor_scale(9))
  assert nth(6, minor_scale(9)) == 7
  assert nth(6, harmonic_minor_scale(9)) == 8
  assert nth(5, harmonic_minor_scale(9)) == 5
  assert nth(5, melodic_minor_scale(9)) == 6
  assert nth(6, melodic_minor_scale(9)) == 8
  # A harmonic minor is A B C D E F G#: the raised seventh is the only accidental.
  assert note_names_of(scale_tones(harmonic_minor_scale(9))) == ["A", "B", "C", "D", "E", "F", "G#"]
end

test "pentatonics and the blues scale"
  assert scale_tones(major_pentatonic_scale(0)) == [0, 2, 4, 7, 9]
  assert scale_tones(minor_pentatonic_scale(9)) == [9, 0, 2, 4, 7]
  # Five notes plus the octave; the blues scale is that plus one passing note.
  assert size(scale_tones(major_pentatonic_scale(0))) == 5
  assert size(scale_tones(blues_scale(9))) == 6
  # A minor pentatonic is a subset of A minor, and the blues note is not.
  assert count_where(fn(pc) is_in_scale(pc, minor_scale(9)) end, scale_tones(minor_pentatonic_scale(9))) == 5
  assert is_in_scale(3, blues_scale(9)) == true
  assert is_in_scale(3, minor_pentatonic_scale(9)) == false
end

test "chromatic and whole-tone scales"
  assert size(scale_tones(chromatic_scale(0))) == 12
  assert scale_tones(chromatic_scale(0)) == range(0, 12)
  assert scale_tones(whole_tone_scale(0)) == [0, 2, 4, 6, 8, 10]
  # The whole-tone scale maps onto itself under transposition by a whole step —
  # true of it and of almost nothing else, so it is a real check on the steps.
  assert transpose_all(scale_tones(whole_tone_scale(0)), 2) == [2, 4, 6, 8, 10, 0]
  assert count_where(fn(pc) is_in_scale(pc, whole_tone_scale(0)) end, transpose_all(scale_tones(whole_tone_scale(0)), 2)) == 6
  assert count_where(fn(pc) is_in_scale(pc, whole_tone_scale(0)) end, transpose_all(scale_tones(whole_tone_scale(0)), 1)) == 0
end

test "scale membership and degree"
  assert scale_degree_of(7, major_scale(0)) == 4
  assert scale_degree_of(0, major_scale(0)) == 0
  assert scale_degree_of(1, major_scale(0)) == 0 - 1
  # The octave restatement must not be counted as an eighth degree.
  assert size(scale_tones(major_scale(0))) == 7
  assert scale_degree_of(12, major_scale(0)) == 0
end

test "transposition is additive and reversible"
  assert transpose_all(major_triad(0), 7) == major_triad(7)
  assert transpose_all(transpose_all(major_scale(3), 5), 0 - 5) == major_scale(3)
  assert transpose_all(major_scale(0), 12) == major_scale(0)
  assert note_names_of([0, 4, 7]) == ["C", "E", "G"]
end

test "the four triad qualities are exactly the four ways to stack two thirds"
  assert diminished_triad(11) == [11, 2, 5]
  assert augmented_triad(0) == [0, 4, 8]
  assert sus4_triad(0) == [0, 5, 7]
  # An augmented triad divides the octave evenly, so its inversions are
  # augmented triads on other roots — the property that distinguishes it.
  assert triad_quality(invert_chord(augmented_triad(0), 1)) == "augmented"
  assert triad_quality(invert_chord(major_triad(0), 1)) == "unknown"
  assert triad_quality(major_triad(7)) == "major"
  assert triad_quality(minor_triad(2)) == "minor"
  assert triad_quality(diminished_triad(11)) == "diminished"
  assert triad_quality(sus2_triad(0)) == "sus2"
  assert triad_quality([0, 1, 2]) == "unknown"
end

test "every seventh quality classifies back to itself"
  built = [major_seventh(0), dominant_seventh(0), minor_seventh(0),
           half_diminished_seventh(0), diminished_seventh(0),
           minor_major_seventh(0), augmented_major_seventh(0),
           augmented_seventh(0)]
  assert map(fn(c) seventh_quality(c) end, built) == seventh_quality_names()
  # The three that are one semitone apart in exactly one voice, spelled out so
  # a transposed table or an off-by-one interval cannot pass.
  assert minor_seventh(0) == [0, 3, 7, 10]
  assert half_diminished_seventh(0) == [0, 3, 6, 10]
  assert diminished_seventh(0) == [0, 3, 6, 9]
  # A diminished seventh is symmetric: rotating it gives another one.
  assert seventh_quality(invert_chord(diminished_seventh(0), 2)) == "diminished seventh"
  assert diminished_seventh(3) == invert_chord(diminished_seventh(0), 1)
end

test "chord shape is independent of root, and naming reads back"
  assert chord_intervals(minor_triad(9)) == [0, 3, 7]
  assert chord_intervals(minor_triad(2)) == chord_intervals(minor_triad(9))
  assert chord_intervals([]) == []
  assert chord_from_root(7, [0, 4, 7]) == major_triad(7)
  assert chord_name([0, 4, 7]) == "C major"
  assert chord_name(dominant_seventh(7)) == "G dominant seventh"
  assert chord_name([]) == "unknown"
  # Three notes are never a seventh chord, whatever the intervals say.
  assert chord_quality([0, 4, 7, 11]) == "major seventh"
  assert chord_quality([0, 4, 7]) == "major"
  assert chord_quality([0, 4]) == "unknown"
end

test "inverting a chord as many times as it has notes returns it"
  assert invert_chord(major_triad(0), 3) == major_triad(0)
  assert invert_chord(major_triad(0), 1) == [4, 7, 0]
  assert invert_chord(major_seventh(0), 4) == major_seventh(0)
  assert invert_chord(major_triad(0), 0 - 1) == invert_chord(major_triad(0), 2)
  assert invert_chord([], 2) == []
end

test "the qualities of a major key are not chosen, they fall out"
  # The fact every first-year harmony student memorises, here derived from the
  # scale by stacking thirds. A hardcoded quality table would also pass this;
  # nothing in the implementation has one.
  assert scale_triad_qualities(major_scale(0)) ==
    ["major", "minor", "minor", "major", "major", "minor", "diminished"]
  assert scale_seventh_qualities(major_scale(0)) ==
    ["major seventh", "minor seventh", "minor seventh", "major seventh",
     "dominant seventh", "minor seventh", "half-diminished seventh"]
  # Exactly one dominant seventh in a major key — that uniqueness is what makes
  # it able to name the key.
  assert count_of(scale_seventh_qualities(major_scale(0)), "dominant seventh") == 1
end

test "chords on scale degrees are real chords in the scale"
  assert scale_triad(major_scale(0), 0) == [0, 4, 7]
  assert scale_triad(major_scale(0), 1) == [2, 5, 9]
  assert scale_triad(major_scale(0), 6) == [11, 2, 5]
  assert scale_seventh(major_scale(0), 4) == [7, 11, 2, 5]
  assert scale_seventh(major_scale(0), 4) == dominant_seventh(7)
  # Every note of a scale chord is in the scale — the invariant the wrapping
  # index exists to preserve.
  assert count_where(fn(pc) is_in_scale(pc, major_scale(3)) end, scale_seventh(major_scale(3), 5)) == 4
  assert scale_triad([], 0) == []
  assert scale_seventh([], 0) == []
end

test "harmonic minor is what puts a dominant seventh under a minor tonic"
  # Natural minor's chord on V is a MINOR seventh and cannot pull home;
  # harmonic minor's is a dominant seventh. That swap is the whole reason the
  # raised seventh exists, and it is the payoff test for both scales.
  assert nth(4, scale_seventh_qualities(minor_scale(9))) == "minor seventh"
  assert nth(4, scale_seventh_qualities(harmonic_minor_scale(9))) == "dominant seventh"
  # Natural minor does own one dominant seventh — on the subtonic VII, which
  # points at the relative major and not at the tonic. Asserting "none" here
  # would be the plausible-sounding wrong claim.
  assert nth(6, scale_seventh_qualities(minor_scale(9))) == "dominant seventh"
  assert nth(0, scale_seventh_qualities(harmonic_minor_scale(9))) == "minor-major seventh"
  assert nth(6, scale_seventh_qualities(harmonic_minor_scale(9))) == "diminished seventh"
  assert nth(2, scale_seventh_qualities(harmonic_minor_scale(9))) == "augmented major seventh"
end

test "stepping by fifths visits every pitch exactly once"
  # 7 and 12 are coprime, so the circle closes only after all twelve. A step
  # size sharing a factor with 12 — 3, 4, 6 — would repeat early, so this is a
  # real check on the 7 and not a restatement of it.
  c = circle_of_fifths(0)
  assert size(c) == 12
  assert c == [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
  assert count_where(fn(pc) contains(c, pc) end, range(0, 12)) == 12
  assert transpose_note(0, 7 * 12) == 0
  assert fifth_down(fifth_up(4)) == 4
  assert first(circle_of_fifths(9)) == 9
end

test "key signatures, against the ones everybody can check"
  assert key_signature(0) == 0
  assert key_signature(7) == 1
  assert key_signature(2) == 2
  assert key_signature(11) == 5
  assert key_signature(5) == 0 - 1
  assert key_signature(10) == 0 - 2
  assert key_signature(1) == 0 - 5
  assert sharp_count(2) == 2
  assert flat_count(2) == 0
  assert flat_count(10) == 2
  assert key_uses_flats(10) == true
  assert key_uses_flats(2) == false
  # Each step round the circle adds one sharp, all the way to six.
  assert map(fn(i) key_signature(transpose_note(0, 7 * i)) end, range(0, 7)) == range(0, 7)
end

test "the accidental count is derivable from the notes, not just from the table"
  # Independent derivation: how many notes of the key are not in C major. It
  # must equal the signature for every key with five or fewer accidentals.
  agree = filter(fn(k) abs(key_signature(k)) < 6 end, range(0, 12))
  assert size(agree) == 11
  assert map(fn(k) count_where(fn(pc) !is_in_scale(pc, major_scale(0)) end, scale_tones(major_scale(k))) end, agree) ==
         map(fn(k) abs(key_signature(k)) end, agree)
  # F# major is the one key where they part company, because its sixth sharp is
  # E# — a sharp on a white key. Pinned so the boundary is documented, not lost.
  assert abs(key_signature(6)) == 6
  assert count_where(fn(pc) !is_in_scale(pc, major_scale(0)) end, scale_tones(major_scale(6))) == 5
end

test "accidentals come in a fixed order, and flats reverse the sharps"
  assert sharps_in_order() == ["F", "C", "G", "D", "A", "E", "B"]
  assert flats_in_order() == ["B", "E", "A", "D", "G", "C", "F"]
  assert key_accidentals(0) == []
  assert key_accidentals(7) == ["F"]
  assert key_accidentals(2) == ["F", "C"]
  assert key_accidentals(5) == ["B"]
  assert key_accidentals(10) == ["B", "E"]
  # The named accidentals must be the letters that actually change in the key.
  assert size(key_accidentals(11)) == 5
  assert key_note_names(7) == ["G", "A", "B", "C", "D", "E", "F#"]
  assert key_note_names(5) == ["F", "G", "A", "Bb", "C", "D", "E"]
  assert key_note_names(1) == ["Db", "Eb", "F", "Gb", "Ab", "Bb", "C"]
  # The documented limit: F# major's seventh degree should be written E#, and a
  # pitch class cannot carry the letter that would say so.
  assert last(key_note_names(6)) == "F"
end

test "relative keys share a signature; parallel keys do not"
  assert relative_minor(0) == 9
  assert relative_major(9) == 0
  assert map(fn(pc) relative_major(relative_minor(pc)) end, range(0, 12)) == range(0, 12)
  # The defining property, checked for all twelve rather than for C alone.
  assert map(fn(pc) minor_key_signature(relative_minor(pc)) end, range(0, 12)) ==
         map(fn(pc) key_signature(pc) end, range(0, 12))
  assert minor_key_signature(9) == 0
  assert minor_key_signature(4) == 1
  # C major and C minor are parallel, not relative: same tonic, different
  # signature. Confusing the two is the classic error and this catches it.
  assert minor_key_signature(0) == 0 - 3
  assert key_signature(0) == 0
end

test "spelling follows the key"
  assert note_name_for_key(3, 10) == "Eb"
  assert note_name_for_key(3, 11) == "D#"
  assert note_name_for_key(0, 5) == "C"
  # Same pitch, two keys, two correct answers — which is the whole reason
  # note_name alone is not enough.
  assert is_enharmonic(note_name_for_key(3, 10), note_name_for_key(3, 11)) == true
end

# --- MIDI numbers, frequency, and tuning --------------------------------------

# Octave numbering follows scientific pitch notation, the convention the
# existing midi_to_hz already commits to: A4 is 69, so middle C is 60 and is
# called C4. Some hardware calls that same note C3; nothing here does.
def note_to_midi(pc, octave)
  (octave + 1) * 12 + pc
end

# floor_div rather than a bare division, so notes below C0 keep counting down
# instead of collapsing toward zero: MIDI 0 is C-1 and MIDI 0 - 1 is B-2.
def midi_octave(n)
  floor_div(n, 12) - 1
end

# The MIDI-facing name for the same fold, so the pair that decomposes a note
# number — pitch class and octave — reads as a pair at the call site.
def midi_pitch_class(n)
  pitch_class(n)
end

def midi_note_name(n)
  concat(note_name(n), to_s(midi_octave(n)))
end

def note_to_hz(pc, octave)
  midi_to_hz(note_to_midi(pc, octave))
end

# The inverse of midi_to_hz. Returns a FRACTIONAL note number on purpose — the
# fraction is how sharp or flat the pitch is, and rounding it away here would
# throw out the only thing a tuner wants.
def hz_to_midi(hz)
  69 + 12 * log(hz / 440) / log(2)
end

def nearest_midi(hz)
  round(hz_to_midi(hz))
end

# How far off the nearest tempered note a frequency is, in cents. Signed:
# positive is sharp.
def cents_off(hz)
  100 * (hz_to_midi(hz) - nearest_midi(hz))
end

# Cents are a logarithmic unit — 1200 to the octave — which is what makes
# intervals addable. Everything about tuning error is stated in them because
# a ratio difference means nothing until it is put on this scale.
def cents_of_ratio(ratio)
  1200 * log(ratio) / log(2)
end

def cents_between(hz1, hz2)
  cents_of_ratio(hz2 / hz1)
end

# Equal temperament: the octave cut into twelve identical ratios. Every
# interval is slightly wrong and every key is equally usable, which is the
# trade the whole system is.
def equal_ratio(semitones)
  expt(2, semitones / 12)
end

# Five-limit just intonation: intervals as small whole-number ratios, which is
# what makes them beat-free. The tritone is the weak entry — 45/32 is one of
# several defensible choices (7/5 and 64/45 are others) and it is the one that
# stays inside the same 5-limit lattice as its neighbours.
def just_ratio_table()
  [[1, 1], [16, 15], [9, 8], [6, 5], [5, 4], [4, 3],
   [45, 32], [3, 2], [8, 5], [5, 3], [16, 9], [15, 8]]
end

# Ratio as exact numerator and denominator, octave-extended: an interval wider
# than an octave doubles the numerator per octave rather than folding back to a
# unison, so 19 semitones is 3/1 and not 3/2. Reduced by gcd so the answer is
# canonical and two callers building the same interval two ways compare equal.
def just_ratio_parts(semitones)
  base = nth(pitch_class(semitones), just_ratio_table())
  octaves = floor_div(semitones, 12)
  if octaves >= 0
    reduce_ratio(nth(0, base) * expt(2, octaves), nth(1, base))
  else
    reduce_ratio(nth(0, base), nth(1, base) * expt(2, 0 - octaves))
  end
end

def reduce_ratio(num, den)
  g = gcd(num, den)
  [floor_div(num, g), floor_div(den, g)]
end

def just_ratio(semitones)
  parts = just_ratio_parts(semitones)
  nth(0, parts) / nth(1, parts)
end

def just_hz(base_hz, semitones)
  base_hz * just_ratio(semitones)
end

# How far equal temperament sits from the pure interval, in cents. Signed, and
# the sign is the point: the tempered fifth is narrow by two cents and nobody
# minds, the tempered major third is wide by fourteen and everybody hears it.
def temperament_error_cents(semitones)
  cents_of_ratio(just_ratio(semitones) / equal_ratio(semitones))
end

test "MIDI numbers and octave names round-trip"
  assert note_to_midi(0, 4) == 60
  assert note_to_midi(9, 4) == 69
  assert note_to_midi(0, 0 - 1) == 0
  # Every note number rebuilds from the pitch class and octave it decomposes
  # into. A truncating divide would break this below MIDI 0, and an off-by-one
  # octave base would break it everywhere.
  assert map(fn(n) note_to_midi(midi_pitch_class(n), midi_octave(n)) end, range(0, 128)) == range(0, 128)
  assert midi_octave(0 - 1) == 0 - 2
  assert midi_note_name(60) == "C4"
  assert midi_note_name(69) == "A4"
  assert midi_note_name(0) == "C-1"
  assert midi_note_name(127) == "G9"
end

test "hz_to_midi inverts midi_to_hz"
  assert near(hz_to_midi(440), 69) == true
  assert near(hz_to_midi(880), 81) == true
  assert near(hz_to_midi(220), 57) == true
  # The round trip over the whole keyboard, both ways.
  assert count_where(fn(n) near(hz_to_midi(midi_to_hz(n)), n) end, range(21, 109)) == 88
  assert near_within(midi_to_hz(hz_to_midi(261.6255653)), 261.6255653, 0.000001) == true
  # Middle C, a number anyone can look up.
  assert near_within(midi_to_hz(60), 261.6255653, 0.000001) == true
  assert near_within(note_to_hz(0, 4), 261.6255653, 0.000001) == true
end

test "a tuner: nearest note and cents off"
  assert nearest_midi(440) == 69
  assert nearest_midi(445) == 69
  assert near(cents_off(440), 0) == true
  # 445 Hz is a familiar orchestral sharpness — just under 20 cents.
  assert near_within(cents_off(445), 19.5622, 0.001) == true
  # Sign is meaningful: flat reads negative, and an implementation using an
  # absolute distance would still pass every assertion above.
  assert cents_off(435) < 0
  assert cents_off(445) > 0
end

test "cents are logarithmic, so intervals add"
  assert near(cents_between(440, 880), 1200) == true
  assert near(cents_between(440, 440), 0) == true
  assert near(cents_of_ratio(1), 0) == true
  # Antisymmetry — the check a formula with the arguments swapped fails.
  assert near(cents_between(440, 660) + cents_between(660, 440), 0) == true
  # Two fifths up and an octave down is a major second, added in cents.
  assert near_within(cents_of_ratio(1.5) + cents_of_ratio(1.5) - 1200, cents_of_ratio(1.5 * 1.5 / 2), 0.000001) == true
end

test "just ratios are exact small integers, and extend past the octave"
  assert just_ratio_parts(0) == [1, 1]
  assert just_ratio_parts(7) == [3, 2]
  assert just_ratio_parts(4) == [5, 4]
  assert just_ratio_parts(5) == [4, 3]
  # Past an octave the ratio grows rather than folding back to a unison.
  assert just_ratio_parts(12) == [2, 1]
  assert just_ratio_parts(19) == [3, 1]
  assert just_ratio_parts(24) == [4, 1]
  assert just_ratio_parts(0 - 12) == [1, 2]
  assert near(just_ratio(7), 1.5) == true
  assert near(just_hz(440, 7), 660) == true
  # A fifth times a fourth is an octave, exactly, which only holds if both
  # entries are the true ratios and not decimal approximations.
  assert near(just_ratio(7) * just_ratio(5), 2) == true
end

test "equal temperament is wrong everywhere, by known amounts"
  assert near(equal_ratio(12), 2) == true
  assert near(equal_ratio(0), 1) == true
  assert near_within(equal_ratio(7), 1.4983070768766815, 0.000001) == true
  # The two numbers every tuning argument is about: the tempered fifth is two
  # cents narrow, the tempered major third fourteen cents wide. Opposite signs,
  # so an implementation that lost the direction fails here.
  assert near_within(temperament_error_cents(7), 1.9550, 0.001) == true
  assert near_within(temperament_error_cents(4), 0 - 13.6863, 0.001) == true
  assert temperament_error_cents(7) > 0
  assert temperament_error_cents(4) < 0
  assert near(temperament_error_cents(0), 0) == true
  assert near(temperament_error_cents(12), 0) == true
end

test "the commas — why twelve pure fifths cannot close the circle"
  # Stack twelve just fifths and you land nearly a quarter-semitone above seven
  # octaves. That gap, the Pythagorean comma, is the reason equal temperament
  # exists at all, and 23.46 cents is a number from any textbook.
  assert near_within(cents_of_ratio(expt(1.5, 12) / expt(2, 7)), 23.4600, 0.001) == true
  # The syntonic comma, the other famous one: four just fifths against a just
  # major third.
  assert near_within(cents_of_ratio(81 / 80), 21.5063, 0.001) == true
  # Twelve TEMPERED fifths close exactly. That is the whole trade.
  assert near(cents_of_ratio(expt(equal_ratio(7), 12) / expt(2, 7)), 0) == true
end
