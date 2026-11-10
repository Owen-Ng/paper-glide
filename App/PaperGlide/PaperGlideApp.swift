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
    }

    var body: some Scene {
        WindowGroup {
            RootView(storage: UserDefaultsGameStorage(), cloud: cloud)
        }
    }
}
