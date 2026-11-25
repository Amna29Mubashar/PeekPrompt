import SwiftUI
import CoreText

/// Font families the script can be shown in.
enum PrompterFont: String, CaseIterable, Identifiable {
    case rounded, system, serif, mono, dyslexic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: return "Rounded"
        case .system: return "Standard"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        case .dyslexic: return "OpenDyslexic"
        }
    }

    func font(size: Double, italic: Bool = false, weight: Font.Weight = .medium) -> Font {
        let base: Font
        switch self {
        case .rounded: base = .system(size: size, weight: weight, design: .rounded)
        case .system:  base = .system(size: size, weight: weight, design: .default)
        case .serif:   base = .system(size: size, weight: weight, design: .serif)
        case .mono:    base = .system(size: size, weight: weight, design: .monospaced)
        case .dyslexic:
            // The bundled italic file has its own name; no synthetic italic needed.
            return .custom(italic ? "OpenDyslexic-Italic" : "OpenDyslexic-Regular", size: size)
        }
        return italic ? base.italic() : base
    }
}

/// Dark (default) or light prompter.
enum PrompterTheme: String, CaseIterable, Identifiable {
    case dark, light

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var background: Color { self == .dark ? .black : Color(white: 0.97) }
    var text: Color { self == .dark ? .white : Color(white: 0.08) }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Makes the fonts bundled in the app (OpenDyslexic) available without installing them.
enum FontRegistrar {
    static func registerBundledFonts() {
        let bundle = Bundle.main
        let urls = (bundle.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "otf", subdirectory: "Fonts") ?? [])
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered is fine; anything else is worth a log line.
                if let error = error?.takeRetainedValue() {
                    print("PeekPrompt: font \(url.lastPathComponent): \(error)")
                }
            }
        }
    }
}
