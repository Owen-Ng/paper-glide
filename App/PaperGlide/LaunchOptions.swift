import Foundation

/// Arguments used by the simulator screenshot test. A normal launch ignores them.
enum LaunchOptions {
    static var resetsStoredProgress: Bool {
        ProcessInfo.processInfo.arguments.contains("-paperGlideResetStore")
    }

    /// When set, physics waits on the coach screen. The first tap ends the run
    /// at this score through `GameSession.endRun(withScore:)`.
    static var scriptedEndScore: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-paperGlideEndScore") else { return nil }
        let valueIndex = arguments.index(after: flag)
        guard valueIndex < arguments.endIndex, let score = Int(arguments[valueIndex]) else { return nil }
        return score
    }
}
