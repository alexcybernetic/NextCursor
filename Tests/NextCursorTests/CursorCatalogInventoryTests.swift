import XCTest

@testable import NextCursor

final class CursorCatalogInventoryTests: XCTestCase {
    func testSystemAndNumericCursorIDNamespacesRemainDistinct() {
        let aliases = [
            CursorSystemAlias(
                systemCursorID: 2,
                name: "com.apple.coregraphics.IBeamXOR"
            )
        ]

        let candidates = CursorInventoryPolicy.candidateSources(aliases: aliases)

        XCTAssertEqual(candidates["com.apple.coregraphics.IBeamXOR"], [.systemAlias])
        XCTAssertEqual(candidates["com.apple.cursor.2"], [.numericCandidate])
    }

    func testCandidateSourcesDeduplicateRepeatedSystemNames() {
        let aliases = [
            CursorSystemAlias(systemCursorID: 0, name: "com.apple.coregraphics.Arrow"),
            CursorSystemAlias(systemCursorID: 100, name: "com.apple.coregraphics.Arrow"),
        ]

        let candidates = CursorInventoryPolicy.candidateSources(aliases: aliases)

        XCTAssertEqual(candidates["com.apple.coregraphics.Arrow"], [.systemAlias])
        XCTAssertEqual(
            candidates.keys.filter { $0.hasPrefix("com.apple.cursor.") }.count,
            42
        )
    }

    func testSnapshotSafetyIsDerivedFromValidationIssues() {
        let valid = makeRegistration(issues: [])
        let invalid = makeRegistration(issues: ["invalid metadata"])

        XCTAssertTrue(valid.isSafeToSnapshot)
        XCTAssertFalse(invalid.isSafeToSnapshot)
    }

    private func makeRegistration(issues: [String]) -> CursorRegistrationInventory {
        CursorRegistrationInventory(
            name: "com.apple.coregraphics.Arrow",
            sources: [.systemAlias],
            logicalSize: CursorSizeInventory(width: 28, height: 40),
            hotspot: CursorPointInventory(x: 5, y: 5),
            frameCount: 1,
            frameDuration: 0,
            representations: [],
            validationIssues: issues
        )
    }
}
