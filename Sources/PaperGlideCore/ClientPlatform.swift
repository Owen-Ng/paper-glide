/// Values stored in `runs.platform` and `analytics_events.platform`.
/// This Swift client always sends `ios`. The Android port sends `android`.
public enum ClientPlatform {
    public static let ios = "ios"
    public static let android = "android"
    public static let current = ios
}
