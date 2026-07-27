import AppKit
import XCTest

@testable import NextCursor

final class CometMarkTests: XCTestCase {
    private func coverage(of image: NSImage) throws -> Double {
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var covered = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                covered += 1
            }
        }
        return Double(covered) / Double(rep.pixelsWide * rep.pixelsHigh)
    }

    func testStatusItemImageIsATemplateSoTheMenuBarCanRecolourIt() {
        let image = CometMark.statusItemImage(isActive: true)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }

    func testTheMarkActuallyDrawsSomething() throws {
        // A path that silently produced nothing would still yield a valid,
        // entirely blank image.
        for isActive in [true, false] {
            let filled = try coverage(of: CometMark.statusItemImage(size: 64, isActive: isActive))
            XCTAssertGreaterThan(filled, 0.02, "isActive=\(isActive)")
            XCTAssertLessThan(filled, 0.9, "isActive=\(isActive)")
        }
    }

    func testTheInactiveMarkIsHollowerThanTheActiveOne() throws {
        // The two states have to be distinguishable at a glance in the menu bar.
        let active = try coverage(of: CometMark.statusItemImage(size: 64, isActive: true))
        let inactive = try coverage(of: CometMark.statusItemImage(size: 64, isActive: false))
        XCTAssertGreaterThan(active, inactive)
    }

    func testBothPartsOfTheMarkStayWithinTheirRectangle() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let tolerance = rect.insetBy(dx: -0.5, dy: -0.5)

        XCTAssertTrue(tolerance.contains(CometMark.headPath(in: rect).bounds))
        XCTAssertTrue(tolerance.contains(CometMark.streakPath(in: rect).bounds))
    }

    func testTheStreakTrailsBehindTheHead() {
        // The head leads up and to the right, so the streak must sit down and
        // to the left of it or the mark reads as travelling backwards.
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let head = CometMark.headPath(in: rect).bounds
        let streak = CometMark.streakPath(in: rect).bounds

        XCTAssertLessThan(streak.midX, head.midX)
        XCTAssertLessThan(streak.midY, head.midY)
    }

    func testTheMarkScalesWithTheRequestedSize() {
        let small = CometMark.statusItemImage(size: 18, isActive: true)
        let large = CometMark.statusItemImage(size: 64, isActive: true)

        XCTAssertEqual(small.size.width, 18)
        XCTAssertEqual(large.size.width, 64)
    }
}
