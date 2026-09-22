import SwiftUI

@main
struct KonjuGoApp: App {
    private let credentials: any KonjuGoCredentials
    private let model: ConjugationViewModel

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--konjugo-ui-testing") {
            VerbLoadingMode.defaults.removeObject(forKey: VerbLoadingMode.defaultsKey)
            let keys = PreviewCredentials()
            credentials = keys
            model = ConjugationViewModel(service: PreviewLookupService(), cache: PreviewCache(), credentials: keys)
            return
        }
        #endif
        let keys = KonjuGoKeychain()
        credentials = keys
        model = ConjugationViewModel(service: OpenAIVerbService(), cache: VerbCache(), credentials: keys)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, credentials: credentials)
        }
        .defaultSize(width: 820, height: 1000)
        #if os(macOS)
        Settings { KonjuGoSettingsView(credentials: credentials) }
        #endif
    }
}
