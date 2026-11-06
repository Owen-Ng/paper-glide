import Foundation

/// Arguments used by the simulator screenshot tests. A normal launch ignores them.
enum LaunchOptions {
    static var resetsStoredProgress: Bool {
        ProcessInfo.processInfo.arguments.contains("-paperGlideResetStore")
    }

    /// When set, physics waits on the coach screen. The first tap ends the run
    /// at this score through `GameSession.endRun(withScore:)`. This is a test hook,
    /// not a simulated flight.
    static var scriptedEndScore: Int? {
        guard let raw = stringArgument("-paperGlideEndScore") else { return nil }
        return Int(raw)
    }

    /// Fixed window seed. Normal launches stay random.
    static var seed: UInt64? {
        guard let raw = stringArgument("-paperGlideSeed") else { return nil }
        return UInt64(raw)
    }

    /// When set, the free-running clock is paused. Each Glide tap applies one real
    /// impulse and then advances the simulation by this many seconds. Coast advances
    /// the same simulation with no impulse.
    static var guidedStride: Double? {
        guard let raw = stringArgument("-paperGlideGuidedStride"),
              let stride = Double(raw),
              stride > 0 else {
            return nil
        }
        return stride
    }

    private static func stringArgument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: name) else { return nil }
        let valueIndex = arguments.index(after: flag)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}
