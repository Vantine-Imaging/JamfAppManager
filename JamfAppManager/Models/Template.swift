// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Every field a template can carry. Raw values are the persistence format —
/// don't rename cases without migrating saved templates.
enum FieldKey: String, Codable, CaseIterable, Identifiable, Sendable {
    // Per-app identity fields: valid in CSV imports (each row has its own
    // value) but excluded from templates, which would stamp one value
    // everywhere.
    case displayName
    case appDescription
    case deploymentType
    case deployAutomatically
    case deployAsManagedApp
    case removeAppWhenMDMProfileIsRemoved
    case preventBackupOfAppData
    case allowUserToDelete
    case requireNetworkTethered
    case keepAppUpdatedOnDevices
    case keepDescriptionAndIconUpToDate
    case makeAvailableAfterInstall
    case takeOverManagement
    case assignVPPDeviceBasedLicenses
    case appConfigurationPreferences
    case category
    case vppLocation
    case ssButtonText
    case ssDescription
    case ssForceViewDescription
    case ssFeatureOnMainPage
    case ssNotificationEnabled
    case ssNotificationSubject
    case ssNotificationMessage
    case ssCategories
    case scopeAllTargets
    case scopeGroups
    case scopeBuildings
    case scopeDepartments
    case scopeExcludedGroups
    case scopeExcludedBuildings
    case scopeExcludedDepartments

    var id: String { rawValue }

    var label: String {
        switch self {
        case .displayName: "Display Name"
        case .appDescription: "Description"
        case .deploymentType: "Deployment Type"
        case .deployAutomatically: "Deploy Automatically"
        case .deployAsManagedApp: "Deploy as Managed App"
        case .removeAppWhenMDMProfileIsRemoved: "Remove with MDM Profile"
        case .preventBackupOfAppData: "Prevent Backup of App Data"
        case .allowUserToDelete: "Allow User to Delete"
        case .requireNetworkTethered: "Require Network Tethered"
        case .keepAppUpdatedOnDevices: "Keep App Updated on Devices"
        case .keepDescriptionAndIconUpToDate: "Keep Description & Icon Up to Date"
        case .makeAvailableAfterInstall: "Make Available After Install"
        case .takeOverManagement: "Take Over Management"
        case .assignVPPDeviceBasedLicenses: "Assign Device-Based Licenses"
        case .appConfigurationPreferences: "App Configuration"
        case .category: "Category"
        case .vppLocation: "VPP Location"
        case .ssButtonText: "Self Service Button Text"
        case .ssDescription: "Self Service Description"
        case .ssForceViewDescription: "Force Users to View Description"
        case .ssFeatureOnMainPage: "Feature on Main Page"
        case .ssNotificationEnabled: "Display Notifications"
        case .ssNotificationSubject: "Notification Subject"
        case .ssNotificationMessage: "Notification Message"
        case .ssCategories: "Self Service Categories"
        case .scopeAllTargets: "All Devices/Computers"
        case .scopeGroups: "Scoped Groups"
        case .scopeBuildings: "Scoped Buildings"
        case .scopeDepartments: "Scoped Departments"
        case .scopeExcludedGroups: "Excluded Groups"
        case .scopeExcludedBuildings: "Excluded Buildings"
        case .scopeExcludedDepartments: "Excluded Departments"
        }
    }

    /// UI grouping in the template editor.
    var group: String {
        switch self {
        case .displayName, .appDescription: "Identity"
        case .category: "General"
        case .assignVPPDeviceBasedLicenses, .vppLocation: "Managed Distribution"
        case .ssButtonText, .ssDescription, .ssForceViewDescription, .ssFeatureOnMainPage,
             .ssNotificationEnabled, .ssNotificationSubject, .ssNotificationMessage, .ssCategories:
            "Self Service"
        case .appConfigurationPreferences: "App Configuration"
        case .scopeAllTargets, .scopeGroups, .scopeBuildings, .scopeDepartments,
             .scopeExcludedGroups, .scopeExcludedBuildings, .scopeExcludedDepartments:
            "Scope"
        default: "Deployment"
        }
    }

    /// Per-app fields stay out of templates but are importable via CSV.
    var includeInTemplates: Bool {
        switch self {
        case .displayName, .appDescription: false
        default: true
        }
    }

    var isBool: Bool {
        switch self {
        case .ssForceViewDescription, .ssFeatureOnMainPage, .ssNotificationEnabled: true
        case .displayName, .appDescription: false
        case .deploymentType, .appConfigurationPreferences: false
        case .category, .vppLocation, .ssButtonText, .ssDescription,
             .ssNotificationSubject, .ssNotificationMessage, .ssCategories:
            false
        case .scopeGroups, .scopeBuildings, .scopeDepartments,
             .scopeExcludedGroups, .scopeExcludedBuildings, .scopeExcludedDepartments:
            false
        default: true
        }
    }

    var isNamedIDList: Bool {
        switch self {
        case .scopeGroups, .scopeBuildings, .scopeDepartments,
             .scopeExcludedGroups, .scopeExcludedBuildings, .scopeExcludedDepartments:
            true
        default: false
        }
    }

    /// Single server-defined entity (category or VPP account).
    var isNamedID: Bool {
        self == .category || self == .vppLocation
    }

    func appliesTo(_ catalog: AppCatalog) -> Bool {
        switch self {
        case .displayName: true
        case .appDescription: catalog == .mobileDevice
        case .deploymentType, .assignVPPDeviceBasedLicenses: true
        case .category, .vppLocation: true
        case .ssForceViewDescription: catalog == .mac
        case .ssButtonText, .ssDescription, .ssFeatureOnMainPage,
             .ssNotificationEnabled, .ssNotificationSubject, .ssNotificationMessage, .ssCategories:
            true
        case .scopeAllTargets, .scopeGroups, .scopeBuildings, .scopeDepartments,
             .scopeExcludedGroups, .scopeExcludedBuildings, .scopeExcludedDepartments:
            true
        default: catalog == .mobileDevice
        }
    }

    static func applicableKeys(for catalog: AppCatalog) -> [FieldKey] {
        allCases.filter { $0.appliesTo(catalog) }
    }

    /// The subset templates may carry (excludes per-app identity fields).
    static func templateKeys(for catalog: AppCatalog) -> [FieldKey] {
        applicableKeys(for: catalog).filter(\.includeInTemplates)
    }
}

enum TemplateValue: Codable, Hashable, Sendable {
    case bool(Bool)
    case string(String)
    case namedIDs([NamedID])
    case namedID(NamedID)
    case ssCategories([SelfServiceCategory])

    var displayValue: String {
        switch self {
        case .bool(let value): value ? "Yes" : "No"
        case .string(let value): value.isEmpty ? "—" : value
        case .namedIDs(let items):
            items.isEmpty ? "None" : items.map { $0.name ?? "ID \($0.id)" }.joined(separator: ", ")
        case .namedID(let item):
            item.id == -1 ? "None" : (item.name ?? "ID \(item.id)")
        case .ssCategories(let items):
            items.isEmpty ? "None" : items.map {
                ($0.name ?? "ID \($0.id)") + ($0.featureIn == true ? " (featured)" : "")
            }.joined(separator: ", ")
        }
    }
}

/// A reusable, field-masked set of app settings: only the fields present in
/// `fields` are applied — everything else on the target app is untouched.
struct SettingsTemplate: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var catalog: AppCatalog
    var fields: [FieldKey: TemplateValue] = [:]

    /// Fields in stable UI order.
    var orderedKeys: [FieldKey] {
        FieldKey.applicableKeys(for: catalog).filter { fields[$0] != nil }
    }

    /// Default value used when a field is first included in the editor.
    static func defaultValue(for key: FieldKey) -> TemplateValue {
        if key.isNamedIDList { return .namedIDs([]) }
        if key.isNamedID { return .namedID(NamedID(id: -1, name: "None")) }
        if key == .ssCategories { return .ssCategories([]) }
        if key == .scopeAllTargets { return .bool(false) }
        if key.isBool { return .bool(true) }
        if key == .deploymentType { return .string(AppEditor.deploymentTypeOptions[0]) }
        return .string("")
    }
}