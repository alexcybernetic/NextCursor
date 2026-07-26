import Darwin
import Dispatch
import Foundation

final class DockCursorOverrideWatchdog {
    static let argument = "--dock-cursor-override-watchdog"

    private enum Message: UInt8 {
        case active = 0xA1
        case stop = 0xA2
        case restored = 0xA3
    }

    private static let startupTimeoutMilliseconds: Int32 = 2_000
    private static let shutdownTimeoutMilliseconds: Int32 = 1_000

    // Keep the first manual trial bounded even while the parent remains alive.
    // Production use will replace this with a monitored, long-lived guardian
    // only after the SPI behavior is confirmed on the target macOS release.
    private static let experimentalTimeoutMilliseconds: Int32 = 5 * 60_000

    private var process: Process?
    private var controlHandle: FileHandle?
    private var isActive = false

    func start() -> Bool {
        if let process {
            guard !process.isRunning else { return isActive }
            resetExitedProcess()
        }

        guard let executableURL = Bundle.main.executableURL,
            let (parentHandle, childHandle) = Self.makeControlSocket()
        else {
            return false
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [Self.argument]
        process.standardInput = childHandle
        process.standardOutput = childHandle
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            parentHandle.closeFile()
            childHandle.closeFile()
            return false
        }

        // The child owns a duplicate of this endpoint after Process.run().
        childHandle.closeFile()
        self.process = process
        controlHandle = parentHandle

        guard
            Self.readMessage(
                from: parentHandle.fileDescriptor,
                timeoutMilliseconds: Self.startupTimeoutMilliseconds
            ) == .active
        else {
            retireCurrentProcess()
            return false
        }

        isActive = true
        return true
    }

    @discardableResult
    func stop() -> Bool {
        guard let process else { return true }

        var didRestore = !isActive
        if isActive, let controlHandle {
            if process.isRunning {
                _ = Self.writeMessage(.stop, to: controlHandle.fileDescriptor)
            }
            didRestore =
                Self.readMessage(
                    from: controlHandle.fileDescriptor,
                    timeoutMilliseconds: Self.shutdownTimeoutMilliseconds
                ) == .restored
        }

        controlHandle?.closeFile()
        controlHandle = nil
        isActive = false

        let didExit = Self.waitForExit(
            process,
            timeoutMilliseconds: Self.shutdownTimeoutMilliseconds
        )
        if didExit {
            self.process = nil
        }

        return didRestore && didExit
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard arguments.dropFirst().first == argument else { return false }

        // Terminal signals may be delivered to the parent's whole process
        // group. The watchdog must survive long enough to restore the shared
        // WindowServer setting after the parent's control socket closes.
        _ = Darwin.signal(SIGINT, SIG_IGN)
        _ = Darwin.signal(SIGTERM, SIG_IGN)
        _ = Darwin.signal(SIGHUP, SIG_IGN)
        _ = Darwin.signal(SIGPIPE, SIG_IGN)

        guard var controller = DockCursorOverrideController(), controller.acquire() else {
            return true
        }

        guard writeMessage(.active, to: STDOUT_FILENO) else {
            controller.release()
            return true
        }

        waitForStopOrTimeout()
        controller.release()
        _ = writeMessage(.restored, to: STDOUT_FILENO)
        return true
    }

    private func retireCurrentProcess() {
        controlHandle?.closeFile()
        controlHandle = nil
        isActive = false

        guard let process else { return }
        if Self.waitForExit(
            process,
            timeoutMilliseconds: Self.shutdownTimeoutMilliseconds
        ) {
            self.process = nil
        }
    }

    private func resetExitedProcess() {
        controlHandle?.closeFile()
        controlHandle = nil
        process = nil
        isActive = false
    }

    private static func makeControlSocket() -> (FileHandle, FileHandle)? {
        var descriptors: [Int32] = [0, 0]
        let result = descriptors.withUnsafeMutableBufferPointer { buffer in
            Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, buffer.baseAddress)
        }
        guard result == 0 else { return nil }

        guard configureSocket(descriptors[0]), configureSocket(descriptors[1]) else {
            Darwin.close(descriptors[0])
            Darwin.close(descriptors[1])
            return nil
        }

        return (
            FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true),
            FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
        )
    }

    private static func configureSocket(_ descriptor: Int32) -> Bool {
        let existingFlags = Darwin.fcntl(descriptor, F_GETFD)
        guard existingFlags >= 0,
            Darwin.fcntl(descriptor, F_SETFD, existingFlags | FD_CLOEXEC) == 0
        else {
            return false
        }

        var enabled: Int32 = 1
        return withUnsafePointer(to: &enabled) { pointer in
            Darwin.setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                pointer,
                socklen_t(MemoryLayout<Int32>.size)
            ) == 0
        }
    }

    private static func waitForStopOrTimeout() {
        let deadline = deadline(after: experimentalTimeoutMilliseconds)
        while true {
            var descriptor = pollfd(
                fd: STDIN_FILENO,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let result = Darwin.poll(&descriptor, 1, remainingMilliseconds(until: deadline))

            if result > 0 {
                if descriptor.revents & Int16(POLLIN) != 0 {
                    _ = readByte(from: STDIN_FILENO)
                }
                return
            }
            if result == 0 { return }
            if errno != EINTR { return }
            if remainingMilliseconds(until: deadline) == 0 { return }
        }
    }

    private static func readMessage(
        from descriptor: Int32,
        timeoutMilliseconds: Int32
    ) -> Message? {
        let deadline = deadline(after: timeoutMilliseconds)
        while true {
            var pollDescriptor = pollfd(
                fd: descriptor,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let result = Darwin.poll(
                &pollDescriptor,
                1,
                remainingMilliseconds(until: deadline)
            )

            if result > 0 {
                guard pollDescriptor.revents & Int16(POLLIN) != 0,
                    let byte = readByte(from: descriptor)
                else {
                    return nil
                }
                return Message(rawValue: byte)
            }
            if result == 0 { return nil }
            if errno != EINTR { return nil }
            if remainingMilliseconds(until: deadline) == 0 { return nil }
        }
    }

    private static func readByte(from descriptor: Int32) -> UInt8? {
        var byte: UInt8 = 0
        while true {
            let count = withUnsafeMutableBytes(of: &byte) { buffer in
                Darwin.read(descriptor, buffer.baseAddress, 1)
            }
            if count == 1 { return byte }
            if count == 0 { return nil }
            if errno != EINTR { return nil }
        }
    }

    private static func writeMessage(_ message: Message, to descriptor: Int32) -> Bool {
        var byte = message.rawValue
        while true {
            let count = withUnsafeBytes(of: &byte) { buffer in
                Darwin.write(descriptor, buffer.baseAddress, 1)
            }
            if count == 1 { return true }
            if count >= 0 || errno != EINTR { return false }
        }
    }

    private static func waitForExit(
        _ process: Process,
        timeoutMilliseconds: Int32
    ) -> Bool {
        let deadline = deadline(after: timeoutMilliseconds)
        while process.isRunning, remainingMilliseconds(until: deadline) > 0 {
            Darwin.usleep(10_000)
        }
        return !process.isRunning
    }

    private static func deadline(after milliseconds: Int32) -> UInt64 {
        DispatchTime.now().uptimeNanoseconds + UInt64(milliseconds) * 1_000_000
    }

    private static func remainingMilliseconds(until deadline: UInt64) -> Int32 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { return 0 }

        let remainingNanoseconds = deadline - now
        let roundedUpMilliseconds = (remainingNanoseconds + 999_999) / 1_000_000
        return Int32(min(roundedUpMilliseconds, UInt64(Int32.max)))
    }

    deinit {
        stop()
    }
}
