import Foundation

/// Minimal RFC 4180 CSV: comma-separated, double-quote quoting with "" as
/// the escape, tolerant of \r\n and \n line endings.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            // Skip rows that are entirely empty (trailing newline artifacts).
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case ",":
                    endField()
                case "\r":
                    if let next = iterator.next(), next != "\n" { pending = next }
                    endRow()
                case "\n":
                    endRow()
                default:
                    field.append(char)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }

    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }
            .joined(separator: ",")
        }
        .joined(separator: "\n")
    }
}
