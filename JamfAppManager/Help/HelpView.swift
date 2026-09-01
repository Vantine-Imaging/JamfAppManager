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

/// Single-window help book: colored icon header, a horizontal bar of topic
/// pills, and the topic's content grouped into cards.
struct HelpView: View {
    @Environment(HelpNavigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let topic = HelpBook.topic(id: navigator.selection)
        VStack(spacing: 0) {
            header(topic)
            tabBar(selected: topic)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(sections(of: topic).enumerated()), id: \.offset) { _, section in
                        sectionCard(section, accent: topic.accent)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            // A fresh topic starts at the top, not wherever the last one was
            // scrolled to.
            .id(topic.id)
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 700, height: 640)
    }

    // MARK: - Header

    private func header(_ topic: HelpTopic) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(topic.accent.opacity(0.22))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: topic.symbol)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(topic.accent)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.title2.weight(.bold))
                Text(topic.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Topic pills

    private func tabBar(selected: HelpTopic) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HelpBook.topics) { topic in
                    let isSelected = topic.id == selected.id
                    Button {
                        navigator.selection = topic.id
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: topic.symbol)
                                .font(.system(size: 11))
                            Text(topic.title)
                                .font(.callout.weight(isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? topic.accent.opacity(0.22) : Color.clear,
                            in: Capsule()
                        )
                        .overlay {
                            if isSelected {
                                Capsule().strokeBorder(topic.accent.opacity(0.5), lineWidth: 1)
                            }
                        }
                        .foregroundStyle(isSelected ? topic.accent : .secondary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Cards

    private struct TopicSection {
        var title: String?
        var blocks: [HelpBlock]
    }

    /// A heading starts a new card; blocks before the first heading form the
    /// intro card.
    private func sections(of topic: HelpTopic) -> [TopicSection] {
        var result: [TopicSection] = []
        var current = TopicSection(title: nil, blocks: [])
        for block in topic.blocks {
            if case .heading(let title) = block {
                if current.title != nil || !current.blocks.isEmpty {
                    result.append(current)
                }
                current = TopicSection(title: title, blocks: [])
            } else {
                current.blocks.append(block)
            }
        }
        if current.title != nil || !current.blocks.isEmpty {
            result.append(current)
        }
        return result
    }

    private func sectionCard(_ section: TopicSection, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = section.title {
                Text(title)
                    .font(.headline)
            }
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block, accent: accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func blockView(_ block: HelpBlock, accent: Color) -> some View {
        switch block {
        case .heading(let text):
            // Headings split cards; a stray one inside renders as a subhead.
            Text(text).font(.headline)

        case .paragraph(let text):
            Text(text)
                .foregroundStyle(.primary.opacity(0.9))

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(accent.opacity(0.8))
                            .frame(width: 5, height: 5)
                            .offset(y: -2)
                        Text(item)
                            .foregroundStyle(.primary.opacity(0.9))
                    }
                }
            }

        case .code(let text):
            Text(text)
                .font(.callout.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

        case .note(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(accent)
                Text(text)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

        case .warning(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(text)
            }
            .font(.callout)
        }
    }
}
