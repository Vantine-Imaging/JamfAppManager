// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The Help menu. Split out so it can pull `openWindow` out of the
/// environment, which command builders in the `App` body cannot.
struct HelpMenuItems: View {
    @Environment(HelpNavigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Jamf App Manager Help") { open(HelpBook.gettingStarted.id) }
            .keyboardShortcut("?", modifiers: .command)

        Divider()

        Button("API Permissions") { open(HelpBook.apiPermissions.id) }
        Button("Editing & Review") { open(HelpBook.editing.id) }
        Button("Templates") { open(HelpBook.templates.id) }
        Button("CSV Import & Export") { open(HelpBook.csv.id) }
        Button("Jamf App Catalog") { open(HelpBook.appCatalog.id) }
        Button("What Can't Be Edited") { open(HelpBook.limitations.id) }
        Button("License") { open(HelpBook.license.id) }
    }

    private func open(_ topic: String) {
        navigator.selection = topic
        openWindow(id: "help")
    }
}
