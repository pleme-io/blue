# Region F: OBSERVE, TEST, QUALITY AND THE ENGINEERING PROCESS

Totals: 395 verb rows, 717 edges, 30 spaces (11 exist, 19 provisional). Waves 0/1/2/3/4 = 118/68/127/76/6.
Drawn from: Go slog/OTel/Prometheus, Rust tracing/proptest/cargo-fuzz/criterion, Python logging/pytest/hypothesis,
Erlang/OTP (tracing, observer), Elixir ExUnit, JVM JFR/JUnit/Pact, Git/GitHub/Jira/Confluence APIs, SRE book (SLO, burn),
DORA, tree-sitter, LSP 3.17, OpenRewrite/comby (codemods), ADR (Nygard), Keep a Changelog, Conventional Commits.
Measured in the repo 2026-10-22: `blue --help` (profile, trace, replay, census, explain, doc, migrate, lsp, serve, watch, test,
fmt, check), `blue_lang_check::RULES`, blue-lang-proc `trace`, blue-lang-mondou, `bidamas/CATALOG.md` (shihyou 19 defs, kyuuji 25, nisshi 147).

## Spaces (provisional names end in ?; all need the `naming` sweep)
Observe: rogu (logging, extended), keisoku? (measurement: metrics, profiles, benchmarks), tsuiseki? (tracing, "tracking"),
shihyou (SLOs plus engineering metrics such as DORA), jiko? (incident, 事故: page, timeline, postmortem), genin? (cause, 原因:
debug, crash, bisect, shrink), nisshi (audit event log), kyuuji (service metrics and health).
Test and quality: kentei? (test, 検定), okite (laws and generators), heni (mutation), hadome (ratchet), fuka? (load and fault, 負荷),
kaiseki? (static analysis, lint, format, 解析), kakikae? (refactor and codemod, 書き換え), hinagata? (templates and codegen, 雛形),
mokuroku (docs generation), chishiki? (knowledge: wiki, search, runbook, 知識).
Process: gitto, shinsa? (code review, 審査), habu (GitHub), hakkou? (release, 発行), kettei? (decision records, 決定), youken?
(requirements, 要件), kadai? (tickets, 課題), keikaku? (planning, 計画), kaihatsu? (developer loop, 開発).
Language tooling: kobun? (syntax trees, 構文), gengo? (language services, 言語), kiwari (grammar spec).
`hanketsu?` from the brief is not used: a verdict is a plain return shape (`verdict`) and gates live in hadome and kaihatsu::gate.

## The 5 highest-leverage gaps
1. kentei?: `snapshot`, `fixture`, `raises?`, `quarantine`, `shard`, `affected`. Testing is blue's most-used verb family (4,715 assert
   lines, STDLIB §8) and has only `assert`; golden files are `snapshot` with a format, not a second verb.
2. keisoku? + tsuiseki? + rogu: no metrics or trace vocabulary exists in blue; kyuuji has one private histogram. Three spaces share
   `sample?`, `push`, `read`, `query` and the lateral pair log/trace, so service code is observable by default.
3. hakkou? + gitto: release is the missing half of the pipeline (next version, changelog, breaking?, promote, rollback, yank).
   `breaking?` is a pure function of `mokuroku::diff`, so blue can refuse a semver lie that no other ecosystem catches in the language.
4. kobun? + gengo?: parse, walk, query, edit, hash, diff as verbs over any language with a kiwari grammar. The crates exist
   (blue-lang-syntax, -mondou, -lsp) but expose no bidama surface; this makes lint, codemod, docs and clone detection one shape.
5. kakikae? with `plan` / `apply` / `preserves?`: the proof-per-file migrate already ships; refactor and codemod become verbs
   with a plan-before-write rule, which is blue's answer to unsafe codemods.

## Stays OUT of blue (and why)
- Debugger wire protocols, ptrace, core-dump formats, DWARF reading: C-level; `dump`, `backtrace`, `symbolize` are the typed
  surface and may sit behind a Rust seam (STDLIB §4.23 spirit; caixa-backtrace is the precedent for Rust).
- Metric/trace/log backends (Prometheus, Tempo, Loki, Datadog, Splunk): blue speaks to them via `push`/`query`/`read`; storage stays theirs.
- GUI profilers, flame-graph viewers, IDE UIs: a rendered artifact (`render`) is blue's job, the viewer is not.
- Fuzzing engines (libFuzzer, AFL), coverage instrumentation (LLVM): Rust/C seams; `fuzz` and `cover` are the verbs over them.
- Issue-tracker and wiki servers (Jira, Confluence, GitHub): clients only; `kadai?` and `chishiki?` are store verbs over their APIs.
- Estimation methods that need judgement (planning poker): `estimate` records a value; it does not compute one from nothing.

## Wave order and why
- Wave 0 (118): what exists (nisshi, hadome, heni, okite, kiwari, shihyou rules, kyuuji, `blue profile/trace/replay/census/fmt/check`)
  plus tiny verbs the runner or STDLIB already designed (rogu levels, snapshot, fixture, gitto reads). Pure renaming into the vocabulary.
- Wave 1 (68): verbs that need only wave 0 and shell-out: bench, rate, quantile, bisect, shrink, gitto stage/rebase/revert,
  hakkou next/changelog/build, kaihatsu gate, kobun parent/normalize, kaiseki fix, kakikae rewrite/plan/apply.
- Wave 2 (127): backends over HTTP (habu, kadai, chishiki, push/query, shinsa) once tsuushin (D3, https) exists; plus incident, load,
  coverage, flaky, scaffold, call graph. Needs STDLIB W5.
- Wave 3 (76): debugger sessions, contracts, fuzz, soak/chaos, canary, requirements, planning. Need Rust seams or operator process.
- Wave 4 (6): mirror, impact, onboarding, risk, retro, requirement diff: research-grade or human-owned.

## Overlaps and duplicates with other regions (seen, not resolved here)
- `critical_path` appears in tsuiseki? and keikaku?; both are the longest chain in a DAG. Region owning graphs should hold one `graph::critical_path`.
- `diff`, `merge`, `watch`, `parse`, `render`, `query`, `list`, `get` are master verbs reused on purpose; `sample?`, `push`, `assign`, `link`, `plan` repeat across my spaces with one meaning each.
- `scan` (kaiseki?) vs a security region's vulnerability and secret scanning; `fault` (fuka?) vs any resilience or network region;
  `publish`/`promote`/`pin` (hakkou?) vs deploy/GitOps verbs; `serve` (gengo?, kyuuji) vs a network region; `profile` vs a performance-of-system region.
- `kettei?` (decisions) vs okite (blue's own decisions): okite stays the enforcement binding, kettei? is the general record.
- Edges to other regions' verbs: jikan::now, jisho::put, jisho::merge, deeta::diff, fairu::with_temp_dir, fairu::watch, himitsu::list, shisutemu::run (all in STDLIB §3-4).

## Risks
- `blue_today` uses `exists:<crate>` for verbs owned by a Rust crate or the runner (blue-lang-cli, -test, -check, -fmt, -mondou, -lsp, -syntax,
  -proc, -runtime) because no bidama surface exists yet; the gate will need a row type for crate-owned verbs.
- `trace` (genin?, a call trace) and a tsuiseki? span trace are different meanings; the space qualifier keeps them apart, but docs must say so.
- `stop`, `start`, `open`, `check`, `run`, `plan`, `info` carry several space meanings; each stays "the same act on a different subject", verify with verb-laws.
- Names are unswept: `genin`, `jiko`, `kentei`, `fuka`, `kobun`, `gengo` may collide (STDLIB rejected `shiken`, `kiroku`, `fugou` by hits).
- 19 new spaces is a lot to land; wave 0 and 1 touch only 11 existing spaces plus kentei?, rogu and gitto, so most provisional spaces can wait.
- Fleet column cites only what was read (README/CLAUDE one-liners or crate lists): metrics-go, logging-go, pleme-observability, caixa-backtrace,
  caixa-proptest, caixa-cargo-fuzz, pleme-testing, pleme-doc-gen, cse-lint, releaser, repo-forge, forge-gen, tend, tameshi, cartorio,
  pangea-pagerduty, confluence-pr-refresh, vendaval (dir and skill only), tundra-gwbench (name only).
