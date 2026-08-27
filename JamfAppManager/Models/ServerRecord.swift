// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A saved Jamf Pro instance. The client secret is not stored here — it lives
/// in the Keychain, keyed by server URL + client ID.
struct ServerRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var urlString: String
    var clientID: String

    var displayName: String {
        name.isEmpty ? host : name
    }

    var host: String {
        URL(string: urlString)?.host() ?? urlString
    }
}