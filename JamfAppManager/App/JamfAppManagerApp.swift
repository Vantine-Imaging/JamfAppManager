// Copyright 2026 Vantine Imaging LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
struct JamfAppManagerApp: App {
    @State private var session = SessionStore()
    @State private var templateStore = TemplateStore()
    @State private var iconStore = IconStore()
    @State private var recordStore = RecordStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(templateStore)
                .environment(iconStore)
                .environment(recordStore)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
    }
}