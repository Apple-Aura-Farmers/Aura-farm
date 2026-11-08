import Foundation

/// What one import of soil report files came to, for the alert that follows it.
struct ImportSummary: Equatable {
    struct Failure: Equatable {
        var fileName: String
        var reason: String
    }

    var imported = 0
    var duplicates = 0
    var failures: [Failure] = []

    var title: String {
        if !failures.isEmpty {
            return imported == 0 ? "Nothing was imported" : "Some reports were not imported"
        }
        if imported == 0 {
            return "Already imported"
        }
        return imported == 1 ? "Imported 1 soil test" : "Imported \(imported) soil tests"
    }

    var message: String {
        var lines: [String] = []
        if imported > 0 {
            lines.append("New soil tests are in the inbox. File each one under the field it came from.")
        }
        if duplicates > 0 {
            lines.append(
                duplicates == 1
                    ? "1 report was already here and was skipped."
                    : "\(duplicates) reports were already here and were skipped."
            )
        }
        for failure in failures {
            lines.append("\(failure.fileName): \(failure.reason)")
        }
        return lines.joined(separator: "\n\n")
    }
}
