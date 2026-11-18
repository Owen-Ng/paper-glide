import Foundation

/// Words drawn on the score card, and the caption that rides with it.
///
/// The caption is `ShareMessage.text`. A name saved on the death screen is
/// included only when the caller passes that name, which is what Share does
/// at tap time.
public struct ShareCardCopy: Equatable {
    public let title: String
    public let scoredLine: String
    public let scoreText: String
    public let caption: String
    public let subject: String

    public init(title: String, scoredLine: String, scoreText: String, caption: String, subject: String) {
        self.title = title
        self.scoredLine = scoredLine
        self.scoreText = scoreText
        self.caption = caption
        self.subject = subject
    }
}

/// What Share hands the system sheet. A missing render is the plain caption,
/// so Share is never withheld.
public enum ShareOffer: Equatable {
    case card(png: Data, caption: String)
    case text(String)
}

public enum ShareCard {
    public static let pixelWidth = 1080
    public static let pixelHeight = 1350
    /// 80px of paper on each side. Lines shrink to stay inside this width.
    public static let maxTextWidth = 920.0
    public static let logoSide = 240.0
    public static let logoTop = 210.0
    public static let titlePointSize = 84.0
    public static let scoredPointSize = 58.0
    public static let scoredShrinkStep = 2.0
    public static let scorePointSize = 300.0
    public static let scoreShrinkStep = 10.0
    /// Tops, in pixels from the top of the card. The score value is the ink top.
    public static let titleTop = 490.0
    public static let scoredTop = 640.0
    public static let scoreInkTop = 750.0

    public static func copy(score: Int, username: String?) -> ShareCardCopy {
        let name = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scoredLine = name.isEmpty ? "I scored" : "\(name) scored"
        return ShareCardCopy(
            title: ShareMessage.subject,
            scoredLine: scoredLine,
            scoreText: String(score),
            caption: ShareMessage.text(score: score, username: username),
            subject: ShareMessage.subject
        )
    }

    /// `renderedPNG` is the on-device card, or nil when drawing failed.
    /// Empty data is a failure. Either way the player can still share.
    public static func offer(score: Int, username: String?, renderedPNG: Data?) -> ShareOffer {
        let caption = ShareMessage.text(score: score, username: username)
        if let renderedPNG, !renderedPNG.isEmpty {
            return .card(png: renderedPNG, caption: caption)
        }
        return .text(caption)
    }

    /// Shrinks by `step` until `width` fits on one line. The caller draws once.
    public static func pointSize(
        starting: Double,
        step: Double,
        maxWidth: Double,
        width: (Double) -> Double
    ) -> Double {
        guard step > 0, maxWidth > 0 else { return starting }
        var size = starting
        var steps = 0
        while width(size) > maxWidth, size > step, steps < 400 {
            size -= step
            steps += 1
        }
        return size
    }
}
