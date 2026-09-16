# Reeve — Plan

macOS uygulaması. Sol panelde tüm terminal oturumları ve Claude ajanları listelenir;
sağda gerçek bir terminal çalışır. `+` ile yeni oturum açılır, istenirse doğrudan
`claude` başlatılır. Oturumlar kapatılıp öldürülebilir.

> Arayüz tasarımı ve onun backend'e getirdiği değişiklikler için: **[UI.md](UI.md)**
> Bu doküman mimariyi, UI.md ekranı anlatıyor. İkisi birlikte okunmalı.

---

## 1. Kesinleşen kararlar

| Konu | Karar | Gerekçe |
|---|---|---|
| Platform | Native macOS, SwiftUI + AppKit | Kullanıcı native istedi |
| Terminal render | **xterm.js + WKWebView** | VS Code'un kullandığı renderer; Claude Code TUI'siyle çalıştığı kanıtlı. SwiftTerm'de bu bilinmezdi |
| Swift bağımlılığı | **Yok** | Her şey Apple framework'ü: Darwin, WebKit, SwiftUI |
| Üçüncü parti | 5 statik dosya, **820 KB**, MIT | `@xterm/xterm` 6.0.0 + fit/search/webgl addon'ları, bundle içinde, `file://` ile yüklenir. Sürümler ve sha256: `Resources/vendor/VENDOR.md` |
| İnternet | Çalışma anında ağa çıkılmaz | WKWebView `file://` dışına kilitlenir |
| PTY | `forkpty()` — Darwin/util.h | Apple'ın kendi API'si, SDK'da doğrulandı |
| Ajan listesi | `claude agents --json` | TTY gerektirmiyor, scripting için tasarlanmış |
| Proje yapısı | SwiftPM (metin tabanlı) + .app paketleyici script | `.xcodeproj` binary; SwiftPM'i Xcode de doğrudan açıyor |
| App Sandbox | Kapalı | Rastgele süreç spawn + `~/.claude` okuma gerekiyor. App Store'a girmez, kişisel kullanım için sorun değil |

### Elenen seçenekler

- **SwiftTerm** — 65k satır Swift, tek geliştirici, Claude TUI'siyle uyumu doğrulanmamış.
- **Kendi emülatörümüzü yazmak** — Apple hiçbir framework sunmuyor (SDK'da doğrulandı: `Term`/`TTY`/`Console` framework'ü yok). Çekirdek emülatör ~36k satır. Haftalar sürer, asıl işimize (sidebar, ajan takibi) katkısı sıfır. Not: hiçbir terminal uygulaması bunu Swift'te yazmamış — Warp Rust, Ghostty Zig, iTerm2 ObjC, VS Code xterm.js.
- **Terminalsiz native arayüz** (`--output-format stream-json`) — Claude'un tüm UI'ını sıfırdan yazmak gerekir; `zsh`/`vim` açılamaz. Ürün hedefiyle uyuşmuyor.

---

## 2. Mimari

```
┌──────────────────── Reeve.app ──────────────────────┐
│                                                     │
│   SOL PANEL (SwiftUI)      SAĞ PANEL (WKWebView)    │
│  ┌──────────────────┐     ┌──────────────────────┐  │
│  │ ▾ Center         │     │                      │  │
│  │   ◉ center-9f    │     │      xterm.js        │  │
│  │   ○ zsh          │     │   byte → piksel      │  │
│  │ ▾ Project        │     │                      │  │
│  │   ⏸ project-2b   │     └──────────┬───────────┘  │
│  └────────┬─────────┘                │              │
│           │                    Swift köprüsü        │
│     AgentRegistry                    │              │
│  (claude agents --json)         PtyProcess          │
└───────────────────────────────────────┼─────────────┘
                                        │ PTY
                                        ▼
                                 claude / zsh süreci
```

**Veri akışı — klavye:**
tuş → xterm.js yakalar → `webkit.messageHandlers` → Swift → `write(fd, ...)` → süreç

**Veri akışı — ekran:**
süreç yazar → `read(fd)` → Swift → `evaluateJavaScript("term.write(...)")` → xterm.js çizer

**Resize:** `addon-fit` sütun/satır hesaplar → Swift'e mesaj → `ioctl(fd, TIOCSWINSZ)` → süreç SIGWINCH alır

### 2.1 Push mı, poll mı? — iki ayrı yol

Sık karışan nokta: **terminal içeriği hiç yoklanmıyor.** Yoklama sadece sol paneldeki
liste için. İkisi tamamen ayrı mekanizmalar:

| | Nasıl gelir | Gecikme |
|---|---|---|
| Terminal byte'ları | **Push** — çekirdek bizi uyandırır | ~1 ms |
| Oturum listesi / durum | **Poll** — `claude agents --json` (pencere öndeyken 1 sn, arkada 5 sn) | 1–5 sn |
| Hook olayları (Faz 3) | **Push** — hook script localhost'a POST eder | anlık |

**Terminal okuma döngüsü.** `forkpty()` bir dosya numarası (fd) veriyor. Onu
`DispatchSource.makeReadSource(fileDescriptor:)` ile kaydediyoruz — "bu fd'ye veri
gelirse beni uyandır" demek. Sorgulama döngüsü yok, boşta CPU harcanmıyor.

```
claude yazar → çekirdek PTY tamponu → DispatchSource uyanır
            → read(fd) → evaluateJavaScript("t.write(...)") → xterm.js çizer
```

**Toplu gönderim şart.** Çıktı sel gibi akarsa her okuma için ayrı
`evaluateJavaScript` çağırmak köprüyü boğar. Okunanlar biriktirilip **~8–16 ms'de bir
tek çağrıda** gönderilmeli (VS Code da böyle yapıyor). Bu yapılmazsa arayüz,
terminalin kendisi değil köprü yüzünden takılır.

**Görünmeyen oturumlar da okunur.** Seçili olmayan oturumun fd'si de dinlenir ve
gizli xterm örneğine yazılır (bkz. `UI.md` D2). Yoksa o oturuma geçildiğinde ekran
boş/eski kalır.

### 2.2 Claude'un TUI'si — otomatik, ama boyut bizim sorumluluğumuzda

Tam ekran arayüze geçiş için **kod yazmıyoruz.** `claude` çalışınca:

1. `isatty()` kontrol eder, gerçek TTY görür, interaktif moda girer
2. `\x1b[?1049h` gönderir — *alternate screen buffer'a geç*
3. Tam ekran arayüzünü çizer

xterm.js bu diziyi zaten biliyor; `vim` veya `htop` açmakla aynı şey. Çıkışta
`\x1b[?1049l` ile alttaki shell ekranı scrollback bozulmadan geri gelir.

**Ama boyutu doğru bildirmek zorundayız.** Claude TUI'yi `sütun × satır` sayısına
göre çiziyor; yanlış boyutta kutu kenarlıkları kırılır, diff'ler sarar. Zincir:

```
boyut değişti → addon-fit div'i ölçer (ör. 132×41) → Swift'e mesaj
             → ioctl(fd, TIOCSWINSZ) → çekirdek SIGWINCH gönderir → claude yeniden çizer
```

Bu zincir **her** boyut değişiminde çalışmalı: pencere sürüklenince, sidebar kademe
değiştirince, panel ikiye bölününce. Ev yapımı terminallerde TUI uygulamalarının
bozulmasının bir numaralı sebebi budur — Faz 0'da ilk doğrulanacak şey.

**Ortam değişkenleri.** `TERM=xterm-256color` ve `COLORTERM=truecolor` verilmeli;
yoksa claude kendini kısıtlı bir terminalde sanıp sade moda düşer.

---

## 3. Veri kaynakları (4 katman)

Sol paneli besleyen katmanlar. Üstteki ikisi stabil, alttaki ikisi bonus.

### Katman 1 — `claude agents --json --all` (omurga)

Periyodik çalıştırılır, önceki sonuçla diff'lenir. Doğrulanmış çıktı:

```json
[
  { "pid": 63678, "cwd": "/Users/x/Desktop/Center", "kind": "interactive",
    "startedAt": 1789562037165, "sessionId": "50aaca80-...",
    "name": "center-9f", "status": "busy" },
  { "pid": 61099, "cwd": "/Users/x/Desktop/Project", "kind": "interactive",
    "sessionId": "fd724aef-...", "name": "project-2b",
    "status": "waiting", "waitingFor": "dialog open" }
]
```

Kritik avantaj: **Reeve dışında, iTerm'de elle açılmış oturumlar da burada görünüyor.**
`status` üç değer alıyor: `idle` · `busy` · `waiting` (+ `waitingFor` açıklaması).

**Poll sıklığı bedava değil.** Her çağrı ayrı bir süreç başlatıyor: ölçüm **~140 ms
duvar, ~0.10 s CPU** (§9). 1 Hz'de bu, sadece sol paneli beslemek için sürekli
~%10 çekirdek demek — pilde hissedilir. Bu yüzden sıklık uyarlanır:

| Durum | Aralık |
|---|---|
| Pencere önde | 1 sn |
| Pencere arkada / gizli | 5 sn |
| Hook köprüsü ayakta (Faz 3) | 5 sn — anlık geçişleri zaten hook veriyor |

Poll'ün işi bundan sonra "durum değişti mi" değil, **yeni/kaybolan oturumu yakalamak**
ve hook'suz (dışarıda açılmış) oturumları takip etmek.

### Katman 2 — Hooks (anlık push)

`~/.claude/settings.json` içine hook yazılır; küçük bir script event JSON'unu
Reeve'e ulaştırır. Polling gecikmesini sıfırlar.

> **Taşıma katmanı değişti (Faz 3).** Plan `NWListener` + `127.0.0.1` + token
> diyordu; onun yerine **spool dizini** kullanıldı: script olayı benzersiz bir
> geçici dosyaya yazıp `mv` ile `~/.claude/reeve/events/` altına atıyor, Reeve
> dizini `DispatchSource` ile izliyor. Gerekçe: imzasız uygulamanın soket
> dinlemesi güvenlik duvarı uyarısı çıkarabiliyor; port her açılışta değişirken
> `settings.json`'daki komut sabit kalıyor; `mv` atomik olduğu için büyük
> `tool_input` payload'ları birbirine karışmıyor; Reeve kapalıyken dizin de
> olmadığından script tek `[ -d ]` kontrolüyle çıkıyor ve dosya birikmiyor.

| Event | Kazanç |
|---|---|
| `PreToolUse` / `PostToolUse` | Hangi tool çalışıyor, argümanı ne |
| `Notification` | İzin bekliyor → rozet + macOS bildirimi |
| `SubagentStop` | Alt-ajan bitti |
| `Stop` | Tur bitti, sıra kullanıcıda |
| `SessionStart` / `SessionEnd` | Yaşam döngüsü |

PTY ↔ oturum eşlemesi: PTY'ye `CENTER_PANE_ID` env değişkeni enjekte edilir, hook
script'i bunu `session_id` ile birlikte geri yollar.

> **Doğrulandı.** `CENTER_PANE_ID=test-pane-123` ile çalıştırılan bir `claude -p`
> oturumunda hook script'i değişkeni gördü. Bu, `--session-id` verilmeden açılmış
> oturumları (kullanıcının shell'de elle `claude` yazdığı hal) da bağlayabildiğimiz
> anlamına geliyor; oturum kimliği `SessionStart`/`PreToolUse` ile sonradan öğrenilip
> Katman 1 eşleşmesi de kuruluyor.

**Ölçülen payload alanları** (claude 2.1.273):

| Olay | Alanlar |
|---|---|
| `SessionStart` | `session_id` · `transcript_path` · `cwd` · `source` |
| `PreToolUse` | + `tool_name` · `tool_input` · `tool_use_id` · `permission_mode` · `effort` |
| `PostToolUse` | + `tool_response` · `duration_ms` |
| `Stop` | + `last_assistant_message` · `background_tasks` · `session_crons` |
| `SessionEnd` | + `reason` |

Alt-ajanlar için `SubagentStop`'u beklemeye gerek yok: `PreToolUse`/`PostToolUse`
çiftinde `tool_name == "Task"` zaten başlangıcı, adı ve süreyi veriyor.

> **Dikkat:** `settings.json`'a yazarken mevcut hook'lar merge edilmeli, ezilmemeli.
> Kurulum opt-in olsun, ayarlardan geri alınabilsin. (Şu an kullanıcının hiç hook'u yok.)

### Katman 3 — Transcript JSONL (bonus)

`~/.claude/projects/<cwd-slug>/<sessionId>.jsonl`
Slug kuralı: cwd'deki `/` → `-` (`/Users/x/Desktop/Center` → `-Users-x-Desktop-Center`).

Append-only; kaydedilmiş offset'ten yalnızca yeni byte'lar okunur. Verdiği: model,
token/maliyet, tam konuşma geçmişi.

**Ölçülen şema** (claude 2.1.273) — aranan her şey `cost-state` kaydında:

```json
{ "type": "cost-state", "totalCostUSD": 4.97, "totalDuration": 2354745,
  "totalLinesAdded": 0, "totalLinesRemoved": 0,
  "modelUsage": { "claude-opus-5[1m]": {
      "inputTokens": 1802, "outputTokens": 61217, "thinkingTokens": 25439,
      "cacheReadInputTokens": 4638263, "cacheCreationInputTokens": 111070,
      "costUSD": 4.969 } } }
```

`type:"assistant"` kayıtları `message.model` ve tur başına `usage` veriyor;
konuşma adımları da oradan çıkarılıyor.

> **Dosya slug kuralına güvenilmiyor.** `cwd`'deki `/` → `-` dönüşümü resmi bir
> sözleşme değil (noktalı yolların nasıl kodlandığı doğrulanamadı). Önce slug
> denenip tutmazsa `~/.claude/projects/*/` altında `<sessionId>.jsonl` aranıyor;
> bulunan yol oturum başına önbelleğe alınıyor.

> **Dikkat:** Resmi API değil, sürümle değişebilir. Savunmacı parse ediliyor;
> bozulursa uygulama etkilenmiyor, sadece bu katman sessizce susuyor.

### Katman 4 — Process ağacı (bonus)

PTY'nin child pid'inden alt süreçler gezilir.

> **`proc_listchildpids` kullanılmadı.** Ölçüldü: iki `sleep` çocuğu olan bir kabuk
> için boş döndü. Onun yerine `proc_listallpids` ile tüm pid'ler alınıp `ppid`'lerden
> ağaç kuruluyor — ~200 süreçte milisaniyeler. `proc_pidinfo(PROC_PIDTASKINFO)`
> RSS'i de veriyor. Ara kabuklar (`bash`, `zsh`, `sh`, `login`) gizleniyor;
> kullanıcı `npm run dev` görmek istiyor, onu taşıyan kabuğu değil. Claude'un arka planda
başlattığı gerçek işlemler (`npm run dev`, test runner) buradan çıkar; CPU/RAM ile
birlikte gösterilir.

---

## 4. Sol panel

```
┌──────────────────────────────┐
│ ⌕ ara                    [+] │
├──────────────────────────────┤
│ ▾ Center        main  ●3     │
│   ◉ center-9f   busy    12m  │  ← claude, Opus 5
│     ⚙ Explore   running  18s │  ← alt-ajan (katman 2/3)
│     ⌘ npm dev   pid 4412     │  ← arka plan süreç (katman 4)
│   ○ zsh         idle         │
│                              │
│ ▾ Project       feat/x  ↑2   │
│   ⏸ project-2b  İZİN BEKLİYOR│  ← turuncu, tıkla → odaklan
│   ◉ project-8b  idle     2h  │
│                              │
│ ▾ Arka plan ajanları         │
│   ⬢ api-refactor  running    │  ← claude --bg
└──────────────────────────────┘
```

**Durum renkleri:** mavi = busy · turuncu = izin bekliyor · gri = idle · kırmızı = hata

**Kural:** izin bekleyenler her zaman en üste toplanır. 5 ajan koştururken tek
önemli sinyal budur.

**Sağ tık:** Odaklan · Yeniden başlat · Durdur (`claude stop`) · Kill (SIGKILL) ·
Sil (`claude rm`) · Finder'da aç · Transcript'i göster

**Gruplama:** repo/cwd bazında. Her grup başlığında git branch + kirli dosya sayısı
+ ahead/behind.

---

## 5. Yeni oturum akışı (`+`)

`--session-id <uuid>` flag'i mevcut → **UUID'yi Reeve üretir**, böylece
PTY ↔ oturum ↔ JSONL eşlemesi tahminle değil garantiyle kurulur.

| Şablon | Komut |
|---|---|
| Shell | `exec /bin/zsh -i` |
| Claude | `claude --session-id <uuid> --name <slug>` |
| Claude (worktree) | `claude --worktree <ad> --session-id <uuid>` |
| Claude (arka plan) | `claude --bg ...` → PTY yok, listede görünür |

`--worktree` her ajana izole git branch'i veriyor, `--name` sol paneldeki etiketi
belirliyor. İkisi de hazır, implemente etmiyoruz.

Claude'dan çıkılınca terminal ölmesin: `claude ...; exec /bin/zsh -i`

---

## 6. Proje yapısı

```
Reeve/
  Package.swift                 bağımlılık yok
  Sources/Reeve/
    main.swift                  NSApplication bootstrap
    PTY/
      PtyProcess.swift          forkpty, read/write, TIOCSWINSZ
      TerminalWebView.swift     WKWebView + köprü (messageHandler)
    Agents/
      AgentRecord.swift         agents --json kaydı (savunmacı çözülüyor)
      AgentRegistry.swift       poller — önde 1 sn, arkada 5 sn
      Notifier.swift            bildirimler + Dock rozeti
      HookServer.swift          NWListener, 127.0.0.1, token'lı        (Faz 3)
      HookInstaller.swift       settings.json merge (opt-in)           (Faz 3)
      TranscriptTail.swift      DispatchSource JSONL tail              (Faz 4)
      ProcessTree.swift         libproc                                (Faz 3)
    Git/GitProbe.swift          branch, dirty, ahead
    UI/
      Theme.swift               mockup'ın renk/ölçü sözlüğü — tek kaynak
      SidebarView.swift
      SessionRow.swift
      NewSessionSheet.swift
      StatusBarView.swift
      ExternalSessionCard.swift
    Model/
      Session.swift             @Observable oturum
      SessionStore.swift        tek doğruluk kaynağı
      SessionFactory.swift      şablonlar + isim üretimi
    Resources/                  hedefin İÇİNDE olmak zorunda (bkz. aşağıdaki not)
      terminal.html             tek boş <div>
      vendor/                   xterm.js · xterm.css · addon-{fit,search,webgl}.js
        VENDOR.md               sürümler, sha256, global isimler
        update.sh               yeniden indirir + checksum karşılaştırır
  Scripts/
    bundle.sh                   .app paketleyici (Info.plist + Resources)
```

> **Resources'ın yeri pazarlığa açık değil.** SwiftPM bir hedefin resource'larını
> yalnızca hedef dizininin içinde kabul ediyor. `path: "Sources/Reeve"` iken
> `.copy("../../Resources")` yazmak hedefin dışına çıkıyor: SwiftPM **hata da uyarı
> da vermeden** o satırı atlıyor, `.bundle` hiç üretilmiyor ve `Bundle.module`
> kodu üretilmediği için `error: type 'Bundle' has no member 'module'` alıyorsun —
> yani hata `Package.swift`'i değil, senin Swift dosyanı işaret ediyor. Doğrusu:
> `Sources/Reeve/Resources/` + `.copy("Resources")`. (Ölçüldü, §9.)

### Veri modeli

```swift
struct Session: Identifiable {
    let id: UUID              // Reeve üretir, --session-id ile claude'a verilir
    var paneID: UUID          // PTY paneli (CENTER_PANE_ID)
    var name: String
    var cwd: String
    var kind: Kind            // .shell | .claude | .backgroundAgent
    var pid: Int32?
    var status: Status        // .idle | .busy | .waiting(String) | .exited(Int32)
    var startedAt: Date
    var git: GitState?
    var children: [ChildProcess]
    var subagents: [Subagent]
}
```

Dört katman da `SessionStore`'a yazar; UI sadece onu izler.

---

## 7. Fazlar

| Faz | Çıktı | Durum |
|---|---|---|
| **0** | xterm.js + WKWebView + `forkpty` ile tek pencerede çalışan terminal. Claude açılır, TUI birebir doğru görünür. **Gözle doğrulanır.** | ✅ **bitti** — gözle doğrulandı |
| **1** | Çoklu PTY, sol panel, `+` ile yeni oturum (shell/claude şablonları), kapat/kill, oturum arası geçiş | ✅ **çekirdek bitti** |
| **1.5** | İki panel bölme (1\|2), sidebar kademeleri (geniş/dar/kapalı), ⌘K oturum arama, ⌘F terminalde arama | sırada |
| **2** | `claude agents --json` entegrasyonu → canlı durum, dışarıda açılan oturumları yakalama, **izin-bekliyor rozeti + macOS bildirimi**, arka plan ajanları + `claude attach`, harici oturum bilgi kartı, **git rozetleri** | ✅ **bitti** |
| **3** | Hook köprüsü (anlık tool durumu), alt-ajanlar, arka plan süreç ağacı | ✅ **bitti** |
| **4** | Transcript görüntüleyici, token/maliyet, worktree listesi, oturum geri yükleme | ✅ **bitti** |

Faz 1'de bilinçli olarak dışarıda bırakılanlar Faz 1.5'e taşındı; UI.md §1'deki
`1|2` segmenti ve üç kademeli sidebar oraya ait.

Git rozetleri Faz 3'ten Faz 2'ye çekildi: `GitProbe` hook'lara, transcript'e ya da
`libproc`'a bağlı değil — üç git komutu ve kısa ömürlü bir önbellek, Faz 3'ün geri
kalanını beklemesi için sebep yoktu.

**Faz 2 sonunda asıl istenen şey çalışır durumda olur.**

---

## 8. Riskler ve açık sorular

**Riskler**

1. ~~Emülatör Claude TUI'sini basabilecek mi~~ — xterm.js seçimiyle kapandı (VS Code kanıtı).
2. **Faz 0 yine de gözle doğrulanmalı.** Köprüde byte kaçağı / encoding hatası olabilir; UTF-8 ve geniş karakterler (kutu çizimi, emoji) özellikle kontrol edilsin. Aynı spike'ta iki şey daha test edilmeli: **pencere yeniden boyutlandırılırken TUI bozulmuyor mu** (2.2'deki SIGWINCH zinciri) ve **yoğun çıktıda arayüz takılmıyor mu** (2.1'deki toplu gönderim). Üçü de köprünün klasik kırılma noktaları.
3. **`settings.json` merge'ü.** Kullanıcının hook'larını ezmek geri dönüşü zor bir hata. Yazmadan önce yedek al.
4. **JSONL formatı iç API.** Katman 3 "bonus" sayılsın, kırılırsa uygulama etkilenmesin.
5. **App Sandbox kapalı.** Notarization gerekirse ayrıca bakılacak.

**Sonraki oturumda karara bağlanacak**

- Tek pencere mi, çoklu pencere mi? (öneri: v1 tek pencere)
- ~~Uygulama kapanınca PTY'ler ölür. v1'de kalıcılık yok, öyle mi?~~
  **Karar (Faz 4): PTY'ler yaşamıyor, konuşmalar geri getirilebiliyor.** Kapanışta
  Reeve'in açtığı oturumların kimlikleri saklanıyor; `Oturum ▸ Önceki oturumları
  geri yükle` (⌘⇧R) her birini `claude --resume <id>` ile yeniden açıyor.
  Açılışta kendiliğinden süreç doğurmak sürpriz olurdu, o yüzden menüden.
- Hook kurulumu opt-in mi, ilk açılışta mı sorulacak?
- Codex / Gemini CLI desteği v1'de kapsam dışı mı? (öneri: evet, kapsam dışı; adapter katmanı Faz 3'te düşünülür)

---

## 9. Doğrulanmış bulgular

Bu plan tahmine değil, makinede ölçülen verilere dayanıyor:

**Ortam** (2026-09-16'da ölçüldü)

- macOS 26.3.1 · Swift 6.1.2 (Xcode kurulu) · `claude` 2.1.273, `/opt/homebrew/bin/claude`.
- macOS SDK'da terminal emülatörü framework'ü **yok**; `forkpty`/`openpty` `usr/include/util.h:100` içinde **var**.

**Claude CLI**

- `claude agents --json --all` çalışıyor, TTY gerektirmiyor.
- `--session-id <uuid>`, `-n/--name`, `-w/--worktree [ad]`, `--bg` mevcut; `attach`, `stop`, `rm`, `logs`, `respawn`, `agents` alt komutları mevcut.
- `attach <id>` yardım metni kısa id'yi tarif ediyor: "`claude --bg` prints and `claude agents` lists". Yani kısa id `agents` çıktısında olmalı — ama JSON'da alanın adı **hâlâ doğrulanmadı**, çünkü ölçüm anında hiç arka plan oturumu yoktu (bkz. `UI.md` D8).
- `claude agents --json` çağrısı başına **~140 ms duvar, ~0.10 s CPU** (3 ölçümün ortalaması).

**Vendor**

- `@xterm/xterm` 6.0.0 · `addon-fit` 0.11.0 · `addon-search` 0.16.0 · `addon-webgl` 0.19.0 — dördü de 2025-12-22'de birlikte yayınlandı, uyumlu set. Hepsi MIT. Toplam **820 KB** (`Resources/vendor/VENDOR.md`: sha256'lar).
- Beşi de UMD, `<script src>` ile `globalThis`e yazıyorlar: `Terminal`, `FitAddon.FitAddon`, `SearchAddon.SearchAddon`, `WebglAddon.WebglAddon` (node ile doğrulandı).
- Paket adları eski `xterm` değil **`@xterm/*`** — v5.3'ten sonra taşındılar.
- SwiftTerm (elenen): MIT, 1.690 yıldız, çekirdek 35.809 satır, toplam 65.181 satır.

**SwiftPM**

- `resources: [.copy("../../Resources")]` hedefin dışına çıkıyor: build yeşil yanıyor, **uyarı bile çıkmıyor**, ama `.bundle` üretilmiyor. İki kopyayla yan yana denendi; `Sources/Reeve/Resources/` + `.copy("Resources")` ile `Reeve_Reeve.bundle` üretiliyor ve beş vendor dosyası da `Bundle.module`'dan bulunuyor. Detay: §6 notu.
- `exclude:` bir `.copy(dizin)` çağrısının içine işlemiyor — `VENDOR.md` ve `update.sh` bundle'a giriyor (~3 KB, zararsız).

**Kullanıcı ortamı**

- `~/.claude/settings.json`'da **hiç hook yok** (`theme`, `tui`, `alwaysThinkingEnabled`, `modelSettings` var), plugin/skill kurulu değil.
