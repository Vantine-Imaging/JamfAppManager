// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers

/// Plain-text CSV wrapper for fileExporter.
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .plainText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// One table row: the list summary plus lazily loaded record info.
struct AppRow: Identifiable {
    let summary: AppSummary
    let info: RowInfo?
    let edited: Bool

    var id: Int { summary.id }
    var name: String { summary.listTitle }
    var bundleID: String { summary.bundleID ?? info?.bundleID ?? "" }
    var version: String { summary.version ?? info?.version ?? "" }
    var category: String { info?.categoryName ?? "" }
    var scope: String { info?.scopeSummary ?? "" }

    /// AppScoper-style short label for the long Jamf deployment strings.
    var deployment: String {
        guard let type = info?.deploymentType, !type.isEmpty else { return "" }
        return type.localizedCaseInsensitiveContains("self service") ? "Self Service" : "Auto Install"
    }

    var vppText: String {
        guard let total = info?.vppTotal else { return info == nil ? "" : "—" }
        return "\(info?.vppUsed ?? 0)/\(total)"
    }

    var vppUsedSort: Int { info?.vppUsed ?? -1 }
}

/// Searchable, sortable, multi-selectable table of one catalog's apps with
/// user-selectable columns. Selecting one app opens its detail; selecting
/// several enables template application. CSV import/export lives here too.
struct AppListView: View {
    let client: JamfClient
    let catalog: AppCatalog
    @Binding var selection: Set<Int>
    var onBatchRequest: (BatchRequest) -> Void = { _ in }

    @Environment(TemplateStore.self) private var templateStore
    @Environment(RowInfoStore.self) private var rowInfoStore
    @Environment(RecordStore.self) private var recordStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PaneLayout.storageKey) private var paneLayoutRaw = PaneLayout.right.rawValue
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\AppRow.name)]
    @State private var columnCustomization = Self.loadColumnCustomization()

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingReview = false
    @State private var exportDocument: CSVDocument?
    @State private var isBuildingExport = false
    @State private var csvAlertMessage: String?

    private var apps: [AppSummary] {
        recordStore.list(for: catalog) ?? []
    }

    private var filteredApps: [AppSummary] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter {
            $0.listTitle.localizedCaseInsensitiveContains(searchText)
                || ($0.bundleID?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var rows: [AppRow] {
        filteredApps.map { summary in
            AppRow(
                summary: summary,
                info: rowInfoStore.info(for: summary, catalog: catalog),
                edited: recordStore.hasUnsavedChanges(catalog: catalog, id: summary.id)
            )
        }
        .sorted(using: sortOrder)
    }

    private var catalogTemplates: [SettingsTemplate] {
        templateStore.templates(for: catalog)
    }

    private var editedApps: [RecordStore.EditedApp] {
        recordStore.editedApps(catalog: catalog)
    }

    private var sortedSelection: [AppSummary] {
        apps.filter { selection.contains($0.id) }
            .sorted { $0.listTitle.localizedCaseInsensitiveCompare($1.listTitle) == .orderedAscending }
    }

    var body: some View {
        Group {
            if isLoading, apps.isEmpty {
                ProgressView("Loading \(catalog.title)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Apps", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load(force: true) } }
                }
            } else {
                table
            }
        }
        .navigationTitle(catalog.title)
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, prompt: "Name or bundle ID")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingReview) {
            MultiReviewSheet(client: client, catalog: catalog)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            if case .success(let url) = result {
                Task { await importCSV(from: url) }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "\(catalog.title) Settings"
        ) { result in
            if case .failure(let error) = result {
                csvAlertMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .alert("CSV", isPresented: Binding(
            get: { csvAlertMessage != nil },
            set: { if !$0 { csvAlertMessage = nil } }
        )) {
            Button("OK") { csvAlertMessage = nil }
        } message: {
            Text(csvAlertMessage ?? "")
        }
        .task { await load(force: false) }
        .onChange(of: columnCustomization) {
            Self.saveColumnCustomization(columnCustomization)
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("App", value: \.name) { row in
                HStack(spacing: 8) {
                    AsyncImage(url: row.info?.iconURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: catalog.systemImage)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, height: 20)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(row.name)
                    if row.edited {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                            .help("Unsaved edits")
                    }
                }
                .task {
                    await rowInfoStore.load(app: row.summary, catalog: catalog, client: client)
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Jamf ID", value: \.id) { row in
                Text(String(row.id)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)
            .customizationID("jamfID")

            TableColumn("Bundle ID", value: \.bundleID) { row in
                Text(row.bundleID).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 200)
            .customizationID("bundleID")

            TableColumn("Category", value: \.category) { row in
                Text(row.category.isEmpty ? (row.info == nil ? "" : "None") : row.category)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 130)
            .customizationID("category")

            TableColumn("Deployment", value: \.deployment) { row in
                if !row.deployment.isEmpty {
                    Text(row.deployment)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            (row.deployment == "Self Service" ? Color.orange : Color.green).opacity(0.18),
                            in: Capsule()
                        )
                        .foregroundStyle(row.deployment == "Self Service" ? .orange : .green)
                }
            }
            .width(min: 90, ideal: 110)
            .customizationID("deployment")

            TableColumn("Version", value: \.version) { row in
                Text(row.version).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            .customizationID("version")

            TableColumn("VPP", value: \.vppUsedSort) { row in
                Text(row.vppText).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
            .customizationID("vpp")

            TableColumn("Scope", value: \.scope) { row in
                if let info = row.info {
                    Text(info.scopeSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(scopeColor(info.scopeKind))
                }
            }
            .width(min: 90, ideal: 140)
            .customizationID("scope")
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            if let id = ids.first, let app = apps.first(where: { $0.id == id }) {
                Button("Open in New Window") { popOut(app) }
                Divider()
                Button("Copy Name") { copy(app.listTitle) }
                if let bundleID = app.bundleID ?? rowInfoStore.info(for: app, catalog: catalog)?.bundleID {
                    Button("Copy Bundle ID") { copy(bundleID) }
                }
                Button("Copy Jamf ID") { copy(String(app.id)) }
            }
        } primaryAction: { ids in
            // Double-click pops the app out, Outlook-style.
            for id in ids {
                if let app = apps.first(where: { $0.id == id }) {
                    popOut(app)
                }
            }
        }
    }

    private func popOut(_ app: AppSummary) {
        openWindow(value: AppDetailTarget(catalogRaw: catalog.rawValue, appID: app.id, title: app.listTitle))
    }

    private func scopeColor(_ kind: RowInfo.ScopeKind) -> Color {
        switch kind {
        case .none: .red
        case .all: .green
        case .some: .primary.opacity(0.75)
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: - Column visibility

    private static let optionalColumns: [(id: String, title: String)] = [
        ("jamfID", "Jamf ID"),
        ("bundleID", "Bundle ID"),
        ("category", "Category"),
        ("deployment", "Deployment"),
        ("version", "Version"),
        ("vpp", "VPP"),
        ("scope", "Scope"),
    ]

    private static let customizationKey = "appList.columns"

    private static func loadColumnCustomization() -> TableColumnCustomization<AppRow> {
        if let data = UserDefaults.standard.data(forKey: customizationKey),
           let saved = try? JSONDecoder().decode(TableColumnCustomization<AppRow>.self, from: data) {
            return saved
        }
        var fresh = TableColumnCustomization<AppRow>()
        // Bundle ID off by default — names carry the row; it's one toggle away.
        fresh[visibility: "bundleID"] = .hidden
        return fresh
    }

    private static func saveColumnCustomization(_ customization: TableColumnCustomization<AppRow>) {
        if let data = try? JSONEncoder().encode(customization) {
            UserDefaults.standard.set(data, forKey: customizationKey)
        }
    }

    private func columnBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { columnCustomization[visibility: id] != .hidden },
            set: { visible in columnCustomization[visibility: id] = visible ? .visible : .hidden }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !editedApps.isEmpty {
            ToolbarItem(placement: .confirmationAction) {
                Button("Review Changes (\(editedApps.count) app\(editedApps.count == 1 ? "" : "s"))") {
                    showingReview = true
                }
                .buttonStyle(.glassProminent)
                .help("Review and push the unsaved edits across this catalog")
            }
        }
        if !selection.isEmpty, !catalogTemplates.isEmpty {
            ToolbarItem {
                Menu {
                    ForEach(catalogTemplates) { template in
                        Button(template.name) {
                            onBatchRequest(.applying(template, to: sortedSelection))
                        }
                    }
                } label: {
                    Label("Apply Template", systemImage: "square.on.square.dashed")
                        .labelStyle(.titleAndIcon)
                }
                .help("Apply a settings template to the \(selection.count) selected app\(selection.count == 1 ? "" : "s")")
            }
        }
        ToolbarItem {
            Menu {
                Picker("Layout", selection: $paneLayoutRaw) {
                    ForEach(PaneLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.symbol)
                            .tag(layout.rawValue)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Section("Columns") {
                    ForEach(Self.optionalColumns, id: \.id) { column in
                        Toggle(column.title, isOn: columnBinding(column.id))
                    }
                }
            } label: {
                Label("View", systemImage: "slider.horizontal.3")
                    .labelStyle(.titleAndIcon)
            }
            .help("Layout and column options")
        }
        ToolbarItem {
            Menu {
                Button("Import CSV…") { showingImporter = true }
                Button(selection.isEmpty
                       ? "Export All to CSV…"
                       : "Export \(selection.count) Selected to CSV…") {
                    Task { await buildExport() }
                }
                .disabled(isBuildingExport || apps.isEmpty)
            } label: {
                if isBuildingExport {
                    ProgressView().controlSize(.small)
                } else {
                    Label("CSV", systemImage: "tablecells")
                        .labelStyle(.titleAndIcon)
                }
            }
            .help("Bulk-edit via CSV: export current settings, edit, and re-import")
        }
        ToolbarItem {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await load(force: true) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isLoading)
        }
    }

    private var subtitle: String {
        selection.count > 1
            ? "\(selection.count) of \(apps.count) selected"
            : "\(apps.count) apps"
    }

    private func load(force: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            try await recordStore.loadList(catalog: catalog, client: client, force: force)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - CSV

    private func importCSV(from url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            csvAlertMessage = "Couldn’t read the file: \(error.localizedDescription)"
            return
        }

        let headers = CSV.parse(text).first ?? []
        var context = CSVBatch.ImportContext()
        if CSVBatch.needsScopeOptions(headers: headers, catalog: catalog) {
            context.scopeOptions = try? await client.fetchScopeOptions(catalog: catalog)
            if context.scopeOptions == nil {
                csvAlertMessage = "The file has scope columns but the server’s group lists couldn’t be loaded."
                return
            }
        }
        if CSVBatch.needsCategories(headers: headers, catalog: catalog) {
            context.categories = (try? await client.fetchCategories()) ?? []
        }
        if CSVBatch.needsVPPAccounts(headers: headers, catalog: catalog) {
            context.vppAccounts = (try? await client.fetchVPPAccounts()) ?? []
        }

        let result = CSVBatch.buildItems(
            csvText: text, catalog: catalog, apps: apps, context: context
        )
        guard !result.items.isEmpty else {
            csvAlertMessage = result.fileErrors.joined(separator: "\n")
            return
        }
        if !result.fileErrors.isEmpty {
            csvAlertMessage = result.fileErrors.joined(separator: "\n")
        }
        onBatchRequest(BatchRequest(
            title: "CSV Import (\(url.lastPathComponent))",
            catalog: catalog,
            items: result.items
        ))
    }

    private func buildExport() async {
        isBuildingExport = true
        defer { isBuildingExport = false }

        let targets = selection.isEmpty ? filteredApps : sortedSelection
        let vppAccounts = (try? await client.fetchVPPAccounts()) ?? []
        var csvRows: [[String]] = [CSVBatch.exportHeaders(for: catalog)]
        var failures: [String] = []

        let batchSize = 4
        var index = 0
        while index < targets.count {
            let end = min(index + batchSize, targets.count)
            let jobs = (index..<end).map { i -> (AppSummary, Task<[String]?, Never>) in
                let summary = targets[i]
                return (summary, Task {
                    do {
                        let editor: AppEditor
                        switch catalog {
                        case .mobileDevice:
                            editor = AppEditor(mobile: try await client.fetchMobileDeviceAppDetail(id: summary.id))
                        case .mac:
                            editor = AppEditor(mac: try await client.fetchMacAppDetail(id: summary.id))
                        }
                        return CSVBatch.exportRow(summary: summary, editor: editor, catalog: catalog, vppAccounts: vppAccounts)
                    } catch {
                        return nil
                    }
                })
            }
            for (summary, job) in jobs {
                if let row = await job.value {
                    csvRows.append(row)
                } else {
                    failures.append(summary.listTitle)
                }
            }
            index = end
        }

        exportDocument = CSVDocument(text: CSV.encode(csvRows))
        showingExporter = true
        if !failures.isEmpty {
            csvAlertMessage = "Couldn’t fetch: \(failures.joined(separator: ", "))"
        }
    }
}
