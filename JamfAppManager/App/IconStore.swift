// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

/// Session-wide cache of app icon URLs. The Classic API only exposes icons
/// on full records, so list rows resolve them lazily as they appear; each
/// app is fetched at most once per session.
@MainActor
@Observable
final class IconStore {
    private var urls: [String: URL] = [:]
    private var attempted: Set<String> = []

    private func key(_ catalog: AppCatalog, _ id: Int) -> String {
        "\(catalog.rawValue)-\(id)"
    }

    func url(for app: AppSummary, catalog: AppCatalog) -> URL? {
        urls[key(catalog, app.id)]
    }

    func load(app: AppSummary, catalog: AppCatalog, client: JamfClient) async {
        let cacheKey = key(catalog, app.id)
        guard !attempted.contains(cacheKey) else { return }
        attempted.insert(cacheKey)

        let uri: String?
        switch catalog {
        case .mobileDevice:
            let detail = try? await client.fetchMobileDeviceAppDetail(id: app.id)
            uri = detail?.general.icon?.uri
        case .mac:
            let detail = try? await client.fetchMacAppDetail(id: app.id)
            uri = detail?.selfService?.icon?.uri
        }
        if let uri, let url = URL(string: uri) {
            urls[cacheKey] = url
        }
    }

    /// Called when a server disconnects so stale icons don't bleed between
    /// instances.
    func reset() {
        urls = [:]
        attempted = []
    }
}