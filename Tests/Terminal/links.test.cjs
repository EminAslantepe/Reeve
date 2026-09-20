// Terminaldeki dosya yolu linkleri.  Çalıştırma: node --test Tests/Terminal/links.test.cjs
//
// terminal.html'in içindeki script gerçek tarayıcı olmadan koşturuluyor; xterm
// yerine buffer'ı elle doldurulan bir sahte Terminal veriliyor. Ölçülen şey
// yolun metinden nasıl çıkarıldığı ve hangi satır/sütuna oturduğu.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const html = readFileSync(new URL('../../Sources/Reeve/Resources/terminal.html', `file://${__filename}`), 'utf8');
const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];

// vm içinde üretilen nesneler başka bir realm'e ait; deepStrictEqual prototip
// eşitliği de aradığı için yapıca aynı değerler eşleşmiyor. Sadeleştirip
// karşılaştırıyoruz.
const plain = (value) => JSON.parse(JSON.stringify(value));

function setup(cols = 80) {
  const messages = [];
  const element = () => ({
    style: {}, dataset: {}, parent: null,
    appendChild(child) { child.parent = this; },
    addEventListener() {}, remove() {}
  });
  const host = element();
  const terminals = [];
  const keys = {};    // document'e bağlanan tuş dinleyicileri
  class Terminal {
    constructor() {
      this.cols = cols; this.rows = 24; this.providers = []; this.lines = [];
      this.buffer = { active: { getLine: (i) => this.lines[i] } };
      terminals.push(this);
    }
    loadAddon(addon) { addon.term = this; }
    open(el) { this.el = el; }
    registerLinkProvider(p) { this.providers.push(p); return { dispose() {} }; }
    onData() {} onBinary() {} focus() {} dispose() {}
  }
  class FitAddon { fit() {} }
  const window = { addEventListener() {}, webkit: { messageHandlers: new Proxy({}, {
    get: (_, name) => ({ postMessage: body => messages.push({ name, ...body }) })
  }) } };
  vm.runInNewContext(script, {
    window,
    document: { getElementById: () => host, createElement: () => element(),
                addEventListener: (type, fn) => { keys[type] = fn; } },
    Terminal, FitAddon: { FitAddon }, SearchAddon: { SearchAddon: class {} },
    WebglAddon: { WebglAddon: class { onContextLoss() {} dispose() {} } },
    ResizeObserver: class { observe() {} },
    TextEncoder, Uint8Array, btoa, atob,
    requestAnimationFrame: (cb) => { cb(); return 1; },
    setTimeout, clearTimeout
  });
  window.reeveCreate('pane');
  const term = terminals[0];

  // Satırları sağdan boşlukla dolduruyoruz: gerçek xterm buffer'ı da her satırı
  // tam `cols` genişliğinde tutuyor, sarma hesabı buna dayanıyor.
  const write = (rows) => {
    term.lines = rows.map(r => ({
      isWrapped: !!r.wrapped,
      translateToString: () => r.text.padEnd(cols, ' ').slice(0, cols)
    }));
  };

  // provideLinks Swift'e sorup cevabı bekliyor; testte cevabı biz veriyoruz.
  const linksAt = (row, exists) => new Promise((done) => {
    const before = messages.length;
    term.providers[0].provideLinks(row, done);
    const asked = messages.slice(before).filter(m => m.name === 'resolvePaths');
    for (const ask of asked) {
      const answer = {};
      for (const path of ask.paths) answer[path] = exists(path);
      window.reeveResolved(ask.req, answer);
    }
    if (!asked.length) done(undefined);   // önbellekten geldi, soru sorulmadı
  });

  // ⌘ basma/bırakma: script bunları document üzerinden dinliyor.
  const press = (type, metaKey) => keys[type] && keys[type]({ metaKey: metaKey });

  return { window, term, messages, write, linksAt, press,
           asked: () => messages.filter(m => m.name === 'resolvePaths') };
}

test('dosya adı ile satır numarası ayrıştırılıyor', async () => {
  const env = setup();
  env.write([{ text: 'Hatayı buldum: GitProbe.swift:73 satırında.' }]);
  const links = await env.linksAt(1, () => true);

  assert.equal(links.length, 1);
  assert.equal(links[0].text, 'GitProbe.swift:73');
  // "Hatayı buldum: " 15 karakter → yol 16. sütunda başlıyor.
  assert.deepEqual(plain(links[0].range), { start: { x: 16, y: 1 }, end: { x: 32, y: 1 } });

  links[0].activate({ metaKey: true });
  const opened = env.messages.at(-1);
  assert.equal(opened.name, 'openPath');
  assert.equal(opened.path, 'GitProbe.swift');   // satır numarası yoldan ayrılmış
  assert.equal(opened.line, 73);
});

test('diskte olmayan aday link olmuyor', async () => {
  const env = setup();
  env.write([{ text: 'Faz 1.5 bitti, PLAN.md §7 güncellensin.' }]);
  // Swift yalnızca gerçek dosyayı onaylıyor.
  const links = await env.linksAt(1, (p) => p === 'PLAN.md');

  // İkisi de aday olarak soruldu — eleme Swift tarafında yapılıyor.
  assert.deepEqual(plain(env.asked()[0].paths), ['1.5', 'PLAN.md']);
  assert.equal(links.length, 1);
  assert.equal(links[0].text, 'PLAN.md');
});

test('satır sonunda sarılan yol bütün olarak yakalanıyor', async () => {
  const env = setup(20);
  env.write([
    { text: 'bak Sources/Reeve/UI' },
    { text: '/Theme.swift:43 tam', wrapped: true }
  ]);
  // Alt satırdan soruluyor: sağlayıcı yukarı yürüyüp mantıksal satırı kurmalı.
  const links = await env.linksAt(2, () => true);

  assert.equal(links.length, 1);
  assert.equal(links[0].text, 'Sources/Reeve/UI/Theme.swift:43');
  // 5. sütunda başlayıp alt satırın 15. sütununda bitiyor.
  assert.deepEqual(plain(links[0].range), { start: { x: 5, y: 1 }, end: { x: 15, y: 2 } });
});

test('cevaplar önbellekte, `cd` sonrası düşüyor', async () => {
  const env = setup();
  env.write([{ text: 'Sources/Reeve/UI/Theme.swift değişti' }]);

  await env.linksAt(1, () => true);
  assert.equal(env.asked().length, 1);

  await env.linksAt(1, () => true);
  assert.equal(env.asked().length, 1, 'aynı aday ikinci kez sorulmamalı');

  env.window.reeveResetLinks('pane');
  const links = await env.linksAt(1, () => true);
  assert.equal(env.asked().length, 2, '`cd` sonrası yeniden sorulmalı');
  assert.equal(links.length, 1);
});

test('⌘ basılı değilken tıklama terminalin', async () => {
  const env = setup();
  env.write([{ text: 'GitProbe.swift:73 satırında' }]);
  const links = await env.linksAt(1, () => true);

  // ⌘ yokken ne altı çizili ne de tıklanabilir.
  assert.equal(links[0].decorations.underline, false);
  assert.equal(links[0].decorations.pointerCursor, false);

  const before = env.messages.length;
  links[0].activate({ metaKey: false });
  assert.equal(env.messages.length, before, 'tıklama Swift\'e gitmemeli');

  links[0].activate({ metaKey: true });
  assert.equal(env.messages.at(-1).name, 'openPath');
});

test('⌘ basılınca hover edilen linkin altı çiziliyor', async () => {
  const env = setup();
  env.write([{ text: 'GitProbe.swift:73 satırında' }]);
  const links = await env.linksAt(1, () => true);

  links[0].hover();
  env.press('keydown', true);
  assert.equal(links[0].decorations.underline, true);
  assert.equal(links[0].decorations.pointerCursor, true);

  env.press('keyup', false);
  assert.equal(links[0].decorations.underline, false);

  // Fare linkten ayrıldıysa ⌘ artık ona dokunmamalı.
  links[0].leave();
  env.press('keydown', true);
  assert.equal(links[0].decorations.underline, false);
});

test('yol geçmeyen satır Swift\'e hiç gitmiyor', async () => {
  const env = setup();
  env.write([{ text: 'Testler geçiyor, her şey yolunda' }]);
  const links = await env.linksAt(1, () => true);

  assert.equal(links, undefined);
  assert.equal(env.asked().length, 0);
});
