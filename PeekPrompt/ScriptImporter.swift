import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Turns documents into plain script text.
///  - .txt / .md: read as text
///  - .rtf / .docx / .doc / .odt / .html: macOS's built-in document reader
///  - .pdf: the text of every page
///  - .pptx: the speaker notes of each slide (falls back to slide text when a slide has no notes)
enum ScriptImporter {
    enum ImportError: LocalizedError {
        case unreadable(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "PeekPrompt couldn't read \(name)."
            case .empty: return "That file doesn't contain any text to read."
            }
        }
    }

    static let supportedExtensions = ["txt", "md", "markdown", "rtf", "rtfd", "docx", "doc", "odt", "html", "htm", "pptx", "pdf"]

    static var allowedContentTypes: [UTType] {
        supportedExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    /// Shows an Open dialog. Returns (title, text) for each file the user picked.
    static func chooseFiles() -> [(title: String, text: String)] {
        let panel = NSOpenPanel()
        panel.title = "Import Script"
        panel.prompt = "Import"
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
            alert.messageText = "Some files couldn't be imported"
            alert.informativeText = failures.joined(separator: "\n")
            alert.runModal()
        }
        return results
    }

    static func text(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let raw: String
        switch ext {
        case "txt", "md", "markdown":
            raw = try String(contentsOf: url, encoding: .utf8)
        case "pptx":
            raw = try PowerPointNotes.text(from: url)
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw ImportError.unreadable(url.lastPathComponent) }
            raw = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n\n")
        default:
            do {
                raw = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
            } catch {
                throw ImportError.unreadable(url.lastPathComponent)
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

/// Reads speaker notes out of a PowerPoint (.pptx) file, in slide order.
enum PowerPointNotes {
    static func text(from url: URL) throws -> String {
        let zip = try ZipReader(url: url)

        let slidePaths = try orderedSlidePaths(zip)
        var sections: [String] = []

        for (index, slidePath) in slidePaths.enumerated() {
            var body = ""
            if let notesPath = try notesPath(forSlide: slidePath, in: zip),
               let xml = try zip.contents(of: notesPath) {
                body = DrawingMLText.extract(from: xml)
            }
            // No notes? Use what's on the slide itself.
            if body.isEmpty, let xml = try zip.contents(of: slidePath) {
                body = DrawingMLText.extract(from: xml)
            }
            if !body.isEmpty {
                sections.append("[Slide \(index + 1)]\n" + body)
            }
        }
        return sections.joined(separator: "\n\n")
    }

    /// Slides in presentation order, e.g. ["ppt/slides/slide1.xml", ...].
    private static func orderedSlidePaths(_ zip: ZipReader) throws -> [String] {
        guard let presentation = try zip.contents(of: "ppt/presentation.xml"),
              let rels = try zip.contents(of: "ppt/_rels/presentation.xml.rels") else {
            // Unusual file: fall back to numeric order.
            return zip.fileNames
                .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
                .sorted { slideNumber($0) < slideNumber($1) }
        }
        let targets = Relationships.parse(rels)
        let ids = SlideIDList.parse(presentation)
        return ids.compactMap { targets[$0]?.target }.map { resolve($0, relativeTo: "ppt/") }
    }

    private static func notesPath(forSlide slidePath: String, in zip: ZipReader) throws -> String? {
        let fileName = (slidePath as NSString).lastPathComponent
        let folder = (slidePath as NSString).deletingLastPathComponent
        guard let rels = try zip.contents(of: "\(folder)/_rels/\(fileName).rels") else { return nil }
        let notes = Relationships.parse(rels).values.first { $0.type.hasSuffix("/notesSlide") }
        return notes.map { resolve($0.target, relativeTo: folder + "/") }
    }

    /// Resolves "../notesSlides/notesSlide1.xml" against "ppt/slides/".
    private static func resolve(_ target: String, relativeTo base: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts = base.split(separator: "/").map(String.init)
        for piece in target.split(separator: "/").map(String.init) {
            if piece == ".." { _ = parts.popLast() } else if piece != "." { parts.append(piece) }
        }
        return parts.joined(separator: "/")
    }

    private static func slideNumber(_ path: String) -> Int {
        Int(path.filter(\.isNumber)) ?? 0
    }
}

// MARK: - Small XML helpers

/// Reads <Relationship Id=".." Type=".." Target=".."/> entries.
private final class Relationships: NSObject, XMLParserDelegate {
    private var result: [String: (type: String, target: String)] = [:]

    static func parse(_ data: Data) -> [String: (type: String, target: String)] {
        let handler = Relationships()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "Relationship", let id = attributes["Id"], let target = attributes["Target"] else { return }
        result[id] = (attributes["Type"] ?? "", target)
    }
}

/// Reads the r:id of each <p:sldId> in presentation.xml, in order.
private final class SlideIDList: NSObject, XMLParserDelegate {
    private var ids: [String] = []

    static func parse(_ data: Data) -> [String] {
        let handler = SlideIDList()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.ids
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "p:sldId" || elementName.hasSuffix(":sldId") || elementName == "sldId" else { return }
        if let id = attributes["r:id"] ?? attributes.first(where: { $0.key.hasSuffix(":id") && $0.key != "id" })?.value {
            ids.append(id)
        }
    }
}

/// Collects the text runs (<a:t>) of a slide or notes page, one line per paragraph.
/// Skips fields such as the slide-number placeholder.
private final class DrawingMLText: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var current = ""
    private var inText = false
    private var fieldDepth = 0

    static func extract(from data: Data) -> String {
        let handler = DrawingMLText()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return ScriptImporter.tidy(handler.paragraphs.joined(separator: "\n"))
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "a:t": inText = true
        case "a:fld": fieldDepth += 1
        case "a:br": current += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "a:t": inText = false
        case "a:fld": fieldDepth = max(0, fieldDepth - 1)
        case "a:p":
            paragraphs.append(current)
            current = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText && fieldDepth == 0 { current += string }
    }
}
