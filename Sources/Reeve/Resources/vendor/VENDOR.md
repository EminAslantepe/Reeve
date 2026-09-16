# Vendor — xterm.js

Elle düzenlenmez. Güncellemek için `update.sh` çalıştırılır, çıktı gözle doğrulanır.

İndirme: 2026-09-16 · Kaynak: cdn.jsdelivr.net (npm registry mirror) · Lisans: MIT (bkz. `LICENSE`)

| Dosya | Paket | Sürüm | sha256 |
|---|---|---|---|
| `xterm.js` | `@xterm/xterm` | 6.0.0 | `14903579ff54664cd72f8e8699e6961a6272c21863ec1c3b118cdc8af5d4a972` |
| `xterm.css` | `@xterm/xterm` | 6.0.0 | `854a7c0fb70e8b1a083c16797ab827299fb18744f5ad34f227b48337e33293c6` |
| `addon-fit.js` | `@xterm/addon-fit` | 0.11.0 | `ba3ea256ce0620a0992a197d6c9baea64823fc93d8da07a9e366ca9943c18527` |
| `addon-search.js` | `@xterm/addon-search` | 0.16.0 | `7bc1b8c7b3549411f6f6f779524c4ded6ca621fd80d64b40a70ae7c78aefbf55` |
| `addon-webgl.js` | `@xterm/addon-webgl` | 0.19.0 | `b85f8d4b3e9756bebb757e3fe47134d70f03ea3d6b187624426d2e2b65dec06c` |

Dördü de 2025-12-22'de birlikte yayınlandı — uyumlu set.

## Global isimler

Hepsi UMD; `<script src>` ile yüklenince `globalThis`e yazıyorlar (node ile doğrulandı):

```js
new Terminal({ ... })                  // xterm.js
term.loadAddon(new FitAddon.FitAddon())
term.loadAddon(new SearchAddon.SearchAddon())
term.loadAddon(new WebglAddon.WebglAddon())
```

## Not

`xterm.js` 6.0.0 (2025-12-22) seçildi. Faz 0 görsel doğrulamasında sorun çıkarsa
uzun süre sahada olan 5.5.0 + fit 0.10.0 / search 0.15.0 / webgl 0.18.0 setine
düşülebilir — `update.sh` içindeki sürüm satırları değiştirilip yeniden çalıştırılır.
