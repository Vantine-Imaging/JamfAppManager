// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

/// Session-wide cache of catalog lists, loaded records, and — critically —
/// their live editors. Because editors live here rather than in the detail
/// view, unsaved edits survive switching between apps, and reopening an app
/// is instant. Explicit Refresh actions pass `force: true` to re-fetch.
@MainActor
@Observable
final class RecordStore {
    struct Entry {
        var detail: AppRecordDetail
        var editor: AppEditor
    }

    private(set) var lists: [AppCatalog: [AppSummary]] = [:]
    private var entries: [String: Entry] = [:]
    private(set) var scopeOptions: [AppCatalog: ScopeOptions] = [:]
    private(set) var categories: [NamedID]?
    private(set) var vppAccounts: [NamedID]?

    private func key(_ catalog: AppCatalog, _ id: Int) -> String {
        "\(catalog.rawValue)-\(id)"
    }

    // MARK: - Catalog lists

    func list(for catalog: AppCatalog) -> [AppSummary]? {
        lists[catalog]
    }

    @discardableResult
    func loadList(catalog: AppCatalog, client: JamfClient, force: Bool = false) async throws -> [AppSummary] {
        if !force, let cached = lists[catalog] { return cached }
        let apps = try await client.fetchAppList(catalog: catalog)
        lists[catalog] = apps
        return apps
    }

    // MARK: - Records + editors

    func entry(catalog: AppCatalog, id: Int) -> Entry? {
        entries[key(catalog, id)]
    }

    @discardableResult
    func loadEntry(catalog: AppCatalog, id: Int, client: JamfClient, force: Bool = false) async throws -> Entry {
        let cacheKey = key(catalog, id)
        if !force, let cached = entries[cacheKey] { return cached }
        let entry: Entry
        switch catalog {
        case .mobileDevice:
            let detail = try await client.fetchMobileDeviceAppDetail(id: id)
            entry = Entry(detail: .mobileDevice(detail), editor: AppEditor(mobile: detail))
        case .mac:
            let detail = try await client.fetchMacAppDetail(id: id)
            entry = Entry(detail: .mac(detail), editor: AppEditor(mac: detail))
        }
        entries[cacheKey] = entry
        return entry
    }

    /// Drops a cached record (used after a confirmed server write, so the
    /// next open re-fetches the server's truth).
    func invalidate(catalog: AppCatalog, id: Int) {
        entries[key(catalog, id)] = nil
    }

    func hasUnsavedChanges(catalog: AppCatalog, id: Int) -> Bool {
        entries[key(catalog, id)]?.editor.hasChanges ?? false
    }

    // MARK: - Picker source lists

    func loadPickers(catalog: AppCatalog, client: JamfClient) async {
        if scopeOptions[catalog] == nil {
            scopeOptions[catalog] = try? await client.fetchScopeOptions(catalog: catalog)
        }
        if categories == nil {
            categories = (try? await client.fetchCategories()) ?? []
        }
        if vppAccounts == nil {
            vppAccounts = (try? await client.fetchVPPAccounts()) ?? []
        }
    }

    struct EditedApp: Identifiable {
        let id: Int
        let title: String
        let editor: AppEditor
    }

    /// Every app in the catalog whose cached editor has unsaved changes —
    /// the working set for the catalog-wide review sheet.
    func editedApps(catalog: AppCatalog) -> [EditedApp] {
        let prefix = "\(catalog.rawValue)-"
        return entries.compactMap { key, entry -> EditedApp? in
            guard key.hasPrefix(prefix), entry.editor.hasChanges else { return nil }
            let id = entry.editor.appID
            let title = lists[catalog]?.first { $0.id == id }?.listTitle
                ?? (entry.editor.displayName.isEmpty ? "ID \(id)" : entry.editor.displayName)
            return EditedApp(id: id, title: title, editor: entry.editor)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Called on disconnect/server switch so nothing bleeds between instances.
    func reset() {
        lists = [:]
        entries = [:]
        scopeOptions = [:]
        categories = nil
        vppAccounts = nil
    }
}