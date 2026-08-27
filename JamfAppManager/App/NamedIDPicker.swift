// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Form row for a multi-select list of Jamf entities (groups, buildings,
/// departments): shows the current selection, edits via a searchable
/// checklist popover.
struct NamedIDPicker: View {
    let title: String
    @Binding var selection: [NamedID]
    let options: [NamedID]
    var disabled = false

    @State private var showingPicker = false
    @State private var searchText = ""

    private var summary: String {
        selection.isEmpty
            ? "None"
            : selection.map { $0.name ?? "ID \($0.id)" }.joined(separator: ", ")
    }

    private var filteredOptions: [NamedID] {
        guard !searchText.isEmpty else { return options }
        return options.filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        LabeledContent(title) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary)
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                Button("Edit") { showingPicker = true }
                    .disabled(disabled)
                    .popover(isPresented: $showingPicker, arrowEdge: .trailing) {
                        picker
                    }
            }
        }
    }

    private var picker: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            Divider()
            List(filteredOptions) { option in
                let isSelected = selection.contains { $0.id == option.id }
                Button {
                    if isSelected {
                        selection.removeAll { $0.id == option.id }
                    } else {
                        selection.append(option)
                    }
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(option.name ?? "ID \(option.id)")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if filteredOptions.isEmpty {
                    Text(options.isEmpty ? "Nothing defined on this server" : "No matches")
                        .foregroundStyle(.secondary)
                }
            }
            if !selection.isEmpty {
                Divider()
                Button("Clear Selection") { selection = [] }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(width: 300, height: 340)
    }
}