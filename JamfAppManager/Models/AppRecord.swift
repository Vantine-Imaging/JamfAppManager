// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

// Full app records from the Classic API. Every field beyond `id`/`name` is
// optional: Jamf omits keys depending on version, app type, and configuration,
// and this app must tolerate all of them on read. Writes are field-masked, so
// optionality never forces a value we didn't intend to send.

struct NamedID: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String?

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

/// The pickable entities a scope can reference, fetched per catalog.
struct ScopeOptions: Sendable {
    var groups: [NamedID] = []
    var buildings: [NamedID] = []
    var departments: [NamedID] = []
}

/// Decodes a NamedID list, tolerating Jamf's XML→JSON quirks: a proper array,
/// a bare single object, or `{}` for an empty XML element (as seen on
/// `mac_application.scope.mobile_device_groups`).
private func decodeNamedIDList<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>, _ key: K
) -> [NamedID]? {
    guard container.contains(key) else { return nil }
    if let array = try? container.decode([NamedID].self, forKey: key) { return array }
    if let single = try? container.decode(NamedID.self, forKey: key) { return [single] }
    return []
}

/// The Scope tab, shared by both catalogs (device/computer arrays differ by key).
struct AppScope: Decodable, Hashable, Sendable {
    var allMobileDevices: Bool?
    var allComputers: Bool?
    var allJSSUsers: Bool?
    var mobileDevices: [NamedID]?
    var mobileDeviceGroups: [NamedID]?
    var computers: [NamedID]?
    var computerGroups: [NamedID]?
    var buildings: [NamedID]?
    var departments: [NamedID]?
    var jssUsers: [NamedID]?
    var jssUserGroups: [NamedID]?
    var limitations: ScopeLimitations?
    var exclusions: ScopeExclusions?

    enum CodingKeys: String, CodingKey {
        case allMobileDevices = "all_mobile_devices"
        case allComputers = "all_computers"
        case allJSSUsers = "all_jss_users"
        case mobileDevices = "mobile_devices"
        case mobileDeviceGroups = "mobile_device_groups"
        case computers
        case computerGroups = "computer_groups"
        case buildings, departments
        case jssUsers = "jss_users"
        case jssUserGroups = "jss_user_groups"
        case limitations, exclusions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allMobileDevices = try container.decodeIfPresent(Bool.self, forKey: .allMobileDevices)
        allComputers = try container.decodeIfPresent(Bool.self, forKey: .allComputers)
        allJSSUsers = try container.decodeIfPresent(Bool.self, forKey: .allJSSUsers)
        mobileDevices = decodeNamedIDList(container, .mobileDevices)
        mobileDeviceGroups = decodeNamedIDList(container, .mobileDeviceGroups)
        computers = decodeNamedIDList(container, .computers)
        computerGroups = decodeNamedIDList(container, .computerGroups)
        buildings = decodeNamedIDList(container, .buildings)
        departments = decodeNamedIDList(container, .departments)
        jssUsers = decodeNamedIDList(container, .jssUsers)
        jssUserGroups = decodeNamedIDList(container, .jssUserGroups)
        limitations = try container.decodeIfPresent(ScopeLimitations.self, forKey: .limitations)
        exclusions = try container.decodeIfPresent(ScopeExclusions.self, forKey: .exclusions)
    }
}

struct ScopeLimitations: Decodable, Hashable, Sendable {
    var users: [NamedID]?
    var userGroups: [NamedID]?
    var networkSegments: [NamedID]?

    enum CodingKeys: String, CodingKey {
        case users
        case userGroups = "user_groups"
        case networkSegments = "network_segments"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = decodeNamedIDList(container, .users)
        userGroups = decodeNamedIDList(container, .userGroups)
        networkSegments = decodeNamedIDList(container, .networkSegments)
    }
}

struct ScopeExclusions: Decodable, Hashable, Sendable {
    var mobileDevices: [NamedID]?
    var mobileDeviceGroups: [NamedID]?
    var computers: [NamedID]?
    var computerGroups: [NamedID]?
    var buildings: [NamedID]?
    var departments: [NamedID]?
    var users: [NamedID]?
    var userGroups: [NamedID]?
    var networkSegments: [NamedID]?
    var jssUsers: [NamedID]?
    var jssUserGroups: [NamedID]?

    enum CodingKeys: String, CodingKey {
        case mobileDevices = "mobile_devices"
        case mobileDeviceGroups = "mobile_device_groups"
        case computers
        case computerGroups = "computer_groups"
        case buildings, departments, users
        case userGroups = "user_groups"
        case networkSegments = "network_segments"
        case jssUsers = "jss_users"
        case jssUserGroups = "jss_user_groups"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mobileDevices = decodeNamedIDList(container, .mobileDevices)
        mobileDeviceGroups = decodeNamedIDList(container, .mobileDeviceGroups)
        computers = decodeNamedIDList(container, .computers)
        computerGroups = decodeNamedIDList(container, .computerGroups)
        buildings = decodeNamedIDList(container, .buildings)
        departments = decodeNamedIDList(container, .departments)
        users = decodeNamedIDList(container, .users)
        userGroups = decodeNamedIDList(container, .userGroups)
        networkSegments = decodeNamedIDList(container, .networkSegments)
        jssUsers = decodeNamedIDList(container, .jssUsers)
        jssUserGroups = decodeNamedIDList(container, .jssUserGroups)
    }
}

/// The Managed Distribution tab. License counts are read-only server state.
struct VPPSettings: Decodable, Hashable, Sendable {
    var assignVPPDeviceBasedLicenses: Bool?
    var vppAdminAccountID: Int?
    var totalVPPLicenses: Int?
    var remainingVPPLicenses: Int?
    var usedVPPLicenses: Int?

    enum CodingKeys: String, CodingKey {
        case assignVPPDeviceBasedLicenses = "assign_vpp_device_based_licenses"
        case vppAdminAccountID = "vpp_admin_account_id"
        case totalVPPLicenses = "total_vpp_licenses"
        case remainingVPPLicenses = "remaining_vpp_licenses"
        case usedVPPLicenses = "used_vpp_licenses"
    }
}

/// The App Configuration tab — a plist-XML fragment.
struct AppConfiguration: Decodable, Hashable, Sendable {
    var preferences: String?
}

/// App icon reference (mobile apps carry it in general, Mac apps in
/// self_service).
struct IconRef: Decodable, Hashable, Sendable {
    var id: Int?
    var name: String?
    var uri: String?
}

struct SelfServiceCategory: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String?
    var displayIn: Bool?
    var featureIn: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name
        case displayIn = "display_in"
        case featureIn = "feature_in"
    }
}

/// The Self Service tab. Jamf spells several keys differently between the
/// two catalogs, and `notification` is a Bool on mobile apps but a string
/// ("Self Service" / "Self Service Plus Notification") on Mac apps — this
/// normalizes both on read; the editor re-serializes per catalog.
struct SelfServiceInfo: Decodable, Hashable, Sendable {
    var installButtonText: String?
    var description: String?
    var forceUsersToViewDescription: Bool?
    var featureOnMainPage: Bool?
    var categories: [SelfServiceCategory]?
    var notificationEnabled: Bool?
    var notificationSubject: String?
    var notificationMessage: String?
    var icon: IconRef?

    enum CodingKeys: String, CodingKey {
        case installButtonText = "install_button_text"
        case mobileInstallButtonText = "self_service_install_button_text"
        case description = "self_service_description"
        case forceUsersToViewDescription = "force_users_to_view_description"
        case featureOnMainPage = "feature_on_main_page"
        case categories = "self_service_categories"
        case notification
        case notificationSubject = "notification_subject"
        case notificationMessage = "notification_message"
        case icon = "self_service_icon"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installButtonText = (try? container.decode(String.self, forKey: .installButtonText))
            ?? (try? container.decode(String.self, forKey: .mobileInstallButtonText))
        description = try? container.decode(String.self, forKey: .description)
        forceUsersToViewDescription = try? container.decode(Bool.self, forKey: .forceUsersToViewDescription)
        featureOnMainPage = try? container.decode(Bool.self, forKey: .featureOnMainPage)
        categories = (try? container.decode(LossyArray<SelfServiceCategory>.self, forKey: .categories))?.elements
        if let flag = try? container.decode(Bool.self, forKey: .notification) {
            notificationEnabled = flag
        } else if let string = try? container.decode(String.self, forKey: .notification) {
            notificationEnabled = (string == "Self Service Plus Notification")
        }
        notificationSubject = try? container.decode(String.self, forKey: .notificationSubject)
        notificationMessage = try? container.decode(String.self, forKey: .notificationMessage)
        icon = try? container.decode(IconRef.self, forKey: .icon)
    }
}

/// A loaded Classic record from either catalog.
enum AppRecordDetail: Sendable {
    case mobileDevice(MobileDeviceAppDetail)
    case mac(MacAppDetail)

    var scope: AppScope? {
        switch self {
        case .mobileDevice(let app): app.scope
        case .mac(let app): app.scope
        }
    }

    var vpp: VPPSettings? {
        switch self {
        case .mobileDevice(let app): app.vpp
        case .mac(let app): app.vpp
        }
    }
}

/// General tab for a mobile device app.
struct MobileDeviceAppGeneral: Decodable, Hashable, Sendable {
    var id: Int
    var name: String?
    var displayName: String?
    var description: String?
    var bundleID: String?
    var version: String?
    var internalApp: Bool?
    var category: NamedID?
    var site: NamedID?
    var iTunesStoreURL: String?
    var iTunesCountryRegion: String?
    var icon: IconRef?
    var deploymentType: String?
    var deployAutomatically: Bool?
    var deployAsManagedApp: Bool?
    var removeAppWhenMDMProfileIsRemoved: Bool?
    var preventBackupOfAppData: Bool?
    var allowUserToDelete: Bool?
    var requireNetworkTethered: Bool?
    var keepDescriptionAndIconUpToDate: Bool?
    var keepAppUpdatedOnDevices: Bool?
    var free: Bool?
    var takeOverManagement: Bool?
    var hostExternally: Bool?
    var externalURL: String?
    var makeAvailableAfterInstall: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, free, icon
        case displayName = "display_name"
        case bundleID = "bundle_id"
        case internalApp = "internal_app"
        case category, site
        case iTunesStoreURL = "itunes_store_url"
        case iTunesCountryRegion = "itunes_country_region"
        case deploymentType = "deployment_type"
        case deployAutomatically = "deploy_automatically"
        case deployAsManagedApp = "deploy_as_managed_app"
        case removeAppWhenMDMProfileIsRemoved = "remove_app_when_mdm_profile_is_removed"
        case preventBackupOfAppData = "prevent_backup_of_app_data"
        case allowUserToDelete = "allow_user_to_delete"
        case requireNetworkTethered = "require_network_tethered"
        case keepDescriptionAndIconUpToDate = "keep_description_and_icon_up_to_date"
        case keepAppUpdatedOnDevices = "keep_app_updated_on_devices"
        case takeOverManagement = "take_over_management"
        case hostExternally = "host_externally"
        case externalURL = "external_url"
        case makeAvailableAfterInstall = "make_available_after_install"
    }
}

struct MobileDeviceAppDetail: Decodable, Sendable {
    var general: MobileDeviceAppGeneral
    var scope: AppScope?
    var vpp: VPPSettings?
    var appConfiguration: AppConfiguration?
    var selfService: SelfServiceInfo?

    enum CodingKeys: String, CodingKey {
        case general, scope, vpp
        case appConfiguration = "app_configuration"
        case selfService = "self_service"
    }
}

/// General tab for a Mac App Store app.
struct MacAppGeneral: Decodable, Hashable, Sendable {
    var id: Int
    var name: String?
    var displayName: String?
    var bundleID: String?
    var version: String?
    var url: String?
    var isFree: Bool?
    var category: NamedID?
    var site: NamedID?
    var deploymentType: String?

    enum CodingKeys: String, CodingKey {
        case id, name, version, url, category, site
        case displayName = "display_name"
        case bundleID = "bundle_id"
        case isFree = "is_free"
        case deploymentType = "deployment_type"
    }
}

struct MacAppDetail: Decodable, Sendable {
    var general: MacAppGeneral
    var scope: AppScope?
    var vpp: VPPSettings?
    var appConfiguration: AppConfiguration?
    var selfService: SelfServiceInfo?

    enum CodingKeys: String, CodingKey {
        case general, scope, vpp
        case appConfiguration = "app_configuration"
        case selfService = "self_service"
    }
}