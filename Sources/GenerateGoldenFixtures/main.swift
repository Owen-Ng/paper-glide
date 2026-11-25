import Foundation
import PaperGlideCore

@main
struct GenerateGoldenFixtures {
    static func main() throws {
        let argument = CommandLine.arguments.dropFirst().first ?? "fixtures/golden"
        let directory = URL(fileURLWithPath: argument, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = [
            GoldenFixture.capture(name: "no-tap-fall", seed: 1, tapSteps: [], maxSteps: 400),
            GoldenFixture.capture(
                name: "fixed-taps",
                seed: 3,
                tapSteps: [12, 30, 48, 70, 96, 120, 150, 180, 210, 240],
                maxSteps: 360
            ),
            GoldenFixture.capturePilot(name: "pilot-ramp", seed: 11, stopScore: 6, maxSteps: 2400)
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for file in files {
            let url = directory.appendingPathComponent("\(file.name).json")
            let data = try encoder.encode(file)
            try data.write(to: url, options: .atomic)
            let score = file.steps.map(\.score).max() ?? 0
            let phase = file.steps.last?.phase ?? "?"
            print("\(file.name).json steps=\(file.steps.count) taps=\(file.tapSteps.count) maxScore=\(score) end=\(phase)")
        }
    }
}
