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

The philosophy is two axes
([`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md) §0).
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
| `blue check FILE` | Check a program against every rule in the registry — unbound names, unused bindings, types, waivers — and report the typing analysis. |
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
| `blue serve` | Serve one evaluation session as JSON lines on stdin/stdout (`theory/BLUE-TOOLING.md` §4): the door an editor drives. |
| `blue repl` | An evaluation session at the terminal. |
| `blue eval TARGET` | Evaluate EXPR, or the top-level form at FILE:LINE:COL in that file's context, and print its value. |
| `blue banner` | Print blue's wordmark. |
| `blue shift FILE` | Report the blueshift: how far this program is shifted, and what is shifting it. |
| `blue morph` | The morphology: what each posture grants, what it forfeits, which pairs are genuinely exclusive, and which language each shape corresponds to. |
| `blue reference` | Print the language reference as JSON: operators, keywords, surface forms, Bluefile words, every bound name and every command, each read from the table the implementation runs on. |
| `blue replay TRACE` | Run a crashed process again from the trace its crash wrote, and say whether it crashed the same way. |
| `blue receipt verify FILE` | Recompute a receipt's name from its bytes and check its form; any edit fails. |
| `blue config [TIER]` | Show the bounds `blue` is running with, at any tier. |
| `blue new NAME` | Start a program (a project with its own bidama), a `--bidama`, or a `--script`, each passing `blue test` as written. |
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
| Built-in names | 307: 280 functions, 14 special forms, 13 macros |
| Surface forms | 29, with 13 operators and 24 reserved words |
| Check rules | 65: 37 fix themselves, 7 suggest a fix |
| Bluefile words | 22 |
| Commands | 39 |

## The standard library

<details>
<summary>Every bidama, with the purpose its <code>@moduledoc</code> states</summary>

86 packages, 4754 definitions, 1545 tests.

- [anaritikusu](bidamas/CATALOG.md#anaritikusu) (アナリティクス) — lifecycle analytics: a database of telemetry, standard models and cross-lifecycle joins, generated from lifecycle definitions.
- [angou](bidamas/CATALOG.md#angou) (暗号) — number theory and the classical ciphers built on it.
- [bougyo](bidamas/CATALOG.md#bougyo) (防御) — the request-side defence of a service: security headers, a request id, and limits on what a request may be.
- [bunsho](bidamas/CATALOG.md#bunsho) (文書) — Markdown as a first-class value: `.md` text parsed into one typed tree whose node kinds are the ones CommonMark, GitHub Flavored Markdown and mdast agree on, the tree rendered back in one canonical formatting, and the tree read by node, by kind and by section.
- [chokkan](bidamas/CATALOG.md#chokkan) (直感) — System One judgment: typed questions in, calibrated answers out.
- [danpen](bidamas/CATALOG.md#danpen) (断片) — GraphQL in blue: documents parsed into plain records, checked against a schema, composed from fragments, rendered and hashed.
- [deeta](bidamas/CATALOG.md#deeta) (データ) — JSON data, read safely.
- [empresa](bidamas/CATALOG.md#empresa) (会社) — a company declared as data: domains, mail, sites and a GitHub org, each entry refused alone, projected to the variables its infrastructure applies.
- [fairu](bidamas/CATALOG.md#fairu) (ファイル) — files: paths and the files they name.
- [gamen](bidamas/CATALOG.md#gamen) (画面) — screen: what a program shows, as values: colors and themes, UI trees rendered to HTML, and styled text, tables and trees on the terminal.
- [gitto](bidamas/CATALOG.md#gitto) (ギット) — git, as verbs: a repository read as commits, refs, branches and files, and written by commit, fetch, merge, push and clone.
- [gurafu](bidamas/CATALOG.md#gurafu) (グラフ) — directed graphs as values: build them, ask them, order them.
- [gyouretsu](bidamas/CATALOG.md#gyouretsu) (行列) — vectors and matrices as nested lists.
- [hadome](bidamas/CATALOG.md#hadome) (歯止め) — a baseline ratchet: recorded debt may shrink or hold, never grow.
- [haibi](bidamas/CATALOG.md#haibi) (配備) — deployment: a Bluefile `service` rendered into everything that ships it.
- [happa](bidamas/CATALOG.md#happa) (葉っぱ) — a template's leaves: their declaration, split, graph, change, schedule and verdicts, as pure decisions.
- [heddaa](bidamas/CATALOG.md#heddaa) (ヘッダー) — header fields as HTTP/2 carries them: HPACK (RFC 7541).
- [heni](bidamas/CATALOG.md#heni) (変異) — mutation testing for a blue package: each mutation changes one literal in a fresh copy of the package, runs its tests, and must make them fail.
- [hikisuu](bidamas/CATALOG.md#hikisuu) (引数) — command-line arguments: one declared spec is parsed into a record, rendered as help, and answered as shell completion.
- [hizuke](bidamas/CATALOG.md#hizuke) (日付) — the proleptic Gregorian calendar, as arithmetic.
- [hon](bidamas/CATALOG.md#hon) (本) — a project's book: its pages, each of one Diátaxis kind, rendered into the files a reader or an agent opens.
- [hyouka](bidamas/CATALOG.md#hyouka) (評価) — evaluation: Nix's command line as data.
- [jisho](bidamas/CATALOG.md#jisho) (辞書) — dictionaries: maps as values, read and changed by key, each change a new map.
- [jitaku](bidamas/CATALOG.md#jitaku) (自宅) — a home, declared entry by entry, each refused alone, projected to pleme.lareira.
- [junjo](bidamas/CATALOG.md#junjo) (順序) — ordering: sorting, searching, selection.
- [kakou](bidamas/CATALOG.md#kakou) (加工) — fabrication: folded sheet, cut tube and bent wire, from the dimensions a shop measures to the blanks, cut lists and solids it makes.
- [kansuu](bidamas/CATALOG.md#kansuu) (関数) — functions about functions.
- [kazu](bidamas/CATALOG.md#kazu) (数) — numbers.
- [keisoku](bidamas/CATALOG.md#keisoku) (計測) — measurement: the instruments a program keeps while it runs, and their samples in the Prometheus text format.
- [keiyu](bidamas/CATALOG.md#keiyu) (経由) — by way of: run one command with a proxy set for it alone.
- [kiibariu](bidamas/CATALOG.md#kiibariu) (キーバリュー) — Valkey and Redis over the runtime's RESP words.
- [kijun](bidamas/CATALOG.md#kijun) (基準) — the standard a private nix fleet repo is held to, as data: layout, expression and evaluated-tree rules, per-entry waivers, and a baseline ratchet.
- [kikagaku](bidamas/CATALOG.md#kikagaku) (幾何学) — plane geometry on [x, y] points.
- [kinji](bidamas/CATALOG.md#kinji) (近似) — approximation: numerical methods: ODEs, roots, minimisation, least squares, interpolation and quadrature.
- [kinko](bidamas/CATALOG.md#kinko) (金庫) — a safe: a 1Password account declared as data, each entry refused alone, projected to Terraform JSON.
- [kirikae](bidamas/CATALOG.md#kirikae) (切り替え) — switching over: whether a system switch must run, may be skipped, or must wait.
- [kiwari](bidamas/CATALOG.md#kiwari) (木割): one grammar spec, every syntax artifact emitted from it.
- [kousei](bidamas/CATALOG.md#kousei) (構成) — a system composed entry by entry: each entry checked, configured off, tuned or refused alone, then judged into what stands.
- [koutei](bidamas/CATALOG.md#koutei) (工程) — one step of a pipeline, as GitHub Actions runs it.
- [kueri](bidamas/CATALOG.md#kueri) (クエリ) — queries: analysis is authored in blue, and SQL is only the rendered bridge to DuckDB.
- [kumiawase](bidamas/CATALOG.md#kumiawase) (組み合わせ) — counting without enumerating.
- [kyasshu](bidamas/CATALOG.md#kyasshu) (キャッシュ) — cache: the normalized entity store of the frontend data runtime.
- [kyohi](bidamas/CATALOG.md#kyohi) (拒否) — refusals, as data.
- [kyuuji](bidamas/CATALOG.md#kyuuji) (給仕) — serving: an HTTP/1.1 service over the runtime's `http_listen`.
- [maakuappu](bidamas/CATALOG.md#maakuappu) (マークアップ) — XML as data: a document parsed by the runtime's xml_parse (quick-xml) into element maps {name, attributes, children, text}, the queries a reader of a scanner export asks of it (children and descendants by name, attributes, text, a path of element names), and the element rendered back with every value escaped. A DTD entity is never expanded or fetched: the document is refused (:xml_refused), and a document that is not well-formed raises :xml_malformed.
- [moji](bidamas/CATALOG.md#moji) (文字) — strings.
- [mokuroku](bidamas/CATALOG.md#mokuroku) (目録): the catalogue of what every bidama on a BLUE_PATH provides.
- [nikkusu](bidamas/CATALOG.md#nikkusu) (ニックス) — Nix source as data: rnix's lossless tree from nix_parse, and the queries a linter asks of it (attrpath bindings, calls by head, with scopes, angle paths, option declarations).
- [nisshi](bidamas/CATALOG.md#nisshi) (日誌) — an event log: append-only JSON Lines, hash-chained, optionally signed, replayed into lifecycle states.
- [okite](bidamas/CATALOG.md#okite) (掟) — blue's decisions, each enforced by laws written in blue.
- [ongaku](bidamas/CATALOG.md#ongaku) (音楽) — twelve-tone music theory, as arithmetic on semitones.
- [outou](bidamas/CATALOG.md#outou) (応答) — a GraphQL request answered: a schema of blue resolvers, execution to {data, errors}, introspection and subscription events, over danpen's documents.
- [raifusaikuru](bidamas/CATALOG.md#raifusaikuru) (ライフサイクル) — lifecycles: event-sourced states, guards that name the rule and the task, and permit limits.
- [ran](bidamas/CATALOG.md#ran) (乱) — deterministic pseudo-randomness.
- [retsu](bidamas/CATALOG.md#retsu) (列) — lists, made TOTAL.
- [rittai](bidamas/CATALOG.md#rittai) (立体) — solids: poses, triangle meshes built by extrusion and sweep, their validity, volume and centroid, and STL.
- [rogu](bidamas/CATALOG.md#rogu) (ログ) — logging: one structured line per call, JSON on stderr.
- [ronri](bidamas/CATALOG.md#ronri) (論理) — predicates, and the algebra over them.
- [ryouiki](bidamas/CATALOG.md#ryouiki) (領域) — region: which region of the inputs produces an outcome.
- [sabi](bidamas/CATALOG.md#sabi) (錆): Rust source from blue data. Build the items as values, render once.
- [saishikou](bidamas/CATALOG.md#saishikou) (再試行) — retrying a step that can fail for a moment.
- [seimei](bidamas/CATALOG.md#seimei) (生命) — cellular automata: elementary rules, and Life.
- [settei](bidamas/CATALOG.md#settei) (設定) — configuration, blue's shikumi: a record of defaults grouped by concern, resolved by read(app, defaults) from the defaults, then ~/.config/<app>/<app>.yaml (or <APP>_CONFIG), then <APP>_<GROUP>__<KEY> in the environment, each value typed by its default and a wrong type refused. The resolved record is read by dotted path; a misspelt path raises and names the fields that exist.
- [shihyou](bidamas/CATALOG.md#shihyou) (指標) — indicator: a service's SLO as data, projected to the rules and the dashboard that watch it.
- [shinchoku](bidamas/CATALOG.md#shinchoku) (進捗) — progress: operational probes that judge by progress over a window, never by one reading.
- [shinsuu](bidamas/CATALOG.md#shinsuu) (進数) — base conversion and checksums.
- [shisei](bidamas/CATALOG.md#shisei) (姿勢) — a service's posture: postures declared as kousei entries, each on by default, each configured off or tuned, each refused alone.
- [shisutemu](bidamas/CATALOG.md#shisutemu) (システム) — the system.
- [shomei](bidamas/CATALOG.md#shomei) (署名) — signatures and hash chains: Ed25519 and BLAKE3, for real.
- [shuugou](bidamas/CATALOG.md#shuugou) (集合) — sets, over plain lists.
- [shuusei](bidamas/CATALOG.md#shuusei) (修正) — amending declared data: put a value at a path, delete it, merge into it, upsert a list element, and amend a keyed set of objects by judged patch entries.
- [souji](bidamas/CATALOG.md#souji) (掃除) — cleaning a node: Rust target/ directories nobody is building in, and nix store paths nothing refers to, with a dry run first.
- [sutoriimu](bidamas/CATALOG.md#sutoriimu) (ストリーム) — NATS JetStream over the runtime's NATS words.
- [tajuu](bidamas/CATALOG.md#tajuu) (多重) — multiplexing: HTTP/2's frames and the streams they carry
- [teeburu](bidamas/CATALOG.md#teeburu) (テーブル) — a service's tables: rows over the runtime's pg_ words, and versioned data models that evolve in pure blue.
- [tehai](bidamas/CATALOG.md#tehai) (手配) — which nix remote builders can take work right now: every declared machine checked, and only the live ones written where nix reads them.
- [tesuto](bidamas/CATALOG.md#tesuto) (テスト) — testing: errors and snapshots as assertions, and the policy that holds every definition to a test beside it.
- [tokumei](bidamas/CATALOG.md#tokumei) (匿名) — anonymity: learn what a group is without exposing anyone in it.
- [toukei](bidamas/CATALOG.md#toukei) (統計) — descriptive statistics.
- [touroku](bidamas/CATALOG.md#touroku) (登録) — registry: a project published to and resolved from registry backends, each a rendering of the Bluefile, never its truth.
- [tsuiseki](bidamas/CATALOG.md#tsuiseki) (追跡) — tracing: spans run around functions and written to the log, a sink or an OTLP collector.
- [tsuushin](bidamas/CATALOG.md#tsuushin) (通信) — communication: what two programs say to each other.
- [ugoki](bidamas/CATALOG.md#ugoki) (動き) — motion: how a value moves over time.
- [ukai](bidamas/CATALOG.md#ukai) (迂回) — a detour: keep an overlay VPN reaching its control plane and relays while a full-tunnel corporate VPN owns the default route.
- [zenbu](bidamas/CATALOG.md#zenbu) (全部) — the whole distribution, as ONE dependency.
- [zumen](bidamas/CATALOG.md#zumen) (図面) — technical drawings: 2-D entities on layers, sheets with a title block, feature-edge views of solids, written as DXF R12 and SVG.

</details>

## What is not built

blue states its gaps plainly, because a language's honest gaps matter more
than its claims. This list is the one in
[Implementing blue](docs/implementing.md#what-is-not-built), rendered here:

Stated so nobody cites it as existing: **no per-process GC heap** (processes have
private environments and messages are deep-copied, but reclamation is `Arc`
refcounting — no independent collection pause), **no registry client** (resolution
is real; nothing fetches), **no self-hosting on the implementation axis**
(`spec/*.b` is the specification axis only), **no comment attachment inside a
form**, **no entropy primitive and no encryption** (the `crypto` layer hashes,
signs and verifies; a keypair comes from a seed the caller supplies),
**no TLS** (`net` speaks NATS and HTTP over plain TCP: an `https://` url and a
NATS server requiring TLS are refused by name; planned in `docs/HTTP2.md` P4,
rustls with ALPN `h2`),
**no import EMISSION into a wasm module** (`blue_lang_waku::imports_of`
derives the table from a frame — nothing puts an entry into a `.wasm`, and no
engine border is wired: that is `BLUE-EXECUTION.md` M2, blocked on `tatara-wasm`
not being on crates.io), **no editor answer inside a broken buffer** (the
LSP answers from the newest revision that parsed until the parser recovers,
`BLUE-ENGINE.md` E6), **project rules in the editor or as wasm** (`blue check`
runs them in-process under the rule frame; the LSP does not run them, and the
ABI is shaped for a wasm module that nothing builds yet), and no **`case`/`when` pattern matching** or **ranges** — the two remaining
surface gaps a Ruby or Elixir author would reach for. `theory/BLUE.md` §V.26 holds the tier ledger; **do not build against a
DESIGN-tier row without saying so.**

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

### Reference

- [Canonical forms](docs/CANONICAL-FORMS.md): every place the surface accepts two spellings, the one blue writes, and the rule that names it
- [Diagnostics](docs/DIAGNOSTICS.md): what the check stage reports, every rule code, and the machine-readable shape of a diagnostic
- [blue examples](docs/EXAMPLES.md): one tested program per common task, ready to paste as examples
- [Glossary: blue's terms and the concepts they name](docs/GLOSSARY.md): every blue term mapped to the compiler, language or distributed-systems concept it names, in both directions, and how the parts meet in a compile, a test run and a deploy
- [blue language reference](docs/REFERENCE.md): syntax, operators, reserved words, every built-in name and the Bluefile words
- [Safety first: blue's posture, row by row](docs/SAFETY.md): the safety-first posture, one row per Rust guarantee: blue today, the gate, its tier and its off switch
- [blue — the agent guide](AGENTS.md): rules for people and agents who write blue programs or change blue itself, with the build commands from the Bluefile
- [Implementing blue — the detail behind the agent guide](docs/implementing.md): the implementer detail behind the agent guide's "Changing blue itself": the check registry, crate map, hard-won rules, CI gates, dependencies and what is not built

### Explanation

<details>
<summary>40 pages on why blue is shaped as it is</summary>

- [ABSENCE — no undeclared nil](docs/ABSENCE.md): no undeclared nil: how blue makes absence a declared, checked state
- [API-EVOLUTION — the API is a versioned rendering of the one model](docs/API-EVOLUTION.md): the API as a versioned rendering of one model (design)
- [BIDAMA-COHESION — one word per job, foundations below, a complete vocabulary](docs/BIDAMA-COHESION.md): one word per job, foundations below, a complete vocabulary across the bidamas (plan)
- [BUILD-ASSURANCE — what a blue build proves, how fast, and from which cache](docs/BUILD-ASSURANCE.md): what a blue build proves, how fast, and from which cache (design)
- [BUILD-STACK — the default platform for a blue service, from Bluefile to a running node](docs/BUILD-STACK.md): the default platform for a blue service, from Bluefile to a running node (design)
- [`Cargo.gen.lock` is committed, and that is a trade](docs/CARGO-GEN-LOCK.md): why Cargo.gen.lock is committed, and what that trade costs
- [CLI-TUI — one way to build a command line and a terminal interface in blue](docs/CLI-TUI.md): one way to build a command line and a terminal interface in blue (design, layer 1 built)
- [Competing languages — what blue takes, and what it refuses](docs/COMPETING-LANGUAGES.md): what blue takes from competing languages on packaging and the standard library, and what it refuses
- [Compile time: Rust's static guarantees and Lua's runtime, in blue](docs/COMPILE-TIME.md): Rust's static guarantees and Lua's runtime, brought into blue
- [Compounding: every evolution break fixes itself](docs/COMPOUNDING.md): every break blue's evolution causes ships its own fixer
- [CST plan: a lossless tree, resilient parsing, surface blame](docs/CST-PLAN.md): the design for a lossless CST with resilient parsing and surface blame; nothing is built yet
- [DOCUMENTATION — every blue project documents itself, and the language has a book](docs/DOCUMENTATION.md): documentation as a battery: one source per fact, a Diátaxis book, rendered README, AGENTS.md and llms.txt (design)
- [FRONTEND-PLAN — building the blue frontend framework](docs/FRONTEND-PLAN.md): the build plan for blue's frontend framework
- [HTTP2 — blue speaks HTTP/2 and gRPC itself](docs/HTTP2.md): blue speaks HTTP/2 and gRPC itself (design, phase 1 built)
- [Lessons behind the agent guide's rules](docs/LESSONS.md): the full story behind each rule the agent page states in short
- [MARKDOWN — Markdown is a first-class blue value](docs/MARKDOWN.md): Markdown as a first-class blue value: one typed tree, one formatting, checked links, and renderings to Markdown, HTML, PDF and the terminal (design)
- [Namespaces: a bidama definition stays in its bidama](docs/NAMESPACES.md): a bidama definition stays in its bidama: the rule as built and its gates
- [naturalize(tree-sitter) — the destination, before the build](docs/NATURALIZE-TREESITTER.md): tree-sitter naturalized: the grammar spec and what is emitted from it
- [OPERATORS — short notation for what blue says most, keyed to the blueshift](docs/OPERATORS.md): short notation for what blue says most, keyed to the blueshift (design)
- [Performance: blue as a scripting language and as a tool](docs/PERFORMANCE.md): what blue costs today, where the time goes, and the order to remove it
- [Registry](docs/REGISTRY.md): how a blue project is published and resolved: registries as renderings of the Bluefile
- [SERVICE-ACCESS — one access declaration, enforced by every layer that builds a service](docs/SERVICE-ACCESS.md): one access declaration, enforced by every layer that builds a service (design)
- [SERVICE-ARCHITECTURE — the default blue service](docs/SERVICE-ARCHITECTURE.md): the default blue service and the batteries it composes (design)
- [SERVICE-DATA — Postgres, Valkey and the nervous system as defaults](docs/SERVICE-DATA.md): Postgres, Valkey and the nervous system as the configurable defaults of a blue service (design)
- [STDLIB: blue's batteries, as one verb vocabulary](docs/STDLIB.md): the standard library's design as one verb vocabulary (design)
- [Testing and the SDLC: one blue pipeline](docs/TESTING.md): every kind of test and its one place beside what it tests, and the Bluefile as the one pipeline
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
