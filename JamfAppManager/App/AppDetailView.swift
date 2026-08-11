import SwiftUI

/// One app's settings across the Jamf tabs. Records and their editors are
/// cached in RecordStore, so unsaved edits survive switching between apps
/// and reopening is instant; Refresh/Discard force a re-fetch. Nothing is
/// written until the user reviews the diff and confirms.
struct AppDetailView: View {
    let client: JamfClient
    let catalog: AppCatalog
    let summary: AppSummary

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case scope = "Scope"
        case selfService = "Self Service"
        case managedDistribution = "Managed Distribution"
        case appConfiguration = "App Configuration"

        var id: String { rawValue }

        /// App Configuration doesn't exist for Mac App Store apps anywhere in
        /// Jamf (web UI included) — managed settings on macOS ship as
        /// configuration profiles instead. Don't show a dead tab.
        static func available(for catalog: AppCatalog) -> [Tab] {
            catalog == .mac
                ? [.general, .scope, .selfService, .managedDistribution]
                : allCases
        }
    }

    @Environment(TemplateStore.self) private var templateStore
    @Environment(RecordStore.self) private var recordStore
    @State private var entry: RecordStore.Entry?
    @State private var errorMessage: String?
    @State private var selectedTab: Tab = .general
    @State private var showingReview = false
    @State private var showingSaveTemplate = false
    @State private var templateName = ""

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load App", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load(force: true) } }
                }
            } else if let entry {
                let editor = entry.editor
                VStack(spacing: 0) {
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(Tab.available(for: catalog)) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding()

                    tabContent(detail: entry.detail, editor: editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .toolbar {
                    if editor.hasChanges {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Review Changes (\(editor.changes.count))") {
                                showingReview = true
                            }
                            .buttonStyle(.glassProminent)
                        }
                        ToolbarItem {
                            Button {
                                Task { await load(force: true) }
                            } label: {
                                Label("Discard", systemImage: "arrow.uturn.backward")
                                    .labelStyle(.titleAndIcon)
                            }
                            .help("Discard unsaved edits and reload from the server")
                        }
                    } else {
                        ToolbarItem {
                            Button {
                                Task { await load(force: true) }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .labelStyle(.titleAndIcon)
                            }
                            .help("Re-fetch this app from the server")
                        }
                    }
                    ToolbarItem {
                        Menu {
                            Button("Save Settings as Template…", systemImage: "square.on.square.dashed") {
                                templateName = "\(summary.listTitle) Settings"
                                showingSaveTemplate = true
                            }
                            Divider()
                            Link(destination: jamfWebURL) {
                                Label("Open in Jamf Pro", systemImage: "safari")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
                .sheet(isPresented: $showingReview) {
                    ReviewChangesSheet(client: client, editor: editor) {
                        Task {
                            await load(force: true)
                            _ = try? await recordStore.loadList(catalog: catalog, client: client, force: true)
                        }
                    }
                }
                .alert("Save Settings as Template", isPresented: $showingSaveTemplate) {
                    TextField("Template Name", text: $templateName)
                    Button("Save") {
                        templateStore.add(editor.makeTemplate(named: templateName))
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Creates a template from the values currently shown (including unsaved edits). You can trim the included fields in the Templates section.")
                }
            } else {
                ProgressView("Loading \(summary.listTitle)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(summary.listTitle)
        .navigationSubtitle("ID \(summary.id)")
        .task { await load(force: false) }
    }

    @ViewBuilder
    private func tabContent(detail: AppRecordDetail, editor: AppEditor) -> some View {
        switch selectedTab {
        case .general:
            generalTab(detail: detail, editor: editor)
        case .scope:
            scopeTab(detail: detail, editor: editor)
        case .selfService:
            selfServiceTab(editor: editor)
        case .managedDistribution:
            managedDistributionTab(detail: detail, editor: editor)
        case .appConfiguration:
            appConfigurationTab(editor: editor)
        }
    }

    // MARK: - General

    @ViewBuilder
    private func generalTab(detail: AppRecordDetail, editor: AppEditor) -> some View {
        @Bindable var editor = editor
        Form {
            switch detail {
            case .mobileDevice(let app):
                let general = app.general
                Section("Identity") {
                    TextField("Display Name", text: $editor.displayName)
                    TextField("Description", text: $editor.appDescription, axis: .vertical)
                        .lineLimit(1...4)
                    LabeledContent("Bundle ID", value: general.bundleID ?? "—")
                    LabeledContent("Version", value: general.version ?? "—")
                    categoryPicker(editor: editor)
                    LabeledContent("Site", value: general.site?.name ?? "—")
                }
                Section("Deployment") {
                    deploymentTypePicker(editor: $editor)
                    Toggle("Deploy Automatically", isOn: $editor.deployAutomatically)
                    Toggle("Deploy as Managed App", isOn: $editor.deployAsManagedApp)
                    Toggle("Remove with MDM Profile", isOn: $editor.removeAppWhenMDMProfileIsRemoved)
                    Toggle("Prevent Backup of App Data", isOn: $editor.preventBackupOfAppData)
                    Toggle("Allow User to Delete", isOn: $editor.allowUserToDelete)
                    Toggle("Require Network Tethered", isOn: $editor.requireNetworkTethered)
                    Toggle("Keep App Updated on Devices", isOn: $editor.keepAppUpdatedOnDevices)
                    Toggle("Keep Description & Icon Up to Date", isOn: $editor.keepDescriptionAndIconUpToDate)
                    Toggle("Make Available After Install", isOn: $editor.makeAvailableAfterInstall)
                    Toggle("Take Over Management", isOn: $editor.takeOverManagement)
                }
            case .mac(let app):
                let general = app.general
                Section("Identity") {
                    TextField("Display Name", text: $editor.displayName)
                    LabeledContent("Bundle ID", value: general.bundleID ?? "—")
                    LabeledContent("Version", value: general.version ?? "—")
                    categoryPicker(editor: editor)
                    LabeledContent("Site", value: general.site?.name ?? "—")
                    LabeledContent("App Store URL", value: general.url ?? "—")
                    boolRow("Free", general.isFree)
                }
                Section {
                    deploymentTypePicker(editor: $editor)
                } header: {
                    Text("Deployment")
                } footer: {
                    Text("Not shown: Enabled, “Schedule Jamf Pro to check the App Store for updates” (incl. country and sync time), “Automatically force app updates”, and Force Update. Jamf stores these outside both public APIs (verified against this server), so they can only be changed in the web UI.")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func deploymentTypePicker(editor: Bindable<AppEditor>) -> some View {
        // The server may report values outside the two standard options
        // (e.g. legacy types); keep whatever it sent as a valid choice.
        let options = AppEditor.deploymentTypeOptions.contains(editor.wrappedValue.deploymentType)
            ? AppEditor.deploymentTypeOptions
            : [editor.wrappedValue.deploymentType] + AppEditor.deploymentTypeOptions
        Picker("Deployment Type", selection: editor.deploymentType) {
            ForEach(options, id: \.self) { option in
                Text(option.isEmpty ? "—" : option).tag(option)
            }
        }
    }

    // MARK: - Scope

    @ViewBuilder
    private func scopeTab(detail: AppRecordDetail, editor: AppEditor) -> some View {
        @Bindable var editor = editor
        let groupsLabel = catalog == .mobileDevice ? "Device Groups" : "Computer Groups"
        let allLabel = catalog == .mobileDevice ? "All Mobile Devices" : "All Computers"
        let options = recordStore.scopeOptions[catalog] ?? ScopeOptions()

        Form {
            Section("Targets") {
                Toggle(allLabel, isOn: $editor.scopeAllTargets)
                NamedIDPicker(title: groupsLabel, selection: $editor.scopeGroups,
                              options: options.groups, disabled: editor.scopeAllTargets)
                NamedIDPicker(title: "Buildings", selection: $editor.scopeBuildings,
                              options: options.buildings, disabled: editor.scopeAllTargets)
                NamedIDPicker(title: "Departments", selection: $editor.scopeDepartments,
                              options: options.departments, disabled: editor.scopeAllTargets)
                // Individually scoped devices/computers stay read-only —
                // one-off machine scoping isn't a bulk-editing concern.
                namedIDRows("Devices (read-only)", detail.scope?.mobileDevices)
                namedIDRows("Computers (read-only)", detail.scope?.computers)
            }
            Section("Exclusions") {
                NamedIDPicker(title: groupsLabel, selection: $editor.scopeExcludedGroups,
                              options: options.groups)
                NamedIDPicker(title: "Buildings", selection: $editor.scopeExcludedBuildings,
                              options: options.buildings)
                NamedIDPicker(title: "Departments", selection: $editor.scopeExcludedDepartments,
                              options: options.departments)
                namedIDRows("Devices (read-only)", detail.scope?.exclusions?.mobileDevices)
                namedIDRows("Computers (read-only)", detail.scope?.exclusions?.computers)
            }
            if let limitations = detail.scope?.limitations,
               [limitations.users, limitations.userGroups, limitations.networkSegments]
                   .contains(where: { !($0 ?? []).isEmpty }) {
                Section("Limitations (read-only)") {
                    namedIDRows("Users", limitations.users)
                    namedIDRows("User Groups", limitations.userGroups)
                    namedIDRows("Network Segments", limitations.networkSegments)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Managed Distribution

    @ViewBuilder
    private func managedDistributionTab(detail: AppRecordDetail, editor: AppEditor) -> some View {
        @Bindable var editor = editor
        Form {
            Section("Volume Purchasing") {
                Toggle("Assign Device-Based Licenses", isOn: $editor.assignVPPDeviceBasedLicenses)
                vppLocationPicker(editor: editor)
            }
            if let total = detail.vpp?.totalVPPLicenses {
                Section("Licenses") {
                    LabeledContent("Total", value: String(total))
                    LabeledContent("In Use", value: detail.vpp?.usedVPPLicenses.map(String.init) ?? "—")
                    LabeledContent("Remaining", value: detail.vpp?.remainingVPPLicenses.map(String.init) ?? "—")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Pickers backed by server lists

    @ViewBuilder
    private func categoryPicker(editor: AppEditor) -> some View {
        let categories = recordStore.categories ?? []
        let currentID = editor.category?.id ?? -1
        let known = currentID == -1 || categories.contains { $0.id == currentID }
        Picker("Category", selection: Binding(
            get: { editor.category?.id ?? -1 },
            set: { newID in
                editor.category = NamedID(
                    id: newID,
                    name: newID == -1 ? "None" : categories.first { $0.id == newID }?.name
                )
            }
        )) {
            Text("None").tag(-1)
            if !known {
                Text(editor.category?.name ?? "ID \(currentID)").tag(currentID)
            }
            ForEach(categories) { category in
                Text(category.name ?? "ID \(category.id)").tag(category.id)
            }
        }
    }

    @ViewBuilder
    private func vppLocationPicker(editor: AppEditor) -> some View {
        let vppAccounts = recordStore.vppAccounts ?? []
        let currentID = editor.vppAccountID
        let known = currentID <= 0 || vppAccounts.contains { $0.id == currentID }
        Picker("Location", selection: Binding(
            get: { editor.vppAccountID },
            set: { newID in
                editor.vppAccountID = newID
                editor.vppAccountName = vppAccounts.first { $0.id == newID }?.name
            }
        )) {
            if currentID <= 0 {
                Text("None").tag(currentID)
            } else if !known {
                Text("ID \(currentID)").tag(currentID)
            }
            ForEach(vppAccounts) { account in
                Text(account.name ?? "ID \(account.id)").tag(account.id)
            }
        }
    }

    // MARK: - Self Service

    @ViewBuilder
    private func selfServiceTab(editor: AppEditor) -> some View {
        @Bindable var editor = editor
        Form {
            Section("Self Service") {
                TextField("Button Name", text: $editor.ssButtonText)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                    TextEditor(text: $editor.ssDescription)
                        .font(.callout)
                        .frame(minHeight: 80)
                }
                if catalog == .mac {
                    Toggle("Force Users to View Description", isOn: $editor.ssForceViewDescription)
                }
                Toggle("Feature on Main Page", isOn: $editor.ssFeatureOnMainPage)
            }
            Section("Notification") {
                Toggle("Display Notifications", isOn: $editor.ssNotificationEnabled)
                TextField("Subject", text: $editor.ssNotificationSubject)
                TextField("Message", text: $editor.ssNotificationMessage)
            }
            Section("Categories") {
                SelfServiceCategoriesEditor(
                    categories: recordStore.categories ?? [],
                    selection: $editor.ssCategories
                )
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - App Configuration

    @ViewBuilder
    private func appConfigurationTab(editor: AppEditor) -> some View {
        @Bindable var editor = editor
        if editor.supportsAppConfiguration {
            VStack(alignment: .leading, spacing: 8) {
                Text("Managed configuration dictionary (plist <dict> fragment)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: $editor.appConfigurationPreferences)
                    .font(.body.monospaced())
                if let validationError = editor.appConfigurationValidationError() {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
        } else {
            ContentUnavailableView(
                "No App Configuration",
                systemImage: "curlybraces",
                description: Text("The Classic API does not expose App Configuration for Mac App Store apps.")
            )
        }
    }

    // MARK: - Row helpers

    @ViewBuilder
    private func boolRow(_ label: String, _ value: Bool?) -> some View {
        if let value {
            LabeledContent(label) {
                Image(systemName: value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(value ? Color.green : Color.secondary)
            }
        }
    }

    @ViewBuilder
    private func namedIDRows(_ label: String, _ items: [NamedID]?) -> some View {
        if let items, !items.isEmpty {
            LabeledContent(label) {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(items) { item in
                        Text(item.name ?? "ID \(item.id)")
                    }
                }
            }
        }
    }

    private var jamfWebURL: URL {
        client.serverURL
            .appending(path: catalog == .mac ? "macApps.html" : "mobileDeviceApps.html")
            .appending(queryItems: [
                URLQueryItem(name: "id", value: String(summary.id)),
                URLQueryItem(name: "o", value: "r"),
            ])
    }

    private func load(force: Bool) async {
        errorMessage = nil
        do {
            entry = try await recordStore.loadEntry(
                catalog: catalog, id: summary.id, client: client, force: force
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await recordStore.loadPickers(catalog: catalog, client: client)
    }
}
