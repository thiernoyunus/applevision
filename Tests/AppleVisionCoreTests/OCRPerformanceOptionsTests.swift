import XCTest
@testable import AppleVisionCore

final class OCRPerformanceOptionsTests: XCTestCase {
    func testDefaultOCRDetailsKeepReviewEvidence() {
        let options = OCRRequestOptions()

        XCTAssertEqual(options.detailLevel, .review)
    }

    func testTextOnlyDetailLevelSkipsCandidatesAndWords() {
        let options = OCRRequestOptions(detailLevel: .textOnly)

        XCTAssertEqual(options.detailLevel, .textOnly)
        XCTAssertFalse(options.detailLevel.includesAlternativeCandidates)
        XCTAssertFalse(options.detailLevel.includesWordGeometry)
    }

    func testReviewDetailLevelKeepsCandidatesAndWords() {
        let options = OCRRequestOptions(detailLevel: .review)

        XCTAssertTrue(options.detailLevel.includesAlternativeCandidates)
        XCTAssertTrue(options.detailLevel.includesWordGeometry)
    }

    func testRecommendedDetailLevelUsesTextOnlyForPlainTextWithoutReview() {
        let detailLevel = OCRDetailLevel.recommended(
            exportChoice: .text,
            reviewBeforeExport: false
        )

        XCTAssertEqual(detailLevel, .textOnly)
    }

    func testRecommendedDetailLevelKeepsReviewDetailsWhenReviewIsEnabled() {
        let detailLevel = OCRDetailLevel.recommended(
            exportChoice: .text,
            reviewBeforeExport: true
        )

        XCTAssertEqual(detailLevel, .review)
    }

    func testRecommendedDetailLevelKeepsReviewDetailsForSearchablePDF() {
        let detailLevel = OCRDetailLevel.recommended(
            exportChoice: .searchablePDF,
            reviewBeforeExport: false
        )

        XCTAssertEqual(detailLevel, .review)
    }

    func testRecommendedCLIDetailLevelUsesTextOnlyForPlainTextWithoutReport() {
        let detailLevel = OCRDetailLevel.recommended(
            outputFormat: .plain,
            writesVerificationReport: false
        )

        XCTAssertEqual(detailLevel, .textOnly)
    }

    func testRecommendedCLIDetailLevelKeepsReviewDetailsForJSON() {
        let detailLevel = OCRDetailLevel.recommended(
            outputFormat: .json,
            writesVerificationReport: false
        )

        XCTAssertEqual(detailLevel, .review)
    }

    func testRecommendedCLIDetailLevelKeepsReviewDetailsForVerificationReport() {
        let detailLevel = OCRDetailLevel.recommended(
            outputFormat: .plain,
            writesVerificationReport: true
        )

        XCTAssertEqual(detailLevel, .review)
    }

    func testPDFRenderConfigurationCapsLargePages() {
        let configuration = PDFRenderConfiguration(scale: 2.0, maximumPixelCount: 2_000_000)
        let size = CGSize(width: 1_000, height: 2_000)

        XCTAssertEqual(configuration.pixelSize(for: size), CGSize(width: 1_000, height: 2_000))
    }

    func testPDFRenderConfigurationUsesRequestedScaleForSmallPages() {
        let configuration = PDFRenderConfiguration(scale: 2.0, maximumPixelCount: 8_000_000)
        let size = CGSize(width: 500, height: 700)

        XCTAssertEqual(configuration.pixelSize(for: size), CGSize(width: 1_000, height: 1_400))
    }

    func testConcurrentPDFPageChunksLimitDocumentReopens() {
        let chunks = OCRService.concurrentPDFPageChunks(pageCount: 10, maxConcurrentOperationCount: 4)

        XCTAssertEqual(chunks, [
            [0, 1, 2],
            [3, 4, 5],
            [6, 7],
            [8, 9],
        ])
    }

    func testConcurrentPDFProgressOmitsOutOfOrderPageNumber() {
        let state = ConcurrentPDFOCRState(pageCount: 2, completedUnitCount: 0)
        let result = OCRResult(sourcePath: "/tmp/example.pdf", pageNumber: 2, lines: [])

        let update = state.record(
            result: result,
            pageIndex: 1,
            totalUnitCount: 2,
            sourcePath: "/tmp/example.pdf"
        )

        XCTAssertEqual(update.completedUnitCount, 1)
        XCTAssertEqual(update.totalUnitCount, 2)
        XCTAssertNil(update.pageNumber)
    }
}
