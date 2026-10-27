# CLI-TUI — one way to build a command line and a terminal interface in blue

Status: DESIGN, 2026-10-27. Layer 1 (arguments and line output) is BUILT; §9
marks each piece.

## 1. Destination

Every command and every terminal interface pleme-io writes in blue reads its
arguments, prints its output and draws its screen through the same words, so
they all look and behave alike: the same help layout, the same refusals and
exit statuses, the same symbols and colours, the same keys. A program declares
what it accepts and what it shows; blue derives the help, the completion, the
plain fallback, the layout and the event loop. A new command is a spec and a
function, never a hand-written parser or a hand-written escape sequence.

## 2. What exists (recon, 2026-10-27)

| Piece | Where | State |
|---|---|---|
| styled text: SGR flags, ANSI-slot inks, truecolor `fg`/`bg` from a theme, `NO_COLOR` | `gamen` (`styled`, `show`, `inks`, `theme`) | built |
| step lines with ✅ ❌ ⚠️ ➖ ⏳ and durations | `gamen` (`step`, `show_step`, `step_marks`) | built |
| whether a stream is a terminal | `gamen::terminal?`, by running `test -t` | built, through a process |
| CLI arguments | none: `souji`, `heni`, `tehai`, `kijun`, `kirikae` and the `blue` tools parse `--flag` by hand (`BIDAMA-COHESION.md` C4 counts 14 bidamas) | absent until `hikisuu` |
| terminal input: a line, a key, raw mode, the window size | none; the runtime has `argv`, `getenv`, `write_stdout`, `write_stderr`, `exit_with` and nothing that reads stdin | absent |
| design tokens | `ishou` (`ishou-tokens`: `SemanticRoles`, the Nord and Vellum themes) is the source of truth; `irodori` holds Nord | Rust |
| the house CLI look | `kazari` (Rust): roles, the sixteen-colour fallback line, severity glyphs, rounded boxes, braille spinner, eighth-block meter, capability probing (`NO_COLOR`, `COLORTERM`, `TERM`) | Rust |
| the house TUI | quadro (`theory/QUADRO.md`): egaku widget state machines, egaku-term cell buffer with diff flush, one event loop, typed `Event` in and `Action` out, `MinSize` gate, synchronized output | Rust |
| the blue agent TUI | `arnes`: a Rust kernel on egaku-term and crossterm; its blue host functions have no terminal words | Rust kernel, blue behaviour |

Two facts set the design. First, the house look already exists as data in
kazari and ishou; blue must take it, not invent a second one. Second, every
input path (a prompt, a key, raw mode, the window size) is a host effect blue
does not have; output needs nothing new.

## 3. Layers and where each lives

| Layer | Words | Bidama | Pure blue or host |
|---|---|---|---|
| arguments | `parse`, `render`, `complete`, `script`, `outcome`, `command` | `hikisuu` | pure, except `command`, which reads `argv` and calls `exit_with` |
| line output | `tone`, `mark`, `verdict_marks`, `table`, `tree`, `meter`, `spinner`, `cells`, `plain` beside the existing `styled`, `show`, `step` | `gamen` | pure; `show` writes |
| interaction | `prompt`, `confirm`, `choose` | `gamen` | blue logic over one new host word, `read_line` |
| screen | layout, widgets, focus, keymaps, the event loop | `gamen` (views), `saishikou` (supervision) | blue logic over the `Terminal` capability |

**Decision: line output extends `gamen`; it is not a new bidama.** The verb
graph already places `show`, `paint`, `progress`, `prompt` and `choose` in the
`gamen?` space, and `gamen` already owns the inks, `NO_COLOR` and the step
line. Rejected: a separate output bidama (it would split one space in two and
copy `styled`, `writer` and `colored?`, which the distribution's duplicate gate
refuses); putting tables in `moji` (text has no colour, and a table cell is a
styled node).

## 4. Arguments: `hikisuu`

**The model is a declared spec read into one record.** A spec is a plain
record: `name`, `about`, `flags`, `positional`, `commands`. `parse(args, spec)`
returns one record holding every flag, every positional, `command` and `help`.

| Question | Answer | Rejected |
|---|---|---|
| how a flag is typed | from its default: `true`/`false` is a switch, a whole number takes `N`, text takes `TEXT`; a record form (`default`, `kind`, `min`, `about`, `value`) covers a nil default and a floor | a type annotation per flag (a second copy of what the default already says); a builder API (`flag(...)` chains), which is not data and cannot be rendered |
| how a flag is spelled | from its key: `dry_run` is `--dry-run`; `--name value` and `--name=value` both read; `--` ends the flags | a separate `long:` field per flag (two names for one thing); single-dash long flags |
| subcommands | `commands:` holds names or records with their own `about`, `flags` and `positional`; global flags apply to every command, a command's flags only to it; a key declared twice is refused | nested command trees (no pleme-io command needs them yet; a command record can grow `commands:` additively) |
| refusals | every fault in a line is collected and raised as one `:usage` error, `e.data.problems` holding each; a bad spec raises `:bad_option` naming the flag, checked whole before any line is read | stop at the first fault (the user fixes one, reruns, meets the next); a `{error:}` record return (the shape the hand parsers used, which every caller had to branch on) |
| exit status | `:usage` is kyohi's ledger kind, exit 64 (EX_USAGE); `command` prints `name: problems`, the usage line and `try name --help` on stderr | a per-program `raise(:souji_usage, ...)` (the old form, which exited 1) |
| help | `render(spec, command)`: title, usage line, commands, arguments, aligned flags with defaults; `-h` and `--help` are hikisuu's own and a spec may not declare `help` | a hand-written usage string (it drifted from the parser in souji) |
| completion | the program answers `prog __complete WORDS...` itself (`complete`), and `script(spec, shell)` renders the bash, zsh or fish hook that calls it | static per-shell scripts listing every flag (three renderings to keep fresh, and wrong the moment a command's flags differ) |
| where effects live | `outcome(args, spec)` is pure and says help, complete, usage or run; `run_with` applies it to given sinks; `command` binds the sinks to stdout, stderr and `exit_with` | parsing inside `command` (untestable without a process) |

Proof, 2026-10-27: `souji` and `heni` dropped their `parse`/`parse_flags` pairs
for a `cli` spec and `hikisuu::command`; `souji --help`, `souji __complete
rust --` and a bad line (exit 64, both faults named) were run by hand.

## 5. Line output: `gamen`

**Colour is a role, and a role is an ANSI slot.** `role_inks` is kazari's
sixteen-colour line: primary cyan, text bright white, muted white, dim and
border bright black, error red, warning yellow, pending bright yellow, success
green, info blue, ident magenta. A pleme-io terminal maps those slots to Nord,
so the output shows ishou's palette while blue carries no hex (the rule
`LESSONS.md` already states for the wordmark). `tone(text, role)` paints by
role. Truecolor stays available through `gamen::theme` for a program that
declares its tokens. Rejected: copying ishou's hex into blue (a second palette
that drifts); probing `COLORTERM` to upgrade to truecolor (the slot line is
correct on every terminal, and the theme path covers the rest).

**Symbols are the house's.** `mark(state)` gives the step marks (✅ done,
❌ failed, ⚠️ warn, ➖ skipped, ⏳ running) and the verdict circles (🟢 pass,
🟡 partial, 🔴 fail). One symbol per state; a symbol replaces a word, never
decorates one. Rejected: kazari's text glyphs (`✓ ⚠ ✗`) for blue programs (the
operator's surfaces use the emoji set; kazari keeps its glyphs for Rust).

**Width is measured in cells.** `cells(text)` counts what a terminal draws:
two for East Asian wide letters and emoji, none for a joiner or a combining
mark, one more for the emoji selector after a narrow symbol (⚠️). Tables and
trees align by it, so a column of ✅ and ❌ lines up.

| Shape | Word | Rule |
|---|---|---|
| table | `table(rows, {columns, headers, align})` | bold header, a `─` rule in the border ink, two spaces between columns, right alignment on request, no line ends in spaces, a cell is text or a styled node |
| tree | `tree({label, children})` | `├──`, `└──` and the `│` rail in the border ink |
| progress | `meter(fraction, width)` | kazari's eighth blocks on a `─` track, clamped to 0..1, always `width` cells |
| busy | `spinner(tick, :braille or :ascii)` | kazari's frames |
| step | `step`, `show_step` (existing) | mark, `[at/of]`, bold name, note, duration |
| diff | (planned) | `+`/`-` lines in success and error inks, through `danpen-diff` |

**Plain output is the same node with colour off.** `show` paints only when
`NO_COLOR` is unset or empty, and `show_step` also only when the stream is a
terminal; `plain(node)` drops every style. Symbols stay in plain output: they
carry state, and a pipe reader needs it as much as a person does. Rejected:
stripping symbols when not a terminal (it loses the verdict), a `--color`
flag on every command (`NO_COLOR` is the standard).

## 6. Interaction

`prompt(question, opts)`, `confirm(question, opts)` and `choose(items, opts)`
are blue over one host word, `read_line()`, a line from stdin or nil at end
of input. When stdin is not a terminal and no default is given, each refuses
with `:usage` naming the flag that answers it (`--yes` for a confirm), so a
script never hangs on a question. `choose` is a numbered list in line mode and
a selection widget in screen mode. Rejected: reading through `exec` of
`sh -c read` (a shell, and no way to tell end of input from an empty answer).

## 7. Screen: the TUI layer

**One loop, Elm-shaped, as a supervised process.** A screen program is
`init`, `update(model, event) -> model` and `view(model) -> node`. The view is
gamen nodes laid out by `layout` (stack, row, grid) into a cell grid; the
runtime diffs the grid against the last frame and writes only the changed
cells, inside a synchronized-output frame (DEC 2026), as quadro does. Events
(keys, resize, ticks, messages from other processes) arrive in the loop's
mailbox. The loop runs under a supervisor from `blue-lang-proc` with its
restart policy from `saishikou` (`BUILD-STACK.md` §5.1), and the terminal is
restored on every exit path, crash included, because restoration is the
supervisor's `terminate`, not the program's.

| Question | Answer | Rejected |
|---|---|---|
| widget state | records in the model; widgets are pure functions of state to nodes (list, table, input, tabs, status line, dialog) | stateful widget objects (state the model cannot see) |
| focus | a focus ring derived from the view's focusable nodes, in order (`gamen`'s `focusable?` and `order` rows); Tab and Shift-Tab move it | focus held by hand in each program |
| keys | a keymap is data, `{key: action}`, judged by kousei (each entry refused alone; a key bound twice is a refusal) | key matching in `update` |
| size | a `min_size` gate: below it the view is one line saying the size it needs | drawing a broken layout |
| theme | the same roles as §5 | a TUI palette separate from the CLI one |

**The host primitive is one capability, `Terminal`,** added to
`blue_lang_waku::Capability` beside `Environment`, so a frame that may read
the environment has not thereby been allowed to take over the terminal:

| Word | Meaning |
|---|---|
| `term_size()` | `{cols, rows}`, nil when not a terminal |
| `term_raw(on)` | enter or leave raw mode and the alternate screen; leaving restores the saved mode |
| `term_event(timeout_ms)` | the next key, paste or resize as a record, nil on timeout |
| `read_line()` | a line from stdin, nil at end of input |
| `is_terminal(fd)` | replaces `gamen::terminal?`'s `test -t` process |

Rust holds only these five (a termios call and an event decoder, through
crossterm behind one seam, per CONTAIN THE C); everything above them is blue.
Rejected: binding ratatui or egaku as host functions (the widgets would be
Rust, and blue grows only by what it cannot express); `stty` through `exec`
(a process per keystroke, and no restore on crash).

## 8. What this replaces

The hand parsers in `tehai`, `kijun`, `kirikae` and `blue`'s own `verbs`,
`doc` and `migrate` tools move to `hikisuu` (C5 in `BIDAMA-COHESION.md`); the
`hand-rolled-flags` rule in `STDLIB.md` W4 then turns the pattern into a
check-stage warning. kensa's hand-written ANSI reporter is a Rust instance of
the same class and moves to kazari (`theory/KAZARI.md`).

## 9. Build order and state

| Step | Work | State |
|---|---|---|
| L1 | `hikisuu`: spec, parse, help, completion, `command`; `souji` and `heni` migrated | BUILT 2026-10-27 |
| L1 | `gamen` line output: roles, marks, verdict circles, cells, table, tree, meter, spinner | BUILT 2026-10-27 |
| L2 | `Terminal` capability with `read_line` and `is_terminal`; `prompt`, `confirm`, `choose` | DESIGN |
| L3 | `term_size`, `term_raw`, `term_event`; the cell grid and diff flush; the supervised loop; widgets, focus, keymaps | DESIGN |
| L4 | the remaining hand parsers and `hand-rolled-flags` at warning | DESIGN |
