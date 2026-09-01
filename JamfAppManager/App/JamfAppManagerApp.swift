// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
struct JamfAppManagerApp: App {
    @State private var session = SessionStore()
    @State private var templateStore = TemplateStore()
    @State private var rowInfoStore = RowInfoStore()
    @State private var recordStore = RecordStore()
    @State private var help = HelpNavigator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(templateStore)
                .environment(rowInfoStore)
                .environment(recordStore)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .help) {
                HelpMenuItems()
                    .environment(help)
            }
        }

        // Popped-out app detail windows (double-click a row, or the
        // "Detail in New Window" layout). One window per app; reopening the
        // same app fronts its existing window.
        WindowGroup("App Detail", for: AppDetailTarget.self) { $target in
            if let target {
                PopoutDetailView(target: target)
                    .environment(session)
                    .environment(templateStore)
                    .environment(rowInfoStore)
                    .environment(recordStore)
            }
        }
        .defaultSize(width: 640, height: 620)

        Window("Jamf App Manager Help", id: "help") {
            HelpView()
                .environment(help)
        }
        .defaultSize(width: 700, height: 640)
        .windowResizability(.contentSize)
    }
}