// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The two Jamf Pro app catalogs this tool manages.
enum AppCatalog: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case mac
    case mobileDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mobileDevice: "Mobile Device Apps"
        case .mac: "Mac Apps"
        }
    }

    var systemImage: String {
        switch self {
        case .mobileDevice: "ipad.and.iphone"
        case .mac: "macbook"
        }
    }

    /// Classic API collection path.
    var classicPath: String {
        switch self {
        case .mobileDevice: "mobiledeviceapplications"
        case .mac: "macapplications"
        }
    }

    /// Top-level key wrapping the collection in Classic API JSON responses.
    var collectionKey: String {
        switch self {
        case .mobileDevice: "mobile_device_applications"
        case .mac: "mac_applications"
        }
    }

    /// Top-level key wrapping a single record in Classic API JSON responses.
    var recordKey: String {
        switch self {
        case .mobileDevice: "mobile_device_application"
        case .mac: "mac_application"
        }
    }
}