// Run with: node --test Tests/Terminal/layout.test.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const html = readFileSync(new URL('../../Sources/Reeve/Resources/terminal.html', `file://${__filename}`), 'utf8');
const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];

function setup() {
  const elements = [], terminals = [], frames = [], messages = [];
  let resize;
  const element = () => ({
    style: {}, dataset: {}, parent: null,
    appendChild(child) { child.parent = this; },
    addEventListener() {}, remove() {}
  });
  const host = element();
  class Terminal {
    constructor() { this.cols = 80; this.rows = 24; this.fits = 0; terminals.push(this); }
    loadAddon(addon) { addon.term = this; }
    open(el) { this.el = el; }
    onData() {} onBinary() {} focus() {} dispose() {}
  }
  class FitAddon {
    // Terminal, panonun icindeki .inner katmanina baglaniyor; genisligi
    // konumlandirmadan aliyor, o yuzden olcuyu ustteki panodan okuyoruz.
    fit() {
      this.term.fits++;
      let box = this.term.el;
      while (box && !box.style.width) box = box.parent;
      this.term.cols = Math.round(parseFloat(box.style.width.slice(5)));
    }
  }
  const window = { addEventListener() {}, webkit: { messageHandlers: new Proxy({}, {
    get: (_, name) => ({ postMessage: body => messages.push({ name, ...body }) })
  }) } };
  vm.runInNewContext(script, {
    window, document: { getElementById: () => host, createElement: () => {
      const el = element(); elements.push(el); return el;
    } },
    Terminal, FitAddon: { FitAddon }, SearchAddon: { SearchAddon: class {} },
    WebglAddon: { WebglAddon: class { onContextLoss() {} dispose() {} } },
    ResizeObserver: class { constructor(callback) { resize = callback; } observe() {} },
    TextEncoder, Uint8Array, btoa, atob,
    requestAnimationFrame: callback => { frames.push(callback); return frames.length; }
  });
  return { window, terminals, messages, resize: () => resize(), flush: () => frames.splice(0).forEach(f => f()), frames };
}

test('resize bursts are coalesced and hidden terminals are not refitted', () => {
  const env = setup();
  env.window.reeveCreate('a'); env.window.reeveCreate('b');
  env.window.reeveLayout(['a']);
  const counts = env.terminals.map(t => t.fits);
  env.resize(); env.resize(); env.resize();
  assert.equal(env.frames.length, 1);
  env.flush();
  assert.equal(env.terminals[0].fits, counts[0] + 1);
  assert.equal(env.terminals[1].fits, counts[1]);
});

test('opening and closing a split immediately reports the final terminal dimensions', () => {
  const env = setup();
  env.window.reeveCreate('a'); env.window.reeveCreate('b');
  env.window.reeveLayout(['a', 'b']);
  assert.deepEqual(env.terminals.map(t => t.cols), [50, 50]);
  env.window.reeveLayout(['b']);
  assert.equal(env.terminals[1].cols, 100);
  assert.equal(env.messages.filter(m => m.name === 'resize' && m.id === 'b').at(-1).cols, 100);
  assert.equal(env.terminals[0].el.parent.dataset.active, '0');
});
