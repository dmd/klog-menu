import Foundation

public struct KlogFailure: LocalizedError {
    let message: String
    public var errorDescription: String? { message }
}

public enum Klog {
    static let executable: String? = {
        let candidates = [NSHomeDirectory() + "/bin/klog", "/opt/homebrew/bin/klog", "/usr/local/bin/klog", NSHomeDirectory() + "/go/bin/klog"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static var supportsNote: Bool = (try? run(["note", "--help"])) != nil

    @discardableResult
    static func run(_ arguments: [String]) throws -> String {
        guard let executable else { throw KlogFailure(message: "klog not found. Install it with: brew install klog") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let outputText = String(decoding: output, as: UTF8.self)
        if process.terminationStatus != 0 {
            let errorText = String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw KlogFailure(message: errorText.isEmpty ? outputText : errorText)
        }
        return outputText
    }

    static func tagValue(_ value: String) -> String {
        if isPlainTagText(value) { return value }
        return "\"\(value)\""
    }

    static func isPlainTagText(_ text: String) -> Bool {
        text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    static func cleanProject(_ name: String) -> String {
        let hyphenated = name.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: \.isWhitespace).joined(separator: "-")
        return String(hyphenated.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
    }

    static func cleanTask(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func summary(project: String, task: String, description: String) -> String {
        var parts: [String] = []
        let text = description.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { parts.append(text) }
        parts.append(task.isEmpty ? "#\(project)" : "#\(project)=\(tagValue(task))")
        return parts.joined(separator: " ")
    }

    static func parseTag(_ tag: String) -> (name: String, value: String?) {
        let body = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        guard let equals = body.firstIndex(of: "=") else { return (body, nil) }
        var value = String(body[body.index(after: equals)...])
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        return (String(body[..<equals]), value)
    }

    static func firstTag(in summary: String) -> (name: String, value: String?)? {
        let range = NSRange(summary.startIndex..., in: summary)
        guard let match = tagPattern.firstMatch(in: summary, range: range),
              let matched = Range(match.range, in: summary) else { return nil }
        return parseTag(String(summary[matched]))
    }

    private static let tagPattern = try! NSRegularExpression(pattern: #"#[\p{L}\p{N}_-]+(=("[^"]*"|'[^']*'|[\p{L}\p{N}_-]*))?"#)

    static func stripTags(_ summary: String) -> String {
        let range = NSRange(summary.startIndex..., in: summary)
        let stripped = tagPattern.stringByReplacingMatches(in: summary, range: range, withTemplate: "")
        return stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func insertNote(_ note: String, intoOpenRangeOf recordDate: String, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        let wantedDate = recordDate.replacingOccurrences(of: "/", with: "-")
        guard let header = lines.firstIndex(where: { line in
            guard let match = line.range(of: #"^\d{4}[-/]\d{2}[-/]\d{2}"#, options: .regularExpression) else { return false }
            return line[match].replacingOccurrences(of: "/", with: "-") == wantedDate
        }) else { return nil }

        var index = header + 1
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            let line = lines[index]
            if let match = line.range(of: #"^([ \t]+)\S+\s*-\s*\?+(\s|$)"#, options: .regularExpression) {
                let indent = String(line[match].prefix { $0 == " " || $0 == "\t" })
                let continuation = indent + indent
                var insertAt = index + 1
                while insertAt < lines.count, lines[insertAt].hasPrefix(continuation),
                      !lines[insertAt].trimmingCharacters(in: .whitespaces).isEmpty {
                    insertAt += 1
                }
                lines.insert(continuation + note, at: insertAt)
                return lines.joined(separator: "\n")
            }
            index += 1
        }
        return nil
    }

    static func normalizeAmount(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^(\d+h)?(\d+m)?$"#, options: .regularExpression) != nil, !trimmed.isEmpty {
            return trimmed
        }
        if let match = trimmed.range(of: #"^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$"#, options: .regularExpression) {
            let pieces = trimmed[match].split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            return "\(pieces[0]) - \(pieces[1])"
        }
        return nil
    }
}

public func formatMinutes(_ minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return "\(rest)m" }
    if rest == 0 { return "\(hours)h" }
    return "\(hours)h\(rest)m"
}

public func formatClock(_ minutes: Int) -> String {
    String(format: "%d:%02d", minutes / 60, minutes % 60)
}

public struct KlogJSON: Decodable {
    let records: [Record]?
    let errors: [ParseError]?

    struct Record: Decodable {
        let date: String
        let summary: String?
        let entries: [Entry]
    }

    struct Entry: Decodable {
        let type: String
        let summary: String
        let total_mins: Int
        let start_mins: Int?
    }

    struct ParseError: Decodable {
        let line: Int?
        let title: String?
        let details: String?
    }
}
