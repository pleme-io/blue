# Blue verb graph: shared brief (read fully first)

## Goal (operator, 2026-10-22, verbatim)
"extend bluelang batteries included nature by going to all of software engineering and building the language and verb graph and giving blue a development roadmap for full software verbalization"

**Full software verbalization** = every action a program or a software engineer performs has ONE short, plain-English verb with one meaning, one argument shape, one return shape and one error behaviour, in every problem space that implements it; verbs compose into larger verbs; each verb has laws. The result is a GRAPH: nodes are verbs (grouped in spaces), edges are the relations between verbs.

## What already exists: do NOT redo it, extend it
- `/Users/luis.d/code/github/pleme-io/blue/docs/STDLIB.md` (979 lines, DESIGN tier): the template. Read §0 (design in one screen), §2 (conventions: names, arguments, returns, errors, values, streaming, purity), §3 (master verb table: content/stores/running/transformation/time-log-output-cli/collections), §4 headings (22 spaces: fairu files, shisutemu processes, kankyou env, settei config, deeta formats, jisho maps, jikan time, moji text, kyohi error ledger, hikisuu args, rogu logging, heikou concurrency/retry, tsuushin HTTP, shomei hashing, gitto git, kurasuta k8s, habu GitHub, joujuu services, himitsu secrets, hyouka nix), §5 (gates), §6 inventory, §10-11 decisions and what is unfinished.
- `/Users/luis.d/code/github/pleme-io/theory/BLUE.md` §V.28 and §V.28.1 (laterals), `theory/BLUE-BATTERIES.md`, `blue/bidamas/CATALOG.md` (every bidama), `blue/bidamas/NAMES.md` (names are Japanese-led `goi`; a new name needs the `naming` skill's sweep: you only PROPOSE, mark `provisional`).
- Laterals (cross-cutting concerns, each ONE battery): error, retry, deadline, cancel, log, trace, config, validate, serialize, time, resource, process, cache, idempotent, capability, test, migrate, ratelimit, switch. Spine: `kyohi` as the ledger of error kinds.
- Verb style: plain English, as short as stays unambiguous, one verb per MEANING (a second spelling of one meaning is a bug), distinct verbs for distinct meanings, a larger verb is built from smaller ones, subjects first and options last as one record, `get` = nil for absent and `need` = raises, `read`/`write`/`put`/`delete`/`list`/`find`, no `_or` variants (recovery is `rescue`).

## Method
1. Read the existing material above before proposing anything. Reuse the master verbs; a new verb is allowed only if its meaning is genuinely different from every existing verb ("sufficiently different").
2. Survey your region of software engineering from what you know of the best standard libraries and ecosystems (Go, Rust, Python, Ruby, Elixir/Erlang-OTP, Clojure, Haskell, Java/JVM, Swift/Apple frameworks, Node, SQL, shell/coreutils, Terraform/Kubernetes/Nix/Git/Docker CLIs and APIs, the relevant RFCs and standards). Say which you drew from.
3. Find the fleet's existing owners of each concern, measured: pleme-io has ~1,400 repos at /Users/luis.d/code/github/pleme-io; the root .gitignore is `*`, so use `rg --no-ignore -g '!**/target*/**'` and iterate PER REPO or per small directory set, never one root-level recursive search (it silently returns zero). Read a repo's CLAUDE.md one-liner before citing it. `blue/bidamas/CATALOG.md` says what blue has today.
4. Read-only on all repos. Write ONLY to `/Volumes/blue-scratch/tmp/verbs/<REGION>/` (RAM disk; create the directory).

## Output (three files in your region directory; tab-separated, UTF-8, NO quotes, header row first, no tabs inside fields)
`verbs.tsv` columns: `region  space  verb  kind  shape  laterals  fleet  blue_today  meaning  wave`
- `space`: an existing bidama/space name, else a PROVISIONAL romaji `goi` name with a trailing `?` (e.g. `kakuritsu?`) and the English gloss in the REGION.md.
- `verb`: the bare verb (`read`, `put`, `diff`, `watch`...). Verbs are always used qualified `space::verb`, so a verb name may repeat across spaces on purpose: that is the vocabulary (same verb, same meaning, many spaces).
- `kind`: `pure` | `effect` | `stream` | `decl` (a declaration/entry, no execution).
- `shape`: `verb(subject, opts) -> returnshape` in one line, e.g. `read(src, opts) -> bytes`.
- `laterals`: comma-separated subset of the lateral names above that this verb touches (e.g. `error,deadline,log`).
- `fleet`: the pleme-io crate/repo that owns it today, or `-`.
- `blue_today`: `exists:<bidama>` | `partial:<bidama>` | `absent`.
- `meaning`: at most 12 words.
- `wave`: 0 (build now: exists or tiny), 1 (next), 2, 3, 4 (long horizon). Justify in REGION.md.
`edges.tsv` columns: `from  rel  to  why` where from/to are `space::verb`, `rel` is exactly one of: `inverse` (undoes), `composes` (from is built from to), `refines` (from is a specialisation of to), `generalizes`, `requires` (from needs to as a precondition), `lifts` (streaming/batch form), `guards` (from checks to's precondition), `pairs` (always used together). `why` at most 8 words. Aim for at least 1.5 edges per verb; every verb has at least one edge.
`REGION.md` (at most 70 lines): the spaces, their gloss, the 5 highest-leverage gaps, what stays OUT of blue (and why: C-level, GUI toolkits, etc., following STDLIB §4.23 spirit), the wave order with reasons, overlaps/duplicates with other regions you noticed, and risks.

## Quality bar
Aim for 15-40 verbs per space and 6-14 spaces per region; depth beats breadth, but a region with fewer than 120 verb rows is incomplete. Every verb earns its place with a meaning that differs from every other verb in the table: if two verbs mean the same, keep one and add a `refines`/`generalizes` edge. Do not invent fleet precedent: cite only what you read. No placeholder rows. Final message: at most 25 lines (counts, the 5 gaps, the files written).
