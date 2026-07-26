import Foundation

enum CursorInventoryCommand {
    static let argument = "--cursor-inventory"

    static func isRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.dropFirst().first == argument
    }

    static func run() -> Int32 {
        do {
            let registry = try ReadOnlyCursorRegistry()
            let report = registry.makeInventoryReport()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
            return EXIT_SUCCESS
        } catch {
            let message = "NextCursor cursor inventory failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            return EXIT_FAILURE
        }
    }
}
