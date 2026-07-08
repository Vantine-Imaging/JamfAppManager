import SwiftUI

/// Searchable listing of Jamf App Catalog (App Installers) deployments.
struct AppInstallerListView: View {
    let client: JamfClient
    @Binding var selection: AppInstallerDeployment?

    @State private var deployments: [AppInstallerDeployment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filtered: [AppInstallerDeployment] {
        guard !searchText.isEmpty else { return deployments }
        return deployments.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.app?.bundleId?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        Group {
            if isLoading, deployments.isEmpty {
                ProgressView("Loading Jamf App Catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Deployments", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else {
                List(filtered, id: \.self, selection: $selection) { deployment in
                    HStack(spacing: 8) {
                        AsyncImage(url: deployment.app?.iconUrl.flatMap(URL.init)) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Image(systemName: "shippingbox")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deployment.name)
                            if let bundleID = deployment.app?.bundleId {
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if deployment.enabled == false {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .tag(deployment)
                    .contextMenu {
                        Button("Copy Name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(deployment.name, forType: .string)
                        }
                        if let bundleID = deployment.app?.bundleId {
                            Button("Copy Bundle ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(bundleID, forType: .string)
                            }
                        }
                    }
                }
                .overlay {
                    if filtered.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                "No Deployments",
                                systemImage: "shippingbox",
                                description: Text("No Jamf App Catalog apps are deployed on this server.")
                            )
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                }
            }
        }
        .navigationSubtitle("\(deployments.count) deployments")
        .searchable(text: $searchText, prompt: "Name or bundle ID")
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await load() }
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            deployments = try await client.fetchAppInstallerDeployments()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Editable detail for one App Installers deployment. Writes go through the
/// same review-diff-confirm gate as Classic records, but as a Pro API JSON PUT.
struct AppInstallerDetailView: View {
    let client: JamfClient
    let deployment: AppInstallerDeployment

    @State private var editor: AppInstallerEditor?
    @State private var errorMessage: String?
    @State private var showingReview = false
    @State private var categories: [NamedID] = []
    @State private var smartGroups: [NamedID] = []

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Deployment", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if let editor {
                form(editor: editor)
                    .toolbar {
                        if editor.hasChanges {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Review Changes (\(editor.changes.count))") {
                                    showingReview = true
                                }
                                .buttonStyle(.glassProminent)
                            }
                            ToolbarItem {
                                Button("Discard", systemImage: "arrow.uturn.backward") {
                                    Task { await load() }
                                }
                                .help("Discard unsaved edits")
                            }
                        }
                    }
                    .sheet(isPresented: $showingReview) {
                        AppInstallerReviewSheet(client: client, editor: editor) {
                            Task { await load() }
                        }
                    }
            } else {
                ProgressView("Loading \(deployment.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(deployment.name)
        .navigationSubtitle("Jamf App Catalog · ID \(deployment.id)")
        .task { await load() }
    }

    @ViewBuilder
    private func form(editor: AppInstallerEditor) -> some View {
        @Bindable var editor = editor
        Form {
            Section("General") {
                Toggle("Enabled", isOn: $editor.enabled)
                Picker("Deployment Type", selection: $editor.deploymentType) {
                    ForEach(AppInstallerEditor.deploymentTypeOptions, id: \.self) { option in
                        Text(AppInstallerEditor.friendly(option)).tag(option)
                    }
                }
                Picker("Update Behavior", selection: $editor.updateBehavior) {
                    ForEach(AppInstallerEditor.updateBehaviorOptions, id: \.self) { option in
                        Text(AppInstallerEditor.friendly(option)).tag(option)
                    }
                }
                categoryPicker(editor: $editor)
                Toggle("Install Predefined Config Profiles", isOn: $editor.installPredefinedConfigProfiles)
                Toggle("Admin Notifications", isOn: $editor.triggerAdminNotifications)
            }
            Section("Version") {
                LabeledContent("Selected", value: deployment.app?.selectedVersion ?? "—")
                LabeledContent("Latest Available", value: deployment.app?.latestVersion ?? "—")
                LabeledContent("Deployed", value: deployment.app?.deployedVersion ?? "—")
            }
            Section("Scope") {
                smartGroupPicker(editor: $editor)
                LabeledContent("Site", value: deployment.site?.name ?? "—")
            }
            if let statuses = deployment.computerStatuses {
                Section("Install Status") {
                    LabeledContent("Installed", value: String(statuses.installed ?? 0))
                    LabeledContent("Available", value: String(statuses.available ?? 0))
                    LabeledContent("In Progress", value: String(statuses.inProgress ?? 0))
                    LabeledContent("Failed", value: String(statuses.failed ?? 0))
                }
            }
            Section("Self Service") {
                Toggle("Include in Featured Category", isOn: $editor.ssIncludeInFeatured)
                Toggle("Include in Compliance Category", isOn: $editor.ssIncludeInCompliance)
                Toggle("Force View Description", isOn: $editor.ssForceViewDescription)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                    TextEditor(text: $editor.ssDescription)
                        .font(.callout)
                        .frame(minHeight: 60)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func categoryPicker(editor: Bindable<AppInstallerEditor>) -> some View {
        let currentID = editor.wrappedValue.categoryID
        let known = categories.contains { String($0.id) == currentID } || currentID == "-1"
        Picker("Category", selection: editor.categoryID) {
            Text("None").tag("-1")
            if !known {
                Text(editor.wrappedValue.categoryName ?? "ID \(currentID)").tag(currentID)
            }
            ForEach(categories) { category in
                Text(category.name ?? "ID \(category.id)").tag(String(category.id))
            }
        }
        .onChange(of: editor.wrappedValue.categoryID) {
            editor.wrappedValue.categoryName = editor.wrappedValue.categoryID == "-1"
                ? "None"
                : categories.first { String($0.id) == editor.wrappedValue.categoryID }?.name
        }
    }

    @ViewBuilder
    private func smartGroupPicker(editor: Bindable<AppInstallerEditor>) -> some View {
        let currentID = editor.wrappedValue.smartGroupID
        let known = smartGroups.contains { String($0.id) == currentID }
        Picker("Smart Group", selection: editor.smartGroupID) {
            if !known {
                Text(editor.wrappedValue.smartGroupName ?? "ID \(currentID)").tag(currentID)
            }
            ForEach(smartGroups) { group in
                Text(group.name ?? "ID \(group.id)").tag(String(group.id))
            }
        }
        .onChange(of: editor.wrappedValue.smartGroupID) {
            editor.wrappedValue.smartGroupName =
                smartGroups.first { String($0.id) == editor.wrappedValue.smartGroupID }?.name
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            let detail = try await client.fetchAppInstallerDeploymentDetail(id: deployment.id)
            editor = AppInstallerEditor(detail: detail, summary: deployment)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if categories.isEmpty {
            categories = (try? await client.fetchCategories()) ?? []
        }
        if smartGroups.isEmpty {
            smartGroups = (try? await client.fetchSmartComputerGroups()) ?? []
        }
    }
}

/// Review-and-confirm gate for App Installer writes.
struct AppInstallerReviewSheet: View {
    let client: JamfClient
    let editor: AppInstallerEditor
    var onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false
    @State private var applyError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review Changes")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(editor.changes.count) field\(editor.changes.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            .padding()

            List {
                Section {
                    ForEach(editor.changes) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(change.label)
                                .font(.headline)
                            HStack(alignment: .top, spacing: 8) {
                                Text(change.oldDisplay)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                                Text(change.newDisplay)
                                    .foregroundStyle(.green)
                            }
                            .font(.callout)
                            .lineLimit(6)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section {
                    DisclosureGroup("JSON sent to the server") {
                        Text((try? editor.buildUpdateBody(prettyPrinted: true))
                            .map { String(decoding: $0, as: UTF8.self) } ?? "—")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            VStack(spacing: 12) {
                if let applyError {
                    Label(applyError, systemImage: "xmark.octagon")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button {
                        Task { await apply() }
                    } label: {
                        if isApplying {
                            ProgressView().controlSize(.small).frame(minWidth: 80)
                        } else {
                            Text("Apply to Server").frame(minWidth: 80)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isApplying || editor.changes.isEmpty)
                }
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func apply() async {
        isApplying = true
        applyError = nil
        do {
            let body = try editor.buildUpdateBody()
            try await client.putProJSON(path: editor.updatePath, body: body)
            isApplying = false
            dismiss()
            onApplied()
        } catch {
            isApplying = false
            applyError = error.localizedDescription
        }
    }
}
