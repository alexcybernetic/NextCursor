import CoreGraphics

struct CursorTarget: Equatable {
    enum Kind: Equatable {
        case control
        case text
    }

    let kind: Kind
    let frame: CGRect
    let cornerRadius: CGFloat
    let role: String
    let identity: Int
}

struct TargetDetectionResult {
    let sampledPoint: CGPoint
    let target: CursorTarget?
}
