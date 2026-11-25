---
kind: explanation
summary: the plan for blue implemented in blue; rungs, dependencies, invariants and order for every track
---
# Pure blue — the implementation plan

**Tier: DESIGN (2026-11-17).** Nothing here is built unless a row says so. This file is the
single source for rungs, dependencies, invariants and order; the track docs under
[`pure-blue/`](pure-blue/) map each rung to the code and do not restate dependencies.

## 1. The destination

1. **Pure.** Every byte of blue's toolchain that runs (reader, expander, checker, formatter,
   compiler, runtime, standard library) is blue source, or machine code that blue emitted from
   blue source. Four facts of the world stay outside, each a typed seam of data, never code in
   another language:
   - the instruction set;
   - the kernel's system call ABI;
   - executable formats (ELF, Mach-O);
   - on macOS, the `libSystem` dynamic imports, because Apple gives no stable raw syscall ABI.
2. **Rust's discipline is the floor, and the compiler proves it.** One owner per value, a
   value freed at its owner's last use, sharing only through a counted handle. Rust makes the
   author prove ownership to the compiler; blue makes the compiler prove it for the author (§4).
3. **Blue all the way down.** `blue` compiles itself to the same bytes twice, and the tower
   ends at a full-source chain from a seed small enough to audit as hex (Guix style). The
   binary seed is a stepping stone, retired at S4.
4. **Two runtimes, one language.** The pure native build is the default. The Rust
   implementation stays a fully supported fallback runtime, and also the independent witness
   for diverse double-compiling. Both are held to the same conformance suite, permanently.
5. **Every build is a selectable configuration.** Runtime, front end, backend, seed and memory
   model are entries of one module-trio registry, chosen per node, per project or per run, with
   the reusable builders in substrate (track D).
6. **Linux first.** x86-64 Linux; aarch64 macOS follows.

## State (2026-11-18)

Built and on main, each with its lock:

| Rung | What exists | Where |
|---|---|---|
| S0 | purity ledger, 25 crates, a ratchet | `gen/purity.b` |
| L0 | rebind census (set!, while, repeated define), a ratchet | `gen/mutation-census.b` |
| L1 | typed cells `cell`, `cell_get`, `cell_put`; every rebind a closure can see migrated, the census at 0 | `crates/blue-lang-runtime/src/cell.rs`, `spec/rows/cells.b`, `gen/mutation-census.baseline` |
| L2 | `u8`..`i64` in `Ty`, compatible with `Int`; a literal argument out of its parameter's range is B0005; arithmetic keeps its operands' width, and a mix of widths or a literal operand that does not fit is B0004; width words in kazu (`low_bits`, `as_signed`, `unsigned_bounds`, `signed_bounds`, `fits`), which kaaneru's bpf width words now call; a returned literal is held to the declared width (B0003); bpf's `mask32`, `low32` and `sign32` declare u32, u32 and i32 | `crates/blue-lang-check/src/lib.rs` |
| L3 | `gensym` per interpreter and fork | `crates/blue-lang-runtime/src/stdlib.rs` |
| M1 (first slice) | `last_use` facts, read from Perceus's own output over the resolved tree (a use no `dup` precedes is the last one), per definition, each naming the source form that consumes the name, through branches and `try`; kuzushi reads the resolved tree's local `define`; `facts([...])` rows judged in-process through blue-lang-host | `bidamas/kuzushi` (`memory_facts`, `last_uses`), `spec/rows/memory.b` |
| B0 | nanopass core: languages, passes, checks | `bidamas/henkan` |
| B1 | A-normal form, Perceus with a reference-count checker, closure conversion, cond and case, and and or, raise and try with explicit propagation (a failing primitive trapped to the nearest try), global functions; borrow inference (`whole_in(form, :borrow)`: a global's parameter only read is borrowed, a greatest fixpoint over the call graph, so Perceus emits no dup or drop for it and a caller keeps what it lends; the dup/drop count in the four borrow-shaped test programs' functions falls 1→0, 6→4, 10→7, 6→4; a parameter a self tail call passes an owned name stays owned); `ir_eval` and `checks.ir-conformance`, the `ir` conformance column: every value row's resolved core lowered and run by kuzushi, an accepted row giving the walker's value with zero live, the agreeing count a ratchet (2026-11-21: 651 value rows, 138 accepted, 138 agree); the IR front `kuzushi/front` (chuuzou's reader, names, records, types, recursion, ranges and read counts moved in; chuuzou is the IR to Rust AST backend, its corpus unchanged), timed over `chuuzou.b` on the walker at 1.2 s before and 0.37 s after (the reader 835 ms to 18 ms); hashiru's calling convention a setting, `:borrow` since 2026-11-21 (the native column: 157 rows under `:borrow`, the ledger `:owned` holds; it was 133 owned, 116 borrowed before hashiru learned to lend natively) | `bidamas/kuzushi`, `bidamas/kuzushi/front`, `gen/ir-row.b`, `gen/ir-rows.baseline` |
| B2 | x86-64 encoder, 2856 instructions byte-identical to llvm-mc (the overflow condition `o` among them since B3) | `bidamas/kikaigo`, `checks.x86-isa-llvm` |
| B3, R1-R3 | native code: tagged values, a free-list allocator, recursive drop, closures, recursion, lists, strings, keywords, maps, errors, string join and content equality, structural list equality, system calls; a list prelude in blue (append, nth, reverse, map, filter, reduce); the overflow fault stub (a tagged `+`, `-` or `*` that leaves the 63-bit range jumps to `rt_overflow`, which ends the program with 1, as `blue run` does, never with a wrapped Int); `checks.native-x64-corpus` (x86_64-linux): every `native/corpus` program compiled by hashiru and run against the interpreter, its output and its exact exit status, 11 programs, 4 agreeing, 7 refused by name in `native/checks/x64.refused`, which only shrinks and holds each refusal's reason (a moved reason and a crash are red; `blue run native/checks/corpus.b record` writes it again) | `bidamas/hashiru`, `native/checks/corpus.b`, `nix/native.nix` |
| R4 (four slices) | `write_stdout` (the native op that was named `print`, renamed to what it does; `print`, which shows a value as blue does, is refused natively until it can), `exit_with` as an exit system call, `read_file` (open, fstat, one block, read, close), `write_bytes` (a list of bytes gathered into one block, created or truncated, written, closed), the clock words `now`, `now_ms`, `now_ns`, `elapsed_since`, `sleep`, `sleep_ms` (clock_gettime, nanosleep), `self_exe` (readlink of /proc/self/exe), `exec_check` (fork, the command found on the inherited PATH as a shell finds it, execve, wait4), `exec_capture` (two pipes read by poll, so neither stream can block the other), `exec_with_env` (a name=value environment built on the stack, a listed name replacing the inherited one), `exec_with_stdin` (a third pipe fed from the same poll loop, PIPE_BUF at a time), the first socket word, `tcp_connect_ms` (a non-blocking connect, poll, SO_ERROR; a dotted IPv4 address, an /etc/hosts name, or a name DNS gives an IPv4 address), the TCP words `tcp_listen`, `tcp_port`, `tcp_accept`, `tcp_connect`, `tcp_read`, `tcp_write` and `tcp_close` over handles (a block of kind 6 holding the descriptor; natively the empty list is nil, so a peer's close reads as nil and closes the handle, which net_wait reports :closed), and `net_wait` over poll(2), level-triggered as the reference is (its keywords passed from the call site, the pollfds in one scratch block), and the terminal words `is_terminal` (TCGETS) and `read_line` (a byte at a time, nil at the end), and the output words C3's corpus prints with, `put_int` (digits built in the frame, one write) and `put_byte`; the host words of `spec/rows/host.b` (type predicates, `getenv`, `env_required`, the `path_*` words, `mkdir`, `mkdir_p`, `rm`, `rm_rf`, `rename_file`, the stat words, `write_file`, `append_file`, `read_bytes`, `ls`, `argv`, `argv_get`, `cwd`, `random_bytes`, `exec_ok?`), with `or`, `and`, `every?` and bare zero-argument words lowered before ANF; a `:show` mode, so the conformance native column observes any value as its literal, not only an exit status (false is its own word, 4, which an if takes as not holding, and the empty list its own word, 6); a path that does not open is an error carrying its errno; blocks of 64 words or more are their own mapping, so the native heap is bounded and large strings fit | `bidamas/hashiru` (`HOST_PROGRAMS`) |
| B4 | static x86-64 ELF executables | `bidamas/kaaneru/erufu` |
| D0 (substrate half) | the bidama builders in substrate | `substrate/lib/build/blue` |
| D1 | `overlays.bidamas` wraps the package set's own `blue`, so an override reaches every bidama tool | `flake.nix`, `checks.overlay-reads-final-blue` |
| D2 | the `pleme.blueToolchain` registry: five entries, an incoherent permutation refused by the entry type, a not-yet entry refused by its rung | `substrate/lib/build/blue/toolchain.nix`, `checks.blue-toolchain` |
| D3 | a Bluefile names its toolchain with `toolchain(entry)`; the project engine checks it against substrate's registry, refusing an unknown name and an entry whose rung has not landed, and builds with `rust` | `crates/blue-lang-pkg/src/bluefile.rs`, `nix/project.nix`, `checks.toolchain-selection` |
| D4 | the nix fleet imports the blueToolchain concept on every NixOS and darwin node, its `packages` from one table (`lib/blue-toolchains.nix`) that the fleet's blue overlay also reads; nodes select with `pleme.blueToolchain.selected`, every node on `rust` with its toplevel drvPath unchanged | nix `06eeca94`: `modules/pleme/shared/blue-toolchain.nix`, `lib/blue-toolchains.nix` |
| D5 | `checks.toolchain-matrix`: every buildable registry entry (no rung pending) has a row that builds `blue` and runs conformance; a buildable entry without a row is refused at evaluation, and the check proves that refusal on a made-up second entry. One row today, `rust` | `flake.nix`, `nix/toolchain-matrix.nix` |
| M2 (first slice) | `blue explain --memory FILE` prints the ownership facts kuzushi reads, one per line, from a blue program the CLI embeds (`crates/blue-lang-cli/blue/memory.b`); the conformance `cli` column now observes `facts` rows through it, so each M1 row is judged in-process and on the CLI | `crates/blue-lang-cli/blue/memory.b`, `crates/blue-lang-test/tests/conformance/eval.rs` |
| R6a (first slice) | `deeta::read`, a JSON reader in blue: it gives the values `json_parse` gives, objects as key-ordered pairs with the last value of a repeated key, an empty object as the empty map, numbers held to JSON's grammar (a Float for a fraction, an exponent, `-0` or a value past what an Int holds, else an Int), `\\u` escapes with surrogate pairs; it agrees with `json_parse` on all 259 `in.json` fixtures that `json_parse` accepts, refuses the 23 it refuses, and agrees on 17 number edges (`-0`, `+1`, `01`, `1.`, `.5`, `1e400` and past what an Int holds among them) | `bidamas/deeta/deeta.b`, `crates/blue-lang-yaml-diff/tests/json_agree.rs` |
| R6a (JSON writers) | `deeta::write` and `deeta::stringify`, JSON writers in blue: the exact text of `json_write` and `json_stringify`, a list of pairs as an object only in `stringify`, keys in byte order with the last of a repeated key kept, floats in ryu's layout from `to_s`'s shortest digits, a float key in Rust's `Display` layout from the same digits (`1000000000000000000000`, never an exponent), control characters as `\\u00XX`, NaN and infinity as null; both agree with Rust on every accepted `in.json` fixture and on 37 edge values | `bidamas/deeta/deeta.b`, `crates/blue-lang-yaml-diff/tests/json_agree.rs` |
| R6a (BLAKE3) | `shomei::blake3`, BLAKE3 hash mode in blue: chunks of 1024 bytes in 64-byte blocks, the seven-round compression over a 16-word state, the parent tree with the largest power-of-two left subtree; it gives `blake3_hex`'s digest at every length from 0 to 4097 bytes across the chunk and tree boundaries | `bidamas/shomei/shomei.b` |
| R6a (SHA-256) | `shomei::sha256`, SHA-256 in blue: the standard padding, the 64-word schedule, the 64 rounds with the round constants read from their hex text; it gives `digest_hex(:sha256, …)` at every length across the 55/56-byte padding edge and one, two and many blocks | `bidamas/shomei/shomei.b` |
| R6a (SHA-512) | `shomei::sha512`, SHA-512 in blue with each 64-bit word a [high, low] pair of 32-bit halves (blue's Int is signed 64-bit and checks overflow): 64-bit add with carry, rotate and shift across the halves, the 80-word schedule and 80 rounds; it gives `digest_hex(:sha512, …)` at every length across the 111/112-byte padding edge and one, two and many blocks | `bidamas/shomei/shomei.b` |
| F1 (lexer) | `yomi`, blue's reader in blue: `yomi::lex` gives the tokens and byte spans of `blue-lang-syntax`'s lexer (strings with escapes and interpolation, heredoc docs, word lists, labels, symbols, numbers, operators and their typographic aliases) and refuses what it refuses; `yomi` owns the operator table, which `kigou.b` now renders from it | `bidamas/yomi/yomi.b`, `crates/blue-lang-kiwari/tests/reader_in_blue.rs` |
| R6c (Nix) | `deeta::parse(text, :nix)` (`nix_document`), rnix 0.14's tokenizer and parser in blue: the lossless tree `nix_parse` gives (node and token kinds, character offsets, trivia where rowan puts it, rnix's `{` lookahead and its bare-`or` and path-interpolation quirks), and `:nix_malformed` for every source rnix reports an error in (its depth limit of 512 too), so `errors` is always `[]`. Measured 2026-11-20: all 24 `.nix` files of this repository and all 97 of the fleet repository's `lib/` identical; a wider sweep (the fleet repository, substrate, nixpkgs `lib`, `nixos/lib`, `pkgs/build-support`) 2,758 of 2,759 identical, the last refused by both. The hot definitions are `volatile`, so `blue run`'s planned memo (which deeta's YAML reader turns on) does not hash the token list per call: 3.5 KB in 0.1 s, 54 KB in 0.7 s | `bidamas/deeta/deeta.b` |
| R6c (YAML, XML) | YAML is read in blue already: `deeta::parse(text, :yaml)` (`yaml_documents`), held to yaml-rust2 over the yaml-test-suite (`crates/blue-lang-yaml-diff/tests/agree.rs`), with no YAML builtin in Rust. XML: `deeta::parse(text, :xml)` (`xml_document`) gives the element map `xml_parse` gives: comments, CDATA, processing instructions, a DOCTYPE refused when it declares an entity, attributes with either quote, the five predefined entities and character references, the text rule (white-space runs dropped beside element children), and the same `:xml_malformed` and `:xml_refused` refusals | `bidamas/deeta/deeta.b` |
| C1 | the native conformance column: every value row compiled by blue's own backend and judged against the walker, its passing count a ratchet (18 rows on 2026-11-18); a call to a global function with the wrong number of arguments is refused before code is made; since 2026-11-25 every row compiles in `:show` mode and is read from what it writes, never from its exit status, a compile exits 3 only for a gap (blind) and 5 for a crash (red), the one contract `kuzushi::exit_for` gives both backend row drivers, a name nothing native binds is refused before code is made, and every literal `blue ast` writes is decoded once by `kuzushi::literal_of` (193 of 651 value rows compile, 192 agree, 1 pending on G29, measured on rio 2026-11-25) | `crates/blue-lang-test/tests/conformance`, `gen/native-row.b`, `spec/native.baseline`, `checks.conformance-three-way` |
| C3 | the `bluec` path in `bench/bench.b native`, keyed `linux`: each corpus program compiled by hashiru through `gen/native-row.b` in `:run` mode, its output held to the Rust twin's, timed; bluec/Rust CPU on rio: fib 13.6x, loop 28.9x, mutual 3.0x (start-up bound); shapes (records) and sums (`reclaim`) refused by name; a program with a row that bluec stops compiling is red. hashiru gained a board `use` of `put_int`/`put_byte`, `define-typed` erased, native `mod` | `bench/bench.b`, `bench/native.baseline`, `bidamas/hashiru`, `gen/native-row.b`, `checks.native-bench` |
| C2 (first slice) | the `leaks(N)` expectation: the bytes one run leaves live, read from the counting allocator on the walker and the VM (a warm-up run, then the mean of three); 3 rows hold `leaks(0)` (a built list, a closure and its captures, a replaced cell), and a probe that keeps its runs live reads 65-67 bytes, so the rows can fail | `crates/blue-lang-test/tests/conformance`, `spec/rows/memory.b` |

Proven on x86-64 Linux: 59 programs across every feature, compiled by blue with no other
language in the path, give their value and end with 0 blocks live.

Not yet: the 7 corpus programs hashiru refuses (`native/checks/x64.refused`); M3a, `Env::take`; M1's other kinds (borrow, unique, escape, reuse), spans and the def-hash cache; M2-M5 on the Rust runtime; B5; R4's last host row (`write_program`, which needs the formatter natively, F1-F4); its home column landed 2026-11-21 (82 names native) and R5 beyond its first commit (native spawn, self, send, receive with a pattern and a timeout, alive?, exit, link, unlink, spawn_link, trap_exit, monitor and demonitor, and spawn_server, supervisor, children and supervisor_adopt as prelude words over them, cooperative, landed 2026-11-22; timers on node time, landed 2026-11-24: `node_time`, `sleep_for`, and `sleep_until` and `after` as prelude words over them, on a virtual clock that starts at 0 and jumps to the earliest wake when only sleepers are left, as `blue test` keeps it; defmigrate, deadlines and preemption are next), R6-R7
beyond the raw words; the front end in blue (F1-F4); the tower (S1-S5); C2 beyond `leaks` (`closes_at`, cycle-through-cell, move vs copy, and I3 over every row); D6.

Next, in order (2026-11-19). Every open rung whose dependencies in §7 are met, each with its
first commit in its track doc. Take the top one; when a rung lands, record it in the table above
and recompute this list from §7.

1. **B1 is done** (§B1): the front moved into `kuzushi/front` and timed (1.2 s to 0.37 s over
   `chuuzou.b`), `checks.ir-conformance` at 138, and hashiru compiles under `:borrow` (157 native
   rows, the ledger `:owned` holds). Each primitive or form kuzushi learns raises the ir ratchet.
2. **R4, the rest** (§R4): time, processes, sockets, epoll, the terminal, then `put_int` and
   `put_byte`, which C3 needs (both landed natively). Critical path: R4 → R6a → S1.
3. **R6a** is done (JSON reader and writers, BLAKE3, SHA-256, SHA-512, each differential against its Rust word). Its exit, the json and hash rows passing natively, waits on the native backend (R4).
4. **F1** is done: `yomi::parse` reads all 457 distinct `.b` files as blue's parser does (`checks.reader-differential`), and the consumers sweep holds the fleet's files to it.
5. **M2** is done: `blue explain --memory` and `--hints`, `local_reads`, and the language server serving the memory hints with live evaluation off and beside the value hints with it on.
6. **C2** is done: `closes_at` counts every host handle kind (TCP, serial, HTTP, NATS, Postgres, RESP, the wire, kernel fds and the display canvas); move vs copy moved to R5 (in the Rust runtime every send deep-copies immutable data, so nothing tells a move from a copy until processes own their heaps). Done: `closes_at(:end)` for TCP and serial handles on the walker and the VM, cycle-through-cell (the VM's letrec ring, an aliased compiled closure and a closure in a list only its frames hold, all released in tatara 0.4.26), and `checks.no-leak` (I3) on the walker and the VM with `spec/leaks.baseline` empty.
7. **B3 is done** (§B3): `checks.native-x64-corpus`, 4 of 11 corpus programs agreeing natively, 7 refused by name (`native/checks/x64.refused`); each one hashiru learns removes a row.
8. **R6c** is done (YAML, XML and Nix read in blue, each differential against its Rust word). Its exit, the format rows passing natively, waits on the native backend (R4).
9. **C3** is done: the `bluec` path in the benchmark, `linux` rows, `checks.native-bench` (I7).

Waiting on others' rungs: M3 (M1, C2), M4, M5, R5 (M4), R6b, R7, F2-F4, S1-S5, B5, D6.

In flight (2026-11-20, for the next session):

- **Landed since 2026-11-19.** tatara-lisp-eval 0.4.24 (M3a early reuse, `Interpreter::on_release`, the closure-argument release) is published and blue requires it; dispatch empties its handlers on release, and the leak ledger fell from 49 to 21 entries. The leak sweep no longer measures into itself (`leaks()` marks its thread). The memo retires a definition on its keying time (`Policy::key_budget`), so recursion that passes a large value is no longer quadratic under `blue run`.
- **C2 sweep.** `BLUE_CONFORMANCE_LEAKS=1` measures every value row on the walker and the VM against `spec/leaks.baseline` (record with `BLUE_CONFORMANCE_LEAKS_RECORD=1`; release build, stdin closed). The ledger is empty since 12dc0db4 (1,148 row-runs, 0 leave bytes live), and `checks.no-leak` holds it there.
- **F1.** `yomi::lex` agrees with the Rust lexer token for token over every `.b` file in the repo; the parser in blue is next.

## 2. Ground truth (measured 2026-11-17)

| Fact | Value |
|---|---|
| Rust in blue | 25 crates, 144,354 source lines |
| Rust from crates.io | tatara-lisp 0.4.23 (~95k lines; reader, expander), tatara-lisp-eval 0.4.23 (~25k; walker, VM). Eight other repos depend on tatara-lisp-eval, so a change to it is a fleet release |
| Blue | 600 `.b` files, ~246k lines |
| Already pure | the BPF path: `kaaneru/bpf` encodes BPF (7,610 lines), `kaaneru/erufu` writes ELF (2,302); byte-identical to `llvm-mc` on 166 of 166 instructions |
| Native today | `chuuzou` (3,386 lines) lowers the resolved tree to a Rust AST for rustc; its subset is Ints, records and Int lists |
| Speed | the walker runs ~790× slower than Rust per unit of work (`docs/PERFORMANCE.md` §1.4.1) |
| Value model (fallback) | `Value` holds `Arc` counts, copy-on-write; `cons`, `append`, `assoc` update in place, but only in tail position |
| Rebinds | `set!` 43 calls in 18 files; `while` 69 in 22 (a `letrec` macro over `set!`); `define` after capture, `letrec` and `delay` also rebind |
| `gensym` | a registered primitive only, so blue can override it without a tatara-lisp release |
| Types | `Dyn, Int, Float, Str, Bool, Sym, Nil, List, Map, Record, Union, Named, Fragment`; fixed-width `u8`..`i64` (L2) |
| Build surface | builders in this repo (`bidamas/mk-bidama.nix`, `nix/project.nix`); one `blue` per fleet; per-run `BLUE_DOOR` only |

## 3. Invariants

Each is a check that fails the build, from the rung named in "From".

| # | Invariant | Check | From |
|---|---|---|---|
| I1 | Every conformance row gives the same answer on the walker, the VM and native; the check holds the value rows native compiles, each read from `:show`, a refused row blind by its named gap and a crash red (193 of 651 value rows on 2026-11-25) | `checks.conformance-three-way` | C1 |
| I2 | Both runtimes free and close at the same points for every row that observes it | resource-timing rows | C2, held by M3 |
| I3 | No row leaks | `checks.no-leak`, live count zero at exit per runtime | C2, held by M3 |
| I4 | A cycle can form only through a typed cell | a checker rule; a fuzz row over every value shape | M3 (flat closures) |
| I5 | Raw-memory words are used only in the runtime subset | a check-stage rule | R1 |
| I6 | The hand-written non-blue bytes in the pure toolchain only fall, except by a receipted rise: a file a `generate` row renders from blue is not counted, a rise needs a typed receipt kept in the ledger, and a record banks every fall | `checks.purity-ledger` | S0 |
| I7 | Native speed never regresses | `checks.native-bench`, owned by C3: a ratio is judged on the machine that recorded it, and a program a path stops running is judged on every machine | C3 |
| I8 | The compiler is a fixpoint of its own source | `checks.pure-fixpoint` | S1 |
| I9 | The seed and the Rust witness rebuild the same bytes (DDC) | `checks.pure-seed-ddc` | S2 |
| I10 | The full-source chain rebuilds the seed | `checks.pure-full-source` | S4 |
| I11 | Every buildable toolchain entry builds and passes conformance | `checks.toolchain-matrix` | D5 |

## 4. Memory: inferred ownership

1. **Values are immutable.** A new value points only at older values, so ordinary data
   cannot form a cycle.
2. **Ownership is inferred.** Each value is freed at its last use (Perceus, as shipped in Lean 4
   and Koka). No lifetimes, no `&`/`&mut`, no borrow checker for the author.
3. **Borrowing is inferred.** A value only read inside a call is passed with no count change.
4. **Counts are the compiler's fallback** where sharing is real (where Rust makes the author
   write `Rc`/`Arc`). They are non-atomic inside a process.
5. **Reuse in place.** An update to a value whose count is one mutates it in place, in any
   position, not only a tail call.
6. **A heap per blue process** (the Erlang model). A message moves when uniquely held and is
   copied otherwise; a dead process frees its heap at once; counts never cross a process.
7. **Cells are the only mutation and the only cycle source.** A `cell` is a typed value; a
   small collector scans cells only. Closures are flat, so `letrec` and local `def` cannot
   build hidden cycles.
8. **Resources are values.** A file, socket or lock closes at its last use, without `defer`,
   `finally` or a finaliser.
9. **The cost model is visible.** The engine and the LSP report each fact: freed here, shared
   here, updated in place here, copied into a message here.

## 5. The method: Lisp

Blue's tree is tatara-lisp data, so: the IR is forms; every pass is a small rewrite between two
declared IR languages (nanopass, `defir`/`defpass`); Perceus, borrow inference and reuse pairing
are such rewrites; macros generate encoder tables and specialisations; the runtime is written in
a declared subset that needs no allocation (PreScheme); the bottom of the tower is a tiny Lisp
over blue forms (GNU Mes). Detail: [`pure-blue/lisp-layer.md`](pure-blue/lisp-layer.md).

## 6. Rungs

Eight tracks. Each rung ends at a check that fails without it. Dependencies are in §7 only.

| Track doc | Tracks |
|---|---|
| [`pure-blue/language-memory.md`](pure-blue/language-memory.md) | L, M |
| [`pure-blue/backend-runtime.md`](pure-blue/backend-runtime.md) | B, R |
| [`pure-blue/front-tower-conformance.md`](pure-blue/front-tower-conformance.md) | F, S, C |
| [`pure-blue/build-surface.md`](pure-blue/build-surface.md) | D |
| [`pure-blue/lisp-layer.md`](pure-blue/lisp-layer.md) | the method for all of them |

### L — the language

| # | Rung | Exit check |
|---|---|---|
| L0 | **Census of every rebind**: `set!`, `define` after capture, `while`, `letrec`, `delay`; rule `B0101 captured-rebind` with a ratchet; `blue census` loads `rules/mutation.b` | census count equals the ratchet; a rise fails `checks.namespace-census` |
| L1 | **Typed cells** `cell`/`cell_get`/`cell_put`; `B0101` active at 0; `blue migrate` rewrites `while`+`set!` to recursion or `reduce`, and sinks to cells | census 0; `spec/rows/cells.b` on walker and VM |
| L2 | **Fixed-width integers** `u8`…`i64` in `Ty`, width-aware `op_sig`, width words in a bidama | checker rows; kaaneru's hand width guards become typed |
| L3 | **Deterministic expansion**: blue's own `gensym` per interpreter, seeded by def-hash; lower → expand → check | two expansions of the corpus byte-identical |

### M — memory

| # | Rung | Exit check |
|---|---|---|
| M1 | **Ownership facts**: B1's Perceus and borrow passes in explain mode over the expanded tree, returning last use, borrow, unique, escape, reuse as data, cached by def-hash | `Expect::Facts` rows in `spec/rows/memory.b` |
| M2 | **Facts reported**: `blue explain --memory`; LSP hints without live evaluation | golden output per row; an LSP test |
| M3a | **Early reuse in the fallback runtime**: `Env::take` from a local liveness pass in tatara-lisp-eval, behind a flag off by default | a non-tail `assoc` in a fold updates in place (allocation count) |
| M3 | **The fallback runtime on the model**: `%move` marks from M1's cached facts, a VM `MoveLocal`, flat closures, cells as the only collector roots | I2, I3, I4 on walker and VM; a gain on `bench/cost.baseline` |
| M4 | **Per-process heaps** in `blue-lang-proc`: `send` moves a unique message and copies otherwise; forks stop sharing frames | move-vs-copy rows; a dead process's account falls to zero |
| M5 | **Non-atomic counts** (Lean 4's scheme): atomic only for a value marked shared across threads | the `Send + Sync` blockers gone; a benchmark gain |

### B — the backend

| # | Rung | Exit check |
|---|---|---|
| B0 | **Nanopass library** `defir`/`defpass` in blue | a pass emitting a form its target language forbids fails at expansion |
| B1 | **IR as forms**: ANF, closure conversion, Perceus `dup`/`drop`, borrow inference, `ir_eval`; chuuzou's front passes move in; chuuzou stays as the IR → Rust backend | `ir_eval` equals the walker on every accepted row (a ratchet), live count zero; the passes over `chuuzou.b` timed on the walker |
| B2 | **x86-64 encoder** (the `kaaneru/bpf` method), with branch relaxation, `movabs` imm64, SSE2 floats; `isa_llvm.b` and the new oracle become flake checks | `checks.x86-isa-llvm`: N of N byte-identical |
| B4 | **ELF executables**: `erufu` writes ET_EXEC with program headers | a hand-assembled exit program runs; `readelf` agrees with `erufu::decode` |
| B3 | **Code generation**: instruction selection, linear-scan allocation, the calling convention, the overflow fault stub, stack-depth guards, yield points | `checks.native-x64-corpus`; an `Ev::Native` column in conformance |
| B5 | **Optimisation**: reuse pairing, drop fusion, inlining, unboxing, specialisation, `cz_nonneg` on the IR | C3's benchmarks improve; none regresses |

### R — the runtime

| # | Rung | Exit check |
|---|---|---|
| R1 | **Raw seam and runtime subset**: `load_word`, `store_word`, `syscall6`; the runtime subset as a declared IR language; a rule confines both | I5; `write(1, …)` prints natively |
| R2 | **Allocator**: size-classed per-process heaps, counts, `dup`/`drop`/`reuse`, the cell collector, a live counter | `checks.no-leak` native |
| R3 | **Values**: UTF-8 strings with Unicode case tables, a persistent vector and sorted map (cross-kind key order), closures, errors, a packed byte value, shortest round-trip float printing and correctly rounded parsing, `render` byte-identical to Rust's | the value rows in the `Ev::Native` column |
| R4 | **Host words over syscalls**: files, time, `execve`/`fork`/`pipe`/`wait4`, sockets, `epoll`, terminal | the host rows natively; `docs/REFERENCE.md` gains a home column |
| R5 | **Processes**: scheduler, green stacks, mailboxes that move or copy, links, monitors, supervisors | the process rows natively |
| R6a | **JSON and hashes** (BLAKE3, SHA-2) in blue — what the compiler needs | json and hash rows natively |
| R6b | **Crypto**: Ed25519, X25519, ChaCha20-Poly1305, HMAC, Bao, FROST, ECDSA P-256, RSA with bignums | crypto rows; the ledger falls |
| R6c | **Formats**: Nix parsing, XML, YAML | their rows; the ledger falls |
| R7 | **TLS 1.3** over R6b | RFC 8448 vectors; the ledger at the four world facts |

### F — the front end

| # | Rung | Exit check |
|---|---|---|
| F1 | **Reader** emitted from the kiwari grammar (the kiwari parser rung, `docs/NATURALIZE-TREESITTER.md:254`), with spans and comments; oracle `blue ast --tree-json` | `checks.reader-differential`: 604 files identical, spans included |
| F2 | **Expander** in blue, running macro bodies on `ir_eval` | `checks.expand-differential` |
| F3 | **Checker** in blue, including import resolution | an `Ev::BlueFront` column agrees with `static`; a JSON differential |
| F4 | **Formatter** in blue | `Ev::BlueFront` on every `formats` row; `blue fmt` byte-identical |

### S — the stages

| # | Rung | Exit check |
|---|---|---|
| S0 | **Purity ledger** (`gen/purity.b`, hadome) | I6 |
| S1 | **The fixpoint.** Stage 0 is `bluec.b` built through IR → chuuzou → rustc (fast); stage 1 → `bluec₁`, `bluec₁` → `bluec₂`, `bluec₂` → `bluec₃`; `bluec₂ == bluec₃` | I8; `nix build --rebuild` bit-identical |
| S2 | **Binary seed and witness**: `seed/x86_64-linux/bluec` as a `generate` row; one walker build per seed as the DDC leg | I9; the default `blue` comes from the seed |
| S3 | **Two runtimes in the fleet**: `pure` default, `rust` selectable (through D) | I1–I3 under both binaries |
| S4 | **Full-source bootstrap**: a hex seed (the nixpkgs `stage0-posix` model), a tiny Lisp over blue forms, then the compiler; the binary seed retires | I10 |
| S5 | **aarch64 macOS**: encoder, Mach-O writer with libSystem imports and an ad-hoc signature, darwin host words | native conformance on aarch64 macOS |

### C — conformance

| # | Rung | Exit check |
|---|---|---|
| C1 | **Three-way conformance** with a ratchet on rows native passes | I1 |
| C2 | **Memory rows**: `leaks(0)`, `closes_at(...)`, cycle-through-cell, move vs copy | I2, I3, I4 rows exist and run |
| C3 | **Benchmarks** against Rust twins, keyed per host | I7 |

### D — the build surface

| # | Rung | Exit check |
|---|---|---|
| D0 | **Builders into substrate** (`substrate/lib/build/blue/`), toolchain as an argument | every project's and node's drvPaths identical before and after |
| D1 | **`bidamasOverlay` reads `final.blue`** | `blueApp` over an overridden `blue` points at the override |
| D2 | **The `blue.toolchain` registry** (module trio, kind `registry`): entries per permutation, refusals named by rung | kijun `trio/every-concept`; the kinds test |
| D3 | **Bluefile `toolchain(...)`** per project | each buildable entry builds a project |
| D4 | **Fleet selection** per node; the fleet's blue overlay becomes the `rust` projection | identical drvPaths with `rust` selected |
| D5 | **The matrix** over every buildable entry | I11 |
| D6 | **Entries come alive** as their rungs land (M3, B1, S2, S4, S5) | a matrix row per entry |

## 7. Dependencies (canonical)

| Rung | After |
|---|---|
| L0, L2, L3, S0, C1, B0, F1, M3a, D0 | — |
| L1 | L0 |
| D1, D2 | D0 |
| D3, D4, D5 | D2 |
| B1 | B0, L1 |
| M1 | B1, L3 |
| M2 | M1 |
| C2 | L1 |
| M3 | M1, C2, M3a |
| M4 | M3 |
| M5 | M4 |
| B2 | L2 |
| B4 | B2 |
| B3 | B1, B2, B4 |
| C3 | B3 |
| B5 | B3, C3 |
| R1 | B3 |
| R2 | R1 |
| R3 | R2 |
| R4 | R1, R3 |
| R5 | R2, R4, M4 |
| R6a | R3, R4, L2 |
| R6b | R6a |
| R6c | R3 |
| R7 | R6b |
| F2 | F1, L3, B1 |
| F3 | F2, M1 |
| F4 | F1 |
| S1 | F1, F2, B4, R3, R5, R6a |
| S2 | S1 |
| S3 | S2, M5, R7, D4 |
| S4 | S2 |
| S5 | S1, R7 |
| D6 | the rung each entry names |

**The critical path:** L0 → L1 → B1 → B3 → R1 → R2 → R3 → R4 → R6a → S1 → S2 → S4 (12 rungs).
The memory chain (B1 → M1 → M3 → M4 → R5) runs beside it and joins at S1. By effort, B1 (the IR
over the whole language) and F1 (~7.7k lines of reader behaviour) are the heaviest; B1 is on
every chain.

## 8. Phases

| Phase | Rungs | What exists at the end |
|---|---|---|
| 1. Ground | S0, L0, L1, L2, L3, C1, B0, M3a, D0, D1, D2 | the ledger; typed cells; fixed-width ints; deterministic expansion; the nanopass library; in-place updates outside tail calls; the toolchain registry |
| 2. The model | B1, M1, M2, C2, M3, M4, M5, D3, D4, D5; F1 beside | the IR and Perceus as forms; both existing runtimes on inferred ownership; facts visible to authors; every build selectable |
| 3. First native program | B2, B4, B3, C3, R1, R2, R3 | blue compiled by blue to x86-64 ELF, no rustc |
| 4. A real host program | R4, R5, R6a, R6b, R6c, R7, B5 | the runtime and libraries in blue |
| 5. The front end | F2, F3, F4 | expander, checker and formatter in blue |
| 6. The tower | S1, S2, S3, S4, D6 | the fixpoint, the seed, two runtimes in the fleet, full-source bootstrap |
| 7. The second host | S5 | aarch64 macOS |

Phase 1 pays off on its own: M3a gives today's runtime in-place updates outside tail calls, and
D0-D2 make every later rung a one-field switch.

## 9. The first five commits

1. **S0**: `gen/purity.b`, a per-crate `purity-bytes` baseline, a gate test that a rise is red.
2. **L0**: `rules/mutation.b` `captured_rebind` with its tests, `census` loading it, the ratchet.
3. **L3**: blue's own `gensym` per interpreter, and a test that expands one file twice to equal bytes.
4. **L1**: `cell`/`cell_get`/`cell_put` as `Value::Foreign`, with `spec/rows/cells.b` on walker and VM.
5. **B0**: a minimal `defir`/`defpass`, with a row where a forbidden form fails at expansion.

D0 (lifting the builders into substrate) runs beside these: it touches only nix.

## 10. Decisions (2026-11-17)

1. Linux first.
2. Memory: inferred ownership (§4).
3. Seed: the most pure; S2's binary seed is a stepping stone to S4's full-source chain.
4. The Rust implementation is a fully supported fallback runtime (S3, D).
5. Lisp is the method (§5).
6. Every build option is a module-trio configuration, with the builders in substrate (D).

## 11. Prior art, used as oracles

- **Perceus** (Reinking, Xie, de Moura, Leijen; PLDI 2021) and **frame-limited reuse** (Lorenzen,
  Leijen; ICFP 2022): §4.2-4.5; Koka's tests are oracles for B1 and M1.
- **Lean 4** ("Counting Immutable Beans", Ullrich, de Moura; IFL 2019): borrow inference, reuse,
  and the shared-marking scheme for M5; its benchmarks are oracles for C3.
- **Project Verona** (Microsoft Research): region ownership with concurrency; M4 and R5.
- **Erlang/BEAM**: per-process heaps, message copying, supervisors; §4.6 and R5.
- **Chez Scheme's nanopass framework** (Keep, Dybvig, 2013): B0 and B1.
- **PreScheme and Scheme48**: the runtime subset, R1-R2.
- **Carp** and **Baker's Linear Lisp** (1992): ownership in a Lisp without a collector.
- **Guix full-source bootstrap** (`hex0`, stage0-posix, GNU Mes): S4.
- **Go 1.5 and Zig** (`zig1.wasm`): self-hosting from a committed previous build; S2.
- **Diverse double-compiling** (Wheeler, 2009): S2's witness.
