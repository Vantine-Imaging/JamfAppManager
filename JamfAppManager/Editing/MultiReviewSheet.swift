// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The confirmation gate for every write: gathers all apps in the catalog
/// with unsaved edits, shows each field as old → new (plus the raw XML), and
/// lets individual apps be unchecked before the one confirmed push. Nothing
/// reaches the server until "Apply" is clicked here.
struct MultiReviewSheet: View {
    let client: JamfClient
    let catalog: AppCatalog

    @Environment(RecordStore.self) private var recordStore
    @Environment(RowInfoStore.self) private var rowInfoStore
    @Environment(\.dismiss) private var dismiss

    private enum Status: Equatable {
        case pending
        case invalid(String)
        case applying
        case success(Int)
        case failed(String)
    }

    private enum Phase {
        case reviewing
        case applying
        case done
    }

    @State private var apps: [RecordStore.EditedApp] = []
    @State private var included: Set<Int> = []
    @State private var statuses: [Int: Status] = [:]
    @State private var phase: Phase = .reviewing

    private var successCount: Int {
        statuses.values.count { if case .success = $0 { true } else { false } }
    }

    private var failedCount: Int {
        statuses.values.count { if case .failed = $0 { true } else { false } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Changes")
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            List(apps) { app in
                appRow(app)
            }

            HStack {
                Button(phase == .done ? "Close" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if phase != .done {
                    Button {
                        Task { await applyAll() }
                    } label: {
                        if phase == .applying {
                            ProgressView().controlSize(.small).frame(minWidth: 120)
                        } else {
                            Text("Apply to \(included.count) App\(included.count == 1 ? "" : "s")")
                                .frame(minWidth: 120)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(phase != .reviewing || included.isEmpty)
                }
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 440)
        .interactiveDismissDisabled(phase == .applying)
        .onAppear { stage() }
    }

    private var subtitle: String {
        switch phase {
        case .reviewing:
            "\(apps.count) app\(apps.count == 1 ? " has" : "s have") unsaved edits in \(catalog.title). Uncheck any you don’t want to push."
        case .applying:
            "Writing changes to the server…"
        case .done:
            "Done: \(successCount) updated, \(failedCount) failed."
        }
    }

    private func stage() {
        apps = recordStore.editedApps(catalog: catalog)
        for app in apps {
            if let validationError = app.editor.appConfigurationValidationError() {
                statuses[app.id] = .invalid(validationError)
            } else {
                statuses[app.id] = .pending
                included.insert(app.id)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func appRow(_ app: RecordStore.EditedApp) -> some View {
        let status = statuses[app.id] ?? .pending
        DisclosureGroup {
            ForEach(app.editor.changes) { change in
                HStack(alignment: .top) {
                    Text(change.label)
                        .frame(width: 220, alignment: .leading)
                    Text(change.oldDisplay)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    Text(change.newDisplay)
                        .foregroundStyle(.green)
                }
                .font(.callout)
                .lineLimit(4)
            }
            DisclosureGroup("XML sent to the server") {
                Text(app.editor.buildUpdateXML())
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        } label: {
            HStack(spacing: 8) {
                Toggle("", isOn: includeBinding(app.id))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(phase != .reviewing || isInvalid(status))

                statusIcon(status, included: included.contains(app.id))

                Text(app.title)
                Spacer()
                Text(statusDetail(status, changeCount: app.editor.changes.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
    }

    private func includeBinding(_ id: Int) -> Binding<Bool> {
        Binding(
            get: { included.contains(id) },
            set: { on in
                if on { included.insert(id) } else { included.remove(id) }
            }
        )
    }

    private func isInvalid(_ status: Status) -> Bool {
        if case .invalid = status { return true }
        return false
    }

    @ViewBuilder
    private func statusIcon(_ status: Status, included: Bool) -> some View {
        switch status {
        case .pending:
            Image(systemName: included ? "pencil.circle.fill" : "minus.circle")
                .foregroundStyle(included ? Color.blue : Color.secondary)
        case .invalid:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .applying:
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.blue)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func statusDetail(_ status: Status, changeCount: Int) -> String {
        switch status {
        case .pending:
            "\(changeCount) field\(changeCount == 1 ? "" : "s")"
        case .invalid(let message):
            message
        case .applying:
            "Applying…"
        case .success(let fieldCount):
            "Updated \(fieldCount) field\(fieldCount == 1 ? "" : "s")"
        case .failed(let message):
            message
        }
    }

    // MARK: - Apply

    /// Writes the checked apps one at a time so a failure is visible
    /// immediately, then re-fetches everything that was written.
    private func applyAll() async {
        phase = .applying
        for app in apps {
            guard included.contains(app.id), statuses[app.id] == .pending else { continue }
            statuses[app.id] = .applying
            do {
                let fieldCount = app.editor.changes.count
                try await client.putClassicXML(path: app.editor.updatePath, xml: app.editor.buildUpdateXML())
                statuses[app.id] = .success(fieldCount)
            } catch {
                statuses[app.id] = .failed(error.localizedDescription)
            }
        }
        for app in apps {
            if case .success = statuses[app.id] ?? .pending {
                _ = try? await recordStore.loadEntry(catalog: catalog, id: app.id, client: client, force: true)
                rowInfoStore.invalidate(catalog: catalog, id: app.id)
            }
        }
        _ = try? await recordStore.loadList(catalog: catalog, client: client, force: true)
        phase = .done
    }
}
