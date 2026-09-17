import Foundation

/// Sidebar kademeleri (UI.md §1.1 / D10).
///
/// **İki kademe.** Tasarımda üçüncü bir "kapalı" (30 px) kademe vardı; kullanımda
/// dar kademe zaten yeterince yer açıyordu, sadece noktalara inmek oturumu
/// tanınmaz hale getiriyordu.
enum SidebarTier: String, CaseIterable {
    case wide
    case narrow

    var width: CGFloat {
        switch self {
        case .wide:   return Theme.sidebarWidth
        case .narrow: return 64
        }
    }

    static let compactThreshold: CGFloat = 160
    static let minimumExpandedWidth: CGFloat = 208
    static let maximumWidth: CGFloat = 280

    static func fitting(width: CGFloat) -> SidebarTier {
        width < compactThreshold ? .narrow : .wide
    }

    static func settledWidth(_ width: CGFloat) -> CGFloat {
        fitting(width: width) == .narrow ? SidebarTier.narrow.width
            : min(max(width, minimumExpandedWidth), maximumWidth)
    }

    var next: SidebarTier { self == .wide ? .narrow : .wide }

    var symbol: String {
        self == .wide ? "sidebar.left" : "sidebar.leading"
    }

    // Seçilen kademe kalıcı: uygulama aynı halde açılıyor (D10).
    private static let key = "SidebarTier"

    static var stored: SidebarTier {
        get { SidebarTier(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .wide }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Karelerde isim baş harfleri; çakışırsa daha uzun bir kısaltma kullanılır.
enum Abbreviator {
    static func labels(for names: [String]) -> [String] {
        let words = names.map { $0.split { !$0.isLetter && !$0.isNumber } }
        let roots = words.map { $0.joined().uppercased() }
        var labels = words.map { parts -> String in
            guard let first = parts.first else { return "•" }
            if parts.count > 1, let last = parts.last {
                return (String(first.prefix(1)) + String(last.prefix(1))).uppercased()
            }
            return String(first.prefix(2)).uppercased()
        }
        for length in 3...4 {
            let counts = Dictionary(grouping: labels, by: { $0 }).mapValues(\.count)
            for index in labels.indices where counts[labels[index], default: 0] > 1 {
                labels[index] = String(roots[index].prefix(length))
            }
        }
        var used: Set<String> = []
        for index in labels.indices {
            let base = labels[index]
            var number = 2
            while used.contains(labels[index]) {
                labels[index] = String(base.prefix(2)) + String(number)
                number += 1
            }
            used.insert(labels[index])
        }
        return labels
    }
}
