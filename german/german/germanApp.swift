import SwiftUI

@main
struct germanApp: App {
    var body: some Scene {
        Window("German Practice", id: "practice") {
            ContentView()
        }
        .defaultSize(width: 780, height: 720)

        Settings { SettingsView() }
    }
}
