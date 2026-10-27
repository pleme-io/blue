@moduledoc """
koutei (工程) — one step of a pipeline, as GitHub Actions runs it.

A pleme-io action keeps its logic in a `run.b`. This bidama is that file's
side of the step: read the inputs the action passed as `INPUT_*` variables,
write outputs and the step summary, raise annotations, and fail the step.
The text each one writes is built by a pure function, so the format is tested
here and the writer is one line.

    input_key("require-symbols") #=> "INPUT_REQUIRE_SYMBOLS"
"""

use("deeta", [:json_at])
use("moji", [:env_key])
use("tesuto", [:raises?])

@doc """
input_key: the environment variable an action passes input `name` in.

    input_key("cache-url") #=> "INPUT_CACHE_URL"
"""
def input_key(name)
  env_key(["input", name])
end

@doc """
present: the text, or nil when it is nil or only whitespace.

    present("  ") #=> nil
"""
def present(text)
  if text.nil? or trim(text) == ""
    nil
  else
    text
  end
end

@doc """
input: input `name`, or nil when the action passed nothing or only whitespace.

    input("koutei-no-such-input") #=> nil
"""
def input(name)
  present(getenv(input_key(name)))
end

@doc """
input_or: input `name`, or `fallback` when it is absent.

    input_or("koutei-no-such-input", "8") #=> "8"
"""
def input_or(name, fallback)
  input(name) or fallback
end

@doc """
truthy?: whether an input's text means yes: true, 1, yes or on.

    truthy?("on") #=> true
"""
def truthy?(text)
  member?(text, ["true", "1", "yes", "on"])
end

@doc """
flag?: whether input `name` is set to a yes word.

    flag?("koutei-no-such-input") #=> false
"""
def flag?(name)
  truthy?(input(name))
end

@doc """
lines_of: the non-blank lines of a text, trimmed; nil reads as no lines.

    lines_of(" a\n\n b ") #=> ["a", "b"]
"""
def lines_of(text)
  if text.nil?
    []
  else
    filter((l) -> l != "", map((l) -> trim(l), split(text, line_break)))
  end
end

@doc """
input_lines: input `name` read as a newline-separated list.

    input_lines("koutei-no-such-input") #=> []
"""
def input_lines(name)
  lines_of(input(name))
end

@doc """
delimiter_for: a heredoc delimiter that does not occur in `value`.

    delimiter_for("x") #=> "KOUTEI_EOF"
"""
def delimiter_for(value)
  widen(value, "KOUTEI_EOF")
end

@doc """
widen: `d`, lengthened with `_` until `value` does not contain it.

    widen("KOUTEI_EOF", "KOUTEI_EOF") #=> "KOUTEI_EOF_"
"""
def widen(value, d)
  if contains?(value, d)
    widen(value, "#{d}_")
  else
    d
  end
end

@doc """
output_record: the GITHUB_OUTPUT record for one output, safe for any text.

    output_record("n", "3") #=> "n<<KOUTEI_EOF\n3\nKOUTEI_EOF\n"
"""
def output_record(key, value)
  text = to_s(value)
  d = delimiter_for(text)
  unlines(["#{key}<<#{d}", text, d])
end

@doc """
append_to: add text to the file the variable `var` names, or print it when the
variable is unset (a local run).

    append_to("KOUTEI_NO_SUCH_FILE_VAR", "") #=> nil
"""
def append_to(var, text)
  path = present(getenv(var))
  if path.nil?
    write_stdout(text)
  else
    append_file(path, text)
  end
  nil
end

@doc """
output: set step output `key` to `value`.

    output_record("ok", true) #=> "ok<<KOUTEI_EOF\ntrue\nKOUTEI_EOF\n"
"""
def output(key, value)
  append_to("GITHUB_OUTPUT", output_record(key, value))
end

@doc """
summary: add markdown to the step summary.

    summary_record("done") #=> "done\n"
"""
def summary(markdown)
  append_to("GITHUB_STEP_SUMMARY", summary_record(markdown))
end

@doc """
summary_record: one summary block, ending in a newline.

    summary_record("a") #=> "a\n"
"""
def summary_record(markdown)
  unlines([markdown])
end

@doc """
mark: the summary symbol for one item: ✅ when it holds, ❌ when it does not.

    mark(false) #=> "❌"
"""
def mark(holds)
  if holds
    "✅"
  else
    "❌"
  end
end

@doc """
escape_data: an annotation message, with %, CR and LF escaped as GitHub reads them.

    escape_data("50%") #=> "50%25"
"""
def escape_data(text)
  replace(
    replace(replace(to_s(text), "%", "%25"), "\r", "%0D"),
    line_break,
    "%0A"
  )
end

@doc """
escape_property: an annotation property value; also escapes : and ,.

    escape_property("a:b,c") #=> "a%3Ab%2Cc"
"""
def escape_property(text)
  replace(replace(escape_data(text), ":", "%3A"), ",", "%2C")
end

@doc """
levels: the annotation levels GitHub shows.

    levels #=> ["error", "warning", "notice"]
"""
def levels()
  ["error", "warning", "notice"]
end

@doc """
annotation: the workflow command for one annotation. `props` is a list of
[name, value] pairs (file, line, col, endLine, endColumn, title); a nil value
is left out. A level GitHub does not show raises :bad_level.

    annotation("notice", "hi", []) #=> "::notice::hi"
"""
def annotation(level, message, props)
  if not member?(level, levels)
    raise(
      :bad_level,
      "#{level} is not an annotation level; the levels are #{join(levels, ", ")}"
    )
  end
  kept = filter((p) -> not nth(1, p).nil?, props)
  shown = map((p) -> "#{nth(0, p)}=#{escape_property(nth(1, p))}", kept)
  if shown == []
    "::#{level}::#{escape_data(message)}"
  else
    "::#{level} #{join(shown, ",")}::#{escape_data(message)}"
  end
end

@doc """
annotate: raise one annotation on the step.

    annotation("warning", "w", [["file", "a.b"]]) #=> "::warning file=a.b::w"
"""
def annotate(level, message, props)
  write_stdout(unlines([annotation(level, message, props)]))
  nil
end

@doc """
fail: raise an error annotation and end the step with status 1.

    annotation("error", "stop", []) #=> "::error::stop"
"""
def fail(message)
  annotate("error", message, [])
  exit_with(1)
end

@doc """
level_of: the annotation level for a blue diagnostic's severity.

    level_of("warning") #=> "warning"
"""
def level_of(severity)
  if severity == "error"
    "error"
  elsif severity == "warning"
    "warning"
  else
    "notice"
  end
end

@doc """
diagnostic?: whether a `blue check --format json` line is a finding (it has a
rule `code`), rather than an override record, which names a tier and is no fault.

    diagnostic?(json_stringify([["kind", "override"], ["name", "first"]])) #=> false
"""
def diagnostic?(json_line)
  not json_at(json_parse(json_line), "code").nil?
end

@doc """
diagnostic_annotation: the annotation for one `blue check --format json` line
(docs/DIAGNOSTICS.md): the rule code titles it, the help line follows the message.

    diagnostic_annotation(json_stringify([["severity", "error"], ["code", "B0001"], ["message", "m"]])) #=> "::error title=B0001::m"
"""
def diagnostic_annotation(json_line)
  d = json_parse(json_line)
  help = json_at(d, "help")
  message = json_at(d, "message")
  text = if help.nil?
    message
  else
    join_lines([message, help])
  end
  annotation(
    level_of(json_at(d, "severity")),
    text,
    [
      ["file", json_at(d, "file")],
      ["line", json_at(d, "line")],
      ["col", json_at(d, "column")],
      ["endLine", json_at(d, "end_line")],
      ["endColumn", json_at(d, "end_column")],
      ["title", json_at(d, "code")]
    ]
  )
end

test "an input name becomes its INPUT_ variable"
  assert input_key("cache-url") == "INPUT_CACHE_URL"
  assert input_key("x") == "INPUT_X"
end

test "absent and blank inputs read as nil, and a fallback fills them"
  assert present(nil).nil?
  assert present(unlines([" "])).nil?
  assert present(" a ") == " a "
  assert input("koutei-no-such-input").nil?
  assert input_or("koutei-no-such-input", "d") == "d"
end

test "only yes words are true"
  assert truthy?("true")
  assert truthy?("1")
  assert not truthy?("false")
  assert not truthy?(nil)
  assert not flag?("koutei-no-such-input")
end

test "a list input keeps its non-blank lines, trimmed"
  assert lines_of(unlines(["a", "", "  b "])) == ["a", "b"]
  assert lines_of(nil) == []
  assert input_lines("koutei-no-such-input") == []
end

test "an output record survives a value that holds the delimiter"
  assert output_record("n", 3) == unlines(["n<<KOUTEI_EOF", "3", "KOUTEI_EOF"])
  tricky = join_lines(["a", "KOUTEI_EOF", "b"])
  assert delimiter_for(tricky) == "KOUTEI_EOF_"
  assert widen("KOUTEI_EOF_ KOUTEI_EOF", "KOUTEI_EOF") == "KOUTEI_EOF__"
  assert output_record("v", tricky) ==
    unlines(["v<<KOUTEI_EOF_", tricky, "KOUTEI_EOF_"])
end

test "with no GITHUB_ files set, writers print and return nil"
  assert append_to("KOUTEI_NO_SUCH_FILE_VAR", "").nil?
  assert summary_record("s") == unlines(["s"])
  assert mark(true) == "✅"
  assert mark(false) == "❌"
end

test "annotation text and properties are escaped as GitHub reads them"
  assert escape_data(join_lines(["a%b", "c\r"])) == "a%25b%0Ac%0D"
  assert escape_property("x:y,z") == "x%3Ay%2Cz"
  assert annotation(
    "error",
    join_lines(["two", "lines"]),
    [["file", "a.b"], ["line", 3], ["col", nil]]
  ) == "::error file=a.b,line=3::two%0Alines"
  assert annotation("notice", "n", []) == "::notice::n"
end

test "a level GitHub does not show is refused"
  assert raises?(:bad_level, () -> annotation("info", "x", []))
end

test "a blue diagnostic becomes an annotation at its span"
  line = "{\"severity\":\"error\",\"code\":\"B0001\",\"message\":\"unbound name `x`\",\"file\":\"a.b\",\"line\":2,\"column\":3,\"end_line\":2,\"end_column\":4,\"help\":\"define it\"}"
  assert diagnostic_annotation(line) ==
    "::error file=a.b,line=2,col=3,endLine=2,endColumn=4,title=B0001::unbound name `x`%0Adefine it"
  assert level_of("warning") == "warning"
  assert level_of("hint") == "notice"
  assert diagnostic?(line)
  assert not diagnostic?("{\"kind\":\"override\",\"name\":\"first\",\"tier\":\"imported\"}")
end
