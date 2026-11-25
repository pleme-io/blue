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
