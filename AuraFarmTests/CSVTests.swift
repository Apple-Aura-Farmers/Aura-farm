import XCTest

@testable import AuraFarm

final class CSVTests: XCTestCase {
    func testPlainFieldsAreLeftAlone() {
        XCTAssertEqual(CSV.field("plain text"), "plain text")
        XCTAssertEqual(CSV.field(""), "")
    }

    func testFieldsWithCommasQuotesOrLineBreaksAreQuoted() {
        XCTAssertEqual(CSV.field("a, b"), "\"a, b\"")
        XCTAssertEqual(CSV.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSV.field("two\nlines"), "\"two\nlines\"")
        XCTAssertEqual(CSV.field("a\r\nb"), "\"a\r\nb\"")
    }

    func testRowsAndDocument() {
        XCTAssertEqual(CSV.row(["a", "b,c", ""]), "a,\"b,c\",")
        XCTAssertEqual(
            CSV.document(header: ["x", "y"], rows: [["1", "2"], ["3", "4"]]), "x,y\n1,2\n3,4\n")
    }

    /// Reads CSV text back into rows of fields, for the other CSV tests.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending = iterator.next()
        while let char = pending {
            pending = iterator.next()
            if quoted {
                if char == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                quoted = true
            } else if char == "," {
                row.append(field)
                field = ""
            } else if char == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(char)
            }
        }
        return rows
    }
}
