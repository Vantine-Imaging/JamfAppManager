// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import Observation

/// One app plus the field values to overlay on it. Template applies use the
/// same fields for every item; CSV imports carry per-row values. A non-nil
/// `error` marks an item that failed before staging (bad CSV row, no match).
struct BatchItem: Sendable {
    var summary: AppSummary
    var fields: [FieldKey: TemplateValue]
    var error: String?
}

/// A batch of per-app field overlays headed for the review sheet.
struct BatchRequest: Identifiable {
    let id = UUID()
    var title: String
    var catalog: AppCatalog
    var items: [BatchItem]

    static func applying(_ template: SettingsTemplate, to targets: [AppSummary]) -> BatchRequest {
        BatchRequest(
            title: "Apply “\(template.name)”",
            catalog: template.catalog,
            items: targets.map { BatchItem(summary: $0, fields: template.fields, error: nil) }
        )
    }
}

@MainActor
@Observable
final class BatchApplyModel {
    enum TargetState: Hashable {
        case staging
        case ready(changes: [FieldChange], xml: String, path: String)
        case noChanges
        case applying
        case success(fieldCount: Int)
        case failed(String)
    }

    struct Target: Identifiable {
        let id = UUID()
        let item: BatchItem
        var state: TargetState = .staging

        var summary: AppSummary { item.summary }
    }

    enum Phase {
        case staging
        case preview
        case applying
        case done
    }

    let client: JamfClient
    let title: String
    let catalog: AppCatalog
    private(set) var targets: [Target]
    private(set) var phase: Phase = .staging

    init(client: JamfClient, request: BatchRequest) {
        self.client = client
        self.title = request.title
        self.catalog = request.catalog
        self.targets = request.items.map { Target(item: $0) }
    }

    var readyCount: Int {
        targets.count { if case .ready = $0.state { true } else { false } }
    }

    var successCount: Int {
        targets.count { if case .success = $0.state { true } else { false } }
    }

    var failedCount: Int {
        targets.count { if case .failed = $0.state { true } else { false } }
    }

    /// Dry run: fetch each app, overlay the template, and record the exact
    /// diff. Nothing is written. Fetches run in small concurrent batches.
    func stageAll() async {
        phase = .staging
        let batchSize = 4
        var index = 0
        while index < targets.count {
            let end = min(index + batchSize, targets.count)
            // Tasks inherit the main actor; the network awaits inside
            // stage(item:) interleave, so fetches run concurrently.
            let jobs = (index..<end).map { i in
                (i, Task { await self.stage(item: self.targets[i].item) })
            }
            for (i, job) in jobs {
                targets[i].state = await job.value
            }
            index = end
        }
        phase = .preview
    }

    private func stage(item: BatchItem) async -> TargetState {
        if let error = item.error {
            return .failed(error)
        }
        do {
            let editor: AppEditor
            switch catalog {
            case .mobileDevice:
                editor = AppEditor(mobile: try await client.fetchMobileDeviceAppDetail(id: item.summary.id))
            case .mac:
                editor = AppEditor(mac: try await client.fetchMacAppDetail(id: item.summary.id))
            }
            for key in FieldKey.applicableKeys(for: catalog) {
                if let value = item.fields[key] {
                    editor.setValue(value, for: key)
                }
            }
            if let validationError = editor.appConfigurationValidationError() {
                return .failed(validationError)
            }
            let changes = editor.changes
            guard !changes.isEmpty else { return .noChanges }
            return .ready(changes: changes, xml: editor.buildUpdateXML(), path: editor.updatePath)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The confirmed write pass: PUTs each staged app one at a time so a
    /// failure is visible immediately and the run can be judged mid-flight.
    func applyAll() async {
        phase = .applying
        for i in targets.indices {
            guard case .ready(let changes, let xml, let path) = targets[i].state else { continue }
            targets[i].state = .applying
            do {
                try await client.putClassicXML(path: path, xml: xml)
                targets[i].state = .success(fieldCount: changes.count)
            } catch {
                targets[i].state = .failed(error.localizedDescription)
            }
        }
        phase = .done
    }
}

/// The batch flow: dry-run diff for every selected app, one explicit
/// confirmation, live per-app results.
struct BatchApplySheet: View {
    @State private var model: BatchApplyModel
    @Environment(\.dismiss) private var dismiss
    @Environment(RecordStore.self) private var recordStore
    @Environment(RowInfoStore.self) private var rowInfoStore

    init(client: JamfClient, request: BatchRequest) {
        _model = State(initialValue: BatchApplyModel(client: client, request: request))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.phase == .staging {
                    ProgressView().controlSize(.small)
                }
            }
            .padding()

            List(model.targets) { target in
                targetRow(target)
            }

            HStack {
                Button(model.phase == .done ? "Close" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.phase == .preview || model.phase == .staging {
                    Button {
                        Task {
                            await model.applyAll()
                            await refreshCaches()
                        }
                    } label: {
                        Text("Apply to \(model.readyCount) App\(model.readyCount == 1 ? "" : "s")")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(model.phase != .preview || model.readyCount == 0)
                } else if model.phase == .applying {
                    ProgressView().controlSize(.small)
                }
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 460)
        .interactiveDismissDisabled(model.phase == .applying)
        .task { await model.stageAll() }
    }

    /// Written apps are stale in the record cache; drop them and refresh the
    /// list so renamed apps show their new titles.
    private func refreshCaches() async {
        var wroteAny = false
        for target in model.targets {
            if case .success = target.state {
                recordStore.invalidate(catalog: model.catalog, id: target.summary.id)
                rowInfoStore.invalidate(catalog: model.catalog, id: target.summary.id)
                wroteAny = true
            }
        }
        if wroteAny {
            _ = try? await recordStore.loadList(catalog: model.catalog, client: model.client, force: true)
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .staging: "Checking \(model.targets.count) apps against the requested values…"
        case .preview: "\(model.readyCount) of \(model.targets.count) apps have differences. Nothing is written until you apply."
        case .applying: "Writing changes to the server…"
        case .done: "Done: \(model.successCount) updated, \(model.failedCount) failed."
        }
    }

    @ViewBuilder
    private func targetRow(_ target: BatchApplyModel.Target) -> some View {
        switch target.state {
        case .staging:
            row(target, icon: "circle.dotted", color: .secondary, detail: "Checking…")
        case .noChanges:
            row(target, icon: "equal.circle", color: .secondary, detail: "Already matches")
        case .ready(let changes, _, _):
            DisclosureGroup {
                ForEach(changes) { change in
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
                    .lineLimit(3)
                }
            } label: {
                row(target, icon: "pencil.circle.fill", color: .blue,
                    detail: "\(changes.count) field\(changes.count == 1 ? "" : "s") will change")
            }
        case .applying:
            row(target, icon: "arrow.up.circle", color: .blue, detail: "Applying…")
        case .success(let fieldCount):
            row(target, icon: "checkmark.circle.fill", color: .green, detail: "Updated \(fieldCount) field\(fieldCount == 1 ? "" : "s")")
        case .failed(let message):
            row(target, icon: "xmark.octagon.fill", color: .red, detail: message)
        }
    }

    private func row(_ target: BatchApplyModel.Target, icon: String, color: Color, detail: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(target.summary.listTitle)
            Spacer()
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}