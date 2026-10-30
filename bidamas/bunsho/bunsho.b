@moduledoc """
bunsho (文書) — Markdown as a first-class value: `.md` text parsed into one typed tree whose node kinds are the ones CommonMark, GitHub Flavored Markdown and mdast agree on, the tree rendered back in one canonical formatting, and the tree read by node, by kind and by section.

A node is a record whose `kind` names it. Blocks are `:root`, `:heading`, `:paragraph`, `:blockquote`, `:list`, `:list_item`, `:code`, `:html`, `:table`, `:table_row`, `:table_cell`, `:thematic_break` and `:fact` (a fenced block whose info string is `hon`). Inside a block are `:text`, `:emphasis`, `:strong`, `:delete`, `:inline_code`, `:break`, `:link`, `:image` and `:html`. A block carries `at: [line, column]`, where it starts in the source; a link and an image carry the line they start on.

    render(parse(join_lines(["Title", "=====", "", "* one", "* two"]))) #=> join_lines(["# Title", "", "- one", "- two", ""])
"""

use("fairu", %i[normalize relative])
use("kazu", %i[max min])
use("moji", %i[is_alnum repeated text_of])

use(
  "retsu",
  %i[concat_lists find_first first flat_map last push rest take_while]
)

@doc """
ascii_punctuation: The characters a backslash escapes, and the ones that decide whether a run of `*` or `_` opens or closes.

    contains?(ascii_punctuation, "*") #=> true
"""
def ascii_punctuation()
  "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
end

@doc """
punct?: Whether one character is ASCII punctuation.

    punct?("a") #=> false
"""
def punct?(c)
  c != nil and c != "" and contains?(ascii_punctuation, c)
end

@doc """
space?: Whether one character is white space, or nil, which stands for the edge of the text.

    space?(nil) #=> true
"""
def space?(c)
  c.nil? or c == " " or c == "\t" or c == line_break
end

@doc """
leading_spaces: How many spaces open a line.

    leading_spaces("   x") #=> 3
"""
def leading_spaces(s)
  length(take_while((c) -> c == " ", chars(s)))
end

@doc """
blank?: Whether a line holds nothing but spaces.

    blank?("   ") #=> true
"""
def blank?(s)
  trim(s) == ""
end

@doc """
dropped: A line with its first `n` characters removed.

    dropped("  - a", 2) #=> "- a"
"""
def dropped(s, n)
  if n < 1
    s
  else
    join(drop(n, chars(s)), "")
  end
end

@doc """
unindented: A line with up to `n` of its leading spaces removed.

    unindented("      x", 4) #=> "  x"
"""
def unindented(s, n)
  dropped(s, min(n, leading_spaces(s)))
end

@doc """
run_of: How many times the character `c` repeats from index `i` of the characters `cs`.

    run_of(chars("**a"), 0, "*") #=> 2
"""
def run_of(cs, i, c)
  length(take_while((j) -> cs[j] == c, range(i, length(cs))))
end

@doc """
fence_open: The opening fence a line holds, as `{char:, size:, indent:, info:}`, or nil: three or more backticks or tildes after at most three spaces, and for backticks an info string with no backtick.

    fence_open("```blue file=a.b")[:info] #=> "blue file=a.b"
"""
def fence_open(s)
  ind = leading_spaces(s)
  t = dropped(s, ind)
  c = first(chars(t))
  if ind > 3 or not member?(c, %w[` ~])
    nil
  else
    size = run_of(chars(t), 0, c)
    info = trim(dropped(t, size))
    if size < 3 or c == "`" and contains?(info, "`")
      nil
    else
      {char: c, size:, indent: ind, info:}
    end
  end
end

@doc """
fence_close?: Whether a line closes the fence `open`: at most three spaces, then at least as many of the same character, then nothing.

    fence_close?("````", {char: "`", size: 3}) #=> true
"""
def fence_close?(s, open)
  ind = leading_spaces(s)
  t = trim(s)
  ind <= 3 and
    length(t) >= open[:size] and
    run_of(chars(t), 0, open[:char]) == length(t)
end

@doc """
heading_open: The ATX heading a line holds, as `{depth:, text:}`, or nil; a closing run of `#` after a space is dropped.

    heading_open("## Gaps ##") #=> {depth: 2, text: "Gaps"}
"""
def heading_open(s)
  ind = leading_spaces(s)
  t = dropped(s, ind)
  n = run_of(chars(t), 0, "#")
  after = dropped(t, n)
  if ind > 3 or n < 1 or n > 6 or after != "" and not starts_with?(after, " ")
    nil
  else
    body = trim(after)
    tail = length(take_while((c) -> c == "#", reverse(chars(body))))
    kept = if tail == length(body)
      ""
    elsif tail > 0 and
        member?(chars(body)[length(body) - tail - 1], [" ", "\t"])
      trim(join(take(length(body) - tail, chars(body)), ""))
    else
      body
    end
    {depth: n, text: kept}
  end
end

@doc """
thematic_break?: Whether a line is a thematic break: three or more of one of `-`, `*` or `_`, with spaces between them allowed.

    thematic_break?("- - -") #=> true
"""
def thematic_break?(s)
  t = replace(trim(s), " ", "")
  c = first(chars(t))
  leading_spaces(s) <= 3 and
    member?(c, %w[- * _]) and
    length(t) >= 3 and
    run_of(chars(t), 0, c) == length(t)
end

@doc """
setext_depth: The heading depth a line underlines the paragraph above it with: 1 for `=`, 2 for `-`, or nil.

    setext_depth("====") #=> 1
"""
def setext_depth(s)
  t = trim(s)
  c = first(chars(t))
  if leading_spaces(s) > 3 or
      not member?(c, %w[= -]) or
      run_of(chars(t), 0, c) != length(t)
    nil
  elsif c == "="
    1
  else
    2
  end
end

@doc """
quote_line?: Whether a line opens with a blockquote marker.

    quote_line?("> a") #=> true
"""
def quote_line?(s)
  leading_spaces(s) <= 3 and starts_with?(trim(s), ">")
end

@doc """
quote_content: A blockquote line without its marker and the one space after it, with how many characters went.

    quote_content("> a") #=> ["a", 2]
"""
def quote_content(s)
  ind = leading_spaces(s)
  rest_text = dropped(s, ind + 1)
  if starts_with?(rest_text, " ")
    [dropped(rest_text, 1), ind + 2]
  else
    [rest_text, ind + 1]
  end
end

@doc """
item_open: The list item marker a line holds, as `{ordered:, mark:, start:, indent:, width:, empty:}`, or nil: `-`, `+` or `*`, or up to nine digits and `.` or `)`, then a space or the end of the line. `width` is the column the item's content starts at.

    item_open("1. one")[:width] #=> 3
"""
def item_open(s)
  ind = leading_spaces(s)
  t = dropped(s, ind)
  cs = chars(t)
  digits = length(take_while((c) -> contains?("0123456789", c), cs))
  c = first(cs)
  marker = if member?(c, %w[- + *])
    {ordered: false, mark: c, start: nil, size: 1}
  elsif digits >= 1 and digits <= 9 and member?(cs[digits], %w[. )])
    {
      ordered: true,
      mark: cs[digits],
      start: to_int(text_of(cs, 0, digits)),
      size: digits + 1
    }
  end
  if ind > 3 or marker.nil?
    nil
  else
    after = dropped(t, marker[:size])
    if after != "" and not starts_with?(after, " ")
      nil
    else
      gap = leading_spaces(after)
      empty = blank?(after)
      pad = if empty or gap > 4
        1
      else
        gap
      end
      {
        ordered: marker[:ordered],
        mark: marker[:mark],
        start: marker[:start],
        indent: ind,
        width: ind + marker[:size] + pad,
        empty:
      }
    end
  end
end

@doc """
block_tags: The HTML tag names that open an HTML block which may interrupt a paragraph.

    member?("details", block_tags) #=> true
"""
def block_tags()
  %w[
    address
    article
    aside
    base
    basefont
    blockquote
    body
    caption
    center
    col
    colgroup
    dd
    details
    dialog
    dir
    div
    dl
    dt
    fieldset
    figcaption
    figure
    footer
    form
    frame
    frameset
    h1
    h2
    h3
    h4
    h5
    h6
    head
    header
    hr
    html
    iframe
    legend
    li
    link
    main
    menu
    menuitem
    nav
    noframes
    ol
    optgroup
    option
    p
    param
    search
    section
    summary
    table
    tbody
    td
    tfoot
    th
    thead
    title
    tr
    track
    ul
  ]
end

@doc """
tag_name: The tag name that follows `<` or `</` at the start of a text, lower case, or "".

    tag_name("</Details>") #=> "details"
"""
def tag_name(t)
  cs = chars(
    dropped(
      t,
      if starts_with?(t, "</")
        2
      else
        1
      end
    )
  )
  downcase(join(take_while((c) -> is_alnum(c) or c == "-", cs), ""))
end

@doc """
html_open: The kind of HTML block a line opens: `:comment` (ends at `-->`), `:raw` (`script`, `pre`, `style` or `textarea`, ends at its closing tag), `:block` (a block tag, ends at a blank line), `:tag` (one whole tag alone on the line, ends at a blank line, never interrupts a paragraph), or nil.

    html_open("<details>") #=> :block
"""
def html_open(s)
  t = trim(s)
  name = tag_name(t)
  after = dropped(
    t,
    length(name) +
      if starts_with?(t, "</")
        2
      else
        1
      end
  )
  if leading_spaces(s) > 3 or not starts_with?(t, "<")
    nil
  elsif starts_with?(t, "<!--")
    :comment
  elsif not starts_with?(t, "</") and
      member?(name, %w[script pre style textarea])
    :raw
  elsif member?(name, block_tags) and
      (after == "" or member?(first(chars(after)), [" ", ">", "/"]))
    :block
  elsif name != "" and ends_with?(t, ">") and not contains?(dropped(t, 1), "<")
    :tag
  end
end

@doc """
html_end?: Whether a line ends an HTML block of `kind` that started with `start`.

    html_end?("a -->", :comment, "<!--") #=> true
"""
def html_end?(s, kind, start)
  if kind == :comment
    contains?(s, "-->")
  elsif kind == :raw
    contains?(downcase(s), "</#{tag_name(trim(start))}>")
  else
    false
  end
end

@doc """
cells_of: The cells of a table row, split at each `|` that no backslash escapes, the row's outer pipes dropped and each `\\|` read as `|`.

    cells_of("| a | b\\|c |") #=> ["a", "b|c"]
"""
def cells_of(s)
  t = trim(s)
  cs = chars(t)
  st = reduce(
    fn(acc, i)
      c = cs[i]
      if acc[:skip]
        {skip: false, cells: acc[:cells], cur: push(acc[:cur], c)}
      elsif c == "\\" and cs[i + 1] == "|"
        {skip: true, cells: acc[:cells], cur: acc[:cur]}
      elsif c == "\\"
        {skip: false, cells: acc[:cells], cur: push(acc[:cur], c)}
      elsif c == "|"
        {skip: false, cells: push(acc[:cells], join(acc[:cur], "")), cur: []}
      else
        {skip: false, cells: acc[:cells], cur: push(acc[:cur], c)}
      end
    end,
    {skip: false, cells: [], cur: []},
    range(0, length(cs))
  )
  all = push(st[:cells], join(st[:cur], ""))
  inner = if starts_with?(t, "|")
    rest(all)
  else
    all
  end
  trimmed = if ends_with?(t, "|") and not ends_with?(t, "\\|") and inner != []
    take(length(inner) - 1, inner)
  else
    inner
  end
  map(trim, trimmed)
end

@doc """
delimiter_row: The column alignments a table's delimiter row states, one of `:left`, `:center`, `:right` or nil each, or nil when the line is not a delimiter row.

    delimiter_row("|:---|:-:|--:|---|") #=> [:left, :center, :right, nil]
"""
def delimiter_row(s)
  if not contains?(s, "-") or not (contains?(s, "|") or contains?(s, ":"))
    nil
  else
    cells = cells_of(s)
    ok = cells != [] and
      every?(
        fn(c)
          c != "" and
            replace(replace(c, ":", ""), "-", "") == "" and
            contains?(c, "-")
        end,
        cells
      )
    if not ok
      nil
    else
      map(
        fn(c)
          if starts_with?(c, ":") and ends_with?(c, ":")
            :center
          elsif ends_with?(c, ":")
            :right
          elsif starts_with?(c, ":")
            :left
          end
        end,
        cells
      )
    end
  end
end

@doc """
table_at?: Whether the line at `i` heads a table: it holds a `|`, and the next line is a delimiter row with as many cells.

    table_at?([["| a |", 1, 1], ["|---|", 2, 1]], 0) #=> true
"""
def table_at?(lines, i)
  if i + 1 >= length(lines) or leading_spaces(lines[i][0]) > 3
    false
  else
    head = lines[i][0]
    aligns = delimiter_row(lines[i + 1][0])
    contains?(head, "|") and
      aligns != nil and
      length(cells_of(head)) == length(aligns)
  end
end

@doc """
interrupts?: Whether the line at `i` ends a paragraph above it: a blank line, a fence, an ATX heading, a thematic break, a blockquote, an HTML block that may interrupt, a list item with content (an ordered one only from 1), or a table.

    interrupts?([["# h", 1, 1]], 0) #=> true
"""
def interrupts?(lines, i)
  s = lines[i][0]
  item = item_open(s)
  html = html_open(s)
  blank?(s) or
    fence_open(s) != nil or
    heading_open(s) != nil or
    thematic_break?(s) or
    quote_line?(s) or
    member?(html, %i[comment raw block]) or
    item != nil and
      not item[:empty] and
      (not item[:ordered] or item[:start] == 1) or
    table_at?(lines, i)
end

@doc """
open_paragraph?: Whether a container's collected lines end inside a paragraph, so that the next line may continue it lazily: the last line is not blank and no fence is open.

    open_paragraph?(["a"]) #=> true
"""
def open_paragraph?(texts)
  if texts == [] or blank?(last(texts))
    false
  else
    st = reduce(
      fn(open, t)
        if open.nil?
          fence_open(t)
        elsif fence_close?(t, open)
          nil
        else
          open
        end
      end,
      nil,
      texts
    )
    st.nil? and fence_open(last(texts)).nil? and heading_open(last(texts)).nil?
  end
end

@doc """
source_lines: The lines of a text, each numbered from 1 and starting at column 1.

    source_lines(join_lines(["a", "b"])) #=> [["a", 1, 1], ["b", 2, 1]]
"""
def source_lines(text)
  ls = split(text, line_break)
  map((i) -> [ls[i], i + 1, 1], range(0, length(ls)))
end

@doc """
start_of: The position of a line's first character that is not a space, as `[line, column]`.

    start_of(["  a", 4, 3]) #=> [4, 5]
"""
def start_of(l)
  [l[1], l[2] + leading_spaces(l[0])]
end

@doc """
fenced_at: The fenced code block that opens at line `i`, and the index after it: its closing fence, or the end of the container when it never closes.

    first(fenced_at([["```blue", 1, 1], ["1", 2, 1], ["```", 3, 1]], 0))[:text] #=> "1"
"""
def fenced_at(lines, i)
  open = fence_open(lines[i][0])
  close = find_first(
    (j) -> fence_close?(lines[j][0], open),
    range(i + 1, length(lines))
  )
  stop = close or length(lines)
  body = map((j) -> unindented(lines[j][0], open[:indent]), range(i + 1, stop))
  words = filter((w) -> w != "", split(open[:info], " "))
  lang = first(words)
  node = if lang == "hon"
    fact_words = filter((w) -> w != "", split(trim(first(body) or ""), " "))
    {
      kind: :fact,
      name: first(fact_words) or "",
      args: rest(fact_words),
      at: start_of(lines[i])
    }
  else
    {
      kind: :code,
      lang:,
      args: rest(words),
      text: join(body, line_break),
      at: start_of(lines[i])
    }
  end
  [
    node,
    if close.nil?
      stop
    else
      close + 1
    end
  ]
end

@doc """
indented_at: The indented code block that opens at line `i`, and the index after it; trailing blank lines are left to the container.

    first(indented_at([["    x", 1, 1]], 0))[:text] #=> "x"
"""
def indented_at(lines, i)
  stop = find_first(
    (j) -> not blank?(lines[j][0]) and leading_spaces(lines[j][0]) < 4,
    range(i, length(lines))
  ) or length(lines)
  kept = last_filled(lines, i, stop)
  [
    {
      kind: :code,
      lang: nil,
      args: [],
      text: join(
        map((j) -> unindented(lines[j][0], 4), range(i, kept)),
        line_break
      ),
      at: start_of(lines[i])
    },
    kept
  ]
end

@doc """
last_filled: The index after the last line from `i` before `stop` that is not blank.

    last_filled([["a", 1, 1], ["", 2, 1]], 0, 2) #=> 1
"""
def last_filled(lines, i, stop)
  reduce(
    fn(acc, j)
      if blank?(lines[j][0])
        acc
      else
        j + 1
      end
    end,
    i,
    range(i, stop)
  )
end

@doc """
html_at: The HTML block that opens at line `i`, and the index after it.

    first(html_at([["<details>", 1, 1], ["", 2, 1]], 0))[:text] #=> "<details>"
"""
def html_at(lines, i)
  kind = html_open(lines[i][0])
  stop = if member?(kind, %i[comment raw])
    hit = find_first(
      (j) -> html_end?(lines[j][0], kind, lines[i][0]),
      range(i, length(lines))
    )
    if hit.nil?
      length(lines)
    else
      hit + 1
    end
  else
    find_first((j) -> blank?(lines[j][0]), range(i, length(lines))) or
      length(lines)
  end
  [
    {
      kind: :html,
      text: join(map((j) -> lines[j][0], range(i, stop)), line_break),
      at: start_of(lines[i])
    },
    stop
  ]
end

@doc """
table_at: The table that opens at line `i`, and the index after it: rows run to a blank line or a line that opens another block.

    first(table_at([["| a |", 1, 1], ["|:-|", 2, 1], ["| b |", 3, 1]], 0))[:align] #=> [:left]
"""
def table_at(lines, i)
  aligns = delimiter_row(lines[i + 1][0])
  stop = find_first(
    fn(j)
      s = lines[j][0]
      blank?(s) or
        fence_open(s) != nil or
        heading_open(s) != nil or
        quote_line?(s) or
        member?(html_open(s), %i[comment raw block])
    end,
    range(i + 2, length(lines))
  ) or length(lines)
  rows = map(
    (j) -> table_row(cells_of(lines[j][0]), length(aligns), lines[j][1]),
    concat_lists([i], range(i + 2, stop))
  )
  [{kind: :table, align: aligns, children: rows, at: start_of(lines[i])}, stop]
end

@doc """
table_row: A row of a table on source line `line` from its cells, padded with empty cells or cut to `width`.

    length(table_row(["a"], 2, 1)[:children]) #=> 2
"""
def table_row(cells, width, line)
  {
    kind: :table_row,
    children: map(
      fn(k)
        text = if k < length(cells)
          cells[k]
        else
          ""
        end
        {kind: :table_cell, children: inlines(text, line)}
      end,
      range(0, width)
    )
  }
end

@doc """
paragraph_at: The paragraph that opens at line `i`, or the setext heading it is, and the index after it.

    first(paragraph_at([["Title", 1, 1], ["---", 2, 1]], 0))[:depth] #=> 2
"""
def paragraph_at(lines, i)
  n = length(lines)
  stop = find_first(
    (j) -> setext_depth(lines[j][0]) != nil or interrupts?(lines, j),
    range(i + 1, n)
  ) or n
  under = if stop < n
    setext_depth(lines[stop][0])
  end
  texts = map((j) -> trim(lines[j][0], {side: :start}), range(i, stop))
  if under != nil
    [
      heading_node(under, join(map(trim, texts), " "), start_of(lines[i])),
      stop + 1
    ]
  else
    [
      {
        kind: :paragraph,
        children: inlines(
          trim(join(texts, line_break), {side: :end}),
          lines[i][1]
        ),
        at: start_of(lines[i])
      },
      stop
    ]
  end
end

@doc """
heading_node: A heading of `depth` whose text is `text`; its anchor is filled in once the whole document is read.

    heading_node(1, "A", [1, 1])[:kind] #=> :heading
"""
def heading_node(depth, text, at)
  {kind: :heading, depth:, children: inlines(text, at[0]), anchor: "", at:}
end

@doc """
quote_at: The blockquote that opens at line `i`, and the index after it: its lines without their markers, and lines that lazily continue a paragraph inside it.

    first(quote_at([["> a", 1, 1], ["b", 2, 1]], 0))[:children][0][:kind] #=> :paragraph
"""
def quote_at(lines, i)
  st = reduce(
    fn(acc, j)
      s = lines[j][0]
      if acc[:done]
        acc
      elsif quote_line?(s)
        q = quote_content(s)
        {
          done: false,
          stop: j + 1,
          inner: push(acc[:inner], [q[0], lines[j][1], lines[j][2] + q[1]])
        }
      elsif not blank?(s) and
          open_paragraph?(map(first, acc[:inner])) and
          not interrupts?(lines, j)
        {
          done: false,
          stop: j + 1,
          inner: push(acc[:inner], [s, lines[j][1], lines[j][2]])
        }
      else
        {done: true, stop: acc[:stop], inner: acc[:inner]}
      end
    end,
    {done: false, stop: i, inner: []},
    range(i, length(lines))
  )
  [
    {
      kind: :blockquote,
      children: blocks_of(st[:inner])[:out],
      at: start_of(lines[i])
    },
    st[:stop]
  ]
end

@doc """
same_list?: Whether an item marker continues the list another marker started: both bullets with one character, or both ordered with one delimiter.

    same_list?({ordered: false, mark: "-"}, {ordered: false, mark: "*"}) #=> false
"""
def same_list?(a, b)
  a[:ordered] == b[:ordered] and a[:mark] == b[:mark]
end

@doc """
item_lines: The lines of the list item that opens at line `i`, its content shifted to column 1, and the index after them: lines indented to its width, blank lines, and lines that lazily continue its paragraph.

    first(item_lines([["- a", 1, 1], ["  b", 2, 1], ["- c", 3, 1]], 0)) #=> [["a", 1, 3], ["b", 2, 3]]
"""
def item_lines(lines, i)
  open = item_open(lines[i][0])
  w = open[:width]
  head = [dropped(lines[i][0], w), lines[i][1], lines[i][2] + w]
  st = reduce(
    fn(acc, j)
      s = lines[j][0]
      texts = map(first, acc[:inner])
      if acc[:done]
        acc
      elsif blank?(s)
        {done: false, inner: push(acc[:inner], ["", lines[j][1], lines[j][2]])}
      elsif leading_spaces(s) >= w
        {
          done: false,
          inner: push(
            acc[:inner],
            [dropped(s, w), lines[j][1], lines[j][2] + w]
          )
        }
      elsif open_paragraph?(texts) and
          not interrupts?(lines, j) and
          setext_depth(s).nil?
        {
          done: false,
          inner: push(
            acc[:inner],
            [trim(s, {side: :start}), lines[j][1], lines[j][2]]
          )
        }
      else
        {done: true, inner: acc[:inner]}
      end
    end,
    {done: false, inner: [head]},
    range(i + 1, length(lines))
  )
  inner = st[:inner]
  filled = reduce(
    fn(acc, k)
      if blank?(inner[k][0])
        acc
      else
        k + 1
      end
    end,
    0,
    range(0, length(inner))
  )
  [take(filled, inner), i + filled]
end

@doc """
list_at: The list that opens at line `i`, and the index after it: items with one kind of marker, blank lines between them allowed, loose when a blank line separates two items or two blocks of one item.

    first(list_at([["- a", 1, 1], ["- b", 2, 1]], 0))[:tight] #=> true
"""
def list_at(lines, i)
  open = item_open(lines[i][0])
  n = length(lines)
  st = reduce(
    fn(acc, j)
      if acc[:done] or j < acc[:next]
        acc
      else
        s = lines[j][0]
        here = item_open(s)
        if here != nil and
            same_list?(here, open) and
            leading_spaces(s) < open[:width] and
            not thematic_break?(s)
          got = item_lines(lines, j)
          parsed = blocks_of(first(got))
          after = find_first(
            (k) -> not blank?(lines[k][0]),
            range(last(got), n)
          )
          gap = after != nil and after > last(got)
          {
            done: false,
            next: last(got),
            stop: last(got),
            items: push(
              acc[:items],
              {kind: :list_item, children: parsed[:out], at: start_of(lines[j])}
            ),
            loose: acc[:loose] or parsed[:gaps] or acc[:pending],
            pending: gap
          }
        elsif blank?(s)
          acc
        else
          assoc(acc, :done, true)
        end
      end
    end,
    {done: false, next: i, stop: i, items: [], loose: false, pending: false},
    range(i, n)
  )
  [
    {
      kind: :list,
      ordered: open[:ordered],
      start: open[:start],
      tight: not st[:loose],
      children: st[:items],
      at: start_of(lines[i])
    },
    st[:stop]
  ]
end

@doc """
block_at: The block that opens at line `i` of a container's lines, and the index after it.

    first(block_at([["---", 1, 1]], 0))[:kind] #=> :thematic_break
"""
def block_at(lines, i)
  s = lines[i][0]
  h = heading_open(s)
  if fence_open(s) != nil
    fenced_at(lines, i)
  elsif leading_spaces(s) >= 4
    indented_at(lines, i)
  elsif h != nil
    [heading_node(h[:depth], h[:text], start_of(lines[i])), i + 1]
  elsif thematic_break?(s)
    [{kind: :thematic_break, at: start_of(lines[i])}, i + 1]
  elsif quote_line?(s)
    quote_at(lines, i)
  elsif item_open(s) != nil
    list_at(lines, i)
  elsif html_open(s) != nil
    html_at(lines, i)
  elsif table_at?(lines, i)
    table_at(lines, i)
  else
    paragraph_at(lines, i)
  end
end

@doc """
blocks_of: The blocks of a container's lines, and whether a blank line separates two of them, as `{out:, gaps:}`.

    blocks_of([["a", 1, 1], ["", 2, 1], ["b", 3, 1]])[:gaps] #=> true
"""
def blocks_of(lines)
  st = reduce(
    fn(acc, i)
      if i < acc[:next]
        acc
      elsif blank?(lines[i][0])
        {next: i + 1, out: acc[:out], gaps: acc[:gaps], blank: acc[:out] != []}
      else
        got = block_at(lines, i)
        {
          next: last(got),
          out: push(acc[:out], first(got)),
          gaps: acc[:gaps] or acc[:blank],
          blank: false
        }
      end
    end,
    {next: 0, out: [], gaps: false, blank: false},
    range(0, length(lines))
  )
  {out: st[:out], gaps: st[:gaps]}
end

@doc """
front_of: The front matter a text opens with, as its `[key, value]` pairs (a line that is not `key: value` is `[line, nil]`), and the lines after it; nil pairs when the text has none.

    first(front_of(join_lines(["---", "kind: howto", "---", "# A"]))) #=> [["kind", "howto"]]
"""
def front_of(text)
  ls = source_lines(text)
  close = if ls != [] and ls[0][0] == "---"
    find_first((j) -> ls[j][0] == "---", range(1, length(ls)))
  end
  if close.nil?
    [nil, ls]
  else
    [
      map(
        fn(j)
          t = ls[j][0]
          k = text_index(t, ":", 0)
          if k > 0 and not starts_with?(t, " ") and not starts_with?(t, "-")
            [trim(join(take(k, chars(t)), "")), trim(dropped(t, k + 1))]
          else
            [t, nil]
          end
        end,
        range(1, close)
      ),
      drop(close + 1, ls)
    ]
  end
end

@doc """
parse: The tree of a Markdown text: a `:root` whose `front` holds its front matter pairs (nil without any) and whose children are its blocks. Every text parses; what is not markup is text. `format` is `:markdown`, the default; any other raises `:parse_error`.

    parse("# Hi")[:children][0][:anchor] #=> "hi"
"""
def parse(text, format?)
  if format != nil and format != :markdown
    raise(:parse_error, "bunsho parses :markdown, not #{to_s(format)}")
  end
  got = front_of(text)
  with_anchors(
    {kind: :root, front: first(got), children: blocks_of(last(got))[:out]}
  )
end

@doc """
plain_text: The text a reader sees in a list of inline nodes, markup removed.

    plain_text([{kind: :text, text: "a "}, {kind: :inline_code, text: "b"}]) #=> "a b"
"""
def plain_text(nodes)
  join(
    map(
      fn(n)
        k = n[:kind]
        if member?(k, %i[text inline_code])
          n[:text]
        elsif k == :image
          n[:alt]
        elsif k == :break
          " "
        elsif k == :html
          ""
        else
          plain_text(n[:children] or [])
        end
      end,
      nodes
    ),
    ""
  )
end

@doc """
anchor_of: The anchor GitHub gives a heading's text: lower case, spaces as hyphens, ASCII punctuation and common symbols dropped, letters of every script kept.

    anchor_of("2. Install `blue` — fast") #=> "2-install-blue--fast"
"""
def anchor_of(text)
  dropped_symbols = "—–→←↑↓↔⇒§·…“”‘’«»×✓✗•©®™°±÷¶†‡★☆"
  join(
    map(
      fn(c)
        if c == " "
          "-"
        else
          c
        end
      end,
      filter(
        fn(c)
          if length(text_bytes(c)) > 1
            not contains?(dropped_symbols, c)
          else
            is_alnum(c) or c == " " or c == "-" or c == "_"
          end
        end,
        chars(downcase(trim(text)))
      )
    ),
    ""
  )
end

@doc """
with_anchors: The tree with every heading's anchor filled in, in document order; a repeated anchor takes `-1`, `-2` and so on, as GitHub numbers them.

    map((h) -> h[:anchor], extract(parse(join_lines(["# A", "# A"])), :heading)) #=> ["a", "a-1"]
"""
def with_anchors(tree)
  order = filter((n) -> n[:kind] == :heading, walk(tree))
  names = get(
    reduce(
      fn(acc, h)
        base = anchor_of(plain_text(h[:children]))
        seen = get(acc[:seen], base) or 0
        {
          seen: assoc(acc[:seen], base, seen + 1),
          names: push(
            acc[:names],
            if seen == 0
              base
            else
              "#{base}-#{to_s(seen)}"
            end
          )
        }
      end,
      {seen: {}, names: []},
      order
    ),
    :names
  )
  last(numbered_headings(tree, names, 0))
end

@doc """
numbered_headings: The tree with the headings met in document order from `next` given the anchors `names` in turn, and the index after the last one used, as `[next, tree]`.

    last(numbered_headings(parse("# A"), ["x"], 0))[:children][0][:anchor] #=> "x"
"""
def numbered_headings(node, names, next)
  here = if node[:kind] == :heading
    [next + 1, assoc(node, :anchor, names[next])]
  else
    [next, node]
  end
  kids = node[:children]
  if kids.nil? or node[:kind] == :heading
    here
  else
    st = reduce(
      fn(acc, child)
        got = numbered_headings(child, names, first(acc))
        [first(got), push(last(acc), last(got))]
      end,
      [first(here), []],
      kids
    )
    [first(st), assoc(last(here), :children, last(st))]
  end
end

@doc """
next_of: The first index at or after `from` where any of the texts `subs` occurs in `text`, or -1.

    next_of("a*b`c", ["`", "*"], 0) #=> 1
"""
def next_of(text, subs, from)
  if from >= length(text)
    -1
  else
    hits = filter((j) -> j >= 0, map((s) -> text_index(text, s, from), subs))
    if hits == []
      -1
    else
      reduce(min, first(hits), rest(hits))
    end
  end
end

@doc """
code_span_end: The index after the code span whose backtick run starts at `i`, or -1 when no run of the same length closes it.

    code_span_end("`a` b", chars("`a` b"), 0) #=> 3
"""
def code_span_end(text, cs, i)
  k = run_of(cs, i, "`")
  closing_run(text, cs, i + k, k)
end

@doc """
closing_run: The index after the first run of exactly `k` backticks at or after `from`, or -1.

    closing_run("a``b`", chars("a``b`"), 0, 1) #=> 5
"""
def closing_run(text, cs, from, k)
  j = next_of(text, ["`"], from)
  if j < 0
    -1
  else
    m = run_of(cs, j, "`")
    if m == k
      j + m
    else
      closing_run(text, cs, j + m, k)
    end
  end
end

@doc """
bracket_close: The index of the `]` that closes the `[` before `from`, past escapes, code spans and nested brackets, or -1.

    bracket_close("[a [b] `]`] c", chars("[a [b] `]`] c"), 1, 1) #=> 10
"""
def bracket_close(text, cs, from, depth)
  k = next_of(text, ["\\", "`", "[", "]"], from)
  if k < 0
    -1
  elsif cs[k] == "\\"
    bracket_close(text, cs, k + 2, depth)
  elsif cs[k] == "`"
    e = code_span_end(text, cs, k)
    past = if e < 0
      k + run_of(cs, k, "`")
    else
      e
    end
    bracket_close(text, cs, past, depth)
  elsif cs[k] == "["
    bracket_close(text, cs, k + 1, depth + 1)
  elsif depth == 1
    k
  else
    bracket_close(text, cs, k + 1, depth - 1)
  end
end

@doc """
unescaped: Text with each backslash before ASCII punctuation removed.

    unescaped("a\\*b") #=> "a*b"
"""
def unescaped(t)
  cs = chars(t)
  join(
    map(
      fn(i)
        if cs[i] == "\\" and punct?(cs[i + 1])
          ""
        else
          cs[i]
        end
      end,
      range(0, length(cs))
    ),
    ""
  )
end

@doc """
spaces_from: The first index at or after `i` that is not a space or a line break.

    spaces_from(chars("  x"), 0) #=> 2
"""
def spaces_from(cs, i)
  i +
    length(
      take_while((j) -> cs[j] != nil and space?(cs[j]), range(i, length(cs)))
    )
end

@doc """
destination: The target and title of a link whose `(` is at `p - 1`, and the index after its `)`, as `{target:, title:, end:}`, or nil when what follows is not a destination.

    destination(chars("(a.md \"T\") x"), 1)[:title] #=> "T"
"""
def destination(cs, p)
  n = length(cs)
  q = spaces_from(cs, p)
  got = if cs[q] == "<"
    close = find_first(
      (j) -> cs[j] == ">" or cs[j] == "<" or cs[j] == line_break,
      range(q + 1, n)
    )
    if close.nil? or cs[close] != ">"
      nil
    else
      [text_of(cs, q + 1, close), close + 1]
    end
  else
    st = reduce(
      fn(acc, j)
        c = cs[j]
        if acc[:stop] != nil or j < acc[:skip]
          acc
        elsif c == "\\"
          assoc(acc, :skip, j + 2)
        elsif space?(c) or c == ")" and acc[:depth] == 0
          assoc(acc, :stop, j)
        elsif c == "("
          assoc(acc, :depth, acc[:depth] + 1)
        elsif c == ")"
          assoc(acc, :depth, acc[:depth] - 1)
        else
          acc
        end
      end,
      {stop: nil, skip: 0, depth: 0},
      range(q, n)
    )
    stop = st[:stop] or n
    if st[:depth] != 0
      nil
    else
      [unescaped(text_of(cs, q, stop)), stop]
    end
  end
  if got.nil?
    nil
  else
    r = spaces_from(cs, last(got))
    opener = cs[r]
    titled = if r > last(got) and member?(opener, ["\"", "'", "("])
      shut = if opener == "("
        ")"
      else
        opener
      end
      e = find_first(
        (j) -> cs[j] == shut and cs[j - 1] != "\\",
        range(r + 1, n)
      )
      if e.nil?
        nil
      else
        [unescaped(text_of(cs, r + 1, e)), spaces_from(cs, e + 1)]
      end
    else
      [nil, r]
    end
    if titled.nil? or cs[last(titled)] != ")"
      nil
    else
      {target: first(got), title: first(titled), end: last(titled) + 1}
    end
  end
end

@doc """
flanking: Whether the run of `k` delimiters at `i` is left-flanking and right-flanking, as `[left, right]`.

    flanking(chars("a *b"), 2, 1) #=> [true, false]
"""
def flanking(cs, i, k)
  before = if i == 0
    nil
  else
    cs[i - 1]
  end
  after = cs[i + k]
  [
    not space?(after) and
      (not punct?(after) or space?(before) or punct?(before)),
    not space?(before) and
      (not punct?(before) or space?(after) or punct?(after))
  ]
end

@doc """
can_open?: Whether the run of `k` copies of `d` at `i` may open emphasis: `*` when left-flanking, `_` when left-flanking and not inside a word.

    can_open?(chars("a_b"), 1, 1, "_") #=> false
"""
def can_open?(cs, i, k, d)
  f = flanking(cs, i, k)
  before = if i == 0
    nil
  else
    cs[i - 1]
  end
  if d == "_"
    f[0] and (not f[1] or punct?(before))
  else
    f[0]
  end
end

@doc """
can_close?: Whether the run of `k` copies of `d` at `i` may close emphasis: `*` when right-flanking, `_` when right-flanking and not inside a word.

    can_close?(chars("a* b"), 1, 1, "*") #=> true
"""
def can_close?(cs, i, k, d)
  f = flanking(cs, i, k)
  if d == "_"
    f[1] and (not f[0] or punct?(cs[i + k]))
  else
    f[1]
  end
end

@doc """
closer: The index of the run of `d` that closes emphasis of size `use` opened before `from`: a run that may close, exactly one long for emphasis and at least two for strong, past escapes and code spans; -1 when none does.

    closer("**b *c* d** e", chars("**b *c* d** e"), 2, "*", 2) #=> 9
"""
def closer(text, cs, from, d, use)
  j = next_of(text, ["\\", "`", d], from)
  if j < 0
    -1
  elsif cs[j] == "\\"
    closer(text, cs, j + 2, d, use)
  elsif cs[j] == "`"
    e = code_span_end(text, cs, j)
    past = if e < 0
      j + run_of(cs, j, "`")
    else
      e
    end
    closer(text, cs, past, d, use)
  else
    m = run_of(cs, j, d)
    fits = if use == 1
      m == 1
    else
      m >= 2
    end
    if fits and can_close?(cs, j, m, d)
      j
    else
      closer(text, cs, j + m, d, use)
    end
  end
end

@doc """
tilde_closer: The index of the next run of exactly two `~` that may close a strikethrough, or -1.

    tilde_closer("~~b ~~c~~", chars("~~b ~~c~~"), 2) #=> 7
"""
def tilde_closer(text, cs, from)
  j = next_of(text, ["~"], from)
  if j < 0
    -1
  else
    m = run_of(cs, j, "~")
    if m == 2 and can_close?(cs, j, 2, "*")
      j
    else
      tilde_closer(text, cs, j + m)
    end
  end
end

@doc """
alpha?: Whether one character is an ASCII letter.

    alpha?("Q") #=> true
"""
def alpha?(c)
  c != nil and
    contains?("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", c)
end

@doc """
scheme_of: The URI scheme an autolink's text starts with, two to 32 letters, digits, `+`, `.` or `-` from a letter up to a `:`, or nil.

    scheme_of("https://x") #=> "https"
"""
def scheme_of(t)
  k = text_index(t, ":", 0)
  if k < 2 or k > 32
    nil
  else
    s = join(take(k, chars(t)), "")
    if alpha?(first(chars(s))) and
        every?((c) -> is_alnum(c) or member?(c, %w[+ . -]), chars(s))
      s
    end
  end
end

@doc """
line_of: The source line of index `i` of an inline text that starts on line `line`.

    line_of(chars(join_lines(["a", "b"])), 2, 4) #=> 5
"""
def line_of(cs, i, line)
  line + length(filter((c) -> c == line_break, take(i, cs)))
end

@doc """
with_text: An inline state with `t` added to the text not yet made a node, reading on from `next`.

    with_text({buf: [], next: 0}, "a", 1)[:buf] #=> ["a"]
"""
def with_text(acc, t, next)
  assoc(assoc(acc, :buf, push(acc[:buf], t)), :next, next)
end

@doc """
flushed: An inline state with its pending text made a `:text` node.

    flushed({buf: ["a", "b"], out: []})[:out] #=> [{kind: :text, text: "ab"}]
"""
def flushed(acc)
  t = join(acc[:buf], "")
  if t == ""
    assoc(acc, :buf, [])
  else
    assoc(assoc(acc, :out, push(acc[:out], {kind: :text, text: t})), :buf, [])
  end
end

@doc """
with_node: An inline state with its pending text flushed, then `node` added, reading on from `next`.

    with_node({buf: [], out: [], next: 0}, {kind: :break}, 2)[:next] #=> 2
"""
def with_node(acc, node, next)
  done = flushed(acc)
  assoc(assoc(done, :out, push(done[:out], node)), :next, next)
end

@doc """
specials: The characters that may begin inline markup; a run of any others is plain text.

    member?("`", specials) #=> true
"""
def specials()
  ["\\", "`", "*", "_", "[", "!", "<", "~", line_break]
end

@doc """
code_step: The inline state after the backtick run at `i`: a code span when a run of its length closes it, else the run as text.

    code_step("`a`", chars("`a`"), {next: 0, out: [], buf: []}, 0)[:out] #=> [{kind: :inline_code, text: "a"}]
"""
def code_step(text, cs, acc, i)
  e = code_span_end(text, cs, i)
  k = run_of(cs, i, "`")
  if e < 0
    with_text(acc, text_of(cs, i, i + k), i + k)
  else
    body = replace(text_of(cs, i + k, e - k), line_break, " ")
    inner = if length(body) >= 2 and
        starts_with?(body, " ") and
        ends_with?(body, " ") and
        trim(body) != ""
      text_of(chars(body), 1, length(body) - 1)
    else
      body
    end
    with_node(acc, {kind: :inline_code, text: inner}, e)
  end
end

@doc """
link_step: The inline state after the `[` or `![` at `i`: a link or an image when a bracketed label and a destination follow, else the character as text.

    link_step("[a](b)", chars("[a](b)"), 1, {next: 0, out: [], buf: []}, 0)[:out][0][:target] #=> "b"
"""
def link_step(text, cs, line, acc, i)
  c = cs[i]
  open = if c == "!"
    i + 1
  else
    i
  end
  close = bracket_close(text, cs, open + 1, 1)
  dest = if close >= 0 and cs[close + 1] == "("
    destination(cs, close + 2)
  end
  if dest.nil?
    with_text(acc, c, i + 1)
  else
    label = text_of(cs, open + 1, close)
    here = line_of(cs, i, line)
    node = if c == "!"
      {
        kind: :image,
        target: dest[:target],
        title: dest[:title],
        alt: plain_text(inlines(label, here)),
        line: here
      }
    else
      {
        kind: :link,
        target: dest[:target],
        title: dest[:title],
        children: inlines(label, here),
        line: here
      }
    end
    with_node(acc, node, dest[:end])
  end
end

@doc """
angle_step: The inline state after the `<` at `i`: an autolink, an HTML comment, an HTML tag, or the character as text.

    angle_step("<https://x>", chars("<https://x>"), 1, {next: 0, out: [], buf: []}, 0)[:out][0][:kind] #=> :link
"""
def angle_step(text, cs, line, acc, i)
  e = text_index(text, ">", i + 1)
  inside = if e < 0
    ""
  else
    text_of(cs, i + 1, e)
  end
  after = cs[i + 1]
  clean = not contains?(inside, " ") and
    not contains?(inside, "<") and
    not contains?(inside, line_break)
  if e > 0 and clean and scheme_of(inside) != nil
    with_node(
      acc,
      {
        kind: :link,
        target: inside,
        title: nil,
        children: [{kind: :text, text: inside}],
        line: line_of(cs, i, line)
      },
      e + 1
    )
  elsif text_of(cs, i, i + 4) == "<!--" and text_index(text, "-->", i + 4) > 0
    stop = text_index(text, "-->", i + 4) + 3
    with_node(acc, {kind: :html, text: text_of(cs, i, stop)}, stop)
  elsif e > 0 and
      not contains?(inside, "<") and
      (alpha?(after) or after == "/" and alpha?(cs[i + 2]))
    with_node(acc, {kind: :html, text: text_of(cs, i, e + 1)}, e + 1)
  else
    with_text(acc, "<", i + 1)
  end
end

@doc """
emphasis_step: The inline state after the run of `*` or `_` at `i`: emphasis or strong when the run may open and a run that may close follows, else the run as text.

    emphasis_step("**a**", chars("**a**"), 1, {next: 0, out: [], buf: []}, 0)[:out][0][:kind] #=> :strong
"""
def emphasis_step(text, cs, line, acc, i)
  c = cs[i]
  k = run_of(cs, i, c)
  use = if k >= 2
    2
  else
    1
  end
  j = if can_open?(cs, i, k, c)
    closer(text, cs, i + k, c, use)
  else
    -1
  end
  if j < 0 or j == i + k
    with_text(acc, text_of(cs, i, i + k), i + k)
  else
    kind = if use == 2
      :strong
    else
      :emphasis
    end
    lead = with_text(acc, text_of(cs, i, i + k - use), i)
    with_node(
      lead,
      {kind:, children: inlines(text_of(cs, i + k, j), line_of(cs, i, line))},
      j + use
    )
  end
end

@doc """
tilde_step: The inline state after the run of `~` at `i`: a strikethrough when the run is two long, may open, and a closing pair follows, else the run as text.

    tilde_step("~~a~~", chars("~~a~~"), 1, {next: 0, out: [], buf: []}, 0)[:out][0][:kind] #=> :delete
"""
def tilde_step(text, cs, line, acc, i)
  k = run_of(cs, i, "~")
  j = if k == 2 and can_open?(cs, i, 2, "*")
    tilde_closer(text, cs, i + 2)
  else
    -1
  end
  if j < 0 or j == i + 2
    with_text(acc, text_of(cs, i, i + k), i + k)
  else
    with_node(
      acc,
      {
        kind: :delete,
        children: inlines(text_of(cs, i + 2, j), line_of(cs, i, line))
      },
      j + 2
    )
  end
end

@doc """
break_step: The inline state after the line break at `i`: a hard break when two spaces end the line, else a soft break kept in the text; spaces before the break go either way.

    break_step({next: 0, out: [], buf: ["a  "]}, 1)[:out] #=> [{kind: :text, text: "a"}, {kind: :break}]
"""
def break_step(acc, i)
  so_far = join(acc[:buf], "")
  kept = trim(so_far, {side: :end})
  if ends_with?(so_far, "  ")
    with_node(assoc(acc, :buf, [kept]), {kind: :break}, i + 1)
  else
    assoc(assoc(acc, :buf, [kept, line_break]), :next, i + 1)
  end
end

@doc """
inline_step: The inline state after the markup, or the run of plain text, that starts at index `i`.

    inline_step("ab", chars("ab"), 2, 1, {next: 0, out: [], buf: []}, 0)[:next] #=> 2
"""
def inline_step(text, cs, n, line, acc, i)
  c = cs[i]
  if c == "\\" and cs[i + 1] == line_break
    with_node(acc, {kind: :break}, i + 2)
  elsif c == "\\" and punct?(cs[i + 1])
    with_text(acc, cs[i + 1], i + 2)
  elsif c == "`"
    code_step(text, cs, acc, i)
  elsif c == "[" or c == "!" and cs[i + 1] == "["
    link_step(text, cs, line, acc, i)
  elsif c == "<"
    angle_step(text, cs, line, acc, i)
  elsif c == "*" or c == "_"
    emphasis_step(text, cs, line, acc, i)
  elsif c == "~"
    tilde_step(text, cs, line, acc, i)
  elsif c == line_break
    break_step(acc, i)
  else
    stop = next_of(text, specials, i + 1)
    upto = if stop < 0
      n
    else
      stop
    end
    with_text(acc, text_of(cs, i, upto), upto)
  end
end

@doc """
inlines: The inline nodes of a block's text, which starts on source line `line`: text, emphasis, strong, strikethrough, code spans, hard breaks, links, images, autolinks and inline HTML.

    inlines("a `c`", 1) #=> [{kind: :text, text: "a "}, {kind: :inline_code, text: "c"}]
"""
def inlines(text, line)
  cs = chars(text)
  n = length(cs)
  st = reduce(
    fn(acc, i)
      if i < acc[:next]
        acc
      else
        inline_step(text, cs, n, line, acc, i)
      end
    end,
    {next: 0, out: [], buf: []},
    range(0, n)
  )
  flushed(st)[:out]
end

@doc """
blank_line: The separator between two blocks: one empty line.

    blank_line #=> unlines(["", ""])
"""
def blank_line()
  unlines(["", ""])
end

@doc """
line_start_escaped: One line of rendered paragraph text with a backslash put where its start would otherwise open a block: a heading, a blockquote, a list item, or a setext underline.

    line_start_escaped("1. x") #=> "1\\. x"
"""
def line_start_escaped(l)
  cs = chars(l)
  hashes = run_of(cs, 0, "#")
  digits = length(take_while((c) -> contains?("0123456789", c), cs))
  t = trim(l)
  if hashes >= 1 and hashes <= 6 and space?(cs[hashes])
    concat("\\", l)
  elsif starts_with?(l, ">")
    concat("\\", l)
  elsif member?(first(cs), %w[- +]) and space?(cs[1])
    concat("\\", l)
  elsif t != "" and replace(replace(t, "-", ""), " ", "") == ""
    concat("\\", l)
  elsif t != "" and replace(t, "=", "") == ""
    concat("\\", l)
  elsif digits >= 1 and
      digits <= 9 and
      member?(cs[digits], %w[. )]) and
      space?(cs[digits + 1])
    concat(text_of(cs, 0, digits), concat("\\", dropped(l, digits)))
  else
    l
  end
end

@doc """
char_escaped: One character of a text node as canonical Markdown writes it, given the characters before and after it (nil at the node's edge) and where it is: `:paragraph`, `:heading`, `:cell` or `:label`.

    char_escaped("*", "a", "b", :paragraph) #=> "\\*"
"""
def char_escaped(c, before, after, where)
  if c == "\\"
    if after.nil? or punct?(after) or after == line_break
      "\\\\"
    else
      c
    end
  elsif c == "`" or c == "[" or c == "]"
    concat("\\", c)
  elsif c == "*"
    if before != nil and after != nil and space?(before) and space?(after)
      c
    else
      "\\*"
    end
  elsif c == "_"
    inside = before != nil and
      after != nil and
      not space?(before) and
      not punct?(before) and
      not space?(after) and
      not punct?(after)
    if inside
      c
    else
      "\\_"
    end
  elsif c == "<"
    if after.nil? or alpha?(after) or member?(after, %w[/ ! ?])
      "\\<"
    else
      c
    end
  elsif c == "~"
    if before.nil? or after.nil? or before == "~" or after == "~"
      "\\~"
    else
      c
    end
  elsif c == "|" and where == :cell
    "\\|"
  else
    c
  end
end

@doc """
text_escaped: A text node as canonical Markdown writes it: each character escaped where it would otherwise be read as markup, and in a paragraph each line start escaped where it would open a block. `starts_line` says whether the node begins a line.

    text_escaped("a * b [c]", :paragraph, true) #=> "a * b \\[c\\]"
"""
def text_escaped(t, where, starts_line)
  cs = chars(t)
  n = length(cs)
  body = join(
    map(
      fn(i)
        before = if i == 0
          nil
        else
          cs[i - 1]
        end
        char_escaped(cs[i], before, cs[i + 1], where)
      end,
      range(0, n)
    ),
    ""
  )
  if where != :paragraph
    body
  else
    ls = split(body, line_break)
    join(
      map(
        fn(k)
          if k > 0 or starts_line
            line_start_escaped(ls[k])
          else
            ls[k]
          end
        end,
        range(0, length(ls))
      ),
      line_break
    )
  end
end

@doc """
code_span: Code as a code span: fenced by one more backtick than its longest run, with a space inside each end when it starts or ends with a backtick or a space; inside a table cell each `|` is escaped.

    code_span("a`b", :paragraph) #=> "``a`b``"
"""
def code_span(t, where)
  cs = chars(t)
  longest = reduce(
    (acc, i) -> max(acc, run_of(cs, i, "`")),
    0,
    range(0, length(cs))
  )
  fence = repeated("`", longest + 1)
  padded = starts_with?(t, "`") or
    ends_with?(t, "`") or
    starts_with?(t, " ") and ends_with?(t, " ") and trim(t) != ""
  inner = if where == :cell
    replace(t, "|", "\\|")
  else
    t
  end
  if padded
    "#{fence} #{inner} #{fence}"
  else
    "#{fence}#{inner}#{fence}"
  end
end

@doc """
target_text: A link destination as canonical Markdown writes it: bare, or in angle brackets when it holds a space, a bracket or an unbalanced parenthesis.

    target_text("a b.md") #=> "<a b.md>"
"""
def target_text(t)
  opens = length(filter((c) -> c == "(", chars(t)))
  shuts = length(filter((c) -> c == ")", chars(t)))
  if contains?(t, " ") or
      contains?(t, "<") or
      contains?(t, ">") or
      opens != shuts
    "<#{t}>"
  else
    replace(t, "\\", "\\\\")
  end
end

@doc """
title_text: A link title as canonical Markdown writes it after the destination, or "" when there is none.

    title_text("say \"hi\"") #=> " \"say \\\"hi\\\"\""
"""
def title_text(t)
  if t.nil?
    ""
  else
    " \"#{replace(replace(t, "\\", "\\\\"), "\"", "\\\"")}\""
  end
end

@doc """
render_inline: One inline node as canonical Markdown, `where` it is, and whether it begins a line.

    render_inline({kind: :strong, children: [{kind: :text, text: "a"}]}, :paragraph, true) #=> "**a**"
"""
def render_inline(node, where, starts_line)
  k = node[:kind]
  label_where = if where == :cell
    :cell
  else
    :label
  end
  if k == :text
    text_escaped(node[:text], where, starts_line)
  elsif k == :inline_code
    code_span(node[:text], where)
  elsif k == :emphasis
    "*#{render_inlines(node[:children], where)}*"
  elsif k == :strong
    "**#{render_inlines(node[:children], where)}**"
  elsif k == :delete
    "~~#{render_inlines(node[:children], where)}~~"
  elsif k == :break
    concat("\\", line_break)
  elsif k == :html
    node[:text]
  elsif k == :image
    "![#{text_escaped(node[:alt], label_where, false)}](#{target_text(node[:target])}#{title_text(node[:title])})"
  elsif k == :link and
      node[:title].nil? and
      node[:children] == [{kind: :text, text: node[:target]}] and
      scheme_of(node[:target]) != nil and
      not contains?(node[:target], " ")
    "<#{node[:target]}>"
  elsif k == :link
    "[#{render_inlines(node[:children], label_where)}](#{target_text(node[:target])}#{title_text(node[:title])})"
  else
    ""
  end
end

@doc """
render_inlines: Inline nodes as canonical Markdown, `where` they are.

    render_inlines([{kind: :text, text: "a "}, {kind: :inline_code, text: "b"}], :paragraph) #=> "a `b`"
"""
def render_inlines(nodes, where)
  reduce(
    fn(acc, n)
      concat(
        acc,
        render_inline(n, where, acc == "" or ends_with?(acc, line_break))
      )
    end,
    "",
    nodes
  )
end

@doc """
heading_text: A heading as canonical Markdown: its depth in `#`, then its text on one line, with a backslash before a closing run of `#` that would otherwise be dropped.

    heading_text({depth: 2, children: [{kind: :text, text: "C #"}]}) #=> "## C \\#"
"""
def heading_text(node)
  t = render_inlines(node[:children], :heading)
  cs = chars(t)
  tail = length(take_while((c) -> c == "#", reverse(cs)))
  fixed = if tail > 0 and
      (tail == length(cs) or space?(cs[length(cs) - tail - 1]))
    concat(text_of(cs, 0, length(cs) - tail), concat("\\", repeated("#", tail)))
  else
    t
  end
  marks = repeated("#", node[:depth])
  if fixed == ""
    marks
  else
    "#{marks} #{fixed}"
  end
end

@doc """
fence_for: The fence a code block is written with: one more backtick than the longest run in its text, and never fewer than three.

    fence_for("x") #=> "```"
"""
def fence_for(t)
  cs = chars(t)
  longest = reduce(
    (acc, i) -> max(acc, run_of(cs, i, "`")),
    0,
    range(0, length(cs))
  )
  repeated("`", max(3, longest + 1))
end

@doc """
indented_lines: Text with every line after the first indented by `w` spaces, an empty line kept empty.

    indented_lines(join_lines(["a", "", "b"]), 2) #=> join_lines(["a", "", "  b"])
"""
def indented_lines(t, w)
  ls = split(t, line_break)
  join(
    map(
      fn(k)
        if k == 0 or ls[k] == ""
          ls[k]
        else
          concat(repeated(" ", w), ls[k])
        end
      end,
      range(0, length(ls))
    ),
    line_break
  )
end

@doc """
list_text: A list as canonical Markdown: `-` bullets or `1.` numbers from its start (`*` and `1)` when `other`, so that two lists in a row stay two), each item's blocks indented under its marker, a blank line between items and blocks when the list is loose.

    list_text({ordered: false, tight: true, children: [{kind: :list_item, children: [{kind: :paragraph, children: [{kind: :text, text: "a"}]}]}]}, false) #=> "- a"
"""
def list_text(node, other)
  items = node[:children]
  sep = if node[:tight]
    line_break
  else
    blank_line
  end
  join(
    map(
      fn(k)
        marker = if node[:ordered]
          "#{to_s((node[:start] or 1) + k)}#{if other
  ")"
else
  "."
end}"
        elsif other
          "*"
        else
          "-"
        end
        body = render_blocks(items[k][:children], sep)
        if body == ""
          marker
        else
          concat("#{marker} ", indented_lines(body, length(marker) + 1))
        end
      end,
      range(0, length(items))
    ),
    sep
  )
end

@doc """
table_text: A table as canonical Markdown: the header row, the delimiter row from the alignments, then the rows, each cell between `| ` and ` |`.

    table_text({align: [nil], children: [{children: [{children: [{kind: :text, text: "a"}]}]}]}) #=> join_lines(["| a |", "| --- |"])
"""
def table_text(node)
  row = fn(r)
    "| #{join(map((c) -> render_inlines(c[:children], :cell), r[:children]), " | ")} |"
  end
  marks = map(
    fn(a)
      if a == :left
        ":---"
      elsif a == :center
        ":---:"
      elsif a == :right
        "---:"
      else
        "---"
      end
    end,
    node[:align]
  )
  rows = node[:children]
  join(
    concat_lists(
      [row(first(rows)), "| #{join(marks, " | ")} |"],
      map(row, rest(rows))
    ),
    line_break
  )
end

@doc """
render_block: One block as canonical Markdown, without a line break after it; `other` asks a list for its other markers.

    render_block({kind: :thematic_break}, false) #=> "***"
"""
def render_block(node, other)
  k = node[:kind]
  if k == :heading
    heading_text(node)
  elsif k == :paragraph
    render_inlines(node[:children], :paragraph)
  elsif k == :thematic_break
    "***"
  elsif k == :code
    fence = fence_for(node[:text])
    info = join(
      filter(
        (w) -> w != nil and w != "",
        concat_lists([node[:lang]], node[:args])
      ),
      " "
    )
    if node[:text] == ""
      join_lines(["#{fence}#{info}", fence])
    else
      join_lines(["#{fence}#{info}", node[:text], fence])
    end
  elsif k == :fact
    join_lines(
      ["```hon", join(concat_lists([node[:name]], node[:args]), " "), "```"]
    )
  elsif k == :html
    node[:text]
  elsif k == :blockquote
    join(
      map(
        fn(l)
          if l == ""
            ">"
          else
            "> #{l}"
          end
        end,
        split(render_blocks(node[:children], blank_line), line_break)
      ),
      line_break
    )
  elsif k == :list
    list_text(node, other)
  elsif k == :table
    table_text(node)
  else
    ""
  end
end

@doc """
render_blocks: Blocks as canonical Markdown, joined by `sep`; a list that follows a list of its kind takes the other markers, so the two stay two lists.

    render_blocks([{kind: :thematic_break}, {kind: :thematic_break}], blank_line) #=> join_lines(["***", "", "***"])
"""
def render_blocks(nodes, sep)
  st = reduce(
    fn(acc, node)
      prev = acc[:prev]
      other = node[:kind] == :list and
        prev != nil and
        prev[:kind] == :list and
        prev[:ordered] == node[:ordered] and
        not acc[:other]
      {prev: node, other:, parts: push(acc[:parts], render_block(node, other))}
    end,
    {prev: nil, other: false, parts: []},
    nodes
  )
  join(st[:parts], sep)
end

@doc """
render: The canonical Markdown of a tree: its front matter between `---` lines, then its blocks with one empty line between them, and a line break at the end; "" for an empty tree. `format` is `:markdown`, the default; any other raises `:render_error`.

    render(parse("Hi   *there*")) #=> unlines(["Hi   *there*"])
"""
def render(tree, format?)
  if format != nil and format != :markdown
    raise(:render_error, "bunsho renders :markdown, not #{to_s(format)}")
  end
  front = tree[:front]
  head = if front.nil?
    ""
  else
    join_lines(
      concat_lists(
        ["---"],
        concat_lists(
          map(
            fn(p)
              if p[1].nil?
                p[0]
              elsif p[1] == ""
                "#{p[0]}:"
              else
                "#{p[0]}: #{p[1]}"
              end
            end,
            front
          ),
          ["---"]
        )
      )
    )
  end
  parts = filter(
    (t) -> t != "",
    [head, render_blocks(tree[:children] or [], blank_line)]
  )
  if parts == []
    ""
  else
    concat(join(parts, blank_line), line_break)
  end
end

@doc """
walk: Every node under a tree, in document order, each before its children.

    map((n) -> n[:kind], walk(parse("# *a*"))) #=> [:heading, :emphasis, :text]
"""
def walk(tree)
  flat_map(tree[:children] or [], (k) -> concat_lists([k], walk(k)))
end

@doc """
extract: Every node of `kinds` in a tree, in document order; `kinds` is one kind (`:heading`, `:link`, `:code`, `:fact`, `:table` or any other) or a list of them, so the links and images a link gate reads come in one pass.

    map((l) -> l[:target], extract(parse("[a](x.md) and ![b](y.png)"), %i[link image])) #=> ["x.md", "y.png"]
"""
def extract(tree, kinds)
  wanted = if list?(kinds)
    kinds
  else
    [kinds]
  end
  filter((n) -> member?(n[:kind], wanted), walk(tree))
end

@doc """
section: The section of a tree under the top-level heading whose anchor is `anchor`: the blocks after it up to the next heading of its depth or above, without the heading; nil when no top-level heading has that anchor.

    length(section(parse(join_lines(["# A", "x", "## B", "y", "# C"])), "a")) #=> 3
"""
def section(tree, anchor)
  kids = tree[:children] or []
  at = find_first(
    (i) -> kids[i][:kind] == :heading and kids[i][:anchor] == anchor,
    range(0, length(kids))
  )
  if at.nil?
    nil
  else
    depth = kids[at][:depth]
    stop = find_first(
      (i) -> kids[i][:kind] == :heading and kids[i][:depth] <= depth,
      range(at + 1, length(kids))
    ) or length(kids)
    take(stop - at - 1, drop(at + 1, kids))
  end
end

@doc """
map_nodes: The tree with `f` applied to every node, children first, the root last.

    map_nodes(parse("a"), (n) -> assoc(n, :seen, true))[:seen] #=> true
"""
def map_nodes(tree, f)
  kids = tree[:children]
  if kids.nil?
    f(tree)
  else
    f(assoc(tree, :children, map((k) -> map_nodes(k, f), kids)))
  end
end

@doc """
outside?: Whether a link target leaves the project: a URL with a scheme, a mail address, an anchor in the same page, or an absolute path.

    outside?("#gaps") #=> true
"""
def outside?(t)
  t == "" or starts_with?(t, "#") or starts_with?(t, "/") or scheme_of(t) != nil
end

@doc """
rebase: The tree moved from directory `from` to directory `to`, both relative to one root: every relative link and image target rewritten to reach the same file, its anchor kept.

    extract(rebase(parse("[s](SAFETY.md#rows)"), "docs", ""), :link)[0][:target] #=> "docs/SAFETY.md#rows"
"""
def rebase(tree, from, to)
  map_nodes(
    tree,
    fn(n)
      if member?(n[:kind], %i[link image]) and not outside?(n[:target])
        k = text_index(n[:target], "#", 0)
        file = if k < 0
          n[:target]
        else
          join(take(k, chars(n[:target])), "")
        end
        anchor = if k < 0
          ""
        else
          dropped(n[:target], k)
        end
        moved = relative(normalize(path_join_rel(from, file)), to)
        assoc(n, :target, concat(moved, anchor))
      else
        n
      end
    end
  )
end

@doc """
path_join_rel: A relative path written in directory `dir`, as a path from the root.

    path_join_rel("docs", "a.md") #=> "docs/a.md"
"""
def path_join_rel(dir, target)
  if dir == ""
    target
  else
    "#{dir}/#{target}"
  end
end

@doc """
bare: The tree without the source positions of its nodes, for comparing two trees by what they say.

    bare(parse("# A")) == bare(parse(join_lines(["", "# A"]))) #=> true
"""
def bare(tree)
  map_nodes(tree, (n) -> dissoc(dissoc(n, :at), :line))
end

@doc """
law_failures: The pages whose text breaks one of the two laws, each as `[name, law]`: rendering is a fixed point (`render(parse(render(t))) == render(t)`), and rendering loses no structure (`parse(render(parse(x)))` is `parse(x)`, positions aside).

    law_failures([["a.md", "# A"]]) #=> []
"""
def law_failures(pages)
  flat_map(
    pages,
    fn(p)
      once = parse(last(p))
      text = render(once)
      again = parse(text)
      concat_lists(
        if render(again) == text
          []
        else
          [[first(p), :fixed_point]]
        end,
        if bare(again) == bare(once)
          []
        else
          [[first(p), :lossless]]
        end
      )
    end
  )
end

@doc """
hand_corpus: The hard cases both laws are held to, as [name, text] pages: nested and unclosed fences, lists in lists and two lists in a row, inline markup with its escapes, GFM tables, and front matter.

    map(first, hand_corpus) #=> %w[fences lists inline tables front]
"""
def hand_corpus()
  [
    [
      "fences",
      join_lines(
        [
          "````markdown",
          "```hon",
          "commands",
          "```",
          "````",
          "",
          "~~~",
          "tilde ``` inside",
          "~~~",
          "",
          "    indented code",
          "    second line",
          "",
          "```",
          "unclosed fence runs to the end"
        ]
      )
    ],
    [
      "lists",
      join_lines(
        [
          "- one",
          "- two",
          "  ## a heading in an item",
          "  - nested",
          "    - deeper",
          "",
          "* other list",
          "",
          "1. first",
          "2. second",
          "",
          "   with a second paragraph",
          "10) tenth",
          "",
          "- lazy",
          "continuation"
        ]
      )
    ],
    [
      "inline",
      join_lines(
        [
          "# Title with `code` and *emphasis* #",
          "",
          "Code `[a](b)` holds `](` as code, a [link](docs/a.md#x \"T\") and an ![image](i.png).",
          "Escapes \\*not\\* emphasis, **strong _inner_ text**, ~~gone~~, <https://example.org>, <br/> and a hard  ",
          "break, then 2 * 3 and snake_case and a\\",
          "backslash break.",
          "",
          "Title",
          "=====",
          "",
          "Sub",
          "---",
          "",
          "> quoted *text*",
          "lazy line",
          ">",
          "> - item in a quote",
          "",
          "<details>",
          "<summary>folded</summary>",
          "",
          "</details>",
          "",
          "***",
          "",
          "<!-- a comment",
          "over two lines -->"
        ]
      )
    ],
    [
      "tables",
      join_lines(
        [
          "| Command | What | Right |",
          "|:---|:---:|---:|",
          "| `blue fmt --check\\|--write` | a \\| b | [x](y.md) |",
          "| short |",
          "",
          "a | b",
          "--- | ---",
          "1 | 2"
        ]
      )
    ],
    [
      "front",
      join_lines(
        [
          "---",
          "kind: howto",
          "summary: a page: with a colon",
          "---",
          "",
          "# Page"
        ]
      )
    ]
  ]
end

test "the empty text is an empty tree, and the empty tree renders to nothing"
  assert parse("") == {kind: :root, front: nil, children: []}
  assert render(parse("")) == ""
  assert walk(parse("")) == []
end

test "both laws hold on a corpus of the hard cases"
  assert law_failures(hand_corpus) == []
end

test "a law breaks when rendering drops structure, and the law names the page"
  bad = [["two-lists", join_lines(["- a", "", "* b"])]]
  assert law_failures(bad) == []
  merged = parse(join_lines(["- a", "", "- b"]))
  assert length(extract(merged, :list)) == 1
  assert length(extract(parse(join_lines(["- a", "", "* b"])), :list)) == 2
end

test "a four-backtick fence holds a three-backtick fence as its text"
  t = parse(join_lines(%w[```` ```hon x ``` ````]))
  assert extract(t, :fact) == []
  assert first(extract(t, :code))[:text] == join_lines(%w[```hon x ```])
  assert render(t) == unlines(%w[```` ```hon x ``` ````])
end

test "a heading inside a list item is that item's heading"
  t = parse(join_lines(["- one", "  ## inside", "- two"]))
  item = first(first(t[:children])[:children])
  assert map((n) -> n[:kind], item[:children]) == %i[paragraph heading]
  assert section(t, "inside").nil?
end

test "a link-like run inside a code span is code"
  t = parse("see `[a](b)` here")
  assert extract(t, :link) == []
  assert first(extract(t, :inline_code))[:text] == "[a](b)"
end

test "a table keeps its alignments, pads a short row, and reads an escaped pipe"
  t = first(parse(join_lines(["| a | b |", "|:-|-:|", "| x\\|y |"]))[:children])
  assert t[:align] == %i[left right]
  assert length(t[:children][1][:children]) == 2
  assert plain_text(t[:children][1][:children][0][:children]) == "x|y"
  assert contains?(
    render(parse(join_lines(["| a |", "|---|", "| x\\|y |"]))),
    "x\\|y"
  )
end

test "front matter reads as pairs, in order, and is written back"
  t = parse(join_lines(["---", "kind: howto", "runs: true", "---", "# A"]))
  assert t[:front] == [%w[kind howto], %w[runs true]]
  assert starts_with?(
    render(t),
    join_lines(["---", "kind: howto", "runs: true", "---", "", "# A"])
  )
end

test "a section runs to the next heading of its depth or above"
  t = parse(join_lines(["# A", "x", "## B", "y", "# C", "z"]))
  assert map((n) -> n[:kind], section(t, "a")) ==
    %i[paragraph heading paragraph]
  assert map((n) -> n[:kind], section(t, "b")) == [:paragraph]
  assert section(t, "nothing").nil?
end

test "repeated headings take numbered anchors as GitHub gives them"
  t = parse(join_lines(["# Run", "## Run", "# Run `it` — now"]))
  assert map((h) -> h[:anchor], extract(t, :heading)) ==
    %w[run run-1 run-it--now]
end

test "links are found in tables and lists, with the line they start on"
  t = parse(join_lines(["- [a](a.md)", "", "| [b](b.md) |", "|---|"]))
  assert map((l) -> [l[:target], l[:line]], extract(t, :link)) ==
    [["a.md", 1], ["b.md", 3]]
end

test "rebase rewrites relative targets and keeps urls, anchors and absolute paths"
  t = rebase(
    parse("[a](../a.md#x) [b](https://b.org) [c](#here) [d](/abs) ![e](img/e.png)"),
    "docs/howto",
    ""
  )
  assert map((l) -> l[:target], extract(t, :link)) ==
    ["docs/a.md#x", "https://b.org", "#here", "/abs"]
  assert first(extract(t, :image))[:target] == "docs/howto/img/e.png"
end

test "a hon block is a fact node with its name and arguments"
  t = parse(join_lines(["```hon", "include implementing.md#gaps", "```"]))
  assert first(extract(t, :fact)) ==
    {kind: :fact, name: "include", args: ["implementing.md#gaps"], at: [1, 1]}
  assert render(t) == unlines(["```hon", "include implementing.md#gaps", "```"])
end

test "every text parses: stray markup is text"
  t = parse(join_lines(["[open", "`tick", "*star", "<not a tag", "a]b(c)"]))
  assert extract(t, :link) == []
  assert plain_text(first(t[:children])[:children]) ==
    join_lines(["[open", "`tick", "*star", "<not a tag", "a]b(c)"])
end

test "another format is refused by name"
  assert (parse("x", :pdf) rescue :refused) == :refused
  assert (render(parse("x"), :pdf) rescue :refused) == :refused
end

test "map_nodes reaches every node, children before their parent"
  seen = map_nodes(
    parse("a *b*"),
    fn(n)
      if n[:kind] == :emphasis
        assoc(n, :kind, :strong)
      else
        n
      end
    end
  )
  assert render(seen) == unlines(["a **b**"])
  assert map_nodes(parse(""), (n) -> n) == parse("")
end
