<!-- Rendered by hon from docs/introduction.md, docs/tutorial/install.md. Edit the sources, then run `nix run .#regen`. -->

# blue

```text
████  blue          nord7 → nord8 → nord9 → nord10
────────────────────    teal   cyan   light  deep blue
a Ruby/Elixir surface on tatara-lisp and Rust
```

**blue** is the pleme-io language. You write it like Ruby or Elixir. It
parses to a [tatara-lisp](https://github.com/pleme-io/tatara-lisp) tree,
macros rewrite that tree, and a Rust runtime runs it, not the BEAM. Each
thing has one spelling, and the formatter writes it. Rigor is your choice:
declare nothing and a program is dynamic and fast; annotate one function and
that function is checked. Safety is not a choice: a program reaches the host
only through the capabilities it is given. The standard library is a set of
packages called bidamas, and one `Bluefile` says how a project is built,
tested, documented and shipped.

The philosophy is two axes.
**Form has no choices:** there is one short, distinct way to write each
thing, every larger form is built from smaller ones, and every tool and gate
enforces it. **Rigor has every choice:** a program is as strict as you write
it, where you write it, and pays for nothing else. Every blue word (bidama,
waku, mondou, the blueshift) maps to the concept you already know in
[the glossary](docs/GLOSSARY.md).

A file is a program, a library and its tests at once:

```blue file=words.b
@doc """
shout: The text in capitals, with an exclamation mark.

    shout("olá") #=> "OLÁ!"
"""
def shout(text: String) -> String
  "#{upcase(text)}!"
end

def main()
  write_stdout(unlines([join(map(shout, argv), " ")]))
end

test "shout raises its voice and keeps the text"
  assert shout("oi") == "OI!"
  assert shout("") == "!"
end
```

```console
$ blue words.b olá mundo
OLÁ! MUNDO!
$ blue test words.b
2 test(s): 2 passed, 0 failed
```

The example in the `@doc` is the second test: `blue test` runs it beside the
`test` block, so a documented example cannot drift from the code.

## Quickstart

You need [Nix](https://nixos.org) with flakes turned on. Install blue into
your profile:

```console host
$ nix profile install github:pleme-io/blue
```

To try blue without installing it, put `nix run github:pleme-io/blue --` in
front of each command below.

Ask blue for a value:

```console
$ blue eval '1 + 2'
3
```

Write a file called `hello.b`:

```blue file=hello.b
write_stdout(unlines(["Olá, mundo!"]))
```

Run it:

```console
$ blue hello.b
Olá, mundo!
```

That is a whole blue program. The next tutorial, [a first script](docs/tutorial/first-script.md),
gives it arguments.

## The blueshift

The blueshift is how far a program has moved from dynamic toward checked.
You move it one definition at a time. Here `add` has no annotation, so
nothing analyses it. `fact` is annotated, so the checker proves it:

```blue file=shift.b
def add(a, b)
  a + b
end

def fact(n: Int) -> Int
  if n < 2
    1
  else
    n * fact(n - 1)
  end
end
```

`blue check` prints what the check cost, so the claim is a measurement:

```console
$ blue check shift.b
typed declarations: 1
nodes analysed:     11
seams:              0
names resolved:     11
waived:             0
```

`blue shift` names the rung the file stands on and what holds it back:

```console
$ blue shift shift.b
██░░ annotated  (1/2 typed, 11 nodes analysed)
some declarations are typed; untyped ones are unchecked

  · untyped declaration      `add` has no annotation — annotate it to shift further
  → type annotation          `fact` is annotated, so it is checked
```

The language server closes the gap for you: on a loose definition it offers a
code action that writes the types its calls showed.

## Safety first

Every effect outside the program is a capability: `process`, `filesystem`,
`environment`, `clock`, `network` or `entropy`. `--allow` holds a run to the
ones you name, and the check stage refuses the program before it runs when it
writes a host name outside them:

```blue file=peek.b
def main()
  write_stdout(read_file("words.b"))
end
```

```console fails
$ blue --allow none peek.b
refused: `read_file` reaches the host (filesystem), which this run does not allow; pass --allow filesystem to grant it
```

A script states its capabilities in its shebang,
`#!/usr/bin/env -S blue --allow filesystem`. A project states them once in its
`Bluefile`: `allow` is the ceiling of the whole program, `reach` is the floor
each package needs, and `blue lock` refuses a package whose floor does not fit
under the ceiling. `virtualize` binds a capability to a pure provider, such as
a stepped clock, a seeded random source or an in-memory file tree, for the
whole program or only for the packages you name. An evaluation session
(`eval`, `repl`, `serve`) is pure unless you start it with `--allow`. Every
Rust guarantee, the blue gate that matches it and its off switch are in
[Safety first](docs/SAFETY.md).

## What ships

| Battery | What you get | Read |
|---|---|---|
| The language | macros as term rewriting, with bounded expansion; errors raised and rescued by kind, or returned as refusals; OTP-style processes with private environments, copy-on-send and supervised restarts | [the reference](docs/REFERENCE.md), [the agent guide](AGENTS.md) |
| Tests | `test` blocks beside the code, a doctest in every `@doc`, coverage, mutation testing, and a conformance suite every evaluator must pass | [Testing](docs/TESTING.md), [the spec](spec/README.md) |
| Tools | one formatter; a check stage whose rules carry their own fixes; a language server with hover, completion, definitions, references, rename, signature help, semantic tokens, inlay hints and code actions; a REPL; `watch`, `profile`, `trace` and code queries | [Diagnostics](docs/DIAGNOSTICS.md) |
| Packages | bidamas, each a namespace; a `Bluefile` that is itself a blue program, pinned by its lock; registries rendered as publish workflows | [Authoring](bidamas/AUTHORING.md), [Registry](docs/REGISTRY.md) |
| Shipping | a Bluefile `app`, `image` (built by nix, distroless by default), `workload` and `service` (Kubernetes objects and a Helm chart, committed and gated fresh for GitOps), and `blue diff`, read-only | [the build stack](docs/BUILD-STACK.md) |
| Services | configuration (`settei`), entries each off or refused alone (`kousei`), postures (`shisei`), request defence (`bougyo`), retries (`saishikou`); HTTP, NATS, PostgreSQL, Valkey and JetStream; HTTP/2 framing and HPACK in pure blue | [Service architecture](docs/SERVICE-ARCHITECTURE.md), [HTTP/2](docs/HTTP2.md) |
| Documentation | this README, `AGENTS.md`, `llms.txt` and the book, rendered from one source per fact, every example run | [Documentation](docs/DOCUMENTATION.md), [Markdown](docs/MARKDOWN.md) |
| Editors | a tree-sitter grammar generated from blue's own grammar spec | [tree-sitter](docs/NATURALIZE-TREESITTER.md) |
| WebAssembly | the whole pipeline compiled to `wasm32-unknown-unknown` with no host imports at all | [`blue-lang-wasm`](crates/blue-lang-wasm) |

## Commands

Every command `blue` takes, read from its own argument parser when this file
was rendered. `blue help COMMAND` shows each one's flags.

| Command | What it does |
|---|---|
| `blue FILE [ARGS]...` | Run a program as a script: quiet, and every argument after the file reaches `argv`. |
| `blue run FILE [ARGS]...` | Parse, type-check, erase, and execute a program. |
| `blue fmt FILE...` | Format a program. |
| `blue ast FILE` | Print the tatara-lisp form, annotations intact. |
| `blue erase FILE` | Print the tatara-lisp form after type erasure — what actually runs. |
| `blue check [FILE]` | Check a program against every rule in the registry — unbound names, unused bindings, types, waivers — and report the typing analysis. |
| `blue query QUERY [PATHS]...` | Every definition under PATH (files, or directories of `.b` files; `.` when none) that satisfies QUERY, one line per hit: `file:line:col: definition  name = value…`. |
| `blue migrate FILES...` | Make every reference each FILE makes to another bidama's definition explicit (`use("retsu", [:first])`, and the bidama's `needs`), keeping a file only when its resolved tree is proven unchanged. |
| `blue doc [NAME]` | What NAME is: its signature, doc line, namespace, tier and an example, for a builtin, `pkg::name`, or a bare name across the builtins and every bidama on BLUE_PATH; a bidama's name lists the package. |
| `blue verbs ARGS...` | The verb graph (`bidamas/mokuroku/graph`): `import` region or merged TSVs into its row files, `export` them back to TSV (the only writer of TSV), `check` its gates against the recorded baseline, `findings` of a TSV directory. |
| `blue explain-name NAME AT` | How a bare NAME resolves at FILE:LINE: every tier of the resolution order, what each holds, and which wins. |
| `blue census [ROOT]` | Count, over every `.b` file under ROOT, each finding of every rule still being ratcheted in, and fail unless each count equals its registry row's `ratchet`. |
| `blue explain [CODE]` | Explain a diagnostic code (`blue explain B0001`), or list them all. |
| `blue test FILE` | Check the file (as `blue check` does), then run its `test` blocks. |
| `blue profile FILE [ARGS]...` | Run a program and report every function it called: calls, inclusive and exclusive time, and what it allocated, most exclusive time first. |
| `blue trace DEF FILE [ARGS]...` | Run a program and print each call of DEF with its arguments, and each exit with its value, to stderr. |
| `blue deps FILE` | Resolve a Bluefile's dependencies. |
| `blue posture FILE` | Report the posture a Bluefile's declared floor requires. |
| `blue bluefile FILES...` | Print a Bluefile's evaluated manifest, or confirm its lock is fresh. |
| `blue lock [DIRS]...` | Evaluate each directory's Bluefile, pin every `source(...)` with `nix flake prefetch`, and write `Bluefile.lock` beside it. |
| `blue bundle FILE` | Seal FILE into an appliance payload: the program compiled (every `use` resolved, checked, erased) with the capability record its project's fresh `Bluefile.lock` verified, closed with its BLAKE3 digest. |
| `blue lsp` | Run the language server, speaking LSP over stdin/stdout. |
| `blue debug` | Debug a recorded run, speaking the Debug Adapter Protocol over stdin/stdout. |
| `blue serve` | Serve one evaluation session as JSON lines on stdin/stdout: the door an editor drives. |
| `blue repl` | An evaluation session at the terminal. |
| `blue eval TARGET` | Evaluate EXPR, or the top-level form at FILE:LINE:COL in that file's context, and print its value. |
| `blue banner` | Print blue's wordmark. |
| `blue shift FILE` | Report the blueshift: how far this program is shifted, and what is shifting it. |
| `blue morph` | The morphology: what each posture grants, what it forfeits, which pairs are genuinely exclusive, and which language each shape corresponds to. |
| `blue reference` | Print the language reference as JSON: operators, keywords, surface forms, Bluefile words, every bound name and every command, each read from the table the implementation runs on. |
| `blue replay TRACE` | Run a crashed process again from the trace its crash wrote, and say whether it crashed the same way. |
| `blue crash dump CRASH` | What a crash violated and where: its class, the host name and capability a breach demanded, the breaching call's file, line and column, the hold, the exit and the mailbox. |
| `blue crash bisect CRASH` | The fewest messages the process took that still replay to the same crash, found by delta debugging against deterministic replay; the reduced trace is written beside the original under its own hash. |
| `blue crash immunize CRASH` | The crash's regression lock: a test that spawns the target, sends it the fewest messages that crashed it and asserts it took them, red until the target is fixed. |
| `blue arika like [FILE[:LINE]]` | The words a draft already is: each definition of FILE (or the one at FILE:LINE) matched to a blue word by def hash (T0), written shape (T1) and shape through a wrapper (T2), with the word's id and import line. |
| `blue arika word NAME` | Find a blue word by NAME: its canonical spelling, an old spelling's new home, and catalogue glosses that mention NAME (T5). |
| `blue arika emit [ROOT]` | Write the header SNAPSHOT.json for the bidamas under ROOT (each package's RFC 9162 unit_root and row count, and the snapshot_root over them) and, with --facts, the facts: every definition the engine sees as one JSON line (readable id, def_hash, shape hashes, gloss, file, line, legacy names). |
| `blue arika find TEXT` | Blue words whose name, package or doc gloss match TEXT, ranked by BM25 (the junni words), from the facts. |
| `blue arika get WORD` | Every fact of one word, by pkg::name or readable id. |
| `blue arika uses WORD` | The definitions that call a word, by pkg::name or readable id. |
| `blue arika groups` | Functions of MIN nodes or more that share one computed shape across words (T2 over the whole tree). |
| `blue arika changed PACKAGE` | How PACKAGE's words moved since an older facts file: added, removed, and code or doc moved. |
| `blue arika ask QUESTION` | Answer a named question over blue's knowledge graph (definitions, tests, docs and rules as khipu quads, asked through DuckDB): untested-CAPABILITY is every definition that reaches the capability and that no test or doc example names. |
| `blue arika golden FILE` | Ask every golden question of FILE (one `intent<TAB>word` per line, # comments) through find and name each whose word is no longer the top hit (G5). |
| `blue arika quads OUT` | Write blue's definitions, tests, docs and rules as N-Quads to OUT. |
| `blue arika tools` | Print the MCP tool list, rendered from the blue schema TOOLS in arika.b. |
| `blue arika mcp REQUEST` | Answer one MCP JSON-RPC request (REQUEST is the JSON text) from the facts, as the service would; a notification prints nothing. |
| `blue arika serve [ADDR]` | Serve the blue_word_* tools as an MCP server over Streamable HTTP (POST JSON-RPC to any path; /healthz answers ok). |
| `blue receipt verify FILE` | Recompute a receipt's name from its bytes and check its form; any edit fails. |
| `blue config [TIER]` | Show the bounds `blue` is running with, at any tier. |
| `blue new NAME` | Start a program (a project with its own bidama), a `--bidama`, a `--script`, or a `--kernel` program, each passing `blue test` as written. |
| `blue watch [CMD] PATH... [-- ARGS]...` | Rerun `check` (the default), `test` or `run` over each PATH whenever a watched file changes: `blue watch test lib.b`. |
| `blue image build [NAME] [-- NIX_ARGS]...` | Build an `image(...)` through nix and report the tarball, its size and its layers. |
| `blue workload render [NAME]` | Print a workload's rendered objects, or with `--write` rewrite every workload's committed `output` file. |
| `blue diff [NAME]` | Compare the committed workload files with a cluster, read-only: exit 0 when they agree, 1 when they differ, 2 when the comparison failed. |
| `blue registry render [BACKEND]` | Print one backend's workflow, or with --write rewrite every standing backend's committed output. |
| `blue registry status` | The sui state of every pin: warm on the origin SUI_CACHE_URL names, cold, or absent; never fails. |

## The language in numbers

Counted from the tables the implementation runs on, when this file was
rendered:

| | |
|---|---|
| Built-in names | 396: 369 functions, 14 special forms, 13 macros |
| Surface forms | 36, with 13 operators and 26 reserved words |
| Check rules | 79: 42 fix themselves, 8 suggest a fix |
| Bluefile words | 28 |
| Commands | 57 |

## The standard library

<details>
<summary>Every bidama, with the purpose its <code>@moduledoc</code> states</summary>

69 packages, 5949 definitions, 2014 tests.

- [angou](bidamas/CATALOG.md#angou) (暗号) — number theory and the classical ciphers built on it.
- [baito](bidamas/CATALOG.md#baito) (バイト) — bytes as data: integers at a declared width and order, and record layouts that say where each field sits.
- [bunsho](bidamas/CATALOG.md#bunsho) (文書) — Markdown as a first-class value: `.md` text parsed into one typed tree whose node kinds are the ones CommonMark, GitHub Flavored Markdown and mdast agree on, the tree rendered back in one canonical formatting, and the tree read by node, by kind and by section.
- [burauza](bidamas/CATALOG.md#burauza) (ブラウザ) — the browser: what a blue page needs from the browser, generated.
- [chokkan](bidamas/CATALOG.md#chokkan) (直感) — System One judgment: typed questions in, calibrated answers out.
- [chozou](bidamas/CATALOG.md#chozou) (貯蔵, storage) — what a service keeps and reads back.
- [deeta](bidamas/CATALOG.md#deeta) (データ) — JSON data, read safely.
- [eigyou](bidamas/CATALOG.md#eigyou) (営業, open for business) — what a running service answers, guards and reports.
- [fairu](bidamas/CATALOG.md#fairu) (ファイル) — files: paths and the files they name.
- [fuuin](bidamas/CATALOG.md#fuuin) (封印) — k-of-n threshold signing: a group whose key no one share holds, signed by any k of its n shares in two rounds, RFC 9591 FROST over Ed25519.
- [gamen](bidamas/CATALOG.md#gamen) (画面) — screen: what a program shows, as values: colors and themes, UI trees rendered to HTML, and styled text, tables and trees on the terminal.
- [gitto](bidamas/CATALOG.md#gitto) (ギット) — git, as verbs: a repository read as commits, refs, branches and files, and written by commit, fetch, merge, push and clone.
- [gurafu](bidamas/CATALOG.md#gurafu) (グラフ) — directed graphs as values: build them, ask them, order them.
- [hadome](bidamas/CATALOG.md#hadome) (歯止め) — a baseline ratchet: recorded debt may shrink or hold, never grow.
- [happa](bidamas/CATALOG.md#happa) (葉っぱ) — a template's leaves: their declaration, split, graph, change, schedule and verdicts, as pure decisions.
- [heni](bidamas/CATALOG.md#heni) (変異) — mutation testing for a blue package: each mutation changes one literal in a fresh copy of the package, runs its tests, and must make them fail.
- [hikisuu](bidamas/CATALOG.md#hikisuu) (引数) — command-line arguments: one declared spec is parsed into a record, rendered as help, and answered as shell completion.
- [hizuke](bidamas/CATALOG.md#hizuke) (日付) — the proleptic Gregorian calendar, as arithmetic.
- [hon](bidamas/CATALOG.md#hon) (本) — a project's book: its pages, each of one Diátaxis kind, rendered into the files a reader or an agent opens.
- [ibuki](bidamas/CATALOG.md#ibuki) (息吹) — the plane an app docks into, as pure decisions: the five structural classes and a docking check over the reach `blue lock` measured, the Flash channel's token bucket, the Tide channel's LEDBAT controller, and a Strand, a last-writer-wins map whose every transition is a hash-linked record of its input and output roots.
- [isshou](bidamas/CATALOG.md#isshou) (一生, a lifetime) — what a thing goes through, recorded and read back.
- [jisho](bidamas/CATALOG.md#jisho) (辞書) — dictionaries: maps as values, read and changed by key, each change a new map.
- [junjo](bidamas/CATALOG.md#junjo) (順序) — ordering: sorting, searching, selection.
- [junni](bidamas/CATALOG.md#junni) — the pure words of blue's full-text index (the subject of the `sakuin` verb space, docs/verbs): text analyzed into tokens, documents inverted into postings, and a question's terms ranked by BM25 over them.
- [kaaneru](bidamas/CATALOG.md#kaaneru) (カーネル) — the Linux kernel, spoken from blue: maps, programs, links and ring buffers over `bpf(2)`, with every struct a `baito` layout and no C library in the path.
- [kakehashi](bidamas/CATALOG.md#kakehashi) (架け橋, a bridge) — blue speaks Nix, Nix runs blue, and a rebuild does only the work that changed.
- [kansuu](bidamas/CATALOG.md#kansuu) (関数) — functions about functions.
- [kazu](bidamas/CATALOG.md#kazu) (数) — numbers.
- [keiyu](bidamas/CATALOG.md#keiyu) (経由) — by way of: run one command with a proxy set for it alone.
- [khipu](bidamas/CATALOG.md#khipu) — blue's knowledge graph (docs/KHIPU.md): RDF terms as a closed sum, quads, and N-Triples and N-Quads read and written.
- [kiwari](bidamas/CATALOG.md#kiwari) (木割): one grammar spec, every syntax artifact emitted from it.
- [kodou](bidamas/CATALOG.md#kodou) (鼓動) — the dual-pulse wire: a Flash channel paced by ibuki's token bucket and a Tide channel paced by ibuki's LEDBAT controller from the one-way delay each acknowledgement measures, over one UDP socket the host frames (0x02 Flash, 0x01 Tide); and the gossip of crash proofs on it: an alert on Flash, the artifact on Tide when a peer asks for it, verified by its content hash and kept in kensa's `kensa-immunity.v1` file.
- [koubou](bidamas/CATALOG.md#koubou) (工房, workshop) — shapes made, measured and cut.
- [kousei](bidamas/CATALOG.md#kousei) (構成) — a system composed entry by entry: each entry checked, configured off, tuned or refused alone, then judged into what stands.
- [koutei](bidamas/CATALOG.md#koutei) (工程) — one step of a pipeline, as GitHub Actions runs it.
- [kueri](bidamas/CATALOG.md#kueri) (クエリ) — queries: analysis is authored in blue, and SQL is only the rendered bridge to DuckDB.
- [kurasuta](bidamas/CATALOG.md#kurasuta) (クラスタ, a cluster): Kubernetes, spoken from blue.
- [kyohi](bidamas/CATALOG.md#kyohi) (拒否) — refusals, as data.
- [maakuappu](bidamas/CATALOG.md#maakuappu) (マークアップ) — XML as data: a document parsed by the runtime's xml_parse (quick-xml) into element maps {name, attributes, children, text}, the queries a reader of a scanner export asks of it (children and descendants by name, attributes, text, a path of element names), and the element rendered back with every value escaped.
- [mitoshi](bidamas/CATALOG.md#mitoshi) (見通し, a clear view ahead) — what a running program shows of itself.
- [moji](bidamas/CATALOG.md#moji) (文字) — strings.
- [mokuroku](bidamas/CATALOG.md#mokuroku) (目録): the catalogue of what every bidama on a BLUE_PATH provides.
- [okite](bidamas/CATALOG.md#okite) (掟) — blue's decisions, each enforced by laws written in blue.
- [ongaku](bidamas/CATALOG.md#ongaku) (音楽) — twelve-tone music theory, as arithmetic on semitones.
- [ran](bidamas/CATALOG.md#ran) (乱) — deterministic pseudo-randomness.
- [retsu](bidamas/CATALOG.md#retsu) (列) — lists, made TOTAL.
- [ronri](bidamas/CATALOG.md#ronri) (論理) — predicates, and the algebra over them.
- [sabi](bidamas/CATALOG.md#sabi) (錆): Rust source from blue data.
- [saishikou](bidamas/CATALOG.md#saishikou) (再試行) — retrying a step that can fail for a moment.
- [seikika](bidamas/CATALOG.md#seikika) (正規化) — canonicalization: one byte form for every blue value, and the root that names it.
- [seimei](bidamas/CATALOG.md#seimei) (生命) — cellular automata: elementary rules, and Life.
- [settei](bidamas/CATALOG.md#settei) (設定) — configuration, blue's shikumi: a record of defaults grouped by concern, resolved by read(app, defaults) from the defaults, then ~/.config/<app>/<app>.yaml (or <APP>_CONFIG), then <APP>_<GROUP>__<KEY> in the environment, each value typed by its default and a wrong type refused.
- [shinchoku](bidamas/CATALOG.md#shinchoku) (進捗) — progress: operational probes that judge by progress over a window, never by one reading.
- [shinsatsu](bidamas/CATALOG.md#shinsatsu) (診察) — the credential doctor: a provider, the failure classes its credential helper can show, and for each class a diagnosis, the remediation steps and a verify step.
- [shinsuu](bidamas/CATALOG.md#shinsuu) (進数) — base conversion and checksums.
- [shisutemu](bidamas/CATALOG.md#shisutemu) (システム) — the system.
- [shomei](bidamas/CATALOG.md#shomei) (署名) — signatures and hash chains: Ed25519 and BLAKE3, for real.
- [shuugou](bidamas/CATALOG.md#shuugou) (集合) — sets, over plain lists.
- [shuusei](bidamas/CATALOG.md#shuusei) (修正) — amending declared data: put a value at a path, delete it, merge into it, upsert a list element, and amend a keyed set of objects by judged patch entries.
- [suugaku](bidamas/CATALOG.md#suugaku) (数学, mathematics) — numbers worked over as a discipline.
- [tesuto](bidamas/CATALOG.md#tesuto) (テスト) — testing: errors and snapshots as assertions, and the policy that holds every definition to a test beside it.
- [todokede](bidamas/CATALOG.md#todokede) (届出, filings) — what a person or a company declares as entries.
- [toride](bidamas/CATALOG.md#toride) (砦) — a fort at the border: split-horizon DNS for a machine that roams between sites.
- [toriyose](bidamas/CATALOG.md#toriyose) (取り寄せ, fetching on order) — what a frontend asks for and keeps.
- [touroku](bidamas/CATALOG.md#touroku) (登録) — registry: a project published to and resolved from registry backends, each a rendering of the Bluefile, never its truth.
- [ugoki](bidamas/CATALOG.md#ugoki) (動き) — motion: how a value moves over time.
- [ukai](bidamas/CATALOG.md#ukai) (迂回) — a detour: keep an overlay VPN reaching its control plane and relays while a full-tunnel corporate VPN owns the default route.
- [utsushi](bidamas/CATALOG.md#utsushi) (写し, a transcription) — a part of a repository's history, shown as a history of its own: a lens picks the part, and each commit is written again over the part's tree, with its author, committer and message unchanged, so the same lens over the same commit gives the same commit id on every machine (docs/UTSUSHI.md).
- [zenbu](bidamas/CATALOG.md#zenbu) (全部) — the whole distribution, as ONE dependency.

</details>

## What is not built

This table lists what blue does not have yet. It is the table in
[Implementing blue](docs/implementing.md#what-is-not-built), rendered here.

This table lists the gaps of the language and its runtime. Do not cite a ❌ row as a feature. Do not build against a ❌ row without saying so.

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| A per-process GC heap | ❌ not built | Processes have private environments, and messages are deep-copied. Reclamation is `Arc` refcounting (`crates/blue-lang-proc/src/lib.rs`), so no process has its own collection pause. |
| A registry client | ✅ built | Resolution works over a git directory (`crates/blue-lang-pkg/src/git_registry.rs`). `blue lock` pins a source with `nix flake prefetch` (`crates/blue-lang-cli/src/prefetch.rs`). The nix build fetches each `source(name, url, dir)` over its pin (`nix/project.nix`, `checks.source-fixture`). The CLI adds a pinned source to the load path (test `a_locked_source_on_this_machine_joins_the_project_after_its_packages`). |
| Self-hosting on the implementation axis | ❌ not built | The parser, checker and runtime are Rust. `spec/rows/*.b` is the specification axis only. |
| Comments inside a form | ✅ built | The formatter places each comment by its span. Tests: `comments_inside_a_body_are_placed`, `comments_inside_a_call_and_a_list_are_placed` (`crates/blue-lang-fmt/src/lib.rs`). |
| Entropy | ✅ built | `random_bytes(n)` reads the kernel's non-blocking device under `Capability::Entropy` (`crates/blue-lang-runtime/src/entropy.rs`, test `a_draw_has_the_requested_length_of_byte_integers`). |
| Encryption | ❌ not built | The `crypto` layer hashes, signs and verifies (`crates/blue-lang-runtime/src/crypto.rs`). A keypair comes from a seed the caller supplies. The ciphers in `angou` are classical and insecure by design. |
| TLS | ❌ not built | `net` speaks NATS and HTTP over plain TCP. An `https://` URL and a NATS server that requires TLS are refused by name (`crates/blue-lang-runtime/src/net/http.rs`, `net/nats.rs`). The plan is HTTP2.md P4: rustls with ALPN `h2`. |
| Import emission into a wasm module | ❌ not built | `blue_lang_waku::imports_of` derives the import table from a frame (`crates/blue-lang-waku/src/imports.rs`). Nothing writes that table into a `.wasm`, and no engine border uses it. |
| Editor answers inside a broken buffer | ❌ not built | The parser does no error recovery. The language server answers from the newest revision that parsed (`crates/blue-lang-lsp/src/analysis.rs`). The plan is [CST-PLAN.md](docs/CST-PLAN.md). |
| Project rules in the editor or as wasm | ❌ not built | `blue check` runs project rules in-process under the rule frame (`crates/blue-lang-runtime/src/project_rules.rs`). The language server does not run them. The ABI fits a wasm module, but nothing builds one. |
| A move the send ring cannot carry | ❌ not built | A moved plain process carries its tape, mailbox journal and host-call count (`blue-image` version 5). A moved server carries its journal, count and state root (version 6). An account past the tape bound or the send ring stays behind. That process's journal, count and receipt root start again at the new node (`crates/blue-lang-proc/tests/nomad.rs`, `a_plain_process_whose_tape_the_send_ring_cannot_hold_still_moves_and_its_trace_says_the_tape_stayed`). |
| A link across nodes | ❌ not built | `evict` breaks a link and tells a partner that traps exits. It refuses a partner that does not (`evict_breaks_a_link_with_evicted_for_every_partner_that_traps_exits_and_names_one_that_does_not`). |
| An authenticated image | ❌ not built | An image's BLAKE3 name proves that it arrived whole. It does not prove who sent it. The image runs under the frame of the node that accepts it, never more (`crates/blue-lang-proc/src/image.rs`). |
| `case` and `when` pattern matching | ✅ built | A `when` destructures a union arm, a list and a map. B0081 refuses a `case` that misses an arm (`spec/rows/patterns.b`, `spec/rows/unions.b`). |
| Range syntax `a..b` | ❌ not built | `range(a, b)` and `range(a, b, step)` exist (`spec/rows/lists.b`). The parser refuses `1..3`. The plan is OPERATORS.md O1. |

## Theming

Colours come from [irodori](https://github.com/pleme-io/irodori), the fleet's
Nord palette. blue carries no hex of its own. `nord10` (`#5E81AC`, deep frost
blue) is its identity, and `nord8` frost cyan stays the fleet's shared
interaction colour: identity and interaction are different roles. The mark is
a blueshift too: four solid cells walk Nord's Frost band toward blue. It names
each colour by ANSI slot, never by hex, so it renders in your Nord and follows
you when you retheme.

## Building blue

```console host
$ nix build .#blue
$ nix flake check
$ cargo test --workspace
```

`nix build` is hermetic. `nix flake check` runs every gate the root
`Bluefile` declares. This README is rendered by `hon` from
[`docs/introduction.md`](docs/introduction.md), the first tutorial, the
implementation's own tables and the catalogue; edit those, then run
`nix run .#regen`. Changing blue itself starts at [AGENTS.md](AGENTS.md).

MIT.

## The book

Read it in order as [The blue Book](docs/BOOK.md), or open one page:

### Tutorials

- [Install blue](docs/tutorial/install.md): install blue, evaluate one expression and run a first file, in about a minute
- [A first script](docs/tutorial/first-script.md): write a script that reads its arguments, and let blue start one for you
- [A first program](docs/tutorial/first-program.md): start a program with blue new, change its code, and test it
- [A first bidama](docs/tutorial/first-bidama.md): write a documented bidama with doctests, read its docs with blue doc, and use it from a program
- [A first service](docs/tutorial/first-service.md): declare a service in a Bluefile, write its handler and tests, and see what blue renders from it
- [A first kernel program](docs/tutorial/first-kernel-program.md): start a kernel program with blue new --kernel, test it with no kernel, make it drop ICMP, and load it on Linux

### How-to guides

- [Write a test and a doctest](docs/howto/test-and-doctest.md): write a test block and a doctest, read a failure, and run one test by name
- [Climb the blueshift](docs/howto/climb-the-blueshift.md): move a file from dynamic to checked one annotation at a time, reading blue shift at each step
- [Declare what a program may touch](docs/howto/declare-access.md): hold a program to the host capabilities it needs with --allow, in a run or in a script's shebang
- [Write an action](docs/howto/write-an-action.md): write a GitHub Actions step in blue with koutei, and run it locally before CI does
- [Publish a bidama](docs/howto/publish-a-bidama.md): make a bidama reachable from other projects, and declare the registries that publish it
- [Run a pure worker](docs/howto/pure-worker.md): write a pure data transformation, run it under --allow none, and see the check stage refuse a variant that reaches the host
- [Supervise processes](docs/howto/supervise-processes.md): start worker processes under a supervisor, crash one, and see its restart strategy bring it back
- [Virtualize a capability](docs/howto/virtualize-a-capability.md): give a program a stepped clock with the Bluefile word virtualize, so now_ms is the same at every run, and scope it to one package with for:
- [Test a refusal](docs/howto/test-a-refusal.md): test that code refuses correctly, for an error raised by kind, a kyohi refusal returned as data, and a run held by --allow that breaches with exit 77
- [Pick a kernel hook](docs/howto/pick-a-kernel-hook.md): choose the kernel hook for a task, compile for its program kind, and attach with one word
- [Read a kernel field](docs/howto/read-a-kernel-field.md): read a field of a kernel struct at the offset the running kernel states, and test the read on the pure machine
- [Debug a kernel refusal](docs/howto/debug-a-kernel-refusal.md): find which layer refused a kernel program, the compiler, the machine or the verifier, and read why
- [Ship a node agent](docs/howto/ship-a-node-agent.md): declare a service that reaches the kernel, see the DaemonSet and exact capabilities blue renders, and test it with no cluster

### Reference

- [Canonical forms](docs/CANONICAL-FORMS.md): every place the surface accepts two spellings, the one blue writes, and the rule that names it
- [Commands](docs/COMMANDS.md): every blue verb with its flags, one row each; the agents page keeps one line per verb and links here
- [Diagnostics](docs/DIAGNOSTICS.md): what the check stage reports, every rule code, and the machine-readable shape of a diagnostic
- [blue examples](docs/EXAMPLES.md): one tested program per common task, ready to paste as examples
- [Glossary: blue's terms and the concepts they name](docs/GLOSSARY.md): every blue term mapped to the compiler, language or distributed-systems concept it names, in both directions, and how the parts meet in a compile, a test run and a deploy
- [blue language reference](docs/REFERENCE.md): syntax, operators, reserved words, every built-in name and the Bluefile words
- [blue roadmap](docs/ROADMAP.md): the one blue roadmap, one row per track with its state and the evidence for it, and every conflict ruled once
- [Safety first: blue's posture, row by row](docs/SAFETY.md): the safety-first posture, one row per Rust guarantee: blue today, the gate, its tier and its off switch
- [blue — the agent guide](AGENTS.md): rules for people and agents who write blue programs or change blue itself, with the build commands from the Bluefile
- [Implementing blue — the detail behind the agent guide](docs/implementing.md): the implementer detail behind the agent guide's "Changing blue itself": the check registry, crate map, hard-won rules, CI gates, dependencies and what is not built

### Explanation

<details>
<summary>52 pages on why blue is shaped as it is</summary>

- [ABSENCE — no undeclared nil](docs/ABSENCE.md): no undeclared nil: how blue makes absence a declared, checked state
- [API-EVOLUTION — the API is a versioned rendering of the one model](docs/API-EVOLUTION.md): the API as a versioned rendering of one model (design)
- [arika (在り処): the design of record](docs/ARIKA.md): arika, blue's word search, Phases 1 and 2 built for blue's own tree and the rest DESIGN: the recon, phases, gates with red runs, risks and every surface that names it
- [Native async: the design of record](docs/ASYNC.md): Native async in blue, DESIGN: one ontology of every async concept as a blue word over parked processes, the mutually exclusive architectures as blueshift positions with defaults, the integration with every system blue already has, and one test matrix that runs every position against the same oracle
- [BIDAMA-COHESION — one word per job, foundations below, a complete vocabulary](docs/BIDAMA-COHESION.md): one word per job, foundations below, a complete vocabulary across the bidamas (plan)
- [BUILD-ASSURANCE — what a blue build proves, how fast, and from which cache](docs/BUILD-ASSURANCE.md): what a blue build proves, how fast, and from which cache (design)
- [BUILD-STACK — the default platform for a blue service, from Bluefile to a running node](docs/BUILD-STACK.md): the default platform for a blue service, from Bluefile to a running node (design)
- [`Cargo.gen.lock` is committed, and that is a trade](docs/CARGO-GEN-LOCK.md): why Cargo.gen.lock is committed, and what that trade costs
- [CLI-TUI — one way to build a command line and a terminal interface in blue](docs/CLI-TUI.md): one way to build a command line and a terminal interface in blue (design, layer 1 built)
- [Competing languages — what blue takes, and what it refuses](docs/COMPETING-LANGUAGES.md): what blue takes from competing languages on packaging and the standard library, and what it refuses
- [Compile time: Rust's static guarantees and Lua's runtime, in blue](docs/COMPILE-TIME.md): Rust's static guarantees and Lua's runtime, brought into blue
- [Compounding: every evolution break fixes itself](docs/COMPOUNDING.md): every break blue's evolution causes ships its own fixer
- [CST plan: a lossless tree, resilient parsing, surface blame](docs/CST-PLAN.md): the design for a lossless CST with resilient parsing and surface blame; nothing is built yet
- [The data framework: one model, every rendering, nothing written twice](docs/DATA-FRAMEWORK.md): the design of the data framework, one blue model rendered to schema, migrations, queries and GraphQL with nothing written twice, and the research it rests on
- [DOCUMENTATION — every blue project documents itself, and the language has a book](docs/DOCUMENTATION.md): documentation as a battery: one source per fact, a Diátaxis book, rendered README, AGENTS.md and llms.txt (design)
- [FRONTEND-PLAN — building the blue frontend framework](docs/FRONTEND-PLAN.md): the build plan for blue's frontend framework
- [Guard-clause `return`: the design of record](docs/GUARD-RETURN.md): Guard-clause return, G1 BUILT: `return x` where the parser can rewrite it into if/else, refused where it cannot (B0080), so blue stays one expression per body at no run-time cost
- [HORIZON: where blue goes next](docs/HORIZON.md): the long plan for blue, ten horizons from hygiene to a language that proves, replays and explains itself, eight authority horizons that make every host effect a capability granted from one declaration in every placement, an ontology of every concept in khipu that the tests are generated from, and the kernel as both a verified target and the enforcer of access; destination first, each horizon with its first step, its gate and what it unlocks
- [HTTP2 — blue speaks HTTP/2 and gRPC itself](docs/HTTP2.md): blue speaks HTTP/2 and gRPC itself (design, phase 1 built)
- [IPHONE: a whole iPhone app in blue](docs/IPHONE.md): the iPhone placement, a whole iPhone app written in blue with one open Rust shell, a nix pipeline from source to simulator, device and CI (design; I0 and I1 tested, 2026-11-10)
- [KERNEL — write only blue for the Linux kernel](docs/KERNEL.md): blue as the whole kernel toolchain, from source to a program the verifier admits, and where each part runs
- [khipu: blue's knowledge graph, the design of record](docs/KHIPU.md): khipu, blue's knowledge graph, DESIGN: OxiRS's essence naturalized, the recon, the typed terms, the phases, the parity gates and the ledger
- [LANDING: faster to main, with every test still meaning what it meant](docs/LANDING.md): how a change reaches main fast without losing a test: batched lands, releases beside main, settled locks, tests skipped only by identity, suites run on runners (design, 2026-11-10)
- [Lessons behind the agent guide's rules](docs/LESSONS.md): the full story behind each rule the agent page states in short
- [MARKDOWN — Markdown is a first-class blue value](docs/MARKDOWN.md): Markdown as a first-class blue value: one typed tree, one formatting, checked links, and renderings to Markdown, HTML, PDF and the terminal (design)
- [Namespaces: a bidama definition stays in its bidama](docs/NAMESPACES.md): a bidama definition stays in its bidama: the rule as built and its gates
- [naturalize(tree-sitter) — the destination, before the build](docs/NATURALIZE-TREESITTER.md): tree-sitter naturalized: the grammar spec and what is emitted from it
- [OPERATORS — short notation for what blue says most, keyed to the blueshift](docs/OPERATORS.md): short notation for what blue says most, keyed to the blueshift (design)
- [P2P: a zero-server peer network in blue, and a game platform on it](docs/P2P.md): a zero-server peer network in blue with capability memory regions, fault-scoped tamper evidence, and a game platform on it (design, destination approved 2026-11-09)
- [Performance: blue as a scripting language and as a tool](docs/PERFORMANCE.md): what blue costs today, where the time goes, and the order to remove it
- [Registry](docs/REGISTRY.md): how a blue project is published and resolved: registries as renderings of the Bluefile
- [SERVICE-ACCESS — one access declaration, enforced by every layer that builds a service](docs/SERVICE-ACCESS.md): one access declaration, enforced by every layer that builds a service (design)
- [SERVICE-ARCHITECTURE — the default blue service](docs/SERVICE-ARCHITECTURE.md): the default blue service and the batteries it composes (design)
- [SERVICE-DATA — Postgres, Valkey and the nervous system as defaults](docs/SERVICE-DATA.md): Postgres, Valkey and the nervous system as the configurable defaults of a blue service (design)
- [STDLIB: blue's batteries, as one verb vocabulary](docs/STDLIB.md): the standard library's design as one verb vocabulary (design)
- [SUBSTRATE — blue as the one language of the whole stack](docs/SUBSTRATE.md): blue as the one language of the whole stack — business logic in blue, everything it needs rendered; layer 1 cloud on engenho, layer 2 every placement, layer 3 high-assurance local systems (design)
- [Testing and the SDLC: one blue pipeline](docs/TESTING.md): every kind of test and its one place beside what it tests, and the Bluefile as the one pipeline
- [utsushi (写し): blue's history projection, the design of record](docs/UTSUSHI.md): utsushi, blue's history projection, DESIGN: Josh's essence naturalized with six improvements, the recon, the lens and view algebra, the phases, the parity gates and the tier ledger
- [Blue verb roadmap: full software verbalization](docs/VERB-ROADMAP.md): the roadmap to full software verbalization
- [vocabularify — the surface/structure vocabulary](docs/VOCABULARIFY-SURFACE.md): kigou and yakugo: a program's spelling separated from its meaning
- [WORKSPACES — one root, many bidamas and many crates](docs/WORKSPACES.md): one root holding many bidamas and many crates (design)
- [Region A: data and knowledge (578 verbs, 30 spaces, 875 edges)](docs/verbs/A/REGION.md): verb graph region A: data and knowledge
- [Region B: storage and state (2026-10-22)](docs/verbs/B/REGION.md): verb graph region B: storage and state
- [Blue verb graph: shared brief (read fully first)](docs/verbs/BRIEF.md): the shared brief behind the verb graph
- [Region C: communication and distributed systems](docs/verbs/C/REGION.md): verb graph region C: communication and distributed systems
- [Region D: security and trust (2026-10-22)](docs/verbs/D/REGION.md): verb graph region D: security and trust
- [Region E: build, ship and run (346 verbs, 567 edges, 29 spaces)](docs/verbs/E/REGION.md): verb graph region E: build, ship and run
- [Region F: OBSERVE, TEST, QUALITY AND THE ENGINEERING PROCESS](docs/verbs/F/REGION.md): verb graph region F: observe, test, quality and process
- [Region G: interfaces, intelligence and the physical world](docs/verbs/G/REGION.md): verb graph region G: interfaces, intelligence and the physical world
- [H: the verb GRAPH as data blue owns (META region)](docs/verbs/H/DESIGN.md): the verb graph as data blue owns
- [Merged graph: repairs and decisions (H0a)](docs/verbs/merged/CHANGES.md): the merged verb graph: repairs and decisions
- [Naming sweep: what is applied and what the operator decided](docs/verbs/names/RULINGS.md): the naming sweep of the verb graph's spaces, and the rulings

</details>
