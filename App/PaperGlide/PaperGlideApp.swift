import SwiftUI

@main
struct PaperGlideApp: App {
    init() {
        if LaunchOptions.resetsStoredProgress {
            UserDefaultsGameStorage.clearPersistedProgress()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(storage: UserDefaultsGameStorage())
        }
    }
}
