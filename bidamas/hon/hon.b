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
  [
    :after_first,
    :before_first,
    :drop_chars,
    :is_alnum,
    :pad_left,
    :repeated,
    :strip_prefix,
    :take_chars,
    :trim
  ]
)

use("mokuroku", [:catalog_of, :pkg_entries, :pkg_gloss, :pkg_name])

use(
  "retsu",
  [
    :concat_lists,
    :drop_while,
    :find_first,
    :first,
    :flat_map,
    :index_of,
    :is_empty,
    :last,
    :push,
    :rest,
    :take_while
  ]
)

use("shisutemu", [:status_of, :stderr_of, :stdout_of])

@doc """
page_kinds: The four Diátaxis kinds, in the order a book shows them.

    page_kinds #=> [:tutorial, :howto, :reference, :explanation]
"""
def page_kinds()
  [:tutorial, :howto, :reference, :explanation]
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
  declared = get(front_matter(text), "kind")
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
      declared = get(front_matter(last(p)), "kind")
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
      inside = nth(0, acc)
      lead = nth(1, acc)
      after = nth(2, acc)
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
  sections = if nth(2, state).nil?
    ""
  else
    join(nth(2, state), line_break)
  end
  [trim(join(nth(1, state), line_break)), trim(sections)]
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
    summary: get(fm, "summary") or lead_sentence(body),
    order: to_int(get(fm, "order") or "1000"),
    role: get(fm, "role"),
    runs: get(fm, "runs") == "true",
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
      "#{to_s(kind_rank(get(p, :kind)))}-#{pad_left(to_s(get(p, :order)), 8, "0")}-#{get(p, :path)}"
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
  intro = find_first((p) -> get(p, :role) == "introduction", records)
  {
    name: if intro.nil?
      get(manifest, "name")
    else
      get(intro, :title)
    end,
    summary: if intro.nil?
      ""
    else
      get(intro, :summary)
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
    get(json_read(read_file(lock)), "manifest")
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
  g = get(get(project, :manifest), "generated")
  if g.nil?
    []
  else
    map((e) -> get(last(e), "output"), map_entries(g))
  end
end

@doc """
page_with_role: The project's page whose front matter names `role`, or nil.

    page_with_role({pages: []}, "agents") #=> nil
"""
def page_with_role(project, role)
  find_first((p) -> get(p, :role) == role, get(project, :pages))
end

@doc """
listed_pages: The pages a book lists under `kind`: every page of that kind except the introduction and the book itself.

    listed_pages({pages: [{path: "a", kind: :howto, role: "book"}]}, :howto) #=> []
"""
def listed_pages(project, kind)
  filter(
    fn(p)
      get(p, :kind) == kind and
        not member?(get(p, :role), ["introduction", "book"])
    end,
    get(project, :pages)
  )
end

@doc """
rendered_path: Where a reader finds a page: the agents page is read as the AGENTS.md it renders, every other page at its own path.

    rendered_path({path: "docs/agents.md", role: "agents"}) #=> "AGENTS.md"
"""
def rendered_path(page)
  if get(page, :role) == "agents"
    "AGENTS.md"
  else
    get(page, :path)
  end
end

@doc """
page_link: A list item linking to a page from directory `to`, with its summary.

    page_link({path: "docs/a.md", title: "A", summary: "does a"}, "") #=> "- [A](docs/a.md): does a"
"""
def page_link(page, to)
  "- [#{get(page, :title)}](#{relative_path(to, rendered_path(page))}): #{get(page, :summary)}"
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
  rebased_links(get(page, :body), path_dirname(get(page, :path)), to)
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
    "# #{get(project, :name)}"
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
    "Read it in order as [#{get(book, :title)}](#{get(book, :path)}), or open one page:"
  end
  paragraphs(
    [
      rendered_notice(
        map(
          (p) -> get(p, :path),
          filter((p) -> p != nil, [intro, first(tutorials)])
        )
      ),
      lead,
      quick,
      last(parts),
      "## The book",
      where,
      book_map(project, "###", "")
    ]
  )
end

@doc """
build_section: How to build and test the project, read from its Bluefile.lock: the checks, the generated files and the commands.

    contains?(build_section({manifest: {}}), "nix flake check") #=> true
"""
def build_section(project)
  m = get(project, :manifest)
  checks = map_entries(get(m, "checks"))
  outputs = generated_outputs(project)
  catalog = get(m, "catalog")
  rows = concat_lists(
    [
      "| `nix flake check` | every check the Bluefile declares, and the gates every blue project gets |",
      "| `nix run .#regen` | rewrites every generated file in place |",
      "| `blue lock .` | rewrites `Bluefile.lock` after an edit to the `Bluefile` |"
    ],
    map(
      (e) -> "| `blue test #{get(last(e), "file")}` | `checks.#{first(e)}` |",
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
    "Read the tutorials and how-to guides in order in [#{get(book, :title)}](#{get(book, :path)})."
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
    ["# #{get(project, :name)}", ""]
  else
    lead_and_sections(page_body_at(page, ""))
  end
  paragraphs(
    [
      rendered_notice(
        if page.nil?
          ["Bluefile.lock"]
        else
          [get(page, :path), "Bluefile.lock"]
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
  catalog = get(get(project, :manifest), "catalog")
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
      [
        "# #{get(project, :name)}",
        "> #{get(project, :summary)}",
        book_line(project)
      ],
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
    (p) -> not member?(get(p, :path), generated),
    flat_map([:tutorial, :howto, :reference], (k) -> listed_pages(project, k))
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
      ["# #{get(project, :name)}", "> #{get(project, :summary)}"],
      map(
        fn(p)
          join_lines(
            [
              "---",
              "",
              "Source: `#{get(p, :path)}`",
              "",
              trim(page_body_at(p, ""))
            ]
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
  parts = doc_parts(first(entry), nth(2, entry))
  examples = last(parts)
  join_lines(
    concat_lists(
      [
        "### `#{pkg}::#{nth(1, entry)}`",
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
          p = nth(i, parts)
          if i % 2 == 0
            p
          else
            url = get(links, p) or get(links, called_name(p))
            before = nth(i - 1, parts)
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
  map((i) -> [i + 1, nth(i, pages)], range(0, length(pages)))
end

@doc """
chapter_heading: A chapter's heading text: its number and its title.

    chapter_heading([3, {title: "Run a test"}]) #=> "3. Run a test"
"""
def chapter_heading(chapter)
  "#{to_s(first(chapter))}. #{get(last(chapter), :title)}"
end

@doc """
book_contents: The book's table of contents: each part with its chapters linked to their anchors, and the reference and explanation pages linked from directory `to`.

    contains?(book_contents({pages: []}), "## Contents") #=> true
"""
def book_contents(project)
  all = chapters(project)
  part = fn(kind)
    mine = filter((c) -> get(last(c), :kind) == kind, all)
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
    [:reference, :explanation],
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
    mine = filter((c) -> get(last(c), :kind) == kind, all)
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
      "# The #{get(project, :name)} Book",
      if intro.nil?
        ""
      else
        get(intro, :summary)
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
        info = get(open, :info)
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
              code: join(get(open, :lines), line_break)
            }
          )
        ]
      elsif open != nil
        [assoc(open, :lines, push(get(open, :lines), line)), found]
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
      words = nth(0, acc)
      word = nth(1, acc)
      mark = nth(2, acc)
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
  if nth(1, state).nil?
    nth(0, state)
  else
    push(nth(0, state), nth(1, state))
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
  member?(get(page, :kind), [:tutorial, :howto]) or get(page, :runs)
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
        [path_in(at, nth(1, words)), fails]
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
  blocks = fenced_blocks(get(page, :body))
  state = reduce(
    fn(acc, i)
      here = first(acc)
      fails = last(acc)
      b = nth(i, blocks)
      name = block_arg(get(b, :args), "file")
      if name != nil
        write_block_file(path_join(path_join(root, here), name), get(b, :code))
        acc
      elsif get(b, :lang) == "blue"
        file = "block-#{to_s(i)}.b"
        write_block_file(path_join(path_join(root, here), file), get(b, :code))
        verb = if contains?(get(b, :code), "test \"")
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
      elsif get(b, :lang) == "console" and not member?("host", get(b, :args))
        r = run_console(
          blue,
          root,
          here,
          console_steps(get(b, :code)),
          member?("fails", get(b, :args))
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
  map((f) -> "#{get(page, :path)}: #{f}", last(state))
end

@doc """
builtin_topics: Each built-in name with the title of its topic, as [name, title], from the JSON `blue reference` prints.

    builtin_topics(json_read("{\"topics\": [{\"slug\": \"s\", \"title\": \"Strings\"}], \"names\": [{\"name\": \"trim\", \"topic\": \"s\"}]}")) #=> [["trim", "Strings"]]
"""
def builtin_topics(reference)
  titles = reduce(
    (acc, t) -> assoc(acc, get(t, "slug"), get(t, "title")),
    {},
    get(reference, "topics")
  )
  map(
    (n) -> [get(n, "name"), get(titles, get(n, "topic"))],
    get(reference, "names")
  )
end

@doc """
published_reference: Where the language reference is read: the project's own `docs/REFERENCE.md` when it has one, else blue's published copy.

    published_reference({pages: []}) #=> "https://github.com/pleme-io/blue/blob/main/docs/REFERENCE.md"
"""
def published_reference(project)
  own = find_first(
    (p) -> get(p, :path) == "docs/REFERENCE.md",
    get(project, :pages)
  )
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
  m = get(project, :manifest)
  builtins = if blue.nil?
    []
  else
    builtin_topics(json_read(stdout_of(exec_capture(blue, "reference"))))
  end
  roots = map((d) -> path_join(root, d), get(m, "packages") or [])
  records = catalog_of(filter(is_dir?, roots))
  reference_links(
    builtins,
    records,
    to,
    published_reference(project),
    get(m, "catalog") or "bidamas/CATALOG.md"
  )
end

@doc """
rendering: The text of one rendering of the project at `root`, by name: `:readme`, `:agents`, `:llms`, `:llms_full`, or `:book` for a book written in directory `to`.

    starts_with?(rendering(:llms, "/nonexistent", ""), "# ") #=> true
"""
def rendering(name, root, to)
  project = project_at(root)
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
          ["kind", "reference"],
          ["role", "book"],
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
  assert get(front_matter(page), "summary") == "why"
  assert page_body(page) == "# Why"
end

test "the front matter a renderer writes reads back as the same kind"
  page = concat(front_matter_text(:howto, "run one test"), "# Run")
  assert page_kind(page) == :howto
  assert get(front_matter(page), "summary") == "run one test"
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
  assert map((r) -> first(r), found) == [:no_kind, :unknown_kind]
  assert contains?(last(first(found)), "docs/b.md")
  assert contains?(last(last(found)), "kind `guide`")
end

test "the kinds are listed in the book's order"
  assert page_kinds == [:tutorial, :howto, :reference, :explanation]
end

test "a directory with pages is read sorted, with paths from the root"
  root = path_join(getenv("TMPDIR", "/tmp"), "hon-pages-#{to_s(now_ns)}")
  mkdir_p(path_join(root, "docs/howto"))
  write_file(path_join(root, "docs/b.md"), "# B")
  write_file(path_join(root, "docs/howto/a.md"), "# A")
  write_file(path_join(root, "docs/notes.txt"), "not a page")
  found = doc_pages(root)
  rm_rf(root)
  assert map((p) -> first(p), found) == ["docs/b.md", "docs/howto/a.md"]
end

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
  assert get(p, :name) == "demo"
  assert get(p, :summary) == "demo is a small language."
  assert map((x) -> get(x, :path), get(p, :pages)) ==
    [
      "docs/tutorial/install.md",
      "docs/howto/test.md",
      "docs/agents.md",
      "docs/DESIGN.md",
      "docs/introduction.md"
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
