// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Translates between CSV files and batch items.
///
/// Import format: a header row, then one row per app. Identifier columns
/// (`id`, `bundle_id`, or `name` — at least one required) locate the app;
/// every other recognized column is a setting. Empty cells leave that field
/// untouched, so sparse sheets are safe. Scope-list cells are
/// semicolon-separated names or #ids ("All iPads; #22").
enum CSVBatch {
    // MARK: - Header resolution

    private static func normalize(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func fieldKey(forHeader header: String, catalog: AppCatalog) -> FieldKey? {
        let normalized = normalize(header)
        return FieldKey.applicableKeys(for: catalog).first {
            normalize($0.rawValue) == normalized || normalize($0.label) == normalized
        }
    }

    enum IdentifierColumn {
        case id, bundleID, name
    }

    static func identifierColumn(forHeader header: String) -> IdentifierColumn? {
        switch normalize(header) {
        case "id", "appid": .id
        case "bundleid", "bundleidentifier": .bundleID
        case "name", "appname": .name
        default: nil
        }
    }

    /// Server lists needed to resolve names in CSV cells.
    struct ImportContext {
        var scopeOptions: ScopeOptions?
        var categories: [NamedID] = []
        var vppAccounts: [NamedID] = []
    }

    /// True when the CSV references scope fields, meaning import needs the
    /// server's group/building/department lists to resolve names.
    static func needsScopeOptions(headers: [String], catalog: AppCatalog) -> Bool {
        headers.contains { fieldKey(forHeader: $0, catalog: catalog)?.isNamedIDList == true }
    }

    static func needsCategories(headers: [String], catalog: AppCatalog) -> Bool {
        headers.contains {
            let key = fieldKey(forHeader: $0, catalog: catalog)
            return key == .category || key == .ssCategories
        }
    }

    static func needsVPPAccounts(headers: [String], catalog: AppCatalog) -> Bool {
        headers.contains { fieldKey(forHeader: $0, catalog: catalog) == .vppLocation }
    }

    // MARK: - Value parsing

    struct ParseFailure: Error {
        var message: String
    }

    /// Resolves one "Name", "#id", or bare-integer token against a server
    /// list. Unknown ids pass through; unknown names fail.
    private static func resolveToken(
        _ token: String, in options: [NamedID], label: String
    ) -> Result<NamedID, ParseFailure> {
        if let id = Int(token.hasPrefix("#") ? String(token.dropFirst()) : token) {
            return .success(options.first { $0.id == id } ?? NamedID(id: id, name: nil))
        }
        if let match = options.first(where: {
            ($0.name ?? "").compare(token, options: .caseInsensitive) == .orderedSame
        }) {
            return .success(match)
        }
        return .failure(ParseFailure(message: "Unknown \(label) entry “\(token)”"))
    }

    static func parseValue(
        _ raw: String, key: FieldKey, context: ImportContext
    ) -> Result<TemplateValue, ParseFailure> {
        if key.isBool {
            switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "1": return .success(.bool(true))
            case "false", "no", "0": return .success(.bool(false))
            default: return .failure(ParseFailure(message: "“\(raw)” is not a boolean (use true/false)"))
            }
        }
        if key.isNamedID {
            let token = raw.trimmingCharacters(in: .whitespaces)
            if token.lowercased() == "none" {
                return .success(.namedID(NamedID(id: -1, name: "None")))
            }
            let options = key == .category ? context.categories : context.vppAccounts
            return resolveToken(token, in: options, label: key.label.lowercased())
                .map { .namedID($0) }
        }
        if key == .ssCategories {
            // "Applications; Maintenance*" — a trailing * marks Feature In.
            var items: [SelfServiceCategory] = []
            for part in raw.split(separator: ";") {
                var token = part.trimmingCharacters(in: .whitespaces)
                guard !token.isEmpty else { continue }
                let featured = token.hasSuffix("*")
                if featured { token = String(token.dropLast()).trimmingCharacters(in: .whitespaces) }
                switch resolveToken(token, in: context.categories, label: "self service category") {
                case .success(let match):
                    items.append(SelfServiceCategory(
                        id: match.id, name: match.name, displayIn: true, featureIn: featured
                    ))
                case .failure(let failure):
                    return .failure(failure)
                }
            }
            return .success(.ssCategories(items))
        }
        if key.isNamedIDList {
            let options: [NamedID] = {
                switch key {
                case .scopeGroups, .scopeExcludedGroups: context.scopeOptions?.groups ?? []
                case .scopeBuildings, .scopeExcludedBuildings: context.scopeOptions?.buildings ?? []
                case .scopeDepartments, .scopeExcludedDepartments: context.scopeOptions?.departments ?? []
                default: []
                }
            }()
            var items: [NamedID] = []
            for part in raw.split(separator: ";") {
                let token = part.trimmingCharacters(in: .whitespaces)
                guard !token.isEmpty else { continue }
                switch resolveToken(token, in: options, label: key.label.lowercased()) {
                case .success(let match): items.append(match)
                case .failure(let failure): return .failure(failure)
                }
            }
            return .success(.namedIDs(items))
        }
        return .success(.string(raw))
    }

    // MARK: - Import

    struct ImportResult {
        var items: [BatchItem] = []
        /// Fatal problems with the file itself (bad header, no identifiers).
        var fileErrors: [String] = []
    }

    static func buildItems(
        csvText: String,
        catalog: AppCatalog,
        apps: [AppSummary],
        context: ImportContext
    ) -> ImportResult {
        var result = ImportResult()
        let rows = CSV.parse(csvText)
        guard rows.count >= 2 else {
            result.fileErrors.append("The file needs a header row and at least one data row.")
            return result
        }

        let headers = rows[0]
        var identifierColumns: [(Int, IdentifierColumn)] = []
        var fieldColumns: [(Int, FieldKey)] = []
        var unknownHeaders: [String] = []
        for (index, header) in headers.enumerated() {
            if let identifier = identifierColumn(forHeader: header) {
                identifierColumns.append((index, identifier))
            } else if let key = fieldKey(forHeader: header, catalog: catalog) {
                fieldColumns.append((index, key))
            } else if !header.trimmingCharacters(in: .whitespaces).isEmpty {
                unknownHeaders.append(header)
            }
        }
        guard !identifierColumns.isEmpty else {
            result.fileErrors.append("No identifier column found — include an “id”, “bundle_id”, or “name” column.")
            return result
        }
        guard !fieldColumns.isEmpty else {
            result.fileErrors.append("No setting columns recognized. Valid columns: \(FieldKey.applicableKeys(for: catalog).map(\.rawValue).joined(separator: ", "))")
            return result
        }
        if !unknownHeaders.isEmpty {
            result.fileErrors.append("Ignored unrecognized column\(unknownHeaders.count == 1 ? "" : "s"): \(unknownHeaders.joined(separator: ", "))")
        }

        for (rowNumber, row) in rows.dropFirst().enumerated() {
            let lineLabel = "Row \(rowNumber + 2)"
            // Raw cell content: string values (descriptions!) must round-trip
            // untrimmed. Trimming happens only for matching and typed parsing.
            func cell(_ index: Int) -> String {
                index < row.count ? row[index] : ""
            }
            func trimmedCell(_ index: Int) -> String {
                cell(index).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Locate the app by the first identifier column with a value.
            var matched: AppSummary?
            var identifierText = ""
            for (index, kind) in identifierColumns {
                let value = trimmedCell(index)
                guard !value.isEmpty else { continue }
                identifierText = value
                switch kind {
                case .id:
                    if let id = Int(value) { matched = apps.first { $0.id == id } }
                case .bundleID:
                    matched = apps.first { $0.bundleID?.compare(value, options: .caseInsensitive) == .orderedSame }
                case .name:
                    matched = apps.first {
                        $0.listTitle.compare(value, options: .caseInsensitive) == .orderedSame
                            || $0.name.compare(value, options: .caseInsensitive) == .orderedSame
                    }
                }
                if matched != nil { break }
            }

            let placeholder = AppSummary(
                id: -(rowNumber + 2),
                name: identifierText.isEmpty ? lineLabel : "\(lineLabel): \(identifierText)",
                displayName: nil, bundleID: nil, version: nil
            )

            guard let summary = matched else {
                result.items.append(BatchItem(
                    summary: placeholder, fields: [:],
                    error: identifierText.isEmpty
                        ? "No identifier value in this row"
                        : "No \(catalog.title.dropLast()) matches “\(identifierText)”"
                ))
                continue
            }

            var fields: [FieldKey: TemplateValue] = [:]
            var rowError: String?
            for (index, key) in fieldColumns {
                guard !trimmedCell(index).isEmpty else { continue } // empty cell = leave untouched
                let needsTrim = key.isBool || key.isNamedIDList || key.isNamedID || key == .ssCategories
                let value = needsTrim ? trimmedCell(index) : cell(index)
                switch parseValue(value, key: key, context: context) {
                case .success(let parsed): fields[key] = parsed
                case .failure(let failure):
                    rowError = "\(key.label): \(failure.message)"
                }
                if rowError != nil { break }
            }

            if let rowError {
                result.items.append(BatchItem(summary: summary, fields: [:], error: rowError))
            } else if fields.isEmpty {
                result.items.append(BatchItem(summary: summary, fields: [:], error: "No values in this row"))
            } else {
                result.items.append(BatchItem(summary: summary, fields: fields, error: nil))
            }
        }
        return result
    }

    // MARK: - Export

    static func exportHeaders(for catalog: AppCatalog) -> [String] {
        ["id", "bundle_id", "name"] + FieldKey.applicableKeys(for: catalog).map(\.rawValue)
    }

    @MainActor
    static func exportRow(
        summary: AppSummary, editor: AppEditor, catalog: AppCatalog, vppAccounts: [NamedID] = []
    ) -> [String] {
        var row = [String(summary.id), summary.bundleID ?? "", summary.listTitle]
        for key in FieldKey.applicableKeys(for: catalog) {
            var value = editor.value(for: key)
            // The record carries only the VPP account id; resolve its name so
            // the exported cell is human-readable.
            if key == .vppLocation, case .namedID(let item) = value, item.name == nil,
               let match = vppAccounts.first(where: { $0.id == item.id }) {
                value = .namedID(match)
            }
            row.append(csvString(value))
        }
        return row
    }

    static func csvString(_ value: TemplateValue) -> String {
        switch value {
        case .bool(let flag): flag ? "true" : "false"
        case .string(let string): string
        case .namedIDs(let items):
            items.map { $0.name ?? "#\($0.id)" }.joined(separator: "; ")
        case .namedID(let item):
            item.id <= 0 ? "None" : (item.name ?? "#\(item.id)")
        case .ssCategories(let items):
            items.map { ($0.name ?? "#\($0.id)") + ($0.featureIn == true ? "*" : "") }
                .joined(separator: "; ")
        }
    }
}