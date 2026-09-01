// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Sidebar destinations.
enum SidebarItem: Hashable {
    case catalog(AppCatalog)
    case templates
}

/// The two sources of Mac apps in Jamf Pro.
enum MacSource: String, CaseIterable, Identifiable {
    case appStore = "App Store"
    case jamfAppCatalog = "Jamf App Catalog"

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(SessionStore.self) private var session
    @Environment(RowInfoStore.self) private var rowInfoStore
    @Environment(RecordStore.self) private var recordStore
    @State private var sidebarSelection: SidebarItem? = .catalog(.mac)
    @State private var selectedApps: Set<Int> = []
    @State private var macSource: MacSource = .appStore
    @State private var selectedDeployment: AppInstallerDeployment?
    @State private var selectedTemplateID: UUID?
    @State private var batchRequest: BatchRequest?
    @AppStorage(PaneLayout.storageKey) private var paneLayoutRaw = PaneLayout.right.rawValue

    private var paneLayout: PaneLayout {
        PaneLayout(rawValue: paneLayoutRaw) ?? .right
    }

    var body: some View {
        Group {
            switch session.phase {
            case .connected:
                mainInterface
            default:
                ConnectView()
            }
        }
        // Lives outside mainInterface: the connected view is unmounted at the
        // moment the server changes, so a reset attached there never fires.
        .onChange(of: session.activeServerID) {
            recordStore.reset()
            rowInfoStore.reset()
        }
    }

    private var mainInterface: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section("Catalogs") {
                    ForEach(AppCatalog.allCases) { catalog in
                        Label(catalog.title, systemImage: catalog.systemImage)
                            .tag(SidebarItem.catalog(catalog))
                    }
                }
                Section("Bulk Editing") {
                    Label("Templates", systemImage: "square.on.square.dashed")
                        .tag(SidebarItem.templates)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            workspace
        }
        // Keep the sidebar a discrete pane — the floating style lets wide
        // tables scroll underneath it.
        .navigationSplitViewStyle(.balanced)
        .onChange(of: sidebarSelection) {
            selectedApps = []
            selectedDeployment = nil
        }
        .onChange(of: macSource) {
            selectedApps = []
            selectedDeployment = nil
        }
        .sheet(item: $batchRequest) { request in
            if let client = session.client {
                BatchApplySheet(client: client, request: request)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    if let active = session.activeServer {
                        Text(active.host)
                        Divider()
                    }
                    ForEach(session.servers.filter { $0.id != session.activeServerID }) { server in
                        Button("Switch to \(server.displayName)") {
                            Task { await session.switchTo(server) }
                        }
                    }
                    Button("Add Server…") { session.disconnect() }
                    Divider()
                    Button("Disconnect") { session.disconnect() }
                } label: {
                    Label(session.activeServer?.displayName ?? "Server", systemImage: "server.rack")
                }
            }
        }
    }

    // MARK: - Workspace

    @ViewBuilder
    private var workspace: some View {
        switch sidebarSelection {
        case .catalog(let catalog):
            if let client = session.client {
                catalogWorkspace(client: client, catalog: catalog)
            }
        case .templates:
            HSplitView {
                TemplatesListView(selectedTemplateID: $selectedTemplateID)
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
                Group {
                    if let selectedTemplateID {
                        TemplateEditorView(templateID: selectedTemplateID)
                            .id(selectedTemplateID)
                    } else {
                        ContentUnavailableView(
                            "No Template Selected",
                            systemImage: "square.on.square.dashed",
                            description: Text("Choose a template from the list, or create one with the + button.")
                        )
                    }
                }
                .frame(minWidth: 380, maxWidth: .infinity)
            }
        case nil:
            Text("Select a catalog")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func catalogWorkspace(client: JamfClient, catalog: AppCatalog) -> some View {
        let showingInstallers = catalog == .mac && macSource == .jamfAppCatalog
        let listPane = VStack(spacing: 0) {
            if catalog == .mac {
                Picker("Source", selection: $macSource) {
                    ForEach(MacSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 4)
            }
            if showingInstallers {
                AppInstallerListView(client: client, selection: $selectedDeployment)
                    .navigationTitle(catalog.title)
            } else {
                AppListView(client: client, catalog: catalog, selection: $selectedApps) { request in
                    batchRequest = request
                }
                .id(catalog)
            }
        }

        switch paneLayout {
        case .right:
            HSplitView {
                listPane
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                detailPane(client: client, catalog: catalog, showingInstallers: showingInstallers)
                    .frame(minWidth: 400, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }
        case .bottom:
            VSplitView {
                listPane
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    .layoutPriority(1)
                detailPane(client: client, catalog: catalog, showingInstallers: showingInstallers)
                    .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
            }
        case .window:
            listPane
        }
    }

    @ViewBuilder
    private func detailPane(client: JamfClient, catalog: AppCatalog, showingInstallers: Bool) -> some View {
        // No .id(...) on these panes: identity churn makes the split view
        // store divider position per app instead of once. The detail views
        // reload themselves via .task(id:) when the selection changes.
        if showingInstallers {
            if let selectedDeployment {
                AppInstallerDetailView(client: client, deployment: selectedDeployment)
            } else {
                noSelectionPlaceholder
            }
        } else if selectedApps.count == 1, let appID = selectedApps.first,
                  let app = recordStore.list(for: catalog)?.first(where: { $0.id == appID }) {
            AppDetailView(client: client, catalog: catalog, summary: app)
        } else if selectedApps.count > 1 {
            ContentUnavailableView {
                Label("\(selectedApps.count) Apps Selected", systemImage: "square.on.square")
            } description: {
                Text("Use the Apply Template button above the list to change settings on all selected apps at once.")
            }
        } else {
            noSelectionPlaceholder
        }
    }

    private var noSelectionPlaceholder: some View {
        ContentUnavailableView(
            "No App Selected",
            systemImage: "app.dashed",
            description: Text("Choose an app from the list to view its settings.")
        )
    }
}

/// Content of a popped-out detail window (double-click a row, or the
/// "Detail in New Window" layout).
struct PopoutDetailView: View {
    let target: AppDetailTarget

    @Environment(SessionStore.self) private var session
    @Environment(RecordStore.self) private var recordStore

    var body: some View {
        if let client = session.client {
            let summary = recordStore.list(for: target.catalog)?
                .first { $0.id == target.appID }
                ?? AppSummary(id: target.appID, name: target.title, displayName: nil, bundleID: nil, version: nil)
            AppDetailView(client: client, catalog: target.catalog, summary: summary)
                .frame(minWidth: 560, minHeight: 480)
        } else {
            ContentUnavailableView(
                "Not Connected",
                systemImage: "bolt.horizontal.circle",
                description: Text("Connect to the server in the main window first.")
            )
            .frame(minWidth: 420, minHeight: 300)
        }
    }
}
