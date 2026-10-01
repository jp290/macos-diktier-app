import XCTest
@testable import FlowCore

final class DoubleCommandTapTests: XCTestCase {
    private var detector = DoubleCommandTap()

    private func change(_ down: Bool, at time: TimeInterval, otherModifier: Bool = false) -> Bool {
        detector.flagsChanged(commandDown: down, otherModifierDown: otherModifier, at: time)
    }

    func testTwoShortTapsTriggerOnlyAfterSecondRelease() {
        XCTAssertFalse(change(true, at: 0))
        XCTAssertFalse(change(false, at: 0.08))
        XCTAssertFalse(change(true, at: 0.18))
        XCTAssertTrue(change(false, at: 0.26))
        XCTAssertFalse(change(true, at: 0.36))
        XCTAssertFalse(change(false, at: 0.44))
        XCTAssertFalse(change(true, at: 0.54))
        XCTAssertTrue(change(false, at: 0.62))
    }

    func testSingleTapAndRepeatedPressDoNotTrigger() {
        XCTAssertFalse(change(true, at: 0))
        XCTAssertFalse(change(false, at: 0.08))
        XCTAssertFalse(change(true, at: 0.18))
        XCTAssertFalse(change(true, at: 0.20))
        XCTAssertFalse(change(false, at: 0.26))
        XCTAssertFalse(change(true, at: 0.36))
        XCTAssertFalse(change(false, at: 0.44))
    }

    func testSlowTapsStartNewPair() {
        XCTAssertFalse(change(true, at: 0))
        XCTAssertFalse(change(false, at: 0.08))
        XCTAssertFalse(change(true, at: 0.8))
        XCTAssertFalse(change(false, at: 0.88))
        XCTAssertFalse(change(true, at: 0.98))
        XCTAssertTrue(change(false, at: 1.06))
    }

    func testLongHoldCancelsPendingPair() {
        XCTAssertFalse(change(true, at: 0))
        XCTAssertFalse(change(false, at: 0.08))
        XCTAssertFalse(change(true, at: 0.18))
        XCTAssertFalse(change(false, at: 0.65))
        XCTAssertFalse(change(true, at: 0.75))
        XCTAssertFalse(change(false, at: 0.83))
        XCTAssertFalse(change(true, at: 0.93))
        XCTAssertTrue(change(false, at: 1.01))
    }

    func testInterveningInputCancelsFirstTap() {
        XCTAssertFalse(change(true, at: 0))
        XCTAssertFalse(change(false, at: 0.08))
        detector.interrupt()
        XCTAssertFalse(change(true, at: 0.18))
        XCTAssertFalse(change(false, at: 0.26))
    }

    func testCommandCombinationCancelsCurrentPressAndFirstTap() {
        XCTAssertFalse(change(true, at: 0))
        XCTAssertFalse(change(false, at: 0.08))
        XCTAssertFalse(change(true, at: 0.18))
        detector.interrupt()
        XCTAssertFalse(change(false, at: 0.26))
        XCTAssertFalse(change(true, at: 0.36))
        XCTAssertFalse(change(false, at: 0.44))
        XCTAssertFalse(change(true, at: 0.54))
        XCTAssertTrue(change(false, at: 0.62))
    }

    func testAdditionalModifierCancelsCommandGesture() {
        XCTAssertFalse(change(true, at: 0))
        XCTAssertFalse(change(false, at: 0.08))
        XCTAssertFalse(change(true, at: 0.18))
        XCTAssertFalse(change(true, at: 0.20, otherModifier: true))
        XCTAssertFalse(change(true, at: 0.22))
        XCTAssertFalse(change(false, at: 0.26))
        XCTAssertFalse(change(true, at: 0.36))
        XCTAssertFalse(change(false, at: 0.44))
    }

    func testCommandPressedWithOtherModifierDoesNotBecomeFirstTap() {
        XCTAssertFalse(change(false, at: 0, otherModifier: true))
        XCTAssertFalse(change(true, at: 0.08, otherModifier: true))
        XCTAssertFalse(change(false, at: 0.16, otherModifier: true))
        XCTAssertFalse(change(false, at: 0.20))
        XCTAssertFalse(change(true, at: 0.26))
        XCTAssertFalse(change(false, at: 0.34))
    }

    func testResetDiscardsPendingTapAndHeldState() {
        XCTAssertFalse(change(true, at: 0))
        XCTAssertFalse(change(false, at: 0.08))
        XCTAssertFalse(change(true, at: 0.18))
        detector.reset()
        XCTAssertFalse(change(false, at: 0.26))
        XCTAssertFalse(change(true, at: 0.36))
        XCTAssertFalse(change(false, at: 0.44))
    }

    func testInvalidTimestampsDoNotTrigger() {
        XCTAssertFalse(change(true, at: 1))
        XCTAssertFalse(change(false, at: 0.8))
        XCTAssertFalse(change(true, at: 1.1))
        XCTAssertFalse(change(false, at: 1.18))
        XCTAssertFalse(change(true, at: 0.9))
        XCTAssertFalse(change(false, at: 0.98))
    }
}
