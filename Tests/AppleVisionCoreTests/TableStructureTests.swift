import XCTest
@testable import AppleVisionCore

final class TableStructureTests: XCTestCase {
    func testStructuredTextRendersTwoByTwoTableOnceAtItsReadingPosition() {
        let result = OCRResult(
            sourcePath: "/tmp/table.png",
            pageNumber: nil,
            lines: [
                OCRLine(text: "Before"),
                OCRLine(text: "A"),
                OCRLine(text: "B"),
                OCRLine(text: "C"),
                OCRLine(text: "D"),
                OCRLine(text: "After"),
            ],
            structure: OCRDocumentStructure(tables: [
                OCRTable(cells: [
                    OCRTableCell(row: 0, column: 0, lineIndices: [1]),
                    OCRTableCell(row: 0, column: 1, lineIndices: [2]),
                    OCRTableCell(row: 1, column: 0, lineIndices: [3]),
                    OCRTableCell(row: 1, column: 1, lineIndices: [4]),
                ])
            ])
        )

        XCTAssertEqual(result.structuredText, "Before\nA\tB\nC\tD\nAfter")
        XCTAssertEqual(result.structuredLineIndices, [0, 1, 2, 3, 4, 5])
    }

    func testStructuredTextUsesCurrentLineTextAndLeavesMergedPositionsEmpty() {
        let result = OCRResult(
            sourcePath: "/tmp/table.png",
            pageNumber: nil,
            lines: [
                OCRLine(text: "Updated heading"),
                OCRLine(text: "Updated left"),
                OCRLine(text: "Updated right"),
            ],
            structure: OCRDocumentStructure(tables: [
                OCRTable(cells: [
                    OCRTableCell(row: 0, column: 0, columnSpan: 2, fallbackText: "Old heading", lineIndices: [0]),
                    OCRTableCell(row: 1, column: 0, fallbackText: "Old left", lineIndices: [1]),
                    OCRTableCell(row: 1, column: 1, fallbackText: "Old right", lineIndices: [2]),
                ])
            ])
        )

        XCTAssertEqual(result.structuredText, "Updated heading\t\nUpdated left\tUpdated right")
        XCTAssertEqual(result.structuredText.components(separatedBy: "Updated heading").count - 1, 1)
    }

    func testNonTableTextAndJSONRemainCompatibleWhileIncludingCellSpans() throws {
        let flatResult = OCRResult(
            sourcePath: "/tmp/flat.png",
            pageNumber: nil,
            text: "first\nsecond",
            lines: [OCRLine(text: "first"), OCRLine(text: "second")]
        )
        XCTAssertEqual(flatResult.structuredText, "first\nsecond")
        XCTAssertEqual(try OutputRenderer.render(results: [flatResult], format: .plain), "first\nsecond\n")

        let tableResult = OCRResult(
            sourcePath: "/tmp/table.png",
            pageNumber: nil,
            lines: [OCRLine(text: "A")],
            structure: OCRDocumentStructure(tables: [
                OCRTable(cells: [
                    OCRTableCell(row: 0, column: 0, rowSpan: 2, columnSpan: 3, fallbackText: "A", lineIndices: [0])
                ])
            ])
        )
        let json = try OutputRenderer.render(results: [tableResult], format: .json)

        XCTAssertTrue(json.contains("\"cells\""))
        XCTAssertTrue(json.contains("\"rowSpan\" : 2"))
        XCTAssertTrue(json.contains("\"columnSpan\" : 3"))
    }

    func testPlainTextExportPreservesBlankEdgeTableCells() throws {
        let result = OCRResult(
            sourcePath: "/tmp/table.png",
            pageNumber: nil,
            lines: [OCRLine(text: "Middle")],
            structure: OCRDocumentStructure(tables: [
                OCRTable(cells: [
                    OCRTableCell(row: 0, column: 0),
                    OCRTableCell(row: 0, column: 1, lineIndices: [0]),
                    OCRTableCell(row: 0, column: 2),
                ])
            ])
        )

        XCTAssertEqual(try OutputRenderer.render(results: [result], format: .plain), "\tMiddle\t\n")
    }
}
