// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

/// Editable working copy of a Jamf App Catalog deployment. Unlike Classic
/// records, the Pro API takes a full JSON document on PUT, so the update body
/// is the fetched record with edited fields overlaid — fields this editor
/// doesn't touch (e.g. notification settings) pass through unchanged.
@MainActor
@Observable
final class AppInstallerEditor {
    private let original: AppInstallerDeploymentDetail

    var enabled: Bool
    var deploymentType: String
    var updateBehavior: String
    var categoryID: String
    var categoryName: String?    // display only, updated by the picker
    var smartGroupID: String
    var smartGroupName: String?  // display only, updated by the picker
    private let originalCategoryName: String?
    private let originalSmartGroupName: String?
    var installPredefinedConfigProfiles: Bool
    var triggerAdminNotifications: Bool
    var ssIncludeInFeatured: Bool
    var ssIncludeInCompliance: Bool
    var ssForceViewDescription: Bool
    var ssDescription: String

    nonisolated static let deploymentTypeOptions = ["INSTALL_AUTOMATICALLY", "SELF_SERVICE"]
    nonisolated static let updateBehaviorOptions = ["AUTOMATIC", "MANUAL"]

    nonisolated static func friendly(_ constant: String?) -> String {
        guard let constant, !constant.isEmpty else { return "—" }
        return constant
            .split(separator: "_")
            .map { $0.prefix(1) + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    init(detail: AppInstallerDeploymentDetail, summary: AppInstallerDeployment) {
        original = detail
        enabled = detail.enabled ?? false
        deploymentType = detail.deploymentType ?? "SELF_SERVICE"
        updateBehavior = detail.updateBehavior ?? "MANUAL"
        categoryID = detail.categoryId ?? "-1"
        categoryName = summary.category?.name
        originalCategoryName = summary.category?.name
        smartGroupID = detail.smartGroupId ?? ""
        smartGroupName = summary.smartGroup?.name
        originalSmartGroupName = summary.smartGroup?.name
        installPredefinedConfigProfiles = detail.installPredefinedConfigProfiles ?? false
        triggerAdminNotifications = detail.triggerAdminNotifications ?? false
        ssIncludeInFeatured = detail.selfServiceSettings?.includeInFeaturedCategory ?? false
        ssIncludeInCompliance = detail.selfServiceSettings?.includeInComplianceCategory ?? false
        ssForceViewDescription = detail.selfServiceSettings?.forceViewDescription ?? false
        ssDescription = detail.selfServiceSettings?.description ?? ""
    }

    var changes: [FieldChange] {
        var result: [FieldChange] = []
        func track(_ label: String, _ old: String, _ new: String, element: String) {
            guard old != new else { return }
            result.append(FieldChange(
                section: "deployment", element: element, label: label,
                oldDisplay: old.isEmpty ? "—" : old,
                newDisplay: new.isEmpty ? "—" : new,
                xmlValue: "" // Pro API updates are JSON; see buildUpdateBody()
            ))
        }

        track("Enabled", (original.enabled ?? false) ? "Yes" : "No", enabled ? "Yes" : "No", element: "enabled")
        track("Deployment Type", Self.friendly(original.deploymentType), Self.friendly(deploymentType), element: "deploymentType")
        track("Update Behavior", Self.friendly(original.updateBehavior), Self.friendly(updateBehavior), element: "updateBehavior")
        // ID comparison with name-based display (names alone can collide
        // with placeholders, so don't reuse track's string guard).
        if categoryID != (original.categoryId ?? "-1") {
            result.append(FieldChange(
                section: "deployment", element: "categoryId", label: "Category",
                oldDisplay: originalCategoryName ?? "None",
                newDisplay: categoryName ?? "ID \(categoryID)", xmlValue: ""
            ))
        }
        if smartGroupID != (original.smartGroupId ?? "") {
            result.append(FieldChange(
                section: "deployment", element: "smartGroupId", label: "Smart Group",
                oldDisplay: originalSmartGroupName ?? "ID \(original.smartGroupId ?? "?")",
                newDisplay: smartGroupName ?? "ID \(smartGroupID)", xmlValue: ""
            ))
        }
        track("Install Predefined Config Profiles",
              (original.installPredefinedConfigProfiles ?? false) ? "Yes" : "No",
              installPredefinedConfigProfiles ? "Yes" : "No",
              element: "installPredefinedConfigProfiles")
        track("Admin Notifications",
              (original.triggerAdminNotifications ?? false) ? "Yes" : "No",
              triggerAdminNotifications ? "Yes" : "No",
              element: "triggerAdminNotifications")
        track("Include in Featured Category",
              (original.selfServiceSettings?.includeInFeaturedCategory ?? false) ? "Yes" : "No",
              ssIncludeInFeatured ? "Yes" : "No", element: "includeInFeaturedCategory")
        track("Include in Compliance Category",
              (original.selfServiceSettings?.includeInComplianceCategory ?? false) ? "Yes" : "No",
              ssIncludeInCompliance ? "Yes" : "No", element: "includeInComplianceCategory")
        track("Force View Description",
              (original.selfServiceSettings?.forceViewDescription ?? false) ? "Yes" : "No",
              ssForceViewDescription ? "Yes" : "No", element: "forceViewDescription")
        track("Self Service Description",
              original.selfServiceSettings?.description ?? "", ssDescription, element: "description")

        return result
    }

    var hasChanges: Bool { !changes.isEmpty }

    var updatePath: String { "api/v1/app-installers/deployments/\(original.id)" }

    func buildUpdatedDetail() -> AppInstallerDeploymentDetail {
        var updated = original
        updated.enabled = enabled
        updated.deploymentType = deploymentType
        updated.updateBehavior = updateBehavior
        updated.categoryId = categoryID
        updated.smartGroupId = smartGroupID.isEmpty ? original.smartGroupId : smartGroupID
        updated.installPredefinedConfigProfiles = installPredefinedConfigProfiles
        updated.triggerAdminNotifications = triggerAdminNotifications
        var selfService = updated.selfServiceSettings ?? AppInstallerSelfServiceSettings()
        selfService.includeInFeaturedCategory = ssIncludeInFeatured
        selfService.includeInComplianceCategory = ssIncludeInCompliance
        selfService.forceViewDescription = ssForceViewDescription
        selfService.description = ssDescription.isEmpty ? nil : ssDescription
        updated.selfServiceSettings = selfService
        return updated
    }

    func buildUpdateBody(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(buildUpdatedDetail())
    }
}