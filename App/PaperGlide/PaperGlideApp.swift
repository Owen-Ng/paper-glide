import SwiftUI

@main
struct PaperGlideApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(storage: UserDefaultsGameStorage())
        }
    }
}
