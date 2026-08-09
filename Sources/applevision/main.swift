import AppleVisionCore
import Foundation
import Vision

struct CLIConfiguration {
    let inputPaths: [String]
    let outputPath: String?
    let verificationReportPath: String?
    let outputFormat: OCRTextFormat
    let options: OCRRequestOptions

    init(arguments: [String]) throws {
        var remainingArguments = Array(arguments.dropFirst())
        var collectedInputPaths: [String] = []
        var outputPath: String?
        var verificationReportPath: String?
        var outputFormat: OCRTextFormat = .text
        var recursive = false
        var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
        var recognitionLanguages: [String] = []
        var usesLanguageCorrection = true
        var pdfTextMode: PDFTextMode = .preferEmbeddedText

        while let argument = remainingArguments.first {
            remainingArguments.removeFirst()

            switch argument {
            case "--help", "-h":
                throw HelpRequested()
            case "--output", "-o":
                guard let value = remainingArguments.first else {
                    throw AppleVisionError.invalidArguments("Missing value for \(argument).")
                }
                remainingArguments.removeFirst()
                outputPath = value
            case "--verification-report":
                guard let value = remainingArguments.first else {
                    throw AppleVisionError.invalidArguments("Missing value for --verification-report.")
                }
                remainingArguments.removeFirst()
                verificationReportPath = value
            case "--format":
                guard let value = remainingArguments.first else {
                    throw AppleVisionError.invalidArguments("Missing value for --format.")
                }
                remainingArguments.removeFirst()
                guard let parsedFormat = OCRTextFormat(rawValue: value.lowercased()) else {
                    throw AppleVisionError.invalidArguments("Unsupported output format '\(value)'. Use 'text', 'plain', or 'json'.")
                }
                outputFormat = parsedFormat
            case "--plain-text":
                outputFormat = .plain
            case "--recursive", "-r":
                recursive = true
            case "--fast":
                recognitionLevel = .fast
            case "--accurate":
                recognitionLevel = .accurate
            case "--language":
                guard let value = remainingArguments.first else {
                    throw AppleVisionError.invalidArguments("Missing value for --language.")
                }
                remainingArguments.removeFirst()
                recognitionLanguages.append(value)
            case "--languages":
                guard let value = remainingArguments.first else {
                    throw AppleVisionError.invalidArguments("Missing value for --languages.")
                }
                remainingArguments.removeFirst()
                recognitionLanguages.append(contentsOf: value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty })
            case "--no-language-correction":
                usesLanguageCorrection = false
            case "--pdf-ocr-only":
                pdfTextMode = .ocrOnly
            default:
                if argument.hasPrefix("-") {
                    throw AppleVisionError.invalidArguments("Unknown option '\(argument)'.")
                }
                collectedInputPaths.append(argument)
            }
        }

        guard !collectedInputPaths.isEmpty else {
            throw AppleVisionError.invalidArguments("Provide at least one image, PDF, or directory.\n\n\(Self.usage)")
        }

        self.inputPaths = collectedInputPaths
        self.outputPath = outputPath
        self.verificationReportPath = verificationReportPath
        self.outputFormat = outputFormat
        self.options = OCRRequestOptions(
            recursive: recursive,
            recognitionLevel: recognitionLevel,
            recognitionLanguages: recognitionLanguages,
            usesLanguageCorrection: usesLanguageCorrection,
            pdfTextMode: pdfTextMode
        )
    }

    static let usage = """
    Usage:
      applevision [options] <file-or-folder> [more paths...]

    Options:
      -o, --output <path>          Write OCR output to a file instead of stdout
          --verification-report <path>
                                   Write a review report for suspicious OCR lines
          --format <text|plain|json>
                                   Output format (default: text)
          --plain-text             Alias for --format plain
      -r, --recursive              Recurse into subdirectories
          --fast                   Use faster recognition
          --accurate               Use more accurate recognition (default)
          --language <code>        Add a recognition language, repeatable
          --languages <a,b,c>      Add multiple recognition languages
          --no-language-correction Disable language correction
          --pdf-ocr-only           Render PDF pages to images and OCR them
      -h, --help                   Show this help text

    Supported input types:
      Images: png, jpg, jpeg, heic, heif, tiff, tif, bmp, gif, webp
      Documents: pdf

    Examples:
      applevision ~/Desktop/scans --output output.txt
      applevision ~/Desktop/page1.jpg ~/Desktop/page2.heic --format json
      applevision ~/Desktop/scans --plain-text --output combined.txt
      applevision ~/Desktop/archive --recursive --languages en-US,fr-FR
    """
}

struct HelpRequested: Error {}

@main
struct AppleVisionCLI {
    static func main() async {
        do {
            let configuration = try CLIConfiguration(arguments: CommandLine.arguments)
            try await run(with: configuration)
        } catch is HelpRequested {
            write(CLIConfiguration.usage, to: .standardOutput)
            exit(EXIT_SUCCESS)
        } catch let error as AppleVisionError {
            write(error.localizedDescription, to: .standardError)
            exit(EXIT_FAILURE)
        } catch {
            write(error.localizedDescription, to: .standardError)
            exit(EXIT_FAILURE)
        }
    }

    private static func run(with configuration: CLIConfiguration) async throws {
        let inputURLs = try InputResolver(recursive: configuration.options.recursive).resolve(paths: configuration.inputPaths)
        let results = try await OCRService(options: configuration.options).processStructured(urls: inputURLs)
        let output = try OutputRenderer.render(results: results, format: configuration.outputFormat)

        if let outputPath = configuration.outputPath {
            let destinationURL = URL(fileURLWithPath: NSString(string: outputPath).expandingTildeInPath)
            do {
                try output.write(to: destinationURL, atomically: true, encoding: .utf8)
            } catch {
                throw AppleVisionError.writeFailed(destinationURL.path)
            }
        } else {
            write(output, to: .standardOutput)
        }

        if let verificationReportPath = configuration.verificationReportPath {
            let report = OCRReviewService().review(results: results)
            let reportText = OutputRenderer.render(report: report)
            let destinationURL = URL(fileURLWithPath: NSString(string: verificationReportPath).expandingTildeInPath)

            do {
                try reportText.write(to: destinationURL, atomically: true, encoding: .utf8)
            } catch {
                throw AppleVisionError.writeFailed(destinationURL.path)
            }
        }
    }

    private static func write(_ string: String, to handle: FileHandle) {
        guard let data = string.data(using: .utf8) else {
            return
        }
        try? handle.write(contentsOf: data)
    }
}
