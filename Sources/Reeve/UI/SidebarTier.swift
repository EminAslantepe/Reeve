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

/// Dar kademede isimlerin son birkaç karakteri gösteriliyor (`center-9f` → `9f`).
/// Çakışma mümkün: `center-9f` ve `project-9f` ikisi de `9f` olurdu — o yüzden
/// kısaltma üretici çakışmayı görüp uzunluğu artırıyor (D10).
enum Abbreviator {
    static func suffixes(for names: [String]) -> [String] {
        guard names.count > 1 else {
            return names.map { String($0.suffix(2)) }
        }
        for length in 2...6 {
            let candidates = names.map { String($0.suffix(length)) }
            if Set(candidates).count == candidates.count { return candidates }
        }
        return names.map { String($0.suffix(6)) }
    }
}
