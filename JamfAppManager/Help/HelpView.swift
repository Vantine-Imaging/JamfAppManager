// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Observation
import SwiftUI

/// Lets the Help menu open the window on a specific topic.
@MainActor
@Observable
final class HelpNavigator {
    var selection: String = HelpBook.gettingStarted.id
}

struct HelpView: View {
    @Environment(HelpNavigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator

        NavigationSplitView {
            List(HelpBook.topics, selection: $navigator.selection) { topic in
                Label(topic.title, systemImage: topic.symbol)
                    .padding(.vertical, 2)
                    .tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            let topic = HelpBook.topic(id: navigator.selection)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.title)
                            .font(.largeTitle.weight(.semibold))
                        Text(topic.summary)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)

                    ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
                .textSelection(.enabled)
            }
            // No navigationTitle here on purpose: it would rename the window
            // itself, so the Window menu would list whichever topic happened
            // to be open instead of "Jamf App Manager Help".
            //
            // A fresh topic should start at the top, not wherever the last one
            // was scrolled to.
            .id(topic.id)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder
    private func blockView(_ block: HelpBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.title3.weight(.semibold))
                .padding(.top, 8)

        case .paragraph(let text):
            Text(text)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(item)
                    }
                }
            }

        case .code(let text):
            Text(text)
                .font(.callout.monospaced())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

        case .note(let text):
            Label(text, systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

        case .warning(let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
