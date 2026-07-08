import Foundation
import Observation

/// One pending edit: where it lands in the Classic XML, and how to show it
/// to the user in the review sheet.
struct FieldChange: Identifiable, Hashable, Sendable {
    var section: String        // XML parent element, e.g. "general"
    var element: String        // XML element name
    var label: String          // human-readable field name
    var oldDisplay: String
    var newDisplay: String
    var xmlValue: String       // inner XML, already escaped/CDATA-wrapped

    var id: String { "\(section)/\(element)" }
}

func xmlEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

/// Editable working copy of one app record. Tracks which fields differ from
/// the server's values and builds the minimal partial-update XML for a
/// Classic API PUT — untouched fields are never sent.
@MainActor
@Observable
final class AppEditor {
    let catalog: AppCatalog
    let appID: Int

    // Mobile-only general fields
    var displayName: String
    var appDescription: String
    var deployAutomatically: Bool
    var deployAsManagedApp: Bool
    var removeAppWhenMDMProfileIsRemoved: Bool
    var preventBackupOfAppData: Bool
    var allowUserToDelete: Bool
    var requireNetworkTethered: Bool
    var keepAppUpdatedOnDevices: Bool
    var keepDescriptionAndIconUpToDate: Bool
    var makeAvailableAfterInstall: Bool
    var takeOverManagement: Bool

    // Shared
    var deploymentType: String
    var assignVPPDeviceBasedLicenses: Bool
    var appConfigurationPreferences: String
    var category: NamedID?
    var vppAccountID: Int
    /// Display-only name for the picked VPP account (not compared).
    var vppAccountName: String?

    // Self Service
    var ssButtonText: String
    var ssDescription: String
    var ssForceViewDescription: Bool   // Mac only
    var ssFeatureOnMainPage: Bool
    var ssNotificationEnabled: Bool
    var ssNotificationSubject: String
    var ssNotificationMessage: String
    var ssCategories: [SelfServiceCategory]

    // Scope. Lists use replacement semantics: the PUT sends the complete new
    // list for any changed category.
    var scopeAllTargets: Bool
    var scopeGroups: [NamedID]
    var scopeBuildings: [NamedID]
    var scopeDepartments: [NamedID]
    var scopeExcludedGroups: [NamedID]
    var scopeExcludedBuildings: [NamedID]
    var scopeExcludedDepartments: [NamedID]

    /// Whether this record supports the App Configuration tab (the Classic
    /// API only returns it for mobile device apps).
    let supportsAppConfiguration: Bool

    private struct Original {
        var displayName = ""
        var appDescription = ""
        var deployAutomatically = false
        var deployAsManagedApp = false
        var removeAppWhenMDMProfileIsRemoved = false
        var preventBackupOfAppData = false
        var allowUserToDelete = false
        var requireNetworkTethered = false
        var keepAppUpdatedOnDevices = false
        var keepDescriptionAndIconUpToDate = false
        var makeAvailableAfterInstall = false
        var takeOverManagement = false
        var deploymentType = ""
        var assignVPPDeviceBasedLicenses = false
        var appConfigurationPreferences = ""
        var scopeAllTargets = false
        var scopeGroups: [NamedID] = []
        var scopeBuildings: [NamedID] = []
        var scopeDepartments: [NamedID] = []
        var scopeExcludedGroups: [NamedID] = []
        var scopeExcludedBuildings: [NamedID] = []
        var scopeExcludedDepartments: [NamedID] = []
        var category: NamedID?
        var vppAccountID = -1
        var ssButtonText = ""
        var ssDescription = ""
        var ssForceViewDescription = false
        var ssFeatureOnMainPage = false
        var ssNotificationEnabled = false
        var ssNotificationSubject = ""
        var ssNotificationMessage = ""
        var ssCategories: [SelfServiceCategory] = []

        mutating func fill(from selfService: SelfServiceInfo?) {
            ssButtonText = selfService?.installButtonText ?? ""
            ssDescription = selfService?.description ?? ""
            ssForceViewDescription = selfService?.forceUsersToViewDescription ?? false
            ssFeatureOnMainPage = selfService?.featureOnMainPage ?? false
            ssNotificationEnabled = selfService?.notificationEnabled ?? false
            ssNotificationSubject = selfService?.notificationSubject ?? ""
            ssNotificationMessage = selfService?.notificationMessage ?? ""
            ssCategories = selfService?.categories ?? []
        }
    }

    private let original: Original

    nonisolated static let deploymentTypeOptions = [
        "Install Automatically/Prompt Users to Install",
        "Make Available in Self Service",
    ]

    init(mobile detail: MobileDeviceAppDetail) {
        catalog = .mobileDevice
        appID = detail.general.id
        supportsAppConfiguration = true
        let general = detail.general
        var orig = Original()
        orig.displayName = general.displayName ?? ""
        orig.appDescription = general.description ?? ""
        orig.deployAutomatically = general.deployAutomatically ?? false
        orig.deployAsManagedApp = general.deployAsManagedApp ?? false
        orig.removeAppWhenMDMProfileIsRemoved = general.removeAppWhenMDMProfileIsRemoved ?? false
        orig.preventBackupOfAppData = general.preventBackupOfAppData ?? false
        orig.allowUserToDelete = general.allowUserToDelete ?? false
        orig.requireNetworkTethered = general.requireNetworkTethered ?? false
        orig.keepAppUpdatedOnDevices = general.keepAppUpdatedOnDevices ?? false
        orig.keepDescriptionAndIconUpToDate = general.keepDescriptionAndIconUpToDate ?? false
        orig.makeAvailableAfterInstall = general.makeAvailableAfterInstall ?? false
        orig.takeOverManagement = general.takeOverManagement ?? false
        orig.deploymentType = general.deploymentType ?? ""
        orig.assignVPPDeviceBasedLicenses = detail.vpp?.assignVPPDeviceBasedLicenses ?? false
        orig.appConfigurationPreferences = detail.appConfiguration?.preferences ?? ""
        orig.scopeAllTargets = detail.scope?.allMobileDevices ?? false
        orig.scopeGroups = detail.scope?.mobileDeviceGroups ?? []
        orig.scopeBuildings = detail.scope?.buildings ?? []
        orig.scopeDepartments = detail.scope?.departments ?? []
        orig.scopeExcludedGroups = detail.scope?.exclusions?.mobileDeviceGroups ?? []
        orig.scopeExcludedBuildings = detail.scope?.exclusions?.buildings ?? []
        orig.scopeExcludedDepartments = detail.scope?.exclusions?.departments ?? []
        orig.category = general.category
        orig.vppAccountID = detail.vpp?.vppAdminAccountID ?? -1
        orig.fill(from: detail.selfService)
        original = orig

        displayName = orig.displayName
        appDescription = orig.appDescription
        deployAutomatically = orig.deployAutomatically
        deployAsManagedApp = orig.deployAsManagedApp
        removeAppWhenMDMProfileIsRemoved = orig.removeAppWhenMDMProfileIsRemoved
        preventBackupOfAppData = orig.preventBackupOfAppData
        allowUserToDelete = orig.allowUserToDelete
        requireNetworkTethered = orig.requireNetworkTethered
        keepAppUpdatedOnDevices = orig.keepAppUpdatedOnDevices
        keepDescriptionAndIconUpToDate = orig.keepDescriptionAndIconUpToDate
        makeAvailableAfterInstall = orig.makeAvailableAfterInstall
        takeOverManagement = orig.takeOverManagement
        deploymentType = orig.deploymentType
        assignVPPDeviceBasedLicenses = orig.assignVPPDeviceBasedLicenses
        appConfigurationPreferences = orig.appConfigurationPreferences
        category = orig.category
        vppAccountID = orig.vppAccountID
        ssButtonText = orig.ssButtonText
        ssDescription = orig.ssDescription
        ssForceViewDescription = orig.ssForceViewDescription
        ssFeatureOnMainPage = orig.ssFeatureOnMainPage
        ssNotificationEnabled = orig.ssNotificationEnabled
        ssNotificationSubject = orig.ssNotificationSubject
        ssNotificationMessage = orig.ssNotificationMessage
        ssCategories = orig.ssCategories
        scopeAllTargets = orig.scopeAllTargets
        scopeGroups = orig.scopeGroups
        scopeBuildings = orig.scopeBuildings
        scopeDepartments = orig.scopeDepartments
        scopeExcludedGroups = orig.scopeExcludedGroups
        scopeExcludedBuildings = orig.scopeExcludedBuildings
        scopeExcludedDepartments = orig.scopeExcludedDepartments
    }

    init(mac detail: MacAppDetail) {
        catalog = .mac
        appID = detail.general.id
        supportsAppConfiguration = false
        var orig = Original()
        // Mac apps have no display_name in the Classic API; the web UI's
        // "Display Name" field maps to `name`.
        orig.displayName = detail.general.name ?? ""
        orig.deploymentType = detail.general.deploymentType ?? ""
        orig.assignVPPDeviceBasedLicenses = detail.vpp?.assignVPPDeviceBasedLicenses ?? false
        orig.scopeAllTargets = detail.scope?.allComputers ?? false
        orig.scopeGroups = detail.scope?.computerGroups ?? []
        orig.scopeBuildings = detail.scope?.buildings ?? []
        orig.scopeDepartments = detail.scope?.departments ?? []
        orig.scopeExcludedGroups = detail.scope?.exclusions?.computerGroups ?? []
        orig.scopeExcludedBuildings = detail.scope?.exclusions?.buildings ?? []
        orig.scopeExcludedDepartments = detail.scope?.exclusions?.departments ?? []
        orig.category = detail.general.category
        orig.vppAccountID = detail.vpp?.vppAdminAccountID ?? -1
        orig.fill(from: detail.selfService)
        original = orig

        displayName = orig.displayName
        appDescription = ""
        deployAutomatically = false
        deployAsManagedApp = false
        removeAppWhenMDMProfileIsRemoved = false
        preventBackupOfAppData = false
        allowUserToDelete = false
        requireNetworkTethered = false
        keepAppUpdatedOnDevices = false
        keepDescriptionAndIconUpToDate = false
        makeAvailableAfterInstall = false
        takeOverManagement = false
        deploymentType = orig.deploymentType
        assignVPPDeviceBasedLicenses = orig.assignVPPDeviceBasedLicenses
        appConfigurationPreferences = ""
        category = orig.category
        vppAccountID = orig.vppAccountID
        ssButtonText = orig.ssButtonText
        ssDescription = orig.ssDescription
        ssForceViewDescription = orig.ssForceViewDescription
        ssFeatureOnMainPage = orig.ssFeatureOnMainPage
        ssNotificationEnabled = orig.ssNotificationEnabled
        ssNotificationSubject = orig.ssNotificationSubject
        ssNotificationMessage = orig.ssNotificationMessage
        ssCategories = orig.ssCategories
        scopeAllTargets = orig.scopeAllTargets
        scopeGroups = orig.scopeGroups
        scopeBuildings = orig.scopeBuildings
        scopeDepartments = orig.scopeDepartments
        scopeExcludedGroups = orig.scopeExcludedGroups
        scopeExcludedBuildings = orig.scopeExcludedBuildings
        scopeExcludedDepartments = orig.scopeExcludedDepartments
    }

    // MARK: - Change tracking

    var changes: [FieldChange] {
        var result: [FieldChange] = []

        func string(_ label: String, _ element: String, _ old: String, _ new: String, section: String = "general") {
            guard old != new else { return }
            result.append(FieldChange(
                section: section, element: element, label: label,
                oldDisplay: old.isEmpty ? "—" : old,
                newDisplay: new.isEmpty ? "—" : new,
                xmlValue: xmlEscaped(new)
            ))
        }
        func bool(_ label: String, _ element: String, _ old: Bool, _ new: Bool, section: String = "general") {
            guard old != new else { return }
            result.append(FieldChange(
                section: section, element: element, label: label,
                oldDisplay: old ? "Yes" : "No",
                newDisplay: new ? "Yes" : "No",
                xmlValue: new ? "true" : "false"
            ))
        }

        // Mac apps carry the display name in `name`; mobile apps in `display_name`.
        string("Display Name", catalog == .mac ? "name" : "display_name",
               original.displayName, displayName)

        if catalog == .mobileDevice {
            string("Description", "description", original.appDescription, appDescription)
            bool("Deploy Automatically", "deploy_automatically", original.deployAutomatically, deployAutomatically)
            bool("Deploy as Managed App", "deploy_as_managed_app", original.deployAsManagedApp, deployAsManagedApp)
            bool("Remove with MDM Profile", "remove_app_when_mdm_profile_is_removed", original.removeAppWhenMDMProfileIsRemoved, removeAppWhenMDMProfileIsRemoved)
            bool("Prevent Backup of App Data", "prevent_backup_of_app_data", original.preventBackupOfAppData, preventBackupOfAppData)
            bool("Allow User to Delete", "allow_user_to_delete", original.allowUserToDelete, allowUserToDelete)
            bool("Require Network Tethered", "require_network_tethered", original.requireNetworkTethered, requireNetworkTethered)
            bool("Keep App Updated on Devices", "keep_app_updated_on_devices", original.keepAppUpdatedOnDevices, keepAppUpdatedOnDevices)
            bool("Keep Description & Icon Up to Date", "keep_description_and_icon_up_to_date", original.keepDescriptionAndIconUpToDate, keepDescriptionAndIconUpToDate)
            bool("Make Available After Install", "make_available_after_install", original.makeAvailableAfterInstall, makeAvailableAfterInstall)
            bool("Take Over Management", "take_over_management", original.takeOverManagement, takeOverManagement)
        }

        string("Deployment Type", "deployment_type", original.deploymentType, deploymentType)
        bool("Assign Device-Based Licenses", "assign_vpp_device_based_licenses",
             original.assignVPPDeviceBasedLicenses, assignVPPDeviceBasedLicenses, section: "vpp")

        if (original.category?.id ?? -1) != (category?.id ?? -1), let category {
            result.append(FieldChange(
                section: "general", element: "category", label: "Category",
                oldDisplay: original.category?.name ?? "None",
                newDisplay: category.name ?? "ID \(category.id)",
                xmlValue: "<id>\(category.id)</id>"
            ))
        }
        if vppAccountID != original.vppAccountID, vppAccountID > 0 {
            result.append(FieldChange(
                section: "vpp", element: "vpp_admin_account_id", label: "VPP Location",
                oldDisplay: original.vppAccountID > 0 ? "ID \(original.vppAccountID)" : "None",
                newDisplay: vppAccountName ?? "ID \(vppAccountID)",
                xmlValue: String(vppAccountID)
            ))
        }

        // Self Service. Key spellings and the notification wire format
        // differ per catalog (string on Mac, bool on mobile).
        string("Self Service Button Text",
               catalog == .mac ? "install_button_text" : "self_service_install_button_text",
               original.ssButtonText, ssButtonText, section: "self_service")
        string("Self Service Description", "self_service_description",
               original.ssDescription, ssDescription, section: "self_service")
        if catalog == .mac {
            bool("Force Users to View Description", "force_users_to_view_description",
                 original.ssForceViewDescription, ssForceViewDescription, section: "self_service")
        }
        bool("Feature on Main Page", "feature_on_main_page",
             original.ssFeatureOnMainPage, ssFeatureOnMainPage, section: "self_service")
        if original.ssNotificationEnabled != ssNotificationEnabled {
            result.append(FieldChange(
                section: "self_service", element: "notification", label: "Display Notifications",
                oldDisplay: original.ssNotificationEnabled ? "Yes" : "No",
                newDisplay: ssNotificationEnabled ? "Yes" : "No",
                xmlValue: catalog == .mac
                    ? (ssNotificationEnabled ? "Self Service Plus Notification" : "Self Service")
                    : (ssNotificationEnabled ? "true" : "false")
            ))
        }
        string("Notification Subject", "notification_subject",
               original.ssNotificationSubject, ssNotificationSubject, section: "self_service")
        string("Notification Message", "notification_message",
               original.ssNotificationMessage, ssNotificationMessage, section: "self_service")

        func ssCategoryKey(_ items: [SelfServiceCategory]) -> Set<String> {
            Set(items.map { "\($0.id)|\($0.displayIn ?? true)|\($0.featureIn ?? false)" })
        }
        if ssCategoryKey(original.ssCategories) != ssCategoryKey(ssCategories) {
            func describe(_ items: [SelfServiceCategory]) -> String {
                items.isEmpty ? "None" : items.map { item in
                    (item.name ?? "ID \(item.id)") + (item.featureIn == true ? " (featured)" : "")
                }.joined(separator: ", ")
            }
            result.append(FieldChange(
                section: "self_service", element: "self_service_categories",
                label: "Self Service Categories",
                oldDisplay: describe(original.ssCategories),
                newDisplay: describe(ssCategories),
                xmlValue: ssCategories.map {
                    "<category><id>\($0.id)</id><display_in>\($0.displayIn ?? true)</display_in><feature_in>\($0.featureIn ?? false)</feature_in></category>"
                }.joined()
            ))
        }

        // Scope. Element names differ per catalog; lists are full replacements.
        func namedList(_ label: String, _ element: String, _ singular: String,
                       _ old: [NamedID], _ new: [NamedID], section: String) {
            guard Set(old.map(\.id)) != Set(new.map(\.id)) else { return }
            func describe(_ items: [NamedID]) -> String {
                items.isEmpty ? "None" : items.compactMap { $0.name ?? "ID \($0.id)" }.joined(separator: ", ")
            }
            result.append(FieldChange(
                section: section, element: element, label: label,
                oldDisplay: describe(old),
                newDisplay: describe(new),
                xmlValue: new.map { "<\(singular)><id>\($0.id)</id></\(singular)>" }.joined()
            ))
        }

        let allElement = catalog == .mobileDevice ? "all_mobile_devices" : "all_computers"
        let groupsElement = catalog == .mobileDevice ? "mobile_device_groups" : "computer_groups"
        let groupSingular = catalog == .mobileDevice ? "mobile_device_group" : "computer_group"
        let allLabel = catalog == .mobileDevice ? "Scope: All Mobile Devices" : "Scope: All Computers"

        bool(allLabel, allElement, original.scopeAllTargets, scopeAllTargets, section: "scope")
        namedList("Scoped Groups", groupsElement, groupSingular,
                  original.scopeGroups, scopeGroups, section: "scope")
        namedList("Scoped Buildings", "buildings", "building",
                  original.scopeBuildings, scopeBuildings, section: "scope")
        namedList("Scoped Departments", "departments", "department",
                  original.scopeDepartments, scopeDepartments, section: "scope")
        namedList("Excluded Groups", groupsElement, groupSingular,
                  original.scopeExcludedGroups, scopeExcludedGroups, section: "scope.exclusions")
        namedList("Excluded Buildings", "buildings", "building",
                  original.scopeExcludedBuildings, scopeExcludedBuildings, section: "scope.exclusions")
        namedList("Excluded Departments", "departments", "department",
                  original.scopeExcludedDepartments, scopeExcludedDepartments, section: "scope.exclusions")

        if supportsAppConfiguration,
           original.appConfigurationPreferences != appConfigurationPreferences {
            result.append(FieldChange(
                section: "app_configuration", element: "preferences",
                label: "App Configuration",
                oldDisplay: original.appConfigurationPreferences.isEmpty ? "(empty)" : original.appConfigurationPreferences,
                newDisplay: appConfigurationPreferences.isEmpty ? "(empty)" : appConfigurationPreferences,
                xmlValue: "<![CDATA[\(appConfigurationPreferences)]]>"
            ))
        }

        return result
    }

    var hasChanges: Bool { !changes.isEmpty }

    /// Validates the App Configuration field parses as a plist fragment.
    /// Returns an error message, or nil when valid (or unchanged/empty).
    func appConfigurationValidationError() -> String? {
        guard supportsAppConfiguration else { return nil }
        let preferences = appConfigurationPreferences.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preferences.isEmpty,
              preferences != original.appConfigurationPreferences.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        \(preferences)
        </plist>
        """
        do {
            _ = try PropertyListSerialization.propertyList(from: Data(document.utf8), format: nil)
            return nil
        } catch {
            return "App Configuration is not a valid plist fragment. It should be a single <dict>…</dict>."
        }
    }

    // MARK: - XML

    /// Builds the minimal partial-update XML containing only changed fields.
    /// Scope exclusions nest inside <scope>; all other sections are flat.
    func buildUpdateXML() -> String {
        let root = catalog == .mobileDevice ? "mobile_device_application" : "mac_application"
        let allChanges = changes

        func elements(in section: String) -> String {
            allChanges
                .filter { $0.section == section }
                .map { "<\($0.element)>\($0.xmlValue)</\($0.element)>" }
                .joined()
        }

        var body = ""
        for section in ["general", "vpp", "self_service", "app_configuration"] {
            let inner = elements(in: section)
            if !inner.isEmpty { body += "<\(section)>\(inner)</\(section)>" }
        }
        let scopeInner = elements(in: "scope")
        let exclusionsInner = elements(in: "scope.exclusions")
        if !scopeInner.isEmpty || !exclusionsInner.isEmpty {
            var inner = scopeInner
            if !exclusionsInner.isEmpty { inner += "<exclusions>\(exclusionsInner)</exclusions>" }
            body += "<scope>\(inner)</scope>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><\(root)>\(body)</\(root)>"
    }

    /// Classic API path this record is updated at.
    var updatePath: String {
        "JSSResource/\(catalog.classicPath)/id/\(appID)"
    }

    // MARK: - Templates

    func value(for key: FieldKey) -> TemplateValue {
        switch key {
        case .displayName: .string(displayName)
        case .appDescription: .string(appDescription)
        case .deploymentType: .string(deploymentType)
        case .deployAutomatically: .bool(deployAutomatically)
        case .deployAsManagedApp: .bool(deployAsManagedApp)
        case .removeAppWhenMDMProfileIsRemoved: .bool(removeAppWhenMDMProfileIsRemoved)
        case .preventBackupOfAppData: .bool(preventBackupOfAppData)
        case .allowUserToDelete: .bool(allowUserToDelete)
        case .requireNetworkTethered: .bool(requireNetworkTethered)
        case .keepAppUpdatedOnDevices: .bool(keepAppUpdatedOnDevices)
        case .keepDescriptionAndIconUpToDate: .bool(keepDescriptionAndIconUpToDate)
        case .makeAvailableAfterInstall: .bool(makeAvailableAfterInstall)
        case .takeOverManagement: .bool(takeOverManagement)
        case .assignVPPDeviceBasedLicenses: .bool(assignVPPDeviceBasedLicenses)
        case .appConfigurationPreferences: .string(appConfigurationPreferences)
        case .category: .namedID(category ?? NamedID(id: -1, name: "None"))
        case .vppLocation: .namedID(NamedID(id: vppAccountID, name: vppAccountName))
        case .ssButtonText: .string(ssButtonText)
        case .ssDescription: .string(ssDescription)
        case .ssForceViewDescription: .bool(ssForceViewDescription)
        case .ssFeatureOnMainPage: .bool(ssFeatureOnMainPage)
        case .ssNotificationEnabled: .bool(ssNotificationEnabled)
        case .ssNotificationSubject: .string(ssNotificationSubject)
        case .ssNotificationMessage: .string(ssNotificationMessage)
        case .ssCategories: .ssCategories(ssCategories)
        case .scopeAllTargets: .bool(scopeAllTargets)
        case .scopeGroups: .namedIDs(scopeGroups)
        case .scopeBuildings: .namedIDs(scopeBuildings)
        case .scopeDepartments: .namedIDs(scopeDepartments)
        case .scopeExcludedGroups: .namedIDs(scopeExcludedGroups)
        case .scopeExcludedBuildings: .namedIDs(scopeExcludedBuildings)
        case .scopeExcludedDepartments: .namedIDs(scopeExcludedDepartments)
        }
    }

    func setValue(_ value: TemplateValue, for key: FieldKey) {
        switch (key, value) {
        case (.displayName, .string(let string)): displayName = string
        case (.appDescription, .string(let string)): appDescription = string
        case (.deploymentType, .string(let string)): deploymentType = string
        case (.deployAutomatically, .bool(let bool)): deployAutomatically = bool
        case (.deployAsManagedApp, .bool(let bool)): deployAsManagedApp = bool
        case (.removeAppWhenMDMProfileIsRemoved, .bool(let bool)): removeAppWhenMDMProfileIsRemoved = bool
        case (.preventBackupOfAppData, .bool(let bool)): preventBackupOfAppData = bool
        case (.allowUserToDelete, .bool(let bool)): allowUserToDelete = bool
        case (.requireNetworkTethered, .bool(let bool)): requireNetworkTethered = bool
        case (.keepAppUpdatedOnDevices, .bool(let bool)): keepAppUpdatedOnDevices = bool
        case (.keepDescriptionAndIconUpToDate, .bool(let bool)): keepDescriptionAndIconUpToDate = bool
        case (.makeAvailableAfterInstall, .bool(let bool)): makeAvailableAfterInstall = bool
        case (.takeOverManagement, .bool(let bool)): takeOverManagement = bool
        case (.assignVPPDeviceBasedLicenses, .bool(let bool)): assignVPPDeviceBasedLicenses = bool
        case (.appConfigurationPreferences, .string(let string)): appConfigurationPreferences = string
        case (.category, .namedID(let item)): category = item
        case (.vppLocation, .namedID(let item)):
            if item.id > 0 {
                vppAccountID = item.id
                vppAccountName = item.name
            }
        case (.ssButtonText, .string(let string)): ssButtonText = string
        case (.ssDescription, .string(let string)): ssDescription = string
        case (.ssForceViewDescription, .bool(let bool)): ssForceViewDescription = bool
        case (.ssFeatureOnMainPage, .bool(let bool)): ssFeatureOnMainPage = bool
        case (.ssNotificationEnabled, .bool(let bool)): ssNotificationEnabled = bool
        case (.ssNotificationSubject, .string(let string)): ssNotificationSubject = string
        case (.ssNotificationMessage, .string(let string)): ssNotificationMessage = string
        case (.ssCategories, .ssCategories(let items)): ssCategories = items
        case (.scopeAllTargets, .bool(let bool)): scopeAllTargets = bool
        case (.scopeGroups, .namedIDs(let items)): scopeGroups = items
        case (.scopeBuildings, .namedIDs(let items)): scopeBuildings = items
        case (.scopeDepartments, .namedIDs(let items)): scopeDepartments = items
        case (.scopeExcludedGroups, .namedIDs(let items)): scopeExcludedGroups = items
        case (.scopeExcludedBuildings, .namedIDs(let items)): scopeExcludedBuildings = items
        case (.scopeExcludedDepartments, .namedIDs(let items)): scopeExcludedDepartments = items
        default: break // mismatched value type; ignore rather than corrupt
        }
    }

    /// Overlays a template's included fields onto this record's working copy.
    /// Change tracking then reports exactly what would differ on the server.
    func apply(_ template: SettingsTemplate) {
        for key in template.orderedKeys where key.appliesTo(catalog) {
            if let value = template.fields[key] {
                setValue(value, for: key)
            }
        }
    }

    /// Captures the current working values as a new template with every
    /// template-eligible field included (per-app identity fields excluded).
    func makeTemplate(named name: String) -> SettingsTemplate {
        var template = SettingsTemplate(name: name, catalog: catalog)
        for key in FieldKey.templateKeys(for: catalog) {
            template.fields[key] = value(for: key)
        }
        return template
    }
}
