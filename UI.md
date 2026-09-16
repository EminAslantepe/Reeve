# Reeve — Arayüz Planı

`PLAN.md`'nin devamı. Burada ekranın nasıl görüneceği, aşağıda da bu tasarımın
backend'de gerektirdiği değişiklikler var.

---

## 0. Tasarımın tek kuralı

Reeve'in asıl işi terminal göstermek değil, şu soruyu cevaplamak:

> **"Şu an hangisi beni bekliyor?"**

Beş ajan koştururken önemli olan tek bilgi bu. Tasarımın her kararı buna hizmet ediyor:
bekleyen oturum en üstte, en dikkat çekici renkte, bildirimle destekli. Geri kalan
her şey ikincil.

Üç durum ve anlamları:

| Durum | Anlamı | Görsel |
|---|---|---|
| `waiting` | **Seni bekliyor.** İzin dialogu açık | Turuncu, en üstte, bildirim |
| `idle` | İşi bitti, sıradaki talimatı bekliyor | Gri — meşgulken idle'a düştüyse "bitti" rozeti |
| `busy` | Çalışıyor, karışma | Mavi, nabız animasyonu |

---

## 1. Ana pencere

Başlık çubuğunda iki kontrol var: soldaki düğme **sidebar kademesini**, `1 | 2`
segmenti **panel sayısını** değiştiriyor.

```
┌────────────────────────────────────────────────────────────────────────┐
│ ●●● ▤  Reeve       1│2                            ⌘K     +        ⚙    │
├──────────────────────────┬─────────────────────────────────────────────┤
│                          │ ◉ center-9f  12m  │ ⏸ project-2b  bekliyor  │
│  DİKKAT (1)              ├───────────────────┼─────────────────────────┤
│  ⏸ project-2b            │ > DİKKAT bölümünü │ ⏺ Read(package.json)    │
│    Bash izni bekliyor    │   ekle            │                         │
│                          │                   │ ⏺ Bash çalıştırmak      │
│  ── Center ───  main ●3  │ ⏺ Read(Sidebar…)  │   istiyor:              │
│  ◉ center-9f       12m   │ ⏺ Edit(Sidebar…)  │                         │
│    Opus 5 · Edit         │   └ +31 / -4      │   rm -rf build          │
│  ○ zsh               —   │                   │                         │
│                          │ ⏺ Task(Explore)   │   1. Evet               │
│  ── Project ─ feat/x ↑2  │ ✻ Düşünüyor… 18s  │   2. Evet, sorma        │
│  ○ project-8b       2s   │                   │   3. Hayır              │
│                          │ ╭───────────────╮ │ ╭─────────────────────╮ │
│  ── Arka plan ─────────  │ │ >             │ │ │ >                   │ │
│  ⬢ api-refactor     41m  │ ╰───────────────╯ │ ╰─────────────────────╯ │
├──────────────────────────┴─────────────────────────────────────────────┤
│ ~/Desktop/Center · main ●3 · Opus 5 · 42k token · 2 panel · 4 oturum   │
└────────────────────────────────────────────────────────────────────────┘
```

**Sekme yok.** Sol panel zaten sekme çubuğu görevini görüyor.

**Panelleri sürükleyerek açıyorsun.** Başlangıçta başlık çubuğunda `1|2` segmenti
vardı; kullanımda ters düştü — panel sayısını bir sayı seçerek ayarlamak, hangi
oturumun nereye gideceğini ayrıca seçmeyi gerektiriyordu. Yerine:

> Sidebar'dan bir oturumu tutup terminal alanına sürükle. Sürükleme başlayınca
> alan bırakma bölgelerine ayrılıyor: her mevcut panel + sağ kenarda **yeni panel**.
> Bıraktığın yer paneli hem açıyor hem oturumu oraya koyuyor.

Panel başlığı oturum adını, maliyetini ve durumunu taşıyor; sağındaki ✕ paneli
kapatıyor (oturumu değil). **En fazla üç panel.**

**Genişlikler:** sidebar 240–320px arası sürüklenebilir. Terminal alanı kalanı alır,
iki panelde eşit bölünür.

---

## 1.1 Sidebar üç kademe

Başlık çubuğunun **solundaki** düğme (trafik ışıklarının hemen yanında, panele
bakan tarafta) kademeler arasında geçiş yapıyor. Durum rengi iki kademede de
taşınıyor; izin bekleyen oturum dar halde bile görünür.

| Kademe | Genişlik | Ne görünüyor |
|---|---|---|
| **Geniş** | 268 px | İsim, durum, model, çalışan tool, maliyet, git rozeti — varsayılan |
| **Dar** | 58 px | Durum noktası + ismin son iki karakteri (`center-9f` → `9f`). Üstüne gelince tam isim balonda |

> **Üçüncü kademe kaldırıldı.** Tasarımda 30 px'lik "kapalı" bir kademe vardı;
> dar kademe zaten yeterince yer açıyor, sadece noktalara inmek oturumu tanınmaz
> hale getiriyordu.

```
  GENİŞ (268)          DAR (58)      KAPALI (30)
┌──────────────────┐  ┌────────┐    ┌──────┐
│ DİKKAT           │  │ ⏸      │    │  ⏸   │
│ ⏸ project-2b     │  │ 2b     │    │      │
│   Bash izni      │  │ ────── │    │  ◉   │
│ ── Center ─ main │  │ ◉      │    │      │
│ ◉ center-9f  12m │  │ 9f     │    │  ○   │
│   Opus 5 · Edit  │  │ ○      │    │      │
│ ○ zsh            │  │ zsh    │    │  ⬢   │
└──────────────────┘  └────────┘    └──────┘
```

---

## 1.2 Oturum arama (⌘K)

Her kademede açılıyor; sidebar kapalıyken **asıl gezinme yolu bu**. Yazdıkça oturum
adı, klasör ve branch üzerinden eşleşiyor. Bekleyenler ayrı bölümde ve her zaman
ilk sırada.

```
╭──────────────────────────────────────────────╮
│ ⌕  oturum ara…                               │
├──────────────────────────────────────────────┤
│ BEKLEYEN                                     │
│ ⏸ project-2b            Bash izni bekliyor   │  ← seçili
│ TÜM OTURUMLAR                                │
│ ◉ center-9f             Center · main · 12m  │
│ ○ project-8b            Project · feat/x · 2s│
│ ○ zsh                   Center · main        │
│ ⬢ api-refactor          arka plan · 41m      │
├──────────────────────────────────────────────┤
│ ⏎ aç    ⌥⏎ ikinci panelde aç    ⌘⇧A bekleyene│
╰──────────────────────────────────────────────╯
```

`⌥⏎` önemli: aramadan doğrudan ikinci panele gönderiyorsun, oturum değiştirmeden.

---

## 2. Sol panel

### Gruplama: hibrit

1. **DİKKAT** — en üstte, sabit. Hangi repoda olduğuna bakmaksızın `waiting`
   durumundaki her oturum buraya toplanır. Boşsa bölüm tamamen gizlenir.
2. **Repo grupları** — cwd bazında. Başlıkta git branch + kirli dosya sayısı +
   ahead/behind.
3. **Arka plan ajanları** — `claude --bg` ile başlatılmış, PTY'si olmayanlar.

Grup içi sıralama: son aktiviteye göre, yeni olan üstte.

### Satır anatomisi

İki satırlık kompakt satır:

```
◉ center-9f                     12m     ← durum noktası · isim · süre
  Opus 5 · Edit(main.swift)   $0.31     ← model · çalışan tool · maliyet
```

Satırlar **sürüklenerek sıralanabiliyor**; sıra `SessionStore.sessions` dizisinde
tutuluyor, açılış zamanına göre otomatik sıralama kaldırıldı.

İkinci satır duruma göre değişiyor:

```
busy      →  Opus 5 · Edit(main.swift)
waiting   →  Bash(rm -rf build) izni isteniyor      ← turuncu
idle      →  3 dakika önce bitti · 18 dosya değişti
shell     →  ~/Desktop/Center
hata      →  exit 1                                 ← kırmızı
harici    →  iTerm · terminal yok                   ← origin == .external
```

Son satır 4. bölümdeki üç davranışın sidebar'daki karşılığı: Reeve'in açmadığı bir
oturumun terminali gösterilemediği için bu **satırda söyleniyor**, kullanıcı tıklayıp
boş ekranla karşılaşmıyor.

### Durum göstergeleri

```
⏸  waiting    turuncu, hafif yanıp söner
◉  busy       mavi, nabız animasyonu
○  idle       gri
⬢  arka plan  mor
✗  hata       kırmızı
•  okunmamış  ada yanında küçük nokta — sen bakmazken çıktı üretti
```

### Alt öğeler (Faz 3)

Seçili oturumun altında, girintili:

```
◉ center-9f              12m
  ⚙ Explore              18s     ← alt-ajan
  ⌘ npm run dev     pid 4412     ← arka plan süreç
```

### Sağ tık menüsü

```
Odaklan                    ⏎
Yeniden başlat
─────────────────────────────
Durdur          claude stop
Kill (SIGKILL)
Sil             claude rm
─────────────────────────────
Finder'da göster
Transcript'i aç
cwd'yi kopyala
```

---

## 3. Yeni oturum (`+` / ⌘N)

```
╭─────────── Yeni oturum ───────────╮
│                                   │
│  Klasör                           │
│  ┌─────────────────────────────┐  │
│  │ ~/Desktop/Center         ▾  │  │  ← son kullanılanlar + Gözat
│  └─────────────────────────────┘  │
│                                   │
│  Ne çalışsın?                     │
│   ● Claude                        │
│   ○ Claude + yeni worktree        │
│   ○ Claude (arka plan)            │
│   ○ Shell (zsh)                   │
│                                   │
│  Model   [ Varsayılan         ▾ ] │
│  İsim    [ center-a3            ] │  ← otomatik, değiştirilebilir
│                                   │
│              [ İptal ]  [ Aç ⏎ ]  │
╰───────────────────────────────────╯
```

**Hız kısayolu:** `+`'a tıklamak bu pencereyi açar, ama **⌥ ile tıklamak**
son kullanılan klasör + son şablonla doğrudan açar, soru sormaz.

---

## 4. Reeve dışında açılmış oturumlar

`claude agents --json` bize Reeve'in açmadığı oturumları da veriyor — iTerm'de
elle açılmış olanlar dahil. Ama onların PTY'si bizde değil, terminalini gösteremeyiz.

Tıklandığında terminal yerine bir bilgi kartı:

```
╭────────────────────────────────────────────╮
│  project-2b                                │
│  Bu oturum Reeve dışında açıldı            │
│                                            │
│  Klasör   ~/Desktop/Project                │
│  PID      61099                            │
│  Durum    izin bekliyor (dialog open)      │
│  Başlangıç 14:32 (2s 14dk önce)            │
│                                            │
│  [ Transcript'i göster ]  [ Durdur ]       │
╰────────────────────────────────────────────╯
```

**Arka plan ajanları için istisna:** `claude attach <id>` komutu var. Reeve yeni
bir PTY açıp içinde `claude attach` çalıştırarak arka plan ajanını **gerçekten
terminalde açabiliyor.** Yani arka plan ajanlarında bilgi kartı değil, tam terminal
gösteriyoruz.

| Oturum tipi | Terminal gösterebiliyor muyuz? |
|---|---|
| Reeve'in açtığı | Evet — PTY bizde |
| `claude --bg` arka plan | Evet — `claude attach <id>` ile yeni PTY |
| iTerm'de elle açılmış | Hayır — bilgi kartı + transcript |

---

## 5. Bildirimler

macOS bildirimi şu iki durumda:

1. **İzin bekliyor** — pencere önde değilken. Tıklayınca o oturuma odaklanır.
2. **İş bitti** — `busy` → `idle` geçişi, pencere önde değilken.

Dock ikonunda badge: dikkat bekleyen oturum sayısı.
Ayarlardan ikisi de kapatılabilir.

---

## 6. Klavye kısayolları

| Kısayol | İş |
|---|---|
| ⌘N | Yeni oturum |
| ⌥ + `+` tık | Soru sormadan son ayarlarla aç |
| ⌘W | Oturumu kapat |
| ⌘1…⌘9 | Oturuma atla |
| ⌘⇧] / ⌘⇧[ | Sonraki / önceki oturum |
| ⌘⇧A | **Dikkat bekleyen ilk oturuma atla** |
| ⌘K | Komut paleti (Faz 4) |
| ⌘F | Terminalde ara |
| ⌘⌥I | Sağ inceleme panelini aç/kapat (Faz 3) |

⌘⇧A en çok kullanılacak kısayol olacak — çok ajanlı akışın bel kemiği.

---

## 7. Sağ inceleme paneli  ✅ Faz 4

⌘⌥I ile açılan, terminalin sağına yapışan 300 px'lik panel. Varsayılan kapalı.

- **Kullanım** — model, token, maliyet, cache okuma, düşünme tokeni, süre
- **Değişiklikler** — `git diff --numstat` + repo'nun worktree listesi
- **Alt-ajanlar ve süreçler** — Task çağrıları süreleriyle, PTY altındaki
  gerçek süreçler RSS ile
- **Transcript** — son konuşma adımları, altında dosyayı Finder'da gösteren bağlantı

> **`git diff` düzenli yoklamaya sokulmadı.** Büyük repolarda pahalı; yalnızca
> panel açıkken ve seçim değiştikçe çalışıyor. Grup başlığındaki hafif rozet
> (`main ●3`) ise 3 saniyelik döngüde kalıyor.

---

## 8. Tema

**Şu an:** uygulama her zaman koyu. Mockup'ın (`Center Ajan Konsolu`) uygulama
penceresi yalnızca koyu temada tanımlı ve renkler oradan birebir alındı; pencereye
`NSAppearance(.darkAqua)` sabitlendi, xterm paleti de aynı sözlükten besleniyor.
Renk ve ölçü değerlerinin tek kaynağı `UI/Theme.swift`.

**Açık kalan:** sistem açık temadayken ne olacağı. Seçenekler: (a) koyu kalmaya
devam — terminal uygulamalarında yaygın, (b) mockup'ın açık tema karşılığı
türetilip sistem takip edilir. (b) seçilirse `Theme.swift` ikinci bir palet
kazanır ve tema nesnesi xterm'e yeniden gönderilir (D7). Faz 1.5'te karara bağlanacak.

---

# Backend'e etkisi

Bu tasarımın `PLAN.md`'de yazılana göre gerektirdiği değişiklikler.

## D1. Tek WKWebView, N terminal  ⚠️ önemli

Plan "sağ panel = WKWebView" diyordu. Her oturum için ayrı WKWebView açarsak
her biri ~60–80 MB tutar; 10 oturumda 800 MB eder. Kabul edilemez.

**Karar:** Tek WKWebView, içinde N adet `Terminal` nesnesi, her biri kendi
`<div>`'inde. **Bir veya iki tanesi görünür** (panel sayısına göre), diğerleri
gizli. Tek WebKit süreci, oturum başına maliyet birkaç MB.

Gizleme yöntemi `display:none` **değil** `visibility:hidden` — gerekçe D2'de.

Sonuç: `TerminalHost.swift` tek bir örnek olarak yaşar, `SessionStore`'a bağlı
olarak hangi div'lerin görüneceğini ve nasıl yerleşeceğini yönetir.

**WebGL bağlamı yalnızca görünür terminale.** Tarayıcı başına eşzamanlı WebGL
bağlamı sınırlı (~16); her oturuma bir tane açmak 10+ oturumda tükeniyor. Bu yüzden
`WebglAddon` seçili terminale yükleniyor, geçişte `dispose()` edilip yenisine
veriliyor — gizli terminaller DOM renderer'a düşüyor. Zaten görünmeyeni GPU'da
çizmenin anlamı yok, ve aynı anda görünür terminal sayısı en fazla iki.

## D2. Görünmeyen oturumlar da beslenmeli

Arka plandaki oturumun PTY'sini okumaya devam etmeli ve çıktıyı gizli xterm
örneğine yazmalıyız. Yoksa oturuma geçtiğinde ekran boş/eski kalır.

Sonuç: `PtyProcess` okuma döngüsü seçili olup olmamaktan bağımsız çalışır.

**Ama `display:none` bunu kırardı.** Sıfır boyutlu elemanda ne `term.open()` doğru
kurulur ne de `fit()` ölçebilir:

| İşlem | `display:none` | `visibility:hidden` |
|---|---|---|
| `term.write(...)` | ✅ | ✅ |
| `term.open(div)` | ❌ eleman sıfır boyutlu | ✅ |
| `fitAddon.fit()` | ❌ ölçemez | ✅ ölçü korunuyor |

**Karar: `visibility:hidden`.** Eleman düzende yerini koruduğu için ölçülebilir
kalıyor; gizli terminal de açılabiliyor, fit edilebiliyor, beslenebiliyor. Bunun
pratik karşılığı D9'da: pencere boyu değişince gizli olanlar dahil **her** terminal
yeniden fit edilip kendi `ioctl(TIOCSWINSZ)`'ini alıyor. Ertelenen bir şey yok,
oturuma geri dönünce ekran zaten doğru boyutta.

Tüm panolar aynı `#host` içinde `position:absolute; inset:0` ile üst üste duruyor —
DOM'da taşınmıyorlar, çünkü canvas'ı yeniden bağlamak WebGL bağlamını düşürür.

> Doğrulandı (Faz 1): üç oturum açıldı, görünmeyen ikisine PTY'den yazıldı, geçiş
> yapıldığında ikisinin de içeriği eksiksiz ve doğru boyuttaydı.

## D3. Vendor dosyaları artıyor

Plan 3 dosya diyordu, tasarım 5 gerektiriyor. **İndirildi** —
`Sources/Reeve/Resources/vendor/`:

| Dosya | Paket | Sürüm | Niçin | Boyut |
|---|---|---|---|---|
| `xterm.js` | `@xterm/xterm` | 6.0.0 | çekirdek | 477 KB |
| `xterm.css` | `@xterm/xterm` | 6.0.0 | stil | 6.9 KB |
| `addon-fit.js` | `@xterm/addon-fit` | 0.11.0 | resize | 1.5 KB |
| `addon-search.js` | `@xterm/addon-search` | 0.16.0 | ⌘F araması | 77 KB |
| `addon-webgl.js` | `@xterm/addon-webgl` | 0.19.0 | GPU render, VS Code'un kullandığı | 242 KB |

Hepsi MIT, dördü de 2025-12-22'de birlikte yayınlandı (uyumlu set).
Toplam **820 KB** — tahmin edilen ~350 KB'ın iki katından fazla, ama `.app` için önemsiz.

**Paket adları değişti:** eski `xterm` değil `@xterm/xterm`; v5.3'ten sonra taşındılar.

**Global isimler** (UMD, `<script src>` ile `globalThis`e yazıyorlar):

```js
new Terminal({ ... })
term.loadAddon(new FitAddon.FitAddon())
term.loadAddon(new SearchAddon.SearchAddon())
term.loadAddon(new WebglAddon.WebglAddon())
```

Sürümler, sha256'lar ve yeniden indirme scripti: `Resources/vendor/VENDOR.md` ·
`update.sh`. xterm 6.0.0 Aralık 2025'te çıktı; Faz 0 görsel doğrulamasında tuhaflık
olursa uzun süre sahada olan 5.5.0 setine düşmek `update.sh`'te dört satır.

## D4. Yeni durum alanları

`Session` modeline eklenecek:

```swift
var lastViewedAt: Date?      // okunmamış rozeti için
var hasUnseenOutput: Bool    // sen bakmazken çıktı üretti mi
var origin: Origin           // .center | .backgroundAgent | .external
var lastOutputLine: String?  // sidebar ikinci satırı için
var tokens: Int?
var costUSD: Double?
```

`origin` yeni ve kritik: 4. bölümdeki üç farklı davranışı bu belirliyor.

## D5. Sidebar için çıktı kuyruğu

Sidebar "son çıktı satırı" gösteriyor. Bunu xterm.js'e sormak yerine Swift
tarafında oturum başına küçük bir halka tampon (son ~4 KB) tutmak daha ucuz
ve senkron.

Sonuç: `PtyProcess` içinde `RingBuffer`, ANSI kodları temizlenmiş son satır.

## D6. Durum geçişlerini izleme

"İş bitti" bildirimi ve "bitti" rozeti için `busy → idle` **geçişini** yakalamak
gerekiyor; anlık durumu bilmek yetmiyor.

Sonuç: `AgentRegistry` her poll'da önceki durumla karşılaştırıp geçiş olayı
yayınlar. Sadece anlık liste tutmak yeterli değil.

## D7. Tema köprüsü

Swift'ten xterm.js'e tema nesnesi geçirilecek, `NSApp.effectiveAppearance`
değişimi dinlenecek.

## D8. `claude attach` desteği

Arka plan ajanını terminalde açabilmek için yeni PTY şablonu:
`claude attach <shortId>`.

**Doğrulandı.** Bir `claude --bg` açılıp `agents --json --all` çıktısına bakıldı:
arka plan kayıtları normal kayıtlardan iki alanla ayrılıyor.

```json
{ "pid": 31090,
  "id": "fee53a86",              // ← attach/logs/stop/rm bunu istiyor
  "kind": "background",          // ← "interactive" değil
  "sessionId": "fee53a86-abce-4d5f-bf4b-459976a247ce",
  "name": "fee53a86", "status": "idle", "state": "blocked" }
```

Kısa id `sessionId`'nin ilk 8 hanesi, ama türetmeye gerek yok — `id` alanı hazır
geliyor. İnteraktif kayıtlarda bu alan **hiç yok**, yani `id`'nin varlığı tek başına
"bu bir arka plan ajanı" demek.

Not: `claude attach --help`, "returns to agent view, Ctrl+Z drops back to your
shell" diyor — yani attach tam ekranı devralıyor. Panel başlığı ve kapatma
davranışı buna göre kurgulanmalı.

## D9. İki panel → panel başına resize  ⚠️ önemli

İki terminal aynı anda görünür olduğu için `addon-fit` **her görünür panel için
ayrı** çalışmalı ve her biri kendi `ioctl(TIOCSWINSZ)` çağrısını tetiklemeli
(bkz. `PLAN.md` §2.2). Mimari değişmiyor, ama boyut zinciri artık tek değil çoklu.

**Bağlı risk:** bölünen her panelde terminal daralıyor ve Claude'un TUI'si dar
alanda bozulabiliyor — kutu çizimleri kırılır, diff'ler sarar. Bölmeye bu yüzden
eşik konuldu: terminal alanı 760 px'in altına düşüyorsa bölme reddediliyor.
Tavan **üç panel**.

> **Uygulandı.** Panolar DOM'da taşınmıyor, sadece `left`/`width` değişiyor —
> canvas'ı yeniden bağlamak WebGL bağlamını düşürürdü. Gizli panolar 0. slotun
> ölçüsünü alıyor, görünür olduklarında zaten doğru boyutta oluyorlar. Pencere
> boyu değişince `ResizeObserver` **her** panoyu yeniden fit ediyor ve her biri
> kendi `ioctl(TIOCSWINSZ)`'ini alıyor.
>
> Harici oturum bir panelde seçiliyse bilgi kartı **o panelde** çıkıyor; diğer
> hücre saydam ve tıklamayı altındaki terminale geçiriyor.

## D10. Sidebar kademeleri → kalıcı tercih + hover balonu

Üç kademe (geniş / dar / kapalı) iki şey gerektiriyor:

- Seçilen kademe `UserDefaults`'ta saklanmalı, uygulama aynı halde açılmalı.
- Dar kademede ismin son iki karakteri gösterildiği için **çakışma mümkün**
  (`center-9f` ve `project-9f` ikisi de `9f`). Kısaltma üretici çakışmayı görüp
  üç karaktere çıkmalı.
- Dar ve kapalı kademede tam isim `NSView.toolTip` ile verilmeli.

Kademe değişimi de bir boyut değişimi, yani D9'daki zinciri tetikliyor.

## D11. Arama indeksi

⌘K oturum adı, klasör ve branch üzerinden eşleşiyor. `SessionStore` üzerinde
basit bir fuzzy eşleştirme yeterli — oturum sayısı onlarla ölçülüyor, ayrı bir
indeks yapısına gerek yok. Sıralama kuralı sabit: **önce `waiting`**, sonra eşleşme
skoru, sonra son aktivite.

`⌥⏎` (ikinci panelde aç) `SessionStore`'da "hangi oturum hangi panelde" durumunu
gerektiriyor — tek bir `selectedID` yetmiyor, `panes: [UUID?]` olmalı.

---

## Karara bağlanacaklar

1. **Satır içi izin düğmeleri.** DİKKAT satırındaki oturuma `İzin ver / Reddet`
   düğmeleri konsun mu? Oturuma hiç geçmeden onaylarsın; karşılığında satır yükselir
   ve sidebar ağırlaşır. (Tasarım keşfinde "Yön B"den gelen fikir.)
2. Sağ inceleme paneli Faz 3'te mi kalsın, yoksa v1'de basit bir versiyonu olsun mu?
3. Okunmamış rozeti (`•`) gerekli mi, yoksa gürültü mü yaratır?
4. Dock badge ve bildirimler varsayılan açık mı gelsin?
5. ~~Sidebar'da alt-ajanları her zaman mı gösterelim, yoksa sadece seçili oturumda mı?~~
   **Karar (Faz 3): yalnızca panelde duran oturumda.** Her satırın altına açmak
   sidebar'ı gürültüye boğuyordu; mockup da böyle çiziyordu. Arka plan süreçleri
   de aynı kuralı izliyor.
