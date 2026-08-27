// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The confirmation gate for every write: shows exactly which fields will
/// change (old → new) and the raw XML that will be sent. Nothing reaches the
/// server until "Apply" is clicked here.
struct ReviewChangesSheet: View {
    let client: JamfClient
    let editor: AppEditor
    var onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false
    @State private var applyError: String?

    private var validationError: String? {
        editor.appConfigurationValidationError()
    }

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
                    DisclosureGroup("XML sent to the server") {
                        Text(editor.buildUpdateXML())
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            VStack(spacing: 12) {
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
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
                    .disabled(isApplying || validationError != nil || editor.changes.isEmpty)
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
            try await client.putClassicXML(path: editor.updatePath, xml: editor.buildUpdateXML())
            isApplying = false
            dismiss()
            onApplied()
        } catch {
            isApplying = false
            applyError = error.localizedDescription
        }
    }
}