import Foundation
import CoreData

enum PlatformStoreHelpers {
    static func scopeItems(_ items: [InventoryItemEntity], workspaceID: UUID?) -> [InventoryItemEntity] {
        items.filter { $0.isInWorkspace(workspaceID) }
    }

    static func allItemsForBackup(from dataController: InventoryDataController) -> [InventoryItemEntity] {
        let request: NSFetchRequest<InventoryItemEntity> = InventoryItemEntity.fetchRequest()
        return (try? dataController.container.viewContext.fetch(request)) ?? []
    }

    static func guardBackupKey(prefix: String, workspaceKey: String, reasonToken: String) -> String {
        "\(prefix)\(workspaceKey).\(reasonToken)"
    }

    static func normalizedGuardBackupToken(_ reason: String) -> String {
        let normalized = reason
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "general" : normalized
    }

    static func confidenceTier(for score: Int) -> InventoryConfidenceTier {
        switch score {
        case 85...:
            return .strong
        case 70...84:
            return .watch
        case 50...69:
            return .weak
        default:
            return .critical
        }
    }

    static func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    static func normalizedBarcode(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    static func csvValue(_ key: String, row: [String], indexByField: [String: Int]) -> String {
        guard let index = indexByField[key], row.indices.contains(index) else {
            return ""
        }
        return row[index]
    }

    static func int64FromString(_ value: String) -> Int64 {
        Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func doubleFromString(_ value: String) -> Double {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func boolFromString(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "true" || normalized == "yes"
    }

    static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for rawLine in rawLines {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            rows.append(parseCSVRow(line))
        }
        return rows
    }

    static func parseCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var isQuoted = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let next = line.index(after: index)
                if isQuoted && next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                }
                isQuoted.toggle()
                index = next
                continue
            }

            if char == "," && !isQuoted {
                result.append(current)
                current = ""
                index = line.index(after: index)
                continue
            }

            current.append(char)
            index = line.index(after: index)
        }

        result.append(current)
        return result
    }
}
