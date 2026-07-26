import AppKit
import Foundation

final class CursorDiagnostics {
    static let shared = CursorDiagnostics()

    private struct CursorState: Equatable {
        let seed: UInt32?
        let visibility: NativeCursorVisibility
        let wantsHidden: Bool
        let hasSuppressionLease: Bool
        let suppressor: String
        let frontmostApplication: String
    }

    private struct InputState: Equatable {
        let moved: Bool
        let isPressed: Bool
        let pressChanged: Bool
        let scrolled: Bool
        let isDeepIdle: Bool
    }

    let isEnabled: Bool

    private let startTime = ProcessInfo.processInfo.systemUptime
    private var lastCursorState: CursorState?
    private var lastInputState: InputState?

    private init() {
        #if DEBUG
            isEnabled = ProcessInfo.processInfo.environment["NEXTCURSOR_DIAGNOSTICS"] == "1"
        #else
            isEnabled = false
        #endif

        if isEnabled {
            emit("diagnostics enabled")
        }
    }

    func observeCursor(
        seed: UInt32?,
        visibility: NativeCursorVisibility,
        wantsHidden: Bool,
        hasSuppressionLease: Bool,
        suppressor: String,
        context: String
    ) {
        guard isEnabled else { return }

        let state = CursorState(
            seed: seed,
            visibility: visibility,
            wantsHidden: wantsHidden,
            hasSuppressionLease: hasSuppressionLease,
            suppressor: suppressor,
            frontmostApplication: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        )
        guard state != lastCursorState else { return }
        lastCursorState = state

        emit(
            "cursor context=\(context) seed=\(Self.optional(state.seed)) "
                + "visibility=\(state.visibility.rawValue) wantsHidden=\(state.wantsHidden) "
                + "suppression=\(state.suppressor) lease=\(state.hasSuppressionLease) "
                + "frontmost=\(state.frontmostApplication)"
        )
    }

    func observeInput(
        moved: Bool,
        isPressed: Bool,
        pressChanged: Bool,
        scrolled: Bool,
        isDeepIdle: Bool
    ) {
        guard isEnabled else { return }

        let state = InputState(
            moved: moved,
            isPressed: isPressed,
            pressChanged: pressChanged,
            scrolled: scrolled,
            isDeepIdle: isDeepIdle
        )
        guard state != lastInputState else { return }
        lastInputState = state

        emit(
            "input moved=\(state.moved) pressed=\(state.isPressed) "
                + "pressChanged=\(state.pressChanged) scrolled=\(state.scrolled) "
                + "deepIdle=\(state.isDeepIdle)"
        )
    }

    func recordCursorOperation(_ operation: String, reason: String) {
        guard isEnabled else { return }
        emit("operation=\(operation) reason=\(reason)")
    }

    private func emit(_ message: String) {
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        let line = "[NextCursor +\(String(format: "%.3f", elapsed))] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func optional<T>(_ value: T?) -> String {
        value.map(String.init(describing:)) ?? "unavailable"
    }
}
