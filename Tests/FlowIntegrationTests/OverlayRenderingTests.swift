import AppKit
import SwiftUI
import XCTest
@testable import DiktierApp

final class OverlayRenderingTests: XCTestCase {
    @MainActor
    func testOverlayStatesFitCompactFrame() throws {
        let controller = AppController()
        defer { controller.shutdown() }
        controller.recorder.level = 0.65
        controller.recorder.elapsed = 12
        for (name, phase) in [("recording", DictationPhase.recording), ("processing", .processing), ("inserting", .inserting)] {
            controller.phase = phase
            let renderer = ImageRenderer(content: RecordingHUD(controller: controller, recorder: controller.recorder)
                .environment(\.colorScheme, .light))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, 400)
            XCTAssertEqual(image.height, 80)
            if let path = ProcessInfo.processInfo.environment["FLOW_PREVIEW_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("overlay-\(name).png"))
            }
        }
    }
}
