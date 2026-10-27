# Region G: interfaces, intelligence and the physical world
395 verb rows, 610 edges (1.54 per verb), 14 new provisional spaces and 22 existing ones extended.
Drawn from: Elm/React/SwiftUI (gamen), WCAG/ICU (theme, plural), CSS springs and easing (ugoki), wgpu render graphs (byouga), ffmpeg/sox/Pillow (onsei, gazou),
pandoc/PDF/OOXML (bunsho), Anthropic and MCP APIs, RAG and eval harnesses (moderu, dairi, kensaku, saiten), Bevy ECS/GGPO (sekai), embedded-hal/RMS scheduling (souchi),
double-entry ledgers (kinyuu), PROJ/GeoJSON/H3 (chizu).
Fleet owners come from Cargo descriptions only; `-` means no owner found on 2026-10-22. `chuuzou` and `kiban` live in `blue/native/bidamas/`.

## Spaces (new ones end in ?, all names provisional, naming sweep owed)
| space | gloss | rows |
|---|---|---|
| gamen? | screen: views, state, events, theme, accessibility, i18n, terminal prompts | 34 |
| ugoki? | motion: easing, springs, timelines, frame clocks (reads ishou-batente, never copies it) | 22 |
| byouga? | rendering: surfaces, render graphs, scenes, cameras (declares; GPU runs) | 21 |
| onsei? | audio: decode, encode, edit, measure, transcribe, speak | 22 |
| gazou? | images and video frames: decode, edit, diff, mux | 24 |
| bunsho? | documents: markdown, PDF, office, slides | 21 |
| moderu? | models: prompts, calls, tokens, embeddings, cost | 18 |
| dairi? | agents: tools, MCP, loops, approval, memory, replay | 24 |
| kensaku? | retrieval: index, search, rank, fuse, ground, cite | 19 |
| saiten? | scoring: eval suites, judges, datasets, fine-tune data | 19 |
| sekai? | world: ECS, physics, procedural generation | 24 |
| souchi? | devices: pins, buses, sensors, real-time tasks, flashing | 23 |
| kinyuu? | finance: money, ledger, interest, pricing | 24 |
| chizu? | maps: points, projection, geometry, geocoding | 20 |
Extended (canonical names or missing verbs only): ongaku, kikagaku, rittai, zumen, ran, tokumei, kazu (units), kinji, gyouretsu, toukei, mokuroku, seimei, kiban, chuuzou, wariate, chokkan, and the arnes packages joutai, kenban, kenkou, meirei, sanshou, yushutsu.

## The 5 highest-leverage gaps
1. **moderu/dairi/kensaku/saiten**: arnes, chokkan and codesearch each hold a private model, tool and search shape in Rust. One vocabulary (`ask`, `call`, `search`, `score`) lets every blue program use them.
2. **gamen + ugoki**: no blue word for a view, a theme or a motion. The fleet has egaku, madori, irodori, ishou-pente and ishou-batente as closed Rust algebras; blue has none of them as data.
3. **bunsho**: markdown, tables, slides and reports are written by hand in every region. One `parse`/`render`/`convert` set removes that.
4. **kinyuu**: money as floats is the classic bad state. `money` refuses floats, `post` refuses unbalanced entries; both are scoped refusals.
5. **sekai + souchi**: ECS, determinism (`replay`, `rollback`) and board I/O already exist in Rust (asobi-ecs, asobi-net-rollback, blue/native). Blue has no verbs for them.

## What stays out of blue (Rust, GPU or C; blue gets a surface only)
- GPU execution (wgpu passes, shaders, glyph atlas upload, tensor kernels): `byouga::draw`, `gyouretsu::run` call Rust. Blue declares and checks.
- Codecs (H.264/VP9, Opus, JPEG, PDF raster) and font shaping: C-level or years of work. Blue calls through a seam; PNG/WAV-class formats may be pure blue later.
- Device registers and interrupts: the one unsafe MMIO seam stays in `blue/native/seam` (CONTAIN THE C). Blue owns specs, frame codecs and schedulability proofs.
- Model training on GPU: `saiten::train` only starts a hosted job. Local training stays ml-forge.
- Physics solvers and dense linear algebra at scale: blue keeps a slow reference solver for tests (fornalha has one), Rust runs the fast one.
- GUI toolkits: `gamen` renders to ansi/html/widget spec; egaku and madori draw windows. No `shadow` verb on purpose: depth is layering and color.

## Wave order
- **0 (66 rows)**: rows that exist or are tiny on existing bidamas (ran, kinji, tokumei, ongaku, rittai, zumen, wariate, chokkan, kiban), plus `theme`, `contrast`, easing and springs (pure arithmetic on kazu).
- **1 (139)**: pure data spaces, no new primitive: gamen view/layout/render/theme/i18n, bunsho markdown, moderu prompt/tokens/cost, kinyuu money and ledger, chizu geometry, saiten datasets, sekai ECS, kensaku rank/fuse, dairi declarations.
- **2 (122)**: needs a primitive: bytes decode/encode (onsei, gazou), HTTPS for `ask` and `geocode` (decision D3 in STDLIB), stdin and TTY for `prompt`, MCP over stdio, file watching.
- **3 (63)**: GPU, audio devices, buses, flashing, speech and OCR models, video frames.
- **4 (5)**: long horizon: `transcode`, shot `segment`, `boolean` CSG, hosted `train`, compiled tensor `run`.
Reason: pure rows prove laws with no host; each host-bound row waits for one primitive.

## New master verbs proposed for STDLIB section 3
`check` (rules over a subject, findings out; 12 spaces use it; the `validate` lateral), `advance` (move a state forward by dt: ugoki, sekai, kinji, dairi, seimei),
`send` and `on` (event in, handler bound), `call` (invoke a named function with args), `open`/`close` (acquire/release a handle), `convert` (same content, other representation: gazou, byouga, kinyuu, kazu, bunsho),
`measure` (a level or size of a subject), `overlay` and `trim` and `segment` (media edits), `search` and `sync` (ranked hits; idempotent catch-up), `hit` (first thing a ray or point meets), `path` (cheapest steps between two things), `post` (record a balanced entry once).
`treat` is used instead of `filter` for media effects, because bare `filter` already means keeping elements.

## Overlaps and duplicates noticed
- `gamen::localize` and `kinyuu::render` both format money for a locale: kinyuu refines gamen (edge).
- `bunsho::fill` is the templating STDLIB 4.23 excluded; this region needs it now (invoices, decks, prompts). Another region may claim it.
- OOXML and EPUB are zip plus XML: `bunsho::read` needs the archive and XML spaces (likely region with files/formats).
- `ran::fork`, `sekai::replay` and `dairi::replay` share one determinism contract (same seed or recorded replies, same result).
- `souchi::fuse` and `kensaku::fuse` merge many sources; `saiten::calibrate` and `souchi::calibrate` fit raw to true. Edges, not new verbs.
- `chokkan::choice` and `moderu::classify` do one job: chokkan is the typed door, moderu the general one.
- `ugoki` and `ishou-batente` must agree: batente is a closed Rust algebra with a no-raw-duration rule; ugoki never re-types durations.

## Risks
- Exact decimal arithmetic for `kinyuu` is not confirmed in blue's `kazu`; if absent, `money` needs an integer-minor-unit record first.
- Per-frame motion and ECS ticks may exceed interpreter speed; the path is chuuzou (compile to Rust) before wave 3.
- Eval and model calls are non-deterministic: `ask` must be cached and recorded (`cache`, `replay`) or the test lateral is empty.
- 14 unswept names; `sekai`, `souchi`, `chizu`, `kinyuu` are plain words and likely to collide (the `naming` sweep found three misses before).
- `bunsho` PDF and docx fidelity is a long tail; claim only a supported subset.
