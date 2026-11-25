import AppKit
import UniformTypeIdentifiers

/// Turns documents into plain script text.
///  - .txt / .md: read as text
///  - .rtf / .docx / .doc / .odt / .html: macOS's built-in document reader
/// The Pro edition adds PDF and PowerPoint (speaker notes).
enum ScriptImporter {
    enum ImportError: LocalizedError {
        case unreadable(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return String(localized: "PeekPrompt couldn't read \(name).")
            case .empty: return String(localized: "That file doesn't contain any text to read.")
            }
        }
    }

    static let baseExtensions = ["txt", "md", "markdown", "rtf", "rtfd", "docx", "doc", "odt", "html", "htm"]

    static var supportedExtensions: [String] {
        baseExtensions + (Edition.pro?.importExtensions ?? [])
    }

    static var allowedContentTypes: [UTType] {
        supportedExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    /// Shows an Open dialog. Returns (title, text) for each file the user picked.
    static func chooseFiles() -> [(title: String, text: String)] {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Script")
        panel.prompt = String(localized: "Import")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedContentTypes
        NSApp.activate()
        guard panel.runModal() == .OK else { return [] }

        var results: [(String, String)] = []
        var failures: [String] = []
        for url in panel.urls {
            do {
                results.append((url.deletingPathExtension().lastPathComponent, try text(from: url)))
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = String(localized: "Some files couldn't be imported")
            alert.informativeText = failures.joined(separator: "\n")
            alert.runModal()
        }
        return results
    }

    static func text(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let raw: String
        if let proText = try Edition.pro?.importText(from: url) {
            raw = proText
        } else {
            switch ext {
            case "txt", "md", "markdown":
                raw = try String(contentsOf: url, encoding: .utf8)
            default:
                do {
                    raw = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
                } catch {
                    throw ImportError.unreadable(url.lastPathComponent)
                }
            }
        }
        let cleaned = tidy(raw)
        guard !cleaned.isEmpty else { throw ImportError.empty }
        return cleaned
    }

    /// Trims stray whitespace and collapses runs of blank lines.
    static func tidy(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) {
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
