import AppKit
import SwiftUI

/// "Center Ajan Konsolu" mockup'ının renk ve ölçü sözlüğü.
/// Değerler mockup'ın CSS değişkenlerinden birebir alındı; elle sayı uydurulmaz,
/// bir renk değişecekse önce orada değişir.
enum Theme {

    // Yüzeyler
    static let appBG     = Color(hex: 0x1C1C20)   // --app-bg
    static let sidebar   = Color(hex: 0x212127)   // --app-side
    static let terminal  = Color(hex: 0x121215)   // --app-term
    static let titlebar  = Color(hex: 0x24242A)
    static let statusbar = Color(hex: 0x1A1A1F)
    static let searchBG  = Color(hex: 0x191920)
    static let rule      = Color(hex: 0x31313A)   // --app-rule
    static let ruleSoft  = Color(hex: 0x292930)   // --app-rule-soft
    static let selection = Color(hex: 0x2F3040)   // --app-sel

    // Mürekkep
    static let ink  = Color(hex: 0xE6E6EA)        // --app-ink
    static let ink2 = Color(hex: 0x9A9AA6)        // --app-ink-2
    static let ink3 = Color(hex: 0x6A6A77)        // --app-ink-3

    // Durum — renk TEK başına taşımıyor, biçimle birlikte (bkz. StatusDot)
    static let wait   = Color(hex: 0xE89440)      // --st-wait
    static let busy   = Color(hex: 0x5B93FF)      // --st-busy
    static let idle   = Color(hex: 0x71717F)      // --st-idle
    static let agent  = Color(hex: 0xA98BF5)      // --st-bg
    static let error  = Color(hex: 0xEF6A5E)      // --st-err

    // Sheet / kontroller
    static let sheetBG   = Color(hex: 0x26262C)
    static let control   = Color(hex: 0x1B1B21)
    static let choiceOn  = Color(hex: 0x32323C)
    static let button    = Color(hex: 0x33333D)
    static let primary   = Color(hex: 0x3B6FE0)

    // ⌘K paleti
    static let paletteBG     = Color(hex: 0x2A2A32)
    static let paletteBorder = Color(hex: 0x43434F)
    static let paletteRowOn  = Color(hex: 0x383844)
    static let paletteFoot   = Color(hex: 0x24242C)

    // Ölçüler
    static let sidebarWidth: CGFloat = 268

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
