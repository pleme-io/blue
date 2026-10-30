---
kind: explanation
summary: Markdown as a first-class blue value: one typed tree, one formatting, checked links, and renderings to Markdown, HTML, PDF and the terminal (design)
---

# MARKDOWN — Markdown is a first-class blue value

Status: DESIGN, 2026-10-30. Built: M0, M1 and M2 (§7): the typed facts
`hon` renders into a page, and the `bunsho` (文書) bidama, which parses
Markdown into the tree of §3 and renders it back. The rest is design.

## 1. Destination

Markdown is blue's primary visual artifact. People and agents read it first:
the README, `AGENTS.md`, the book, `llms.txt`, a pull request body, a report.
blue makes it a value like a list or a record:

- `.md` text parses into one typed tree, and the tree renders back to text in
  one canonical formatting, as `blue fmt` does for `.b`;
- a program builds, queries, transforms and checks the tree, never the text;
- every reader-facing format renders from the same tree: Markdown for GitHub,
  HTML for the site, PDF for print and hand-off, and styled text for the
  terminal;
- a broken link, a missing anchor or an unknown fact is a red gate that names
  the page and the link, and every other link still passes.

A fact is written once, and every format agrees on it, because every format
is a rendering of one tree.

## 2. Why a tree, measured

`hon` (2026-10-30) holds 96 definitions. About 20 re-derive structure that
Markdown text does not keep: `fence_line?`, `outside_fences`, `demoted`,
`page_title`, `without_title`, `lead_sentence`, `lead_and_sections`,
`rebased_target`, `rebased_links` (it splits text at `](`), `fenced_blocks`,
`heading_anchor`, `with_facts`, `heading_level` and `section_of`. Each one is a
small parser, and each one disagrees with the others at an edge: a
four-backtick fence, a heading inside a list, a `](` inside code. No gate
checked a link target before M2. With a tree, each of these is one node
operation, and a link is a node whose target a gate resolves.

## 3. The shape, adopted

The node kinds are the ones that CommonMark, GitHub Flavored Markdown and
mdast (unified, remark) agree on. blue invents no kind except `fact`.

| Kind | Fields | From |
|---|---|---|
| `root` | `children`, `front` (the front matter record) | mdast, front matter as YAML |
| `heading` | `depth` 1–6, `children`, `anchor` | CommonMark ATX and setext |
| `paragraph`, `blockquote`, `list_item` | `children` | CommonMark |
| `list` | `ordered`, `start`, `tight`, `children` | CommonMark |
| `code` | `lang`, `args` (the info string after the language), `text` | CommonMark fenced and indented |
| `html` | `text` | CommonMark HTML blocks and inline HTML |
| `table`, `table_row`, `table_cell` | `align`, `children` | GFM tables |
| `thematic_break` | — | CommonMark |
| `text`, `emphasis`, `strong`, `delete`, `inline_code`, `break` | `text` or `children` | CommonMark, GFM strikethrough |
| `link`, `image` | `target`, `title`, `children` or `alt` | CommonMark |
| `fact` | `name`, `args` | blue: a `hon` block (§5) |

A node is a record, `{kind: :heading, depth: 2, children: [...], at: [line,
column]}`. `at` is the position in the source, so a gate names the line.

## 4. The verbs

Each is a row in the verb graph before it is built (`blue verbs`), with one
contract in every space that has the verb.

| Verb | Contract | Tier |
|---|---|---|
| `bunsho::parse(text)` | `.md` text to a `root`; never raises: text it cannot read is a `text` or `html` node | built |
| `bunsho::render(tree)` | the canonical Markdown of a tree | built |
| `bunsho::section(tree, anchor)` | the nodes under one heading, up to the next of its depth or above; nil when absent | built |
| `bunsho::extract(tree, kinds)` | the nodes of one kind, or of several, in order: headings, links, code blocks, facts | built |
| `bunsho::walk(tree)` | every node, in document order | built |
| `bunsho::map_nodes(tree, f)` | the tree with `f` applied to every node, bottom up | built |
| `bunsho::rebase(tree, from, to)` | every relative link target rewritten to reach the same file from another directory | built |
| `to_html(tree)`, `to_typst(tree)`, `to_terminal(tree)` | the renderings of §6 | design |

One verb reads nodes by kind, not one verb per kind (the verb law,
`docs/VERB-ROADMAP.md`). The section verb is `section`, not the graph's
`get`: a bidama that defines `get` breaks its own `m[:k]`, because the
bracket lowers to a bare `get` and recurses. Not yet read as CommonMark
reads them: entity references, reference-style links, e-mail autolinks and
the delimiter-stack edges of emphasis. Each is stable under both laws.

Two laws hold on every page of `docs/` and on the CommonMark examples the
parser claims, each an okite law with a witness:

- `render(parse(render(t))) == render(t)`: the canonical form is a fixed point;
- `parse(render(parse(x)))` equals `parse(x)`, positions aside: rendering
  loses no structure.

## 5. Facts are nodes

M0 (§7) puts a fact in a page as a fenced code block whose info string is
`hon`. The block's first line names the fact: `commands`, or `include
implementing.md#what-is-not-built`. This page cannot show such a block inside
an example block, because `hon` reads fences line by line and a nested fence
ends its scan early. That is the defect of §2 again, and the tree removes it.

The block renders in place from a typed source: `commands` and `language`
from `blue reference`, `packages` from the catalogue, and `include
page.md#anchor` for one section of another page. With the tree, the block is a
`fact` node, the facts are ordinary blue functions that return nodes, and a new
fact is one definition, not a change to the renderer.

## 6. Renderings

| Format | How | Gate |
|---|---|---|
| Markdown | `render`, the one formatting | `-fresh` on each generated file; a `docs/` page that is not canonical is refused, naming `blue fmt --write` |
| HTML | `to_html`, written by blue (`theory/BLUE-FRONTEND.md`) | the D5 site of `docs/DOCUMENTATION.md` |
| PDF | `to_typst`, then `typst compile`, run by nix as a Bluefile `run` | `nix build .#book-pdf` builds the Blue Book as one PDF; the PDF is an artifact, never committed |
| terminal | `to_terminal`, coloured from irodori by ANSI slot | `blue doc` and a page viewer |

## 7. Build order and tier

| Step | Work | Gate | Tier |
|---|---|---|---|
| M0 | typed facts in a page: `commands`, `language`, `packages`, `include` | `checks.docs` refuses an unknown fact or a missing section by page; `bidama-test-hon` | built 2026-10-30 |
| M1 | the block tree: `parse` and `render` for every block kind of §3 | `checks.markdown-laws`: both laws on every page of `docs/`; `bidama-test-bunsho`; heni catches every mutation | built 2026-10-30 (`bunsho`) |
| M2 | inline nodes: links, code spans, emphasis, images; the link and anchor gate | `checks.markdown-laws`: every relative link and image under `docs/` (330 on 2026-10-30) reaches a file, and every `#anchor` a heading, each refused by page and line | built 2026-10-30 |
| M3 | `hon` on the tree: its text functions removed, facts as nodes | every `hon` test, unchanged renderings byte for byte | design |
| M4 | `blue fmt` formats `.md` | an md-fmt gate over `docs/` | design |
| M5 | `to_typst` and `typst` from nixpkgs | `nix build .#book-pdf` | design |
| M6 | `to_html`, the static site | D5 | design |
| M7 | `to_terminal` | `blue doc` shows a page | design |

## 8. Decisions

| Question | Chosen | Rejected, and why |
|---|---|---|
| The source format | Markdown, kept as the surface people write and read | **a new markup or blue-coded pages**: GitHub, editors and agents read Markdown natively; a page written as blue calls is hard to write prose in |
| The tree's kinds | CommonMark + GFM + mdast, adopted | **our own kinds**: a second vocabulary for a solved shape |
| The parser | blue, in a bidama | **pulldown-cmark or comrak behind a host seam**: Markdown is text in and records out, so blue can express it, and the house ladder puts blue first |
| PDF | Typst: one Rust binary in nixpkgs, hermetic, no browser | **pandoc and LaTeX**: a second toolchain and a large closure; **headless Chromium `printToPDF`** (the `hikyaku` seam that `malote` plans): a browser in the closure, and the output depends on its version |
| Where facts live | in the page, as `hon` blocks, then `fact` nodes | **a template language** around the page: a second syntax to learn and to parse |
