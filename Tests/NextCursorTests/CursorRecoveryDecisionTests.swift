import XCTest

@testable import NextCursor

final class CursorRecoveryDecisionTests: XCTestCase {
    func testRemovableOverrideOverSurvivingOriginalIsReversible() {
        let verdict = CursorActivationGate.evaluate(
            CursorReversibilityEvidence(
                originalMappingSurvivesReplacement: true,
                originalProvenanceIsKnown: false,
                ownedOverrideCanBeRemoved: true,
                snapshotPreservesCompleteSemantics: false
            )
        )

        XCTAssertEqual(verdict, .reversible(.removeOwnedOverride))
    }

    func testCompleteKnownSnapshotIsReversible() {
        let verdict = CursorActivationGate.evaluate(
            CursorReversibilityEvidence(
                originalMappingSurvivesReplacement: false,
                originalProvenanceIsKnown: true,
                ownedOverrideCanBeRemoved: false,
                snapshotPreservesCompleteSemantics: true
            )
        )

        XCTAssertEqual(verdict, .reversible(.restoreCompleteSnapshot))
    }

    func testCurrentNamedCopyEvidenceFailsClosed() {
        let verdict = CursorActivationGate.evaluate(
            CursorReversibilityEvidence(
                originalMappingSurvivesReplacement: false,
                originalProvenanceIsKnown: false,
                ownedOverrideCanBeRemoved: false,
                snapshotPreservesCompleteSemantics: false
            )
        )

        XCTAssertEqual(
            verdict,
            .rejected(CursorActivationRejection.allCases)
        )
    }

    func testRestorationClassifiesOwnedOriginalAndForeignStates() {
        let original = fingerprint(0x11)
        let replacement = fingerprint(0x22)

        XCTAssertEqual(
            CursorRestorationClassifier.action(
                currentFingerprint: replacement,
                originalFingerprint: original,
                replacementFingerprint: replacement
            ),
            .restoreCapturedOriginal
        )
        XCTAssertEqual(
            CursorRestorationClassifier.action(
                currentFingerprint: original,
                originalFingerprint: original,
                replacementFingerprint: replacement
            ),
            .alreadyRestored
        )
        XCTAssertEqual(
            CursorRestorationClassifier.action(
                currentFingerprint: fingerprint(0x33),
                originalFingerprint: original,
                replacementFingerprint: replacement
            ),
            .preserveForeignValue
        )
    }

    func testRestorationRetainsJournalForUnreadableOrInvalidState() {
        let original = fingerprint(0x11)
        let replacement = fingerprint(0x22)

        XCTAssertEqual(
            CursorRestorationClassifier.action(
                currentFingerprint: nil,
                originalFingerprint: original,
                replacementFingerprint: replacement
            ),
            .retainJournalBecauseStateIsUnreadable
        )
        XCTAssertEqual(
            CursorRestorationClassifier.action(
                currentFingerprint: original,
                originalFingerprint: original,
                replacementFingerprint: original
            ),
            .retainJournalBecauseFingerprintsAreInvalid
        )
    }

    private func fingerprint(_ byte: UInt8) -> Data {
        Data(repeating: byte, count: 32)
    }
}
