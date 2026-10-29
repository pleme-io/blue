@moduledoc """
hikisuu (引数) — command-line arguments: one declared spec is parsed into a record, rendered as help, and answered as shell completion.

A spec is a plain record: `name`, `about`, `flags` (key to a default, or to
a record with `default`, `about`, `min`, `kind` and `value`), `positional`
(records with `name`, `about`, `many` and `optional`) and `commands` (names,
or records with their own `about`, `flags` and `positional`). A flag's kind
comes from its default: true or false is a switch, a whole number takes a
number, text takes text. Its name comes from its key: `dry_run` is
`--dry-run`. `parse` returns one record holding every flag, every positional
and the command; every fault in the line is named in one `:usage` error.
`command` is the program's door: help on `-h`, completion on `__complete`,
the usage text and exit 64 on a bad line, and otherwise the record handed
to the program.

    get(parse(["--dry-run"], {name: "x", flags: {dry_run: false}}), :dry_run) #=> true
"""

use("jisho")
use("kyohi", [:exit_status])
use("moji", %i[checked pad_right])

use(
  "retsu",
  %i[find_first first index_of is_empty last remove_at rest size take_while]
)

@doc """
flag_text: the spelling of a flag key on the command line.

    flag_text(:dry_run) #=> "--dry-run"
"""
def flag_text(key)
  "--#{replace(to_s(key), "_", "-")}"
end

@doc """
kind_of: the kind a flag default implies: switch, int or text.

    kind_of(false) #=> :switch
"""
def kind_of(default)
  if boolean?(default)
    :switch
  elsif integer?(default)
    :int
  elsif string?(default)
    :text
  end
end

@doc """
flag_record: a flag entry as one record of key, text, kind, default, about, min and value.

    get(flag_record(:older_than_days, 14), :kind) #=> :int
"""
def flag_record(key, entry)
  e = if map?(entry)
    checked(entry, %i[default about min kind value])
  else
    {default: entry}
  end
  default = e[:default]
  kind = e[:kind] or kind_of(default)
  if not member?(kind, %i[switch int text])
    raise(
      :bad_option,
      "flag #{flag_text(key)} needs a default of true, false, a whole number or text, or kind: :int or :text"
    )
  end
  if kind_of(default) != nil and kind_of(default) != kind
    raise(
      :bad_option,
      "flag #{flag_text(key)} is kind #{to_s(kind)} with a default of another kind"
    )
  end
  {
    key:,
    text: flag_text(key),
    kind:,
    default:,
    about: e[:about] or "",
    min: e[:min],
    value: e[:value] or
      if kind == :int
        "N"
      else
        "TEXT"
      end
  }
end

@doc """
flags_of: the flag records a flags map declares, in key order.

    map((f) -> get(f, :text), flags_of({b: 1, a: false})) #=> ["--a", "--b"]
"""
def flags_of(flags)
  map((e) -> flag_record(first(e), second(e)), map_entries(flags or {}))
end

@doc """
slot_record: a positional entry as one record of name, about, many and optional.

    get(slot_record({name: :roots, many: true}), :optional) #=> true
"""
def slot_record(entry)
  e = checked(entry, %i[name about many optional])
  if not keyword?(e[:name])
    raise(:bad_option, "a positional needs name: as a symbol")
  end
  many = e[:many] == true
  {
    name: e[:name],
    about: e[:about] or "",
    many:,
    optional: many or e[:optional] == true
  }
end

@doc """
command_record: a command entry, a bare name or a record, as one record of name, about, flags and positional.

    get(command_record(:nix), :name) #=> :nix
"""
def command_record(entry)
  e = if keyword?(entry)
    {name: entry}
  else
    checked(entry, %i[name about flags positional])
  end
  if not keyword?(e[:name])
    raise(:bad_option, "a command needs name: as a symbol")
  end
  {
    name: e[:name],
    about: e[:about] or "",
    flags: e[:flags] or {},
    positional: e[:positional]
  }
end

@doc """
commands_of: the command records a spec declares; empty when it has none.

    commands_of({name: "x"}) #=> []
"""
def commands_of(spec)
  map(command_record, spec[:commands] or [])
end

@doc """
shape: the flags and positionals in force for a command of a spec, nil for none, refusing a key declared twice.

    size(get(shape({name: "x", flags: {a: 1}}, nil), :flags)) #=> 1
"""
def shape(spec, command)
  checked(spec, %i[name about flags positional commands])
  c = if command.nil?
    nil
  else
    find_first((r) -> r[:name] == command, commands_of(spec))
  end
  own = if c.nil?
    {}
  else
    c[:flags]
  end
  clash = filter(
    (k) -> member?(k, map(first, map_entries(spec[:flags] or {}))),
    map(first, map_entries(own))
  )
  if not is_empty(clash)
    raise(:bad_option, "flag #{flag_text(first(clash))} is declared twice")
  end
  if member?(:help, map(first, map_entries(spec[:flags] or {}))) or
      member?(:help, map(first, map_entries(own)))
    raise(
      :bad_option,
      "--help is hikisuu's own flag; a spec does not declare it"
    )
  end
  slots = if c != nil and c[:positional] != nil
    c[:positional]
  else
    spec[:positional] or []
  end
  {
    flags: append(flags_of(spec[:flags]), flags_of(own)),
    positional: map(slot_record, slots)
  }
end

@doc """
help_wanted?: whether a line asks for help before any `--`.

    help_wanted?(["rust", "-h"]) #=> true
"""
def help_wanted?(args)
  before = take_while((a) -> a != "--", args)
  member?("-h", before) or member?("--help", before)
end

@doc """
read_value: a flag's text value read as its kind, with the fault named when it does not read.

    read_value({text: "--n", kind: :int, min: 0}, "7") #=> {value: 7}
"""
def read_value(f, raw)
  if f[:kind] == :int
    n = to_int(raw)
    if n.nil? or not integer?(n) or to_s(n) != raw
      {problem: "#{f[:text]} takes a whole number, not #{raw}"}
    elsif f[:min] != nil and n < f[:min]
      {problem: "#{f[:text]} takes #{to_s(f[:min])} or more, not #{raw}"}
    else
      {value: n}
    end
  else
    {value: raw}
  end
end

@doc """
split_flag: a `--name=value` argument as its name and value; value nil without `=`.

    split_flag("--days=3") #=> ["--days", "3"]
"""
def split_flag(arg)
  at = text_index(arg, "=", 0)
  if at < 0
    [arg, nil]
  else
    [join(take(at, chars(arg)), ""), join(drop(at + 1, chars(arg)), "")]
  end
end

@doc """
walk: the flags, positional words and problems a line holds, read left to right.

    get(walk(["--a", "x"], [flag_record(:a, false)], {values: {}, words: [], problems: []}), :words) #=> ["x"]
"""
def walk(args, flags, acc)
  if is_empty(args)
    acc
  else
    arg = first(args)
    if arg == "--"
      assoc(acc, :words, append(acc[:words], rest(args)))
    elsif arg == "-h" or arg == "--help"
      walk(rest(args), flags, acc)
    elsif starts_with?(arg, "--")
      parts = split_flag(arg)
      f = find_first((r) -> r[:text] == first(parts), flags)
      if f.nil?
        walk(rest(args), flags, problem(acc, "unknown flag #{first(parts)}"))
      elsif f[:kind] == :switch
        if second(parts) != nil
          walk(
            rest(args),
            flags,
            problem(acc, "#{first(parts)} is a switch and takes no value")
          )
        else
          walk(rest(args), flags, value(acc, f[:key], true))
        end
      else
        inline = second(parts)
        raw = if inline != nil
          inline
        elsif size(args) > 1
          second(args)
        end
        left = if inline != nil
          rest(args)
        else
          drop(2, args)
        end
        if raw.nil?
          walk(
            left,
            flags,
            problem(acc, "#{first(parts)} needs a #{f[:value]}")
          )
        else
          read = read_value(f, raw)
          if read[:problem] != nil
            walk(left, flags, problem(acc, read[:problem]))
          else
            walk(left, flags, value(acc, f[:key], read[:value]))
          end
        end
      end
    elsif starts_with?(arg, "-") and arg != "-"
      walk(rest(args), flags, problem(acc, "unknown flag #{arg}"))
    else
      walk(rest(args), flags, assoc(acc, :words, append(acc[:words], [arg])))
    end
  end
end

@doc """
problem: an accumulator with one more problem.

    get(problem({problems: []}, "x"), :problems) #=> ["x"]
"""
def problem(acc, text)
  jisho::update(acc, :problems, (ps) -> append(ps, [text]))
end

@doc """
value: an accumulator with one flag's value set.

    get(get(value({values: {}}, :a, 1), :values), :a) #=> 1
"""
def value(acc, key, v)
  assoc(acc, :values, assoc(acc[:values], key, v))
end

@doc """
place: positional words bound to their slots, with a problem for each missing or extra word.

    get(get(place(["a"], [slot_record({name: :x})], {}, []), :values), :x) #=> "a"
"""
def place(words, slots, values, problems)
  if is_empty(slots)
    {
      values:,
      problems: if is_empty(words)
        problems
      else
        append(problems, ["unexpected #{join(words, " ")}"])
      end
    }
  else
    s = first(slots)
    if s[:many]
      place([], rest(slots), assoc(values, s[:name], words), problems)
    elsif is_empty(words)
      if s[:optional]
        place([], rest(slots), assoc(values, s[:name], nil), problems)
      else
        place(
          [],
          rest(slots),
          values,
          append(problems, ["missing #{slot_label(s)}"])
        )
      end
    else
      place(
        rest(words),
        rest(slots),
        assoc(values, s[:name], first(words)),
        problems
      )
    end
  end
end

@doc """
slot_label: how help and errors name a positional: upper case, with dots when it takes many.

    slot_label(slot_record({name: :root, many: true})) #=> "ROOT..."
"""
def slot_label(s)
  base = upcase(to_s(s[:name]))
  if s[:many]
    "#{base}..."
  else
    base
  end
end

@doc """
command_names: the names of a spec's commands joined for a sentence.

    command_names({commands: [:rust, :nix]}) #=> "rust, nix"
"""
def command_names(spec)
  join(map((c) -> to_s(c[:name]), commands_of(spec)), ", ")
end

@doc """
pick_command: the command a line names and the arguments after it, or a problem.

    get(pick_command(["nix", "-x"], {commands: [:nix]}), :command) #=> :nix
"""
def pick_command(args, spec)
  cs = commands_of(spec)
  if is_empty(cs)
    {command: nil, args:}
  else
    head = find_first((a) -> not starts_with?(a, "-"), args)
    c = find_first((r) -> to_s(r[:name]) == head, cs)
    if head.nil?
      {problem: "a command: #{command_names(spec)}", args:}
    elsif c.nil?
      {problem: "unknown command #{head}: #{command_names(spec)}", args:}
    else
      {command: c[:name], args: remove_at(args, index_of(args, head))}
    end
  end
end

@doc """
sound: a spec checked whole, its own flags and every command's, before any line is read; returns the spec.

    sound({name: "x"}) #=> {name: "x"}
"""
def sound(spec)
  shape(spec, nil)
  map((c) -> shape(spec, c[:name]), commands_of(spec))
  spec
end

@doc """
parse: a command line read by a spec into one record of every flag, positional and the command; every fault raised together as `:usage`.

    get(parse(["--days", "3"], {name: "x", flags: {days: 14}}), :days) #=> 3
"""
def parse(args, spec)
  sound(spec)
  picked = pick_command(args, spec)
  if help_wanted?(args)
    {help: true, command: picked[:command]}
  elsif picked[:problem] != nil
    raise(:usage, picked[:problem], {data: {problems: [picked[:problem]]}})
  else
    s = shape(spec, picked[:command])
    defaults = reduce((m, f) -> assoc(m, f[:key], f[:default]), {}, s[:flags])
    read = walk(
      picked[:args],
      s[:flags],
      {values: defaults, words: [], problems: []}
    )
    placed = place(read[:words], s[:positional], read[:values], read[:problems])
    problems = placed[:problems]
    if not is_empty(problems)
      raise(:usage, join(problems, "; "), {data: {problems:}})
    end
    assoc(assoc(placed[:values], :command, picked[:command]), :help, false)
  end
end

@doc """
usage_line: the one-line synopsis of a spec, or of one of its commands.

    usage_line({name: "x", flags: {a: false}}, nil) #=> "usage: x [flags]"
"""
def usage_line(spec, command)
  s = shape(spec, command)
  head = if command != nil
    "#{spec[:name]} #{to_s(command)}"
  elsif not is_empty(commands_of(spec))
    "#{spec[:name]} <command>"
  else
    spec[:name]
  end
  flags = if is_empty(s[:flags])
    []
  else
    ["[flags]"]
  end
  slots = map(
    fn(p)
      if p[:optional]
        "[#{slot_label(p)}]"
      else
        slot_label(p)
      end
    end,
    s[:positional]
  )
  "usage: #{join(append([head], flags, slots), " ")}"
end

@doc """
flag_left: a flag's left column in help: its text, and its value word when it takes one.

    flag_left(flag_record(:days, 14)) #=> "--days N"
"""
def flag_left(f)
  if f[:kind] == :switch
    f[:text]
  else
    "#{f[:text]} #{f[:value]}"
  end
end

@doc """
flag_right: a flag's right column in help: its about text and a default worth showing.

    flag_right(flag_record(:days, {default: 14, about: "age"})) #=> "age (default 14)"
"""
def flag_right(f)
  d = f[:default]
  shown = if d.nil? or d == false or d == ""
    ""
  else
    " (default #{to_s(d)})"
  end
  trim("#{f[:about]}#{shown}", {side: :start})
end

@doc """
columns: rows of a left and right text laid out as two aligned columns under a heading.

    columns("flags:", [["-a", "x"]]) #=> ["flags:", "  -a  x"]
"""
def columns(heading, rows)
  w = reduce((m, r) -> blue::max(m, size(chars(first(r)))), 0, rows)
  append(
    [heading],
    map(
      fn(r)
        trim("  #{pad_right(first(r), w, " ")}  #{second(r)}", {side: :end})
      end,
      rows
    )
  )
end

@doc """
render: the help text of a spec, or of one of its commands.

    first(split(render({name: "x", about: "does x"}, nil), line_break)) #=> "x — does x"
"""
def render(spec, command)
  s = shape(spec, command)
  c = if command.nil?
    nil
  else
    find_first((r) -> r[:name] == command, commands_of(spec))
  end
  about = if c != nil and c[:about] != ""
    c[:about]
  else
    spec[:about]
  end
  title = if about.nil? or about == ""
    spec[:name]
  else
    "#{spec[:name]} — #{about}"
  end
  cmds = if command.nil? and not is_empty(commands_of(spec))
    append(
      [""],
      columns(
        "commands:",
        map((r) -> [to_s(r[:name]), r[:about]], commands_of(spec))
      )
    )
  else
    []
  end
  slots = if is_empty(s[:positional])
    []
  else
    append(
      [""],
      columns(
        "arguments:",
        map((p) -> [slot_label(p), p[:about]], s[:positional])
      )
    )
  end
  flags = append(
    [""],
    columns(
      "flags:",
      append(
        map((f) -> [flag_left(f), flag_right(f)], s[:flags]),
        [["-h, --help", "show this help"]]
      )
    )
  )
  unlines(append([title, "", usage_line(spec, command)], cmds, slots, flags))
end

@doc """
complete: the words that may follow a partial command line, for the last word as typed so far.

    complete(["--d"], {name: "x", flags: {days: 1, dry_run: false}}) #=> ["--days", "--dry-run"]
"""
def complete(args, spec)
  typed = if is_empty(args)
    ""
  else
    last(args)
  end
  before = if is_empty(args)
    []
  else
    take(size(args) - 1, args)
  end
  picked = pick_command(before, spec)
  if picked[:problem] != nil
    if starts_with?(typed, "-")
      matching(typed, ["--help"])
    else
      matching(typed, map((c) -> to_s(c[:name]), commands_of(spec)))
    end
  else
    s = shape(spec, picked[:command])
    prev = if is_empty(before)
      nil
    else
      last(before)
    end
    valued = find_first(
      (f) -> f[:text] == prev and f[:kind] != :switch,
      s[:flags]
    )
    if valued != nil
      []
    elsif starts_with?(typed, "-")
      matching(typed, append(map((f) -> f[:text], s[:flags]), ["--help"]))
    else
      []
    end
  end
end

@doc """
matching: the candidates that start with what was typed, sorted.

    matching("n", ["rust", "nix"]) #=> ["nix"]
"""
def matching(typed, candidates)
  sort_keyed((w) -> w, filter((w) -> starts_with?(w, typed), candidates))
end

@doc """
script: the completion script a shell sources for a program, asking the program itself through `__complete`.

    contains?(script({name: "souji"}, :fish), "souji __complete") #=> true
"""
def script(spec, shell)
  n = spec[:name]
  f = "_#{replace(n, "-", "_")}_complete"
  if shell == :bash
    unlines(
      [
        "#{f}() {",
        "  COMPREPLY=($(#{n} __complete \"${COMP_WORDS[@]:1:COMP_CWORD}\"))",
        "}",
        "complete -F #{f} #{n}"
      ]
    )
  elsif shell == :zsh
    unlines(
      [
        "#compdef #{n}",
        "#{f}() {",
        "  compadd -- ${(f)\"$(#{n} __complete \"${(@)words[2,CURRENT]}\")\"}",
        "}",
        "compdef #{f} #{n}"
      ]
    )
  elsif shell == :fish
    unlines(
      [
        "complete -c #{n} -f -a '(#{n} __complete (commandline -opc)[2..-1] (commandline -ct))'"
      ]
    )
  else
    raise(
      :bad_option,
      "a completion script is for bash, zsh or fish, got #{to_s(shell)}"
    )
  end
end

@doc """
outcome: what a command line asks of a program: help text, completion words, a usage refusal with its exit status, or the record to run with.

    get(outcome(["-h"], {name: "x"}), :kind) #=> :help
"""
def outcome(args, spec)
  if not is_empty(args) and first(args) == "__complete"
    {kind: :complete, text: unlines(complete(rest(args), spec))}
  else
    begin
      opts = parse(args, spec)
      if opts[:help]
        {kind: :help, text: render(spec, opts[:command])}
      else
        {kind: :run, opts:}
      end
    rescue :usage as e
      {
        kind: :usage,
        status: exit_status(:usage),
        text: unlines(
          [
            "#{spec[:name]}: #{e.message}",
            usage_line(spec, nil),
            "try #{spec[:name]} --help"
          ]
        )
      }
    end
  end
end

@doc """
run_with: one program run through its spec against given sinks for stdout, stderr and exit; returns what the program returned, or nil.

    run_with(["-h"], {name: "x"}, (_o) -> 1, {out: (_t) -> nil, err: (_t) -> nil, exit: (_n) -> nil}) #=> nil
"""
def run_with(args, spec, f, io)
  checked(io, %i[out err exit])
  o = outcome(args, spec)
  k = o[:kind]
  if k == :run
    f(o[:opts])
  elsif k == :usage
    io[:err](o[:text])
    io[:exit](o[:status])
    nil
  else
    if o[:text] != ""
      io[:out](o[:text])
    end
    nil
  end
end

@doc """
command: the program's door: argv read by the spec; help and completion printed, a bad line refused on stderr with exit 64, otherwise f called with the record.

    procedure?(command) #=> true
"""
def command(spec, f)
  run_with(
    argv,
    spec,
    f,
    {
      out: (t) -> write_stdout(t),
      err: (t) -> write_stderr(t),
      exit: (n) -> exit_with(n)
    }
  )
end

@doc """
souji_like: a spec shaped like souji's, the fixture the tests read.

    get(souji_like, :name) #=> "souji"
"""
def souji_like()
  {
    name: "souji",
    about: "clean a node's build caches",
    flags: {
      dry_run: {default: false, about: "delete nothing; say what would go"}
    },
    commands: [
      {
        name: :rust,
        about: "idle target/ directories",
        flags: {
          min_age_hours: {default: 6, min: 0, about: "idle at least this long"}
        },
        positional: [{name: :roots, many: true, about: "where to look"}]
      },
      {
        name: :nix,
        about: "unreferenced store paths",
        flags: {older_than_days: {default: 14, min: 0}}
      }
    ]
  }
end

test "a switch, a number and positionals read into one record with defaults"
  o = parse(%w[rust --dry-run --min-age-hours 12 /a /b], souji_like)
  assert o ==
    {
      command: :rust,
      dry_run: true,
      min_age_hours: 12,
      roots: %w[/a /b],
      help: false
    }
  d = parse(["nix"], souji_like)
  assert d[:older_than_days] == 14
  assert d[:dry_run] == false
  assert jisho::has?(d, :min_age_hours) == false
end

test "a value reads after = or as the next word, and flags may come before the command"
  assert get(
    parse(%w[--dry-run nix --older-than-days=3], souji_like),
    :older_than_days
  ) == 3
  assert parse(%w[nix --older-than-days 0], souji_like)[:older_than_days] == 0
end

test "-- ends the flags: what follows is positional"
  assert parse(%w[rust -- --dry-run], souji_like)[:roots] == ["--dry-run"]
  assert parse(%w[rust -- --dry-run], souji_like)[:dry_run] == false
end

test "every fault in a line is named in one usage error"
  e = begin
    parse(%w[rust --min-age-hours x --nope --dry-run=yes], souji_like)
  rescue err
    err
  end
  assert e.kind == :usage
  assert e.message ==
    "--min-age-hours takes a whole number, not x; unknown flag --nope; --dry-run is a switch and takes no value"
  assert size(e.data[:problems]) == 3
end

test "a missing or unknown command, a value below its floor and a missing value are refused"
  refused = fn(args)
    begin
      parse(args, souji_like)
      nil
    rescue err
      err.message
    end
  end
  assert refused([]) == "a command: rust, nix"
  assert refused(["sweep"]) == "unknown command sweep: rust, nix"
  assert refused(%w[nix --older-than-days -1]) ==
    "--older-than-days takes 0 or more, not -1"
  assert refused(%w[nix --older-than-days]) == "--older-than-days needs a N"
  assert refused(%w[nix -x]) == "unknown flag -x"
  assert refused(%w[nix extra]) == "unexpected extra"
  assert refused(%w[rust --older-than-days 1]) ==
    "unknown flag --older-than-days"
end

test "a required positional is missing, an optional one is nil"
  spec = {
    name: "heni",
    flags: {blue: {kind: :text, default: nil}},
    positional: [
      {name: :package},
      {name: :mutations},
      {name: :extra, optional: true}
    ]
  }
  assert parse(%w[p m], spec) ==
    {
      blue: nil,
      package: "p",
      mutations: "m",
      extra: nil,
      command: nil,
      help: false
    }
  e = begin
    parse(["p"], spec)
  rescue err
    err
  end
  assert e.message == "missing MUTATIONS"
end

test "help is asked by -h or --help anywhere before --, with the command it names"
  assert parse(["-h"], souji_like) == {help: true, command: nil}
  assert parse(%w[nix --help], souji_like) == {help: true, command: :nix}
  assert parse(%w[rust -- -h], souji_like)[:help] == false
end

test "a bad spec is refused as bad_option, naming the flag"
  bad = fn(spec)
    begin
      parse([], spec)
      nil
    rescue err
      [err.kind, err.message]
    end
  end
  assert bad({name: "x", flags: {a: nil}}) ==
    [
      :bad_option,
      "flag --a needs a default of true, false, a whole number or text, or kind: :int or :text"
    ]
  assert bad({name: "x", flags: {a: {default: 1, kind: :text}}}) ==
    [:bad_option, "flag --a is kind text with a default of another kind"]
  assert bad({name: "x", flags: {help: false}}) ==
    [:bad_option, "--help is hikisuu's own flag; a spec does not declare it"]
  assert bad({name: "x", flags: {a: {default: 1, colour: :red}}}) ==
    [
      :bad_option,
      "unknown option colour; this verb takes default, about, min, kind, value"
    ]
  assert bad({name: "x", positional: [{name: "p"}]}) ==
    [:bad_option, "a positional needs name: as a symbol"]
  assert bad(
    {name: "x", flags: {a: 1}, commands: [{name: :c, flags: {a: 2}}]}
  ) == [:bad_option, "flag --a is declared twice"]
  assert bad({name: "x", commands: [{name: "c"}]}) ==
    [:bad_option, "a command needs name: as a symbol"]
  assert bad({name: "x", colour: 1}) ==
    [
      :bad_option,
      "unknown option colour; this verb takes name, about, flags, positional, commands"
    ]
end

test "help renders the title, usage, commands, arguments and aligned flags"
  assert render(souji_like, nil) ==
    unlines(
      [
        "souji — clean a node's build caches",
        "",
        "usage: souji <command> [flags]",
        "",
        "commands:",
        "  rust  idle target/ directories",
        "  nix   unreferenced store paths",
        "",
        "flags:",
        "  --dry-run   delete nothing; say what would go",
        "  -h, --help  show this help"
      ]
    )
  assert render(souji_like, :rust) ==
    unlines(
      [
        "souji — idle target/ directories",
        "",
        "usage: souji rust [flags] [ROOTS...]",
        "",
        "arguments:",
        "  ROOTS...  where to look",
        "",
        "flags:",
        "  --dry-run          delete nothing; say what would go",
        "  --min-age-hours N  idle at least this long (default 6)",
        "  -h, --help         show this help"
      ]
    )
end

test "completion offers commands first, then the flags of the command, and nothing for a value"
  assert complete([""], souji_like) == %w[nix rust]
  assert complete(["r"], souji_like) == ["rust"]
  assert complete(%w[rust --m], souji_like) == ["--min-age-hours"]
  assert complete(%w[rust --], souji_like) ==
    %w[--dry-run --help --min-age-hours]
  assert complete(["nix", "--older-than-days", ""], souji_like) == []
  assert complete(%w[nix --older-than-days -], souji_like) == []
  assert complete(%w[nix x], souji_like) == []
  assert complete(["-"], souji_like) == ["--help"]
  assert complete([], {name: "x", flags: {a: false}}) == []
end

test "a completion script calls the program back for each shell, and refuses another shell"
  assert contains?(
    script({name: "souji"}, :bash),
    "complete -F _souji_complete souji"
  ) == true
  assert contains?(script({name: "souji"}, :zsh), "#compdef souji") == true
  assert contains?(script({name: "my-tool"}, :fish), "complete -c my-tool") ==
    true
  e = begin
    script({name: "x"}, :tcsh)
  rescue err
    err
  end
  assert e.kind == :bad_option
end

test "outcome answers help, completion, a usage refusal with 64, or the record"
  assert outcome(%w[nix -h], souji_like)[:text] == render(souji_like, :nix)
  assert outcome(%w[__complete n], souji_like) ==
    {kind: :complete, text: unlines(["nix"])}
  u = outcome(["sweep"], souji_like)
  assert u[:kind] == :usage
  assert u[:status] == 64
  assert u[:text] ==
    unlines(
      [
        "souji: unknown command sweep: rust, nix",
        "usage: souji <command> [flags]",
        "try souji --help"
      ]
    )
  assert outcome(["nix"], souji_like)[:opts][:command] == :nix
end

test "run_with calls the program only on a good line, and exits 64 on a bad one"
  seen = [[], [], []]
  io = {
    out: fn(t)
      set!(seen, [append(first(seen), [t]), second(seen), third(seen)])
    end,
    err: fn(t)
      set!(seen, [first(seen), append(second(seen), [t]), third(seen)])
    end,
    exit: fn(n)
      set!(seen, [first(seen), second(seen), append(third(seen), [n])])
    end
  }
  assert run_with(["nix"], souji_like, (o) -> o[:older_than_days], io) == 14
  assert run_with(["sweep"], souji_like, (_o) -> 1, io).nil?
  assert run_with(["-h"], souji_like, (_o) -> 1, io).nil?
  assert run_with(%w[__complete zz], souji_like, (_o) -> 1, io).nil?
  assert third(seen) == [64]
  assert size(second(seen)) == 1
  assert first(seen) == [render(souji_like, nil)]
end
