import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import AppleVisionCore

final class PDFPageRenderingTests: XCTestCase {
    func testRenderPDFPageKeepsTopMarkerAtTopAndHonorsRotation() throws {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 200)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            return XCTFail("Unable to create test PDF.")
        }

        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 20, y: 150, width: 60, height: 20))
        context.endPDFPage()
        context.closePDF()

        guard let document = PDFDocument(data: data as Data),
              let page = document.page(at: 0)
        else {
            return XCTFail("Unable to load test PDF page.")
        }
        page.setBounds(CGRect(x: 10, y: 20, width: 80, height: 160), for: .cropBox)

        guard let image = OCRService.renderPDFPage(page) else {
            return XCTFail("Unable to render test PDF page.")
        }

        XCTAssertGreaterThan(darkPixelCount(in: image, rows: 0 ..< image.height / 2, columns: 0 ..< image.width), 0)
        XCTAssertEqual(darkPixelCount(in: image, rows: image.height / 2 ..< image.height, columns: 0 ..< image.width), 0)

        page.rotation = 90
        guard let rotatedImage = OCRService.renderPDFPage(page) else {
            return XCTFail("Unable to render rotated test PDF page.")
        }

        XCTAssertEqual(rotatedImage.width, image.height)
        XCTAssertEqual(rotatedImage.height, image.width)
        XCTAssertGreaterThan(darkPixelCount(in: rotatedImage, rows: 0 ..< rotatedImage.height, columns: rotatedImage.width / 2 ..< rotatedImage.width), 0)
        XCTAssertEqual(darkPixelCount(in: rotatedImage, rows: 0 ..< rotatedImage.height, columns: 0 ..< rotatedImage.width / 2), 0)
    }

    private func darkPixelCount(in image: CGImage, rows: Range<Int>, columns: Range<Int>) -> Int {
        guard let data = image.dataProvider?.data,
              let pixels = CFDataGetBytePtr(data)
        else {
            return 0
        }

        return rows.reduce(into: 0) { count, y in
            for x in columns {
                let offset = y * image.bytesPerRow + x * 4
                let channelCount = (0 ..< 4).reduce(into: 0) { darkChannels, channel in
                    if pixels[offset + channel] < 32 {
                        darkChannels += 1
                    }
                }
                if channelCount >= 3 {
                    count += 1
                }
            }
        }
    }
}
