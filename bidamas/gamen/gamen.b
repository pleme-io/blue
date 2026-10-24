use("jisho")
use("kyohi", [:kind, :kinds, :refusal, :why])
use("moji", [:checked, :trim])
use("retsu", [:count_where, :find_first, :first, :flat_map, :is_empty, :size])
use("shinsuu", [:parse_int, :to_hex_width])
use("shisutemu", [:esc_char, :status_of, :stderr_of, :stdout_of])
use("tesuto", [:raises?])

def hex_channels(text)
  digits = moji::strip_prefix(text, "#")
  full = if size(chars(digits)) == 3
    join(map((c) -> concat(c, c), chars(digits)), "")
  else
    digits
  end
  values = map(
    (i) -> parse_int(join(take(2, drop(i * 2, chars(full))), ""), 16),
    range(0, 3)
  )
  if text == digits or
      size(chars(full)) != 6 or
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

@doc """
contrast: WCAG contrast ratio of two colors.
"""
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

@doc """
theme: declare a theme: Nord tokens for light and dark.

    theme({}, :light) #=> {mode: :light, tokens: {}}
"""
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

def codes(node, theme)
  flags = filter(
    (p) -> get(node, first(p)) == true,
    [[:bold, "1"], [:dim, "2"], [:underline, "4"]]
  )
  colors = filter(
    (x) -> x != nil,
    [
      if get(node, :ink).nil?
        nil
      else
        ink_code(get(node, :ink))
      end,
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

@doc """
show: put a node on the terminal as styled output.
"""
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

    styled(step({state: :done, at: 3, of: 11, name: "regen", ms: 87240}), {color: false, theme: nil}) #=> "✅ [3/11] regen (1m 27s)"
"""
def step(s)
  checked(s, [:state, :at, :of, :name, :note, :ms])
  state = get(s, :state)
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
    {text: get(s, :name), bold: true}
  else
    {text: get(s, :name), bold: true, ink: tone}
  end
  note = if get(s, :note).nil?
    []
  else
    [{text: " — ", ink: :bright_black}, get(s, :note)]
  end
  tail = if get(s, :ms) != nil
    [{text: " (#{duration_text(get(s, :ms))})", ink: :bright_black}]
  elsif state == :running
    [{text: " …", ink: :bright_black}]
  else
    []
  end
  append(
    [
      "#{mark} ",
      {text: "[#{to_s(get(s, :at))}/#{to_s(get(s, :of))}]", ink: :bright_black},
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
  to = get(opts, :to) or :stderr
  color = if get(opts, :color).nil?
    color_default and
      terminal?(
        if to == :stdout
          1
        else
          2
        end
      )
  else
    get(opts, :color)
  end
  show(step(s), assoc(assoc(opts, :to, to), :color, color))
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

def tag_row(tag, void, attrs)
  {tag:, void:, attrs:}
end

def tags()
  [
    tag_row(:html, false, []),
    tag_row(:head, false, []),
    tag_row(:body, false, []),
    tag_row(:title, false, []),
    tag_row(:meta, true, [:charset, :name, :content]),
    tag_row(:main, false, []),
    tag_row(:header, false, []),
    tag_row(:footer, false, []),
    tag_row(:nav, false, []),
    tag_row(:section, false, []),
    tag_row(:article, false, []),
    tag_row(:aside, false, []),
    tag_row(:div, false, []),
    tag_row(:span, false, []),
    tag_row(:p, false, []),
    tag_row(:h1, false, []),
    tag_row(:h2, false, []),
    tag_row(:h3, false, []),
    tag_row(:h4, false, []),
    tag_row(:h5, false, []),
    tag_row(:h6, false, []),
    tag_row(:ul, false, []),
    tag_row(:ol, false, [:start]),
    tag_row(:li, false, []),
    tag_row(:a, false, [:href, :rel]),
    tag_row(:img, true, [:src, :alt, :width, :height]),
    tag_row(:figure, false, []),
    tag_row(:figcaption, false, []),
    tag_row(:blockquote, false, [:cite]),
    tag_row(:strong, false, []),
    tag_row(:em, false, []),
    tag_row(:small, false, []),
    tag_row(:code, false, []),
    tag_row(:pre, false, []),
    tag_row(:br, true, []),
    tag_row(:hr, true, []),
    tag_row(:button, false, [:type, :name, :value, :disabled]),
    tag_row(:form, false, [:action, :method]),
    tag_row(:label, false, [:for]),
    tag_row(
      :input,
      true,
      [:type, :name, :value, :placeholder, :required, :disabled, :checked]
    ),
    tag_row(
      :textarea,
      false,
      [:name, :placeholder, :required, :disabled, :rows]
    ),
    tag_row(:select, false, [:name, :required, :disabled]),
    tag_row(:option, false, [:value, :selected, :disabled]),
    tag_row(:table, false, []),
    tag_row(:thead, false, []),
    tag_row(:tbody, false, []),
    tag_row(:tr, false, []),
    tag_row(:th, false, [:scope, :colspan]),
    tag_row(:td, false, [:colspan])
  ]
end

def attr_row(key, name, kind, global)
  {key:, name:, kind:, global:}
end

def attributes()
  [
    attr_row(:id, "id", :text, true),
    attr_row(:class, "class", :text, true),
    attr_row(:title, "title", :text, true),
    attr_row(:lang, "lang", :text, true),
    attr_row(:dir, "dir", :text, true),
    attr_row(:hidden, "hidden", :bool, true),
    attr_row(:tabindex, "tabindex", :int, true),
    attr_row(:role, "role", :text, true),
    attr_row(:aria_label, "aria-label", :text, true),
    attr_row(:aria_labelledby, "aria-labelledby", :text, true),
    attr_row(:aria_describedby, "aria-describedby", :text, true),
    attr_row(:aria_hidden, "aria-hidden", :flag, true),
    attr_row(:aria_expanded, "aria-expanded", :flag, true),
    attr_row(:aria_current, "aria-current", :text, true),
    attr_row(:style, "style", :style, true),
    attr_row(:href, "href", :url, false),
    attr_row(:src, "src", :url, false),
    attr_row(:action, "action", :url, false),
    attr_row(:cite, "cite", :url, false),
    attr_row(:rel, "rel", :text, false),
    attr_row(:alt, "alt", :text, false),
    attr_row(:width, "width", :int, false),
    attr_row(:height, "height", :int, false),
    attr_row(:type, "type", :text, false),
    attr_row(:name, "name", :text, false),
    attr_row(:value, "value", :text, false),
    attr_row(:placeholder, "placeholder", :text, false),
    attr_row(:required, "required", :bool, false),
    attr_row(:disabled, "disabled", :bool, false),
    attr_row(:checked, "checked", :bool, false),
    attr_row(:selected, "selected", :bool, false),
    attr_row(:for, "for", :text, false),
    attr_row(:method, "method", :text, false),
    attr_row(:rows, "rows", :int, false),
    attr_row(:colspan, "colspan", :int, false),
    attr_row(:scope, "scope", :text, false),
    attr_row(:start, "start", :int, false),
    attr_row(:charset, "charset", :text, false),
    attr_row(:content, "content", :text, false)
  ]
end

def color_roles()
  [
    :background,
    :surface,
    :surface_elevated,
    :text,
    :text_muted,
    :text_dim,
    :primary,
    :accent,
    :border,
    :error,
    :warning,
    :success,
    :info,
    :selection,
    :cursor,
    :agent
  ]
end

def space_scale()
  [
    [:none, "0"],
    [:xs, "0.25rem"],
    [:sm, "0.5rem"],
    [:md, "1rem"],
    [:lg, "1.5rem"],
    [:xl, "2rem"]
  ]
end

def size_scale()
  [
    [:sm, "0.875rem"],
    [:md, "1rem"],
    [:lg, "1.25rem"],
    [:xl, "1.5rem"],
    [:xxl, "2rem"]
  ]
end

def layouts()
  [
    [:stack, "display:flex;flex-direction:column"],
    [:row, "display:flex;flex-direction:row;flex-wrap:wrap"],
    [:grid, "display:grid"]
  ]
end

def aligns()
  [:start, :center, :end, :stretch]
end

def style_row(key, name, kind)
  {key:, name:, kind:}
end

def style_props()
  [
    style_row(:layout, nil, :layout),
    style_row(:columns, "grid-template-columns", :columns),
    style_row(:align, "align-items", :align),
    style_row(:gap, "gap", :space),
    style_row(:padding, "padding", :space),
    style_row(:margin, "margin", :space),
    style_row(:color, "color", :color),
    style_row(:background, "background", :color),
    style_row(:border_color, "border-color", :color),
    style_row(:font_size, "font-size", :size)
  ]
end

def roles()
  [
    :alert,
    :article,
    :banner,
    :button,
    :cell,
    :checkbox,
    :columnheader,
    :complementary,
    :contentinfo,
    :dialog,
    :figure,
    :form,
    :group,
    :heading,
    :img,
    :link,
    :list,
    :listitem,
    :main,
    :menu,
    :menuitem,
    :navigation,
    :none,
    :presentation,
    :progressbar,
    :region,
    :row,
    :rowheader,
    :search,
    :separator,
    :status,
    :switch,
    :tab,
    :table,
    :tablist,
    :tabpanel,
    :textbox,
    :tooltip
  ]
end

def tag_of(tag)
  find_first((r) -> get(r, :tag) == tag, tags)
end

def attr_of(key)
  find_first((r) -> get(r, :key) == key, attributes)
end

def style_of(key)
  find_first((r) -> get(r, :key) == key, style_props)
end

def scale_value(scale, key)
  found = find_first((p) -> first(p) == key, scale)
  if found.nil?
    nil
  else
    nth(1, found)
  end
end

def allowed?(tag, key)
  a = attr_of(key)
  t = tag_of(tag)
  a != nil and t != nil and (get(a, :global) or member?(key, get(t, :attrs)))
end

def escape(text)
  s = to_s(text)
  replace(
    replace(
      replace(replace(replace(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"),
      "\"",
      "&quot;"
    ),
    "'",
    "&#39;"
  )
end

def url_chars()
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:/?#[]@!$&'()*+,;=%"
end

def scheme_of(url)
  colon = text_index(url, ":", 0)
  cuts = filter(
    (i) -> i >= 0,
    map((c) -> text_index(url, c, 0), ["/", "?", "#"])
  )
  if colon < 0 or not is_empty(cuts) and apply(blue::min, cuts) < colon
    nil
  else
    downcase(join(take(colon, chars(url)), ""))
  end
end

def url_ok?(url)
  if not string?(url)
    false
  elsif not every?((c) -> contains?(url_chars, c), chars(url))
    false
  elsif starts_with?(url, "//")
    false
  else
    scheme = scheme_of(url)
    scheme.nil? or
      scheme == "https" and starts_with?(downcase(url), "https://") or
      scheme == "mailto"
  end
end

def where(path)
  if is_empty(path)
    "root"
  else
    join(path, ".")
  end
end

def element?(node)
  map?(node) and jisho::has?(node, :tag)
end

def text_node?(node)
  string?(node) or number?(node)
end

def props_of(node)
  p = get(node, :props)
  if map?(p)
    p
  else
    {}
  end
end

def prop(node, key)
  get(props_of(node), key)
end

def kids(node)
  c = get(node, :children)
  if list?(c)
    filter((x) -> x != nil, flatten(c))
  else
    []
  end
end

def style_faults(value)
  if not map?(value)
    [refusal(:not_a_token, "style takes a record of token roles")]
  else
    flat_map(
      map_entries(value),
      fn(e)
        k = first(e)
        v = nth(1, e)
        row = style_of(k)
        kind = if row.nil?
          nil
        else
          get(row, :kind)
        end
        if row.nil?
          [refusal(:unknown_style, "style #{to_s(k)} is not in the table")]
        elsif v.nil?
          []
        elsif kind == :color and not member?(v, color_roles)
          if keyword?(v)
            [refusal(:not_a_token, "#{to_s(v)} is not a color role")]
          else
            [
              refusal(
                :literal_color,
                "style #{to_s(k)} takes a color role, not a literal color"
              )
            ]
          end
        elsif kind == :space and scale_value(space_scale, v).nil?
          [refusal(:not_a_token, "#{to_s(v)} is not a space token")]
        elsif kind == :size and scale_value(size_scale, v).nil?
          [refusal(:not_a_token, "#{to_s(v)} is not a size token")]
        elsif kind == :layout and scale_value(layouts, v).nil?
          [refusal(:not_a_token, "#{to_s(v)} is not a layout")]
        elsif kind == :align and not member?(v, aligns)
          [refusal(:not_a_token, "#{to_s(v)} is not an alignment")]
        elsif kind == :columns and not (integer?(v) and v >= 1 and v <= 12)
          [refusal(:not_a_token, "columns is a whole number from 1 to 12")]
        else
          []
        end
      end
    )
  end
end

def value_faults(row, value)
  kind = get(row, :kind)
  name = get(row, :name)
  if value.nil?
    []
  elsif kind == :text and
      not (string?(value) or number?(value) or keyword?(value))
    [refusal(:bad_value, "#{name} takes text")]
  elsif kind == :bool and not boolean?(value)
    [refusal(:bad_value, "#{name} takes true or false")]
  elsif kind == :flag and not boolean?(value)
    [refusal(:bad_value, "#{name} takes true or false")]
  elsif kind == :int and not integer?(value)
    [refusal(:bad_value, "#{name} takes a whole number")]
  elsif kind == :url and not url_ok?(value)
    [refusal(:bad_url, "#{name} takes https, mailto or a relative url")]
  elsif kind == :style
    style_faults(value)
  else
    []
  end
end

def prop_faults(tag, entry)
  key = first(entry)
  if allowed?(tag, key)
    value_faults(attr_of(key), nth(1, entry))
  else
    [
      refusal(
        :unknown_attribute,
        "attribute #{to_s(key)} is not in the table for #{to_s(tag)}"
      )
    ]
  end
end

def node_faults(node)
  if not element?(node) or not keyword?(get(node, :tag))
    [refusal(:bad_node, "a node is text, a list, or a record with a tag")]
  else
    tag = get(node, :tag)
    row = tag_of(tag)
    extra = filter(
      (e) -> not member?(first(e), [:tag, :props, :children, :events]),
      map_entries(node)
    )
    shape = filter(
      (x) -> x != nil,
      [
        if is_empty(extra)
          nil
        else
          refusal(:bad_node, "a node has only tag, props, children and events")
        end,
        if get(node, :props).nil? or map?(get(node, :props))
          nil
        else
          refusal(:bad_node, "props is a record")
        end,
        if get(node, :children).nil? or list?(get(node, :children))
          nil
        else
          refusal(:bad_node, "children is a list")
        end
      ]
    )
    if row.nil?
      [refusal(:unknown_tag, "tag #{to_s(tag)} is not in the table")]
    elsif not is_empty(shape)
      shape
    elsif get(row, :void) and not is_empty(kids(node))
      [refusal(:bad_node, "#{to_s(tag)} takes no children")]
    else
      flat_map(map_entries(props_of(node)), (e) -> prop_faults(tag, e))
    end
  end
end

def entries(node, path, ancestors)
  if node.nil? or text_node?(node)
    []
  elsif list?(node)
    xs = filter((x) -> x != nil, flatten(node))
    flat_map(
      range(0, size(xs)),
      (i) -> entries(nth(i, xs), append(path, [i]), ancestors)
    )
  elsif element?(node) and is_empty(node_faults(node))
    cs = kids(node)
    append(
      [{path:, node:, ancestors:}],
      flat_map(
        range(0, size(cs)),
        (i) -> entries(nth(i, cs), append(path, [i]), append(ancestors, [node]))
      )
    )
  else
    [{path:, node:, ancestors:}]
  end
end

def elements(tree)
  entries(tree, [], [])
end

def at(entry, r)
  label = if element?(get(entry, :node))
    " <#{to_s(get(get(entry, :node), :tag))}>"
  else
    ""
  end
  refusal(kind(r), "at #{where(get(entry, :path))}#{label}: #{why(r)}")
end

def refusals(tree)
  flat_map(
    elements(tree),
    (e) -> map((r) -> at(e, r), node_faults(get(e, :node)))
  )
end

def declarations(value)
  flat_map(
    style_props,
    fn(row)
      k = get(row, :key)
      v = get(value, k)
      kind = get(row, :kind)
      if v.nil?
        []
      elsif kind == :layout
        [scale_value(layouts, v)]
      elsif kind == :columns
        ["#{get(row, :name)}:repeat(#{to_s(v)},minmax(0,1fr))"]
      elsif kind == :align
        ["#{get(row, :name)}:#{to_s(v)}"]
      else
        prefix = if kind == :color
          "color"
        elsif kind == :space
          "space"
        else
          "size"
        end
        ["#{get(row, :name)}:var(--#{prefix}-#{replace(to_s(v), "_", "-")})"]
      end
    end
  )
end

def attr_text(entry)
  row = attr_of(first(entry))
  v = nth(1, entry)
  name = get(row, :name)
  kind = get(row, :kind)
  if v.nil? or kind == :bool and v == false
    nil
  elsif kind == :bool
    " #{name}"
  elsif kind == :style
    " #{name}=\"#{escape(join(declarations(v), ";"))}\""
  else
    " #{name}=\"#{escape(v)}\""
  end
end

def open_tag(node)
  attrs = filter((x) -> x != nil, map(attr_text, map_entries(props_of(node))))
  "<#{to_s(get(node, :tag))}#{join(attrs, "")}>"
end

def html_of(node, path, ctx)
  if node.nil?
    ""
  elsif text_node?(node)
    escape(node)
  elsif list?(node)
    xs = filter((x) -> x != nil, flatten(node))
    join(
      map(
        (i) -> html_of(nth(i, xs), append(path, [i]), ctx),
        range(0, size(xs))
      ),
      ""
    )
  else
    faults = node_faults(node)
    if not is_empty(faults)
      "<!--gamen:refused #{join(map(to_s, distinct(kinds(faults))), ",")} at #{where(path)}-->"
    else
      tag = get(node, :tag)
      row = tag_of(tag)
      cs = kids(node)
      inner = join(
        map(
          (i) -> html_of(nth(i, cs), append(path, [i]), ctx),
          range(0, size(cs))
        ),
        ""
      )
      head = if tag == :head and get(ctx, :theme) != nil
        "<style>#{css(get(ctx, :theme))}</style>"
      else
        ""
      end
      doctype = if tag == :html
        "<!doctype html>"
      else
        ""
      end
      if get(row, :void)
        "#{doctype}#{open_tag(node)}"
      else
        "#{doctype}#{open_tag(node)}#{inner}#{head}</#{to_s(tag)}>"
      end
    end
  end
end

def css(theme)
  pairs = map_entries(get(theme, :tokens))
  strays = filter((e) -> not member?(first(e), color_roles), pairs)
  if not is_empty(strays)
    raise(
      :bad_option,
      "theme token #{to_s(first(first(strays)))} is not a color role"
    )
  end
  vars = append(
    map(
      (e) -> "--color-#{replace(to_s(first(e)), "_", "-")}:#{hex(nth(1, e))}",
      pairs
    ),
    map((e) -> "--space-#{to_s(first(e))}:#{nth(1, e)}", space_scale),
    map((e) -> "--size-#{to_s(first(e))}:#{nth(1, e)}", size_scale)
  )
  ":root{#{join(vars, ";")}}"
end

@doc """
render: tree to html, ansi, svg or widget spec text.

    render("a & b's", :html) #=> "a &amp; b&#39;s"
"""
def render(tree, target, opts?)
  o = opts or {}
  checked(o, [:theme, :refuse])
  refuse = get(o, :refuse) or :node
  if target != :html
    raise(
      :bad_option,
      "render target #{to_s(target)} is not built; :html is, and show draws the terminal"
    )
  end
  if not member?(refuse, [:node, :page])
    raise(:bad_option, "refuse is :node or :page, got #{to_s(refuse)}")
  end
  found = refusals(tree)
  if refuse == :page and not is_empty(found)
    raise(:render_error, join(map(why, found), "; "), {data: found})
  end
  html_of(tree, [], {theme: get(o, :theme)})
end

def event_key?(key)
  starts_with?(to_s(key), "on")
end

def element(tag, props, children)
  if tag_of(tag).nil?
    raise(:bad_option, "tag #{to_s(tag)} is not in the table")
  end
  events = get(props, :on)
  attrs = dissoc(props, :on)
  map(
    fn(e)
      key = first(e)
      if event_key?(key) and not allowed?(tag, key)
        raise(
          :bad_option,
          "#{to_s(key)} is an event: bind it with on:, never as an attribute"
        )
      elsif not allowed?(tag, key)
        raise(
          :bad_option,
          "attribute #{to_s(key)} is not in the table for #{to_s(tag)}"
        )
      end
      nil
    end,
    map_entries(attrs)
  )
  if events != nil and not map?(events)
    raise(:bad_option, "on: takes a record of event to handler")
  end
  node = {
    tag:,
    props: attrs,
    children: filter((x) -> x != nil, flatten(children))
  }
  if events.nil?
    node
  else
    assoc(node, :events, events)
  end
end

def component?(kind)
  map?(kind) and jisho::has?(kind, :component)
end

@doc """
view: declare one UI node with props and children.

    view(:br) #=> {tag: :br, props: {}, children: []}
"""
def view(kind, props?, children?)
  p = props or {}
  c = if children.nil?
    []
  elsif list?(children) or map?(children)
    children
  else
    [children]
  end
  if not map?(p)
    raise(:bad_option, "props is a record")
  end
  if component?(kind)
    instance(kind, p, c)
  elsif keyword?(kind) and map?(c)
    raise(:bad_option, "named slots are for components")
  elsif keyword?(kind)
    element(kind, p, c)
  else
    raise(:bad_option, "a view is a tag keyword or a component")
  end
end

@doc """
component: declare a reusable view: props, state, events.
"""
def component(name, spec)
  checked(spec, [:props, :slots, :variants, :events, :a11y, :view])
  props = get(spec, :props) or {}
  slots = get(spec, :slots) or [:default]
  variants = get(spec, :variants) or {}
  events = get(spec, :events) or []
  a11y = get(spec, :a11y) or {}
  body = get(spec, :view)
  if not keyword?(name)
    raise(:bad_option, "a component name is a keyword")
  end
  if not procedure?(body)
    raise(
      :bad_option,
      "component #{to_s(name)} needs view: (props, slots) -> tree"
    )
  end
  checked(a11y, [:role, :label])
  if get(a11y, :role) != nil and not member?(get(a11y, :role), roles)
    raise(
      :bad_option,
      "component #{to_s(name)}: role #{to_s(get(a11y, :role))} is not in the role table"
    )
  end
  if get(a11y, :label) != nil and not jisho::has?(props, get(a11y, :label))
    raise(
      :bad_option,
      "component #{to_s(name)}: a11y label names prop #{to_s(get(a11y, :label))}, which it does not declare"
    )
  end
  map(
    fn(e)
      if not list?(nth(1, e)) or is_empty(nth(1, e))
        raise(
          :bad_option,
          "component #{to_s(name)}: variant #{to_s(first(e))} lists its values"
        )
      end
      nil
    end,
    map_entries(variants)
  )
  {component: name, props:, slots:, variants:, events:, a11y:, view: body}
end

def filled(c, given)
  name = to_s(get(c, :component))
  declared = get(c, :props)
  variants = get(c, :variants)
  map(
    fn(e)
      k = first(e)
      if not jisho::has?(declared, k) and not jisho::has?(variants, k)
        raise(:bad_option, "component #{name} has no prop #{to_s(k)}")
      end
      if jisho::has?(variants, k) and not member?(nth(1, e), get(variants, k))
        raise(
          :bad_option,
          "component #{name}: #{to_s(nth(1, e))} is not a #{to_s(k)} variant"
        )
      end
      nil
    end,
    map_entries(given)
  )
  with_props = reduce(
    fn(acc, e)
      k = first(e)
      d = nth(1, e)
      v = get(given, k)
      if v != nil
        assoc(acc, k, v)
      elsif d == :required
        raise(:bad_option, "component #{name} needs prop #{to_s(k)}")
      elsif d.nil?
        acc
      else
        assoc(acc, k, d)
      end
    end,
    {},
    map_entries(declared)
  )
  reduce(
    (acc, e) -> assoc(acc, first(e), get(given, first(e)) or first(nth(1, e))),
    with_props,
    map_entries(variants)
  )
end

def slotted(c, children)
  name = to_s(get(c, :component))
  declared = get(c, :slots)
  given = if map?(children)
    children
  elsif is_empty(children)
    {}
  else
    {default: children}
  end
  map(
    fn(e)
      if not member?(first(e), declared)
        raise(:bad_option, "component #{name} has no slot #{to_s(first(e))}")
      end
      nil
    end,
    map_entries(given)
  )
  given
end

def instance(c, given, children)
  name = to_s(get(c, :component))
  handlers = get(given, :on) or {}
  map(
    fn(e)
      if not member?(first(e), get(c, :events))
        raise(
          :bad_option,
          "component #{name} declares no event #{to_s(first(e))}"
        )
      end
      nil
    end,
    map_entries(handlers)
  )
  props = filled(c, dissoc(given, :on))
  tree = get(c, :view)(props, slotted(c, children))
  if not element?(tree)
    raise(:bad_option, "component #{name} must return one element")
  end
  a11y = get(c, :a11y)
  role = get(a11y, :role)
  label = if get(a11y, :label).nil?
    nil
  else
    get(props, get(a11y, :label))
  end
  extra = filter((e) -> nth(1, e) != nil, [[:role, role], [:aria_label, label]])
  root = assoc(
    tree,
    :props,
    reduce((acc, e) -> assoc(acc, first(e), nth(1, e)), props_of(tree), extra)
  )
  if is_empty(map_entries(handlers))
    root
  else
    assoc(root, :events, jisho::merge(get(root, :events) or {}, handlers))
  end
end

@doc """
labels: display text keyed by each backend enum value.
"""
def labels(set, entries)
  if not keyword?(set)
    raise(:bad_option, "labels: the set is the enum's name, as a keyword")
  elsif not map?(entries) or is_empty(map_entries(entries))
    raise(:bad_option, "labels: entries map each value to its display text")
  end
  map(
    fn(e)
      if not string?(nth(1, e))
        raise(
          :bad_option,
          "labels: the label of #{to_s(first(e))} is display text, a string"
        )
      end
      nil
    end,
    map_entries(entries)
  )
  {
    labels: set,
    entries: reduce(
      (m, e) -> assoc(m, to_s(first(e)), nth(1, e)),
      {},
      map_entries(entries)
    )
  }
end

@doc """
layout: place nodes in a size: stack, flex or grid.

    layout(:row, []) #=> {tag: :div, props: {style: {layout: :row}}, children: []}
"""
def layout(kind, children, opts?)
  o = opts or {}
  checked(o, [:gap, :columns, :align, :tag, :props])
  if scale_value(layouts, kind).nil?
    raise(:bad_option, "a layout is :stack, :row or :grid, got #{to_s(kind)}")
  end
  if get(o, :columns) != nil and kind != :grid
    raise(:bad_option, "columns is for a grid")
  end
  s = reduce(
    fn(acc, k)
      if get(o, k).nil?
        acc
      else
        assoc(acc, k, get(o, k))
      end
    end,
    {layout: kind},
    [:gap, :columns, :align]
  )
  view(get(o, :tag) or :div, assoc(get(o, :props) or {}, :style, s), children)
end

def resolved(theme, row, v)
  kind = get(row, :kind)
  if kind == :color
    token_for(theme, v)
  elsif kind == :space
    scale_value(space_scale, v)
  elsif kind == :size
    scale_value(size_scale, v)
  else
    v
  end
end

@doc """
style: resolve semantic tokens on a node to colors and sizes.
"""
def style(node, theme)
  s = prop(node, :style)
  if s.nil?
    node
  else
    faults = style_faults(s)
    if not is_empty(faults)
      raise(:bad_option, join(map(why, faults), "; "))
    end
    out = reduce(
      fn(acc, e)
        assoc(acc, first(e), resolved(theme, style_of(first(e)), nth(1, e)))
      end,
      {},
      map_entries(s)
    )
    assoc(node, :props, assoc(props_of(node), :style, out))
  end
end

def page(spec)
  checked(spec, [:title, :lang, :body])
  view(
    :html,
    {lang: get(spec, :lang) or "en"},
    [
      view(
        :head,
        {},
        [
          view(:meta, {charset: "utf-8"}),
          view(
            :meta,
            {name: "viewport", content: "width=device-width, initial-scale=1"}
          ),
          view(:title, {}, [get(spec, :title)])
        ]
      ),
      view(:body, {}, get(spec, :body))
    ]
  )
end

def text_content(node)
  if text_node?(node)
    to_s(node)
  elsif list?(node)
    join(map(text_content, node), "")
  elsif element?(node)
    join(map(text_content, kids(node)), "")
  else
    ""
  end
end

def named?(node)
  l = prop(node, :aria_label)
  string?(l) and trim(l) != "" or prop(node, :aria_labelledby) != nil
end

def finding(entry, k, message)
  at(entry, refusal(k, message))
end

def alt_rule(tree)
  flat_map(
    elements(tree),
    fn(e)
      n = get(e, :node)
      if element?(n) and get(n, :tag) == :img and prop(n, :alt).nil?
        [
          finding(
            e,
            :missing_alt,
            "an image needs alt text, empty when it is decoration"
          )
        ]
      else
        []
      end
    end
  )
end

def label_targets(tree)
  filter(
    (x) -> x != nil,
    map(
      (e) -> prop(get(e, :node), :for),
      filter(
        (e) -> element?(get(e, :node)) and get(get(e, :node), :tag) == :label,
        elements(tree)
      )
    )
  )
end

def label_rule(tree)
  targets = label_targets(tree)
  flat_map(
    elements(tree),
    fn(e)
      n = get(e, :node)
      tag = if element?(n)
        get(n, :tag)
      end
      exempt = tag == :input and
        member?(prop(n, :type), ["hidden", "submit", "button", "reset"])
      wrapped = any?((a) -> get(a, :tag) == :label, get(e, :ancestors))
      by_for = prop(n, :id) != nil and member?(prop(n, :id), targets)
      if member?(tag, [:input, :textarea, :select]) and
          not exempt and
          not named?(n) and
          not wrapped and
          not by_for
        [finding(e, :missing_label, "a form control needs a label")]
      elsif member?(tag, [:button, :a]) and
          not named?(n) and
          trim(text_content(n)) == "" and
          not any?(
            fn(x)
              element?(get(x, :node)) and
                get(get(x, :node), :tag) == :img and
                string?(prop(get(x, :node), :alt)) and
                trim(prop(get(x, :node), :alt)) != ""
            end,
            elements(kids(n))
          )
        [
          finding(
            e,
            :missing_label,
            "a #{to_s(tag)} needs text or an aria label"
          )
        ]
      else
        []
      end
    end
  )
end

def interactive()
  [:a, :button, :input, :select, :textarea, :option, :label]
end

def role_rule(tree)
  flat_map(
    elements(tree),
    fn(e)
      n = get(e, :node)
      role = if element?(n)
        prop(n, :role)
      end
      events = if element?(n)
        get(n, :events)
      end
      if role != nil and
          not member?(role, roles) and
          not member?(role, map(to_s, roles))
        [finding(e, :bad_role, "role #{to_s(role)} is not in the role table")]
      elsif map?(events) and
          not is_empty(map_entries(events)) and
          not member?(get(n, :tag), interactive) and
          role.nil?
        [
          finding(
            e,
            :missing_role,
            "a node with events needs an interactive role"
          )
        ]
      else
        []
      end
    end
  )
end

def focusable?(n)
  tag = get(n, :tag)
  t = prop(n, :tabindex)
  member?(tag, [:button, :input, :select, :textarea]) or
    tag == :a and prop(n, :href) != nil or
    integer?(t) and t >= 0
end

def focus_rule(tree)
  flat_map(
    elements(tree),
    fn(e)
      n = get(e, :node)
      t = if element?(n)
        prop(n, :tabindex)
      end
      if integer?(t) and t > 0
        [
          finding(
            e,
            :focus_order,
            "a positive tabindex breaks the reading order; use 0"
          )
        ]
      elsif element?(n) and prop(n, :aria_hidden) == true and focusable?(n)
        [
          finding(
            e,
            :focus_order,
            "a focusable node is hidden from assistive tech"
          )
        ]
      else
        []
      end
    end
  )
end

def a11y_rules()
  [alt_rule, label_rule, role_rule, focus_rule]
end

@doc """
check: find accessibility and layout faults in a tree.

    check(view(:img, {src: "/a"}), [focus_rule]) #=> []
"""
def check(tree, rules?)
  kyohi::check(tree, rules or append([refusals], a11y_rules))
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
    write_program(
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

test "view builds a plain record of tag, props and children"
  assert view(:p, {class: "x"}, ["hi"]) ==
    {tag: :p, props: {class: "x"}, children: ["hi"]}
  assert view(:br) == {tag: :br, props: {}, children: []}
  assert view(:p, {}, "one") == {tag: :p, props: {}, children: ["one"]}
  assert view(:ul, {}, [[view(:li, {}, ["a"])], nil]) ==
    {tag: :ul, props: {}, children: [{tag: :li, props: {}, children: ["a"]}]}
  b = view(:button, {on: {press: (_e) -> nil}, type: "button"}, ["Go"])
  assert get(b, :props) == {type: "button"}
  assert map(first, map_entries(get(b, :events))) == [:press]
  assert render(b, :html) == "<button type=\"button\">Go</button>"
end

test "view refuses a tag or attribute outside the table and every on attribute"
  assert raises?(:bad_option, () -> view(:script, {}, ["alert(1)"]))
  assert raises?(:bad_option, () -> view(:iframe, {}, []))
  assert raises?(:bad_option, () -> view(:style, {}, []))
  assert raises?(:bad_option, () -> view(:div, {onclick: "steal()"}, []))
  assert raises?(:bad_option, () -> view(:a, {onmouseover: "x"}, []))
  assert raises?(:bad_option, () -> view(:a, {src: "/x"}, []))
  assert raises?(:bad_option, () -> view(:div, {data_x: 1}, []))
  assert raises?(:bad_option, () -> view(:div, {}, {default: []}))
  assert raises?(:bad_option, () -> view("div", {}, []))
  assert raises?(:bad_option, () -> view(:div, [], []))
  message = begin
    view(:div, {onclick: "x"}, [])
  rescue :bad_option as e
    e.message
  end
  assert contains?(message, "bind it with on:") == true
end

test "the table is closed: no script, style or frame tag and no on attribute"
  banned = [:script, :style, :iframe, :object, :embed, :link, :base, :frame]
  assert every?((r) -> not member?(get(r, :tag), banned), tags)
  assert every?((r) -> not starts_with?(get(r, :name), "on"), attributes)
  assert size(distinct(map((r) -> get(r, :tag), tags))) == size(tags)
  assert size(distinct(map((r) -> get(r, :key), attributes))) ==
    size(attributes)
  assert every?((r) -> every?((k) -> attr_of(k) != nil, get(r, :attrs)), tags)
end

test "every tag row renders as its own element"
  shown = map((r) -> render(view(get(r, :tag)), :html), tags)
  want = map(
    fn(r)
      t = to_s(get(r, :tag))
      lead = if get(r, :tag) == :html
        "<!doctype html>"
      else
        ""
      end
      if get(r, :void)
        "#{lead}<#{t}>"
      else
        "#{lead}<#{t}></#{t}>"
      end
    end,
    tags
  )
  assert shown == want
  assert size(shown) == 49
  assert render(view(:img, {src: "/a.png", alt: ""}), :html) ==
    "<img alt=\"\" src=\"/a.png\">"
end

test "every attribute row renders on a tag that takes it"
  sample = {
    text: "v",
    bool: true,
    flag: true,
    int: 3,
    url: "/u",
    style: {gap: :sm}
  }
  home = fn(row)
    if get(row, :global)
      :div
    else
      get(
        find_first((t) -> member?(get(row, :key), get(t, :attrs)), tags),
        :tag
      )
    end
  end
  shown = map(
    fn(row)
      render(
        view(home(row), {get(row, :key) => get(sample, get(row, :kind))}),
        :html
      )
    end,
    attributes
  )
  assert every?((s) -> not contains?(s, "refused"), shown)
  assert size(shown) == size(attributes)
  assert render(
    view(:a, {href: "https://x.org/?a=1&b=2", rel: "next"}, ["go"]),
    :html
  ) == "<a href=\"https://x.org/?a=1&amp;b=2\" rel=\"next\">go</a>"
  assert render(
    view(
      :input,
      {
        type: "checkbox",
        checked: true,
        disabled: false,
        name: "n",
        aria_label: "Pick"
      }
    ),
    :html
  ) == "<input aria-label=\"Pick\" checked name=\"n\" type=\"checkbox\">"
  assert render(view(:div, {aria_hidden: false, tabindex: 0}), :html) ==
    "<div aria-hidden=\"false\" tabindex=\"0\"></div>"
end

test "text and attribute values are always escaped"
  assert render(view(:p, {}, ["<script>alert(1)</script>"]), :html) ==
    "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>"
  assert render(view(:p, {title: "\" onmouseover=\"x"}, []), :html) ==
    "<p title=\"&quot; onmouseover=&quot;x\"></p>"
  assert render("a & b's", :html) == "a &amp; b&#39;s"
  assert render([1, " < ", 2.5], :html) == "1 &lt; 2.5"
  assert render(view(:p, {class: "<b>"}, []), :html) ==
    "<p class=\"&lt;b&gt;\"></p>"
end

test "render keeps the text: unescaping the output gives the input back"
  unescape = fn(s)
    replace(
      replace(
        replace(replace(replace(s, "&#39;", "'"), "&quot;", "\""), "&gt;", ">"),
        "&lt;",
        "<"
      ),
      "&amp;",
      "&"
    )
  end
  inputs = [
    "",
    "plain",
    "<script>alert('x')</script>",
    "&amp; is already escaped",
    "\"quoted\" & 'single'",
    "a<b>c&d\"e'f",
    "&lt;&gt;"
  ]
  assert map((s) -> unescape(render(s, :html)), inputs) == inputs
  assert every?((s) -> not contains?(render(s, :html), "<"), inputs)
  page = view(:div, {}, [view(:p, {}, ["a<"]), "&b", view(:em, {}, ["'c"])])
  assert unescape(
    replace(
      replace(
        replace(replace(render(page, :html), "<div>", ""), "</div>", ""),
        "<p>",
        ""
      ),
      "</p>",
      ""
    )
  ) == "a<&b<em>'c</em>"
  assert text_content(page) == "a<&b'c"
end

test "a url attribute takes https, mailto and relative, nothing else"
  good = [
    "https://a.example/c?d=1#e",
    "HTTPS://A.EXAMPLE",
    "mailto:a@b.example",
    "/x",
    "./x",
    "../x",
    "x/y",
    "?q=1",
    "#top",
    "",
    "a/b:c"
  ]
  bad = [
    "javascript:alert(1)",
    "JaVaScRiPt:alert(1)",
    "java\tscript:alert(1)",
    " javascript:alert(1)",
    "data:text/html,x",
    "http://a.example",
    "//evil.example",
    "vbscript:x",
    "https:evil",
    "\\\\evil",
    "/a b",
    5,
    :x
  ]
  assert map(url_ok?, good) == map((_u) -> true, good)
  assert map(url_ok?, bad) == map((_u) -> false, bad)
  assert render(view(:a, {href: "javascript:alert(1)"}, ["x"]), :html) ==
    "<!--gamen:refused bad_url at root-->"
  assert render(view(:img, {src: "data:image/png,x", alt: ""}), :html) ==
    "<!--gamen:refused bad_url at root-->"
end

test "a refused node becomes a marker and its siblings still render"
  tree = {
    tag: :ul,
    props: {},
    children: [
      view(:li, {}, ["one"]),
      {tag: :li, props: {onclick: "steal()"}, children: ["two"]},
      {tag: :script, props: {}, children: ["alert(1)"]},
      view(:li, {}, ["three"])
    ]
  }
  assert render(tree, :html) ==
    "<ul><li>one</li><!--gamen:refused unknown_attribute at 1--><!--gamen:refused unknown_tag at 2--><li>three</li></ul>"
  assert kinds(refusals(tree)) == [:unknown_attribute, :unknown_tag]
  assert contains?(why(first(refusals(tree))), "at 1 <li>") == true
  assert refusals(view(:p, {}, ["fine"])) == []
end

test "refuse page raises one render_error that carries every refusal"
  tree = view(
    :div,
    {},
    [
      view(:a, {href: "javascript:x"}, ["a"]),
      view(:p, {style: {color: "#ff0000"}}, ["b"])
    ]
  )
  caught = begin
    render(tree, :html, {refuse: :page})
  rescue :render_error as e
    e
  end
  assert caught.kind == :render_error
  assert kinds(caught.data) == [:bad_url, :literal_color]
  assert render(view(:p, {}, ["ok"]), :html, {refuse: :page}) == "<p>ok</p>"
  assert raises?(:bad_option, () -> render(tree, :html, {refuse: :all}))
  assert raises?(:bad_option, () -> render(tree, :ansi))
  assert raises?(:bad_option, () -> render(tree, :html, {color: true}))
end

test "each render rule refuses its own fault"
  k = (props) -> kinds(refusals({tag: :p, props:, children: []}))
  assert k({style: {color: "#ff0000"}}) == [:literal_color]
  assert k({style: {background: {r: 1, g: 2, b: 3}}}) == [:literal_color]
  assert k({style: {color: :pink}}) == [:not_a_token]
  assert k({style: {padding: "4px"}}) == [:not_a_token]
  assert k({style: {font_size: :huge}}) == [:not_a_token]
  assert k({style: {font: :md}}) == [:unknown_style]
  assert k({style: {columns: 13}}) == [:not_a_token]
  assert k({style: {layout: :float}}) == [:not_a_token]
  assert k({style: {align: :left}}) == [:not_a_token]
  assert k({style: "color:red"}) == [:not_a_token]
  assert k({tabindex: "1"}) == [:bad_value]
  assert k({hidden: "yes"}) == [:bad_value]
  assert k({aria_hidden: 1}) == [:bad_value]
  assert k({title: [1]}) == [:bad_value]
  assert k({onclick: "x"}) == [:unknown_attribute]
  assert k({href: "/x"}) == [:unknown_attribute]
  assert k({style: {color: :text, padding: :md}, tabindex: 0}) == []
  assert kinds(refusals({tag: :br, props: {}, children: ["x"]})) == [:bad_node]
  assert kinds(refusals({tag: :p, props: [], children: []})) == [:bad_node]
  assert kinds(refusals({tag: :p, children: "x"})) == [:bad_node]
  assert kinds(refusals({tag: :p, kids: []})) == [:bad_node]
  assert kinds(refusals({tag: "p"})) == [:bad_node]
  assert kinds(refusals(view(:p, {}, [:sym, true]))) == [:bad_node, :bad_node]
  assert kinds(refusals({tag: :blink})) == [:unknown_tag]
end

test "a marker names the kind and place, never the author's text"
  out = render(
    {tag: :p, props: {"--><script>alert(1)</script>" => 1}, children: []},
    :html
  )
  assert out == "<!--gamen:refused unknown_attribute at root-->"
  assert contains?(out, "script") == false
end

test "layout builds a div with a style record and refuses what it does not know"
  assert layout(:stack, ["a"], {gap: :md}) ==
    {tag: :div, props: {style: {layout: :stack, gap: :md}}, children: ["a"]}
  assert layout(
    :grid,
    [],
    {columns: 3, align: :center, tag: :ul, props: {class: "g"}}
  ) ==
    {
      tag: :ul,
      props: {class: "g", style: {layout: :grid, columns: 3, align: :center}},
      children: []
    }
  assert layout(:row, []) ==
    {tag: :div, props: {style: {layout: :row}}, children: []}
  assert raises?(:bad_option, () -> layout(:float, []))
  assert raises?(:bad_option, () -> layout(:stack, [], {columns: 2}))
  assert raises?(:bad_option, () -> layout(:stack, [], {width: 2}))
end

test "style tokens render as variables, a layout as fixed display rules"
  assert render(
    layout(:grid, ["x"], {columns: 3, gap: :sm, align: :center}),
    :html
  ) ==
    "<div style=\"display:grid;grid-template-columns:repeat(3,minmax(0,1fr));align-items:center;gap:var(--space-sm)\">x</div>"
  assert render(
    view(
      :p,
      {
        style: {
          color: :text_muted,
          background: :surface_elevated,
          font_size: :lg,
          padding: :none
        }
      },
      ["t"]
    ),
    :html
  ) ==
    "<p style=\"padding:var(--space-none);color:var(--color-text-muted);background:var(--color-surface-elevated);font-size:var(--size-lg)\">t</p>"
  assert render(layout(:row, []), :html) ==
    "<div style=\"display:flex;flex-direction:row;flex-wrap:wrap\"></div>"
end

test "style resolves tokens through a theme, and html refuses the resolved colors"
  t = theme(
    {text: "#2E3440", accent: {light: "#5e81ac", dark: "#88c0d0"}},
    :dark
  )
  n = view(:p, {style: {color: :accent, padding: :md}}, ["x"])
  s = style(n, t)
  assert prop(s, :style) == {color: "#88c0d0", padding: "1rem"}
  assert style(view(:p), t) == view(:p)
  assert raises?(
    :bad_option,
    () -> style(view(:p, {style: {color: :error}}), t)
  )
  assert raises?(
    :bad_option,
    () -> style(view(:p, {style: {color: "#fff"}}), t)
  )
  assert kinds(refusals(s)) == [:literal_color, :not_a_token]
end

test "css writes a theme as variables and refuses a token that is no role"
  t = theme({text: "#2e3440", text_muted: "#4c566a"}, :light)
  assert css(t) ==
    ":root{--color-text:#2e3440;--color-text-muted:#4c566a;--space-none:0;--space-xs:0.25rem;--space-sm:0.5rem;--space-md:1rem;--space-lg:1.5rem;--space-xl:2rem;--size-sm:0.875rem;--size-md:1rem;--size-lg:1.25rem;--size-xl:1.5rem;--size-xxl:2rem}"
  assert raises?(:bad_option, () -> css(theme({link: "#fff"}, :light)))
  assert render(
    view(:head, {}, [view(:title, {}, ["t"])]),
    :html,
    {theme: t}
  ) == "<head><title>t</title><style>#{css(t)}</style></head>"
  assert size(color_roles) == 16
end

test "a component fills defaults and variants, takes slots, and sets its a11y row"
  button = component(
    :button,
    {
      props: {label: :required, kind: "button"},
      variants: {tone: [:plain, :danger]},
      events: [:press],
      view: fn(p, _s)
        view(
          :button,
          {type: get(p, :kind), class: "btn #{to_s(get(p, :tone))}"},
          [get(p, :label)]
        )
      end
    }
  )
  assert view(button, {label: "Save"}) ==
    {
      tag: :button,
      props: {type: "button", class: "btn plain"},
      children: ["Save"]
    }
  assert view(button, {label: "Drop", tone: :danger, kind: "submit"}) ==
    {
      tag: :button,
      props: {type: "submit", class: "btn danger"},
      children: ["Drop"]
    }
  pressed = view(button, {label: "Go", on: {press: (_e) -> nil}})
  assert map(first, map_entries(get(pressed, :events))) == [:press]
  card = component(
    :card,
    {
      props: {title: :required},
      slots: [:default, :footer],
      a11y: {role: :region, label: :title},
      view: fn(p, s)
        view(
          :section,
          {},
          [
            view(:h2, {}, [get(p, :title)]),
            get(s, :default),
            view(:footer, {}, [get(s, :footer)])
          ]
        )
      end
    }
  )
  assert view(card, {title: "News"}, {default: ["body"], footer: ["end"]}) ==
    {
      tag: :section,
      props: {role: :region, aria_label: "News"},
      children: [
        {tag: :h2, props: {}, children: ["News"]},
        "body",
        {tag: :footer, props: {}, children: ["end"]}
      ]
    }
  assert view(card, {title: "T"}, ["only"]) ==
    {
      tag: :section,
      props: {role: :region, aria_label: "T"},
      children: [
        {tag: :h2, props: {}, children: ["T"]},
        "only",
        {tag: :footer, props: {}, children: []}
      ]
    }
  nav = component(
    :nav,
    {
      props: {links: [], label: "Main"},
      a11y: {label: :label},
      view: fn(p, _s)
        view(
          :nav,
          {},
          [
            view(
              :ul,
              {},
              map(
                (l) -> view(:li, {}, [view(:a, {href: nth(1, l)}, [first(l)])]),
                get(p, :links)
              )
            )
          ]
        )
      end
    }
  )
  assert view(nav, {links: [["Home", "/"]]}) ==
    {
      tag: :nav,
      props: {aria_label: "Main"},
      children: [
        {
          tag: :ul,
          props: {},
          children: [
            {
              tag: :li,
              props: {},
              children: [{tag: :a, props: {href: "/"}, children: ["Home"]}]
            }
          ]
        }
      ]
    }
end

test "a component refuses an unknown prop, a missing one, a bad variant, slot or event"
  c = component(
    :tag,
    {
      props: {label: :required},
      variants: {size: [:sm, :lg]},
      events: [:press],
      view: (p, _s) -> view(:span, {}, [get(p, :label)])
    }
  )
  assert raises?(:bad_option, () -> view(c, {}))
  assert raises?(:bad_option, () -> view(c, {label: "x", colour: "red"}))
  assert raises?(:bad_option, () -> view(c, {label: "x", size: :xl}))
  assert raises?(:bad_option, () -> view(c, {label: "x"}, {footer: []}))
  assert raises?(
    :bad_option,
    () -> view(c, {label: "x", on: {hover: (_e) -> nil}})
  )
  assert get(view(c, {label: "x", size: :lg}), :children) == ["x"]
  assert raises?(:bad_option, () -> component("tag", {view: (_p, _s) -> nil}))
  assert raises?(:bad_option, () -> component(:tag, {}))
  assert raises?(
    :bad_option,
    () -> component(:tag, {view: (_p, _s) -> nil, colour: 1})
  )
  assert raises?(
    :bad_option,
    () -> component(:tag, {view: (_p, _s) -> nil, a11y: {role: :widget}})
  )
  assert raises?(
    :bad_option,
    () -> component(:tag, {view: (_p, _s) -> nil, a11y: {label: :title}})
  )
  assert raises?(
    :bad_option,
    () -> component(:tag, {view: (_p, _s) -> nil, variants: {size: []}})
  )
  assert raises?(
    :bad_option,
    () -> view(component(:t, {view: (_p, _s) -> "text"}), {})
  )
end

test "check finds each accessibility fault and nothing on a sound tree"
  fk = (tree) -> kinds(check(tree))
  assert fk(view(:img, {src: "/a.png"})) == [:missing_alt]
  assert fk(view(:img, {src: "/a.png", alt: ""})) == []
  assert fk(view(:input, {name: "q"})) == [:missing_label]
  assert fk(view(:input, {name: "q", aria_label: "Search"})) == []
  assert fk(view(:input, {type: "hidden", name: "q"})) == []
  assert fk(view(:label, {}, ["Name ", view(:input, {name: "n"})])) == []
  assert fk(
    view(
      :form,
      {},
      [view(:label, {for: "e"}, ["Email"]), view(:input, {id: "e"})]
    )
  ) == []
  assert fk(
    view(
      :form,
      {},
      [view(:label, {for: "x"}, ["Email"]), view(:input, {id: "e"})]
    )
  ) == [:missing_label]
  assert fk(view(:textarea, {})) == [:missing_label]
  assert fk(view(:select, {aria_label: "  "})) == [:missing_label]
  assert fk(view(:button, {}, [])) == [:missing_label]
  assert fk(view(:button, {}, ["  "])) == [:missing_label]
  assert fk(
    view(:a, {href: "/"}, [view(:img, {src: "/l.png", alt: "Home"})])
  ) == []
  assert fk(view(:a, {href: "/"}, [view(:img, {src: "/l.png", alt: ""})])) ==
    [:missing_label]
  assert fk(view(:div, {role: :clicker})) == [:bad_role]
  assert fk(view(:div, {role: "navigation"})) == []
  assert fk(view(:div, {on: {press: (_e) -> nil}})) == [:missing_role]
  assert fk(view(:div, {role: :button, on: {press: (_e) -> nil}}, ["Go"])) == []
  assert fk(view(:button, {on: {press: (_e) -> nil}}, ["Go"])) == []
  assert fk(view(:div, {tabindex: 2})) == [:focus_order]
  assert fk(view(:div, {tabindex: 0})) == []
  assert fk(view(:button, {aria_hidden: true}, ["x"])) == [:focus_order]
  assert fk(view(:p, {aria_hidden: true}, ["x"])) == []
  assert fk(
    view(
      :div,
      {},
      [view(:img, {src: "/a"}), view(:a, {href: "javascript:x"}, ["x"])]
    )
  ) == [:bad_url, :missing_alt]
  assert check(view(:img, {src: "/a"}), [focus_rule]) == []
  assert contains?(
    why(first(check(view(:div, {}, [view(:img, {src: "/a"})])))),
    "at 0 <img>"
  ) == true
end

test "a static page of components renders to one html document"
  card = component(
    :card,
    {
      props: {title: :required},
      a11y: {role: :region, label: :title},
      view: fn(p, s)
        view(
          :article,
          {style: {padding: :md, background: :surface}},
          [view(:h2, {}, [get(p, :title)]), get(s, :default)]
        )
      end
    }
  )
  t = theme({text: "#2e3440", surface: "#eceff4"}, :light)
  doc = page(
    {
      title: "Status <ok>",
      body: [
        view(
          :main,
          {},
          [
            layout(
              :stack,
              [
                view(card, {title: "Build"}, [view(:p, {}, ["green & fast"])]),
                view(
                  card,
                  {title: "Docs"},
                  [view(:a, {href: "https://blue.example/docs"}, ["read"])]
                )
              ],
              {gap: :lg}
            )
          ]
        )
      ]
    }
  )
  assert check(doc) == []
  assert render(doc, :html, {theme: t, refuse: :page}) ==
    "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta content=\"width=device-width, initial-scale=1\" name=\"viewport\"><title>Status &lt;ok&gt;</title><style>#{css(t)}</style></head><body><main><div style=\"display:flex;flex-direction:column;gap:var(--space-lg)\"><article aria-label=\"Build\" role=\"region\" style=\"padding:var(--space-md);background:var(--color-surface)\"><h2>Build</h2><p>green &amp; fast</p></article><article aria-label=\"Docs\" role=\"region\" style=\"padding:var(--space-md);background:var(--color-surface)\"><h2>Docs</h2><a href=\"https://blue.example/docs\">read</a></article></div></main></body></html>"
  assert raises?(:bad_option, () -> page({title: "x", body: [], theme: t}))
end

test "labels keys display text by each value of a closed set"
  t = labels(:Tone, {WARM: "Warm", COOL: "Cool"})
  assert t == {labels: :Tone, entries: {"WARM" => "Warm", "COOL" => "Cool"}}
  assert get(t.entries, "WARM") == "Warm"
  assert raises?(:bad_option, () -> labels("Tone", {WARM: "Warm"}))
  assert raises?(:bad_option, () -> labels(:Tone, {}))
  assert raises?(:bad_option, () -> labels(:Tone, {WARM: 1}))
end

test "an ink paints by ANSI slot, after the flags and before a hex colour, and an unknown ink is refused"
  ctx = {color: true, theme: nil}
  esc = esc_char
  assert styled({text: "x", ink: :cyan}, ctx) == "#{esc}[36mx#{esc}[0m"
  assert styled(
    {text: "x", bold: true, ink: :bright_black, fg: "#ff0000"},
    ctx
  ) == "#{esc}[1;90;38;2;255;0;0mx#{esc}[0m"
  assert styled({text: "x", ink: :cyan}, {color: false, theme: nil}) == "x"
  assert size(map_entries(inks)) == 16
  assert raises?(:bad_option, () -> styled({text: "x", ink: :teal}, ctx))
end

test "duration_text: tenths under a minute, minutes and padded seconds above"
  assert duration_text(0) == "0s"
  assert duration_text(87) == "0.1s"
  assert duration_text(59940) == "59.9s"
  assert duration_text(60000) == "1m 00s"
  assert duration_text(551_000) == "9m 11s"
end

test "a step line reads mark, place, name, note and duration, and refuses an unknown state"
  plain = {color: false, theme: nil}
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
    {color: true, theme: nil}
  ) ==
    "❌ #{esc_char}[90m[4/5]#{esc_char}[0m #{esc_char}[1;31mswitch#{esc_char}[0m"
  assert raises?(
    :bad_option,
    () -> step({state: :gone, at: 1, of: 1, name: "x"})
  )
  assert raises?(
    :bad_option,
    () -> step({state: :done, at: 1, of: 1, name: "x", eta: 1})
  )
end

test "show_step writes one line through the sink and keeps colour off when told"
  seen = [""]
  sink = (t) -> set!(seen, [concat(first(seen), t)])
  assert show_step(
    {state: :done, at: 1, of: 2, name: "x", ms: 1500},
    {sink:, color: false}
  ).nil?
  assert first(seen) == "✅ [1/2] x (1.5s)\n"
  assert terminal?(9) == false
end
