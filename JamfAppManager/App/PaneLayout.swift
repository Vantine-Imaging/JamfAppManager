// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Where the detail pane lives relative to the app list — Outlook-style.
enum PaneLayout: String, CaseIterable, Identifiable {
    case right
    case bottom
    case window

    var id: String { rawValue }

    static let storageKey = "paneLayout"

    var title: String {
        switch self {
        case .right: "Detail on Right"
        case .bottom: "Detail Below"
        case .window: "Detail in New Window"
        }
    }

    var symbol: String {
        switch self {
        case .right: "rectangle.split.2x1"
        case .bottom: "rectangle.split.1x2"
        case .window: "macwindow.on.rectangle"
        }
    }
}

/// Identifies an app for a popped-out detail window (double-click a row, or
/// the "Detail in New Window" layout).
struct AppDetailTarget: Codable, Hashable {
    var catalogRaw: String
    var appID: Int
    var title: String

    var catalog: AppCatalog { AppCatalog(rawValue: catalogRaw) ?? .mac }
}
