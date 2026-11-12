const base = process.argv[2];
const absolute = (u) => new URL(u, base).href;
const nativeFetch = globalThis.fetch;
const fetched = [];
globalThis.fetch = (u, init) => {
  fetched.push(new URL(absolute(u)).pathname);
  return nativeFetch(absolute(u), init);
};

const page = await nativeFetch(base);
const html = await page.text();
const csp = page.headers.get('content-security-policy') || '';

const attr = (tag, name) => {
  const m = tag.match(new RegExp(`${name}="([^"]*)"`));
  return m ? m[1].replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&') : null;
};

const elements = [...html.matchAll(/<[a-z]+ [^>]*data-seam="[^"]*"[^>]*>/g)].map((m) => {
  const tag = m[0];
  const el = {
    seam: attr(tag, 'data-seam'),
    dataset: { value: attr(tag, 'data-value') },
    attributes: {},
    rendered: null,
    textContent: '',
    setAttribute(k, v) { this.attributes[k] = String(v); },
    replaceChildren(...nodes) { this.rendered = nodes.map((n) => n.html).join(''); },
  };
  return el;
});
const matches = (sel) => {
  const m = sel.match(/^\[data-seam=([a-z-]+)\]$/);
  return m ? elements.filter((e) => e.seam === m[1]) : [];
};
globalThis.document = {
  querySelector: (sel) => matches(sel)[0] || null,
  querySelectorAll: (sel) => matches(sel),
};
globalThis.DOMParser = class {
  parseFromString(text) { return { body: { childNodes: [{ html: text }] } }; }
};

const scripts = [...html.matchAll(/<script src="([^"]+)"/g)].map((m) => m[1]);
for (const src of scripts) {
  const code = await (await nativeFetch(absolute(src))).text();
  new Function(code)();
}

const mount = elements.find((e) => e.seam === 'engine');
const receipt = elements.find((e) => e.seam === 'receipt');
const deadline = Date.now() + 60000;
while (mount && !mount.attributes['data-state'] && Date.now() < deadline) {
  await new Promise((r) => setTimeout(r, 20));
}
const named = mount ? JSON.parse(mount.dataset.value) : null;
const imports = named
  ? WebAssembly.Module.imports(new WebAssembly.Module(await (await nativeFetch(absolute(named.wasm))).arrayBuffer())).length
  : null;
console.log(JSON.stringify({
  state: mount ? mount.attributes['data-state'] || 'timeout' : 'no-mount',
  value: mount ? mount.rendered : null,
  error: mount && !mount.rendered ? mount.textContent : null,
  receipt: receipt ? receipt.textContent : null,
  scripts,
  fetched,
  csp,
  imports,
}));
