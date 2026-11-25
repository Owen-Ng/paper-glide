import SwiftUI

@main
struct PaperGlideApp: App {
    @StateObject private var cloud: CloudModel

    init() {
        if LaunchOptions.resetsStoredProgress {
            UserDefaultsGameStorage.clearPersistedProgress()
            KeychainSessionStore().clear()
        }
        _cloud = StateObject(wrappedValue: CloudModel())
        #if DEBUG
        if let preset = LaunchOptions.presetBest {
            UserDefaults.standard.set(preset, forKey: UserDefaultsGameStorage.bestScoreKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(storage: UserDefaultsGameStorage(), cloud: cloud)
        }
    }
}
