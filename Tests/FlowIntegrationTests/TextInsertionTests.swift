import AppKit
import XCTest
@testable import DiktierApp

final class TextInsertionTests: XCTestCase {
    @MainActor
    func testMissingTargetRefusesInsertionWithoutTouchingClipboard() async {
        let originalCount = NSPasteboard.general.changeCount
        let inserted = await TextInsertion.paste("This must stay out of other apps.", into: nil)
        XCTAssertFalse(inserted)
        XCTAssertEqual(NSPasteboard.general.changeCount, originalCount)
    }

    @MainActor
    func testCaptureRejectsMissingAndOwnApplication() {
        XCTAssertNil(TextInsertion.capture(nil))
        XCTAssertNil(TextInsertion.capture(NSRunningApplication.current))
    }

    @MainActor
    func testOverlayCannotStealKeyboardFocusFromDictationTarget() {
        let panel = DictationPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.frame.size, NSSize(width: 200, height: 40))
    }
}
