# The DuckDB door — plan, written before code

Status: DESIGN, opened 2026-11-27. The unit exists because a measured gap
closed the wrong way first: kueri's `duckdb_at` execs the `duckdb` CLI
(`exec_capture("duckdb", db, "-json", "-c", sql)`), whose DISPLAY rendering
leaks into every value (text-typed integers, the receipt in
renban/prova.b's `num()` shim) and whose subprocess-per-statement shape
needed a PATH fix on rio to run under systemd at all.

## The tiers

1. **The door (this unit): `duckdb_open` / `duckdb_query` / `duckdb_exec`
   builtins in blue-lang-runtime**, mirroring `install_pg`'s shape —
   `Foreign` connection value, typed rows out, `duckdb_query` returns blue
   values (ints as ints), `duckdb_exec` returns nil. The engine behind the
   door is a **dlopen'd binding to DuckDB's C API** (one auditable seam,
   `#![deny(unsafe_code)]` elsewhere, no `-sys` crate, no bindgen —
   CONTAIN THE C, the zbus/evdev/ash pattern), **feature-gated** so a
   build that names no database engine pays nothing: the C++ amalgamation
   is minutes of build and the closure decision belongs to each consumer.
   `kueri::duckdb_at` switches to the door when the feature is on and
   falls back to the CLI with a named warning when it is not, until the
   door is universal.
2. **The pure-blue engine (a later unit):** a query evaluator over blue's
   own values for the SQL subset kueri already renders — filter, project,
   aggregate, order over lists of records. For probe-sized data this makes
   the whole path 100% blue with no seam at all. The namimado shape: the
   house writes the engine when the engine is the point.
3. **Never: reimplementing DuckDB.** The embedded engine is ~1M lines of
   C++ — a world-fact. MIRAGEM: typed, not dissolved.

## Why not link the duckdb crate directly

The crate binds the C++ amalgamation into every blue closure; the house
law takes the lowest ABI behind one seam instead. The C API is stable,
small for our needs (open, query, destroy, value extraction), and the
dlopen route keeps blue itself free of the C++ toolchain at build time.

## Ships with

A `docs::NAMES` row per builtin, spec rows for the conformance suite, the
kueri switch, and a red-run gate: a value round-trip test that fails on
the CLI path's text typing (an int read back must be `integer?`, not a
numeral string).

## The SQL-door abstraction (the mysql point)

`pg_*` and `duckdb_*` are two engines behind one door shape — connect
with a string, query with SQL plus params, typed rows back. A third engine
(MySQL, or the tier-2 in-memory one) joins by the same trio; kueri's
SQL builder already renders for engines, not for one of them.
