import Foundation
import Compression

/// A tiny read-only ZIP reader, enough to open .pptx files (which are ZIP archives
/// of XML). Supports "stored" and "deflate" entries, which is all Office uses.
struct ZipReader {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: Error { case notAZip, corrupt, unsupported }

    private let data: Data
    let entries: [String: Entry]

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    init(data: Data) throws {
        self.data = data
        self.entries = try ZipReader.readCentralDirectory(data)
    }

    var fileNames: [String] { Array(entries.keys) }

    func contents(of name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        let header = entry.localHeaderOffset
        guard data.count >= header + 30, data.u32(at: header) == 0x0403_4B50 else { throw ZipError.corrupt }
        let nameLength = Int(data.u16(at: header + 26))
        let extraLength = Int(data.u16(at: header + 28))
        let start = header + 30 + nameLength + extraLength
        guard data.count >= start + entry.compressedSize else { throw ZipError.corrupt }
        let compressed = data.subdata(in: start..<(start + entry.compressedSize))

        switch entry.method {
        case 0: return compressed
        case 8: return try ZipReader.inflate(compressed, expectedSize: entry.uncompressedSize)
        default: throw ZipError.unsupported
        }
    }

    func string(of name: String) throws -> String? {
        guard let data = try contents(of: name) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Internals

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        // Find the "end of central directory" record by scanning backwards.
        guard data.count >= 22 else { throw ZipError.notAZip }
        var eocd = -1
        var i = data.count - 22
        let lowest = max(0, data.count - 65_557)
        while i >= lowest {
            if data.u32(at: i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let count = Int(data.u16(at: eocd + 10))
        var offset = Int(data.u32(at: eocd + 16))
        var result: [String: Entry] = [:]

        for _ in 0..<count {
            guard data.count >= offset + 46, data.u32(at: offset) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = data.u16(at: offset + 10)
            let compressedSize = Int(data.u32(at: offset + 20))
            let uncompressedSize = Int(data.u32(at: offset + 24))
            let nameLength = Int(data.u16(at: offset + 28))
            let extraLength = Int(data.u16(at: offset + 30))
            let commentLength = Int(data.u16(at: offset + 32))
            let localOffset = Int(data.u32(at: offset + 42))
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let name = String(decoding: nameData, as: UTF8.self)
            result[name] = Entry(name: name, method: method, compressedSize: compressedSize,
                                 uncompressedSize: uncompressedSize, localHeaderOffset: localOffset)
            offset += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    /// ZIP uses raw DEFLATE, which is what Apple's COMPRESSION_ZLIB decodes.
    private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        let capacity = max(expectedSize, 64)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { outBuffer -> Int in
            input.withUnsafeBytes { inBuffer -> Int in
                guard let outBase = outBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let inBase = inBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(outBase, capacity, inBase, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 || expectedSize == 0 else { throw ZipError.corrupt }
        output.count = written
        return output
    }
}

private extension Data {
    func u16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func u32(at offset: Int) -> UInt32 {
        UInt32(u16(at: offset)) | UInt32(u16(at: offset + 2)) << 16
    }
}
