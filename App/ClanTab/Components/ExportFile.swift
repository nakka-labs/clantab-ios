import Foundation

/// Writes export content to the temp directory so it can be shared via
/// `ShareLink(item: url)` with a real filename and extension — unlike sharing
/// a plain `String`/`Data`, this lets the receiving app see it as an actual
/// `.csv`/`.json` file. File I/O belongs here, not in `ClanTabKit`'s pure
/// `Export` functions.
enum ExportFile {
    static func write(_ content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func write(_ data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Strips characters that aren't safe in a filename, so a group name like
    /// "Goa Trip 🌴" becomes a usable "Goa-Trip-".
    static func sanitizedFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(cleaned)
        return result.isEmpty ? "clantab-group" : result
    }
}
