import AppKit
import Darwin
import Foundation

// A C function pointer cannot capture context, so the controller under test
// and its restore path are file-scope rather than members of the command.
private var controllerUnderTest: SystemCursorController?

private func restoreCursorForCheck() {
    controllerUnderTest?.show()
    controllerUnderTest = nil
}

/// Verifies, on the machine actually running NextCursor, that native-cursor
/// suppression holds from a never-frontmost accessory process.
///
/// This exercises the shipping `SystemCursorController` rather than a
/// reimplementation, so a pass is evidence about the real code path. The
/// cursor is suppressed only for the sampling window and is restored on every
/// exit path; because suppression is scoped to this process's WindowServer
/// connection, killing the check also restores it.
enum CursorSuppressionCheckCommand {
    static let argument = "--verify-cursor-suppression"

    private static let sampleCount = 60
    private static let sampleIntervalMicroseconds: useconds_t = 20_000

    static func isRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.dropFirst().first == argument
    }

    static func run() -> Int32 {
        NSApp.setActivationPolicy(.accessory)

        let suppressor = NativeCursorSuppressor.resolve()
        let before = suppressor.nativeCursorVisibility()

        // A cursor that is already off screen makes every sample read as
        // hidden regardless of what this code does, so the result could not be
        // attributed. The cause cannot be identified from here: it may be
        // another process's suppression, or simply the transient obscuring
        // macOS applies until the mouse next moves. Refuse to report a false
        // pass either way.
        guard before == .visible else {
            let message = """
                suppressor: \(suppressor.identifier)
                visibility before: \(before.rawValue)
                result: INCONCLUSIVE — the native cursor is already off screen, so \
                this check cannot attribute its own effect. Move the mouse (macOS \
                obscures the cursor until it moves) and quit any running NextCursor \
                instance, then retry.
                """
            FileHandle.standardError.write(Data((message + "\n").utf8))
            return 2
        }

        let controller = SystemCursorController()
        controllerUnderTest = controller
        installRestoreHandlers()

        controller.hide()

        var observed: [NativeCursorVisibility: Int] = [:]
        for _ in 0..<sampleCount {
            // Let AppKit and WindowServer settle between samples so a foreign
            // cursor set has a real opportunity to defeat suppression.
            CFRunLoopRunInMode(.defaultMode, 0.001, true)
            controller.maintainHiddenState()
            observed[suppressor.nativeCursorVisibility(), default: 0] += 1
            usleep(sampleIntervalMicroseconds)
        }

        restoreCursorForCheck()
        let after = suppressor.nativeCursorVisibility()

        let heldSamples = observed[.hidden] ?? 0
        let leakedSamples = observed[.visible] ?? 0
        let unknownSamples = observed[.unknown] ?? 0

        var lines = [
            "suppressor: \(suppressor.identifier)",
            "visibility before: \(before.rawValue)",
            "samples: \(sampleCount) "
                + "hidden=\(heldSamples) visible=\(leakedSamples) unknown=\(unknownSamples)",
            "visibility after restore: \(after.rawValue)",
        ]

        let suppressionHeld = heldSamples == sampleCount
        let cursorWasRestored = after == .visible
        if suppressionHeld, cursorWasRestored {
            lines.append("result: PASS — suppression held and the cursor was restored")
        } else if !suppressionHeld {
            lines.append(
                "result: FAIL — the native cursor was composited for "
                    + "\(leakedSamples + unknownSamples) of \(sampleCount) samples; "
                    + "NextCursor is falling back to transparent-image replacement"
            )
        } else {
            lines.append(
                "result: FAIL — suppression held but the cursor was not restored "
                    + "(visibility \(after.rawValue)); quit any running NextCursor process"
            )
        }

        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        return suppressionHeld && cursorWasRestored ? EXIT_SUCCESS : EXIT_FAILURE
    }

    private static func installRestoreHandlers() {
        atexit { restoreCursorForCheck() }
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            Darwin.signal(signalNumber) { _ in
                restoreCursorForCheck()
                _exit(EXIT_FAILURE)
            }
        }
    }
}
