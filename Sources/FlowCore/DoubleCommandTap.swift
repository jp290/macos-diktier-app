import Foundation

public struct DoubleCommandTap {
    private var commandIsDown = false
    private var pressStartedAt: TimeInterval?
    private var firstReleaseAt: TimeInterval?
    private let maximumPressDuration: TimeInterval = 0.3
    private let maximumTapInterval: TimeInterval = 0.45

    public init() {}

    public mutating func flagsChanged(commandDown: Bool, otherModifierDown: Bool,
                                      at time: TimeInterval) -> Bool {
        let changed = commandDown != commandIsDown
        commandIsDown = commandDown
        guard changed, !otherModifierDown else {
            interrupt()
            return false
        }
        if commandDown {
            pressStartedAt = time
            return false
        }
        guard let start = pressStartedAt, time >= start,
              time - start <= maximumPressDuration else {
            interrupt()
            return false
        }
        pressStartedAt = nil
        if let firstRelease = firstReleaseAt, time >= firstRelease,
           time - firstRelease <= maximumTapInterval {
            firstReleaseAt = nil
            return true
        }
        firstReleaseAt = time
        return false
    }

    public mutating func interrupt() {
        pressStartedAt = nil
        firstReleaseAt = nil
    }

    public mutating func reset() {
        commandIsDown = false
        interrupt()
    }
}
