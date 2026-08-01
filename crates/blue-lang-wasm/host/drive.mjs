import { readFileSync } from 'node:fs';
const bytes = readFileSync(process.argv[2]);
// NO IMPORT OBJECT. If the module needed a single host function this would
// throw — which is the point: capability restriction is the absence of an
// import, not a policy checked at call time.
const { instance } = await WebAssembly.instantiate(bytes, {});
const ex = instance.exports;

const imports = WebAssembly.Module.imports(new WebAssembly.Module(bytes));
console.log(`imports: ${imports.length}`);

function evalBlue(src) {
  const enc = new TextEncoder().encode(src);
  const ptr = ex.alloc(enc.length);
  new Uint8Array(ex.memory.buffer, ptr, enc.length).set(enc);
  const tagged = ex.blue_eval(ptr, enc.length);
  ex.dealloc(ptr, enc.length);
  const tag = Number(BigInt(tagged) & 3n);
  if (tag === 0) return { kind: 'int', value: BigInt(tagged) >> 2n };
  if (tag === 1) return { kind: 'nonint' };
  const len = ex.blue_last_error_len();
  const buf = ex.alloc(len);
  ex.blue_last_error(buf);
  const msg = new TextDecoder().decode(new Uint8Array(ex.memory.buffer, buf, len));
  ex.dealloc(buf, len);
  return { kind: 'error', message: msg };
}

const cases = [
  ['1 + 2', 'int', 3n],
  ['def fact(n)\n  if n < 2\n    1\n  else\n    n * fact(n - 1)\n  end\nend\nfact(10)', 'int', 3628800n],
  ['defmacro double(x)\n  quote\n    unquote(x) + unquote(x)\n  end\nend\ndouble(21)', 'int', 42n],
  ['6 % 3', 'int', 0n],
  ['def bad(a: Int) -> Str\n  a\nend\nbad(1)', 'error', null],
  ['no_such_fn()', 'error', null],
  ['true', 'nonint', null],
];

let failed = 0;
for (const [src, kind, want] of cases) {
  const got = evalBlue(src);
  const ok = got.kind === kind && (want === null || got.value === want);
  if (!ok) { failed++; console.log(`FAIL ${JSON.stringify(src)} -> ${JSON.stringify(String(got.value ?? got.message ?? got.kind))} (wanted ${kind} ${want})`); }
  else { console.log(`ok   ${kind.padEnd(7)} ${JSON.stringify(src).slice(0, 46)}`); }
}
console.log(failed === 0 ? 'ALL WASM CASES PASSED' : `${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
