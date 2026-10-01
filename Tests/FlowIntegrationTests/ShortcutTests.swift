import AppKit
import Carbon
import XCTest
@testable import DiktierApp

final class ShortcutTests: XCTestCase {
    @MainActor
    func testLeftAndRightCommandEventsToggleOncePerPair() throws {
        let shortcut = GlobalShortcut()
        var calls = 0
        shortcut.action = { calls += 1 }
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0, key: 55))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.08, key: 55))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0.18, key: 54))
        XCTAssertEqual(calls, 0)
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.26, key: 54))
        XCTAssertEqual(calls, 1)
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0.36, key: 55))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.44, key: 55))
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testCommandCDoesNotToggleOrCountAsTap() throws {
        let shortcut = GlobalShortcut()
        var calls = 0
        shortcut.action = { calls += 1 }
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0))
        shortcut.handleDoubleCommandEvent(try event(.keyDown, flags: .command, at: 0.04, key: 8))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.08))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0.18))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.26))
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testOtherModifiersRejectTapAndCapsLockAllowsIt() throws {
        for flag: NSEvent.ModifierFlags in [.shift, .control, .option, .function] {
            let shortcut = GlobalShortcut()
            var calls = 0
            shortcut.action = { calls += 1 }
            for start in [0.0, 0.18] {
                shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [.command, flag], at: start))
                shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: flag, at: start + 0.08))
            }
            XCTAssertEqual(calls, 0, "Unexpected toggle for \(flag)")
        }
        let shortcut = GlobalShortcut()
        var calls = 0
        shortcut.action = { calls += 1 }
        for start in [0.0, 0.18] {
            shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [.command, .capsLock], at: start))
            shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .capsLock, at: start + 0.08))
        }
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testMouseClickAndUnregisterDiscardPendingTap() throws {
        let shortcut = GlobalShortcut()
        var calls = 0
        shortcut.action = { calls += 1 }
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.08))
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0.12, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        shortcut.handleDoubleCommandEvent(click)
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0.18))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.26))
        XCTAssertEqual(calls, 0)
        shortcut.unregister()
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0.36))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.44))
        XCTAssertEqual(calls, 0)
    }

    func testShortcutDefaultsAndExistingPreferences() {
        XCTAssertEqual(DictationShortcut.restored(from: nil), .doubleCommand)
        XCTAssertEqual(DictationShortcut.restored(from: "unknown"), .doubleCommand)
        XCTAssertEqual(DictationShortcut.restored(from: "doubleCommand"), .doubleCommand)
        XCTAssertEqual(DictationShortcut.restored(from: "optionSpace"), .optionSpace)
        XCTAssertEqual(DictationShortcut.restored(from: "controlSpace"), .controlSpace)
        XCTAssertEqual(DictationShortcut.restored(from: "optionD"), .optionD)
        XCTAssertEqual(DictationShortcut.optionSpace.key, UInt32(kVK_Space))
        XCTAssertEqual(DictationShortcut.optionSpace.modifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(DictationShortcut.optionD.key, UInt32(kVK_ANSI_D))
        XCTAssertEqual(DictationShortcut.controlSpace.modifiers, UInt32(cmdKey | controlKey))
    }

    @MainActor
    func testAppSwitchAndReregisterCancelPendingTap() throws {
        let shortcut = GlobalShortcut()
        defer { shortcut.unregister() }
        var calls = 0
        shortcut.action = { calls += 1 }
        XCTAssertTrue(shortcut.register(.doubleCommand))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.08))
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0.18))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.26))
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(shortcut.register(.doubleCommand))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0.36))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.44))
        XCTAssertEqual(calls, 0)
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: .command, at: 0.54))
        shortcut.handleDoubleCommandEvent(try event(.flagsChanged, flags: [], at: 0.62))
        XCTAssertEqual(calls, 1)
    }

    private func event(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags,
                       at timestamp: TimeInterval, key: UInt16 = 55) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
            timestamp: timestamp, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: key))
    }
}
