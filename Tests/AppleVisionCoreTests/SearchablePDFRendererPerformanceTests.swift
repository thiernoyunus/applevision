import Foundation
import XCTest
@testable import AppleVisionCore

final class SearchablePDFRendererPerformanceTests: XCTestCase {
    func testRenderToDestinationURLWritesPDFWithoutReturningData() throws {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        defer {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        try SearchablePDFRenderer.render(results: [], to: destinationURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let fileSize = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertGreaterThan(fileSize.intValue, 0)
    }

    func testRenderToDestinationURLReportsWriteFailure() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        XCTAssertThrowsError(try SearchablePDFRenderer.render(results: [], to: directoryURL)) { error in
            guard case let AppleVisionError.writeFailed(message) = error else {
                return XCTFail("Expected writeFailed, got \(error)")
            }

            XCTAssertTrue(message.contains(directoryURL.path))
        }
    }
}
