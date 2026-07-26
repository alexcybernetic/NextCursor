import CoreGraphics
import CryptoKit
import Darwin
import Foundation

private typealias CGSConnectionID = Int32
private typealias CGSMainConnectionIDFunction = @convention(c) () -> CGSConnectionID
private typealias CGSCursorNameForSystemCursorFunction =
    @convention(c) (Int32) -> UnsafePointer<CChar>?
private typealias CGSCopyRegisteredCursorImagesFunction =
    @convention(c) (
        CGSConnectionID,
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<CGSize>?,
        UnsafeMutablePointer<CGPoint>?,
        UnsafeMutablePointer<UInt>?,
        UnsafeMutablePointer<CGFloat>?,
        UnsafeMutablePointer<Unmanaged<CFArray>?>
    ) -> Int32

private struct CopiedCursorRegistration {
    let logicalSize: CGSize
    let hotspot: CGPoint
    let frameCount: UInt
    let frameDuration: CGFloat
    let images: [CGImage]
}

private enum CursorRegistryQueryError: Error {
    case queryFailed(Int32)
    case invalidResult(String)

    var reportFields: (errorCode: Int32?, reason: String) {
        switch self {
        case .queryFailed(let errorCode):
            return (errorCode, "not currently registered or query failed")
        case .invalidResult(let reason):
            return (nil, reason)
        }
    }
}

enum ReadOnlyCursorRegistryError: Error, LocalizedError {
    case frameworkUnavailable
    case symbolUnavailable(String)
    case windowServerConnectionUnavailable

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            return "CoreGraphics could not be loaded"
        case .symbolUnavailable(let name):
            return "Required read-only cursor symbol is unavailable: \(name)"
        case .windowServerConnectionUnavailable:
            return "No WindowServer connection is available"
        }
    }
}

/// A deliberately narrow private-SPI boundary. This type resolves and calls
/// named cursor query functions only. It must not resolve any CoreCursor,
/// register, set, remove, show, or hide function: some apparently read-only
/// CoreCursor APIs lazily register missing cursors on current macOS releases.
final class ReadOnlyCursorRegistry {
    private static let coreGraphicsPath =
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

    private let framework: UnsafeMutableRawPointer
    private let connectionID: CGSConnectionID
    private let cursorNameForSystemCursor: CGSCursorNameForSystemCursorFunction
    private let copyRegisteredCursorImages: CGSCopyRegisteredCursorImagesFunction

    init() throws {
        guard let framework = dlopen(Self.coreGraphicsPath, RTLD_NOW | RTLD_LOCAL) else {
            throw ReadOnlyCursorRegistryError.frameworkUnavailable
        }

        do {
            let mainConnectionID: CGSMainConnectionIDFunction = try Self.loadSymbol(
                "CGSMainConnectionID",
                from: framework
            )
            let cursorNameForSystemCursor: CGSCursorNameForSystemCursorFunction =
                try Self.loadSymbol("CGSCursorNameForSystemCursor", from: framework)
            let copyRegisteredCursorImages: CGSCopyRegisteredCursorImagesFunction =
                try Self.loadSymbol("CGSCopyRegisteredCursorImages", from: framework)

            let connectionID = mainConnectionID()
            guard connectionID != 0 else {
                throw ReadOnlyCursorRegistryError.windowServerConnectionUnavailable
            }

            self.framework = framework
            self.connectionID = connectionID
            self.cursorNameForSystemCursor = cursorNameForSystemCursor
            self.copyRegisteredCursorImages = copyRegisteredCursorImages
        } catch {
            dlclose(framework)
            throw error
        }
    }

    func makeInventoryReport() -> CursorInventoryReport {
        let aliases = systemAliases(in: CursorInventoryPolicy.systemCursorIDs)
        let candidates = CursorInventoryPolicy.candidateSources(aliases: aliases)
        var registrations: [CursorRegistrationInventory] = []
        var failures: [CursorQueryFailure] = []

        for name in candidates.keys.sorted() {
            let sources = Array(candidates[name] ?? []).sorted()
            do {
                let copied = try copyRegistration(named: name)
                registrations.append(
                    Self.makeRegistrationInventory(
                        name: name,
                        sources: sources,
                        copied: copied
                    )
                )
            } catch let error as CursorRegistryQueryError {
                let fields = error.reportFields
                failures.append(
                    CursorQueryFailure(
                        name: name,
                        sources: sources,
                        errorCode: fields.errorCode,
                        reason: fields.reason
                    )
                )
            } catch {
                failures.append(
                    CursorQueryFailure(
                        name: name,
                        sources: sources,
                        errorCode: nil,
                        reason: String(describing: error)
                    )
                )
            }
        }

        return CursorInventoryReport(
            schemaVersion: 1,
            generatedAt: Self.timestamp(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            discovery: CursorInventoryDiscovery(
                systemCursorIDLowerBound: CursorInventoryPolicy.systemCursorIDs.lowerBound,
                systemCursorIDUpperBound: CursorInventoryPolicy.systemCursorIDs.upperBound,
                numericCursorIDLowerBound: CursorInventoryPolicy.numericCursorIDs.lowerBound,
                numericCursorIDUpperBound: CursorInventoryPolicy.numericCursorIDs.upperBound,
                namedQueriesAttempted: candidates.count,
                coreCursorAPIsInvoked: false,
                completeness:
                    "bounded Apple system aliases and com.apple.cursor.2...43; arbitrary third-party names cannot be enumerated"
            ),
            systemAliases: aliases,
            registrations: registrations,
            unavailableRegistrations: failures
        )
    }

    func systemAliases(in cursorIDs: ClosedRange<Int32>) -> [CursorSystemAlias] {
        cursorIDs.compactMap { cursorID in
            guard let namePointer = cursorNameForSystemCursor(cursorID) else { return nil }
            return CursorSystemAlias(
                systemCursorID: cursorID,
                name: String(cString: namePointer)
            )
        }
    }

    private func copyRegistration(named name: String) throws -> CopiedCursorRegistration {
        guard !name.isEmpty, name.utf8.count <= 127, name.utf8.allSatisfy({ $0 < 128 }) else {
            throw CursorRegistryQueryError.invalidResult("cursor name is not valid bounded ASCII")
        }

        var logicalSize = CGSize.zero
        var hotspot = CGPoint.zero
        var frameCount: UInt = 0
        var frameDuration: CGFloat = 0
        var unmanagedImages: Unmanaged<CFArray>?

        let errorCode = name.withCString { namePointer in
            copyRegisteredCursorImages(
                connectionID,
                namePointer,
                &logicalSize,
                &hotspot,
                &frameCount,
                &frameDuration,
                &unmanagedImages
            )
        }
        guard errorCode == 0 else {
            throw CursorRegistryQueryError.queryFailed(errorCode)
        }
        guard let unmanagedImages else {
            throw CursorRegistryQueryError.invalidResult(
                "successful query returned no image array"
            )
        }

        let array = unmanagedImages.takeRetainedValue()
        let images = try Self.copyImages(from: array)
        return CopiedCursorRegistration(
            logicalSize: logicalSize,
            hotspot: hotspot,
            frameCount: frameCount,
            frameDuration: frameDuration,
            images: images
        )
    }

    private static func copyImages(from array: CFArray) throws -> [CGImage] {
        let count = CFArrayGetCount(array)
        guard count > 0 else {
            throw CursorRegistryQueryError.invalidResult("image array is empty")
        }

        var images: [CGImage] = []
        images.reserveCapacity(count)
        for index in 0..<count {
            guard let rawValue = CFArrayGetValueAtIndex(array, index) else {
                throw CursorRegistryQueryError.invalidResult(
                    "image array contains a null entry"
                )
            }
            let value = Unmanaged<CFTypeRef>.fromOpaque(rawValue).takeUnretainedValue()
            guard CFGetTypeID(value) == CGImage.typeID else {
                throw CursorRegistryQueryError.invalidResult(
                    "image array contains a non-CGImage entry"
                )
            }
            images.append(Unmanaged<CGImage>.fromOpaque(rawValue).takeUnretainedValue())
        }
        return images
    }

    private static func makeRegistrationInventory(
        name: String,
        sources: [CursorRegistrationSource],
        copied: CopiedCursorRegistration
    ) -> CursorRegistrationInventory {
        var issues = validate(copied)
        let representations = copied.images.enumerated().map { index, image in
            makeRepresentationInventory(
                image,
                index: index,
                frameCount: copied.frameCount,
                issues: &issues
            )
        }

        return CursorRegistrationInventory(
            name: name,
            sources: sources,
            logicalSize: CursorSizeInventory(
                width: copied.logicalSize.width,
                height: copied.logicalSize.height
            ),
            hotspot: CursorPointInventory(
                x: copied.hotspot.x,
                y: copied.hotspot.y
            ),
            frameCount: copied.frameCount,
            frameDuration: copied.frameDuration,
            representations: representations,
            validationIssues: Array(Set(issues)).sorted()
        )
    }

    private static func validate(_ copied: CopiedCursorRegistration) -> [String] {
        var issues: [String] = []
        let width = copied.logicalSize.width
        let height = copied.logicalSize.height
        if !width.isFinite || !height.isFinite || width <= 0 || height <= 0
            || width > 4_096 || height > 4_096
        {
            issues.append("logical size is outside the supported range")
        }

        let hotspotX = copied.hotspot.x
        let hotspotY = copied.hotspot.y
        if !hotspotX.isFinite || !hotspotY.isFinite || hotspotX < 0 || hotspotY < 0
            || hotspotX > width || hotspotY > height
        {
            issues.append("hotspot is outside the logical cursor bounds")
        }

        if copied.frameCount < 1 || copied.frameCount > 32 {
            issues.append("frame count is outside 1...32")
        }
        if !copied.frameDuration.isFinite || copied.frameDuration < 0
            || copied.frameDuration > 60
        {
            issues.append("frame duration is outside the supported range")
        }
        if copied.images.count > 32 {
            issues.append("representation count exceeds 32")
        }
        return issues
    }

    private static func makeRepresentationInventory(
        _ image: CGImage,
        index: Int,
        frameCount: UInt,
        issues: inout [String]
    ) -> CursorRepresentationInventory {
        let width = image.width
        let height = image.height

        let framePixelHeight: Int?
        if frameCount >= 1, frameCount <= UInt(Int.max), height % Int(frameCount) == 0 {
            framePixelHeight = height / Int(frameCount)
        } else {
            framePixelHeight = nil
            issues.append("representation height is not divisible by frame count")
        }

        let hasValidFrameDimensions =
            width >= 1 && width <= 4_096
            && framePixelHeight.map { $0 >= 1 && $0 <= 4_096 } == true
        if !hasValidFrameDimensions {
            issues.append("per-frame representation dimensions are outside 1...4096")
        }

        let pixelCount = width.multipliedReportingOverflow(by: height)
        if pixelCount.overflow || pixelCount.partialValue > 64_000_000 {
            issues.append("stacked representation exceeds the pixel limit")
        }
        let byteCount = image.bytesPerRow.multipliedReportingOverflow(by: height)
        if byteCount.overflow || byteCount.partialValue > 256 * 1_024 * 1_024 {
            issues.append("stacked representation exceeds the byte limit")
        }

        let dataHash: String?
        if !pixelCount.overflow, pixelCount.partialValue <= 64_000_000,
            !byteCount.overflow, byteCount.partialValue <= 256 * 1_024 * 1_024,
            let provider = image.dataProvider, let providerData = provider.data
        {
            dataHash = SHA256.hash(data: providerData as Data).hexString
        } else {
            dataHash = nil
            if !pixelCount.overflow, pixelCount.partialValue <= 64_000_000,
                !byteCount.overflow, byteCount.partialValue <= 256 * 1_024 * 1_024
            {
                issues.append("representation pixel data is unavailable")
            }
        }

        return CursorRepresentationInventory(
            index: index,
            pixelWidth: width,
            pixelHeight: height,
            framePixelHeight: framePixelHeight,
            bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow,
            alphaInfo: image.alphaInfo.rawValue,
            bitmapInfo: image.bitmapInfo.rawValue,
            colorSpaceName: image.colorSpace?.name as String?,
            providerDataSHA256: dataHash
        )
    }

    private static func loadSymbol<T>(
        _ name: String,
        from framework: UnsafeMutableRawPointer
    ) throws -> T {
        guard let symbol = dlsym(framework, name) else {
            throw ReadOnlyCursorRegistryError.symbolUnavailable(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static var architecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }

    deinit {
        dlclose(framework)
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
