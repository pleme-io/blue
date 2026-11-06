---
kind: explanation
summary: utsushi, blue's history projection, DESIGN: Josh's essence naturalized with six improvements, the recon, the lens and view algebra, the phases, the parity gates and the tier ledger
---

# utsushi (写し): blue's history projection, the design of record

**Tier (2026-11-06): U1 BUILT, U2-U6 DESIGN.** utsushi is the naturalization of
Josh, "Just One Single History" (https://github.com/josh-project/josh): any
subtree or composed workspace of a repository shown as a repository of its
own, with history, both ways. It keeps the problem and the good ideas. It
vendors no Josh code. It is its own bidama, `bidamas/utsushi`, over `gitto`:
not a level of it, because a level never imports its root. U1 is `sub`,
`prefix`, `chain`, `compose` and `project`, and on a fixed-date fixture its
commit ids equal `josh-filter` 24.10.04's for `:/a/b` and `:prefix=lib/x`
(the tests in `bidamas/utsushi/utsushi.b`). The roadmap row is the utsushi
track in [`ROADMAP.md`](ROADMAP.md).

**The name.** 写し is a transcription: a faithful copy of an original, made
by hand, that keeps its form. A projected history is a transcription of part
of a repository's history.

## Destination

utsushi rewrites history with a small typed algebra. A **lens** is a
bijection on its part of the tree, so its history can go back up: push
accepts only a lens. A **view** is read-only. A workspace is blue entries,
each judged alone. Rewriting is incremental and content-addressed, so the
same filter over the same commit gives the same commit id on every machine,
and a changed filter misses only its own cache. A push that has no exact
inverse is refused, naming the path in conflict. It never guesses a base by
trial merges.

The first consumers are pleme-io's own: a bidama graduating to its own repo
with its history (`theory/PROJECT-GROWTH.md`), a repo absorbed with its
history, and `gen/tree.b` moves that keep `git log` for a moved package.

## What Josh teaches

Measured 2026-11-06 from Josh's docs, issues and releases.

| Good idea | utsushi keeps it as |
|---|---|
| a filter algebra in place of scripts (`:/a`, `:prefix=`, `:[..]`, `:exclude`, `:workspace=`) | the lens and view constructors |
| cost proportional to new commits, not history | a memo keyed by (filter hash, commit id) |
| the workspace mapping versioned in the repo | a blue file of workspace entries |
| a proxy that is stateless; the cache is only for speed | the cache is content-addressed, so it is never a source of truth |
| a repeatable, fast `git subtree split` | the CLI verb `blue utsushi split` |

## Six improvements, each tied to a Josh leak

| # | Josh leak (issue or doc) | utsushi |
|---|---|---|
| 1 | non-invertible filters (`:replace`, message rewrites, `:hook`, `:unsign`) can sit on a push path | lens and view are different types; push accepts a lens only |
| 2 | a nested workspace replaces its parent (#305); a path mapped twice warns only (#569); two sources map to one destination (#653); an invalid mapping does not fail (#644) | each workspace entry is refused alone, with its reason; valid siblings still apply |
| 3 | push-back guesses a base by trial merges and produced broken round trips (#998, after a wrong first fix #994) | `unapply` is a total function: it returns the commit or a refusal naming the conflict path; the law `filter(unapply(c, base)) == c` is a property test |
| 4 | filters keyed as strings (#684); the cache backend changed three times and an upgrade recomputes all | the key is the `def_hash` of the filter's normal form and the commit id |
| 5 | signatures are copied byte for byte and are invalid after rewriting | a signature policy is a required field: `drop`, `keep_when_tree_unchanged` or `re_sign` (`shomei` Ed25519) |
| 6 | an anonymous fetch implies an unauthenticated push unless `--require-auth` is set | the auth mode is a required field of the service; push options are a closed set |

Copybara's `reversible_check` is the run-time backstop for a lens a person
writes; the type is the first line.

## Recon: what blue already has

| Capability | Existing primitive | Gap |
|---|---|---|
| git verbs | `bidamas/gitto` (runs `git`: refs, commits, files, diffs, commit, fetch, push) | no object model; one process per call |
| SHA-1 and BLAKE3 | `digest_hex(:sha1, …)`, `blake3` in the runtime | none |
| byte layouts | `bidamas/baito`, `read_bytes`, `write_bytes` | tree, commit and tag object parsers |
| an HTTP server | `bidamas/eigyou/kyuuji` with a streaming reply | pkt-line, upload-pack, receive-pack |
| a memo | mondou's `recall` and `def_hash` | a persistent memo keyed by (filter, commit) |
| a path move over a tree | `gen/tree.b` | it moves the work tree, not history |
| repo growth | `theory/PROJECT-GROWTH.md`, `tend`, `repo-forge` | no step keeps history on graduate or absorb |

About 25% of the parts exist. Almost none of Josh's own logic does.

## Phases

| # | Deliverable | Gate | Exit |
|---|---|---|---|
| U1 | lenses `sub` and `prefix`, and `compose` of disjoint lenses, over history through git plumbing (`cat-file --batch`, `mktree`, `commit-tree`) in one long-lived process | differential against `josh-filter` on fixture repositories: equal commit ids | `blue utsushi split` gives Josh's ids for `:/a` and `:prefix=a` |
| U2 | workspace entries; `exclude`; views (`replace`, message templates) | each refusal has a fixture (overlap, double map, self-reference, cycle) with a red run | a workspace with one bad entry still projects the rest |
| U3 | `unapply` and push-back | the round-trip law as a property test; a refusal fixture for a conflict | a push through a lens lands upstream with the law green |
| U4 | the content-keyed cache | a cache hit equals a cold run byte for byte | an upgrade recomputes nothing that did not change |
| U5 | native objects: loose objects and packs | a pure-Rust inflate host primitive (`miniz_oxide`); pack and delta in blue, measured first | U1's differential holds with no `git` process |
| U6 | the proxy: smart HTTP fetch and push as a blue `service(...)` | protocol fixtures; the auth field required | `git clone` and `git push` through the service work |

## What blue lacks (host primitives)

| Need | Why | Where it goes |
|---|---|---|
| zlib inflate and deflate | loose objects and packs | a `blue-lang-host` seam over `miniz_oxide` (pure Rust, no C) |
| an https client | an upstream on GitHub (`http_request` speaks http only) | a host seam |
| fast pack and delta I/O | large monorepos | blue first; a host primitive only if U5 measures blue too slow |

## Tier ledger

<!-- tier-ledger -->

| Josh capability | utsushi realization | tier |
|---|---|---|
| a non-invertible filter on a push path | push's parameter is a lens; a view has no lens constructor | truly-unrep |
| an invalid or overlapping workspace entry | that entry is refused with its reason when the workspace is read | parse-time-rejected |
| a push with no exact inverse | `unapply` returns a refusal naming the conflict path | only-mitigated (C2) |
| commit ids stable across machines | the differential against `josh-filter`; a cache hit equals a cold run | only-mitigated (C2) |
| a copied signature that no longer verifies | the signature policy is a required field | truly-unrep |
| an unauthenticated push | the auth mode is a required field of the service | truly-unrep |

C2 is the external-world ceiling: the round-trip law and the id parity are
tested facts about runs, not types.

## Risks

| Risk | Mitigation |
|---|---|
| a `git` process per object is too slow | U1 uses one long-lived `cat-file --batch`; U5 removes the process |
| history with merges | merges are projected by the same function as other commits; a merge whose parents project to one commit follows Josh's `prune=trivial-merge`, as an explicit option |
| claiming "we replaced Josh" | parity is only the differential rows that are green |
