import Foundation

/// Comma-separated text with RFC 4180 quoting.
enum CSV {
    /// Quoted when it holds a comma, a quote or a line break; quotes inside are doubled.
    static func field(_ text: String) -> String {
        // By scalar, because Swift counts "\r\n" as a single character.
        let needsQuotes = text.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
        guard needsQuotes else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    /// The header and every row, one per line, ending with a line break.
    static func document(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map(row).joined(separator: "\n") + "\n"
    }
}
