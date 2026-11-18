import CoreGraphics
import CoreText
import CoreTransferable
import PaperGlideCore
import UIKit
import UniformTypeIdentifiers

/// PNG passed to the system share sheet. The caption is the share message.
struct ScoreCardPNG: Transferable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            card.png
        }
    }
}

struct RenderedShareCard {
    let image: UIImage
    let png: Data
    let scoredPointSize: CGFloat
    let scorePointSize: CGFloat
    let scoredWidth: CGFloat
    let scoreWidth: CGFloat
}

/// Draws the 1080×1350 score card on device. No network.
///
/// Fraunces is the title and the score. Nunito is the scored line. Both are
/// the unmodified variable fonts, licensed under the OFL (see Fonts/).
/// The approved card uses Fraunces optical size 9, softness 100, and wonk 0.
/// The reference script asks for optical size 72 under the key "Optical size",
/// and the font axis is "Optical Size", so that request becomes the axis
/// minimum, 9. Weight is 600 for the title and 800 for the score. Nunito is 700.
enum ShareCardRenderer {
    private static let width = ShareCard.pixelWidth
    private static let height = ShareCard.pixelHeight
    private static let bytesPerPixel = 4

    static var fontsMatchApprovedInstance: Bool {
        CardFonts.shared?.matchesApprovedInstance ?? false
    }

    static func render(_ copy: ShareCardCopy) -> RenderedShareCard? {
        guard let fonts = CardFonts.shared else { return nil }
        guard let context = bitmapContext(width: width, height: height) else { return nil }
        guard let buffer = context.data else { return nil }
        let pixels = buffer.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        paintBackdrop(pixels)

        drawMark(in: context)
        let scored = drawLine(
            copy.scoredLine,
            descriptor: fonts.scored,
            starting: ShareCard.scoredPointSize,
            step: ShareCard.scoredShrinkStep,
            anchorTop: ShareCard.scoredTop,
            color: cg(214, 107, 91),
            inkBox: false,
            in: context
        )
        let title = measure(
            copy.title,
            font: CTFontCreateWithFontDescriptor(fonts.title, ShareCard.titlePointSize, nil),
            color: cg(73, 58, 51)
        )
        draw(
            title,
            penX: (CGFloat(width) - title.advance) / 2,
            anchorTop: ShareCard.titleTop,
            in: context
        )
        let score = drawLine(
            copy.scoreText,
            descriptor: fonts.score,
            starting: ShareCard.scorePointSize,
            step: ShareCard.scoreShrinkStep,
            anchorTop: ShareCard.scoreInkTop,
            color: cg(73, 58, 51),
            inkBox: true,
            in: context
        )
        guard let cgImage = context.makeImage() else { return nil }
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        guard let png = image.pngData(), !png.isEmpty else { return nil }
        return RenderedShareCard(
            image: image,
            png: png,
            scoredPointSize: scored.size,
            scorePointSize: score.size,
            scoredWidth: scored.width,
            scoreWidth: score.width
        )
    }

    static func fontReport() -> String {
        CardFonts.shared?.report ?? "fonts did not load"
    }

    private static func drawLine(
        _ text: String,
        descriptor: CTFontDescriptor,
        starting: Double,
        step: Double,
        anchorTop: Double,
        color: CGColor,
        inkBox: Bool,
        in context: CGContext
    ) -> (size: CGFloat, width: CGFloat) {
        let size = ShareCard.pointSize(starting: starting, step: step, maxWidth: ShareCard.maxTextWidth) { pointSize in
            let font = CTFontCreateWithFontDescriptor(descriptor, pointSize, nil)
            return Double(measure(text, font: font, color: color).advance)
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let line = measure(text, font: font, color: color)
        let penX: CGFloat
        let top: CGFloat
        if inkBox {
            let inkTop = line.ascent - line.inkMaxY
            let inkWidth = line.inkMaxX - line.inkMinX
            penX = (CGFloat(width) - inkWidth) / 2 - line.inkMinX
            top = CGFloat(anchorTop) - inkTop
        } else {
            penX = (CGFloat(width) - line.advance) / 2
            top = CGFloat(anchorTop)
        }
        draw(line, penX: penX, anchorTop: top, in: context)
        return (CGFloat(size), line.advance)
    }
}

private struct LineMeasure {
    let line: CTLine
    let advance: CGFloat
    let ascent: CGFloat
    let inkMinX: CGFloat
    let inkMaxX: CGFloat
    let inkMaxY: CGFloat
}

private func measure(_ text: String, font: CTFont, color: CGColor) -> LineMeasure {
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color
    ]
    let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    return LineMeasure(
        line: line,
        advance: advance,
        ascent: ascent,
        inkMinX: bounds.minX,
        inkMaxX: bounds.maxX,
        inkMaxY: bounds.maxY
    )
}

private func draw(_ line: LineMeasure, penX: CGFloat, anchorTop: CGFloat, in context: CGContext) {
    let baseline = CGFloat(ShareCard.pixelHeight) - (anchorTop + line.ascent)
    context.textPosition = CGPoint(x: penX, y: baseline)
    CTLineDraw(line.line, context)
}

private func cg(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, alpha]
    )!
}

private func bitmapContext(width: Int, height: Int) -> CGContext? {
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: info
    )
    context?.interpolationQuality = .high
    context?.setAllowsAntialiasing(true)
    context?.setShouldAntialias(true)
    context?.setAllowsFontSmoothing(false)
    context?.setShouldSmoothFonts(false)
    context?.setAllowsFontSubpixelPositioning(true)
    context?.setShouldSubpixelPositionFonts(true)
    return context
}

private func paintBackdrop(_ pixels: UnsafeMutablePointer<UInt8>) {
    let width = ShareCard.pixelWidth
    let height = ShareCard.pixelHeight
    let sky = [188, 219, 237]
    let paper = [247, 239, 226]
    for y in 0..<height {
        let t = min(1.0, Double(y) / (Double(height) * 0.72))
        var rgb = [UInt8](repeating: 0, count: 3)
        for channel in 0..<3 {
            let mixed = Double(sky[channel]) + Double(paper[channel] - sky[channel]) * t
            rgb[channel] = UInt8(Int(mixed))
        }
        for x in 0..<width {
            let index = (y * width + x) * 4
            pixels[index] = rgb[0]
            pixels[index + 1] = rgb[1]
            pixels[index + 2] = rgb[2]
            pixels[index + 3] = 255
        }
    }

    var clouds = [UInt8](repeating: 0, count: width * height * 4)
    for run in cloudRuns {
        fill(run.0, run.1, run.0, run.2, in: &clouds, width: width, height: height, color: (252, 248, 239, 200))
    }
    clouds = gaussianBlur(clouds, width: width, height: height)
    paste(clouds, onto: pixels, width: width, height: height)

    var skyline = [UInt8](repeating: 0, count: width * height * 4)
    for block in facadeBlocks {
        let color = facadeColors[block.color]
        fill(block.y0, block.x0, block.y1, block.x1, in: &skyline, width: width, height: height, color: (color.0, color.1, color.2, 150))
        for window in block.windows {
            fill(window.1, window.0, window.3, window.2, in: &skyline, width: width, height: height, color: (252, 248, 239, 120))
        }
    }
    paste(skyline, onto: pixels, width: width, height: height)
}

private let facadeColors: [(UInt8, UInt8, UInt8)] = [
    (242, 193, 175),
    (193, 214, 193),
    (214, 198, 232),
    (249, 219, 178),
    (186, 211, 229)
]

private func fill(
    _ y0: Int,
    _ x0: Int,
    _ y1: Int,
    _ x1: Int,
    in buffer: inout [UInt8],
    width: Int,
    height: Int,
    color: (UInt8, UInt8, UInt8, UInt8)
) {
    let top = max(0, min(y0, y1))
    let bottom = min(height - 1, max(y0, y1))
    let left = max(0, min(x0, x1))
    let right = min(width - 1, max(x0, x1))
    guard top <= bottom, left <= right else { return }
    for y in top...bottom {
        for x in left...right {
            let index = (y * width + x) * 4
            buffer[index] = color.0
            buffer[index + 1] = color.1
            buffer[index + 2] = color.2
            buffer[index + 3] = color.3
        }
    }
}

private func paste(_ source: [UInt8], onto destination: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            let alpha = Int(source[index + 3])
            if alpha == 0 { continue }
            for channel in 0..<3 {
                let src = Int(source[index + channel])
                let dst = Int(destination[index + channel])
                destination[index + channel] = UInt8((src * alpha + dst * (255 - alpha) + 127) / 255)
            }
            destination[index + 3] = 255
        }
    }
}

private func gaussianBlur(_ source: [UInt8], width: Int, height: Int) -> [UInt8] {
    // The puffs sit in this rect, and the blur kernel does not reach its edge.
    let minX = 20
    let minY = 60
    let cropWidth = 1000
    let cropHeight = 260
    var crop = [UInt8](repeating: 0, count: cropWidth * cropHeight * 4)
    for row in 0..<cropHeight {
        let from = ((row + minY) * width + minX) * 4
        let to = row * cropWidth * 4
        crop.replaceSubrange(to..<(to + cropWidth * 4), with: source[from..<(from + cropWidth * 4)])
    }
    let blurred = blurBuffer(crop, width: cropWidth, height: cropHeight)
    var output = source
    for row in 0..<cropHeight {
        let from = row * cropWidth * 4
        let to = ((row + minY) * width + minX) * 4
        output.replaceSubrange(to..<(to + cropWidth * 4), with: blurred[from..<(from + cropWidth * 4)])
    }
    return output
}

private func blurBuffer(_ source: [UInt8], width: Int, height: Int) -> [UInt8] {
    let passes = 3
    let sigma2 = 4.0 / Double(passes)
    let length = (12.0 * sigma2 + 1.0).squareRoot()
    let box = floor((length - 1.0) / 2.0)
    var fractional = (2 * box + 1) * (box * (box + 1) - 3 * sigma2)
    fractional /= 6 * (sigma2 - (box + 1) * (box + 1))
    let floatRadius = box + fractional
    let radius = Int(floatRadius)
    let ww = Int(Double(1 << 24) / (floatRadius * 2 + 1))
    let fw = ((1 << 24) - (radius * 2 + 1) * ww) / 2
    var current = source
    var scratch = [UInt8](repeating: 0, count: source.count)
    for _ in 0..<passes {
        blur(current, into: &scratch, width: width, height: height, horizontal: true, radius: radius, ww: ww, fw: fw)
        swap(&current, &scratch)
    }
    for _ in 0..<passes {
        blur(current, into: &scratch, width: width, height: height, horizontal: false, radius: radius, ww: ww, fw: fw)
        swap(&current, &scratch)
    }
    return current
}

private func blur(
    _ source: [UInt8],
    into destination: inout [UInt8],
    width: Int,
    height: Int,
    horizontal: Bool,
    radius: Int,
    ww: Int,
    fw: Int
) {
    let lines = horizontal ? height : width
    let count = horizontal ? width : height
    for line in 0..<lines {
        for channel in 0..<4 {
            let origin = horizontal ? (line * width * 4 + channel) : (line * 4 + channel)
            let stride = horizontal ? 4 : width * 4
            blurLine(
                source,
                into: &destination,
                origin: origin,
                stride: stride,
                count: count,
                radius: radius,
                ww: ww,
                fw: fw
            )
        }
    }
}

private func blurLine(
    _ source: [UInt8],
    into destination: inout [UInt8],
    origin: Int,
    stride: Int,
    count: Int,
    radius: Int,
    ww: Int,
    fw: Int
) {
    guard count > 0 else { return }
    let edgeA = min(radius + 1, count)
    let edgeB = max(count - radius - 1, 0)
    let last = count - 1
    func at(_ index: Int) -> Int { Int(source[origin + index * stride]) }
    func put(_ index: Int, _ bulk: Int) {
        destination[origin + index * stride] = UInt8((bulk + (1 << 23)) >> 24)
    }
    var acc = at(0) * (radius + 1)
    let lead = max(edgeA - 1, 0)
    if lead > 0 {
        for index in 0..<lead { acc += at(index) }
    }
    acc += at(last) * (radius - edgeA + 1)
    func far(_ left: Int, _ right: Int) -> Int {
        acc * ww + (at(left) + at(right)) * fw
    }
    if edgeA <= edgeB {
        for index in 0..<edgeA {
            acc += at(index + radius) - at(0)
            put(index, far(0, index + radius + 1))
        }
        for index in edgeA..<edgeB {
            acc += at(index + radius) - at(index - radius - 1)
            put(index, far(index - radius - 1, index + radius + 1))
        }
        if last >= edgeB {
            for index in edgeB...last {
                acc += at(last) - at(index - radius - 1)
                put(index, far(index - radius - 1, last))
            }
        }
    } else {
        for index in 0..<edgeB {
            acc += at(index + radius) - at(0)
            put(index, far(0, index + radius + 1))
        }
        for index in edgeB..<edgeA {
            acc += at(last) - at(0)
            put(index, far(0, last))
        }
        if last >= edgeA {
            for index in edgeA...last {
                acc += at(last) - at(index - radius - 1)
                put(index, far(index - radius - 1, last))
            }
        }
    }
}

private func drawMark(in context: CGContext) {
    let scale = 4
    let side = Int(ShareCard.logoSide) * scale
    guard let mark = bitmapContext(width: side, height: side) else { return }
    let s = CGFloat(side)
    let frame = CGRect(x: s * 0.18, y: s * 0.14, width: s * 0.32, height: s * 0.72)
    mark.addPath(CGPath(roundedRect: frame, cornerWidth: s * 0.05, cornerHeight: s * 0.05, transform: nil))
    mark.setFillColor(cg(214, 107, 91))
    mark.fillPath()
    let hole = CGRect(x: s * 0.26, y: s * 0.32, width: s * 0.16, height: s * 0.36)
    mark.setBlendMode(.clear)
    mark.addPath(CGPath(roundedRect: hole, cornerWidth: s * 0.025, cornerHeight: s * 0.025, transform: nil))
    mark.fillPath()
    mark.setBlendMode(.normal)

    func point(_ x: CGFloat, _ yFromTop: CGFloat) -> CGPoint {
        CGPoint(x: x, y: s - yFromTop)
    }
    let nose = point(s * 0.86, s * 0.50)
    let tailTop = point(s * 0.30, s * 0.40)
    let tailBottom = point(s * 0.30, s * 0.62)
    let fold = point(s * 0.42, s * 0.51)
    let plane = CGMutablePath()
    plane.move(to: tailTop)
    plane.addLine(to: nose)
    plane.addLine(to: tailBottom)
    plane.addLine(to: fold)
    plane.closeSubpath()
    mark.setFillColor(cg(252, 248, 239))
    mark.addPath(plane)
    mark.fillPath()
    mark.setStrokeColor(cg(73, 58, 51))
    mark.setLineWidth(CGFloat(Int(s * 0.014)))
    mark.setLineJoin(.round)
    mark.setLineCap(.round)
    mark.addPath(plane)
    mark.strokePath()
    mark.setStrokeColor(cg(73, 58, 51, 200.0 / 255.0))
    mark.setLineWidth(CGFloat(Int(s * 0.008)))
    mark.move(to: fold)
    mark.addLine(to: nose)
    mark.strokePath()

    guard let image = mark.makeImage() else { return }
    let logo = CGFloat(ShareCard.logoSide)
    let rect = CGRect(
        x: (CGFloat(ShareCard.pixelWidth) - logo) / 2,
        y: CGFloat(ShareCard.pixelHeight) - CGFloat(ShareCard.logoTop) - logo,
        width: logo,
        height: logo
    )
    context.interpolationQuality = .high
    context.draw(image, in: rect)
}

private final class CardFonts {
    static let shared: CardFonts? = CardFonts()
    let title: CTFontDescriptor
    let score: CTFontDescriptor
    let scored: CTFontDescriptor
    let report: String
    let matchesApprovedInstance: Bool

    private init?() {
        guard let fraunces = CardFonts.url("Fraunces-Variable"),
              let nunito = CardFonts.url("Nunito-Variable"),
              let title = CardFonts.face(fraunces, [Axis.opsz: 9, Axis.wght: 600, Axis.soft: 100, Axis.wonk: 0]),
              let score = CardFonts.face(fraunces, [Axis.opsz: 9, Axis.wght: 800, Axis.soft: 100, Axis.wonk: 0]),
              let scored = CardFonts.face(nunito, [Axis.wght: 700]) else {
            return nil
        }
        self.title = title
        self.score = score
        self.scored = scored
        let titleFont = CTFontCreateWithFontDescriptor(title, 84, nil)
        let scoreFont = CTFontCreateWithFontDescriptor(score, 300, nil)
        let scoredFont = CTFontCreateWithFontDescriptor(scored, 58, nil)
        report = """
        title \(CardFonts.describe(titleFont))
        score \(CardFonts.describe(scoreFont))
        scored \(CardFonts.describe(scoredFont))
        """
        let titleOK = CardFonts.near(titleFont, Axis.wght, 600, fallback: 900)
            && CardFonts.near(titleFont, Axis.soft, 100, fallback: 0)
            && CardFonts.near(titleFont, Axis.wonk, 0, fallback: 1)
            && CardFonts.near(titleFont, Axis.opsz, 9, fallback: 9)
        let scoreOK = CardFonts.near(scoreFont, Axis.wght, 800, fallback: 900)
        let scoredOK = CardFonts.near(scoredFont, Axis.wght, 700, fallback: 200)
        matchesApprovedInstance = titleOK && scoreOK && scoredOK
    }

    private static func url(_ name: String) -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: name, withExtension: "ttf") { return url }
        if let url = bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") { return url }
        guard let root = bundle.resourceURL else { return nil }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == "\(name).ttf" { return item }
        }
        return nil
    }

    private static func face(_ url: URL, _ axes: [Int32: CGFloat]) -> CTFontDescriptor? {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let base = list.first else {
            return nil
        }
        var variations: [NSNumber: NSNumber] = [:]
        for (tag, value) in axes {
            variations[NSNumber(value: tag)] = NSNumber(value: Double(value))
        }
        let attributes: [CFString: Any] = [kCTFontVariationAttribute: variations]
        return CTFontDescriptorCreateCopyWithAttributes(base, attributes as CFDictionary)
    }

    private static func near(_ font: CTFont, _ tag: Int32, _ expected: CGFloat, fallback: CGFloat) -> Bool {
        abs(value(font, tag, fallback: fallback) - expected) < 0.6
    }

    private static func value(_ font: CTFont, _ tag: Int32, fallback: CGFloat) -> CGFloat {
        guard let raw = CTFontCopyVariation(font) as? [NSNumber: NSNumber] else { return fallback }
        for (key, value) in raw where key.int32Value == tag {
            return CGFloat(value.doubleValue)
        }
        return fallback
    }

    private static func describe(_ font: CTFont) -> String {
        let tags = [Axis.opsz, Axis.wght, Axis.soft, Axis.wonk]
        let parts = tags.map { tag -> String in
            let shown = value(font, tag, fallback: -1)
            return String(format: "%08X:%.1f", tag, shown)
        }
        let name = CTFontCopyPostScriptName(font) as String
        return "\(name) \(parts.joined(separator: " "))"
    }
}

private enum Axis {
    static let opsz: Int32 = 0x6F70737A
    static let wght: Int32 = 0x77676874
    static let soft: Int32 = 0x534F4654
    static let wonk: Int32 = 0x574F4E4B
}
private struct FacadeBlock {
    let x0, y0, x1, y1, color: Int
    let windows: [(Int, Int, Int, Int)]
}
private let facadeBlocks: [FacadeBlock] = [
    FacadeBlock(x0: -20, y0: 1241, x1: 111, y1: 1350, color: 3, windows: [(-2,1265,14,1287), (36,1265,52,1287), (74,1265,90,1287), (-2,1309,14,1331), (36,1309,52,1331), (74,1309,90,1331)]),
    FacadeBlock(x0: 125, y0: 1251, x1: 221, y1: 1350, color: 4, windows: [(143,1275,159,1297), (181,1275,197,1297), (143,1319,159,1341), (181,1319,197,1341)]),
    FacadeBlock(x0: 226, y0: 1186, x1: 362, y1: 1350, color: 0, windows: [(244,1210,260,1232), (282,1210,298,1232), (320,1210,336,1232), (244,1254,260,1276), (282,1254,298,1276), (320,1254,336,1276), (244,1298,260,1320), (282,1298,298,1320), (320,1298,336,1320)]),
    FacadeBlock(x0: 374, y0: 1256, x1: 491, y1: 1350, color: 0, windows: [(392,1280,408,1302), (430,1280,446,1302), (392,1324,408,1346), (430,1324,446,1346)]),
    FacadeBlock(x0: 501, y0: 1252, x1: 644, y1: 1350, color: 1, windows: [(519,1276,535,1298), (557,1276,573,1298), (595,1276,611,1298), (519,1320,535,1342), (557,1320,573,1342), (595,1320,611,1342)]),
    FacadeBlock(x0: 649, y0: 1206, x1: 809, y1: 1350, color: 0, windows: [(667,1230,683,1252), (705,1230,721,1252), (743,1230,759,1252), (781,1230,797,1252), (667,1274,683,1296), (705,1274,721,1296), (743,1274,759,1296), (781,1274,797,1296), (667,1318,683,1340), (705,1318,721,1340), (743,1318,759,1340), (781,1318,797,1340)]),
    FacadeBlock(x0: 822, y0: 1232, x1: 927, y1: 1350, color: 4, windows: [(840,1256,856,1278), (878,1256,894,1278), (840,1300,856,1322), (878,1300,894,1322)]),
    FacadeBlock(x0: 931, y0: 1186, x1: 1094, y1: 1350, color: 3, windows: [(949,1210,965,1232), (987,1210,1003,1232), (1025,1210,1041,1232), (1063,1210,1079,1232), (949,1254,965,1276), (987,1254,1003,1276), (1025,1254,1041,1276), (1063,1254,1079,1276), (949,1298,965,1320), (987,1298,1003,1320), (1025,1298,1041,1320), (1063,1298,1079,1320)]),
]
private let cloudRuns: [(Int, Int, Int)] = [
    (76, 754, 765), (77, 750, 769), (78, 747, 772), (79, 745, 774),
    (80, 743, 776), (81, 741, 778), (82, 739, 780), (83, 738, 781),
    (84, 737, 782), (85, 736, 783), (86, 735, 784), (87, 734, 785),
    (88, 733, 786), (89, 732, 787), (90, 731, 788), (91, 143, 157),
    (91, 730, 789), (92, 137, 163), (92, 730, 789), (93, 133, 167),
    (93, 729, 790), (94, 130, 170), (94, 728, 791), (95, 127, 173),
    (95, 728, 791), (96, 125, 175), (96, 727, 797), (97, 122, 178),
    (97, 727, 801), (98, 120, 180), (98, 727, 803), (99, 119, 181),
    (99, 722, 805), (100, 117, 183), (100, 718, 807), (101, 115, 185),
    (101, 716, 808), (102, 114, 186), (102, 714, 810), (103, 113, 187),
    (103, 712, 811), (104, 111, 189), (104, 711, 812), (105, 110, 190),
    (105, 709, 813), (106, 109, 191), (106, 708, 814), (107, 108, 192),
    (107, 707, 814), (108, 107, 193), (108, 706, 815), (109, 105, 195),
    (109, 706, 816), (110, 104, 196), (110, 705, 816), (111, 104, 196),
    (111, 704, 824), (112, 103, 197), (112, 704, 827), (113, 102, 198),
    (113, 703, 829), (114, 101, 199), (114, 702, 831), (115, 100, 200),
    (115, 702, 832), (116, 99, 201), (116, 702, 833), (117, 99, 201),
    (117, 701, 834), (118, 98, 202), (118, 701, 835), (119, 97, 203),
    (119, 701, 836), (120, 96, 204), (120, 700, 837), (121, 96, 204),
    (121, 700, 837), (122, 95, 205), (122, 700, 838), (123, 95, 205),
    (123, 700, 838), (124, 94, 206), (124, 700, 839), (125, 93, 207),
    (125, 700, 839), (126, 93, 207), (126, 700, 839), (127, 92, 208),
    (127, 700, 840), (128, 92, 217), (128, 700, 840), (129, 92, 222),
    (129, 700, 840), (130, 91, 225), (130, 700, 840), (131, 91, 228),
    (131, 701, 840), (132, 84, 230), (132, 701, 840), (133, 79, 232),
    (133, 701, 840), (134, 75, 234), (134, 702, 840), (135, 73, 236),
    (135, 702, 839), (136, 70, 237), (136, 702, 839), (137, 68, 239),
    (137, 703, 839), (138, 66, 240), (138, 704, 838), (139, 65, 241),
    (139, 704, 838), (140, 63, 243), (140, 705, 837), (141, 62, 244),
    (141, 706, 837), (142, 61, 245), (142, 706, 836), (143, 59, 246),
    (143, 707, 835), (144, 58, 247), (144, 708, 745), (144, 747, 772),
    (144, 774, 834), (145, 57, 248), (145, 709, 744), (145, 750, 769),
    (145, 775, 833), (146, 56, 248), (146, 711, 742), (146, 754, 765),
    (146, 777, 832), (147, 55, 249), (147, 712, 741), (147, 778, 807),
    (147, 809, 831), (148, 54, 250), (148, 714, 739), (148, 780, 805),
    (148, 811, 829), (149, 53, 251), (149, 716, 737), (149, 782, 803),
    (149, 813, 827), (150, 53, 251), (150, 718, 735), (150, 784, 801),
    (150, 816, 824), (151, 52, 252), (151, 722, 731), (151, 788, 797),
    (152, 51, 253), (153, 50, 253), (154, 50, 265), (155, 49, 270),
    (156, 48, 273), (157, 48, 275), (158, 47, 277), (159, 47, 279),
    (160, 46, 280), (161, 46, 281), (162, 46, 283), (163, 45, 284),
    (164, 45, 285), (165, 44, 286), (166, 44, 287), (167, 44, 288),
    (168, 44, 288), (169, 43, 289), (170, 43, 290), (171, 43, 291),
    (172, 43, 291), (173, 43, 292), (174, 42, 292), (175, 42, 293),
    (176, 42, 293), (177, 42, 294), (178, 42, 294), (179, 42, 294),
    (180, 42, 295), (181, 42, 295), (182, 42, 295), (183, 42, 295),
    (184, 42, 295), (185, 42, 296), (186, 42, 296), (186, 873, 886),
    (187, 43, 296), (187, 868, 891), (188, 43, 296), (188, 864, 895),
    (189, 43, 296), (189, 861, 898), (190, 43, 296), (190, 859, 900),
    (191, 43, 296), (191, 857, 902), (192, 44, 296), (192, 855, 904),
    (193, 44, 296), (193, 853, 906), (194, 44, 296), (194, 852, 907),
    (195, 44, 296), (195, 850, 909), (196, 45, 295), (196, 849, 910),
    (197, 45, 295), (197, 848, 911), (198, 46, 295), (198, 846, 913),
    (199, 46, 295), (199, 845, 914), (200, 46, 295), (200, 844, 915),
    (201, 47, 294), (201, 843, 916), (202, 47, 294), (202, 842, 917),
    (203, 48, 294), (203, 841, 918), (204, 48, 293), (204, 840, 919),
    (205, 49, 293), (205, 840, 919), (206, 50, 292), (206, 839, 920),
    (207, 50, 292), (207, 838, 921), (208, 51, 291), (208, 837, 922),
    (209, 52, 291), (209, 837, 922), (210, 53, 290), (210, 836, 923),
    (211, 53, 289), (211, 835, 924), (212, 54, 288), (212, 835, 924),
    (213, 55, 288), (213, 834, 925), (214, 56, 287), (214, 834, 925),
    (215, 57, 123), (215, 127, 173), (215, 176, 286), (215, 833, 926),
    (216, 58, 122), (216, 130, 170), (216, 177, 285), (216, 833, 934),
    (217, 59, 121), (217, 133, 167), (217, 179, 284), (217, 832, 938),
    (218, 61, 119), (218, 137, 163), (218, 180, 283), (218, 832, 941),
    (219, 62, 118), (219, 143, 157), (219, 181, 281), (219, 826, 944),
    (220, 63, 117), (220, 183, 237), (220, 240, 280), (220, 821, 946),
    (221, 65, 115), (221, 184, 236), (221, 241, 279), (221, 818, 948),
    (222, 66, 114), (222, 186, 234), (222, 243, 277), (222, 816, 949),
    (223, 68, 112), (223, 188, 232), (223, 245, 275), (223, 814, 951),
    (224, 70, 110), (224, 190, 230), (224, 247, 273), (224, 812, 952),
    (225, 73, 107), (225, 192, 228), (225, 250, 270), (225, 811, 953),
    (226, 75, 105), (226, 195, 225), (226, 255, 265), (226, 809, 955),
    (227, 79, 101), (227, 198, 222), (227, 808, 956), (228, 84, 96),
    (228, 203, 217), (228, 807, 957), (229, 806, 958), (230, 805, 958),
    (231, 804, 959), (232, 803, 960), (233, 802, 961), (234, 801, 961),
    (235, 800, 962), (236, 800, 963), (237, 799, 972), (238, 798, 976),
    (239, 798, 979), (240, 797, 981), (241, 797, 982), (242, 796, 984),
    (243, 796, 985), (244, 795, 986), (245, 795, 987), (246, 795, 988),
    (247, 794, 989), (248, 794, 990), (249, 794, 991), (250, 794, 991),
    (251, 794, 992), (252, 793, 993), (253, 793, 993), (254, 793, 994),
    (255, 793, 994), (256, 793, 994), (257, 793, 995), (258, 793, 995),
    (259, 793, 995), (260, 793, 995), (261, 793, 996), (262, 793, 996),
    (263, 793, 996), (264, 794, 996), (265, 794, 996), (266, 794, 996),
    (267, 794, 996), (268, 794, 996), (269, 795, 996), (270, 795, 996),
    (271, 795, 995), (272, 796, 995), (273, 796, 995), (274, 797, 995),
    (275, 797, 994), (276, 798, 994), (277, 798, 994), (278, 799, 993),
    (279, 800, 993), (280, 800, 992), (281, 801, 991), (282, 802, 991),
    (283, 803, 990), (284, 804, 989), (285, 805, 988), (286, 806, 857),
    (286, 861, 898), (286, 901, 987), (287, 807, 856), (287, 864, 895),
    (287, 903, 986), (288, 808, 855), (288, 868, 891), (288, 904, 985),
    (289, 809, 854), (289, 873, 886), (289, 905, 984), (290, 811, 852),
    (290, 907, 949), (290, 953, 982), (291, 812, 851), (291, 908, 948),
    (291, 954, 981), (292, 814, 849), (292, 910, 946), (292, 956, 979),
    (293, 816, 847), (293, 912, 944), (293, 959, 976), (294, 818, 845),
    (294, 915, 941), (294, 963, 972), (295, 821, 842), (295, 918, 938),
    (296, 826, 837), (296, 922, 934),
]
