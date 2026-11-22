import PaperGlideCore
import UIKit
import XCTest
@testable import PaperGlide

final class ShareCardRenderTests: XCTestCase {
    func testBundledFontsAreTheApprovedInstances() {
        XCTAssertTrue(ShareCardRenderer.fontsMatchApprovedInstance, ShareCardRenderer.fontReport())
    }

    func testRenderedCardMatchesTheReferencePixels() throws {
        let owen = try XCTUnwrap(ShareCardRenderer.render(ShareCard.copy(score: 27, username: "owen")))
        XCTAssertEqual(owen.image.size, CGSize(width: 1080, height: 1350))
        XCTAssertEqual(owen.image.scale, 1)
        XCTAssertGreaterThan(owen.png.count, 8_000)
        XCTAssertEqual(Array(owen.png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        expect(owen.image, 20, 20, 189, 219, 236, "sky")
        expect(owen.image, 111, 1300, 248, 227, 198, "facade")
        expect(owen.image, 112, 1300, 247, 239, 226, "gap")
        expect(owen.image, 40, 1241, 248, 227, 198, "facade top")
        expect(owen.image, 40, 1240, 247, 239, 226, "above facade")
        expect(owen.image, 470, 260, 214, 107, 91, "logo")
        expect(owen.image, 500, 300, 206, 225, 233, "window")
        expect(owen.image, 150, 170, 240, 242, 238, "cloud")
        attach(owen, name: "death-card-owen-27")

        let long = try XCTUnwrap(ShareCardRenderer.render(ShareCard.copy(score: 4096, username: "skyward_pilot_01")))
        XCTAssertLessThanOrEqual(long.scoredWidth, ShareCard.maxTextWidth)
        XCTAssertLessThanOrEqual(long.scoreWidth, ShareCard.maxTextWidth)
        XCTAssertGreaterThan(long.scoredPointSize, 20)
        XCTAssertGreaterThan(long.scorePointSize, 100)
        XCTAssertEqual(long.image.size, CGSize(width: 1080, height: 1350))
        attach(long, name: "death-card-longname-4096")

        let zero = try XCTUnwrap(ShareCardRenderer.render(ShareCard.copy(score: 0, username: nil)))
        XCTAssertEqual(zero.image.size, CGSize(width: 1080, height: 1350))
        XCTAssertNotEqual(zero.png, owen.png)
        attach(zero, name: "death-card-noname-0")

        guard case .card(let png, let caption) = ShareCard.offer(score: 27, username: "owen", renderedPNG: owen.png) else {
            return XCTFail("offer dropped the rendered card")
        }
        XCTAssertEqual(png, owen.png)
        XCTAssertEqual(caption, "I scored 27 in Paper Glide as owen")
    }

    private func attach(_ card: RenderedShareCard, name: String) {
        let attachment = XCTAttachment(image: card.image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func expect(
        _ image: UIImage,
        _ x: Int,
        _ y: Int,
        _ red: Int,
        _ green: Int,
        _ blue: Int,
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let pixel = sample(image, x, y)
        XCTAssertEqual(pixel.0, red, "\(name) red at \(x),\(y) was \(pixel)", file: file, line: line)
        XCTAssertEqual(pixel.1, green, "\(name) green at \(x),\(y) was \(pixel)", file: file, line: line)
        XCTAssertEqual(pixel.2, blue, "\(name) blue at \(x),\(y) was \(pixel)", file: file, line: line)
    }

    private func sample(_ image: UIImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return (-1, -1, -1)
        }
        let offset = y * cgImage.bytesPerRow + x * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}
