import CoreGraphics
import XCTest
@testable import AppleVisionCore

final class BoundingBoxGeometryTests: XCTestCase {
    func testMapsVisionBoxIntoTopLeftBoundsAndKeepsItsLocationWhenZoomedAndPanned() {
        let box = OCRBoundingBox(minX: 0.2, minY: 0.25, width: 0.3, height: 0.1)
        let bounds = CGRect(x: 40, y: 60, width: 500, height: 300)

        let rect = box.rect(in: bounds)

        XCTAssertEqual(rect, CGRect(x: 140, y: 255, width: 150, height: 30))

        let zoom: CGFloat = 4
        let pan = CGSize(width: 35, height: -20)
        let zoomedAndPannedRect = CGRect(
            x: bounds.midX + (rect.minX - bounds.midX) * zoom + pan.width,
            y: bounds.midY + (rect.minY - bounds.midY) * zoom + pan.height,
            width: rect.width * zoom,
            height: rect.height * zoom
        )

        XCTAssertEqual(zoomedAndPannedRect, CGRect(x: -275, y: 370, width: 600, height: 120))
    }
}
