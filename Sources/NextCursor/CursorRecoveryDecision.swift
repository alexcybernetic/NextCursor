import Foundation

enum CursorRecoveryStrategy: Equatable {
    case removeOwnedOverride
    case restoreCompleteSnapshot
}

enum CursorActivationRejection: String, Equatable, CaseIterable {
    case originalMappingWouldBeDestroyed
    case originalProvenanceIsUnknown
    case ownedOverrideCannotBeRemoved
    case snapshotIsSemanticallyIncomplete
}

enum CursorActivationVerdict: Equatable {
    case reversible(CursorRecoveryStrategy)
    case rejected([CursorActivationRejection])
}

struct CursorReversibilityEvidence: Equatable {
    let originalMappingSurvivesReplacement: Bool
    let originalProvenanceIsKnown: Bool
    let ownedOverrideCanBeRemoved: Bool
    let snapshotPreservesCompleteSemantics: Bool
}

enum CursorActivationGate {
    static func evaluate(_ evidence: CursorReversibilityEvidence) -> CursorActivationVerdict {
        if evidence.originalMappingSurvivesReplacement,
            evidence.ownedOverrideCanBeRemoved
        {
            return .reversible(.removeOwnedOverride)
        }

        if evidence.originalProvenanceIsKnown,
            evidence.snapshotPreservesCompleteSemantics
        {
            return .reversible(.restoreCompleteSnapshot)
        }

        var rejections: [CursorActivationRejection] = []
        if !evidence.originalMappingSurvivesReplacement {
            rejections.append(.originalMappingWouldBeDestroyed)
        }
        if !evidence.originalProvenanceIsKnown {
            rejections.append(.originalProvenanceIsUnknown)
        }
        if !evidence.ownedOverrideCanBeRemoved {
            rejections.append(.ownedOverrideCannotBeRemoved)
        }
        if !evidence.snapshotPreservesCompleteSemantics {
            rejections.append(.snapshotIsSemanticallyIncomplete)
        }
        return .rejected(rejections)
    }
}

enum CursorRestorationAction: Equatable {
    case restoreCapturedOriginal
    case alreadyRestored
    case preserveForeignValue
    case retainJournalBecauseStateIsUnreadable
    case retainJournalBecauseFingerprintsAreInvalid
}

enum CursorRestorationClassifier {
    static func action(
        currentFingerprint: Data?,
        originalFingerprint: Data,
        replacementFingerprint: Data
    ) -> CursorRestorationAction {
        guard originalFingerprint.count == 32,
            replacementFingerprint.count == 32,
            originalFingerprint != replacementFingerprint
        else {
            return .retainJournalBecauseFingerprintsAreInvalid
        }
        guard let currentFingerprint, currentFingerprint.count == 32 else {
            return .retainJournalBecauseStateIsUnreadable
        }
        if currentFingerprint == replacementFingerprint {
            return .restoreCapturedOriginal
        }
        if currentFingerprint == originalFingerprint {
            return .alreadyRestored
        }
        return .preserveForeignValue
    }
}
