# STDLIB: blue's batteries, as one verb vocabulary

**Status: DESIGN (2026-10-19).** Nothing here is built. It is written against the forms the
canonical-forms work is landing (`raise :kind, "msg"`, `rescue :kind as e … ensure … end`, inline
`expr rescue default`, records read as `value.field`, splat `f(*args)`, the `main` entry, default
per-file namespaces, `json_at`). `docs/CANONICAL-FORMS.md` was not committed when this was
written. Where it settles a spelling differently, the spelling here changes and the design does
not. Every count below was measured on 2026-10-19 (§9 has the method).

The operator's two directives:

> *"leverage knowledge of all other languages to build the default tools and batteries included
> to make the great majority of bluelang code extremely repetitive and batteries included."*

> *"there should be a complete set of verbs for all predictable problemscapes."*

"Repetitive" here means **uniform**: the same task is always written the same way, so a reader who
knows one corner of the library can read all of it. The mechanism is a **closed vocabulary of
verbs**. Each verb means one thing in every problem space where it appears. Each space declares the
complete set of verbs it implements, and a build gate holds the declaration (§5). Readability comes
first: verbs are plain English words, never abbreviations.

**Beyond scripting:** [`VERB-ROADMAP.md`](VERB-ROADMAP.md) extends this vocabulary to all of software engineering: 2,839 verbs in 163 spaces and 4,529 relations, the defects the merge found, and the phased plan. Data: `docs/verbs/`.

## 0. The design in one screen

```ruby
use("deeta")
use("fairu")
use("rogu")
use("shisutemu")

def main(args)
  rev = shisutemu::capture("git", ["rev-parse", "HEAD"], {cwd: args.repo})
  lock = deeta::read(fairu::join(args.repo, "flake.lock"))
  fairu::write(fairu::join(args.out, "rev.txt"), rev)
  rogu::info("pinned", {rev: rev, inputs: size(lock.nodes)})
end
```

- A **space** is one problem domain (files, processes, data formats, time, git…). Each space is one
  bidama, named by the plain Japanese noun for the domain (the goi rule, `theory/NAMING.md`), and
  its verbs are always written qualified: `fairu::read`, never a bare `read`.
- A **verb** has one meaning everywhere. `read` gets the whole content of a source, whether the
  source is a file, a URL, a secret, a config tier or a git blob. `get` looks a key up in a store and
  answers nil when the key is absent, whether the store is a map, the environment, a Kubernetes
  kind or a GitHub path.
- **Arguments:** the subject comes first and options come last, as one record with defaults.
  **Returns:** records, never association lists. **Errors:** the verb raises a typed kind, and the
  call site decides with `rescue`. There are no `_or` or `_or_nil` variants.

## 1. Survey: what the best standard libraries get right

The survey is organised by what each library does well **for a reader**. The last column is what
blue adopts.

| Domain | Best reading elsewhere | Why it reads well | Blue takes |
|---|---|---|---|
| Files and paths | Python `pathlib` (`p.read_text()`, `p / "x"`), Elixir `File` + `Path` (`File.read!`, `Path.join`), Ruby `File.write`, Go `os.ReadFile` | one call per whole-file operation; joining paths is a function rather than string concatenation; Elixir pairs `read` (a tuple) with `read!` (raises) | whole-file verbs, `join`, path properties named as nouns (`parent`, `name`, `extension`); one raising form, since the call site rescues |
| Processes | Python `subprocess.run(check=True, capture_output=True)`, Ruby `Open3.capture3`, Go `exec.Command(...).Output()`, Elixir `System.cmd` → `{out, status}` | an argv list with no shell; one result object; `check=True` turns a bad status into an error | argv lists with no shell, one result record, raising by default, `ok:` for the statuses that count as success, `pipefail` built into `pipe` |
| Environment | Elixir `System.get_env/fetch_env!`, Python `os.environ.get` vs `[]`, Rust `std::env::var` | absence as nil next to a raising lookup, each with one name | `get` (nil) and `need` (raises) |
| Typed config | shikumi tiers, Rust `figment`, Go `viper`, Python pydantic-settings | defaults < file < environment, typed by the default | `settei::read(app, defaults)` returns one record; each value's type comes from its default |
| Data formats | Rust `serde` (one model, many formats), Python `json`/`csv`/`tomllib`, Ruby `JSON.parse`/`YAML.load` | parse and dump are symmetric; one data model across every format | `deeta::parse(text, :yaml)` and `deeta::render(value, :yaml)` over one value model, with records |
| Time | Rust `jiff`/`chrono`, Python `datetime` + `timedelta`, Go `time.Duration` (`30*time.Second`), Elixir `:timer.seconds` | a duration is a typed value, never a bare integer | instants and durations as values (`jikan::seconds(30)`); no option key carries a unit |
| Regex | Ruby `=~`, `scan`, `gsub`; Rust `regex` | a compiled pattern is a value; one `replace` takes text or a pattern | `moji::pattern(text)`, which `find`, `replace`, `split` and `matches?` all accept |
| HTTP client | Deno/Bun built-in `fetch`, Python `requests`, Go `net/http` | one request call; status is data; JSON bodies are first class | `tsuushin::request` plus the store verbs over REST (`get`, `list` with pagination, `create`, `update`) |
| CLI parsing | Rust `clap` derive, Python `argparse`, Ruby `OptionParser`, Go `flag` | one declaration yields parsing, defaults, types and `--help` | `hikisuu::parse(args, spec)` with the type taken from each default; help is rendered from the spec |
| Logging | Go `slog`, Rust `tracing`, Python `logging` | levels as calls, structured fields, one handler choice | `rogu::info("msg", {k: v})`: JSON lines on stderr, text on a terminal |
| Errors | Rust `anyhow`/`thiserror`, Ruby `raise`/`rescue`/`ensure`, Elixir `!` functions | typed kinds, context added on the way up, one place to recover | the new `raise`/`rescue` model, a closed ledger of kinds (§4.9), no parallel non-raising APIs |
| Collections | Elixir `Enum`, Ruby `Enumerable`, Python `itertools`/`functools`, Nushell structured pipelines | subject-first data, so a pipeline reads left to right; one name per operation | the Enum vocabulary, subject-first (decision D2), records in and records out |
| Concurrency | Go `errgroup` + `context`, Elixir `Task.async_stream(max_concurrency:)`, Python `asyncio.gather` | bounded parallel map; first failure cancels the rest | `heikou::map(xs, f, {limit: 8})`, `heikou::all(fs)`, `heikou::retry(f, policy)`, with `timeout:` on every effectful verb |
| Hashing and encoding | Python `hashlib`/`base64`, Go `crypto/sha256` + `encoding/hex` | the algorithm is an argument | `shomei::hash(data, :sha256)`, `deeta::encode(bytes, :base64)` |
| Testing | Deno `assertEquals` diffs, pytest's assertion rewriting, Jest snapshots, Go `t.TempDir()` | a plain `assert a == b` that prints a structural diff; temporary directories that clean themselves up | `assert a == b` keeps its spelling and gains a diff; `snapshot`; `with_temp_dir` |
| Shell-like flows | Nushell (`ls \| where size > 1mb \| sort-by modified`) | commands return tables; filters are data operations | file and process verbs return records, so `fairu::list(dir) \|> filter(...)` is the pipeline |
| DSL ergonomics | Ruby (bare zero-argument calls, keyword args), Lua tables | configuration that reads as data | an options record last; specs (`hikisuu`, `settei`) are plain records |

What every one of these gets right, and what blue holds as law: **each operation has one name**,
**the common case is one call**, and **failure is loud by default with recovery written at the call
site**. The libraries that fall short (Python's `os.path` beside `pathlib`, Go's `ioutil` beside
`os`, Ruby's `File.exists?` beside `exist?`) do so because they keep two spellings of one operation
alive.

## 2. Conventions: the template every space follows

These are the rules that make blue code repetitive. Each one is a check-stage rule or a gate,
named in §5 and §8.

### 2.1 Names

| Kind | Form | Examples |
|---|---|---|
| a space | a bidama with a plain Japanese domain noun, always written as the qualifier | `fairu::read`, `shisutemu::run` |
| an effect or a transformation | a **master verb** (§3) | `read`, `run`, `parse`, `delete` |
| a verb that needs its subject named | `verb_noun`, where the noun is one the space declares | `fairu::make_dir`, `fairu::with_temp_dir` |
| a pure property of a value | the **noun** for what it returns, declared by the space | `fairu::parent(p)`, `jikan::year(t)`, `retsu::size(xs)` |
| a constructor | the noun for the value | `jikan::seconds(30)`, `moji::pattern("^v[0-9]+")` |
| a predicate | an adjective or verb with `?`, never `is_` | `fairu::exists?(p)`, `moji::blank?(s)`, `shisutemu::succeeds?(...)` |

Space verbs are **always qualified**. Listing one bare (`use("fairu", [:read])`) is refused with a
fix, because a bare `read` cannot say which space it reads. The collection verbs (§3.6) are the
exception: they are the prelude and are written bare.

### 2.2 Arguments

- **Subject first.** The thing acted on (a path, a command, a store, a list) is the first argument,
  so `x |> verb(...)` works for every space verb.
- **Required positionals, at most three.** Anything optional goes in the trailing options record.
- **Options are one record, last, optional, with declared defaults.** An unknown key raises
  `:bad_option` and names the keys the verb takes, so a typo is never silently ignored. Option names
  are the same across spaces: `cwd:`, `env:`, `timeout:`, `ok:`, `show:`, `at:`, `limit:`,
  `context:`, `format:`.
- **Varargs only through splat.** A process's arguments are a list (`run("nix", ["build", a])`).
  `run("nix", *args)` is written when the list is already in hand.

### 2.3 Returns

- **Records**, read as `r.field`. A verb's return shape never depends on its options. A verb that
  would need two shapes is two verbs (`run` returns a result record, `capture` returns text).
- `nil` means "absent", and only lookups (`get`, `find`, `which`) return it. Every other verb that
  has nothing to return returns `nil` to show that it ran for its effect.
- Lists are **complete** (`list` follows every page) and **sorted** wherever the source has no
  order of its own (`walk`, `glob` and `list` in every space). The trap of a bare `walk_dir` ("in no
  fixed order: sort before comparing") disappears.

### 2.4 Errors: one policy

1. **Raise by default.** A verb that cannot do what it says raises a kind from the ledger (§4.9),
   with a message naming the subject (`fairu::read: /etc/x: not found`) and the data a handler needs
   (`e.data.result` for a failed command).
2. **Recover at the call site**, with `expr rescue default` or `rescue :kind as e`. There are no
   `read_or`, `get_or`, `_or_nil` or `try_` variants, and the rule in §8 refuses new ones.
3. **The exceptions are by verb, not by space.** A lookup (`get`, `find`, `which`) answers nil for
   absence, because absence is data. A predicate (`exists?`, `has?`, `succeeds?`) never raises for the
   condition it tests. `delete` treats an absent subject as already done. `need` is the raising
   lookup.
4. **Program faults are not recoverable by a bare `rescue`.** An unbound name, an arity error or a
   type mismatch reaches a handler only when the handler names that kind (`theory/BLUE-GAPS.md` G4).

```ruby
text = fairu::read(path) rescue ""

def head_of(repo)
  shisutemu::capture("git", ["rev-parse", "HEAD"], {cwd: repo})
rescue :command_failed as e
  raise :not_a_repo, "#{repo}: #{e.message}"
end
```

### 2.5 Values

| Value | Representation | Why |
|---|---|---|
| a path | a string | it goes straight into an argv, into interpolation and into every primitive. Path properties are `fairu` nouns. `~` is never expanded implicitly; `fairu::home` is explicit |
| a duration | `jikan::seconds(n)` and friends: a record `{milliseconds:}` | a bare integer passed as a duration is the classic units bug. A `timeout:` given a number raises `:bad_option` |
| an instant | `jikan::now`: a record `{unix_nanoseconds:, zone:}` | arithmetic and rendering go through `jikan`; `now_ms` stays as the raw primitive |
| bytes | a byte list, as today | `deeta::encode` and `decode` move between bytes and text |
| a secret | a `himitsu` record that renders as `<secret>` through `to_s`, interpolation and `rogu` | a leak through a log line becomes a value you cannot render; `himitsu::reveal(s)` is the one door, and it can be searched for |
| a result | `{status:, stdout:, stderr:, took:, command:}` | the same record from `run`, `wait`, `pipe` and `stream` |
| a resource | the store's own record (a Kubernetes object, a GitHub JSON body) | read as fields; `deeta` parses into records |

### 2.6 Eager and streaming

The default is **eager and whole**: `read`, `list` and `capture` hold the whole answer. Streaming has
one spelling: the verb `stream` (or `watch` for change events) takes a function that is called per
item and returns the final record. There is no lazy sequence type in the standard library. Lazy
sequences are tatara-lisp's, and `cycle`/`realize` stay a known trap.

### 2.7 Purity and capability

A verb that touches the host declares its capability (`Capability::Filesystem`, `Process`,
`Network`, `Environment`, `Clock`). Pure verbs (paths, parse, render, collections) declare none, so
the evaluation engine may cache them (`theory/BLUE-ENGINE.md`). A space mixes both kinds, and each
definition's capability is derived, never asserted by hand.

### 2.8 Each verb's documentation and tests

Every public definition carries its one-line doc (it reaches `CATALOG.md` and `blue doc`). It also
carries the four tests (the empty case, an identity, an independently checked value, a control),
and it passes the laws of its verb (§5.3).

## 3. The master verb table

This table is the vocabulary itself. A space may implement only verbs listed here (plus its declared
`verb_noun` forms, nouns and predicates), and a new verb is a new row, landed with its laws.

### 3.1 Content: a source that holds something

| Verb | Meaning | Shape | Raises | Spaces |
|---|---|---|---|---|
| `read` | the whole content of a source | `read(source, opts) -> content` | `:not_found`, `:permission_denied`, `:parse_error` (spaces that parse) | fairu (text), deeta (parsed value, format from the extension), tsuushin (GET body), himitsu (secret), settei (the resolved config record), kankyou (a dotenv file), gitto (a file at a ref), kurasuta (pod logs), joujuu (journal) |
| `write` | replace the whole content, atomically, creating parents | `write(target, content, opts) -> nil` | `:permission_denied` | fairu, deeta (renders by extension), himitsu |
| `append` | add to the end, creating the file if needed | `append(target, content) -> nil` | `:permission_denied` | fairu |
| `exists?` | whether the subject is there; never raises | `exists?(subject) -> Bool` | none | fairu, tsuushin (HEAD), gitto (a ref) |
| `copy` | place a copy at a destination | `copy(from, to, opts) -> nil` | `:not_found`, `:exists` (without `replace: true`) | fairu, hyouka (`nix copy`, `to:` a host) |
| `move` | move or rename, atomically on one filesystem | `move(from, to, opts) -> nil` | `:not_found`, `:exists` | fairu |
| `walk` | every file under a root, sorted | `walk(root, opts) -> [path]` | `:not_found` | fairu |
| `glob` | the paths matching a pattern, sorted; absolute patterns work | `glob(pattern, opts) -> [path]` | none (no match is `[]`) | fairu |
| `info` | the subject's current state, as a record | `info(subject, opts) -> record` | `:not_found` | fairu (stat), gitto (status), joujuu (unit status), shisutemu (the host), hyouka (path info), kurasuta (cluster) |

### 3.2 Stores: a collection of keyed things

A **store** is anything holding named entries: a map, the environment, a config record, a sops
file, a Kubernetes kind, a GitHub path, a git repository's refs, a key-value bucket, a table. The
same verbs and laws apply to every one.

| Verb | Meaning | Shape | Raises | Spaces |
|---|---|---|---|---|
| `list` | every entry, all pages, sorted by key | `list(store, opts) -> [record]` | `:not_found` (the store itself) | fairu (directory entries), kankyou, kurasuta, habu, gitto, joujuu, himitsu |
| `get` | one entry, or nil when it is absent | `get(store, key, opts) -> value or nil` | only for an unreachable store, never for absence | jisho, kankyou, settei, himitsu, kurasuta, habu, gitto, tsuushin |
| `need` | one entry, raising when it is absent | `need(store, key, opts) -> value` | `:not_found`, naming the key and the store | the same as `get` |
| `has?` | whether the key is present | `has?(store, key) -> Bool` | none | the same as `get` |
| `put` | create or replace (an idempotent upsert) | `put(store, key, value, opts) -> value` | `:permission_denied` | jisho (a new map), himitsu, habu |
| `create` | add a new entry; refuses to overwrite | `create(store, key, value, opts) -> value` | `:exists` | habu, gitto (a branch) |
| `update` | replace an entry with `f(old)` | `update(store, key, f, opts) -> value` | `:not_found`, `:conflict` (a concurrent writer) | jisho, habu |
| `delete` | make the entry absent; absent counts as done | `delete(store, key) -> nil` (`delete(path)` in fairu) | `:permission_denied` | fairu, jisho, himitsu, habu, gitto |
| `watch` | call `f(event)` per change until it returns `:stop` | `watch(store, f, opts) -> nil` | `:not_found` | fairu (polling), kurasuta, settei |
| `query` | ask the store a question in its own language | `query(store, question, params) -> [record]` | `:query_error` | kueri (DuckDB), teeburu (PostgreSQL), habu (GraphQL) |

`update` takes a function, never a patch record, so "read, change, write back" has one spelling in
every store. A remote store implements it as get, then `f`, then a conditional write
(resourceVersion, ETag), and raises `:conflict` rather than losing an update.

### 3.3 Running things

| Verb | Meaning | Shape | Raises | Spaces |
|---|---|---|---|---|
| `run` | run to completion and return the result | `run(command, args, opts) -> result` | `:command_not_found`, `:command_failed` (status not in `ok:`, `e.data.result`), `:timeout` | shisutemu; heikou (`run(f, opts) -> value`) |
| `capture` | run and return stdout, minus its trailing newline | `capture(command, args, opts) -> text` | as `run` | shisutemu |
| `succeeds?` | whether the command exits with an `ok:` status | `succeeds?(command, args, opts) -> Bool` | `:command_not_found` only | shisutemu |
| `stream` | run, calling `f(line)` per stdout line as it arrives | `stream(command, args, f, opts) -> result` | as `run` | shisutemu, tsuushin |
| `pipe` | run stages connected stdout to stdin; any failing stage raises | `pipe(stages, opts) -> result` | as `run`, naming the stage | shisutemu |
| `spawn` | start without waiting; return a handle | `spawn(command, args, opts) -> handle` | `:command_not_found` | shisutemu, heikou (`spawn(f)`; the builtin for blue processes) |
| `wait` | wait for a handle to finish | `wait(handle, opts) -> result` | `:timeout`, then as `run` | shisutemu, heikou |
| `stop` | end it: TERM, a grace period, then KILL | `stop(handle or unit, opts) -> nil` | none when it is already stopped | shisutemu, heikou, joujuu |
| `start` / `restart` | start a service, or restart it | `start(unit, opts) -> nil` | `:not_found`, `:command_failed` | joujuu |
| `which` | the absolute path of a command on PATH, or nil | `which(name) -> path or nil` | none | shisutemu |
| `become` | replace this program with a command; does not return | `become(command, args, opts)` | `:command_not_found` | shisutemu |
| `retry` | call `f` again under a policy while it raises a retryable kind | `retry(f, policy) -> value` | the last error | heikou |
| `all` | run functions concurrently; values in order; the first failure stops the rest | `all(fs, opts) -> [value]` | the first error | heikou |
| `plan` | what a mutating verb would do, as data, changing nothing | `plan(...) -> [action]` | as the verb | hyouka, joujuu, souji, kirikae |

### 3.4 Transformation (pure)

| Verb | Meaning | Shape | Raises | Spaces |
|---|---|---|---|---|
| `parse` | text to a value | `parse(text, format, opts) -> value` | `:parse_error` (`e.data.line`, `e.data.column`) | deeta, jikan, hikisuu (args), tsuushin (URLs), moji (`pattern`) |
| `render` | a value to text, canonical and stable | `render(value, format, opts) -> text` | `:render_error` | deeta, jikan, hikisuu (help), kueri (SQL), sabi (Rust) |
| `encode` / `decode` | bytes to text in an encoding, and back | `encode(data, encoding) -> text` | `:decode_error` | deeta (`:base64`, `:base64url`, `:hex`, `:url`) |
| `hash` | a digest, in lowercase hex | `hash(data, algorithm, opts) -> text` | `:bad_option` | shomei (`:blake3`, `:sha256`, `:sha512`, `:sha1`, keyed with `key:` for HMAC) |
| `sign` / `verify?` | sign data; check a signature | `sign(data, secret) -> text` | `:bad_key` | shomei |
| `diff` | the differences between two values, as change records | `diff(a, b, opts) -> [change]` | none | deeta (structural, which the test runner uses), gitto (commits) |
| `merge` | combine `b` into `a` | `merge(a, b, opts) -> value` | `:conflict` | jisho (records, deep with `deep: true`), gitto (`merge(repo, ref)`) |

### 3.5 Time, logging, output, CLI

| Verb | Meaning | Spaces |
|---|---|---|
| `now` | the current instant | jikan |
| `since` / `until` | the duration from an instant to now, or from now to an instant | jikan |
| `add` | an instant moved by a duration (subtracting is adding a negative duration) | jikan |
| `sleep` | pause for a duration | jikan |
| `debug` / `info` / `warn` / `error` | a structured log line at that level | rogu |
| `say` | a line of program output on stdout | builtin |
| `fail` | not a verb: `raise :usage, "…"`, which `main` turns into a usage message and exit 64 | — |

`info` is both a log level (`rogu::info`) and the state verb (`fairu::info`). That is the one name
used with two meanings, and it is accepted because both are qualified and the shapes cannot be
confused: a log line takes a message, a state lookup takes a subject. Decision D5 offers the
alternative.

### 3.6 The collection verbs (the prelude, written bare)

These are Elixir's `Enum` and Ruby's `Enumerable` names, subject first (decision D2). Lists live in
`retsu`, maps and records in `jisho`, sets in `shuugou`, and the bare names are builtins that
dispatch on the value.

`map` · `filter` · `reject` · `reduce` · `find` · `count` · `sum` · `sort` · `sort_by` ·
`group_by` · `partition` · `chunk` · `windows` · `zip` · `unzip` · `flatten` · `flat_map` ·
`unique` · `take` · `drop` · `take_while` · `drop_while` · `first` · `last` · `rest` · `size` ·
`reverse` · `each` · `tally` · `min_by` · `max_by` · `index_of` · `join` · `split` ·
`contains?` · `empty?` · `any?` · `all?` · `none?` · `keys` · `values` · `entries`

`contains?(subject, x)` replaces four spellings in use today: retsu `contains` (126 sites),
`member?` (84), the string-only `contains?` (76) and shuugou `member` (14), for 313 external sites in
49 files. `empty?` replaces `retsu::is_empty` and `null?` (414 sites in 57 files).

## 4. The spaces

Each space below gives the bidama, its closed verb set, what the set covers and what it leaves out
on purpose, its surface in the new syntax, a short example, what it absorbs, and its runtime needs
on the house ladder (blue → tatara-lisp → Rust). **Rust primitives are moved, never copied**: most
already exist in `tatara-lisp-script/src/stdlib/` (regex, hash, encoding, toml, yaml, uuid, fs
temporaries, os, log, sops), and blue's own `sys.rs` took its exec and fs words from there before.

Names marked *new* were swept on 2026-10-19 with `rg --no-ignore -w -i` over the pleme-io tree,
finding 0 hits for `fairu`, `kankyou`, `jikan`, `hikisuu`, `rogu`, `heikou`, `tsuushin`, `jisho`,
`joujuu`, `himitsu`, `kurasuta` and `gitto`, and 1 for `habu`, a word list in
`caixa-aho-corasick`. The `naming` procedure and the `NAMES.md` row are still owed when each one
lands. `shiken` (16 hits), `kiroku` (25) and `fugou` (9) were rejected.

### 4.1 fairu (ファイル), files and paths, *new*

**Verbs:** `read`, `write`, `append`, `exists?`, `file?`, `dir?`, `list`, `walk`, `glob`, `copy`,
`move`, `delete`, `make_dir`, `with_temp_dir`, `with_temp_file`, `info`, `watch`. **Nouns (pure):**
`join`, `parent`, `name`, `stem`, `extension`, `absolute`, `relative`, `parts`, `home`, `current`.

**Completeness.** This set covers every whole-file operation Python's `pathlib`/`shutil`/`tempfile`,
Go's `os`/`io/fs`/`filepath` and Elixir's `File`/`Path` offer for scripts, and it covers every fs
call measured in the corpus. **Left out on purpose:** open file handles and seeking (streaming is
`stream` over a command or a future `fairu::stream`, added only when a program needs a file bigger
than memory, which no measured program does); permissions and ownership changes (nix and the module
system own them on this fleet); symlink creation (generated trees are nix's job); `chdir` (global
mutable state, and the evaluation engine could no longer cache by input; use the `cwd:` option).

```ruby
fairu::read(path, opts) -> Text
fairu::write(path, text, {atomic: true, parents: true, mode: nil}) -> nil
fairu::delete(path, {all: false}) -> nil
fairu::walk(root, {include: nil, exclude: [".git"], files: true, dirs: false}) -> [Text]
fairu::glob(pattern, {root: fairu::current}) -> [Text]
fairu::info(path) -> {kind:, size:, modified:, mode:}
fairu::with_temp_dir(fn(dir) ... end) -> value
```

```ruby
config = fairu::join(fairu::home, ".config", "tend", "config.yaml")
fairu::write(fairu::join(out, "live"), text)
stale = filter(fairu::walk(root, {dirs: true}), fn(p) fairu::name(p) == "target" end)
```

**Absorbs:** `read_file`, `write_file`, `append_file`, `shisutemu::read_or` (becomes
`fairu::read(p) rescue d`), `mkdir`/`mkdir_p` → `make_dir`, `rm` → `delete`, `rm_rf` →
`delete(p, {all: true})`, `rename_file` → `move`, `walk_dir` → `walk`, `glob`, `ls` → `list`,
`is_file?`/`is_dir?`/`path_exists`, `file_size`/`file_mtime_ms`/`shisutemu::file_age_ms` → `info`,
`path_join`/`path_dirname`/`path_basename`/`path_extension` → nouns, `cwd` → `current`,
`tehai::write_atomic` → `write`. The builtins stay as the primitive layer, which fairu calls. They
are switched off for programs by a rule (§8), never deleted.

**Runtime:** temporary directories (move `tmp-dir`/`tmp-file` from tatara-lisp-script `fs.rs`),
`absolute` (move `path-absolute`), an absolute-pattern `glob` fix in `sys.rs`, and `info` as one
primitive returning a record. Atomic `write` is blue (a temporary file beside the target, then
`rename_file`). `watch` is blue, polling `info` with a `jikan` interval, because the native file
watchers sit on C (macOS FSEvents) and CONTAIN THE C says to start with the lowest-ABI path.

### 4.2 shisutemu (システム), processes and the host, *rewritten*

**Verbs:** `run`, `capture`, `succeeds?`, `stream`, `pipe`, `spawn`, `wait`, `stop`, `which`,
`become`, `info` (the host: `{os:, arch:, host:, user:, home:, pid:}`), `exit` (with a status).
**Options for every running verb:** `cwd:`, `env:` (a record merged over the inherited
environment), `stdin:` (text), `timeout:` (a duration), `ok:` (the accepted statuses, default `[0]`,
`:any` to treat every status as data), `show:` (also stream output to the terminal), `on:` (a host:
run over ssh).

**Completeness.** These verbs cover subprocess (`run`, `check_output`, `Popen`, pipelines), Open3,
`os/exec` and Elixir's `System.cmd`/`Port`. **ssh is an option, not a space:** `run(cmd, args,
{on: "rio"})` sends the argv to the host with every argument quoted by the primitive. The hand-built
remote shell string, the one place quoting breaks, cannot be written. **Left out on purpose:**
running a shell script (`sh_exec` stays a waivable primitive, since `run("sh", ["-c", script])` is
the explicit form), and pseudo-terminals (no program needs one).

```ruby
shisutemu::run(command, args, opts) -> {status:, stdout:, stderr:, took:, command:}
shisutemu::capture(command, args, opts) -> Text
shisutemu::succeeds?(command, args, opts) -> Bool
shisutemu::stream(command, args, fn(line) ... end, opts) -> result
shisutemu::pipe([["nix", ["path-info", "-r", p]], ["sort", []]], opts) -> result
```

```ruby
rev = shisutemu::capture("git", ["rev-parse", "HEAD"], {cwd: repo})
shisutemu::run("nix", ["build", ".#blue"], {show: true, timeout: jikan::minutes(30)})
up = shisutemu::succeeds?("tailscale", ["status"], {timeout: jikan::seconds(3)})
```

**Absorbs:** `exec_capture`, `exec_check`, `exec_ok?`, `exec_with_env`, `exec_with_stdin`,
`exec_into` → `become`, `exit_with` → `exit`, `self_exe` (stays a noun), the accessors
`status_of`/`stdout_of`/`stderr_of` → record fields, and the 54 hand-written wrapper definitions in
31 files, for example `hyouka::capture` and `run_nix`, `kirikae::git_out`, `ukai::capture`,
`kueri::duckdb`, `tehai::probe`, `keiyu::run_via` (whose proxy becomes `env:`) and node-health's
`nh_*_failures`. `strip_ansi` moves to moji, `age_s` to jikan (`render` of a duration),
`last_nonempty_line` to moji and `short_rev` to gitto.

**Runtime:** one primitive, `process(spec)`, that takes a record `{argv, cwd, env, stdin, timeout_ms,
output: :capture | :inherit | :both}` and returns the result record. It replaces six exec builtins,
so the variety lives in blue and the Rust seam is one function. Add `process_spawn`, `process_wait`,
`process_signal` and `process_next_line` for `spawn`, `stop` and `stream`. `which` and `pipe` are
blue (`pipe` chains `stdin:` through captured stages, then a streamed variant once
`process_next_line` exists). The host record is moved from `os.rs`.

### 4.3 kankyou (環境), the environment, *new*

**Verbs:** `get`, `need`, `has?`, `list`, `read` (a dotenv file → a record, never applied to the
process). **Left out on purpose:** `put` and `delete` on the program's own environment, because a
global mutable environment is hidden state that breaks caching and every child that reads it. A
child receives `env:` instead.

```ruby
token = kankyou::need("GITHUB_TOKEN")
level = kankyou::get("BLUE_LOG") || "info"
local = kankyou::read(".env")
```

**Absorbs:** `getenv` (195 external sites with `env_required`, in 62 files), `env_required` →
`need`, and the `settei::env_*` helpers used for discovery. **Runtime:** none; it is blue over
`getenv`, plus a primitive listing the whole environment, moved from `env.rs`.

### 4.4 settei (設定), typed configuration, *extended*

**Verbs:** `read(app, defaults, opts) -> record` (defaults < `$XDG_CONFIG_HOME/<app>/<app>.yaml` <
`<APP>_*` environment, shikumi's tiers, each value's type taken from its default and checked),
`get`, `need`, `render` (the resolved record with the tier each value came from), `watch` (reload
on change). **Left out on purpose:** writing configuration, which home-manager and nix own.

```ruby
cfg = settei::read("tend", {interval: jikan::minutes(5), workspaces: []})
rogu::info("loaded", {interval: cfg.interval})
```

**Absorbs:** `settei::load` → `read`, `flag`/`setting` → fields, `coerce`/`same_kind?` (internal).

### 4.5 deeta (データ), data formats and encodings, *extended*

**Verbs:** `parse(text, format)`, `render(value, format, {pretty: false})`, `read(path)` (format
from the extension), `write(path, value)`, `encode(bytes, encoding)`, `decode(text, encoding)`,
`diff(a, b)`, `get(doc, path)` / `need` over a dotted path (the same as `json_at`; one of the two
names is kept, decision owed with canonical-forms). **Formats:** `:json`, `:yaml`, `:toml`, `:csv`
(records keyed by the header row), `:lisp` (tatara-lisp forms, blue's own AST), `:lines`.
**Encodings:** `:base64`, `:base64url`, `:hex`, `:url`.

**Completeness.** The formats cover every file the fleet reads or writes (flake.lock JSON, sops
YAML, Cargo and kijun TOML, DuckDB CSV results, tatara forms). **Left out on purpose:** XML (no
measured use; add it as a row when one appears) and binary formats (protobuf and msgpack belong
behind a forge-gen surface, not hand-written).

```ruby
lock = deeta::read("flake.lock")
fairu::write("out.json", deeta::render(report, :json, {pretty: true}))
rows = deeta::parse(shisutemu::capture("duckdb", ["-csv", "-c", sql]), :csv)
```

**Absorbs:** `json_parse` and `json_read` → `parse(_, :json)` returning records, `json_stringify`
→ `render`, `json_get`/`json_get_or` and `deeta::get_str`/`get_int`/`get_number`/`as_json`/
`is_doc` → field access (`doc.field`) or `get` over a path, `deeta::get_or` → `jisho`,
`deeta::pretty`/`yaml` → `render`, and `shinsuu::to_hex` for bytes. That is 392 field reads and 151
parse/render calls today. **Runtime:** move `yaml-parse`, `toml-parse`/`toml-stringify` and the
encoding words from tatara-lisp-script. CSV is blue (RFC 4180 is a small state machine; it moves to
Rust only if it is measurably slow).

### 4.6 jisho (辞書), maps and records, *new*

**Verbs:** `get`, `need`, `has?`, `put`, `delete`, `update`, `merge`, `select` (keep only the
listed keys), plus the nouns `keys`, `values`, `entries`, and `from_entries`. A record is a map
with keyword keys, so the same verbs serve both. **Absorbs:** `assoc` → `put`, `dissoc` →
`delete`, `map_entries` → `entries`, `zipmap`, `deeta::get_or`, `shuugou::lookup`,
`kirikae::assoc_all` → `merge`, and `haibi::entries_of`/`from_entries`. **Runtime:** none.

### 4.7 jikan (時間), instants and durations, *new*, over hizuke

**Verbs:** `now`, `since`, `until`, `add`, `sleep`, `parse(text, format)`, `render(value,
format)`. **Constructors:** `milliseconds`, `seconds`, `minutes`, `hours`, `days`. **Nouns:**
`year`, `month`, `day`, `hour`, `minute`, `second`, `weekday`, `zone`, `unix_seconds`, `today`,
`in_zone(t, name)`. **Formats:** `:rfc3339`, `:date`, `:human` (`3m12s`), or a strftime pattern.

hizuke stays the pure calendar engine underneath (proleptic Gregorian arithmetic, ISO weeks), and
jikan is the surface programs use. **Left out on purpose:** calendars other than Gregorian, and
leap seconds.

```ruby
start = jikan::now
shisutemu::run("nix", ["flake", "update"], {cwd: repo})
rogu::info("updated", {took: jikan::render(jikan::since(start), :human)})
```

**Absorbs:** `now`, `now_ms`, `now_ns`, `now_rfc3339`, `elapsed_since`, `sleep`, `sleep_ms` (all
stay as primitives), `shisutemu::age_s`, `hizuke::format_iso` → `render(_, :date)`. **Runtime:**
one primitive, `zone_offset(zone, unix_seconds)` from the `jiff` crate's bundled tz database (pure
Rust). Formatting and parsing are blue.

### 4.8 moji (文字), text, *extended*

Text keeps its verbs and gains **patterns**: `moji::pattern(text)` builds a compiled regex value
(raising `:parse_error`), and `find`, `find_all`, `replace`, `split`, `matches?` and `contains?`
each accept a literal string or a pattern. `find` returns a match record `{text:, start:, groups:}`
or nil, the same meaning as the collection `find`.

**Renames** (the predicate law): `is_blank` → `blank?`, `is_space` → `space?`, `is_digit` →
`digit?`, `is_alpha` → `letter?`, `is_alnum` → `alphanumeric?`, `is_hex` → `hex?`, `is_upper` →
`upper?`, `is_lower` → `lower?`, `includes` → `contains?`, `starts_with`/`ends_with` → the builtins
`starts_with?`/`ends_with?`, `glob_match?` → `fairu::matches?` for paths. **Absorbs**
`shisutemu::strip_ansi` and `last_nonempty_line`. **Runtime:** move `regex.rs` (the `regex` crate
is pure Rust).

### 4.9 kyohi (拒否), the ledger of error kinds, *rewritten*

With `raise`/`rescue` in the language, kyohi stops being a parallel error model and becomes the
**closed ledger of kinds**. Each row is `{kind:, meaning:, exit_status:, retryable:}`, for example
`:not_found` (exit 66), `:usage` (64), `:hold` (75, EX_TEMPFAIL), `:timeout` (retryable),
`:command_failed`, `:parse_error` (65), `:conflict` (retryable). `main` maps an uncaught kind to its
exit status. `heikou::retry` reads `retryable` by default. Every `raise` in a space package must
name a ledger kind (§5.4). Collect-every-problem validation keeps one verb, `kyohi::check(subject, rules)`,
which returns every finding as a list (empty when sound); `kyohi::enforce(subject, rules, opts)` is its
raising form and throws a single error carrying the list (`kind: :first` takes the first finding's kind). **Absorbs:** `refusal`, `refuse` → `enforce`, `ok`,
`refused`, `ok?`, `value`, `refusal_of` (the result-wrapper half is retired, since rescue does that
job) and the per-package refusal families (kueri 16, nisshi 12, raifusaikuru 12, kinji 8, …;
`theory/BLUE-GAPS.md` G4).

### 4.10 hikisuu (引数), command-line arguments, *new*

**Verbs:** `parse(args, spec) -> record`, `render(spec) -> help text`. A spec is a record:
`about`, `commands` (a list, or records with their own `flags`), `flags` (name → default; the type
comes from the default, a duration default accepts `30s`/`5m`), and `positional`. `--help` and `-h`
print `render(spec)` and exit 0. A bad flag raises `:usage`, which `main` turns into the usage text
on stderr and exit 64. Flag names come from keys (`dry_run` → `--dry-run`).

```ruby
def main(args)
  opts = hikisuu::parse(args, {
    about: "clean a node's build caches",
    commands: [:rust, :nix, :all],
    flags: {dry_run: false, older_than: jikan::days(3)},
  })
  souji::clean(opts.command, opts)
end
```

**Absorbs:** `argv_get`, and the hand-written parsers: 124 `"--flag"` literals in 26 files, 12
`parse`/`parse_flags` definitions (souji, tehai, heni, kijun, kirikae's `node_arg`) and the usage
printing in 18 `main` definitions. **Runtime:** none.

### 4.11 rogu (ログ), logging, and `say`, *new*

**Verbs:** `debug`, `info`, `warn`, `error`, each `(message, fields)`. Output goes to stderr as one
JSON object per line (`{at:, level:, message:, …fields}`), or as aligned text when stderr is a
terminal. The level comes from `BLUE_LOG`. A `himitsu` secret in the fields renders `<secret>`.
**`say(x)`** is a new builtin: `to_s(x)` plus a newline, written to stdout. It is the one spelling
for a program's output, which settles the `println`-quotes-strings trap.

**Absorbs:** `write_stderr` used for diagnostics, and `println`/`print`/`display` in stored files
(48 output calls in 27 files). `write_stdout` stays the raw primitive. **Runtime:** none
(`isatty` moved from `io.rs`).

### 4.12 heikou (並行), concurrency, timeouts and retry, *new*

**Verbs:** `map(xs, f, {limit: 8})` (bounded parallel map, results in order), `all(fs)`, `run(f,
{timeout:})`, `spawn(f)` / `wait` / `stop` over blue processes, and `retry(f, policy)`. A policy is
a record: `{times: 5, base: jikan::seconds(1), cap: jikan::minutes(1), on: :retryable}`, with
exponential backoff and jitter. **Left out on purpose:** shared-memory primitives (blue processes
share nothing, by design) and channels (tatara's `chan` has no blue spelling).

**Absorbs:** `kirikae::policy`/`backoff_ms` → `retry` policies. **Runtime:** none; it is built on
`spawn`/`receive` with a timeout, and depends on processes running under `blue run`
(`AUTHORING.md`, "Missing today").

### 4.13 tsuushin (通信), the HTTP client, *new*

**Verbs:** `request(method, url, opts) -> {status:, headers:, body:, took:}` (any status is data),
`read(url)` (the GET body, raising `:http_status` outside 2xx), and the store verbs over a REST base:
`get` (parsed JSON or nil on 404), `need`, `list` (follows `Link: rel="next"`), `create` (POST),
`update` (GET, `f`, then PATCH with `If-Match`), `put`, `delete`, plus `exists?` (HEAD) and
`stream`. **Options:** `headers:`, `token:` (sent as a bearer token, never logged), `query:`,
`json:` (a body sent as JSON), `timeout:` and `retry:` (a heikou policy). **Left out on purpose:**
cookies and sessions (no use on this fleet) and HTTP/2 (HTTP/1.1 covers every API we call).

**Runtime:** TLS is the gap, since `http_request` refuses https today. That is decision D3. Until it
lands, `tsuushin` and the spaces on it (`habu`) speak through a process (`curl` supplied by nix)
behind the same surface: a typed fallback, not a second API.

### 4.14 shomei (署名), hashing and signatures, *extended*

**Verbs:** `hash(data, algorithm, {key: nil})`, `sign(data, secret)`, `verify?(data, signature,
public)`, the noun `keypair(seed)`, and the hash-chain nouns kept as they are. **Renames:**
`hash_message` → `hash(_, :blake3)`, `sign_message` → `sign`, `verify_message` → `verify?`,
`signing_keypair` → `keypair`, `is_hash_hex` → `hash?`. **Runtime:** move `sha256`, `sha512`,
`sha1` and `hmac-sha256` from tatara-lisp-script (`sha2` is already a blue-runtime dependency) and
`random-bytes` (getrandom), which also gives blue the entropy source it lacks
(`ed25519_keypair`'s caller-supplied seed).

### 4.15 Testing, owned by the runner

**Verbs (inside `test` blocks):** `assert` (unchanged spelling), `snapshot(value, name)`,
`fixture(name)`, `raises?(kind, f)`, plus `fairu::with_temp_dir`. `assert a == b` keeps its exact
spelling and its failure prints `deeta::diff(a, b)`: the paths that differ, the expected value and
the actual one. pytest's assertion rewriting is the model. `snapshot` compares against
`snapshots/<file>/<name>.b` (blue literals, readable in review), and `blue test --update` rewrites
them. `fixture` reads `fixtures/<name>` beside the test file.

**Absorbs:** the teardown pattern (`rm_rf`, 30 sites in 13 files, and `mkdir_p`, 29 in 23, are
mostly test scaffolding) and `heni`'s fresh-copy logic. **Payoff without a rewrite:** 4,715 lines
with `assert … ==` in 116 files get a diff on failure, with no change to their source.

### 4.16 hyouka (評価), nix, *extended*

**Verbs:** `eval(installable, opts) -> value`, `build(installable, opts) -> [out path]`,
`plan(installable) -> {build:, fetch:}` (the dry run), `info(path) -> path info`, `copy(paths, {to:
host})`, `lock(flake, {inputs: [...]}) -> changed inputs` (`nix flake update`, which is blue's own
`lock` verb), and `get(flake_lock, input)` for a pinned revision. **Left out on purpose:**
`develop`, `shell` and `profile install`. The first two are interactive. The third is forbidden on
this fleet, because `~/.nix-profile` shadows home-manager.

**Absorbs:** `hyouka::eval_json`/`eval_raw` → `eval`, `plan_build` → `plan`, `run_nix`/`capture` →
shisutemu, and `souji::nix_argv`. **Runtime:** none (a process boundary).

### 4.17 gitto (ギット), git, *new*

**Verbs:** `info(repo)` (`{branch:, head:, ahead:, behind:, clean?:, changes:}`), `get(repo, ref, opts)`
(a commit record or nil), `list(repo, {of: :branches | :tags | :commits | :remotes | :worktrees, limit:, ref:})`, `read(repo,
path, {at: ref})`, `exists?(repo, ref)`, `diff(repo, a, b)`, `commit(repo, message, {paths:,
author:})`, `fetch(repo)`, `merge(repo, ref, {fast_forward_only: true})`, `push(repo, opts)` (a
rebase-or-refuse shape, never a force by default), `clone(url, dir)`, and `create`/`delete` for
branches. `commit`, `fetch`, `push` and `clone` are git's own verbs and join the master table as rows
scoped to this space. **Left out on purpose:** interactive rebase, a plain `pull` (the house rule is
fetch plus a fast-forward-only merge, and `merge`'s default encodes it), and `--force` (an option
that needs a reason string).

**Absorbs:** `kirikae::git_out`/`checkout_of`, `shisutemu::short_rev` → `jikan`-independent noun
`gitto::short(rev)`, and the git calls in kijun and node-facts. **Runtime:** none (the git CLI
through shisutemu, not libgit2, which is C).

### 4.18 kurasuta (クラスタ), Kubernetes reads, *new*

**Verbs:** `list(kind, opts)`, `get(kind, name, opts)`, `need`, `watch(kind, f, opts)`, `read(pod,
{container:, since:})` (logs) and `info(opts)`. **The required option is `context:`.** A call without
it raises `:bad_option`, because this kubeconfig also holds akeyless production contexts and the
house rule is to pass `--context` every time. **Left out on purpose:** `put`, `create`, `update` and
`delete`. Clusters change through GitOps, and blue already says so (`blue diff`, no `blue apply`).
The completeness argument is the doctrine: every read a program makes is here, and every write
belongs to a reconciler.

**Runtime:** `kubectl get -o json` through shisutemu first. A direct API client over tsuushin
(needs TLS, a kubeconfig parse and an exec credential plugin) comes later, behind the same surface.

### 4.19 habu (ハブ), the GitHub API, *new*

**Verbs:** the store verbs over `https://api.github.com`: `list(path, opts)` (every page),
`get`/`need`, `create`, `update`, `put`, `delete`, and `query(graphql, variables)`. The token comes
from `GITHUB_TOKEN` or the app-token directory (`GITHUB_APP_TOKEN_DIR`), in that order.
**Absorbs:** the `gh api` calls in `nix/nodes/ryn/github-org-repos/*.b`. **Runtime:** tsuushin (D3),
and the `gh` CLI as the fallback until then.

### 4.20 joujuu (常駐), services, *new*

**Verbs:** `list(opts)`, `info(unit)`, `start`, `stop`, `restart`, `read(unit, {since:})` (the
journal, or the launchd log) and `plan` (what a restart would touch). One surface spans systemd and
launchd. The launchd half queries `gui/<uid>` for user agents, so the "invisible over ssh" trap in
`~/.claude/CLAUDE.md`'s probe table cannot happen. **Left out on purpose:** `enable`, `disable` and
writing unit files, which nix and home-manager own. **Runtime:** none (systemctl and launchctl
through shisutemu).

### 4.21 himitsu (秘密), secrets, *new*

**Verbs:** `read("secrets.yaml#github/token") -> Secret`, `get`/`need`/`has?` over a sops file's
keys, `list(file)` (keys only), `put(file, key, value)` (`sops set`), and the noun `reveal(secret)
-> Text`. A Secret renders as `<secret>` everywhere except through `reveal`. **Runtime:** the `sops`
binary through shisutemu (move `sops-extract`'s argv shape).

### 4.22 Unchanged spaces, conformed

kazu, toukei, junjo, shuugou, retsu, hizuke, kueri, teeburu, kyuuji and sabi keep their subjects.
They are conformed to §2: predicates gain `?` (`kazu::even` → the builtin `even?`, `junjo::is_sorted`
→ `sorted?`, `shuugou::subset` → `subset?`, `hizuke::is_leap` → `leap?`), arguments go subject-first
(D2), and the query packages expose `query`. The domain packages (ongaku, kikagaku, rittai, zumen,
seimei, …) are not spaces. They declare no space, and the gate does not apply to them.

### 4.23 Excluded spaces

| Space | Why it has no package |
|---|---|
| ssh | it is the `on:` option of shisutemu (§4.2) |
| templating | interpolation and heredocs cover every measured site (0 template files today); a `hinagata` space becomes a row when a program needs templates loaded from files |
| tatara-lisp interop | blue's AST is tatara-lisp: `deeta::parse(text, :lisp)` / `render`, and the existing `quote`/`eval` |
| a database ORM | kueri (DuckDB) and teeburu (PostgreSQL) answer `query`; haibi generates the schema |

## 5. The gate: the vocabulary is enforced, not advised

The house's all-variants shape is this: a matrix that fails the build when a variant lands without
a row. Here it is applied to verbs.

### 5.1 One source of truth

`bidamas/mokuroku/verbs.b` (mokuroku already renders `CATALOG.md` and owns the collision gate)
holds three kinds of row, as blue data:

```ruby
verb(:read, {
  meaning: "the whole content of a source",
  shape: "read(source, opts) -> content",
  raises: [:not_found, :permission_denied],
  laws: [:write_then_read, :read_absent_raises],
})

space(:files, {
  package: "fairu",
  verbs: [:read, :write, :append, :exists?, :list, :walk, :glob, :copy, :move, :delete,
          :info, :watch],
  compounds: [:make_dir, :with_temp_dir, :with_temp_file],
  nouns: [:join, :parent, :name, :stem, :extension, :absolute, :relative, :parts, :home,
          :current],
  predicates: [:file?, :dir?, :matches?],
  excluded: [
    {verb: :open, why: "no measured program reads a file larger than memory"},
    {verb: :chdir, why: "global mutable state; pass cwd: instead"},
  ],
})

kind(:not_found, {exit_status: 66, retryable: false})
```

The package ties itself to its row with one new Bluefile word, `space("files")` (one row in
`blue-lang-pkg`'s `WORDS` table). The master table in §3 is then **generated** from these rows
(`generate("stdlib-verbs", "docs/STDLIB-VERBS.md", …)`) and gated fresh, like `REFERENCE.md`.

### 5.2 The matrix check: `checks.bidama-verbs`

A blue program over the rows and the catalogue fails the build, naming each cell, when:

1. a space's package lacks a declared verb, compound, noun or predicate, or defines it with an arity
   outside the verb's shape;
2. a space's package defines a public name that is not one of its rows (an ad-hoc function);
3. a space declares a verb that is not in the master table;
4. a master verb is implemented by no space (a dead row);
5. an `excluded` entry has no `why`, or names a verb the space also implements.

Item 2 needs private definitions, since helpers such as moji's `split_words` are public today
(every `def` is exported). Until a `defp` (or equivalent) lands, a space lists its helpers in a
`helpers:` field, and the field's length is a ratchet that can only shrink.

### 5.3 The laws: one meaning, proved per space

A verb row names laws. A law is a blue property test parameterised by a **space adapter**: a record
of the space's functions plus a fixture (a temp dir for fairu, a map for jisho, an environment
record for kankyou, recorded responses for habu and kurasuta). The check `checks.verb-laws` runs
every law against every space that implements the verb, which is the same mechanism as okite's laws,
one level up. The first laws:

| Law | Holds for |
|---|---|
| `get(s, absent)` is nil, and `need(s, absent)` raises `:not_found` naming the key | every store |
| `has?(s, k) == (get(s, k) != nil)` | every store |
| `put(s, k, v)` then `get(s, k) == v` | every store with `put` |
| `delete` twice is the same as once, and the second returns nil | every space with `delete` |
| `write(t, x)` then `read(t) == x` | fairu, deeta, himitsu |
| `parse(render(v, f), f) == v` | deeta (every format), jikan |
| `list` is sorted and has no duplicate keys | every space with `list` |
| `run` with a status in `ok:` never raises; with one outside, it raises `:command_failed` carrying the result | shisutemu |
| a failing stage of `pipe` raises, naming the stage | shisutemu |
| an unknown option raises `:bad_option` listing the accepted keys | every verb with options |

### 5.4 Kinds are rows too

A check-stage rule refuses `raise :x, …` inside a space package when `:x` is not a `kind` row, so the
set of errors a program can rescue from the standard library is closed, documented and mapped to an
exit status.

### 5.5 Each gate goes red once

Before it lands, each gate is broken on purpose and seen to fail with the fault named: delete
`fairu::glob`, add a `fairu::slurp`, declare `:fetch` on files, drop a `why`, and make `delete` raise
on an absent path. Those are the five red runs.

## 6. Inventory: blue today against the spaces

| Domain | State | What exists | The gap |
|---|---|---|---|
| strings | **present**, renames owed | builtins (split, join, trim, replace, `starts_with?`, `text_index`); moji (62 definitions) | regex absent; predicates spelled `is_x`; moji duplicates `starts_with?`/`ends_with?` |
| lists | **present**, inconsistent | builtins (Lisp argument order); retsu (49, total and data-first); ronri (quantifiers); junjo (sorting) | four spellings of `contains?`, two of `empty?`; function-first builtins against data-first retsu (D2) |
| maps and records | **partial** | `get`, `assoc`, `dissoc`, `map_entries`, `zipmap`; `deeta::get_or` | no `merge`, `update`, `select`, `keys`; records arrive with canonical-forms |
| sets | **present** | shuugou (29) | predicates without `?`; `group_by` returns pairs while `map_entries` exists |
| files and paths | **partial** | 17 builtins; `shisutemu::read_or`, `file_age_ms` | absolute `glob` broken; no temp dirs, atomic write (hand-rolled in tehai), sorted walk, `info` record, copy or watch |
| processes | **partial** | 7 exec builtins and alist accessors | no cwd, timeout, streaming, spawn/wait/stop, pipe or which; 54 wrapper definitions in 31 files |
| environment | **partial** | `getenv`, `env_required` | no listing, dotenv or `need` spelling |
| typed config | **partial** | settei (18: tiers, coercion) | not in the verb shape; undocumented (empty catalog line) |
| data formats | **partial** | JSON builtins; deeta (19: JSON reads, YAML render) | YAML/TOML/CSV parse, encodings and records absent |
| time | **partial** | `now*`, `sleep*`, `elapsed_since`; hizuke (46, pure calendar) | no instant or duration values, time zones, parse or render |
| regex | **missing** | `moji::glob_match?` only | everything (move `regex.rs`) |
| HTTP client | **partial** | `http_request` (HTTP/1.1, http only) | TLS, redirects, JSON helpers, pagination, retry |
| HTTP server | **present** | `http_listen`/`http_next_request`/`http_respond`; kyuuji (14) | verb conformance only |
| CLI parsing | **missing** | `argv`, `argv_get` | hand-written parsers in 26 files |
| logging | **missing** | `write_stderr` | levels, structure, a terminal mode |
| testing | **partial** | `test`, `assert`, `--coverage`, heni (mutation) | diffs, snapshots, fixtures, temp dirs, `raises?` |
| errors and retry | **partial**, in flight | `throw`/`error`/`try`; kyohi (10) | raise/rescue (canonical-forms); a kinds ledger; retry |
| concurrency | **partial** | `spawn`, `receive`, supervisors | parallel map, `all`, timeouts as a verb |
| hashing and encoding | **partial** | `blake3_hex`, Ed25519; shomei (16); shinsuu (base conversion) | sha256/512, hmac, base64/hex/url, entropy |
| templating | **excluded** | interpolation | — |
| math and stats | **present** | kazu (33), toukei (44), kinji (50), gyouretsu (55) | predicate renames only |
| nix | **partial** | hyouka (25), kirikae (52), tehai (17), nikkusu (source as data) | the verb shape; `build`, `copy`, `lock` |
| git | **missing** | ad-hoc calls (kirikae `git_out`) | the space |
| Kubernetes reads | **missing** | `blue diff` (CLI, Rust) | the space |
| GitHub | **missing** | `gh` calls in nix's github-org-repos | the space |
| ssh | **missing** | tehai and keiyu build argv by hand | `on:` |
| services | **missing** | node-health's hand-written systemctl calls | the space |
| secrets | **missing** | — | the space and the Secret value |
| tatara-lisp interop | **present** | blue's AST is tatara-lisp | the `:lisp` format row |
| SQL | **present** | kueri (199), teeburu (8), `pg_*` | `query` naming |

## 7. Renames: the names the catalogue already has

Every rename goes through the existing machinery, not a text replace. `blue migrate` rewrites
callers on the resolved tree (it proves each file's tree unchanged apart from the rename), the old
name stays as a `legacy_names` bridge until the package's next minor version (B0021 reports a
caller still on it), and `blue check --fix` applies the machine-applicable cases.

| Old | Canonical | Fix |
|---|---|---|
| `retsu::is_empty`, `null?` | `empty?` | machine-applicable |
| `retsu::contains(xs, v)`, `member?(v, xs)`, `shuugou::member(xs, v)`, `moji::includes(s, t)` | `contains?(subject, x)` | machine-applicable (`member?` swaps its arguments) |
| every `is_x` definition (61 definitions, 416 external references) | `x?` | machine-applicable |
| `retsu::find_first`, `ronri::find_by` | `find` | machine-applicable |
| `retsu::count_where`, `ronri::count_if` | `count(xs, f)` | machine-applicable |
| `retsu::take_n`/`drop_n` | `take`/`drop` (subject-first under D2) | machine-applicable |
| `ronri::every`/`any`/`none`, `every?` | `all?`/`any?`/`none?` | machine-applicable |
| `shisutemu::status_of(c)`, `stdout_of(c)`, `stderr_of(c)` | `c.status`, `c.stdout`, `c.stderr` once `c` comes from `run(..., {ok: :any})` | machine-applicable when the capture is bound once and read only through the accessors; otherwise maybe-incorrect |
| `exec_capture(c, a…)` | `shisutemu::run(c, [a…], {ok: :any})` | machine-applicable (`ok: :any` keeps the never-raise meaning) |
| `exec_check(c, a…)` | `shisutemu::run(c, [a…], {ok: :any, show: true}).status` | machine-applicable |
| `exec_ok?(c, a…)` | `shisutemu::succeeds?(c, [a…])` | machine-applicable |
| `shisutemu::read_or(p, d)` | `fairu::read(p) rescue d` | machine-applicable |
| `read_file`, `write_file`, `append_file` | `fairu::read`/`write`/`append` | write becomes atomic (D4); maybe-incorrect for a path under `/proc` or `/sys` |
| `rm(p)` | `fairu::delete(p)` | maybe-incorrect: `rm` raised on absence, `delete` does not |
| `path_join`, `path_dirname`, `path_basename`, `path_extension`, `path_exists` | `fairu::join`, `parent`, `name`, `extension`, `exists?` | machine-applicable |
| `getenv(n)`, `getenv(n, d)`, `env_required(n)` | `kankyou::get(n)`, `kankyou::get(n) \|\| d`, `kankyou::need(n)` | machine-applicable (`\|\|` differs only for a variable set to the empty string, which getenv already returns as text) |
| `json_parse`, `json_read` | `deeta::parse(t, :json)` | maybe-incorrect: objects become records, not pair lists |
| `json_get(o, k)`, `deeta::get_str(o, k, d)` | `o.k`, `deeta::get(o, k) \|\| d` | maybe-incorrect (the typed defaults) |
| `json_stringify`, `deeta::pretty`, `deeta::yaml` | `deeta::render(v, :json)`, `{pretty: true}`, `:yaml` | machine-applicable |
| `now_ms` arithmetic with `elapsed_since` | `jikan::since(start)` | maybe-incorrect |
| `println(x)`, `print(x)` in a stored file | `say(x)` | maybe-incorrect: strings lose their quotes, which is the point |
| `shomei::hash_message`, `sign_message`, `verify_message`, `signing_keypair` | `hash(_, :blake3)`, `sign`, `verify?`, `keypair` | machine-applicable |
| `hyouka::eval_json`, `plan_build` | `eval`, `plan` | machine-applicable |
| `settei::load` | `settei::read` | machine-applicable |
| `kyohi::refuse(rs)` | `kyohi::enforce(rs, [(r) -> r], {kind: :first})` | machine-applicable |

The raw builtins are **switched off for programs, never deleted**: `exec_capture`, `read_file` and the
rest stay bound, because the space packages are built on them, and outside those packages a rule
refuses them with a fix (§8). The legacy names are the shrinking bridge.

## 8. Rollout: waves, the rules that steer, and what each pays

The codes are assigned when each rule lands, after canonical-forms' B0024+ block, so the rules are
named here by slug. Each rule is a row in `blue_lang_check::RULES`: it starts as a ratchet (counted
by `blue census`, the count pinned) and becomes an error when the count reaches zero. The one
escape is the usual `# waive CODE: reason`.

Measured payoff = the external call sites the wave rewrites (the defining package's own
references are excluded), from §9's census.

| Wave | Packages | Steering rules (slug → fix) | Depends on | Payoff (sites / files) |
|---|---|---|---|---|
| **W0** the vocabulary and the gate | `mokuroku::verbs` rows, the `space` Bluefile word, `checks.bidama-verbs` and `verb-laws` (ratchet), the generated table | `predicate-without-question-mark` (`is_x` → `x?`); `parallel-variant` (a new `_or`/`_or_nil`/`try_` definition refused) | canonical-forms merged | 416 references to 61 `is_x` definitions in 60 files |
| **W1** collections and the test runner | `contains?`/`empty?`/`all?`/`find`/`count` unified; retsu, shuugou, ronri and junjo conformed; the runner's `assert` diff, `snapshot`, `fixture`, `raises?` | `collection-synonym` (the four spellings of `contains?`, two of `empty?` → one); D2's argument-order flip if taken, in the same rewrite | W0; D2 | 313 `contains?` + 414 `empty?` = 727 sites; **4,715 asserts gain diffs with no rewrite**; D2 itself touches 5,309 sites in 147 files |
| **W2** host: files, processes, environment | fairu, shisutemu (the `process` primitive, temp dirs, `info`), kankyou, jisho | `raw-process` (`exec_*` + `status_of`/`stdout_of` outside shisutemu → `run`/`capture`); `raw-file` (`read_file`, `path_*` and friends outside fairu → fairu); `raw-env` (`getenv` → kankyou) | W0; records | process 60 + 97 accessors (31 files, 54 wrapper definitions); files 281 (65 files); paths 220 (43); env 195 (62) |
| **W3** data and errors | deeta (parse/render/read/write for json, yaml, toml, csv, lisp; encode/decode), the kyohi kinds ledger | `raw-json-field` (`json_get`/`deeta::get_*` → field access); `kind-not-in-ledger` (inside space packages) | W2; raise/rescue; `json_at` | 392 field reads (33 files), 151 parse/render (38); 164 `throw` + 100 kyohi sites move onto the ledger |
| **W4** time, CLI, logging, output | jikan, hikisuu, rogu, `say` | `hand-rolled-flags` (a definition comparing args to `"--…"` literals → hikisuu; warning, no autofix); `println-in-file` (→ `say`); `unit-in-option-name` (`timeout_ms:` → `timeout: jikan::…`) | W2, W3 | time 54 (20 files); flags 124 literals in 26 files, 12 parsers, 18 `main`s; output 48 (27) |
| **W5** network and primitives moved from tatara-lisp-script | tsuushin, heikou, moji patterns, shomei hashes, deeta encodings | `raw-http` (`http_request` outside tsuushin) | D3 for https | small today (`http_request` 2, hashes 8, `glob_match?` 9); it unlocks W6 |
| **W6** house batteries | hyouka (conformed), gitto, kurasuta, habu, joujuu, himitsu | `raw-tool` (a `shisutemu::run` of `git`/`nix`/`kubectl`/`gh`/`systemctl`/`launchctl`/`sops` outside its space → the space verb; warning first) | W2–W5 | the tool calls in kirikae, kijun, tehai, souji, node-health, node-facts and github-org-repos; the 54 wrappers again, now by tool |

**Why this order.** W0 and W1 change names only and need nothing new from the runtime. W1's diff is
a runner change with the largest measured payoff and no rewrite at all. W2 is the first wave that
needs Rust (one `process` primitive and temp dirs), and every later space is built on it. W3 needs the
error model and records from canonical-forms. W5's https decision gates W6's GitHub and Kubernetes
API paths, which ship on process fallbacks first, so W6 does not have to wait for it.

### The five largest payoffs

| # | Change | Sites | Files |
|---|---|---|---|
| 1 | `assert a == b` prints a structural diff (runner only, no rewrite) | 4,715 assert lines | 116 |
| 2 | one spelling each for `contains?` and `empty?` | 727 | 57 |
| 3 | fairu: files and paths | 501 | 65 |
| 4 | deeta records instead of pair-list reads | 543 (392 reads + 151 parse/render) | 38 |
| 5 | the predicate law (`is_x` → `x?`) | 416 references to 61 definitions | 60 |

These are followed by kankyou (195 sites in 62 files) and shisutemu (157 sites, plus 54 wrapper
definitions in 31 files). D2, if taken, is the largest rewrite of all (5,309 sites) and is a cost,
not a payoff. Its return is that every pipeline reads left to right.

## 9. Method and denominators

- **Corpus:** every `.b` file under `~/code/github/pleme-io` found by `rg --no-ignore --files -g
  '*.b'` (1,326), minus the eight blue worktrees (`blue-canon`, `blue-ns`, `blue-te`, `blue-tk`,
  `blue-tm`, `blue-tn`, `blue-tp`, `blue-fmtfix`), which copy `blue/`, and minus `.claude/worktrees`:
  **240 files** in blue, makoto, nix, nupastel, arnes, blackmatter-akeyless, ola-mundo and
  substrate.
- **Resolution:** `blue ast --resolved --json` (blue 0.0.73) on each file with `BLUE_PATH` set to
  blue's and makoto's bidamas. 239 of 240 resolved. The one failure is
  `blue/spec/bidamas/sp_uses/sp_uses.b`, a conformance fixture that imports a missing package on
  purpose. 72,407 references were loaded into DuckDB, and `blue/spec/**` was excluded from usage
  counts.
- **External** = a reference outside the file of the bidama that defines it, so a package's own tests
  do not inflate its reach. Builtins are counted everywhere.
- **Line counts** (`assert … ==`, `"--flag"` literals, `try(`) come from `rg --no-ignore -c` over the
  same eight repositories, excluding `blue/spec`. They count lines, not calls.
- **Not measured:** call sites in private repos outside pleme-io, and calls that build a command name
  at run time (most exec calls pass a variable, so the per-tool split in W6 is by the wrappers'
  names, not by argv).

## 10. Operator decisions

Only the genuine trade-offs are listed here. Everything else above is decided against a stated
rule.

- **D1, the names at call sites.** Option (a): goi package names (`fairu::read`, `shisutemu::run`),
  which follow NAMING's goi rule and the namespace decision of 2026-09-29 (the qualifier is the
  package name, with no aliases). Option (b): English space names (`file::read`, `process::run`),
  which read with no learning, at the price of an exception to goi and an alias layer that decision
  closed. **Recommendation: (a).** A reader learns about 20 nouns once, the verbs carry the meaning,
  and `rg 'fairu::'` finds every file operation.
- **D2, collection argument order.** Option (a): flip `map`, `filter`, `reduce`, `take`, `drop`,
  `nth`, `member?` and the rest to subject-first, so pipes read left to right as in Elixir and every
  verb in the library has one argument order. That rewrites 5,309 sites in 147 files, all of them
  mechanical on the resolved tree. Option (b): keep Lisp order for the prelude and subject-first
  everywhere else, living with two orders. **Recommendation: (a), done inside canonical-forms' rewrite
  of every `.b` file**, so the corpus is rewritten once rather than twice.
- **D3, TLS for https.** Option (a): rustls with the pure-Rust RustCrypto provider, which matches
  `crypto.rs`'s pure, C-free stance but is younger and less audited. Option (b): rustls with
  aws-lc-rs or ring, which are mature but are C and assembly behind the seam. Option (c): no TLS in
  the runtime, with `curl` through shisutemu permanently. **Recommendation: (a)**, with (c) as the
  typed fallback while it lands.
- **D4, `write` is atomic by default.** A temporary file plus a rename changes the file's inode. That
  breaks hard links and writes through to a symlink's target differently, and it fails on `/proc`
  and `/sys`. **Recommendation:** atomic by default, with `{atomic: false}` for the rare in-place
  write, since a torn file after a crash is the worse bad state.
- **D5, the one shared name.** `info` is both a log level and the state verb. Option (a): keep both,
  which are qualified and differently shaped. Option (b): rename the state verb to `status`, which
  reads well for git and services and badly for a file's stat. **Recommendation: (a).**

## 11. UNFINISHED: what this design still owes

Three sections were requested and are not yet written. Their measurements are recorded here so the
next pass starts from them. Counts are occurrences / files / repos over `~/code/github/pleme-io`
`*.rs` (25,911 files in 704 repos, measured 2026-10-19), and include vendored OSS (`caixa-*`,
`gitoxide`, `vector`).

**§11a, the house's Rust patterns mapped to blue batteries.** Each line gives the pattern, its
frequency, then the space that covers it:

- serde: derived on 20,397 types, depended on in 473 repos → deeta.
- thiserror and anyhow: 359 and 210 repos, `.context(` 3,054 times, `bail!` 2,128 → raise/rescue
  plus kyohi.
- tokio: `spawn` 1,075, `mpsc` 1,187, `select!` 259, `time::timeout` 388; 249 repos → heikou plus
  mailboxes.
- clap: `#[arg(` 5,238; 244 repos → hikisuu.
- tracing: `info!` 7,220, `#[instrument` 1,396; 232 repos → rogu, plus a `with_span`.
- reqwest and todoku: 112 and 15 repos → tsuushin. tsuushin should adopt todoku's retry, which
  honours Retry-After and retries only idempotent methods.
- shikumi: `TieredConfig` 765; 98 repos → settei.
- schemars: `JsonSchema` derived on 2,824 types; 84 repos → a JSON-schema `render` of a record shape
  (haibi's `schema_of` exists).
- axum: `.route(` 1,050; 73 repos → kyuuji.
- rmcp: about 50 MCP servers in 45 repos → kyuuji `serve` with an MCP protocol. This needs a stdin
  line primitive, since blue cannot read stdin today.
- kube-rs: `Controller::new` 371; 37 repos → kurasuta plus vigy.
- sqlx and SeaORM: 30 and 26 repos; `DeriveEntityModel` 152, `Entity::find` 588, `Column::` 1,600,
  `MigrationTrait` 136 → teeburu, extended into the data layer.
- octocrab: 11 repos → habu.

The data-layer design is owed. The candidate verbs are `connect`, `query`, `list`, `get`/`need`,
`create`, `put`, `update`, `delete`, `with_transaction`, `migrate` and `plan`. The schema would come
from the Bluefile `service(..., {schema:})` rows. haibi already renders the SQL and the shinka
migration from those rows, and could render keifu changesets and SeaORM entities from them too, so
blue and Rust read one schema.

**§12, the web, end to end.** The measurement is still running. The working recommendation is a
blue-native component model expressed as data, with renderers chosen by placement (fueki): HTML on
the server first, generated React/TSX second, and WASM later. That choice is operator decision D6,
and the UI package name `gamen` (画面) swept clean. The server side extends kyuuji with `serve`,
`respond`, `redirect` and `stream`, plus CORS and CSP defaults.

**§13, the tatara-lisp domain vocabularies.** These are 595 `TataraDomain` derives (about 520
keywords in 33 repos) and 1,466 lisp files. Almost all of them are declarations made of nouns, and
`defcaixa` (245 repos) and `defgotool` (Go repos) are the widely used ones. The action words the
master table lacks:
- `observe`, `apply` (paired with `plan`), `publish` (for vigy's `emit`), `record` (→ `append`),
  `assert`, `serve`, `rollback`;
- `ensure` (→ `put`), `patch` (→ `update`), `wait_until` (visita's Wait).

The conflicts to settle:
- cordel's cluster `sleep`/`wake` should become `park`/`unpark`, the words camelot-incept already
  uses;
- the tatara-script stdlib's kebab words (`read-file`, `exec-capture`) become legacy aliases of the
  space words written as tatara's `fairu/read`, which is the same tree blue lowers `fairu::read`
  to, so the two languages share one vocabulary.

Still to do: fold these rows into §3 and the waves, run the naming procedure and add a `NAMES.md`
row for every *new* package, and re-check the forms against `docs/CANONICAL-FORMS.md` once it lands.
