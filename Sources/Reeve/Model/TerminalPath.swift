import Foundation

/// Terminal çıktısında geçen bir yol metnini gerçek bir dosyaya çevirir.
///
/// Claude sürekli `Sources/Reeve/UI/Theme.swift:43` gibi yollar basıyor ve
/// bunların tıklanabilir olması isteniyor (`terminal.html` içindeki link
/// sağlayıcı). Ama dosya adına **benzeyen** metin de bol: "Faz 1.5", "PLAN.md §7".
/// Ayrımı burada yapıyoruz — diskte karşılığı olmayan aday link olmuyor.
enum TerminalPath {

    /// Göreli yol oturumun **canlı** dizinine göre çözülüyor: `cd` edilmişse
    /// doğru kök orası, açılış dizini değil.
    ///
    /// Klasörler de `nil` dönüyor; görüntüleyici dosya gösteriyor, klasör değil.
    static func resolve(_ text: String, in cwd: String?) -> URL? {
        guard !text.isEmpty else { return nil }

        var expanded = text
        if expanded.hasPrefix("~") {
            expanded = (expanded as NSString).expandingTildeInPath
        }

        let full: String
        if expanded.hasPrefix("/") {
            full = expanded
        } else if let cwd, cwd.hasPrefix("/") {
            full = (cwd as NSString).appendingPathComponent(expanded)
        } else {
            return nil          // göreli yol ama nereye göre olduğunu bilmiyoruz
        }

        let standardized = (full as NSString).standardizingPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: standardized)
    }

    /// Çalışma dizinine göre bulunamayan adayı repo içinde adıyla arar.
    ///
    /// Claude dosya adlarını çoğu zaman kısaltıyor — "main.swift", ya da başlık
    /// altında "UI/ — Theme.swift". Bunların hiçbiri çalışma dizinine göre
    /// çözülmüyor; repo kökü `Sources/Reeve/main.swift` diyor.
    ///
    /// Ad **tek** dosyayla eşleşirse ona bağlanıyor; birden fazlaysa hiç
    /// bağlanmıyor. Yanlış dosyayı açmak, link olmamasından daha kötü.
    static func locate(_ text: String, in index: FileIndex) -> URL? {
        var candidate = text
        while candidate.hasPrefix("./") { candidate = String(candidate.dropFirst(2)) }
        guard !candidate.isEmpty, !candidate.hasPrefix("/"), !candidate.hasPrefix("~")
        else { return nil }

        let name = (candidate as NSString).lastPathComponent
        guard let sameName = index.byName[name] else { return nil }
        // Aday bir yol parçası taşıyorsa ("UI/Theme.swift") onu da doğruluyoruz.
        let matches = candidate == name
            ? sameName
            : sameName.filter { $0 == candidate || $0.hasSuffix("/" + candidate) }
        guard matches.count == 1, let only = matches.first else { return nil }
        return URL(fileURLWithPath: (index.root as NSString).appendingPathComponent(only))
    }
}
