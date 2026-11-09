import SwiftUI
import UIKit

enum AppTheme {
    static let ink = Color(red: 0.29, green: 0.23, blue: 0.20)
    static let coral = Color(red: 0.84, green: 0.42, blue: 0.36)
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.94)
    /// Morning top, used until the play scene paints the live wash.
    static let skyBackground = UIColor(red: 0.74, green: 0.86, blue: 0.93, alpha: 1)
    static let inkUI = UIColor(red: 0.29, green: 0.23, blue: 0.20, alpha: 1)
    static let planeFill = UIColor(red: 0.99, green: 0.975, blue: 0.94, alpha: 1)
    static let planeStroke = UIColor(red: 0.35, green: 0.33, blue: 0.31, alpha: 1)
    /// Constant paper rim. The live sky does not recolor window frames.
    static let paperLip = UIColor(red: 0.99, green: 0.975, blue: 0.935, alpha: 1)
    static let gapEdge = UIColor(red: 0.33, green: 0.28, blue: 0.24, alpha: 1)

    static let facades: [UIColor] = [
        UIColor(red: 0.95, green: 0.76, blue: 0.69, alpha: 1),
        UIColor(red: 0.76, green: 0.84, blue: 0.76, alpha: 1),
        UIColor(red: 0.84, green: 0.78, blue: 0.91, alpha: 1),
        UIColor(red: 0.98, green: 0.86, blue: 0.70, alpha: 1),
        UIColor(red: 0.73, green: 0.83, blue: 0.90, alpha: 1)
    ]
}
