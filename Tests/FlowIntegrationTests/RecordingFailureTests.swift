import XCTest
@testable import DiktierApp

final class RecordingFailureTests: XCTestCase {
    @MainActor
    func testRecordingFailureOpensWindowWithTheActualError() {
        let controller = AppController()
        defer { controller.shutdown() }
        controller.phase = .recording
        var shownErrors: [String?] = []
        controller.showWindow = { shownErrors.append(controller.error) }

        controller.recorder.onFailure?("Das Mikrofon konnte nicht gestartet werden (CoreAudio -10877).")

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.error, "Das Mikrofon konnte nicht gestartet werden (CoreAudio -10877).")
        XCTAssertEqual(shownErrors, ["Das Mikrofon konnte nicht gestartet werden (CoreAudio -10877)."])
        XCTAssertFalse(controller.canRetry)
    }

    @MainActor
    func testLateRecordingFailureDoesNotCancelTranscription() {
        let controller = AppController()
        defer { controller.shutdown() }
        controller.phase = .processing
        var opened = 0
        controller.showWindow = { opened += 1 }

        controller.recorder.onFailure?("Veralteter Aufnahmefehler")

        XCTAssertEqual(controller.phase, .processing)
        XCTAssertNil(controller.error)
        XCTAssertEqual(opened, 0)
    }
}
