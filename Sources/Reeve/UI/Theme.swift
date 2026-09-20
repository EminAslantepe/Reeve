import AppKit
import SwiftUI

/// Koyu yüzeyler, okunabilir metin tonları ve ortak arayüz ölçüleri.
enum Theme {

    // Yüzeyler
    static let appBG     = Color(hex: 0x0B0B0B)   // --app-bg
    static let sidebar   = Color(hex: 0x111111)   // --app-side
    static let terminal  = Color(hex: 0x0B0B0B)   // terminal.html ile eşleşir
    static let titlebar  = Color(hex: 0x111111)
    static let statusbar = Color(hex: 0x101010)
    static let searchBG  = Color(hex: 0x0D0D0D)
    static let rule      = Color(hex: 0x2B2B2B)   // --app-rule
    static let ruleSoft  = Color(hex: 0x222222)   // --app-rule-soft
    static let selection = Color(hex: 0x202020)   // --app-sel
    static let focusRule = Color(hex: 0x505050)

    // Mürekkep
    static let ink  = Color(hex: 0xECECEC)        // --app-ink
    static let ink2 = Color(hex: 0xB0B0B0)        // --app-ink-2
    static let ink3 = Color(hex: 0x898989)        // --app-ink-3

    // Durum — renk TEK başına taşımıyor, biçimle birlikte (bkz. StatusDot)
    static let wait   = Color(hex: 0xEFA65E)      // --st-wait
    static let busy   = Color(hex: 0xEC9147)      // --st-busy
    static let idle   = Color(hex: 0x858585)      // --st-idle
    static let agent  = Color(hex: 0xC8A584)      // --st-bg
    static let error  = Color(hex: 0xEF6A5E)      // --st-err

    // Fark görünümü — terminal paletindeki yeşil ve kırmızıyla aynı.
    static let diffAdd = Color(hex: 0x6FCF97)
    static let diffDel = Color(hex: 0xEF6A5E)

    // Sheet / kontroller
    static let sheetBG   = Color(hex: 0x151515)
    static let control   = Color(hex: 0x141414)
    static let choiceOn  = Color(hex: 0x1B1B1B)
    static let button    = Color(hex: 0x292929)
    static let primary   = Color(hex: 0xEC9147)

    // ⌘K paleti
    static let paletteBG     = Color(hex: 0x171717)
    static let paletteBorder = Color(hex: 0x363636)
    static let paletteRowOn  = Color(hex: 0x252525)
    static let paletteFoot   = Color(hex: 0x111111)

    // Ölçüler
    static let sidebarWidth: CGFloat = 236
    static let hairline: CGFloat = 0.5

    static var nsPaletteBG: NSColor { NSColor(paletteBG) }

    static var nsSheetBG: NSColor { NSColor(sheetBG) }

    static var nsAppBG: NSColor { NSColor(appBG) }
    static var nsTitlebar: NSColor { NSColor(titlebar) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
