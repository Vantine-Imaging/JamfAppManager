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
    @Environment(IconStore.self) private var iconStore
    @Environment(RecordStore.self) private var recordStore
    @State private var sidebarSelection: SidebarItem? = .catalog(.mac)
    @State private var selectedApps: Set<AppSummary> = []
    @State private var macSource: MacSource = .appStore
    @State private var selectedDeployment: AppInstallerDeployment?
    @State private var selectedTemplateID: UUID?
    @State private var batchRequest: BatchRequest?

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
            iconStore.reset()
        }
    }

    private var showingJamfAppCatalog: Bool {
        sidebarSelection == .catalog(.mac) && macSource == .jamfAppCatalog
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
        } content: {
            switch sidebarSelection {
            case .catalog(let catalog):
                if let client = session.client {
                    catalogList(client: client, catalog: catalog)
                }
            case .templates:
                TemplatesListView(selectedTemplateID: $selectedTemplateID)
            case nil:
                Text("Select a catalog")
                    .foregroundStyle(.secondary)
            }
        } detail: {
            detailColumn
        }
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

    @ViewBuilder
    private func catalogList(client: JamfClient, catalog: AppCatalog) -> some View {
        if catalog == .mac {
            VStack(spacing: 0) {
                Picker("Source", selection: $macSource) {
                    ForEach(MacSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 4)

                switch macSource {
                case .appStore:
                    AppListView(client: client, catalog: .mac, selection: $selectedApps) { request in
                        batchRequest = request
                    }
                case .jamfAppCatalog:
                    AppInstallerListView(client: client, selection: $selectedDeployment)
                        .navigationTitle(catalog.title)
                }
            }
        } else {
            AppListView(client: client, catalog: catalog, selection: $selectedApps) { request in
                batchRequest = request
            }
            .id(catalog)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if sidebarSelection == .templates {
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
        } else if case .catalog(let catalog) = sidebarSelection, let client = session.client {
            if showingJamfAppCatalog {
                if let selectedDeployment {
                    AppInstallerDetailView(client: client, deployment: selectedDeployment)
                        .id(selectedDeployment.id)
                } else {
                    noSelectionPlaceholder
                }
            } else if selectedApps.count == 1, let app = selectedApps.first {
                AppDetailView(client: client, catalog: catalog, summary: app)
                    .id(app.id)
            } else if selectedApps.count > 1 {
                ContentUnavailableView {
                    Label("\(selectedApps.count) Apps Selected", systemImage: "square.on.square")
                } description: {
                    Text("Use the Apply Template button above the list to change settings on all selected apps at once.")
                }
            } else {
                noSelectionPlaceholder
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
