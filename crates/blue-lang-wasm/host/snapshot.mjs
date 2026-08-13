// **Capture and restore a blue instance's whole linear memory as bytes.**
//
// The claim under test is narrow and mechanical: blue's interpreter runs
// *inside* a wasm instance, so everything it allocates lives in that
// instance's linear memory — and linear memory is an ArrayBuffer the host can
// copy out and write back. Nothing escapes, because the module imports
// nothing: `WebAssembly.Module.imports()` is `[]`, so there is no host handle,
// no descriptor and no external reference for a byte-copy to miss.
//
// **What this is NOT.** It is not a mid-execution capture. A wasm call stack
// is engine-internal — locals, return addresses and the operand stack are not
// in linear memory and are not reachable from JS — so a snapshot is only
// meaningful at a *quiescent* point, between exported calls. The module's one
// mutable global (LLVM's shadow-stack pointer, unexported) is likewise
// invisible; at quiescence it holds its initial value in every instance, which
// is why not capturing it is sound here and would not be mid-call.
//
// **And it is not an actor snapshot**, because there is no actor to snapshot:
// `blue_eval` builds a fresh interpreter per call (`pipeline.rs` —
// `interpreter_hostless()`), so a binding made in one call is gone by the
// next. Measured: `x = 41` then `x + 1` reports ``unbound symbol `x` ``. The
// state this test round-trips is what the shipped ABI actually keeps in the
// heap across a call — a blue program's error value, and a host-owned region.

import { readFileSync } from 'node:fs';

const PAGE = 65536;
const bytes = readFileSync(process.argv[2]);
const mod = new WebAssembly.Module(bytes);

let failed = 0;
function check(ok, label, detail = '') {
  if (ok) console.log(`ok   ${label}`);
  else {
    failed++;
    console.log(`FAIL ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

function mk() {
  // No import object, exactly as `drive.mjs`. If the module needed one host
  // function this would throw, and the "nothing escapes" argument would be
  // false rather than merely unverified.
  return new WebAssembly.Instance(mod, {}).exports;
}

function evalBlue(ex, src) {
  const enc = new TextEncoder().encode(src);
  const ptr = ex.alloc(enc.length);
  new Uint8Array(ex.memory.buffer, ptr, enc.length).set(enc);
  const tagged = ex.blue_eval(ptr, enc.length);
  ex.dealloc(ptr, enc.length);
  const tag = Number(BigInt(tagged) & 3n);
  if (tag === 0) return { kind: 'int', value: BigInt(tagged) >> 2n };
  if (tag === 1) return { kind: 'nonint' };
  return { kind: 'error' };
}

function lastError(ex) {
  const len = ex.blue_last_error_len();
  if (len === 0) return null;
  const buf = ex.alloc(len);
  ex.blue_last_error(buf);
  const msg = new TextDecoder().decode(new Uint8Array(ex.memory.buffer, buf, len));
  ex.dealloc(buf, len);
  return msg;
}

/// The whole linear memory, copied out. `.slice()` and not a view: a view onto
/// `memory.buffer` is a window into the live instance and detaches the moment
/// the memory grows, which is the difference between a snapshot and a promise
/// to read later.
function capture(ex) {
  return new Uint8Array(ex.memory.buffer).slice();
}

/// Write a snapshot back. Growing first is not an optimisation — a fresh
/// instance starts at the module's declared minimum, and every snapshot taken
/// after real work is larger.
function restore(ex, snap) {
  const have = ex.memory.buffer.byteLength;
  if (snap.length > have) ex.memory.grow(Math.ceil((snap.length - have) / PAGE));
  new Uint8Array(ex.memory.buffer).set(snap);
}

// A payload the host owns, so the test is not resting on one thread-local.
// `alloc` hands back a real region from the module's own allocator; if the
// allocator's bookkeeping did not survive the round trip, the pointer would
// not still be ours on the other side.
const PAYLOAD = Uint8Array.from({ length: 32 }, (_, i) => (i * 7 + 3) & 0xff);

// ---------------------------------------------------------------------------
// Two instances, two different blue programs, two different snapshots.
// ---------------------------------------------------------------------------

const a = mk();
check(evalBlue(a, 'no_such_fn()').kind === 'error', 'A: a blue program ran and failed');
const errA = lastError(a);
const ptrA = a.alloc(PAYLOAD.length);
new Uint8Array(a.memory.buffer, ptrA, PAYLOAD.length).set(PAYLOAD);
const snapA = capture(a);

const c = mk();
check(
  evalBlue(c, 'def bad(a: Int) -> Str\n  a\nend\nbad(1)').kind === 'error',
  'C: a different blue program ran and failed differently',
);
const errC = lastError(c);
const snapC = capture(c);

check(errA !== null && errC !== null && errA !== errC, 'the two programs left different state', `${errA} vs ${errC}`);

// ---------------------------------------------------------------------------
// The baseline: a fresh instance has none of it.
// ---------------------------------------------------------------------------

const b = mk();
check(b.blue_last_error_len() === 0, 'a fresh instance observes no error');
check(
  b.memory.buffer.byteLength < snapA.length,
  'a fresh instance is smaller than the snapshot',
  `${b.memory.buffer.byteLength} vs ${snapA.length}`,
);

// ---------------------------------------------------------------------------
// Restore A into it, and see A's state.
// ---------------------------------------------------------------------------

restore(b, snapA);
check(lastError(b) === errA, "the restored instance observes A's error", `${lastError(b)}`);
const gotPayload = new Uint8Array(b.memory.buffer, ptrA, PAYLOAD.length);
check(
  gotPayload.every((v, i) => v === PAYLOAD[i]),
  "the restored instance holds A's heap payload at A's pointer",
);

// It is still a working instance, not just a bag of bytes: the restored heap
// has to be coherent enough for the allocator and the whole blue pipeline to
// run on top of it.
const after = evalBlue(b, 'def fact(n)\n  if n < 2\n    1\n  else\n    n * fact(n - 1)\n  end\nend\nfact(10)');
check(after.kind === 'int' && after.value === 3628800n, 'the restored instance still runs blue programs');

// ---------------------------------------------------------------------------
// **The load-bearing gate: a DIFFERENT snapshot must give DIFFERENT state.**
//
// Everything above is satisfied by an implementation that never restored
// anything, as long as the observation happened to match. This is the control.
//
// RED RUN 1, recorded 2026-08-13 — `restore` stubbed to a no-op:
//   `FAIL the restored instance observes A's error — null`, then a hard
//   `RangeError: Invalid typed array length: 32` on the payload read, because
//   an un-grown fresh memory does not even span A's pointer. Exit 1.
//
// RED RUN 2, recorded 2026-08-13 — `restore` rewired to write `snapA`
// whatever it was handed, a "restore" that restores a CONSTANT:
//   every check above still passes, and this differential is the only thing
//   that goes red — `FAIL restoring C's snapshot observes C's error` and
//   `FAIL a different snapshot gives a different observation`. Exit 1.
// That is the mutation this gate exists for: red run 1 is caught by any of
// these checks, red run 2 is caught by this pair alone.
// ---------------------------------------------------------------------------

const d = mk();
restore(d, snapC);
check(lastError(d) === errC, "restoring C's snapshot observes C's error", `${lastError(d)}`);
check(lastError(d) !== errA, 'a different snapshot gives a different observation');

// ---------------------------------------------------------------------------
// Measure. A claim of "microseconds" needs a number.
// ---------------------------------------------------------------------------

const N = 25;
const capT = [];
const resT = [];
for (let i = 0; i < N; i++) {
  const t0 = performance.now();
  const s = capture(a);
  const t1 = performance.now();
  const fresh = mk();
  const t2 = performance.now();
  restore(fresh, s);
  const t3 = performance.now();
  capT.push((t1 - t0) * 1000);
  resT.push((t3 - t2) * 1000);
}
const med = (xs) => xs.slice().sort((x, y) => x - y)[Math.floor(xs.length / 2)];

console.log(`snapshot-bytes: ${snapA.length}`);
console.log(`snapshot-pages: ${snapA.length / PAGE}`);
console.log(`capture-us-median: ${med(capT).toFixed(1)}`);
console.log(`capture-us-min: ${Math.min(...capT).toFixed(1)}`);
console.log(`restore-us-median: ${med(resT).toFixed(1)}`);
console.log(`restore-us-min: ${Math.min(...resT).toFixed(1)}`);

console.log(failed === 0 ? 'ALL SNAPSHOT CASES PASSED' : `${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
