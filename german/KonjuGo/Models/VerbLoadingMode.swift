import Foundation

enum VerbLoadingMode: String, CaseIterable, Identifiable {
    case onDemand, everything
    static let defaultsKey = "konjugo.loadingMode"
    var id: String { rawValue }
    var title: String { self == .onDemand ? "On demand" : "Load everything" }
    static var defaults: UserDefaults {
        if ProcessInfo.processInfo.arguments.contains("--konjugo-ui-testing") {
            return UserDefaults(suiteName: "com.skylinevision.KonjuGo.ui-tests")!
        }
        return .standard
    }
    static func saved(in defaults: UserDefaults? = nil) -> Self {
        (defaults ?? Self.defaults).string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .onDemand
    }
}
