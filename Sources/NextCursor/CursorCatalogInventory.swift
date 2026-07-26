import Foundation

enum CursorRegistrationSource: String, Codable, Comparable {
    case numericCandidate
    case systemAlias

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct CursorSystemAlias: Codable, Equatable {
    let systemCursorID: Int32
    let name: String
}

struct CursorPointInventory: Codable, Equatable {
    let x: Double
    let y: Double
}

struct CursorSizeInventory: Codable, Equatable {
    let width: Double
    let height: Double
}

struct CursorRepresentationInventory: Codable, Equatable {
    let index: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let framePixelHeight: Int?
    let bitsPerComponent: Int
    let bitsPerPixel: Int
    let bytesPerRow: Int
    let alphaInfo: UInt32
    let bitmapInfo: UInt32
    let colorSpaceName: String?
    let providerDataSHA256: String?
}

struct CursorRegistrationInventory: Codable, Equatable {
    let name: String
    let sources: [CursorRegistrationSource]
    let logicalSize: CursorSizeInventory
    let hotspot: CursorPointInventory
    let frameCount: UInt
    let frameDuration: Double
    let representations: [CursorRepresentationInventory]
    let validationIssues: [String]
    let isSafeToSnapshot: Bool

    init(
        name: String,
        sources: [CursorRegistrationSource],
        logicalSize: CursorSizeInventory,
        hotspot: CursorPointInventory,
        frameCount: UInt,
        frameDuration: Double,
        representations: [CursorRepresentationInventory],
        validationIssues: [String]
    ) {
        self.name = name
        self.sources = sources
        self.logicalSize = logicalSize
        self.hotspot = hotspot
        self.frameCount = frameCount
        self.frameDuration = frameDuration
        self.representations = representations
        self.validationIssues = validationIssues
        isSafeToSnapshot = validationIssues.isEmpty
    }
}

struct CursorQueryFailure: Codable, Equatable {
    let name: String
    let sources: [CursorRegistrationSource]
    let errorCode: Int32?
    let reason: String
}

struct CursorInventoryDiscovery: Codable, Equatable {
    let systemCursorIDLowerBound: Int32
    let systemCursorIDUpperBound: Int32
    let numericCursorIDLowerBound: Int32
    let numericCursorIDUpperBound: Int32
    let namedQueriesAttempted: Int
    let coreCursorAPIsInvoked: Bool
    let completeness: String
}

struct CursorInventoryReport: Codable, Equatable {
    let schemaVersion: UInt32
    let generatedAt: String
    let operatingSystem: String
    let architecture: String
    let discovery: CursorInventoryDiscovery
    let systemAliases: [CursorSystemAlias]
    let registrations: [CursorRegistrationInventory]
    let unavailableRegistrations: [CursorQueryFailure]
}

enum CursorInventoryPolicy {
    static let systemCursorIDs: ClosedRange<Int32> = 0...255
    static let numericCursorIDs: ClosedRange<Int32> = 2...43

    static func numericName(for cursorID: Int32) -> String {
        "com.apple.cursor.\(cursorID)"
    }

    static func candidateSources(
        aliases: [CursorSystemAlias]
    ) -> [String: Set<CursorRegistrationSource>] {
        var candidates: [String: Set<CursorRegistrationSource>] = [:]
        for alias in aliases {
            candidates[alias.name, default: []].insert(.systemAlias)
        }
        for cursorID in numericCursorIDs {
            candidates[numericName(for: cursorID), default: []].insert(.numericCandidate)
        }
        return candidates
    }
}
