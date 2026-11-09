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

**Output is the terminal's, and colour is a theme's.** `show` writes a node
to stdout or stderr, `styled` wraps it in SGR codes, and `step` and
`show_step` draw one step of a run with its mark and duration. A named ink
is the terminal's own slot. A hex or theme colour is read through the paint
function a caller passes, which gamen's `styled` and `show` build from a
theme, so this package holds no colour model.

`is_alpha` is delegated to moji, not re-derived: an ANSI final byte is any
ASCII letter, which is exactly what the Rust original's `is_ascii_alphabetic`
checks, and hand-rolling a character class here would drift from it.

    age_s(0) #=> "0s"
"""

use("deeta", [:get_str])
use("kyohi", [:raised])
use("moji", %i[checked is_alpha is_blank lines take_chars])
use("retsu", %i[first is_empty last rest size])
use("settei")

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
  get_str(cap, :stdout, "")
end

@doc """
stderr_of: The captured stderr; "" when absent or not a capture.

    stderr_of(42) #=> ""
"""
def stderr_of(cap)
  get_str(cap, :stderr, "")
end

@doc """
spawn_defaults: the settings that choose which blue a blue program spawns. from_path off means the blue running the program; settei lays ~/.config/blue_spawn/blue_spawn.yaml over it, then BLUE_SPAWN_FROM_PATH=1 turns PATH lookup back on.

    spawn_defaults["from_path"] #=> false
"""
def spawn_defaults()
  {"from_path" => false}
end

@doc """
blue_from: the blue to spawn given the from_path setting and the running blue's path: `blue` on PATH when from_path is on or there is no running blue, else that path.

    blue_from(false, "/b/blue") #=> "/b/blue"
"""
def blue_from(from_path, exe)
  if from_path or exe.nil?
    "blue"
  else
    exe
  end
end

@doc """
blue_exe: the blue a program spawns to run blue: the blue running it (self_exe), so a generator run by a built blue never reaches an older blue on PATH. `blue` on PATH when self_exe is nil or BLUE_SPAWN_FROM_PATH=1.

    blue_from(true, "/b/blue") #=> "blue"
"""
def blue_exe()
  blue_from(settei::read("blue_spawn", spawn_defaults)["from_path"], self_exe)
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

def sequence(prefix, value, paint)
  if paint.nil?
    raise(
      :bad_option,
      "#{to_s(value)} is a colour, and styled reads a colour only through the paint function its context holds, as gamen's styled and show give it"
    )
  end
  c = paint(value)
  "#{prefix};2;#{to_s(round(c[:r]))};#{to_s(round(c[:g]))};#{to_s(round(c[:b]))}"
end

@doc """
inks: the sixteen ANSI colour slots by name with their SGR codes, so a terminal paints text in its own theme (Nord on a pleme-io terminal) and blue carries no hex.

    get(inks, :cyan) #=> "36"
"""
def inks()
  {
    black: "30",
    red: "31",
    green: "32",
    yellow: "33",
    blue: "34",
    magenta: "35",
    cyan: "36",
    white: "37",
    bright_black: "90",
    bright_red: "91",
    bright_green: "92",
    bright_yellow: "93",
    bright_blue: "94",
    bright_magenta: "95",
    bright_cyan: "96",
    bright_white: "97"
  }
end

@doc """
ink_code: the SGR code of an ANSI slot name, refusing a name that is no slot.

    ink_code(:bright_black) #=> "90"
"""
def ink_code(name)
  code = get(inks, name)
  if code.nil?
    raise(
      :bad_option,
      "no ink #{to_s(name)}; an ink is one of the sixteen ANSI slots"
    )
  end
  code
end

def codes(node, ctx)
  flags = filter(
    (p) -> get(node, first(p)) == true,
    [[:bold, "1"], [:dim, "2"], [:underline, "4"]]
  )
  colors = filter(
    (x) -> x != nil,
    [
      if node[:ink].nil?
        nil
      else
        ink_code(node[:ink])
      end,
      if node[:fg].nil?
        nil
      else
        sequence("38", node[:fg], ctx[:paint])
      end,
      if node[:bg].nil?
        nil
      else
        sequence("48", node[:bg], ctx[:paint])
      end
    ]
  )
  append(map((p) -> p[1], flags), colors)
end

@doc """
styled: a node as text: a string, a list of nodes, or a record with text and its flags, ink, fg and bg, wrapped in SGR codes when `ctx` has color on; a fg or bg colour is read through the context's paint function.

    styled({text: "x", ink: :cyan}, {color: false}) #=> "x"
"""
def styled(node, ctx)
  if string?(node)
    node
  elsif list?(node)
    join(map((n) -> styled(n, ctx), node), "")
  elsif map?(node) and string?(node[:text])
    on = codes(node, ctx)
    if is_empty(on) or not ctx[:color]
      node[:text]
    else
      "#{esc_char}[#{join(on, ";")}m#{node[:text]}#{esc_char}[0m"
    end
  else
    raise(:bad_option, "a node is text, a list of nodes, or a record with text")
  end
end

def colored?(no_color)
  no_color.nil? or no_color == ""
end

def color_default()
  colored?(getenv("NO_COLOR"))
end

def writer(opts)
  sink = opts[:sink]
  to = opts[:to] or :stdout
  if sink != nil
    sink
  elsif to == :stdout
    (text) -> write_stdout(text)
  elsif to == :stderr
    (text) -> write_stderr(text)
  else
    raise(:bad_option, "show writes to :stdout or :stderr, got #{to_s(to)}")
  end
end

@doc """
show: put a node on the terminal as styled output.
"""
def show(node, opts)
  checked(opts, %i[paint color sink to newline])
  write = writer(opts)
  on = opts[:color]
  ctx = {
    color: if on.nil?
      color_default
    else
      on
    end,
    paint: opts[:paint]
  }
  text = styled(node, ctx)
  if opts[:newline] == false
    write(text)
  else
    write(unlines([text]))
  end
  nil
end

@doc """
terminal?: whether a file descriptor is a terminal, asked of `test -t`.

    terminal?(9) #=> false
"""
def terminal?(fd)
  exec_check("test", "-t", to_s(fd)) == 0 rescue false
end

@doc """
step_marks: the symbol each state of a step shows.

    get(step_marks, :done) #=> "✅"
"""
def step_marks()
  {running: "⏳", done: "✅", failed: "❌", skipped: "➖", warn: "⚠️"}
end

@doc """
duration_text: milliseconds as a person reads a duration: tenths of a second under a minute, minutes and seconds above.

    duration_text(87240) #=> "1m 27s"
"""
def duration_text(ms)
  if ms < 60000
    "#{to_s(round(ms / 100) / 10)}s"
  else
    m = floor(ms / 60000)
    sec = floor((ms - m * 60000) / 1000)
    pad = if sec < 10
      "0"
    else
      ""
    end
    "#{to_s(m)}m #{pad}#{to_s(sec)}s"
  end
end

@doc """
step: one step of a run as a node: the state's mark, its place as [at/of], its name in bold, an optional note after a dash, the duration once known, and an ellipsis while it runs.

    styled(step({state: :done, at: 3, of: 11, name: "regen", ms: 87240}), {color: false}) #=> "✅ [3/11] regen (1m 27s)"
"""
def step(s)
  checked(s, %i[state at of name note ms])
  state = s[:state]
  mark = get(step_marks, state)
  if mark.nil?
    raise(
      :bad_option,
      "a step state is running, done, failed, skipped or warn, got #{to_s(state)}"
    )
  end
  tone = get(
    {running: :cyan, failed: :red, warn: :yellow, skipped: :bright_black},
    state
  )
  name = if tone.nil?
    {text: s[:name], bold: true}
  else
    {text: s[:name], bold: true, ink: tone}
  end
  note = if s[:note].nil?
    []
  else
    [{text: " — ", ink: :bright_black}, s[:note]]
  end
  tail = if s[:ms] != nil
    [{text: " (#{duration_text(s[:ms])})", ink: :bright_black}]
  elsif state == :running
    [{text: " …", ink: :bright_black}]
  else
    []
  end
  append(
    [
      "#{mark} ",
      {text: "[#{to_s(s[:at])}/#{to_s(s[:of])}]", ink: :bright_black},
      " ",
      name
    ],
    note,
    tail
  )
end

@doc """
show_step: write one step line, to stderr unless told otherwise, painted only when NO_COLOR is unset and the stream is a terminal.

    show_step({state: :skipped, at: 1, of: 1, name: "x"}, {sink: (_t) -> nil}) #=> nil
"""
def show_step(s, opts)
  to = opts[:to] or :stderr
  color = if opts[:color].nil?
    color_default and
      terminal?(
        if to == :stdout
          1
        else
          2
        end
      )
  else
    opts[:color]
  end
  show(step(s), assoc(assoc(opts, :to, to), :color, color))
end

@doc """
run_capture: run a command and answer {ok: true, stdout} when it exits 0, else {ok: false, why} naming the command and its last stderr line, or that it could not start.

    run_capture(["blue-no-such-command"])[:ok] #=> false
"""
def run_capture(argv)
  cap = exec_capture(*argv) rescue nil
  if cap.nil?
    {ok: false, why: "#{first(argv)} could not be started"}
  elsif status_of(cap) != 0
    {
      ok: false,
      why: "#{first(argv)} exited #{to_s(status_of(cap))}: #{last_nonempty_line(stderr_of(cap))}"
    }
  else
    {ok: true, stdout: stdout_of(cap)}
  end
end

@doc """
load_and_cores: the host's one-minute load and its online cores, as [load1, cores], each nil when the host does not say.

    size(load_and_cores) #=> 2
"""
def load_and_cores()
  la = read_or("/proc/loadavg", "")
  load1 = if la != ""
    to_float(first(split(la, " ")))
  else
    r = run_capture(%w[sysctl -n vm.loadavg])
    if r[:ok]
      to_float(split(trim(r[:stdout]), " ")[1])
    end
  end
  c = run_capture(%w[getconf _NPROCESSORS_ONLN])
  cores = if c[:ok]
    to_int(trim(c[:stdout]))
  end
  [load1, cores]
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

test "blue_from takes the running blue unless from_path is on or there is none"
  assert blue_from(false, "/b/blue") == "/b/blue"
  assert blue_from(true, "/b/blue") == "blue"
  assert blue_from(false, nil) == "blue"
  assert blue_from(true, nil) == "blue"
  assert spawn_defaults == {"from_path" => false}
end

test "blue_exe is the running blue, and BLUE_SPAWN_FROM_PATH=1 makes it PATH's"
  if not settei::read("blue_spawn", spawn_defaults)["from_path"]
    assert blue_exe == blue_from(false, self_exe)
  end
  if self_exe != nil
    dir = path_join(getenv("TMPDIR", "/tmp"), "shisutemu-#{to_s(now_ns)}")
    mkdir_p(dir)
    prog = path_join(dir, "probe.b")
    write_program(
      prog,
      unlines(["use(\"shisutemu\")", "write_stdout(shisutemu::blue_exe)"])
    )
    own = exec_with_env([], self_exe, "run", "--quiet", prog)
    path = exec_with_env(
      [%w[BLUE_SPAWN_FROM_PATH 1]],
      self_exe,
      "run",
      "--quiet",
      prog
    )
    bad = exec_with_env(
      [%w[BLUE_SPAWN_FROM_PATH maybe]],
      self_exe,
      "run",
      "--quiet",
      prog
    )
    rm_rf(dir)
    assert stdout_of(own) == self_exe
    assert stdout_of(path) == "blue"
    assert status_of(bad) != 0
    assert contains?(stderr_of(bad), "BLUE_SPAWN_FROM_PATH")
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

test "styled paints flags, ink, then fg and bg through the paint function"
  esc = esc_char
  ctx = {color: true, paint: (_v) -> {r: 1, g: 2, b: 3}}
  assert styled({text: "x", ink: :cyan}, ctx) == "#{esc}[36mx#{esc}[0m"
  assert styled({text: "x", bold: true, ink: :bright_black, fg: "c"}, ctx) ==
    "#{esc}[1;90;38;2;1;2;3mx#{esc}[0m"
  assert styled({text: "x", bg: "c"}, ctx) == "#{esc}[48;2;1;2;3mx#{esc}[0m"
  assert styled({text: "x", ink: :cyan}, {color: false}) == "x"
  assert styled([], ctx) == ""
  assert size(map_entries(inks)) == 16
  assert raised(() -> styled({text: "x", ink: :teal}, ctx)) == :bad_option
end

test "a colour with no paint function is refused, and a node with none needs none"
  assert raised(() -> styled({text: "x", fg: "#ff0000"}, {color: true})) ==
    :bad_option
  assert styled({text: "x", bold: true}, {color: false}) == "x"
end

test "NO_COLOR turns color off unless it is unset or empty"
  assert colored?(nil) == true
  assert colored?("") == true
  assert colored?("1") == false
  assert colored?("anything") == false
end

test "the writer goes to stdout or stderr and refuses any other place"
  assert writer({})("").nil?
  assert writer({to: :stdout})("").nil?
  assert writer({to: :stderr})("").nil?
  assert raised(() -> writer({to: :file})) == :bad_option
  assert raised(() -> writer({to: "stderr"})) == :bad_option
end

test "show refuses an unknown option, and a theme belongs to gamen"
  assert raised(() -> show("a", {sink: (_t) -> nil, style: 1})) == :bad_option
  assert raised(() -> show("a", {sink: (_t) -> nil, theme: nil})) == :bad_option
  assert show("a", {sink: (_t) -> nil}).nil?
end

test "show writes stdout by default and stderr on request, each to its own stream"
  if self_exe != nil
    dir = path_join(getenv("TMPDIR", "/tmp"), "shisutemu-#{to_s(now_ns)}")
    mkdir_p(dir)
    prog = path_join(dir, "probe.b")
    write_program(
      prog,
      unlines(
        [
          "use(\"shisutemu\")",
          "shisutemu::show(\"out\", {color: false})",
          "shisutemu::show(\"err\", {to: :stderr, newline: false})"
        ]
      )
    )
    cap = exec_with_env([], self_exe, "run", "--quiet", prog)
    rm_rf(dir)
    assert status_of(cap) == 0
    assert stdout_of(cap) == unlines(["out"])
    assert stderr_of(cap) == "err"
  end
end

test "duration_text: tenths under a minute, minutes and padded seconds above"
  assert duration_text(0) == "0s"
  assert duration_text(87) == "0.1s"
  assert duration_text(59940) == "59.9s"
  assert duration_text(60000) == "1m 00s"
  assert duration_text(551_000) == "9m 11s"
end

test "a step line reads mark, place, name, note and duration, and refuses an unknown state"
  plain = {color: false}
  assert styled(step({state: :running, at: 1, of: 5, name: "guard"}), plain) ==
    "⏳ [1/5] guard …"
  assert styled(
    step(
      {state: :running, at: 2, of: 5, name: "wait", note: "held", ms: 60000}
    ),
    plain
  ) == "⏳ [2/5] wait — held (1m 00s)"
  assert styled(
    step({state: :skipped, at: 2, of: 5, name: "wait", note: "free"}),
    plain
  ) == "➖ [2/5] wait — free"
  assert styled(
    step({state: :failed, at: 4, of: 5, name: "switch"}),
    {color: true}
  ) ==
    "❌ #{esc_char}[90m[4/5]#{esc_char}[0m #{esc_char}[1;31mswitch#{esc_char}[0m"
  assert raised(() -> step({state: :gone, at: 1, of: 1, name: "x"})) ==
    :bad_option
  assert raised(() -> step({state: :done, at: 1, of: 1, name: "x", eta: 1})) ==
    :bad_option
end

test "show_step writes one line through the sink and keeps colour off when told"
  seen = [""]
  sink = (t) -> set!(seen, [concat(first(seen), t)])
  assert show_step(
    {state: :done, at: 1, of: 2, name: "x", ms: 1500},
    {sink:, color: false}
  ).nil?
  assert first(seen) == unlines(["✅ [1/2] x (1.5s)"])
  assert terminal?(9) == false
end

test "run_capture answers stdout on success and why on failure or no start"
  assert run_capture(["blue-no-such-command-xyz"]) ==
    {ok: false, why: "blue-no-such-command-xyz could not be started"}
  assert run_capture(%w[sh -c true]) == {ok: true, stdout: ""}
  assert run_capture(["sh", "-c", "echo boom >&2; exit 3"]) ==
    {ok: false, why: "sh exited 3: boom"}
end

test "load_and_cores answers the load and a positive core count on a host that has them"
  lc = load_and_cores
  assert size(lc) == 2
  assert lc[1].nil? or lc[1] > 0
end
