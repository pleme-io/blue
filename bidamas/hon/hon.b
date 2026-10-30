@moduledoc """
hon (本) — a project's book: its pages, each of one Diátaxis kind, rendered into the files a reader or an agent opens.

A page is a Markdown file under `docs/` that opens with front matter naming
its kind: `tutorial`, `howto`, `reference` or `explanation`. hon reads the
pages and returns every rendering as a value; a program writes the value.
A page with no kind is refused by name, and its siblings still render.

    page_kind(join_lines(["---", "kind: howto", "---", "# Run a test"])) #=> :howto
"""

use("kyohi", [:refusal])

use(
  "moji",
  %i[
    after_first
    before_first
    drop_chars
    is_alnum
    pad_left
    repeated
    strip_prefix
    take_chars
    trim
  ]
)

use(
  "mokuroku",
  %i[
    catalog_def_count
    catalog_of
    md_cell
    pkg_entries
    pkg_gloss
    pkg_name
    pkg_tests
  ]
)

use(
  "retsu",
  %i[
    concat_lists
    count_where
    drop_while
    find_first
    first
    flat_map
    index_of
    is_empty
    last
    push
    rest
    take_while
  ]
)

use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
page_kinds: The four Diátaxis kinds, in the order a book shows them.

    page_kinds #=> [:tutorial, :howto, :reference, :explanation]
"""
def page_kinds()
  %i[tutorial howto reference explanation]
end

@doc """
front_matter_lines: The lines between a page's opening `---` and the next `---`, or [] when the page has none.

    front_matter_lines(join_lines(["---", "kind: tutorial", "---", "# Hi"])) #=> ["kind: tutorial"]
"""
def front_matter_lines(text)
  all = split(text, line_break)
  if first(all) != "---"
    []
  else
    stop = index_of(rest(all), "---")
    if stop < 0
      []
    else
      take(stop, rest(all))
    end
  end
end

@doc """
front_matter: A page's front matter as a map from each key to its text.

    front_matter(join_lines(["---", "kind: howto", "order: 2", "---"])) #=> {"kind" => "howto", "order" => "2"}
"""
def front_matter(text)
  reduce(
    fn(acc, line)
      if contains?(line, ":")
        assoc(acc, trim(before_first(line, ":")), trim(after_first(line, ":")))
      else
        acc
      end
    end,
    {},
    front_matter_lines(text)
  )
end

@doc """
front_matter_text: The front matter block for a page of `kind` with a one-line `summary`, ending in a blank line.

    front_matter_text(:reference, "the words") #=> unlines(["---", "kind: reference", "summary: the words", "---", ""])
"""
def front_matter_text(kind, summary)
  front_matter_of([["kind", to_s(kind)], ["summary", summary]])
end

@doc """
front_matter_of: A front matter block from [key, value] pairs, in order, ending in a blank line.

    front_matter_of([["kind", "howto"]]) #=> unlines(["---", "kind: howto", "---", ""])
"""
def front_matter_of(pairs)
  unlines(
    concat_lists(
      concat_lists(["---"], map((p) -> "#{first(p)}: #{last(p)}", pairs)),
      ["---", ""]
    )
  )
end

@doc """
page_body: A page without its front matter.

    page_body(join_lines(["---", "kind: howto", "---", "# Run"])) #=> "# Run"
"""
def page_body(text)
  head = front_matter_lines(text)
  if is_empty(head)
    text
  else
    join(drop(length(head) + 2, split(text, line_break)), line_break)
  end
end

@doc """
page_kind: The kind a page's front matter declares, as a keyword, or nil when it declares none the book knows.

    page_kind("# No front matter") #=> nil
"""
def page_kind(text)
  declared = front_matter(text)["kind"]
  find_first((k) -> to_s(k) == declared, page_kinds)
end

@doc """
kind_refusals: One refusal for each page, given as [path, text], that declares no kind or a kind the book does not know.

    kind_refusals([["docs/a.md", "# A"]]) #=> [[:no_kind, "docs/a.md declares no kind: open it with front matter `kind: tutorial`, `howto`, `reference` or `explanation`"]]
"""
def kind_refusals(pages)
  flat_map(
    pages,
    fn(p)
      path = first(p)
      declared = front_matter(last(p))["kind"]
      if declared.nil?
        [
          refusal(
            :no_kind,
            "#{path} declares no kind: open it with front matter `kind: tutorial`, `howto`, `reference` or `explanation`"
          )
        ]
      elsif page_kind(last(p)).nil?
        [
          refusal(
            :unknown_kind,
            "#{path} declares kind `#{declared}`; the kinds are tutorial, howto, reference and explanation"
          )
        ]
      else
        []
      end
    end
  )
end

@doc """
doc_pages: Every Markdown page under `root/docs`, as [path from root, text], sorted by path.

    doc_pages("/nonexistent") #=> []
"""
def doc_pages(root)
  dir = path_join(root, "docs")
  if not is_dir?(dir)
    []
  else
    paths = filter((p) -> ends_with?(p, ".md"), walk_dir(dir))
    sort_keyed(
      (p) -> first(p),
      map((p) -> [strip_prefix(p, concat(root, "/")), read_file(p)], paths)
    )
  end
end

@doc """
normal_path: A relative path with each `.` step and each `dir/..` pair removed.

    normal_path("docs/howto/../SAFETY.md") #=> "docs/SAFETY.md"
"""
def normal_path(path)
  steps = reduce(
    fn(acc, step)
      if step == "" or step == "."
        acc
      elsif step == ".." and acc != [] and last(acc) != ".."
        take(length(acc) - 1, acc)
      else
        push(acc, step)
      end
    end,
    [],
    split(path, "/")
  )
  join(steps, "/")
end

@doc """
common_steps: How many leading steps two split paths share.

    common_steps(["docs", "a"], ["docs", "b"]) #=> 1
"""
def common_steps(a, b)
  if a == [] or b == [] or first(a) != first(b)
    0
  else
    1 + common_steps(rest(a), rest(b))
  end
end

@doc """
relative_path: The path to `path` as a file in directory `from` writes it, both paths relative to one root.

    relative_path("docs", "bidamas/CATALOG.md") #=> "../bidamas/CATALOG.md"
"""
def relative_path(from, path)
  a = filter((s) -> s != "", split(normal_path(from), "/"))
  b = split(normal_path(path), "/")
  n = common_steps(a, b)
  join(concat_lists(map((_s) -> "..", drop(n, a)), drop(n, b)), "/")
end

@doc """
path_in: The root-relative path of `target` written in a file in directory `dir`.

    path_in("docs", "SAFETY.md") #=> "docs/SAFETY.md"
"""
def path_in(dir, target)
  if dir == ""
    normal_path(target)
  else
    normal_path("#{dir}/#{target}")
  end
end

@doc """
outside_link?: Whether a link target leaves the project: a URL, a mail address, an anchor or an absolute path.

    outside_link?("https://example.org") #=> true
"""
def outside_link?(target)
  starts_with?(target, "#") or
    starts_with?(target, "/") or
    contains?(target, "://") or
    starts_with?(target, "mailto:")
end

@doc """
rebased_target: A link target written in directory `from`, rewritten to reach the same file from directory `to`.

    rebased_target("SAFETY.md#rows", "docs", "") #=> "docs/SAFETY.md#rows"
"""
def rebased_target(target, from, to)
  if outside_link?(target) or target == ""
    target
  else
    file = before_first(target, "#")
    anchor = if contains?(target, "#")
      concat("#", after_first(target, "#"))
    else
      ""
    end
    concat(relative_path(to, path_in(from, file)), anchor)
  end
end

@doc """
rebased_links: Markdown text moved from directory `from` to directory `to`, each relative link rewritten to reach the same file.

    rebased_links("see [safety](SAFETY.md).", "docs", "") #=> "see [safety](docs/SAFETY.md)."
"""
def rebased_links(text, from, to)
  parts = split(text, "](")
  if length(parts) < 2
    text
  else
    concat(
      first(parts),
      join(
        map(
          fn(part)
            close = text_index(part, ")", 0)
            if close < 0
              concat("](", part)
            else
              target = take_chars(part, close)
              "](#{rebased_target(target, from, to)}#{drop_chars(part, close)}"
            end
          end,
          rest(parts)
        ),
        ""
      )
    )
  end
end

@doc """
fence_line?: Whether a line opens or closes a fenced code block.

    fence_line?("```blue") #=> true
"""
def fence_line?(line)
  starts_with?(trim(line), "```")
end

@doc """
outside_fences: The text with `f` applied to every line that is not inside a fenced code block.

    outside_fences(join_lines(["a", "```", "a", "```"]), upcase) #=> join_lines(["A", "```", "a", "```"])
"""
def outside_fences(text, f)
  state = reduce(
    fn(acc, line)
      inside = first(acc)
      out = last(acc)
      if fence_line?(line)
        [not inside, push(out, line)]
      elsif inside
        [inside, push(out, line)]
      else
        [inside, push(out, f(line))]
      end
    end,
    [false, []],
    split(text, line_break)
  )
  join(last(state), line_break)
end

@doc """
demoted: The text with every heading outside code moved `n` levels down.

    demoted("# Install", 2) #=> "### Install"
"""
def demoted(text, n)
  outside_fences(
    text,
    fn(line)
      if starts_with?(line, "#")
        concat(repeated("#", n), line)
      else
        line
      end
    end
  )
end

@doc """
page_title: The text of a page body's first `# ` heading, or `fallback` when it has none.

    page_title(join_lines(["", "# Install blue"]), "x") #=> "Install blue"
"""
def page_title(body, fallback)
  line = find_first((l) -> starts_with?(l, "# "), split(body, line_break))
  if line.nil?
    fallback
  else
    trim(drop_chars(line, 2))
  end
end

@doc """
without_title: A page body without its `# ` heading and the blank lines around it.

    without_title(join_lines(["# T", "", "Body."])) #=> "Body."
"""
def without_title(body)
  ls = drop_while((l) -> trim(l) == "", split(body, line_break))
  if ls != [] and starts_with?(first(ls), "# ")
    join(drop_while((l) -> trim(l) == "", rest(ls)), line_break)
  else
    join(ls, line_break)
  end
end

@doc """
lead_sentence: The first line of prose in a page body, used when its front matter gives no summary.

    lead_sentence(join_lines(["# T", "", "It runs."])) #=> "It runs."
"""
def lead_sentence(body)
  line = find_first(
    (l) -> trim(l) != "" and not starts_with?(l, "#") and not fence_line?(l),
    split(body, line_break)
  )
  if line.nil?
    ""
  else
    trim(line)
  end
end

@doc """
lead_and_sections: [lead, sections] of a page body: the text before its first `## ` heading, and the text from it on.

    lead_and_sections(join_lines(["# T", "Lead.", "## One", "x"])) #=> [join_lines(["# T", "Lead."]), join_lines(["## One", "x"])]
"""
def lead_and_sections(body)
  state = reduce(
    fn(acc, line)
      inside = acc[0]
      lead = acc[1]
      after = acc[2]
      fence = if fence_line?(line)
        not inside
      else
        inside
      end
      if after != nil
        [fence, lead, push(after, line)]
      elsif not inside and starts_with?(line, "## ")
        [fence, lead, [line]]
      else
        [fence, push(lead, line), nil]
      end
    end,
    [false, [], nil],
    split(body, line_break)
  )
  sections = if state[2].nil?
    ""
  else
    join(state[2], line_break)
  end
  [trim(join(state[1], line_break)), trim(sections)]
end

@doc """
page_of: A page's record from its path and text: path, kind, title, summary, order, role, runs and body.

    get(page_of("docs/a.md", join_lines(["---", "kind: howto", "---", "# Run a test"])), :title) #=> "Run a test"
"""
def page_of(path, text)
  fm = front_matter(text)
  body = page_body(text)
  {
    path:,
    kind: page_kind(text),
    title: page_title(body, path_basename(path)),
    summary: fm["summary"] or lead_sentence(body),
    order: to_int(fm["order"] or "1000"),
    role: fm["role"],
    runs: fm["runs"] == "true",
    body:
  }
end

@doc """
kind_rank: Where a kind stands in the book's order, from 0.

    kind_rank(:reference) #=> 2
"""
def kind_rank(kind)
  index_of(page_kinds, kind)
end

@doc """
book_order: Pages in the book's order: by kind, then by their `order`, then by path.

    map((p) -> get(p, :path), book_order([{path: "b", kind: :explanation, order: 1}, {path: "a", kind: :tutorial, order: 9}])) #=> ["a", "b"]
"""
def book_order(pages)
  sort_keyed(
    fn(p)
      "#{to_s(kind_rank(p[:kind]))}-#{pad_left(to_s(p[:order]), 8, "0")}-#{p[:path]}"
    end,
    pages
  )
end

@doc """
kind_heading: The heading a book gives the part of one kind.

    kind_heading(:howto) #=> "How-to guides"
"""
def kind_heading(kind)
  get(
    {
      tutorial: "Tutorials",
      howto: "How-to guides",
      reference: "Reference",
      explanation: "Explanation"
    },
    kind
  )
end

@doc """
project_of: A project record from its pages, given as [path, text], and the manifest of its Bluefile.lock.

    get(project_of([], {"name" => "demo"}), :name) #=> "demo"
"""
def project_of(pages, manifest)
  records = book_order(map((p) -> page_of(first(p), last(p)), pages))
  intro = find_first((p) -> p[:role] == "introduction", records)
  {
    name: if intro.nil?
      manifest["name"]
    else
      intro[:title]
    end,
    summary: if intro.nil?
      ""
    else
      intro[:summary]
    end,
    pages: records,
    manifest:
  }
end

@doc """
project_at: The project whose root is `root`: its pages under `docs/` and its Bluefile.lock manifest.

    get(project_at("/nonexistent"), :pages) #=> []
"""
def project_at(root)
  lock = path_join(root, "Bluefile.lock")
  manifest = if path_exists(lock)
    json_read(read_file(lock))["manifest"]
  else
    {}
  end
  project_of(doc_pages(root), manifest)
end

@doc """
generated_outputs: The paths the project's Bluefile declares as generated files.

    generated_outputs({manifest: {"generated" => {"r" => {"output" => "docs/R.md"}}}}) #=> ["docs/R.md"]
"""
def generated_outputs(project)
  g = project[:manifest]["generated"]
  if g.nil?
    []
  else
    map((e) -> last(e)["output"], map_entries(g))
  end
end

@doc """
page_with_role: The project's page whose front matter names `role`, or nil.

    page_with_role({pages: []}, "agents") #=> nil
"""
def page_with_role(project, role)
  find_first((p) -> p[:role] == role, project[:pages])
end

@doc """
listed_pages: The pages a book lists under `kind`: every page of that kind except the introduction and the book itself.

    listed_pages({pages: [{path: "a", kind: :howto, role: "book"}]}, :howto) #=> []
"""
def listed_pages(project, kind)
  filter(
    (p) -> p[:kind] == kind and not member?(p[:role], %w[introduction book]),
    project[:pages]
  )
end

@doc """
rendered_path: Where a reader finds a page: the agents page is read as the AGENTS.md it renders, every other page at its own path.

    rendered_path({path: "docs/agents.md", role: "agents"}) #=> "AGENTS.md"
"""
def rendered_path(page)
  if page[:role] == "agents"
    "AGENTS.md"
  else
    page[:path]
  end
end

@doc """
page_link: A list item linking to a page from directory `to`, with its summary.

    page_link({path: "docs/a.md", title: "A", summary: "does a"}, "") #=> "- [A](docs/a.md): does a"
"""
def page_link(page, to)
  "- [#{page[:title]}](#{relative_path(to, rendered_path(page))}): #{page[:summary]}"
end

@doc """
book_map: Every listed page grouped by kind under headings of `level`, each linked from directory `to`.

    book_map({pages: [{path: "docs/a.md", kind: :howto, title: "A", summary: "s"}]}, "##", "") #=> join_lines(["## How-to guides", "", "- [A](docs/a.md): s"])
"""
def book_map(project, level, to)
  join(
    flat_map(
      page_kinds,
      fn(kind)
        pages = listed_pages(project, kind)
        if pages == []
          []
        else
          [
            join_lines(
              concat_lists(
                ["#{level} #{kind_heading(kind)}", ""],
                map((p) -> page_link(p, to), pages)
              )
            )
          ]
        end
      end
    ),
    unlines(["", ""])
  )
end

@doc """
rendered_notice: The HTML comment that opens a rendered file and names its sources and the command that rewrites it.

    rendered_notice(["docs/agents.md"]) #=> "<!-- Rendered by hon from docs/agents.md. Edit the sources, then run `nix run .#regen`. -->"
"""
def rendered_notice(sources)
  "<!-- Rendered by hon from #{join(sources, ", ")}. Edit the sources, then run `nix run .#regen`. -->"
end

@doc """
page_body_at: A page's body with its links rewritten for a file in directory `to`.

    page_body_at({path: "docs/a.md", body: "[s](S.md)"}, "") #=> "[s](docs/S.md)"
"""
def page_body_at(page, to)
  rebased_links(page[:body], path_dirname(page[:path]), to)
end

@doc """
paragraphs: Text joined from parts, one blank line between each and a line break at the end.

    paragraphs(["a", "", "b"]) #=> unlines(["a", "", "b"])
"""
def paragraphs(parts)
  unlines([join(filter((p) -> p != "", parts), unlines(["", ""]))])
end

@doc """
readme_text: README.md: the introduction's lead, a quickstart from the first tutorial, the introduction's sections, and a map of the book.

    contains?(readme_text(project_of([], {"name" => "demo"})), "demo") #=> true
"""
def readme_text(project)
  intro = page_with_role(project, "introduction")
  tutorials = listed_pages(project, :tutorial)
  book = page_with_role(project, "book")
  parts = if intro.nil?
    ["", ""]
  else
    lead_and_sections(page_body_at(intro, ""))
  end
  lead = if first(parts) == ""
    "# #{project[:name]}"
  else
    first(parts)
  end
  quick = if tutorials == []
    ""
  else
    join_lines(
      [
        "## Quickstart",
        "",
        trim(demoted(without_title(page_body_at(first(tutorials), "")), 1))
      ]
    )
  end
  where = if book.nil?
    ""
  else
    "Read it in order as [#{book[:title]}](#{book[:path]}), or open one page:"
  end
  paragraphs(
    [
      rendered_notice(
        map((p) -> p[:path], filter((p) -> p != nil, [intro, first(tutorials)]))
      ),
      lead,
      quick,
      last(parts),
      "## The book",
      where,
      readme_map(project)
    ]
  )
end

@doc """
readme_map: The book's pages as a README lists them: each tutorial, how-to and reference page in the open, and the explanation pages folded behind one line that counts them.

    readme_map({name: "demo", pages: [{path: "docs/w.md", kind: :explanation, title: "W", summary: "why"}]}) #=> join_lines(["### Explanation", "", "<details>", "<summary>1 page on why demo is shaped as it is</summary>", "", "- [W](docs/w.md): why", "", "</details>"])
"""
def readme_map(project)
  why = listed_pages(project, :explanation)
  told = book_map(
    assoc(
      project,
      :pages,
      filter((p) -> p[:kind] != :explanation, project[:pages])
    ),
    "###",
    ""
  )
  noun = if length(why) == 1
    "page"
  else
    "pages"
  end
  folded = if why == []
    ""
  else
    join_lines(
      concat_lists(
        [
          "### Explanation",
          "",
          "<details>",
          "<summary>#{to_s(length(why))} #{noun} on why #{project[:name]} is shaped as it is</summary>",
          ""
        ],
        concat_lists(map((p) -> page_link(p, ""), why), ["", "</details>"])
      )
    )
  end
  join(filter((t) -> t != "", [told, folded]), unlines(["", ""]))
end

@doc """
build_section: How to build and test the project, read from its Bluefile.lock: the checks, the generated files and the commands.

    contains?(build_section({manifest: {}}), "nix flake check") #=> true
"""
def build_section(project)
  m = project[:manifest]
  checks = map_entries(m["checks"])
  outputs = generated_outputs(project)
  catalog = m["catalog"]
  rows = concat_lists(
    [
      "| `nix flake check` | every check the Bluefile declares, and the gates every blue project gets |",
      "| `nix run .#regen` | rewrites every generated file in place |",
      "| `blue lock .` | rewrites `Bluefile.lock` after an edit to the `Bluefile` |"
    ],
    map(
      (e) -> "| `blue test #{last(e)["file"]}` | `checks.#{first(e)}` |",
      checks
    )
  )
  written = concat_lists(
    if catalog.nil?
      []
    else
      [catalog]
    end,
    outputs
  )
  paragraphs(
    [
      "## Build and test",
      "These commands come from the Bluefile. Run them from the repository root.",
      join_lines(
        concat_lists(["| Command | What it does |", "|---|---|"], rows)
      ),
      if written == []
        ""
      else
        "Generated files, never edited by hand: #{join(map((w) -> "`#{w}`", written), ", ")}."
      end
    ]
  )
end

@doc """
book_line: The sentence that names the project's book, or empty text when it has none.

    book_line({pages: []}) #=> ""
"""
def book_line(project)
  book = page_with_role(project, "book")
  if book.nil?
    ""
  else
    "Read the tutorials and how-to guides in order in [#{book[:title]}](#{book[:path]})."
  end
end

@doc """
book_pointer: Where a reader finds the book and the index of every page, as one paragraph: an agent file stays short and points into the book.

    book_pointer({pages: []}) #=> "Every page, by kind, is listed in [llms.txt](llms.txt)."
"""
def book_pointer(project)
  trim(
    concat(
      book_line(project),
      " Every page, by kind, is listed in [llms.txt](llms.txt)."
    )
  )
end

@doc """
agents_text: AGENTS.md and CLAUDE.md: the agents page's lead, the build commands from the Bluefile, the page's sections, and where the book is.

    contains?(agents_text(project_of([], {"name" => "demo"})), "Build and test") #=> true
"""
def agents_text(project)
  page = page_with_role(project, "agents")
  parts = if page.nil?
    ["# #{project[:name]}", ""]
  else
    lead_and_sections(page_body_at(page, ""))
  end
  paragraphs(
    [
      rendered_notice(
        if page.nil?
          ["Bluefile.lock"]
        else
          [page[:path], "Bluefile.lock"]
        end
      ),
      first(parts),
      trim(build_section(project), {side: :end}),
      last(parts),
      "## The book",
      book_pointer(project)
    ]
  )
end

@doc """
llms_text: llms.txt: the project's name as the heading, its summary as a quote, then one section of links per kind, explanation last as Optional.

    starts_with?(llms_text(project_of([], {"name" => "demo"})), "# demo") #=> true
"""
def llms_text(project)
  catalog = project[:manifest]["catalog"]
  sections = map(
    fn(kind)
      pages = listed_pages(project, kind)
      extra = if kind == :reference and catalog != nil
        [
          "- [#{catalog}](#{catalog}): every package and each of its definitions"
        ]
      else
        []
      end
      items = concat_lists(map((p) -> page_link(p, ""), pages), extra)
      if items == []
        ""
      else
        title = if kind == :explanation
          "Optional"
        else
          kind_heading(kind)
        end
        join_lines(concat_lists(["## #{title}", ""], items))
      end
    end,
    page_kinds
  )
  paragraphs(
    concat_lists(
      ["# #{project[:name]}", "> #{project[:summary]}", book_line(project)],
      sections
    )
  )
end

@doc """
llms_full_text: llms-full.txt: the introduction, then the full text of every hand-written tutorial, how-to and reference page, each opened by its path.

    starts_with?(llms_full_text(project_of([], {"name" => "demo"})), "# demo") #=> true
"""
def llms_full_text(project)
  generated = generated_outputs(project)
  intro = page_with_role(project, "introduction")
  pages = filter(
    (p) -> not member?(p[:path], generated),
    flat_map(%i[tutorial howto reference], (k) -> listed_pages(project, k))
  )
  shown = concat_lists(
    if intro.nil?
      []
    else
      [intro]
    end,
    pages
  )
  paragraphs(
    concat_lists(
      ["# #{project[:name]}", "> #{project[:summary]}"],
      map(
        fn(p)
          join_lines(
            ["---", "", "Source: `#{p[:path]}`", "", trim(page_body_at(p, ""))]
          )
        end,
        shown
      )
    )
  )
end

@doc """
doc_parts: [prose, examples] of a definition's `@doc` lines: the prose with the leading `name: ` removed, and each indented example line without its indent.

    doc_parts("inc", ["inc: Adds one.", "", "    inc(1)"]) #=> ["Adds one.", ["inc(1)"]]
"""
def doc_parts(name, lines)
  prose = filter((l) -> not starts_with?(l, "    "), lines)
  examples = map(
    (l) -> drop_chars(l, 4),
    filter((l) -> starts_with?(l, "    "), lines)
  )
  text = trim(join(prose, line_break))
  [strip_prefix(text, "#{name}: "), examples]
end

@doc """
entry_section: The reference section for one definition of package `pkg`: its qualified signature, its doc prose and its examples as a blue block.

    entry_section("retsu", ["size", "size(xs)", ["size: Total length.", "", "    size([])"], []]) #=> join_lines(["### `retsu::size(xs)`", "", "Total length.", "", "```blue", "size([])", "```"])
"""
def entry_section(pkg, entry)
  parts = doc_parts(first(entry), entry[2])
  examples = last(parts)
  join_lines(
    concat_lists(
      [
        "### `#{pkg}::#{entry[1]}`",
        "",
        if first(parts) == ""
          "Undocumented."
        else
          first(parts)
        end
      ],
      if examples == []
        []
      else
        concat_lists(["", "```blue"], push(examples, "```"))
      end
    )
  )
end

@doc """
reference_text: The reference of every package in `records` (mokuroku's catalogue records): each package's purpose, then each definition's signature, doc and examples.

    starts_with?(reference_text("Packages", []), "# Packages") #=> true
"""
def reference_text(title, records)
  paragraphs(
    concat_lists(
      [
        "# #{title}",
        "Rendered by hon from each package's `@moduledoc` and `@doc`. Every example below runs in `blue test`."
      ],
      map(
        fn(r)
          join_lines(
            concat_lists(
              ["## #{pkg_name(r)}", "", pkg_gloss(r)],
              flat_map(
                pkg_entries(r),
                (e) -> ["", entry_section(pkg_name(r), e)]
              )
            )
          )
        end,
        records
      )
    )
  )
end

@doc """
heading_anchor: The anchor GitHub gives a heading: lower case, spaces as hyphens, other punctuation dropped.

    heading_anchor("1. Install blue") #=> "1-install-blue"
"""
def heading_anchor(text)
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
        (c) -> is_alnum(c) or c == " " or c == "-" or c == "_",
        chars(downcase(trim(text)))
      )
    ),
    ""
  )
end

@doc """
link_from: A link to `target` written in directory `to`: a URL as it is, a project path made relative.

    link_from("docs", "https://example.org/R.md") #=> "https://example.org/R.md"
"""
def link_from(to, target)
  if outside_link?(target)
    target
  else
    relative_path(to, target)
  end
end

@doc """
reference_links: A map from each name a reader may write in code to the place the reference documents it: a built-in, given as [name, topic title], under its topic in `reference`; a package, and each of its definitions, under the package in `catalog`. Paths are written from directory `to`.

    reference_links([["trim", "Strings"]], [], "docs", "docs/REFERENCE.md", "bidamas/CATALOG.md") #=> {"trim" => "REFERENCE.md#strings"}
"""
def reference_links(builtins, records, to, reference, catalog)
  at_ref = link_from(to, reference)
  at_cat = link_from(to, catalog)
  from_records = flat_map(
    records,
    fn(r)
      concat_lists(
        [[pkg_name(r), "#{at_cat}##{pkg_name(r)}"]],
        map(
          (e) -> ["#{pkg_name(r)}::#{first(e)}", "#{at_cat}##{pkg_name(r)}"],
          pkg_entries(r)
        )
      )
    end
  )
  reduce(
    (acc, pair) -> assoc(acc, first(pair), last(pair)),
    {},
    concat_lists(
      map((b) -> [first(b), "#{at_ref}##{heading_anchor(last(b))}"], builtins),
      from_records
    )
  )
end

@doc """
called_name: The name a code span calls, when the span is a call: the text before its first parenthesis.

    called_name("argv_get(0, \"world\")") #=> "argv_get"
"""
def called_name(span)
  if contains?(span, "(")
    before_first(span, "(")
  else
    ""
  end
end

@doc """
linked_code: A line with each inline code span that names an entry of `links` turned into a link to it; a span already inside a link is left alone.

    linked_code("call `trim` here", {"trim" => "R.md#strings"}) #=> "call [`trim`](R.md#strings) here"
"""
def linked_code(line, links)
  parts = split(line, "`")
  if length(parts) % 2 == 0
    line
  else
    join(
      map(
        fn(i)
          p = parts[i]
          if i % 2 == 0
            p
          else
            url = get(links, p) or get(links, called_name(p))
            before = parts[i - 1]
            if url.nil? or ends_with?(before, "[")
              "`#{p}`"
            else
              "[`#{p}`](#{url})"
            end
          end
        end,
        range(0, length(parts))
      ),
      ""
    )
  end
end

@doc """
chapters: The book's numbered chapters: every listed tutorial, then every listed how-to, each as [number, page].

    chapters({pages: []}) #=> []
"""
def chapters(project)
  pages = concat_lists(
    listed_pages(project, :tutorial),
    listed_pages(project, :howto)
  )
  map((i) -> [i + 1, pages[i]], range(0, length(pages)))
end

@doc """
chapter_heading: A chapter's heading text: its number and its title.

    chapter_heading([3, {title: "Run a test"}]) #=> "3. Run a test"
"""
def chapter_heading(chapter)
  "#{to_s(first(chapter))}. #{last(chapter)[:title]}"
end

@doc """
book_contents: The book's table of contents: each part with its chapters linked to their anchors, and the reference and explanation pages linked from directory `to`.

    contains?(book_contents({pages: []}), "## Contents") #=> true
"""
def book_contents(project)
  all = chapters(project)
  part = fn(kind)
    mine = filter((c) -> last(c)[:kind] == kind, all)
    if mine == []
      []
    else
      concat_lists(
        ["- #{kind_heading(kind)}"],
        map(
          fn(c)
            "  - [#{chapter_heading(c)}](##{heading_anchor(chapter_heading(c))})"
          end,
          mine
        )
      )
    end
  end
  later = flat_map(
    %i[reference explanation],
    fn(kind)
      if listed_pages(project, kind) == []
        []
      else
        ["- [#{kind_heading(kind)}](##{heading_anchor(kind_heading(kind))})"]
      end
    end
  )
  join_lines(
    concat_lists(
      ["## Contents", ""],
      concat_lists(concat_lists(part(:tutorial), part(:howto)), later)
    )
  )
end

@doc """
chapter_text: One chapter as the book prints it: a numbered heading, then the page body with its headings moved under it, its links rewritten for directory `to`, and its code names linked to the reference.

    chapter_text([1, {path: "docs/t/a.md", title: "A", body: join_lines(["# A", "", "Use `trim`."])}], {"trim" => "R.md#s"}, "docs") #=> join_lines(["### 1. A", "", "Use [`trim`](R.md#s)."])
"""
def chapter_text(chapter, links, to)
  page = last(chapter)
  body = demoted(without_title(page_body_at(page, to)), 2)
  join_lines(
    [
      "### #{chapter_heading(chapter)}",
      "",
      outside_fences(body, (l) -> linked_code(l, links))
    ]
  )
end

@doc """
book_text: The book in Markdown, written to a file in directory `to`: its contents, the tutorial and how-to chapters in full, and the reference and explanation pages as linked lists.

    starts_with?(book_text(project_of([], {"name" => "demo"}), {}, "docs"), "# The demo Book") #=> true
"""
def book_text(project, links, to)
  intro = page_with_role(project, "introduction")
  all = chapters(project)
  part = fn(kind, title)
    mine = filter((c) -> last(c)[:kind] == kind, all)
    if mine == []
      ""
    else
      paragraphs(
        concat_lists(
          ["## #{title}"],
          map((c) -> chapter_text(c, links, to), mine)
        )
      )
    end
  end
  listing = fn(kind)
    pages = listed_pages(project, kind)
    if pages == []
      ""
    else
      join_lines(
        concat_lists(
          ["## #{kind_heading(kind)}", ""],
          map((p) -> page_link(p, to), pages)
        )
      )
    end
  end
  paragraphs(
    [
      "# The #{project[:name]} Book",
      if intro.nil?
        ""
      else
        intro[:summary]
      end,
      "Tutorials teach by doing, from an empty directory. How-to guides each do one task. Reference states the facts, and explanation gives the reasons. Every blue block and every console session in the first two parts runs in `blue test`, through the project's `docs` check.",
      book_contents(project),
      trim(part(:tutorial, "Tutorials"), {side: :end}),
      trim(part(:howto, "How-to guides"), {side: :end}),
      listing(:reference),
      listing(:explanation)
    ]
  )
end

@doc """
fenced_blocks: Every fenced code block in a page body, as a record of its language, its arguments and its code.

    fenced_blocks(join_lines(["```blue file=a.b", "1", "```"])) #=> [{lang: "blue", args: ["file=a.b"], code: "1"}]
"""
def fenced_blocks(body)
  state = reduce(
    fn(acc, line)
      open = first(acc)
      found = last(acc)
      if open.nil? and fence_line?(line)
        words = filter((w) -> w != "", split(drop_chars(trim(line), 3), " "))
        [{info: words, lines: []}, found]
      elsif open != nil and trim(line) == "```"
        info = open[:info]
        [
          nil,
          push(
            found,
            {
              lang: if info == []
                ""
              else
                first(info)
              end,
              args: rest(info),
              code: join(open[:lines], line_break)
            }
          )
        ]
      elsif open != nil
        [assoc(open, :lines, push(open[:lines], line)), found]
      else
        acc
      end
    end,
    [nil, []],
    split(body, line_break)
  )
  last(state)
end

@doc """
block_arg: The value of argument `key=value` among a block's arguments, or nil.

    block_arg(["file=hello.b"], "file") #=> "hello.b"
"""
def block_arg(args, key)
  hit = find_first((a) -> starts_with?(a, "#{key}="), args)
  if hit.nil?
    nil
  else
    after_first(hit, "=")
  end
end

@doc """
command_words: The words of a console command, with single and double quotes grouping words as a shell reads them.

    command_words("blue eval '1 + 2'") #=> ["blue", "eval", "1 + 2"]
"""
def command_words(line)
  state = reduce(
    fn(acc, c)
      words = acc[0]
      word = acc[1]
      mark = acc[2]
      if mark != nil and c == mark
        [words, word, nil]
      elsif mark != nil
        [words, concat(word or "", c), mark]
      elsif c == "'" or c == "\""
        [words, word or "", c]
      elsif c == " "
        if word.nil?
          acc
        else
          [push(words, word), nil, nil]
        end
      else
        [words, concat(word or "", c), nil]
      end
    end,
    [[], nil, nil],
    chars(line)
  )
  if state[1].nil?
    state[0]
  else
    push(state[0], state[1])
  end
end

@doc """
console_steps: The commands of a console block, each as [command line, expected output lines].

    console_steps(join_lines(["$ blue eval 1", "1"])) #=> [["blue eval 1", ["1"]]]
"""
def console_steps(code)
  reduce(
    fn(acc, line)
      if starts_with?(line, "$ ")
        push(acc, [drop_chars(line, 2), []])
      elsif acc == []
        acc
      else
        step = last(acc)
        push(take(length(acc) - 1, acc), [first(step), push(last(step), line)])
      end
    end,
    [],
    split(code, line_break)
  )
end

@doc """
runnable_page?: Whether the docs check runs a page's blocks: every tutorial and how-to, and any page whose front matter says `runs: true`.

    runnable_page?({kind: :howto, runs: false}) #=> true
"""
def runnable_page?(page)
  member?(page[:kind], %i[tutorial howto]) or page[:runs]
end

@doc """
run_command: Run one console command in directory `dir` with blue at `blue`: leading NAME=value words set the environment, and a leading `blue` is the blue under test.

    first(run_command("/nonexistent-blue", "/", ["true"])) #=> [:status, 0]
"""
def run_command(blue, dir, words)
  env = map(
    (w) -> [before_first(w, "="), after_first(w, "=")],
    take_while((w) -> contains?(w, "=") and not starts_with?(w, "-"), words)
  )
  rest_words = drop(length(env), words)
  program = if first(rest_words) == "blue"
    blue
  else
    first(rest_words)
  end
  exec_with_env(env, "env", "-C", dir, program, *rest(rest_words))
end

@doc """
trimmed_output: Command output without its trailing line breaks, as the book shows it.

    trimmed_output(unlines(["a", ""])) #=> "a"
"""
def trimmed_output(text)
  trim(text, {side: :end})
end

@doc """
step_failure: Why one console step does not hold, or nil. A step holds when its command exits 0 and, if the page shows output, prints exactly it; in a block marked `fails`, when its command exits non-zero and prints every line the page shows.

    step_failure("blue x", ["no"], [[:status, 1], [:stdout, ""], [:stderr, "no such file"]], true) #=> nil
"""
def step_failure(line, expected, cap, failing)
  status = status_of(cap)
  out = trimmed_output(stdout_of(cap))
  all = trimmed_output(concat(stdout_of(cap), stderr_of(cap)))
  want = trimmed_output(join(expected, line_break))
  missing = find_first((l) -> not contains?(all, trim(l)), expected)
  if failing and status == 0
    "`#{line}` exited 0; the page shows it failing"
  elsif failing and missing != nil
    "`#{line}` did not print #{inspect_text(missing)}: #{inspect_text(all)}"
  elsif failing
    nil
  elsif status != 0
    "`#{line}` exited #{to_s(status)}: #{all}"
  elsif expected != [] and out != want
    "`#{line}` printed #{inspect_text(out)}, the page shows #{inspect_text(want)}"
  end
end

@doc """
run_console: Run a console block's steps in the sandbox `root`, from the directory `here` inside it; returns [here, failures]. `cd` moves `here`; every other step is judged by `step_failure`.

    run_console("/nonexistent-blue", "/", "", [["cd sub", []]], false) #=> ["sub", []]
"""
def run_console(blue, root, here, steps, failing)
  reduce(
    fn(acc, step)
      at = first(acc)
      fails = last(acc)
      words = command_words(first(step))
      if words != [] and first(words) == "cd"
        [path_in(at, words[1]), fails]
      else
        cap = run_command(blue, path_join(root, at), words)
        why = step_failure(first(step), last(step), cap, failing)
        if why.nil?
          [at, fails]
        else
          [at, push(fails, why)]
        end
      end
    end,
    [here, []],
    steps
  )
end

@doc """
inspect_text: Text shown in a failure message as the list of its lines, so a line break or a trailing space is visible.

    inspect_text(join_lines(["a", "b"])) #=> "[\"a\", \"b\"]"
"""
def inspect_text(text)
  to_s(split(text, line_break))
end

@doc """
write_block_file: Write a block's code to `path`: a blue file through the formatter, any other file as written.

    (write_block_file("/nonexistent/dir/x.txt", "x") rescue :refused) #=> :refused
"""
def write_block_file(path, code)
  mkdir_p(path_dirname(path))
  if ends_with?(path, ".b") or path_basename(path) == "Bluefile"
    write_program(path, unlines([code]))
  else
    write_file(path, unlines([code]))
  end
end

@doc """
run_blocks: Run every blue and console block of one page, in order, in a fresh directory under `scratch`; returns the failures, each naming the page. A block with `file=PATH` is written there; a blue block without one runs, with `blue test` when it holds a test; a console block with the argument `fails` must fail; a console block with the argument `host` needs the network or nix and is shown, not run.

    run_blocks("/nonexistent-blue", getenv("TMPDIR", "/tmp"), {path: "docs/a.md", body: "No code."}) #=> []
"""
def run_blocks(blue, scratch, page)
  root = path_join(scratch, "hon-#{to_s(now_ns)}")
  mkdir_p(root)
  blocks = fenced_blocks(page[:body])
  state = reduce(
    fn(acc, i)
      here = first(acc)
      fails = last(acc)
      b = blocks[i]
      name = block_arg(b[:args], "file")
      if name != nil
        write_block_file(path_join(path_join(root, here), name), b[:code])
        acc
      elsif b[:lang] == "blue"
        file = "block-#{to_s(i)}.b"
        write_block_file(path_join(path_join(root, here), file), b[:code])
        verb = if contains?(b[:code], "test \"")
          "test"
        else
          "run"
        end
        cap = exec_with_env(
          [],
          "env",
          "-C",
          path_join(root, here),
          blue,
          *if verb == "run"
            ["run", "--quiet", file]
          else
            ["test", file]
          end
        )
        if status_of(cap) == 0
          acc
        else
          [
            here,
            push(
              fails,
              "blue block #{to_s(i)} failed: #{trimmed_output(concat(stdout_of(cap), stderr_of(cap)))}"
            )
          ]
        end
      elsif b[:lang] == "console" and not member?("host", b[:args])
        r = run_console(
          blue,
          root,
          here,
          console_steps(b[:code]),
          member?("fails", b[:args])
        )
        [first(r), concat_lists(fails, last(r))]
      else
        acc
      end
    end,
    ["", []],
    range(0, length(blocks))
  )
  rm_rf(root)
  map((f) -> "#{page[:path]}: #{f}", last(state))
end

@doc """
builtin_topics: Each built-in name with the title of its topic, as [name, title], from the JSON `blue reference` prints.

    builtin_topics(json_read("{\"topics\": [{\"slug\": \"s\", \"title\": \"Strings\"}], \"names\": [{\"name\": \"trim\", \"topic\": \"s\"}]}")) #=> [["trim", "Strings"]]
"""
def builtin_topics(reference)
  titles = reduce(
    (acc, t) -> assoc(acc, t["slug"], t["title"]),
    {},
    reference["topics"]
  )
  map((n) -> [n["name"], get(titles, n["topic"])], reference["names"])
end

@doc """
published_reference: Where the language reference is read: the project's own `docs/REFERENCE.md` when it has one, else blue's published copy.

    published_reference({pages: []}) #=> "https://github.com/pleme-io/blue/blob/main/docs/REFERENCE.md"
"""
def published_reference(project)
  own = find_first((p) -> p[:path] == "docs/REFERENCE.md", project[:pages])
  if own.nil?
    "https://github.com/pleme-io/blue/blob/main/docs/REFERENCE.md"
  else
    "docs/REFERENCE.md"
  end
end

@doc """
book_links: The code names a book written in directory `to` links: every built-in, from the reference that `blue` at `blue` prints, and every definition of the project's own packages under `root`.

    book_links(nil, "/nonexistent", project_of([], {}), "docs") #=> {}
"""
def book_links(blue, root, project, to)
  m = project[:manifest]
  builtins = if blue.nil?
    []
  else
    builtin_topics(json_read(stdout_of(exec_capture(blue, "reference"))))
  end
  roots = map((d) -> path_join(root, d), m["packages"] or [])
  records = catalog_of(filter(is_dir?, roots))
  reference_links(
    builtins,
    records,
    to,
    published_reference(project),
    m["catalog"] or "bidamas/CATALOG.md"
  )
end

@doc """
fact_names: The facts a page may hold in a `hon` block, each named by the block's first word: `commands` and `language` from the reference the rendering blue prints, `packages` from the project's catalogue, and `include PAGE#ANCHOR` for one section of another page.

    fact_names #=> %w[commands include language packages]
"""
def fact_names()
  %w[commands include language packages]
end

@doc """
fact_line: The fact a `hon` block names, as [name, arguments]: the words of its first line.

    fact_line("include implementing.md#what-is-not-built") #=> ["include", ["implementing.md#what-is-not-built"]]
"""
def fact_line(code)
  words = filter(
    (w) -> w != "",
    split(trim(first(split(code, line_break)) or ""), " ")
  )
  [first(words) or "", rest(words)]
end

@doc """
facts_in: The facts a page body names, one [name, arguments] for each of its `hon` blocks, in order.

    facts_in(join_lines(["```hon", "commands", "```", "```blue", "1", "```"])) #=> [["commands", []]]
"""
def facts_in(body)
  map(
    (b) -> fact_line(b[:code]),
    filter((b) -> b[:lang] == "hon", fenced_blocks(body))
  )
end

@doc """
with_facts: A page body with each `hon` block replaced by the text `render` gives for the fact it names; every other block is kept as written.

    with_facts(join_lines(["a", "```hon", "x", "```"]), (f) -> upcase(first(f))) #=> join_lines(["a", "X"])
"""
def with_facts(body, render)
  state = reduce(
    fn(acc, line)
      fence = acc[0]
      held = acc[1]
      out = acc[2]
      if fence.nil? and fence_line?(line)
        if trim(line) == "```hon"
          [:hon, [], out]
        else
          [:code, [], push(out, line)]
        end
      elsif fence == :hon and trim(line) == "```"
        [nil, [], push(out, render(fact_line(join(held, line_break))))]
      elsif fence == :hon
        [fence, push(held, line), out]
      elsif fence == :code and trim(line) == "```"
        [nil, [], push(out, line)]
      else
        [fence, held, push(out, line)]
      end
    end,
    [nil, [], []],
    split(body, line_break)
  )
  join(state[2], line_break)
end

@doc """
heading_level: The level of a Markdown heading line, or 0 for any other line.

    heading_level("### Three") #=> 3
"""
def heading_level(line)
  n = length(take_while((c) -> c == "#", chars(line)))
  if n > 0 and starts_with?(drop_chars(line, n), " ")
    n
  else
    0
  end
end

@doc """
section_of: The text under the heading of `body` whose anchor is `anchor`, up to the next heading of its level or above, without the heading itself; nil when no heading has that anchor.

    section_of(join_lines(["# T", "## Gaps", "none", "## Next", "x"]), "gaps") #=> "none"
"""
def section_of(body, anchor)
  state = reduce(
    fn(acc, line)
      inside = acc[0]
      level = acc[1]
      found = acc[2]
      fence = if fence_line?(line)
        not inside
      else
        inside
      end
      h = if inside or fence_line?(line)
        0
      else
        heading_level(line)
      end
      if acc[3]
        acc
      elsif level.nil? and
          h > 0 and
          heading_anchor(drop_chars(line, h + 1)) == anchor
        [fence, h, [], false]
      elsif level.nil?
        [fence, nil, found, false]
      elsif h > 0 and h <= level
        [fence, level, found, true]
      else
        [fence, level, push(found, line), false]
      end
    end,
    [false, nil, [], false],
    split(body, line_break)
  )
  if state[1].nil?
    nil
  else
    trim(join(state[2], line_break))
  end
end

@doc """
included_text: The section `target` names, written `page#anchor` from directory `dir`, with its links rewritten for `dir`; raises naming what is missing when the page or the section does not exist.

    (included_text(project_of([], {}), "docs", "a.md#gaps") rescue :refused) #=> :refused
"""
def included_text(project, dir, target)
  if target.nil? or not contains?(target, "#")
    raise(:no_section, "an include names `page#anchor`, not `#{to_s(target)}`")
  end
  path = path_in(dir, before_first(target, "#"))
  anchor = after_first(target, "#")
  page = find_first((p) -> p[:path] == path, project[:pages])
  if page.nil?
    raise(:no_page, "include #{target}: there is no page #{path}")
  end
  text = section_of(page[:body], anchor)
  if text.nil?
    raise(
      :no_section,
      "include #{target}: #{path} has no heading whose anchor is `#{anchor}`"
    )
  end
  rebased_links(text, path_dirname(path), dir)
end

@doc """
first_sentence: The first sentence of a help text, ending in a full stop.

    first_sentence("Run it. More") #=> "Run it."
"""
def first_sentence(text)
  s = trim(before_first(concat(text, " "), ". "))
  if s == "" or ends_with?(s, ".") or ends_with?(s, "?") or ends_with?(s, "!")
    s
  else
    concat(s, ".")
  end
end

@doc """
command_table: The commands `blue reference` lists, as a Markdown table: each as it is typed, with the first sentence of its help.

    command_table([{"name" => "run", "usage" => "FILE", "about" => "Run it. More", "flags" => []}]) #=> join_lines(["| Command | What it does |", "|---|---|", "| `blue run FILE` | Run it. |"])
"""
def command_table(commands)
  join_lines(
    concat_lists(
      ["| Command | What it does |", "|---|---|"],
      map(
        fn(c)
          typed = join(
            filter((w) -> w != "", ["blue", c["name"], c["usage"]]),
            " "
          )
          "| `#{md_cell(typed)}` | #{md_cell(first_sentence(c["about"]))} |"
        end,
        commands
      )
    )
  )
end

@doc """
language_table: The size of the language as `blue reference` states it, read from the tables the implementation runs on: its names by arbiter, its forms, operators and reserved words, its check rules by fix, its Bluefile words and its commands.

    contains?(language_table({"names" => [], "forms" => [], "operators" => [], "keywords" => [], "rules" => [], "bluefile" => [], "commands" => []}), "| Check rules | 0") #=> true
"""
def language_table(reference)
  names = reference["names"]
  rules = reference["rules"]
  functions = count_where((n) -> n["arbiter"] == "function", names)
  forms = count_where((n) -> n["arbiter"] == "special form", names)
  macros = count_where((n) -> n["arbiter"] == "macro", names)
  fixed = count_where((r) -> r["fix"] == "autofix", rules)
  suggested = count_where((r) -> r["fix"] == "suggested", rules)
  join_lines(
    [
      "| | |",
      "|---|---|",
      "| Built-in names | #{to_s(length(names))}: #{to_s(functions)} functions, #{to_s(forms)} special forms, #{to_s(macros)} macros |",
      "| Surface forms | #{to_s(length(reference["forms"]))}, with #{to_s(length(reference["operators"]))} operators and #{to_s(length(reference["keywords"]))} reserved words |",
      "| Check rules | #{to_s(length(rules))}: #{to_s(fixed)} fix themselves, #{to_s(suggested)} suggest a fix |",
      "| Bluefile words | #{to_s(length(reference["bluefile"]))} |",
      "| Commands | #{to_s(length(reference["commands"] or []))} |"
    ]
  )
end

@doc """
package_line: One package as a list item: its name linked to its section of the catalogue at `catalog`, then the purpose its `@moduledoc` states.

    package_line(["kazu", "0.1.0", [], "kazu (数) — numbers.", [], 0, nil, "b/kazu"], "C.md") #=> "- [kazu](C.md#kazu) (数) — numbers."
"""
def package_line(record, catalog)
  name = pkg_name(record)
  gloss = pkg_gloss(record)
  link = "[#{name}](#{catalog}##{name})"
  if gloss == ""
    "- #{link}"
  elsif starts_with?(gloss, name)
    "- #{link}#{drop_chars(gloss, length(name))}"
  else
    "- #{link} — #{gloss}"
  end
end

@doc """
package_list: The project's packages, counted, then one line each, linked into the catalogue at `catalog`.

    package_list([], "C.md") #=> "0 packages, 0 definitions, 0 tests."
"""
def package_list(records, catalog)
  tests = reduce((acc, r) -> acc + pkg_tests(r), 0, records)
  join_lines(
    concat_lists(
      [
        "#{to_s(length(records))} packages, #{to_s(catalog_def_count(records))} definitions, #{to_s(tests)} tests."
      ],
      if records == []
        []
      else
        concat_lists([""], map((r) -> package_line(r, catalog), records))
      end
    )
  )
end

@doc """
fact_sources: What the facts of a project's pages read, gathered once: the reference that `blue` at `blue` prints, when a page names `commands` or `language`, and the catalogue of the project's packages under `root`, when a page names `packages`.

    fact_sources(nil, "/nonexistent", project_of([], {})) #=> {reference: nil, packages: nil}
"""
def fact_sources(blue, root, project)
  named = map(first, flat_map(project[:pages], (p) -> facts_in(p[:body])))
  roots = map((d) -> path_join(root, d), project[:manifest]["packages"] or [])
  {
    reference: if blue.nil? or
        not any?((n) -> member?(n, %w[commands language]), named)
      nil
    else
      json_read(stdout_of(exec_capture(blue, "reference")))
    end,
    packages: if not member?("packages", named)
      nil
    elsif roots != [] and filter(is_dir?, roots) == []
      :unseen
    else
      catalog_of(filter(is_dir?, roots))
    end
  }
end

@doc """
fact_text: The text one fact renders in `page`, from the gathered `sources`; raises naming the page when the fact is unknown or its source is absent.

    (fact_text({reference: nil, packages: nil}, project_of([], {}), {path: "docs/a.md"}, ["nothing", []]) rescue :refused) #=> :refused
"""
def fact_text(sources, project, page, fact)
  name = first(fact)
  dir = path_dirname(page[:path])
  if member?(name, %w[commands language]) and sources[:reference].nil?
    raise(
      :no_reference,
      "#{page[:path]}: the `#{name}` fact reads `blue reference`, and this rendering has no blue to ask"
    )
  end
  if name == "packages" and sources[:packages] == :unseen
    raise(
      :no_packages,
      "#{page[:path]}: the `packages` fact reads #{join(project[:manifest]["packages"], ", ")}, which this rendering cannot see; list it in the inputs of the Bluefile `generate` that renders this page"
    )
  end
  if name == "commands"
    command_table(sources[:reference]["commands"] or [])
  elsif name == "language"
    language_table(sources[:reference])
  elsif name == "packages"
    package_list(
      sources[:packages] or [],
      link_from(dir, project[:manifest]["catalog"] or "bidamas/CATALOG.md")
    )
  elsif name == "include"
    with_facts(
      included_text(project, dir, first(last(fact))),
      fn(f)
        if first(f) == "include"
          raise(
            :nested_include,
            "#{page[:path]}: include #{first(last(fact))} holds another include; an included section names facts, not pages"
          )
        end
        fact_text(sources, project, page, f)
      end
    )
  else
    raise(
      :unknown_fact,
      "#{page[:path]} names the fact `#{name}`; hon renders #{join(fact_names, ", ")}"
    )
  end
end

@doc """
with_facts_of: The project with every `hon` block of every page rendered from the gathered `sources`.

    with_facts_of(project_of([], {}), {reference: nil, packages: nil})[:pages] #=> []
"""
def with_facts_of(project, sources)
  assoc(
    project,
    :pages,
    map(
      fn(p)
        assoc(
          p,
          :body,
          with_facts(p[:body], (f) -> fact_text(sources, project, p, f))
        )
      end,
      project[:pages]
    )
  )
end

@doc """
fact_refusals: One refusal for each `hon` block of the project's pages that names no fact hon renders, or includes a page or a section that does not exist; each names its page, and every other block still renders.

    fact_refusals(project_of([["docs/a.md", join_lines(["---", "kind: howto", "---", "```hon", "tally", "```"])]], {})) #=> [[:unknown_fact, "docs/a.md names the fact `tally`; hon renders commands, include, language, packages"]]
"""
def fact_refusals(project)
  flat_map(
    project[:pages],
    fn(page)
      flat_map(
        facts_in(page[:body]),
        fn(f)
          name = first(f)
          if not member?(name, fact_names)
            [
              refusal(
                :unknown_fact,
                "#{page[:path]} names the fact `#{name}`; hon renders #{join(fact_names, ", ")}"
              )
            ]
          elsif name == "include"
            begin
              included_text(project, path_dirname(page[:path]), first(last(f)))
              []
            rescue e
              [refusal(e.kind, "#{page[:path]}: #{e.message}")]
            end
          else
            []
          end
        end
      )
    end
  )
end

@doc """
rendering: The text of one rendering of the project at `root`, by name: `:readme`, `:agents`, `:llms`, `:llms_full`, or `:book` for a book written in directory `to`.

    starts_with?(rendering(:llms, "/nonexistent", ""), "# ") #=> true
"""
def rendering(name, root, to)
  written = project_at(root)
  project = with_facts_of(written, fact_sources(self_exe, root, written))
  if name == :readme
    readme_text(project)
  elsif name == :agents
    agents_text(project)
  elsif name == :llms
    llms_text(project)
  elsif name == :llms_full
    llms_full_text(project)
  elsif name == :book
    concat(
      front_matter_of(
        [
          %w[kind reference],
          %w[role book],
          [
            "summary",
            "the book: tutorials and how-to guides in full, then the reference and the explanation"
          ]
        ]
      ),
      book_text(project, book_links(self_exe, root, project, to), to)
    )
  else
    raise(
      :unknown_rendering,
      "hon renders readme, agents, llms, llms_full and book, not #{to_s(name)}"
    )
  end
end

@doc """
write_rendering: Write one rendering of the project at $GEN_ROOT (default `.`) to $GEN_OUT (default `out`): what a Bluefile `generate` runs.

    (write_rendering(:nothing, "x") rescue :refused) #=> :refused
"""
def write_rendering(name, out)
  target = getenv("GEN_OUT", out)
  text = rendering(name, getenv("GEN_ROOT", "."), path_dirname(out))
  write_file(target, text)
  target
end

test "a path climbs out of a directory it entered"
  assert normal_path("hello/..") == ""
  assert path_in("hello", "..") == ""
  assert relative_path("", "docs/a.md") == "docs/a.md"
end

test "a page with front matter declares its kind"
  page = join_lines(
    ["---", "kind: explanation", "summary: why", "---", "# Why"]
  )
  assert page_kind(page) == :explanation
  assert front_matter(page)["summary"] == "why"
  assert page_body(page) == "# Why"
end

test "the front matter a renderer writes reads back as the same kind"
  page = concat(front_matter_text(:howto, "run one test"), "# Run")
  assert page_kind(page) == :howto
  assert front_matter(page)["summary"] == "run one test"
  assert page_body(page) == join_lines(["", "# Run"])
end

test "a page without front matter has no kind and keeps its body"
  assert page_kind("# Plain").nil?
  assert front_matter("# Plain") == {}
  assert page_body("# Plain") == "# Plain"
end

test "an unclosed front matter is no front matter"
  assert front_matter_lines(join_lines(["---", "kind: howto", "# Run"])) == []
end

test "each bad page is refused alone and named"
  pages = [
    ["docs/a.md", join_lines(["---", "kind: tutorial", "---", "# A"])],
    ["docs/b.md", "# B"],
    ["docs/c.md", join_lines(["---", "kind: guide", "---", "# C"])]
  ]
  found = kind_refusals(pages)
  assert map((r) -> first(r), found) == %i[no_kind unknown_kind]
  assert contains?(last(first(found)), "docs/b.md")
  assert contains?(last(last(found)), "kind `guide`")
end

test "the kinds are listed in the book's order"
  assert page_kinds == %i[tutorial howto reference explanation]
end

test "a directory with pages is read sorted, with paths from the root"
  root = path_join(getenv("TMPDIR", "/tmp"), "hon-pages-#{to_s(now_ns)}")
  mkdir_p(path_join(root, "docs/howto"))
  write_file(path_join(root, "docs/b.md"), "# B")
  write_file(path_join(root, "docs/howto/a.md"), "# A")
  write_file(path_join(root, "docs/notes.txt"), "not a page")
  found = doc_pages(root)
  rm_rf(root)
  assert map((p) -> first(p), found) == %w[docs/b.md docs/howto/a.md]
end

@doc """
sample_pages: The pages of a small sample project the tests render: an introduction, a tutorial, a how-to, an agents page and an explanation.

    length(sample_pages) #=> 5
"""
def sample_pages()
  [
    [
      "docs/introduction.md",
      join_lines(
        [
          "---",
          "kind: explanation",
          "role: introduction",
          "summary: demo is a small language.",
          "---",
          "# demo",
          "",
          "demo is a small language. See [safety](SAFETY.md).",
          "",
          "## Building",
          "",
          "Run the build."
        ]
      )
    ],
    [
      "docs/tutorial/install.md",
      join_lines(
        [
          "---",
          "kind: tutorial",
          "order: 1",
          "summary: install demo",
          "---",
          "# Install demo",
          "",
          "Call `trim`, then read [the reference](../REFERENCE.md).",
          "",
          "## Check it",
          "",
          "```console",
          "$ blue eval 1",
          "1",
          "```"
        ]
      )
    ],
    [
      "docs/howto/test.md",
      join_lines(
        ["---", "kind: howto", "---", "# Write a test", "", "Write one."]
      )
    ],
    [
      "docs/agents.md",
      join_lines(
        [
          "---",
          "kind: reference",
          "role: agents",
          "summary: rules for agents",
          "---",
          "# demo for agents",
          "",
          "Read this first.",
          "",
          "## Traps",
          "",
          "One trap."
        ]
      )
    ],
    [
      "docs/DESIGN.md",
      join_lines(
        ["---", "kind: explanation", "summary: why it is so", "---", "# Design"]
      )
    ]
  ]
end

@doc """
sample_project: The sample pages as a project, with a manifest that declares a catalogue, a check and a generated README.

    get(sample_project, :name) #=> "demo"
"""
def sample_project()
  project_of(
    sample_pages,
    {
      "name" => "demo-repository",
      "catalog" => "bidamas/CATALOG.md",
      "checks" => {"docs" => {"file" => "gen/docs.b", "inputs" => ["docs"]}},
      "generated" => {"readme" => {"output" => "README.md"}}
    }
  )
end

test "the project takes its name and summary from the introduction"
  p = sample_project
  assert p[:name] == "demo"
  assert p[:summary] == "demo is a small language."
  assert map((x) -> x[:path], p[:pages]) ==
    %w[
      docs/tutorial/install.md
      docs/howto/test.md
      docs/agents.md
      docs/DESIGN.md
      docs/introduction.md
    ]
end

test "the README leads with the introduction, then the first tutorial as a quickstart"
  r = readme_text(sample_project)
  assert starts_with?(r, "<!-- Rendered by hon")
  assert contains?(r, "See [safety](docs/SAFETY.md).")
  assert contains?(r, "## Quickstart")
  assert contains?(r, "### Check it")
  assert contains?(r, "[the reference](docs/REFERENCE.md)")
  assert text_index(r, "## Quickstart", 0) < text_index(r, "## Building", 0)
  assert contains?(r, "- [Write a test](docs/howto/test.md): Write one.")
  assert contains?(r, "- [demo for agents](AGENTS.md): rules for agents")
  assert not contains?(r, "](docs/introduction.md)")
end

test "the agent file carries the Bluefile's commands between the page's lead and its sections"
  a = agents_text(sample_project)
  assert contains?(a, "| `blue test gen/docs.b` | `checks.docs` |")
  assert contains?(a, "`bidamas/CATALOG.md`, `README.md`")
  assert text_index(a, "Read this first.", 0) <
    text_index(a, "## Build and test", 0)
  assert text_index(a, "## Build and test", 0) < text_index(a, "## Traps", 0)
end

test "llms.txt is a heading, a quoted summary and one section of links per kind"
  l = llms_text(sample_project)
  assert starts_with?(
    l,
    join_lines(
      ["# demo", "", "> demo is a small language.", "", "## Tutorials"]
    )
  )
  assert contains?(
    l,
    "- [bidamas/CATALOG.md](bidamas/CATALOG.md): every package and each of its definitions"
  )
  assert contains?(
    l,
    join_lines(["## Optional", "", "- [Design](docs/DESIGN.md): why it is so"])
  )
end

test "llms-full.txt holds the hand-written pages in full and leaves out the explanation"
  f = llms_full_text(sample_project)
  assert contains?(f, "Source: `docs/tutorial/install.md`")
  assert contains?(f, "One trap.")
  assert not contains?(f, "Source: `docs/DESIGN.md`")
end

test "the book numbers its chapters, links its contents and its code names"
  b = book_text(sample_project, {"trim" => "REFERENCE.md#strings"}, "docs")
  assert contains?(b, "  - [1. Install demo](#1-install-demo)")
  assert contains?(b, "  - [2. Write a test](#2-write-a-test)")
  assert contains?(b, "### 1. Install demo")
  assert contains?(b, "#### Check it")
  assert contains?(b, "Call [`trim`](REFERENCE.md#strings)")
  assert contains?(b, "[the reference](REFERENCE.md)")
  assert contains?(b, "- [Design](DESIGN.md): why it is so")
end

test "every block of a page runs, and a wrong output or a failing command is named"
  if self_exe != nil
    good = page_of(
      "docs/t.md",
      join_lines(
        [
          "---",
          "kind: tutorial",
          "---",
          "```blue file=hello.b",
          "write_stdout(unlines([\"hi\"]))",
          "```",
          "```console",
          "$ mkdir sub",
          "$ cd sub",
          "$ blue ../hello.b",
          "hi",
          "```",
          "```blue",
          "test \"one\"",
          "  assert 1 + 1 == 2",
          "end",
          "```",
          "```console fails",
          "$ blue missing.b",
          "missing.b",
          "```",
          "```console host",
          "$ nix profile install github:pleme-io/blue",
          "```"
        ]
      )
    )
    assert run_blocks(self_exe, getenv("TMPDIR", "/tmp"), good) == []
    bad = page_of(
      "docs/b.md",
      join_lines(
        [
          "```console",
          "$ blue eval 1",
          "2",
          "```",
          "```blue",
          "raise(:no, \"no\")",
          "```"
        ]
      )
    )
    found = run_blocks(self_exe, getenv("TMPDIR", "/tmp"), bad)
    assert length(found) == 2
    assert contains?(first(found), "docs/b.md: `blue eval 1` printed [\"1\"]")
    assert contains?(last(found), "blue block 1 failed")
  end
end

test "a code span that calls a known name links to it, and a package name links to its catalogue entry"
  links = reference_links(
    [["argv_get", "Environment and arguments"]],
    [
      [
        "settei",
        "0.1.0",
        [],
        "",
        [["serving?", "serving?", [], []]],
        0,
        nil,
        "x"
      ]
    ],
    "docs",
    "docs/REFERENCE.md",
    "bidamas/CATALOG.md"
  )
  assert linked_code("`argv_get(0, \"w\")`", links) ==
    "[`argv_get(0, \"w\")`](REFERENCE.md#environment-and-arguments)"
  assert linked_code("`settei`", links) ==
    "[`settei`](../bidamas/CATALOG.md#settei)"
  assert linked_code("`settei::serving?`", links) ==
    "[`settei::serving?`](../bidamas/CATALOG.md#settei)"
  assert linked_code("`unknown`", links) == "`unknown`"
end

test "the reference shows each definition's prose and its examples as code"
  r = reference_text(
    "Packages",
    [
      [
        "demo",
        "0.1.0",
        [],
        "demo: a sample.",
        [["inc", "inc(n)", ["inc: Adds one.", "", "    inc(1)"], []]],
        1,
        nil,
        "bidamas/demo"
      ]
    ]
  )
  assert contains?(r, "## demo")
  assert contains?(
    r,
    join_lines(
      ["### `demo::inc(n)`", "", "Adds one.", "", "```blue", "inc(1)", "```"]
    )
  )
end

@doc """
fact_pages: The pages of a sample project the fact tests render: an introduction that includes a section of an implementer's page.

    map(first, fact_pages) #=> ["docs/introduction.md", "docs/implementing.md"]
"""
def fact_pages()
  [
    [
      "docs/introduction.md",
      join_lines(
        [
          "---",
          "kind: explanation",
          "role: introduction",
          "---",
          "# demo",
          "",
          "## Gaps",
          "",
          "```hon",
          "include implementing.md#what-is-not-built",
          "```",
          "",
          "```console",
          "$ echo kept",
          "```"
        ]
      )
    ],
    [
      "docs/implementing.md",
      join_lines(
        [
          "---",
          "kind: reference",
          "---",
          "# Implementing",
          "",
          "## What is not built",
          "",
          "No TLS; see [HTTP2](HTTP2.md).",
          "",
          "```text",
          "## not a heading",
          "```",
          "",
          "### A detail",
          "",
          "kept too",
          "",
          "## Next",
          "",
          "left out"
        ]
      )
    ]
  ]
end

test "an include brings one section, links rewritten, up to the next heading of its level"
  project = project_of(fact_pages, {"name" => "demo"})
  text = included_text(project, "", "docs/implementing.md#what-is-not-built")
  assert contains?(text, "[HTTP2](docs/HTTP2.md)")
  assert contains?(text, "## not a heading")
  assert contains?(text, "kept too")
  assert not contains?(text, "left out")
end

test "the facts of a page render in place and every other block is kept"
  project = project_of(fact_pages, {"name" => "demo"})
  done = with_facts_of(project, {reference: nil, packages: nil})
  intro = page_with_role(done, "introduction")
  assert contains?(intro[:body], "No TLS; see [HTTP2](HTTP2.md).")
  assert not contains?(intro[:body], "```hon")
  assert contains?(intro[:body], "$ echo kept")
end

test "only a block marked hon names a fact"
  assert facts_in(join_lines(%w[```text hon ``` ```hon packages ```])) ==
    [["packages", []]]
end

test "each bad fact is refused alone, naming its page, and good ones pass"
  pages = concat_lists(
    fact_pages,
    [
      [
        "docs/bad.md",
        join_lines(
          [
            "---",
            "kind: howto",
            "---",
            "# Bad",
            "```hon",
            "tally",
            "```",
            "```hon",
            "include nowhere.md#x",
            "```",
            "```hon",
            "include implementing.md#no-such-heading",
            "```",
            "```hon",
            "commands",
            "```"
          ]
        )
      ]
    ]
  )
  found = fact_refusals(project_of(pages, {"name" => "demo"}))
  assert map(first, found) == %i[unknown_fact no_page no_section]
  assert every?((r) -> contains?(last(r), "docs/bad.md"), found)
end

test "an included section that includes another page is refused"
  pages = [
    [
      "docs/a.md",
      join_lines(
        [
          "---",
          "kind: howto",
          "---",
          "# A",
          "```hon",
          "include b.md#one",
          "```"
        ]
      )
    ],
    [
      "docs/b.md",
      join_lines(
        [
          "---",
          "kind: reference",
          "---",
          "# B",
          "## One",
          "```hon",
          "include a.md#a",
          "```"
        ]
      )
    ]
  ]
  project = project_of(pages, {"name" => "demo"})
  refused = with_facts_of(project, {reference: nil, packages: nil}) rescue
    :nested
  assert refused == :nested
end

test "a fact that reads the reference is refused when no blue renders"
  project = project_of(
    [
      [
        "docs/a.md",
        join_lines(["---", "kind: howto", "---", "```hon", "language", "```"])
      ]
    ],
    {"name" => "demo"}
  )
  assert (with_facts_of(project, {reference: nil, packages: nil}) rescue
    :no_blue) == :no_blue
end

test "the commands table types each command and keeps a pipe inside its cell"
  t = command_table(
    [
      {
        "name" => "",
        "usage" => "FILE [ARGS]...",
        "about" => "Run a script",
        "flags" => []
      },
      {
        "name" => "image build",
        "usage" => "[NAME]",
        "about" => "Build a|b. Then more",
        "flags" => []
      }
    ]
  )
  assert contains?(t, "| `blue FILE [ARGS]...` | Run a script. |")
  assert contains?(t, "| `blue image build [NAME]` | Build a\\|b. |")
end

test "the README folds the explanation and keeps every other kind in the open"
  r = readme_text(sample_project)
  assert contains?(r, "<details>")
  assert contains?(r, "### How-to guides")
end

test "a packages fact refuses when the rendering cannot see the packages, rather than count none"
  project = project_of(
    [
      [
        "docs/a.md",
        join_lines(["---", "kind: howto", "---", "```hon", "packages", "```"])
      ]
    ],
    {"name" => "demo", "packages" => ["bidamas"]}
  )
  sources = fact_sources(nil, "/nonexistent", project)
  assert sources[:packages] == :unseen
  assert (with_facts_of(project, sources) rescue :refused) == :refused
end
