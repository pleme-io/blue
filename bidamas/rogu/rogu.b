@moduledoc """
rogu (ログ) — logging: one structured line per call, JSON on stderr.

debug, info, warn and error each take a message and a record of fields and
write {at, level, message, ...fields} as one JSON object per line, when the
level is on. The level comes from BLUE_LOG (debug, info, warn or error;
info when unset); `enabled?` asks it, `level` reads it. `with` binds base
fields to a logger whose calls carry them on every line; `exporting` is the
same logger that also POSTs each line to a Vector HTTP source (observe's
vector_endpoint or VECTOR_ENDPOINT), on unless observe sets logs: :off.

    level_of("") #=> :info
"""

use("jisho", [:merge])
use("retsu", [:first, :is_empty, :size])
use("shisutemu", [:status_of, :stderr_of, :stdout_of])

def levels()
  [:debug, :info, :warn, :error]
end

def rank(lvl)
  at = position(lvl, levels)
  if at < 0
    raise(:bad_option, "no log level #{lvl}; one of debug, info, warn, error")
  end
  at
end

def level_of(raw)
  if raw.nil? or raw == ""
    :info
  else
    named = filter((l) -> to_s(l) == raw, levels)
    if is_empty(named)
      raise(:bad_option, "BLUE_LOG is #{raw}; one of debug, info, warn, error")
    end
    first(named)
  end
end

@doc """
level: the active level from BLUE_LOG; info when unset.
"""
def level()
  level_of(getenv("BLUE_LOG"))
end

def passes?(lvl, active)
  rank(lvl) >= rank(active)
end

@doc """
enabled?: whether a line at this level would be written.

    enabled?(:error) #=> true
"""
def enabled?(lvl)
  passes?(lvl, level)
end

def plain(fields)
  if fields.nil?
    {}
  else
    e = fields[:error]
    if error?(e)
      assoc(fields, :error, {kind: e.kind, message: e.message})
    else
      fields
    end
  end
end

def line(lvl, message, fields)
  rank(lvl)
  json_stringify(
    merge(
      plain(fields),
      {at: now_rfc3339, level: to_s(lvl), message: to_s(message)}
    )
  )
end

def emit(lvl, message, fields)
  if enabled?(lvl)
    write_stderr(unlines([line(lvl, message, fields)]))
  end
  nil
end

@doc """
debug: write a structured line at debug level.
"""
def debug(message, fields)
  emit(:debug, message, fields)
end

@doc """
info: write a structured line at info level.
"""
def info(message, fields)
  emit(:info, message, fields)
end

@doc """
warn: write a structured line at warn level.
"""
def warn(message, fields)
  emit(:warn, message, fields)
end

@doc """
error: write a structured line at error level; carries an error record.
"""
def error(message, fields)
  emit(:error, message, fields)
end

@doc """
on?: whether an observe record leaves a signal on; every signal is on unless set to :off.

    on?({logs: :off}, :traces) #=> true
"""
def on?(observe, signal)
  v = get(observe or {}, signal)
  v != :off and v != false
end

@doc """
given: a value that is neither nil nor empty text, else nil.

    given("") #=> nil
"""
def given(v)
  if v != nil and v != ""
    v
  end
end

@doc """
vector_endpoint: where logs ship: observe's vector_endpoint, else VECTOR_ENDPOINT, else nil.

    vector_endpoint({logs: :off, vector_endpoint: "http://v/"}) #=> nil
"""
def vector_endpoint(observe)
  if on?(observe, :logs)
    given((observe or {})[:vector_endpoint]) or given(getenv("VECTOR_ENDPOINT"))
  end
end

@doc """
ship: POST one JSON line to a Vector HTTP source; a failure is written to stderr, never raised.

    ship("http://127.0.0.1:1/", "{}", 100) #=> false
"""
def ship(url, text, wait_ms)
  http_request(
    "POST",
    url,
    {"Content-Type" => "application/json"},
    text,
    wait_ms
  )
  true
rescue e
  write_stderr(
    unlines([line(:warn, "log export failed", {error: e, endpoint: url})])
  )
  false
end

@doc """
emit_to: write one line at a level when it is on, and ship it when a url is given.

    emit_to(:debug, "m", {}, nil) #=> nil
"""
def emit_to(lvl, message, fields, url)
  if enabled?(lvl)
    text = line(lvl, message, fields)
    write_stderr(unlines([text]))
    if url != nil
      ship(url, text, 1000)
    end
  end
  nil
end

@doc """
logger: the logger record `with` and `exporting` build.

    get(logger({}, nil), :endpoint) #=> nil
"""
def logger(base, url)
  carry = (fields) -> merge(plain(base), plain(fields))
  {
    debug: (m, f) -> emit_to(:debug, m, carry(f), url),
    info: (m, f) -> emit_to(:info, m, carry(f), url),
    warn: (m, f) -> emit_to(:warn, m, carry(f), url),
    error: (m, f) -> emit_to(:error, m, carry(f), url),
    enabled: enabled?,
    endpoint: url
  }
end

@doc """
with: a logger that adds fields to every line.
"""
def with(base)
  logger(base, nil)
end

@doc """
exporting: a logger that adds fields to every line and ships each line to Vector, unless observe turns logs off.

    get(exporting({logs: :off}, {}), :endpoint) #=> nil
"""
def exporting(observe, base)
  logger(base, vector_endpoint(observe))
end

def probe(env, body)
  dir = path_join(getenv("TMPDIR", "/tmp"), "rogu-#{to_s(now_ns)}")
  mkdir_p(dir)
  prog = path_join(dir, "probe.b")
  write_program(prog, unlines(["use(\"rogu\")", body]))
  cap = exec_with_env(env, self_exe, "run", "--quiet", prog)
  rm_rf(dir)
  cap
end

def written(cap)
  map(json_read, filter((l) -> l != "", split(stderr_of(cap), line_break)))
end

test "levels are ordered and an unknown level is refused"
  assert levels == [:debug, :info, :warn, :error]
  assert map(rank, levels) == [0, 1, 2, 3]
  caught = begin
    rank(:trace)
  rescue e
    e
  end
  assert caught.kind == :bad_option
end

test "level reads BLUE_LOG text: each name, unset and empty mean info, a typo is refused"
  assert map(level_of, ["debug", "info", "warn", "error"]) == levels
  assert level_of(nil) == :info
  assert level_of("") == :info
  caught = begin
    level_of("verbose")
  rescue e
    e
  end
  assert caught.kind == :bad_option
  assert contains?(caught.message, "verbose") == true
end

test "a line passes when its level is at or above the active one"
  assert passes?(:debug, :debug) == true
  assert passes?(:debug, :info) == false
  assert passes?(:info, :info) == true
  assert passes?(:info, :warn) == false
  assert passes?(:warn, :info) == true
  assert passes?(:error, :error) == true
  assert passes?(:warn, :error) == false
  caught = begin
    passes?(:trace, :info)
  rescue e
    e
  end
  assert caught.kind == :bad_option
end

test "enabled? answers from the process BLUE_LOG and refuses an unknown level"
  active = level
  assert enabled?(active) == true
  assert enabled?(:error) == true
  caught = begin
    enabled?(:trace)
  rescue e
    e
  end
  assert caught.kind == :bad_option
end

test "a line is one JSON object: at, level, message, then the fields"
  rec = json_read(line(:warn, "disk low", {free: 3, host: "a"}))
  assert rec["level"] == "warn"
  assert rec["message"] == "disk low"
  assert rec["free"] == 3
  assert rec["host"] == "a"
  assert is_empty(rec["at"]) == false
  assert contains?(line(:info, "x", {}), line_break) == false
end

test "fields cannot overwrite at, level or message"
  rec = json_read(
    line(:info, "real", {level: "fake", message: "fake", at: "never"})
  )
  assert rec["level"] == "info"
  assert rec["message"] == "real"
  assert rec["at"] != "never"
end

test "nil fields and an empty record both log the bare line, and a non-text message is shown as text"
  assert size(map_entries(json_read(line(:info, "m", nil)))) == 3
  assert size(map_entries(json_read(line(:info, "m", {})))) == 3
  assert json_read(line(:info, 42, {}))["message"] == "42"
end

test "an error value in the fields is carried as its kind and message"
  caught = begin
    raise(:timeout, "slow")
  rescue e
    e
  end
  rec = json_read(line(:error, "failed", {error: caught, op: "pull"}))
  assert rec["error"]["kind"] == "timeout"
  assert rec["error"]["message"] == "slow"
  assert rec["op"] == "pull"
end

test "a line at an unknown level is refused before anything is written"
  caught = begin
    line(:trace, "x", {})
  rescue e
    e
  end
  assert caught.kind == :bad_option
end

test "stderr gets one JSON line per call and stdout gets nothing"
  if self_exe != nil
    cap = probe(
      [["BLUE_LOG", "debug"]],
      "rogu::info(\"pinned\", {rev: \"abc\", n: 2})"
    )
    assert status_of(cap) == 0
    assert stdout_of(cap) == ""
    rows = written(cap)
    assert size(rows) == 1
    row = first(rows)
    assert row["level"] == "info"
    assert row["message"] == "pinned"
    assert row["rev"] == "abc"
    assert row["n"] == 2
    assert is_empty(row["at"]) == false
  end
end

test "each verb writes its own level when everything is on"
  if self_exe != nil
    cap = probe(
      [["BLUE_LOG", "debug"]],
      join_lines(
        [
          "rogu::debug(\"a\", {})",
          "rogu::info(\"b\", {})",
          "rogu::warn(\"c\", {})",
          "rogu::error(\"d\", {})"
        ]
      )
    )
    assert map((r) -> r["level"], written(cap)) ==
      ["debug", "info", "warn", "error"]
    assert map((r) -> r["message"], written(cap)) == ["a", "b", "c", "d"]
  end
end

test "BLUE_LOG filters: warn drops debug and info, error keeps only error"
  if self_exe != nil
    body = join_lines(
      [
        "rogu::debug(\"a\", {})",
        "rogu::info(\"b\", {})",
        "rogu::warn(\"c\", {})",
        "rogu::error(\"d\", {})"
      ]
    )
    warn_run = probe([["BLUE_LOG", "warn"]], body)
    assert map((r) -> r["level"], written(warn_run)) == ["warn", "error"]
    error_run = probe([["BLUE_LOG", "error"]], body)
    assert map((r) -> r["level"], written(error_run)) == ["error"]
  end
end

test "with BLUE_LOG unset or empty the default is info"
  if self_exe != nil
    body = join_lines(["rogu::debug(\"a\", {})", "rogu::info(\"b\", {})"])
    cap = probe([["BLUE_LOG", ""]], body)
    assert map((r) -> r["message"], written(cap)) == ["b"]
  end
end

test "a call under a bad BLUE_LOG fails loudly and writes no line"
  if self_exe != nil
    cap = probe([["BLUE_LOG", "verbose"]], "rogu::info(\"x\", {})")
    assert status_of(cap) != 0
    assert contains?(stderr_of(cap), "BLUE_LOG is verbose") == true
    assert contains?(stderr_of(cap), "\"level\"") == false
  end
end

test "enabled? in a child follows BLUE_LOG"
  if self_exe != nil
    body = "write_stdout(to_s([rogu::enabled?(:debug), rogu::enabled?(:info), rogu::enabled?(:warn), rogu::enabled?(:error)]))"
    assert stdout_of(probe([["BLUE_LOG", "debug"]], body)) ==
      "[true, true, true, true]"
    assert stdout_of(probe([["BLUE_LOG", "warn"]], body)) ==
      "[false, false, true, true]"
    assert stdout_of(probe([["BLUE_LOG", ""]], body)) ==
      "[false, true, true, true]"
  end
end

test "with carries base fields on every line, and a call's own fields win"
  if self_exe != nil
    body = join_lines(
      [
        "l = rogu::with({svc: \"api\", n: 1})",
        "get(l, :info)(\"up\", {n: 2, extra: true})",
        "get(l, :debug)(\"hidden\", {})",
        "get(l, :error)(\"down\", nil)"
      ]
    )
    rows = written(probe([["BLUE_LOG", "info"]], body))
    assert map((r) -> r["message"], rows) == ["up", "down"]
    assert first(rows)["svc"] == "api"
    assert first(rows)["n"] == 2
    assert first(rows)["extra"] == true
    assert rows[1]["svc"] == "api"
    assert rows[1]["n"] == 1
  end
end

test "with carries fields in-process too: the logger's enabled follows the level"
  l = with({svc: "api"})
  assert l[:enabled](:error) == true
  assert with(nil)[:enabled](level) == true
end

test "a signal is on unless observe sets it to :off"
  assert on?(nil, :logs) == true
  assert on?({}, :logs) == true
  assert on?({logs: :vector}, :logs) == true
  assert on?({logs: :off}, :logs) == false
  assert on?({logs: :off}, :traces) == true
end

test "logs off leaves no endpoint even when one is named"
  assert vector_endpoint({logs: :off, vector_endpoint: "http://v/"}).nil?
  assert vector_endpoint({vector_endpoint: "http://v/"}) == "http://v/"
  assert get(
    exporting({logs: :off, vector_endpoint: "http://v/"}, {}),
    :endpoint
  ).nil?
end

test "an exporting logger POSTs each line to Vector, and with logs off sends nothing"
  captured = fn(observe, body)
    l = http_listen("127.0.0.1:0")
    url = "http://127.0.0.1:#{to_s(http_listener_port(l))}/"
    me = self
    spawn(
      fn()
        body(exporting(assoc(observe, :vector_endpoint, url), {svc: "api"}))
        send(me, :done)
      end
    )
    receive(:_, 2000, :none)
    http_next_request(l, 500)
  end
  req = captured({}, (log) -> log[:error]("down", {n: 1}))
  assert req[:method] == "POST"
  rec = json_read(req[:body])
  assert rec["message"] == "down"
  assert rec["svc"] == "api"
  assert rec["n"] == 1
  assert captured({logs: :off}, (log) -> log[:error]("down", {})).nil?
end

test "a failed export is reported, not raised"
  assert ship("http://127.0.0.1:1/", "{}", 200) == false
end
