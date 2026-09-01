// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

/// Per-row display info the Classic list endpoints don't provide (icon,
/// category, deployment, VPP counts, a scope summary). Rows resolve it
/// lazily from the full record as they appear; each app is fetched at most
/// once per session, and writes invalidate the row so it re-fetches.
struct RowInfo: Sendable {
    var iconURL: URL?
    var bundleID: String?
    var version: String?
    var categoryName: String?
    var deploymentType: String?
    var vppUsed: Int?
    var vppTotal: Int?
    var scopeSummary: String
    var scopeKind: ScopeKind

    enum ScopeKind: Sendable {
        case none
        case all
        case some
    }
}

@MainActor
@Observable
final class RowInfoStore {
    private var infos: [String: RowInfo] = [:]
    private var attempted: Set<String> = []

    private func key(_ catalog: AppCatalog, _ id: Int) -> String {
        "\(catalog.rawValue)-\(id)"
    }

    func info(for app: AppSummary, catalog: AppCatalog) -> RowInfo? {
        infos[key(catalog, app.id)]
    }

    func load(app: AppSummary, catalog: AppCatalog, client: JamfClient) async {
        let cacheKey = key(catalog, app.id)
        guard !attempted.contains(cacheKey) else { return }
        attempted.insert(cacheKey)

        switch catalog {
        case .mobileDevice:
            guard let detail = try? await client.fetchMobileDeviceAppDetail(id: app.id) else { return }
            infos[cacheKey] = Self.info(
                icon: detail.general.icon?.uri,
                bundleID: detail.general.bundleID,
                version: detail.general.version,
                category: detail.general.category?.name,
                deployment: detail.general.deploymentType,
                vpp: detail.vpp,
                scope: detail.scope,
                allTargets: detail.scope?.allMobileDevices ?? false
            )
        case .mac:
            guard let detail = try? await client.fetchMacAppDetail(id: app.id) else { return }
            infos[cacheKey] = Self.info(
                icon: detail.selfService?.icon?.uri,
                bundleID: detail.general.bundleID,
                version: detail.general.version,
                category: detail.general.category?.name,
                deployment: detail.general.deploymentType,
                vpp: detail.vpp,
                scope: detail.scope,
                allTargets: detail.scope?.allComputers ?? false
            )
        }
    }

    private static func info(
        icon: String?, bundleID: String?, version: String?, category: String?,
        deployment: String?, vpp: VPPSettings?, scope: AppScope?, allTargets: Bool
    ) -> RowInfo {
        var parts: [String] = []
        var kind = RowInfo.ScopeKind.none
        if allTargets {
            kind = .all
            parts = ["All devices"]
        } else if let scope {
            let groups = (scope.mobileDeviceGroups?.count ?? 0) + (scope.computerGroups?.count ?? 0)
            let places = (scope.buildings?.count ?? 0) + (scope.departments?.count ?? 0)
            let singles = (scope.mobileDevices?.count ?? 0) + (scope.computers?.count ?? 0)
            if groups > 0 { parts.append("\(groups) group\(groups == 1 ? "" : "s")") }
            if places > 0 { parts.append("\(places) bldg/dept") }
            if singles > 0 { parts.append("\(singles) device\(singles == 1 ? "" : "s")") }
            let exclusions = (scope.exclusions?.mobileDeviceGroups?.count ?? 0)
                + (scope.exclusions?.computerGroups?.count ?? 0)
                + (scope.exclusions?.buildings?.count ?? 0)
                + (scope.exclusions?.departments?.count ?? 0)
            if exclusions > 0 { parts.append("\(exclusions) excl") }
            kind = parts.isEmpty ? .none : .some
        }
        return RowInfo(
            iconURL: icon.flatMap(URL.init),
            bundleID: bundleID,
            version: version,
            categoryName: category,
            deploymentType: deployment,
            vppUsed: vpp?.usedVPPLicenses,
            vppTotal: vpp?.totalVPPLicenses,
            scopeSummary: parts.isEmpty ? "No scope" : parts.joined(separator: " · "),
            scopeKind: kind
        )
    }

    /// Drop one row so it re-fetches after a write.
    func invalidate(catalog: AppCatalog, id: Int) {
        let cacheKey = key(catalog, id)
        infos[cacheKey] = nil
        attempted.remove(cacheKey)
    }

    /// Called when a server disconnects so nothing bleeds between instances.
    func reset() {
        infos = [:]
        attempted = []
    }
}
