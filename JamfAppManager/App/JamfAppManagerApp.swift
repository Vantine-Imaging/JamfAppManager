import SwiftUI

@main
struct JamfAppManagerApp: App {
    @State private var session = SessionStore()
    @State private var templateStore = TemplateStore()
    @State private var iconStore = IconStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(templateStore)
                .environment(iconStore)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
    }
}
