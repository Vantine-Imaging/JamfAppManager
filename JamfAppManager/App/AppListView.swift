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

/// Searchable, multi-selectable listing of one catalog's apps. Selecting one
/// app opens its detail; selecting several enables template application.
/// CSV import/export lives here too — both feed the same batch review sheet.
struct AppListView: View {
    let client: JamfClient
    let catalog: AppCatalog
    @Binding var selection: Set<AppSummary>
    var onBatchRequest: (BatchRequest) -> Void = { _ in }

    @Environment(TemplateStore.self) private var templateStore
    @Environment(IconStore.self) private var iconStore
    @Environment(RecordStore.self) private var recordStore
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    @State private var showingImporter = false
    @State private var showingExporter = false
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

    private var catalogTemplates: [SettingsTemplate] {
        templateStore.templates(for: catalog)
    }

    private var sortedSelection: [AppSummary] {
        selection.sorted {
            $0.listTitle.localizedCaseInsensitiveCompare($1.listTitle) == .orderedAscending
        }
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
                List(filteredApps, id: \.self, selection: $selection) { app in
                    HStack(spacing: 8) {
                        AsyncImage(url: iconStore.url(for: app, catalog: catalog)) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Image(systemName: catalog.systemImage)
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .frame(width: 24, height: 24)
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.listTitle)
                            if let bundleID = app.bundleID, !bundleID.isEmpty {
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if recordStore.hasUnsavedChanges(catalog: catalog, id: app.id) {
                            Spacer()
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(.orange)
                                .help("Unsaved edits")
                        }
                    }
                    .tag(app)
                    .task {
                        await iconStore.load(app: app, catalog: catalog, client: client)
                    }
                    .contextMenu {
                        Button("Copy Name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(app.listTitle, forType: .string)
                        }
                        if let bundleID = app.bundleID, !bundleID.isEmpty {
                            Button("Copy Bundle ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(bundleID, forType: .string)
                            }
                        }
                        Button("Copy Jamf ID") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(String(app.id), forType: .string)
                        }
                    }
                }
                .overlay {
                    if filteredApps.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .navigationTitle(catalog.title)
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, prompt: "Name or bundle ID")
        .toolbar {
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
        ) { _ in }
        .alert("CSV", isPresented: Binding(
            get: { csvAlertMessage != nil },
            set: { if !$0 { csvAlertMessage = nil } }
        )) {
            Button("OK") { csvAlertMessage = nil }
        } message: {
            Text(csvAlertMessage ?? "")
        }
        .task { await load(force: false) }
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
        var rows: [[String]] = [CSVBatch.exportHeaders(for: catalog)]
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
                    rows.append(row)
                } else {
                    failures.append(summary.listTitle)
                }
            }
            index = end
        }

        exportDocument = CSVDocument(text: CSV.encode(rows))
        showingExporter = true
        if !failures.isEmpty {
            csvAlertMessage = "Couldn’t fetch: \(failures.joined(separator: ", "))"
        }
    }
}
