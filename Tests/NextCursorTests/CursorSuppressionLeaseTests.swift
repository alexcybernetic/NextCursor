import XCTest

@testable import NextCursor

final class CursorSuppressionLeaseTests: XCTestCase {
    func testAcquireAndReleaseEachCallTheBackendOnce() {
        var suppressCalls = 0
        var restoreCalls = 0
        var lease = CursorSuppressionLease()

        for _ in 0..<5 {
            lease.acquire { suppressCalls += 1 }
        }

        XCTAssertTrue(lease.isAcquired)
        XCTAssertEqual(suppressCalls, 1)

        for _ in 0..<5 {
            lease.release { restoreCalls += 1 }
        }

        XCTAssertFalse(lease.isAcquired)
        XCTAssertEqual(restoreCalls, 1)
    }

    func testRepeatedRecoveryCannotAccumulateRequests() {
        // Stacking a request per recovery drove a feedback loop against
        // WindowServer and, once it hit its ceiling, left the cursor
        // suppressed with nothing left to release it. Recovery re-arms
        // instead, so the outstanding count never exceeds one.
        var suppressCalls = 0
        var restoreCalls = 0
        var lease = CursorSuppressionLease()

        lease.acquire { suppressCalls += 1 }
        for _ in 0..<100 {
            lease.release { restoreCalls += 1 }
            lease.acquire { suppressCalls += 1 }
        }

        XCTAssertTrue(lease.isAcquired)
        XCTAssertEqual(suppressCalls - restoreCalls, 1)

        lease.release { restoreCalls += 1 }
        XCTAssertEqual(suppressCalls, restoreCalls)
    }

    func testTransitionResultReportsWhetherTheBackendRan() {
        var lease = CursorSuppressionLease()

        XCTAssertTrue(lease.acquire {})
        XCTAssertFalse(lease.acquire {})
        XCTAssertTrue(lease.release {})
        XCTAssertFalse(lease.release {})
    }

    func testReleaseWithoutAcquireIsANoOperation() {
        var restoreCalls = 0
        var lease = CursorSuppressionLease()

        XCTAssertFalse(lease.release { restoreCalls += 1 })
        XCTAssertEqual(restoreCalls, 0)
    }

    func testHeldSuppressionNeedsNoPerFrameWork() {
        for visibility in [NativeCursorVisibility.hidden, .unknown] {
            XCTAssertEqual(
                CursorMaintenancePolicy.action(
                    suppressionIsAuthoritative: true,
                    visibility: visibility
                ),
                .none
            )
        }
    }

    func testDefeatedSuppressionIsRecoveredRatherThanLeftPersistent() {
        XCTAssertEqual(
            CursorMaintenancePolicy.action(
                suppressionIsAuthoritative: true,
                visibility: .visible
            ),
            .reassertSuppressionAndReapplyFallbackImage
        )
    }

    func testNonAuthoritativeSuppressionMaintainsTheFallbackImageEveryFrame() {
        for visibility in [NativeCursorVisibility.visible, .hidden, .unknown] {
            XCTAssertEqual(
                CursorMaintenancePolicy.action(
                    suppressionIsAuthoritative: false,
                    visibility: visibility
                ),
                .reapplyFallbackImage
            )
        }
    }
}
