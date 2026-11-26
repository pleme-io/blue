---
kind: explanation
summary: the cohesion refactor of blue; one model per domain, and refactor units in waves, each landable alone with its lock
---

# COHESION: one true blue

## 1. Destination

blue is one system. Each meaning has one spelling, one tree, one runtime shape and one word. Every door runs one pipeline: parse, check, erase, run. Every evaluator passes the same rows, or it pends on a named gap. Every gate can fail. Every doc claim links checked evidence. A bad state is refused where it starts, and the refusal names its fix. Behaviour is configured off, never deleted.

This plan puts 273 confirmed audit findings into 76 units. It defers 3 findings, and part of a fourth, to the plans that own them. A unit adds a feature only where it fills a blank that the audit found.

## 2. The model

- **Surface.** One spelling per meaning, the shortest that stays distinct. Machine fixes rewrite older spellings, and every write keeps def_hash. The dot reads a field, a call is f(x, y), and a function in a field is (x.f)(y). A position counts from 0. Syntax lowers to owned heads. One grammar table, one character table and one locale pack serve a run. A waiver is an @waive attribute.
- **Absence and errors.** Absence is umu::none, refusal is a must-use kyohi result, fault is a raise. nil is unit and JSON null only. ? stays in its channel. Kinds are snake_case, an error crosses every boundary whole, and kyohi's ledger is the exit grammar.
- **Data shapes.** Maps walk in one total key order, and size and empty? are total. Only a checked construction carries a record tag (D0017). One value walk renders text, and every Float keeps its point. deeta is the codec door, with keyword keys. shomei owns the content address.
- **Words and verbs.** The subject comes first. One meaning has one word, a predicate ends in ?, and no word has an _or variant. The prelude is the contract's 42 names. Synonyms retire through legacy_names bridges. One word runs a process; one policy record serves retry and restart.
- **Types.** One type grammar lives in blue-lang-syntax, with one accepts relation. Builtins have typed signatures, tails are checked, and kazu::fits decides width. The boundary follows the 2026-11-19 ruling. settei's type grows into the one value-type vocabulary.
- **Names and modules.** Each bidama is a namespace. One predicate decides flat-era refusals, and the window closes by a stated rule. A kept-prefix word has one outside spelling.
- **Configuration and authority.** A capability has one snake_case spelling. The hold is meet(shebang, CLI, project). Bounds meet at every door, and each has one word. settei configures programs and blue. One switch registry refuses unknown values. Configured off has one encoding, and blue lock decides it.
- **Processes and time.** A run has one clock source and one provider state. spawn is sealed. pid, ref and timer are typed, and a timer is a process. case and receive share one pattern language. A deadline bounds host waits too.
- **Evaluators and placements.** The walker is the reference. Every other column passes each row or pends on a named gap. A closure means one thing, and the auto door never hides a raise. Native code lowers only checked trees, and its column can fail.
- **Pipeline and levers.** parse, check, erase, run, through one door builder. One lever table decides. Every lever stands down under a bound (ROADMAP R10), and PERFORMANCE R19 fuses only pure chains. Macros expand in one stage. TreeHash and DefHash are two types.
- **Host words.** A grant covers where the bytes go. One Fs serves two stores, and a write is atomic. Every handle has one lifecycle, bytes decode per field, and one end-of-run seam writes the receipt.
- **Gates and ledgers.** One hadome ratchet ledger: every rise has a receipt, and blind reads red. The Bluefile declares every gate. Every gate can fail. A doc claim links checked evidence.
- **Tooling faces.** mondou's facts are the one source. One recognizer and one resolver serve every face, and blind is never none. The CLI has one flag vocabulary. Tables render from code, and bunsho renders Markdown.
- **Project model.** One project context serves every door and built app. One floor and one ceiling meet at lock. One list holds the rendered files and their readers. service is the one deploy word. Scaffolds pass their gates.
- **Legacy with a fixer.** x.f(y) sends, # waive comments, kebab names, pair-list JSON codecs, element-first verbs, synonym and _or words, the nine process words, timer numbers, def main(args), check-tiers.nix.
- **Configured off, not deleted.** chan, go and defactor; workload; the second macro schedule; BLUE_SCRIPTS=ambient; old flag aliases.

## 3. Rules for every unit

- A unit lands alone on main with its lock: a test that fails without the change.
- A changed spelling ships its fixer: a RULES row with a machine fix, a legacy_names row or a formatter rewrite.
- A retired behaviour gets an off switch. Its code, declaration and tests stay.
- A new ruling goes into docs/ROADMAP.md as ROADMAP R14 and on, in the same commit as its fix.
- A unit starts when every unit in its After column is ✅.
- A gate gets a red run on a broken input before anyone trusts it.
- A row starts ❌. It goes ⏳ when its first commit lands, and ✅ when its lock is green on main.

## 4. Rulings

Six units needed a ruling. Each is decided. A unit that applies a ruling records it in docs/ROADMAP.md § Rulings in the same commit.

| Unit | Title | Ruling | Rejected | Date, who |
|---|---|---|---|---|
| U16 | One position meaning | A position counts from 0. A negative position is before the start, so it answers nil. index_of keeps -1 for "not found", and an index read with it can never return the last item. | Ruby's rule (a negative position counts from the end) | 2026-11-25, operator |
| U17 | One call through a field | After the refusal window, x.f(y) means (x.f)(y): read the field, then call what it holds. The dot has one meaning. | x.f(y) refused forever | 2026-11-25, operator |
| U24 | Subject-first verbs | Every verb takes its subject first: map(xs, f), filter(xs, f), reduce(xs, init, f). A machine fix rewrites each call, and a tatara bridge keeps Lisp callers working. | Lisp order for callback verbs | 2026-11-25, operator |
| U27 | Close the flat-era window | The window closes by a stated rule: a legacy_names `until:` or a date, never by bumping the four roots at once. | Bump the four roots to 0.2.0 (it breaks 86 Bluefiles at once, a refusal wider than its fault) | 2026-11-25, decided under "every break ships its fixer" and "scoped to the fault" |
| U46 | One exit grammar | An uncaught raise exits with its kind's exit status, from kyohi's ledger, at every door. | Always 1, with an extra word to exit by kind | 2026-11-25, operator |
| U70 | One macro expansion stage | Macros expand in one batch stage before check, so check judges the expansion (parse, check, erase, run). Per-form expansion with a recheck stays an off policy. | Per-form expansion as the default | 2026-11-25, decided under "the pipeline is the architecture" |

## 5. Waves

Wave 0 has no dependencies. Each later wave depends only on earlier waves.

### Wave 0: foundations

| State | Unit | Title | Size | After |
|---|---|---|---|---|
| ❌ | U1 | Write doors keep meaning | M | ➖ |
| ⏳ | U2 | The nil test is a question | S | ➖ |
| ⏳ | U3 | One text for keys and floats | M | ➖ |
| ⏳ | U4 | Snake-case kinds at the rescue seam | M | ➖ |
| ❌ | U5 | VM and walker mean one thing | M | ➖ |
| ⏳ | U6 | The native column can say no | M | ➖ |
| ⏳ | U7 | PERFORMANCE R19 sees purity and scope | M | ➖ |
| ⏳ | U8 | Gates and ratchets can say no | L | ➖ |
| ⏳ | U9 | Docs of record match main | L | ➖ |
| ❌ | U10 | One capability vocabulary and the shebang hold | L | ➖ |
| ⏳ | U11 | Macro foundations | M | ➖ |
| ⏳ | U12 | One definition recognizer | S | ➖ |
| ❌ | U13 | Docs teach only canonical spellings | M | ➖ |
| ⏳ | U14 | settei has one engine and one reader | L | ➖ |

U2, U4, U6, U7 and U11 land together (2026-11-25). U11 lands its first two
commits. Its third commit adds the G30 and G31 rows to `spec/rows/macros.b`,
with the DIAGNOSTICS text on the head that a project rule receives for
`quote … end`. That commit waits for the tatara-lisp release that closes both
gaps: the tatara-lisp release gate runs the rows of blue main against the
candidate, so the two marks on main would turn that release red.

U3, U8, U9, U12 and U14 land together after them (2026-11-25), with their
rulings ROADMAP R17 (U3), ROADMAP R18 (U8), ROADMAP R19 and ROADMAP R20 (U9).
U3's gap G32 stays open until blue bumps to the tatara-lisp release that holds
its map order (6011c03): the bump takes the `flaky("G32")` mark and the three
ignored G32 tests away in one commit.

Four units are held for review fixes:

- U1: `blue fmt` refuses a canonical file in which a tail `if` holds a guard
  in a branch and its whole `else` is a bare `return`. `within` builds that
  `else` again with an empty span, so the `return` is lost, the printer drops
  the `else` and the meaning law refuses the result. The G1 ✅ row in
  GUARD-RETURN.md says that `blue fmt` keeps every guard as written.
- U5: the door gate does not flush on an empty write. On the default door,
  `display("a")`, `write_stdout("")` and then `write_stderr("b")` print `b`
  first, where the walker and the VM print `"a"` first.
- U10: the help of `blue run --allow` says that a script that declares no
  capability runs with none, and does not say that `--allow` or a Bluefile can
  hold it. The plan edits the review names (r2doors-14 and its locks in U28,
  the line-1 lock of `blue test` in U56, and a unit for the label flip, the
  Bluefile fixer and the meta-word grammar) are not made yet.
- U13: three spellings that the gated texts teach are refused by
  `blue check`: B0073's help offers `use(%i[thing sub])`, `blue doc list?`
  teaches `x == nil`, and B0004's explanation names `&&` and `||`.

### Wave 1: one table per concern

| State | Unit | Title | Size | After |
|---|---|---|---|---|
| ❌ | U15 | Formatter canon and typed waivers | L | U1 |
| ❌ | U16 | One position meaning | S | ➖ |
| ❌ | U17 | One call through a field | S | U1 |
| ❌ | U18 | One reader front | L | ➖ |
| ❌ | U19 | One type and binder grammar | M | ➖ |
| ❌ | U20 | Collections answer totally | M | U9 |
| ❌ | U21 | One content address | M | ➖ |
| ❌ | U22 | One value walk and one render refusal | L | U3 |
| ❌ | U23 | One result and option shape | M | U9 |
| ❌ | U24 | Subject-first verbs | L | ➖ |
| ❌ | U25 | The verb graph closes | M | ➖ |
| ❌ | U26 | Lowerings cannot be captured | M | ➖ |
| ❌ | U27 | Close the flat-era window | M | U13 |
| ❌ | U28 | One door builder | L | U10 |
| ❌ | U29 | Bounds and switches have one reader | L | ➖ |
| ❌ | U30 | Off states and floors are decided at lock | L | ➖ |
| ❌ | U31 | One clock per run | M | ➖ |
| ❌ | U32 | Processes are sealed and pinned by rows | L | ➖ |
| ❌ | U33 | Native meaning matches the walker | M | U6 |
| ❌ | U34 | Kernel and BPF follow their rules | L | ➖ |
| ❌ | U35 | Contain the C in the kernel seam | M | ➖ |
| ❌ | U36 | One lever table that decides | M | U7 |
| ❌ | U37 | Host words keep their contracts | L | U10 |
| ❌ | U38 | The Bluefile declares every gate | M | U8 |
| ❌ | U39 | Renderings come from one source | L | U13 |
| ❌ | U40 | Facts hold every word, and faces render them | L | U12 |
| ❌ | U41 | One CLI vocabulary and clean scaffolds | L | ➖ |
| ❌ | U42 | The check stage reads macros | M | U11 |
| ❌ | U43 | Generators and seeds are held | S | ➖ |
| ❌ | U44 | Bidama tiers hold | M | ➖ |

### Wave 2: unifications on the tables

| State | Unit | Title | Size | After |
|---|---|---|---|---|
| ❌ | U45 | Results keep their channel | L | U23 |
| ❌ | U46 | One exit grammar | M | U4, U9 |
| ❌ | U47 | Only checked constructions carry a record tag | M | U19, U20 |
| ❌ | U48 | One codec door | M | U20, U22 |
| ❌ | U49 | Types are checked at tails by one relation | L | U19 |
| ❌ | U50 | Typed call heads | L | U19 |
| ❌ | U51 | One fixed-width meaning | M | U19 |
| ❌ | U52 | The prelude follows the contract | M | U24 |
| ❌ | U53 | One word per meaning | L | U24 |
| ❌ | U54 | One process-run word | M | U24 |
| ❌ | U55 | One policy record | M | U24 |
| ❌ | U56 | Tests and doors share one hold and one check | L | U28 |
| ❌ | U57 | Errors cross every boundary whole | M | U4 |
| ❌ | U58 | One guest runner and one program identity | L | U1, U28 |
| ❌ | U59 | A parity column per interpreter | M | U28 |
| ❌ | U60 | blue configures itself with settei | L | U14 |
| ❌ | U61 | Renderings hold the settings model | L | U14 |
| ❌ | U62 | Process handles and deadlines are typed | L | U31, U32 |
| ❌ | U63 | One pattern language | L | U19 |
| ❌ | U64 | Backend refusals are diagnostics | M | U33 |
| ❌ | U65 | Bounds hold over every lever | M | U29, U36 |
| ❌ | U66 | One filesystem | M | U37 |
| ❌ | U67 | Built apps keep their project | L | U10, U28 |
| ❌ | U68 | service deploys and connects | L | ➖ |
| ❌ | U69 | One serving loop with the default stack | L | U4 |
| ❌ | U70 | One macro expansion stage | L | U11, U42 |
| ❌ | U71 | One quote family | M | U11 |
| ❌ | U72 | The run record is a closed world | L | U28, U31 |
| ❌ | U73 | One resolver for every face | M | U40 |

### Wave 3: closing the chains

| State | Unit | Title | Size | After |
|---|---|---|---|---|
| ❌ | U74 | JSON keys are keywords | M | U48 |
| ❌ | U75 | One replay verb | M | U72 |
| ❌ | U76 | One value-type vocabulary | L | U14, U19 |

## 6. Deferred

- processes-11 (await, cancel and scope): ASYNC A2 owns this deliverable in ROADMAP's owner table. One deliverable has one owner, so this plan does not plan it twice.
- pipeline-11 (one middle-end, kuzushi, for chuuzou and hashiru): PURE-BLUE B0 owns the backend plan. The docs-of-record unit (U9) fixes only the false henkan claims now.
- r2services-10 (the service batteries in two repos): nix/docs/campaign-2026-11-09.md wave 1 owns the move into the bidama-<family> repos.
- bidamas-15, the habu and himitsu parts: SAFETY row 14 owns secrets, and habu waits for its own track. The policy-record unit (U55) takes only heikou's second retry.

## 7. The freeze

The operator ruled a feature freeze on 2026-11-25: ROADMAP R21 in [ROADMAP.md](ROADMAP.md). It holds until every exit criterion in §8 is met.

While the freeze holds, main takes only:

- the units of this plan, and the fixes their reviews ask for;
- a bug fix with its lock;
- a security fix;
- release, ledger, regen and lock mechanics.

Everything else waits. A new word, form, operator, bidama, CLI verb, flag, Bluefile entry, switch, capability, evaluator rung, placement or design track does not land, unless a unit of this plan needs it. An open track in [ROADMAP.md](ROADMAP.md) keeps its row and its state; its next step waits. A consumer repository uses blue as it is. A change to blue that a consumer needs is a bug fix, or it waits.

A change that is not a unit names its clause in its first sentence: fix, security or mechanics.

## 8. 100 %: the exit criteria

blue is fully cohesive when all six criteria hold. Each one is checked, never claimed.

| # | Criterion | Evidence |
|---|---|---|
| 1 | Every unit in §5 is ✅: its lock is green on main. A unit leaves the plan only by an operator ruling that names its new owner. | the §5 tables |
| 2 | Every confirmed finding is fixed, or deferred in §6 to a named owner. | each unit's finding list in its commits |
| 3 | A re-audit with the 25 lenses of [cohesion/LENSES.md](cohesion/LENSES.md), run on main after criterion 1, confirms no new finding of medium severity or higher. | the re-audit's report, linked in this row |
| 4 | Every gate in §10.3 is live on main and has had a red run on a broken input. | each gate's red-run receipt |
| 5 | Every conformance column passes each row or pends on a named gap. No divergence between evaluators lacks a gap id. | `checks.conformance` and its columns |
| 6 | The consumers sweep is green at the final pin: every fleet repository that uses blue builds and passes its tests. | `blue gen/consumers.b sweep` |

When all six hold, the cohesion row in [ROADMAP.md](ROADMAP.md) turns ✅ with these links, and the freeze ends.

## 9. What it takes

§5 holds each unit's state. This section names the work around the units and the order it forces.

### 9.1 The chains

A unit starts when every unit in its After column is ✅. The longest chains are four units long:

- U10 > U28 > U72 > U75: one capability vocabulary, one door builder, the run record as a closed world, one replay verb.
- U3 > U22 > U48 > U74 and U9 > U20 > U48 > U74: one text, one value walk, one codec door, JSON keys as keywords.

So U10 is on the critical path. U1 blocks U15, U17 and U58; U10 blocks U28, U37 and U67, and through U28 also U56, U58, U59, U72 and U75; U13 blocks U27 and U39.

| Wave | Units | S | M | L |
|---|---|---|---|---|
| 0 | 14 | 2 | 8 | 4 |
| 1 | 30 | 3 | 14 | 13 |
| 2 | 29 | 0 | 14 | 15 |
| 3 | 3 | 0 | 2 | 1 |

### 9.2 Work beyond the units

- **tatara-lisp releases.** One release carries U3's ordered map text and U11's linear lift and nested quasiquote. Their branches are `cohesion/u3-one-text-for-keys-and-floats` and `cohesion/u11-macro-foundations` in tatara-lisp. blue's bump lands with U11's last commit, which removes the G30 and G31 marks. A later release carries U24's bridge for callers in Lisp order. tatara-lisp's release runs blue main's conformance against the candidate, so a blue pending mark that only the release closes waits for the release, never the reverse.
- **The consumers sweep.** A unit that changes a spelling lands after its consumers are rewritten by its fixer (`blue gen/consumers.b sweep`, then `fix REPO`), as the agent guide requires. U16, U17, U24, U27, U46, U53 and U74 change spellings. U10 already has branches in televisao and blackmatter-claude (`cohesion/u10-one-capability-vocabulary`).
- **The re-audit** (criterion 3), and a red run of each §10.3 gate (criterion 4).

### 9.3 How a wave runs

1. Each unit is built in its own worktree (`blue-uN`, branch `cohesion/uN-slug`) from one base, with its locks and a red run.
2. A reviewer reads the diff and checks the main lock against the base. A unit goes back only for a blocking issue, or for a should issue that changes behaviour or the truth of a claim.
3. One integrator picks every approved unit onto `cohesion/wave-N`, regenerates once, records each ledger once, and runs the land's gates. The wave lands with `git land`.
4. A held unit carries into the next round with its review.
5. Waves overlap: a wave builds on the previous wave's integration head while that one lands.

Two traps hold when agents share one repository. `git stash` is shared by every worktree, so a guard ref makes it fail while waves run. A running workflow agent cannot take a message: a message starts a second copy that writes in the same worktree.

### 9.4 Pace, measured on wave 0

- Wave 0 has 14 units. Its first pass took 9 hours with 58 agents and approved 5 units. A second pass approved 5 more in about 5 hours. 4 units need a third pass.
- One land takes about 2 hours 15 minutes of CI (run 45676636213).
- With 8 builders in parallel, that pace gives about 2 to 3 days for wave 1, 2 to 3 days for wave 2, and about 1 day each for wave 3 and the re-audit. This projection comes from one wave. Each land updates it.

## 10. No drift

The drift came from many parallel sessions. Each made a good local decision, and no step merged the concepts. Git merges code; nothing merged the ideas. These rules make that merge part of every change. They hold after the freeze ends.

### 10.1 One table per concern

Each concern has one table. A new meaning is a row in it. A second table for the same concern is refused.

| Concern | The one table | Units |
|---|---|---|
| grammar: operators, powers, reserved words, forms | one grammar table that every reader is derived from and gated against | U18 |
| spellings | FORMS, and RULES rows with machine fixes | U15 |
| words and verbs | `docs/verbs/contracts.tsv` and the verb graph | U25, U53 |
| types and binders | one type grammar in blue-lang-syntax, with one accepts relation | U19, U49 |
| patterns | one pattern language for `case` and `receive` | U63 |
| absence and errors | umu, kyohi's ledger, snake-case kinds | U4, U23, U46 |
| data and codecs | one value walk, and one codec door in deeta | U22, U48 |
| capabilities | `Capability::ALL` | U10 |
| switches and bounds | one switch registry | U29, U65 |
| levers | one lever table | U36 |
| configuration | settei | U14, U60 |
| time | one clock per run | U31 |
| doors | one door builder | U28 |
| definitions and names | one recognizer and one resolver in blue-lang-syntax | U12, U73 |
| facts | mondou's emitter, ROADMAP R6 | U40 |
| renderings | one source for each rendered file | U39 |
| ratchets and ledgers | the hadome ratchet ledger | U8 |

### 10.2 The concept merge

After the freeze, a change that adds a meaning lands only when all five hold. A meaning is a word, form, operator, flag, entry, switch, capability, evaluator or placement.

1. No word or form already has the meaning: `blue arika word NAME` and `blue arika like FILE` find none. A near miss is extended, never copied.
2. The change adds a row to the one table in §10.1 that owns its concern.
3. It carries its contract row or rule row with a witness, and its fixer when it replaces a spelling.
4. It carries spec rows that every evaluator column judges, or a pending mark that names a gap.
5. Its docs link checked evidence for every claim they make.

### 10.3 Gates that fail on a second way

| Gate | It refuses | Units |
|---|---|---|
| the reuse census, `blue census --reuse` | a definition copied between scopes | live |
| the reader differential | a reader that disagrees with the one grammar table | U18 |
| the verb graph check | a word with no contract row, or a second word for one contract | U25, U53 |
| canonical forms | an older spelling with no machine fix | U15 |
| markdown laws | a doc claim with no checked evidence, and a doc that teaches a refused spelling | U9, U13 |
| conformance columns | an evaluator that disagrees with the walker and names no gap | U6, U59 |
| the switch registry | an unknown switch value | U29 |
| hadome ratchets | a rise with no receipt, and a blind measure read as green | U8 |

### 10.4 The re-audit

The lenses of [cohesion/LENSES.md](cohesion/LENSES.md) run again at three times:

- at 100 %, for criterion 3;
- before each minor version of blue;
- after any two weeks that land more than 150 commits on main.

A confirmed finding of a re-audit becomes a unit of this plan, and the plan stays open until a re-audit is clean.
