// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One block of help prose. Kept as data rather than a web view so the text is
/// selectable, searchable and themed like the rest of the app.
enum HelpBlock: Hashable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    case code(String)
    case note(String)
    case warning(String)
}

struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    let blocks: [HelpBlock]
}

enum HelpBook {
    static let topics: [HelpTopic] = [
        gettingStarted, apiPermissions, editing, templates, csv, appCatalog,
        limitations, license,
    ]

    static func topic(id: String) -> HelpTopic {
        topics.first { $0.id == id } ?? gettingStarted
    }

    // MARK: -

    static let gettingStarted = HelpTopic(
        id: "getting-started",
        title: "Getting Started",
        symbol: "sparkles",
        summary: "Connect once, then browse and edit every app catalog.",
        blocks: [
            .paragraph("Jamf App Manager talks to Jamf Pro through an API client — the same modern authentication Jamf recommends for every integration. Nothing is installed on your server and nothing runs in the background: the app reads records when you look at them and writes only when you confirm a change."),
            .heading("Connecting"),
            .bullets([
                "In Jamf Pro, create an API role and client under Settings → System → API Roles and Clients (the exact privileges are listed in the API Permissions topic).",
                "Enter your server URL, client ID and client secret on the connect screen. The secret is stored in your login Keychain, never on disk.",
                "On an enrolled Mac the server URL is prefilled from the machine's own MDM enrollment.",
                "You can save several servers and switch between them from the toolbar's server menu.",
            ]),
            .heading("Browsing"),
            .bullets([
                "Mac Apps covers both the App Store catalog and Jamf App Catalog (App Installers) deployments — switch with the tabs above the list.",
                "Mobile Device Apps covers iOS and iPadOS App Store apps.",
                "Search matches names and bundle identifiers. ⌘R refreshes the list from the server.",
                "Records are cached for the session: reopening an app is instant, and the Refresh button in the detail view re-fetches it.",
            ]),
        ]
    )

    static let apiPermissions = HelpTopic(
        id: "api-permissions",
        title: "API Permissions",
        symbol: "key",
        summary: "The exact privileges the API role needs — nothing more.",
        blocks: [
            .paragraph("Create an API role with these privileges (Settings → System → API Roles and Clients → API Roles). The names below are exactly as they appear in Jamf Pro's privilege picker."),
            .heading("To browse (read-only)"),
            .bullets([
                "Read Mac Applications",
                "Read Mobile Device Applications",
                "Read Smart Computer Groups and Read Static Computer Groups",
                "Read Smart Mobile Device Groups and Read Static Mobile Device Groups",
                "Read Buildings",
                "Read Departments",
                "Read Categories",
                "Read Volume Purchasing Locations",
            ]),
            .heading("To save changes"),
            .bullets([
                "Update Mac Applications",
                "Update Mobile Device Applications",
            ]),
            .note("Groups, buildings, departments, categories and volume purchasing locations only ever need Read — the app references them in scopes and pickers but never modifies them."),
            .paragraph("Jamf App Catalog (App Installers) deployments have no privilege of their own anywhere in Jamf's privilege catalog; their endpoints are governed by the Mac Applications privileges above."),
            .paragraph("A useful rollout pattern: start with a read-only role to evaluate safely — the app works fully as a browser — and add the two Update privileges when you're ready to write."),
        ]
    )

    static let editing = HelpTopic(
        id: "editing",
        title: "Editing & Review",
        symbol: "pencil.line",
        summary: "Every write is a reviewed diff of exactly what changes.",
        blocks: [
            .paragraph("Edit fields directly in the detail tabs — General, Scope, Self Service, Managed Distribution, and (for mobile device apps) App Configuration. Changes are tracked against the server's values: an orange pencil badge marks each edited app in the list, and a Review Changes button appears above the list the moment anything in the catalog differs."),
            .heading("The review gate"),
            .bullets([
                "Review Changes gathers every app with unsaved edits in the current catalog into one sheet.",
                "Each app has a checkbox — uncheck any you want to hold back; they keep their edits for a later push.",
                "Expand an app to see each field as old → new, plus the raw XML that will be sent.",
                "Only changed fields are transmitted (a field-masked partial update), so settings you never touched cannot be clobbered.",
                "Nothing reaches the server until you press Apply, and apps are written one at a time with live per-app results.",
            ]),
            .heading("Unsaved edits"),
            .bullets([
                "Edits survive switching between apps — pile up changes across the catalog, then push once.",
                "Discard (in an app's detail view) reloads that record from the server and throws its edits away.",
                "Scope lists are replacements: applying a new group list sets it exactly, it does not merge.",
            ]),
        ]
    )

    static let templates = HelpTopic(
        id: "templates",
        title: "Templates",
        symbol: "square.on.square.dashed",
        summary: "A reusable set of settings applied to many apps at once.",
        blocks: [
            .paragraph("A template carries only the fields you check — everything else on the target app stays untouched. Build one by hand in the Templates section, or capture a configured app with Save Settings as Template from its detail view and trim the fields afterwards."),
            .heading("Applying"),
            .bullets([
                "Select several apps in a list (⌘-click or ⇧-click) and pick a template from the Apply Template menu.",
                "Every selected app is staged first: fetched fresh, the template overlaid, and the real differences shown per app.",
                "Apps that already match show as “Already matches” and are skipped.",
                "One confirmation applies the rest, written one at a time with live per-app results.",
            ]),
            .note("Per-app identity fields (display name, description) are deliberately not template fields — a template would stamp the same name on every target. Use CSV for per-app values."),
        ]
    )

    static let csv = HelpTopic(
        id: "csv",
        title: "CSV Import & Export",
        symbol: "tablecells",
        summary: "Bulk-edit in a spreadsheet; every row is diffed before writing.",
        blocks: [
            .paragraph("The CSV menu above each list exports the current settings of all (or selected) apps, and imports a file back. The dependable workflow is export → edit cells → re-import: an unedited export re-imports as a no-op."),
            .heading("Format"),
            .bullets([
                "Header row, one row per app. Identifier columns: id, bundle_id, or name (at least one).",
                "Setting columns take field names (deployAsManagedApp, scopeGroups, category, ssButtonText, …) or their UI labels.",
                "Empty cells leave that field untouched, so sparse sheets are safe.",
                "Booleans accept true/false, yes/no, 1/0.",
            ]),
            .heading("Special columns"),
            .code("scopeGroups        All iPads; #22\ncategory           Productivity   (or #id, or None to clear)\nssCategories       Applications; Maintenance*   (* = featured)"),
            .paragraph("Rows that fail — unknown app, bad value, unknown group name — appear in the preview as errors with their row numbers; valid rows still stage normally. Nothing is written until the single confirmation."),
        ]
    )

    static let appCatalog = HelpTopic(
        id: "app-catalog",
        title: "Jamf App Catalog",
        symbol: "shippingbox",
        summary: "App Installers deployments, editable with the same review gate.",
        blocks: [
            .paragraph("The Jamf App Catalog tab under Mac Apps lists App Installers deployments — Jamf's own managed installer pipeline. The detail view edits the deployment: enabled, deployment type, update behavior, category, smart group, config-profile and notification switches, and Self Service settings."),
            .bullets([
                "Writes go to the Jamf Pro API as a full JSON document; the review sheet shows exactly what is sent.",
                "Settings the editor doesn't cover (notification timing details) pass through unchanged.",
                "Deployments can only target smart computer groups — that's a Jamf App Installers rule, not an app limitation.",
                "Install-status counts (installed, in progress, failed) come straight from the deployment record.",
            ]),
        ]
    )

    static let limitations = HelpTopic(
        id: "limitations",
        title: "What Can't Be Edited",
        symbol: "lock",
        summary: "Fields Jamf keeps outside its public APIs.",
        blocks: [
            .paragraph("A few things visible in the Jamf Pro web interface have no representation in either public API, so no external tool — this app, The MUT, or anything else — can change them. They are shown (or footnoted) as read-only:"),
            .bullets([
                "Mac App Store apps: Enabled, “Schedule Jamf Pro to check the App Store for updates” (including country and sync time), “Automatically force app updates”, and the Force Update button.",
                "App Configuration for Mac App Store apps — the feature doesn't exist in Jamf for Mac apps at all; deliver managed settings with a configuration profile instead.",
                "Self Service icons (uploading needs a separate multipart endpoint the app doesn't use yet).",
                "Scope limitations (users, network segments) and one-off device/computer scope entries are displayed read-only; groups, buildings and departments are fully editable.",
            ]),
            .note("These were verified against a live Jamf Pro instance by diffing records before and after changing the fields in the web UI, and by searching the full Pro API schema."),
        ]
    )

    static let license = HelpTopic(
        id: "license",
        title: "License",
        symbol: "doc.text",
        summary: "Apache License 2.0, © 2026 Vantine Imaging LLC.",
        blocks: [
            .paragraph("Jamf App Manager is copyright 2026 Vantine Imaging LLC and is licensed under the Apache License, Version 2.0."),
            .paragraph("You may use, modify and redistribute it, including commercially, provided you keep the copyright and license notices and state any changes you make. It is provided without warranty of any kind."),
            .paragraph("The full license text ships in the repository as LICENSE, with the accompanying attribution notice in NOTICE."),
        ]
    )
}
