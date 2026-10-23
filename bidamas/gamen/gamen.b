use("jisho")
use("moji", [:checked])
use("retsu", [:count_where, :first, :is_empty])
use("shinsuu", [:parse_int, :to_hex_width])
use("shisutemu", [:esc_char, :status_of, :stderr_of, :stdout_of])
use("tesuto", [:raises?])

def hex_channels(text)
  digits = moji::strip_prefix(text, "#")
  full = if retsu::size(chars(digits)) == 3
    join(map((c) -> concat(c, c), chars(digits)), "")
  else
    digits
  end
  values = map(
    (i) -> parse_int(join(take(2, drop(i * 2, chars(full))), ""), 16),
    range(0, 3)
  )
  if text == digits or
      retsu::size(chars(full)) != 6 or
      count_where(number?, values) != 3
    raise(:bad_option, "#{text} is not #rgb or #rrggbb")
  end
  {r: nth(0, values), g: nth(1, values), b: nth(2, values)}
end

def rgb(color)
  if string?(color)
    hex_channels(color)
  elsif map?(color) and
      jisho::has?(color, :r) and
      jisho::has?(color, :g) and
      jisho::has?(color, :b)
    parts = map((k) -> get(color, k), [:r, :g, :b])
    if count_where((v) -> number?(v) and v >= 0 and v <= 255, parts) != 3
      raise(:bad_option, "a color record takes r, g and b from 0 to 255")
    end
    {r: get(color, :r), g: get(color, :g), b: get(color, :b)}
  else
    raise(:bad_option, "a color is #rgb, #rrggbb or a record with r, g and b")
  end
end

def hex(color)
  c = rgb(color)
  concat(
    "#",
    to_hex_width(round(get(c, :r)), 2),
    to_hex_width(round(get(c, :g)), 2),
    to_hex_width(round(get(c, :b)), 2)
  )
end

def linear(channel)
  c = channel / 255
  if c <= 0.03928
    c / 12.92
  else
    exp(2.4 * log((c + 0.055) / 1.055))
  end
end

def luminance(color)
  c = rgb(color)
  0.2126 * linear(get(c, :r)) +
    0.7152 * linear(get(c, :g)) +
    0.0722 * linear(get(c, :b))
end

def contrast(a, b)
  la = luminance(a)
  lb = luminance(b)
  (blue::max(la, lb) + 0.05) / (blue::min(la, lb) + 0.05)
end

def modes()
  [:light, :dark]
end

def token_color(name, value, mode)
  picked = if map?(value) and
      jisho::has?(value, :light) and
      jisho::has?(value, :dark)
    get(value, mode)
  else
    value
  end
  hex(picked)
rescue :bad_option as e
  raise(:bad_option, "token #{to_s(name)}: #{e.message}")
end

def theme(tokens, mode)
  if not member?(mode, modes)
    raise(:bad_option, "a theme mode is light or dark, got #{to_s(mode)}")
  end
  {
    mode:,
    tokens: reduce(
      (acc, e) -> assoc(acc, first(e), token_color(first(e), nth(1, e), mode)),
      {},
      map_entries(tokens)
    )
  }
end

def token_for(theme, name)
  found = if theme.nil?
    nil
  else
    get(get(theme, :tokens), name)
  end
  if found.nil?
    raise(:bad_option, "no theme token #{to_s(name)}")
  end
  found
end

def paint(value, theme)
  if string?(value) or map?(value)
    rgb(value)
  else
    rgb(token_for(theme, value))
  end
end

def sequence(prefix, value, theme)
  c = paint(value, theme)
  "#{prefix};2;#{to_s(round(get(c, :r)))};#{to_s(round(get(c, :g)))};#{to_s(round(get(c, :b)))}"
end

def codes(node, theme)
  flags = filter(
    (p) -> get(node, first(p)) == true,
    [[:bold, "1"], [:dim, "2"], [:underline, "4"]]
  )
  colors = filter(
    (x) -> x != nil,
    [
      if get(node, :fg).nil?
        nil
      else
        sequence("38", get(node, :fg), theme)
      end,
      if get(node, :bg).nil?
        nil
      else
        sequence("48", get(node, :bg), theme)
      end
    ]
  )
  append(map((p) -> nth(1, p), flags), colors)
end

def styled(node, ctx)
  if string?(node)
    node
  elsif list?(node)
    join(map((n) -> styled(n, ctx), node), "")
  elsif map?(node) and string?(get(node, :text))
    on = codes(node, get(ctx, :theme))
    if is_empty(on) or not get(ctx, :color)
      get(node, :text)
    else
      "#{esc_char}[#{join(on, ";")}m#{get(node, :text)}#{esc_char}[0m"
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
  sink = get(opts, :sink)
  to = get(opts, :to) or :stdout
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

def show(node, opts)
  checked(opts, [:theme, :color, :sink, :to, :newline])
  write = writer(opts)
  on = get(opts, :color)
  ctx = {
    color: if on.nil?
      color_default
    else
      on
    end,
    theme: get(opts, :theme)
  }
  text = styled(node, ctx)
  if get(opts, :newline) == false
    write(text)
  else
    write("#{text}\n")
  end
  nil
end

def close?(a, b)
  blue::abs(a - b) < 0.001
end

def collect(opts, node)
  seen = [""]
  sink = (t) -> set!(seen, [concat(first(seen), t)])
  show(node, jisho::merge(opts, {sink:}))
  first(seen)
end

test "rgb reads long and short hex, any case, and a record"
  assert rgb("#ff8000") == {r: 255, g: 128, b: 0}
  assert rgb("#FF8000") == {r: 255, g: 128, b: 0}
  assert rgb("#f80") == {r: 255, g: 136, b: 0}
  assert rgb("#000000") == {r: 0, g: 0, b: 0}
  assert rgb({r: 1, g: 2, b: 3}) == {r: 1, g: 2, b: 3}
  assert rgb({r: 1, g: 2, b: 3, a: 0.5}) == {r: 1, g: 2, b: 3}
end

test "rgb refuses what is not a color"
  assert raises?(:bad_option, () -> rgb("ff8000"))
  assert raises?(:bad_option, () -> rgb("#ff80"))
  assert raises?(:bad_option, () -> rgb("#gg0000"))
  assert raises?(:bad_option, () -> rgb(""))
  assert raises?(:bad_option, () -> rgb("#"))
  assert raises?(:bad_option, () -> rgb({r: 1, g: 2}))
  assert raises?(:bad_option, () -> rgb({r: 256, g: 0, b: 0}))
  assert raises?(:bad_option, () -> rgb({r: -1, g: 0, b: 0}))
  assert raises?(:bad_option, () -> rgb({r: "1", g: 0, b: 0}))
  assert raises?(:bad_option, () -> rgb(nil))
  assert raises?(:bad_option, () -> rgb(5))
end

test "hex writes lowercase six digits and rounds a blended channel"
  assert hex("#FF8000") == "#ff8000"
  assert hex("#f80") == "#ff8800"
  assert hex({r: 0, g: 0, b: 0}) == "#000000"
  assert hex({r: 127.5, g: 1, b: 15}) == "#80010f"
end

test "contrast is 21 for black on white, 1 for a color on itself, in either order"
  assert close?(contrast("#000000", "#ffffff"), 21)
  assert close?(contrast("#ffffff", "#000000"), 21)
  assert close?(contrast("#336699", "#336699"), 1)
  assert close?(contrast({r: 0, g: 0, b: 0}, "#fff"), 21)
end

test "contrast matches the WCAG values people quote"
  assert close?(contrast("#777777", "#ffffff"), 4.478)
  assert close?(contrast("#767676", "#ffffff"), 4.542)
  assert close?(contrast("#ff0000", "#ffffff"), 3.998)
  assert contrast("#777777", "#ffffff") < 4.5
  assert contrast("#767676", "#ffffff") >= 4.5
end

test "contrast refuses a value that is not a color"
  assert raises?(:bad_option, () -> contrast("red", "#fff"))
  assert raises?(:bad_option, () -> contrast("#fff", nil))
end

test "theme picks the mode of a light and dark pair and keeps a single color"
  tokens = {
    background: {light: "#eceff4", dark: "#2e3440"},
    text: {light: "#2e3440", dark: "#eceff4"},
    accent: "#88c0d0"
  }
  light = theme(tokens, :light)
  assert get(light, :mode) == :light
  assert get(light, :tokens) ==
    {accent: "#88c0d0", background: "#eceff4", text: "#2e3440"}
  dark = theme(tokens, :dark)
  assert get(get(dark, :tokens), :background) == "#2e3440"
  assert get(get(dark, :tokens), :accent) == "#88c0d0"
end

test "theme normalizes records and short hex to six digit text, and may be empty"
  t = theme({a: "#F80", b: {r: 1, g: 2, b: 3}}, :dark)
  assert get(t, :tokens) == {a: "#ff8800", b: "#010203"}
  assert theme({}, :light) == {mode: :light, tokens: {}}
end

test "theme refuses a mode it does not know and names the token that is no color"
  assert raises?(:bad_option, () -> theme({}, :sepia))
  assert raises?(:bad_option, () -> theme({}, "light"))
  assert raises?(:bad_option, () -> theme({a: "nope"}, :light))
  assert raises?(
    :bad_option,
    () -> theme({a: {light: "#fff", dark: "bad"}}, :dark)
  )
  assert get(theme({a: {light: "#fff", dark: "bad"}}, :light), :tokens) ==
    {a: "#ffffff"}
  message = begin
    theme({link: "nope"}, :light)
  rescue :bad_option as e
    e.message
  end
  assert contains?(message, "token link") == true
end

test "styled leaves plain text and lists of text alone"
  ctx = {color: true, theme: nil}
  assert styled("hi", ctx) == "hi"
  assert styled(["a", "b", "c"], ctx) == "abc"
  assert styled([], ctx) == ""
  assert styled({text: "plain"}, ctx) == "plain"
end

test "styled wraps text in SGR codes: flags first, then foreground and background"
  ctx = {color: true, theme: nil}
  esc = esc_char
  assert styled({text: "x", bold: true}, ctx) == "#{esc}[1mx#{esc}[0m"
  assert styled({text: "x", bold: true, dim: true, underline: true}, ctx) ==
    "#{esc}[1;2;4mx#{esc}[0m"
  assert styled({text: "x", fg: "#ff0000"}, ctx) ==
    "#{esc}[38;2;255;0;0mx#{esc}[0m"
  assert styled(
    {text: "x", fg: "#010203", bg: {r: 4, g: 5, b: 6}, bold: true},
    ctx
  ) == "#{esc}[1;38;2;1;2;3;48;2;4;5;6mx#{esc}[0m"
  assert styled({text: "x", bold: false}, ctx) == "x"
end

test "styled with color off keeps the text and nothing else"
  ctx = {color: false, theme: nil}
  assert styled({text: "x", bold: true, fg: "#ff0000"}, ctx) == "x"
  assert styled(["a", {text: "b", bold: true}], ctx) == "ab"
end

test "styled resolves a theme token and refuses one the theme lacks"
  t = theme({warn: "#ebcb8b"}, :dark)
  ctx = {color: true, theme: t}
  assert styled({text: "w", fg: :warn}, ctx) ==
    "#{esc_char}[38;2;235;203;139mw#{esc_char}[0m"
  assert raises?(:bad_option, () -> styled({text: "w", fg: :error}, ctx))
  assert raises?(
    :bad_option,
    () -> styled({text: "w", fg: :warn}, {color: true, theme: nil})
  )
end

test "styled refuses a node that is neither text, a list nor a record with text"
  ctx = {color: true, theme: nil}
  assert raises?(:bad_option, () -> styled(5, ctx))
  assert raises?(:bad_option, () -> styled({bold: true}, ctx))
  assert raises?(:bad_option, () -> styled(nil, ctx))
  assert raises?(:bad_option, () -> styled({text: 5}, ctx))
  assert raises?(:bad_option, () -> styled({text: "x", fg: "nope"}, ctx))
end

test "show writes the styled text and a newline to the sink, and returns nil"
  assert collect({color: true}, "hello") == "hello\n"
  assert collect({color: true}, {text: "x", bold: true}) ==
    "#{esc_char}[1mx#{esc_char}[0m\n"
  assert collect({color: false}, {text: "x", bold: true}) == "x\n"
  assert show("a", {sink: (_t) -> nil}).nil?
end

test "show without a newline writes the text as it is"
  assert collect({color: false, newline: false}, "ab") == "ab"
  assert collect({color: false, newline: true}, "ab") == "ab\n"
  assert collect({color: false, newline: false}, []) == ""
end

test "show takes its tokens from the theme option"
  t = theme({ok: "#a3be8c"}, :light)
  assert collect({color: true, theme: t}, {text: "ok", fg: :ok}) ==
    "#{esc_char}[38;2;163;190;140mok#{esc_char}[0m\n"
  assert raises?(
    :bad_option,
    () -> collect({color: true}, {text: "ok", fg: :ok})
  )
end

test "show refuses an unknown option and an unknown destination"
  assert raises?(:bad_option, () -> show("a", {sink: (_t) -> nil, style: 1}))
  assert raises?(:bad_option, () -> show("a", {to: :file}))
end

test "show leaves color to NO_COLOR when color is not given"
  expected = if color_default
    "#{esc_char}[1mx#{esc_char}[0m\n"
  else
    "x\n"
  end
  assert collect({}, {text: "x", bold: true}) == expected
end

test "rgb refuses extra and missing hex digits"
  assert raises?(:bad_option, () -> rgb("#ff80000"))
  assert raises?(:bad_option, () -> rgb("#ffff"))
  assert raises?(:bad_option, () -> rgb("#ff"))
  assert raises?(:bad_option, () -> rgb("#ffffffff"))
end

test "a missing theme token is named, with and without a theme at all"
  t = theme({a: "#fff"}, :light)
  e1 = begin
    styled({text: "x", fg: :zzz}, {color: true, theme: t})
  rescue :bad_option as e
    e.message
  end
  e2 = begin
    styled({text: "x", fg: :zzz}, {color: true, theme: nil})
  rescue :bad_option as e
    e.message
  end
  assert contains?(e1, "no theme token zzz") == true
  assert contains?(e2, "no theme token zzz") == true
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
  assert raises?(:bad_option, () -> writer({to: :file}))
  assert raises?(:bad_option, () -> writer({to: "stderr"}))
end

test "show writes stdout by default and stderr on request, each to its own stream"
  if self_exe != nil
    dir = path_join(getenv("TMPDIR", "/tmp"), "gamen-#{to_s(now_ns)}")
    mkdir_p(dir)
    prog = path_join(dir, "probe.b")
    write_file(
      prog,
      "use(\"gamen\")\ngamen::show(\"out\", {color: false})\ngamen::show(\"err\", {to: :stderr, newline: false})\n"
    )
    cap = exec_with_env([], self_exe, "run", "--quiet", prog)
    rm_rf(dir)
    assert status_of(cap) == 0
    assert stdout_of(cap) == "out\n"
    assert stderr_of(cap) == "err"
  end
end
