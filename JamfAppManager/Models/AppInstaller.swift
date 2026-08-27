// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

// Jamf App Catalog (App Installers) deployments, from the Jamf Pro API
// (/api/v1/app-installers). Unlike the Classic API these use string IDs
// and camelCase JSON.

struct AppInstallerRef: Codable, Hashable, Sendable {
    var id: String
    var name: String?
}

struct AppInstallerAppInfo: Codable, Hashable, Sendable {
    var id: String?
    var bundleId: String?
    var latestVersion: String?
    var selectedVersion: String?
    var deployedVersion: String?
    var versionRemoved: Bool?
    var titleAvailableInAis: Bool?
    var iconUrl: String?
    var mediaSourceType: String?
}

struct AppInstallerComputerStatuses: Codable, Hashable, Sendable {
    var installed: Int?
    var available: Int?
    var inProgress: Int?
    var failed: Int?
    var unqualified: Int?
}

/// One row from GET /api/v1/app-installers/deployments.
struct AppInstallerDeployment: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var enabled: Bool?
    var deploymentType: String?
    var updateBehavior: String?
    var site: AppInstallerRef?
    var smartGroup: AppInstallerRef?
    var category: AppInstallerRef?
    var computerStatuses: AppInstallerComputerStatuses?
    var app: AppInstallerAppInfo?
}

struct AppInstallerNotificationSettings: Codable, Hashable, Sendable {
    var notificationMessage: String?
    var notificationInterval: Int?
    var deadlineMessage: String?
    var deadline: Int?
    var quitDelay: Int?
    var completeMessage: String?
    var relaunch: Bool?
    var suppress: Bool?
}

struct AppInstallerSelfServiceCategory: Codable, Hashable, Sendable {
    var id: String
    var featured: Bool?
}

struct AppInstallerSelfServiceSettings: Codable, Hashable, Sendable {
    var includeInFeaturedCategory: Bool?
    var includeInComplianceCategory: Bool?
    var forceViewDescription: Bool?
    var description: String?
    var categories: [AppInstallerSelfServiceCategory]?
}

/// Full record from GET /api/v1/app-installers/deployments/{id}.
struct AppInstallerDeploymentDetail: Codable, Sendable {
    var id: String
    var name: String?
    var enabled: Bool?
    var appTitleId: String?
    var deploymentType: String?
    var updateBehavior: String?
    var categoryId: String?
    var siteId: String?
    var smartGroupId: String?
    var installPredefinedConfigProfiles: Bool?
    var titleAvailableInAis: Bool?
    var triggerAdminNotifications: Bool?
    var notificationSettings: AppInstallerNotificationSettings?
    var selfServiceSettings: AppInstallerSelfServiceSettings?
    var selectedVersion: String?
    var latestAvailableVersion: String?
    var versionRemoved: Bool?
}

/// Pro API pagination envelope.
struct ProAPIPage<Element: Decodable & Sendable>: Decodable, Sendable {
    var totalCount: Int
    var results: [Element]
}