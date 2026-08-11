import SwiftUI

/// Content-column list of saved templates.
struct TemplatesListView: View {
    @Environment(TemplateStore.self) private var store
    @Binding var selectedTemplateID: UUID?

    var body: some View {
        List(selection: $selectedTemplateID) {
            ForEach(store.templates) { template in
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                    Text("\(template.catalog.title) · \(template.fields.count) field\(template.fields.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(template.id)
                .contextMenu {
                    Button("Duplicate") {
                        selectedTemplateID = store.duplicate(template).id
                    }
                    Button("Delete", role: .destructive) {
                        if selectedTemplateID == template.id { selectedTemplateID = nil }
                        store.remove(template)
                    }
                }
            }
        }
        .overlay {
            if store.templates.isEmpty {
                ContentUnavailableView(
                    "No Templates",
                    systemImage: "square.on.square.dashed",
                    description: Text("Create a template here, or use “Save Settings as Template” on any app.")
                )
            }
        }
        .navigationTitle("Templates")
        .navigationSubtitle("\(store.templates.count) templates")
        .toolbar {
            ToolbarItem {
                Button("New Template", systemImage: "plus") {
                    selectedTemplateID = store.add(
                        SettingsTemplate(name: "New Template", catalog: .mac)
                    ).id
                }
            }
        }
    }
}

/// Detail-column editor for one template: which fields it carries and their
/// values. Edits save immediately.
struct TemplateEditorView: View {
    @Environment(TemplateStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(RecordStore.self) private var recordStore
    let templateID: UUID

    private var template: SettingsTemplate? {
        store.template(id: templateID)
    }

    private var categories: [NamedID] { recordStore.categories ?? [] }
    private var vppAccounts: [NamedID] { recordStore.vppAccounts ?? [] }

    var body: some View {
        if let template {
            Form {
                Section {
                    TextField("Name", text: binding(\.name))
                    Picker("Applies To", selection: catalogBinding) {
                        ForEach(AppCatalog.allCases) { catalog in
                            Text(catalog.title).tag(catalog)
                        }
                    }
                } footer: {
                    Text("Only checked fields are applied. Everything else on the target app stays untouched.")
                }

                let keys = FieldKey.templateKeys(for: template.catalog)
                ForEach(["General", "Deployment", "Scope", "Self Service", "Managed Distribution", "App Configuration"], id: \.self) { group in
                    let groupKeys = keys.filter { $0.group == group }
                    if !groupKeys.isEmpty {
                        Section(group) {
                            ForEach(groupKeys) { key in
                                fieldRow(key: key, template: template)
                            }
                            if group == "Scope", session.client == nil {
                                Label("Connect to a server to pick groups.", systemImage: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(template.name)
            .navigationSubtitle(template.catalog.title)
            .task(id: template.catalog) {
                if let client = session.client {
                    await recordStore.loadPickers(catalog: template.catalog, client: client)
                }
            }
        } else {
            ContentUnavailableView("Template Deleted", systemImage: "square.on.square.dashed")
        }
    }

    @ViewBuilder
    private func fieldRow(key: FieldKey, template: SettingsTemplate) -> some View {
        let included = template.fields[key] != nil
        HStack(alignment: key == .appConfigurationPreferences ? .top : .center) {
            Toggle(isOn: includeBinding(key)) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Include \(key.label) in this template")

            if key.isNamedIDList {
                NamedIDPicker(
                    title: key.label,
                    selection: namedIDsBinding(key),
                    options: options(for: key),
                    disabled: !included
                )
            } else if key.isNamedID {
                let choices = key == .category ? categories : vppAccounts
                Picker(key.label, selection: namedIDBinding(key, options: choices)) {
                    if key == .category { Text("None").tag(-1) }
                    ForEach(choices) { choice in
                        Text(choice.name ?? "ID \(choice.id)").tag(choice.id)
                    }
                }
                .disabled(!included)
            } else if key == .ssCategories {
                VStack(alignment: .leading, spacing: 4) {
                    Text(key.label)
                    SelfServiceCategoriesEditor(categories: categories, selection: ssCategoriesBinding(key))
                        .disabled(!included)
                        .opacity(included ? 1 : 0.4)
                }
            } else if key.isBool {
                Toggle(key.label, isOn: boolBinding(key))
                    .disabled(!included)
            } else if key == .deploymentType {
                Picker(key.label, selection: stringBinding(key)) {
                    ForEach(AppEditor.deploymentTypeOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .disabled(!included)
            } else if key == .appConfigurationPreferences {
                VStack(alignment: .leading, spacing: 4) {
                    Text(key.label)
                    TextEditor(text: stringBinding(key))
                        .font(.callout.monospaced())
                        .frame(minHeight: 80)
                        .disabled(!included)
                        .opacity(included ? 1 : 0.4)
                    Text("plist <dict> fragment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if key == .ssDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Text(key.label)
                    TextEditor(text: stringBinding(key))
                        .font(.callout)
                        .frame(minHeight: 60)
                        .disabled(!included)
                        .opacity(included ? 1 : 0.4)
                }
            } else {
                TextField(key.label, text: stringBinding(key))
                    .disabled(!included)
            }
        }
    }

    private func options(for key: FieldKey) -> [NamedID] {
        guard let template,
              let scopeOptions = recordStore.scopeOptions[template.catalog]
        else { return [] }
        switch key {
        case .scopeGroups, .scopeExcludedGroups: return scopeOptions.groups
        case .scopeBuildings, .scopeExcludedBuildings: return scopeOptions.buildings
        case .scopeDepartments, .scopeExcludedDepartments: return scopeOptions.departments
        default: return []
        }
    }

    // MARK: - Bindings into the store

    private func binding<Value>(_ keyPath: WritableKeyPath<SettingsTemplate, Value>) -> Binding<Value> {
        Binding(
            get: { store.template(id: templateID)![keyPath: keyPath] },
            set: { newValue in
                guard var template = store.template(id: templateID) else { return }
                template[keyPath: keyPath] = newValue
                store.update(template)
            }
        )
    }

    private var catalogBinding: Binding<AppCatalog> {
        Binding(
            get: { store.template(id: templateID)?.catalog ?? .mac },
            set: { newCatalog in
                guard var template = store.template(id: templateID) else { return }
                template.catalog = newCatalog
                // Drop fields the new catalog doesn't support.
                template.fields = template.fields.filter { $0.key.appliesTo(newCatalog) }
                store.update(template)
            }
        )
    }

    private func includeBinding(_ key: FieldKey) -> Binding<Bool> {
        Binding(
            get: { store.template(id: templateID)?.fields[key] != nil },
            set: { include in
                guard var template = store.template(id: templateID) else { return }
                template.fields[key] = include ? SettingsTemplate.defaultValue(for: key) : nil
                store.update(template)
            }
        )
    }

    private func boolBinding(_ key: FieldKey) -> Binding<Bool> {
        Binding(
            get: {
                if case .bool(let value) = store.template(id: templateID)?.fields[key] { return value }
                return false
            },
            set: { newValue in
                guard var template = store.template(id: templateID) else { return }
                template.fields[key] = .bool(newValue)
                store.update(template)
            }
        )
    }

    private func namedIDBinding(_ key: FieldKey, options: [NamedID]) -> Binding<Int> {
        Binding(
            get: {
                if case .namedID(let item) = store.template(id: templateID)?.fields[key] { return item.id }
                return -1
            },
            set: { newID in
                guard var template = store.template(id: templateID) else { return }
                let name = newID == -1 ? "None" : options.first { $0.id == newID }?.name
                template.fields[key] = .namedID(NamedID(id: newID, name: name))
                store.update(template)
            }
        )
    }

    private func ssCategoriesBinding(_ key: FieldKey) -> Binding<[SelfServiceCategory]> {
        Binding(
            get: {
                if case .ssCategories(let items) = store.template(id: templateID)?.fields[key] { return items }
                return []
            },
            set: { newValue in
                guard var template = store.template(id: templateID) else { return }
                template.fields[key] = .ssCategories(newValue)
                store.update(template)
            }
        )
    }

    private func namedIDsBinding(_ key: FieldKey) -> Binding<[NamedID]> {
        Binding(
            get: {
                if case .namedIDs(let items) = store.template(id: templateID)?.fields[key] { return items }
                return []
            },
            set: { newValue in
                guard var template = store.template(id: templateID) else { return }
                template.fields[key] = .namedIDs(newValue)
                store.update(template)
            }
        )
    }

    private func stringBinding(_ key: FieldKey) -> Binding<String> {
        Binding(
            get: {
                if case .string(let value) = store.template(id: templateID)?.fields[key] { return value }
                return ""
            },
            set: { newValue in
                guard var template = store.template(id: templateID) else { return }
                template.fields[key] = .string(newValue)
                store.update(template)
            }
        )
    }
}
