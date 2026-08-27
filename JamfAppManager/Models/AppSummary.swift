// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One row in a catalog listing (GET /JSSResource/<collection>).
struct AppSummary: Identifiable, Hashable, Sendable, Decodable {
    let id: Int
    let name: String
    var displayName: String?
    var bundleID: String?
    var version: String?

    enum CodingKeys: String, CodingKey {
        case id, name, version
        case displayName = "display_name"
        case bundleID = "bundle_id"
    }

    /// What to show in lists: display name when present, falling back to record name.
    var listTitle: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return name
    }
}