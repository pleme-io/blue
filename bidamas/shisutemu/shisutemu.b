@moduledoc """
shisutemu (システム) — the system.

Layered on the runtime's host-side sys surface (blue-lang-runtime's `sys`
module, behind the `sys` cargo feature): process, filesystem, clock. The
primitives there are exactly as honest as the OS — `read_file` raises when
the file is not there — so this package is where the total wrappers live.
A widget like the sentinela SwiftBar plugin must not die because a log is
missing; that is the ordinary case, not the exceptional one.

# Three rules this package holds

**Total where the primitive is not.** `read_file` raises on a missing file;
`read_or` answers a default. `file_mtime_ms` raises; `file_age_ms` answers
nil. The capture alist accessors answer a sensible zero value rather than
leaking json_get's type error. A caller should be able to read a file, an
exit code or a clock without surrounding it in guards.

**A capture is an alist, and the accessors read it without needing to know
that.** `exec_capture` returns `((:status N) (:stdout "…") (:stderr "…"))`;
`status_of`/`stdout_of`/`stderr_of` are the one place the shape is known, so
the shape can change without touching a call site.

**Formatting is deterministic.** `age_s` mirrors the sentinela display
exactly: whole seconds under a minute, whole minutes under an hour, and
`h`/`m` from there. `age_s(3600000)` is "1h0m", not "1h" and not "1h00m" —
the exact string a human's eye is used to from the Rust original.

# What is deliberately absent

**No error handling, because blue has none.** There is no `rescue`; a
fallible call is guarded *before* it is made (`read_or` checks `is_file?`
first) or documented as raising (`json_parse` on garbage still raises — see
`deeta`). The one un-guardable race, a file vanishing between the check and
the read, is noted on `read_or` rather than pretended away.

**No stdout writer.** Raw output is the *final value* of a program: `blue run`
prints the last expression with `render`, which is the one path that does not
quote strings (every `print`/`println` renders through Value's Debug Display,
which quotes them). A multi-line widget is built as a list and joined with
"\n" as the last expression — see the sentinela-sui.b consumer.

`is_alpha` is delegated to moji, not re-derived: an ANSI final byte is any
ASCII letter, which is exactly what the Rust original's `is_ascii_alphabetic`
checks, and hand-rolling a character class here would drift from it.

    age_s(0) #=> "0s"
"""

use("moji", %i[is_alpha is_blank lines take_chars])
use("retsu", %i[first is_empty last rest])

# ── process captures ───────────────────────────────────────────────

@doc """
status_of: The exit status of a capture alist; 0 when the shape is wrong or the status
is missing. Total, because a capture should never make a caller choose
between the value and the error.

    status_of([1, 2]) #=> 0
"""
def status_of(cap)
  v = nil
  if not null?(cap) and list?(cap)
    v = json_get(cap, :status)
  end
  if integer?(v)
    v
  else
    0
  end
end

@doc """
stdout_of: The captured stdout; "" when absent or not a capture.

    stdout_of(nil) #=> ""
"""
def stdout_of(cap)
  v = nil
  if not null?(cap) and list?(cap)
    v = json_get(cap, :stdout)
  end
  if string?(v)
    v
  else
    ""
  end
end

@doc """
stderr_of: The captured stderr; "" when absent or not a capture.

    stderr_of(42) #=> ""
"""
def stderr_of(cap)
  v = nil
  if not null?(cap) and list?(cap)
    v = json_get(cap, :stderr)
  end
  if string?(v)
    v
  else
    ""
  end
end

# ── filesystem ─────────────────────────────────────────────────────

@doc """
read_or: The file's contents, or `default` when it is not a readable file.

The check is `is_file?`, not `path_exists`: a directory exists and is not
readable as text, and answering a directory's contents as if they were text
would be a lie. The residual race — the file being replaced between the check
and the read — raises rather than fabricating a default, which is the honest
direction for a file that existed a moment ago.

    read_or("/tmp", "fallback") #=> "fallback"
"""
def read_or(path, default)
  if is_file?(path)
    read_file(path)
  else
    default
  end
end

@doc """
file_age_ms: Milliseconds since the file was last modified, or nil when it is not a file.

nil, not a sentinel number: a missing log is a different question from a
stalled one, and a caller that conflates them cannot tell "never started"
from "stopped long ago". Branch on nil first.
"""
def file_age_ms(path)
  if is_file?(path)
    now_ms - file_mtime_ms(path)
  end
end

# ── text from the system ───────────────────────────────────────────

@doc """
last_nonempty_line: The last line of `text` that has content in it, or "" when there is none.

Built on moji's `lines` (which invents no trailing line) and `is_blank`, so
"\r\n" endings and trailing newlines are handled before this sees them. A
log whose final line is a blank or a spinner echo answers the line before.

    last_nonempty_line("") #=> ""
"""
def last_nonempty_line(text)
  ls = filter((l) -> not is_blank(l), lines(text))
  if is_empty(ls)
    ""
  else
    last(ls)
  end
end

@doc """
esc_char: The ESC character, spelled once. Blue strings accept `\u{1b}`.
"""
def esc_char()
  "\u{1b}"
end

@doc """
ansi_final: True when `c` is the final byte of an ANSI escape sequence: any ASCII letter.
This mirrors the Rust original's `is_ascii_alphabetic` — the sequences nix
writes into log files all end in a letter (m, J, K, A, …).
"""
def ansi_final(c)
  is_alpha(c)
end

@doc """
strip_ansi_from: Walk the characters, dropping every ESC-prefixed sequence.

The state machine: 0 = ordinary text, 1 = just saw ESC, 2 = inside a CSI
sequence (ESC [ … final byte). An ESC followed by anything other than "[" is
a two-character escape and is dropped whole; an ESC alone at the end is
dropped rather than leaked. This is deliberately the same scope as the Rust
original's strip_ansi — CSI SGR colouring — not a full VT parser (OSC title
sequences are outside it and documented so).
"""
def strip_ansi_from(cs, state, acc)
  if is_empty(cs)
    acc
  else
    c = first(cs)
    if state == 2
      if ansi_final(c)
        strip_ansi_from(rest(cs), 0, acc)
      else
        strip_ansi_from(rest(cs), 2, acc)
      end
    elsif state == 1
      if c == "["
        strip_ansi_from(rest(cs), 2, acc)
      else
        strip_ansi_from(rest(cs), 0, acc)
      end
    elsif c == esc_char
      strip_ansi_from(rest(cs), 1, acc)
    else
      strip_ansi_from(rest(cs), 0, concat(acc, c))
    end
  end
end

@doc """
strip_ansi: Remove ANSI escape sequences, matching the sentinela widget's strip_ansi.

    strip_ansi("") #=> ""
"""
def strip_ansi(s)
  strip_ansi_from(chars(s), 0, "")
end

# ── clock ──────────────────────────────────────────────────────────

@doc """
age_s: Compact human age for a millisecond duration — the sentinela display.

Whole seconds under a minute, whole minutes under an hour, hours and minutes
from there. The exact boundaries and the "1h0m" at one hour mirror the Rust
original byte for byte, which is what keeps the widget's text unchanged when
the implementation language changes.

    age_s(0) #=> "0s"
"""
def age_s(ms)
  if ms < 60000
    "#{floor(ms / 1000)}s"
  elsif ms < 3_600_000
    "#{floor(ms / 60000)}m"
  else
    "#{floor(ms / 3_600_000)}h#{floor(ms % 3_600_000 / 60000)}m"
  end
end

# ── git ────────────────────────────────────────────────────────────

@doc """
short_rev: A revision shortened to at most `n` characters; the em dash when it is absent.

`take_chars` clamps over-asking, so a short or exactly-n rev comes through
whole — the two cases a `substring(rev, 0, n)` on a short string would get
wrong. "—" is the sentinela's spelling for "no revision known", kept here so
a null head and an absent head cannot diverge.

    short_rev("", 8) #=> "—"
"""
def short_rev(rev, n)
  if null?(rev) or length(rev) == 0
    "—"
  else
    take_chars(rev, n)
  end
end

test "capture accessors read the process alist"
  cap = exec_capture("sh", "-c", "printf 'hi'; exit 3")
  assert status_of(cap) == 3
  assert stdout_of(cap) == "hi"
  assert stderr_of(cap) == ""
  cap2 = exec_capture("sh", "-c", "printf 'x' >&2")
  assert status_of(cap2) == 0
  assert stdout_of(cap2) == ""
  assert stderr_of(cap2) == "x"
end

test "capture accessors are total over non-captures"
  # Not a list at all: a capture's shape is the alist, and anything else must
  # not leak a type error out of an accessor whose job is to answer.
  assert status_of("nonsense") == 0
  assert stdout_of(nil) == ""
  assert stderr_of(42) == ""
  # A list that is not a proper alist still answers the zero value.
  assert status_of([1, 2]) == 0
  assert stdout_of([["a", 1]]) == ""
end

test "read_or is total over a missing file and honest about a directory"
  assert read_or("/definitely/not/here/blue-test", "fallback") == "fallback"
  # A directory exists but is not a readable text FILE — the check is is_file?.
  assert read_or("/tmp", "fallback") == "fallback"
end

test "read_or reads a real file"
  p = path_join(getenv("TMPDIR", "/tmp"), "blue-shisutemu-reador.txt")
  write_file(p, "hello")
  assert read_or(p, "fallback") == "hello"
  rm(p)
  assert path_exists(p) == false
end

test "file_age_ms answers nil for a missing file and a small age for a real one"
  assert file_age_ms("/definitely/not/here/blue-test").nil?
  p = path_join(getenv("TMPDIR", "/tmp"), "blue-shisutemu-age.txt")
  write_file(p, "x")
  age = file_age_ms(p)
  assert integer?(age) == true
  assert age >= 0
  assert age < 5000
  rm(p)
end

test "last_nonempty_line ignores trailing blank lines and invents none"
  assert last_nonempty_line(unlines(["a", "", "b"])) == "b"
  assert last_nonempty_line(join_lines(%w[a b])) == "b"
  assert last_nonempty_line("only") == "only"
  assert last_nonempty_line(unlines(["", ""])) == ""
  assert last_nonempty_line("") == ""
end

test "strip_ansi removes CSI sequences and leaves plain text alone"
  assert strip_ansi("\u{1b}[31mred\u{1b}[0m") == "red"
  assert strip_ansi("\u{1b}[1;32mgreen") == "green"
  assert strip_ansi("\u{1b}[2Jclear") == "clear"
  assert strip_ansi("plain") == "plain"
  assert strip_ansi("") == ""
  # A non-CSI escape is still a two-character escape and is dropped whole.
  assert strip_ansi("a\u{1b}7b") == "ab"
  # An ESC alone at the end cannot be a sequence; it must not leak.
  assert strip_ansi("x\u{1b}") == "x"
end

test "age_s mirrors the sentinela display exactly"
  assert age_s(0) == "0s"
  assert age_s(1000) == "1s"
  assert age_s(59000) == "59s"
  assert age_s(60000) == "1m"
  assert age_s(59999) == "59s"
  assert age_s(3_599_000) == "59m"
  # The exact-hour boundary is "1h0m", not "1h" — the Rust original's spelling.
  assert age_s(3_600_000) == "1h0m"
  assert age_s(3_660_000) == "1h1m"
  assert age_s(5_400_000) == "1h30m"
end

test "short_rev clamps to the width and answers the em dash for an absent rev"
  assert short_rev("abcdef123456", 8) == "abcdef12"
  # Short and exactly-n revs come through whole — take_chars clamps over-ask.
  assert short_rev("abc", 8) == "abc"
  assert short_rev("abcdefgh", 8) == "abcdefgh"
  assert short_rev(nil, 8) == "—"
  assert short_rev("", 8) == "—"
end
