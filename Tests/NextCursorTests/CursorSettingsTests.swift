import XCTest

@testable import NextCursor

final class CursorSettingsTests: XCTestCase {
    func testOutOfRangeValuesAreClampedRatherThanTrusted() {
        var settings = CursorAppearanceSettings()
        settings.pointerSize = 10_000
        settings.borderWidth = -5

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.pointerSize, CursorAppearanceSettings.sizeRange.upperBound)
        XCTAssertEqual(
            normalized.borderWidth,
            CursorAppearanceSettings.borderWidthRange.lowerBound
        )
    }

    func testColourComponentsAreClampedIntoRange() {
        var settings = CursorAppearanceSettings()
        settings.lightFill = StoredColor(red: 4, green: -1, blue: 0.5, alpha: 9)

        let fill = settings.normalized().lightFill

        XCTAssertEqual(fill.red, 1)
        XCTAssertEqual(fill.green, 0)
        XCTAssertEqual(fill.blue, 0.5)
        XCTAssertEqual(fill.alpha, 1)
    }

    func testSettingsSurviveAnEncodeDecodeRoundTrip() throws {
        var settings = CursorAppearanceSettings()
        settings.shape = .star
        settings.pointerSize = 33
        settings.usesPointerInertia = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CursorAppearanceSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testRoundedRectangleShapesCarryACornerRadiusAndPolygonsDoNot() {
        // Circle, rounded square, and square differ only in corner radius, so
        // they morph into a snapped control through the existing spring.
        XCTAssertEqual(CursorShapeKind.circle.cornerRadiusFraction, 0.5)
        XCTAssertEqual(CursorShapeKind.square.cornerRadiusFraction, 0)
        XCTAssertTrue(CursorShapeKind.roundedSquare.isRoundedRectangle)

        for shape in [CursorShapeKind.triangle, .octagon, .star] {
            XCTAssertFalse(shape.isRoundedRectangle)
        }
    }

    func testPolygonsProduceVerticesInsideTheirBounds() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        let expectedCounts: [CursorShapeKind: Int] = [
            .triangle: 3,
            .octagon: 8,
            .star: 10,
        ]

        for (shape, expectedCount) in expectedCounts {
            let points = shape.polygonPoints(in: rect)
            XCTAssertEqual(points.count, expectedCount, "\(shape)")
            for point in points {
                XCTAssertTrue(
                    rect.insetBy(dx: -0.001, dy: -0.001).contains(point),
                    "\(shape) vertex \(point) escaped its bounds"
                )
            }
        }
    }

    func testRoundedRectangleShapesProduceNoPolygon() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        for shape in [CursorShapeKind.circle, .roundedSquare, .square] {
            XCTAssertTrue(shape.polygonPoints(in: rect).isEmpty, "\(shape)")
        }
    }

    func testBlendReachesEachEndpoint() {
        let from = StoredColor(red: 0, green: 0, blue: 0, alpha: 0)
        let to = StoredColor(red: 1, green: 1, blue: 1, alpha: 1)

        XCTAssertEqual(from.blended(toward: to, amount: 0), from)
        XCTAssertEqual(from.blended(toward: to, amount: 1), to)
        // Out-of-range amounts must not overshoot into invalid colours.
        XCTAssertEqual(from.blended(toward: to, amount: 5), to)
        XCTAssertEqual(from.blended(toward: to, amount: -5), from)
    }
}

final class CursorSettingsStoreTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "NextCursorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testSettingsPersistAcrossStoreInstances() throws {
        let defaults = try makeDefaults()

        let store = CursorSettingsStore(defaults: defaults)
        store.set(.octagon, for: \.shape)
        store.set(31, for: \.pointerSize)

        let reloaded = CursorSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.shape, .octagon)
        XCTAssertEqual(reloaded.settings.pointerSize, 31)
    }

    func testStoredValuesOutsideTheSupportedRangeAreClampedOnLoad() throws {
        let defaults = try makeDefaults()
        var tampered = CursorAppearanceSettings()
        tampered.pointerSize = 9_999
        // Bypass normalized() to simulate a hand-edited or older payload.
        defaults.set(try JSONEncoder().encode(tampered), forKey: CursorSettingsStore.storageKey)

        let store = CursorSettingsStore(defaults: defaults)

        XCTAssertEqual(
            store.settings.pointerSize,
            CursorAppearanceSettings.sizeRange.upperBound
        )
    }

    func testUnreadablePayloadFallsBackToDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: CursorSettingsStore.storageKey)

        let store = CursorSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, CursorAppearanceSettings())
    }

    func testResetRestoresDefaultsAndPersistsThem() throws {
        let defaults = try makeDefaults()
        let store = CursorSettingsStore(defaults: defaults)
        store.set(.star, for: \.shape)

        store.reset()

        XCTAssertEqual(store.settings, CursorAppearanceSettings())
        XCTAssertEqual(
            CursorSettingsStore(defaults: defaults).settings,
            CursorAppearanceSettings()
        )
    }
}

final class CursorShapePathTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 40, height: 40)

    func testEveryNonRectangularShapeProducesAPath() {
        for shape in [CursorShapeKind.triangle, .octagon, .star, .heart] {
            let path = shape.customPath(in: rect)
            XCTAssertNotNil(path, "\(shape) produced no path")
            XCTAssertGreaterThan(path?.elementCount ?? 0, 2, "\(shape)")
        }
    }

    func testRoundedRectangleShapesProduceNoCustomPath() {
        // These are drawn through the corner-radius spring instead, which is
        // what lets them morph into a snapped control.
        for shape in [CursorShapeKind.circle, .roundedSquare, .square] {
            XCTAssertNil(shape.customPath(in: rect), "\(shape)")
        }
    }

    func testHeartIsCurvedRatherThanAPolygon() {
        // The heart cannot come from polygonPoints; it needs cubic segments.
        XCTAssertTrue(CursorShapeKind.heart.polygonPoints(in: rect).isEmpty)

        let path = try? XCTUnwrap(CursorShapeKind.heart.customPath(in: rect))
        var hasCurve = false
        if let path {
            for index in 0..<path.elementCount where path.element(at: index) == .curveTo {
                hasCurve = true
            }
        }
        XCTAssertTrue(hasCurve, "heart should contain curve segments")
    }

    func testEveryShapeStaysWithinItsBounds() {
        let tolerance = rect.insetBy(dx: -0.5, dy: -0.5)
        for shape in CursorShapeKind.allCases {
            guard let path = shape.customPath(in: rect) else { continue }
            XCTAssertTrue(
                tolerance.contains(path.bounds),
                "\(shape) bounds \(path.bounds) escaped \(rect)"
            )
        }
    }

    func testControlAppearanceValuesAreClamped() {
        var settings = CursorAppearanceSettings()
        settings.controlPadding = 500
        settings.controlBorderWidth = -3

        let normalized = settings.normalized()

        XCTAssertEqual(
            normalized.controlPadding,
            CursorAppearanceSettings.controlPaddingRange.upperBound
        )
        XCTAssertEqual(
            normalized.controlBorderWidth,
            CursorAppearanceSettings.controlBorderWidthRange.lowerBound
        )
    }
}






final class CursorSettingsDecodingTests: XCTestCase {
    func testAPayloadMissingNewerFieldsKeepsTheOnesItHas() throws {
        // Adding a property must not make older stored settings undecodable:
        // the store falls back to defaults on failure, silently discarding
        // everything the user configured.
        let legacy = """
            {"version":1,"shape":"star","pointerSize":33,"usesPointerInertia":true}
            """
        let decoded = try JSONDecoder().decode(
            CursorAppearanceSettings.self,
            from: Data(legacy.utf8)
        )

        XCTAssertEqual(decoded.shape, .star)
        XCTAssertEqual(decoded.pointerSize, 33)
        XCTAssertTrue(decoded.usesPointerInertia)
        // Absent fields fall back rather than failing the whole decode.
        XCTAssertEqual(decoded.borderWidth, CursorAppearanceSettings().borderWidth)
        XCTAssertEqual(decoded.controlPadding, CursorAppearanceSettings().controlPadding)
    }

    func testAnEmptyObjectDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(
            CursorAppearanceSettings.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(decoded, CursorAppearanceSettings())
    }

    func testStoreKeepsConfiguredValuesWhenAFieldIsMissing() throws {
        let suiteName = "NextCursorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = #"{"version":2,"shape":"heart","pointerSize":28}"#
        defaults.set(Data(legacy.utf8), forKey: CursorSettingsStore.storageKey)

        let store = CursorSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings.shape, .heart)
        XCTAssertEqual(store.settings.pointerSize, 28)
    }
}


